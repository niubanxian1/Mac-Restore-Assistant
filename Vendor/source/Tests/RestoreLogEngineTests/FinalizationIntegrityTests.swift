import Foundation
import XCTest
@testable import RestoreLogEngine

/// F03 — integrity finalization false-positive prevention.
///
/// Every assertion below is made against bytes on disk, not only against the
/// Swift object returned by `finalize`, because the defect being guarded is
/// precisely "the object said verified but the disk said otherwise".
final class FinalizationIntegrityTests: XCTestCase {
    private var root: URL = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlm-f03-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Harness

    private var config: CaptureConfig { CaptureConfig(outputDirectory: root) }

    private func makeStore() -> EvidenceStore {
        EvidenceStore(root: root.appendingPathComponent("Sessions", isDirectory: true))
    }

    private func makeEngine(
        backend: LogCaptureBackend = SimulatedLogCaptureBackend(),
        store: EvidenceStore? = nil
    ) -> CaptureCoordinator {
        CaptureCoordinator(backend: backend, store: store ?? makeStore())
    }

    private func sessionDir(_ handle: SessionHandle) -> URL {
        URL(fileURLWithPath: handle.outputDirectory, isDirectory: true)
    }

    private func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func readMetadata(in dir: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("session.json")),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return nil }
        return dictionary
    }

    /// True only for a regular file — a directory squatting on the path is not
    /// metadata and must never be read as a completion marker.
    private func metadataFileExists(in dir: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let path = dir.appendingPathComponent("session.json").path
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    private func recordedHashes(fromSumsText text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            out[String(parts[1]).trimmingCharacters(in: .whitespaces)] = String(parts[0])
        }
        return out
    }

    private func finalizeExpectingThrow(_ engine: CaptureCoordinator, _ id: UUID) async -> Bool {
        do {
            _ = try await engine.finalize(sessionID: id)
            return false
        } catch {
            return true
        }
    }

    // MARK: - A01 valid capture completes verification

    func testA01ValidCaptureCompletesVerification() async throws {
        let engine = makeEngine()
        let session = try await engine.beginCapture(config: config)
        _ = try await engine.stopCapture(sessionID: session.sessionID)

        let rawURL = URL(fileURLWithPath: session.rawLogPath)
        let hashBeforeFinalize = try Integrity.sha256(ofFileAt: rawURL)

        let exported = try await engine.finalize(sessionID: session.sessionID)

        XCTAssertEqual(exported.record.integrityStatus, .verified)
        XCTAssertEqual(exported.record.captureState, .savedPartial)

        let dir = sessionDir(session)
        let metadata = try XCTUnwrap(readMetadata(in: dir), "session.json must exist after a successful finalize")
        XCTAssertEqual(metadata["integrityStatus"] as? String, "verified")
        XCTAssertEqual(metadata["captureState"] as? String, "SAVED_PARTIAL")

        // The manifest on disk must actually describe the bytes on disk.
        let sumsText = try readText(dir.appendingPathComponent("SHA256SUMS.txt"))
        let recorded = recordedHashes(fromSumsText: sumsText)
        XCTAssertEqual(recorded["restore.log"], hashBeforeFinalize)

        XCTAssertEqual(
            try Integrity.sha256(ofFileAt: rawURL), hashBeforeFinalize,
            "finalization must never rewrite raw log bytes"
        )
    }

    // MARK: - A02 raw log tampered before verification

    func testA02TamperedRawLogIsRejectedByVerification() throws {
        let dir = root.appendingPathComponent("A02", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let paths = SessionPaths(directory: dir)
        let rawURL = paths.rawLogURL

        try Data("original bytes\n".utf8).write(to: rawURL)
        let goodHash = try Integrity.sha256(ofFileAt: rawURL)
        let files = [
            EvidenceFile(role: "raw-log", relativePath: "restore.log", byteSize: 15, sha256: goodHash)
        ]
        try Data("\(goodHash)  restore.log\n".utf8).write(to: paths.sha256SumsURL)

        // Control: verifies while the bytes still match the recorded digest.
        XCTAssertNoThrow(try CaptureCoordinator.verifyChecksumFile(paths: paths, expected: files))

        // Attack: change the bytes after the digest was recorded.
        try Data("tampered bytes\n".utf8).write(to: rawURL)

        XCTAssertThrowsError(try CaptureCoordinator.verifyChecksumFile(paths: paths, expected: files)) { error in
            guard case CaptureError.integrityCheckFailed = error else {
                return XCTFail("expected integrityCheckFailed, got \(error)")
            }
        }
    }

    // MARK: - A03 raw log unreadable

    func testA03UnreadableRawLogIsNeverVerified() async throws {
        let engine = makeEngine()
        let session = try await engine.beginCapture(config: config)
        _ = try await engine.stopCapture(sessionID: session.sessionID)

        try FileManager.default.removeItem(atPath: session.rawLogPath)

        let exported = try await engine.finalize(sessionID: session.sessionID)

        XCTAssertEqual(exported.record.integrityStatus, .failed)
        XCTAssertEqual(exported.record.captureState, .failed)
        XCTAssertTrue(exported.record.missingEvidence.contains { $0.hasPrefix("Raw log unreadable") })

        let metadata = try XCTUnwrap(readMetadata(in: sessionDir(session)))
        XCTAssertEqual(metadata["integrityStatus"] as? String, "failed")
    }

    // MARK: - A04 hash comparison failure (missing entry)

    func testA04MissingChecksumEntryIsRejected() throws {
        let dir = root.appendingPathComponent("A04", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let paths = SessionPaths(directory: dir)

        try Data("payload\n".utf8).write(to: paths.rawLogURL)
        let hash = try Integrity.sha256(ofFileAt: paths.rawLogURL)
        let files = [EvidenceFile(role: "raw-log", relativePath: "restore.log", byteSize: 8, sha256: hash)]

        // Manifest written but silently missing the entry for a promised file.
        try Data("".utf8).write(to: paths.sha256SumsURL)

        XCTAssertThrowsError(try CaptureCoordinator.verifyChecksumFile(paths: paths, expected: files)) { error in
            guard case CaptureError.integrityCheckFailed = error else {
                return XCTFail("expected integrityCheckFailed, got \(error)")
            }
        }
    }

    // MARK: - A05 metadata write failure

    func testA05MetadataWriteFailureIsNotSuccess() async throws {
        let engine = makeEngine()
        let session = try await engine.beginCapture(config: config)
        _ = try await engine.stopCapture(sessionID: session.sessionID)

        let dir = sessionDir(session)
        // An atomic write onto an existing directory fails.
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("session.json"),
            withIntermediateDirectories: true
        )

        let threw = await finalizeExpectingThrow(engine, session.sessionID)
        XCTAssertTrue(threw, "finalize must throw when metadata cannot be written")
        XCTAssertFalse(metadataFileExists(in: dir), "no metadata file may exist after a failed commit")
        XCTAssertNil(readMetadata(in: dir))
    }

    // MARK: - A06 metadata read-back mismatch

    func testA06MetadataReadBackMismatchIsNotSuccess() async throws {
        let forged = #"{"integrityStatus":"verified","schemaVersion":1}"#
        let store = EvidenceStore(root: root.appendingPathComponent("Sessions", isDirectory: true)) { url in
            // Replace the just-written bytes with valid JSON that claims verified,
            // so the read-back comparison must catch the divergence.
            try Data(forged.utf8).write(to: url, options: .atomic)
        }
        let engine = makeEngine(store: store)
        let session = try await engine.beginCapture(config: config)
        _ = try await engine.stopCapture(sessionID: session.sessionID)

        let threw = await finalizeExpectingThrow(engine, session.sessionID)
        XCTAssertTrue(threw, "a read-back mismatch must fail finalization")

        let dir = sessionDir(session)
        XCTAssertFalse(
            metadataFileExists(in: dir),
            "a mismatched metadata file must be removed, never left as a completion marker"
        )
    }

    // MARK: - A07 checksum manifest write/verify failure

    func testA07ManifestFailureLeavesNoVerifiedMetadata() async throws {
        let engine = makeEngine()
        let session = try await engine.beginCapture(config: config)
        _ = try await engine.stopCapture(sessionID: session.sessionID)

        let dir = sessionDir(session)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("SHA256SUMS.txt"),
            withIntermediateDirectories: true
        )

        let threw = await finalizeExpectingThrow(engine, session.sessionID)
        XCTAssertTrue(threw, "finalize must throw when the checksum manifest cannot be written")
        XCTAssertFalse(metadataFileExists(in: dir))
        XCTAssertNil(readMetadata(in: dir))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: session.rawLogPath),
            "raw evidence must survive a failed finalization"
        )
    }

    // MARK: - A08 memory state cannot override disk

    func testA08MemoryStateCannotOverrideDisk() async throws {
        let engine = makeEngine()
        let session = try await engine.beginCapture(config: config)
        _ = try await engine.stopCapture(sessionID: session.sessionID)

        let dir = sessionDir(session)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("SHA256SUMS.txt"),
            withIntermediateDirectories: true
        )

        let threw = await finalizeExpectingThrow(engine, session.sessionID)
        XCTAssertTrue(threw)

        let status = try await engine.getStatus(sessionID: session.sessionID)
        XCTAssertNotEqual(status.state, .savedVerified)
        XCTAssertNotEqual(status.state, .savedPartial)
        XCTAssertEqual(status.state, .failed)
        XCTAssertFalse(metadataFileExists(in: dir))
    }

    // MARK: - A09 zero-byte raw log

    func testA09ZeroByteLogIsNeverAVerifiedCapture() async throws {
        let engine = makeEngine(backend: SimulatedLogCaptureBackend(fixture: .empty))
        let session = try await engine.beginCapture(config: config)
        _ = try await engine.stopCapture(sessionID: session.sessionID)

        let exported = try await engine.finalize(sessionID: session.sessionID)

        XCTAssertEqual(exported.record.eventCount, 0)
        XCTAssertEqual(exported.record.coverageStatus, .unverified)
        XCTAssertEqual(exported.record.captureState, .savedPartial)
        XCTAssertNotEqual(exported.record.captureState, .savedVerified)

        let metadata = try XCTUnwrap(readMetadata(in: sessionDir(session)))
        XCTAssertNotEqual(metadata["captureState"] as? String, "SAVED_VERIFIED")
        // A non-empty hash of an empty file is still not evidence of a restore.
        XCTAssertEqual(metadata["coverageStatus"] as? String, "unverified")
        XCTAssertEqual(metadata["eventCount"] as? Int, 0)
    }

    // MARK: - A10 tamper after a successful verification

    func testA10PostVerificationTamperIsDetectable() async throws {
        let engine = makeEngine()
        let session = try await engine.beginCapture(config: config)
        _ = try await engine.stopCapture(sessionID: session.sessionID)
        let exported = try await engine.finalize(sessionID: session.sessionID)

        let recorded = try XCTUnwrap(
            exported.record.files.first { $0.role == "raw-log" }?.sha256
        )
        let rawURL = URL(fileURLWithPath: session.rawLogPath)

        // VERIFIED_AT_FINALIZATION was true; CURRENT_BYTES_VERIFIED must now be false.
        var bytes = try Data(contentsOf: rawURL)
        bytes.append(0x41)
        try bytes.write(to: rawURL)

        XCTAssertNotEqual(try Integrity.sha256(ofFileAt: rawURL), recorded)

        let paths = SessionPaths(directory: sessionDir(session))
        XCTAssertThrowsError(try CaptureCoordinator.verifyChecksumFile(paths: paths, expected: exported.record.files)) { error in
            guard case CaptureError.integrityCheckFailed = error else {
                return XCTFail("expected integrityCheckFailed after post-verification tamper, got \(error)")
            }
        }
    }
}

import Foundation
import XCTest
@testable import RestoreLogEngine

/// DIAGNOSTIC_STATUS_SEPARATION — raw integrity vs diagnostic build outcome.
final class DiagnosticStatusSeparationTests: XCTestCase {
    private var root: URL = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlm-dss-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var config: CaptureConfig { CaptureConfig(outputDirectory: root) }

    private func makeEngine() -> CaptureCoordinator {
        CaptureCoordinator(
            backend: SimulatedLogCaptureBackend(),
            store: EvidenceStore(root: root.appendingPathComponent("Sessions", isDirectory: true))
        )
    }

    private func sessionDir(_ handle: SessionHandle) -> URL {
        URL(fileURLWithPath: handle.outputDirectory, isDirectory: true)
    }

    private func readMetadata(in dir: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("session.json")),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return nil }
        return dictionary
    }

    /// ① raw valid + diagnostic build fails → integrity verified, diagnostic failed, health degraded.
    func testRawVerifiedWhenDiagnosticBuildFails() async throws {
        let engine = makeEngine()
        let session = try await engine.beginCapture(config: config)
        _ = try await engine.stopCapture(sessionID: session.sessionID)

        let rawURL = URL(fileURLWithPath: session.rawLogPath)
        let rawBefore = try Data(contentsOf: rawURL)
        let rawHashBefore = try Integrity.sha256(ofFileAt: rawURL)

        // Squatting directory makes DiagnosticLogBuilder unable to write diagnostic.log.
        let diagURL = rawURL.deletingLastPathComponent().appendingPathComponent("diagnostic.log")
        try FileManager.default.createDirectory(at: diagURL, withIntermediateDirectories: true)

        let exported = try await engine.finalize(sessionID: session.sessionID)

        XCTAssertEqual(exported.record.integrityStatus, .verified)
        XCTAssertEqual(exported.record.diagnosticStatus, .failed)
        XCTAssertEqual(exported.record.captureHealth, .degraded)
        XCTAssertNotEqual(exported.record.captureState, .failed)
        XCTAssertTrue(exported.record.missingEvidence.contains { $0.hasPrefix("Diagnostic log failed") })
        XCTAssertFalse(exported.record.files.contains { $0.role == "diagnostic-log" })
        XCTAssertTrue(exported.record.files.contains { $0.role == "raw-log" })

        let sums = try String(contentsOf: URL(fileURLWithPath: exported.sha256SumsPath), encoding: .utf8)
        XCTAssertFalse(sums.contains("diagnostic.log"), "SHA256SUMS must not invent a diagnostic entry")
        XCTAssertTrue(sums.contains("restore.log"))

        let rawAfter = try Data(contentsOf: rawURL)
        XCTAssertEqual(rawAfter, rawBefore, "restore.log must remain immutable")
        XCTAssertEqual(try Integrity.sha256(ofFileAt: rawURL), rawHashBefore)

        let metadata = try XCTUnwrap(readMetadata(in: sessionDir(session)))
        XCTAssertEqual(metadata["integrityStatus"] as? String, "verified")
        XCTAssertEqual(metadata["diagnosticStatus"] as? String, "failed")
        XCTAssertEqual(metadata["captureHealth"] as? String, "degraded")
    }

    /// ② raw unreadable → integrity failed; diagnostic never claims raw verified.
    func testRawUnreadableNeverVerifiedRegardlessOfDiagnostic() async throws {
        let engine = makeEngine()
        let session = try await engine.beginCapture(config: config)
        _ = try await engine.stopCapture(sessionID: session.sessionID)

        try FileManager.default.removeItem(atPath: session.rawLogPath)

        let exported = try await engine.finalize(sessionID: session.sessionID)

        XCTAssertEqual(exported.record.integrityStatus, .failed)
        XCTAssertEqual(exported.record.diagnosticStatus, .skipped)
        XCTAssertEqual(exported.record.captureState, .failed)
        XCTAssertTrue(exported.record.missingEvidence.contains { $0.hasPrefix("Raw log unreadable") })
        XCTAssertFalse(exported.record.files.contains { $0.role == "raw-log" })
        XCTAssertFalse(exported.record.files.contains { $0.role == "diagnostic-log" })

        let metadata = try XCTUnwrap(readMetadata(in: sessionDir(session)))
        XCTAssertEqual(metadata["integrityStatus"] as? String, "failed")
        XCTAssertEqual(metadata["diagnosticStatus"] as? String, "skipped")
        XCTAssertNotEqual(metadata["integrityStatus"] as? String, "verified")
    }

    /// Old session.json without diagnosticStatus decodes as unchecked (never invent ok).
    func testLegacySessionJSONMissingDiagnosticStatusIsUnchecked() throws {
        let json = """
        {
          "schemaVersion": 1,
          "sessionID": "00000000-0000-4000-8000-000000000001",
          "captureState": "SAVED_PARTIAL",
          "captureHealth": "unconfirmed",
          "startedAtUTC": null,
          "endedAtUTC": null,
          "captureProfile": "test",
          "captureCommand": ["test"],
          "captureBackend": "test",
          "eventCount": 0,
          "coverageStatus": "partial",
          "archiveStatus": "NOT_REQUESTED",
          "integrityStatus": "verified",
          "files": [],
          "missingEvidence": [],
          "errorReason": null
        }
        """
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.diagnosticStatus, .unchecked)
        XCTAssertEqual(decoded.integrityStatus, .verified)
    }

    /// Happy path still marks diagnostic ok when build succeeds.
    func testDiagnosticOkWhenBuildSucceeds() async throws {
        let engine = makeEngine()
        let session = try await engine.beginCapture(config: config)
        _ = try await engine.stopCapture(sessionID: session.sessionID)

        let exported = try await engine.finalize(sessionID: session.sessionID)
        XCTAssertEqual(exported.record.integrityStatus, .verified)
        XCTAssertEqual(exported.record.diagnosticStatus, .ok)
        XCTAssertTrue(exported.record.files.contains { $0.role == "diagnostic-log" })
        let sums = try String(contentsOf: URL(fileURLWithPath: exported.sha256SumsPath), encoding: .utf8)
        XCTAssertTrue(sums.contains("diagnostic.log"))
    }
}

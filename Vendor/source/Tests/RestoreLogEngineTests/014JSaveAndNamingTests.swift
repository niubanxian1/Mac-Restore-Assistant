import XCTest
@testable import RestoreLogEngine

final class SaveAndNaming014JTests: XCTestCase {
    private var root: URL = FileManager.default.temporaryDirectory
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("rlm-014j-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func engine() -> CaptureCoordinator {
        CaptureCoordinator(backend: SimulatedLogCaptureBackend(), store: EvidenceStore(root: root.appendingPathComponent("Sessions", isDirectory: true)))
    }

    func testSaveOnlySkipsDiagnosticAndDefersEventScan() async throws {
        let e = engine()
        let s = try await e.beginCapture(config: CaptureConfig(outputDirectory: root))
        _ = try await e.stopCapture(sessionID: s.sessionID)
        let r = try await e.finalize(sessionID: s.sessionID, mode: .saveOnly, displayName: "A2485-Restore-Failure")
        XCTAssertEqual(r.record.analysisDeferred, true)
        XCTAssertEqual(r.record.diagnosticStatus, .skipped)
        XCTAssertEqual(r.record.eventCount, 0)
        XCTAssertEqual(r.record.sessionDisplayName, "A2485-Restore-Failure")
        XCTAssertFalse(FileManager.default.fileExists(atPath: URL(fileURLWithPath: s.outputDirectory).appendingPathComponent("diagnostic.log").path))
        XCTAssertEqual(r.record.integrityStatus, .verified)
    }

    func testNamingReaderUsesVerifiedMarketingMapAndFailure() throws {
        let raw = root.appendingPathComponent("real.log")
        try Data("""
        2026-11-08 13:00:00.000 I DeviceService MacBookPro18,2 ECID:000469023A9A801E
        2026-11-08 13:01:00.000 E DeviceService Restore failed (result = -1)
        """.utf8).write(to: raw)
        let evidence = SessionNamingReader.read(rawURL: raw)
        XCTAssertEqual(evidence.modelIdentifier, "MacBookPro18,2")
        XCTAssertEqual(evidence.ecid, "0x469023A9A801E")
        XCTAssertEqual(evidence.marketingModel, "A2485")
        XCTAssertEqual(evidence.terminalKind, .failure)
        let name = SessionNamingReader.makeName(style: .automaticConcise, evidence: evidence)
        XCTAssertTrue(name.contains("A2485"))
        XCTAssertTrue(name.contains("Failure"))
    }

    func testNamingConflictWhenTwoECIDsAppear() throws {
        let raw = root.appendingPathComponent("two.log")
        try Data("""
        MacBookPro18,2 ECID:000469023A9A801E
        MacBookPro18,3 ECID:000469023A9A801F
        """.utf8).write(to: raw)
        let evidence = SessionNamingReader.read(rawURL: raw)
        XCTAssertTrue(evidence.conflict)
        XCTAssertNil(evidence.ecid)
    }

    func testLegacySessionWithoutDisplayNameFallsBackToStableSessionID() throws {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let record = SessionRecord(
            sessionID: id,
            captureState: .savedPartial,
            captureHealth: .degraded,
            startedAtUTC: nil,
            endedAtUTC: nil,
            captureProfile: "p",
            captureCommand: [],
            captureBackend: "simulated",
            eventCount: 0,
            coverageStatus: .unverified,
            archiveStatus: .notRequested,
            integrityStatus: .verified,
            files: [],
            missingEvidence: [],
            errorReason: nil
        )
        let name = SessionEvidencePackage.zipName(for: record)
        XCTAssertTrue(name.hasPrefix("Session-"))
        XCTAssertTrue(name.hasSuffix(".zip"))
        XCTAssertFalse(name.contains("UNKNOWN"))
    }

    func testDisplayNamePersistsAndPackageZipInheritsIt() throws {
        let id = UUID()
        let record = SessionRecord(
            sessionID: id,
            sessionDisplayName: "A2485-Restore-Failure-20261108-153000",
            captureState: .savedPartial,
            captureHealth: .degraded,
            startedAtUTC: nil,
            endedAtUTC: nil,
            captureProfile: "p",
            captureCommand: [],
            captureBackend: "process",
            eventCount: 0,
            coverageStatus: .unverified,
            archiveStatus: .notRequested,
            integrityStatus: .verified,
            files: [],
            missingEvidence: [],
            errorReason: nil
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: data)
        XCTAssertEqual(decoded.sessionDisplayName, record.sessionDisplayName)
        XCTAssertEqual(SessionEvidencePackage.zipName(for: decoded), "A2485-Restore-Failure-20261108-153000.zip")
    }

    func testTwoSessionsKeepSeparateDisplayNames() throws {
        func record(_ id: UUID, _ name: String) -> SessionRecord {
            SessionRecord(sessionID: id, sessionDisplayName: name, captureState: .savedPartial,
                          captureHealth: .degraded, startedAtUTC: nil, endedAtUTC: nil,
                          captureProfile: "p", captureCommand: [], captureBackend: "process",
                          eventCount: 0, coverageStatus: .unverified, archiveStatus: .notRequested,
                          integrityStatus: .verified, files: [], missingEvidence: [], errorReason: nil)
        }
        let a = record(UUID(), "A2485-One")
        let b = record(UUID(), "A2681-Two")
        XCTAssertEqual(SessionEvidencePackage.zipName(for: a), "A2485-One.zip")
        XCTAssertEqual(SessionEvidencePackage.zipName(for: b), "A2681-Two.zip")
        XCTAssertNotEqual(a.sessionID, b.sessionID)
    }

    func testDiagnosticBuilderHonorsCancellation() throws {
        let raw = root.appendingPathComponent("cancel.log")
        let lines = (1...5000).map { "2026-11-08 13:00:00.000 I DeviceService line \($0)" }.joined(separator: "\n")
        try Data(lines.utf8).write(to: raw)
        let diag = root.appendingPathComponent("cancel.diagnostic.log")
        XCTAssertThrowsError(try DiagnosticLogBuilder.build(
            fromRaw: raw,
            to: diag,
            shouldCancel: { true }
        ))
    }

    func testPackageArchiveIsActualZipAndNoOverwrite() throws {
        let pkg = root.appendingPathComponent("pkg", isDirectory: true)
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: pkg.appendingPathComponent("README.md"))
        let zip = root.appendingPathComponent("out.zip")
        let result = try EvidencePackageArchive.archive(packageDirectory: pkg, destination: zip)
        XCTAssertEqual(result.byteSize, try Integrity.byteSize(ofFileAt: zip))
        XCTAssertEqual(try Integrity.sha256(ofFileAt: zip), result.sha256)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-t", zip.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertThrowsError(try EvidencePackageArchive.archive(packageDirectory: root.appendingPathComponent("nope"), destination: zip))
    }
}

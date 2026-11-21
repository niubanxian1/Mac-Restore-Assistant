import XCTest
@testable import RestoreLogEngine

final class WorkflowIntegration014ITests: XCTestCase {
    private var root: URL = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlm-014i-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var store: EvidenceStore {
        EvidenceStore(root: root.appendingPathComponent("Sessions", isDirectory: true))
    }

    private func engine() -> CaptureCoordinator {
        CaptureCoordinator(backend: SimulatedLogCaptureBackend(), store: store)
    }

    private var config: CaptureConfig {
        CaptureConfig(outputDirectory: root)
    }

    // A: default RC coverage is the 014A-derived profile, with bounded flags.
    func testA_defaultProfileIs014APrimaryAndBounded() {
        XCTAssertEqual(CaptureProfile.restore014APrimaryV2.id, "restore-014a-primary-v2")
        let p = CaptureProfile.restore014APrimaryV2
        XCTAssertTrue(p.predicate.contains("MobileDevice"))
        XCTAssertTrue(p.predicate.contains("AMPDevices"))
        XCTAssertFalse(p.predicate.contains("eventMessage CONTAINS[c] \"CHECKPOINT\""))
        XCTAssertEqual(p.commandArguments.first, "stream")
        XCTAssertTrue(p.commandArguments.contains("--no-backtrace"))
        XCTAssertTrue(p.commandArguments.contains("--no-signpost"))
        XCTAssertTrue(p.commandArguments.contains("--timeout"))
        XCTAssertEqual(p.commandArguments.last, p.predicate)
    }

    func testA_limitsAreBoundedAndNonZero() {
        let limits = CaptureLimits.standard
        XCTAssertGreaterThan(limits.maxDurationSeconds, 0)
        XCTAssertGreaterThan(limits.minFreeDiskBytes, 0)
        XCTAssertGreaterThan(limits.maxResidentBytes, 0)
        XCTAssertGreaterThan(limits.sampleIntervalSeconds, 0)
    }

    // B: pre-capture context is stored separately, not prepended to raw.
    func testB_preCaptureContextIsSeparateEvidenceFile() async throws {
        var cfg = config
        cfg.preCaptureContext = "2026-11-08 monitor context\nACURestoreFirmwareCommand\n"
        let e = engine()
        let session = try await e.beginCapture(config: cfg)
        _ = try await e.stopCapture(sessionID: session.sessionID)
        let result = try await e.finalize(sessionID: session.sessionID)
        let dir = URL(fileURLWithPath: session.outputDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("pre-capture-context.log").path))
        XCTAssertTrue(result.record.files.contains { $0.role == "pre-capture-context" })
        let raw = try String(contentsOf: URL(fileURLWithPath: session.rawLogPath), encoding: .utf8)
        XCTAssertFalse(raw.contains("monitor context"))
    }

    // C: discard removes only this stopped session and never a saved sibling.
    func testC_discardRemovesOnlyCurrentSession() async throws {
        let e = engine()
        let old = try await e.beginCapture(config: config)
        _ = try await e.stopCapture(sessionID: old.sessionID)
        let saved = try await e.finalize(sessionID: old.sessionID)

        let doomed = try await e.beginCapture(config: config)
        _ = try await e.stopCapture(sessionID: doomed.sessionID)
        let discarded = try await e.discard(sessionID: doomed.sessionID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: discarded.removedDirectory))
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.sessionJSONPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.rawLogPath))
    }

    // D: naming template expands present fields, has explicit fallback, and cannot escape a parent path.
    func testD_sessionPackageNamingExpandsAndSanitizes() {
        let ctx = SessionPackageNamingContext(
            date: "20261108", time: "132738", model: "MacBookPro18,2",
            ecid: "0x469023A9A801E", restoreStatus: "failure", sessionID: "ABC"
        )
        let name = SessionPackageNaming.expand(
            template: "RLM-{date}-{time}-{model}-{ecid}-{status}-{unknown}",
            context: ctx
        )
        XCTAssertTrue(name.contains("MacBookPro18,2"))
        XCTAssertTrue(name.contains("0x469023A9A801E"))
        XCTAssertTrue(name.contains("failure"))
        XCTAssertTrue(name.contains("UNKNOWN"))
        XCTAssertFalse(name.contains("/"))
        let fallback = SessionPackageNaming.expand(
            template: "../{model}/{ecid}",
            context: SessionPackageNamingContext(date: "", time: "", model: "", ecid: "", restoreStatus: "", sessionID: "")
        )
        XCTAssertFalse(fallback.contains("/"))
        XCTAssertTrue(fallback.contains("UNKNOWN"))
    }

    // E: package builder can carry real session metadata and session.json without changing raw.
    func testE_sessionPackageBuilderUsesSessionMetadataAndPreservesRaw() throws {
        let raw = root.appendingPathComponent("restore.log")
        let diag = root.appendingPathComponent("diagnostic.log")
        let sessionJSON = root.appendingPathComponent("session.json")
        let rawBytes = Data("raw-session-bytes\n".utf8)
        try rawBytes.write(to: raw)
        try Data("diagnostic\n".utf8).write(to: diag)
        try Data("{\"sessionID\":\"x\"}\n".utf8).write(to: sessionJSON)
        let analysis = ImportedDiagnosticAnalysis(
            rawPath: raw.path, rawBytes: rawBytes.count, rawLines: 1,
            diagnosticPath: diag.path, diagnosticBytes: 11, diagnosticLines: 1,
            terminalKind: .failure, eventLines: 1, metadataLines: 0,
            malformedJSONLines: 0, keptLines: 1, droppedLines: 0,
            checkpointLineCount: 1, preservedNeedles: [:]
        )
        let dest = root.appendingPathComponent("package", isDirectory: true)
        let result = try ImportedEvidencePackageBuilder.build(
            rawURL: raw, diagnosticURL: diag, analysis: analysis, destination: dest,
            sessionMetadata: ["schema": "rlm-session-metadata-v1", "status": "AVAILABLE", "fabricated": false],
            sessionJSONURL: sessionJSON
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.directoryPath + "/session-metadata.json"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.directoryPath + "/session.json"))
        let metadata = try String(contentsOfFile: result.directoryPath + "/session-metadata.json", encoding: .utf8)
        XCTAssertTrue(metadata.contains("AVAILABLE"))
        XCTAssertFalse(metadata.contains("NOT_AVAILABLE"))
        XCTAssertEqual(try Data(contentsOf: raw), rawBytes)
        XCTAssertTrue(result.files.contains { $0.role == "session-json" })
    }

    // F: monitor predicate is a Restore command, never a DFU/USB predicate.
    func testF_restoreMonitorPredicateIsNotDFU() {
        let cfg = RestoreStartMonitor.Config()
        XCTAssertTrue(cfg.predicate.contains("ACURestoreFirmwareCommand"))
        XCTAssertTrue(cfg.arguments.contains("--no-backtrace"))
        XCTAssertFalse(cfg.predicate.lowercased().contains("dfu"))
        XCTAssertFalse(cfg.predicate.lowercased().contains("usb"))
    }
}

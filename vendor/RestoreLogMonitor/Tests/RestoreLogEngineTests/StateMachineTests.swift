import XCTest
@testable import RestoreLogEngine

final class StateMachineTests: XCTestCase {
    private var root: URL = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlm-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeEngine(backend: LogCaptureBackend) -> CaptureCoordinator {
        CaptureCoordinator(
            backend: backend,
            store: EvidenceStore(root: root.appendingPathComponent("Sessions", isDirectory: true))
        )
    }

    private var config: CaptureConfig {
        CaptureConfig(outputDirectory: root)
    }

    // T01 — a simulated restore sequence produces evidence that survives a re-read.
    func testRestoreSequenceIsCapturedAndHashed() async throws {
        let engine = makeEngine(backend: SimulatedLogCaptureBackend())
        let session = try await engine.beginCapture(config: config)

        let running = try await engine.getStatus(sessionID: session.sessionID)
        XCTAssertEqual(running.state, .recording)
        XCTAssertGreaterThan(running.rawByteCount, 0)

        let stop = try await engine.stopCapture(sessionID: session.sessionID)
        XCTAssertEqual(stop.reason, .userRequested)

        let exported = try await engine.finalize(sessionID: session.sessionID)

        XCTAssertEqual(exported.record.eventCount, 8)
        XCTAssertEqual(exported.record.integrityStatus, .verified)
        XCTAssertEqual(exported.record.captureBackend, "simulated")
        XCTAssertEqual(exported.record.coverageStatus, .partial)
        // D0 may not claim a verified capture: no archive is collected yet.
        XCTAssertEqual(exported.record.captureState, .savedPartial)

        let rawURL = URL(fileURLWithPath: session.rawLogPath)
        let recomputed = try Integrity.sha256(ofFileAt: rawURL)
        XCTAssertEqual(recomputed, exported.record.files.first { $0.role == "raw-log" }?.sha256)

        let json = try Data(contentsOf: URL(fileURLWithPath: exported.sessionJSONPath))
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: json)
        XCTAssertEqual(decoded.sessionID, session.sessionID)
        XCTAssertEqual(decoded.captureCommand, ["simulated://log-stream"] + CaptureProfile.restore014APrimaryV2.commandArguments)
    }

    // T05/T06 — zero evidence must never render as a verified capture.
    func testEmptyCaptureIsNeverVerified() async throws {
        let engine = makeEngine(backend: SimulatedLogCaptureBackend(fixture: .empty))
        let session = try await engine.beginCapture(config: config)
        _ = try await engine.stopCapture(sessionID: session.sessionID)
        let exported = try await engine.finalize(sessionID: session.sessionID)

        XCTAssertEqual(exported.record.eventCount, 0)
        XCTAssertEqual(exported.record.coverageStatus, .unverified)
        XCTAssertEqual(exported.record.captureState, .savedPartial)
        XCTAssertNotEqual(exported.record.captureState, .savedVerified)
        XCTAssertTrue(exported.record.missingEvidence.contains("No verified restore event"))
    }

    // T02 — two starts may never produce two capture processes.
    func testSecondStartIsRejected() async throws {
        let engine = makeEngine(backend: SimulatedLogCaptureBackend())
        _ = try await engine.beginCapture(config: config)

        do {
            _ = try await engine.beginCapture(config: config)
            XCTFail("second start must be rejected")
        } catch let error as CaptureError {
            guard case .invalidTransition = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    // T03 — the second stop must not finalize twice.
    func testSecondStopIsRejected() async throws {
        let engine = makeEngine(backend: SimulatedLogCaptureBackend())
        let session = try await engine.beginCapture(config: config)
        _ = try await engine.stopCapture(sessionID: session.sessionID)

        do {
            _ = try await engine.stopCapture(sessionID: session.sessionID)
            XCTFail("second stop must be rejected")
        } catch let error as CaptureError {
            guard case .invalidTransition = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    // T04 — a dead child means the session is interrupted, not "still recording".
    func testBackendExitIsReportedAsInterrupted() async throws {
        let engine = makeEngine(backend: SimulatedLogCaptureBackend(immediateExit: 7))
        let session = try await engine.beginCapture(config: config)

        let status = try await engine.getStatus(sessionID: session.sessionID)
        XCTAssertEqual(status.state, .interrupted)
        XCTAssertEqual(status.health, .degraded)
    }

    // Classification order: an error carrying a phase marker is an error.
    func testErrorClassificationWins() {
        let line = "2026-10-30 19:06:31.115 Df com.apple.configurator.xpc.DeviceService[1:2] (MobileDevice) _AMRUSBDeviceSendDeviceRequestTO_block_invoke: AMRUSBDevice error (-536854449)"
        XCTAssertEqual(EventTaxonomy.classify(line)?.tier, .t5Error)
    }

    // The GUI process predicate is the wrong one; the profile must name the XPC service family.
    func testProfilePredicateTargetsXPCService() {
        XCTAssertEqual(CaptureProfile.restoreDefaultV1.predicate, #"process CONTAINS[c] "configurator""#)
        XCTAssertEqual(CaptureProfile.restore014APrimaryV2.commandArguments.first, "stream")
    }

    // T15 baseline — a changed byte must change the hash.
    func testHashChangesAfterTamper() throws {
        let url = root.appendingPathComponent("probe.log")
        try Data("abc".utf8).write(to: url)
        let before = try Integrity.sha256(ofFileAt: url)
        try Data("abd".utf8).write(to: url)
        let after = try Integrity.sha256(ofFileAt: url)
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(try Integrity.byteSize(ofFileAt: url), 3)
    }
}

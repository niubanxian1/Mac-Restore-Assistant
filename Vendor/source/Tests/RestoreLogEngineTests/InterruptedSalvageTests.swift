import Foundation
import XCTest
@testable import RestoreLogEngine

// MARK: - Test-only backend doubles
//
// These implement the public `LogCaptureBackend` seam so a test can drive an
// *unexpected* process exit (no `requestTermination` call), observe termination
// requests (to prove nothing kills a process during salvage), and gate
// `isRunning` to place the coordinator in the normal-stop/crash race window.

/// A backend whose child can die on its own.
actor ProbeBackend: LogCaptureBackend {
    let kind = "probe"
    private var running = false
    private var exitStatus: Int32? = 9
    private var terminationRequests = 0
    private let payload: String

    init(payload: String = ProbeBackend.defaultPayload) {
        self.payload = payload
    }

    static let defaultPayload = """
    2026-10-30 19:00:00.000 Df com.apple.configurator.xpc.DeviceService[1:2] (MobileDevice) Created state machine for device with ECID=0x469023A9A801E
    2026-10-30 19:00:01.000 I com.apple.configurator.xpc.DeviceService[1:2] (MobileDevice) Sent image successfully from: /Users/operator/tmp/img4

    """

    func start(config: CaptureConfig, rawLogURL: URL, stderrURL: URL) async throws -> BackendHandle {
        try Data(payload.utf8).write(to: rawLogURL)
        try Data().write(to: stderrURL)
        running = true
        return BackendHandle(
            pid: 4242,
            executablePath: "probe://crash",
            arguments: config.profile.commandArguments,
            startedAtUTC: Date()
        )
    }

    /// Simulates the capture process dying without anyone asking it to.
    func crash() { running = false }
    func setExitStatus(_ status: Int32?) { exitStatus = status }
    func terminationRequestCount() -> Int { terminationRequests }

    func waitForExit(handle: BackendHandle) async -> Int32? { running ? nil : exitStatus }
    func requestTermination(handle: BackendHandle) async {
        terminationRequests += 1
        running = false
    }
    func isRunning(handle: BackendHandle) async -> Bool { running }
}

/// A backend that parks `isRunning` until the test releases it, so the
/// normal-stop / crash race can be reproduced deterministically.
actor GatedBackend: LogCaptureBackend {
    let kind = "gated"
    private var running = true
    private var gateOpen = false
    private var enteredCheck: CheckedContinuation<Void, Never>?
    private var entered = false
    private var release: CheckedContinuation<Void, Never>?

    func start(config: CaptureConfig, rawLogURL: URL, stderrURL: URL) async throws -> BackendHandle {
        try Data(ProbeBackend.defaultPayload.utf8).write(to: rawLogURL)
        try Data().write(to: stderrURL)
        running = true
        return BackendHandle(
            pid: 5151,
            executablePath: "gated://probe",
            arguments: config.profile.commandArguments,
            startedAtUTC: Date()
        )
    }

    /// Resolves once `isRunning` has begun and is parked.
    func waitUntilParked() async {
        if entered { return }
        await withCheckedContinuation { enteredCheck = $0 }
    }

    func openGate() {
        gateOpen = true
        release?.resume()
        release = nil
    }

    func isRunning(handle: BackendHandle) async -> Bool {
        entered = true
        enteredCheck?.resume()
        enteredCheck = nil
        if !gateOpen {
            await withCheckedContinuation { release = $0 }
        }
        return running
    }

    func waitForExit(handle: BackendHandle) async -> Int32? { running ? nil : 3 }
    func requestTermination(handle: BackendHandle) async { running = false }
}

// MARK: - F05 — interrupted session evidence salvage

final class InterruptedSalvageTests: XCTestCase {
    private var root: URL = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlm-f05-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var config: CaptureConfig { CaptureConfig(outputDirectory: root) }

    private func makeStore() -> EvidenceStore {
        EvidenceStore(root: root.appendingPathComponent("Sessions", isDirectory: true))
    }

    private func makeEngine(backend: LogCaptureBackend) -> CaptureCoordinator {
        CaptureCoordinator(backend: backend, store: makeStore())
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

    private func metadataFileExists(in dir: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let path = dir.appendingPathComponent("session.json").path
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    private func sha256(_ url: URL) throws -> String {
        try Integrity.sha256(ofFileAt: url)
    }

    @discardableResult
    private func finalizeResult(
        _ engine: CaptureCoordinator, _ id: UUID
    ) async -> (ExportResult?, Error?) {
        do { return (try await engine.finalize(sessionID: id), nil) }
        catch { return (nil, error) }
    }

    /// Starts a session, lets real bytes land, then kills the child without a
    /// termination request, and confirms the coordinator moved to INTERRUPTED.
    private func interruptedSession(
        _ engine: CaptureCoordinator, _ backend: ProbeBackend
    ) async throws -> (SessionHandle, CaptureStatus) {
        let session = try await engine.beginCapture(config: config)
        await backend.crash()
        let status = try await engine.getStatus(sessionID: session.sessionID)
        return (session, status)
    }

    // MARK: A01 — normal capture still behaves exactly as before

    func testA01NormalCaptureIsUnchanged() async throws {
        let backend = ProbeBackend()
        let engine = makeEngine(backend: backend)
        let session = try await engine.beginCapture(config: config)

        let stopped = try await engine.stopCapture(sessionID: session.sessionID)
        XCTAssertEqual(stopped.reason, .userRequested)

        let exported = try await engine.finalize(sessionID: session.sessionID)
        XCTAssertEqual(exported.record.captureState, .savedPartial)
        XCTAssertEqual(exported.record.integrityStatus, .verified)
        XCTAssertEqual(exported.record.captureHealth, .unconfirmed)
        XCTAssertNil(exported.record.errorReason, "a clean stop must not carry an interrupt reason")
        XCTAssertFalse(exported.record.missingEvidence.contains { $0.contains("interrupted") })
    }

    // MARK: A02 — interrupted session with real bytes is salvageable

    func testA02InterruptedSessionWithBytesIsSalvageable() async throws {
        let backend = ProbeBackend()
        let engine = makeEngine(backend: backend)
        let (session, interrupted) = try await interruptedSession(engine, backend)

        XCTAssertEqual(interrupted.state, .interrupted)
        XCTAssertGreaterThan(interrupted.rawByteCount, 0)

        let dir = sessionDir(session)
        let before = try sha256(dir.appendingPathComponent("restore.log"))

        let (exported, error) = await finalizeResult(engine, session.sessionID)
        // Identical assertion and wording to the red run, so red -> green is a
        // change in the implementation, not in the test.
        XCTAssertNotNil(
            exported,
            "F05: an INTERRUPTED session holding real captured bytes must be salvageable "
            + "through finalize(); instead it threw: \(String(describing: error))"
        )
        let result = try XCTUnwrap(exported)

        XCTAssertEqual(result.record.captureState, .savedPartial)
        XCTAssertNotEqual(result.record.captureState, .savedVerified)
        XCTAssertEqual(result.record.integrityStatus, .verified)
        XCTAssertEqual(result.record.captureHealth, .degraded,
                       "an interrupted acquisition is degraded even when the bytes hash cleanly")
        XCTAssertGreaterThan(result.record.eventCount, 0)

        // Raw bytes untouched by the salvage.
        XCTAssertEqual(try sha256(dir.appendingPathComponent("restore.log")), before)

        // The interruption is recorded, not hidden.
        let metadata = try XCTUnwrap(readMetadata(in: dir))
        XCTAssertEqual(metadata["captureState"] as? String, "SAVED_PARTIAL")
        XCTAssertEqual(metadata["captureHealth"] as? String, "degraded")
        let reason = try XCTUnwrap(metadata["errorReason"] as? String)
        XCTAssertTrue(reason.contains("exited unexpectedly"), "got reason: \(reason)")
        let missing = try XCTUnwrap(metadata["missingEvidence"] as? [String])
        XCTAssertTrue(missing.contains { $0.contains("Session interrupted") })
        XCTAssertTrue(missing.contains { $0.contains("continuity not verified") })

        // The completion marker and manifest now exist and agree with disk.
        XCTAssertTrue(metadataFileExists(in: dir))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("SHA256SUMS.txt").path))
    }

    // MARK: A03 — interrupted with an empty log must not fake valid evidence

    func testA03InterruptedWithEmptyLogIsNotAFalsePass() async throws {
        let backend = ProbeBackend(payload: "")
        let engine = makeEngine(backend: backend)
        let (session, interrupted) = try await interruptedSession(engine, backend)
        XCTAssertEqual(interrupted.state, .interrupted)
        XCTAssertEqual(interrupted.rawByteCount, 0)

        let (exported, _) = await finalizeResult(engine, session.sessionID)
        let result = try XCTUnwrap(exported)

        XCTAssertEqual(result.record.eventCount, 0)
        XCTAssertEqual(result.record.coverageStatus, .unverified)
        XCTAssertEqual(result.record.captureState, .savedPartial)
        XCTAssertNotEqual(result.record.captureState, .savedVerified)
        XCTAssertTrue(result.record.missingEvidence.contains("No verified restore event"))
    }

    // MARK: A04 — repeated salvage must not race or corrupt

    func testA04SecondSalvageIsRejectedAndHarmless() async throws {
        let backend = ProbeBackend()
        let engine = makeEngine(backend: backend)
        let (session, _) = try await interruptedSession(engine, backend)

        let (first, error1) = await finalizeResult(engine, session.sessionID)
        XCTAssertNotNil(first, "first salvage must succeed: \(String(describing: error1))")

        let dir = sessionDir(session)
        let afterFirst = try sha256(dir.appendingPathComponent("restore.log"))
        let metadataAfterFirst = try Data(contentsOf: dir.appendingPathComponent("session.json"))

        let (second, error2) = await finalizeResult(engine, session.sessionID)
        XCTAssertNil(second, "a second salvage must be refused")
        let captureError = try XCTUnwrap(error2 as? CaptureError)
        guard case .invalidTransition = captureError else {
            return XCTFail("expected invalidTransition, got \(captureError)")
        }

        XCTAssertEqual(try sha256(dir.appendingPathComponent("restore.log")), afterFirst)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("session.json")), metadataAfterFirst,
                       "a refused second salvage must not rewrite the committed metadata")
    }

    // MARK: A05 — salvage failure keeps the raw evidence

    func testA05SalvageFailurePreservesRawEvidence() async throws {
        let backend = ProbeBackend()
        let engine = makeEngine(backend: backend)
        let (session, _) = try await interruptedSession(engine, backend)

        let dir = sessionDir(session)
        let before = try sha256(dir.appendingPathComponent("restore.log"))
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("SHA256SUMS.txt"), withIntermediateDirectories: true)

        let (exported, error) = await finalizeResult(engine, session.sessionID)
        XCTAssertNil(exported)
        XCTAssertNotNil(error)

        XCTAssertEqual(try sha256(dir.appendingPathComponent("restore.log")), before,
                       "raw evidence must survive a failed salvage")
        XCTAssertFalse(metadataFileExists(in: dir), "no completion marker after a failed salvage")
    }

    // MARK: A06 — unwritable destination fails loudly

    func testA06UnwritableSaveFailsExplicitly() async throws {
        let backend = ProbeBackend()
        let engine = makeEngine(backend: backend)
        let (session, _) = try await interruptedSession(engine, backend)

        let dir = sessionDir(session)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("session.json"), withIntermediateDirectories: true)

        let (exported, error) = await finalizeResult(engine, session.sessionID)
        XCTAssertNil(exported, "an unwritable destination must not report success")
        XCTAssertNotNil(error)
        XCTAssertFalse(metadataFileExists(in: dir))
    }

    // MARK: A07 — a tampered log cannot pass verification

    func testA07TamperedLogIsRejectedByVerification() async throws {
        let backend = ProbeBackend()
        let engine = makeEngine(backend: backend)
        let (session, _) = try await interruptedSession(engine, backend)

        let (exported, _) = await finalizeResult(engine, session.sessionID)
        let result = try XCTUnwrap(exported)

        let dir = sessionDir(session)
        let rawURL = dir.appendingPathComponent("restore.log")
        let recorded = try XCTUnwrap(result.record.files.first { $0.role == "raw-log" }?.sha256)

        // Tamper after the digest was recorded.
        var bytes = try Data(contentsOf: rawURL)
        bytes.append(0x42)
        try bytes.write(to: rawURL)
        XCTAssertNotEqual(try sha256(rawURL), recorded)

        let paths = SessionPaths(directory: dir)
        XCTAssertThrowsError(
            try CaptureCoordinator.verifyChecksumFile(paths: paths, expected: result.record.files)
        ) { error in
            guard case CaptureError.integrityCheckFailed = error else {
                return XCTFail("expected integrityCheckFailed, got \(error)")
            }
        }
    }

    // MARK: A08 — salvage never kills a process

    func testA08SalvageNeverSignalsAProcess() async throws {
        let backend = ProbeBackend()
        let engine = makeEngine(backend: backend)
        let (session, _) = try await interruptedSession(engine, backend)

        let beforeSalvage = await backend.terminationRequestCount()
        XCTAssertEqual(beforeSalvage, 0, "the crash must not be produced by a termination request")

        let (exported, _) = await finalizeResult(engine, session.sessionID)
        XCTAssertNotNil(exported)

        let afterSalvage = await backend.terminationRequestCount()
        XCTAssertEqual(afterSalvage, 0,
                       "salvage must not signal or kill any pid, let alone a recycled one")
    }

    // MARK: A09 — a later session must not overwrite earlier evidence

    func testA09LaterSessionDoesNotOverwriteEarlierEvidence() async throws {
        let backend = ProbeBackend()
        let engine = makeEngine(backend: backend)
        let (first, _) = try await interruptedSession(engine, backend)

        let firstDir = sessionDir(first)
        let firstRaw = firstDir.appendingPathComponent("restore.log")
        let firstHash = try sha256(firstRaw)

        // INTERRUPTED accepts a new session; that must not touch session one's files.
        let second = try await engine.beginCapture(config: config)
        let secondDir = sessionDir(second)
        XCTAssertNotEqual(firstDir.path, secondDir.path, "session paths must be unique")

        XCTAssertTrue(FileManager.default.fileExists(atPath: firstRaw.path))
        XCTAssertEqual(try sha256(firstRaw), firstHash,
                       "starting a new session must not rewrite another session's raw log")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: firstDir.path).sorted(),
                       ["capture-stderr.log", "restore.log"],
                       "session one must still hold only its own files")
    }

    // MARK: A10 — normal stop must win the race against a stale crash read

    func testA10NormalStopIsNotClobberedByAStaleStatusRead() async throws {
        let backend = GatedBackend()
        let engine = makeEngine(backend: backend)
        let session = try await engine.beginCapture(config: config)

        // Park getStatus inside `await backend.isRunning` while state is .recording.
        let statusTask = Task { try await engine.getStatus(sessionID: session.sessionID) }
        await backend.waitUntilParked()

        // A normal stop completes while the status read is still parked.
        let stopped = try await engine.stopCapture(sessionID: session.sessionID)
        XCTAssertEqual(stopped.reason, .userRequested)

        // Release the parked read: it must not resurrect INTERRUPTED.
        await backend.openGate()
        let status = try await statusTask.value

        XCTAssertNotEqual(
            status.state, .interrupted,
            "a completed normal stop must never be converted into INTERRUPTED by a stale read"
        )
        XCTAssertEqual(status.state, .finalizing)
    }

    // MARK: A11 — an unobserved exit status stays UNKNOWN

    func testA11UnknownExitStatusStaysUnknown() async throws {
        let backend = ProbeBackend()
        await backend.setExitStatus(nil)
        let engine = makeEngine(backend: backend)
        let (session, _) = try await interruptedSession(engine, backend)

        let (exported, _) = await finalizeResult(engine, session.sessionID)
        let result = try XCTUnwrap(exported)

        let reason = try XCTUnwrap(result.record.errorReason)
        XCTAssertTrue(reason.contains("exit status unknown"),
                      "an unobserved exit status must stay unknown, got: \(reason)")
        XCTAssertTrue(result.record.missingEvidence.contains("Capture process exit not observed"))
        XCTAssertEqual(result.record.captureState, .savedPartial)
        XCTAssertNotEqual(result.record.captureState, .savedVerified)
    }

    // MARK: A12 — the F03 protection still holds on the salvage path

    func testA12SalvageNeverClaimsVerifiedCapture() async throws {
        let backend = ProbeBackend()
        let engine = makeEngine(backend: backend)
        let (session, _) = try await interruptedSession(engine, backend)

        let (exported, _) = await finalizeResult(engine, session.sessionID)
        let result = try XCTUnwrap(exported)

        // Integrity of the bytes may be verified; the capture itself never is.
        XCTAssertEqual(result.record.integrityStatus, .verified)
        XCTAssertNotEqual(result.record.captureState, .savedVerified)
        XCTAssertEqual(result.record.coverageStatus, .partial,
                       "observation ended early, so coverage can only be partial")

        // F03 ordering still applies: the manifest exists and matches disk.
        let dir = sessionDir(session)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("SHA256SUMS.txt").path))
        XCTAssertTrue(metadataFileExists(in: dir))
    }
}

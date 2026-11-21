import Foundation
import XCTest
@testable import DeviceCapturePrototype
import RestoreLogEngine

@MainActor
final class Batch3RLMPersistencePolicyTests: XCTestCase {
    func testNewInstallAutoSaveDefaultsOffAndAutoMonitorStaysIndependent() {
        let suite = "Batch3RLMPolicy-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = LogWorkspacePreferences(
            defaults: defaults,
            startingRoot: FileManager.default.temporaryDirectory)
        let rawSettings = RestoreRawPersistenceSettings(defaults: defaults)

        XCTAssertFalse(rawSettings.autoSaveRestoreRawLogs)
        XCTAssertFalse(preferences.autoMonitorEnabled)

        preferences.autoMonitorEnabled = true
        XCTAssertFalse(rawSettings.autoSaveRestoreRawLogs)

        rawSettings.autoSaveRestoreRawLogs = true
        XCTAssertTrue(preferences.autoMonitorEnabled)
        XCTAssertTrue(rawSettings.autoSaveRestoreRawLogs)
    }

    func testRawPolicyThresholdsAndRetentionPersist() {
        let suite = "Batch3RLMPolicyPersist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = RestoreRawPersistenceSettings(defaults: defaults)
        first.autoSaveRestoreRawLogs = true
        first.spaceWarningThresholdBytes = 2_147_483_648
        first.retentionDays = 14
        first.retentionBytes = 4_294_967_296

        let restarted = RestoreRawPersistenceSettings(defaults: defaults)
        XCTAssertTrue(restarted.autoSaveRestoreRawLogs)
        XCTAssertEqual(
            restarted.spaceWarningThresholdBytes,
            2_147_483_648)
        XCTAssertEqual(restarted.retentionDays, 14)
        XCTAssertEqual(restarted.retentionBytes, 4_294_967_296)
    }

    func testNotRequestedWithoutManualSessionNeverStartsRLM() async {
        let capture = Batch3PolicyCapture(state: .idle)
        let coordinator = RestoreRLMCoordinator(
            capture: capture,
            startupTimeout: 0.01,
            drainTimeout: 0.01,
            pollInterval: 0.001)

        let binding = await coordinator.prepare(
            taskID: UUID(),
            canonicalECID: "0011223344556677",
            saveRequested: false)

        XCTAssertEqual(binding.status, .notRequested)
        XCTAssertEqual(binding.ownership, .notRequested)
        XCTAssertEqual(capture.startCount, 0)
        XCTAssertEqual(capture.stopCount, 0)
    }

    func testNotRequestedWithManualSessionIsReadOnlyAndNeverStopped() async {
        let raw = URL(fileURLWithPath: "/tmp/manual-batch3.log")
        let capture = Batch3PolicyCapture(state: .recording, rawURL: raw)
        let coordinator = RestoreRLMCoordinator(
            capture: capture,
            startupTimeout: 0.01,
            drainTimeout: 0.01,
            pollInterval: 0.001)
        let taskID = UUID()

        let binding = await coordinator.prepare(
            taskID: taskID,
            canonicalECID: "0011223344556677",
            saveRequested: false)
        await coordinator.finish(taskID: taskID, outcome: .success)

        XCTAssertEqual(binding.status, .notRequested)
        XCTAssertEqual(binding.ownership, .manualUserOwned)
        XCTAssertEqual(binding.rawLogURL, raw)
        XCTAssertEqual(capture.startCount, 0)
        XCTAssertEqual(capture.stopCount, 0)
        XCTAssertTrue(capture.state == .recording)
        let finalization = await coordinator.finalization(
            taskID: taskID,
            timeout: 0.02)
        XCTAssertNil(finalization?.finalizedAt)
        XCTAssertEqual(
            finalization?.disposition,
            .continuedInManualSession)
    }

    func testSaveRequestedPreservesExistingOwnedReuseRules() async {
        let capture = Batch3PolicyCapture(
            state: .idle,
            rawURL: URL(fileURLWithPath: "/tmp/owned-batch3.log"))
        let coordinator = RestoreRLMCoordinator(
            capture: capture,
            startupTimeout: 0.05,
            drainTimeout: 0.02,
            pollInterval: 0.002)

        let first = await coordinator.prepare(
            taskID: UUID(),
            canonicalECID: "0011223344556677",
            saveRequested: true)
        let second = await coordinator.prepare(
            taskID: UUID(),
            canonicalECID: "0011223344556678",
            saveRequested: true)

        XCTAssertEqual(first.status, .startedOwnedSession)
        XCTAssertEqual(first.ownership, .restoreOwned)
        XCTAssertEqual(second.status, .recordingReused)
        XCTAssertEqual(second.ownership, .restoreOwned)
        XCTAssertEqual(capture.startCount, 1)
    }

    func testOwnedSessionFinalizationRecordsTimestampAfterActualTerminalState() async throws {
        let capture = Batch3PolicyCapture(
            state: .idle,
            rawURL: URL(fileURLWithPath: "/tmp/owned-final.log"))
        let coordinator = RestoreRLMCoordinator(
            capture: capture,
            startupTimeout: 0.05,
            drainTimeout: 0.01,
            pollInterval: 0.002)
        let taskID = UUID()
        let binding = await coordinator.prepare(
            taskID: taskID,
            canonicalECID: "0011223344556677",
            saveRequested: true)
        XCTAssertEqual(binding.ownership, .restoreOwned)
        await coordinator.finish(taskID: taskID, outcome: .success)

        let finalizationTask = Task { @MainActor in
            await coordinator.finalization(taskID: taskID, timeout: 0.2)
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(capture.stopCount, 1)
        capture.completeFinalization(as: .savedVerified)
        let finalization = await finalizationTask.value

        XCTAssertEqual(capture.stopCount, 1)
        XCTAssertNotNil(finalization?.finalizedAt)
        XCTAssertEqual(finalization?.disposition, .finalizedOwnedSession)
    }

    func testManualSessionFinalizationNeverClaimsOwnedEndTime() async {
        let capture = Batch3PolicyCapture(
            state: .recording,
            rawURL: URL(fileURLWithPath: "/tmp/manual-final.log"))
        let coordinator = RestoreRLMCoordinator(
            capture: capture,
            startupTimeout: 0.02,
            drainTimeout: 0.01,
            pollInterval: 0.001)
        let taskID = UUID()
        _ = await coordinator.prepare(
            taskID: taskID,
            canonicalECID: "0011223344556677",
            saveRequested: true)
        await coordinator.finish(taskID: taskID, outcome: .failure)

        let finalization = await coordinator.finalization(
            taskID: taskID,
            timeout: 0.02)

        XCTAssertNil(finalization?.finalizedAt)
        XCTAssertEqual(
            finalization?.disposition,
            .continuedInManualSession)
        XCTAssertEqual(capture.stopCount, 0)
    }
}

@MainActor
private final class Batch3PolicyCapture: RestoreCaptureLifecycle {
    var state: CaptureState
    var currentRawLogURL: URL?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(state: CaptureState, rawURL: URL? = nil) {
        self.state = state
        currentRawLogURL = rawURL
    }

    func start(preCaptureContext: String?, automatic: Bool) {
        startCount += 1
        state = .recording
    }

    func stop() {
        stopCount += 1
        state = .finalizing
    }

    func completeFinalization(as state: CaptureState) {
        self.state = state
    }
}

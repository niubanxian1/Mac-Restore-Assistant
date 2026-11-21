import Foundation
import XCTest
@testable import DeviceCapturePrototype
import RestoreLogEngine

@MainActor
final class RestoreRLMCoordinatorTests: XCTestCase {
    func testExistingRecordingSessionIsReusedAndManualSessionIsNeverStopped() async throws {
        let raw = URL(fileURLWithPath: "/tmp/manual-restore.log")
        let capture = FakeRestoreCapture(state: .recording, rawURL: raw)
        let coordinator = RestoreRLMCoordinator(
            capture: capture,
            startupTimeout: 0.1,
            drainTimeout: 0.02,
            pollInterval: 0.005)

        let binding = await coordinator.prepare(
            taskID: UUID(),
            canonicalECID: "0000000012345670")

        XCTAssertEqual(binding.status, .recordingReused)
        XCTAssertEqual(binding.rawLogURL, raw)
        XCTAssertEqual(capture.startCount, 0)

        await coordinator.finish(taskID: binding.taskID, outcome: .success)
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(capture.stopCount, 0)
    }

    func testIdleCaptureStartsOnceAndStopsOnlyAfterBoundedDrain() async throws {
        let raw = URL(fileURLWithPath: "/tmp/owned-restore.log")
        let capture = FakeRestoreCapture(state: .idle, rawURL: raw)
        let coordinator = RestoreRLMCoordinator(
            capture: capture,
            startupTimeout: 0.1,
            drainTimeout: 0.03,
            pollInterval: 0.005)

        let binding = await coordinator.prepare(
            taskID: UUID(),
            canonicalECID: "0000000012345670")

        XCTAssertEqual(binding.status, .startedOwnedSession)
        XCTAssertEqual(capture.startCount, 1)
        XCTAssertEqual(capture.lastStartECID, "0000000012345670")
        await coordinator.finish(taskID: binding.taskID, outcome: .success)
        XCTAssertEqual(capture.stopCount, 0)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(capture.stopCount, 1)
    }

    func testStoppingOrFinalizingSessionFailsOverToUnavailableWithoutSecondStart() async {
        for state in [CaptureState.stopping, .finalizing, .failed] {
            let capture = FakeRestoreCapture(
                state: state,
                rawURL: URL(fileURLWithPath: "/tmp/old.log"))
            let coordinator = RestoreRLMCoordinator(
                capture: capture,
                startupTimeout: 0.02,
                drainTimeout: 0.01,
                pollInterval: 0.002)
            let binding = await coordinator.prepare(
                taskID: UUID(),
                canonicalECID: "0000000012345670")
            XCTAssertEqual(binding.status, .unavailable)
            XCTAssertEqual(capture.startCount, 0)
            XCTAssertEqual(capture.stopCount, 0)
        }
    }

    func testContinuousRestoreUsesTheSameRecordingSessionAndPreemptsDrain() async throws {
        let capture = FakeRestoreCapture(
            state: .idle,
            rawURL: URL(fileURLWithPath: "/tmp/continuous.log"))
        let coordinator = RestoreRLMCoordinator(
            capture: capture,
            startupTimeout: 0.1,
            drainTimeout: 0.08,
            pollInterval: 0.005)
        let first = await coordinator.prepare(
            taskID: UUID(),
            canonicalECID: "0000000012345670")
        await coordinator.finish(taskID: first.taskID, outcome: .success)

        try await Task.sleep(nanoseconds: 15_000_000)
        let second = await coordinator.prepare(
            taskID: UUID(),
            canonicalECID: "0000000012345671")

        XCTAssertEqual(first.status, .startedOwnedSession)
        XCTAssertEqual(second.status, .recordingReused)
        XCTAssertEqual(capture.startCount, 1)
        XCTAssertEqual(capture.stopCount, 0)
        XCTAssertTrue(coordinator.windowWasPreempted(taskID: first.taskID))
        XCTAssertEqual(second.rawLogURL, first.rawLogURL)
    }
}

@MainActor
private final class FakeRestoreCapture: RestoreCaptureLifecycle {
    var state: CaptureState
    var currentRawLogURL: URL?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var lastStartECID: String?
    var startTransitionsToRecording = true

    init(state: CaptureState, rawURL: URL?) {
        self.state = state
        currentRawLogURL = rawURL
    }

    func start(preCaptureContext: String?, automatic: Bool) {
        startCount += 1
        lastStartECID = preCaptureContext?
            .split(separator: " ")
            .last
            .map(String.init)
        if startTransitionsToRecording {
            state = .recording
        }
    }

    func stop() {
        stopCount += 1
        state = .finalizing
    }
}

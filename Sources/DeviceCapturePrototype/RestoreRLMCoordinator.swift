import Foundation
import RestoreLogEngine

@MainActor
protocol RestoreCaptureLifecycle: AnyObject {
    var state: CaptureState { get }
    var currentRawLogURL: URL? { get }
    func start(preCaptureContext: String?, automatic: Bool)
    func stop()
}

extension CaptureModel: RestoreCaptureLifecycle {}

enum RestoreRLMLogStatus: String, Codable, Equatable, Sendable {
    case recordingReused = "RLM_RECORDING_REUSED"
    case startedOwnedSession = "RLM_STARTED_OWNED_SESSION"
    case notRequested = "RLM_NOT_REQUESTED"
    case unavailable = "RLM_UNAVAILABLE"
    case completedWithPartialEvidence = "RLM_PARTIAL"
}

struct RestoreRLMBinding: Equatable, Sendable {
    let taskID: UUID
    let canonicalECID: String
    let status: RestoreRLMLogStatus
    let rawLogURL: URL?
    let startAt: Date
    let endAt: Date?
    let reason: String?
    let ownership: RestoreRLMOwnership
    let ownsSessionLifecycle: Bool
    let finishedTimePoint: RestoreLifecycleTimePoint?
    let finalizedAt: RestoreLifecycleTimePoint?

    init(
        taskID: UUID,
        canonicalECID: String,
        status: RestoreRLMLogStatus,
        rawLogURL: URL?,
        startAt: Date,
        endAt: Date?,
        reason: String?,
        ownership: RestoreRLMOwnership = .unavailable,
        ownsSessionLifecycle: Bool = false,
        finishedTimePoint: RestoreLifecycleTimePoint? = nil,
        finalizedAt: RestoreLifecycleTimePoint? = nil
    ) {
        self.taskID = taskID
        self.canonicalECID = canonicalECID
        self.status = status
        self.rawLogURL = rawLogURL
        self.startAt = startAt
        self.endAt = endAt
        self.reason = reason
        self.ownership = ownership
        self.ownsSessionLifecycle = ownsSessionLifecycle
        self.finishedTimePoint = finishedTimePoint
        self.finalizedAt = finalizedAt
    }
}

/// Coordinates task time windows over the single App-owned CaptureModel.
///
/// It never constructs a log engine and never stops a session it did not start.
@MainActor
final class RestoreRLMCoordinator {
    private let capture: any RestoreCaptureLifecycle
    private let startupTimeout: TimeInterval
    private let drainTimeout: TimeInterval
    private let pollInterval: TimeInterval
    private var ownedSessionActive = false
    private var windows: [UUID: RestoreRLMBinding] = [:]
    private var drainTask: Task<Void, Never>?
    private var pendingDrainTaskID: UUID?
    private var preemptedTaskIDs: Set<UUID> = []
    private var finalizations: [UUID: RestoreRLMFinalization] = [:]

    init(
        capture: any RestoreCaptureLifecycle,
        startupTimeout: TimeInterval = 3,
        drainTimeout: TimeInterval = 15,
        pollInterval: TimeInterval = 0.1
    ) {
        self.capture = capture
        self.startupTimeout = max(0, startupTimeout)
        self.drainTimeout = max(0, drainTimeout)
        self.pollInterval = max(0.001, pollInterval)
    }

    func prepare(taskID: UUID, canonicalECID: String) async -> RestoreRLMBinding {
        await prepare(
            taskID: taskID,
            canonicalECID: canonicalECID,
            saveRequested: true)
    }

    func prepare(
        taskID: UUID,
        canonicalECID: String,
        saveRequested: Bool
    ) async -> RestoreRLMBinding {
        if let pendingDrainTaskID {
            drainTask?.cancel()
            drainTask = nil
            preemptedTaskIDs.insert(pendingDrainTaskID)
            self.pendingDrainTaskID = nil
        }

        let startAt = Date()
        guard saveRequested else {
            let ownership: RestoreRLMOwnership =
                capture.state == .recording
                ? .manualUserOwned
                : .notRequested
            let binding = RestoreRLMBinding(
                taskID: taskID,
                canonicalECID: canonicalECID,
                status: .notRequested,
                rawLogURL: capture.state == .recording
                    ? capture.currentRawLogURL
                    : nil,
                startAt: startAt,
                endAt: nil,
                reason: "Restore-owned raw persistence was not requested.",
                ownership: ownership,
                ownsSessionLifecycle: false)
            windows[taskID] = binding
            return binding
        }
        switch capture.state {
        case .recording:
            let ownership: RestoreRLMOwnership =
                ownedSessionActive ? .restoreOwned : .manualUserOwned
            let binding = RestoreRLMBinding(
                taskID: taskID,
                canonicalECID: canonicalECID,
                status: .recordingReused,
                rawLogURL: capture.currentRawLogURL,
                startAt: startAt,
                endAt: nil,
                reason: nil,
                ownership: ownership,
                ownsSessionLifecycle: false)
            windows[taskID] = binding
            return binding

        case .idle, .savedVerified, .savedPartial, .interrupted:
            capture.start(
                preCaptureContext: "Restore task \(taskID.uuidString), ECID \(canonicalECID)",
                automatic: true)
            let ready = await waitForRecording()
            guard ready else {
                let binding = RestoreRLMBinding(
                    taskID: taskID,
                    canonicalECID: canonicalECID,
                    status: .unavailable,
                    rawLogURL: nil,
                    startAt: startAt,
                    endAt: Date(),
                    reason: "RLM did not enter RECORDING within \(startupTimeout) seconds; cfgutil continues independently.",
                    ownership: .unavailable)
                windows[taskID] = binding
                return binding
            }
            ownedSessionActive = true
            let binding = RestoreRLMBinding(
                taskID: taskID,
                canonicalECID: canonicalECID,
                status: .startedOwnedSession,
                rawLogURL: capture.currentRawLogURL,
                startAt: startAt,
                endAt: nil,
                reason: nil,
                ownership: .restoreOwned,
                ownsSessionLifecycle: true)
            windows[taskID] = binding
            return binding

        case .starting, .stopping, .finalizing, .failed:
            let binding = RestoreRLMBinding(
                taskID: taskID,
                canonicalECID: canonicalECID,
                status: .unavailable,
                rawLogURL: nil,
                startAt: startAt,
                endAt: Date(),
                reason: "Previous RLM session is \(capture.state.rawValue); no second log stream is allowed.",
                ownership: .unavailable)
            windows[taskID] = binding
            return binding
        }
    }

    func finish(taskID: UUID, outcome: RestoreOutcome) async {
        guard let existing = windows[taskID] else { return }
        let finishedAt = Date()
        let finishedTimePoint = RestoreLifecycleClock.now()
        windows[taskID] = RestoreRLMBinding(
            taskID: existing.taskID,
            canonicalECID: existing.canonicalECID,
            status: existing.status,
            rawLogURL: existing.rawLogURL,
            startAt: existing.startAt,
            endAt: finishedAt,
            reason: outcome.rawValue,
            ownership: existing.ownership,
            ownsSessionLifecycle: existing.ownsSessionLifecycle,
            finishedTimePoint: finishedTimePoint,
            finalizedAt: nil)

        guard ownedSessionActive else { return }
        guard !windows.values.contains(where: { $0.endAt == nil }) else { return }
        scheduleOwnedDrain()
    }

    func finalization(
        taskID: UUID,
        timeout: TimeInterval
    ) async -> RestoreRLMFinalization? {
        if let finalization = finalizations[taskID] {
            return finalization
        }
        guard let binding = windows[taskID] else { return nil }
        switch binding.ownership {
        case .notRequested:
            let finalization = RestoreRLMFinalization(
                ownership: .notRequested,
                disposition: .notRequested,
                finalizedAt: nil,
                drainDurationSeconds: nil,
                rawLogURL: nil,
                reason: binding.reason)
            finalizations[taskID] = finalization
            return finalization
        case .manualUserOwned:
            let finalization = RestoreRLMFinalization(
                ownership: .manualUserOwned,
                disposition: .continuedInManualSession,
                finalizedAt: nil,
                drainDurationSeconds: nil,
                rawLogURL: binding.rawLogURL,
                reason: "The manual RLM session continues under user ownership.")
            finalizations[taskID] = finalization
            return finalization
        case .unavailable:
            let finalization = RestoreRLMFinalization(
                ownership: .unavailable,
                disposition: .unavailable,
                finalizedAt: nil,
                drainDurationSeconds: nil,
                rawLogURL: nil,
                reason: binding.reason)
            finalizations[taskID] = finalization
            return finalization
        case .restoreOwned:
            guard binding.ownsSessionLifecycle else {
                let finalization = RestoreRLMFinalization(
                    ownership: .restoreOwned,
                    disposition: .continuedInSharedRestoreSession,
                    finalizedAt: nil,
                    drainDurationSeconds: nil,
                    rawLogURL: binding.rawLogURL,
                    reason: "A different Restore task owns the active session lifecycle.")
                finalizations[taskID] = finalization
                return finalization
            }
            let deadline = RestoreLifecycleClock.now(
                systemUptime:
                    ProcessInfo.processInfo.systemUptime
                    + max(0, timeout))
            while !Self.isTerminal(capture.state),
                  ProcessInfo.processInfo.systemUptime
                    <= TimeInterval(
                        deadline.monotonicNanoseconds)
                        / 1_000_000_000 {
                try? await Task.sleep(
                    nanoseconds: UInt64(
                        max(0.001, pollInterval) * 1_000_000_000))
            }
            guard Self.isTerminal(capture.state) else {
                let finalization = RestoreRLMFinalization(
                    ownership: .restoreOwned,
                    disposition: .timedOut,
                    finalizedAt: nil,
                    drainDurationSeconds: nil,
                    rawLogURL: binding.rawLogURL,
                    reason: "Owned RLM session did not reach a terminal state before the observation timeout.")
                finalizations[taskID] = finalization
                return finalization
            }
            let finalizedAt = RestoreLifecycleClock.now()
            let finalization = RestoreRLMFinalization(
                ownership: .restoreOwned,
                disposition: .finalizedOwnedSession,
                finalizedAt: finalizedAt,
                drainDurationSeconds: RestoreLifecycleClock.seconds(
                    from: binding.finishedTimePoint,
                    to: finalizedAt),
                rawLogURL: binding.rawLogURL,
                reason: capture.state.rawValue)
            finalizations[taskID] = finalization
            return finalization
        }
    }

    func windowWasPreempted(taskID: UUID) -> Bool {
        preemptedTaskIDs.contains(taskID)
    }

    func binding(taskID: UUID) -> RestoreRLMBinding? {
        windows[taskID]
    }

    func shutdown() {
        drainTask?.cancel()
        drainTask = nil
        pendingDrainTaskID = nil
        finalizations.removeAll()
    }

    private func waitForRecording() async -> Bool {
        let deadline = Date().addingTimeInterval(startupTimeout)
        while Date() <= deadline {
            if capture.state == .recording { return true }
            if capture.state == .failed || capture.state == .stopping || capture.state == .finalizing {
                return false
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            try? await Task.sleep(
                nanoseconds: UInt64(min(pollInterval, remaining) * 1_000_000_000))
        }
        return capture.state == .recording
    }

    private func scheduleOwnedDrain() {
        drainTask?.cancel()
        let currentTaskID = windows.values
            .filter { $0.endAt != nil }
            .max(by: { ($0.endAt ?? .distantPast) < ($1.endAt ?? .distantPast) })?
            .taskID
        pendingDrainTaskID = currentTaskID
        let delay = drainTimeout
        drainTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.pendingDrainTaskID = nil
            self.drainTask = nil
            guard self.ownedSessionActive else { return }
            guard !self.windows.values.contains(where: { $0.endAt == nil }) else { return }
            guard self.capture.state == .recording else {
                self.ownedSessionActive = false
                return
            }
            self.capture.stop()
            self.ownedSessionActive = false
        }
    }

    private static func isTerminal(_ state: CaptureState) -> Bool {
        switch state {
        case .savedVerified, .savedPartial, .interrupted, .failed:
            return true
        case .idle, .starting, .recording, .stopping, .finalizing:
            return false
        }
    }
}

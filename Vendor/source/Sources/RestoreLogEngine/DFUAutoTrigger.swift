import Foundation

/// Decides *when* an automatic capture session should start.
///
/// It is a pure state machine: no IOKit, no capture, no session creation. The caller
/// feeds it USB observations and manual lifecycle facts, and acts on the decisions it
/// returns. That keeps the concurrency rules testable without hardware.
///
/// Hard rule encoded here: a removed device never stops a running capture, and a
/// manual stop suppresses auto-restart for the rest of that device episode. The device
/// sitting in DFU is not a new reason to start again.
public struct DFUAutoTrigger: Sendable {

    public enum State: String, Sendable {
        case idle
        case startPending
        case capturing
        case stopPending
        case suppressedUntilRearm
    }

    public enum Decision: Sendable, Equatable {
        case startCapture(trigger: String)
        case ignore(reason: String)
        case ambiguousDevices(count: Int)
    }

    public private(set) var state: State = .idle
    /// DFU candidates currently believed present, keyed by registry entry id.
    public private(set) var presentDFU: [UInt64: String?] = [:]  // id -> ECID if parsed
    /// Ids seen during the suppressed episode; a returning one is not a new episode.
    private var suppressedIDs: Set<UInt64> = []
    private var startedForCurrentEpisode = false

    public init() {}

    /// Feeds one observation. `ecid` is an *observation*, never an identity authority.
    public mutating func observeDFUCandidate(registryEntryID: UInt64, ecid: String?) -> Decision {
        presentDFU[registryEntryID] = ecid
        switch state {
        case .idle:
            guard presentDFU.count == 1 else {
                return .ambiguousDevices(count: presentDFU.count)
            }
            state = .startPending
            startedForCurrentEpisode = true
            return .startCapture(trigger: "first-dfu-candidate")
        case .startPending:
            return .ignore(reason: "start already pending")
        case .capturing:
            return .ignore(reason: "already capturing")
        case .stopPending:
            return .ignore(reason: "stop pending")
        case .suppressedUntilRearm:
            return .ignore(reason: "suppressed until rearm")
        }
    }

    /// A second DFU device with a different registry id is an ambiguity, not a reason
    /// to start a second host-wide session.
    public mutating func observeDFUCandidateWhileOthersPresent(registryEntryID: UInt64, ecid: String?) -> Decision {
        presentDFU[registryEntryID] = ecid
        // Before a session is committed, a second DFU device makes ownership ambiguous:
        // we must not start (or keep) a session that would implicitly claim device #1.
        if state == .idle || state == .startPending || state == .suppressedUntilRearm {
            if state == .startPending { state = .idle }
            return .ambiguousDevices(count: presentDFU.count)
        }
        return .ignore(reason: "extra device while \(state.rawValue)")
    }

    /// Removal never stops capture and never declares an outcome.
    public mutating func deviceRemoved(registryEntryID: UInt64) -> Decision {
        presentDFU.removeValue(forKey: registryEntryID)
        if state == .suppressedUntilRearm { suppressedIDs.insert(registryEntryID) }
        return .ignore(reason: "removal does not affect capture")
    }

    /// Called once the capture backend actually reported success.
    public mutating func captureDidStart() {
        if state == .startPending { state = .capturing }
    }

    /// Called when the backend refused to start. Returns to idle so a later, genuinely
    /// new episode may try again — but not silently, the caller reports the error.
    public mutating func captureFailedToStart() {
        if state == .startPending { state = .idle }
    }

    /// Owner pressed stop.
    public mutating func manualStopRequested() {
        if state == .capturing { state = .stopPending }
    }

    /// Finalization finished. Suppression begins here, not at the next USB event.
    public mutating func manualStopCompleted() {
        if state == .stopPending {
            state = .suppressedUntilRearm
            suppressedIDs.formUnion(presentDFU.keys)
            startedForCurrentEpisode = false
        }
    }

    /// Explicit, deliberate re-arm. Not reachable from a USB notification.
    public mutating func rearm() {
        state = .idle
        suppressedIDs.removeAll()
        presentDFU.removeAll()
        startedForCurrentEpisode = false
    }

    public var isSuppressed: Bool { state == .suppressedUntilRearm }
    public var didStartCurrentEpisode: Bool { startedForCurrentEpisode }
}

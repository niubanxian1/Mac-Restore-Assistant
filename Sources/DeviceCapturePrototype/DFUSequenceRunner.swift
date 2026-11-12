import Foundation
import MRAHelperProtocol

struct DFUSequenceTarget: Equatable, Sendable {
    let controller: String
    let portNumber: Int
    let rid: Int
}

struct DFUSequenceEvent: Sendable {
    let requestID: String
    let plannedAt: Date
    let dispatchedAt: Date
    let finishedAt: Date
    let response: HelperResponse
    /// True only if the send closure was actually invoked. A cancelled timer
    /// is not an attempt.
    let attempted: Bool

    var backendReceipt: BackendActionReceipt? {
        BackendActionReceipt.parse(stdout: response.stdout)
    }

    /// The Helper returned an exit code, which means the backend process was
    /// actually invoked. A Helper-unavailable/caller-rejected response has no
    /// exit code.
    var backendCalled: Bool { response.exitCode != nil }

    /// Backend JSON says the VDM boundary was crossed, or the Helper's legacy
    /// success receipt says the request was submitted.
    var backendConfirmedSubmit: Bool {
        (backendReceipt?.sendPerformed == true && backendReceipt?.status == "REQUEST_SUBMITTED")
            || (response.ok && response.dispatchTruth == "REQUEST_SENT")
    }
}

struct DFUSequenceResult: Sendable {
    let sequenceID: String
    let target: DFUSequenceTarget
    let startedAt: Date
    let plannedSecond: Date
    let first: DFUSequenceEvent
    let second: DFUSequenceEvent
}

/// Fixed legacy-compatible two-send sequence. The second send is scheduled
/// from the absolute 1.5 s deadline and is not gated on the first response.
struct DFUSequenceRunner {
    typealias Send = @Sendable (String, DFUSequenceTarget) async -> HelperResponse
    let send: Send
    let delaySeconds: TimeInterval

    init(delaySeconds: TimeInterval = 1.5,
         send: @escaping Send) {
        self.delaySeconds = delaySeconds
        self.send = send
    }

    func run(sequenceID: String, target: DFUSequenceTarget,
             startedAt: Date = Date()) async -> DFUSequenceResult {
        let plannedSecond = startedAt.addingTimeInterval(delaySeconds)
        let firstID = sequenceID + "-1"
        let secondID = sequenceID + "-2"
        let send = self.send
        let firstStart = Date()
        // Structured tasks so cancelling the parent (timeout / terminal state)
        // cancels a second send that has not been dispatched yet.
        async let first = Self.dispatch(requestID: firstID, target: target,
                                        plannedAt: startedAt, dispatchedAt: firstStart,
                                        send: send)
        async let second = Self.plannedSecond(requestID: secondID, target: target,
                                              plannedAt: plannedSecond, send: send)
        return DFUSequenceResult(sequenceID: sequenceID, target: target,
                                 startedAt: startedAt, plannedSecond: plannedSecond,
                                 first: await first, second: await second)
    }

    private static func dispatch(requestID: String, target: DFUSequenceTarget,
                                 plannedAt: Date, dispatchedAt: Date,
                                 send: Send) async -> DFUSequenceEvent {
        let response = await send(requestID, target)
        return DFUSequenceEvent(requestID: requestID, plannedAt: plannedAt,
                                dispatchedAt: dispatchedAt, finishedAt: Date(),
                                response: response, attempted: true)
    }

    private static func plannedSecond(requestID: String, target: DFUSequenceTarget,
                                      plannedAt: Date, send: Send) async -> DFUSequenceEvent {
        let wait = plannedAt.timeIntervalSinceNow
        if wait > 0 {
            do {
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            } catch {
                return cancelledEvent(requestID: requestID, plannedAt: plannedAt)
            }
        }
        if Task.isCancelled {
            return cancelledEvent(requestID: requestID, plannedAt: plannedAt)
        }
        let dispatched = Date()
        return await dispatch(requestID: requestID, target: target,
                              plannedAt: plannedAt, dispatchedAt: dispatched, send: send)
    }

    private static func cancelledEvent(requestID: String, plannedAt: Date) -> DFUSequenceEvent {
        let now = Date()
        return DFUSequenceEvent(
            requestID: requestID, plannedAt: plannedAt,
            dispatchedAt: now, finishedAt: now,
            response: HelperResponse(requestID: requestID, ok: false,
                                     dispatchTruth: "NOT_DISPATCHED",
                                     exitCode: nil, reason: "SEND_CANCELLED"),
            attempted: false)
    }
}

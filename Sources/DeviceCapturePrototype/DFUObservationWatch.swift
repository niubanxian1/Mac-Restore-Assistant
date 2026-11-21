import Foundation

enum DFUObservationMode: String, Equatable {
    case absent
    case connected
    case recovery
    case dfu
    case unknown
}

enum DFUConfirmationResult: String, Equatable {
    case requestSent = "REQUEST_SENT"
    case observed = "DFU_OBSERVED"
    case confirmed = "DFU_CONFIRMED"
    case unknown = "OUTCOME_UNKNOWN"
}

enum DFUConfirmationScope: String, Equatable {
    case none = "NONE"
    case portTransition = "PORT_TRANSITION"
    case sameDevice = "SAME_DEVICE"
}

struct DFUObservationBatch: Equatable {
    let batchID: UInt64
    let readStartedAt: TimeInterval
    let readCompletedAt: TimeInterval
    let isValid: Bool
    let portKey: String?
    let mode: DFUObservationMode
    let ecid: String?
    let registryID: String?
}

private struct DFUDispatchRecord: Equatable {
    let requestID: String
    let dispatchedAt: TimeInterval
    let confirmedSubmit: Bool
    let responseAt: TimeInterval?
}

struct DFUEvaluation: Equatable {
    let result: DFUConfirmationResult
    let scope: DFUConfirmationScope
    let reason: String
    let evidencePort: String?
    let evidenceTime: TimeInterval?
    let baselineAge: TimeInterval?
    let currentTargetState: DFUObservationMode

    static func unknown(
        _ reason: String,
        currentTargetState: DFUObservationMode = .unknown
    ) -> DFUEvaluation {
        DFUEvaluation(
            result: .unknown,
            scope: .none,
            reason: reason,
            evidencePort: nil,
            evidenceTime: nil,
            baselineAge: nil,
            currentTargetState: currentTargetState)
    }
}

struct DFUObservationWatch {
    var operationID: UUID
    let targetPortKey: String
    let clickedAt: TimeInterval
    let windowSeconds: TimeInterval
    let maxBaselineAgeSeconds: TimeInterval
    let maxBufferedBatches: Int
    private(set) var baseline: DFUObservationBatch?
    private(set) var evaluation: DFUEvaluation
    private var dispatches: [DFUDispatchRecord] = []
    private var samples: [DFUObservationBatch] = []
    private var terminalAt: TimeInterval?
    private var confirmed: DFUEvaluation?
    private var projectionPublished = false
    private(set) var droppedBatchCount = 0

    init(
        operationID: UUID,
        targetPortKey: String,
        clickedAt: TimeInterval,
        baseline: DFUObservationBatch?,
        windowSeconds: TimeInterval = 15,
        maxBaselineAgeSeconds: TimeInterval = 5,
        maxBufferedBatches: Int = 30
    ) {
        self.operationID = operationID
        self.targetPortKey = targetPortKey
        self.clickedAt = clickedAt
        self.baseline = baseline
        self.windowSeconds = windowSeconds
        self.maxBaselineAgeSeconds = maxBaselineAgeSeconds
        self.maxBufferedBatches = max(1, maxBufferedBatches)
        self.evaluation = .unknown("no command dispatch recorded")
    }

    mutating func noteDispatch(
        requestID: String,
        dispatchedAt: TimeInterval,
        confirmedSubmit: Bool,
        responseAt: TimeInterval? = nil
    ) -> DFUEvaluation {
        if let index = dispatches.firstIndex(where: { $0.requestID == requestID }) {
            let previous = dispatches[index]
            dispatches[index] = DFUDispatchRecord(
                requestID: requestID,
                dispatchedAt: min(previous.dispatchedAt, dispatchedAt),
                confirmedSubmit: previous.confirmedSubmit || confirmedSubmit,
                responseAt: responseAt ?? previous.responseAt)
        } else {
            dispatches.append(DFUDispatchRecord(
                requestID: requestID,
                dispatchedAt: dispatchedAt,
                confirmedSubmit: confirmedSubmit,
                responseAt: responseAt))
        }
        return evaluate(final: false)
    }

    mutating func observe(_ batch: DFUObservationBatch) -> DFUEvaluation {
        guard batch.readStartedAt >= clickedAt else {
            return evaluate(final: false)
        }
        samples.append(batch)
        if samples.count > maxBufferedBatches {
            let overflow = samples.count - maxBufferedBatches
            samples.removeFirst(overflow)
            droppedBatchCount += overflow
        }
        if batch.portKey == targetPortKey {
            currentTargetState = batch.isValid ? batch.mode : .unknown
        }
        return evaluate(final: false)
    }

    mutating func noteActionTerminal(at: TimeInterval) -> DFUEvaluation {
        terminalAt = terminalAt.map { min($0, at) } ?? at
        return evaluate(final: true)
    }

    mutating func expireIfNeeded(at: TimeInterval) -> DFUEvaluation {
        guard confirmed == nil else {
            return evaluationWithCurrentState(confirmed!)
        }
        guard let floor = dispatchFloor else {
            return evaluate(final: false)
        }
        let deadline = min(floor + windowSeconds, terminalAt ?? .greatestFiniteMagnitude)
        if at >= deadline {
            terminalAt = terminalAt.map { min($0, deadline) } ?? deadline
            return evaluate(final: true)
        }
        return evaluate(final: false)
    }

    mutating func finalize(at: TimeInterval? = nil) -> DFUEvaluation {
        if let at {
            terminalAt = terminalAt.map { min($0, at) } ?? at
        }
        return evaluate(final: true)
    }

    private var currentTargetState: DFUObservationMode {
        get { evaluation.currentTargetState }
        set {
            evaluation = DFUEvaluation(
                result: evaluation.result,
                scope: evaluation.scope,
                reason: evaluation.reason,
                evidencePort: evaluation.evidencePort,
                evidenceTime: evaluation.evidenceTime,
                baselineAge: evaluation.baselineAge,
                currentTargetState: newValue)
        }
    }

    private var dispatchFloor: TimeInterval? {
        dispatches.map(\.dispatchedAt).min()
    }

    private var hasConfirmedSubmit: Bool {
        dispatches.contains { $0.confirmedSubmit }
    }

    private func baselineIsValidAndFresh(
        dispatchFloor: TimeInterval
    ) -> (valid: Bool, age: TimeInterval?) {
        guard let baseline = self.baseline, baseline.isValid else {
            return (false, nil)
        }
        let age = dispatchFloor - baseline.readCompletedAt
        guard baseline.portKey == targetPortKey,
              baseline.mode != .dfu,
              baseline.readCompletedAt <= dispatchFloor else {
            return (false, age)
        }
        return (age >= 0 && age <= maxBaselineAgeSeconds, age)
    }

    private func postDispatchSamples(dispatchFloor: TimeInterval) -> [DFUObservationBatch] {
        let windowEnd = min(
            dispatchFloor + windowSeconds,
            terminalAt ?? .greatestFiniteMagnitude)
        return samples.filter {
            $0.isValid
                && $0.portKey == targetPortKey
                && $0.readStartedAt >= dispatchFloor
                && $0.readCompletedAt <= windowEnd
        }
    }

    private func allPostDispatchSamples(dispatchFloor: TimeInterval) -> [DFUObservationBatch] {
        let windowEnd = min(
            dispatchFloor + windowSeconds,
            terminalAt ?? .greatestFiniteMagnitude)
        return samples.filter {
            $0.isValid
                && $0.readStartedAt >= dispatchFloor
                && $0.readCompletedAt <= windowEnd
        }
    }

    private mutating func evaluate(final: Bool) -> DFUEvaluation {
        if let confirmed {
            return evaluationWithCurrentState(confirmed)
        }
        guard let floor = dispatchFloor else {
            let result = DFUEvaluation.unknown(
                "no command dispatch recorded",
                currentTargetState: evaluation.currentTargetState)
            evaluation = result
            return result
        }

        let post = postDispatchSamples(dispatchFloor: floor)
        let dfuSamples = post.filter { $0.mode == .dfu }
        let allPost = allPostDispatchSamples(dispatchFloor: floor)
        let freshness = baselineIsValidAndFresh(dispatchFloor: floor)

        if let baseline,
           baseline.isValid,
           baseline.portKey == targetPortKey,
           baseline.mode == .dfu {
            let result = DFUEvaluation(
                result: .observed,
                scope: .none,
                reason: "target port was already DFU before dispatch",
                evidencePort: targetPortKey,
                evidenceTime: baseline.readCompletedAt,
                baselineAge: freshness.age,
                currentTargetState: evaluation.currentTargetState)
            evaluation = result
            return result
        }

        let conflicts = post.filter { sample in
            guard let baselineECID = baseline?.ecid,
                  let sampleECID = sample.ecid else {
                return false
            }
            return normalizedECID(baselineECID) != normalizedECID(sampleECID)
        }
        if let conflict = conflicts.first {
            let result = DFUEvaluation(
                result: .observed,
                scope: .none,
                reason: "same port showed a conflicting ECID before/after dispatch",
                evidencePort: targetPortKey,
                evidenceTime: conflict.readCompletedAt,
                baselineAge: freshness.age,
                currentTargetState: evaluation.currentTargetState)
            evaluation = result
            return result
        }

        let distinctDFUECIDs = Set(
            dfuSamples.compactMap(\.ecid).map(normalizedECID))
        if distinctDFUECIDs.count > 1 {
            let result = DFUEvaluation(
                result: .observed,
                scope: .none,
                reason: "multiple DFU identities appeared on the frozen port",
                evidencePort: targetPortKey,
                evidenceTime: dfuSamples.last?.readCompletedAt,
                baselineAge: freshness.age,
                currentTargetState: evaluation.currentTargetState)
            evaluation = result
            return result
        }

        if hasConfirmedSubmit && freshness.valid {
            for sample in dfuSamples {
                guard sample.readCompletedAt <= terminalAt ?? .greatestFiniteMagnitude else {
                    continue
                }
                let scope: DFUConfirmationScope
                let reason: String
                if let baselineECID = baseline?.ecid,
                   let sampleECID = sample.ecid {
                    guard normalizedECID(baselineECID) == normalizedECID(sampleECID) else {
                        continue
                    }
                    scope = .sameDevice
                    reason = "post-dispatch DFU on frozen port with matching ECID"
                } else {
                    scope = .portTransition
                    reason = "post-dispatch DFU transition on frozen port; device identity not proven"
                }
                let candidate = DFUEvaluation(
                    result: .confirmed,
                    scope: scope,
                    reason: reason,
                    evidencePort: targetPortKey,
                    evidenceTime: sample.readCompletedAt,
                    baselineAge: freshness.age,
                    currentTargetState: evaluation.currentTargetState)
                let settled = final || samples.contains {
                    $0.isValid && $0.readCompletedAt > sample.readCompletedAt
                }
                if settled {
                    confirmed = candidate
                    evaluation = candidate
                    publishConfirmationProjection(candidate)
                    return candidate
                }
                let result = DFUEvaluation(
                    result: .observed,
                    scope: .none,
                    reason: "qualified DFU transition pending one settled observation frame",
                    evidencePort: targetPortKey,
                    evidenceTime: sample.readCompletedAt,
                    baselineAge: freshness.age,
                    currentTargetState: evaluation.currentTargetState)
                evaluation = result
                return result
            }
        }

        if let current = dfuSamples.last {
            let reason: String
            if !hasConfirmedSubmit {
                reason = "DFU observed before a confirmed command receipt"
            } else if baseline == nil {
                reason = "baseline unavailable"
            } else if baseline?.isValid == false {
                reason = "baseline read was invalid"
            } else if baseline?.portKey != targetPortKey {
                reason = "baseline was not from the frozen physical port"
            } else if baseline?.mode == .dfu {
                reason = "target port was already DFU before dispatch"
            } else if let baseline, baseline.readCompletedAt > floor {
                reason = "baseline did not complete before dispatch"
            } else if let age = freshness.age, age > maxBaselineAgeSeconds {
                reason = "baseline is stale for this operation"
            } else if current.readCompletedAt > floor + windowSeconds {
                reason = "DFU arrived outside the observation window"
            } else {
                reason = "DFU observed without a qualified transition"
            }
            let result = DFUEvaluation(
                result: .observed,
                scope: .none,
                reason: reason,
                evidencePort: targetPortKey,
                evidenceTime: current.readCompletedAt,
                baselineAge: freshness.age,
                currentTargetState: evaluation.currentTargetState)
            evaluation = result
            return result
        }

        if !hasConfirmedSubmit {
            let result = DFUEvaluation.unknown(
                "no confirmed command receipt",
                currentTargetState: evaluation.currentTargetState)
            evaluation = result
            return result
        }

        if final {
            if allPost.contains(where: { $0.portKey == nil && $0.mode == .dfu }) {
                let result = DFUEvaluation.unknown(
                    "DFU appeared but could not be assigned to exactly one physical port",
                    currentTargetState: evaluation.currentTargetState)
                evaluation = result
                return result
            }
            if allPost.contains(where: {
                $0.portKey != nil && $0.portKey != targetPortKey && $0.mode == .dfu
            }) {
                let result = DFUEvaluation.unknown(
                    "DFU appears only on another physical port",
                    currentTargetState: evaluation.currentTargetState)
                evaluation = result
                return result
            }
            let result = DFUEvaluation.unknown(
                "observation window ended without qualified DFU evidence",
                currentTargetState: evaluation.currentTargetState)
            evaluation = result
            return result
        }

        let result = DFUEvaluation(
            result: .requestSent,
            scope: .none,
            reason: "observation window in progress",
            evidencePort: targetPortKey,
            evidenceTime: nil,
            baselineAge: freshness.age,
            currentTargetState: evaluation.currentTargetState)
        evaluation = result
        return result
    }

    private func evaluationWithCurrentState(
        _ historical: DFUEvaluation
    ) -> DFUEvaluation {
        DFUEvaluation(
            result: historical.result,
            scope: historical.scope,
            reason: historical.reason,
            evidencePort: historical.evidencePort,
            evidenceTime: historical.evidenceTime,
            baselineAge: historical.baselineAge,
            currentTargetState: evaluation.currentTargetState)
    }

    private func normalizedECID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private mutating func publishConfirmationProjection(
        _ evaluation: DFUEvaluation
    ) {
        guard !projectionPublished else { return }
        projectionPublished = true
        let projection = DFUConfirmationProjection(
            operationID: operationID,
            targetPortKey: targetPortKey,
            scope: evaluation.scope,
            reason: evaluation.reason,
            evidenceTime: evaluation.evidenceTime,
            publishedAt: Date())
        NotificationCenter.default.post(
            name: .mraDFUConfirmationProjected,
            object: projection)
    }
}

struct DFUObservationRouter {
    private var activeOperationID: UUID?
    private var activeWatch: DFUObservationWatch?

    mutating func begin(_ watch: DFUObservationWatch) {
        activeOperationID = watch.operationID
        activeWatch = watch
    }

    mutating func observe(
        operationID: UUID,
        batch: DFUObservationBatch
    ) -> DFUEvaluation? {
        guard operationID == activeOperationID else { return nil }
        return activeWatch?.observe(batch)
    }

    mutating func finalize(
        operationID: UUID,
        at: TimeInterval
    ) -> DFUEvaluation? {
        guard operationID == activeOperationID else { return nil }
        return activeWatch?.finalize(at: at)
    }
}

import Foundation

enum RestoreOutcome: String, Codable, Equatable, Sendable {
    case success = "SUCCESS"
    case failure = "FAILURE"
    case canceled = "CANCELED"
    case unknown = "UNKNOWN"
}

struct RestoreOutputSnapshot: Equatable, Sendable {
    var stepText = ""
    var stageFraction: Double?
    var overallFraction: Double? = nil
    var sentinelComplete = false
    var stepCompleted = false
    var restoreActivityObserved = false
    var sawRestoredSystemForTarget = false
    var sawSuccessSummary = false
    var sawFailure = false
    var sawIndependentFailure = false
    var sawCancellationInterruptionFailure = false
    var terminalSummarySeen = false
    var lastOutputAt: Date?
    var firstRestoreActivityTime: RestoreLifecycleTimePoint?
    var firstFailureObservedTime: RestoreLifecycleTimePoint?
    var processLaunched: RestoreLifecycleTimePoint?
    var failureText = ""
    var outputTail: [String] = []
    var outputSequence: UInt64 = 0
}

/// Incremental parser for cfgutil's text/plist-like restore stream.
/// Raw bytes remain the caller's responsibility; this type only classifies.
final class RestoreOutputParser: @unchecked Sendable {
    private static let maxRetainedOutputLines = 240
    private static let maxRetainedCharactersPerLine = 8_192

    private let targetECID: UInt64
    private let timeProvider: @Sendable () -> RestoreLifecycleTimePoint
    private let lock = NSLock()
    private var pending = Data()
    private var pendingFields: [String: String] = [:]
    private var state = RestoreOutputSnapshot()

    init(
        targetECID: UInt64,
        timeProvider: @escaping @Sendable () -> RestoreLifecycleTimePoint = {
            RestoreLifecycleClock.now()
        }
    ) {
        self.targetECID = targetECID
        self.timeProvider = timeProvider
    }

    var snapshot: RestoreOutputSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    @discardableResult
    func feed(_ data: Data) -> RestoreOutputSnapshot {
        lock.lock()
        defer { lock.unlock() }
        pending.append(data)
        while let boundary = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let line = pending[..<boundary]
            pending = pending[pending.index(after: boundary)...]
            if !line.isEmpty {
                consumeLine(
                    String(decoding: line, as: UTF8.self),
                    retainOutput: true)
            }
        }
        if !pending.isEmpty {
            consumeLine(
                String(decoding: pending, as: UTF8.self),
                retainOutput: false)
        }
        if pending.count > 1_048_576 {
            let line = pending
            pending.removeAll(keepingCapacity: true)
            consumeLine(
                String(decoding: line, as: UTF8.self),
                retainOutput: true)
        }
        return state
    }

    @discardableResult
    func flush() -> RestoreOutputSnapshot {
        lock.lock()
        defer { lock.unlock() }
        if !pending.isEmpty {
            consumeLine(
                String(decoding: pending, as: UTF8.self),
                retainOutput: true)
            pending.removeAll(keepingCapacity: true)
        }
        return state
    }

    func outcome(
        exitCode: Int32?,
        userCancelled: Bool,
        tailComplete: Bool
    ) -> RestoreOutcome {
        let cancellationTime = userCancelled ? timeProvider() : nil
        return outcome(context: RestoreOutcomeContext(
            exitCode: exitCode,
            userCancelled: userCancelled,
            processLaunched: exitCode != nil,
            cancelRequestedAt: cancellationTime,
            tailComplete: tailComplete,
            terminationReason: userCancelled ? .uncaughtSignal : .exit,
            sentSignals: cancellationTime.map {
                [RestoreSentSignal(kind: .interrupt, time: $0)]
            } ?? []))
    }

    func outcome(context: RestoreOutcomeContext) -> RestoreOutcome {
        lock.lock()
        defer { lock.unlock() }
        if context.exitCode == 0,
           context.tailComplete,
           state.sawRestoredSystemForTarget,
           state.sawSuccessSummary,
           !state.sawFailure {
            return .success
        }
        guard context.tailComplete else { return .unknown }
        guard context.processLaunched else {
            return context.userCancelled ? .canceled : .unknown
        }
        if state.sawIndependentFailure {
            return .failure
        }
        let hasTerminationEvidence =
            !context.sentSignals.isEmpty
            || context.terminationReason == .uncaughtSignal
        if state.sawFailure {
            guard let cancelRequestedAt = context.cancelRequestedAt,
                  let firstFailure = state.firstFailureObservedTime else {
                return .failure
            }
            if firstFailure.monotonicNanoseconds
                < cancelRequestedAt.monotonicNanoseconds {
                return .failure
            }
            if state.sawCancellationInterruptionFailure,
               hasTerminationEvidence {
                return .canceled
            }
            return .unknown
        }
        if context.userCancelled,
           context.cancelRequestedAt != nil,
           hasTerminationEvidence {
            return .canceled
        }
        if let exitCode = context.exitCode, exitCode != 0 {
            return .failure
        }
        return .unknown
    }

    private func consumeLine(
        _ rawLine: String,
        retainOutput: Bool
    ) {
        let observedAt = timeProvider()
        state.lastOutputAt = observedAt.wallTime
        let decoded = Self.decodeUnicodeEscapes(rawLine)
        let segments = decoded
            .replacingOccurrences(of: "}{", with: "}\n{")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for line in segments {
            classifyLine(line, observedAt: observedAt)
            if retainOutput {
                let boundedLine = String(
                    line.prefix(Self.maxRetainedCharactersPerLine))
                state.outputTail.append(boundedLine)
                state.outputSequence &+= 1
                if state.outputTail.count > Self.maxRetainedOutputLines {
                    state.outputTail.removeFirst(
                        state.outputTail.count
                            - Self.maxRetainedOutputLines)
                }
            }
        }
    }

    private func classifyLine(
        _ line: String,
        observedAt: RestoreLifecycleTimePoint
    ) {
        let lower = line.lowercased()
        if let human = Self.humanStep(from: line) {
            state.stepText = human.name
            state.stageFraction = Double(human.percent) / 100
            state.sentinelComplete = false
            state.stepCompleted = false
            state.restoreActivityObserved = true
            if state.firstRestoreActivityTime == nil {
                state.firstRestoreActivityTime = observedAt
            }
        }
        let type = Self.field("Type", in: line)?.uppercased()

        for field in ["Step", "Progress"] {
            if let value = Self.field(field, in: line) {
                pendingFields[field] = value
            }
        }
        if let type {
            processRecord(
                type: type,
                fields: pendingFields,
                observedAt: observedAt)
            pendingFields.removeAll(keepingCapacity: true)
        }

        if lower.contains("restored system on"),
           ECIDIdentity.values(in: line).contains(targetECID) {
            state.sawRestoredSystemForTarget = true
        }

        if lower.contains(#"operation "restore" succeeded"#)
            || lower.contains("operation restore succeeded") {
            state.sawSuccessSummary = true
            state.terminalSummarySeen = true
        }

        let failure =
            lower.contains(#""restore" failed on"#)
            || lower.contains("operation restore failed")
            || lower.contains("cfgutil: error:")
            || lower.contains("amrestoreerrordomain")
            || lower.contains("ramroderrordomain")
        if failure {
            state.sawFailure = true
            state.terminalSummarySeen = true
            if state.firstFailureObservedTime == nil {
                state.firstFailureObservedTime = observedAt
            }
            if !state.failureText.contains(line) {
                state.failureText += (state.failureText.isEmpty ? "" : "\n") + line
            }
        } else if state.sawFailure,
                  lower.contains("domain:")
                    || lower.contains("error code")
                    || lower.contains("code:") {
            if !state.failureText.contains(line) {
                state.failureText += (state.failureText.isEmpty ? "" : "\n") + line
            }
        }
        updateFailureClassification()
    }

    private func processRecord(
        type: String,
        fields: [String: String],
        observedAt: RestoreLifecycleTimePoint
    ) {
        guard ["STEP", "PROGRESS", "STEPCOMPLETE"].contains(type) else {
            return
        }
        state.restoreActivityObserved = true
        if state.firstRestoreActivityTime == nil {
            state.firstRestoreActivityTime = observedAt
        }

        if type == "STEP" {
            state.stepText = fields["Step"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""
            state.stageFraction = nil
            state.sentinelComplete = false
            state.stepCompleted = false
        } else if let step = fields["Step"], !step.isEmpty,
                  state.stepText != step {
            state.stepText = step
            state.stageFraction = nil
            state.sentinelComplete = false
            state.stepCompleted = false
        }

        if type == "PROGRESS",
           let raw = fields["Progress"],
           let value = Double(raw) {
            if value == -1 {
                state.sentinelComplete = true
                state.stageFraction = nil
            } else if (0...1).contains(value) {
                state.stageFraction = value
                state.sentinelComplete = false
            }
        }

        if type == "STEPCOMPLETE" {
            state.stageFraction = nil
            state.stepCompleted = true
        }
    }

    private func updateFailureClassification() {
        let lower = state.failureText.lowercased()
        let cancellationInterruption =
            lower.contains("restoreos device removed before restored completed")
            && lower.contains("mobilerestore")
            && (lower.contains("code: 9") || lower.contains("code 9"))
        let explicitIndependentDomain =
            lower.contains("ramroderrordomain")
            || lower.contains("amrestoreerrordomain")
            || lower.contains(#""restore" failed on"#)
            || lower.contains("operation restore failed")
        state.sawCancellationInterruptionFailure = cancellationInterruption
        state.sawIndependentFailure =
            explicitIndependentDomain
            || (lower.contains("cfgutil: error:") && !cancellationInterruption)
    }

    private static func humanStep(from line: String) -> (name: String, percent: Int)? {
        let patterns: [String] = [
            #"^\s*第\s*(\d+)\s*/\s*(\d+)\s*步\s*[：:]\s*(.+?)\s*(\d{1,3})\s*%\s*$"#,
            #"^\s*Step\s+(\d+)\s+of\s+(\d+)\s*[:：]\s*(.+?)\s*(\d{1,3})\s*%\s*$"#,
            #"^\s*(正在等待设备|Waiting for device)\s*\[\s*\d+\s*/\s*\d+\s*\]\s*(\d{1,3})\s*%\s*$"#
        ]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]) else { continue }
            let ns = line as NSString
            guard let match = regex.firstMatch(
                in: line,
                range: NSRange(location: 0, length: ns.length)) else { continue }
            let nameRange = match.range(at: index == 2 ? 1 : 3)
            let percentRange = match.range(at: index == 2 ? 2 : 4)
            guard nameRange.location != NSNotFound,
                  percentRange.location != NSNotFound,
                  let swiftName = Range(nameRange, in: line),
                  let swiftPercent = Range(percentRange, in: line),
                  let percent = Int(line[swiftPercent]),
                  (0...100).contains(percent) else { continue }
            var name = String(line[swiftName]).trimmingCharacters(in: .whitespaces)
            name = name.replacingOccurrences(
                of: #"\s*\[\s*\d+\s*/\s*\d+\s*\]\s*$"#,
                with: "",
                options: .regularExpression)
            name = name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            return (name, percent)
        }
        return nil
    }

    private static func field(_ name: String, in line: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "\\b\(escaped)\\s*=\\s*(?:\"([^\"]*)\"|([^;\\r\\n}]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(
            in: line,
            range: NSRange(location: 0, length: ns.length)) else { return nil }
        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            if range.location != NSNotFound, let swiftRange = Range(range, in: line) {
                return line[swiftRange].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func decodeUnicodeEscapes(_ text: String) -> String {
        let pattern = #"\\U([0-9A-Fa-f]{4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        var output = ""
        var cursor = 0
        for match in matches {
            output += ns.substring(with: NSRange(
                location: cursor,
                length: match.range.location - cursor))
            let token = ns.substring(with: match.range(at: 1))
            if let scalar = UInt32(token, radix: 16),
               let unicode = UnicodeScalar(scalar) {
                output.unicodeScalars.append(unicode)
            } else {
                output += ns.substring(with: match.range)
            }
            cursor = match.range.location + match.range.length
        }
        output += ns.substring(from: cursor)
        return output
    }
}

import Foundation

enum USBConnectionTimelineMode: String, Equatable {
    case dfu
    case recovery
    case connected
    case hub
    case usb
    case unknown

    var displayText: String {
        switch self {
        case .dfu: return "DFU"
        case .recovery: return "Recovery"
        case .connected: return "Mac"
        case .hub: return "Hub"
        case .usb: return "USB"
        case .unknown: return "未知模式"
        }
    }
}

enum USBConnectionTimelineDirection: Equatable {
    case initialPresent
    case arrived
    case removed
}

enum USBConnectionTimelineIdentityRelation: Equatable {
    case sameMachine
    case changedMachine
    case unknown
}

enum USBConnectionTimelineModeTransition: Equatable {
    case sameMode
    case changedMode
    case unknown
}

enum USBTimelineLocationNormalizer {
    static func normalize(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let number = value as? NSNumber {
            return String(format: "%08X", number.uint64Value)
        }
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("0x") {
            return parseHex(String(trimmed.dropFirst(2)))
        }
        if trimmed.count == 8,
           (trimmed.hasPrefix("0")
                || trimmed.rangeOfCharacter(
                    from: CharacterSet(charactersIn: "abcdefABCDEF")) != nil) {
            return parseHex(trimmed)
        }
        if trimmed.allSatisfy(\.isNumber),
           let decimal = UInt64(trimmed) {
            return String(format: "%08X", decimal)
        }
        return nil
    }

    static func normalize(_ value: String?) -> String? {
        normalize(value as Any?)
    }

    private static func parseHex(_ raw: String) -> String? {
        guard !raw.isEmpty,
              let number = UInt64(raw, radix: 16) else { return nil }
        return String(format: "%08X", number)
    }
}

enum USBConnectionTimelineOrigin: Equatable {
    case sessionStart
    case clearedAt(TimeInterval)
}

enum USBConnectionTimelineIncompleteReason: String, Hashable {
    case registrationPending
    case arrivedRegistrationFailed
    case terminatedRegistrationFailed
    case initialDrainFailed
    case unknownRegistryID
    case unmatchedRemoval
    case historyOverflow
    case reappearanceOverflow
    case activeInstanceOverflow
    case multipleActiveInstances
    case portCapacityExceeded
    case outOfOrderEvent
    case sessionEnded
}

enum USBConnectionObservationCoverage: Equatable {
    case registering
    case complete
    case incomplete(USBConnectionTimelineIncompleteReason)
}

struct USBPortTimelineAssignment: Equatable, Hashable {
    let portKey: String?
    let portLabel: String?
    let evidence: String
    let isConfirmed: Bool

    static func unowned(location: String?) -> USBPortTimelineAssignment {
        USBPortTimelineAssignment(
            portKey: nil,
            portLabel: nil,
            evidence: location == nil
                ? "没有 USB location"
                : "USB location 未获可信端口归属",
            isConfirmed: false)
    }
}

struct USBConnectionTimelineObservation: Equatable {
    let sessionID: UUID
    let sequence: UInt64
    let batchID: UUID
    let observedAtUTC: Date
    let monotonicSeconds: TimeInterval
    let direction: USBConnectionTimelineDirection
    let registryEntryID: UInt64?
    let locationID: String?
    let mode: USBConnectionTimelineMode
    let vendorID: Int?
    let productID: Int?
    let ecid: String?
    let productName: String?
    let deviceClass: Int?
    let assignment: USBPortTimelineAssignment
    let retainedAttributes: Bool
}

struct PanoramaUSBDeviceObservation: Equatable {
    let sessionID: UUID
    let sequence: UInt64
    let batchID: UUID
    let observedAtUTC: Date
    let monotonicSeconds: TimeInterval
    let direction: USBConnectionTimelineDirection
    let registryEntryID: UInt64?
    let locationID: String?
    let mode: USBConnectionTimelineMode
    let vendorID: Int?
    let productID: Int?
    let ecid: String?
    let productName: String?
    let deviceClass: Int?
    let retainedAttributes: Bool
}

struct PanoramaUSBWatchUpdate: Equatable {
    let observations: [PanoramaUSBDeviceObservation]
    let coverage: USBConnectionObservationCoverage
    let droppedInBatch: Int
}

struct USBConnectionTimelineEvent: Identifiable, Equatable {
    let id: String
    let sequence: UInt64
    let batchID: UUID
    let observedAtUTC: Date
    let monotonicSeconds: TimeInterval
    let direction: USBConnectionTimelineDirection
    let registryEntryID: UInt64?
    let locationID: String?
    let mode: USBConnectionTimelineMode
    let vendorID: Int?
    let productID: Int?
    let ecid: String?
    let productName: String?
    let deviceClass: Int?
    let assignment: USBPortTimelineAssignment
    let retainedAttributes: Bool
    let modeTransition: USBConnectionTimelineModeTransition?
}

struct USBConnectionTimelineCurrentPresence: Equatable {
    let registryEntryID: UInt64?
    let locationID: String?
    let mode: USBConnectionTimelineMode
    let vendorID: Int?
    let productID: Int?
    let ecid: String?
    let productName: String?
    let startKind: USBConnectionTimelineOrigin
    let sinceMonotonicSeconds: TimeInterval?
    let observedAtLeastSeconds: TimeInterval
}

struct USBConnectionTimelineSnapshot: Equatable {
    let portKey: String
    let portLabel: String?
    let currentPresence: USBConnectionTimelineCurrentPresence?
    let currentResidenceSeconds: TimeInterval?
    let observedAtLeastSeconds: TimeInterval?
    let lastResidenceSeconds: TimeInterval?
    let lastReappearanceGapSeconds: TimeInterval?
    let lastReconnectionIdentity: USBConnectionTimelineIdentityRelation?
    let portReappearancesIn60Seconds: Int
    let sameMachineReenumerationsIn60Seconds: Int?
    let recentEvents: [USBConnectionTimelineEvent]
    let timelineOrigin: USBConnectionTimelineOrigin
    let isIncomplete: Bool
    let incompleteReasons: Set<USBConnectionTimelineIncompleteReason>
    let droppedEventCount: Int
    let activeInstanceCount: Int
}

struct USBConnectionTimelineTracker {
    static let defaultMaxEventsPerPort = 128
    static let defaultMaxReappearancesPerPort = 1_024
    static let defaultMaxPorts = 64
    static let defaultMaxUnownedEvents = 64
    static let defaultMaxActivePerPort = 64

    private struct ActiveInstance {
        var observation: USBConnectionTimelineObservation
        var baselineStart: TimeInterval
        var startKnown: Bool
        var origin: USBConnectionTimelineOrigin
    }

    private struct RemovedInstance {
        let observedAt: TimeInterval
        let ecid: String?
        let mode: USBConnectionTimelineMode
        let registryEntryID: UInt64?
    }

    private struct ReappearanceSample {
        let monotonicSeconds: TimeInterval
        let identity: USBConnectionTimelineIdentityRelation
    }

    private struct PortState {
        var events: [USBConnectionTimelineEvent] = []
        var active: [UInt64: ActiveInstance] = [:]
        var pendingRemoval: RemovedInstance?
        var lastResidenceSeconds: TimeInterval?
        var lastReappearanceGapSeconds: TimeInterval?
        var lastReconnectionIdentity: USBConnectionTimelineIdentityRelation?
        var reappearances: [ReappearanceSample] = []
        var origin: USBConnectionTimelineOrigin
        var incompleteReasons: Set<USBConnectionTimelineIncompleteReason> = []
    }

    private let maxEventsPerPort: Int
    private let maxReappearancesPerPort: Int
    private let maxPorts: Int
    private let maxUnownedEvents: Int
    private let maxActivePerPort: Int

    private var sessionID: UUID?
    private var sessionActive = false
    private var coverage: USBConnectionObservationCoverage = .registering
    private var globalIncompleteReasons: Set<USBConnectionTimelineIncompleteReason> = []
    private var startedAtMonotonic: TimeInterval = 0
    private var lastSequence: UInt64 = 0
    private var ports: [String: PortState] = [:]
    private var unowned: [USBConnectionTimelineEvent] = []
    private var droppedEventCount = 0

    init(
        maxEventsPerPort: Int = Self.defaultMaxEventsPerPort,
        maxReappearancesPerPort: Int = Self.defaultMaxReappearancesPerPort,
        maxPorts: Int = Self.defaultMaxPorts,
        maxUnownedEvents: Int = Self.defaultMaxUnownedEvents,
        maxActivePerPort: Int = Self.defaultMaxActivePerPort
    ) {
        self.maxEventsPerPort = max(10, maxEventsPerPort)
        self.maxReappearancesPerPort = max(60, maxReappearancesPerPort)
        self.maxPorts = max(1, maxPorts)
        self.maxUnownedEvents = max(1, maxUnownedEvents)
        self.maxActivePerPort = max(1, maxActivePerPort)
    }

    mutating func beginSession(
        id: UUID,
        wallTime: Date,
        monotonicSeconds: TimeInterval
    ) {
        sessionID = id
        sessionActive = true
        coverage = .registering
        globalIncompleteReasons.removeAll(keepingCapacity: true)
        startedAtMonotonic = monotonicSeconds
        lastSequence = 0
        ports.removeAll(keepingCapacity: true)
        unowned.removeAll(keepingCapacity: true)
        droppedEventCount = 0
        _ = wallTime
    }

    mutating func setCoverage(_ newCoverage: USBConnectionObservationCoverage) {
        coverage = newCoverage
        switch newCoverage {
        case .complete:
            globalIncompleteReasons.remove(.registrationPending)
            globalIncompleteReasons.remove(.arrivedRegistrationFailed)
            globalIncompleteReasons.remove(.terminatedRegistrationFailed)
        case .incomplete(let reason):
            globalIncompleteReasons.insert(reason)
        case .registering:
            globalIncompleteReasons.insert(.registrationPending)
        }
    }

    mutating func endSession() {
        sessionActive = false
        globalIncompleteReasons.insert(.sessionEnded)
    }

    mutating func recordDropped(
        _ count: Int,
        reason: USBConnectionTimelineIncompleteReason
    ) {
        guard count > 0 else { return }
        droppedEventCount += count
        globalIncompleteReasons.insert(reason)
    }

    @discardableResult
    mutating func ingest(_ observations: [USBConnectionTimelineObservation]) -> Int {
        var ignored = 0
        for observation in observations.sorted(by: { $0.sequence < $1.sequence }) {
            guard observation.sessionID == sessionID, sessionActive else {
                ignored += 1
                continue
            }
            guard observation.sequence > lastSequence else {
                ignored += 1
                markIncomplete(.outOfOrderEvent, portKey: observation.assignment.portKey)
                continue
            }
            lastSequence = observation.sequence
            _ = accept(observation)
        }
        droppedEventCount += ignored
        return ignored
    }

    mutating func clear(
        portKey: String,
        monotonicSeconds: TimeInterval,
        wallTime: Date
    ) {
        _ = wallTime
        var state = ports[portKey] ?? PortState(origin: .clearedAt(monotonicSeconds))
        for key in state.active.keys {
            state.active[key]?.baselineStart = monotonicSeconds
            state.active[key]?.startKnown = false
            state.active[key]?.origin = .clearedAt(monotonicSeconds)
        }
        state.events.removeAll(keepingCapacity: true)
        state.pendingRemoval = nil
        state.lastResidenceSeconds = nil
        state.lastReappearanceGapSeconds = nil
        state.lastReconnectionIdentity = nil
        state.reappearances.removeAll(keepingCapacity: true)
        state.origin = .clearedAt(monotonicSeconds)
        ports[portKey] = state
    }

    func snapshot(
        for portKey: String,
        label: String?,
        nowMonotonicSeconds: TimeInterval,
        nowWallTime: Date
    ) -> USBConnectionTimelineSnapshot {
        _ = nowWallTime
        let state = ports[portKey]
        let active = state?.active.values.sorted {
            $0.observation.sequence < $1.observation.sequence
        } ?? []
        let current: USBConnectionTimelineCurrentPresence?
        if active.count == 1, let instance = active.first {
            current = USBConnectionTimelineCurrentPresence(
                registryEntryID: instance.observation.registryEntryID,
                locationID: instance.observation.locationID,
                mode: instance.observation.mode,
                vendorID: instance.observation.vendorID,
                productID: instance.observation.productID,
                ecid: instance.observation.ecid,
                productName: instance.observation.productName,
                startKind: instance.origin,
                sinceMonotonicSeconds: instance.startKnown ? instance.baselineStart : nil,
                observedAtLeastSeconds: max(0, nowMonotonicSeconds - instance.baselineStart))
        } else {
            current = nil
        }
        let reappearances = (state?.reappearances ?? []).filter {
            $0.monotonicSeconds > nowMonotonicSeconds - 60
                && $0.monotonicSeconds <= nowMonotonicSeconds
        }
        let sameMachineCount: Int?
        if reappearances.allSatisfy({ $0.identity != .unknown }) {
            sameMachineCount = reappearances.filter { $0.identity == .sameMachine }.count
        } else {
            sameMachineCount = nil
        }
        var reasons = incompleteReasons(portKey: portKey)
        reasons.formUnion(state?.incompleteReasons ?? [])
        if (state?.active.count ?? 0) > 1 {
            reasons.insert(.multipleActiveInstances)
        }
        return USBConnectionTimelineSnapshot(
            portKey: portKey,
            portLabel: label,
            currentPresence: current,
            currentResidenceSeconds: current?.sinceMonotonicSeconds.map {
                max(0, nowMonotonicSeconds - $0)
            },
            observedAtLeastSeconds: current?.observedAtLeastSeconds,
            lastResidenceSeconds: state?.lastResidenceSeconds,
            lastReappearanceGapSeconds: state?.lastReappearanceGapSeconds,
            lastReconnectionIdentity: state?.lastReconnectionIdentity,
            portReappearancesIn60Seconds: reappearances.count,
            sameMachineReenumerationsIn60Seconds: sameMachineCount,
            recentEvents: Array((state?.events ?? []).suffix(10).reversed()),
            timelineOrigin: state?.origin ?? .sessionStart,
            isIncomplete: !reasons.isEmpty,
            incompleteReasons: reasons,
            droppedEventCount: droppedEventCount,
            activeInstanceCount: active.count)
    }

    func unownedEvents(limit: Int = 10) -> [USBConnectionTimelineEvent] {
        Array(unowned.suffix(max(0, limit)).reversed())
    }

    private mutating func accept(_ observation: USBConnectionTimelineObservation) -> Bool {
        guard observation.direction != .initialPresent else {
            return acceptInitial(observation)
        }
        guard let portKey = observation.assignment.portKey,
              observation.assignment.isConfirmed else {
            appendUnowned(observation)
            return false
        }
        guard ports[portKey] != nil || ports.count < maxPorts else {
            droppedEventCount += 1
            globalIncompleteReasons.insert(.portCapacityExceeded)
            return false
        }
        var state = ports[portKey] ?? PortState(origin: .sessionStart)
        switch observation.direction {
        case .arrived:
            guard let id = observation.registryEntryID else {
                appendEvent(observation, to: &state)
                markIncomplete(.unknownRegistryID, portKey: portKey, state: &state)
                ports[portKey] = state
                return false
            }
            if state.active[id] != nil {
                ports[portKey] = state
                return false
            }
            if state.active.count >= maxActivePerPort {
                droppedEventCount += 1
                markIncomplete(.activeInstanceOverflow, portKey: portKey, state: &state)
                ports[portKey] = state
                return false
            }
            if let removal = state.pendingRemoval {
                let gap = max(0, observation.monotonicSeconds - removal.observedAt)
                let relation = identityRelation(
                    previous: removal.ecid,
                    current: observation.ecid)
                let modeTransition: USBConnectionTimelineModeTransition =
                    removal.mode == observation.mode ? .sameMode : .changedMode
                appendReappearance(
                    ReappearanceSample(
                        monotonicSeconds: observation.monotonicSeconds,
                        identity: relation),
                    to: &state)
                state.lastReappearanceGapSeconds = gap
                state.lastReconnectionIdentity = relation
                state.pendingRemoval = nil
                appendEvent(
                    observation,
                    to: &state,
                    modeTransition: modeTransition)
            } else {
                appendEvent(observation, to: &state)
            }
            state.active[id] = ActiveInstance(
                observation: observation,
                baselineStart: observation.monotonicSeconds,
                startKnown: true,
                origin: .sessionStart)
            ports[portKey] = state
            return true
        case .removed:
            appendEvent(observation, to: &state)
            guard let id = observation.registryEntryID,
                  let active = state.active.removeValue(forKey: id) else {
                markIncomplete(.unmatchedRemoval, portKey: portKey, state: &state)
                ports[portKey] = state
                return false
            }
            if active.startKnown {
                state.lastResidenceSeconds = max(
                    0,
                    observation.monotonicSeconds - active.baselineStart)
            }
            if state.active.isEmpty {
                state.pendingRemoval = RemovedInstance(
                    observedAt: observation.monotonicSeconds,
                    ecid: observation.ecid,
                    mode: observation.mode,
                    registryEntryID: observation.registryEntryID)
            } else {
                state.pendingRemoval = nil
                state.incompleteReasons.insert(.multipleActiveInstances)
            }
            ports[portKey] = state
            return true
        case .initialPresent:
            return false
        }
    }

    private mutating func acceptInitial(
        _ observation: USBConnectionTimelineObservation
    ) -> Bool {
        guard let portKey = observation.assignment.portKey,
              observation.assignment.isConfirmed else {
            appendUnowned(observation)
            return false
        }
        guard ports[portKey] != nil || ports.count < maxPorts else {
            droppedEventCount += 1
            globalIncompleteReasons.insert(.portCapacityExceeded)
            return false
        }
        var state = ports[portKey] ?? PortState(origin: .sessionStart)
        guard let id = observation.registryEntryID else {
            markIncomplete(.unknownRegistryID, portKey: portKey, state: &state)
            ports[portKey] = state
            return false
        }
        state.active[id] = ActiveInstance(
            observation: observation,
            baselineStart: startedAtMonotonic,
            startKnown: false,
            origin: .sessionStart)
        ports[portKey] = state
        return true
    }

    private mutating func appendEvent(
        _ observation: USBConnectionTimelineObservation,
        to state: inout PortState,
        modeTransition: USBConnectionTimelineModeTransition? = nil
    ) {
        let event = makeEvent(observation, modeTransition: modeTransition)
        state.events.append(event)
        if state.events.count > maxEventsPerPort {
            let removed = state.events.count - maxEventsPerPort
            state.events.removeFirst(removed)
            droppedEventCount += removed
            state.incompleteReasons.insert(.historyOverflow)
        }
    }

    private mutating func appendReappearance(
        _ sample: ReappearanceSample,
        to state: inout PortState
    ) {
        state.reappearances.append(sample)
        if state.reappearances.count > maxReappearancesPerPort {
            let removed = state.reappearances.count - maxReappearancesPerPort
            state.reappearances.removeFirst(removed)
            droppedEventCount += removed
            state.incompleteReasons.insert(.reappearanceOverflow)
        }
    }

    private mutating func appendUnowned(_ observation: USBConnectionTimelineObservation) {
        unowned.append(makeEvent(observation))
        if unowned.count > maxUnownedEvents {
            unowned.removeFirst(unowned.count - maxUnownedEvents)
            droppedEventCount += 1
        }
    }

    private func makeEvent(
        _ observation: USBConnectionTimelineObservation,
        modeTransition: USBConnectionTimelineModeTransition? = nil
    ) -> USBConnectionTimelineEvent {
        USBConnectionTimelineEvent(
            id: "\(observation.sessionID.uuidString):\(observation.sequence)",
            sequence: observation.sequence,
            batchID: observation.batchID,
            observedAtUTC: observation.observedAtUTC,
            monotonicSeconds: observation.monotonicSeconds,
            direction: observation.direction,
            registryEntryID: observation.registryEntryID,
            locationID: observation.locationID,
            mode: observation.mode,
            vendorID: observation.vendorID,
            productID: observation.productID,
            ecid: observation.ecid,
            productName: observation.productName,
            deviceClass: observation.deviceClass,
            assignment: observation.assignment,
            retainedAttributes: observation.retainedAttributes,
            modeTransition: modeTransition)
    }

    private func identityRelation(previous: String?, current: String?) -> USBConnectionTimelineIdentityRelation {
        guard let previous, !previous.isEmpty,
              let current, !current.isEmpty else {
            return .unknown
        }
        return previous.caseInsensitiveCompare(current) == .orderedSame
            ? .sameMachine
            : .changedMachine
    }

    private mutating func markIncomplete(
        _ reason: USBConnectionTimelineIncompleteReason,
        portKey: String?,
        state: inout PortState
    ) {
        _ = portKey
        state.incompleteReasons.insert(reason)
    }

    private mutating func markIncomplete(
        _ reason: USBConnectionTimelineIncompleteReason,
        portKey: String?
    ) {
        guard let portKey, var state = ports[portKey] else { return }
        markIncomplete(reason, portKey: portKey, state: &state)
        ports[portKey] = state
    }

    private func incompleteReasons(
        portKey: String
    ) -> Set<USBConnectionTimelineIncompleteReason> {
        var reasons: Set<USBConnectionTimelineIncompleteReason> = []
        switch coverage {
        case .incomplete(let reason):
            reasons.insert(reason)
        case .registering:
            reasons.insert(.registrationPending)
        case .complete:
            break
        }
        reasons.formUnion(globalIncompleteReasons)
        if !sessionActive {
            reasons.insert(.sessionEnded)
        }
        return reasons
    }
}

enum USBConnectionTimelineFormatter {
    static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "未知" }
        let clamped = max(0, seconds)
        let hours = Int(clamped) / 3_600
        let minutes = (Int(clamped) % 3_600) / 60
        let remaining = clamped - Double(hours * 3_600 + minutes * 60)
        if hours > 0 {
            return String(format: "%d:%02d:%06.3f", hours, minutes, remaining)
        }
        return String(format: "%02d:%06.3f", minutes, remaining)
    }

    static func timestamp(
        _ date: Date,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS XXX"
        return formatter.string(from: date)
    }

    static func eventLine(
        _ event: USBConnectionTimelineEvent,
        timeZone: TimeZone = .current
    ) -> String {
        let direction: String
        switch event.direction {
        case .arrived: direction = L10n.t("出现")
        case .removed: direction = L10n.t("消失")
        case .initialPresent: direction = L10n.t("开始观察时已存在")
        }
        let vid = event.vendorID.map { String(format: "VID 0x%04X", $0) } ?? "VID 未知"
        let pid = event.productID.map { String(format: "PID 0x%04X", $0) } ?? "PID 未知"
        let ecid = event.ecid.map { "ECID \($0)" } ?? "ECID 未知"
        let instance = event.registryEntryID
            .map { "Registry \($0)" }
            ?? L10n.t("实例 ID 未知")
        let retained = event.retainedAttributes
            ? L10n.t("终止时使用留存字段")
            : ""
        let modeTransition: String
        switch event.modeTransition {
        case .sameMode:
            modeTransition = L10n.t("同模式再枚举")
        case .changedMode:
            modeTransition = L10n.t("模式改变")
        case .unknown:
            modeTransition = L10n.t("模式关系未知")
        case .none:
            modeTransition = ""
        }
        return [
            timestamp(event.observedAtUTC, timeZone: timeZone),
            direction,
            L10n.t(event.mode.displayText),
            vid,
            pid,
            ecid,
            instance,
            event.assignment.portLabel.map(L10n.localizedPortName)
                ?? L10n.t("端口归属未知"),
            L10n.t(event.assignment.evidence),
            retained,
            modeTransition
        ].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func copyText(
        _ snapshot: USBConnectionTimelineSnapshot,
        timeZone: TimeZone = .current
    ) -> String {
        var lines = [
            "\(L10n.t("USB 时序观察"))：\(L10n.localizedPortName(snapshot.portLabel ?? snapshot.portKey))",
            L10n.t("时区：\(timeZone.identifier)")
        ]
        if snapshot.isIncomplete {
            let reasons = snapshot.incompleteReasons.map(\.rawValue).sorted().joined(separator: ", ")
            lines.append(L10n.t("观察不完整：\(reasons)"))
        }
        if let current = snapshot.currentPresence {
            lines.append(
                L10n.t("当前：")
                + L10n.t(current.mode.displayText)
                + " · "
                + (current.productName ?? L10n.t("身份待识别")))
            if let residence = snapshot.currentResidenceSeconds {
                lines.append(L10n.t("当前驻留：") + duration(residence))
            } else if let observed = snapshot.observedAtLeastSeconds {
                let baseline = current.startKind == .sessionStart
                    ? L10n.t("开始观察时已存在")
                    : L10n.t("清零后建立观察基线")
                lines.append(
                    baseline
                    + "；"
                    + L10n.t("出现时间未知")
                    + "；"
                    + L10n.t("已观察至少")
                    + duration(observed))
            }
        } else {
            lines.append(L10n.t("当前未见可归属于此口的 USB 设备"))
        }
        lines.append(L10n.t("上次驻留：") + duration(snapshot.lastResidenceSeconds))
        lines.append(
            L10n.t("上次端口再出现间隔：")
            + duration(snapshot.lastReappearanceGapSeconds))
        lines.append(
            L10n.t("最近 60 秒端口再出现：")
            + L10n.times(snapshot.portReappearancesIn60Seconds))
        if let same = snapshot.sameMachineReenumerationsIn60Seconds {
            lines.append(
                L10n.t("其中同机重枚举：")
                + L10n.times(same))
        } else {
            lines.append(L10n.t("同机重枚举：未知"))
        }
        if snapshot.droppedEventCount > 0 {
            lines.append(
                L10n.t("事件不完整，至少丢失")
                + String(snapshot.droppedEventCount)
                + L10n.t("条"))
        }
        lines.append(L10n.t("最近 USB 系统通知："))
        if snapshot.recentEvents.isEmpty {
            lines.append(L10n.t("暂无"))
        } else {
            lines.append(contentsOf: snapshot.recentEvents.map {
                eventLine($0, timeZone: timeZone)
            })
        }
        return lines.joined(separator: "\n")
    }
}

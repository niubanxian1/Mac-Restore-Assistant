import Foundation

/// A clearly located physical-port observation used only for display change logs.
struct LocatedPortState: Equatable {
    var portKey: String
    var portLabel: String
    var present: Bool
    var mode: ObservedDeviceMode?
    var ecid: String?

    var identityKnown: Bool {
        guard let ecid, !ecid.isEmpty else { return false }
        return true
    }
}

struct UnlocatedDeviceState: Equatable {
    var id: String
    var mode: ObservedDeviceMode?
    var ecid: String?
}

/// A validated (or failed) observation snapshot. A failed read must not be treated as unplug.
struct PortConnectionSnapshot: Equatable {
    var isValid: Bool
    var ports: [String: LocatedPortState]
    var unlocated: [UnlocatedDeviceState]

    static func failed() -> PortConnectionSnapshot {
        PortConnectionSnapshot(isValid: false, ports: [:], unlocated: [])
    }
}

/// One session-scoped connection-change row. Never persisted, never a send precondition.
struct ConnectionChangeEvent: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let portKey: String?
    let portLabel: String
    var fact: String
    var isUniqueInterfaceChange: Bool
    var reconnectSeconds: TimeInterval?
    var ecid: String?
    /// True when this row started as "connection changed, identity not yet read" and may be filled in.
    var awaitingIdentity: Bool

    func displayLine(formatter: DateFormatter) -> String {
        "\(formatter.string(from: timestamp))　\(portLabel)　\(fact)"
    }
}

struct ConnectionChangeIngestResult: Equatable {
    var addedOrUpdated: [ConnectionChangeEvent] = []
    var changedPortKeys: [String] = []
    var uniqueChangedPortKey: String? = nil
}

/// Reuses the old calibration-tool unique-delta judgment:
/// compare two already-valid snapshots keyed by a unique port identity;
/// zero changes → unchanged; exactly one clearly located port change → unique;
/// several located ports changing → record each, do not mark unique;
/// missing/duplicate identity is not forced onto a port.
/// Source read (do not import that Python flow):
/// `/Users/Shared/RC17_DIAG_NEXT120_RECONCILE/port_connection_delta.py`
/// (`compute_connection_delta`) and `hardware_preview_model.record_after`.
struct ConnectionChangeEngine {
    private(set) var events: [ConnectionChangeEvent] = []
    private var didCaptureBaseline = false
    private var lastValid: PortConnectionSnapshot?
    private var lastDisappearAt: [String: Date] = [:]
    private var lastDisappearECID: [String: String] = [:]

    mutating func resetSession() {
        events = []
        didCaptureBaseline = false
        lastValid = nil
        lastDisappearAt = [:]
        lastDisappearECID = [:]
    }

    mutating func ingest(_ snapshot: PortConnectionSnapshot, at now: Date) -> ConnectionChangeIngestResult {
        guard snapshot.isValid else {
            // A single read failure is not an unplug and must not invent events.
            return ConnectionChangeIngestResult()
        }
        if !didCaptureBaseline {
            didCaptureBaseline = true
            lastValid = snapshot
            // First launch / initial enumeration is current state only, not a just-inserted event.
            return ConnectionChangeIngestResult()
        }
        guard let before = lastValid else {
            lastValid = snapshot
            return ConnectionChangeIngestResult()
        }
        if before == snapshot {
            // Repeated identical refresh must not flood the list.
            return ConnectionChangeIngestResult()
        }

        let locatedKeys = Set(before.ports.keys).union(snapshot.ports.keys)
        var portChanges: [(key: String, event: ConnectionChangeEvent)] = []
        var pendingFillIns: [ConnectionChangeEvent] = []

        for key in locatedKeys.sorted() {
            let previous = before.ports[key]
            let current = snapshot.ports[key]
            if let fill = fillInIdentityIfNeeded(portKey: key, previous: previous, current: current, at: now) {
                pendingFillIns.append(fill)
                continue
            }
            if let event = eventForLocatedChange(portKey: key, previous: previous, current: current, at: now) {
                portChanges.append((key, event))
            }
        }

        // Unlocated devices are recorded separately and never borrowed onto a selected or nearby port.
        var unlocatedEvents: [ConnectionChangeEvent] = []
        let beforeUnlocated = Set(before.unlocated.map(\.id))
        let afterUnlocated = Set(snapshot.unlocated.map(\.id))
        if beforeUnlocated != afterUnlocated {
            for item in snapshot.unlocated where !beforeUnlocated.contains(item.id) {
                unlocatedEvents.append(ConnectionChangeEvent(
                    id: UUID(), timestamp: now, portKey: nil, portLabel: "端口未确认",
                    fact: appearFact(mode: item.mode, identityKnown: item.ecid?.isEmpty == false),
                    isUniqueInterfaceChange: false, reconnectSeconds: nil, ecid: item.ecid,
                    awaitingIdentity: item.ecid == nil || item.ecid?.isEmpty == true))
            }
            for item in before.unlocated where !afterUnlocated.contains(item.id) {
                unlocatedEvents.append(ConnectionChangeEvent(
                    id: UUID(), timestamp: now, portKey: nil, portLabel: "端口未确认",
                    fact: "设备暂时未枚举到",
                    isUniqueInterfaceChange: false, reconnectSeconds: nil, ecid: item.ecid,
                    awaitingIdentity: false))
            }
        }

        for fill in pendingFillIns {
            if let index = events.lastIndex(where: { $0.id == fill.id }) {
                events[index] = fill
            }
        }

        let unique = portChanges.count == 1 && unlocatedEvents.isEmpty
        var result = ConnectionChangeIngestResult()
        result.addedOrUpdated.append(contentsOf: pendingFillIns)
        result.changedPortKeys = portChanges.map(\.key)
        if unique {
            result.uniqueChangedPortKey = portChanges[0].key
        }
        for (index, change) in portChanges.enumerated() {
            var event = change.event
            event.isUniqueInterfaceChange = unique
            portChanges[index].event = event
            events.append(event)
            result.addedOrUpdated.append(event)
        }
        for event in unlocatedEvents {
            events.append(event)
            result.addedOrUpdated.append(event)
        }

        lastValid = snapshot
        return result
    }

    func eventsForPort(_ portKey: String, limit: Int = 3) -> [ConnectionChangeEvent] {
        events.filter { $0.portKey == portKey }.reversed().prefix(limit).map { $0 }
    }

    static func timeFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone.current
        f.dateFormat = "HH:mm:ss"
        return f
    }

    static func formatReconnectSeconds(_ value: TimeInterval) -> String {
        String(format: "%.1f", max(0, value))
    }

    // MARK: - Private

    private mutating func fillInIdentityIfNeeded(portKey: String,
                                                 previous: LocatedPortState?,
                                                 current: LocatedPortState?,
                                                 at now: Date) -> ConnectionChangeEvent? {
        guard let previous, let current, previous.present, current.present else { return nil }
        // Identity arriving later on the same port is not a second interface change.
        let identityArrived = !previous.identityKnown && current.identityKnown
        let modeNewlyKnown = previous.mode == nil && current.mode != nil
        guard identityArrived || modeNewlyKnown else { return nil }
        guard var last = events.last(where: { $0.portKey == portKey && $0.awaitingIdentity }) else {
            return nil
        }
        last.fact = appearFact(mode: current.mode, identityKnown: current.identityKnown)
        last.ecid = current.ecid
        last.awaitingIdentity = false
        _ = now
        return last
    }

    private mutating func eventForLocatedChange(portKey: String,
                                                previous: LocatedPortState?,
                                                current: LocatedPortState?,
                                                at now: Date) -> ConnectionChangeEvent? {
        let label = current?.portLabel ?? previous?.portLabel ?? "端口未确认"
        let wasPresent = previous?.present == true
        let isPresent = current?.present == true

        if wasPresent && !isPresent {
            lastDisappearAt[portKey] = now
            if let ecid = previous?.ecid, !ecid.isEmpty {
                lastDisappearECID[portKey] = ecid
            }
            return ConnectionChangeEvent(
                id: UUID(), timestamp: now, portKey: portKey, portLabel: label,
                fact: "设备暂时未枚举到",
                isUniqueInterfaceChange: false, reconnectSeconds: nil, ecid: previous?.ecid,
                awaitingIdentity: false)
        }

        if !wasPresent && isPresent {
            let seconds = lastDisappearAt[portKey].map { now.timeIntervalSince($0) }
            lastDisappearAt[portKey] = nil
            let previousECID = lastDisappearECID[portKey]
            lastDisappearECID[portKey] = nil
            let fact = reconnectOrAppearFact(
                portLabel: label,
                mode: current?.mode,
                currentECID: current?.ecid,
                previousECID: previousECID,
                seconds: seconds)
            let awaiting = current?.identityKnown != true && current?.mode == nil
            return ConnectionChangeEvent(
                id: UUID(), timestamp: now, portKey: portKey, portLabel: label,
                fact: fact,
                isUniqueInterfaceChange: false,
                reconnectSeconds: seconds,
                ecid: current?.ecid,
                awaitingIdentity: awaiting)
        }

        if wasPresent && isPresent {
            let modeChanged = previous?.mode != current?.mode && current?.mode != nil
            guard modeChanged || previous?.ecid != current?.ecid else { return nil }
            if modeChanged {
                let same = sameDevice(previous?.ecid, current?.ecid)
                let modeTitle = current?.mode?.title ?? "未知模式"
                let fact: String
                if same {
                    fact = "同一设备以 \(modeTitle) 模式重新出现"
                } else if current?.mode != nil {
                    fact = appearFact(mode: current?.mode, identityKnown: current?.identityKnown == true)
                } else {
                    fact = "检测到连接变化"
                }
                return ConnectionChangeEvent(
                    id: UUID(), timestamp: now, portKey: portKey, portLabel: label,
                    fact: fact,
                    isUniqueInterfaceChange: false, reconnectSeconds: nil, ecid: current?.ecid,
                    awaitingIdentity: current?.identityKnown != true)
            }
        }
        return nil
    }

    private func reconnectOrAppearFact(portLabel: String,
                                       mode: ObservedDeviceMode?,
                                       currentECID: String?,
                                       previousECID: String?,
                                       seconds: TimeInterval?) -> String {
        if let seconds, seconds >= 0, lastDisconnectKnown(previousECID: previousECID, currentECID: currentECID, seconds: seconds) {
            if sameDevice(previousECID, currentECID) {
                let modeTitle = mode?.title ?? "未知模式"
                return "同一设备于 \(Self.formatReconnectSeconds(seconds)) 秒后以 \(modeTitle) 重新出现"
            }
            return "\(portLabel)于 \(Self.formatReconnectSeconds(seconds)) 秒后再次出现设备"
        }
        if mode == nil || mode == .connected {
            return "设备插入"
        }
        if mode == .unknown && (currentECID == nil || currentECID?.isEmpty == true) {
            return "检测到连接变化"
        }
        return appearFact(mode: mode, identityKnown: currentECID?.isEmpty == false)
    }

    private func lastDisconnectKnown(previousECID: String?, currentECID: String?, seconds: TimeInterval) -> Bool {
        _ = previousECID
        _ = currentECID
        return seconds >= 0
    }

    private func sameDevice(_ left: String?, _ right: String?) -> Bool {
        guard let left, let right, !left.isEmpty, !right.isEmpty else { return false }
        return left.caseInsensitiveCompare(right) == .orderedSame
    }

    private func appearFact(mode: ObservedDeviceMode?, identityKnown: Bool) -> String {
        _ = identityKnown
        if let mode {
            switch mode {
            case .dfu: return "新出现 DFU 设备"
            case .recovery: return "新出现 Recovery 设备"
            case .connected: return "设备插入"
            case .unknown: return "检测到连接变化"
            }
        }
        return "检测到连接变化"
    }
}

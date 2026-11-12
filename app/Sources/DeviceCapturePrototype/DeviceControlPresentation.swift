import Foundation
import AppKit

struct TechnicalDetailRow: Identifiable, Equatable {
    var id: String { group + "/" + name }
    var group: String
    var name: String
    var value: String
}

struct SelectedHostPortDetail: Equatable {
    var hasSelection: Bool
    var controllerText: String
    var portNumberText: String
    var ridText: String
    var slotText: String
    var builtInCalibrationText: String
    var adoptedCalibrationText: String
    var hostModelText: String
}

struct SelectedPortDetail: Equatable {
    var title: String
    var hasCurrentDevice: Bool
    var currentHeadline: String
    var ecid: String?
    var serial: String?
    var lastIdentified: String?
    var connectionSummary: String?
    var reconnectText: String?
    var technicalRows: [TechnicalDetailRow]
    var recentChanges: [ConnectionChangeEvent]

    var emptyChangesText: String { "本次打开后暂无连接变化" }
}

enum DeviceDisplayIdentity {
    /// Serial is only a clearly identified device serial; never a USB product string or ECID.
    static func displaySerial(from device: ObservedDevice) -> String? {
        let raw = device.serial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if raw.localizedCaseInsensitiveContains("Apple Mobile Device") { return nil }
        if raw.range(of: "ECID:", options: .caseInsensitive) != nil { return nil }
        if let ecid = device.ecid, raw.caseInsensitiveCompare(ecid) == .orderedSame { return nil }
        if ECIDIdentity(hex: raw) != nil { return nil }
        return raw
    }

    /// Do not invent a marketing model from USB product text or host calibration.
    /// When DFU is recognized but no identified model is available, say so explicitly
    /// instead of showing 「无设备」 or a bare mode with no model context.
    static func currentHeadline(mode: ObservedDeviceMode?, identifiedModel: String?) -> String {
        // Only an explicit machine identifier is a model. `Mac` or
        // `Apple Mobile Device (DFU Mode)` must never become one.
        let model = TargetModelCatalog.identifier(from: identifiedModel)
        let modelText = model.map(TargetModelCatalog.displayName(for:))
        if let mode {
            switch mode {
            case .connected:
                if let modelText { return "\(modelText) · 已连接" }
                return "已连接 Mac · 具体机型未知"
            case .dfu:
                if let modelText { return "\(modelText) · DFU" }
                return "DFU · 机型未识别"
            case .recovery:
                if let modelText { return "\(modelText) · Recovery" }
                return "Recovery"
            case .unknown:
                if let modelText { return "\(modelText) · 未知模式" }
                return "未知模式"
            }
        }
        if let modelText { return modelText }
        return "当前未识别到设备"
    }
}

extension DeviceControlModel {
    var selectionHintText: String {
        if let live = selectedLivePort {
            return "已选\(label(for: live))，可进入 DFU 或重启"
        }
        return "请先选择物理端口，再执行进入 DFU 或重启"
    }

    func portSwitchFeedbackTitle(for live: LiveHostPort) -> String {
        "操作目标已切换：\(label(for: live))"
    }

    /// Host-model token when the model is identified. Empty / "unknown" is not a model.
    var statusLineHostModelText: String {
        let raw = calibration.hostModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || raw.caseInsensitiveCompare("unknown") == .orderedSame {
            return ""
        }
        return raw
    }

    var isHostModelIdentified: Bool { !statusLineHostModelText.isEmpty }

    /// Exact verified record: production `builtInLayout = database[host]`
    /// and that record is still the layout actually in use.
    /// Importing a pack, adding a model, applying a layout, or a tool save
    /// must not flip this to true.
    var hasExactVerifiedHostCalibration: Bool {
        if let overlay = calibration.adoptedOverlay {
            if !overlay.isUsableEffectiveRecord {
                return calibration.builtInLayout != nil
            }
            if overlay.source == .inAppCalibration {
                return overlay.sourceHostModel.caseInsensitiveCompare(calibration.hostModel) == .orderedSame
                    && !overlay.layout.partial
            }
            // A pack for the same host whose complete slot mapping equals the
            // verified builtin record is the same exact hit, not "same mold".
            if overlay.sourceHostModel.caseInsensitiveCompare(calibration.hostModel) == .orderedSame,
               overlay.matchesExactBuiltIn(calibration.builtInLayout) {
                return true
            }
            guard calibration.builtInLayout != nil else { return false }
            return overlay.isExactVerifiedHit
        }
        return calibration.builtInLayout != nil
    }

    /// Same-mold candidate from existing `sharedLayoutCandidates`.
    /// Settings already labels these “共享布局候选（不自动套用）”.
    var hasSameMoldLayoutCandidate: Bool {
        guard isHostModelIdentified else { return false }
        let host = statusLineHostModelText
        return calibration.sharedLayoutCandidates.contains { candidate in
            candidate.models.contains { $0.caseInsensitiveCompare(host) == .orderedSame }
        }
    }

    /// Owner-confirmed shared physical layout. This is data-driven and never
    /// inferred from CPU generation, model-number similarity, or display name.
    var confirmedSharedHostLayout: (sourceHost: String, layout: BuiltInLayout)? {
        let host = statusLineHostModelText
        guard !host.isEmpty else { return nil }
        for candidate in calibration.sharedLayoutCandidates where candidate.isConfirmed {
            guard candidate.models.contains(where: { $0.caseInsensitiveCompare(host) == .orderedSame }) else {
                continue
            }
            for source in candidate.models where source.caseInsensitiveCompare(host) != .orderedSame {
                if let layout = calibration.builtInLayouts[source] {
                    return (source, layout)
                }
            }
        }
        return nil
    }

    var hasConfirmedSharedHostCalibration: Bool { confirmedSharedHostLayout != nil }

    struct HostLayoutMappingComparison: Equatable {
        var hasLayout: Bool
        var layoutName: String
        var sourceFile: String
        var expected: [String]
        var expectedWithSlots: [String]
        var actual: [String]
        var expectedOnly: [String]
        var actualOnly: [String]
        var conflict: Bool

        var detail: String {
            guard hasLayout else { return "没有可用于当前主机比较的布局记录" }
            let expectedText = expectedWithSlots.isEmpty ? "—" : expectedWithSlots.joined(separator: "、")
            let actualText = actual.isEmpty ? "—" : actual.joined(separator: "、")
            if conflict {
                var parts = ["布局 \(layoutName)（\(sourceFile)）",
                             "预期 \(expectedText)",
                             "实测 \(actualText)"]
                if !expectedOnly.isEmpty { parts.append("仅预期 \(expectedOnly.joined(separator: "、"))") }
                if !actualOnly.isEmpty { parts.append("仅实测 \(actualOnly.joined(separator: "、"))") }
                return parts.joined(separator: "；")
            }
            return "布局 \(layoutName)（\(sourceFile)）；预期 \(expectedText)；实测 \(actualText)"
        }
    }

    /// Explicit comparison used by both the lamp and the detail. Only mapped
    /// data ports participate; MagSafe/charging HPM nodes are not data slots.
    var hostLayoutMappingComparison: HostLayoutMappingComparison {
        let layout: BuiltInLayout?
        if let shared = confirmedSharedHostLayout {
            layout = shared.layout
        } else {
            layout = calibration.builtInLayout
        }
        let mappedPorts = orderedDisplayPorts
        let expectedWithSlots: [String] = layout?.slots.compactMap { slot in
            guard let portNumber = slot.portNumber else { return nil }
            return "\(slot.slot) \(portNumber):\(slot.rid ?? -1)"
        } ?? []
        let expected = layout?.slots.compactMap { slot -> String? in
            guard let portNumber = slot.portNumber else { return nil }
            return "\(portNumber):\(slot.rid ?? -1)"
        } ?? []
        let actual = mappedPorts.map { "\($0.portNumber):\($0.rid)" }
        let expectedSet = Set(expected)
        let actualSet = Set(actual)
        let conflict = !expected.isEmpty
            && mappedPorts.count >= expected.count
            && actualSet != expectedSet
        return HostLayoutMappingComparison(
            hasLayout: layout != nil,
            layoutName: layout?.displayName ?? "—",
            sourceFile: layout?.sourceFile ?? "—",
            expected: expected,
            expectedWithSlots: expectedWithSlots,
            actual: actual,
            expectedOnly: expected.filter { !actualSet.contains($0) },
            actualOnly: actual.filter { !expectedSet.contains($0) },
            conflict: conflict)
    }

    /// Compare the live controller/PortNumber/RID set with a direct or
    /// Owner-confirmed shared layout. Missing ports are not a conflict; a
    /// complete live set with a different mapping is.
    var hostLayoutMappingConflict: Bool { hostLayoutMappingComparison.conflict }
    var hostLayoutMappingConflictDetail: String { hostLayoutMappingComparison.detail }

    enum HostModelCalibrationKind: Equatable {
        case exactVerifiedRecord
        case confirmedSharedLayout
        case sameMoldLayoutReuse
        case unidentified
        case uncalibrated
    }

    /// Host-model calibration kind. Independent of selected port and DUT presence.
    /// Exact verified hit wins over a same-mold candidate for the same host.
    var hostModelCalibrationKind: HostModelCalibrationKind {
        if !isHostModelIdentified { return .unidentified }
        if hasExactVerifiedHostCalibration { return .exactVerifiedRecord }
        if hasConfirmedSharedHostCalibration { return .confirmedSharedLayout }
        if let overlay = calibration.adoptedOverlay, overlay.source != .addedModelOnly {
            // The same host with a non-matching layout is uncalibrated, not
            // "same mold". A different host may reuse only a same-mold layout.
            if overlay.sourceHostModel.caseInsensitiveCompare(calibration.hostModel) == .orderedSame {
                return .uncalibrated
            }
            if calibration.sameMoldPair(overlay.sourceHostModel) {
                return .sameMoldLayoutReuse
            }
            return .uncalibrated
        }
        if hasSameMoldLayoutCandidate { return .sameMoldLayoutReuse }
        return .uncalibrated
    }

    enum HostCalibrationLampState: Equatable {
        case calibrated
        case uncalibrated
        case layoutNeedsReview
        case noModel
        case unidentified

        var text: String {
            switch self {
            case .calibrated: return "已校准"
            case .uncalibrated: return "未校准"
            case .layoutNeedsReview: return "布局待核对"
            case .noModel: return "无模型"
            case .unidentified: return "机型未识别"
            }
        }

        var color: String {
            switch self {
            case .calibrated: return "green"
            case .uncalibrated, .layoutNeedsReview: return "orange"
            case .noModel, .unidentified: return "gray"
            }
        }

        var help: String {
            switch self {
            case .calibrated:
                return "当前主机机型精确命中已有的已验证校准记录"
            case .uncalibrated:
                return "当前主机机型已知，但没有精确校准记录"
            case .layoutNeedsReview:
                return "当前主机读到的 PortNumber/RID 映射与库中记录冲突，布局待核对"
            case .noModel:
                return "模型库没有当前主机的可用模型"
            case .unidentified:
                return "未读取到当前主机机型（不代表模型库为空）"
            }
        }
    }

    /// Bottom-bar lamp only. It is host-model based, never selected-port based.
    /// `noModel` is distinct from `unidentified`: a known host with no usable
    /// model is not the same as a failed host-model read.
    var hostCalibrationLampState: HostCalibrationLampState {
        if !isHostModelIdentified { return .unidentified }
        if hostLayoutMappingConflict { return .layoutNeedsReview }
        switch hostModelCalibrationKind {
        case .exactVerifiedRecord, .confirmedSharedLayout:
            return .calibrated
        case .sameMoldLayoutReuse:
            return .uncalibrated
        case .uncalibrated:
            let hasUsableModel = calibration.builtInLayout != nil
                || (calibration.adoptedOverlay?.isUsableEffectiveRecord ?? false)
                || hasSameMoldLayoutCandidate
            return hasUsableModel ? .uncalibrated : .noModel
        case .unidentified:
            return .unidentified
        }
    }

    var hostCalibrationLampHelp: String {
        if hostCalibrationLampState == .layoutNeedsReview {
            return hostCalibrationLampState.help
        }
        if hostModelCalibrationKind == .sameMoldLayoutReuse {
            return "正在使用同模具布局，当前机型未经精确校准"
        }
        if hostModelCalibrationKind == .confirmedSharedLayout {
            return "同模具共享布局（已确认），当前主机未单独做本机校准"
        }
        return hostCalibrationLampState.help
    }

    /// Detail-only distinction; bottom lamp uses the same green for direct and
    /// Owner-confirmed shared layouts.
    var hostCalibrationMatchDetail: String {
        if !isHostModelIdentified { return "机型未识别" }
        if hostLayoutMappingConflict { return "布局待核对" }
        switch hostModelCalibrationKind {
        case .exactVerifiedRecord: return "本机型直接匹配"
        case .confirmedSharedLayout: return "同模具共享布局"
        case .sameMoldLayoutReuse: return "同模具布局（未确认）"
        case .uncalibrated: return "未校准"
        case .unidentified: return "机型未识别"
        }
    }

    var hostCalibrationSummaryText: String {
        switch hostModelCalibrationKind {
        case .exactVerifiedRecord:
            return L10n.hostCalibrationStatus("exact", host: statusLineHostModelText)
        case .confirmedSharedLayout:
            return L10n.hostCalibrationStatus("shared", host: statusLineHostModelText)
        case .sameMoldLayoutReuse:
            return L10n.hostCalibrationStatus("reuse", host: statusLineHostModelText)
        case .unidentified:
            return L10n.hostCalibrationStatus("unidentified", host: statusLineHostModelText)
        case .uncalibrated:
            return L10n.hostCalibrationStatus("uncalibrated", host: statusLineHostModelText)
        }
    }

    /// 「去校准…」only for 未校准 / 未精确校准 (including same-mold). Not for exact hits.
    var shouldOfferGoCalibrate: Bool {
        switch hostModelCalibrationKind {
        case .exactVerifiedRecord, .confirmedSharedLayout:
            return false
        case .sameMoldLayoutReuse, .uncalibrated, .unidentified:
            return hostCalibrationLampState != .layoutNeedsReview
        }
    }

    /// Opens the existing Settings → 模型校准 editor. No nag or confirmation.
    var goCalibrateSettingsTab: SettingsTab { .model }

    static let goCalibrateRequiresConfirmation = false

    /// Full-width spaces and bar between Helper status and the host summary.
    static let statusLineSeparator = "　｜　"

    /// Status phrase for a currently observed device. Never uses USB product text or ECID as a model.
    func observedStatusPhrase(for device: ObservedDevice) -> String {
        DeviceDisplayIdentity.currentHeadline(
            mode: device.mode,
            identifiedModel: identifiedTargetModel(for: device))
    }

    /// Left-row status only: current observation, never "上次 DFU".
    func compactRowStatus(for live: LiveHostPort) -> String {
        if let device = observedDevice(for: live) {
            return observedStatusPhrase(for: device)
        }
        if live.link?.isConnected == true {
            return "已连接"
        }
        return "未识别设备"
    }

    func compactRowTitle(for live: LiveHostPort) -> String {
        L10n.portRowTitle(label: label(for: live), status: compactRowStatus(for: live))
    }

    func lastIdentifiedText(for live: LiveHostPort) -> String? {
        guard observedDevice(for: live) == nil else { return nil }
        guard let slot = uniquelyMappedBuiltInSlot(for: live)?.slot else { return nil }
        let fingerprint = PortHistoryStore.fingerprint(hostModel: calibration.hostModel, layout: calibration.builtInLayout)
        guard portHistory.matchesCurrentMapping(hostModel: calibration.hostModel, fingerprint: fingerprint),
              let record = portHistory.record(forSlot: slot), !record.lastMode.isEmpty else {
            return nil
        }
        let f = ConnectionChangeEngine.timeFormatter()
        return "上次识别：\(f.string(from: record.lastSeenAt)) · \(record.lastMode)"
    }

    var selectedHostPortDetail: SelectedHostPortDetail {
        guard let live = selectedLivePort else {
            return SelectedHostPortDetail(
                hasSelection: false,
                controllerText: "—",
                portNumberText: "—",
                ridText: "—",
                slotText: "尚未选择主机物理端口",
                builtInCalibrationText: "尚未选择主机物理端口",
                adoptedCalibrationText: "尚未选择主机物理端口",
                hostModelText: calibration.hostModel.isEmpty ? "未获取主机型号" : calibration.hostModel)
        }
        let slotText: String
        if let adopted = uniquelyMappedAdoptedSlot(for: live) {
            slotText = "\(adopted.displayLabel) · \(adopted.slot)"
        } else if let built = uniquelyMappedBuiltInSlot(for: live) {
            slotText = "\(built.displayLabel) · \(built.slot)"
        } else if let custom = calibrationEntry(for: live) {
            slotText = "\(custom.label) · \(custom.physicalPort)"
        } else {
            slotText = "未匹配槽位"
        }
        let hostModel = calibration.hostModel.isEmpty ? "未获取主机型号" : calibration.hostModel
        return SelectedHostPortDetail(
            hasSelection: true,
            controllerText: live.controller,
            portNumberText: String(live.portNumber),
            ridText: String(live.rid),
            slotText: slotText,
            builtInCalibrationText: builtInSlotSummary,
            adoptedCalibrationText: selectedSourceText,
            hostModelText: hostModel)
    }

    var selectedPortDetail: SelectedPortDetail {
        guard let live = selectedLivePort else {
            return SelectedPortDetail(
                title: "未选择 · 设备详情",
                hasCurrentDevice: false,
                currentHeadline: "当前未识别到设备",
                ecid: nil, serial: nil, lastIdentified: nil,
                connectionSummary: nil, reconnectText: nil,
                technicalRows: [], recentChanges: [])
        }
        return detail(for: live)
    }

    func detail(for live: LiveHostPort) -> SelectedPortDetail {
        let name = label(for: live)
        let current = observedDevice(for: live)
        let linkConnected = live.link?.isConnected == true
        let hasCurrent = current != nil || linkConnected
        // Never present historical ECID / serial / model as the current device.
        // identifiedModel is filled only by explicit descriptor evidence or a
        // same-ECID trusted cache; USB product text and host calibration are
        // never passed in as a model.
        let headline: String
        if let current {
            headline = DeviceDisplayIdentity.currentHeadline(
                mode: current.mode,
                identifiedModel: identifiedTargetModel(for: current))
        } else if linkConnected {
            headline = "设备身份暂未读取"
        } else {
            headline = "当前未识别到设备"
        }
        let last = hasCurrent ? nil : lastIdentifiedText(for: live)
        var rows: [TechnicalDetailRow] = []
        // Identity evidence actually read from IOUSB.
        if let current {
            if let model = identifiedTargetModel(for: current) {
                rows.append(TechnicalDetailRow(group: "设备身份", name: "机型",
                                               value: TargetModelCatalog.displayName(for: model)))
                if let source = identifiedTargetModelSource(for: current) {
                    rows.append(TechnicalDetailRow(group: "设备身份", name: "机型来源", value: source))
                }
            }
            if !current.locationID.isEmpty {
                rows.append(TechnicalDetailRow(group: "连接路径", name: "USB location", value: current.locationID))
            }
            if let hub = current.hubName, !hub.isEmpty {
                rows.append(TechnicalDetailRow(group: "连接路径", name: "Hub 名称", value: hub))
            }
            if let path = current.topologyPath, !path.isEmpty {
                rows.append(TechnicalDetailRow(group: "连接路径", name: "拓扑路径", value: path))
            }
            if !current.product.isEmpty {
                rows.append(TechnicalDetailRow(group: "连接路径", name: "读取的 USB 产品名", value: current.product))
            }
        }
        // Controller/port facts come from the same AppleHPM read as the port row.
        rows.append(TechnicalDetailRow(group: "连接路径", name: "端口控制器", value: live.controller))
        rows.append(TechnicalDetailRow(group: "连接路径", name: "控制器端口",
                                       value: "PortNumber \(live.portNumber) · RID \(live.rid)"))
        if let link = live.link {
            let protocolParts = link.transportsProvisioned.isEmpty
                ? link.transportsActive : link.transportsProvisioned
            if !protocolParts.isEmpty {
                rows.append(TechnicalDetailRow(
                    group: "当前链路", name: "当前协议",
                    value: protocolParts.joined(separator: "、") + "（已配置传输，观察）"))
            }
            if let speed = negotiatedSpeedText(device: current, link: link) {
                rows.append(TechnicalDetailRow(group: "当前链路", name: "协商速率", value: speed))
            }
            if let superSpeed = link.superSpeedActive {
                rows.append(TechnicalDetailRow(group: "当前链路", name: "USB 超速活动",
                                               value: L10n.yesNo(superSpeed)))
            }
            if let cable = link.cableIdentityText {
                rows.append(TechnicalDetailRow(group: "线材与能力", name: "线材标识", value: cable))
            }
            if !link.transportsSupported.isEmpty {
                rows.append(TechnicalDetailRow(
                    group: "线材与能力", name: "线材/端口能力",
                    value: link.transportsSupported.joined(separator: "、") + "（能力，不代表当前速率）"))
            }
            if let capability = capabilitySpeedText(link.cableSpeed) {
                rows.append(TechnicalDetailRow(group: "线材与能力", name: "线材速率能力", value: capability))
            }
            if let active = link.connectionActive {
                rows.append(TechnicalDetailRow(group: "端口控制器", name: "控制器连接状态",
                                               value: active ? "已连接" : "未连接"))
            }
            if let count = link.connectionCount {
                rows.append(TechnicalDetailRow(group: "端口控制器", name: "连接计数", value: String(count)))
            }
            if let type = link.connectType {
                rows.append(TechnicalDetailRow(group: "端口控制器", name: "连接类型（读取值）", value: String(type)))
            }
        }
        let connectionSummary: String?
        if let location = current?.locationID, !location.isEmpty {
            connectionSummary = L10n.connectionSummary(location: location)
        } else if linkConnected {
            connectionSummary = "端口控制器已确认连接；USB/Configurator 目标身份暂未读取"
        } else {
            connectionSummary = nil
        }
        let reconnectText = connectionEventsForPort(live.id).compactMap { event -> String? in
            guard event.reconnectSeconds != nil else { return nil }
            return event.fact
        }.first
        // Hub / link speed / cable / board are omitted unless already confirmed. Do not infer 直连.
        return SelectedPortDetail(
            title: "\(L10n.localizedPortName(name)) · 设备详情",
            hasCurrentDevice: hasCurrent,
            currentHeadline: headline,
            ecid: hasCurrent ? current?.ecid : nil,
            serial: hasCurrent ? current.flatMap { DeviceDisplayIdentity.displaySerial(from: $0) } : nil,
            lastIdentified: last,
            connectionSummary: connectionSummary,
            reconnectText: reconnectText,
            technicalRows: rows,
            recentChanges: connectionEventsForPort(live.id))
    }

    private func negotiatedSpeedText(device: ObservedDevice?, link: HostPortLink) -> String? {
        if let bps = device?.linkSpeedBps, bps > 0 { return speedText(bps) }
        for value in [link.dataRateDescription, link.linkRateDescription,
                      link.superspeedSignaling, link.cableSpeed] {
            guard let value, !value.isEmpty, !isCapabilityText(value) else { continue }
            return value
        }
        return nil
    }

    private func capabilitySpeedText(_ value: String?) -> String? {
        guard let value, !value.isEmpty, isCapabilityText(value) else { return nil }
        return value + "（能力上限，非当前速率）"
    }

    private func isCapabilityText(_ value: String) -> Bool {
        let text = value.lowercased()
        return text.contains("up to") || text.contains("最高") || text.contains("capab")
    }

    private func speedText(_ bps: Int) -> String {
        if bps >= 1_000_000_000 { return "\(bps / 1_000_000_000) Gb/s" }
        if bps >= 1_000_000 { return "\(bps / 1_000_000) Mb/s" }
        return "\(bps) bps"
    }

    var connectionEventsForSelectedPort: [ConnectionChangeEvent] {
        guard let key = selectedLivePort?.id else { return [] }
        return connectionEventsForPort(key)
    }

    func connectionEventsForPort(_ key: String) -> [ConnectionChangeEvent] {
        connectionEngine.eventsForPort(key, limit: 3)
    }

    func copySummaryText() -> String {
        let detail = selectedPortDetail
        var lines: [String] = []
        lines.append(detail.title)
        if detail.hasCurrentDevice {
            lines.append("当前观察：\(detail.currentHeadline)")
            if let ecid = detail.ecid, !ecid.isEmpty { lines.append("当前 ECID：\(ecid)") }
            if let serial = detail.serial, !serial.isEmpty { lines.append("当前序列号：\(serial)") }
            if let summary = detail.connectionSummary, !summary.isEmpty {
                lines.append(summary)
            }
            if let reconnect = detail.reconnectText, !reconnect.isEmpty {
                lines.append("重连：\(reconnect)")
            }
        } else {
            lines.append("当前观察：当前未识别到设备")
            if let last = detail.lastIdentified {
                lines.append("上次记录：\(last)（不是当前设备）")
            }
        }
        let formatter = ConnectionChangeEngine.timeFormatter()
        if detail.recentChanges.isEmpty {
            lines.append("最近连接变化：本次打开后暂无连接变化")
        } else {
            lines.append("最近连接变化：")
            for event in detail.recentChanges {
                lines.append("  \(event.displayLine(formatter: formatter))")
            }
        }
        return lines.joined(separator: "\n")
    }
}

enum ObservedDeviceReadResult: Equatable {
    case failed(String)
    case success([ObservedDevice])
}

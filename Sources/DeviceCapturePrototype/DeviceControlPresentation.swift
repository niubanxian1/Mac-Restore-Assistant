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

struct PortIdentityProjection: Equatable {
    let firstLine: String
    let secondLine: String
    let accessibilityLabel: String
}

struct MainPortUSBProjection: Equatable {
    let displayName: String?
    let isMacEvidence: Bool
    let modeText: String
    let evidence: String
    var powerAttribution: PanoramaPowerAttributionResult = .notProvided
}

enum PanoramaUSBStatisticsPresentation {
    static func rows(
        for statistics: PanoramaUSBRootStatistics
    ) -> [TechnicalDetailRow] {
        var rows: [TechnicalDetailRow] = []
        func append(_ name: String, _ value: Int?) {
            guard let value else { return }
            rows.append(TechnicalDetailRow(
                group: "USB 根端口统计",
                name: name,
                value: value == 0xFFFF ? "0xFFFF（饱和/不可用）" : String(value)))
        }
        append("link-error-count", statistics.linkErrorCount)
        append("连接次数", statistics.connectCount)
        append("过流次数", statistics.overcurrentCount)
        append("枚举失败次数", statistics.enumerationFailureCount)
        append("USB3 链路失败次数", statistics.usb3LinkFailureCount)
        return rows
    }
}

enum PhysicalPortListPriority: Int, Comparable {
    case identifiedMac = 0
    case unknownMac = 1
    case usbHubOrPeripheral = 2
    case ownedCable = 3
    case ownedPeerOrPower = 4
    case noDevice = 5

    static func < (lhs: PhysicalPortListPriority, rhs: PhysicalPortListPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
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
    static func currentHeadline(
        mode: ObservedDeviceMode?,
        identifiedModel: String?,
        modelIsCandidate: Bool = false
    ) -> String {
        // Only an explicit machine identifier is a model. `Mac` or
        // `Apple Mobile Device (DFU Mode)` must never become one.
        let model = TargetModelCatalog.identifier(from: identifiedModel)
        let modelText = model.map(TargetModelCatalog.displayName(for:))
        let candidateSuffix = modelIsCandidate ? " · 候选" : ""
        if let mode {
            switch mode {
            case .connected:
                if let modelText { return "\(modelText) · 已连接\(candidateSuffix)" }
                return "已连接 Mac · 具体机型未知"
            case .dfu:
                if let modelText { return "\(modelText) · DFU\(candidateSuffix)" }
                return "DFU · 机型未识别"
            case .recovery:
                if let modelText { return "\(modelText) · Recovery\(candidateSuffix)" }
                return "Recovery"
            case .unknown:
                if let modelText { return "\(modelText) · 未知模式\(candidateSuffix)" }
                return "未知模式"
            }
        }
        if let modelText { return modelText + candidateSuffix }
        return "当前未识别到设备"
    }

    static func currentHeadline(
        mode: ObservedDeviceMode?,
        resolution: ResolvedMacIdentity?
    ) -> String {
        guard let resolution else {
            return currentHeadline(
                mode: mode, identifiedModel: nil, modelIsCandidate: false)
        }
        let modeText = mode?.title ?? "未知模式"
        switch resolution.state {
        case .confirmedCurrent:
            return marketingHeadline(resolution, mode: modeText)
        case .uniqueCurrentMatch:
            return marketingHeadline(resolution, mode: modeText) + " · 唯一匹配"
        case .candidates:
            if resolution.modelIdentifiers.count == 1 {
                return marketingHeadline(resolution, mode: modeText) + " · 候选"
            }
            return "\(resolution.modelIdentifiers.count) 个机型候选 · \(modeText)"
        case .conflict:
            return "身份冲突 · \(modeText)"
        case .historicalHintOnly:
            return "\(modeText) · 当前无身份证据"
        case .unknown:
            return currentHeadline(
                mode: mode, identifiedModel: nil, modelIsCandidate: false)
        }
    }

    private static func marketingHeadline(
        _ resolution: ResolvedMacIdentity,
        mode: String
    ) -> String {
        if resolution.modelIdentifiers.count == 1,
           let identifier = resolution.modelIdentifiers.first {
            let preferred = TargetModelCatalog.displayName(for: identifier)
            if preferred.caseInsensitiveCompare(identifier) != .orderedSame,
               !preferred.contains("候选") {
                let localized = L10n.code() == "zh-Hans"
                    ? preferred : L10n.t(preferred)
                return "\(localized) · \(mode)"
            }
        }
        let names = Array(Set(resolution.records.map(\.marketingName))).sorted()
        let model = names.count == 1
            ? names[0]
            : resolution.modelIdentifiers.first.map(TargetModelCatalog.displayName(for:))
        if let model, !model.isEmpty {
            return "\(model) · \(mode)"
        }
        return mode
    }
}

extension DeviceControlModel {
    var priorityOrderedDisplayPorts: [LiveHostPort] {
        matchedLivePorts.sorted { lhs, rhs in
            let left = portListPriority(for: lhs)
            let right = portListPriority(for: rhs)
            if left != right { return left < right }
            let leftRank = displayPortRank(lhs)
            let rightRank = displayPortRank(rhs)
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.id < rhs.id
        }
    }

    func portListPriority(for live: LiveHostPort) -> PhysicalPortListPriority {
        if let device = observedDevice(for: live) {
            if let resolution = device.identityResolution,
               resolution.state == .confirmedCurrent ||
                resolution.state == .uniqueCurrentMatch {
                return .identifiedMac
            }
            return .unknownMac
        }
        if live.link?.isConnected == true {
            let cableOnly = (live.link?.activeCable == true
                || live.link?.opticalCable == true)
                && (live.link?.connectionCount ?? 0) == 0
            if cableOnly { return .ownedCable }
            return .usbHubOrPeripheral
        }
        if (live.link?.powerMode ?? 0) > 0 {
            return .ownedPeerOrPower
        }
        return .noDevice
    }

    func readonlyMainPortLabel(forUSBlocation rawLocation: String) -> String? {
        let location = Self.normalizeUSBlocation(rawLocation)
        guard !location.isEmpty else { return nil }
        let matches = observedDevices.filter {
            Self.normalizeUSBlocation($0.locationID) == location
        }
        let keys = Set(matches.compactMap { observedPortKey(for: $0) })
        guard keys.count == 1, let key = keys.first,
              let live = livePorts.first(where: { $0.id == key }) else {
            return nil
        }
        return label(for: live)
    }

    /// A physical port association is trusted only when a current live
    /// controller/PortNumber/RID can be tied to the same calibrated USB
    /// location without ambiguity. Built-in slots and legacy RID-only rows do
    /// not carry a USB location and therefore cannot establish this proof.
    func trustedTimelineAssignment(forUSBlocation rawLocation: String) -> USBPortTimelineAssignment {
        let location = Self.normalizeUSBlocation(rawLocation)
        guard !location.isEmpty else {
            return .unowned(location: nil)
        }
        let locationEntries = calibration.ports.filter {
            Self.normalizeUSBlocation($0.location) == location
        }
        var matchedPorts: [LiveHostPort] = []
        var matchedEntries: [PortCalibrationEntry] = []
        for entry in locationEntries {
            guard let controller = entry.controller,
                  let portNumber = entry.portNumber,
                  let rid = Int(entry.rid) else { continue }
            let matches = livePorts.filter {
                $0.controller == controller
                    && $0.portNumber == portNumber
                    && $0.rid == rid
            }
            if matches.count == 1 {
                matchedPorts.append(matches[0])
                matchedEntries.append(entry)
            }
        }
        let uniquePorts = Dictionary(grouping: matchedPorts, by: \.id)
            .compactMap { $0.value.first }
        let uniqueEntries = Set(matchedEntries.map {
            "\($0.physicalPort)|\($0.controller ?? "")|\($0.portNumber ?? -1)|\($0.rid)"
        })
        guard uniquePorts.count == 1,
              uniqueEntries.count == 1,
              let live = uniquePorts.first else {
            return .unowned(location: location)
        }
        return USBPortTimelineAssignment(
            portKey: live.id,
            portLabel: label(for: live),
            evidence: "controller + PortNumber + RID + USB location 精确校准一致",
            isConfirmed: true)
    }

    private static func normalizeUSBlocation(_ value: String) -> String {
        USBTimelineLocationNormalizer.normalize(value)
            ?? value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

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
                && candidate.models.contains { calibration.builtInLayouts[$0] != nil }
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
        case .exactVerifiedRecord:
            return .calibrated
        case .confirmedSharedLayout, .sameMoldLayoutReuse:
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
            return "已有可复用的已确认共享接口布局，但当前主机未做本机精确校准"
        }
        return hostCalibrationLampState.help
    }

    /// Detail-only distinction. Only a direct/in-App exact record lights green.
    var hostCalibrationMatchDetail: String {
        if !isHostModelIdentified { return "机型未识别" }
        if hostLayoutMappingConflict { return "布局待核对" }
        switch hostModelCalibrationKind {
        case .exactVerifiedRecord: return "本机型直接匹配"
        case .confirmedSharedLayout: return "共享接口布局（未精确校准）"
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
        case .exactVerifiedRecord:
            return false
        case .confirmedSharedLayout, .sameMoldLayoutReuse, .uncalibrated, .unidentified:
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
        playbackHeadline(for: device)
    }

    /// Left-row status only: current observation, never "上次 DFU".
    func compactRowStatus(
        for live: LiveHostPort,
        sharedUSB: MainPortUSBProjection? = nil
    ) -> String {
        if let device = observedDevice(for: live) {
            return observedStatusPhrase(for: device)
        }
        if let sharedUSB {
            if sharedUSB.isMacEvidence {
                return "\(L10n.t(sharedUSB.modeText)) · \(L10n.t("型号待确认"))"
            }
            if let name = sharedUSB.displayName, !name.isEmpty {
                return "USB 设备已连接 · \(name)"
            }
            return "USB 设备已连接 · 身份待识别"
        }
        if observationAvailability.isCurrent {
            return "未检测到目标 Mac"
        }
        return "当前观察未知"
    }

    func compactRowTitle(
        for live: LiveHostPort,
        sharedUSB: MainPortUSBProjection? = nil
    ) -> String {
        L10n.portRowTitle(
            label: label(for: live),
            status: compactRowStatus(for: live, sharedUSB: sharedUSB))
    }

    func compactPortIdentity(
        for live: LiveHostPort,
        sharedUSB: MainPortUSBProjection? = nil
    ) -> PortIdentityProjection {
        let current = observedDevice(for: live)
        let portText = L10n.localizedPortName(label(for: live))
        guard let current else {
            let firstLine: String
            let secondLine: String
            if let sharedUSB {
                if sharedUSB.isMacEvidence {
                    firstLine = "\(portText) · \(macHeadline(modeText: sharedUSB.modeText))"
                    secondLine = L10n.t("当前 Mac 身份证据不足")
                } else {
                    let name = sharedUSB.displayName.flatMap {
                        $0.isEmpty ? nil : $0
                    }
                    firstLine = name.map { "\(portText) · USB 设备已连接 · \($0)" }
                        ?? "\(portText) · USB 设备已连接 · 身份待识别"
                    secondLine = "USB 外设，不冒充目标 Mac"
                }
            } else if observationAvailability.isCurrent {
                firstLine = "\(portText) · 未检测到目标 Mac"
                secondLine = live.link?.isConnected == true
                    ? "端口链路有连接；未枚举到目标设备"
                    : "当前没有目标设备"
            } else {
                firstLine = "\(portText) · 当前观察未知"
                secondLine = "当前读取失败或尚未完成；不认定拔出"
            }
            return PortIdentityProjection(
                firstLine: firstLine,
                secondLine: secondLine,
                accessibilityLabel: "\(firstLine)，\(secondLine)")
        }
        let hasMacEvidence = current.identityResolution != nil
            || current.modelIdentifier != nil
            || current.product.localizedCaseInsensitiveContains("mac")
        if !hasMacEvidence {
            let name = current.product.isEmpty ? nil : current.product
            let firstLine = name.map { "\(portText) · USB 设备已连接 · \($0)" }
                ?? "\(portText) · USB 设备已连接 · 身份待识别"
            return PortIdentityProjection(
                firstLine: firstLine,
                secondLine: "USB 外设，不冒充目标 Mac",
                accessibilityLabel: firstLine + "，USB 外设，不冒充目标 Mac")
        }
        let modeText = current.mode.title
        let resolution = current.identityResolution
        if resolution == nil || resolution?.state == .unknown {
            let firstLine = "\(portText) · \(macHeadline(modeText: current.mode.title))"
            let secondLine = "已确认当前枚举为 Mac；A 型号和年份未确定"
            return PortIdentityProjection(
                firstLine: firstLine,
                secondLine: secondLine,
                accessibilityLabel: "\(firstLine)，\(secondLine)")
        }
        let aText: String
        let yearText: String
        switch resolution?.state {
        case .confirmedCurrent, .uniqueCurrentMatch, .candidates:
            if let resolution,
               !resolution.commonANumbers.isEmpty,
               resolution.commonANumbers.count <= 2 {
                aText = resolution.commonANumbers.joined(separator: "/")
            } else if resolution?.candidateANumbers.isEmpty == false {
                aText = "A 型号待确认"
            } else {
                aText = "A 型号未知"
            }
            if let resolution, resolution.commonYears.count == 1 {
                yearText = String(resolution.commonYears[0])
            } else if let resolution, resolution.candidateYears.count > 1 {
                yearText = "年份待确认"
            } else {
                yearText = "年份未知"
            }
        case .conflict:
            aText = "身份冲突"
            yearText = "A/年份未定"
        case .historicalHintOnly:
            aText = "A 型号未知"
            yearText = "年份未知"
        case .unknown, .none:
            aText = "A 型号未知"
            yearText = "年份未知"
        }
        var status = modeText
        if let resolution {
            switch resolution.state {
            case .uniqueCurrentMatch:
                status += " · 唯一匹配"
            case .candidates:
                let count = max(1, resolution.modelIdentifiers.count)
                status += count > 1 ? " · 候选 \(count)" : " · 候选"
            case .conflict:
                status += " · 身份冲突"
            case .historicalHintOnly:
                status = "当前无身份证据"
            case .confirmedCurrent:
                status += " · 确定"
            case .unknown:
                if resolution.state == .unknown, current.mode == .connected {
                    status = "Mac 设备已连接 · 身份未知"
                }
            }
        }
        let marketing = resolution?.records.map(\.marketingName).first
            .map { L10n.t($0) }
        let accessibility = [portText, aText, yearText, status, marketing]
            .compactMap { $0 }
            .joined(separator: "，")
        return PortIdentityProjection(
            firstLine: "\(portText) · \(aText) · \(yearText)",
            secondLine: status,
            accessibilityLabel: accessibility)
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
        selectedPortDetail(sharedUSB: nil)
    }

    func selectedPortDetail(sharedUSB: MainPortUSBProjection?) -> SelectedPortDetail {
        guard let live = selectedLivePort else {
            return SelectedPortDetail(
                title: "未选择 · 设备详情",
                hasCurrentDevice: false,
                currentHeadline: "当前未识别到设备",
                ecid: nil, serial: nil, lastIdentified: nil,
                connectionSummary: nil, reconnectText: nil,
                technicalRows: [], recentChanges: [])
        }
        return detail(for: live, sharedUSB: sharedUSB)
    }

    func detail(
        for live: LiveHostPort,
        sharedUSB: MainPortUSBProjection? = nil
    ) -> SelectedPortDetail {
        let name = label(for: live)
        let current = observedDevice(for: live)
        let linkConnected = live.link?.isConnected == true
        let hasCurrent = current != nil || sharedUSB != nil
        // Only current-generation evidence can drive the current identity.
        let headline: String
        if let current {
            headline = playbackHeadline(for: current)
        } else if let sharedUSB {
            if sharedUSB.isMacEvidence {
                headline = macHeadline(modeText: sharedUSB.modeText)
            } else if let name = sharedUSB.displayName, !name.isEmpty {
                headline = "USB 设备已连接 · \(name)"
            } else {
                headline = "USB 设备已连接 · 身份待识别"
            }
        } else if observationAvailability.isCurrent {
            headline = "当前未检测到目标设备"
        } else {
            headline = "当前观察未知"
        }
        let last = hasCurrent ? nil : lastIdentifiedText(for: live)
        var rows: [TechnicalDetailRow] = []
        // Identity evidence actually read from IOUSB and fixed data sources.
        if let current {
            rows.append(contentsOf: identityDetailRows(for: current))
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
        if let sharedUSB, current == nil {
            rows.append(TechnicalDetailRow(
                group: "USB 外设",
                name: "当前外设",
                value: sharedUSB.displayName ?? "身份待识别"))
            rows.append(TechnicalDetailRow(
                group: "USB 外设",
                name: "归属证据",
                value: sharedUSB.evidence))
        }
        // Controller/port facts come from the same AppleHPM read as the port row.
        rows.append(TechnicalDetailRow(group: "连接路径", name: "端口控制器", value: live.controller))
        rows.append(TechnicalDetailRow(group: "连接路径", name: "控制器端口",
                                       value: "PortNumber \(live.portNumber) · RID \(live.rid)"))
        if let link = live.link {
            if let location = link.portLocation {
                rows.append(TechnicalDetailRow(
                    group: "连接路径",
                    name: "端口位置",
                    value: location))
            }
            if link.parentPortNumber != nil || link.parentPortTypeDescription != nil {
                let number = link.parentPortNumber.map(String.init) ?? "未知"
                let type = link.parentPortTypeDescription ?? "未知"
                rows.append(TechnicalDetailRow(
                    group: "连接路径",
                    name: "父端口证据",
                    value: "Port \(number) · \(type)"))
            }
            let protocolParts = link.transportsProvisioned.isEmpty
                ? link.transportsActive : link.transportsProvisioned
            if !protocolParts.isEmpty {
                rows.append(TechnicalDetailRow(
                    group: "当前链路", name: "当前协议",
                    value: protocolParts.joined(separator: "、") + "（已配置传输，观察）"))
            }
            rows.append(TechnicalDetailRow(
                group: "当前链路",
                name: "传输支持",
                value: listStateText(link.transportsSupportedState)))
            rows.append(TechnicalDetailRow(
                group: "当前链路",
                name: "传输配置",
                value: listStateText(link.transportsProvisionedState)))
            rows.append(TechnicalDetailRow(
                group: "当前链路",
                name: "传输活动",
                value: listStateText(link.transportsActiveState)))
            for transport in link.activeTransportDetails {
                rows.append(TechnicalDetailRow(
                    group: "当前链路",
                    name: "活动传输 · \(transport.name)",
                    value: activeTransportText(transport)))
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
            if let count = link.overcurrentCount {
                rows.append(TechnicalDetailRow(
                    group: "端口控制器",
                    name: "HPM 过流计数",
                    value: String(count)))
            }
            appendListStateRow(
                to: &rows,
                group: "端口控制器",
                name: "未授权传输",
                state: link.transportsUnauthorized)
            if let required = link.authorizationRequired {
                rows.append(TechnicalDetailRow(
                    group: "端口控制器",
                    name: "授权要求",
                    value: required ? "是" : "否"))
            }
            if let status = link.userAuthorizationStatusDescription {
                rows.append(TechnicalDetailRow(
                    group: "端口控制器",
                    name: "用户授权状态",
                    value: status))
            }
            appendListStateRow(
                to: &rows,
                group: "端口控制器",
                name: "支持功能",
                state: link.featuresSupported)
            appendListStateRow(
                to: &rows,
                group: "端口控制器",
                name: "启用功能",
                state: link.featuresEnabled)
        }
        if let sharedUSB {
            rows.append(TechnicalDetailRow(
                group: "供电与 PD",
                name: "PD 合约",
                value: powerContractText(sharedUSB.powerAttribution)))
        }
        let connectionSummary: String?
        if let location = current?.locationID, !location.isEmpty {
            connectionSummary = L10n.connectionSummary(location: location)
        } else if let sharedUSB {
            connectionSummary = sharedUSB.evidence
        } else if linkConnected && hasCurrent {
            connectionSummary = "端口控制器已确认连接；当前目标身份待读取"
        } else if linkConnected {
            connectionSummary = "端口控制器连接状态存在；当前未检测到目标设备"
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

    /// One presentation-only source for current-device copy shared by the
    /// compact port rows, detail pane, accessibility text and copy summary.
    /// It does not add or change any identity evidence.
    private func playbackHeadline(for device: ObservedDevice) -> String {
        let isMac = device.identityResolution != nil
            || device.modelIdentifier != nil
            || device.product.localizedCaseInsensitiveContains("mac")
        guard isMac else {
            return device.product.isEmpty
                ? "USB 设备已连接 · 身份待识别"
                : "USB 设备已连接 · \(device.product)"
        }
        if device.identityResolution == nil
            || device.identityResolution?.state == .unknown {
            return macHeadline(modeText: device.mode.title)
        }
        return DeviceDisplayIdentity.currentHeadline(
            mode: device.mode,
            resolution: device.identityResolution)
    }

    private func macHeadline(modeText: String) -> String {
        "Mac \(L10n.t(modeText)) · \(L10n.t("型号待确认"))"
    }

    private func listStateText(_ state: HostPortListReadState) -> String {
        switch state {
        case .notProvided:
            return "系统未提供"
        case .provided(let values):
            return values.isEmpty ? "无（空列表）" : values.joined(separator: "、")
        }
    }

    private func appendListStateRow(
        to rows: inout [TechnicalDetailRow],
        group: String,
        name: String,
        state: HostPortListReadState
    ) {
        rows.append(TechnicalDetailRow(
            group: group,
            name: name,
            value: listStateText(state)))
    }

    private func activeTransportText(
        _ transport: HostPortActiveTransport
    ) -> String {
        var parts: [String] = []
        if let rate = transport.dataRateDescription ?? transport.linkRateDescription {
            parts.append(rate)
        }
        if let signaling = transport.superspeedSignalingDescription {
            parts.append("信号 \(signaling)")
        }
        if let role = transport.dataRoleDescription {
            parts.append("数据角色 \(role)")
        }
        if let tunneled = transport.tunneled {
            parts.append("Tunneled \(tunneled ? "是" : "否")")
        }
        if let trm = transport.trmStateDescription {
            parts.append("TRM \(trm)")
        }
        return parts.isEmpty ? "系统未提供附加工程字段" : parts.joined(separator: " · ")
    }

    private func powerContractText(
        _ attribution: PanoramaPowerAttributionResult
    ) -> String {
        switch attribution {
        case .unique(let contract):
            let source = contract.sourceName ?? "USB-PD"
            let voltage = contract.voltageMillivolts.map {
                String(format: "%.3f V", Double($0) / 1_000)
            } ?? "电压未知"
            let current = contract.maxCurrentMilliamps.map {
                String(format: "%.3f A", Double($0) / 1_000)
            } ?? "最大电流未知"
            let power = contract.maxPowerMilliwatts.map {
                String(format: "%.3f W", Double($0) / 1_000)
            } ?? "最大功率未知"
            let limit = contract.isContractLimitOnly
                ? "（合约最大功率上限，非实时功耗）"
                : ""
            return "\(source) · \(voltage) · \(current) · \(power)\(limit)"
        case .conflicting:
            return "归属未证实：存在多个 USB-C 合约"
        case .notUSBCOwned:
            return "仅检测到非 USB-C 供电记录；未挂接"
        case .notProvided:
            return "系统未提供"
        }
    }

    private func identityDetailRows(
        for device: ObservedDevice
    ) -> [TechnicalDetailRow] {
        guard let resolved = device.identityResolution else {
            return [
                TechnicalDetailRow(group: "设备身份", name: "识别状态", value: "未知"),
                TechnicalDetailRow(group: "设备身份", name: "A 型号", value: "未读取"),
                TechnicalDetailRow(group: "设备身份", name: "年份", value: "未读取"),
                TechnicalDetailRow(group: "设备身份", name: "机型标识符", value: "未读取"),
                TechnicalDetailRow(group: "设备身份", name: "ECID", value: device.ecid ?? "未读取"),
                TechnicalDetailRow(
                    group: "设备身份", name: "CPID",
                    value: device.chipID.map { String(format: "0x%04X", $0) } ?? "未读取"),
                TechnicalDetailRow(
                    group: "设备身份", name: "BDID",
                    value: device.boardID.map { String(format: "0x%02X", $0) } ?? "未读取"),
            ]
        }
        let marketingNames: [String]
        if resolved.modelIdentifiers.count == 1,
           let identifier = resolved.modelIdentifiers.first {
            let preferred = TargetModelCatalog.displayName(for: identifier)
            marketingNames = preferred.caseInsensitiveCompare(identifier) == .orderedSame
                ? Array(Set(resolved.records.map(\.marketingName))).sorted()
                : [preferred]
        } else {
            marketingNames = Array(Set(resolved.records.map(\.marketingName))).sorted()
        }
        let category: String
        switch resolved.commonCategory {
        case .notebook: category = "笔记本"
        case .desktop: category = "台式机"
        case .unknown, .none: category = resolved.records.isEmpty ? "未读取" : "待确认"
        }
        let aValue: String
        if !resolved.commonANumbers.isEmpty {
            aValue = resolved.commonANumbers.joined(separator: " / ")
        } else if !resolved.candidateANumbers.isEmpty {
            aValue = "待确认：" + resolved.candidateANumbers.joined(separator: " / ")
        } else {
            aValue = "未读取"
        }
        let yearValue: String
        if resolved.commonYears.count == 1 {
            yearValue = String(resolved.commonYears[0])
        } else if !resolved.candidateYears.isEmpty {
            yearValue = "待确认：" + resolved.candidateYears.map(String.init).joined(separator: " / ")
        } else {
            yearValue = "未读取"
        }
        let bridge = resolved.hardwareRecords.first {
            $0.classification.caseInsensitiveCompare("T2") == .orderedSame
        }
        let bridgeText: String
        if let productType = device.productType,
           productType.lowercased().hasPrefix("ibridge") {
            bridgeText = "\(productType)（当前读取）"
        } else if let bridge {
            bridgeText = "\(bridge.productType)（固定资料匹配）"
        } else if resolved.records.isEmpty {
            bridgeText = "未读取"
        } else if resolved.commonCategory == .desktop &&
                    resolved.records.allSatisfy({ $0.architecture == "apple_silicon" }) {
            bridgeText = "不适用（Apple Silicon 资料）"
        } else {
            bridgeText = "未读取"
        }
        let t2Text: String
        if bridge != nil {
            t2Text = "是（固定资料匹配）"
        } else if !resolved.records.isEmpty &&
                    resolved.records.allSatisfy({ $0.architecture == "apple_silicon" }) {
            t2Text = "否（机型资料）"
        } else if !resolved.records.isEmpty &&
                    resolved.records.allSatisfy({ $0.architecture == "intel" }) {
            t2Text = "未读取 T2 证据"
        } else {
            t2Text = "待确认"
        }
        let stateText = identityStateText(resolved.state)
        var rows: [TechnicalDetailRow] = [
            TechnicalDetailRow(group: "设备身份", name: "识别状态", value: stateText),
            TechnicalDetailRow(
                group: "设备身份", name: "机型",
                value: marketingNames.isEmpty ? "未读取" : marketingNames.joined(separator: " / ")),
            TechnicalDetailRow(group: "设备身份", name: "设备类别", value: category),
            TechnicalDetailRow(
                group: "设备身份", name: "系列",
                value: resolved.commonSeries ?? (resolved.records.isEmpty ? "未读取" : "待确认")),
            TechnicalDetailRow(
                group: "设备身份", name: "尺寸",
                value: resolved.commonSizeLabel ?? (resolved.commonCategory == .desktop ? "—" : "资料未收录")),
            TechnicalDetailRow(
                group: "设备身份", name: "芯片/SoC",
                value: resolved.commonChip ?? (resolved.records.isEmpty ? "未读取" : "待确认")),
            TechnicalDetailRow(group: "设备身份", name: "A 型号", value: aValue),
            TechnicalDetailRow(group: "设备身份", name: "年份", value: yearValue),
            TechnicalDetailRow(
                group: "设备身份", name: "机型标识符",
                value: resolved.modelIdentifiers.isEmpty
                    ? "未读取" : resolved.modelIdentifiers.joined(separator: " / ")),
            TechnicalDetailRow(group: "设备身份", name: "iBridge", value: bridgeText),
            TechnicalDetailRow(group: "设备身份", name: "T2", value: t2Text),
            TechnicalDetailRow(group: "设备身份", name: "ECID", value: device.ecid ?? "未读取"),
            TechnicalDetailRow(
                group: "设备身份", name: "CPID",
                value: device.chipID.map { String(format: "0x%04X", $0) } ?? "未读取"),
            TechnicalDetailRow(
                group: "设备身份", name: "BDID",
                value: device.boardID.map { String(format: "0x%02X", $0) } ?? "未读取"),
            TechnicalDetailRow(
                group: "设备身份", name: "HardwareCode",
                value: device.hardwareCode ?? "未读取"),
            TechnicalDetailRow(
                group: "身份观察", name: "观察代际",
                value: "\(device.connectionGeneration) · \(device.observationID)"),
        ]
        for (index, source) in resolved.sourceSummary.enumerated() {
            rows.append(TechnicalDetailRow(
                group: "识别来源",
                name: "来源 \(index + 1)",
                value: source))
        }
        if !resolved.conflictFields.isEmpty {
            rows.append(TechnicalDetailRow(
                group: "身份冲突",
                name: "冲突字段",
                value: resolved.conflictFields.joined(separator: " / ")))
        }
        if let hint = resolved.historicalHint {
            let formatter = ISO8601DateFormatter()
            rows.append(TechnicalDetailRow(
                group: "历史提示",
                name: "同 ECID 旧记录",
                value: "\(hint.modelIdentifier) · \(formatter.string(from: hint.capturedAt)) · 不参与当前确认"))
        }
        return rows
    }

    private func identityStateText(_ state: MacIdentityState) -> String {
        switch state {
        case .confirmedCurrent: return "确定（当前明确字段）"
        case .uniqueCurrentMatch: return "唯一匹配"
        case .candidates: return "候选"
        case .conflict: return "冲突"
        case .unknown: return "未知"
        case .historicalHintOnly: return "仅历史提示"
        }
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

    func copySummaryText(sharedUSB: MainPortUSBProjection? = nil) -> String {
        let detail = selectedPortDetail(sharedUSB: sharedUSB)
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

enum DeviceObservationAvailability: Equatable {
    case notStarted
    case live
    case failed(String)

    var isCurrent: Bool {
        if case .live = self { return true }
        return false
    }
}

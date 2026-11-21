import Foundation
import Combine
import RestoreLogEngine
import MRAHelperProtocol
import AppKit
import Darwin

// MARK: - Calibration data (editable, JSON, no database)

struct ModelCalibrationEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var model: String
    var layout: String
    var physicalPort: String
    var rid: String
}

struct PortCalibrationEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var physicalPort: String
    var location: String
    var label: String
    var rid: String
    var side: String
    // Optional exact host binding. A PortNumber alone is not a key across
    // AppleHPM controllers, so the controller is retained when known.
    var controller: String?
    var portNumber: Int?

    init(id: UUID = UUID(), physicalPort: String, location: String, label: String,
         rid: String, side: String, controller: String? = nil, portNumber: Int? = nil) {
        self.id = id
        self.physicalPort = physicalPort
        self.location = location
        self.label = label
        self.rid = rid
        self.side = side
        self.controller = controller
        self.portNumber = portNumber
    }
}

struct CalibrationDocument: Codable {
    var models: [ModelCalibrationEntry]
    var ports: [PortCalibrationEntry]
    var selectedPort: String

    static let initial = CalibrationDocument(
        models: [
            .init(model: "Mac14,2", layout: "LEFT_DUAL_DATA", physicalPort: "left2", rid: "1"),
            .init(model: "Mac14,2", layout: "LEFT_DUAL_DATA", physicalPort: "left1", rid: "0"),
            .init(model: "MacBookAir10,1", layout: "LEFT_DUAL_DATA", physicalPort: "left2", rid: "0"),
            .init(model: "MacBookAir10,1", layout: "LEFT_DUAL_DATA", physicalPort: "left1", rid: "1"),
        ],
        ports: [
            .init(physicalPort: "left2", location: "01100000", label: "左侧下方", rid: "1", side: "左侧"),
            .init(physicalPort: "left1", location: "01200000", label: "左侧上方", rid: "0", side: "左侧"),
            .init(physicalPort: "right1", location: "02100000", label: "右侧", rid: "2", side: "右侧"),
        ],
        selectedPort: "left2"
    )
}

@MainActor
final class CalibrationStore: ObservableObject {
    @Published var models: [ModelCalibrationEntry]
    @Published var ports: [PortCalibrationEntry]
    @Published var selectedPort: String
    @Published var saveMessage = ""
    @Published var loadError = ""
    /// Layout actually in use after a tool save / pack import / applied layout.
    /// Independent of the exact verified builtin hit.
    @Published var adoptedOverlay: AdoptedCalibrationOverlay?

    private let url: URL
    let hostModel: String
    let builtInLayout: BuiltInLayout?
    let builtInLayouts: [String: BuiltInLayout]
    let sharedLayoutCandidates: [SharedCandidate]
    let builtInNotes: [String]
    let builtInSourceFile: String?
    let adoptedLayoutFileURL: URL
    let isPersistentStore: Bool

    init() {
        let loaded = BuiltInCalibration.load()
        hostModel = loaded.host
        builtInLayout = loaded.database[loaded.host]
        builtInLayouts = loaded.database
        sharedLayoutCandidates = loaded.shared
        builtInNotes = loaded.notes
        builtInSourceFile = builtInLayout?.sourceFile
        url = AppSupportLocations.calibrationURL()
        adoptedLayoutFileURL = CalibrationToolLauncher.adoptedLayoutURL()
        isPersistentStore = true
        if let data = try? Data(contentsOf: url),
           let doc = try? JSONDecoder().decode(CalibrationDocument.self, from: data) {
            models = doc.models
            ports = doc.ports
            selectedPort = doc.selectedPort
        } else {
            models = CalibrationDocument.initial.models
            ports = CalibrationDocument.initial.ports
            selectedPort = CalibrationDocument.initial.selectedPort
        }
        if migrateLegacyRightPortIfNeeded() {
            save()
        }
        reloadAdoptedOverlayFromDisk()
    }

    /// In-memory store for tests. Writes only to a unique temp file, never the user calibration.
    init(testingDocument document: CalibrationDocument,
         hostModel: String = "TestHost",
         builtInLayout: BuiltInLayout? = nil,
         builtInLayouts: [String: BuiltInLayout]? = nil,
         sharedLayoutCandidates: [SharedCandidate] = [],
         fileURL: URL? = nil) {
        self.hostModel = hostModel
        self.builtInLayout = builtInLayout
        self.builtInLayouts = builtInLayouts ?? builtInLayout.map { [hostModel: $0] } ?? [:]
        self.sharedLayoutCandidates = sharedLayoutCandidates
        self.builtInNotes = []
        self.builtInSourceFile = builtInLayout?.sourceFile
        self.isPersistentStore = false
        if let fileURL {
            self.url = fileURL
            self.adoptedLayoutFileURL = fileURL.deletingLastPathComponent().appendingPathComponent("adopted-layout.json")
        } else {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MRA_022_B_tests_\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.url = directory.appendingPathComponent("calibration.json")
            self.adoptedLayoutFileURL = directory.appendingPathComponent("adopted-layout.json")
        }
        models = document.models
        ports = document.ports
        selectedPort = document.selectedPort
        adoptedOverlay = nil
        _ = migrateLegacyRightPortIfNeeded()
    }

    /// Old right1 / USB location 02100000 rows sometimes stored RID 0, which
    /// is S3 (left, PortNumber 1). Migrate those to RID 2 (S5) and explain why.
    @discardableResult
    func migrateLegacyRightPortIfNeeded() -> Bool {
        var changed = false
        var names: [String] = []
        for index in ports.indices where isLegacyRightRID0(ports[index]) {
            ports[index].rid = "2"
            names.append(ports[index].physicalPort)
            changed = true
        }
        if changed {
            let label = names.joined(separator: "、")
            saveMessage = "已将右侧 02100000 / \(label) 的旧 RID 0 迁移为 RID 2；不会映射到 S3。"
        }
        return changed
    }

    private func isLegacyRightRID0(_ entry: PortCalibrationEntry) -> Bool {
        guard entry.rid == "0" else { return false }
        let location = Self.normalizedLocation(entry.location)
        return entry.physicalPort == "right1" || location == "02100000"
    }

    private static func normalizedLocation(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .uppercased()
    }

    var selectedPortEntry: PortCalibrationEntry? {
        ports.first { $0.physicalPort == selectedPort }
    }

    var selectedModel: ModelCalibrationEntry? {
        guard let port = selectedPortEntry else { return nil }
        // Model calibration is an explicit association. Do not substitute a
        // different port's model merely to fill the panel.
        return models.first { $0.physicalPort == port.physicalPort }
    }

    var builtInStatusText: String {
        if let layout = builtInLayout {
            return L10n.builtInStatus(host: hostModel, layout: layout.displayName, partial: layout.partial, skipped: layout.skippedSlots.joined(separator: ", "))
        }
        return L10n.builtInStatus(host: hostModel, layout: "—", partial: false, skipped: "")
    }

    func builtInSlot(for live: LiveHostPort) -> BuiltInSlot? {
        guard let layout = builtInLayout else { return nil }
        let matches = layout.slots.filter {
            $0.portNumber == live.portNumber && $0.rid == live.rid
        }
        return matches.count == 1 ? matches[0] : nil
    }

    func save() {
        do {
            let doc = CalibrationDocument(models: models, ports: ports, selectedPort: selectedPort)
            let data = try JSONEncoder.pretty.encode(doc)
            try data.write(to: url, options: .atomic)
            saveMessage = "已保存，重启后仍会复用。"
        } catch {
            saveMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    func reload() {
        do {
            let data = try Data(contentsOf: url)
            let doc = try JSONDecoder().decode(CalibrationDocument.self, from: data)
            models = doc.models
            ports = doc.ports
            selectedPort = doc.selectedPort
            saveMessage = "已重新载入已保存的校准。"
            loadError = ""
        } catch {
            saveMessage = ""
            loadError = "尚无可载入的保存文件。"
        }
        reloadAdoptedOverlayFromDisk()
    }

    /// Layout actually adopted for port details. Overlay wins over the builtin exact record.
    var adoptedLayout: BuiltInLayout? { adoptedOverlay?.layout ?? builtInLayout }

    func adoptedSlot(for live: LiveHostPort) -> BuiltInSlot? {
        guard let layout = adoptedLayout else { return nil }
        let matches = layout.slots.filter {
            $0.portNumber == live.portNumber && $0.rid == live.rid
        }
        return matches.count == 1 ? matches[0] : nil
    }

    func sameMoldPair(_ model: String) -> Bool {
        let host = hostModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let other = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !other.isEmpty else { return false }
        return sharedLayoutCandidates.contains { candidate in
            let models = candidate.models.map { $0.lowercased() }
            return models.contains(host.lowercased()) && models.contains(other.lowercased())
        }
    }

    func addHostModel(_ model: String, layoutName: String = "") {
        let identifier = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else {
            saveMessage = "添加模型失败：机型标识为空。"
            return
        }
        if !models.contains(where: { $0.model.caseInsensitiveCompare(identifier) == .orderedSame }) {
            models.append(.init(model: identifier, layout: layoutName, physicalPort: "", rid: ""))
        }
        if adoptedOverlay == nil {
            adoptedOverlay = AdoptedCalibrationOverlay(
                source: .addedModelOnly,
                sourceHostModel: identifier,
                sourceFile: nil,
                displayName: "已添加 \(identifier)",
                layout: BuiltInLayout(displayName: "已添加 \(identifier)", sourceFile: "", slots: [],
                                      partial: true, skippedSlots: [], generatedAt: ""),
                savedAt: ISO8601DateFormatter().string(from: Date()))
            persistAdoptedOverlay()
        }
        saveMessage = "已添加主机模型 \(identifier)。仅添加模型不会将本机标为已精确校准。"
        save()
    }

    @discardableResult
    func importModelPack(from url: URL, as source: AdoptedLayoutSource = .importedPack) throws -> HardwarePreviewReport {
        let report = try HardwarePreviewPack.load(from: url)
        addHostModel(report.hostModel, layoutName: report.displayHint)
        let overlay = report.makeOverlay(source: source)
        adoptedOverlay = overlay
        persistAdoptedOverlay()
        try writeIsolatedPreviewDraft(from: report)
        saveMessage = "已导入 \(report.hostModel) 的模型包（\(url.lastPathComponent)）。导入或套用布局不会自动升级为「机型已精确校准」。"
        return report
    }

    @discardableResult
    func exportModelPack(
        to destination: URL,
        layout suppliedLayout: BuiltInLayout? = nil,
        hostModel suppliedHostModel: String? = nil
    ) throws -> HardwarePreviewReport {
        guard let layout = suppliedLayout ?? adoptedLayout ?? builtInLayout else {
            throw HardwarePreviewPackWriteError.noSlots
        }
        let host: String
        if let suppliedHostModel, !suppliedHostModel.isEmpty {
            host = suppliedHostModel
        } else if let overlay = adoptedOverlay, overlay.layout == layout {
            host = overlay.sourceHostModel
        } else if let bindingHost = layout.slots.compactMap({
            let value = HardwarePreviewReport.parseBinding($0.binding).hostModel
            return value.isEmpty ? nil : value
        }).first {
            host = bindingHost
        } else {
            host = hostModel
        }
        let report = try HardwarePreviewPack.export(
            layout: layout,
            hostModel: host,
            sourceFile: adoptedOverlay?.sourceFile ?? builtInSourceFile,
            to: destination)
        saveMessage = "模型包已导出：\(destination.lastPathComponent)"
        return report
    }

    func applyImportedLayout() {
        guard var overlay = adoptedOverlay, overlay.source == .importedPack else { return }
        overlay.source = .appliedLayout
        adoptedOverlay = overlay
        persistAdoptedOverlay()
        saveMessage = "已套用导入的布局。套用布局不会将本机标为已精确校准。"
    }

    /// Save the in-App slot calibration and make it the effective record
    /// immediately. Only a complete, unskipped calibration is exact.
    func applyInAppCalibration(layout: BuiltInLayout, displayName: String, complete: Bool) {
        let overlay = AdoptedCalibrationOverlay(
            source: complete ? .inAppCalibration : .customLayout,
            sourceHostModel: hostModel,
            sourceFile: nil,
            displayName: displayName,
            layout: layout,
            savedAt: ISO8601DateFormatter().string(from: Date()))
        adoptedOverlay = overlay
        persistAdoptedOverlay()
        saveMessage = complete
            ? "已保存并立即应用本机精确校准（\(displayName)）。"
            : "已保存并应用自定义布局；未完成全部槽位，不标记精确校准。"
    }

    func reloadAdoptedOverlayFromDisk() {
        // Only a usable effective record may override the builtin exact hit.
        // A legacy B.1 draft with no host id / no port mapping is ignored and
        // is not re-imported from the old tool directory.
        if let overlay = readOverlay(at: adoptedLayoutFileURL), overlay.isUsableEffectiveRecord {
            adoptedOverlay = overlay
            return
        }
        adoptedOverlay = nil
    }

    private func persistAdoptedOverlay() {
        guard let overlay = adoptedOverlay else { return }
        do {
            let data = try JSONEncoder.pretty.encode(overlay)
            try data.write(to: adoptedLayoutFileURL, options: .atomic)
        } catch {
            loadError = "无法保存实际采用的布局：\(error.localizedDescription)"
        }
    }

    private func readOverlay(at url: URL) -> AdoptedCalibrationOverlay? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AdoptedCalibrationOverlay.self, from: data)
    }

    private func writeIsolatedPreviewDraft(from report: HardwarePreviewReport) throws {
        guard isPersistentStore else { return }
        let support = CalibrationToolLauncher.previewSupportURL()
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let defaultLibrary = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Yifei.MacFlashAssistantHardwarePreview")
            .standardizedFileURL
        if support.standardizedFileURL.path == defaultLibrary.path {
            throw HardwarePreviewPackError.unreadable
        }
        let payload: [String: Any] = [
            "version": report.version,
            "associations": report.associations,
            "skipped": report.skippedSlots,
            "slot_index": 0,
            "revision_ids": [],
            "slots": report.slots.map { ["slot_id": $0.slotID, "face": $0.face, "label": $0.label] },
            "device_name": report.hostModel,
            "updated_at": report.generatedAt,
            "imported_from": report.sourceFile ?? "",
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: CalibrationToolLauncher.draftURL(), options: .atomic)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
}

// MARK: - Device control (real fixed-action backend; no simulated Helper)

enum ControlFeedbackTone { case neutral, working, success, warning, failure }

/// Stable UI semantics. Business decisions must use this value, never a
/// localized title/detail string.
enum ControlFeedbackSemantic: Equatable { case generic, idle, requestSent }

struct ControlFeedback: Equatable {
    var title: String
    var detail: String
    var tone: ControlFeedbackTone = .neutral
    var semantic: ControlFeedbackSemantic = .generic
    static let idle = ControlFeedback(title: "等待操作", detail: "选择物理端口后可执行设备控制。", semantic: .idle)
}

@MainActor
final class DeviceControlModel: ObservableObject {
    @Published var livePorts: [LiveHostPort] = []
    @Published var selectedLiveKey = ""
    @Published var helperAvailable = false
    @Published var helperStatusText = "正在查询…"
    @Published var helperVersion = ""
    @Published var actionInFlight = false
    @Published var activeAction = ""
    @Published var feedback = ControlFeedback.idle
    @Published var lastActionLog = ""
    @Published var refreshMessage = ""
    @Published var mappingNote = ""
    @Published var observedDevices: [ObservedDevice] = []
    @Published var deviceCards: [ObservedDeviceCard] = []
    @Published var observationMessage = ""
    @Published var historyMessage = ""
    @Published var connectionEvents: [ConnectionChangeEvent] = []
    @Published var brieflyHighlightedPortKeys: Set<String> = []
    @Published private(set) var observationAvailability: DeviceObservationAvailability = .notStarted
    // BEGIN OBSERVATION_HEARTBEAT_DECL
    enum ObservationHeartbeatResult: Equatable, Sendable {
        case pending
        case successChanged
        case successUnchanged
        case failed(reason: String)
    }
    struct ObservationHeartbeatSnapshot: Equatable, Sendable {
        let observationSequence: UInt64
        let completedUptimeNs: UInt64?
        let observationResult: ObservationHeartbeatResult
        let devices: [ObservedDevice]

        func isFreshSuccess(
            atUptimeNs now: UInt64,
            maximumAgeNs: UInt64 = 3_000_000_000
        ) -> Bool {
            guard let completedUptimeNs,
                  now >= completedUptimeNs,
                  now - completedUptimeNs <= maximumAgeNs else {
                return false
            }
            switch observationResult {
            case .successChanged, .successUnchanged:
                return true
            case .pending, .failed:
                return false
            }
        }
    }
    @MainActor
    final class ObservationHeartbeatChannel: ObservableObject {
        @Published private(set) var latest = ObservationHeartbeatSnapshot(
            observationSequence: 0,
            completedUptimeNs: nil,
            observationResult: .pending,
            devices: []
        )

        fileprivate func publish(_ snapshot: ObservationHeartbeatSnapshot) {
            latest = snapshot
        }
    }
    let observationHeartbeat = ObservationHeartbeatChannel()
    // END OBSERVATION_HEARTBEAT_DECL
    private(set) var deviceQueryCount = 0
    var connectionEngine = ConnectionChangeEngine()
    var observationReadHandler: (() -> ObservedDeviceReadResult)?
    var hostPortReadHandler: (() -> HostPortReader.Result)?
    private var observationTask: Task<Void, Never>?
    private var portRefreshTask: Task<Void, Never>?
    private var highlightTask: Task<Void, Never>?
    /// Same-ECID trusted cache: a model identifier is written only from an
    /// explicit descriptor field on that ECID, then reused when a later
    /// observation of the same ECID no longer carries the field.
    private var targetModelByECID: [String: String] = [:]
    private var targetModelSourceByECID: [String: String] = [:]
    private var targetModelCandidateByECID: [String: Bool] = [:]
    private var targetModelCapturedAtByECID: [String: Date] = [:]
    private var identityGenerations: [String: UInt64] = [:]
    private var identityFingerprints: [String: String] = [:]
    private var identityCapturedAtByKey: [String: Date] = [:]
    private var activeIdentityKeys: Set<String> = []
    private var observationIntervalNanoseconds: UInt64 = 1_000_000_000
    nonisolated static let readOnlyPortRefreshIntervalNanoseconds: UInt64 = 3_000_000_000
    private var pendingAction: HelperAction?
    private var pendingActionPort: String?
    private var actionGeneration: UInt64 = 0
    private var inFlightWorkTask: Task<Void, Never>?
    private var activeDFUWatch: DFUObservationWatch?
    private var dfuWatchExpiryTask: Task<Void, Never>?
    private var lastObservationSnapshot: ObservedDeviceReadSnapshot?
    private var observationBatchSequence: UInt64 = 0

    // Test-only boot-options hypothesis. This state is inert unless the
    // MRA_TEST_BOOT_OPTIONS UI calls performTestBootOptionsTriple().
    @Published private(set) var bootOptionsTestActive = false
    @Published private(set) var bootOptionsTestAttempted = 0
    @Published private(set) var bootOptionsTestStatusText = ""
    @Published private(set) var bootOptionsTestCanStop = false
    private var bootOptionsTestGroupID: UUID?
    private var bootOptionsTestTarget: DFUSequenceTarget?
    private var bootOptionsTestTasks: [Task<Void, Never>] = []
    private var bootOptionsTestCompletionTask: Task<Void, Never>?
    private var bootOptionsTestStarted = [false, false, false, false, false]
    private var bootOptionsTestFinished = [false, false, false, false, false]
    private var bootOptionsTestCancelled = [false, false, false, false, false]
    private var bootOptionsTestStopRequested = false
    private var bootOptionsTestStoppedForTarget = false
    private var bootOptionsTestStartedAt = Date()
    private let offlineSampleCards = ProcessInfo.processInfo.environment["MRA_OFFLINE_SAMPLE_CARDS"] == "1"

    let calibration: CalibrationStore
    let portHistory: PortHistoryStore
    private let client = HelperClient()
    private let persistPortSelection: Bool
    private var requestHandler: HelperRequestHandler?
    var sendTimeout: TimeInterval
    var sequenceDelaySeconds: TimeInterval
    var dfuObservationWindowSeconds: TimeInterval = 15
    var dfuObservationMaxBaselineAgeSeconds: TimeInterval = 5

    typealias HelperRequestHandler = @MainActor (HelperAction, String, Int, Int, String) async -> HelperResponse
    nonisolated static let defaultSendTimeout: TimeInterval = 10

    convenience init(calibration: CalibrationStore) {
        self.init(calibration: calibration, startLiveWork: true)
    }

    init(calibration: CalibrationStore,
         livePorts: [LiveHostPort] = [],
         helperAvailable: Bool = false,
         sendTimeout: TimeInterval = DeviceControlModel.defaultSendTimeout,
         sequenceDelaySeconds: TimeInterval = 1.5,
         persistPortSelection: Bool = true,
         startLiveWork: Bool = true,
         requestHandler: HelperRequestHandler? = nil,
         historyURL: URL? = nil) {
        self.calibration = calibration
        self.persistPortSelection = persistPortSelection
        self.sendTimeout = sendTimeout
        self.sequenceDelaySeconds = sequenceDelaySeconds
        self.requestHandler = requestHandler
        let fingerprint = PortHistoryStore.fingerprint(hostModel: calibration.hostModel, layout: calibration.builtInLayout)
        let resolvedHistoryURL: URL
        if let historyURL {
            resolvedHistoryURL = historyURL
        } else if startLiveWork {
            resolvedHistoryURL = PortHistoryStore.defaultURL()
        } else {
            resolvedHistoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("mra-history-\(UUID().uuidString).json")
        }
        self.portHistory = PortHistoryStore(
            fileURL: resolvedHistoryURL,
            hostModel: calibration.hostModel,
            slotMapFingerprint: fingerprint)
        self.historyMessage = portHistory.availabilityMessage
        if startLiveWork {
            refreshPorts()
            startPortRefreshLoop(
                intervalNanoseconds: Self.readOnlyPortRefreshIntervalNanoseconds)
            Task { @MainActor in await self.refreshHelper() }
            if offlineSampleCards {
                installOfflineSampleCards()
            } else {
                startObservation()
            }
        } else {
            self.helperAvailable = helperAvailable
            self.helperStatusText = helperAvailable ? "测试桩 · 已连接" : "测试桩 · 不可用"
            self.observationAvailability = .live
            applyDiscoveredPorts(livePorts, persistCalibration: false)
        }
    }

    deinit {
        observationTask?.cancel()
        portRefreshTask?.cancel()
        dfuWatchExpiryTask?.cancel()
    }

    var selectedLivePort: LiveHostPort? {
        guard let live = livePorts.first(where: { $0.id == selectedLiveKey }) else { return nil }
        return isMapped(live) ? live : nil
    }

    func observedDevice(for live: LiveHostPort) -> ObservedDevice? {
        observedDevices.first { observedPortKey(for: $0) == live.id }
    }

    /// Model shown in a current title. Only current-generation evidence is
    /// accepted; same-ECID cache is exposed as a historical hint elsewhere.
    func identifiedTargetModel(for device: ObservedDevice) -> String? {
        guard let model = device.modelIdentifier else { return nil }
        return TargetModelCatalog.identifier(from: model)
    }

    func identifiedTargetModelSource(for device: ObservedDevice) -> String? {
        device.modelIdentifier == nil ? nil : device.modelSource
    }

    func identifiedTargetModelIsCandidate(for device: ObservedDevice) -> Bool {
        device.modelIdentifier == nil ? false : device.modelIsCandidate
    }

    func resolvedIdentity(for device: ObservedDevice) -> ResolvedMacIdentity? {
        device.identityResolution
    }

    func retainedCard(for live: LiveHostPort) -> ObservedDeviceCard? {
        deviceCards.first { $0.portKey == live.id }
    }

    func observedPortKey(for device: ObservedDevice) -> String? {
        PortAssociationResolver.resolve(locationID: device.locationID,
                                         calibratedPorts: calibration.ports,
                                         livePorts: livePorts)
    }

    func deviceStatusText(for live: LiveHostPort) -> String {
        if let device = observedDevice(for: live) {
            return "当前：\(observedStatusPhrase(for: device))"
        }
        if live.link?.isConnected == true {
            return "已连接"
        }
        if let slot = uniquelyMappedBuiltInSlot(for: live)?.slot {
            let fingerprint = PortHistoryStore.fingerprint(hostModel: calibration.hostModel, layout: calibration.builtInLayout)
            return portHistory.displayStatus(slotID: slot,
                                             hostModel: calibration.hostModel,
                                             fingerprint: fingerprint,
                                             isPresent: false)
        }
        if let card = retainedCard(for: live), !card.isConnected {
            return "当前未识别设备 · 上次 \(card.device.mode.title)"
        }
        return "无设备"
    }

    /// Host ports in a fixed bench order: 左侧上方 → 左侧下方 → 右侧.
    /// Order does not change with online state or recent use.
    var orderedDisplayPorts: [LiveHostPort] {
        matchedLivePorts.sorted { a, b in
            let ra = displayPortRank(a)
            let rb = displayPortRank(b)
            if ra != rb { return ra < rb }
            return a.id < b.id
        }
    }

    func displayPortRank(_ live: LiveHostPort) -> Int {
        let name = uniquelyMappedBuiltInSlot(for: live)?.physicalName
            ?? uniquelyMappedBuiltInSlot(for: live)?.displayLabel
            ?? label(for: live)
        if name == "左侧上方" || name.contains("左侧上方") { return 0 }
        if name == "左侧下方" || name.contains("左侧下方") { return 1 }
        if name == "右侧" || name.hasPrefix("右侧") { return 2 }
        if let built = uniquelyMappedBuiltInSlot(for: live) {
            if built.face == "LEFT" { return 10 + (built.portNumber ?? 99) }
            if built.face == "RIGHT" { return 20 + (built.portNumber ?? 99) }
        }
        return 100
    }

    var operationTargetText: String {
        guard let live = selectedLivePort else { return "操作目标：未选择端口" }
        return "操作目标：\(L10n.localizedPortName(label(for: live)))"
    }

    func selectedDeviceStatus() -> String {
        guard let live = selectedLivePort else { return "无设备" }
        if let card = retainedCard(for: live) {
            let state = card.isConnected ? card.device.mode.title : "已断开（保留记录）"
            return "Mac · \(state)" + (card.device.ecid.map { " · ECID \($0)" } ?? "")
        }
        return "无设备"
    }

    func startObservation() {
        startObservationLoop(intervalNanoseconds: 1_000_000_000)
    }

    private func startObservationLoop(intervalNanoseconds: UInt64) {
        if offlineSampleCards { return }
        observationIntervalNanoseconds = intervalNanoseconds
        observationTask?.cancel()
        observationTask = Task { @MainActor in
            while !Task.isCancelled {
                self.refreshObservedDevices()
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
            }
        }
    }

    private func installOfflineSampleCards() {
        let samples = [
            ("00C0FFEE00000001", ObservedDeviceMode.dfu, "01100000"),
            ("0011223344556677", ObservedDeviceMode.dfu, "02100000"),
            ("00AABBCCDDEEFF00", ObservedDeviceMode.recovery, "03100000"),
        ]
        deviceCards = samples.enumerated().map { index, item in
            let device = ObservedDevice(
                id: "sample:\(index)", ecid: item.0, mode: item.1,
                locationID: item.2,
                product: item.1 == .recovery ? "Apple Mobile Device (Recovery Mode)" : "Apple Mobile Device (DFU Mode)",
                serial: "SAMPLE ECID:\(item.0)")
            return ObservedDeviceCard(
                id: device.id, device: device, portKey: nil,
                portLabel: ["左侧上方", "左侧下方", "右侧"][index],
                lastSeen: Date(), isConnected: true, isSample: true)
        }
        observationMessage = "离线样本：仅用于双/三设备布局与日志隔离检查，不是实机状态。"
    }

    func refreshObservedDevices() {
        deviceQueryCount += 1
        let snapshot: ObservedDeviceReadSnapshot
        if let observationReadHandler {
            let startedAt = Date()
            let result = observationReadHandler()
            let completedAt = Date()
            observationBatchSequence &+= 1
            snapshot = ObservedDeviceReadSnapshot(
                result: result,
                batchID: DispatchTime.now().uptimeNanoseconds
                    ^ observationBatchSequence,
                readStartedAt: startedAt,
                readCompletedAt: completedAt)
        } else {
            snapshot = ObservedDeviceReader.readSnapshot()
        }
        applyObservationResult(
            snapshot.result,
            now: snapshot.readCompletedAt,
            batchID: snapshot.batchID,
            readStartedAt: snapshot.readStartedAt,
            readCompletedAt: snapshot.readCompletedAt)
    }

    func applyObservationResult(
        _ result: ObservedDeviceReadResult,
        now: Date = Date(),
        batchID: UInt64? = nil,
        readStartedAt: Date? = nil,
        readCompletedAt: Date? = nil
    ) {
        let completedAt = readCompletedAt ?? now
        observationBatchSequence &+= 1
        let snapshot = ObservedDeviceReadSnapshot(
            result: result,
            batchID: batchID
                ?? (DispatchTime.now().uptimeNanoseconds
                    ^ observationBatchSequence),
            readStartedAt: readStartedAt ?? completedAt,
            readCompletedAt: completedAt)
        lastObservationSnapshot = snapshot
        switch result {
        case .failed(let reason):
            if observationAvailability != .failed(reason) {
                observationAvailability = .failed(reason)
            }
            _ = connectionEngine.ingest(.failed(), at: Date())
            consumeFailedDFUObservation(snapshot: snapshot)
        case .success(let devices):
            if observationAvailability != .live {
                observationAvailability = .live
            }
            // Apply raw port/device state immediately; model enrichment is
            // display-only and must never block observation or a send.
            applyObservedDevices(
                TargetModelReadOnlyResolver.enrich(devices),
                now: now)
            if TargetModelReadOnlyResolver.shouldStartQuery(for: devices) {
                Task { @MainActor [weak self] in
                    let hints = await TargetModelReadOnlyResolver.refreshHints()
                    self?.applyReadOnlyModelHints(hints)
                }
            }
            consumeDFUObservation(devices: devices, snapshot: snapshot)
        }
        // BEGIN OBSERVATION_HEARTBEAT_PUBLISH
        let heartbeatResult: ObservationHeartbeatResult
        let heartbeatDevices: [ObservedDevice]
        switch result {
        case .success:
            heartbeatDevices = observedDevices
            heartbeatResult = observationHeartbeat.latest.devices == observedDevices
                ? .successUnchanged : .successChanged
        case .failed(let reason):
            heartbeatDevices = []
            heartbeatResult = .failed(reason: reason)
        }
        observationHeartbeat.publish(
            ObservationHeartbeatSnapshot(
                observationSequence: observationHeartbeat.latest.observationSequence &+ 1,
                completedUptimeNs: DispatchTime.now().uptimeNanoseconds,
                observationResult: heartbeatResult,
                devices: heartbeatDevices
            )
        )
        // END OBSERVATION_HEARTBEAT_PUBLISH
    }

    func startObservationForTests(intervalNanoseconds: UInt64) {
        startObservationLoop(intervalNanoseconds: intervalNanoseconds)
    }

    func stopObservationForTests() {
        observationTask?.cancel()
        observationTask = nil
    }

    /// Testable observation intake. Does not send device commands.
    func applyObservedDevices(_ devices: [ObservedDevice], now: Date = Date()) {
        let isolatedDevices = isolateIdentityObservations(devices)
        let annotatedDevices = isolatedDevices.map { device in
            let historical = historicalIdentityHint(for: device)
            let resolved = MacIdentityResolver.resolve(
                device: device,
                historicalHint: historical)
            var copy = device
            copy.identityResolution = resolved
            copy.modelIdentifier = resolved.primaryModelIdentifier
            copy.modelSource = resolved.sourceSummary.isEmpty
                ? nil : resolved.sourceSummary.joined(separator: "\n")
            copy.modelIsCandidate = resolved.state == .candidates
            copy.modelCandidates = (
                resolved.state == .candidates || resolved.state == .conflict
            ) ? resolved.modelIdentifiers : []
            copy.modelFieldsConflict = resolved.state == .conflict
            return copy
        }
        // Remember only validated model identifiers, keyed by the device's
        // ECID. A generic Mac observation later on the same ECID may reuse it.
        for device in annotatedDevices {
            guard let model = device.modelIdentifier,
                  let identifier = TargetModelCatalog.identifier(from: model),
                  let ecid = device.ecid, !ecid.isEmpty else { continue }
            targetModelByECID[ecid.uppercased()] = identifier
            targetModelSourceByECID[ecid.uppercased()] = device.modelSource
            targetModelCandidateByECID[ecid.uppercased()] = device.modelIsCandidate
            targetModelCapturedAtByECID[ecid.uppercased()] = now
        }
        if observedDevices != annotatedDevices {
            observedDevices = annotatedDevices
        }
        var changed = false
        for device in annotatedDevices {
            let key = device.id
            let port = observedPortKey(for: device)
            if let index = deviceCards.firstIndex(where: { $0.id == key }) {
                if deviceCards[index].device != device || !deviceCards[index].isConnected {
                    deviceCards[index].device = device
                    deviceCards[index].portKey = port
                    deviceCards[index].portLabel = port.flatMap { key in
                        livePorts.first(where: { $0.id == key }).map { label(for: $0) }
                    }
                    deviceCards[index].lastSeen = now
                    deviceCards[index].isConnected = true
                    changed = true
                } else if deviceCards[index].portKey != port {
                    deviceCards[index].portKey = port
                    deviceCards[index].portLabel = port.flatMap { key in
                        livePorts.first(where: { $0.id == key }).map { label(for: $0) }
                    }
                    changed = true
                }
            } else {
                deviceCards.append(ObservedDeviceCard(
                    id: key, device: device, portKey: port,
                    portLabel: port.flatMap { key in
                        livePorts.first(where: { $0.id == key }).map { label(for: $0) }
                    },
                    lastSeen: now, isConnected: true))
                changed = true
            }
            observeActionResolution(device: device, portKey: port)
        }
        for index in deviceCards.indices where !annotatedDevices.contains(where: { $0.id == deviceCards[index].id }) {
            if deviceCards[index].isConnected {
                deviceCards[index].isConnected = false
                changed = true
            }
        }
        updatePortHistory(devices: annotatedDevices, now: now)
        recordConnectionChanges(devices: annotatedDevices, now: now)
        if changed {
            observationMessage = "只读设备观察已更新；不会自动开始日志采集。"
        }
        if let live = selectedLivePort,
           let observed = observedDevice(for: live),
           observed.mode == .dfu,
           pendingAction == nil,
           feedback.semantic == .idle || feedback.semantic == .requestSent {
            feedback = ControlFeedback(
                title: "设备当前在 DFU",
                detail: "Mac · DFU" + (observed.ecid.map { " · ECID \($0)" } ?? "") + "；来自被动 USB 观察。",
                tone: .success)
        }
    }

    private func isolateIdentityObservations(
        _ devices: [ObservedDevice]
    ) -> [ObservedDevice] {
        let previousActive = activeIdentityKeys
        var nextActive = Set<String>()
        let isolated = devices.map { device in
            let key = identityEvidenceKey(device)
            let fingerprint = identityFingerprint(device)
            let wasActive = previousActive.contains(key)
            let changed = identityFingerprints[key] != fingerprint
            let generation: UInt64
            let capturedAt: Date
            if wasActive && !changed {
                generation = identityGenerations[key] ?? 1
                capturedAt = identityCapturedAtByKey[key] ?? Date()
            } else {
                generation = max(1, (identityGenerations[key] ?? 0) + 1)
                capturedAt = Date()
            }
            identityGenerations[key] = generation
            identityFingerprints[key] = fingerprint
            identityCapturedAtByKey[key] = capturedAt
            nextActive.insert(key)
            var copy = device
            copy.connectionGeneration = generation
            copy.observationID = "identity:\(key):\(generation)"
            copy.identityCapturedAt = capturedAt
            return copy
        }
        activeIdentityKeys = nextActive
        return isolated
    }

    private func identityEvidenceKey(_ device: ObservedDevice) -> String {
        if let ecid = device.ecid, !ecid.isEmpty {
            return "ecid:\(ecid.uppercased())"
        }
        if let registryID = device.registryID, !registryID.isEmpty {
            return "registry:\(registryID)"
        }
        return "usb:\(device.locationID):\(device.mode.rawValue):\(device.product)"
    }

    private func identityFingerprint(_ device: ObservedDevice) -> String {
        [
            device.ecid ?? "",
            device.registryID ?? "",
            device.locationID,
            device.mode.rawValue,
            device.product,
            device.vendorID.map(String.init) ?? "",
            device.productID.map(String.init) ?? "",
            device.hardwareCode ?? "",
            device.chipID.map(String.init) ?? "",
            device.boardID.map(String.init) ?? "",
        ].joined(separator: "|")
    }

    private func historicalIdentityHint(
        for device: ObservedDevice
    ) -> HistoricalIdentityHint? {
        guard let ecid = device.ecid, !ecid.isEmpty,
              let model = targetModelByECID[ecid.uppercased()] else {
            return nil
        }
        if let current = device.identityResolution?.primaryModelIdentifier
            ?? device.modelIdentifier,
           current.caseInsensitiveCompare(model) == .orderedSame {
            return nil
        }
        return HistoricalIdentityHint(
            modelIdentifier: model,
            capturedAt: targetModelCapturedAtByECID[ecid.uppercased()] ?? Date(),
            source: targetModelSourceByECID[ecid.uppercased()]
                ?? "同 ECID 历史缓存")
    }

    private func applyReadOnlyModelHints(_ hints: [TargetModelReadOnlyResolver.Hint]) {
        guard !hints.isEmpty else { return }
        let enriched = TargetModelReadOnlyResolver.enrich(observedDevices, hints: hints)
        guard enriched != observedDevices else { return }
        observedDevices = enriched
        for device in enriched {
            if let model = device.modelIdentifier,
               let identifier = TargetModelCatalog.identifier(from: model),
               let ecid = device.ecid, !ecid.isEmpty {
                targetModelByECID[ecid.uppercased()] = identifier
                targetModelSourceByECID[ecid.uppercased()] = device.modelSource ?? "同 ECID 历史缓存"
                targetModelCandidateByECID[ecid.uppercased()] = device.modelIsCandidate
                targetModelCapturedAtByECID[ecid.uppercased()] = Date()
            }
        }
        for index in deviceCards.indices {
            if let device = enriched.first(where: { $0.id == deviceCards[index].id }) {
                deviceCards[index].device = device
            }
        }
    }

    private func observeActionResolution(device: ObservedDevice, portKey: String?) {
        guard let pendingAction, let portKey, portKey == pendingActionPort else { return }
        guard pendingAction == .dfu, device.mode == .dfu else { return }
        feedback = ControlFeedback(
            title: "设备已进入 DFU",
            detail: "Mac · DFU" + (device.ecid.map { " · ECID \($0)" } ?? "") + "；来自被动 USB 观察。",
            tone: .success)
        lastActionLog += "\n[\(timeStamp())] observed DFU on \(portKey) ecid=\(device.ecid ?? "—")"
        self.pendingAction = nil
        self.pendingActionPort = nil
    }

    func calibrationEntry(for live: LiveHostPort) -> PortCalibrationEntry? {
        // Exact controller + PortNumber wins. A RID-only match is accepted only
        // when it is unique among live ports; never merge two controllers by
        // PortNumber alone.
        if let exact = calibration.ports.first(where: {
            $0.controller == live.controller && $0.portNumber == live.portNumber
        }) { return exact }
        // Built-in host data wins over legacy RID-only custom rows; otherwise
        // an old row could silently mask the exact host calibration.
        if calibration.builtInSlot(for: live) != nil { return nil }
        let ridMatches = calibration.ports.filter { $0.rid == String(live.rid) }
        let sameRIDLive = livePorts.filter { $0.rid == live.rid }
        if ridMatches.count == 1 && sameRIDLive.count == 1 { return ridMatches[0] }
        return nil
    }

    func label(for live: LiveHostPort) -> String {
        if let custom = calibrationEntry(for: live) { return custom.label }
        if let built = uniquelyMappedBuiltInSlot(for: live) { return built.displayLabel }
        return "控制器 \(live.controller) · 端口 \(live.portNumber)"
    }

    func physicalPortID(for live: LiveHostPort) -> String {
        if let custom = calibrationEntry(for: live) { return custom.physicalPort }
        if let built = uniquelyMappedBuiltInSlot(for: live) { return built.slot }
        return live.id
    }

    func exactCustom(for live: LiveHostPort) -> PortCalibrationEntry? {
        calibration.ports.first {
            $0.controller == live.controller && $0.portNumber == live.portNumber
        }
    }

    func legacyRIDCustom(for live: LiveHostPort) -> PortCalibrationEntry? {
        guard exactCustom(for: live) == nil, calibration.builtInSlot(for: live) == nil else { return nil }
        let matches = calibration.ports.filter { $0.rid == String(live.rid) }
        let sameRIDLive = livePorts.filter { $0.rid == live.rid }
        return matches.count == 1 && sameRIDLive.count == 1 ? matches[0] : nil
    }

    func uniquelyMappedBuiltInSlot(for live: LiveHostPort) -> BuiltInSlot? {
        guard let slot = calibration.builtInSlot(for: live),
              let portNumber = slot.portNumber, let rid = slot.rid else { return nil }
        let same = livePorts.filter { $0.portNumber == portNumber && $0.rid == rid }
        // Ambiguous portNumber+RID across controllers is fail-closed: no slot.
        return same.count == 1 ? slot : nil
    }

    func uniquelyMappedAdoptedSlot(for live: LiveHostPort) -> BuiltInSlot? {
        guard let slot = calibration.adoptedSlot(for: live),
              let portNumber = slot.portNumber, let rid = slot.rid else { return nil }
        let same = livePorts.filter { $0.portNumber == portNumber && $0.rid == rid }
        return same.count == 1 ? slot : nil
    }

    func isCompleteUniqueTarget(_ live: LiveHostPort) -> Bool {
        !live.controller.isEmpty && live.portNumber >= 0 && live.rid >= 0
            && livePorts.filter { $0.controller == live.controller && $0.portNumber == live.portNumber }.count == 1
    }

    func isMapped(_ live: LiveHostPort) -> Bool {
        exactCustom(for: live) != nil
            || uniquelyMappedAdoptedSlot(for: live) != nil
            || uniquelyMappedBuiltInSlot(for: live) != nil
            || legacyRIDCustom(for: live) != nil
    }

    var matchedLivePorts: [LiveHostPort] { livePorts.filter { isMapped($0) } }
    var unmatchedLivePorts: [LiveHostPort] { livePorts.filter { !isMapped($0) } }

    var selectedSourceText: String {
        guard let live = selectedLivePort else { return "未选择端口" }
        if exactCustom(for: live) != nil { return L10n.t("实际采用：自定义校准（controller + PortNumber）") }
        if let overlay = calibration.adoptedOverlay, overlay.source != .builtinExact {
            return "实际采用：\(overlay.sourceSummary)"
        }
        if uniquelyMappedBuiltInSlot(for: live) != nil { return "实际采用：内置主机校准" }
        if legacyRIDCustom(for: live) != nil { return "实际采用：旧式自定义（仅 RID）" }
        return "未匹配"
    }

    var builtInSlotSummary: String {
        guard let port = selectedLivePort else { return "未选择端口" }
        if let custom = calibrationEntry(for: port) {
            return L10n.customCalibrationSummary(label: custom.label, physicalPort: custom.physicalPort)
        }
        if let built = uniquelyMappedBuiltInSlot(for: port) {
            return "内置校准：\(L10n.localizedPortName(built.displayLabel)) · \(built.slot)"
        }
        return "当前端口未匹配内置/自定义校准"
    }

    var selectedCalibration: PortCalibrationEntry? {
        guard let live = selectedLivePort else { return nil }
        return calibrationEntry(for: live)
    }

    var portUsable: Bool {
        guard let live = selectedLivePort else { return false }
        return isCompleteUniqueTarget(live)
    }

    var canControl: Bool { helperAvailable && portUsable && !actionInFlight }
    var canChangePortSelection: Bool { !actionInFlight }
    var recoveryReason: String {
        "恢复模式：向点击时选定的同一主机端口发送 5 次普通重启（0/3/6/9/12 秒，15 秒窗口）；不调用 reboot serial/DVEn。"
    }

    var disabledReason: String {
        if !helperAvailable { return "设备控制调用不可用：\(helperStatusText)" }
        if livePorts.isEmpty { return "未识别到主机物理端口；请刷新端口。" }
        if selectedLivePort == nil { return "请选择唯一的主机物理端口。" }
        if !portUsable { return "端口不可操作：控制器、PortNumber 与 RID 不完整或不唯一。" }
        if actionInFlight { return "请求发送中；本次点击已锁定，不会重复发送。" }
        return ""
    }

    var deviceSummary: String {
        guard let live = selectedLivePort else { return "未识别到设备" }
        return "未识别到设备（无 ECID/DFU 不是进入 DFU 的阻断条件）· \(live.rawTitle)"
    }

    var selectedModelSummary: String {
        if let entry = selectedCalibration,
           let model = calibration.models.first(where: { $0.physicalPort == entry.physicalPort }) {
            return "\(model.model) · \(model.layout) · RID \(model.rid)"
        }
        if let layout = calibration.builtInLayout {
            return L10n.hostModelSummary(host: calibration.hostModel, layout: layout.displayName)
        }
        return "未关联模型校准"
    }

    func refreshPorts() {
        applyPortReadResult(
            hostPortReadHandler?() ?? HostPortReader.readResult(),
            persistCalibration: persistPortSelection)
    }

    private func applyPortReadResult(
        _ result: HostPortReader.Result,
        persistCalibration: Bool
    ) {
        switch result {
        case .success(let ports):
            applyDiscoveredPorts(ports, persistCalibration: persistCalibration)
        case .failed(let reason):
            // A read failure means "unknown now", not an empty host. Preserve
            // the last known port state instead of clearing a usable layout.
            refreshMessage = "主机端口只读刷新失败：\(reason)；保留上次端口状态。"
        }
    }

    private func startPortRefreshLoop(intervalNanoseconds: UInt64) {
        portRefreshTask?.cancel()
        portRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
                guard !Task.isCancelled, let self else { continue }
                await self.refreshPortsIfSafeForReadOnlyPolling()
            }
        }
    }

    /// Periodic state refresh is display-only. It is skipped while an action is
    /// in flight so a background process cannot retarget or overwrite action
    /// state.
    func refreshPortsIfSafeForReadOnlyPolling() async {
        guard !actionInFlight else { return }
        let handler = hostPortReadHandler
        let result = await Task.detached(priority: .utility) {
            handler?() ?? HostPortReader.readResult()
        }.value
        guard !actionInFlight, !Task.isCancelled else { return }
        applyPortReadResult(result, persistCalibration: persistPortSelection)
    }

    func applyDiscoveredPorts(_ ports: [LiveHostPort], persistCalibration: Bool) {
        if livePorts != ports {
            livePorts = ports
        }
        let explicitlyDisconnected = Set(
            ports.filter { port in
                guard let link = port.link else { return false }
                return !link.isConnected
            }.map(\.id))
        if !explicitlyDisconnected.isEmpty {
            // The host-port sample is newer than the cached USB observation.
            // Clear the current device immediately; historical cards remain
            // available as "last seen" records.
            let hasDisconnectedObservedDevice = observedDevices.contains { device in
                observedPortKey(for: device).map(explicitlyDisconnected.contains) == true
            }
            if hasDisconnectedObservedDevice {
                observedDevices.removeAll { device in
                    guard let key = observedPortKey(for: device) else { return false }
                    return explicitlyDisconnected.contains(key)
                }
            }
            for index in deviceCards.indices
            where deviceCards[index].isConnected
                && deviceCards[index].portKey.map(explicitlyDisconnected.contains) == true {
                deviceCards[index].isConnected = false
            }
        }
        let matched = livePorts.filter { isMapped($0) && isCompleteUniqueTarget($0) }
        if !actionInFlight {
            let resolved = resolvePortSelection(preferred: calibration.selectedPort, matched: matched)
            let newSelection = resolved ?? ""
            if selectedLiveKey != newSelection {
                selectedLiveKey = newSelection
            }
            if let resolved, persistCalibration, calibration.selectedPort != resolved {
                calibration.selectedPort = resolved
                calibration.save()
            }
            if let resolved, !resolved.isEmpty, feedback.semantic == .idle,
               let selected = livePorts.first(where: { $0.id == resolved }),
               isCompleteUniqueTarget(selected), portUsable {
                let ready = ControlFeedback(title: "目标端口已就绪",
                                            detail: L10n.readyPortDetail(label(for: selected)),
                                            tone: .neutral)
                if feedback != ready {
                    feedback = ready
                }
            }
        }
        let newRefreshMessage: String
        if livePorts.isEmpty {
            newRefreshMessage = "未识别到主机 AppleHPM 端口。"
        } else {
            newRefreshMessage = "已读取 \(livePorts.count) 个主机物理端口；控制器+PortNumber+RID 唯一定位。"
        }
        if refreshMessage != newRefreshMessage {
            refreshMessage = newRefreshMessage
        }
        var newMappingNote = ""
        if calibration.builtInLayout == nil {
            newMappingNote = "主机 \(calibration.hostModel) 没有匹配的内置校准；可选择自定义端口校准。"
        } else if calibration.builtInLayout?.partial == true {
            newMappingNote = "内置布局为部分校准；未关联槽位不自动推断。"
        }
        let builtMatches = matched.compactMap { calibration.builtInSlot(for: $0) }
        let duplicated = Dictionary(grouping: builtMatches, by: { $0.slot }).filter { $0.value.count > 1 }
        if !duplicated.isEmpty {
            newMappingNote = "内置布局映射冲突：\(duplicated.keys.sorted().joined(separator: ", "))；请检查端口，不自动执行。"
        }
        if calibration.builtInLayout != nil {
            let legacy = calibration.ports.filter { $0.controller == nil && $0.portNumber == nil }
            if !legacy.isEmpty {
                newMappingNote += (newMappingNote.isEmpty ? "" : "\n") + L10n.legacyRIDNote(legacy.count)
            }
        }
        if !unmatchedLivePorts.isEmpty {
            newMappingNote += (newMappingNote.isEmpty ? "" : "\n") + L10n.unmatchedPortsNote(unmatchedLivePorts.map { "RID \($0.rid)" }.joined(separator: ", "))
        }
        if selectedLiveKey.isEmpty && !livePorts.isEmpty && !actionInFlight {
            newMappingNote += (newMappingNote.isEmpty ? "" : "\n") + "未自动选择端口：没有唯一可确认的端口，需要人工确认。不会按列表顺序猜测。"
        }
        if mappingNote != newMappingNote {
            mappingNote = newMappingNote
        }
    }

    func resolvePortSelection(preferred: String, matched: [LiveHostPort]) -> String? {
        if let preferredLive = matched.first(where: { $0.id == preferred }),
           matched.filter({ $0.id == preferred }).count == 1 {
            return preferredLive.id
        }
        if !preferred.isEmpty {
            if let legacy = calibration.ports.first(where: { $0.physicalPort == preferred }) {
                let exact = matched.filter {
                    $0.controller == legacy.controller && $0.portNumber == legacy.portNumber
                }
                if exact.count == 1 { return exact[0].id }
                if legacy.controller == nil && legacy.portNumber == nil,
                   let rid = Int(legacy.rid) {
                    let byRID = matched.filter { $0.rid == rid }
                    if byRID.count == 1 { return byRID[0].id }
                }
            }
            // Preferred was set but missed: do not replace with the first remaining port.
            return nil
        }
        if let layout = calibration.builtInLayout {
            var uniqueHits: [LiveHostPort] = []
            for slot in layout.slots {
                guard let portNumber = slot.portNumber, let rid = slot.rid else { continue }
                let hits = matched.filter { $0.portNumber == portNumber && $0.rid == rid }
                if hits.count == 1 { uniqueHits.append(hits[0]) }
            }
            let uniqueIDs = Set(uniqueHits.map(\.id))
            if uniqueIDs.count == 1, let only = uniqueHits.first { return only.id }
        }
        if matched.count == 1 { return matched[0].id }
        return nil
    }

    func selectPort(_ live: LiveHostPort) {
        if actionInFlight {
            // Fail-closed: do not retarget or overwrite in-flight feedback (C-011).
            lastActionLog += "\n[\(timeStampMillis())] ignored port selection during in-flight action; frozen target unchanged"
            return
        }
        guard isMapped(live), isCompleteUniqueTarget(live) else {
            feedback = ControlFeedback(title: "未选择端口",
                                       detail: "端口身份不完整或不唯一，已拒绝选择。不会按列表顺序猜测。",
                                       tone: .warning)
            return
        }
        selectedLiveKey = live.id
        calibration.selectedPort = live.id
        if persistPortSelection { calibration.save() }
        feedback = ControlFeedback(title: portSwitchFeedbackTitle(for: live),
                                   detail: "采集会话不会被清空；执行时使用当前端口/控制器/RID。")
    }

    func refreshHelper() async {
        helperStatusText = "正在查询…"
        let hadHelperWarning = feedback.title == "设备控制调用不可用"
        let response: HelperResponse
        if let requestHandler {
            response = await requestHandler(.status, "", -1, -1, UUID().uuidString)
        } else {
            response = await client.request(action: .status)
        }
        helperAvailable = response.ok && response.reason == "READY"
        helperVersion = response.helperVersion
        helperStatusText = helperAvailable
            ? "已连接 · \(response.helperVersion)"
            : "不可用 · \(humanReason(response.reason))"
        if !helperAvailable {
            feedback = ControlFeedback(
                title: "设备控制调用不可用",
                detail: helperStatusText,
                tone: .warning)
        } else if hadHelperWarning {
            // Helper management can recover the connection while the window is
            // open. Do not leave the old red "Helper unavailable" card until
            // the operator happens to click another control.
            feedback = .idle
        }
    }

    func performDFU() { performDFUSequence() }
    func performReboot() { performSingle(.reboot, title: "重启") }
    func performRecoveryMode() {
        // Product entry for the Owner-verified 1720 five-reboot sequence.
        // Keep the 1720 implementation unchanged: 0/3/6/9/12, same frozen
        // physical target, five attempts, stop-pending behavior.
        performTestBootOptionsTriple()
    }

    func performRecovery() { performRecoveryMode() }

    /// Test-only hypothesis: three ordinary reboot requests to the clicked
    /// physical port at 0, 1.5, and 3.0 seconds. No serial/DVEn command.
    /// Running the group again does not open a second group.
    func performTestBootOptionsTriple() {
        if bootOptionsTestActive {
            feedback = ControlFeedback(
                title: "测试组运行中",
                detail: "本次点击不会另开一组；等待五次尝试结束或停止尚未发起的请求。",
                tone: .working)
            return
        }
        guard canControl, let live = selectedLivePort, isCompleteUniqueTarget(live) else {
            feedback = ControlFeedback(
                title: "未发送",
                detail: disabledReason.isEmpty ? "主机侧无法唯一定位所选物理端口；未换口、未广播。" : disabledReason,
                tone: .warning)
            return
        }
        let target = DFUSequenceTarget(controller: live.controller,
                                       portNumber: live.portNumber, rid: live.rid)
        let groupID = UUID()
        let generation = beginActionFlight()
        activeAction = "恢复模式"
        pendingAction = nil
        pendingActionPort = live.id
        bootOptionsTestGroupID = groupID
        bootOptionsTestTarget = target
        bootOptionsTestStartedAt = Date()
        bootOptionsTestAttempted = 0
        bootOptionsTestActive = true
        bootOptionsTestCanStop = true
        bootOptionsTestStopRequested = false
        bootOptionsTestStoppedForTarget = false
        bootOptionsTestStarted = [false, false, false, false, false]
        bootOptionsTestFinished = [false, false, false, false, false]
        bootOptionsTestCancelled = [false, false, false, false, false]
        bootOptionsTestStatusText = "已尝试 0/5"
        lastActionLog = "[\(timeStampMillis())] test-boot group=\(groupID) target=\(target.controller)/\(target.portNumber)/\(target.rid) schedule=0,3,6,9,12s window=15s"
        feedback = ControlFeedback(
            title: "恢复模式进行中",
            detail: "固定同一端口，0/3/6/9/12 秒各一次普通重启；15 秒窗口结束；不调用 reboot serial/DVEn，不自动宣告恢复。",
            tone: .working)
        let offsets: [TimeInterval] = [0, 3, 6, 9, 12]
        let count = bootOptionsTestStarted.count
        bootOptionsTestTasks = (0..<count).map { index in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wait = self.bootOptionsTestStartedAt.addingTimeInterval(offsets[index]).timeIntervalSinceNow
                if wait > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                }
                guard self.bootOptionsTestActive,
                      self.bootOptionsTestGroupID == groupID,
                      self.isCurrentAction(generation) else { return }
                if Task.isCancelled {
                    self.bootOptionsMarkCancelled(index, groupID: groupID)
                    return
                }
                await self.bootOptionsDispatch(index: index, groupID: groupID, generation: generation)
            }
        }
        bootOptionsTestCompletionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let deadline = self.bootOptionsTestStartedAt.addingTimeInterval(15)
            let wait = deadline.timeIntervalSinceNow
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
            guard self.bootOptionsTestActive,
                  self.bootOptionsTestGroupID == groupID,
                  self.isCurrentAction(generation) else { return }
            self.bootOptionsFinalizeIfDone(groupID: groupID, deadlineReached: true)
        }
    }

    /// Stop only children that have not reached the backend. In-flight calls
    /// are allowed to finish; no cancellation is sent to the device.
    func stopPendingBootOptionsTest() {
        guard bootOptionsTestActive, let groupID = bootOptionsTestGroupID else { return }
        bootOptionsTestStopRequested = true
        for index in 0..<bootOptionsTestStarted.count where !bootOptionsTestStarted[index]
            && !bootOptionsTestFinished[index]
            && !bootOptionsTestCancelled[index] {
            bootOptionsTestTasks.indices.contains(index) ? bootOptionsTestTasks[index].cancel() : ()
            bootOptionsTestCancelled[index] = true
        }
        bootOptionsTestCanStop = false
        bootOptionsTestStatusText = "已停止尚未发起的请求"
        lastActionLog += "\n[\(timeStampMillis())] test-boot stop-pending group=\(groupID)"
        bootOptionsFinalizeIfDone(groupID: groupID)
    }

    private func bootOptionsTargetStillUnique(_ target: DFUSequenceTarget) -> Bool {
        livePorts.filter {
            $0.controller == target.controller
                && $0.portNumber == target.portNumber
                && $0.rid == target.rid
        }.count == 1
    }

    private func bootOptionsDispatch(index: Int, groupID: UUID, generation: UInt64) async {
        guard bootOptionsTestActive,
              bootOptionsTestGroupID == groupID,
              isCurrentAction(generation) else { return }
        if Task.isCancelled {
            bootOptionsMarkCancelled(index, groupID: groupID)
            return
        }
        guard let target = bootOptionsTestTarget else { return }
        guard bootOptionsTargetStillUnique(target) else {
            bootOptionsTestStoppedForTarget = true
            bootOptionsTestStatusText = "已停止：主机侧无法唯一定位原端口"
            lastActionLog += "\n[\(timeStampMillis())] test-boot STOP target-not-unique \(target.controller)/\(target.portNumber)/\(target.rid)"
            for i in 0..<bootOptionsTestStarted.count where !bootOptionsTestStarted[i] && !bootOptionsTestFinished[i] && !bootOptionsTestCancelled[i] {
                bootOptionsTestTasks[i].cancel()
                bootOptionsTestCancelled[i] = true
            }
            bootOptionsTestCanStop = false
            bootOptionsFinalizeIfDone(groupID: groupID)
            return
        }
        bootOptionsTestStarted[index] = true
        bootOptionsTestAttempted += 1
        bootOptionsTestStatusText = "已尝试 \(bootOptionsTestAttempted)/\(bootOptionsTestStarted.count)"
        bootOptionsTestCanStop = (0..<bootOptionsTestStarted.count).contains { !bootOptionsTestStarted[$0] && !bootOptionsTestFinished[$0] && !bootOptionsTestCancelled[$0] }
        let requestID = UUID().uuidString
        let dispatchedAt = Date()
        lastActionLog += "\n[\(timeStampMillis(dispatchedAt))] test-boot attempt=\(index + 1)/\(bootOptionsTestStarted.count) backend_start request=\(requestID) target=\(target.controller)/\(target.portNumber)/\(target.rid)"
        let response = await sendRequest(action: .reboot,
                                         controller: target.controller,
                                         portNumber: target.portNumber,
                                         rid: target.rid,
                                         requestID: requestID)
        guard bootOptionsTestActive,
              bootOptionsTestGroupID == groupID,
              isCurrentAction(generation) else { return }
        bootOptionsTestFinished[index] = true
        bootOptionsTestCanStop = (0..<bootOptionsTestStarted.count).contains { !bootOptionsTestStarted[$0] && !bootOptionsTestFinished[$0] && !bootOptionsTestCancelled[$0] }
        let receipt = BackendActionReceipt.parse(stdout: response.stdout)
        lastActionLog += "\n[\(timeStampMillis())] test-boot attempt=\(index + 1)/\(bootOptionsTestStarted.count) result request=\(requestID) dispatch=\(response.dispatchTruth) exit=\(response.exitCode.map(String.init) ?? "—") status=\(receipt?.status ?? "UNKNOWN") reason=\(response.reason) stdout=\(response.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) stderr=\(response.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        bootOptionsFinalizeIfDone(groupID: groupID)
    }

    private func bootOptionsMarkCancelled(_ index: Int, groupID: UUID) {
        guard bootOptionsTestActive, bootOptionsTestGroupID == groupID, !bootOptionsTestStarted[index] else { return }
        bootOptionsTestCancelled[index] = true
        bootOptionsFinalizeIfDone(groupID: groupID)
    }

    private func bootOptionsFinalizeIfDone(groupID: UUID, deadlineReached: Bool = false) {
        guard bootOptionsTestActive, bootOptionsTestGroupID == groupID else { return }
        let count = bootOptionsTestStarted.count
        let done = (0..<count).allSatisfy { bootOptionsTestFinished[$0] || bootOptionsTestCancelled[$0] }
        guard done else { return }
        if !deadlineReached && !bootOptionsTestStopRequested && !bootOptionsTestStoppedForTarget {
            let deadline = bootOptionsTestStartedAt.addingTimeInterval(15)
            if Date() < deadline { return }
        }
        bootOptionsTestActive = false
        bootOptionsTestCanStop = false
        bootOptionsTestTasks = []
        bootOptionsTestCompletionTask?.cancel()
        bootOptionsTestCompletionTask = nil
        actionInFlight = false
        activeAction = ""
        inFlightWorkTask = nil
        pendingAction = nil
        pendingActionPort = nil
        if bootOptionsTestStoppedForTarget {
            bootOptionsTestStatusText = "已停止：主机侧无法唯一定位原端口"
            feedback = ControlFeedback(
                title: "已停止：主机侧无法唯一定位原端口",
                detail: "已尝试 \(bootOptionsTestAttempted)/\(count)；未换口、未广播。",
                tone: .warning)
        } else if bootOptionsTestAttempted == count {
            bootOptionsTestStatusText = "恢复模式请求已完成"
            feedback = ControlFeedback(
                title: "恢复模式请求已完成",
                detail: "已尝试 \(count)/\(count)；15 秒窗口结束；固定原端口；不自动宣告已进入恢复模式。",
                tone: .warning)
        } else {
            bootOptionsTestStatusText = "已停止尚未发起的请求"
            feedback = ControlFeedback(
                title: "已停止尚未发起的请求",
                detail: "已尝试 \(bootOptionsTestAttempted)/\(count)；未发起的请求已取消，未换口、未广播。",
                tone: .warning)
        }
    }

    private func performDFUSequence() {
        guard canControl, let live = selectedLivePort, isCompleteUniqueTarget(live) else {
            feedback = ControlFeedback(title: "未发送", detail: disabledReason.isEmpty ? "端口身份不完整或不唯一，已拒绝发送。" : disabledReason, tone: .warning)
            return
        }
        let generation = beginActionFlight()
        activeAction = "进入 DFU"
        pendingAction = .dfu
        pendingActionPort = live.id
        let sequenceID = UUID().uuidString
        let target = DFUSequenceTarget(controller: live.controller,
                                       portNumber: live.portNumber, rid: live.rid)
        let started = Date()
        beginDFUObservationWatch(for: live, startedAt: started)
        let plannedSecond = started.addingTimeInterval(sequenceDelaySeconds)
        feedback = ControlFeedback(title: "双发序列进行中",
                                   detail: "\(label(for: live)) · RID \(live.rid)；固定两次，不换口、不重试。",
                                   tone: .working)
        lastActionLog = "[\(timeStampMillis(started))] sequence=\(sequenceID) start=\(timeStampMillis(started)) plannedSecond=\(timeStampMillis(plannedSecond)) target=\(target.controller)/\(target.portNumber)/\(target.rid)"
        inFlightWorkTask = Task { @MainActor in
            let timeoutTask = startSendTimeoutWatch(generation: generation)
            let historySlot = uniquelyMappedBuiltInSlot(for: live)?.slot
            let runner = DFUSequenceRunner(delaySeconds: sequenceDelaySeconds) { requestID, frozenTarget in
                let response = await self.sendRequest(action: .dfu,
                                       controller: frozenTarget.controller,
                                       portNumber: frozenTarget.portNumber,
                                       rid: frozenTarget.rid,
                                       requestID: requestID)
                if response.ok && response.dispatchTruth == "REQUEST_SENT", let historySlot {
                    await MainActor.run {
                        self.portHistory.recordDFUSend(slotID: historySlot, operationID: sequenceID, sentAt: Date())
                    }
                }
                return response
            }
            let result = await runner.run(sequenceID: sequenceID, target: target, startedAt: started)
            timeoutTask.cancel()
            guard isCurrentAction(generation) else {
                lastActionLog += "\n[\(timeStampMillis())] ignored late response req1=\(result.first.requestID) dispatch=\(result.first.response.dispatchTruth) req2=\(result.second.requestID) dispatch=\(result.second.response.dispatchTruth)"
                return
            }
            actionInFlight = false
            activeAction = ""
            let first = result.first
            let second = result.second
            noteDFUWatchDispatches(first: first, second: second)
            lastActionLog += "\n" + dfuAttemptDiagnostic("req1", event: first)
            lastActionLog += "\n" + dfuAttemptDiagnostic("req2", event: second)
            let attempted = [first.attempted, second.attempted].filter { $0 }.count
            let backendCalls = [first.backendCalled, second.backendCalled].filter { $0 }.count
            let confirmed = [first.backendConfirmedSubmit, second.backendConfirmedSubmit].filter { $0 }.count
            let reasons = [first.response.reason, second.response.reason]
                .filter { !$0.isEmpty }.joined(separator: " / ")
            let observedDFU = observedDevice(for: live)?.mode == .dfu
            if observedDFU {
                feedback = ControlFeedback(title: "观察到 DFU",
                                           detail: "被动 USB 观察已看到 DFU；这不等于恢复/刷机成功。",
                                           tone: .success)
            } else {
                let title: String
                if attempted == 0 {
                    title = "未尝试"
                } else if confirmed > 0 {
                    title = "后端确认提交 · 结果未确认"
                } else if backendCalls > 0 && [first, second].contains(where: { $0.backendReceipt?.reason == "DFU_COMMAND_FAILED" }) {
                    title = "DFU 命令返回失败 · 设备结果未确认"
                } else if backendCalls > 0 {
                    title = "已尝试 · 后端未确认提交"
                } else {
                    title = "已尝试 · 结果未知"
                }
                feedback = ControlFeedback(
                    title: title,
                    detail: "已尝试 \(attempted)/2；后端调用 \(backendCalls)/2；后端确认提交 \(confirmed)/2；不认定设备成功。\(reasons)",
                    tone: attempted > 0 ? .warning : .failure)
            }
            pendingAction = nil
            pendingActionPort = nil
            if let watch = activeDFUWatch,
               watch.evaluation.result != .requestSent {
                reconcileDFUWatchFeedback(
                    operationID: watch.operationID,
                    evaluation: watch.evaluation)
            }
        }
    }

    private func dfuAttemptDiagnostic(_ label: String, event: DFUSequenceEvent) -> String {
        let receipt = event.backendReceipt
        let status = receipt?.status ?? "UNKNOWN"
        let send = receipt?.sendPerformed.map { $0 ? "true" : "false" } ?? "UNKNOWN"
        let exit = event.response.exitCode.map(String.init) ?? "—"
        return "[\(timeStampMillis(event.dispatchedAt))] \(label)=\(event.requestID) attempted=\(event.attempted) backend_called=\(event.backendCalled) confirmed_submit=\(event.backendConfirmedSubmit) dispatch=\(event.response.dispatchTruth) exit=\(exit) status=\(status) send_performed=\(send) reason=\(event.response.reason) stdout=\(event.response.stdout) stderr=\(event.response.stderr)"
    }

    private func performSingle(_ action: HelperAction, title: String) {
        guard canControl, let live = selectedLivePort, isCompleteUniqueTarget(live) else {
            feedback = ControlFeedback(title: "未发送", detail: disabledReason.isEmpty ? "端口身份不完整或不唯一，已拒绝发送。" : disabledReason, tone: .warning)
            return
        }
        let generation = beginActionFlight()
        activeAction = title
        pendingAction = action
        pendingActionPort = live.id
        let requestID = UUID().uuidString
        let frozen = DFUSequenceTarget(controller: live.controller,
                                       portNumber: live.portNumber, rid: live.rid)
        feedback = ControlFeedback(title: "请求发送中",
                                   detail: "\(label(for: live)) · RID \(live.rid)；只发送一次，不重试。",
                                   tone: .working)
        lastActionLog = "[\(timeStampMillis())] \(title) → controller \(frozen.controller) port \(frozen.portNumber) RID \(frozen.rid) request=\(requestID)"
        inFlightWorkTask = Task { @MainActor in
            let timeoutTask = startSendTimeoutWatch(generation: generation)
            let response = await sendRequest(action: action,
                                             controller: frozen.controller,
                                             portNumber: frozen.portNumber,
                                             rid: frozen.rid,
                                             requestID: requestID)
            timeoutTask.cancel()
            guard isCurrentAction(generation) else {
                lastActionLog += "\n[\(timeStampMillis())] ignored late response request=\(requestID) dispatch=\(response.dispatchTruth) reason=\(response.reason)"
                return
            }
            actionInFlight = false
            activeAction = ""
            let reason = humanReason(response.reason)
            if response.ok && response.dispatchTruth == "REQUEST_SENT" {
                feedback = ControlFeedback(title: "请求已发送 · 结果未确认",
                                           detail: "Helper 已提交请求；设备是否进入目标模式未确认。\(reason)",
                                           tone: .warning, semantic: .requestSent)
                lastActionLog += "\n[\(timeStampMillis())] request=\(requestID) dispatch=REQUEST_SENT exit=\(response.exitCode.map(String.init) ?? "—")"
            } else if action == .recovery {
                // Helper maps a non-zero backend exit with empty stderr to
                // BACKEND_FAILED. The backend's phase/reason is in stdout; use
                // it instead of treating every non-zero exit as NOT_DISPATCHED.
                let diagnosis = RecoveryFailurePresentation.make(for: response)
                feedback = ControlFeedback(title: diagnosis.title,
                                           detail: diagnosis.sentence,
                                           tone: diagnosis.isDispatched == false ? .failure : .warning)
                lastActionLog += "\n[\(timeStampMillis())] \(diagnosis.technical)"
                pendingAction = nil
                pendingActionPort = nil
            } else {
                feedback = ControlFeedback(title: "未发送/失败", detail: reason, tone: .failure)
                lastActionLog += "\n[\(timeStampMillis())] request=\(requestID) dispatch=NOT_DISPATCHED reason=\(response.reason)"
                pendingAction = nil
                pendingActionPort = nil
            }
        }
    }

    private func beginActionFlight() -> UInt64 {
        invalidateDFUObservationWatch()
        actionGeneration += 1
        actionInFlight = true
        return actionGeneration
    }

    private func isCurrentAction(_ generation: UInt64) -> Bool {
        generation == actionGeneration
    }

    private func startSendTimeoutWatch(generation: UInt64) -> Task<Void, Never> {
        let timeout = sendTimeout
        return Task { @MainActor in
            let nanos = UInt64(max(timeout, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            unlockAfterSendTimeout(generation: generation)
        }
    }

    private func unlockAfterSendTimeout(generation: UInt64) {
        guard isCurrentAction(generation), actionInFlight else { return }
        terminateDFUObservationWatch()
        actionGeneration += 1
        actionInFlight = false
        activeAction = ""
        pendingAction = nil
        pendingActionPort = nil
        inFlightWorkTask?.cancel()
        inFlightWorkTask = nil
        feedback = ControlFeedback(title: "请求超时，结果未确认",
                                   detail: "Helper 未在时限内返回；未认定设备成功。界面已解锁，可再次操作。迟到的响应将被忽略。尚未发出的后续发送已取消。",
                                   tone: .failure)
        lastActionLog += "\n[\(timeStampMillis())] SEND_TIMEOUT generation=\(generation) unlocked pending-second-cancelled-if-any"
    }

    private func beginDFUObservationWatch(
        for live: LiveHostPort,
        startedAt: Date
    ) {
        let baseline = currentDFUBaseline(for: live)
        activeDFUWatch = DFUObservationWatch(
            operationID: UUID(),
            targetPortKey: live.id,
            clickedAt: startedAt.timeIntervalSinceReferenceDate,
            baseline: baseline,
            windowSeconds: dfuObservationWindowSeconds,
            maxBaselineAgeSeconds: dfuObservationMaxBaselineAgeSeconds)
    }

    private func currentDFUBaseline(
        for live: LiveHostPort
    ) -> DFUObservationBatch? {
        guard let snapshot = lastObservationSnapshot else { return nil }
        let isValid: Bool
        switch snapshot.result {
        case .success:
            isValid = true
        case .failed:
            isValid = false
        }
        let matching = observedDevices.filter {
            observedPortKey(for: $0) == live.id
        }
        let distinctECIDs = Set(
            matching.compactMap(\.ecid).map {
                $0.uppercased()
            })
        guard matching.count <= 1, distinctECIDs.count <= 1 else {
            return DFUObservationBatch(
                batchID: snapshot.batchID,
                readStartedAt: snapshot.readStartedAt.timeIntervalSinceReferenceDate,
                readCompletedAt: snapshot.readCompletedAt.timeIntervalSinceReferenceDate,
                isValid: false,
                portKey: live.id,
                mode: .unknown,
                ecid: nil,
                registryID: nil)
        }
        let device = matching.first
        return DFUObservationBatch(
            batchID: snapshot.batchID,
            readStartedAt: snapshot.readStartedAt.timeIntervalSinceReferenceDate,
            readCompletedAt: snapshot.readCompletedAt.timeIntervalSinceReferenceDate,
            isValid: isValid,
            portKey: live.id,
            mode: device.map { dfuObservationMode($0.mode) } ?? .absent,
            ecid: device?.ecid,
            registryID: device?.registryID)
    }

    private func consumeDFUObservation(
        devices: [ObservedDevice],
        snapshot: ObservedDeviceReadSnapshot
    ) {
        guard var watch = activeDFUWatch else { return }
        var batches = devices.map { device in
            DFUObservationBatch(
                batchID: snapshot.batchID,
                readStartedAt: snapshot.readStartedAt.timeIntervalSinceReferenceDate,
                readCompletedAt: snapshot.readCompletedAt.timeIntervalSinceReferenceDate,
                isValid: true,
                portKey: observedPortKey(for: device),
                mode: dfuObservationMode(device.mode),
                ecid: device.ecid,
                registryID: device.registryID)
        }
        if !batches.contains(where: { $0.portKey == watch.targetPortKey }) {
            batches.append(DFUObservationBatch(
                batchID: snapshot.batchID,
                readStartedAt: snapshot.readStartedAt.timeIntervalSinceReferenceDate,
                readCompletedAt: snapshot.readCompletedAt.timeIntervalSinceReferenceDate,
                isValid: true,
                portKey: watch.targetPortKey,
                mode: .absent,
                ecid: nil,
                registryID: nil))
        }
        for batch in batches {
            _ = watch.observe(batch)
        }
        activeDFUWatch = watch
        if watch.evaluation.result != .requestSent {
            reconcileDFUWatchFeedback(
                operationID: watch.operationID,
                evaluation: watch.evaluation)
        }
    }

    private func consumeFailedDFUObservation(
        snapshot: ObservedDeviceReadSnapshot
    ) {
        guard var watch = activeDFUWatch else { return }
        _ = watch.observe(DFUObservationBatch(
            batchID: snapshot.batchID,
            readStartedAt: snapshot.readStartedAt.timeIntervalSinceReferenceDate,
            readCompletedAt: snapshot.readCompletedAt.timeIntervalSinceReferenceDate,
            isValid: false,
            portKey: watch.targetPortKey,
            mode: .unknown,
            ecid: nil,
            registryID: nil))
        activeDFUWatch = watch
    }

    private func noteDFUWatchDispatches(
        first: DFUSequenceEvent,
        second: DFUSequenceEvent
    ) {
        guard var watch = activeDFUWatch else { return }
        let events = [first, second].filter(\.attempted)
        guard !events.isEmpty else {
            let evaluation = watch.finalize()
            activeDFUWatch = watch
            reconcileDFUWatchFeedback(
                operationID: watch.operationID,
                evaluation: evaluation)
            activeDFUWatch = nil
            return
        }
        for event in events {
            _ = watch.noteDispatch(
                requestID: event.requestID,
                dispatchedAt: event.dispatchedAt.timeIntervalSinceReferenceDate,
                confirmedSubmit: event.backendConfirmedSubmit,
                responseAt: event.finishedAt.timeIntervalSinceReferenceDate)
        }
        activeDFUWatch = watch
        if watch.evaluation.result != .requestSent {
            reconcileDFUWatchFeedback(
                operationID: watch.operationID,
                evaluation: watch.evaluation)
        }
        if let earliest = events.map(\.dispatchedAt).min() {
            scheduleDFUWatchExpiry(
                operationID: watch.operationID,
                earliestDispatch: earliest)
        }
    }

    private func scheduleDFUWatchExpiry(
        operationID: UUID,
        earliestDispatch: Date
    ) {
        dfuWatchExpiryTask?.cancel()
        let deadline = earliestDispatch.addingTimeInterval(
            dfuObservationWindowSeconds)
        dfuWatchExpiryTask = Task { @MainActor [weak self] in
            let delay = max(0, deadline.timeIntervalSinceNow)
            if delay > 0 {
                try? await Task.sleep(
                    nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            self?.expireDFUObservationWatch(operationID: operationID)
        }
    }

    private func expireDFUObservationWatch(operationID: UUID) {
        guard var watch = activeDFUWatch,
              watch.operationID == operationID else { return }
        let evaluation = watch.expireIfNeeded(
            at: Date().timeIntervalSinceReferenceDate)
        activeDFUWatch = watch
        reconcileDFUWatchFeedback(
            operationID: operationID,
            evaluation: evaluation)
        activeDFUWatch = nil
        dfuWatchExpiryTask = nil
    }

    private func invalidateDFUObservationWatch() {
        dfuWatchExpiryTask?.cancel()
        dfuWatchExpiryTask = nil
        activeDFUWatch = nil
    }

    private func terminateDFUObservationWatch(at date: Date = Date()) {
        guard var watch = activeDFUWatch else { return }
        _ = watch.noteActionTerminal(
            at: date.timeIntervalSinceReferenceDate)
        activeDFUWatch = nil
        dfuWatchExpiryTask?.cancel()
        dfuWatchExpiryTask = nil
    }

    private func reconcileDFUWatchFeedback(
        operationID: UUID,
        evaluation: DFUEvaluation
    ) {
        guard activeDFUWatch?.operationID == operationID else { return }
        switch evaluation.result {
        case .requestSent:
            feedback = ControlFeedback(
                title: "请求已发送 · 观察中",
                detail: "只读观察进行中；尚未确认设备进入 DFU。只读确认不会解锁按钮或改变发送链。",
                tone: .working,
                semantic: .requestSent)
        case .observed:
            feedback = ControlFeedback(
                title: "观察到 DFU · 结果未确认",
                detail: "只读观察看到 DFU；本次命令因果或设备身份尚未确认。",
                tone: .warning)
        case .confirmed where evaluation.scope == .sameDevice:
            if evaluation.currentTargetState == .dfu {
                let observedECID = selectedLivePort
                    .flatMap { observedDevice(for: $0) }?.ecid
                let ecid = observedECID.map { "（ECID \($0)）" } ?? ""
                feedback = ControlFeedback(
                    title: "已确认进入 DFU · 同一设备",
                    detail: "本次请求后，同一设备已进入 DFU\(ecid)；这不代表 Restore 成功。",
                    tone: .success)
            } else {
                feedback = ControlFeedback(
                    title: "已确认进入 DFU · 同一设备",
                    detail: "本次操作已确认进入 DFU；当前端口未观察到 DFU。",
                    tone: .success)
            }
        case .confirmed:
            feedback = ControlFeedback(
                title: "已确认该端口出现 DFU · 设备身份未确认",
                detail: "本次请求后，该物理端口出现 DFU；具体设备身份未确认。",
                tone: .success)
        case .unknown:
            feedback = ControlFeedback(
                title: "结果未确认 · 观察窗口结束",
                detail: "未获得足以确认本次操作进入 DFU 的完整证据。",
                tone: .warning)
        }
    }

    private func dfuObservationMode(
        _ mode: ObservedDeviceMode
    ) -> DFUObservationMode {
        switch mode {
        case .dfu: return .dfu
        case .recovery: return .recovery
        case .connected: return .connected
        case .unknown: return .unknown
        }
    }


    private func recordConnectionChanges(devices: [ObservedDevice], now: Date) {
        var ports: [String: LocatedPortState] = [:]
        for live in matchedLivePorts {
            let dev = devices.first { observedPortKey(for: $0) == live.id }
            // Controller-confirmed connection is present even when USB /
            // Configurator has not read a target identity yet.
            let present = (live.link?.isConnected ?? false) || dev != nil
            ports[live.id] = LocatedPortState(
                portKey: live.id,
                portLabel: label(for: live),
                present: present,
                mode: dev?.mode,
                ecid: dev?.ecid)
        }
        var unlocated: [UnlocatedDeviceState] = []
        for dev in devices where observedPortKey(for: dev) == nil {
            unlocated.append(UnlocatedDeviceState(id: dev.id, mode: dev.mode, ecid: dev.ecid))
        }
        let snapshot = PortConnectionSnapshot(isValid: true, ports: ports, unlocated: unlocated)
        let result = connectionEngine.ingest(snapshot, at: now)
        if connectionEvents != connectionEngine.events {
            connectionEvents = connectionEngine.events
        }
        let selected = selectedLiveKey
        let highlight = Set(result.changedPortKeys.filter { $0 != selected })
        if !highlight.isEmpty {
            brieflyHighlightedPortKeys = highlight
            highlightTask?.cancel()
            highlightTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                self.brieflyHighlightedPortKeys = []
            }
        }
    }

    private func updatePortHistory(devices: [ObservedDevice], now: Date) {

        let fingerprint = PortHistoryStore.fingerprint(hostModel: calibration.hostModel, layout: calibration.builtInLayout)
        portHistory.pruneAssociations(at: now)

        var boundByPort: [String: ObservedDevice] = [:]
        var unbound: [ObservedDevice] = []
        for device in devices {
            if let key = observedPortKey(for: device) {
                boundByPort[key] = device
            } else {
                unbound.append(device)
            }
        }

        var associatedBySlot: [String: ObservedDevice] = [:]
        if let pending = portHistory.singleValidAssociation(at: now) {
            let slotLive = livePorts.first { uniquelyMappedBuiltInSlot(for: $0)?.slot == pending.slotID }
            let alreadyBound = slotLive.flatMap { boundByPort[$0.id] }
            let conflictingOther = boundByPort.contains { key, device in
                uniquelyMappedBuiltInSlot(forLiveKey: key)?.slot != pending.slotID && device.mode == .dfu
            }
            let eligibleUnbound = unbound.filter {
                portHistory.isEligibleHistoryObservation(product: $0.product, mode: $0.mode) && $0.mode == .dfu
            }
            if alreadyBound == nil && !conflictingOther && eligibleUnbound.count == 1 {
                associatedBySlot[pending.slotID] = eligibleUnbound[0]
            }
        }

        for live in livePorts {
            guard let slot = uniquelyMappedBuiltInSlot(for: live)?.slot else { continue }
            let present = boundByPort[live.id] ?? associatedBySlot[slot]
            if let device = present,
               portHistory.isEligibleHistoryObservation(product: device.product, mode: device.mode) {
                _ = portHistory.updateIfEligible(
                    slotID: slot, product: device.product, mode: device.mode, ecid: device.ecid,
                    seenAt: now, controller: live.controller, portNumber: live.portNumber, rid: live.rid,
                    hostModel: calibration.hostModel, fingerprint: fingerprint)
            } else {
                portHistory.preserveOnDisconnect(slotID: slot)
            }
        }
        if historyMessage != portHistory.availabilityMessage {
            historyMessage = portHistory.availabilityMessage
        }
    }

    private func uniquelyMappedBuiltInSlot(forLiveKey key: String) -> BuiltInSlot? {
        guard let live = livePorts.first(where: { $0.id == key }) else { return nil }
        return uniquelyMappedBuiltInSlot(for: live)
    }

    private func sendRequest(action: HelperAction, controller: String, portNumber: Int,
                             rid: Int, requestID: String) async -> HelperResponse {
        if let requestHandler {
            return await requestHandler(action, controller, portNumber, rid, requestID)
        }
        return await client.request(action: action, controller: controller,
                                    portNumber: portNumber, rid: rid, requestID: requestID)
    }

    private func timeStampMillis(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }

    private func humanReason(_ code: String) -> String {
        switch code {
        case "READY": return "Helper 就绪"
        case "HELPER_UNAVAILABLE": return "Helper 未安装或未运行"
        case "CALLER_NOT_AUTHORIZED": return "调用者签名未获许可"
        case "PORT_RID_MISMATCH": return "当前端口/RID 与 Helper 读取结果不一致"
        case "INVALID_TARGET": return "端口/RID 参数无效"
        case "BACKEND_MISSING": return "精确 RID 后端缺失"
        case "BACKEND_SPAWN_FAILED": return "精确 RID 后端启动失败"
        case "BACKEND_FAILED": return "精确 RID 后端执行失败"
        case "SEND_TIMEOUT": return "发送超时，结果未确认"
        default: return code.isEmpty ? "未知结果" : code
        }
    }

    private func timeStamp() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}

// MARK: - Capture panel: real RLM CaptureCoordinator, offline simulated backend

enum CaptureBackendMode {
    case simulated
    case process
    var title: String {
        switch self {
        case .simulated: return "离线模拟采集"
        case .process: return "真实日志采集"
        }
    }
}

enum LogImportState: Equatable {
    case idle
    case analyzing
    case completed
    case failed

    var title: String {
        switch self {
        case .idle: return "未导入"
        case .analyzing: return "分析中"
        case .completed: return "分析完成"
        case .failed: return "分析失败"
        }
    }
}

struct CaptureSaveResult {
    var zipURL: URL?
    var logURL: URL?
    var zipError: String?
    var logError: String?
    var finalized: ExportResult?
    var message: String {
        if zipURL != nil && logURL != nil {
            return "证据包和原始日志均已保存。"
        }
        if zipURL != nil {
            return "证据包已保存；原始日志保存失败。"
        }
        if logURL != nil {
            return "原始日志已保存；证据包保存失败。"
        }
        return "保存失败；采集会话仍保留，可重试。"
    }
}

@MainActor
final class CaptureModel: ObservableObject {
    @Published var state: CaptureState = .idle
    @Published var logs: [String] = []
    @Published var byteCount = 0
    @Published var lineCount = 0
    @Published var durationText = CaptureDisplayFormat.duration(seconds: 0)
    @Published var elapsedSeconds = 0
    @Published var saveMessage = ""
    @Published var captureError = ""
    @Published var savedZipURL: URL?
    @Published var savedLogURL: URL? // retained only so older tests compile if referenced; 0.2.3 no longer writes a sidecar .log
    @Published var saveSheetRequested = false
    @Published var exportProgressText = ""
    @Published var exportFraction: Double? = nil
    @Published var previewTruncated = false
    @Published var previewNotice = "仅预览末尾，保存完整日志"
    @Published var lastExportStats: ZipIOStats?
    @Published var lastExportManifest: SessionZipManifest?
    @Published var exportBaseName: String = ""
    @Published var isExporting = false
    @Published var isDiscarding = false
    @Published var previewLines: [String] = []
    @Published var previewVisible = false
    @Published var monitorState = "OFF"
    @Published var isListening = false
    @Published var monitorError = ""
    @Published var exportProgress: LogExportProgress?
    @Published var isRawExporting = false
    @Published var isPackageExporting = false
    @Published var lastRawExportURL: URL?
    @Published var lastEvidencePackageURL: URL?
    @Published var importState: LogImportState = .idle
    @Published var importedFileName = ""
    @Published var importedFileSize = ""
    @Published var importedAnalysis: ImportedDiagnosticAnalysis?
    @Published var importStatus = "选择历史日志进行只读分析；不会修改原文件。"
    @Published var importedRawURL: URL?
    @Published var importedDiagnosticURL: URL?
    @Published var includeTimeline = true {
        didSet { UserDefaults.standard.set(includeTimeline, forKey: "MRA.log.packageIncludeTimeline") }
    }
    @Published var includeDiagnosticSummary = true {
        didSet { UserDefaults.standard.set(includeDiagnosticSummary, forKey: "MRA.log.packageIncludeSummary") }
    }
    @Published var includeUpdaterOutput = true {
        didSet { UserDefaults.standard.set(includeUpdaterOutput, forKey: "MRA.log.packageIncludeUpdaterOutput") }
    }

    var pasteboard: FilePasteboard = AppKitFilePasteboard()
    var appCDHashProvider: () -> String? = { AppCodeSignature.currentCDHash() }
    var appVersionOverride: String? = nil
    var zip64Threshold: UInt64 = ZipStoreWriter.defaultZip64Threshold
    var exportThreadProbe: (@Sendable (LogExportOperation, Bool) -> Void)?
    var restoreMonitorStartProbe: (() throws -> Void)?
    private var exportGeneration: UInt64 = 0
    private var discardRequested = false
    let workspacePreferences: LogWorkspacePreferences

    private let store: EvidenceStore
    private let coordinator: CaptureCoordinator
    let backendMode: CaptureBackendMode
    private var sessionID: UUID?
    private var rawURL: URL?
    private var monitorTask: Task<Void, Never>?
    private var finalized: ExportResult?
    private var finalizedSource: SessionPackageSource?
    private var saveTask: Task<Void, Never>?
    private var finalizeTask: Task<SessionPackageSource, Error>?
    private var restoreMonitor: RestoreStartMonitor?
    private var preferencesCancellable: AnyCancellable?
    private var exportCancellationToken: ExportCancellationToken?
    private var lastProgressPublish = Date.distantPast
    private var lastPublishedStage: LogExportStage?
    private let projection = IncrementalLogProjection()
    private var importTask: Task<Void, Never>?

    // Test-only seams for exercising partial-save reporting. Production leaves
    // both nil and uses the RLM builders directly.
    var packageBuildOverride: ((SessionPackageSource, URL, String) throws -> URL)?
    var rawExportOverride: ((URL, URL, String, UUID, Bool, String) async throws -> URL)?

    init(
        root suppliedRoot: URL? = nil,
        backendMode: CaptureBackendMode = .simulated,
        preferences suppliedPreferences: LogWorkspacePreferences? = nil,
        activateAutoMonitor: Bool = false
    ) {
        let root: URL
        if let suppliedRoot {
            root = suppliedRoot
        } else if let defaultRoot = try? EvidenceStore.defaultRoot() {
            root = defaultRoot
        } else {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("MRA_DeviceCapture_Prototype/Sessions", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = EvidenceStore(root: root)
        // Offline prototype: the coordinator is real; the producer is simulated.
        // The production path is ProcessLogCaptureBackend(), intentionally not used here.
        self.backendMode = backendMode
        let preferences = suppliedPreferences ?? LogWorkspacePreferences()
        workspacePreferences = preferences
        let backend: LogCaptureBackend = (backendMode == .process)
            ? ProcessLogCaptureBackend()
            : SimulatedLogCaptureBackend()
        coordinator = CaptureCoordinator(backend: backend, store: store)
        let defaults = UserDefaults.standard
        includeTimeline = defaults.object(forKey: "MRA.log.packageIncludeTimeline") as? Bool ?? true
        includeDiagnosticSummary = defaults.object(forKey: "MRA.log.packageIncludeSummary") as? Bool ?? true
        includeUpdaterOutput = defaults.object(forKey: "MRA.log.packageIncludeUpdaterOutput") as? Bool ?? true
        preferencesCancellable = preferences.$autoMonitorEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                Task { @MainActor [weak self] in
                    self?.applyAutoMonitorPreference(enabled)
                }
            }
        if activateAutoMonitor && preferences.autoMonitorEnabled {
            Task { @MainActor [weak self] in
                self?.applyAutoMonitorPreference(true)
            }
        }
    }

    deinit {
        monitorTask?.cancel()
        saveTask?.cancel()
        importTask?.cancel()
        restoreMonitor?.stop()
    }

    var isCapturing: Bool {
        state == .starting || state == .recording || state == .stopping
    }

    var canSave: Bool {
        state == .finalizing || state == .savedPartial || state == .savedVerified || state == .interrupted
    }

    /// A finished, not-yet-exported session may be packed into one ZIP.
    var canExportZIP: Bool { canSave && savedZipURL == nil && !isExporting }

    var exportDisabledReason: String {
        if savedZipURL != nil { return "" }
        if isExporting { return "正在导出…" }
        if canExportZIP { return "" }
        return "停止采集后可导出"
    }

    var canCopyExportedZip: Bool { savedZipURL != nil }
    var canRevealExportedZip: Bool { savedZipURL != nil }

    var copyDisabledReason: String {
        savedZipURL == nil ? "导出后可复制" : ""
    }

    var savedZipFileName: String { savedZipURL?.lastPathComponent ?? "" }

    var captureMeterText: String {
        let sizeText = CaptureDisplayFormat.dataSize(bytes: byteCount)
        if isCapturing {
            return "\(CaptureDisplayFormat.duration(seconds: elapsedSeconds)) · \(sizeText)"
        }
        if canSave && savedZipURL == nil {
            return "已停止 · \(CaptureDisplayFormat.duration(seconds: elapsedSeconds)) · \(sizeText)"
        }
        if savedZipURL != nil {
            return "已导出 · \(CaptureDisplayFormat.duration(seconds: elapsedSeconds)) · \(sizeText)"
        }
        return "\(CaptureDisplayFormat.duration(seconds: elapsedSeconds)) · \(sizeText)"
    }

    var stateText: String {
        switch state {
        case .idle: return "空闲"
        case .starting: return "正在启动采集"
        case .recording: return backendMode == .process ? "采集中（真实日志）" : "采集中（离线模拟）"
        case .stopping: return "正在停止"
        case .finalizing: return "已停止，等待保存"
        case .savedVerified: return "已保存并校验"
        case .savedPartial: return "已保存（部分证据）"
        case .interrupted: return "采集被中断"
        case .failed: return "采集失败"
        }
    }

    var stateTone: ControlFeedbackTone {
        switch state {
        case .recording: return .success
        case .starting, .stopping, .finalizing: return .working
        case .failed, .interrupted: return .failure
        case .savedPartial, .savedVerified, .idle: return .neutral
        }
    }

    func setAutoMonitorEnabled(_ enabled: Bool) {
        workspacePreferences.autoMonitorEnabled = enabled
        applyAutoMonitorPreference(enabled)
    }

    private func applyAutoMonitorPreference(_ enabled: Bool) {
        if enabled {
            startRestoreMonitorIfNeeded()
        } else {
            stopRestoreMonitor()
            monitorState = "OFF"
        }
    }

    private func startRestoreMonitorIfNeeded() {
        guard workspacePreferences.autoMonitorEnabled,
              restoreMonitor == nil,
              state.acceptsNewSession,
              state != .finalizing else { return }
        if let restoreMonitorStartProbe {
            do {
                try restoreMonitorStartProbe()
                isListening = true
                monitorState = "WAITING_FOR_RESTORE"
                monitorError = ""
            } catch {
                isListening = false
                monitorState = "FAILED"
                monitorError = "监听启动失败：\(error.localizedDescription)。手动采集仍可用。"
            }
            return
        }
        let monitor = RestoreStartMonitor(
            onStart: { [weak self] context in
                Task { @MainActor [weak self] in
                    self?.handleRestoreStarted(preCaptureContext: context)
                }
            },
            onFailure: { [weak self] reason in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.restoreMonitor?.stop()
                    self.restoreMonitor = nil
                    self.isListening = false
                    self.monitorState = "FAILED"
                    self.monitorError = "监听失败：\(reason)。手动采集仍可用。"
                    self.workspacePreferences.autoMonitorEnabled = false
                }
            })
        do {
            try monitor.start()
            restoreMonitor = monitor
            isListening = monitor.isRunning
            monitorError = ""
            monitorState = isListening ? "WAITING_FOR_RESTORE" : "STARTING"
        } catch {
            restoreMonitor = nil
            isListening = false
            monitorState = "FAILED"
            monitorError = "监听启动失败：\(error.localizedDescription)。手动采集仍可用。"
            workspacePreferences.autoMonitorEnabled = false
        }
    }

    private func stopRestoreMonitor() {
        restoreMonitor?.stop()
        restoreMonitor = nil
        isListening = false
    }

    private func restartRestoreMonitorAfterDecision() {
        guard workspacePreferences.autoMonitorEnabled else { return }
        startRestoreMonitorIfNeeded()
    }

    private func handleRestoreStarted(preCaptureContext: String) {
        guard workspacePreferences.autoMonitorEnabled else { return }
        switch state {
        case .idle, .savedPartial, .savedVerified, .interrupted, .failed:
            stopRestoreMonitor()
            monitorState = "TRIGGERED"
            start(preCaptureContext: preCaptureContext, automatic: true)
        case .starting, .recording, .stopping, .finalizing:
            monitorError = "检测到 Restore，但当前已有采集会话；未重复启动。"
        }
    }

    var needsTerminationDecision: Bool {
        isExporting || isCapturing || state == .finalizing ||
            (canSave && savedLogURL == nil)
    }

    func shutdownForTermination(save: Bool) async {
        let rawLogDirectoryPath = workspacePreferences.rawLogDirectory
        let defaultBaseName = workspacePreferences.defaultFileBaseName
        let requestedBaseName = exportBaseName
        stopRestoreMonitor()
        if isExporting {
            exportCancellationToken?.cancel()
            saveTask?.cancel()
            await saveTask?.value
        }
        if isCapturing, let id = sessionID {
            _ = try? await coordinator.stopCapture(sessionID: id)
            state = .finalizing
        }
        guard let id = sessionID else { return }
        if save {
            if savedLogURL == nil {
                do {
                    let source = try await ensureFinalized(
                        displayName: requestedBaseName.isEmpty
                            ? defaultBaseName
                            : requestedBaseName)
                    guard let raw = source.record.files.first(where: { $0.role == "raw-log" }) else {
                        throw SessionZipExportError.missingRaw
                    }
                    let destination = URL(
                        fileURLWithPath: rawLogDirectoryPath,
                        isDirectory: true)
                    let base = requestedBaseName.isEmpty
                        ? defaultBaseName
                        : requestedBaseName
                    let result = try await Task.detached(priority: .userInitiated) {
                        try RawLogExporter.export(
                            RawLogExportRequest(
                                sourceURL: source.rawURL,
                                destinationDirectory: destination,
                                baseName: base,
                                sessionID: source.record.sessionID,
                                isPartial: source.record.captureState != .savedVerified,
                                expectedSourceSHA256: raw.sha256))
                    }.value
                    savedLogURL = result.url
                    lastRawExportURL = result.url
                } catch {
                    saveMessage = "退出前保存失败：\(error.localizedDescription)"
                }
            }
        } else {
            _ = try? await coordinator.discard(sessionID: id)
            resetForNewSession()
        }
    }

    func start(preCaptureContext: String? = nil, automatic: Bool = false) {
        guard !isCapturing, state != .finalizing else { return }
        stopRestoreMonitor()
        if state == .savedPartial || state == .savedVerified || state == .interrupted {
            // A new session is allowed only after the previous one has been
            // explicitly saved and its data is no longer at risk.
            resetForNewSession()
        }
        state = .starting
        captureError = ""
        saveMessage = ""
        savedZipURL = nil
        savedLogURL = nil
        exportBaseName = defaultBaseName
        isExporting = false
        exportProgressText = ""
        exportFraction = nil
        exportProgress = nil
        logs.removeAll()
        previewLines.removeAll()
        lineCount = 0
        byteCount = 0
        durationText = CaptureDisplayFormat.duration(seconds: 0)
        elapsedSeconds = 0
        monitorTask?.cancel()
        discardRequested = false
        Task { @MainActor in
            do {
                let config = CaptureConfig(
                    outputDirectory: store.root,
                    profile: .restore014APrimaryV2,
                    updaterWatchRoot: FileManager.default.temporaryDirectory,
                    ecidHint: nil,
                    preCaptureContext: preCaptureContext,
                    limits: .standard
                )
                let handle = try await coordinator.beginCapture(config: config)
                self.sessionID = handle.sessionID
                self.rawURL = URL(fileURLWithPath: handle.rawLogPath)
                if self.discardRequested {
                    await self.completeDiscardAfterStop()
                    return
                }
                self.state = .recording
                self.monitorState = automatic ? "CAPTURING_AUTOMATIC" : "OFF"
                self.startMonitor()
            } catch {
                if self.discardRequested {
                    self.state = .idle
                    self.captureError = "停止失败：采集未能启动，未删除任何会话。\(error)"
                    self.isDiscarding = false
                    self.discardRequested = false
                    return
                }
                self.state = .failed
                self.captureError = "采集启动失败：\(error)"
                if self.workspacePreferences.autoMonitorEnabled {
                    self.startRestoreMonitorIfNeeded()
                }
            }
        }
    }

    func stop() {
        guard isCapturing, let id = sessionID else { return }
        monitorTask?.cancel()
        monitorTask = nil
        state = .stopping
        Task { @MainActor in
            do {
                _ = try await coordinator.stopCapture(sessionID: id)
                self.state = .finalizing
                self.refreshStatusOnce()
                self.reloadVisibleLog()
                self.saveMessage = "采集已停止。请选择保存原始日志或丢弃；证据包必须另行明确导出。"
            } catch {
                self.state = .failed
                self.captureError = "停止失败：\(error)"
            }
        }
    }

    /// There is an unsaved current session that can be voided. Never true
    /// during an in-flight export, and never after a ZIP has been saved.
    var canDiscardUnsavedSession: Bool {
        if isExporting || isDiscarding { return false }
        if savedZipURL != nil || savedLogURL != nil { return false }
        if isCapturing { return true }
        if sessionID != nil && (canSave || state == .failed) { return true }
        return false
    }

    var discardButtonTitle: String {
        if isCapturing || state == .stopping { return "作废并停止" }
        return "作废本次日志"
    }

    /// Stop (if needed), wait until this session's backend has exited and the
    /// log is no longer growing, then delete only this unsaved session.
    /// One click, no confirmation. A failed stop never deletes or claims success.
    func discardUnsavedSession() {
        guard canDiscardUnsavedSession else { return }
        discardRequested = true
        isDiscarding = true
        captureError = ""
        saveMessage = ""
        monitorTask?.cancel()
        monitorTask = nil
        if isCapturing {
            state = .stopping
        }
        Task { @MainActor in
            await self.completeDiscardAfterStop()
        }
    }

    private func completeDiscardAfterStop() async {
        // Wait briefly if start() has not yet published a session.
        if sessionID == nil && discardRequested {
            for _ in 0..<50 {
                if sessionID != nil || state == .failed || state == .idle { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        guard let id = sessionID else {
            isDiscarding = false
            discardRequested = false
            if state != .idle {
                state = .idle
                captureError = "停止失败：没有可作废的采集会话，未删除任何文件。"
            }
            return
        }
        let sessionDir = rawURL?.deletingLastPathComponent()
        do {
            try await confirmBackendExitedThenDiscard(sessionID: id)
            if let sessionDir, FileManager.default.fileExists(atPath: sessionDir.path) {
                throw NSError(domain: "CaptureDiscard", code: 1, userInfo: [NSLocalizedDescriptionKey: "会话临时目录仍存在，未声明作废。"])
            }
            applySuccessfulDiscard()
        } catch {
            isDiscarding = false
            // Leave files in place. Never show the voided-success message.
            if state != .failed {
                state = .failed
            }
            captureError = "停止失败：\(error.localizedDescription) 未删除本次日志。"
            saveMessage = ""
        }
    }

    private func confirmBackendExitedThenDiscard(sessionID id: UUID) async throws {
        var status = try await coordinator.getStatus(sessionID: id)
        if status.state == .starting {
            for _ in 0..<50 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                status = try await coordinator.getStatus(sessionID: id)
                if status.state != .starting { break }
            }
        }
        if status.state == .recording {
            _ = try await coordinator.stopCapture(sessionID: id)
            self.state = .finalizing
            self.refreshStatusOnce()
            status = try await coordinator.getStatus(sessionID: id)
        }
        if status.state == .recording || status.state == .starting || status.state == .stopping {
            throw NSError(domain: "CaptureDiscard", code: 2, userInfo: [NSLocalizedDescriptionKey: "采集后端尚未退出。"])
        }
        let firstBytes = status.rawByteCount
        let firstSize = rawFileSize()
        try await Task.sleep(nanoseconds: 200_000_000)
        let later = try await coordinator.getStatus(sessionID: id)
        let laterSize = rawFileSize()
        if later.rawByteCount != firstBytes || (firstSize != nil && laterSize != firstSize) {
            throw NSError(domain: "CaptureDiscard", code: 3, userInfo: [NSLocalizedDescriptionKey: "日志仍在写入。"])
        }
        _ = try await coordinator.discard(sessionID: id)
    }

    private func rawFileSize() -> Int? {
        guard let rawURL else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: rawURL.path)[.size] as? Int)
    }

    private func applySuccessfulDiscard() {
        resetForNewSession()
        state = .idle
        byteCount = 0
        lineCount = 0
        durationText = CaptureDisplayFormat.duration(seconds: 0)
        elapsedSeconds = 0
        logs.removeAll()
        previewTruncated = false
        captureError = ""
        saveMessage = "本次日志已作废，采集已停止"
        isDiscarding = false
        discardRequested = false
        restartRestoreMonitorAfterDecision()
    }

    var currentSessionDirectory: URL? {
        rawURL?.deletingLastPathComponent()
    }

    var currentRawLogURL: URL? { rawURL }
    var hasPendingSessionDecision: Bool {
        sessionID != nil && (isCapturing || state == .finalizing || state == .stopping ||
            state == .interrupted || state == .failed)
    }

    func openSaveSheet() {
        guard canSave else { return }
        saveMessage = ""
        saveSheetRequested = true
    }

    var defaultBaseName: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "MRA-\(f.string(from: Date()))"
    }

    var sessionFolderHint: String {
        guard let raw = rawURL else { return "尚无采集会话" }
        return raw.deletingLastPathComponent().path
    }

    var canStartRawExport: Bool {
        (canSave || finalized != nil) && !isExporting && !isDiscarding
    }

    var canExportEvidencePackage: Bool {
        (canSave || finalized != nil) && !isExporting && !isDiscarding
    }

    func setPreviewVisible(_ visible: Bool) {
        previewVisible = visible
        if visible { reloadVisibleLog() }
    }

    private func baseNameForSession() -> String {
        let trimmed = exportBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.safeBase(trimmed.isEmpty
            ? workspacePreferences.defaultFileBaseName
            : trimmed)
    }

    func saveRawLog(directory: URL? = nil, baseName: String? = nil) {
        guard canStartRawExport else { return }
        let destinationDirectory = directory
            ?? URL(fileURLWithPath: workspacePreferences.rawLogDirectory, isDirectory: true)
        let base = baseName ?? baseNameForSession()
        beginExport(operation: .rawLog)
        let token = ExportCancellationToken()
        exportCancellationToken = token
        let generation = exportGeneration
        saveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let source = try await self.ensureFinalized(displayName: base)
                guard self.exportGeneration == generation, !token.isCancelled else {
                    throw CancellationError()
                }
                let raw = try source.record.files.first(where: { $0.role == "raw-log" })
                    ?? source.record.files.first ?? {
                        throw SessionZipExportError.missingRaw
                    }()
                let request = RawLogExportRequest(
                    sourceURL: source.rawURL,
                    destinationDirectory: destinationDirectory,
                    baseName: base,
                    sessionID: source.record.sessionID,
                    isPartial: source.record.captureState != .savedVerified,
                    expectedSourceSHA256: raw.sha256)
                let threadProbe = self.exportThreadProbe
                let result: RawLogExportResult = try await Task.detached(priority: .userInitiated) {
                    threadProbe?(.rawLog, pthread_main_np() != 0)
                    return try RawLogExporter.export(
                        request,
                        shouldCancel: {
                            token.isCancelled
                        },
                        progress: { update in
                            Task { @MainActor [weak self] in
                                self?.publishExportProgress(update)
                            }
                        })
                }.value
                guard generation == self.exportGeneration, !token.isCancelled else {
                    if FileManager.default.fileExists(atPath: result.url.path) {
                        self.savedLogURL = result.url
                    }
                    return
                }
                self.savedLogURL = result.url
                self.lastRawExportURL = result.url
                self.saveMessage = "原始日志已保存并校验：\(result.url.lastPathComponent)"
                self.captureError = ""
                self.completeExport(
                    operation: .rawLog,
                    message: "已保存 \(result.url.lastPathComponent)")
                self.restartRestoreMonitorAfterDecision()
            } catch is CancellationError {
                self.failExportCancelled()
            } catch {
                self.failExport(error.localizedDescription)
            }
        }
    }

    func exportEvidencePackage(directory: URL, baseName: String) {
        guard canExportEvidencePackage else { return }
        let destination = Self.uniqueURL(
            in: directory,
            baseName: baseName.lowercased().hasSuffix(".zip") ? String(baseName.dropLast(4)) : baseName)
        let options = SessionZipExportOptions(
            includeTimeline: includeTimeline,
            includeSummary: includeDiagnosticSummary,
            includeUpdaterOutput: includeUpdaterOutput)
        beginExport(operation: .evidencePackage)
        let token = ExportCancellationToken()
        exportCancellationToken = token
        let generation = exportGeneration
        saveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let source = try await self.ensureFinalized(displayName: baseName)
                guard self.exportGeneration == generation, !token.isCancelled else {
                    throw CancellationError()
                }
                let cdhash = self.appCDHashProvider() ?? "UNVERIFIED"
                let version = self.appVersionOverride
                    ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
                    ?? "1.0.6"
                let zip64Threshold = self.zip64Threshold
                let threadProbe = self.exportThreadProbe
                let outcome: SessionZipExportResult = try await Task.detached(priority: .userInitiated) {
                    threadProbe?(.evidencePackage, pthread_main_np() != 0)
                    return try SessionZipExporter.export(
                        SessionZipExportRequest(
                            source: source,
                            destination: destination,
                            appVersion: version,
                            appCDHash: cdhash,
                            zip64Threshold: zip64Threshold),
                        options: options,
                        shouldCancel: {
                            token.isCancelled
                        },
                        detailedProgress: { update in
                            let mapped = LogExportProgress(
                                operation: .evidencePackage,
                                stage: update.stage,
                                processedBytes: update.stage == .generatingAttachments ||
                                    update.stage == .writingMetadata ||
                                    update.stage == .verifyingArchive ||
                                    update.stage == .publishing
                                    ? nil : update.processedBytes,
                                totalBytes: update.stage == .packagingZIP ? update.totalBytes : nil,
                                elapsedSeconds: update.elapsedSeconds,
                                bytesPerSecond: update.elapsedSeconds > 0.001 && update.totalBytes > 0
                                    ? Double(update.processedBytes) / update.elapsedSeconds : nil,
                                isIndeterminate: update.stage == .generatingAttachments ||
                                    update.stage == .writingMetadata ||
                                    update.stage == .verifyingArchive ||
                                    update.stage == .publishing)
                            Task { @MainActor [weak self] in
                                self?.publishExportProgress(mapped)
                            }
                        })
                }.value
                guard generation == self.exportGeneration, !token.isCancelled else {
                    if FileManager.default.fileExists(atPath: outcome.zipURL.path) {
                        self.savedZipURL = outcome.zipURL
                        self.lastEvidencePackageURL = outcome.zipURL
                    }
                    return
                }
                self.savedZipURL = outcome.zipURL
                self.lastEvidencePackageURL = outcome.zipURL
                self.lastExportManifest = outcome.manifest
                self.lastExportStats = outcome.stats
                self.saveMessage = "证据包已生成并校验：\(outcome.zipURL.lastPathComponent)"
                self.completeExport(
                    operation: .evidencePackage,
                    message: "已导出 \(outcome.zipURL.lastPathComponent)")
                self.restartRestoreMonitorAfterDecision()
            } catch is CancellationError {
                self.failExportCancelled()
            } catch let error as SessionZipExportError {
                self.failExport(error.localizedDescription)
            } catch {
                self.failExport(error.localizedDescription)
            }
        }
    }

    private func ensureFinalized(displayName: String) async throws -> SessionPackageSource {
        if let finalizedSource { return finalizedSource }
        if let finalizeTask { return try await finalizeTask.value }
        guard let id = sessionID else { throw CaptureError.noActiveSession }
        let operation = exportProgress?.operation ?? .evidencePackage
        let task = Task { @MainActor [weak self] () throws -> SessionPackageSource in
            guard let self else { throw CaptureError.noActiveSession }
            let result = try await self.coordinator.finalize(
                sessionID: id,
                mode: .saveOnly,
                displayName: displayName,
                progress: { progress in
                    let stage: LogExportStage
                    switch progress.stage {
                    case "HASHING_RAW": stage = .validatingRaw
                    case "WRITING_METADATA": stage = .writingMetadata
                    case "PREPARING": stage = .preparing
                    default: stage = .preparing
                    }
                    let update = LogExportProgress(
                        operation: operation,
                        stage: stage,
                        processedBytes: progress.totalBytes > 0 ? progress.processedBytes : nil,
                        totalBytes: progress.totalBytes > 0 ? progress.totalBytes : nil,
                        elapsedSeconds: progress.elapsedSeconds,
                        bytesPerSecond: progress.elapsedSeconds > 0.001 && progress.totalBytes > 0
                            ? Double(progress.processedBytes) / progress.elapsedSeconds : nil,
                        isIndeterminate: progress.totalBytes == 0)
                    Task { @MainActor [weak self] in
                        self?.publishExportProgress(update)
                    }
                })
            self.finalized = result
            self.state = result.record.captureState
            let directory = URL(fileURLWithPath: result.sessionJSONPath).deletingLastPathComponent()
            let source = SessionPackageSource(record: result.record, directory: directory)
            self.finalizedSource = source
            return source
        }
        finalizeTask = task
        do {
            let source = try await task.value
            finalizeTask = nil
            return source
        } catch {
            finalizeTask = nil
            throw error
        }
    }

    private func beginExport(operation: LogExportOperation) {
        saveTask?.cancel()
        exportGeneration += 1
        isExporting = true
        isRawExporting = operation == .rawLog
        isPackageExporting = operation == .evidencePackage
        exportProgressText = "准备导出"
        exportFraction = nil
        lastProgressPublish = .distantPast
        lastPublishedStage = nil
        exportProgress = LogExportProgress(
            operation: operation,
            stage: .preparing,
            processedBytes: nil,
            totalBytes: nil,
            elapsedSeconds: 0,
            bytesPerSecond: nil,
            isIndeterminate: true)
    }

    private func publishExportProgress(_ progress: LogExportProgress) {
        let now = Date()
        let stageChanged = progress.stage != lastPublishedStage
        let terminal = progress.stage == .complete ||
            progress.stage == .failed ||
            progress.stage == .cancelled
        guard stageChanged || terminal || now.timeIntervalSince(lastProgressPublish) >= 0.05 else {
            return
        }
        lastProgressPublish = now
        lastPublishedStage = progress.stage
        exportProgress = progress
        exportProgressText = progress.stage.displayName
        exportFraction = progress.fraction
    }

    private func completeExport(operation: LogExportOperation, message: String) {
        let elapsed = exportProgress?.elapsedSeconds ?? 0
        publishExportProgress(LogExportProgress(
            operation: operation,
            stage: .complete,
            processedBytes: exportProgress?.totalBytes,
            totalBytes: exportProgress?.totalBytes,
            elapsedSeconds: elapsed,
            bytesPerSecond: nil,
            isIndeterminate: false,
            message: message))
        isExporting = false
        isRawExporting = false
        isPackageExporting = false
        exportCancellationToken = nil
    }

    private func failExportCancelled() {
        publishExportProgress(LogExportProgress(
            operation: exportProgress?.operation ?? .evidencePackage,
            stage: .cancelled,
            processedBytes: nil,
            totalBytes: nil,
            elapsedSeconds: exportProgress?.elapsedSeconds ?? 0,
            bytesPerSecond: nil,
            isIndeterminate: true,
            message: "导出已取消；原始日志保留。"))
        isExporting = false
        isRawExporting = false
        isPackageExporting = false
        exportCancellationToken = nil
        saveMessage = "导出已取消；原始日志保留。"
    }

    private func failExport(_ reason: String) {
        publishExportProgress(LogExportProgress(
            operation: exportProgress?.operation ?? .evidencePackage,
            stage: .failed,
            processedBytes: nil,
            totalBytes: nil,
            elapsedSeconds: exportProgress?.elapsedSeconds ?? 0,
            bytesPerSecond: nil,
            isIndeterminate: true,
            message: reason))
        isExporting = false
        isRawExporting = false
        isPackageExporting = false
        exportCancellationToken = nil
        saveMessage = "导出失败：\(reason)\n原始日志保留，可重试。"
    }

    func importHistoricalLog(url: URL) {
        guard importState != .analyzing else { return }
        importTask?.cancel()
        importState = .analyzing
        importedFileName = url.lastPathComponent
        importedAnalysis = nil
        importedRawURL = url
        importedDiagnosticURL = nil
        importStatus = "正在只读分析 \(url.lastPathComponent)…"
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        importedFileSize = CaptureDisplayFormat.dataSize(bytes: bytes)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MRA-ImportedLog-\(UUID().uuidString)", isDirectory: true)
        let diagnosticURL = root.appendingPathComponent("diagnostic.log")
        importTask = Task { @MainActor [weak self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ImportedDiagnosticAnalyzer.analyze(
                        rawURL: url,
                        diagnosticURL: diagnosticURL)
                }.value
                self?.importedAnalysis = result
                self?.importedDiagnosticURL = diagnosticURL
                self?.importState = .completed
                self?.importStatus = "分析完成。原始日志未被修改。"
            } catch {
                self?.importState = .failed
                self?.importStatus = "分析失败：\(error.localizedDescription)"
            }
        }
    }

    func openLastRawExport() {
        guard let url = lastRawExportURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openLastEvidencePackage() {
        guard let url = lastEvidencePackageURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyPath(_ url: URL?) {
        guard let url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    private static func uniqueURL(in directory: URL, baseName: String) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safe = safeBase(baseName)
        for index in 1...999 {
            let name = index == 1 ? "\(safe).zip" : "\(safe)-\(index).zip"
            let url = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return directory.appendingPathComponent("\(safe)-\(UUID().uuidString.prefix(8)).zip")
    }

    func save(folder: URL, baseName: String, includeZip: Bool = true, includeLog: Bool = false) {
        guard canSave, let id = sessionID else {
            saveMessage = "当前没有可保存的已停止会话。"
            return
        }
        let base = Self.safeBase(baseName.isEmpty ? defaultBaseName : baseName)
        let zipURL = folder.appendingPathComponent(base + ".zip")
        if FileManager.default.fileExists(atPath: zipURL.path) {
            saveMessage = "目标文件已存在：请改名或选择其他文件夹；不会静默覆盖。"
            return
        }
        saveTask?.cancel()
        exportGeneration += 1
        let generation = exportGeneration
        let exportToken = ExportCancellationToken()
        exportCancellationToken = exportToken
        exportProgressText = "准备导出"
        exportFraction = nil
        saveMessage = "正在保存…"
        savedZipURL = nil
        savedLogURL = nil
        lastExportStats = nil
        lastExportManifest = nil
        isExporting = true
        saveTask = Task { @MainActor in
            defer { self.isExporting = false }
            do {
                self.exportProgressText = "正在 finalize"
                self.exportFraction = nil
                let result: ExportResult
                if let existing = self.finalized {
                    result = existing
                } else {
                    result = try await self.coordinator.finalize(
                        sessionID: id, mode: .saveOnly, displayName: base, progress: nil)
                    guard self.exportGeneration == generation else { return }
                    self.finalized = result
                    self.state = result.record.captureState
                }
                guard self.exportGeneration == generation else { return }
                let sourceDir = URL(fileURLWithPath: result.sessionJSONPath).deletingLastPathComponent()
                let source = SessionPackageSource(record: result.record, directory: sourceDir)
                let cdhash = self.appCDHashProvider() ?? "UNVERIFIED"
                let version = self.appVersionOverride
                    ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
                    ?? "0.2.3"
                self.exportProgressText = "正在封装"
                if let override = self.packageBuildOverride {
                    let built = try override(source, zipURL, base)
                    guard self.exportGeneration == generation else {
                        // Cancel after a successful commit: the file stays; UI follows the commit.
                        return
                    }
                    self.savedZipURL = built
                    self.saveMessage = "保存成功；已导出一个 ZIP，完整原始日志在包内仅保存一份。"
                    self.exportProgressText = "完成"
                    self.exportFraction = 1
                    self.exportCancellationToken = nil
                    UserDefaults.standard.set(folder.path, forKey: "MRA.lastSaveFolder")
                    self.restartRestoreMonitorAfterDecision()
                    return
                }
                let zip64Threshold = self.zip64Threshold
                let threadProbe = self.exportThreadProbe
                let outcome: SessionZipExportResult = try await Task.detached(priority: .userInitiated) {
                    threadProbe?(.evidencePackage, pthread_main_np() != 0)
                    return try SessionZipExporter.export(
                        SessionZipExportRequest(
                            source: source,
                            destination: zipURL,
                            appVersion: version,
                            appCDHash: cdhash,
                            zip64Threshold: zip64Threshold),
                        options: .rawOnly,
                        shouldCancel: { exportToken.isCancelled },
                        progress: { phase, fraction in
                            Task { @MainActor [weak self] in
                                self?.exportProgressText = phase
                                self?.exportFraction = fraction
                            }
                        })
                }.value
                if self.exportGeneration != generation {
                    // If the ZIP was already published, treat as completed.
                    if FileManager.default.fileExists(atPath: zipURL.path) {
                        self.savedZipURL = zipURL
                        self.saveMessage = "保存成功；已导出一个 ZIP，完整原始日志在包内仅保存一份。"
                        self.exportProgressText = "完成"
                        self.exportFraction = 1
                    } else {
                        self.saveMessage = "导出已取消。未留下半截成功文件。"
                        self.exportProgressText = "已取消"
                    }
                    return
                }
                self.savedZipURL = outcome.zipURL
                self.lastExportStats = outcome.stats
                self.lastExportManifest = outcome.manifest
                self.saveMessage = "保存成功；已导出一个 ZIP，完整原始日志在包内仅保存一份。"
                self.exportProgressText = "完成"
                self.exportFraction = 1
                self.exportCancellationToken = nil
                UserDefaults.standard.set(folder.path, forKey: "MRA.lastSaveFolder")
                self.restartRestoreMonitorAfterDecision()
            } catch is CancellationError {
                self.saveMessage = "导出已取消。未留下半截成功文件。"
                self.exportProgressText = "已取消"
                self.exportCancellationToken = nil
            } catch let error as SessionZipExportError {
                self.saveMessage = "保存失败：\(error.localizedDescription)\n会话保留，可重试。"
                self.exportProgressText = "失败"
                self.exportCancellationToken = nil
            } catch {
                self.saveMessage = "保存失败：\(error.localizedDescription)\n会话保留，可重试。"
                self.exportProgressText = "失败"
                self.exportCancellationToken = nil
            }
        }
    }

    func cancelExport() {
        exportGeneration += 1
        exportCancellationToken?.cancel()
        saveTask?.cancel()
        if savedZipURL == nil {
            saveMessage = "导出已取消。未留下半截成功文件。"
            exportProgressText = "已取消"
            isExporting = false
            isRawExporting = false
            isPackageExporting = false
            exportCancellationToken = nil
        }
    }

    func copySavedZip() {
        guard let url = savedZipURL else { return }
        do {
            try pasteboard.copyFileURL(url)
            saveMessage = "已复制 ZIP（原生文件 URL）。"
        } catch {
            saveMessage = "复制失败。ZIP 已成功导出，位置未改变。"
        }
    }

    func revealSavedFiles() {
        guard let zip = savedZipURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([zip])
    }

    private func resetForNewSession() {
        state = .idle
        finalized = nil
        finalizedSource = nil
        sessionID = nil
        rawURL = nil
        savedZipURL = nil
        savedLogURL = nil
        isExporting = false
        exportProgressText = ""
        exportFraction = nil
        lastExportStats = nil
        lastExportManifest = nil
    }

    private var displayTimerPaused = false

    func setDisplayTimerPaused(_ paused: Bool) {
        if paused {
            displayTimerPaused = true
            monitorTask?.cancel()
            monitorTask = nil
        } else {
            let wasPaused = displayTimerPaused
            displayTimerPaused = false
            if isCapturing {
                refreshStatusOnce()
                startMonitor()
            } else if wasPaused {
                refreshStatusOnce()
            }
        }
    }

    private func startMonitor() {
        if displayTimerPaused { return }
        monitorTask?.cancel()
        monitorTask = Task { @MainActor in
            var ticks = 0
            while !Task.isCancelled {
                if let raw = self.rawURL {
                    let snapshot = await self.projection.snapshot(
                        path: raw,
                        maxPreviewLines: self.workspacePreferences.previewLineLimit)
                    if self.byteCount != snapshot.byteCount {
                        self.byteCount = snapshot.byteCount
                    }
                    if self.lineCount != snapshot.lineCount {
                        self.lineCount = snapshot.lineCount
                    }
                    if self.previewVisible,
                       self.previewLines != snapshot.previewLines {
                        self.previewLines = snapshot.previewLines
                    }
                    self.previewTruncated = snapshot.lineCount > snapshot.previewLines.count
                }
                ticks += 1
                if ticks % 5 == 0 {
                    await self.refreshStatusNow()
                }
                try? await Task.sleep(nanoseconds: 700_000_000)
                if Task.isCancelled || self.displayTimerPaused { break }
            }
        }
    }

    private func refreshStatusOnce() {
        Task { @MainActor [weak self] in
            await self?.refreshStatusNow()
        }
    }

    private func refreshStatusNow() async {
        guard let id = sessionID else { return }
        do {
            let status = try await coordinator.getStatus(sessionID: id)
            if self.state != status.state { self.state = status.state }
            if self.byteCount != status.rawByteCount { self.byteCount = status.rawByteCount }
            if self.lineCount != status.rawLineCount { self.lineCount = status.rawLineCount }
            if let started = status.startedAtUTC {
                let end = status.endedAtUTC ?? Date()
                let seconds = max(0, Int(end.timeIntervalSince(started)))
                self.elapsedSeconds = seconds
                let text = CaptureDisplayFormat.duration(seconds: seconds)
                if self.durationText != text { self.durationText = text }
            }
        } catch {
            // Status is observational; never replace capture ownership with a view error.
        }
    }

    private func reloadVisibleLog() {
        guard previewVisible, let raw = rawURL else { return }
        let snapshot = LogPreviewReader.tail(
            url: raw, maxLines: workspacePreferences.previewLineLimit)
        previewLines = snapshot.lines
        previewTruncated = snapshot.truncated
    }

    private static func safeBase(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasSuffix(".zip") { text.removeLast(4) }
        if text.lowercased().hasSuffix(".log") { text.removeLast(4) }
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        text = text.components(separatedBy: bad).joined(separator: "_")
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return text.isEmpty ? "MRA-Session" : String(text.prefix(80))
    }
}

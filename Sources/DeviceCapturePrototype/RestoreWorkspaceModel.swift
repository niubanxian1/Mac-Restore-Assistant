import Combine
import Foundation

struct RestoreTarget: Identifiable, Equatable, Sendable {
    let ecid: UInt64
    let canonicalHex: String
    let productType: String?
    let deviceClass: String?
    let boardID: Int?
    let chipID: Int?
    let locationID: String
    let connectionGeneration: UInt64
    let portKey: String?
    let portDisplayName: String
    let mode: ObservedDeviceMode
    let displayName: String
    let machineIdentifier: String?
    let identityProvenance: DeviceIdentityProvenance

    init(
        ecid: UInt64,
        canonicalHex: String,
        productType: String?,
        deviceClass: String?,
        boardID: Int?,
        chipID: Int?,
        locationID: String,
        connectionGeneration: UInt64,
        portKey: String?,
        portDisplayName: String,
        mode: ObservedDeviceMode,
        displayName: String,
        machineIdentifier: String? = nil,
        identityProvenance: DeviceIdentityProvenance = .unverifiedGeneric
    ) {
        self.ecid = ecid
        self.canonicalHex = canonicalHex
        self.productType = productType
        self.deviceClass = deviceClass
        self.boardID = boardID
        self.chipID = chipID
        self.locationID = locationID
        self.connectionGeneration = connectionGeneration
        self.portKey = portKey
        self.portDisplayName = portDisplayName
        self.mode = mode
        self.displayName = displayName
        self.machineIdentifier = machineIdentifier
        self.identityProvenance = identityProvenance
    }

    var id: String { canonicalHex }

    var displayIdentity: String {
        "\(displayName) · \(mode.title) · ECID \(canonicalHex)"
    }

    var portDescription: String {
        let location = locationID.isEmpty
            ? "USB location 未知"
            : "USB location \(locationID)"
        return "\(portDisplayName) · \(location)"
    }

    var firmwareIdentity: FirmwareTargetIdentity {
        FirmwareTargetIdentity(
            productType: productType,
            machineIdentifier: machineIdentifier,
            deviceClass: deviceClass,
            boardID: boardID,
            chipID: chipID,
            provenance: identityProvenance)
    }
}

struct RestoreBrowsePort: Identifiable, Equatable, Sendable {
    let key: String
    let displayName: String

    var id: String { key }
}

enum RestoreTargetError: Error, LocalizedError, Equatable {
    case observationFailed
    case staleSnapshot
    case targetMissing
    case targetDuplicated
    case invalidECID
    case wrongMode

    var errorDescription: String? {
        switch self {
        case .observationFailed: return "设备观察失败，无法建立启动前新鲜快照。"
        case .staleSnapshot: return "设备观察快照已过期；请刷新后再确认恢复。"
        case .targetMissing: return "所选 Restore 目标已不在最新设备观察中。"
        case .targetDuplicated: return "最新观察中出现重复 ECID，无法安全绑定单一目标。"
        case .invalidECID: return "所选目标的 ECID 无法规范化为正整数。"
        case .wrongMode: return "所选目标当前不在 DFU 或 Recovery 模式。"
        }
    }
}

enum RestoreSnapshotInspector {
    @MainActor
    static func targets(
        from devices: [ObservedDevice],
        portKeyResolver: (ObservedDevice) -> String? = { _ in nil },
        portDisplayNameResolver: (String) -> String = { _ in "端口未归属" }
    ) -> [RestoreTarget] {
        devices.compactMap { device -> RestoreTarget? in
            guard device.mode == .dfu || device.mode == .recovery,
                  let rawECID = device.ecid,
                  let identity = ECIDIdentity(hex: rawECID) else {
                return nil
            }
            let model = device.modelIdentifier
                ?? device.productType
                ?? device.product
            let portKey = portKeyResolver(device)
            let displayName = portKey.map(portDisplayNameResolver)
                ?? "端口未归属"
            let resolvedIdentity = MacIdentityResolver.resolve(
                device: device,
                historicalHint: nil)
            let liveIdentifier = liveMachineIdentifier(
                productType: device.productType,
                machineIdentifier: device.modelIdentifier,
                explicitMachineIdentifier: device.explicitMachineIdentifierRaw)
            return RestoreTarget(
                ecid: identity.value,
                canonicalHex: identity.canonicalHex,
                productType: device.productType
                    ?? liveIdentifier
                    ?? device.modelIdentifier,
                deviceClass: device.hardwareCode,
                boardID: device.boardID,
                chipID: device.chipID,
                locationID: device.locationID,
                connectionGeneration: device.connectionGeneration,
                portKey: portKey,
                portDisplayName: displayName,
                mode: device.mode,
                displayName: model,
                machineIdentifier:
                    liveIdentifier ?? resolvedIdentity.primaryModelIdentifier,
                identityProvenance:
                    liveIdentifier == nil
                        ? identityProvenance(from: resolvedIdentity.state)
                        : .liveConfirmed)
        }
    }

    @MainActor
    static func targets(
        from snapshot: ObservedDeviceReadSnapshot,
        portKeyResolver: (ObservedDevice) -> String? = { _ in nil },
        portDisplayNameResolver: (String) -> String = { _ in "端口未归属" }
    ) -> [RestoreTarget] {
        guard case .success(let devices) = snapshot.result else { return [] }
        return targets(
            from: devices,
            portKeyResolver: portKeyResolver,
            portDisplayNameResolver: portDisplayNameResolver)
    }

    static func validate(
        target: RestoreTarget,
        devices: [ObservedDevice]
    ) throws {
        let matches = targetsWithoutPortResolution(from: devices)
            .filter { $0.ecid == target.ecid }
        guard !matches.isEmpty else { throw RestoreTargetError.targetMissing }
        guard matches.count == 1 else { throw RestoreTargetError.targetDuplicated }
        guard matches[0].mode == .dfu || matches[0].mode == .recovery else {
            throw RestoreTargetError.wrongMode
        }
    }

    private static func targetsWithoutPortResolution(
        from devices: [ObservedDevice]
    ) -> [RestoreTarget] {
        devices.compactMap { device -> RestoreTarget? in
            guard device.mode == .dfu || device.mode == .recovery,
                  let rawECID = device.ecid,
                  let identity = ECIDIdentity(hex: rawECID) else {
                return nil
            }
            let resolvedIdentity = MacIdentityResolver.resolve(
                device: device,
                historicalHint: nil)
            let liveIdentifier = liveMachineIdentifier(
                productType: device.productType,
                machineIdentifier: device.modelIdentifier,
                explicitMachineIdentifier: device.explicitMachineIdentifierRaw)
            return RestoreTarget(
                ecid: identity.value,
                canonicalHex: identity.canonicalHex,
                productType: device.productType
                    ?? liveIdentifier
                    ?? device.modelIdentifier,
                deviceClass: device.hardwareCode,
                boardID: device.boardID,
                chipID: device.chipID,
                locationID: device.locationID,
                connectionGeneration: device.connectionGeneration,
                portKey: nil,
                portDisplayName: "端口未归属",
                mode: device.mode,
                displayName: device.modelIdentifier
                    ?? device.productType
                    ?? device.product,
                machineIdentifier:
                    liveIdentifier ?? resolvedIdentity.primaryModelIdentifier,
                identityProvenance:
                    liveIdentifier == nil
                        ? identityProvenance(from: resolvedIdentity.state)
                        : .liveConfirmed)
        }
    }

    private static func liveMachineIdentifier(
        productType: String?,
        machineIdentifier: String?,
        explicitMachineIdentifier: String?
    ) -> String? {
        let product = TargetModelCatalog.identifier(from: productType)
        let machine = TargetModelCatalog.identifier(from: machineIdentifier)
        let explicit = TargetModelCatalog.identifier(from: explicitMachineIdentifier)
        let strongValues = [product, machine, explicit].compactMap { $0 }
        guard let first = strongValues.first,
              strongValues.allSatisfy({
                  $0.caseInsensitiveCompare(first) == .orderedSame
              }) else {
            return nil
        }
        return first
    }

    private static func identityProvenance(
        from state: MacIdentityState
    ) -> DeviceIdentityProvenance {
        switch state {
        case .confirmedCurrent, .uniqueCurrentMatch:
            return .liveConfirmed
        case .historicalHintOnly:
            return .portHistoryAssisted
        case .candidates, .conflict, .unknown:
            return .unverifiedGeneric
        }
    }
}

enum RestoreTaskPhase: String, Equatable, Sendable {
    case userConfirmed = "USER_CONFIRMED"
    case processStarted = "PROCESS_STARTED"
    case restoreActivityObserved = "RESTORE_ACTIVITY_OBSERVED"
    case terminal = "TERMINAL"
}

struct RestoreTaskSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let attemptID: UUID
    let target: RestoreTarget
    let ipswURL: URL
    let ipswIdentity: IPSWFileIdentity?
    let firmwareLibraryEntryID: UUID?
    let buildManifestSHA256: String
    let wholeFileSHA256: String?
    var rawOutputDirectory: URL?
    let metadata: IPSWMetadata?
    let compatibility: HardwareCompatibility
    var rlmStatus: RestoreRLMLogStatus
    var rlmOwnership: RestoreRLMOwnership
    var rlmFinalizedAt: RestoreLifecycleTimePoint?
    var rlmDrainDurationSeconds: TimeInterval?
    var rlmRawLogURL: URL?
    let rawPersistencePolicy: RestoreRawPersistencePolicy
    var rawEvidenceStatus: RestoreRawEvidenceStatus
    var rawArchive: RestoreArchiveRecord? = nil
    var rawArchiveMessage = ""
    var lifecycle: RestoreLifecycleTimes
    var attemptStage: PendingRestoreAttemptStage
    let userConfirmedAt: Date
    var processStartedAt: Date?
    var restoreActivityObservedAt: Date?
    var finishedAt: Date?
    var phase: RestoreTaskPhase
    var outcome: RestoreOutcome?
    var stepText = ""
    var stepCompleted = false
    var stageFraction: Double?
    var overallFraction: Double? = nil
    var lastOutputAt: Date?
    var exitCode: Int32?
    var terminationReason: RestoreTerminationReason = .unknown
    var sentSignals: [RestoreSentSignal] = []
    var failureText = ""
    var stdoutURL: URL?
    var stderrURL: URL?
    var stdoutSHA256 = ""
    var stderrSHA256 = ""
    var tailComplete = false
    var cfgutilOutputTail: [String] = []
    var cfgutilOutputSequence: UInt64 = 0
    var cancellationRequested = false
    var cancellationGraceExpired = false
    var forcedKill = false
}

enum PendingRestoreAttemptStage: String, Equatable, Sendable {
    case userConfirmed = "USER_CONFIRMED"
    case waitingForFreshHeartbeat
    case validatingPreflight
    case preparingRLM
    case readyToLaunch
    case processLaunching
    case processRunning
    case processExited
    case bothStreamsEOF
    case outcomeConfirmed
    case finalizingEvidence
    case completed
}

struct PendingRestoreAttempt: Identifiable, Equatable, Sendable {
    let attemptID: UUID
    let taskID: UUID
    let target: RestoreTarget
    let canonicalECID: String
    let stablePortKey: String?
    let portDisplayName: String
    let ipswURL: URL
    let ipswIdentity: IPSWFileIdentity?
    let firmwareLibraryEntryID: UUID?
    let buildManifestSHA256: String
    let rawPersistencePolicy: RestoreRawPersistencePolicy
    let userConfirmedAt: RestoreLifecycleTimePoint
    var stage: PendingRestoreAttemptStage
    var lifecycle: RestoreLifecycleTimes
    var cancelRequestedAt: RestoreLifecycleTimePoint?
    var launchPermitted = true

    var id: UUID { attemptID }

    var cancelRequested: Bool {
        cancelRequestedAt != nil
    }
}

@MainActor
protocol RestoreRLMPreparing: AnyObject {
    func prepare(taskID: UUID, canonicalECID: String) async -> RestoreRLMBinding
    func prepare(
        taskID: UUID,
        canonicalECID: String,
        saveRequested: Bool
    ) async -> RestoreRLMBinding
    func finish(taskID: UUID, outcome: RestoreOutcome) async
    func finalization(
        taskID: UUID,
        timeout: TimeInterval
    ) async -> RestoreRLMFinalization?
}

extension RestoreRLMCoordinator: RestoreRLMPreparing {}

extension RestoreRLMPreparing {
    func prepare(
        taskID: UUID,
        canonicalECID: String,
        saveRequested: Bool
    ) async -> RestoreRLMBinding {
        await prepare(taskID: taskID, canonicalECID: canonicalECID)
    }

    func finalization(
        taskID: UUID,
        timeout: TimeInterval
    ) async -> RestoreRLMFinalization? {
        nil
    }
}

struct RestoreConfirmationToken: Equatable, Sendable {
    let tokenID: UUID
    let targetID: String
    let canonicalECID: String
    let portKey: String?
    let connectionGeneration: UInt64
    let ipswURL: URL
    let fileIdentity: IPSWFileIdentity
    let buildManifestSHA256: String
    let rawSaveRequested: Bool
    let createdAt: Date
}

@MainActor
final class RestoreWorkspaceModel: ObservableObject {
    @Published private(set) var availableTargets: [RestoreTarget] = []
    @Published private(set) var availableBrowsePorts: [RestoreBrowsePort] = []
    @Published private(set) var browsePortScope: String?
    @Published private(set) var selectedTargetID: String?
    @Published private(set) var hasUserRestorePreparationContext = false
    @Published private(set) var lockedTarget: RestoreTarget?
    @Published private(set) var firmwareURL: URL?
    @Published private(set) var firmwareMetadata: IPSWMetadata?
    @Published private(set) var firmwareValidity: IPSWFileValidity = .unverified
    @Published private(set) var firmwareFileIdentity: IPSWFileIdentity?
    @Published private(set) var buildManifestSHA256 = ""
    @Published private(set) var hardwareCompatibility = HardwareCompatibility(
        status: .unverified,
        message: "请选择目标设备和本地 IPSW。")
    @Published private(set) var firmwareCandidates: [URL] = []
    @Published private(set) var firmwareLibraryEntries: [FirmwareLibraryEntry] = []
    @Published private(set) var firmwareLibraryEntryID: UUID?
    @Published private(set) var firmwareSelectionSource: FirmwareSelectionSource = .none
    @Published private(set) var recommendedFirmware: FirmwareRecommendation?
    @Published private(set) var firmwareLibraryMessage = ""
    @Published private(set) var firmwareLibraryRoots: [URL] = []
    @Published private(set) var isFirmwareDiscoveryActive = false
    @Published private(set) var firmwareDiscoveryMessage = ""
    @Published var autoScanFirmwareOnLaunch: Bool =
        (UserDefaults.standard.object(forKey: "firmware.autoScanOnLaunch") as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(
                autoScanFirmwareOnLaunch,
                forKey: "firmware.autoScanOnLaunch")
        }
    }
    @Published private(set) var firmwareDrafts: [String: RestoreFirmwareDraft] = [:]
    @Published private(set) var firmwareDraftMessage = ""
    private(set) var firmwareDraftMessageKey: String?
    @Published private(set) var firmwarePreferenceIssue = ""
    @Published private(set) var firmwareReferenceResolutions:
        [String: FirmwareReferenceResolution] = [:]
    @Published private(set) var executionSlot: RestoreExecutionSlot?
    @Published private(set) var secondaryTask: RestoreTaskSnapshot?
    @Published private(set) var secondaryAttempt: PendingRestoreAttempt?
    private(set) var secondaryAttemptID: UUID?
    private(set) var lastSecondaryTaskSnapshot: RestoreTaskSnapshot?
    private var secondaryCore: RestoreDualRestoreCore?
    private var secondaryDraft: RestoreFirmwareDraft?
    private(set) var leaseShareCount = 0
    var activeLeaseShareCount: Int { leaseShareCount }
    var isMachineLeaseHeld: Bool { processLease.isHeld }
    @Published private(set) var lastCompletedTaskSnapshot: RestoreTaskSnapshot?

    /// 兼容/界面投影：切片 1 始终绑定当前唯一执行槽。
    private(set) var activeAttempt: PendingRestoreAttempt? {
        get { executionSlot?.attempt }
        set {
            objectWillChange.send()
            executionSlot?.attempt = newValue
        }
    }

    private(set) var currentTask: RestoreTaskSnapshot? {
        get { executionSlot?.task }
        set {
            objectWillChange.send()
            executionSlot?.task = newValue
        }
    }
    @Published private(set) var rawSaveRequestedThisRun = false
    @Published private(set) var rawSaveRequestedByPort: [String: Bool] = [:]
    private var rawSaveSelectionExplicitPorts: Set<String> = []
    @Published private(set) var restoreHistoryStatistics =
        RestoreHistoryStatistics.empty
    @Published private(set) var restoreHistoryMessage = ""
    @Published private(set) var isLoadingFirmware = false
    @Published private(set) var isComputingHash = false
    @Published private(set) var firmwareSHA256 = ""
    @Published private(set) var frozenRestoreConfirmation: RestoreConfirmationToken?
    @Published var errorMessage = ""
    @Published var message = ""

    let outputRoot: URL
    /// G2：首任务与后加入任务共用的容量 2 权威注册表。
    let taskRegistry = RestoreTaskRegistry(capacity: 2)
    let maximumSnapshotAge: TimeInterval
    let heartbeatPollInterval: TimeInterval
    let cancellationGraceDelay: TimeInterval
    private let engine: any RestoreEngineRunning
    private let rlmCoordinator: any RestoreRLMPreparing
    private let observationHeartbeat: DeviceControlModel.ObservationHeartbeatChannel?
    private let portKeyResolver: (ObservedDevice) -> String?
    private let portDisplayNameResolver: (String) -> String
    private let metadataReader: (URL) throws -> IPSWMetadataReadResult
    private let firmwareLibrary: FirmwareLibraryStore
    private let firmwarePreferences: FirmwarePreferencesStore?
    private let recommendationEngine: FirmwareRecommendationEngine
    private let historyStore: any RestoreHistoryStoring
    private let rawArchivePublisher: any RestoreArchivePublishing
    private let rawArchiveObservationHook: (@MainActor () async -> Void)?
    private let rawPersistenceDefaultsProvider:
        @MainActor () -> RestoreRawPersistenceDefaults
    private let stablePortKeyProvider: @MainActor (RestoreTarget) -> String?
    private let recentSuccessfulUsesProvider: @MainActor () -> [FirmwareUsageRecord]
    private let modelDefaultCandidateIDProvider: @MainActor (ModelFamilyKey) -> UUID?
    private let globalDefaultCandidateIDProvider: @MainActor () -> UUID?
    private let cfgutilURL: URL?
    private let processLease: RestoreProcessLease
    private let secondaryEngineFactory: @MainActor () -> any RestoreEngineRunning
    private var allAvailableTargets: [RestoreTarget] = []
    private var latestHeartbeat = DeviceControlModel.ObservationHeartbeatSnapshot(
        observationSequence: 0,
        completedUptimeNs: nil,
        observationResult: .pending,
        devices: [])
    private var heartbeatCancellable: AnyCancellable?
    private var targetSignature = ""
    private var runTask: Task<Void, Never>? {
        get { executionSlot?.runTask }
        set { executionSlot?.runTask = newValue }
    }
    private var suppressAutomaticRecommendation = false
    private var historyUsageRecords: [FirmwareUsageRecord] = []
    private var historyRecords: [RestoreHistoryRecord] = []
    private var rawSaveSelectionExplicit = false
    private var preferenceResolutionGeneration = 0
    private var preferenceResolutionTask: Task<Void, Never>?
    private let firmwareDiscoveryService = FirmwareDiscoveryService()
    private let firmwareDirectoryWatcher = FirmwareDirectoryWatcher()
    private var firmwareDiscoveryTask: Task<Void, Never>?
    private var firmwareDiscoveryPending = false
    private var didAutoDiscoverFirmware = false

    init(
        capture: any RestoreCaptureLifecycle,
        engine: (any RestoreEngineRunning)? = nil,
        outputRoot: URL? = nil,
        maximumSnapshotAge: TimeInterval = 3,
        heartbeatPollInterval: TimeInterval = 0.02,
        cancellationGraceDelay: TimeInterval = 3,
        observationHeartbeat: DeviceControlModel.ObservationHeartbeatChannel? = nil,
        portKeyResolver: @escaping (ObservedDevice) -> String? = { _ in nil },
        portDisplayNameResolver: @escaping (String) -> String = { _ in "端口未归属" },
        metadataReader: @escaping (URL) throws -> IPSWMetadataReadResult = {
            try IPSWMetadataReader.read(url: $0)
        },
        cfgutilURL: URL? = nil,
        rlmCoordinator: (any RestoreRLMPreparing)? = nil,
        firmwareLibrary: FirmwareLibraryStore? = nil,
        firmwarePreferences: FirmwarePreferencesStore? = nil,
        recommendationEngine: FirmwareRecommendationEngine = FirmwareRecommendationEngine(),
        historyStore: (any RestoreHistoryStoring)? = nil,
        rawArchivePublisher: (any RestoreArchivePublishing)? = nil,
        rawArchiveObservationHook: (@MainActor () async -> Void)? = nil,
        rawPersistenceDefaultsProvider:
            @escaping @MainActor () -> RestoreRawPersistenceDefaults = {
                .standard
            },
        stablePortKeyProvider:
            @escaping @MainActor (RestoreTarget) -> String? = { _ in nil },
        recentSuccessfulUsesProvider: @escaping @MainActor () -> [FirmwareUsageRecord] = {
            []
        },
        modelDefaultCandidateIDProvider: @escaping @MainActor (ModelFamilyKey) -> UUID? = {
            _ in nil
        },
        globalDefaultCandidateIDProvider: @escaping @MainActor () -> UUID? = {
            nil
        },
        processLease: RestoreProcessLease? = nil,
        secondaryEngineFactory:
            @escaping @MainActor () -> any RestoreEngineRunning = {
                CfgutilRestoreEngine()
            }
    ) {
        self.engine = engine ?? CfgutilRestoreEngine()
        self.outputRoot = outputRoot
            ?? AppSupportLocations.directory()
                .appendingPathComponent("RestoreStaging", isDirectory: true)
        self.maximumSnapshotAge = max(0.001, maximumSnapshotAge)
        self.heartbeatPollInterval = max(0.001, heartbeatPollInterval)
        self.cancellationGraceDelay = max(0.001, cancellationGraceDelay)
        self.observationHeartbeat = observationHeartbeat
        self.portKeyResolver = portKeyResolver
        self.portDisplayNameResolver = portDisplayNameResolver
        self.metadataReader = metadataReader
        self.firmwareLibrary = firmwareLibrary
            ?? FirmwareLibraryStore(metadataLoader: metadataReader)
        self.firmwarePreferences = firmwarePreferences
        self.recommendationEngine = recommendationEngine
        self.historyStore = historyStore ?? RestoreHistoryStore()
        self.rawArchivePublisher = rawArchivePublisher
            ?? RestoreLogRetentionManager(
                localStagingRoot: self.outputRoot)
        self.rawArchiveObservationHook = rawArchiveObservationHook
        self.rawPersistenceDefaultsProvider = rawPersistenceDefaultsProvider
        self.stablePortKeyProvider = stablePortKeyProvider
        self.rawSaveRequestedThisRun =
            rawPersistenceDefaultsProvider().autoSaveDefault
        self.recentSuccessfulUsesProvider = recentSuccessfulUsesProvider
        self.modelDefaultCandidateIDProvider = modelDefaultCandidateIDProvider
        self.globalDefaultCandidateIDProvider = globalDefaultCandidateIDProvider
        self.cfgutilURL = cfgutilURL ?? CfgutilRestoreEngine.locateCfgutil()
        self.processLease = processLease ?? RestoreProcessLease.shared
        self.secondaryEngineFactory = secondaryEngineFactory
        self.rlmCoordinator = rlmCoordinator
            ?? RestoreRLMCoordinator(capture: capture)

        if let observationHeartbeat {
            latestHeartbeat = observationHeartbeat.latest
            heartbeatCancellable = observationHeartbeat.$latest.sink {
                [weak self] snapshot in
                self?.ingestHeartbeat(snapshot)
            }
        }
        ingestHeartbeat(latestHeartbeat)
    }

    var selectedTarget: RestoreTarget? {
        if let activeAttempt {
            return activeAttempt.target
        }
        guard activeAttempt == nil,
              let selectedTargetID else {
            return nil
        }
        return availableTargets.first { $0.id == selectedTargetID }
    }

    var displayedTask: RestoreTaskSnapshot? {
        currentTask ?? lastCompletedTaskSnapshot
    }

    var navigationTargetInventory: [RestoreTarget] {
        allAvailableTargets
    }

    var restoreStartInFlight: Bool {
        activeAttempt != nil
    }

    var isRestoring: Bool {
        (currentTask?.processStartedAt != nil && currentTask?.outcome == nil)
            || (secondaryTask?.processStartedAt != nil && secondaryTask?.outcome == nil)
    }

    var isRestoreTaskActive: Bool {
        if secondaryTask != nil || secondaryAttempt != nil { return true }
        return activeAttempt != nil || runTask != nil || engine.isRunning
    }

    var canCancelRestoreTask: Bool {
        activeAttempt != nil && currentTask?.outcome == nil
    }

    var isFinalizingRestoreEvidence: Bool {
        activeAttempt != nil && currentTask?.outcome != nil
    }

    var currentAttemptID: UUID? {
        activeAttempt?.attemptID
    }

    var canStartRestore: Bool {
        !isRestoreTaskActive
            && !isLoadingFirmware
            && cfgutilURL != nil
            && selectedTarget != nil
            && firmwareURL != nil
            && firmwareValidity == .valid
            && firmwareFileIdentity != nil
            && selectedFirmwareLibraryEntryIsRestoreEligible
            && hardwareCompatibility.status == .compatible
    }

    var startDisabledReason: String {
        if isRestoreTaskActive { return "已有 Restore 任务或启动准备正在进行。" }
        if cfgutilURL == nil { return "未找到 Apple Configurator cfgutil。" }
        if selectedTarget == nil { return "请选择一个 DFU 或 Recovery 目标。" }
        if firmwareURL == nil { return "请选择本地 IPSW。" }
        if let entry = selectedFirmwareLibraryEntry,
           !entry.isRestoreEligible {
            switch entry.accessState {
            case .unreadable:
                return "所选固件当前无法读取。"
            case .cloudNotDownloaded:
                return "所选固件是 iCloud 占位文件，尚未下载。"
            case nil:
                break
            }
            switch entry.state {
            case .missing:
                return "所选固件文件已丢失。"
            case .ambiguous:
                return "所选固件存在多个重定位候选，需人工确认。"
            case .invalid:
                return "所选固件无效或已损坏。"
            case .available:
                return "所选固件未通过文件身份或 BuildManifest 验证。"
            }
        }
        if firmwareLibraryEntryID != nil && selectedFirmwareLibraryEntry == nil {
            return "所选固件库条目已失效，请重新扫描并选择。"
        }
        if firmwareValidity == .unverified { return "正在读取固件信息。" }
        if firmwareValidity == .invalid { return "固件文件无效或已损坏。" }
        if firmwareFileIdentity == nil { return "固件文件身份不可读取。" }
        if hardwareCompatibility.status == .incompatible {
            return "固件与目标硬件明确不兼容。"
        }
        return ""
    }

    var confirmationWarning: String {
        if firmwareURL == nil {
            return "请选择目标设备和本地 IPSW。"
        }
        if let entry = selectedFirmwareLibraryEntry,
           !entry.isRestoreEligible {
            if let detail = entry.errorMessage, !detail.isEmpty {
                return "当前固件不可用于 Restore：\(detail)"
            }
            switch entry.accessState {
            case .unreadable:
                return "当前固件无法读取，不会进入 Restore 准备。"
            case .cloudNotDownloaded:
                return "当前固件是 iCloud 占位文件，尚未下载，不会进入 Restore 准备。"
            case nil:
                break
            }
            switch entry.state {
            case .missing:
                return "当前固件文件已丢失，不会进入 Restore 准备。"
            case .ambiguous:
                return "当前固件存在多个重定位候选，未经人工确认不会进入 Restore 准备。"
            case .invalid:
                return "当前固件无效或已损坏，不会进入 Restore 准备。"
            case .available:
                return "当前固件未通过文件身份或 BuildManifest 验证，不会进入 Restore 准备。"
            }
        }
        if firmwareLibraryEntryID != nil && selectedFirmwareLibraryEntry == nil {
            return "当前固件库条目已失效，请重新扫描并选择，不会进入 Restore 准备。"
        }
        if firmwareValidity == .unverified {
            return "正在读取或复验固件信息。"
        }
        if firmwareValidity == .invalid {
            return errorMessage.isEmpty
                ? "当前固件无效或已损坏，不会进入 Restore 准备。"
                : "当前固件不可用于 Restore：\(errorMessage)"
        }
        return hardwareCompatibility.status == .unverified
            ? "固件文件有效，但缺少精确硬件身份或同一 BuildIdentity 证据；必须人工确认机型后继续。"
            : hardwareCompatibility.message
    }

    private var selectedFirmwareLibraryEntry: FirmwareLibraryEntry? {
        guard let firmwareLibraryEntryID else { return nil }
        return firmwareLibraryEntries.first {
            $0.id == firmwareLibraryEntryID
        }
    }

    private var selectedFirmwareLibraryEntryIsRestoreEligible: Bool {
        firmwareLibraryEntryID == nil
            || selectedFirmwareLibraryEntry?.isRestoreEligible == true
    }

    var selectedFirmwareReference: FirmwareReference? {
        if let entry = selectedFirmwareLibraryEntry {
            return FirmwareReference(entry: entry)
        }
        guard let firmwareURL,
              let firmwareFileIdentity else {
            return nil
        }
        return FirmwareReference(
            entryID: firmwareLibraryEntryID
                ?? FirmwareReference.syntheticEntryID(
                    identity: firmwareFileIdentity),
            url: firmwareURL,
            fileIdentity: firmwareFileIdentity,
            metadata: firmwareMetadata)
    }

    var recentFirmwareUses: [FirmwareUseRecord] {
        firmwarePreferences?.recentUsed ?? []
    }

    var globalDefaultFirmwareReference: FirmwareReference? {
        firmwarePreferences?.globalDefault
    }

    var modelDefaultFirmwareKeys: [String] {
        firmwarePreferences?.modelDefaults.keys.sorted() ?? []
    }

    func modelDefaultFirmwareReference(
        for key: ModelFamilyKey
    ) -> FirmwareReference? {
        firmwarePreferences?.modelDefault(for: key)
    }

    func resolveFirmwareReference(
        _ reference: FirmwareReference?
    ) -> FirmwareReferenceResolution? {
        guard let reference else { return nil }
        if let cached = firmwareReferenceResolutions[reference.cacheKey] {
            return cached
        }
        return firmwarePreferences?.resolve(
            reference,
            in: firmwareLibraryEntries)
    }

    func setSelectedFirmwareAsGlobalDefault() -> Bool {
        guard !isRestoreTaskActive,
              let preferences = firmwarePreferences,
              !preferences.persistenceIsBlocked,
              let reference = selectedFirmwareReference,
              let entry = selectedFirmwareLibraryEntry,
              entry.isRestoreEligible else {
            message = "请先选择通过 BuildManifest 与文件身份验证的 IPSW。"
            return false
        }
        guard preferences.setGlobalDefault(reference) else {
            message = preferences.loadError
                ?? "全局默认固件未能保存。"
            return false
        }
        firmwarePreferencesDidChange()
        message = "已将 \(reference.fileName) 设为全局默认固件。"
        return true
    }

    func setSelectedFirmwareAsModelDefault() -> Bool {
        guard !isRestoreTaskActive,
              let preferences = firmwarePreferences,
              !preferences.persistenceIsBlocked,
              let reference = selectedFirmwareReference,
              let entry = selectedFirmwareLibraryEntry,
              entry.isRestoreEligible else {
            message = "请先选择通过验证的 IPSW。"
            return false
        }
        guard let target = selectedTarget,
              let key = ModelFamilyKey.resolve(
                identity: target.firmwareIdentity) else {
            message = "当前设备机型尚未可靠识别，未创建机型默认。"
            return false
        }
        guard preferences.setModelDefault(reference, for: key) else {
            message = preferences.loadError
                ?? "机型默认固件未能保存。"
            return false
        }
        firmwarePreferencesDidChange()
        message =
            "已将 \(reference.fileName) 设为 \(key.rawValue) 的默认固件。"
        return true
    }

    func useFirmwareReference(_ reference: FirmwareReference) -> Bool {
        guard !isRestoreTaskActive,
              let resolution = resolveFirmwareReference(reference),
              resolution.isUsable,
              let entry = resolution.entry else {
            message = resolveFirmwareReference(reference)?.message
                ?? "该固件当前不可用。"
            return false
        }
        selectFirmwareFromLibrary(id: entry.id)
        return true
    }

    func clearGlobalFirmwareDefault() {
        guard let preferences = firmwarePreferences else {
            message = "固件偏好存储不可用，未修改全局默认固件。"
            return
        }
        guard preferences.clearGlobalDefault() else {
            message = preferences.loadError
                ?? "全局默认固件未能清除。"
            return
        }
        firmwarePreferencesDidChange()
    }

    func clearModelFirmwareDefault(for key: ModelFamilyKey) {
        guard let preferences = firmwarePreferences else {
            message = "固件偏好存储不可用，未修改机型默认固件。"
            return
        }
        guard preferences.clearModelDefault(for: key) else {
            message = preferences.loadError
                ?? "机型默认固件未能删除。"
            return
        }
        firmwarePreferencesDidChange()
    }

    @discardableResult
    func setGlobalFirmwareDefault(entryID: UUID) -> Bool {
        guard let preferences = firmwarePreferences else {
            message = "固件偏好存储不可用，未保存全局默认固件。"
            return false
        }
        guard !preferences.persistenceIsBlocked,
              let entry = firmwareLibraryEntries.first(where: {
            $0.id == entryID && $0.isRestoreEligible
        }) else {
            return false
        }
        guard preferences.setGlobalDefault(
            FirmwareReference(entry: entry)) else {
            message = preferences.loadError
                ?? "全局默认固件未能保存。"
            return false
        }
        firmwarePreferencesDidChange()
        message = "全局默认固件已保存。"
        return true
    }

    @discardableResult
    func setModelFirmwareDefault(
        entryID: UUID,
        modelFamilyKey: ModelFamilyKey
    ) -> Bool {
        guard let preferences = firmwarePreferences else {
            message = "固件偏好存储不可用，未保存机型默认固件。"
            return false
        }
        guard !preferences.persistenceIsBlocked,
              let entry = firmwareLibraryEntries.first(where: {
            $0.id == entryID && $0.isRestoreEligible
        }) else {
            return false
        }
        guard preferences.setModelDefault(
            FirmwareReference(entry: entry),
            for: modelFamilyKey) else {
            message = preferences.loadError
                ?? "机型默认固件未能保存。"
            return false
        }
        firmwarePreferencesDidChange()
        message = "机型默认固件已保存。"
        return true
    }

    func refreshFirmwarePreferenceResolutions() async {
        preferenceResolutionGeneration &+= 1
        let generation = preferenceResolutionGeneration
        guard let preferences = firmwarePreferences else {
            firmwareReferenceResolutions = [:]
            return
        }
        var references: [FirmwareReference] = []
        if let global = preferences.globalDefault {
            references.append(global)
        }
        references.append(contentsOf: preferences.modelDefaults.values)
        if let selected = preferences.lastSelected?.reference {
            references.append(selected)
        }
        if let lastUsed = preferences.lastUsed?.reference {
            references.append(lastUsed)
        }
        references.append(contentsOf: preferences.recentUsed.map(\.reference))

        var unique: [String: FirmwareReference] = [:]
        for reference in references {
            unique[reference.cacheKey] = reference
        }
        var resolutions: [String: FirmwareReferenceResolution] = [:]
        for (key, reference) in unique {
            guard !Task.isCancelled,
                  generation == preferenceResolutionGeneration else {
                return
            }
            let resolution =
                await firmwareLibrary.revalidateReference(reference)
            guard !Task.isCancelled,
                  generation == preferenceResolutionGeneration else {
                return
            }
            resolutions[key] = resolution
        }
        guard generation == preferenceResolutionGeneration else { return }
        firmwareReferenceResolutions = resolutions
        if !isRestoreTaskActive,
           firmwareSelectionSource != .userManualSelected {
            applyAutomaticRecommendation()
        }
    }

    func firmwarePreferencesDidChange() {
        guard !isRestoreTaskActive else { return }
        if firmwareSelectionSource != .userManualSelected {
            firmwareSelectionSource = .none
            applyAutomaticRecommendation()
        }
        preferenceResolutionTask?.cancel()
        preferenceResolutionTask = Task { @MainActor [weak self] in
            await self?.refreshFirmwarePreferenceResolutions()
        }
    }

    func refreshTargets() {
        if let observationHeartbeat {
            ingestHeartbeat(observationHeartbeat.latest)
        } else {
            latestHeartbeat = DeviceControlModel.ObservationHeartbeatSnapshot(
                observationSequence: latestHeartbeat.observationSequence,
                completedUptimeNs: latestHeartbeat.completedUptimeNs,
                observationResult: .failed(reason: "设备观察心跳通道不可用。"),
                devices: [])
            reconcileTargets([])
        }
    }

    func selectBrowsePort(_ key: String?) {
        let normalized = key?.isEmpty == true ? nil : key
        guard normalized != browsePortScope else { return }

        if isRestoreTaskActive {
            browsePortScope = normalized
            applyTargetProjection()
            return
        }

        clearPendingRestoreSelection()
        hasUserRestorePreparationContext = true
        suppressAutomaticRecommendation = true
        browsePortScope = normalized
        applyTargetProjection()
        if let onlyTarget = availableTargets.first,
           availableTargets.count == 1 {
            selectedTargetID = onlyTarget.id
            recomputeCompatibility()
        }
    }

    private var canPreparePrimary: Bool {
        activeAttempt == nil && runTask == nil && !engine.isRunning
    }

    func selectTarget(id: String) {
        guard canPreparePrimary,
              availableTargets.contains(where: { $0.id == id }) else {
            return
        }
        selectedTargetID = id
        hasUserRestorePreparationContext = true
        lockedTarget = nil
        suppressAutomaticRecommendation = false
        firmwareSelectionSource = .none
        recommendedFirmware = nil
        recomputeCompatibility()
        applyAutomaticRecommendation()
        scheduleHistoryStatisticsRefresh()
    }

    func loadFirmware(url: URL) async {
        guard canPreparePrimary else { return }
        hasUserRestorePreparationContext = true
        suppressAutomaticRecommendation = false
        isLoadingFirmware = true
        firmwareValidity = .unverified
        firmwareMetadata = nil
        firmwareFileIdentity = nil
        buildManifestSHA256 = ""
        firmwareSHA256 = ""
        errorMessage = ""
        defer { isLoadingFirmware = false }
        do {
            let entry = try await firmwareLibrary.addFile(url)
            firmwareLibraryEntries = await firmwareLibrary.allEntries()
            firmwareCandidates = firmwareLibraryEntries.map(\.url)
            firmwareLibraryMessage =
                "固件库已更新：\(firmwareLibraryEntries.count) 个固件条目。"
            applyFirmwareEntry(entry, selectionSource: .userManualSelected)
            await refreshFirmwarePreferenceResolutions()
        } catch {
            let reader = metadataReader
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try reader(url)
                }.value
                applyFirmwareResult(
                    url: url,
                    result: result,
                    selectionSource: .userManualSelected,
                    entryID: nil)
            } catch {
                firmwareURL = url
                firmwareValidity = .invalid
                firmwareMetadata = nil
                firmwareFileIdentity = nil
                buildManifestSHA256 = ""
                firmwareSelectionSource = .userManualSelected
                self.errorMessage = error.localizedDescription
                recomputeCompatibility()
            }
        }
    }

    // MARK: - P2-B 独立固件草稿（只准备，不执行）

    /// 当前设备对应的独立草稿（只读）。
    func firmwareDraftKeyForTesting(_ target: RestoreTarget) -> String? {
        stablePortKeyProvider(target)
    }

    func firmwareDraft(for target: RestoreTarget?) -> RestoreFirmwareDraft? {
        guard let target,
              let key = stablePortKeyProvider(target) else { return nil }
        return firmwareDrafts[key]
    }

    /// 草稿相对当前设备的可用状态；只读，不触碰执行状态。
    func firmwareDraftStatus(
        for target: RestoreTarget?
    ) -> RestoreFirmwareDraftStatus? {
        guard let target else { return nil }
        guard let draft = firmwareDraft(for: target) else { return nil }
        let unchanged = draft.fileUnchangedOnDisk()
        UIFixture.debugEvent("G4_DRAFT_STATUS", "key=\(draft.stablePortKey) ecid=\(draft.deviceECID) targetEcid=\(target.canonicalHex) gen=\(draft.connectionGeneration) targetGen=\(target.connectionGeneration) identity=\(draft.fileIdentity != nil) unchanged=\(unchanged) validity=\(draft.validity) compat=\(draft.compatibility.status) invalidation=\(String(describing: draft.invalidation)) manifest=\(draft.fileIdentity?.buildManifestSHA256.prefix(8) ?? "nil")")
        return RestoreFirmwareDraft.status(
            for: draft,
            target: target,
            fileUnchanged: draft.fileUnchangedOnDisk())
    }

    /// 为"查看中的第二台设备"准备固件草稿。
    ///
    /// 只写 `firmwareDrafts`，不修改 `firmwareURL` / `firmwareValidity` /
    /// `firmwareFileIdentity` / `selectedTarget` / `activeAttempt`，也不启动任何进程。
    /// 进入 B 准备页时自动带入一个已验证可用的固件草稿。
    /// 只自动“选择”，绝不自动启动；已有草稿/手动选择优先。
    @discardableResult
    func autoPrepareDraft(for target: RestoreTarget) async -> Bool {
        guard firmwareDraft(for: target) == nil else { return false }
        let family = ModelFamilyKey.resolve(identity: target.firmwareIdentity)
        func compatibleEntry(_ entry: FirmwareLibraryEntry?) -> FirmwareLibraryEntry? {
            guard let entry,
                  entry.isRestoreEligible,
                  FileManager.default.isReadableFile(atPath: entry.url.path),
                  let metadata = entry.metadata else { return nil }
            let compatibility = IPSWCompatibilityEvaluator.evaluate(
                metadata: metadata,
                target: RestoreTargetIdentity(
                    productType: target.productType,
                    deviceClass: target.deviceClass,
                    boardID: target.boardID,
                    chipID: target.chipID))
            guard compatibility.status != .incompatible else { return nil }
            return entry
        }
        func entry(id: UUID?) -> FirmwareLibraryEntry? {
            guard let id else { return nil }
            return firmwareLibraryEntries.first { $0.id == id }
        }
        func resolved(_ reference: FirmwareReference?) -> FirmwareLibraryEntry? {
            guard let reference,
                  let resolution = resolveFirmwareReference(reference),
                  resolution.isUsable else { return nil }
            return resolution.entry
        }
        var selected: FirmwareLibraryEntry?
        var source = ""
        if let family {
            selected = compatibleEntry(
                entry(id: modelDefaultCandidateIDProvider(family)))
                ?? compatibleEntry(resolved(firmwarePreferences?.modelDefault(for: family)))
            if selected != nil { source = "当前机型默认固件" }
        }
        if selected == nil {
            selected = compatibleEntry(
                entry(id: globalDefaultCandidateIDProvider()))
                ?? compatibleEntry(resolved(firmwarePreferences?.globalDefault))
            if selected != nil { source = "全局默认固件" }
        }
        if selected == nil, let family {
            for use in firmwarePreferences?.recentUses(matching: family) ?? [] {
                if let candidate = compatibleEntry(resolved(use.reference)) {
                    selected = candidate; source = "最近使用固件"; break
                }
            }
        }
        if selected == nil,
           let last = firmwarePreferences?.lastSelected,
           last.modelFamilyKey == family,
           let candidate = compatibleEntry(resolved(last.reference)) {
            selected = candidate; source = "上次选择固件"
        }
        if selected == nil {
            selected = firmwareLibraryEntries.first { compatibleEntry($0) != nil }
            if selected != nil { source = "兼容固件库推荐" }
        }
        let draftKey = stablePortKeyProvider(target)
            ?? "unattributed|\(target.portKey ?? target.canonicalHex)"
        guard let selected else {
            firmwareDraftMessageKey = draftKey
            firmwareDraftMessage = L10n.t(
                "没有找到当前设备可用且兼容的固件；请手动选择 IPSW。")
            return false
        }
        let ok = await prepareFirmwareDraft(for: target, url: selected.url)
        if ok {
            firmwareDraftMessageKey = draftKey
            firmwareDraftMessage = L10n.t("已自动选择")
                + "：" + L10n.t(source)
                + " · " + selected.url.lastPathComponent
        }
        return ok
    }

    func prepareFirmwareDraft(
        for target: RestoreTarget,
        url: URL
    ) async -> Bool {
        firmwareDraftMessage = ""
        let reader = metadataReader
        guard let draftKey = stablePortKeyProvider(target) else {
            firmwareDraftMessage = L10n.t(
                "无法确定该设备的稳定端口键，已拒绝保存可执行草稿。")
            firmwareDraftMessageKey = nil
            return false
        }
        let previous = firmwareDrafts[draftKey]
        let result = try? await Task.detached(priority: .userInitiated) {
            try reader(url)
        }.value
        let entry = try? await firmwareLibrary.addFile(url)
        guard result != nil || entry != nil else {
            firmwareDraftMessage = L10n.t("无法读取该 IPSW 的固件信息；草稿未保存。")
            firmwareDraftMessageKey = draftKey
            return false
        }
        let identity = entry?.fileIdentity
            ?? result?.fileIdentity
            ?? (try? IPSWMetadataReader.fileIdentity(
                url: url,
                buildManifestSHA256: result?.buildManifestSHA256 ?? ""))
        let validity = entry?.validity ?? result?.validity ?? .unverified
        let metadata = entry?.metadata ?? result?.metadata
        let compatibility: HardwareCompatibility
        if let metadata {
            compatibility = IPSWCompatibilityEvaluator.evaluate(
                metadata: metadata,
                target: RestoreTargetIdentity(
                    productType: target.productType,
                    deviceClass: target.deviceClass,
                    boardID: target.boardID,
                    chipID: target.chipID))
        } else {
            compatibility = Self.defaultCompatibility
        }
        let key = draftKey
        let now = Date()
        firmwareDrafts[key] = RestoreFirmwareDraft(
            id: previous?.id ?? UUID(),
            stablePortKey: key,
            deviceECID: target.canonicalHex,
            connectionGeneration: target.connectionGeneration,
            locationID: target.locationID,
            deviceDisplayName: target.displayName,
            ipswURL: url,
            libraryEntryID: entry?.id,
            fileIdentity: identity,
            productVersion: metadata?.productVersion,
            productBuild: metadata?.productBuild,
            validity: validity,
            compatibility: compatibility,
            createdAt: previous?.createdAt ?? now,
            updatedAt: now,
            invalidation: nil)
        firmwareDraftMessageKey = key
        if validity != .valid {
            firmwareDraftMessage = L10n.t(
                "固件未通过验证；草稿已保留，但不能直接用于启动。")
        } else if compatibility.status == .incompatible {
            firmwareDraftMessage = L10n.t(
                "固件与当前设备不兼容；草稿已保留，但不能直接用于启动。")
        } else if compatibility.status == .unverified {
            firmwareDraftMessage = L10n.t(
                "兼容性未确认，需人工核验后才能使用。")
        } else {
            firmwareDraftMessage = L10n.t(
                "固件草稿已保存；可在 A 运行时手动启动 B。")
        }
        return true
    }

    /// 同一稳定端口 + 同一 ECID 的正常心跳刷新：只更新代际，不把草稿打成失效。
    /// 换机/文件变化/兼容性不足仍由 status 拒绝。
    @discardableResult
    func revalidateDraftIfSameDevice(for target: RestoreTarget) -> Bool {
        guard let key = stablePortKeyProvider(target),
              var draft = firmwareDrafts[key],
              draft.stablePortKey == key,
              draft.deviceECID.caseInsensitiveCompare(target.canonicalHex) == .orderedSame,
              draft.validity == .valid,
              draft.compatibility.status != .incompatible,
              draft.fileIdentity != nil,
              draft.fileUnchangedOnDisk() else { return false }
        guard draft.connectionGeneration != target.connectionGeneration else {
            return draft.invalidation == nil
        }
        draft.connectionGeneration = target.connectionGeneration
        draft.updatedAt = Date()
        draft.invalidation = nil
        firmwareDrafts[key] = draft
        return true
    }

    func discardFirmwareDraft(for target: RestoreTarget?) {
        guard let target,
              let key = stablePortKeyProvider(target) else { return }
        firmwareDrafts[key] = nil
        if firmwareDraftMessageKey == key {
            firmwareDraftMessage = ""
            firmwareDraftMessageKey = nil
        }
    }

    /// 只显示与当前设备键匹配的草稿消息，避免 B 的消息显示在 C 的卡片下。
    func firmwareDraftMessage(for target: RestoreTarget?) -> String {
        guard let target,
              let key = stablePortKeyProvider(target),
              firmwareDraftMessageKey == key else { return "" }
        return firmwareDraftMessage
    }

    func scanFirmwareDirectory(_ directory: URL) async {
        guard !isRestoreTaskActive else { return }
        hasUserRestorePreparationContext = true
        isLoadingFirmware = true
        defer { isLoadingFirmware = false }
        do {
            let result = try await firmwareLibrary.addDirectory(directory)
            firmwareLibraryEntries = result.entries
            firmwareLibraryRoots = await firmwareLibrary.libraryRoots()
            refreshFirmwareDirectoryWatcher()
            _ = firmwarePreferences?.reconcileStaleIdentitiesIfContentUnchanged(
                in: result.entries)
            firmwareCandidates = result.entries.map(\.url)
            firmwareLibraryMessage = libraryMessage(for: result)
            await refreshFirmwarePreferenceResolutions()
            retryAutomaticFirmwareSelectionIfNeeded()
        } catch {
            firmwareLibraryMessage =
                "固件目录未完成索引：\(error.localizedDescription)"
        }
    }

    func loadFirmwareLibrary() async {
        do {
            firmwareLibraryEntries = try await firmwareLibrary.loadEntries()
            _ = firmwarePreferences?.reconcileStaleIdentitiesIfContentUnchanged(
                in: firmwareLibraryEntries)
            firmwareCandidates = firmwareLibraryEntries.map(\.url)
            firmwareLibraryRoots = await firmwareLibrary.libraryRoots()
            refreshFirmwareDirectoryWatcher()
            let ignoredTemporary =
                await firmwareLibrary.ignoredTemporaryEntryCount()
            firmwareLibraryMessage =
                ignoredTemporary > 0
                    ? "已恢复 \(firmwareLibraryEntries.count) 个本地固件索引；已隔离 \(ignoredTemporary) 个遗留临时测试条目。"
                    : "已恢复 \(firmwareLibraryEntries.count) 个本地固件索引。"
            await refreshFirmwarePreferenceResolutions()
            retryAutomaticFirmwareSelectionIfNeeded()
            if autoScanFirmwareOnLaunch, !didAutoDiscoverFirmware {
                didAutoDiscoverFirmware = true
                startFirmwareDiscovery()
            }
        } catch {
            firmwareLibraryMessage =
                "固件索引无法读取：\(error.localizedDescription)"
        }
    }

    func refreshFirmwareLibrary() async {
        guard !isRestoreTaskActive else { return }
        hasUserRestorePreparationContext = true
        do {
            let result = try await firmwareLibrary.refresh()
            firmwareLibraryEntries = result.entries
            firmwareLibraryRoots = await firmwareLibrary.libraryRoots()
            refreshFirmwareDirectoryWatcher()
            _ = firmwarePreferences?.reconcileStaleIdentitiesIfContentUnchanged(
                in: result.entries)
            firmwareCandidates = result.entries.map(\.url)
            firmwareLibraryMessage = libraryMessage(for: result)
            await refreshFirmwarePreferenceResolutions()
            retryAutomaticFirmwareSelectionIfNeeded()
        } catch {
            firmwareLibraryMessage =
                "固件库刷新失败：\(error.localizedDescription)"
        }
    }

    /// Single-flight lightweight discovery. The main actor only manages
    /// state; mdfind and ZIP metadata reads run in their own actors.
    func startFirmwareDiscovery() {
        switch FirmwareDiscoveryPolicy.action(
            isRestoreActive: isRestoreTaskActive,
            isScanning: isFirmwareDiscoveryActive) {
        case .deferForRestore:
            firmwareDiscoveryPending = true
            firmwareDiscoveryMessage = "Restore 进行中，自动固件扫描已延后。"
            return
        case .coalesce:
            firmwareDiscoveryPending = true
            return
        case .start:
            break
        }
        firmwareDiscoveryPending = false
        isFirmwareDiscoveryActive = true
        firmwareDiscoveryMessage = L10n.t("正在扫描本地 IPSW…")
        firmwareDiscoveryTask = Task(priority: .utility) { [weak self] in
            await self?.performFirmwareDiscovery()
        }
    }

    private func refreshFirmwareDirectoryWatcher() {
        firmwareDirectoryWatcher.onChange = { [weak self] in
            self?.startFirmwareDiscovery()
        }
        firmwareDirectoryWatcher.update(roots: firmwareLibraryRoots)
    }

    func cancelFirmwareDiscovery() {
        firmwareDiscoveryTask?.cancel()
        let service = firmwareDiscoveryService
        Task { await service.cancel() }
        firmwareDiscoveryTask = nil
        firmwareDiscoveryPending = false
        isFirmwareDiscoveryActive = false
        firmwareDiscoveryMessage = "固件扫描已取消。"
    }

    func resumeDeferredFirmwareDiscoveryIfNeeded() {
        guard firmwareDiscoveryPending, !isRestoreTaskActive else { return }
        startFirmwareDiscovery()
    }

    func removeFirmwareDirectory(_ directory: URL) async {
        do {
            let entries = try await firmwareLibrary.removeRoot(directory)
            firmwareLibraryEntries = entries
            firmwareLibraryRoots = await firmwareLibrary.libraryRoots()
            refreshFirmwareDirectoryWatcher()
            firmwareCandidates = entries.map(\.url)
            firmwareLibraryMessage = "已移除固件目录；文件本身未删除。"
            await refreshFirmwarePreferenceResolutions()
            retryAutomaticFirmwareSelectionIfNeeded()
        } catch {
            firmwareLibraryMessage =
                "移除固件目录失败：\(error.localizedDescription)"
        }
    }

    private func performFirmwareDiscovery() async {
        let roots = await firmwareLibrary.libraryRoots()
        let urls = await firmwareDiscoveryService.discoverIPSWURLs(
            roots: roots,
            home: FileManager.default.homeDirectoryForCurrentUser)
        if Task.isCancelled {
            isFirmwareDiscoveryActive = false
            firmwareDiscoveryTask = nil
            return
        }
        guard !isRestoreTaskActive else {
            isFirmwareDiscoveryActive = false
            firmwareDiscoveryTask = nil
            firmwareDiscoveryPending = true
            firmwareDiscoveryMessage = "Restore 进行中，自动固件扫描已延后。"
            return
        }
        do {
            let result = try await firmwareLibrary.refresh(
                discoveredURLs: urls,
                pruneMissing: true)
            firmwareLibraryEntries = result.entries
            firmwareLibraryRoots = await firmwareLibrary.libraryRoots()
            refreshFirmwareDirectoryWatcher()
            _ = firmwarePreferences?.reconcileStaleIdentitiesIfContentUnchanged(
                in: result.entries)
            firmwareCandidates = result.entries.map(\.url)
            firmwareLibraryMessage = libraryMessage(for: result)
            await refreshFirmwarePreferenceResolutions()
            retryAutomaticFirmwareSelectionIfNeeded()
            firmwareDiscoveryMessage = result.scanIncomplete
                ? L10n.t("扫描完成（部分目录受权限或上限限制）。")
                : L10n.t("扫描完成。") + " \(result.discoveredCount)"
        } catch {
            firmwareDiscoveryMessage =
                "固件扫描未完成：\(error.localizedDescription)"
        }
        isFirmwareDiscoveryActive = false
        firmwareDiscoveryTask = nil
        if firmwareDiscoveryPending, !isRestoreTaskActive {
            firmwareDiscoveryPending = false
            startFirmwareDiscovery()
        }
    }

    func selectFirmwareFromLibrary(id: UUID) {
        guard !isRestoreTaskActive,
              let entry = firmwareLibraryEntries.first(where: { $0.id == id }) else {
            return
        }
        hasUserRestorePreparationContext = true
        suppressAutomaticRecommendation = false
        recommendedFirmware = nil
        applyFirmwareEntry(entry, selectionSource: .userManualSelected)
    }

    /// 固件库异步到达后，按最新目标/手动选择状态重算默认固件。
    /// 不改变推荐优先级；手动选择、活动任务和明确失效默认由既有逻辑处理。
    func retryAutomaticFirmwareSelectionIfNeeded() {
        guard !isRestoreTaskActive,
              selectedTarget != nil,
              firmwareSelectionSource != .userManualSelected else {
            return
        }
        applyAutomaticRecommendation()
    }

    func restoreAutomaticRecommendation() {
        guard !isRestoreTaskActive else { return }
        hasUserRestorePreparationContext = true
        suppressAutomaticRecommendation = false
        firmwareSelectionSource = .none
        firmwareLibraryEntryID = nil
        recommendedFirmware = nil
        applyAutomaticRecommendation()
    }

    func resumeAutomaticNavigationAfterUserAction() {
        guard !isRestoreTaskActive else { return }
        hasUserRestorePreparationContext = false
    }

    func computeFirmwareSHA256() async {
        guard !isRestoreTaskActive, let firmwareURL else { return }
        isComputingHash = true
        defer { isComputingHash = false }
        firmwareSHA256 = await Task.detached(priority: .utility) {
            (try? RestoreWorkspaceModel.sha256(ofFileAt: firmwareURL)) ?? ""
        }.value
    }

    func setRawSaveRequestedThisRun(_ value: Bool) {
        guard !isRestoreTaskActive else { return }
        hasUserRestorePreparationContext = true
        rawSaveSelectionExplicit = true
        rawSaveRequestedThisRun = value
        if let target = selectedTarget {
            let key = stablePortKeyProvider(target) ?? target.portKey ?? target.id
            rawSaveSelectionExplicitPorts.insert(key)
            rawSaveRequestedByPort[key] = value
        }
    }

    func rawSaveRequested(for target: RestoreTarget?) -> Bool {
        guard let target else { return rawSaveRequestedThisRun }
        let key = stablePortKeyProvider(target) ?? target.portKey ?? target.id
        return rawSaveRequestedByPort[key]
            ?? rawPersistenceDefaultsProvider().autoSaveDefault
    }

    func isTaskActive(for target: RestoreTarget?) -> Bool {
        guard let target else { return isRestoreTaskActive }
        return currentTask?.target.id == target.id
            || secondaryTask?.target.id == target.id
    }

    func setRawSaveRequested(_ value: Bool, for target: RestoreTarget?) {
        guard let target,
              !isTaskActive(for: target) else { return }
        let key = stablePortKeyProvider(target) ?? target.portKey ?? target.id
        hasUserRestorePreparationContext = true
        rawSaveSelectionExplicitPorts.insert(key)
        rawSaveRequestedByPort[key] = value
        rawSaveRequestedThisRun = value
    }

    func refreshRawSaveSelectionFromSettingsIfNeeded() {
        guard !isRestoreTaskActive,
              !rawSaveSelectionExplicit else {
            return
        }
        rawSaveRequestedThisRun =
            rawPersistenceDefaultsProvider().autoSaveDefault
    }

    func successDurationReference(
        for target: RestoreTarget,
        metadata: IPSWMetadata? = nil
    ) -> RestoreSuccessDurationReference? {
        successDurationReference(
            for: target,
            productVersion: metadata?.productVersion,
            productBuild: metadata?.productBuild)
    }

    func successDurationReference(
        for target: RestoreTarget,
        productVersion: String?,
        productBuild: String?
    ) -> RestoreSuccessDurationReference? {
        RestoreSuccessDurationMatcher.match(
            records: historyRecords,
            target: target,
            productVersion: productVersion,
            productBuild: productBuild)
    }

    func loadRestoreHistory() async {
        do {
            let records = try await historyStore.records()
            historyRecords = records
            historyUsageRecords =
                (try? await historyStore.firmwareUsageRecords()) ?? []
            restoreHistoryMessage = records.isEmpty
                ? "暂无可信恢复历史。"
                : "已载入 \(records.count) 条轻量恢复历史。"
            await refreshRestoreHistoryStatistics()
            applyAutomaticRecommendation()
        } catch {
            historyUsageRecords = []
            restoreHistoryStatistics = .empty
            restoreHistoryMessage =
                "历史库不可用；手动 IPSW 选择仍可正常使用。"
        }
    }

    func linkedTaskIDs(
        forRLMSessionID sessionID: String
    ) async -> [UUID] {
        do {
            return try await historyStore.records()
                .filter { $0.rlmSessionID == sessionID }
                .map(\.taskID)
        } catch {
            return []
        }
    }

    private func beginRestoreAfterConfirmation() async {
        // 每次启动尝试先清空上一次的提示，避免把旧错误带进本次拒绝。
        errorMessage = ""
        message = ""

        guard activeAttempt == nil,
              runTask == nil,
              !engine.isRunning else {
            errorMessage = L10n.t(
                "当前已有首任务正在运行，请先完成当前任务。")
            return
        }
        guard taskRegistry.activeCount < taskRegistry.capacity else {
            errorMessage = L10n.t("当前已有两个 Restore 任务，无法再启动第三个。")
            return
        }

        guard let target = selectedTarget,
              let cfgutilURL,
              let firmwareURL,
              let firmwareFileIdentity else {
            errorMessage = startDisabledReason
            return
        }
        guard firmwareValidity == .valid else {
            errorMessage = startDisabledReason
            return
        }
        guard hardwareCompatibility.status == .compatible else {
            var missing: [String] = []
            if target.productType == nil { missing.append("ProductType") }
            if target.deviceClass == nil { missing.append("DeviceClass") }
            if target.boardID == nil { missing.append("BoardID") }
            if target.chipID == nil { missing.append("ChipID") }
            errorMessage = missing.isEmpty
                ? L10n.t("固件尚未通过本机 BuildIdentity 精确验证，已拒绝启动。")
                : L10n.t("目标身份缺少必需字段：")
                    + missing.joined(separator: "、")
                    + L10n.t("；已保留 IPSW，修正前禁止启动。")
            return
        }
        // 机器级租约：首个任务取得，第二任务通过份额加入；最后一个收尾后释放。
        guard acquireLeaseShare() else { return }

        let attemptID = UUID()
        let userConfirmed = RestoreLifecycleClock.now()
        let rawPolicy = rawPersistenceDefaultsProvider().policy(
            saveThisRun: rawSaveRequested(for: target))
        let stablePortKey = stablePortKeyProvider(target) ?? target.portKey
        let taskDirectory = rawPolicy.saveThisRun
            ? outputRoot.appendingPathComponent(
                attemptID.uuidString,
                isDirectory: true)
            : nil

        lockedTarget = target
        let lifecycle = RestoreLifecycleTimes(
            userConfirmed: userConfirmed)
        let attempt = PendingRestoreAttempt(
            attemptID: attemptID,
            taskID: attemptID,
            target: target,
            canonicalECID: target.canonicalHex,
            stablePortKey: stablePortKey,
            portDisplayName: target.portDisplayName,
            ipswURL: firmwareURL,
            ipswIdentity: firmwareFileIdentity,
            firmwareLibraryEntryID: firmwareLibraryEntryID,
            buildManifestSHA256: buildManifestSHA256,
            rawPersistencePolicy: rawPolicy,
            userConfirmedAt: userConfirmed,
            stage: .waitingForFreshHeartbeat,
            lifecycle: lifecycle)
        let initialTask = RestoreTaskSnapshot(
            id: attemptID,
            attemptID: attemptID,
            target: target,
            ipswURL: firmwareURL,
            ipswIdentity: firmwareFileIdentity,
            firmwareLibraryEntryID: firmwareLibraryEntryID,
            buildManifestSHA256: buildManifestSHA256,
            wholeFileSHA256: firmwareSHA256.isEmpty ? nil : firmwareSHA256,
            rawOutputDirectory: taskDirectory,
            metadata: firmwareMetadata,
            compatibility: hardwareCompatibility,
            rlmStatus: .notRequested,
            rlmOwnership: .notRequested,
            rlmFinalizedAt: nil,
            rlmDrainDurationSeconds: nil,
            rlmRawLogURL: nil,
            rawPersistencePolicy: rawPolicy,
            rawEvidenceStatus: rawPolicy.saveThisRun
                ? .incompleteProtected
                : .notSavedByChoice,
            lifecycle: lifecycle,
            attemptStage: .waitingForFreshHeartbeat,
            userConfirmedAt: userConfirmed.wallTime,
            phase: .userConfirmed,
            outcome: nil)
        do {
            try taskRegistry.reserve(
                attemptID: attemptID,
                canonicalECID: attempt.canonicalECID,
                portKey: attempt.stablePortKey ?? target.portKey)
        } catch {
            lockedTarget = nil
            releaseLeaseShare()
            errorMessage = L10n.t("任务注册失败，已拒绝启动。")
            return
        }
        executionSlot = RestoreExecutionSlot(
            attempt: attempt,
            task: initialTask)

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runRestoreAttempt(
                attemptID: attemptID,
                target: target,
                cfgutilURL: cfgutilURL,
                firmwareURL: firmwareURL,
                expectedIPSWIdentity: firmwareFileIdentity,
                taskDirectory: taskDirectory)
        }
        runTask = task
        await task.value
        releaseLeaseShare()
    }

    /// G2：零占用时把任一端口路由到首任务入口；一占用时走并发入口。
    /// 两个入口共享 capacity-2 registry 与 P1 份额。
    @discardableResult
    func freezeRestoreConfirmation(targetID: String) -> Bool {
        guard let target = availableTargets.first(where: { $0.id == targetID }) else {
            errorMessage = L10n.t("目标已不在可用列表中，无法确认。")
            return false
        }
        let draft = firmwareDraft(for: target)
        let identity: IPSWFileIdentity?
        let url: URL?
        let manifest: String
        if let draft {
            identity = draft.fileIdentity
            url = draft.ipswURL
            manifest = draft.fileIdentity?.buildManifestSHA256 ?? ""
        } else if targetID == selectedTargetID {
            identity = firmwareFileIdentity
            url = firmwareURL
            manifest = buildManifestSHA256
        } else {
            identity = nil; url = nil; manifest = ""
        }
        guard let url, let identity else {
            errorMessage = L10n.t("尚无已校验的 IPSW，无法确认。")
            return false
        }
        frozenRestoreConfirmation = RestoreConfirmationToken(
            tokenID: UUID(),
            targetID: target.id,
            canonicalECID: target.canonicalHex,
            portKey: stablePortKeyProvider(target) ?? target.portKey,
            connectionGeneration: target.connectionGeneration,
            ipswURL: url,
            fileIdentity: identity,
            buildManifestSHA256: manifest,
            rawSaveRequested: rawSaveRequested(for: target),
            createdAt: Date())
        return true
    }

    func invalidateRestoreConfirmation() {
        frozenRestoreConfirmation = nil
    }

    private func validateFrozenConfirmation(
        target: RestoreTarget,
        draft: RestoreFirmwareDraft?
    ) -> String? {
        guard let token = frozenRestoreConfirmation else { return L10n.t("确认已失效，请重新确认。") }
        guard token.targetID == target.id,
              token.canonicalECID.caseInsensitiveCompare(target.canonicalHex) == .orderedSame,
              token.portKey == (stablePortKeyProvider(target) ?? target.portKey),
              token.connectionGeneration == target.connectionGeneration,
              token.rawSaveRequested == rawSaveRequested(for: target) else {
            return L10n.t("确认对象已变化，请重新确认。")
        }
        let currentIdentity = draft?.fileIdentity ?? firmwareFileIdentity
        let currentURL = draft?.ipswURL ?? firmwareURL
        guard currentURL?.standardizedFileURL == token.ipswURL.standardizedFileURL,
              currentIdentity == token.fileIdentity,
              (draft?.fileIdentity?.buildManifestSHA256 ?? buildManifestSHA256)
                == token.buildManifestSHA256 else {
            return L10n.t("IPSW 或文件身份已变化，请重新确认。")
        }
        return nil
    }

    @discardableResult
    func beginUnifiedRestoreAfterConfirmation(targetID: String) async -> Bool {
        if canPreparePrimary {
            guard let target = availableTargets.first(where: { $0.id == targetID }) else {
                errorMessage = L10n.t("目标已不在可用列表中，已拒绝启动。")
                return false
            }
            let draft = firmwareDraft(for: target)
            if let issue = validateFrozenConfirmation(target: target, draft: draft) {
                errorMessage = issue
                return false
            }
            let confirmedURL = draft?.ipswURL
                ?? (target.id == selectedTargetID ? firmwareURL : nil)
            guard let confirmedURL else {
                errorMessage = L10n.t("该设备的固件尚未准备，已拒绝启动。")
                return false
            }
            selectTarget(id: target.id)
            await loadFirmware(url: confirmedURL)
            guard selectedTarget?.id == target.id,
                  let token = frozenRestoreConfirmation,
                  firmwareFileIdentity == token.fileIdentity,
                  buildManifestSHA256 == token.buildManifestSHA256 else {
                errorMessage = L10n.t("IPSW 文件身份在确认期间已变化，请重新确认。")
                return false
            }
            frozenRestoreConfirmation = nil
            let before = lastCompletedTaskSnapshot?.id
            await beginRestoreAfterConfirmation()
            let changed = lastCompletedTaskSnapshot?.id != nil
                && lastCompletedTaskSnapshot?.id != before
            UIFixture.debugEvent("G4_UNIFIED_RESULT", "target=\(target.id) current=\(currentTask != nil) lastChanged=\(changed) err=\(errorMessage.prefix(60)) fail=\(lastCompletedTaskSnapshot?.failureText.prefix(80) ?? "")")
            return currentTask != nil || changed
        }
        guard let target = availableTargets.first(where: { $0.id == targetID }) else {
            errorMessage = L10n.t("目标已不在可用列表中，已拒绝启动。")
            return false
        }
        let draft = firmwareDraft(for: target)
        if let issue = validateFrozenConfirmation(target: target, draft: draft) {
            errorMessage = issue
            return false
        }
        frozenRestoreConfirmation = nil
        return await beginSecondaryRestoreAfterConfirmation(targetID: targetID)
    }

    // MARK: - 切片 2：第二任务（复用 P3-A 双任务核心，租约由本模型持有）

    var hasSecondaryRestore: Bool { secondaryTask != nil }

    var canStartSecondaryRestore: Bool {
        currentTask != nil && secondaryTask == nil && secondaryAttempt == nil
    }

    private func secondaryTargetStillValid() -> Bool {
        guard let attempt = secondaryAttempt,
              let draft = secondaryDraft else {
            UIFixture.debugEvent("B_SPAWN_CHECK", "fail=missing")
            return false
        }
        guard draft.fileUnchangedOnDisk() else {
            UIFixture.debugEvent("B_SPAWN_CHECK", "fail=draftChanged")
            return false
        }
        let heartbeat = observationHeartbeat?.latest ?? latestHeartbeat
        guard heartbeat.isFreshSuccess(
            atUptimeNs: DispatchTime.now().uptimeNanoseconds,
            maximumAgeNs: UInt64(maximumSnapshotAge * 1_000_000_000)) else {
            UIFixture.debugEvent("B_SPAWN_CHECK", "fail=stale")
            return false
        }
        let matches = allAvailableTargets.filter {
            $0.canonicalHex == attempt.canonicalECID
        }
        guard matches.count == 1, let current = matches.first else {
            UIFixture.debugEvent(
                "B_SPAWN_CHECK", "fail=matches=\(matches.count)")
            return false
        }
        let fields: [(String, Bool)] = [
            ("port", current.portKey == attempt.target.portKey),
            ("location", current.locationID == attempt.target.locationID),
            ("generation", current.connectionGeneration == attempt.target.connectionGeneration),
            ("provenance", current.identityProvenance == attempt.target.identityProvenance),
            ("product", current.productType == attempt.target.productType),
            ("class", current.deviceClass == attempt.target.deviceClass),
            ("board", current.boardID == attempt.target.boardID),
            ("chip", current.chipID == attempt.target.chipID),
            ("machine", current.machineIdentifier == attempt.target.machineIdentifier),
            ("mode", current.mode == attempt.target.mode),
        ]
        if let bad = fields.first(where: { !$0.1 }) {
            UIFixture.debugEvent("B_SPAWN_CHECK", "fail=identity:\(bad.0)")
            return false
        }
        UIFixture.debugEvent("B_SPAWN_CHECK", "ok")
        return true
    }

    @discardableResult
    private func beginSecondaryRestoreAfterConfirmation(targetID: String) async -> Bool {
        UIFixture.debugEvent("B_MODEL_START_ENTER", "target=\(targetID)")
        errorMessage = ""
        message = ""
        guard let primaryTask = currentTask,
              activeAttempt != nil else {
            errorMessage = L10n.t("请先开始第一台 Restore。")
            UIFixture.debugEvent("B_ADMISSION_RESULT", "reject=noPrimary")
            return false
        }
        guard secondaryTask == nil, secondaryAttempt == nil else {
            errorMessage = L10n.t("当前已有两个 Restore 任务，无法再启动第三个。")
            UIFixture.debugEvent("B_ADMISSION_RESULT", "reject=capacity")
            return false
        }
        guard let target = allAvailableTargets.first(where: { $0.id == targetID }) else {
            errorMessage = L10n.t("第二台设备已不在可用目标中，请重新核验。")
            UIFixture.debugEvent("B_ADMISSION_RESULT", "reject=targetGone")
            return false
        }
        guard target.canonicalHex.caseInsensitiveCompare(
                primaryTask.target.canonicalHex) != .orderedSame else {
            errorMessage = L10n.t("第二台与第一台是同一设备，已拒绝。")
            UIFixture.debugEvent("B_ADMISSION_RESULT", "reject=sameECID")
            return false
        }
        guard let port = target.portKey, !port.isEmpty,
              port != primaryTask.target.portKey else {
            errorMessage = L10n.t("第二台与第一台占用同一物理端口，已拒绝。")
            UIFixture.debugEvent("B_ADMISSION_RESULT", "reject=samePort")
            return false
        }
        // 与 A 相同的身份门禁：ECID 必须唯一，观察必须新鲜。
        guard allAvailableTargets.filter({ $0.canonicalHex == target.canonicalHex }).count == 1 else {
            errorMessage = L10n.t("第二台设备身份不唯一，已拒绝启动。")
            UIFixture.debugEvent("B_ADMISSION_RESULT", "reject=duplicateECID")
            return false
        }
        let heartbeat = observationHeartbeat?.latest ?? latestHeartbeat
        guard heartbeat.isFreshSuccess(
            atUptimeNs: DispatchTime.now().uptimeNanoseconds,
            maximumAgeNs: UInt64(maximumSnapshotAge * 1_000_000_000)) else {
            errorMessage = L10n.t("设备观察快照不新鲜，已拒绝启动第二台。")
            UIFixture.debugEvent("B_ADMISSION_RESULT", "reject=staleHeartbeat")
            return false
        }
        // RLM 承诺在 A 完成 prepare 后才写入；准备阶段加入 B 会形成竞态。
        let rlmReadyStages: [PendingRestoreAttemptStage] = [
            .readyToLaunch, .processLaunching, .processRunning,
            .processExited, .bothStreamsEOF, .outcomeConfirmed,
        ]
        guard rlmReadyStages.contains(primaryTask.attemptStage) else {
            errorMessage = L10n.t(
                "第一台仍在确认目标与日志策略，请稍后再加入第二台。")
            UIFixture.debugEvent("B_ADMISSION_RESULT", "reject=primaryStage")
            return false
        }
        guard let draft = firmwareDraft(for: target),
              firmwareDraftStatus(for: target) == .ready,
              draft.fileUnchangedOnDisk() else {
            errorMessage = L10n.t("第二台的固件草稿未就绪或文件已变化。")
            UIFixture.debugEvent("B_ADMISSION_RESULT", "reject=draft")
            return false
        }
        // 与首任务同等：启动前重读完整文件身份与 BuildManifest。
        guard let expected = draft.fileIdentity else {
            errorMessage = L10n.t("第二台缺少已冻结的文件身份，已拒绝启动。")
            return false
        }
        guard let rereadResult = try? metadataReader(draft.ipswURL) else {
            errorMessage = L10n.t("第二台的 IPSW 无法重新读取，已拒绝启动。")
            return false
        }
        guard rereadResult.validity == .valid,
              rereadResult.metadata != nil else {
            errorMessage = L10n.t("第二台的 IPSW 当前内容无效，已拒绝启动。")
            return false
        }
        let currentManifest = rereadResult.buildManifestSHA256
        guard let actual = rereadResult.fileIdentity else {
            errorMessage = L10n.t("第二台当前 IPSW 缺少文件身份，已拒绝启动。")
            return false
        }
        guard !expected.buildManifestSHA256.isEmpty,
              !currentManifest.isEmpty else {
            errorMessage = L10n.t("第二台缺少有效的 BuildManifest 身份，已拒绝启动。")
            return false
        }
        guard currentManifest == expected.buildManifestSHA256,
              actual.buildManifestSHA256 == expected.buildManifestSHA256,
              actual.buildManifestSHA256 == currentManifest else {
            errorMessage = L10n.t(
                "第二台的 IPSW 文件身份或 BuildManifest 已变化，已拒绝启动。")
            return false
        }
        guard actual == expected else {
            errorMessage = L10n.t(
                "第二台的 IPSW 文件身份或 BuildManifest 已变化，已拒绝启动。")
            return false
        }
        let primary = primaryTask
        if primary.rlmOwnership != .notRequested
            || primary.rlmStatus == .recordingReused
            || primary.rlmStatus == .startedOwnedSession
            || primary.rlmRawLogURL != nil {
            errorMessage = L10n.t(
                "第一台正在使用独立 RLM 日志，无法安全加入第二台；第二台草稿已保留。")
            UIFixture.debugEvent("B_ADMISSION_RESULT", "reject=rlm")
            return false
        }
        guard let cfgutilURL else {
            errorMessage = L10n.t("未找到可执行的 cfgutil。")
            UIFixture.debugEvent("B_ADMISSION_RESULT", "reject=cfgutil")
            return false
        }
        guard acquireLeaseShare() else { return false }

        let attemptID = UUID()
        let confirmed = RestoreLifecycleClock.now()
        let rawPolicy = rawPersistenceDefaultsProvider().policy(
            saveThisRun: rawSaveRequested(for: target))
        let directory = rawPolicy.saveThisRun
            ? outputRoot.appendingPathComponent(attemptID.uuidString, isDirectory: true)
            : nil
        let attempt = PendingRestoreAttempt(
            attemptID: attemptID,
            taskID: attemptID,
            target: target,
            canonicalECID: target.canonicalHex,
            stablePortKey: stablePortKeyProvider(target),
            portDisplayName: target.portDisplayName,
            ipswURL: draft.ipswURL,
            ipswIdentity: draft.fileIdentity,
            firmwareLibraryEntryID: draft.libraryEntryID,
            buildManifestSHA256: draft.fileIdentity?.buildManifestSHA256 ?? "",
            rawPersistencePolicy: rawPolicy,
            userConfirmedAt: confirmed,
            stage: .waitingForFreshHeartbeat,
            lifecycle: RestoreLifecycleTimes(userConfirmed: confirmed))
        let task = RestoreTaskSnapshot(
            id: attemptID,
            attemptID: attemptID,
            target: target,
            ipswURL: draft.ipswURL,
            ipswIdentity: draft.fileIdentity,
            firmwareLibraryEntryID: draft.libraryEntryID,
            buildManifestSHA256: draft.fileIdentity?.buildManifestSHA256 ?? "",
            wholeFileSHA256: nil,
            rawOutputDirectory: directory,
            metadata: nil,
            compatibility: draft.compatibility,
            rlmStatus: .notRequested,
            rlmOwnership: .notRequested,
            rlmFinalizedAt: nil,
            rlmDrainDurationSeconds: nil,
            rlmRawLogURL: nil,
            rawPersistencePolicy: rawPolicy,
            rawEvidenceStatus: rawPolicy.saveThisRun
                ? .incompleteProtected
                : .notSavedByChoice,
            lifecycle: RestoreLifecycleTimes(userConfirmed: confirmed),
            attemptStage: .waitingForFreshHeartbeat,
            userConfirmedAt: confirmed.wallTime,
            phase: .userConfirmed,
            outcome: nil)
        secondaryAttempt = attempt
        secondaryTask = task
        secondaryAttemptID = attemptID
        secondaryDraft = draft
        let core = RestoreDualRestoreCore(
            registry: taskRegistry,
            releaseRegistryOnComplete: false,
            lease: processLease,
            engineFactory: secondaryEngineFactory)
        // 启动前再次确认：目标仍在、仍是同一连接代际、IPSW 未被替换。
        core.launchGuard = { [weak self] _ in
            self?.secondaryTargetStillValid() ?? false
        }
        secondaryCore = core
        let execution = RestoreTaskExecutionRequest(
            attemptID: attemptID,
            taskID: attemptID,
            canonicalECID: target.canonicalHex,
            portKey: port,
            ipswURL: draft.ipswURL,
            request: CfgutilRestoreRequest(
                taskID: attemptID,
                executableURL: cfgutilURL,
                ipswURL: draft.ipswURL,
                targetECID: target.ecid,
                outputDirectory: directory))
        do {
            try core.start(
                execution,
                leaseOwnership: .ownedExternally,
                onUpdate: { [weak self] id, snapshot in
                    self?.applySecondarySnapshot(id, snapshot)
                },
                onFinish: { [weak self] record in
                    self?.finishSecondary(record)
                })
        } catch {
            secondaryAttempt = nil
            secondaryTask = nil
            secondaryAttemptID = nil
            secondaryCore = nil
            secondaryDraft = nil
            releaseLeaseShare()
            errorMessage = L10n.t(
                "第二台 Restore 无法启动：占用或租约冲突，已拒绝。")
            return false
        }
        UIFixture.debugEvent("B_ADMISSION_RESULT", "ok")
        UIFixture.debugEvent("B_SLOT_RESULT", "created")
        UIFixture.debugEvent(
            "B_SLOT_RESULT",
            "attempt=\(attemptID.uuidString.prefix(8)) created=true")
        message = L10n.t("第二台 Restore 已开始。")
        return true
    }

    func cancelRestore(attemptID: UUID) {
        if attemptID == activeAttempt?.attemptID {
            cancelRestore()
            return
        }
        guard attemptID == secondaryAttemptID else {
            message = L10n.t("取消对象已变化，取消未执行。")
            return
        }
        guard let secondaryCore else {
            message = L10n.t("次任务引擎句柄已释放，取消未送达；请等待终态或使用强杀。")
            return
        }
        secondaryCore.cancel(attemptID)
        secondaryTask?.cancellationRequested = true
        message = L10n.t("正在取消次任务：已发送中断信号，等待进程退出…")
        scheduleSecondaryCancellationGrace(attemptID: attemptID)
    }

    func forceKillSecondaryRestore(attemptID: UUID) {
        guard attemptID == secondaryAttemptID,
              secondaryTask?.cancellationRequested == true else {
            message = L10n.t("强杀对象已变化或尚未请求取消，强杀未执行。")
            return
        }
        secondaryCore?.forceKill(attemptID)
        secondaryTask?.forcedKill = true
        message = L10n.t("已对次任务发送强制结束信号。")
    }

    private func applySecondarySnapshot(
        _ attemptID: UUID,
        _ snapshot: RestoreOutputSnapshot
    ) {
        guard secondaryAttemptID == attemptID, var task = secondaryTask else { return }
        task.stepText = snapshot.stepText
        task.stepCompleted = snapshot.stepCompleted
        task.stageFraction = snapshot.stageFraction
        task.failureText = snapshot.failureText
        task.lastOutputAt = snapshot.lastOutputAt
        task.cfgutilOutputTail = Array(snapshot.outputTail.suffix(48))
        task.cfgutilOutputSequence = snapshot.outputSequence
        if let launched = snapshot.processLaunched,
           task.lifecycle.processLaunched == nil {
            task.phase = .processStarted
            task.processStartedAt = launched.wallTime
            task.lifecycle.processLaunched = launched
            task.attemptStage = .processRunning
        }
        if snapshot.restoreActivityObserved {
            task.phase = .restoreActivityObserved
            if task.lifecycle.firstRestoreActivity == nil {
                task.lifecycle.firstRestoreActivity = RestoreLifecycleClock.now()
            }
        }
        secondaryTask = task
    }

    private func finishSecondary(_ record: RestoreTaskTerminalRecord) {
        UIFixture.debugEvent(
            "B_MODEL_FINISH_SECONDARY",
            "attempt=\(record.attemptID.uuidString.prefix(8)) status=\(record.status.rawValue)")
        UIFixture.debugEvent(
            "B_FINISH",
            "status=\(record.status.rawValue) attempt=\(record.attemptID.uuidString.prefix(8))")
        guard let attemptID = secondaryAttemptID,
              record.attemptID == attemptID,
              let attempt = secondaryAttempt,
              var task = secondaryTask else { return }
        let outcome: RestoreOutcome
        switch record.status {
        case .succeeded: outcome = .success
        case .failed: outcome = .failure
        case .canceled: outcome = .canceled
        case .unknown: outcome = .unknown
        }
        task.outcome = outcome
        task.phase = .terminal
        task.finishedAt = Date()
        task.exitCode = record.exitCode
        task.stdoutURL = record.stdoutURL
        task.stderrURL = record.stderrURL
        if let lifecycle = record.lifecycle {
            task.lifecycle = lifecycle
        }
        task.terminationReason = record.terminationReason
        task.sentSignals = record.sentSignals
        task.cancellationRequested = record.status == .canceled
        task.attemptStage = .completed
        task.rawEvidenceStatus = record.rawEvidenceStatus
        let finishedTask = task
        // 终态先投影；历史写完前保留 secondaryTask，阻止新的 B 抢占。
        secondaryTask = finishedTask
        secondaryAttempt = nil
        secondaryAttemptID = nil
        secondaryCore = nil
        secondaryDraft = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.rawArchiveObservationHook?()
            var archivedTask = finishedTask
            await self.archiveSecondaryRawIfNeeded(task: &archivedTask)
            await self.persistSecondaryHistory(
                task: archivedTask,
                attempt: attempt)
            self.lastSecondaryTaskSnapshot = archivedTask
            self.secondaryTask = nil
            self.taskRegistry.release(attemptID)
            self.releaseLeaseShare()
        }
    }

    private func archiveSecondaryRawIfNeeded(
        task: inout RestoreTaskSnapshot
    ) async {
        guard task.rawPersistencePolicy.saveThisRun,
              let stagingDirectory = task.rawOutputDirectory else {
            UIFixture.debugEvent("B_RAW_ARCHIVE", "skip=noPolicyOrDir")
            return
        }
        UIFixture.debugEvent(
            "B_RAW_ARCHIVE", "start attempt=\(task.attemptID.uuidString.prefix(8))")
        let candidate = RestoreArchiveCandidate(
            taskID: task.id,
            attemptID: task.attemptID,
            targetDisplayName: task.target.displayName,
            modelFamilyKey: ModelFamilyKey.resolve(
                identity: task.target.firmwareIdentity),
            modelYear: nil,
            productVersion: task.metadata?.productVersion,
            productBuild: task.metadata?.productBuild,
            outcome: task.outcome ?? .unknown,
            liveConfirmed: task.outcome == .success,
            tailComplete: task.tailComplete,
            rawWriteComplete: task.rawEvidenceStatus == .complete,
            summaryComplete: task.rawEvidenceStatus == .complete,
            manuallyLocked: false,
            linkedTaskIDs: [task.attemptID],
            linkedRLMSessionID: nil,
            generatedAt: Date())
        do {
            let configuredDestination =
                task.rawPersistencePolicy.destinationDirectory
            let destinationRoot = configuredDestination.isEmpty
                ? outputRoot.deletingLastPathComponent()
                    .appendingPathComponent("RestoreRawArchives", isDirectory: true)
                : URL(fileURLWithPath: configuredDestination, isDirectory: true)
            guard !UIFixture.isActive
                    || UIFixture.isPathIsolated(destinationRoot) else {
                task.rawArchiveMessage =
                    "G4 隔离失败：Raw 归档目标不在夹具根目录，已拒绝写入。"
                return
            }
            let publication = try await rawArchivePublisher.publish(
                stagingDirectory: stagingDirectory,
                destinationRoot: destinationRoot,
                candidate: candidate)
            task.rawArchive = publication.record
            task.rawOutputDirectory = publication.finalDirectory
            task.rawArchive = publication.record
            task.rawOutputDirectory = publication.finalDirectory
            task.rawArchiveMessage = publication.directorySyncLevel.isDurable
                ? "第二台原始日志已校验并安全发布。"
                : "第二台原始日志已发布；目标卷不支持完整目录同步。"
            UIFixture.debugEvent(
                "B_RAW_ARCHIVE", "ok archive=\(publication.record.archiveID)")
        } catch {
            task.rawArchiveMessage =
                "第二台原始日志归档失败；Restore 执行结果不受影响。"
            UIFixture.debugEvent(
                "B_RAW_ARCHIVE", "fail=\(error.localizedDescription.prefix(120))")
        }
    }

    func rawArchiveRecord(for attemptID: UUID) -> RestoreArchiveRecord? {
        let candidates = [
            lastCompletedTaskSnapshot,
            lastSecondaryTaskSnapshot,
            currentTask,
            secondaryTask,
        ].compactMap { $0 }
        return candidates.first {
            $0.attemptID == attemptID && $0.rawArchive != nil
        }?.rawArchive
    }

    func exportRawArchive(
        attemptID: UUID,
        to destination: URL
    ) throws -> RestoreRawExportResult {
        guard let archive = rawArchiveRecord(for: attemptID) else {
            throw RestoreRawExportError.noArchive
        }
        return try RestoreRawArchiveExporter.export(
            archive: archive,
            attemptID: attemptID,
            destination: destination)
    }

    private func persistSecondaryHistory(
        task: RestoreTaskSnapshot,
        attempt: PendingRestoreAttempt
    ) async {
        let modelFamilyKey =
            ModelFamilyKey.resolve(identity: task.target.firmwareIdentity)
        let hardwareBindingKey =
            HardwareBindingKey.resolve(identity: task.target.firmwareIdentity)
        let classification: RestoreErrorClassification
        switch task.outcome {
        case .success?: classification = .none
        case .failure?: classification = .explicitFailure
        case .canceled?: classification = .cancellationInterruption
        default: classification = .none
        }
        let record = RestoreHistoryRecord(
            taskID: task.id,
            attemptID: task.attemptID,
            operationType: .restore,
            deviceDisplayName: task.target.displayName,
            modelFamilyKey: modelFamilyKey,
            hardwareBindingKey: hardwareBindingKey,
            stablePortKey: attempt.stablePortKey,
            firmwareLibraryEntryID: task.firmwareLibraryEntryID,
            firmwareFileName: task.ipswURL.lastPathComponent,
            ipswIdentity: task.ipswIdentity,
            productVersion: task.metadata?.productVersion,
            productBuild: task.metadata?.productBuild,
            deviceECID: task.target.canonicalHex,
            lifecycle: task.lifecycle,
            outcome: task.outcome ?? .unknown,
            errorClassification: classification,
            exitCode: task.exitCode,
            terminationReason: .unknown,
            cancellationRequested: task.cancellationRequested,
            sentSignals: [],
            failureSummary: task.failureText,
            rawPersistencePolicy: task.rawPersistencePolicy,
            rawEvidenceStatus: task.rawEvidenceStatus,
            rawArchive: task.rawArchive,
            rlmSessionID: nil,
            rlmStatus: .notRequested,
            rlmOwnership: .notRequested,
            rlmFinalizedAt: nil,
            rlmDrainDurationSeconds: nil,
            recordSource: .nativeV1703Verified,
            verificationComplete: false)
        do {
            try await historyStore.upsert(record)
        } catch {
            restoreHistoryMessage = "第二台 Restore 历史写入失败；执行结果不受影响。"
        }
    }

    func cancelRestore() {
        guard canCancelRestoreTask,
              var attempt = activeAttempt else {
            message = L10n.t("当前任务已结束或不可取消，取消未执行。")
            return
        }
        if attempt.cancelRequested && !attempt.launchPermitted {
            message = L10n.t("取消已请求，正在等待进程退出…")
            return
        }
        attempt.cancelRequestedAt =
            attempt.cancelRequestedAt ?? RestoreLifecycleClock.now()
        attempt.launchPermitted = false
        activeAttempt = attempt
        currentTask?.cancellationRequested = true
        message = engine.isRunning
            ? "正在请求取消 cfgutil；已启动进程仍按 SIGINT → SIGTERM 顺序收尾。"
            : "正在取消本次恢复准备；cfgutil 尚未启动。"

        guard engine.isRunning else { return }
        engine.cancel()
        scheduleCancellationGrace(attemptID: attempt.attemptID)
    }

    func forceKillRestore() {
        guard isRestoreTaskActive,
              currentTask?.cancellationRequested == true,
              engine.isRunning else {
            message = L10n.t("强杀不可用：任务已结束、未请求取消或进程已退出。")
            return
        }
        currentTask?.forcedKill = true
        engine.forceKill()
    }

    func setCancellationGraceExpiredForPresentation() {
        guard currentTask?.cancellationRequested == true else { return }
        if engine.cancellationGraceExpired {
            currentTask?.cancellationGraceExpired = true
            message = "已发送取消信号，cfgutil 进程仍在等待系统响应。"
        }
    }

    func releaseAttemptIfCurrent(attemptID: UUID) {
        guard activeAttempt?.attemptID == attemptID else { return }
        taskRegistry.release(attemptID)
        activeAttempt = nil
    }

    // MARK: - 切片 2：机器租约份额（一个 App 一把锁）

    private func acquireLeaseShare() -> Bool {
        if leaseShareCount == 0 {
            switch processLease.acquire() {
            case .acquired:
                break
            case .busy:
                errorMessage = L10n.t(
                    "当前已有 Restore 任务正在运行，请先完成当前任务。")
                return false
            case .unavailable(let reason):
                errorMessage = L10n.t(
                    "无法取得 Restore 独占锁，已阻止启动以避免并发冲突。")
                    + " (\(reason))"
                return false
            }
            guard processLease.writeInProgress() else {
                processLease.release()
                errorMessage = L10n.t(
                    "无法写入 Restore 在制标记，已阻止启动以避免并发冲突。")
                return false
            }
        }
        leaseShareCount += 1
        return true
    }

    private func releaseLeaseShare() {
        leaseShareCount = max(0, leaseShareCount - 1)
        guard leaseShareCount == 0 else { return }
        processLease.clearInProgress()
        processLease.release()
    }

    /// 主任务收尾：仍有第二任务时保留在制标记与机器锁。
    private func clearMarkerIfLastShare() {
        guard leaseShareCount <= 1 else { return }
        processLease.clearInProgress()
    }

    private func runRestoreAttempt(
        attemptID: UUID,
        target: RestoreTarget,
        cfgutilURL: URL,
        firmwareURL: URL,
        expectedIPSWIdentity: IPSWFileIdentity,
        taskDirectory: URL?
    ) async {
        let waitResult = await waitForFreshHeartbeat(
            attemptID: attemptID,
            target: target)
        switch waitResult {
        case .canceled:
            await completeAttempt(
                attemptID: attemptID,
                outcome: .canceled,
                runResult: nil,
                failureText: "",
                classification: .cancellationBeforeLaunch)
            return
        case .failed(let reason):
            await completeAttempt(
                attemptID: attemptID,
                outcome: .failure,
                runResult: nil,
                failureText: reason,
                classification: .preflight)
            return
        case .ready:
            break
        }

        updateAttemptStage(attemptID: attemptID, stage: .validatingPreflight)
        guard isCurrentAttempt(attemptID), isLaunchPermitted(attemptID) else {
            await completeAttempt(
                attemptID: attemptID,
                outcome: .canceled,
                runResult: nil,
                failureText: "",
                classification: .cancellationBeforeLaunch)
            return
        }

        guard self.firmwareURL?.standardizedFileURL
                == firmwareURL.standardizedFileURL,
              activeAttempt?.ipswIdentity == expectedIPSWIdentity else {
            await completeAttempt(
                attemptID: attemptID,
                outcome: .failure,
                runResult: nil,
                failureText: "启动前 IPSW 选择或冻结身份已变化，cfgutil 未启动。",
                classification: .preflight)
            return
        }

        let reader = metadataReader
        let revalidation: Result<IPSWMetadataReadResult, Error> =
            await Task.detached(priority: .userInitiated) {
                Result {
                    try reader(firmwareURL)
                }
            }.value
        guard isCurrentAttempt(attemptID), isLaunchPermitted(attemptID) else {
            await completeAttempt(
                attemptID: attemptID,
                outcome: .canceled,
                runResult: nil,
                failureText: "",
                classification: .cancellationBeforeLaunch)
            return
        }
        let revalidatedResult: IPSWMetadataReadResult
        switch revalidation {
        case .success(let result):
            revalidatedResult = result
        case .failure(let error):
            await completeAttempt(
                attemptID: attemptID,
                outcome: .failure,
                runResult: nil,
                failureText:
                    "启动前 IPSW 身份复验失败：\(error.localizedDescription)",
                classification: .preflight)
            return
        }
        guard revalidatedResult.validity == .valid,
              let revalidatedMetadata = revalidatedResult.metadata,
              let actualIdentity = normalizedIdentity(
                url: firmwareURL,
                result: revalidatedResult) else {
            await completeAttempt(
                attemptID: attemptID,
                outcome: .failure,
                runResult: nil,
                failureText:
                    "启动前 IPSW 身份或 BuildManifest 已变化，cfgutil 未启动。"
                    + (revalidatedResult.error.map { " \($0)" } ?? ""),
                classification: .preflight)
            return
        }
        guard actualIdentity == expectedIPSWIdentity,
              actualIdentity.buildManifestSHA256
                == activeAttempt?.buildManifestSHA256 else {
            await completeAttempt(
                attemptID: attemptID,
                outcome: .failure,
                runResult: nil,
                failureText:
                    "启动前 IPSW 文件身份与已绑定元数据不一致，cfgutil 未启动。",
                classification: .preflight)
            return
        }
        firmwareMetadata = revalidatedMetadata
        firmwareValidity = .valid
        firmwareFileIdentity = actualIdentity
        buildManifestSHA256 = actualIdentity.buildManifestSHA256
        recomputeCompatibility()
        guard hardwareCompatibility.status != .incompatible else {
            await completeAttempt(
                attemptID: attemptID,
                outcome: .failure,
                runResult: nil,
                failureText:
                    "启动前 IPSW 兼容性复验为不兼容，cfgutil 未启动。",
                classification: .preflight)
            return
        }

        updateAttemptStage(attemptID: attemptID, stage: .preparingRLM)
        let rawSaveRequested =
            activeAttempt?.rawPersistencePolicy.saveThisRun == true
        // Raw persistence is the cfgutil sink's own policy. It must never
        // start or take ownership of the independent RLM session.
        let binding = await rlmCoordinator.prepare(
            taskID: attemptID,
            canonicalECID: target.canonicalHex,
            saveRequested: false)

        guard isCurrentAttempt(attemptID), isLaunchPermitted(attemptID) else {
            await completeAttempt(
                attemptID: attemptID,
                outcome: .canceled,
                runResult: nil,
                failureText: "",
                classification: .cancellationBeforeLaunch)
            return
        }
        currentTask?.rlmStatus = binding.status
        currentTask?.rlmOwnership = binding.ownership
        currentTask?.rlmRawLogURL = binding.rawLogURL

        updateAttemptStage(attemptID: attemptID, stage: .readyToLaunch)
        guard isCurrentAttempt(attemptID), isLaunchPermitted(attemptID) else {
            await completeAttempt(
                attemptID: attemptID,
                outcome: .canceled,
                runResult: nil,
                failureText: "",
                classification: .cancellationBeforeLaunch)
            return
        }

        let request = CfgutilRestoreRequest(
            taskID: attemptID,
            executableURL: cfgutilURL,
            ipswURL: firmwareURL,
            targetECID: target.ecid,
            outputDirectory: taskDirectory)
        updateAttemptStage(attemptID: attemptID, stage: .processLaunching)
        // 在制标记：App 崩溃/被强退时，重启的实例会据此发现"可能仍有 cfgutil 在刷机"
        // 并 fail-closed，而不是误开第二个 Restore。
        guard processLease.writeInProgress() else {
            await completeAttempt(
                attemptID: attemptID,
                outcome: .failure,
                runResult: nil,
                failureText:
                    "无法写入 Restore 在制标记，已阻止启动以避免并发冲突。",
                classification: .preflight)
            return
        }
        defer { clearMarkerIfLastShare() }

        let result = await engine.run(
            request: request,
            launchPermitted: { [weak self] in
                self?.isLaunchPermitted(attemptID) == true
            }
        ) { [weak self] snapshot in
            self?.applyEngineSnapshot(
                snapshot,
                attemptID: attemptID)
        }

        guard isCurrentAttempt(attemptID) else { return }
        updateAttemptLifecycleFromRunResult(
            attemptID: attemptID,
            runResult: result)
        publishTerminalOutcomeBeforeEvidenceFinalization(
            attemptID: attemptID,
            runResult: result)
        await rawArchiveObservationHook?()
        if rawSaveRequested,
           let taskDirectory,
           result.rawEvidence.status == .complete {
            await archiveRawEvidenceIfNeeded(
                attemptID: attemptID,
                stagingDirectory: taskDirectory,
                result: result)
        }
        await completeAttempt(
            attemptID: attemptID,
            outcome: result.outcome,
            runResult: result,
            failureText: result.snapshot.failureText,
            classification: classification(for: result))
    }

    private func publishTerminalOutcomeBeforeEvidenceFinalization(
        attemptID: UUID,
        runResult: CfgutilRestoreRunResult
    ) {
        guard isCurrentAttempt(attemptID) else { return }
        currentTask?.phase = .terminal
        currentTask?.outcome = runResult.outcome
        currentTask?.finishedAt =
            runResult.lifecycle.outcomeConfirmed?.wallTime
            ?? RestoreLifecycleClock.now().wallTime
        currentTask?.failureText = runResult.snapshot.failureText
        currentTask?.attemptStage = .finalizingEvidence
    }

    private func archiveRawEvidenceIfNeeded(
        attemptID: UUID,
        stagingDirectory: URL,
        result: CfgutilRestoreRunResult
    ) async {
        guard let task = currentTask,
              let stdoutURL = result.stdoutURL,
              let stderrURL = result.stderrURL,
              FileManager.default.fileExists(atPath: stdoutURL.path),
              FileManager.default.fileExists(atPath: stderrURL.path) else {
            currentTask?.rawArchiveMessage =
                "原始日志未形成可归档的完整本机 Staging；Restore 终态未改变。"
            return
        }
        let policy = task.rawPersistencePolicy
        let destinationRoot =
            policy.destinationDirectory
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            ? outputRoot
            : URL(
                fileURLWithPath: policy.destinationDirectory,
                isDirectory: true)
        let candidate = RestoreArchiveCandidate(
            taskID: task.id,
            attemptID: task.attemptID,
            targetDisplayName: task.target.displayName,
            modelFamilyKey: ModelFamilyKey.resolve(
                identity: task.target.firmwareIdentity),
            modelYear: nil,
            productVersion: task.metadata?.productVersion,
            productBuild: task.metadata?.productBuild,
            outcome: result.outcome,
            liveConfirmed:
                task.target.identityProvenance == .liveConfirmed,
            tailComplete: result.tailComplete,
            rawWriteComplete: result.rawEvidence.writeComplete,
            summaryComplete: true,
            manuallyLocked: false,
            linkedTaskIDs: [attemptID],
            linkedRLMSessionID:
                task.rlmRawLogURL?
                    .deletingLastPathComponent()
                    .lastPathComponent,
            generatedAt: Date())
        do {
            let publication = try await rawArchivePublisher.publish(
                stagingDirectory: stagingDirectory,
                destinationRoot: destinationRoot,
                candidate: candidate)
            currentTask?.rawArchive = publication.record
            currentTask?.rawOutputDirectory =
                publication.finalDirectory
            currentTask?.rawArchiveMessage =
                publication.directorySyncLevel.isDurable
                ? "原始日志已校验并安全发布。"
                : "原始日志已发布；目标卷不支持完整目录同步，本机 Staging 已保留。"
        } catch {
            currentTask?.rawArchiveMessage =
                "原始日志归档未完成，本机 Staging 已保留；Restore 终态未改变。"
        }
    }

    private enum HeartbeatWaitResult {
        case ready
        case canceled
        case failed(String)
    }

    private func waitForFreshHeartbeat(
        attemptID: UUID,
        target: RestoreTarget
    ) async -> HeartbeatWaitResult {
        let maximumAgeNs = UInt64(maximumSnapshotAge * 1_000_000_000)
        let deadline = DispatchTime.now().uptimeNanoseconds &+ maximumAgeNs
        var lastFailureReason = ""

        while true {
            guard isCurrentAttempt(attemptID) else { return .canceled }
            guard isLaunchPermitted(attemptID) else { return .canceled }

            let now = DispatchTime.now().uptimeNanoseconds
            let snapshot = observationHeartbeat?.latest ?? latestHeartbeat
            if snapshot.isFreshSuccess(
                atUptimeNs: now,
                maximumAgeNs: maximumAgeNs) {
                switch validateHeartbeat(snapshot, against: target) {
                case nil:
                    return .ready
                case .some(let reason):
                    return .failed(reason)
                }
            }
            if case .failed(let reason) = snapshot.observationResult {
                lastFailureReason = reason
            }
            guard now < deadline else {
                let suffix = lastFailureReason.isEmpty
                    ? ""
                    : "；最近一次观察失败：\(lastFailureReason)"
                return .failed(
                    "设备观察快照过期或超时，未启动恢复。"
                        + suffix)
            }
            let remaining = deadline - now
            let sleepNs = min(
                UInt64(heartbeatPollInterval * 1_000_000_000),
                remaining)
            try? await Task.sleep(nanoseconds: max(1, sleepNs))
        }
    }

    private func validateHeartbeat(
        _ snapshot: DeviceControlModel.ObservationHeartbeatSnapshot,
        against target: RestoreTarget
    ) -> String? {
        let targets = RestoreSnapshotInspector.targets(
            from: snapshot.devices,
            portKeyResolver: portKeyResolver,
            portDisplayNameResolver: portDisplayNameResolver)
        let matches = targets.filter { $0.ecid == target.ecid }
        guard !matches.isEmpty else {
            return "最新观察中已找不到冻结的 ECID；端口切换不会重定向本次 Restore。"
        }
        guard matches.count == 1 else {
            return "最新观察中出现重复 ECID，无法安全启动单一 Restore 目标。"
        }
        let candidate = matches[0]
        guard candidate.mode == target.mode,
              candidate.locationID == target.locationID,
              candidate.connectionGeneration == target.connectionGeneration,
              candidate.portKey == target.portKey else {
            return "冻结目标的端口、模式或连接代际已变化，cfgutil 未启动。"
        }
        guard candidate.productType == target.productType,
              candidate.machineIdentifier == target.machineIdentifier,
              candidate.deviceClass == target.deviceClass,
              candidate.boardID == target.boardID,
              candidate.chipID == target.chipID,
              candidate.identityProvenance == target.identityProvenance else {
            return "冻结目标的硬件身份与同轮心跳不一致，cfgutil 未启动。"
        }
        return nil
    }

    private func isCurrentAttempt(_ attemptID: UUID) -> Bool {
        activeAttempt?.attemptID == attemptID
            && currentTask?.id == attemptID
    }

    private func isLaunchPermitted(_ attemptID: UUID) -> Bool {
        guard let attempt = activeAttempt,
              attempt.attemptID == attemptID else {
            return false
        }
        return attempt.launchPermitted && !attempt.cancelRequested
    }

    private func updateAttemptStage(
        attemptID: UUID,
        stage: PendingRestoreAttemptStage
    ) {
        guard var attempt = activeAttempt,
              attempt.attemptID == attemptID else {
            return
        }
        attempt.stage = stage
        activeAttempt = attempt
        currentTask?.attemptStage = stage
    }

    private func applyEngineSnapshot(
        _ snapshot: RestoreOutputSnapshot,
        attemptID: UUID
    ) {
        guard isCurrentAttempt(attemptID) else { return }
        currentTask?.lastOutputAt = snapshot.lastOutputAt
        currentTask?.stepText = snapshot.stepText
        currentTask?.stepCompleted = snapshot.stepCompleted
        currentTask?.stageFraction = snapshot.stageFraction
        currentTask?.overallFraction = nil
        currentTask?.failureText = snapshot.failureText
        currentTask?.cfgutilOutputTail = Array(
            snapshot.outputTail.suffix(240))
        currentTask?.cfgutilOutputSequence = snapshot.outputSequence

        if let launched = snapshot.processLaunched {
            let isFirstLaunchObservation =
                currentTask?.lifecycle.processLaunched == nil
            currentTask?.phase = .processStarted
            currentTask?.processStartedAt = launched.wallTime
            currentTask?.lifecycle.processLaunched = launched
            if var attempt = activeAttempt,
               attempt.attemptID == attemptID {
                attempt.lifecycle.processLaunched = launched
                attempt.stage = .processRunning
                activeAttempt = attempt
                currentTask?.attemptStage = .processRunning
            }
            if isFirstLaunchObservation {
                recordFirmwareUseAfterProcessLaunch(at: launched.wallTime)
            }
        }
        if let activity = snapshot.firstRestoreActivityTime {
            currentTask?.phase = .restoreActivityObserved
            currentTask?.restoreActivityObservedAt = activity.wallTime
            currentTask?.lifecycle.firstRestoreActivity = activity
            if var attempt = activeAttempt,
               attempt.attemptID == attemptID {
                attempt.lifecycle.firstRestoreActivity = activity
                activeAttempt = attempt
            }
        }
    }

    private func recordFirmwareUseAfterProcessLaunch(at date: Date) {
        guard let preferences = firmwarePreferences,
              let task = currentTask,
              let identity = task.ipswIdentity else {
            return
        }
        let entryID = task.firmwareLibraryEntryID
            ?? FirmwareReference.syntheticEntryID(identity: identity)
        let reference = FirmwareReference(
            entryID: entryID,
            url: task.ipswURL,
            fileIdentity: identity,
            metadata: task.metadata,
            recordedAt: date)
        let persisted = preferences.recordUsed(
            reference,
            modelFamilyKey: ModelFamilyKey.resolve(
                identity: task.target.firmwareIdentity),
            at: date)
        if !persisted {
            firmwarePreferenceIssue =
                preferences.loadError
                ?? "本次 Restore 已启动，但最近使用记录未能保存。"
        }
    }

    private func updateAttemptLifecycleFromRunResult(
        attemptID: UUID,
        runResult: CfgutilRestoreRunResult
    ) {
        guard var attempt = activeAttempt,
              attempt.attemptID == attemptID else {
            return
        }
        let lifecycle = RestoreLifecycleTimes(
            userConfirmed: attempt.userConfirmedAt,
            processLaunched: runResult.lifecycle.processLaunched,
            firstRestoreActivity: runResult.lifecycle.firstRestoreActivity,
            processExited: runResult.lifecycle.processExited,
            bothStreamsEOF: runResult.lifecycle.bothStreamsEOF,
            outcomeConfirmed: runResult.lifecycle.outcomeConfirmed,
            rlmFinalized: attempt.lifecycle.rlmFinalized)
        attempt.lifecycle = lifecycle
        attempt.stage = .outcomeConfirmed
        activeAttempt = attempt
        currentTask?.lifecycle = lifecycle
        currentTask?.attemptStage = .outcomeConfirmed
        if let launched = lifecycle.processLaunched {
            currentTask?.processStartedAt = launched.wallTime
            currentTask?.phase = .processStarted
        }
        if let activity = lifecycle.firstRestoreActivity {
            currentTask?.restoreActivityObservedAt = activity.wallTime
            currentTask?.phase = .restoreActivityObserved
        }
    }

    private func classification(
        for result: CfgutilRestoreRunResult
    ) -> RestoreErrorClassification {
        switch result.outcome {
        case .success:
            return .none
        case .failure:
            if result.snapshot.sawIndependentFailure {
                return .explicitFailure
            }
            return result.lifecycle.processLaunched == nil
                ? .launchFailure
                : .explicitFailure
        case .canceled:
            if result.lifecycle.processLaunched == nil {
                return .cancellationBeforeLaunch
            }
            if result.snapshot.sawCancellationInterruptionFailure {
                return .cancellationInterruption
            }
            return result.sentSignals.isEmpty
                ? .missingOutcome
                : .terminationSignal
        case .unknown:
            return result.tailComplete
                ? .missingOutcome
                : .incompleteEvidence
        }
    }

    private func completeAttempt(
        attemptID: UUID,
        outcome: RestoreOutcome,
        runResult: CfgutilRestoreRunResult?,
        failureText: String,
        classification: RestoreErrorClassification
    ) async {
        guard isCurrentAttempt(attemptID) else { return }

        let finishedAt =
            runResult?.lifecycle.outcomeConfirmed?.wallTime
            ?? RestoreLifecycleClock.now().wallTime
        currentTask?.phase = .terminal
        currentTask?.outcome = outcome
        currentTask?.finishedAt = finishedAt
        currentTask?.attemptStage = .finalizingEvidence
        if let runResult {
            currentTask?.exitCode = runResult.exitCode
            currentTask?.stepText = runResult.snapshot.stepText
            currentTask?.stepCompleted = runResult.snapshot.stepCompleted
            currentTask?.stageFraction = runResult.snapshot.stageFraction
            currentTask?.failureText = runResult.snapshot.failureText
            currentTask?.stdoutURL = runResult.stdoutURL
            currentTask?.stderrURL = runResult.stderrURL
            currentTask?.stdoutSHA256 = runResult.stdoutSHA256
            currentTask?.stderrSHA256 = runResult.stderrSHA256
            currentTask?.tailComplete = runResult.tailComplete
            currentTask?.cancellationRequested = runResult.cancellationRequested
            currentTask?.forcedKill = runResult.forcedKill
            currentTask?.terminationReason =
                runResult.terminationReason
            currentTask?.sentSignals = runResult.sentSignals
            currentTask?.rawEvidenceStatus =
                runResult.rawEvidence.status
        } else {
            currentTask?.failureText = failureText
            currentTask?.tailComplete = false
            currentTask?.cancellationRequested = outcome == .canceled
            currentTask?.lifecycle.outcomeConfirmed =
                RestoreLifecycleClock.now()
            currentTask?.rawEvidenceStatus =
                currentTask?.rawPersistencePolicy.saveThisRun == true
                    ? .incompleteProtected
                    : .notSavedByChoice
            if var attempt = activeAttempt {
                attempt.lifecycle.outcomeConfirmed =
                    currentTask?.lifecycle.outcomeConfirmed
                activeAttempt = attempt
            }
        }

        await rlmCoordinator.finish(taskID: attemptID, outcome: outcome)

        if var task = currentTask {
            if let sessionID = task.rlmRawLogURL?
                .deletingLastPathComponent()
                .lastPathComponent {
                let ownedDrainActive =
                    task.rlmOwnership == .restoreOwned
                    && task.rlmStatus == .startedOwnedSession
                do {
                    try await RestoreLogRetentionStore.shared
                        .registerSessionProtection(
                            RestoreRLMSessionProtection(
                                sessionID: sessionID,
                                ownership: task.rlmOwnership,
                                linkedTaskIDs: [attemptID],
                                linkedTaskOutcomes: [outcome],
                                manuallyLocked: false,
                                hasExportedBundle: false,
                                recording: ownedDrainActive,
                                finalizing: ownedDrainActive,
                                historyComplete: !ownedDrainActive,
                                lifecycleOwnerTaskID:
                                    ownedDrainActive
                                    ? attemptID
                                    : nil))
                } catch {
                    restoreHistoryMessage =
                        "RLM 会话保护状态未能持久写入；未知会话默认保持保护。"
                }
            }
            task.attemptStage = .finalizingEvidence
            lastCompletedTaskSnapshot = task
            await persistHistoryRecord(
                task: task,
                classification: classification)
            if let persisted = lastCompletedTaskSnapshot {
                scheduleRLMFinalization(
                    attemptID: attemptID,
                    taskID: persisted.id)
            }
        }

        guard isCurrentAttempt(attemptID) else { return }
        taskRegistry.release(attemptID)
        activeAttempt = nil
        currentTask = nil
        lockedTarget = nil
        runTask = nil
        hasUserRestorePreparationContext = false
        rawSaveSelectionExplicit = false
        rawSaveRequestedThisRun =
            rawPersistenceDefaultsProvider().autoSaveDefault
        message = outcome.rawValue
    }

    private func persistHistoryRecord(
        task: RestoreTaskSnapshot,
        classification: RestoreErrorClassification
    ) async {
        guard let attempt = activeAttempt,
              attempt.attemptID == task.attemptID else {
            return
        }
        let modelFamilyKey =
            ModelFamilyKey.resolve(identity: task.target.firmwareIdentity)
        let hardwareBindingKey =
            HardwareBindingKey.resolve(identity: task.target.firmwareIdentity)
        let hasCompleteCoreTiming =
            task.lifecycle.processLaunched != nil
            && task.lifecycle.firstRestoreActivity != nil
            && task.lifecycle.processExited != nil
            && task.lifecycle.bothStreamsEOF != nil
            && task.lifecycle.outcomeConfirmed != nil
        let verificationComplete =
            task.outcome == .success
            && hasCompleteCoreTiming
            && modelFamilyKey != nil
            && attempt.stablePortKey != nil
        let record = RestoreHistoryRecord(
            taskID: task.id,
            attemptID: task.attemptID,
            operationType: .restore,
            deviceDisplayName: task.target.displayName,
            modelFamilyKey: modelFamilyKey,
            hardwareBindingKey: hardwareBindingKey,
            stablePortKey: attempt.stablePortKey,
            firmwareLibraryEntryID: attempt.firmwareLibraryEntryID,
            firmwareFileName: task.ipswURL.lastPathComponent,
            ipswIdentity: task.ipswIdentity,
            productVersion: task.metadata?.productVersion,
            productBuild: task.metadata?.productBuild,
            deviceECID: task.target.canonicalHex,
            lifecycle: task.lifecycle,
            outcome: task.outcome ?? .unknown,
            errorClassification: classification,
            exitCode: task.exitCode,
            terminationReason: task.terminationReason,
            cancellationRequested: task.cancellationRequested,
            sentSignals: task.sentSignals,
            failureSummary: task.failureText,
            rawPersistencePolicy: task.rawPersistencePolicy,
            rawEvidenceStatus: task.rawEvidenceStatus,
            rawArchive: task.rawArchive,
            rlmSessionID:
                task.rlmRawLogURL?
                    .deletingLastPathComponent()
                    .lastPathComponent,
            rlmStatus: task.rlmStatus,
            rlmOwnership: task.rlmOwnership,
            rlmFinalizedAt: task.rlmFinalizedAt,
            rlmDrainDurationSeconds: task.rlmDrainDurationSeconds,
            recordSource: .nativeV1703Verified,
            verificationComplete: verificationComplete)
        do {
            try await historyStore.upsert(record)
            restoreHistoryMessage = "本次恢复已写入轻量历史。"
            historyUsageRecords =
                (try? await historyStore.firmwareUsageRecords()) ?? []
            if var completed = lastCompletedTaskSnapshot,
               completed.id == task.id {
                completed.attemptStage = .completed
                lastCompletedTaskSnapshot = completed
            }
            await refreshRestoreHistoryStatistics()
        } catch {
            restoreHistoryMessage =
                "轻量历史写入失败；cfgutil 终态不受影响。"
        }
    }

    private func scheduleRLMFinalization(
        attemptID: UUID,
        taskID: UUID
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let finalization = await self.rlmCoordinator.finalization(
                taskID: attemptID,
                timeout: 45)
            guard let finalization else { return }
            if var task = self.lastCompletedTaskSnapshot,
               task.id == taskID {
                task.rlmOwnership = finalization.ownership
                task.rlmFinalizedAt = finalization.finalizedAt
                task.rlmDrainDurationSeconds =
                    finalization.drainDurationSeconds
                task.lifecycle.rlmFinalized = finalization.finalizedAt
                self.lastCompletedTaskSnapshot = task
            }
            do {
                if let sessionID = finalization.rawLogURL?
                    .deletingLastPathComponent()
                    .lastPathComponent {
                    try await RestoreLogRetentionStore.shared
                        .resolveOwnedSessionFinalization(
                            sessionID: sessionID,
                            taskID: attemptID,
                            finalized:
                                finalization.disposition
                                    == .finalizedOwnedSession)
                }
                try await self.historyStore.updateRLMFinalization(
                    attemptID: attemptID,
                    finalizedAt: finalization.finalizedAt,
                    drainDurationSeconds:
                        finalization.drainDurationSeconds,
                    disposition: finalization.disposition,
                    reason: finalization.reason)
            } catch {
                self.restoreHistoryMessage =
                    "RLM 收尾摘要未能更新历史；会话与 Restore 终态未改变。"
            }
        }
    }

    private func refreshRestoreHistoryStatistics() async {
        guard let target = selectedTarget,
              let modelFamilyKey =
                ModelFamilyKey.resolve(identity: target.firmwareIdentity) else {
            restoreHistoryStatistics = .empty
            return
        }
        let build = firmwareMetadata?.productBuild
        do {
            let statistics = try await historyStore.statistics(
                modelFamilyKey: modelFamilyKey,
                productBuild: build)
            guard selectedTarget?.firmwareIdentity == target.firmwareIdentity,
                  firmwareMetadata?.productBuild == build else {
                return
            }
            restoreHistoryStatistics = statistics
        } catch {
            restoreHistoryStatistics = .empty
        }
    }

    private func scheduleHistoryStatisticsRefresh() {
        Task { @MainActor [weak self] in
            await self?.refreshRestoreHistoryStatistics()
        }
    }

    private func scheduleSecondaryCancellationGrace(attemptID: UUID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(
                nanoseconds: UInt64(
                    self.cancellationGraceDelay * 1_000_000_000))
            guard self.secondaryAttemptID == attemptID else { return }
            self.secondaryTask?.cancellationGraceExpired = true
            self.message = L10n.t("次任务仍未退出，可使用强制结束。")
        }
    }

    private func scheduleCancellationGrace(attemptID: UUID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(
                nanoseconds: UInt64(
                    self.cancellationGraceDelay * 1_000_000_000))
            guard self.isCurrentAttempt(attemptID),
                  self.engine.isRunning else {
                return
            }
            self.currentTask?.cancellationGraceExpired = true
            self.message = "已发送取消信号，cfgutil 进程仍在等待系统响应。"
        }
    }

    private func ingestHeartbeat(
        _ snapshot: DeviceControlModel.ObservationHeartbeatSnapshot
    ) {
        latestHeartbeat = snapshot
        switch snapshot.observationResult {
        case .pending:
            reconcileTargets([])
        case .failed:
            reconcileTargets([])
        case .successChanged, .successUnchanged:
            let targets = RestoreSnapshotInspector.targets(
                from: snapshot.devices,
                portKeyResolver: portKeyResolver,
                portDisplayNameResolver: portDisplayNameResolver)
            reconcileTargets(targets)
        }
    }

    private func reconcileTargets(_ targets: [RestoreTarget]) {
        allAvailableTargets = targets.sorted {
            if $0.canonicalHex != $1.canonicalHex {
                return $0.canonicalHex < $1.canonicalHex
            }
            return ($0.portKey ?? "") < ($1.portKey ?? "")
        }
        let browsePorts = Dictionary(
            grouping: allAvailableTargets.compactMap { target -> RestoreBrowsePort? in
                guard let key = target.portKey else { return nil }
                return RestoreBrowsePort(
                    key: key,
                    displayName: target.portDisplayName)
            },
            by: \.key)
            .compactMap { $0.value.first }
            .sorted {
                if $0.displayName != $1.displayName {
                    return $0.displayName.localizedStandardCompare($1.displayName)
                        == .orderedAscending
                }
                return $0.key < $1.key
            }
        if availableBrowsePorts != browsePorts {
            availableBrowsePorts = browsePorts
        }

        if let browsePortScope,
           !availableBrowsePorts.contains(where: { $0.key == browsePortScope }) {
            self.browsePortScope = nil
        }

        let signature = allAvailableTargets.map {
            [
                $0.canonicalHex,
                String(describing: $0.mode),
                $0.locationID,
                String($0.connectionGeneration),
                $0.portKey ?? "",
                $0.productType ?? "",
                $0.machineIdentifier ?? "",
                $0.deviceClass ?? "",
                $0.boardID.map(String.init) ?? "",
                $0.chipID.map(String.init) ?? "",
                $0.identityProvenance.rawValue,
                $0.displayName
            ].joined(separator: "|")
        }.joined(separator: "\n")

        if signature != targetSignature {
            targetSignature = signature
            applyTargetProjection()
        } else if isRestoreTaskActive {
            applyTargetProjection()
        }
    }

    private func applyTargetProjection() {
        let projected: [RestoreTarget]
        if let browsePortScope {
            projected = allAvailableTargets.filter {
                $0.portKey == browsePortScope
            }
        } else {
            projected = allAvailableTargets
        }
        if availableTargets != projected {
            availableTargets = projected
        }

        guard !isRestoreTaskActive else { return }
        if let selectedTargetID,
           !projected.contains(where: { $0.id == selectedTargetID }) {
            self.selectedTargetID = nil
        }
        if selectedTargetID == nil,
           let firstTarget = projected.first {
            // 多个目标时也自动选中第一个，避免界面停在“无目标”而无法加载默认固件。
            selectedTargetID = firstTarget.id
        }
        if selectedTargetID == nil {
            lockedTarget = nil
        }
        recomputeCompatibility()
        applyAutomaticRecommendation()
    }

    private func clearPendingRestoreSelection() {
        guard !isRestoreTaskActive else { return }
        hasUserRestorePreparationContext = false
        selectedTargetID = nil
        lockedTarget = nil
        firmwareURL = nil
        firmwareMetadata = nil
        firmwareFileIdentity = nil
        buildManifestSHA256 = ""
        firmwareSHA256 = ""
        firmwareValidity = .unverified
        firmwareLibraryEntryID = nil
        firmwareSelectionSource = .none
        recommendedFirmware = nil
        firmwarePreferenceIssue = ""
        hardwareCompatibility = Self.defaultCompatibility
        currentTask = nil
        restoreHistoryStatistics = .empty
        rawSaveSelectionExplicit = false
        rawSaveRequestedThisRun =
            rawPersistenceDefaultsProvider().autoSaveDefault
        errorMessage = ""
        message = ""
    }

    private func applyFirmwareEntry(
        _ entry: FirmwareLibraryEntry,
        selectionSource: FirmwareSelectionSource
    ) {
        firmwareURL = entry.url
        firmwareMetadata = entry.metadata
        firmwareValidity = entry.validity
        firmwareFileIdentity = entry.fileIdentity
        buildManifestSHA256 =
            entry.fileIdentity?.buildManifestSHA256 ?? ""
        firmwareSHA256 = entry.wholeFileSHA256 ?? ""
        firmwareLibraryEntryID = entry.id
        firmwareSelectionSource = selectionSource
        errorMessage = entry.errorMessage ?? ""
        recomputeCompatibility()
        scheduleHistoryStatisticsRefresh()
        if selectionSource == .userManualSelected {
            recordManualFirmwareSelection(FirmwareReference(entry: entry))
        }
    }

    private func applyFirmwareResult(
        url: URL,
        result: IPSWMetadataReadResult,
        selectionSource: FirmwareSelectionSource,
        entryID: UUID?
    ) {
        let identity = normalizedIdentity(url: url, result: result)
        firmwareURL = url
        firmwareMetadata = result.metadata
        firmwareValidity = result.validity
        firmwareFileIdentity = identity
        buildManifestSHA256 =
            identity?.buildManifestSHA256
                ?? result.buildManifestSHA256
        firmwareSHA256 = result.wholeFileSHA256 ?? ""
        firmwareLibraryEntryID = entryID
        firmwareSelectionSource = selectionSource
        errorMessage = result.error ?? ""
        recomputeCompatibility()
        scheduleHistoryStatisticsRefresh()
        if selectionSource == .userManualSelected {
            let referenceID = entryID
                ?? identity.map {
                    FirmwareReference.syntheticEntryID(identity: $0)
                }
            if let referenceID {
            recordManualFirmwareSelection(
                FirmwareReference(
                    entryID: referenceID,
                    url: url,
                    fileIdentity: identity,
                    metadata: result.metadata))
            }
        }
    }

    private func recordManualFirmwareSelection(
        _ reference: FirmwareReference
    ) {
        guard let firmwarePreferences else { return }
        let persisted = firmwarePreferences.recordSelection(
            reference,
            modelFamilyKey: selectedTarget.flatMap {
                ModelFamilyKey.resolve(identity: $0.firmwareIdentity)
            })
        if !persisted {
            firmwarePreferenceIssue =
                firmwarePreferences.loadError
                ?? "上次选择未能保存。"
        }
    }

    private func normalizedIdentity(
        url: URL,
        result: IPSWMetadataReadResult
    ) -> IPSWFileIdentity? {
        if let identity = result.fileIdentity {
            return identity
        }
        return try? IPSWMetadataReader.fileIdentity(
            url: url,
            buildManifestSHA256: result.buildManifestSHA256)
    }

    private func applyAutomaticRecommendation() {
        guard !isRestoreTaskActive,
              !suppressAutomaticRecommendation else {
            return
        }
        guard let target = selectedTarget else {
            recommendedFirmware = nil
            firmwarePreferenceIssue = ""
            return
        }
        let candidates = firmwareLibraryEntries
            .filter(\.isRestoreEligible)
            .map { entry in
            let compatibility = entry.metadata.map {
                IPSWCompatibilityEvaluator.evaluate(
                    metadata: $0,
                    target: RestoreTargetIdentity(
                        productType: target.productType,
                        deviceClass: target.deviceClass,
                        boardID: target.boardID,
                        chipID: target.chipID))
            } ?? HardwareCompatibility(
                status: .unverified,
                message: "固件缺少可用 BuildManifest。")
            return FirmwareRecommendationCandidate(
                entry: entry,
                compatibility: compatibility)
        }
        let modelFamilyKey = ModelFamilyKey.resolve(identity: target.firmwareIdentity)
        let providerModelDefaultCandidateID = modelFamilyKey.flatMap {
            modelDefaultCandidateIDProvider($0)
        }
        let providerGlobalDefaultCandidateID =
            globalDefaultCandidateIDProvider()
        let modelDefaultReference = modelFamilyKey.flatMap {
            firmwarePreferences?.modelDefault(for: $0)
        }
        let globalDefaultReference = firmwarePreferences?.globalDefault

        var preferenceIssue = ""
        var modelDefaultCandidateID = providerModelDefaultCandidateID
        let modelDefaultIsConfigured =
            modelDefaultReference != nil
                || providerModelDefaultCandidateID != nil
        if let modelDefaultReference {
            let resolved = resolvedDefaultCandidate(
                modelDefaultReference,
                target: target,
                label: "当前机型默认固件")
            if let candidateID = resolved.candidateID {
                modelDefaultCandidateID = candidateID
            } else {
                modelDefaultCandidateID = nil
                preferenceIssue = resolved.issue
                    ?? "当前机型默认固件不可用。"
            }
        }

        var globalDefaultCandidateID =
            providerGlobalDefaultCandidateID
        let globalDefaultIsConfigured =
            globalDefaultReference != nil
                || providerGlobalDefaultCandidateID != nil
        if let globalDefaultReference {
            let resolved = resolvedDefaultCandidate(
                globalDefaultReference,
                target: target,
                label: "全局默认固件")
            if let candidateID = resolved.candidateID {
                globalDefaultCandidateID = candidateID
            } else {
                globalDefaultCandidateID = nil
                if preferenceIssue.isEmpty {
                    preferenceIssue = resolved.issue
                        ?? "全局默认固件不可用。"
                }
            }
        }

        var recentUsedCandidateIDs: [UUID] = []
        if let modelFamilyKey {
            let recentUses =
                firmwarePreferences?.recentUses(
                    matching: modelFamilyKey) ?? []
            for use in recentUses {
                guard let resolution =
                        resolveFirmwareReference(use.reference),
                      resolution.isUsable,
                      let entry = resolution.entry else {
                    continue
                }
                if !recentUsedCandidateIDs.contains(entry.id) {
                    recentUsedCandidateIDs.append(entry.id)
                }
            }
            let successfulHistory = (
                historyUsageRecords + recentSuccessfulUsesProvider())
                .filter {
                    $0.modelFamilyKey == modelFamilyKey
                        && $0.outcome == .success
                        && $0.source == .nativeV1703Verified
                        && $0.verificationComplete
                }
                .sorted { $0.occurredAt > $1.occurredAt }
            for use in successfulHistory
            where !recentUsedCandidateIDs.contains(use.candidateID) {
                recentUsedCandidateIDs.append(use.candidateID)
            }
        }

        let lastSelectedCandidateID: UUID?
        if let modelFamilyKey,
           let lastSelected = firmwarePreferences?.lastSelected,
           lastSelected.modelFamilyKey == modelFamilyKey,
           let resolution =
                resolveFirmwareReference(lastSelected.reference),
           resolution.isUsable,
           let entry = resolution.entry {
            lastSelectedCandidateID = entry.id
        } else {
            lastSelectedCandidateID = nil
        }

        let request = FirmwareRecommendationRequest(
            target: target.firmwareIdentity,
            candidates: candidates,
            recentSuccessfulUses:
                historyUsageRecords + recentSuccessfulUsesProvider(),
            recentUsedCandidateIDs: recentUsedCandidateIDs,
            lastSelectedCandidateID: lastSelectedCandidateID,
            modelDefaultCandidateID: modelDefaultCandidateID,
            modelDefaultIsConfigured: modelDefaultIsConfigured,
            globalDefaultCandidateID: globalDefaultCandidateID,
            globalDefaultIsConfigured: globalDefaultIsConfigured,
            manualCandidateID:
                firmwareSelectionSource == .userManualSelected
                    ? firmwareLibraryEntryID
                    : nil)
        let recommendation = recommendationEngine.recommend(request)
        recommendedFirmware = recommendation
        firmwarePreferenceIssue = preferenceIssue

        guard firmwareSelectionSource != .userManualSelected,
              let recommendation else {
            if firmwareSelectionSource != .userManualSelected {
                firmwareURL = nil
                firmwareMetadata = nil
                firmwareFileIdentity = nil
                buildManifestSHA256 = ""
                firmwareSHA256 = ""
                firmwareValidity = .unverified
                firmwareLibraryEntryID = nil
                hardwareCompatibility = Self.defaultCompatibility
            }
            return
        }
        guard recommendation.selectionSource
                == FirmwareSelectionSource.systemRecommended else {
            return
        }
        applyFirmwareEntry(
            recommendation.candidate.entry,
            selectionSource: .systemRecommended)
    }

    private func resolvedDefaultCandidate(
        _ reference: FirmwareReference,
        target: RestoreTarget,
        label: String
    ) -> (candidateID: UUID?, issue: String?) {
        let resolution = resolveFirmwareReference(reference)
        guard let resolution,
              resolution.isUsable,
              let entry = resolution.entry else {
            return (
                nil,
                resolution?.message
                    ?? "\(label)当前不可用。")
        }
        guard let metadata = entry.metadata else {
            return (nil, "\(label)缺少可验证的 BuildManifest。")
        }
        let compatibility = IPSWCompatibilityEvaluator.evaluate(
            metadata: metadata,
            target: RestoreTargetIdentity(
                productType: target.productType,
                deviceClass: target.deviceClass,
                boardID: target.boardID,
                chipID: target.chipID))
        guard compatibility.status != .incompatible else {
            return (
                nil,
                "\(label)与当前设备不兼容：\(compatibility.message)")
        }
        return (entry.id, nil)
    }

    private func libraryMessage(for result: FirmwareLibraryScanResult) -> String {
        var parts = [
            "已发现 \(result.discoveredCount) 个 IPSW，其中 \(result.indexedCount) 个有效。"
        ]
        if result.invalidCount > 0 {
            parts.append("\(result.invalidCount) 个无效或无法解析。")
        }
        if result.unreadableCount > 0 {
            parts.append("\(result.unreadableCount) 个当前不可读取。")
        }
        if result.cloudNotDownloadedCount > 0 {
            parts.append(
                "\(result.cloudNotDownloadedCount) 个 iCloud 文件尚未下载。")
        }
        if result.unreadableDirectoryCount > 0 {
            parts.append(
                "\(result.unreadableDirectoryCount) 个子目录无法读取。")
        }
        if result.attributeReadFailureCount > 0 {
            parts.append(
                "\(result.attributeReadFailureCount) 个目录项属性无法读取。")
        }
        if result.scanLimitReached {
            parts.append(
                "扫描达到安全深度、条目或固件数量上限；未扫描到的旧索引不会标记为丢失。")
        } else if result.scanIncomplete
                    && result.unreadableDirectoryCount == 0
                    && result.attributeReadFailureCount == 0 {
            parts.append("扫描不完整；未扫描到的旧索引不会标记为丢失。")
        }
        if !result.relocatedEntryIDs.isEmpty {
            parts.append("唯一重定位 \(result.relocatedEntryIDs.count) 个。")
        }
        if !result.ambiguousEntryIDs.isEmpty {
            parts.append(
                "\(result.ambiguousEntryIDs.count) 个索引存在多候选重定位，需人工确认。")
        }
        return parts.joined(separator: " ")
    }

    private static var defaultCompatibility: HardwareCompatibility {
        HardwareCompatibility(
            status: .unverified,
            message: "请选择目标设备和本地 IPSW。")
    }

    private func recomputeCompatibility() {
        guard let metadata = firmwareMetadata,
              let target = selectedTarget else {
            hardwareCompatibility = Self.defaultCompatibility
            return
        }
        hardwareCompatibility = IPSWCompatibilityEvaluator.evaluate(
            metadata: metadata,
            target: RestoreTargetIdentity(
                productType: target.productType,
                deviceClass: target.deviceClass,
                boardID: target.boardID,
                chipID: target.chipID))
    }

    nonisolated private static func sha256(ofFileAt url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8),
              let hash = text.split(whereSeparator: \.isWhitespace).first else {
            throw CocoaError(.fileReadUnknown)
        }
        return String(hash)
    }
}

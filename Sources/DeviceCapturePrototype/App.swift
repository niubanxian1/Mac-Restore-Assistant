import SwiftUI
import AppKit

@main
struct DeviceCapturePrototypeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @NSApplicationDelegateAdaptor(MRAApplicationDelegate.self) private var applicationDelegate
    @StateObject private var calibration: CalibrationStore
    @StateObject private var device: DeviceControlModel
    @StateObject private var logPreferences: LogWorkspacePreferences
    @StateObject private var rawPersistenceSettings: RestoreRawPersistenceSettings
    @StateObject private var capture: CaptureModel
    @StateObject private var restore: RestoreWorkspaceModel
    @StateObject private var firmwarePreferences: FirmwarePreferencesStore
    @StateObject private var previewSettings: LogPreviewSettings
    @StateObject private var helperEnvironment: HelperEnvironmentModel
    @StateObject private var calibrationTool: CalibrationToolLauncher
    @StateObject private var language = LanguageStore()
    @StateObject private var appearance = WorkbenchAppearancePreferences()

    private static var requestedDefaultWindowSize: CGSize {
        let raw = ProcessInfo.processInfo.environment["MRA_UI_WINDOW_SIZE"] ?? ""
        let parts = raw.lowercased().split(separator: "x")
        if parts.count == 2,
           let width = Double(parts[0]),
           let height = Double(parts[1]) {
            return CGSize(
                width: max(920, width),
                height: max(680, height))
        }
        return CGSize(width: 1000, height: 720)
    }

    init() {
        FirstLaunchAuthorizationWindowGuard.configureForLaunch()
        NSApplication.shared.setActivationPolicy(.regular)
        let env = ProcessInfo.processInfo.environment
        let fixtureRuntime = UIFixtureRuntimePolicy(environment: env)
        AppSupportLocations.configureProcessIsolationRoot(
            fixtureRuntime.applicationSupportRoot)
        let calibrationModel: CalibrationStore
        let deviceModel: DeviceControlModel
        if fixtureRuntime.isActive {
            let calibration = UIFixture.makeCalibrationStore()
            calibrationModel = calibration
            deviceModel = UIFixture.makeDevice(store: calibration)
        } else {
            let calibration = CalibrationStore()
            calibrationModel = calibration
            deviceModel = DeviceControlModel(calibration: calibration)
        }
        _calibration = StateObject(wrappedValue: calibrationModel)
        _device = StateObject(wrappedValue: deviceModel)

        let simulated = fixtureRuntime.usesSimulatedCapture
        let workspacePreferences = LogWorkspacePreferences()
        _logPreferences = StateObject(wrappedValue: workspacePreferences)
        let rawPersistence = RestoreRawPersistenceSettings()
        _rawPersistenceSettings = StateObject(
            wrappedValue: rawPersistence)
        let captureRoot: URL? =
            (
                fixtureRuntime.applicationSupportRoot != nil
                || AppSupportLocations.environmentOverride != nil
            )
            ? AppSupportLocations.sessionRoot()
            : nil
        let captureModel = CaptureModel(
            root: captureRoot,
            backendMode: simulated ? .simulated : .process,
            preferences: workspacePreferences,
            activateAutoMonitor: !UIFixture.isActive)
        _capture = StateObject(wrappedValue: captureModel)
        MRAApplicationDelegate.registerCapture(captureModel)
        let restoreFixtureActive = UIFixture.isRestoreRunning
        let fixtureRestoreEngineActive = UIFixture.isActive
        let firmwareLibrary = restoreFixtureActive
            ? UIFixture.makeFirmwareLibrary()
            : FirmwareLibraryStore()
        let firmwarePreferenceStore = FirmwarePreferencesStore()
        _firmwarePreferences = StateObject(
            wrappedValue: firmwarePreferenceStore)
        let restoreHistory = RestoreHistoryStore()
        let restoreModel = RestoreWorkspaceModel(
            capture: captureModel,
            engine: fixtureRestoreEngineActive
                ? UIFixture.makeRestoreEngine()
                : nil,
            observationHeartbeat: deviceModel.observationHeartbeat,
            portKeyResolver: { [weak deviceModel] device in
                deviceModel?.observedPortKey(for: device)
            },
            portDisplayNameResolver: { [weak deviceModel] key in
                guard let deviceModel,
                      let live = deviceModel.livePorts.first(where: { $0.id == key }) else {
                    return "端口未归属"
                }
                return deviceModel.label(for: live)
            },
            metadataReader: restoreFixtureActive
                ? UIFixture.readFirmwareMetadata
                : { try IPSWMetadataReader.read(url: $0) },
            cfgutilURL: fixtureRestoreEngineActive
                ? URL(fileURLWithPath: "/usr/bin/true")
                : nil,
            firmwareLibrary: firmwareLibrary,
            firmwarePreferences: firmwarePreferenceStore,
            historyStore: restoreHistory,
            rawPersistenceDefaultsProvider: {
                RestoreRawPersistenceDefaults(
                    autoSaveDefault:
                        rawPersistence.autoSaveRestoreRawLogs,
                    destinationDirectory:
                        UIFixture.isActive
                        ? (UIFixture.isolatedRawLogDirectory?.path
                            ?? "/__G4_RAW_UNSAFE__")
                        : workspacePreferences.rawLogDirectory,
                    autoMonitorEnabled:
                        workspacePreferences.autoMonitorEnabled,
                    spaceWarningThresholdBytes:
                        rawPersistence.spaceWarningThresholdBytes,
                    retentionPolicy:
                        "failures-\(rawPersistence.retentionDays)d-\(rawPersistence.retentionBytes)b/manual-delete")
            },
            stablePortKeyProvider: { target in
                let hostFingerprint = PortHistoryStore.fingerprint(
                    hostModel: calibrationModel.hostModel,
                    layout: calibrationModel.builtInLayout)
                return "\(hostFingerprint)|\(target.portKey ?? "unattributed")"
            },
            // 仅夹具模式注入隔离租约；正常启动保持 nil（= 共享权威租约）。
            processLease: UIFixture.isActive
                ? UIFixture.makeProcessLease()
                : nil,
            // 夹具下第二任务也必须使用夹具引擎，绝不能落到真实 cfgutil。
            secondaryEngineFactory: {
                UIFixture.isActive
                    ? UIFixture.makeRestoreEngine()
                    : CfgutilRestoreEngine()
            })
        _restore = StateObject(wrappedValue: restoreModel)
        MRAApplicationDelegate.registerRestore(restoreModel)
        if !UIFixture.isActive {
            let archiveRoot = URL(
                fileURLWithPath:
                    workspacePreferences.rawLogDirectory,
                isDirectory: true)
            let stagingRoot = AppSupportLocations.directory()
                .appendingPathComponent(
                    "RestoreStaging",
                    isDirectory: true)
            Task {
                let recovery = RestoreLogRetentionManager(
                    localStagingRoot: stagingRoot)
                _ = try? await recovery
                    .recoverPublishedArchives(
                        destinationRoot: archiveRoot)
                _ = try? await RestoreLogRetentionStore.shared
                    .recoverPendingExports()
            }
        }
        _previewSettings = StateObject(wrappedValue: LogPreviewSettings())

        let helperModel: HelperEnvironmentModel
        let helperSimulate = fixtureRuntime.helperSimulation
        if helperSimulate == .notInstalled
            || helperSimulate == .currentHealthy {
            // Isolated destinations and a mock executor: never invoke the real
            // install/uninstall scripts, and never touch system Helper paths.
            let root = AppSupportLocations.directory().appendingPathComponent("simulated-helper", isDirectory: true)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let destinations = HelperDestinations(
                helper: root.appendingPathComponent("helper"),
                backend: root.appendingPathComponent("backend"),
                plist: root.appendingPathComponent("plist"),
                socket: root.appendingPathComponent("sock"),
                logDirectory: root.appendingPathComponent("logs", isDirectory: true),
                packageDirectory: root)
            let io = MockHelperEnvironmentIO()
            if helperSimulate == .currentHealthy {
                io.files[destinations.helper.path] = (
                    KnownHelperManifest.expectedCurrentHelperSHA256, "6NFD357KL3", "签名有效")
                io.files[destinations.backend.path] = (
                    KnownHelperManifest.expectedCurrentBackendSHA256, "6NFD357KL3", "签名有效")
                io.files[destinations.plist.path] = (
                    KnownHelperManifest.expectedCurrentPlistSHA256, nil, "N/A")
                io.launchctl = "pid = 1\nstate = running"
                io.socketIsListening = true
            }
            helperModel = HelperEnvironmentModel(
                destinations: destinations,
                io: io,
                executor: MockHelperCommandExecutor(),
                requireExecutor: true)
        } else {
            helperModel = HelperEnvironmentModel(
                destinations: .system,
                io: LiveHelperEnvironmentIO(),
                executor: ProcessHelperCommandExecutor(),
                requireExecutor: false)
        }
        helperModel.bindDeviceConnection(deviceModel)
        _helperEnvironment = StateObject(wrappedValue: helperModel)
        _calibrationTool = StateObject(wrappedValue: CalibrationToolLauncher())
        // Let Launch Services activate the app for a normal user launch.
        // Forcing activation here can cover Gatekeeper's Privacy & Security
        // password prompt when an unnotarized build is opened for the first time.
    }

    var body: some Scene {
        Window("牛半仙Mac维修辅助工具", id: "main") {
            ContentView()
                .environmentObject(calibration)
                .environmentObject(device)
                .environmentObject(capture)
                .environmentObject(restore)
                .environmentObject(firmwarePreferences)
                .environmentObject(logPreferences)
                .environmentObject(rawPersistenceSettings)
                .environmentObject(previewSettings)
                .environmentObject(helperEnvironment)
                .environmentObject(calibrationTool)
                .environmentObject(language)
                .environmentObject(appearance)
                .environment(\.locale, language.locale)
                .frame(minWidth: 920, minHeight: 648)
                .onAppear {
                    helperEnvironment.redetect()
                    calibrationTool.attachReload {
                        calibration.reloadAdoptedOverlayFromDisk()
                    }
                    DispatchQueue.main.async {
                        for window in NSApplication.shared.windows where window.sheetParent == nil {
                            window.minSize = NSSize(width: 920, height: 680)
                            window.title = language.appDisplayName
                            window.titleVisibility = .hidden
                        }
                    }
                    if UIFixture.isActive {
                        Task { @MainActor in
                            await UIFixture.prepare(
                                device: device,
                                capture: capture,
                                restore: restore)
                        }
                    }
                }
                .onChange(of: language.resolvedCode) { _, _ in
                    for window in NSApplication.shared.windows where window.sheetParent == nil {
                        window.title = language.appDisplayName
                        window.titleVisibility = .hidden
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    capture.setDisplayTimerPaused(phase == .background)
                }
        }
        .defaultSize(
            width: Self.requestedDefaultWindowSize.width,
            height: Self.requestedDefaultWindowSize.height)
    }
}

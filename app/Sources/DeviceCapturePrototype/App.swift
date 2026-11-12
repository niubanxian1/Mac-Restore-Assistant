import SwiftUI
import AppKit

@main
struct DeviceCapturePrototypeApp: App {
    @StateObject private var calibration: CalibrationStore
    @StateObject private var device: DeviceControlModel
    @StateObject private var capture: CaptureModel
    @StateObject private var previewSettings: LogPreviewSettings
    @StateObject private var helperEnvironment: HelperEnvironmentModel
    @StateObject private var calibrationTool: CalibrationToolLauncher
    @StateObject private var language = LanguageStore()

    init() {
        let env = ProcessInfo.processInfo.environment
        if UIFixture.isActive {
            let calibration = UIFixture.makeCalibrationStore()
            _calibration = StateObject(wrappedValue: calibration)
            _device = StateObject(wrappedValue: UIFixture.makeDevice(store: calibration))
        } else {
            let calibration = CalibrationStore()
            _calibration = StateObject(wrappedValue: calibration)
            _device = StateObject(wrappedValue: DeviceControlModel(calibration: calibration))
        }

        let simulated = env["MRA_CAPTURE_BACKEND"] == "simulated"
        let captureRoot: URL? = AppSupportLocations.environmentOverride == nil
            ? nil
            : AppSupportLocations.sessionRoot()
        _capture = StateObject(wrappedValue: CaptureModel(
            root: captureRoot,
            backendMode: simulated ? .simulated : .process))
        _previewSettings = StateObject(wrappedValue: LogPreviewSettings())

        let helperModel: HelperEnvironmentModel
        let helperSimulate = env["MRA_HELPER_SIMULATE"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if helperSimulate == "not_installed" || helperSimulate == "current_healthy" {
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
            if helperSimulate == "current_healthy" {
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
        _helperEnvironment = StateObject(wrappedValue: helperModel)
        _calibrationTool = StateObject(wrappedValue: CalibrationToolLauncher())
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup("牛半仙Mac维修辅助工具") {
            ContentView()
                .environmentObject(calibration)
                .environmentObject(device)
                .environmentObject(capture)
                .environmentObject(previewSettings)
                .environmentObject(helperEnvironment)
                .environmentObject(calibrationTool)
                .environmentObject(language)
                .environment(\.locale, language.locale)
                .frame(minWidth: 920, minHeight: 680)
                .onAppear {
                    helperEnvironment.redetect()
                    calibrationTool.attachReload {
                        calibration.reloadAdoptedOverlayFromDisk()
                    }
                    DispatchQueue.main.async {
                        for window in NSApplication.shared.windows where window.sheetParent == nil {
                            window.title = language.appDisplayName
                        }
                    }
                    if UIFixture.isActive {
                        Task { @MainActor in
                            await UIFixture.prepare(device: device, capture: capture)
                        }
                    }
                }
                .onChange(of: language.resolvedCode) { _ in
                    for window in NSApplication.shared.windows where window.sheetParent == nil {
                        window.title = language.appDisplayName
                    }
                }
        }
        .defaultSize(width: 1000, height: 720)
    }
}

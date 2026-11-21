import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

enum PrimaryWorkspaceTab: String, CaseIterable, Identifiable {
    case device
    case restore
    case logs

    var id: String { rawValue }
    var title: String {
        switch self {
        case .device: return "端口与设备"
        case .logs: return "RLM 日志"
        case .restore: return "固件与恢复"
        }
    }
}

extension ConfiguratorResetModel {
    static func makeForUI(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        applicationSupportRoot: URL = AppSupportLocations.directory()
    ) -> ConfiguratorResetModel {
        let fixtureName = environment["MRA_UI_FIXTURE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard fixtureName?.isEmpty == false else {
            return makeFromEnvironment()
        }

        let home = applicationSupportRoot.appendingPathComponent(
            "configurator-home",
            isDirectory: true)
        try? FileManager.default.createDirectory(
            at: home,
            withIntermediateDirectories: true)
        return ConfiguratorResetModel(
            home: home,
            executor: MockConfiguratorExecutor(running: false),
            simulationOnly: true)
    }
}

struct ContentView: View {
    @EnvironmentObject private var calibration: CalibrationStore
    @EnvironmentObject private var device: DeviceControlModel
    @EnvironmentObject private var capture: CaptureModel
    @EnvironmentObject private var restore: RestoreWorkspaceModel
    @EnvironmentObject private var logPreferences: LogWorkspacePreferences
    @EnvironmentObject private var rawPersistenceSettings:
        RestoreRawPersistenceSettings
    @EnvironmentObject private var previewSettings: LogPreviewSettings
    @EnvironmentObject private var helperEnvironment: HelperEnvironmentModel
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var appearance: WorkbenchAppearancePreferences
    @StateObject private var configuratorReset = ConfiguratorResetModel.makeForUI()
    @StateObject private var panorama = PanoramaViewModel()
    @StateObject private var observation = PortDeviceWorkspaceModel()
    @State private var showSettings = false
    @State private var settingsTab: SettingsTab = .model
    @State private var showConfiguratorReset = false
    @State private var showInstallPrompt = false
    @State private var didOfferInstall = false
    @State private var workspaceTab: PrimaryWorkspaceTab = .device

    var body: some View {
        MinimalWorkbenchView(
            panorama: panorama,
            observation: observation,
            configuratorReset: configuratorReset,
            workspaceTab: $workspaceTab,
            showSettings: $showSettings,
            settingsTab: $settingsTab)
        .sheet(isPresented: $showSettings) {
            SettingsView(selectedTab: $settingsTab, configuratorReset: configuratorReset)
                .environmentObject(calibration)
                .environmentObject(device)
                .environmentObject(previewSettings)
                .environmentObject(logPreferences)
                .environmentObject(rawPersistenceSettings)
                .environmentObject(restore)
                .environmentObject(helperEnvironment)
                .environmentObject(language)
                .environmentObject(appearance)
                .environment(\.locale, language.locale)
                .frame(minWidth: 820, minHeight: 640)
                .onAppear { helperEnvironment.redetect() }
        }
        .sheet(isPresented: $showConfiguratorReset) {
            ConfiguratorResetView(model: configuratorReset)
        }
        .background {
            shortcutHost
        }
        .onAppear {
            applyIsolatedPresentationOverrides()
            capture.setPreviewVisible(workspaceTab == .logs)
            panorama.startWatching(device: device)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                offerInstallIfNeeded()
            }
        }
        .onChange(of: workspaceTab) { _, tab in
            capture.setPreviewVisible(tab == .logs)
        }
        .onReceive(
            capture.$lastExportManifest.compactMap { $0 }
        ) { manifest in
            guard let exportURL = capture.lastEvidencePackageURL else {
                return
            }
            Task {
                let taskIDs = await restore.linkedTaskIDs(
                    forRLMSessionID: manifest.sessionID)
                do {
                    _ = try await RestoreLogRetentionStore.shared
                        .registerExportWithFallback(
                        exportURL: exportURL,
                        linkedSessionID: manifest.sessionID,
                        linkedTaskIDs: taskIDs)
                    await MainActor.run {
                        restore.message =
                            "证据包已导出，关联日志保护已持久登记。"
                    }
                } catch RestoreLogRetentionError
                    .pendingExportProtectionPersisted {
                    await MainActor.run {
                        restore.errorMessage =
                            "证据包已生成，但保护登记写入失败；已保存待重试标记，日志清理保持关闭。"
                    }
                } catch {
                    await MainActor.run {
                        restore.errorMessage =
                            "证据包已生成，但保护登记和待重试标记均写入失败；本次运行已禁用日志清理。"
                    }
                }
            }
        }
        .onDisappear {
            capture.setPreviewVisible(false)
            panorama.stopWatching()
        }
        .onChange(of: helperEnvironment.snapshot.kind) { _, kind in
            if kind == .notInstalled {
                offerInstallIfNeeded()
            } else {
                didOfferInstall = false
                showInstallPrompt = false
            }
        }
        .alert(Text(L10n.installAlertTitle()), isPresented: $showInstallPrompt) {
            Button(L10n.installAlertButton()) {
                showInstallPrompt = false
                helperEnvironment.perform(.install, quarantineConfirmed: true)
            }
            Button(L10n.t("稍后"), role: .cancel) {}
        } message: {
            Text(L10n.installAlertMessage())
        }
    }

    private var shortcutHost: some View {
        HStack(spacing: 0) {
            Button("") { workspaceTab = .device }
                .keyboardShortcut("1", modifiers: .command)
            Button("") { workspaceTab = .restore }
                .keyboardShortcut("2", modifiers: .command)
            Button("") { workspaceTab = .logs }
                .keyboardShortcut("3", modifiers: .command)
            Button("") {
                switch workspaceTab {
                case .restore:
                    restore.startFirmwareDiscovery()
                case .device:
                    device.refreshObservedDevices()
                    device.refreshPorts()
                case .logs:
                    break
                }
            }
            .keyboardShortcut("r", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func offerInstallIfNeeded() {
        guard !didOfferInstall, helperEnvironment.snapshot.kind == .notInstalled else { return }
        didOfferInstall = true
        showInstallPrompt = true
    }

    private func applyIsolatedPresentationOverrides() {
        let env = ProcessInfo.processInfo.environment
        if let raw = env["MRA_UI_OPEN_SETTINGS"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            switch raw {
            case "helper": settingsTab = .helper
            case "about": settingsTab = .about
            case "configurator": settingsTab = .configurator
            case "model": settingsTab = .model
            case "port": settingsTab = .port
            case "map": settingsTab = .map
            case "logFilter": settingsTab = .logFilter
            case "storage": settingsTab = .storage
            case "firmware": settingsTab = .firmware
            case "language": settingsTab = .language
            case "appearance": settingsTab = .appearance
            default: break
            }
            showSettings = true
        }
        if env["MRA_UI_OPEN_APPEARANCE"] == "1" {
            settingsTab = .appearance
            showSettings = true
        }
        if env["MRA_UI_OPEN_CONFIGURATOR_PANEL"] == "1" {
            showConfiguratorReset = true
        }
        if env["MRA_UI_OPEN_LOG_WORKSPACE"] == "1" {
            workspaceTab = .logs
        }
        if env["MRA_UI_OPEN_PANORAMA"] == "1" {
            workspaceTab = .device
        }
        if env["MRA_UI_OPEN_RESTORE_WORKSPACE"] == "1" {
            workspaceTab = .restore
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(language.appDisplayName)
                    .font(.system(size: 20, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.t("设备控制与日志采集 · 先看清端口和设备，再采集日志；刷机仍用 Apple Configurator。"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(AboutSoftwareInfo.productVersion)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
            headerConfiguratorAction
            Button(L10n.t("设置")) { showSettings = true }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .padding(.bottom, 10)
    }

    private var headerConfiguratorAction: some View {
        Button {
            configuratorReset.runPreferredAction()
        } label: {
            Label(
                configuratorReset.isBusy
                    ? L10n.t("正在执行…")
                    : configuratorReset.mainActionTitle,
                systemImage: "arrow.clockwise.circle")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
        .disabled(configuratorReset.isBusy)
        .help(L10n.t(configuratorReset.preferredActionSummary))
        .accessibilityIdentifier("header-configurator-action")
    }
}

// MARK: - Left device control

struct DeviceControlPane: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var calibration: CalibrationStore
    @EnvironmentObject private var device: DeviceControlModel
    @EnvironmentObject private var helperEnvironment: HelperEnvironmentModel
    @ObservedObject var panorama: PanoramaViewModel
    @Binding var showSettings: Bool
    @Binding var settingsTab: SettingsTab
    @State private var portDetailsExpanded = true

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("设备控制"))
                .font(.system(size: 15, weight: .semibold))

            VStack(spacing: 4) {
                ForEach(device.priorityOrderedDisplayPorts) { port in
                    portRow(port)
                }
                if device.livePorts.isEmpty {
                    Text(L10n.t("未识别到主机 AppleHPM 端口"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }

            portDetailsDisclosure

            Text(L10n.t(device.operationTargetText))
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            actionButtons
            if !device.disabledReason.isEmpty {
                Label(L10n.t(device.disabledReason), systemImage: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            feedbackCard

            if !device.lastActionLog.isEmpty {
                Text(device.lastActionLog)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            HStack(alignment: .center, spacing: 14) {
                Button {
                    settingsTab = .helper
                    showSettings = true
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(helperStatusColor)
                            .frame(width: 8, height: 8)
                        Text(L10n.t(HelperRuntimePresentation.homeText(
                            snapshot: helperEnvironment.snapshot,
                            authenticatedCallAvailable: device.helperAvailable)))
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("打开 Helper / 运行环境管理页")
                .accessibilityLabel("Helper 状态：\(HelperRuntimePresentation.homeText(snapshot: helperEnvironment.snapshot, authenticatedCallAvailable: device.helperAvailable))")

                Button {
                    // Navigation only: existing Settings → 模型校准.
                    settingsTab = .model
                    showSettings = true
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(calibrationStatusColor)
                            .frame(width: 8, height: 8)
                        Text(L10n.t(device.hostCalibrationLampState.text))
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(device.hostCalibrationLampHelp)
                .accessibilityLabel("主机校准状态：\(device.hostCalibrationLampState.text)")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var portDetailsDisclosure: some View {
        DisclosureGroup(L10n.t("端口详情"), isExpanded: $portDetailsExpanded) {
            Group {
                if let port = device.selectedLivePort {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("控制器 \(port.controller) · PortNumber \(port.portNumber) · RID \(port.rid)"))
                            .font(.system(size: 11, design: .monospaced))
                        Text(L10n.t(device.builtInSlotSummary))
                            .font(.system(size: 11))
                        Text(L10n.t(device.selectedSourceText))
                            .font(.system(size: 11))
                        Text(L10n.t("主机校准：\(device.hostCalibrationMatchDetail)"))
                            .font(.system(size: 11))
                        if device.hostLayoutMappingConflict {
                            Text(L10n.t("布局核对：\(device.hostLayoutMappingConflictDetail)"))
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(L10n.t("模型：\(device.selectedModelSummary)"))
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                } else {
                    Text(L10n.t("尚未选择主机物理端口"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .font(.system(size: 12))
    }

    private func portRow(_ port: LiveHostPort) -> some View {
        let selected = device.selectedLiveKey == port.id
        let highlighted = device.brieflyHighlightedPortKeys.contains(port.id)
        let identity = device.compactPortIdentity(
            for: port,
            sharedUSB: panorama.mainPortProjection(for: port))
        return Button {
            device.selectPort(port)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .font(.system(size: 16, weight: selected ? .semibold : .regular))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(identity.firstLine))
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(L10n.t(identity.secondLine))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(selected ? Color.accentColor : Color.clear)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(highlighted && !selected ? Color.secondary.opacity(0.55) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t(identity.accessibilityLabel))
        .disabled(!device.canChangePortSelection)
        .opacity(device.canChangePortSelection ? 1 : 0.55)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    device.performDFU()
                } label: {
                    Label(L10n.t("进入 DFU"), systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!device.canControl)

                Button {
                    device.performReboot()
                } label: {
                    Label(L10n.t("重启设备"), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!device.canControl)
            }
#if MRA_TEST_BOOT_OPTIONS
            Button {
                device.performTestBootOptionsTriple()
            } label: {
                Label("测试启动选项（15 秒 5 次）", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!device.canControl || device.bootOptionsTestActive)
            .help("仅测试：0/3/6/9/12 秒向同一端口各发一次普通重启；15 秒窗口；不是恢复模式")
            if device.bootOptionsTestActive {
                HStack(spacing: 8) {
                    Text(device.bootOptionsTestStatusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(L10n.t("停止后续")) { device.stopPendingBootOptionsTest() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(!device.bootOptionsTestCanStop)
                }
            } else {
                Text(L10n.t("测试假设：0/3/6/9/12 秒五次普通重启；15 秒窗口；不调用 serial/DVEn，不自动宣告恢复模式。"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
#else
            Button {
                device.performRecoveryMode()
            } label: {
                Label(L10n.t("恢复模式"), systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!device.canControl || device.bootOptionsTestActive)
            .help("恢复模式 / Recovery：向当前物理口发送五次普通重启；15 秒窗口结束；不调用 reboot serial/DVEn")
            if device.bootOptionsTestActive {
                HStack(spacing: 8) {
                    Text(device.bootOptionsTestStatusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(L10n.t("停止后续")) { device.stopPendingBootOptionsTest() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(!device.bootOptionsTestCanStop)
                }
            }
#endif
        }
    }

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: icon(for: device.feedback.tone))
                    .foregroundStyle(color(for: device.feedback.tone))
                Text(L10n.t(device.feedback.title)).font(.system(size: 13, weight: .semibold))
                Spacer()
                if device.actionInFlight {
                    ProgressView().controlSize(.small)
                }
            }
            Text(L10n.t(device.feedback.detail))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(color(for: device.feedback.tone).opacity(0.08)))
    }

    private var helperStatusColor: Color {
        switch HelperRuntimePresentation.homeColor(
            snapshot: helperEnvironment.snapshot,
            authenticatedCallAvailable: device.helperAvailable) {
        case "green": return .green
        case "orange": return .orange
        case "yellow": return .yellow
        case "red": return .red
        default: return .secondary
        }
    }

    private var calibrationStatusColor: Color {
        switch device.hostCalibrationLampState.color {
        case "green": return .green
        case "orange": return .orange
        default: return .secondary
        }
    }

    private func color(for tone: ControlFeedbackTone) -> Color {
        switch tone {
        case .neutral: return .secondary
        case .working: return .accentColor
        case .success: return .primary
        case .warning, .failure: return .red
        }
    }

    private func icon(for tone: ControlFeedbackTone) -> String {
        switch tone {
        case .neutral: return "circle"
        case .working: return "hourglass"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.octagon.fill"
        }
    }
}

// MARK: - Top-right capture

struct CapturePane: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var capture: CaptureModel
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var configuratorReset: ConfiguratorResetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    Text(L10n.t("刷机日志采集"))
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    resetConfiguratorButton
                    statePill
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(L10n.t("刷机日志采集"))
                            .font(.system(size: 15, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        statePill
                    }
                    resetConfiguratorButton
                }
            }

            if !resetMessage.isEmpty {
                Text(L10n.t(resetMessage))
                    .font(.system(size: 11))
                    .foregroundStyle(resetMessage.contains("未完成") || resetMessage.contains("失败") ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .center, spacing: 10) {
                captureToggleButton
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.t(capture.stateText))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(L10n.t(capture.captureMeterText))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Text(L10n.t("文件名"))
                    .font(.system(size: 13, weight: .medium))
                TextField("默认名称，可修改", text: $capture.exportBaseName)
                    .textFieldStyle(.roundedBorder)
            }
            .onAppear {
                if capture.exportBaseName.isEmpty {
                    capture.exportBaseName = capture.defaultBaseName
                }
            }

            HStack(alignment: .center, spacing: 16) {
                exportButton
                Button(L10n.t(capture.discardButtonTitle)) {
                    capture.discardUnsavedSession()
                }
                .buttonStyle(.bordered)
                .disabled(!capture.canDiscardUnsavedSession)
                .help("停止抓取并删除本次未导出的日志")
                if !capture.exportDisabledReason.isEmpty {
                    Text(L10n.t(capture.exportDisabledReason))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if capture.isExporting {
                    ProgressView().controlSize(.small)
                    if !capture.exportProgressText.isEmpty {
                        Text(L10n.t(capture.exportProgressText))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if let zipName = capture.savedZipURL?.lastPathComponent {
                HStack(alignment: .center, spacing: 10) {
                    Text(L10n.t("已保存：\(zipName)"))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                    Button(L10n.t("复制 ZIP")) { capture.copySavedZip() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!capture.canCopyExportedZip)
                    Button(L10n.t("在访达中显示")) { capture.revealSavedFiles() }
                        .buttonStyle(.bordered)
                        .disabled(!capture.canRevealExportedZip)
                    Spacer(minLength: 0)
                }
            } else if !capture.copyDisabledReason.isEmpty {
                Text(L10n.t(capture.copyDisabledReason))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if !capture.saveMessage.isEmpty {
                Text(L10n.t(capture.saveMessage))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !capture.captureError.isEmpty {
                Text(L10n.t(capture.captureError))
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .onChange(of: scenePhase) { _, phase in
            capture.setDisplayTimerPaused(phase == .background)
        }
    }

    @ViewBuilder
    private var captureToggleButton: some View {
        if capture.isCapturing {
            Button(L10n.t("停止采集")) { capture.stop() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(capture.state == .stopping || capture.state == .finalizing)
        } else if capture.canExportZIP {
            Button(L10n.t("开始采集")) { capture.start() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(capture.state == .stopping || capture.state == .finalizing)
        } else {
            Button(L10n.t("开始采集")) { capture.start() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(capture.state == .stopping || capture.state == .finalizing)
        }
    }

    @ViewBuilder
    private var exportButton: some View {
        if capture.canExportZIP {
            Button(L10n.t("导出 ZIP…")) { chooseExportFolder() }
                .buttonStyle(.borderedProminent)
        } else {
            Button(L10n.t("导出 ZIP…")) { chooseExportFolder() }
                .buttonStyle(.bordered)
                .disabled(true)
        }
    }

    private var resetConfiguratorButton: some View {
        Button {
            configuratorReset.runPreferredAction()
        } label: {
            Label(isResetRunning ? L10n.t("正在执行…") : configuratorReset.mainActionTitle,
                  systemImage: "arrow.clockwise.circle")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 6)
                .frame(minHeight: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(isResetRunning)
        .help(L10n.t(configuratorReset.preferredActionSummary))
    }

    private var isResetRunning: Bool {
        configuratorReset.isBusy
    }

    private var resetMessage: String {
        configuratorReset.overallMessage
    }

    private var statePill: some View {
        HStack(spacing: 6) {
            Circle().fill(colorForState).frame(width: 7, height: 7)
            Text(L10n.t(capture.stateText)).font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Color.secondary.opacity(0.10)))
    }

    private var colorForState: Color {
        switch capture.state {
        case .recording: return .green
        case .starting, .stopping, .finalizing: return .accentColor
        case .failed, .interrupted: return .red
        default: return .secondary
        }
    }

    private func chooseExportFolder() {
        guard capture.canExportZIP else { return }
        if let preset = ProcessInfo.processInfo.environment["MRA_EXPORT_DIRECTORY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !preset.isEmpty {
            let url = URL(fileURLWithPath: preset, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            capture.save(folder: url, baseName: capture.exportBaseName)
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择保存位置"
        panel.message = "将导出一个包含完整原始日志与证据的 ZIP"
        if let last = UserDefaults.standard.string(forKey: "MRA.lastSaveFolder") {
            panel.directoryURL = URL(fileURLWithPath: last, isDirectory: true)
        }
        if panel.runModal() == .OK, let url = panel.url {
            capture.save(folder: url, baseName: capture.exportBaseName)
        }
    }
}

// MARK: - Bottom-right selected-port detail

struct CombinedPortDeviceWorkspace: View {
    @ObservedObject var panorama: PanoramaViewModel
    @EnvironmentObject private var device: DeviceControlModel
    @StateObject private var observation = PortDeviceWorkspaceModel()
    @State private var showSimpleDeviceTree = false

    var body: some View {
        GeometryReader { geometry in
            let availableHeight = geometry.size.height
            let hasExpandedTree = observation.density != .simple || showSimpleDeviceTree
            let detailHeight = min(
                max(190, availableHeight * (hasExpandedTree ? 0.44 : 0.72)),
                max(190, availableHeight - (hasExpandedTree ? 230 : 92)))
            VStack(spacing: 0) {
                observationToolbar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                Divider()
                ScrollView {
                    SelectedPortDetailPane(
                        panorama: panorama,
                        port: observedPort,
                        density: observation.density,
                        showPanoramaSummary: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .defaultScrollAnchor(.top)
                .frame(height: detailHeight)
                .accessibilityIdentifier("port-device-detail-scroll")

                Divider()

                if hasExpandedTree {
                    PanoramaView(model: panorama, isEmbedded: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("port-device-tree")
                } else {
                    Button {
                        showSimpleDeviceTree = true
                    } label: {
                        Label(L10n.t("展开接口与设备树"), systemImage: "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                    .accessibilityIdentifier("port-device-tree-expand")
                }
            }
        }
        .accessibilityIdentifier("port-device-workspace")
    }

    private var availablePorts: [LiveHostPort] {
        device.priorityOrderedDisplayPorts
    }

    private var observedPort: LiveHostPort? {
        let portID = observation.observationPortID(
            controlPortID: device.selectedLiveKey,
            availablePortIDs: availablePorts.map(\.id))
        return portID.flatMap { key in
            availablePorts.first { $0.id == key }
        }
    }

    private var observationToolbar: some View {
        HStack(spacing: 12) {
            Text(L10n.t("查看端口"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Picker(
                "",
                selection: Binding(
                    get: {
                        observation.followsLeftControl
                            ? "__follow_left__"
                            : observation.fixedPortID ?? "__follow_left__"
                    },
                    set: { value in
                        if value == "__follow_left__" {
                            observation.followLeftControl()
                        } else {
                            observation.setFixedObservationPort(value)
                        }
                    })
            ) {
                Text(L10n.t("跟随左侧"))
                    .tag("__follow_left__")
                ForEach(availablePorts) { port in
                    Text(device.label(for: port))
                        .tag(port.id)
                }
            }
            .labelsHidden()
            .frame(minWidth: 180, idealWidth: 230, maxWidth: 280)

            Spacer(minLength: 8)

            Picker("", selection: $observation.density) {
                ForEach(PortDisplayDensity.allCases) { density in
                    Text(L10n.t(density.title)).tag(density)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)
            .accessibilityIdentifier("port-device-density")
        }
    }
}

struct SelectedPortDetailPane: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var device: DeviceControlModel
    @ObservedObject var panorama: PanoramaViewModel
    var port: LiveHostPort?
    var density: PortDisplayDensity = .all
    var showPanoramaSummary = true
    @State private var technicalDetailsExpanded = true

    var body: some View {
        let selectedPort = port
        let sharedUSB = selectedPort.flatMap { panorama.mainPortProjection(for: $0) }
        let detail = selectedPort.map {
            device.detail(for: $0, sharedUSB: sharedUSB)
        } ?? device.selectedPortDetail(sharedUSB: nil)
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t(detail.title))
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t(detail.currentHeadline))
                    .font(.system(size: 16, weight: .medium))
                if detail.hasCurrentDevice {
                    if let ecid = detail.ecid, !ecid.isEmpty {
                        labeledCopyable(name: "ECID", value: ecid)
                    }
                    if let serial = detail.serial, !serial.isEmpty {
                        labeledCopyable(name: "序列号", value: serial)
                    }
                    if let summary = detail.connectionSummary, !summary.isEmpty {
                        Text(L10n.t(summary))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if let reconnect = detail.reconnectText, !reconnect.isEmpty {
                        Text(L10n.t("重连耗时：\(reconnect)"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else if let last = detail.lastIdentified {
                    Text(L10n.t(last))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("最近连接变化"))
                    .font(.system(size: 12, weight: .semibold))
                if detail.recentChanges.isEmpty {
                    Text(L10n.t(detail.emptyChangesText))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    let formatter = ConnectionChangeEngine.timeFormatter()
                    ForEach(detail.recentChanges) { event in
                        Text(L10n.t(event.displayLine(formatter: formatter)))
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .foregroundStyle(.primary)
                    }
                }
            }

            if let selectedPort {
                USBConnectionTimingView(
                    panorama: panorama,
                    port: selectedPort)
            }

            technicalDetailsBlock(detail)

            if showPanoramaSummary {
                selectedPortPanoramaBlock(for: selectedPort)
            }

            Button(L10n.t("复制摘要")) {
                copySummary(detail: detail, sharedUSB: sharedUSB)
            }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if panorama.updated == nil { panorama.refreshUSBOnly() }
        }
    }

    private var technicalToggleLabel: String {
        technicalDetailsExpanded ? L10n.t("收起") : L10n.t("展开")
    }

    private func technicalDetailsBlock(_ detail: SelectedPortDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                technicalDetailsExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: technicalDetailsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 12)
                    Text(L10n.t("技术详情"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(technicalToggleLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if technicalDetailsExpanded && density != .simple {
                if detail.technicalRows.isEmpty {
                    Text(L10n.t(detail.hasCurrentDevice ? "当前没有额外的连接路径信息" : "当前未识别到设备，没有可展示的连接路径"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(grouped(detail.technicalRows), id: \.0) { group, rows in
                            Text(L10n.t(group))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                            ForEach(rows) { row in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(L10n.t(row.name))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 120, alignment: .leading)
                                    Text(L10n.t(row.value))
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                    Spacer(minLength: 0)
                                }
                                .id(language.resolvedCode)
                            }
                        }
                    }
                }
            }
        }
    }

    private func grouped(_ rows: [TechnicalDetailRow]) -> [(String, [TechnicalDetailRow])] {
        let visibleRows = rows.filter {
            PortDeviceDensityPolicy.visible(group: $0.group, density: density)
        }
        var order: [String] = []
        var map: [String: [TechnicalDetailRow]] = [:]
        for row in visibleRows {
            if map[row.group] == nil { order.append(row.group) }
            map[row.group, default: []].append(row)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private func selectedPortPanoramaBlock(for selectedPort: LiveHostPort?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("同端口只读 USB 全景"))
                .font(.system(size: 12, weight: .semibold))
            if let live = selectedPort,
               let projection = panorama.mainPortProjection(for: live) {
                Text(projection.displayName ?? L10n.t(projection.modeText))
                    .font(.system(size: 11, weight: .medium))
                Text(L10n.t(projection.evidence))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text(L10n.t("没有可信的当前 USB location 归属；不强行分配外设或线材。"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func labeledCopyable(name: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func copySummary(detail: SelectedPortDetail, sharedUSB: MainPortUSBProjection?) {
        var lines = [detail.title, detail.currentHeadline]
        if let ecid = detail.ecid, !ecid.isEmpty { lines.append("ECID: \(ecid)") }
        if let serial = detail.serial, !serial.isEmpty { lines.append("Serial: \(serial)") }
        if let sharedUSB { lines.append(sharedUSB.evidence) }
        lines.append(contentsOf: detail.technicalRows
            .filter { PortDeviceDensityPolicy.visible(group: $0.group, density: density) }
            .map { "\($0.name): \($0.value)" })
        let text = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct USBConnectionTimingView: View {
    @ObservedObject var panorama: PanoramaViewModel
    let port: LiveHostPort
    @State private var expanded =
        ProcessInfo.processInfo.environment["MRA_QA_EXPAND_TIMING"] == "1"
    @State private var copied = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let snapshot = panorama.timelineSnapshot(
                    for: port,
                    wallTime: context.date)
                VStack(alignment: .leading, spacing: 7) {
                    if snapshot.isIncomplete {
                        Label(
                            L10n.t("观察不完整；缺失区间不计算精确次数"),
                            systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    timingSummary(snapshot)
                    HStack(spacing: 8) {
                        Button(L10n.t("复制当前口时序")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(
                                USBConnectionTimelineFormatter.copyText(snapshot),
                                forType: .string)
                            copied = true
                        }
                        .buttonStyle(.bordered)
                        Button(L10n.t("清零当前口统计")) {
                            panorama.clearTimeline(for: port, wallTime: context.date)
                        }
                        .buttonStyle(.bordered)
                        if copied {
                            Text(L10n.t("已复制同屏快照"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !snapshot.recentEvents.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t("最近 10 条真实出现/消失"))
                                .font(.system(size: 11, weight: .semibold))
                            ForEach(snapshot.recentEvents) { event in
                                Text(USBConnectionTimelineFormatter.eventLine(event))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.secondary)
                Text(L10n.t("USB 时序观察"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("usb-connection-timing")
    }

    @ViewBuilder
    private func timingSummary(_ snapshot: USBConnectionTimelineSnapshot) -> some View {
        if let current = snapshot.currentPresence {
            Text(
                L10n.t("当前：")
                + L10n.t(current.mode.displayText)
                + " · "
                + (current.productName ?? L10n.t("身份待识别")))
                .font(.system(size: 12, weight: .medium))
            if let residence = snapshot.currentResidenceSeconds {
                Text(
                    L10n.t("当前驻留：")
                    + USBConnectionTimelineFormatter.duration(residence))
                    .font(.system(size: 11, design: .monospaced))
            } else if let observed = snapshot.observedAtLeastSeconds {
                let baseline = current.startKind == .sessionStart
                    ? L10n.t("开始观察时已存在")
                    : L10n.t("清零后建立观察基线")
                Text(
                    baseline
                    + "；"
                    + L10n.t("出现时间未知")
                    + "；"
                    + L10n.t("已观察至少")
                    + USBConnectionTimelineFormatter.duration(observed))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(L10n.t("当前未见可归属于此口的 USB 设备"))
                .font(.system(size: 12, weight: .medium))
        }
        Text(
            L10n.t("上次驻留：")
            + USBConnectionTimelineFormatter.duration(snapshot.lastResidenceSeconds))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        Text(
            L10n.t("上次端口再出现间隔：")
            + USBConnectionTimelineFormatter.duration(snapshot.lastReappearanceGapSeconds))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        Text(
            L10n.t("最近 60 秒端口再出现：")
            + L10n.times(snapshot.portReappearancesIn60Seconds))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        if let same = snapshot.sameMachineReenumerationsIn60Seconds {
            Text(
                L10n.t("其中同机重枚举：")
                + L10n.times(same))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            Text(L10n.t("同机重枚举：未知"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        if snapshot.droppedEventCount > 0 {
            Text(
                L10n.t("事件不完整，至少丢失")
                + String(snapshot.droppedEventCount)
                + L10n.t("条"))
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Settings

enum SettingsTab: String, Hashable, CaseIterable, Identifiable {
    case model, port, map, logFilter, storage, firmware, language, appearance, helper, configurator, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .model: return "模型校准"
        case .port: return "端口校准"
        case .map: return "校准与位置图"
        case .logFilter: return "日志预览过滤"
        case .storage: return "日志存储与清理"
        case .firmware: return "固件偏好"
        case .language: return "语言"
        case .appearance: return "外观与动效"
        case .helper: return "Helper / 运行环境"
        case .about: return "关于软件"
        case .configurator: return "Apple Configurator"
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTab: SettingsTab
    @ObservedObject var configuratorReset: ConfiguratorResetModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("设置")).font(.system(size: 20, weight: .semibold))
                Spacer()
                Button(L10n.t("完成")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            HStack(spacing: 0) {
                List(SettingsTab.allCases, selection: $selectedTab) { tab in
                    Text(L10n.t(tab.title))
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .tag(tab)
                }
                .listStyle(.sidebar)
                .frame(minWidth: 200, idealWidth: 216, maxWidth: 240)
                Divider()
                Group {
                    switch selectedTab {
                    case .model: InAppModelCalibrationView()
                    case .port: PortCalibrationView()
                    case .map: LocationMapView()
                    case .language: LanguageSettingsView()
                    case .firmware: FirmwarePreferencesSettingsView()
                    case .appearance: WorkbenchAppearanceSettingsView()
                    case .helper: HelperEnvironmentView()
                    case .logFilter: LogFilterSettingsView()
                    case .storage: StorageCleanupSettingsView()
                    case .about: AboutSoftwareView()
                    case .configurator: ConfiguratorStorageReadOnlyView(model: configuratorReset)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

struct LanguageSettingsView: View {
    @EnvironmentObject private var language: LanguageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("界面语言"))
                .font(.system(size: 15, weight: .semibold))
            Text(L10n.t("只改变界面显示，不会改变端口选择、设备状态、DFU、重启、恢复序列或采集。"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Picker(L10n.t("语言"), selection: $language.mode) {
                Text(L10n.t("简体中文")).tag("zh-Hans")
                Text(L10n.t("繁體中文")).tag("zh-Hant")
                Text(L10n.t("English")).tag("en")
                Text(L10n.t("日本語")).tag("ja")
                Text(L10n.t("한국어")).tag("ko")
            }
            .pickerStyle(.radioGroup)
            Text(L10n.t("当前：\(language.modeLabel)"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct LogFilterSettingsView: View {
    @EnvironmentObject private var previewSettings: LogPreviewSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("单机刷机日志预览过滤")).font(.system(size: 15, weight: .semibold))
            Text(L10n.t(previewSettings.caption))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Toggle(L10n.t("启用预览过滤"), isOn: $previewSettings.isEnabled)
            if previewSettings.isEnabled {
                Picker(L10n.t("预览范围"), selection: $previewSettings.scope) {
                    ForEach(LogPreviewScope.allCases) { scope in
                        Text(L10n.t(scope.rawValue)).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
            }
            Text(L10n.t("关闭后立即回到完整原始预览，不会留下隐藏的活动过滤条件。保存始终为完整原始日志。主界面默认不显示实时日志行。"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
    }
}

struct ModelCalibrationView: View {
    @EnvironmentObject private var store: CalibrationStore
    @EnvironmentObject private var device: DeviceControlModel
    @EnvironmentObject private var calibrationTool: CalibrationToolLauncher
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("模型校准")).font(.system(size: 15, weight: .semibold))
            Text(L10n.t("打开独立校准工具 Hardware Preview B.1（\(CalibrationToolLauncher.expectedVersion)）编辑布局并自行校准。本页不再用简化 RID 表代替该工具。导入模型包来自 v2 整合能力，不是 B.1 成品里已有的导入按钮。"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t(device.hostCalibrationSummaryText))
                    .font(.system(size: 11, weight: .medium))
                Text(store.builtInStatusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let overlay = store.adoptedOverlay {
                    Text(L10n.t("实际采用：" + overlay.sourceSummary))
                        .font(.system(size: 11))
                    Text(overlay.displayName)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(L10n.t("隔离保存：\(CalibrationToolLauncher.previewSupportURL().path)"))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if !calibrationTool.lastAppPath.isEmpty {
                    Text(L10n.t("工具路径：\(calibrationTool.lastAppPath)"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
            HStack {
                Button(L10n.t("打开模型校准工具…")) {
                    calibrationTool.launchStandaloneCalibrator()
                    message = calibrationTool.statusMessage
                }
                .buttonStyle(.borderedProminent)
                Button(L10n.t("导入已有模型包…")) {
                    importPack()
                }
                Button(L10n.t("重新读回")) {
                    store.reloadAdoptedOverlayFromDisk()
                    message = store.saveMessage.isEmpty ? "已尝试从隔离目录读回。" : store.saveMessage
                }
                Spacer()
            }
            Text(L10n.t("仅添加模型、导入其他机型的包或套用布局，不会自动升级为「本机型已精确校准」或「机型已精确校准」。插拔「检测到唯一变化」仍在 B.1 工具中完成，需实机验收。"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let overlay = store.adoptedOverlay, !overlay.layout.slots.isEmpty {
                Text(L10n.t("已读回的槽位")).font(.system(size: 12, weight: .medium))
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(overlay.layout.slots, id: \.slot) { slot in
                            Text(L10n.t("\(slot.displayLabel) · \(slot.slot) · \(slot.binding)"))
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            Text(displayMessage).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(8)
        .onAppear {
            store.reloadAdoptedOverlayFromDisk()
        }
    }

    private var displayMessage: String {
        let tool = calibrationTool.statusMessage
        if !message.isEmpty { return message }
        if !tool.isEmpty { return tool }
        return " "
    }

    private func importPack() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip, .json]
        panel.message = "选择 Hardware Preview 模型包（report.json ZIP）。不会写入日常校准库。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try store.importModelPack(from: url)
            store.applyImportedLayout()
            message = store.saveMessage
        } catch {
            message = "导入失败：\(error.localizedDescription)"
        }
    }
}

struct PortCalibrationView: View {
    @EnvironmentObject private var store: CalibrationStore
    @State private var draft: [PortCalibrationEntry] = []
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("端口校准")).font(.system(size: 15, weight: .semibold))
            Text(L10n.t("校准物理位置、PortNumber/RID、USB location。与模型校准分开保存；不替代模型校准。"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach($draft) { $row in
                        HStack(spacing: 8) {
                            TextField(L10n.t("端口 ID"), text: $row.physicalPort).frame(width: 100)
                            VStack(alignment: .leading, spacing: 2) {
                                TextField(L10n.t("显示名"), text: $row.label)
                                Text(L10n.portLocation(side: row.side, location: row.location))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 150)
                            TextField(L10n.t("方向"), text: $row.side).frame(width: 70)
                            TextField("location", text: $row.location).frame(width: 110)
                            TextField("RID", text: $row.rid).frame(width: 60)
                            Button(role: .destructive) {
                                draft.removeAll { $0.id == row.id }
                            } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            HStack {
                Button(L10n.t("添加端口")) {
                    draft.append(.init(physicalPort: "new", location: "", label: "新端口", rid: "", side: "左侧"))
                }
                Spacer()
                Button(L10n.t("重新载入")) { store.reload(); draft = store.ports; message = store.saveMessage }
                Button(L10n.t("保存端口校准")) {
                    store.ports = draft; store.save(); message = store.saveMessage
                }
                .buttonStyle(.borderedProminent)
            }
            Text(message.isEmpty ? " " : L10n.t(message)).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(8)
        .onAppear { draft = store.ports }
    }
}

struct LocationMapView: View {
    @EnvironmentObject private var store: CalibrationStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("接口位置图")).font(.system(size: 15, weight: .semibold))
            Text(L10n.t("只读展示校准后的主机端口位置；编辑入口在“端口校准”，模型关联在“模型校准”。"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 28) {
                ForEach(["左侧", "右侧"], id: \.self) { side in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.t(side)).font(.system(size: 12, weight: .medium))
                        ForEach(store.ports.filter { $0.side == side }) { port in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.accentColor.opacity(0.18))
                                    .frame(width: 80, height: 26)
                                    .overlay(Text(port.label).font(.system(size: 10)))
                                Text("RID \(port.rid.isEmpty ? "—" : port.rid) · \(port.location)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            Spacer()
        }
        .padding(8)
    }
}

struct HelperEnvironmentView: View {
    @EnvironmentObject private var device: DeviceControlModel
    @EnvironmentObject private var helperEnvironment: HelperEnvironmentModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.t("Helper / 运行环境")).font(.system(size: 15, weight: .semibold))
                HStack {
                    Circle().fill(color)
                        .frame(width: 8, height: 8)
                    Text(L10n.t(HelperRuntimePresentation.callStatusText(
                        authenticatedCallAvailable: device.helperAvailable,
                        callReason: device.helperStatusText)))
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    if helperEnvironment.snapshot.allowedActions.contains(.redetect) {
                        Button(L10n.t("重新检测")) {
                            helperEnvironment.redetect()
                            Task { await device.refreshHelper() }
                        }
                    }
                }
                Text(L10n.t("安装与服务检测：\(helperEnvironment.snapshot.statusLine)"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                ForEach(helperEnvironment.snapshot.detailLines, id: \.self) { line in
                    Text(L10n.t(line)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if let error = helperEnvironment.snapshot.detectionError {
                    Text(L10n.t(error)).font(.system(size: 11)).foregroundStyle(.orange)
                }
                Text(L10n.t("这些检查只用于展示和管理入口，不会作为发送 DFU / 重启的新门槛。基线已有的 Helper 连接方式保持不变。"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if !device.mappingNote.isEmpty {
                    Text(L10n.t(device.mappingNote))
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                managementButtons
                if !helperEnvironment.managementMessage.isEmpty {
                    Text(L10n.t(helperEnvironment.managementMessage))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .onAppear { helperEnvironment.redetect() }
    }

    private var color: Color {
        switch HelperRuntimePresentation.homeColor(
            snapshot: helperEnvironment.snapshot,
            authenticatedCallAvailable: device.helperAvailable) {
        case "green": return .green
        case "orange": return .orange
        case "yellow": return .yellow
        case "red": return .red
        default: return .secondary
        }
    }

    @ViewBuilder
    private var managementButtons: some View {
        let primary = HelperManagementPresentation.primaryActions(from: helperEnvironment.snapshot.allowedActions)
        let secondary = HelperManagementPresentation.secondaryActions(from: helperEnvironment.snapshot.allowedActions)
        VStack(alignment: .leading, spacing: 8) {
            if !primary.isEmpty {
                HStack {
                    ForEach(primary, id: \.self) { action in
                        Button(L10n.t(title(for: action))) {
                            // One click: the macOS administrator prompt is the authorization.
                            helperEnvironment.perform(action, quarantineConfirmed: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(helperEnvironment.isBusy)
                    }
                }
            }
            if !secondary.isEmpty {
                DisclosureGroup(L10n.t("其他管理…")) {
                    HStack {
                        ForEach(secondary, id: \.self) { action in
                            Button(L10n.t(title(for: action))) {
                                helperEnvironment.perform(action, quarantineConfirmed: true)
                            }
                            .buttonStyle(.borderless)
                            .disabled(helperEnvironment.isBusy)
                        }
                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func title(for action: HelperManagementAction) -> String {
        switch action {
        case .install: return "安装 Helper"
        case .repair: return "修复 Helper"
        case .upgrade: return "升级 Helper"
        case .uninstall: return "卸载 Helper…"
        case .redetect: return "重新检测"
        }
    }
}

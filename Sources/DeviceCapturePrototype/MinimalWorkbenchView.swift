import Combine
import SwiftUI

struct MinimalWorkbenchView: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var calibration: CalibrationStore
    @EnvironmentObject private var device: DeviceControlModel
    @EnvironmentObject private var capture: CaptureModel
    @EnvironmentObject private var restore: RestoreWorkspaceModel
    @EnvironmentObject private var previewSettings: LogPreviewSettings
    @EnvironmentObject private var helperEnvironment: HelperEnvironmentModel
    @EnvironmentObject private var appearance: WorkbenchAppearancePreferences

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ObservedObject var panorama: PanoramaViewModel
    @ObservedObject var observation: PortDeviceWorkspaceModel
    @ObservedObject var configuratorReset: ConfiguratorResetModel
    @Binding var workspaceTab: PrimaryWorkspaceTab
    @Binding var showSettings: Bool
    @Binding var settingsTab: SettingsTab

    @State private var showConfiguratorStorage = false
    @StateObject private var navigation = WorkbenchNavigationState()
    @State private var autoNavigationPaused = false
    @State private var autoNavigation = DFUAutoNavigationCoordinator()
    @State private var contextCue: DFUAutomaticCue?
    @State private var restoreNavigationPortID: String?
    @State private var toastText: String?
    @State private var toastToken = UUID()

    private var palette: WorkbenchPalette {
        appearance.visualStyle.palette(for: colorScheme)
    }

    /// UI-1：`.precision` 使用锁定的 V2 提议 Token；其余外观样式映射其 palette。
    private var visual: MRAVisualTokens {
        MRAVisualTokens.resolve(
            style: appearance.visualStyle,
            scheme: colorScheme,
            palette: palette)
    }

    private var reduceMotion: Bool {
        systemReduceMotion
            || appearance.motionStrength < 0.05
            || ProcessInfo.processInfo.environment[
                "MRA_UI_FORCE_REDUCE_MOTION"]
                == "1"
    }

    private var reduceTransparency: Bool {
        systemReduceTransparency
            || ProcessInfo.processInfo.environment[
                "MRA_UI_FORCE_REDUCE_TRANSPARENCY"]
                == "1"
    }

    private var increaseContrast: Bool {
        contrast == .increased
            || ProcessInfo.processInfo.environment[
                "MRA_UI_FORCE_INCREASE_CONTRAST"]
                == "1"
    }

    private var tokens: WorkbenchMotionTokens {
        .make(
            motionStrength: appearance.motionStrength,
            floatingDepth: appearance.floatingDepth,
            reduceMotion: reduceMotion
        )
    }

    private var sceneIsActive: Bool {
        controlActiveState == .key
    }

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                topBar

                Rectangle()
                    .fill(
                        increaseContrast
                            ? visual.hairlineStrong
                            : visual.hairline
                    )
                    .frame(height: visual.dividerThickness)

                GeometryReader { proxy in
                    let compact = proxy.size.width < 1_020
                    HStack(spacing: 0) {
                        MinimalControlSidebar(
                            panorama: panorama,
                            compact: compact,
                            palette: palette,
                            visual: visual,
                            tokens: tokens,
                            reduceTransparency: reduceTransparency,
                            increaseContrast: increaseContrast,
                            reduceMotion: reduceMotion,
                            parallaxEnabled: appearance.parallaxEnabled,
                            advanced3DEnabled: appearance.advanced3DEnabled,
                            glassStrength: appearance.glassStrength,
                            edgeGlowStrength: appearance.edgeGlowStrength,
                            performDFU: armAndPerformDFU,
                            performReboot: device.performReboot,
                            performRecovery: device.performRecoveryMode,
                            controlTargetSuffix: controlTargetSuffix,
                            activeRestoreNote: activeRestoreNote,
                            onSelectPort: { port in
                                device.selectPort(port)
                                // 点击左侧端口 = 跟随左侧：清掉显式查看绑定，
                                // 否则旧 viewedPortKey 会在后续切换时压住新选中端口。
                                navigation.clearTaskView()
                                observation.followLeftControl()
                                navigation.viewPort(nil)
                            },
                            openHelperSettings: {
                                settingsTab = .helper
                                showSettings = true
                            },
                            openCalibrationSettings: {
                                settingsTab = .port
                                showSettings = true
                            }
                        )
                        .frame(width: compact
                            ? visual.sidebarWidthCompact
                            : visual.sidebarWidthRegular)

                        Rectangle()
                            .fill(
                                increaseContrast
                                    ? visual.hairlineStrong
                                    : visual.hairline
                            )
                            .frame(width: visual.dividerThickness)

                        workspaces(
                            compact: compact,
                            palette: palette,
                            visual: visual,
                            tokens: tokens,
                            reduceTransparency: reduceTransparency,
                            increaseContrast: increaseContrast,
                            reduceMotion: reduceMotion
                        )
                    }
                }
            }

            if let toastText {
                VStack {
                    Spacer()
                    WorkbenchToast(
                        text: toastText,
                        palette: palette,
                        visual: visual,
                        reduceTransparency: reduceTransparency,
                        increaseContrast: increaseContrast
                    )
                }
                .padding(.bottom, 18)
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .sheet(isPresented: $showConfiguratorStorage) {
            ConfiguratorStorageReadOnlyView(model: configuratorReset)
                .environmentObject(language)
                .environment(\.locale, language.locale)
                .frame(minWidth: 780, minHeight: 600)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .mraDFUConfirmationProjected
            ).compactMap { $0.object as? DFUConfirmationProjection }
        ) { event in
            handleDFUConfirmation(event)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : tokens.workspaceAnimation,
            value: workspaceTab
        )
        .animation(
            reduceMotion ? .easeOut(duration: 0.10) : .easeOut(duration: 0.16),
            value: toastText
        )
        .animation(
            reduceMotion ? .easeOut(duration: 0.10) : .easeOut(duration: 0.16),
            value: contextCue
        )
    }

    @ViewBuilder
    private var backdrop: some View {
        if appearance.visualStyle == .precision {
            // V2 基线：单一画布底色，无材质叠层、无呼吸/粒子层。
            visual.canvasPrimary.ignoresSafeArea()
        } else {
            WorkbenchBackdrop(
                palette: palette,
                style: appearance.visualStyle,
                preferences: appearance,
                reduceMotion: reduceMotion,
                reduceTransparency: reduceTransparency,
                active: sceneIsActive
            )
        }
    }

    private var topBar: some View {
        GeometryReader { proxy in
            topBarContent(width: proxy.size.width)
        }
        .frame(height: 52)
        .background(visual.canvasPrimary)
    }

    private func topBarContent(width: CGFloat) -> some View {
        // 920pt 是最窄窗口：标题收窄、头部按钮图标化、药丸使用紧凑文案；
        // 三主模块与两个头部按钮必须完整可见（见 920×680 GUI 取证）。
        let narrow = width < 1_140
        let compactPills = width < 1_000
        let pickerMaxWidth: CGFloat = width < 1_000
            ? 292
            : (narrow ? 320 : 390)
        return HStack(spacing: narrow ? 8 : 14) {
            appIdentity(compact: narrow)
                .frame(
                    minWidth: narrow ? 188 : 210,
                    idealWidth: narrow ? 188 : 255,
                    maxWidth: 300,
                    alignment: .leading
                )

            Spacer(minLength: 4)

            workspacePicker
                .frame(maxWidth: pickerMaxWidth)

            Spacer(minLength: 4)

            portStatusPills(compact: compactPills)

            headerActions(compact: narrow)
        }
        .padding(.horizontal, narrow ? 12 : 14)
        .frame(width: width, height: 52)
    }

    private func appIdentity(compact: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(visual.accentPrimary)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Text(language.appDisplayName)
                        .font(MRAFont.title(13))
                        .foregroundStyle(visual.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    if UIFixture.isActive {
                        Text(L10n.t("模拟环境"))
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(visual.stateDFU)
                            .padding(.horizontal, 6)
                            .frame(height: 17)
                            .background(
                                visual.stateDFU.opacity(0.12),
                                in: Capsule()
                            )
                    }
                }
                if !compact {
                    Text(L10n.t("专业 Mac 设备控制、USB-C 证据与 Restore 工作台"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(visual.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func headerActions(compact: Bool) -> some View {
        HStack(spacing: 7) {
            Button {
                showConfiguratorStorage = true
            } label: {
                Group {
                    if compact {
                        Image(systemName: "externaldrive")
                    } else {
                        Label(L10n.t("Configurator 存储"), systemImage: "externaldrive")
                    }
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n.t(
                "只读盘点 Configurator 存储；不提供未授权清理"))
            .accessibilityLabel(Text(L10n.t("Configurator 存储")))

            Button {
                showSettings = true
            } label: {
                Group {
                    if compact {
                        Image(systemName: "gearshape")
                    } else {
                        Label(L10n.t("设置"), systemImage: "gearshape")
                    }
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n.t("设置"))
            .accessibilityLabel(L10n.t("设置"))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - S3 / S4 / S5 顶部状态药丸

    @ViewBuilder
    private func portStatusPills(compact: Bool) -> some View {
        let pills = HStack(spacing: compact ? 4 : 6) {
            ForEach(device.orderedDisplayPorts) { port in
                portStatusPill(port, compact: compact)
            }
        }
        if device.orderedDisplayPorts.count > 3 {
            // 非本项目三端口主机：仍展示全部真实端口，不允许静默丢端口。
            ScrollView(.horizontal, showsIndicators: false) {
                pills
            }
            .frame(maxWidth: 300)
        } else {
            pills.fixedSize(horizontal: true, vertical: false)
        }
    }

    private func portStatusPill(_ port: LiveHostPort, compact: Bool) -> some View {
        let info = portPillInfo(port)
        let selected = viewedPillPortKey == port.id
        let text = compact
            ? "\(info.slot)·\(info.stateText)"
            : "\(info.slot) · \(info.stateText)"
        // 紧凑态下限：11pt Mono、5px 状态点、22pt 高、6pt 内边距、54pt 最小宽。
        return Button {
            viewPortFromStatusPill(port)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(info.tone)
                    .frame(width: 5, height: 5)
                Text(text)
                    .font(MRAFont.mono(MRAFont.monoSmallSize))
                    .foregroundStyle(
                        selected ? visual.textPrimary : visual.textSecondary
                    )
                    .lineLimit(1)
            }
            .padding(.horizontal, compact ? 6 : 8)
            .frame(minWidth: 54, minHeight: 22)
            .background(
                selected
                    ? info.tone.opacity(0.14)
                    : visual.surfaceSubtle,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(
                        selected
                            ? info.tone.opacity(0.42)
                            : visual.hairline,
                        lineWidth: 1
                    )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workbench-port-pill-\(port.id)")
        .accessibilityLabel("\(info.slot) \(info.name)：\(info.stateText)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(L10n.t(
            "仅切换右侧查看目标；不改变左侧物理控制目标与 Restore 锁定目标"))
    }

    private var viewedPillPortKey: String {
        navigation.viewedPortKey ?? device.selectedLiveKey
    }

    private func portPillInfo(_ port: LiveHostPort) -> MRAPillInfo {
        let name = L10n.localizedPortName(device.label(for: port))
        let slot = device.uniquelyMappedBuiltInSlot(for: port)?.slot
            ?? fallbackSlotLabel(port)
        if let task = restoreTask(on: port) {
            let fraction = RestoreStageProgressPresentation(task: task)
                .stageFraction
            let percent = fraction.map { Int(($0 * 100).rounded()) }
            return MRAPillInfo(
                slot: slot,
                name: name,
                stateText: percent.map { "Restore \($0)%" }
                    ?? L10n.t("执行中"),
                tone: visual.telemetryCyan
            )
        }
        switch device.observedDevice(for: port)?.mode {
        case .dfu:
            return MRAPillInfo(
                slot: slot, name: name,
                stateText: "DFU", tone: visual.stateDFU)
        case .recovery:
            return MRAPillInfo(
                slot: slot, name: name,
                stateText: L10n.t("恢复模式"), tone: visual.accentPrimary)
        case .connected:
            return MRAPillInfo(
                slot: slot, name: name,
                stateText: L10n.t("正常"), tone: visual.stateSuccess)
        case .unknown:
            return MRAPillInfo(
                slot: slot, name: name,
                stateText: L10n.t("未知"), tone: visual.stateNeutral)
        case .none:
            return MRAPillInfo(
                slot: slot, name: name,
                stateText: L10n.t("空闲"), tone: visual.stateNeutral)
        }
    }

    /// 未校准兜底：只使用真实 `PortNumber`，不硬编码 S3/S4/S5，也不假定端口数量。
    private func fallbackSlotLabel(_ port: LiveHostPort) -> String {
        "P\(port.portNumber)"
    }

    /// 仅匹配既有 Restore 任务；不读取/不修改任何 Restore 状态。
    private func restoreTask(on port: LiveHostPort) -> RestoreTaskSnapshot? {
        let candidates = [restore.currentTask, restore.secondaryTask]
            .compactMap { $0 }
        return candidates.first { task in
            task.outcome == nil
                && (task.target.portKey == port.id
                    || task.target.portDisplayName == device.label(for: port))
        }
    }

    /// 三域隔离：只移动右侧“查看目标”。
    /// 不调用 `device.selectPort`、不触碰 `restore`、不改变物理控制目标或
    /// 正在运行的 Restore 冻结目标。
    private func viewPortFromStatusPill(_ port: LiveHostPort) {
        observation.setFixedObservationPort(port.id)
        navigation.viewPort(port.id)
        autoNavigationPaused = true
        contextCue = nil
    }

    private var workspacePicker: some View {
        Picker(
            "",
            selection: Binding(
                get: { workspaceTab },
                set: { newValue in
                    if newValue != workspaceTab {
                        autoNavigationPaused = true
                        contextCue = nil
                    }
                    workspaceTab = newValue
                }
            )
        ) {
            ForEach(PrimaryWorkspaceTab.allCases) { tab in
                Text(L10n.t(tab.title)).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .id(language.resolvedCode)
        .frame(minWidth: 292, idealWidth: 352, maxWidth: 390)
        .accessibilityIdentifier("workbench-workspace-picker")
    }

    @ViewBuilder
    private func workspaces(
        compact: Bool,
        palette: WorkbenchPalette,
        visual: MRAVisualTokens,
        tokens: WorkbenchMotionTokens,
        reduceTransparency: Bool,
        increaseContrast: Bool,
        reduceMotion: Bool
    ) -> some View {
        let stage = MinimalWorkspaceStage(
            panorama: panorama,
            observation: observation,
            activeTab: $workspaceTab,
            compact: compact,
            appearance: appearance,
            palette: palette,
            visual: visual,
            tokens: tokens,
            reduceTransparency: reduceTransparency,
            increaseContrast: increaseContrast,
            reduceMotion: reduceMotion,
            autoNavigationPaused: $autoNavigationPaused,
            contextCue: $contextCue,
            restoreNavigationPortID: $restoreNavigationPortID,
            navigation: navigation,
            navigateToRestore: { portID in
                navigateToRestore(portID: portID)
            }
        )
        .environmentObject(device)
        .environmentObject(restore)
        .environmentObject(capture)

        let overview = RestoreTaskOverviewView(
            restore: restore,
            navigation: navigation,
            palette: palette,
            increaseContrast: increaseContrast,
            onOpenTask: { _ in
                autoNavigationPaused = true
                contextCue = nil
                workspaceTab = .restore
            }
        )

        VStack(spacing: 0) {
            // UI-3.1：无活动任务时不再占用顶部空间；仅运行/启动中有总览。
            if restore.isRestoreTaskActive {
                overview
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                Rectangle()
                    .fill(
                        increaseContrast
                            ? visual.hairlineStrong
                            : visual.hairline
                    )
                    .frame(height: visual.dividerThickness)
            }

            if reduceMotion {
                stage
            } else {
                stage.transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.997)),
                        removal: .opacity
                    )
                )
            }
        }
    }

    private func armAndPerformDFU() {
        guard !device.selectedLiveKey.isEmpty else {
            device.performDFU()
            return
        }

        let selectedPortID = device.selectedLiveKey
        autoNavigation.arm(portID: selectedPortID)
        device.performDFU()
    }

    private func handleDFUConfirmation(
        _ event: DFUConfirmationProjection
    ) {
        let navigationContext = WorkbenchNavigationContext(
            isDeviceWorkspace: workspaceTab == .device,
            restoreTaskActive: restore.isRestoreTaskActive,
            settingsPresented: showSettings,
            configuratorPresented: showConfiguratorStorage,
            followsControlPort: observation.followsLeftControl,
            restorePreparationActive:
                restore.hasUserRestorePreparationContext)
        let decision = autoNavigation.evaluate(
            event,
            currentControlPortID: device.selectedLiveKey,
            autoNavigationPaused: autoNavigationPaused,
            importantContextActive: navigationContext.isImportant
        )

        switch decision {
        case .none:
            return
        case .cue(let portID, _):
            let portName = device.orderedDisplayPorts
                .first(where: { $0.id == portID })
                .map { L10n.localizedPortName(device.label(for: $0)) }
                ?? "当前操作接口"
            contextCue = DFUAutomaticCue(
                portID: portID,
                message: confirmationMessage(
                    portName: portName,
                    scope: event.scope)
            )
        case .navigate(let portID, _):
            let portName = device.orderedDisplayPorts
                .first(where: { $0.id == portID })
                .map { L10n.localizedPortName(device.label(for: $0)) }
                ?? "当前操作接口"
            navigateToRestore(
                portID: portID,
                confirmation: confirmationMessage(
                    portName: portName,
                    scope: event.scope))
        }
    }

    private var controlTargetSuffix: String {
        guard let port = device.selectedLivePort else { return "" }
        return " · " + L10n.localizedPortName(device.label(for: port))
    }

    /// 纯展示风险说明：不新增任何发送门禁（具名确认方案 B 未接入）。
    private var activeRestoreNote: String? {
        guard let task = restore.currentTask else { return nil }
        let port = task.target.portDisplayName
        return "「\(port)」有 Restore 在执行；物理控制可能中断写入，操作前请核对端口与设备。"
    }

    private func navigateToRestore(
        portID: String,
        confirmation: String? = nil
    ) {
        restoreNavigationPortID = portID
        workspaceTab = .restore
        contextCue = nil
        showToast(
            confirmation.map { "\($0)，已定位到固件与恢复" }
                ?? "已定位到固件与恢复"
        )
    }

    private func confirmationMessage(
        portName: String,
        scope: DFUConfirmationScope
    ) -> String {
        switch scope {
        case .sameDevice:
            return "\(portName) 已确认进入 DFU · 同一设备"
        case .portTransition:
            return "\(portName) 已确认出现 DFU · 物理端口归属已确认"
        case .none:
            return "\(portName) 已确认出现 DFU"
        }
    }

    private func showToast(_ text: String) {
        let token = UUID()
        toastToken = token
        toastText = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.8) {
            guard toastToken == token else { return }
            toastText = nil
        }
    }
}

private struct DFUAutomaticCue: Equatable {
    let portID: String
    let message: String
}

private struct MinimalControlSidebar: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var device: DeviceControlModel
    @EnvironmentObject private var helperEnvironment: HelperEnvironmentModel
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ObservedObject var panorama: PanoramaViewModel

    let compact: Bool
    let palette: WorkbenchPalette
    let visual: MRAVisualTokens
    let tokens: WorkbenchMotionTokens
    let reduceTransparency: Bool
    let increaseContrast: Bool
    let reduceMotion: Bool
    let parallaxEnabled: Bool
    let advanced3DEnabled: Bool
    let glassStrength: Double
    let edgeGlowStrength: Double
    let performDFU: () -> Void
    let performReboot: () -> Void
    let performRecovery: () -> Void
    let controlTargetSuffix: String
    let activeRestoreNote: String?
    let onSelectPort: (LiveHostPort) -> Void
    let openHelperSettings: () -> Void
    let openCalibrationSettings: () -> Void

    @State private var feedbackDetailsPresented = false

    var body: some View {
        VStack(spacing: 0) {
            portListSection
            railDivider
            telemetrySection
            railDivider
            controlSection
            Spacer(minLength: 8)
            railDivider
            statusLampSection
        }
        .background(visual.sidebarBackground)
    }

    private var portListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeading(
                "物理端口",
                detail: L10n.ports(device.orderedDisplayPorts.count)
            )

            if device.orderedDisplayPorts.isEmpty {
                Text(L10n.t("未识别到主机 AppleHPM 端口"))
                    .font(MRAFont.body(MRAFont.labelSize))
                    .foregroundStyle(visual.textSecondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(device.orderedDisplayPorts) { port in
                            minimalPortRow(port)
                        }
                    }
                }
                .frame(
                    height: min(
                        190,
                        CGFloat(device.orderedDisplayPorts.count) * 46
                    )
                )
                .scrollIndicators(.automatic)
            }
        }
        .padding(.horizontal, visual.railHorizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 9)
    }

    /// 只读遥测：仅展示现有数据源真实提供的字段；缺值明确显示 `未获取`，
    /// 不为尚未接入的字段创建空白区域。
    private var telemetrySection: some View {
        let port = device.selectedLivePort
        let observed = port.flatMap { device.observedDevice(for: $0) }
        return VStack(alignment: .leading, spacing: 7) {
            sectionHeading("端口遥测", detail: L10n.t("只读"))
            VStack(spacing: 0) {
                telemetryRow(
                    "PortNumber",
                    port.map { "\($0.portNumber)" }
                )
                telemetryRow("RID", port.map { "\($0.rid)" })
                telemetryRow(
                    "ECID",
                    observed?.ecid,
                    emphasized: true
                )
                telemetryRow(
                    L10n.t("端口校准"),
                    port.map { detailCalibrationText(for: $0) }
                )
            }
        }
        .padding(.horizontal, visual.railHorizontalPadding)
        .padding(.vertical, 9)
    }

    private var controlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeading("快捷控制", detail: currentPortName)

            MRASidebarActionButton(
                title: L10n.t("进入 DFU") + controlTargetSuffix,
                symbol: "bolt.shield",
                role: .primary,
                enabled: device.canControl,
                busy: device.actionInFlight
                    && device.activeAction == "进入 DFU",
                visual: visual,
                tokens: tokens,
                reduceTransparency: reduceTransparency,
                increaseContrast: increaseContrast,
                action: performDFU
            )
            .accessibilityIdentifier("workbench-enter-dfu")

            HStack(spacing: 8) {
                MRASidebarActionButton(
                    title: L10n.t("重启设备"),
                    symbol: "restart",
                    role: .secondary,
                    enabled: device.canControl,
                    busy: device.actionInFlight
                        && device.activeAction == "重启",
                    visual: visual,
                    tokens: tokens,
                    reduceTransparency: reduceTransparency,
                    increaseContrast: increaseContrast,
                    action: performReboot
                )
                .accessibilityLabel(Text(L10n.t("重启设备") + controlTargetSuffix))
                .help(L10n.t("重启设备") + controlTargetSuffix)
                .accessibilityIdentifier("workbench-reboot")

                MRASidebarActionButton(
                    title: L10n.t("恢复模式"),
                    symbol: "arrow.counterclockwise",
                    role: .secondary,
                    enabled: device.canControl
                        && !device.bootOptionsTestActive,
                    busy: device.actionInFlight
                        && device.activeAction == "恢复模式",
                    visual: visual,
                    tokens: tokens,
                    reduceTransparency: reduceTransparency,
                    increaseContrast: increaseContrast,
                    action: performRecovery
                )
                .accessibilityLabel(Text(L10n.t("进入恢复模式") + controlTargetSuffix))
                .help(L10n.t("进入恢复模式") + controlTargetSuffix)
                .accessibilityIdentifier("workbench-enter-recovery")
            }

            executionFeedback

            if let activeRestoreNote {
                Text(activeRestoreNote)
                    .font(.system(size: 10.5))
                    .foregroundStyle(visual.stateDFU)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(
                        "workbench-active-restore-risk-note")
            }
        }
        .padding(.horizontal, visual.railHorizontalPadding)
        .padding(.top, 10)
    }

    private var statusLampSection: some View {
        HStack(spacing: 7) {
            MRASidebarLamp(
                title: "Helper",
                state: helperStateText,
                tone: helperStateTone,
                detail: helperDetail,
                visual: visual,
                action: openHelperSettings
            )

            MRASidebarLamp(
                title: L10n.t("主机校准"),
                state: L10n.t(device.hostCalibrationLampState.text),
                tone: calibrationStateTone,
                detail: device.hostCalibrationLampHelp,
                visual: visual,
                action: openCalibrationSettings
            )
        }
        .padding(.horizontal, visual.railHorizontalPadding)
        .padding(.vertical, 9)
        .accessibilityIdentifier("workbench-status-lamps")
    }

    private var railDivider: some View {
        Rectangle()
            .fill(
                increaseContrast
                    ? visual.hairlineStrong
                    : visual.hairline
            )
            .frame(height: visual.dividerThickness)
    }

    private var currentPortName: String {
        device.selectedLivePort.map {
            L10n.localizedPortName(device.label(for: $0))
        }
            ?? L10n.t("未选择")
    }

    private var helperStateText: String {
        if device.helperAvailable {
            return L10n.t("已授权")
        }
        switch helperEnvironment.snapshot.kind {
        case .notInstalled:
            return L10n.t("未安装")
        case .currentHealthy, .currentUnhealthy, .knownLegacy,
             .backendNeedsUpdate, .mixedKnown:
            return L10n.t("未授权")
        case .unknown:
            return L10n.t("未知")
        case .detectFailed:
            return L10n.t("检测失败")
        }
    }

    private var helperDetail: String {
        L10n.t(device.helperStatusText)
    }

    private var helperStateTone: WorkbenchStatusTone {
        switch HelperRuntimePresentation.homeColor(
            snapshot: helperEnvironment.snapshot,
            authenticatedCallAvailable: device.helperAvailable
        ) {
        case "green": return .positive
        case "orange", "yellow": return .caution
        case "red": return .negative
        default: return .neutral
        }
    }

    private var calibrationStateTone: WorkbenchStatusTone {
        switch device.hostCalibrationLampState.color {
        case "green": return .positive
        case "orange": return .caution
        default: return .neutral
        }
    }

    private func sectionHeading(_ title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(L10n.t(title))
                .font(MRAFont.label(MRAFont.labelSize))
                .tracking(0.35)
                .foregroundStyle(visual.textSecondary)
            Spacer(minLength: 4)
            if let detail {
                Text(detail)
                    .font(MRAFont.label(10))
                    .foregroundStyle(visual.textTertiary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func minimalPortRow(_ port: LiveHostPort) -> some View {
        let selected = device.selectedLiveKey == port.id
        let projection = panorama.mainPortProjection(for: port)
        let presentation = MRAPortPresentation(
            device: device,
            port: port,
            projection: projection
        )
        return MinimalPortRowView(
            presentation: presentation,
            selected: selected,
            enabled: device.canChangePortSelection,
            highlighted: device.brieflyHighlightedPortKeys.contains(port.id),
            visual: visual,
            tokens: tokens,
            increaseContrast: increaseContrast,
            reduceMotion: reduceMotion,
            parallaxEnabled: parallaxEnabled,
            advanced3DEnabled: advanced3DEnabled,
            edgeGlowStrength: edgeGlowStrength,
            action: { onSelectPort(port) }
        )
        .accessibilityIdentifier("workbench-port-\(port.id)")
    }

    private func telemetryRow(
        _ label: String,
        _ rawValue: String?,
        emphasized: Bool = false
    ) -> some View {
        let trimmed = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let missing = trimmed.isEmpty
        let value = missing ? L10n.t("未获取") : trimmed
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(MRAFont.label(10.5))
                .foregroundStyle(visual.textTertiary)
                .frame(width: 66, alignment: .leading)
                .lineLimit(1)
            Text(value)
                .font(MRAFont.mono(MRAFont.monoSmallSize))
                .foregroundStyle(
                    missing
                        ? visual.textTertiary
                        : (emphasized
                            ? visual.textPrimary
                            : visual.textSecondary)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 21)
        .accessibilityElement(children: .combine)
    }

    private func detailCalibrationText(for port: LiveHostPort) -> String {
        if let entry = device.selectedCalibration {
            return "\(entry.physicalPort) · \(entry.controller ?? port.controller)"
        }
        if let built = device.uniquelyMappedBuiltInSlot(for: port) {
            return "\(built.slot) · \(L10n.localizedPortName(built.displayLabel))"
        }
        return device.builtInSlotSummary
    }

    private var executionFeedback: some View {
        HStack(spacing: 6) {
            Image(systemName: feedbackSymbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(feedbackTone)
            Text(L10n.t(device.feedback.title))
                .font(MRAFont.label(MRAFont.labelSize))
                .foregroundStyle(visual.textSecondary)
                .lineLimit(1)
            Text(L10n.t(device.feedback.detail))
                .font(MRAFont.label(11))
                .foregroundStyle(visual.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 2)
            if !device.lastActionLog.isEmpty
                || !device.feedback.detail.isEmpty {
                Button(L10n.t("详情")) {
                    feedbackDetailsPresented.toggle()
                }
                .buttonStyle(.link)
                .font(.system(size: 10.5, weight: .medium))
                .popover(
                    isPresented: $feedbackDetailsPresented,
                    arrowEdge: .bottom
                ) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(L10n.t(device.feedback.title))
                                .font(.system(size: 11.5, weight: .semibold))
                            if !device.feedback.detail.isEmpty {
                                Text(L10n.t(device.feedback.detail))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            if !device.lastActionLog.isEmpty {
                                Divider()
                                Text(device.lastActionLog)
                                    .font(.system(size: 10, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    .frame(minWidth: 430, minHeight: 160, maxHeight: 330)
                }
            }
        }
        .padding(.horizontal, 3)
        .frame(minHeight: 23)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(device.feedback.title)，\(device.feedback.detail)"
        )
    }

    private var feedbackTone: Color {
        switch device.feedback.tone {
        case .neutral: return visual.textTertiary
        case .working: return visual.accentPrimary
        case .success: return visual.stateSuccess
        case .warning, .failure: return visual.stateDFU
        }
    }

    private var feedbackSymbol: String {
        switch device.feedback.tone {
        case .neutral: return "circle"
        case .working: return "hourglass"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.octagon.fill"
        }
    }
}

/// UI-1 纯展示：物理端口在左栏的四种真实状态。
private enum MRAPortState {
    case dfu
    case recovery
    case normal
    case unknownMode
    case noDevice

    init(observed: ObservedDevice?) {
        switch observed?.mode {
        case .dfu: self = .dfu
        case .recovery: self = .recovery
        case .connected: self = .normal
        case .unknown: self = .unknownMode
        case .none: self = .noDevice
        }
    }

    func tone(in visual: MRAVisualTokens) -> Color {
        switch self {
        case .dfu: return visual.stateDFU
        case .recovery: return visual.accentPrimary
        case .normal: return visual.stateSuccess
        case .unknownMode, .noDevice: return visual.stateNeutral
        }
    }
}

/// UI-1 纯展示：只读取既有设备观察结果的端口行文案。
@MainActor
private struct MRAPortPresentation {
    let title: String
    let detail: String
    let state: MRAPortState

    init(
        device: DeviceControlModel,
        port: LiveHostPort,
        projection: MainPortUSBProjection?
    ) {
        let name = L10n.localizedPortName(device.label(for: port))
        if let slot = device.uniquelyMappedBuiltInSlot(for: port)?.slot {
            title = "\(slot) · \(name)"
        } else {
            title = name
        }
        state = MRAPortState(observed: device.observedDevice(for: port))
        detail = L10n.t(device.compactRowStatus(
            for: port,
            sharedUSB: projection))
    }
}

/// UI-1 纯展示：顶部药丸的槽位、真实状态与颜色。
private struct MRAPillInfo {
    let slot: String
    let name: String
    let stateText: String
    let tone: Color
}

private struct MinimalPortRowView: View {
    let presentation: MRAPortPresentation
    let selected: Bool
    let enabled: Bool
    let highlighted: Bool
    let visual: MRAVisualTokens
    let tokens: WorkbenchMotionTokens
    let increaseContrast: Bool
    let reduceMotion: Bool
    let parallaxEnabled: Bool
    let advanced3DEnabled: Bool
    let edgeGlowStrength: Double
    let action: () -> Void

    @State private var hovered = false
    @State private var hoverLocation: CGPoint?
    @State private var rowSize: CGSize = .zero

    private var stateColor: Color {
        presentation.state.tone(in: visual)
    }

    private var pointerEffectsEnabled: Bool {
        !reduceMotion && (parallaxEnabled || advanced3DEnabled)
    }

    private var normalizedHoverPoint: UnitPoint? {
        guard
            pointerEffectsEnabled,
            let hoverLocation,
            rowSize.width > 0,
            rowSize.height > 0
        else {
            return nil
        }
        return UnitPoint(
            x: min(1, max(0, hoverLocation.x / rowSize.width)),
            y: min(1, max(0, hoverLocation.y / rowSize.height)))
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(selected ? visual.accentPrimary : .clear)
                    .frame(width: 2.5, height: 26)

                ZStack {
                    Circle()
                        .fill(stateColor.opacity(0.16))
                        .frame(width: 12, height: 12)
                    Circle()
                        .fill(stateColor)
                        .frame(width: 6, height: 6)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(MRAFont.title(12.5))
                        .foregroundStyle(
                            enabled
                                ? visual.textPrimary
                                : visual.textTertiary
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)

                    Text(presentation.detail)
                        .font(MRAFont.label(10.5))
                        .foregroundStyle(
                            enabled
                                ? visual.textSecondary
                                : visual.textTertiary
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 2)

                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(visual.accentPrimary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        selected
                            ? visual.surfaceSubtle
                            : (
                                hovered
                                    ? visual.textPrimary.opacity(0.035)
                                    : .clear
                            )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        selected
                            ? visual.hairlineStrong
                            : (
                                highlighted
                                    ? visual.hairline
                                    : .clear
                            ),
                        lineWidth: increaseContrast ? 1 : 1
                    )
            }
            .overlay {
                if parallaxEnabled,
                   let point = normalizedHoverPoint {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [
                                    visual.accentPrimary.opacity(
                                        increaseContrast ? 0.075 : 0.05),
                                    .clear
                                ],
                                center: point,
                                startRadius: 0,
                                endRadius: max(rowSize.width, rowSize.height) * 0.46
                            )
                        )
                        .allowsHitTesting(false)
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            rowSize = proxy.size
                        }
                        .onChange(of: proxy.size) { _, size in
                            rowSize = size
                        }
                }
            }
            .rotation3DEffect(
                .degrees(advanced3DEnabled ? hoverTiltX : 0),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.08
            )
            .rotation3DEffect(
                .degrees(advanced3DEnabled ? hoverTiltY : 0),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.08
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(WorkbenchPressButtonStyle(tokens: tokens, enabled: enabled))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.58)
        .onContinuousHover { phase in
            withAnimation(.easeOut(duration: tokens.hover)) {
                switch phase {
                case .active(let location):
                    hovered = true
                    hoverLocation = pointerEffectsEnabled ? location : nil
                case .ended:
                    hovered = false
                    hoverLocation = nil
                }
            }
        }
        .accessibilityLabel("\(presentation.title)，\(presentation.detail)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var hoverTiltX: Double {
        guard let point = normalizedHoverPoint else { return 0 }
        return (0.5 - Double(point.y)) * 1.6
    }

    private var hoverTiltY: Double {
        guard let point = normalizedHoverPoint else { return 0 }
        return (Double(point.x) - 0.5) * 1.4
    }
}

/// UI-1 左栏核心控制按钮。
///
/// 保留 `WorkbenchCoreButton` 的全部交互契约（每动作独立 busy、hover、键盘
/// 焦点环、disabled 三态、minimumScaleFactor、减少透明度/增强对比），但主按钮
/// 使用 V2 的实色 `accentPrimary`。不修改 `WorkbenchDesignSystem.swift`。
private struct MRASidebarActionButton: View {
    enum Role {
        case primary
        case secondary
    }

    let title: String
    let symbol: String
    let role: Role
    let enabled: Bool
    let busy: Bool
    let visual: MRAVisualTokens
    let tokens: WorkbenchMotionTokens
    let reduceTransparency: Bool
    let increaseContrast: Bool
    let action: () -> Void

    @State private var hovered = false
    @FocusState private var focused: Bool

    private var height: CGFloat { role == .primary ? 54 : 46 }

    private var foreground: Color {
        guard enabled else { return visual.textTertiary }
        return role == .primary ? visual.accentText : visual.textPrimary
    }

    private var background: Color {
        guard enabled else {
            return visual.surfaceSubtle.opacity(
                reduceTransparency ? 1 : 0.55)
        }
        switch role {
        case .primary:
            return hovered
                ? visual.accentPrimary.opacity(0.92)
                : visual.accentPrimary
        case .secondary:
            return hovered
                ? visual.textPrimary.opacity(0.07)
                : visual.surfaceSubtle
        }
    }

    private var border: Color {
        guard enabled else { return visual.hairline }
        if focused {
            return role == .primary
                ? visual.accentText.opacity(0.9)
                : visual.hairlineStrong
        }
        switch role {
        case .primary:
            return visual.accentPrimary
        case .secondary:
            return hovered ? visual.hairlineStrong : visual.hairline
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 15)
                } else {
                    Image(systemName: symbol)
                        .font(.system(
                            size: role == .primary ? 13 : 12,
                            weight: .semibold))
                        .frame(width: 15)
                }
                Text(title)
                    .font(.system(
                        size: role == .primary ? 13 : 11.5,
                        weight: .semibold))
                    .lineLimit(role == .primary ? 1 : 2)
                    .minimumScaleFactor(0.88)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                background,
                in: RoundedRectangle(
                    cornerRadius: role == .primary ? 10 : 8,
                    style: .continuous)
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: role == .primary ? 10 : 8,
                    style: .continuous
                )
                .strokeBorder(
                    border,
                    lineWidth: increaseContrast
                        ? 1.2
                        : (focused ? 2 : 1)
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(WorkbenchPressButtonStyle(tokens: tokens, enabled: enabled))
        .focused($focused)
        .disabled(!enabled)
        .onHover { hovering in
            var transaction = Transaction()
            transaction.animation = .easeOut(duration: tokens.hover)
            withTransaction(transaction) {
                hovered = hovering
            }
        }
        .accessibilityLabel(title)
    }
}

/// UI-1 左栏底部低调状态灯。保留可点进入设置、help 与无障碍语义。
private struct MRASidebarLamp: View {
    let title: String
    let state: String
    let tone: WorkbenchStatusTone
    let detail: String
    let visual: MRAVisualTokens
    let action: () -> Void

    @State private var hovered = false

    private var color: Color {
        switch tone {
        case .positive: return visual.stateSuccess
        case .caution: return visual.stateDFU
        case .negative: return visual.stateError
        case .neutral: return visual.stateNeutral
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                Text(L10n.t("\(title)：\(state)"))
                    .font(MRAFont.label(10.5))
                    .foregroundStyle(visual.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                hovered
                    ? color.opacity(0.08)
                    : visual.surfaceSubtle.opacity(0.55),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(visual.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hovered = hovering
            }
        }
        .help(detail)
        .accessibilityLabel(L10n.t("\(title)状态：\(state)"))
        .accessibilityHint(L10n.t(detail))
    }
}

private struct MinimalWorkspaceStage: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var device: DeviceControlModel
    @EnvironmentObject private var restore: RestoreWorkspaceModel
    @EnvironmentObject private var capture: CaptureModel
    @EnvironmentObject private var previewSettings: LogPreviewSettings

    @ObservedObject var panorama: PanoramaViewModel
    @ObservedObject var observation: PortDeviceWorkspaceModel

    @Binding var activeTab: PrimaryWorkspaceTab
    let compact: Bool
    let appearance: WorkbenchAppearancePreferences
    let palette: WorkbenchPalette
    let visual: MRAVisualTokens
    let tokens: WorkbenchMotionTokens
    let reduceTransparency: Bool
    let increaseContrast: Bool
    let reduceMotion: Bool
    @Binding var autoNavigationPaused: Bool
    @Binding var contextCue: DFUAutomaticCue?
    @Binding var restoreNavigationPortID: String?
    @ObservedObject var navigation: WorkbenchNavigationState
    let navigateToRestore: (String) -> Void

    @State private var showTreeForSimpleDensity = false

    /// P2-B：把"查看中的物理端口"映射到 Restore 目标（只读），用于第二台设备的草稿准备区。
    private var viewedRestoreTarget: RestoreTarget? {
        if let taskID = navigation.viewedTaskID,
           taskID == restore.currentTask?.id {
            return nil // 查看任务 A：主工作区恢复 A 的实时详情
        }
        let liveID = navigation.viewedPortKey
            ?? device.selectedLiveKey
        guard !liveID.isEmpty,
              let port = device.orderedDisplayPorts.first(where: { $0.id == liveID }),
              let observed = device.observedDevice(for: port),
              let portKey = device.observedPortKey(for: observed) else {
            return nil
        }
        // 端口归属必须唯一且连接代际一致；歧义时宁可不显示 B 的准备区，
        // 也不猜测设备身份（P2-B 要求 4）。
        let observedECID = observed.ecid ?? ""
        let inventory = restore.navigationTargetInventory
        let candidates = inventory.filter {
            $0.portKey == portKey
                && $0.canonicalHex.caseInsensitiveCompare(observedECID) == .orderedSame
        }
        if candidates.count == 1, let only = candidates.first {
            // 正常心跳可能刷新 connectionGeneration；查看目标仍可显示，
            // 由草稿状态机决定是否需要重新核验。ECID 必须与当前观察一致。
            return only
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader

            Rectangle()
                .fill(
                    increaseContrast
                        ? visual.hairlineStrong
                        : visual.hairline
                )
                .frame(height: visual.dividerThickness)

            if activeTab == .device {
                deviceTelemetryBar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(visual.surfaceSubtle.opacity(0.55))
                Rectangle().fill(visual.hairline).frame(height: 1)
            }

            if let contextCue {
                DFUContextCueView(
                    message: contextCue.message,
                    palette: palette,
                    visual: visual,
                    reduceTransparency: reduceTransparency,
                    increaseContrast: increaseContrast,
                    open: { navigateToRestore(contextCue.portID) },
                    dismiss: { self.contextCue = nil }
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }

            workspaceContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(visual.canvasPrimary)
    }

    private var deviceTelemetryBar: some View {
        let live = device.selectedLivePort
        let link = live?.link
        let speed = link?.dataRateDescription
            ?? link?.linkRateDescription
            ?? link?.superspeedSignaling
            ?? link?.activeTransportDetails.first?.dataRateDescription
            ?? link?.activeTransportDetails.first?.linkRateDescription
            ?? L10n.t("未获取")
        let pd: String
        if let live,
           let attribution = panorama.mainPortProjection(for: live)?.powerAttribution {
            switch attribution {
            case .unique(let contract):
                let voltage = contract.voltageMillivolts.map {
                    String(format: "%.1fV", Double($0) / 1_000)
                } ?? "?"
                let current = contract.maxCurrentMilliamps.map {
                    String(format: "%.1fA", Double($0) / 1_000)
                } ?? "?"
                pd = "\(voltage) · \(current)"
            case .conflicting:
                pd = L10n.t("归属冲突")
            case .notUSBCOwned:
                pd = L10n.t("非 USB-C")
            case .notProvided:
                pd = L10n.t("未获取")
            }
        } else {
            pd = L10n.t("未获取")
        }
        let hpm: String
        if let count = link?.overcurrentCount {
            hpm = count > 0
                ? L10n.t("异常 · 过流") + " \(count)"
                : L10n.t("正常")
        } else {
            hpm = L10n.t("未获取")
        }
        let recent = device.connectionEvents.filter {
            Date().timeIntervalSince($0.timestamp) <= 60
        }.count
        let recentTone = recent >= 3 ? visual.stateDFU : visual.textTertiary
        return HStack(spacing: 12) {
            Text("USB-C").font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(visual.textTertiary)
            Text(speed).font(MRAFont.mono(9.5))
                .foregroundStyle(visual.textSecondary).lineLimit(1)
            Text("PD").font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(visual.textTertiary)
            Text(pd).font(MRAFont.mono(9.5))
                .foregroundStyle(visual.textSecondary).lineLimit(1)
            Text("HPM").font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(visual.textTertiary)
            Text(hpm).font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(link?.overcurrentCount ?? 0 > 0
                    ? visual.stateError : visual.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(L10n.t("近 1 分钟变化") + " \(recent)")
                .font(MRAFont.mono(9.5))
                .foregroundStyle(recentTone)
                .help(L10n.t("近 1 分钟重连/掉线次数；≥3 次提示反复重启/掉盘可能"))
        }
        .accessibilityIdentifier("device-telemetry-bar")
    }

    private var workspaceHeader: some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(workspaceTitle))
                    .font(MRAFont.title(15.5))
                    .foregroundStyle(visual.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                Text(L10n.t(workspaceSubtitle))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(visual.textTertiary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            observationTargetMenu

            Button {
                observation.followLeftControl()
                navigation.viewPort(nil)
                restore.resumeAutomaticNavigationAfterUserAction()
                autoNavigationPaused = false
                contextCue = nil
            } label: {
                Group {
                    if compact {
                        Image(systemName:
                            autoNavigationPaused
                            ? "arrow.triangle.2.circlepath"
                            : "scope")
                    } else {
                        Label(
                            L10n.t(autoNavigationPaused
                                ? "恢复自动导航"
                                : "自动导航"),
                            systemImage:
                                autoNavigationPaused
                                ? "arrow.triangle.2.circlepath"
                                : "scope"
                        )
                    }
                }
                .font(.system(size: 9, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                autoNavigationPaused
                    ? visual.stateDFU
                    : visual.textTertiary
            )
            .padding(.horizontal, 7)
            .frame(height: 24)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                (
                    autoNavigationPaused
                        ? visual.stateDFU.opacity(0.095)
                        : visual.textPrimary.opacity(0.04)
                ),
                in: Capsule()
            )
            .accessibilityLabel(
                L10n.t(autoNavigationPaused
                    ? "恢复自动导航"
                    : "自动导航")
            )
            .help(
                L10n.t(autoNavigationPaused
                    ? "恢复自动导航"
                    : "自动导航")
            )

            if !compact {
                restoreStatusBadge
            } else if restore.isRestoreTaskActive {
                compactRestoreStatusBadge
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var workspaceContent: some View {
        Group {
            switch activeTab {
            case .device:
                MinimalPortDeviceWorkspace(
                    panorama: panorama,
                    observation: observation,
                    showTreeForSimpleDensity: $showTreeForSimpleDensity,
                    palette: palette,
                    visual: visual,
                    increaseContrast: increaseContrast,
                    viewedPortKey: navigation.viewedPortKey,
                    controlPortID: device.selectedLiveKey,
                    onReturnToControl: {
                        navigation.viewPort(nil)
                        observation.followLeftControl()
                    },
                    onUserTreeSelection: {
                        autoNavigationPaused = true
                        contextCue = nil
                    }
                )
            case .restore:
                FirmwareRestoreWorkspaceView(
                    navigationPortID: $restoreNavigationPortID,
                    viewedTarget: viewedRestoreTarget,
                    viewedPortKey: navigation.viewedPortKey,
                    viewedTaskID: navigation.viewedTaskID,
                    palette: palette,
                    increaseContrast: increaseContrast)
                    .background(visual.canvasPrimary)
            case .logs:
                LogCaptureWorkspaceView()
                    .background(visual.canvasPrimary)
            }
        }
    }

    private var workspaceTitle: String {
        switch activeTab {
        case .device: return "端口与设备"
        case .restore: return "固件与恢复"
        case .logs: return "RLM 日志"
        }
    }

    private var workspaceSubtitle: String {
        switch activeTab {
        case .device:
            return "完整设备身份、USB-C、PD、HPM、USB4、Thunderbolt 与设备树"
        case .restore:
            return "锁定目标、固件身份、任务状态与真实执行输出"
        case .logs:
            return "独立 RLM 会话与原始记录；不与 cfgutil 实时输出混用"
        }
    }

    private var observationTargetMenu: some View {
        Menu {
            Button {
                observation.followLeftControl()
                navigation.viewPort(nil)
            } label: {
                if observation.followsLeftControl {
                    Label(L10n.t("跟随当前操作接口"), systemImage: "checkmark")
                } else {
                    Text(L10n.t("跟随当前操作接口"))
                }
            }
            Divider()
            ForEach(device.orderedDisplayPorts) { port in
                Button {
                    observation.setFixedObservationPort(port.id)
                    navigation.viewPort(port.id)
                    autoNavigationPaused = true
                } label: {
                    if !observation.followsLeftControl,
                       observation.fixedPortID == port.id {
                        Label(
                            L10n.t(
                                "固定查看：\(L10n.localizedPortName(device.label(for: port)))"),
                            systemImage: "checkmark")
                    } else {
                        Text(L10n.t("固定查看：\(L10n.localizedPortName(device.label(for: port)))"))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "eye")
                    .font(.system(size: 8.5, weight: .semibold))
                Text(observation.followsLeftControl
                    ? L10n.t("当前查看 · 跟随左侧")
                    : L10n.t("当前查看 · \(viewedPortName)"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(visual.textSecondary)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(
                visual.textPrimary.opacity(0.04),
                in: Capsule()
            )
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: compact ? 184 : 240)
        .help(L10n.t(
            "查看目标与控制目标、Restore 锁定目标相互独立"))
    }

    private var viewedPortName: String {
        guard let id = observation.fixedPortID,
              let port = device.orderedDisplayPorts.first(where: { $0.id == id }) else {
            return "已固定端口不可用"
        }
        return L10n.localizedPortName(device.label(for: port))
    }

    private var restoreStatusBadge: some View {
        let title: String
        let tone: Color
        if restore.isRestoreTaskActive {
            title = restore.currentTask?.outcome?.displayTitle ?? "Restore 运行"
            tone = visual.accentPrimary
        } else if let displayed = restore.displayedTask {
            title = displayed.outcome?.displayTitle ?? displayed.phase.displayTitle
            tone = color(for: displayed.outcome)
        } else {
            title = "无 Restore 任务"
            tone = visual.textTertiary
        }
        return HStack(spacing: 4) {
            Circle()
                .fill(tone)
                .frame(width: 5, height: 5)
            Text(L10n.t(title))
                .font(.system(size: 8.8, weight: .semibold))
                .foregroundStyle(visual.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(
            visual.textPrimary.opacity(0.035),
            in: Capsule()
        )
    }

    private var compactRestoreStatusBadge: some View {
        let title = restore.currentTask?.outcome?.displayTitle
            ?? "恢复中"
        return HStack(spacing: 4) {
            Circle()
                .fill(visual.accentPrimary)
                .frame(width: 5, height: 5)
            Text(L10n.t(title))
                .font(.system(size: 8.8, weight: .semibold))
                .foregroundStyle(visual.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(
            visual.accentPrimary.opacity(0.09),
            in: Capsule()
        )
        .fixedSize(horizontal: true, vertical: false)
        .help(L10n.t(
            "Restore 任务保持独立运行；切换查看工作区不会改变锁定目标。"))
    }

    private func color(for outcome: RestoreOutcome?) -> Color {
        switch outcome {
        case .success: return visual.stateSuccess
        case .failure: return visual.stateError
        case .canceled: return visual.textTertiary
        case .unknown: return visual.stateDFU
        case nil: return visual.accentPrimary
        }
    }
}

private struct MinimalPortDeviceWorkspace: View {
    @EnvironmentObject private var device: DeviceControlModel
    @EnvironmentObject private var language: LanguageStore

    @ObservedObject var panorama: PanoramaViewModel
    @ObservedObject var observation: PortDeviceWorkspaceModel
    @Binding var showTreeForSimpleDensity: Bool
    let palette: WorkbenchPalette
    let visual: MRAVisualTokens
    let increaseContrast: Bool
    let viewedPortKey: String?
    let controlPortID: String
    let onReturnToControl: () -> Void
    let onUserTreeSelection: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let hasTree =
                observation.density != .simple
                || showTreeForSimpleDensity
            let detailHeight = min(
                max(210, geometry.size.height * (hasTree ? 0.48 : 0.78)),
                max(210, geometry.size.height - (hasTree ? 205 : 64))
            )

            VStack(spacing: 0) {
                if isViewingNonControlPort {
                    HStack(spacing: 6) {
                        Image(systemName: "eye")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(visual.accentPrimary)
                        Text(L10n.t("正在查看") + " " + (viewedPortLabel ?? L10n.t("未知端口")))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(visual.textSecondary)
                            .lineLimit(1)
                        if let controlPortLabel {
                            Text("· " + L10n.t("物理控制") + " " + controlPortLabel)
                                .font(.system(size: 9))
                                .foregroundStyle(visual.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Button(L10n.t("返回控制端口")) { onReturnToControl() }
                            .buttonStyle(.plain)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(visual.accentPrimary)
                            .accessibilityIdentifier("workbench-return-to-control-port")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        visual.accentPrimary.opacity(increaseContrast ? 0.18 : 0.08)
                    )
                    .accessibilityIdentifier("workbench-viewing-port-banner")

                    Rectangle()
                        .fill(visual.hairline)
                        .frame(height: visual.dividerThickness)
                }

                HStack(spacing: 8) {
                    Text(L10n.t("显示密度"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(visual.textTertiary)
                    Spacer()
                    Picker("", selection: $observation.density) {
                        ForEach(PortDisplayDensity.allCases) { density in
                            Text(L10n.t(density.title)).tag(density)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.mini)
                    .id(language.resolvedCode)
                    .frame(width: 154)
                    .accessibilityIdentifier("workbench-density")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)

                Rectangle()
                    .fill(
                        increaseContrast
                            ? visual.hairlineStrong
                            : visual.hairline
                    )
                    .frame(height: increaseContrast ? 1 : 0.7)

                ScrollView {
                    if viewedPortKey != nil, observedPort == nil {
                        unavailableViewedPortDetail
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    } else {
                        SelectedPortDetailPane(
                            panorama: panorama,
                            port: observedPort,
                            density: observation.density,
                            showPanoramaSummary: false
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .defaultScrollAnchor(.top)
                .accessibilityIdentifier("port-device-detail-scroll")
                .frame(height: detailHeight)

                Rectangle()
                    .fill(
                        increaseContrast
                            ? visual.hairlineStrong
                            : visual.hairline
                    )
                    .frame(height: increaseContrast ? 1 : 0.7)

                if hasTree {
                    PanoramaView(
                        model: panorama,
                        isEmbedded: true,
                        emptyPrimaryText: treeEmptyStateText,
                        onUserSelection: onUserTreeSelection)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(visual.canvasPrimary)
                        .accessibilityIdentifier("port-device-tree")
                } else {
                    Button {
                        showTreeForSimpleDensity = true
                    } label: {
                        Label(
                            L10n.t("展开接口与设备树"),
                            systemImage: "chevron.down")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(visual.accentPrimary)
                    .padding(12)
                }
            }
        }
    }

    private var observedPort: LiveHostPort? {
        // 明确查看的端口优先；若该端口已消失，返回 nil（显示"不可用"），
        // 绝不回退到控制端口的设备信息。
        if viewedPortKey != nil {
            guard let key = viewedPortKey,
                  let viewed = device.orderedDisplayPorts.first(where: { $0.id == key }) else {
                return nil
            }
            return viewed
        }
        let portID = observation.observationPortID(
            controlPortID: device.selectedLiveKey,
            availablePortIDs: device.orderedDisplayPorts.map(\.id))
        return portID.flatMap { key in
            device.orderedDisplayPorts.first { $0.id == key }
        }
    }

    private var isViewingNonControlPort: Bool {
        guard let viewedPortKey else { return false }
        return viewedPortKey != controlPortID
    }

    private var unavailableViewedPortDetail: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("查看端口当前不可用"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(visual.textPrimary)
            Text(L10n.t("该端口已不在当前设备列表中；此处不显示该端口的设备详情。"))
                .font(.system(size: 10.5))
                .foregroundStyle(visual.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.t("物理控制") + " " + (controlPortLabel ?? L10n.t("未知端口")))
                .font(.system(size: 9.5))
                .foregroundStyle(visual.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("workbench-viewed-port-unavailable")
    }

    private var viewedPortLabel: String? {
        guard let viewedPortKey,
              let port = device.orderedDisplayPorts.first(where: { $0.id == viewedPortKey }) else {
            return nil
        }
        return L10n.localizedPortName(device.label(for: port))
    }

    private var controlPortLabel: String? {
        guard let port = device.orderedDisplayPorts.first(where: { $0.id == controlPortID }) else {
            return nil
        }
        return L10n.localizedPortName(device.label(for: port))
    }

    private var treeEmptyStateText: String? {
        guard
            let observedPort,
            device.observedDevice(for: observedPort) != nil
        else {
            return nil
        }
        return L10n.t("USB 观察已看到设备，但接口树尚无可靠物理归属。")
    }
}

private struct DFUContextCueView: View {
    let message: String
    let palette: WorkbenchPalette
    let visual: MRAVisualTokens
    let reduceTransparency: Bool
    let increaseContrast: Bool
    let open: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.shield.fill")
                .foregroundStyle(visual.stateSuccess)
            Text(L10n.t(message))
                .font(.system(size: 9.7, weight: .semibold))
                .foregroundStyle(visual.textSecondary)
            Spacer()
            Button(L10n.t("前往固件与恢复"), action: open)
                .buttonStyle(.link)
                .font(.system(size: 9.4, weight: .semibold))
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(visual.textTertiary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(L10n.t("关闭提示"))
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            reduceTransparency
                ? visual.surfaceSubtle
                : visual.stateSuccess.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    increaseContrast
                        ? visual.hairlineStrong
                        : visual.stateSuccess.opacity(0.22),
                    lineWidth: increaseContrast ? 1 : 0.6
                )
        }
    }
}

private struct WorkbenchToast: View {
    let text: String
    let palette: WorkbenchPalette
    let visual: MRAVisualTokens
    let reduceTransparency: Bool
    let increaseContrast: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(visual.stateSuccess)
            Text(L10n.t(text))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(visual.textSecondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
        .workbenchSurface(
            palette: visual.derivedWorkbenchPalette(fallback: palette),
            radius: 10,
            strength: reduceTransparency ? 0 : 0.32,
            edgeGlow: 0.08,
            depth: 0.22,
            reduceTransparency: reduceTransparency,
            increaseContrast: increaseContrast
        )
    }
}

private extension RestoreOutcome {
    var displayTitle: String {
        switch self {
        case .success: return "Restore 成功"
        case .failure: return "Restore 失败"
        case .canceled: return "Restore 已取消"
        case .unknown: return "Restore 未知"
        }
    }
}

private extension RestoreTaskPhase {
    var displayTitle: String {
        switch self {
        case .userConfirmed: return "Restore 准备"
        case .processStarted: return "Restore 已启动"
        case .restoreActivityObserved: return "Restore 运行"
        case .terminal: return "Restore 已结束"
        }
    }
}

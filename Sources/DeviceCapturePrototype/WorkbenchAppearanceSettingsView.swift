import AppKit
import SwiftUI

enum SystemAccessibilitySettings {
    // macOS 27.3 accepts the extension identifier without showing an error,
    // but does not actually launch Settings. The stable legacy alias is
    // backed by AccessibilitySettingsExtension and opens the same pane.
    static let preferredURLString =
        "x-apple.systempreferences:com.apple.preference.universalaccess"
    static let fallbackURLString =
        "x-apple.systempreferences:com.apple.Accessibility-Settings.extension"

    static var candidateURLs: [URL] {
        [preferredURLString, fallbackURLString].compactMap(URL.init(string:))
    }

    @MainActor
    static func open() -> Bool {
        for url in candidateURLs where NSWorkspace.shared.open(url) {
            return true
        }
        return false
    }
}

struct WorkbenchAppearanceSettingsView: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var appearance: WorkbenchAppearancePreferences
    @EnvironmentObject private var device: DeviceControlModel
    @EnvironmentObject private var helperEnvironment: HelperEnvironmentModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @State private var systemSettingsError = ""

    private var palette: WorkbenchPalette {
        appearance.visualStyle.palette(for: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                previewCard
                presetSection
                visualStyleSection
                appearanceSection
                slidersSection
                togglesSection
                accessibilitySection
                HStack {
                    Button(L10n.t("恢复默认")) {
                        appearance.resetToDefaults()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Text("Appearance / Motion Preferences v1")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.tertiaryText)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.t("外观与动效"))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.primaryText)
            Text(L10n.t("视觉参数只改变材质、空间和反馈，不参与设备控制、端口解析、Restore 或 RLM 的状态判断。"))
                .font(.system(size: 10.5))
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label(L10n.t("实时预览"), systemImage: "eye")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                Text(L10n.t(appearance.currentPreset.title))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(palette.accent.opacity(0.08), in: Capsule())
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.t("当前操作接口"))
                        .font(.system(size: 8.8, weight: .medium))
                        .foregroundStyle(palette.tertiaryText)
                    Text(currentPortText)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    HStack(spacing: 6) {
                        previewChip(
                            L10n.t("Helper：\(helperPreviewText)"),
                            color: helperPreviewColor)
                        previewChip(
                            L10n.t("主机校准：\(L10n.t(device.hostCalibrationLampState.text))"),
                            color: calibrationPreviewColor)
                    }
                }
                Spacer()
                VStack(spacing: 5) {
                    previewAction("进入 DFU", primary: true)
                    HStack(spacing: 5) {
                        previewAction("重启设备", primary: false)
                        previewAction("进入恢复模式", primary: false)
                    }
                }
                .frame(width: 260)
            }
        }
        .padding(13)
        .workbenchSurface(
            palette: palette,
            radius: palette.panelRadius,
            strength: appearance.glassStrength,
            edgeGlow: appearance.edgeGlowStrength,
            depth: appearance.floatingDepth,
            reduceTransparency: systemReduceTransparency,
            increaseContrast: contrast == .increased,
            interactive: true
        )
    }

    private var currentPortText: String {
        guard let port = device.selectedLivePort else {
            return L10n.t("未选择物理端口")
        }
        return "\(L10n.localizedPortName(device.label(for: port))) · \(port.id)"
    }

    private var helperPreviewText: String {
        if device.helperAvailable {
            return "已授权"
        }
        switch helperEnvironment.snapshot.kind {
        case .notInstalled: return "未安装"
        case .unknown: return "未知"
        case .detectFailed: return "检测失败"
        default: return "未授权"
        }
    }

    private var helperPreviewColor: Color {
        switch HelperRuntimePresentation.homeColor(
            snapshot: helperEnvironment.snapshot,
            authenticatedCallAvailable: device.helperAvailable
        ) {
        case "green": return palette.success
        case "orange", "yellow": return palette.warning
        case "red": return palette.danger
        default: return palette.tertiaryText
        }
    }

    private var calibrationPreviewColor: Color {
        switch device.hostCalibrationLampState.color {
        case "green": return palette.success
        case "orange": return palette.warning
        default: return palette.tertiaryText
        }
    }

    private func previewChip(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 4, height: 4)
            Text(text)
                .font(.system(size: 8.2, weight: .medium))
                .foregroundStyle(palette.secondaryText)
        }
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(palette.primaryText.opacity(0.035), in: Capsule())
    }

    private func previewAction(_ title: String, primary: Bool) -> some View {
        Text(L10n.t(title))
            .font(.system(size: primary ? 9.4 : 8.3, weight: .semibold))
            .foregroundStyle(primary ? palette.primaryText : palette.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: primary ? 42 : 32)
            .background(
                primary
                    ? palette.accent.opacity(0.11)
                    : palette.primaryText.opacity(0.04),
                in: RoundedRectangle(cornerRadius: primary ? 9 : 7)
            )
            .overlay {
                RoundedRectangle(cornerRadius: primary ? 9 : 7)
                    .strokeBorder(
                        primary
                            ? palette.accent.opacity(0.28)
                            : palette.separator,
                        lineWidth: 0.65
                    )
            }
    }

    private var presetSection: some View {
        settingsGroup(L10n.t("预设")) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(
                    WorkbenchAppearancePreset.allCases.filter { $0 != .custom }
                ) { preset in
                    selectionCard(
                        title: preset.title,
                        subtitle: preset.subtitle,
                        symbol: preset.symbol,
                        selected: appearance.currentPreset == preset,
                        action: { appearance.applyPreset(preset) }
                    )
                }
            }
            if appearance.currentPreset == .custom {
                Label(
                    L10n.t("当前参数已偏离预设，自动标记为“自定义”。"),
                    systemImage: "slider.horizontal.3")
                    .font(.system(size: 9.2, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                    .padding(.horizontal, 8)
                    .frame(height: 27)
                    .background(
                        palette.accent.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 7)
                    )
            }
        }
    }

    private var visualStyleSection: some View {
        settingsGroup(L10n.t("视觉方向")) {
            ForEach(WorkbenchVisualStyle.allCases) { style in
                selectionRow(
                    title: style.title,
                    subtitle: style.subtitle,
                    symbol: style.symbol,
                    selected: appearance.visualStyle == style,
                    action: { appearance.visualStyle = style }
                )
            }
        }
    }

    private var appearanceSection: some View {
        settingsGroup(L10n.t("外观")) {
            HStack(spacing: 7) {
                ForEach(WorkbenchAppearanceMode.allCases) { mode in
                    selectionCard(
                        title: mode.title,
                        subtitle: nil,
                        symbol: appearanceSymbol(mode),
                        selected: appearance.appearanceMode == mode,
                        action: { appearance.appearanceMode = mode }
                    )
                }
            }
        }
    }

    private var slidersSection: some View {
        settingsGroup(L10n.t("材质、空间与动效")) {
            preferenceSlider(
                L10n.t("玻璃材质强度"),
                detail: L10n.t("影响工具栏与浮层；工程数据面保持不透明"),
                value: Binding(
                    get: { appearance.glassStrength },
                    set: { appearance.glassStrength = $0 })
            )
            preferenceSlider(
                L10n.t("边缘光效"),
                detail: L10n.t("只影响 Hover、选中和焦点边缘"),
                value: Binding(
                    get: { appearance.edgeGlowStrength },
                    set: { appearance.edgeGlowStrength = $0 })
            )
            preferenceSlider(
                L10n.t("空间悬浮深度"),
                detail: L10n.t("影响阴影、层差和轻微抬升"),
                value: Binding(
                    get: { appearance.floatingDepth },
                    set: { appearance.floatingDepth = $0 })
            )
            preferenceSlider(
                L10n.t("动效强度"),
                detail: L10n.t("影响 Hover、按压、工作区切换和相关动画"),
                value: Binding(
                    get: { appearance.motionStrength },
                    set: { appearance.motionStrength = $0 })
            )
        }
    }

    private var togglesSection: some View {
        settingsGroup(L10n.t("装饰动效")) {
            preferenceToggle(
                L10n.t("环境呼吸"),
                detail: L10n.t("窗口激活时显示极低频背景亮度变化"),
                isOn: Binding(
                    get: { appearance.ambientBreathingEnabled },
                    set: { appearance.ambientBreathingEnabled = $0 })
            )
            preferenceToggle(
                L10n.t("粒子背景"),
                detail: L10n.t("少量低速点光；默认关闭，不影响按钮命中区"),
                isOn: Binding(
                    get: { appearance.particlesEnabled },
                    set: { appearance.particlesEnabled = $0 })
            )
            preferenceToggle(
                L10n.t("视差与局部高光"),
                detail: L10n.t("只改变光影，不移动控件点击区域"),
                isOn: Binding(
                    get: { appearance.parallaxEnabled },
                    set: { appearance.parallaxEnabled = $0 })
            )
            preferenceToggle(
                L10n.t("高级 3D"),
                detail: L10n.t("仅限轻微空间层次；Reduce Motion 时归零"),
                isOn: Binding(
                    get: { appearance.advanced3DEnabled },
                    set: { appearance.advanced3DEnabled = $0 })
            )
        }
    }

    private var accessibilitySection: some View {
        settingsGroup(L10n.t("macOS 系统辅助功能")) {
            HStack {
                Text(L10n.t("系统状态（只读）"))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                Text(L10n.t("不会修改 macOS 全局设置"))
                    .font(.system(size: 8.9))
                    .foregroundStyle(palette.tertiaryText)
            }
            VStack(alignment: .leading, spacing: 5) {
                accessibilityStatus(
                    L10n.t("减少动态效果"),
                    active: systemReduceMotion,
                    accessibilityID: "system-reduce-motion-status")
                accessibilityStatus(
                    L10n.t("降低透明度"),
                    active: systemReduceTransparency,
                    accessibilityID: "system-reduce-transparency-status")
                accessibilityStatus(
                    L10n.t("提高对比度"),
                    active: contrast == .increased,
                    accessibilityID: "system-increase-contrast-status")
            }
            HStack(spacing: 8) {
                Button(L10n.t("打开 macOS 辅助功能设置…")) {
                    systemSettingsError = SystemAccessibilitySettings.open()
                        ? ""
                        : "无法打开 macOS 辅助功能设置。"
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("open-system-accessibility-settings")
                Spacer()
            }
            if !systemSettingsError.isEmpty {
                Text(L10n.t(systemSettingsError))
                    .font(.system(size: 9.2, weight: .medium))
                    .foregroundStyle(palette.danger)
            }
            Text(L10n.t(
                "系统辅助功能优先于视觉预设。应用内动效强度不会改写这些系统状态；降低动效或透明度后，全部设备控制、Restore 与日志功能保持可用。"))
                .font(.system(size: 9.2))
                .foregroundStyle(palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func settingsGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t(title))
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.35)
                .foregroundStyle(palette.secondaryText)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(10)
            .background(
                palette.panel,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        contrast == .increased
                            ? palette.strongSeparator
                            : palette.separator,
                        lineWidth: contrast == .increased ? 1.1 : 0.65
                    )
            }
        }
    }

    private func selectionRow(
        title: String,
        subtitle: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        selected ? palette.accent : palette.secondaryText
                    )
                    .frame(width: 27, height: 27)
                    .background(
                        (
                            selected ? palette.accent : palette.secondaryText
                        ).opacity(0.075),
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.t(title))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                    Text(L10n.t(subtitle))
                        .font(.system(size: 8.7))
                        .foregroundStyle(palette.tertiaryText)
                        .lineLimit(2)
                }
                Spacer()
                Image(
                    systemName: selected
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .foregroundStyle(
                    selected ? palette.accent : palette.tertiaryText
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                selected
                    ? palette.accent.opacity(0.055)
                    : palette.primaryText.opacity(0.018),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        selected
                            ? palette.accent.opacity(0.25)
                            : palette.separator,
                        lineWidth: selected ? 0.8 : 0.55
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(L10n.t(selected ? "已选择" : "未选择"))
    }

    private func selectionCard(
        title: String,
        subtitle: String?,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: symbol)
                        .foregroundStyle(
                            selected ? palette.accent : palette.secondaryText
                        )
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(palette.accent)
                    }
                }
                Text(L10n.t(title))
                    .font(.system(size: 10.8, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                if let subtitle {
                    Text(L10n.t(subtitle))
                        .font(.system(size: 8.5))
                        .foregroundStyle(palette.tertiaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: subtitle == nil ? 54 : 70, alignment: .topLeading)
            .background(
                selected
                    ? palette.accent.opacity(0.07)
                    : palette.primaryText.opacity(0.018),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        selected
                            ? palette.accent.opacity(0.30)
                            : palette.separator,
                        lineWidth: selected ? 0.85 : 0.55
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(L10n.t(selected ? "已选择" : "未选择"))
    }

    private func preferenceSlider(
        _ title: String,
        detail: String,
        value: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(L10n.t(title))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.tertiaryText)
            }
            Slider(value: value, in: 0...1)
                .tint(palette.accent)
            Text(L10n.t(detail))
                .font(.system(size: 8.6))
                .foregroundStyle(palette.tertiaryText)
        }
    }

    private func preferenceToggle(
        _ title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t(title))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                Text(L10n.t(detail))
                    .font(.system(size: 8.6))
                    .foregroundStyle(palette.tertiaryText)
            }
        }
        .toggleStyle(.switch)
    }

    private func accessibilityStatus(
        _ title: String,
        active: Bool,
        accessibilityID: String
    ) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(active ? palette.warning : palette.tertiaryText)
                .frame(width: 4, height: 4)
            Text(L10n.t("\(title)：\(active ? "已启用" : "关闭")"))
                .font(.system(size: 8.6, weight: .medium))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 24)
        .background(
            palette.primaryText.opacity(0.03),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityID)
    }

    private func appearanceSymbol(_ mode: WorkbenchAppearanceMode) -> String {
        switch mode {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

import AppKit
import SwiftUI

/// Apple Native Precision Tool V2 — UI-1 视觉 Token。
///
/// 纯展示层：这些值绝不参与设备控制、Restore、Helper 授权、端口校准、
/// 取消/强杀或任何证据判定。深色值是 Owner 提供的 **V2 提议基线**（待 Owner
/// GUI 验收）；浅色值是同一语义在 macOS 浅色外观下的高可读映射。
struct MRAVisualTokens: Sendable {
    // 背景层级
    let canvasPrimary: Color
    let sidebarBackground: Color
    let surfaceSubtle: Color

    // 描边
    let hairline: Color
    let hairlineStrong: Color

    // 文字
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    // 唯一主交互色
    let accentPrimary: Color
    /// 放在 `accentPrimary` 实色填充上的可读文字色（深色主色用白字）。
    let accentText: Color

    // 状态
    let stateDFU: Color
    let telemetryCyan: Color
    let stateSuccess: Color
    let stateError: Color
    let stateNeutral: Color

    // 主框架几何
    let sidebarWidthCompact: CGFloat
    let sidebarWidthRegular: CGFloat
    let railHorizontalPadding: CGFloat
    let dividerThickness: CGFloat

    /// 深色提议基线。
    static let dark = MRAVisualTokens(
        canvasPrimary: Self.hex(0x0F1115),
        sidebarBackground: Self.hex(0x15181E),
        surfaceSubtle: Self.hex(0x1A1E26),
        hairline: Color.white.opacity(0.10),
        hairlineStrong: Color.white.opacity(0.16),
        textPrimary: Self.hex(0xF1F3F5),
        textSecondary: Self.hex(0xA0A7B2),
        textTertiary: Self.hex(0x6E7681),
        accentPrimary: Self.hex(0x0A84FF),
        accentText: .white,
        stateDFU: Self.hex(0xF5A623),
        telemetryCyan: Self.hex(0x22D3EE),
        stateSuccess: Self.hex(0x30D158),
        stateError: Self.hex(0xFF453A),
        stateNeutral: Self.hex(0x6E7681),
        sidebarWidthCompact: 288,
        sidebarWidthRegular: 294,
        railHorizontalPadding: 12,
        dividerThickness: 1
    )

    /// 浅色语义映射：保持同一层级关系，使用高可读的 macOS 原生浅色底。
    static let light = MRAVisualTokens(
        canvasPrimary: Self.hex(0xF4F5F7),
        sidebarBackground: Self.hex(0xECEEF1),
        surfaceSubtle: Self.hex(0xFFFFFF),
        hairline: Color.black.opacity(0.10),
        hairlineStrong: Color.black.opacity(0.18),
        textPrimary: Self.hex(0x1B1E22),
        textSecondary: Self.hex(0x5B6470),
        textTertiary: Self.hex(0x7C858F),
        accentPrimary: Self.hex(0x0A84FF),
        accentText: .white,
        stateDFU: Self.hex(0xB25E00),
        telemetryCyan: Self.hex(0x0E7490),
        stateSuccess: Self.hex(0x1E7A34),
        stateError: Self.hex(0xD70015),
        stateNeutral: Self.hex(0x8A929C),
        sidebarWidthCompact: 288,
        sidebarWidthRegular: 294,
        railHorizontalPadding: 12,
        dividerThickness: 1
    )

    /// `.precision`（V2 基线）使用锁定的提议值；其余既有外观样式继续沿用
    /// 自己的 `WorkbenchPalette`，以免 UI-1 移除用户可见的主题能力。
    static func resolve(
        style: WorkbenchVisualStyle,
        scheme: ColorScheme,
        palette: WorkbenchPalette
    ) -> MRAVisualTokens {
        let baseline: MRAVisualTokens = scheme == .light ? .light : .dark
        switch style {
        case .precision:
            return baseline
        case .liquid, .spatial:
            return MRAVisualTokens(
                canvasPrimary: palette.windowBackground,
                sidebarBackground: palette.controlColumn,
                surfaceSubtle: palette.panelMuted,
                hairline: palette.separator,
                hairlineStrong: palette.strongSeparator,
                textPrimary: palette.primaryText,
                textSecondary: palette.secondaryText,
                textTertiary: palette.tertiaryText,
                accentPrimary: palette.accent,
                accentText: Self.readableText(on: palette.accent),
                stateDFU: palette.warning,
                telemetryCyan: palette.accent,
                stateSuccess: palette.success,
                stateError: palette.danger,
                stateNeutral: palette.tertiaryText,
                sidebarWidthCompact: baseline.sidebarWidthCompact,
                sidebarWidthRegular: baseline.sidebarWidthRegular,
                railHorizontalPadding: baseline.railHorizontalPadding,
                dividerThickness: baseline.dividerThickness
            )
        }
    }

    /// 由 Token 派生既有组件（`WorkbenchStatusLamp` 等）所需的 palette，
    /// 让 `.precision` 只有一套颜色来源；不修改 `WorkbenchDesignSystem.swift`。
    func derivedWorkbenchPalette(fallback: WorkbenchPalette) -> WorkbenchPalette {
        WorkbenchPalette(
            windowBackground: canvasPrimary,
            controlColumn: sidebarBackground,
            panel: surfaceSubtle,
            panelRaised: surfaceSubtle,
            panelMuted: surfaceSubtle,
            primaryText: textPrimary,
            secondaryText: textSecondary,
            tertiaryText: textTertiary,
            separator: hairline,
            strongSeparator: hairlineStrong,
            accent: accentPrimary,
            success: stateSuccess,
            warning: stateDFU,
            danger: stateError,
            shadow: fallback.shadow,
            chromeRadius: fallback.chromeRadius,
            panelRadius: fallback.panelRadius,
            controlRadius: fallback.controlRadius
        )
    }

    private static func readableText(on color: Color) -> Color {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return .white }
        let luminance = 0.2126 * ns.redComponent
            + 0.7152 * ns.greenComponent
            + 0.0722 * ns.blueComponent
        return luminance > 0.62 ? Color.black.opacity(0.88) : .white
    }

    private static func hex(_ value: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// 字体规范：正文/控件 SF Pro 13–14pt；标题 14–16pt Semibold；
/// 技术数据 SF Mono 11–13pt 且等宽数字。尺寸集中在常量里供测试与设计核对。
enum MRAFont {
    static let bodySize: CGFloat = 13
    static let labelSize: CGFloat = 11
    static let titleSize: CGFloat = 15
    static let monoSize: CGFloat = 12
    static let monoSmallSize: CGFloat = 11

    static func body(_ size: CGFloat = bodySize) -> Font {
        .system(size: size, weight: .regular)
    }

    static func label(_ size: CGFloat = labelSize) -> Font {
        .system(size: size, weight: .medium)
    }

    static func title(_ size: CGFloat = titleSize) -> Font {
        .system(size: size, weight: .semibold)
    }

    static func mono(_ size: CGFloat = monoSize) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
            .monospacedDigit()
    }
}

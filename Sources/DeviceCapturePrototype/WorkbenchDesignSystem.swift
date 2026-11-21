import SwiftUI

struct WorkbenchPalette: Sendable {
    let windowBackground: Color
    let controlColumn: Color
    let panel: Color
    let panelRaised: Color
    let panelMuted: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let separator: Color
    let strongSeparator: Color
    let accent: Color
    let success: Color
    let warning: Color
    let danger: Color
    let shadow: Color
    let chromeRadius: CGFloat
    let panelRadius: CGFloat
    let controlRadius: CGFloat
}

extension WorkbenchVisualStyle {
    func palette(for scheme: ColorScheme) -> WorkbenchPalette {
        switch (self, scheme) {
        case (.precision, .dark):
            return WorkbenchPalette(
                windowBackground: Color(red: 0.052, green: 0.060, blue: 0.067),
                controlColumn: Color(red: 0.044, green: 0.052, blue: 0.059),
                panel: Color(red: 0.085, green: 0.096, blue: 0.104),
                panelRaised: Color(red: 0.115, green: 0.128, blue: 0.138),
                panelMuted: Color(red: 0.068, green: 0.078, blue: 0.085),
                primaryText: Color(red: 0.95, green: 0.97, blue: 0.97),
                secondaryText: Color(red: 0.68, green: 0.72, blue: 0.74),
                tertiaryText: Color(red: 0.50, green: 0.54, blue: 0.57),
                separator: Color.white.opacity(0.075),
                strongSeparator: Color.white.opacity(0.16),
                accent: Color(red: 0.46, green: 0.84, blue: 0.78),
                success: Color(red: 0.37, green: 0.82, blue: 0.55),
                warning: Color(red: 0.94, green: 0.70, blue: 0.30),
                danger: Color(red: 0.94, green: 0.44, blue: 0.40),
                shadow: Color.black.opacity(0.42),
                chromeRadius: 13,
                panelRadius: 9,
                controlRadius: 7
            )
        case (.precision, .light):
            return WorkbenchPalette(
                windowBackground: Color(red: 0.925, green: 0.941, blue: 0.949),
                controlColumn: Color(red: 0.892, green: 0.912, blue: 0.922),
                panel: Color(red: 0.978, green: 0.984, blue: 0.987),
                panelRaised: .white,
                panelMuted: Color(red: 0.930, green: 0.944, blue: 0.949),
                primaryText: Color(red: 0.075, green: 0.105, blue: 0.115),
                secondaryText: Color(red: 0.27, green: 0.32, blue: 0.345),
                tertiaryText: Color(red: 0.42, green: 0.47, blue: 0.49),
                separator: Color.black.opacity(0.075),
                strongSeparator: Color.black.opacity(0.15),
                accent: Color(red: 0.02, green: 0.40, blue: 0.35),
                success: Color(red: 0.07, green: 0.43, blue: 0.20),
                warning: Color(red: 0.53, green: 0.30, blue: 0.0),
                danger: Color(red: 0.69, green: 0.13, blue: 0.11),
                shadow: Color.black.opacity(0.16),
                chromeRadius: 13,
                panelRadius: 9,
                controlRadius: 7
            )
        case (.liquid, .dark):
            return WorkbenchPalette(
                windowBackground: Color(red: 0.055, green: 0.073, blue: 0.094),
                controlColumn: Color(red: 0.072, green: 0.091, blue: 0.118),
                panel: Color(red: 0.098, green: 0.119, blue: 0.148),
                panelRaised: Color(red: 0.126, green: 0.153, blue: 0.188),
                panelMuted: Color(red: 0.082, green: 0.101, blue: 0.126),
                primaryText: Color(red: 0.95, green: 0.97, blue: 0.99),
                secondaryText: Color(red: 0.68, green: 0.74, blue: 0.81),
                tertiaryText: Color(red: 0.51, green: 0.57, blue: 0.64),
                separator: Color.white.opacity(0.085),
                strongSeparator: Color.white.opacity(0.17),
                accent: Color(red: 0.54, green: 0.78, blue: 1.0),
                success: Color(red: 0.37, green: 0.84, blue: 0.57),
                warning: Color(red: 0.98, green: 0.72, blue: 0.33),
                danger: Color(red: 0.98, green: 0.42, blue: 0.39),
                shadow: Color.black.opacity(0.40),
                chromeRadius: 18,
                panelRadius: 14,
                controlRadius: 9
            )
        case (.liquid, .light):
            return WorkbenchPalette(
                windowBackground: Color(red: 0.94, green: 0.96, blue: 0.98),
                controlColumn: Color(red: 0.905, green: 0.932, blue: 0.952),
                panel: .white,
                panelRaised: .white,
                panelMuted: Color(red: 0.95, green: 0.967, blue: 0.98),
                primaryText: Color(red: 0.08, green: 0.115, blue: 0.15),
                secondaryText: Color(red: 0.29, green: 0.35, blue: 0.42),
                tertiaryText: Color(red: 0.43, green: 0.49, blue: 0.55),
                separator: Color.black.opacity(0.08),
                strongSeparator: Color.black.opacity(0.15),
                accent: Color(red: 0.0, green: 0.38, blue: 0.79),
                success: Color(red: 0.08, green: 0.46, blue: 0.22),
                warning: Color(red: 0.56, green: 0.32, blue: 0.0),
                danger: Color(red: 0.73, green: 0.15, blue: 0.13),
                shadow: Color.black.opacity(0.17),
                chromeRadius: 18,
                panelRadius: 14,
                controlRadius: 9
            )
        case (.spatial, .dark):
            return WorkbenchPalette(
                windowBackground: Color(red: 0.065, green: 0.080, blue: 0.098),
                controlColumn: Color(red: 0.087, green: 0.106, blue: 0.130),
                panel: Color(red: 0.115, green: 0.140, blue: 0.170),
                panelRaised: Color(red: 0.145, green: 0.174, blue: 0.210),
                panelMuted: Color(red: 0.095, green: 0.117, blue: 0.145),
                primaryText: .white,
                secondaryText: Color(red: 0.72, green: 0.77, blue: 0.83),
                tertiaryText: Color(red: 0.54, green: 0.60, blue: 0.67),
                separator: Color.white.opacity(0.095),
                strongSeparator: Color.white.opacity(0.19),
                accent: Color(red: 0.57, green: 0.80, blue: 1.0),
                success: Color(red: 0.41, green: 0.85, blue: 0.61),
                warning: Color(red: 1.0, green: 0.72, blue: 0.33),
                danger: Color(red: 1.0, green: 0.44, blue: 0.41),
                shadow: Color.black.opacity(0.44),
                chromeRadius: 22,
                panelRadius: 17,
                controlRadius: 11
            )
        case (.spatial, .light):
            return WorkbenchPalette(
                windowBackground: Color(red: 0.93, green: 0.95, blue: 0.97),
                controlColumn: Color(red: 0.895, green: 0.92, blue: 0.95),
                panel: .white,
                panelRaised: .white,
                panelMuted: Color(red: 0.945, green: 0.96, blue: 0.975),
                primaryText: Color(red: 0.075, green: 0.105, blue: 0.145),
                secondaryText: Color(red: 0.28, green: 0.34, blue: 0.41),
                tertiaryText: Color(red: 0.42, green: 0.48, blue: 0.54),
                separator: Color.black.opacity(0.08),
                strongSeparator: Color.black.opacity(0.15),
                accent: Color(red: 0.0, green: 0.36, blue: 0.72),
                success: Color(red: 0.08, green: 0.45, blue: 0.21),
                warning: Color(red: 0.56, green: 0.32, blue: 0.0),
                danger: Color(red: 0.73, green: 0.15, blue: 0.13),
                shadow: Color.black.opacity(0.18),
                chromeRadius: 22,
                panelRadius: 17,
                controlRadius: 11
            )
        @unknown default:
            return Self.precision.palette(for: scheme)
        }
    }
}

struct WorkbenchMotionTokens: Sendable {
    let hover: Double
    let press: Double
    let workspaceResponse: Double
    let workspaceDamping: Double
    let hoverLift: CGFloat
    let glowRadius: CGFloat

    static func make(
        motionStrength: Double,
        floatingDepth: Double,
        reduceMotion: Bool
    ) -> WorkbenchMotionTokens {
        if reduceMotion || motionStrength < 0.05 {
            return WorkbenchMotionTokens(
                hover: 0.01,
                press: 0.01,
                workspaceResponse: 0.16,
                workspaceDamping: 1,
                hoverLift: 0,
                glowRadius: 54
            )
        }
        let motion = min(1, max(0, motionStrength))
        let depth = min(1, max(0, floatingDepth))
        return WorkbenchMotionTokens(
            hover: 0.10 + motion * 0.08,
            press: 0.08 + motion * 0.05,
            workspaceResponse: 0.24 + motion * 0.08,
            workspaceDamping: 0.96,
            hoverLift: 0.35 + depth * 0.55,
            glowRadius: 54 + depth * 32
        )
    }

    var workspaceAnimation: Animation {
        .spring(response: workspaceResponse, dampingFraction: workspaceDamping)
    }
}

private struct WorkbenchSurfaceModifier: ViewModifier {
    let palette: WorkbenchPalette
    let radius: CGFloat
    let strength: Double
    let edgeGlow: Double
    let depth: Double
    let reduceTransparency: Bool
    let increaseContrast: Bool
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let effectiveStrength = min(1, max(0, strength))
        let effectiveGlow = min(1, max(0, edgeGlow))
        let effectiveDepth = min(1, max(0, depth))

        if reduceTransparency || effectiveStrength < 0.08 {
            content
                .background(palette.panelRaised)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(
                        increaseContrast
                            ? palette.strongSeparator
                            : palette.separator,
                        lineWidth: increaseContrast ? 1.15 : 0.65
                    )
                }
                .shadow(
                    color: palette.shadow.opacity(0.16 + effectiveDepth * 0.28),
                    radius: 7 + 10 * effectiveDepth,
                    y: 3 + 5 * effectiveDepth
                )
        } else {
            content
                .background(
                    shape.fill(
                        palette.panel.opacity(
                            0.48 + effectiveStrength * 0.20
                        )
                    )
                )
                .clipShape(shape)
                .glassEffect(
                    .regular
                        .tint(palette.accent.opacity(0.02 + effectiveStrength * 0.08))
                        .interactive(interactive),
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.055 + effectiveGlow * 0.08),
                                increaseContrast
                                    ? palette.strongSeparator
                                    : palette.separator,
                                palette.accent.opacity(0.02 + effectiveGlow * 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: increaseContrast ? 1.15 : 0.65
                    )
                }
                .shadow(
                    color: palette.shadow.opacity(0.18 + effectiveDepth * 0.30),
                    radius: 8 + 12 * effectiveDepth,
                    y: 4 + 7 * effectiveDepth
                )
        }
    }
}

extension View {
    func workbenchSurface(
        palette: WorkbenchPalette,
        radius: CGFloat,
        strength: Double,
        edgeGlow: Double,
        depth: Double,
        reduceTransparency: Bool,
        increaseContrast: Bool,
        interactive: Bool = false
    ) -> some View {
        modifier(
            WorkbenchSurfaceModifier(
                palette: palette,
                radius: radius,
                strength: strength,
                edgeGlow: edgeGlow,
                depth: depth,
                reduceTransparency: reduceTransparency,
                increaseContrast: increaseContrast,
                interactive: interactive
            )
        )
    }
}

struct WorkbenchCoreButton: View {
    let title: String
    let symbol: String
    let primary: Bool
    let showsSymbol: Bool
    let enabled: Bool
    let busy: Bool
    let palette: WorkbenchPalette
    let tokens: WorkbenchMotionTokens
    let reduceTransparency: Bool
    let increaseContrast: Bool
    let edgeGlowStrength: Double
    let action: () -> Void

    @State private var hovered = false
    @FocusState private var focused: Bool

    init(
        title: String,
        symbol: String,
        primary: Bool,
        showsSymbol: Bool = true,
        enabled: Bool,
        busy: Bool,
        palette: WorkbenchPalette,
        tokens: WorkbenchMotionTokens,
        reduceTransparency: Bool,
        increaseContrast: Bool,
        edgeGlowStrength: Double = 0.16,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.primary = primary
        self.showsSymbol = showsSymbol
        self.enabled = enabled
        self.busy = busy
        self.palette = palette
        self.tokens = tokens
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
        self.edgeGlowStrength = edgeGlowStrength
        self.action = action
    }

    private var fill: Color {
        if !enabled {
            return palette.panelMuted
        }
        if primary {
            return palette.accent.opacity(
                reduceTransparency
                    ? 0.20
                    : (hovered ? 0.18 : 0.115)
            )
        }
        return palette.primaryText.opacity(
            reduceTransparency
                ? 0.035
                : (hovered ? 0.075 : 0.038)
        )
    }

    private var border: Color {
        if !enabled {
            return palette.separator
        }
        if focused {
            return primary ? palette.accent : palette.strongSeparator
        }
        if primary {
            let base = 0.18
                + min(1, max(0, edgeGlowStrength)) * 0.28
            return palette.accent.opacity(
                hovered ? min(0.72, base + 0.18) : base)
        }
        return hovered
            ? palette.secondaryText.opacity(
                0.14
                    + min(1, max(0, edgeGlowStrength)) * 0.24)
            : (increaseContrast ? palette.strongSeparator : palette.separator)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: showsSymbol ? 7 : 0) {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14)
                } else if showsSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: primary ? 13 : 12, weight: .semibold))
                        .frame(width: 15)
                }
                Text(title)
                    .font(.system(size: primary ? 13 : 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
                Spacer(minLength: 0)
            }
            .foregroundStyle(
                enabled
                    ? (primary ? palette.primaryText : palette.secondaryText)
                    : palette.tertiaryText
            )
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: primary ? 54 : 44)
            .background(
                RoundedRectangle(
                    cornerRadius: primary ? 11 : 9,
                    style: .continuous
                )
                .fill(fill)
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: primary ? 11 : 9,
                    style: .continuous
                )
                .strokeBorder(border, lineWidth: increaseContrast ? 1.1 : 0.7)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(
            WorkbenchPressButtonStyle(
                tokens: tokens,
                enabled: enabled
            )
        )
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

struct WorkbenchPressButtonStyle: ButtonStyle {
    let tokens: WorkbenchMotionTokens
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                configuration.isPressed && enabled
                    ? 0.982
                    : 1
            )
            .brightness(
                configuration.isPressed && enabled
                    ? -0.018
                    : 0
            )
            .animation(
                .easeOut(
                    duration: tokens.press
                        * (configuration.isPressed ? 0.75 : 1.15)
                ),
                value: configuration.isPressed
            )
    }
}

enum WorkbenchStatusTone: Sendable {
    case positive
    case caution
    case negative
    case neutral
}

struct WorkbenchStatusLamp: View {
    let title: String
    let state: String
    let tone: WorkbenchStatusTone
    let detail: String
    let palette: WorkbenchPalette
    let reduceTransparency: Bool
    let increaseContrast: Bool
    let edgeGlowStrength: Double
    let action: () -> Void

    @State private var hovered = false

    private var color: Color {
        switch tone {
        case .positive: return palette.success
        case .caution: return palette.warning
        case .negative: return palette.danger
        case .neutral: return palette.tertiaryText
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 11, height: 11)
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                    Circle()
                        .strokeBorder(color.opacity(0.28), lineWidth: 0.55)
                        .frame(width: 9, height: 9)
                }
                Text(L10n.t("\(title)：\(state)"))
                    .font(.system(size: 9.3, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity)
            .frame(height: 27)
            .background(
                reduceTransparency
                    ? palette.panelRaised
                    : (
                        hovered
                            ? color.opacity(0.075)
                            : palette.primaryText.opacity(0.028)
                    ),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(
                        hovered
                            ? color.opacity(
                                0.12
                                    + min(1, max(0, edgeGlowStrength))
                                        * 0.24)
                            : (
                                increaseContrast
                                    ? palette.strongSeparator
                                    : palette.separator
                            ),
                        lineWidth: increaseContrast ? 1 : 0.55
                    )
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

struct WorkbenchBackdrop: View {
    let palette: WorkbenchPalette
    let style: WorkbenchVisualStyle
    let preferences: WorkbenchAppearancePreferences
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let active: Bool

    var body: some View {
        ZStack {
            palette.windowBackground

            LinearGradient(
                colors: [
                    palette.controlColumn.opacity(0.42),
                    palette.windowBackground,
                    palette.panel.opacity(0.26)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if style != .precision {
                RadialGradient(
                    colors: [
                        palette.accent.opacity(
                            reduceTransparency ? 0.015 : 0.035
                        ),
                        .clear
                    ],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 680
                )
            }

            if active,
               preferences.ambientBreathingEnabled,
               !reduceMotion,
               !reduceTransparency {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate
                    RadialGradient(
                        colors: [
                            palette.accent.opacity(
                                0.018
                                    + 0.010
                                    * (sin(phase * 0.22) * 0.5 + 0.5)
                            ),
                            .clear
                        ],
                        center: UnitPoint(
                            x: 0.78 + 0.04 * sin(phase * 0.08),
                            y: 0.18 + 0.03 * cos(phase * 0.07)
                        ),
                        startRadius: 0,
                        endRadius: 430
                    )
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            if active,
               preferences.particlesEnabled,
               !reduceMotion,
               !reduceTransparency {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        for index in 0..<28 {
                            let seed = Double(index) * 0.61803398875
                            let x = (seed.truncatingRemainder(dividingBy: 1)
                                + sin(t * 0.035 + seed * 7) * 0.018)
                                * size.width
                            let y = (
                                (seed * 1.71).truncatingRemainder(dividingBy: 1)
                                    + cos(t * 0.028 + seed * 5) * 0.014
                            ) * size.height
                            let rect = CGRect(x: x, y: y, width: 1.2, height: 1.2)
                            context.fill(
                                Path(ellipseIn: rect),
                                with: .color(palette.accent.opacity(0.13))
                            )
                        }
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
    }
}

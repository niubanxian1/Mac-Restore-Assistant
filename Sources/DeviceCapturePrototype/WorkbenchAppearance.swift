import Combine
import Foundation
import SwiftUI

enum WorkbenchVisualStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case liquid
    case precision
    case spatial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liquid: return "Liquid Glass"
        case .precision: return "Precision Graphite"
        case .spatial: return "Spatial Pro"
        }
    }

    var subtitle: String {
        switch self {
        case .liquid: return "轻盈材质与克制层次，接近 Apple 原生表达"
        case .precision: return "石墨工程表面、清晰字段与低强度状态光"
        case .spatial: return "更明显的空间层次，仍保持专业数据可读性"
        }
    }

    var symbol: String {
        switch self {
        case .liquid: return "circle.grid.cross"
        case .precision: return "square.grid.3x3.square"
        case .spatial: return "square.3.layers.3d"
        }
    }
}

enum WorkbenchAppearanceMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum WorkbenchAppearancePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case pure
    case balanced
    case immersive
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pure: return "纯净"
        case .balanced: return "均衡"
        case .immersive: return "沉浸"
        case .custom: return "自定义"
        }
    }

    var subtitle: String {
        switch self {
        case .pure: return "低装饰、低动效，优先长时间阅读与稳定功耗"
        case .balanced: return "克制的材质与反馈，日常维修推荐默认"
        case .immersive: return "更完整的层次与局部环境反馈"
        case .custom: return "独立参数，不再跟随预设覆盖"
        }
    }

    var symbol: String {
        switch self {
        case .pure: return "circle"
        case .balanced: return "circle.lefthalf.filled"
        case .immersive: return "sparkles.rectangle.stack"
        case .custom: return "slider.horizontal.3"
        }
    }
}

@MainActor
final class WorkbenchAppearancePreferences: ObservableObject {
    nonisolated static let storageKey = "MRA.workbench.appearance.v1"

    @Published var visualStyle: WorkbenchVisualStyle {
        didSet { persistIfReady() }
    }

    @Published var appearanceMode: WorkbenchAppearanceMode {
        didSet { persistIfReady() }
    }

    @Published private(set) var currentPreset: WorkbenchAppearancePreset

    @Published var glassStrength: Double {
        didSet { markCustomAndPersist() }
    }

    @Published var edgeGlowStrength: Double {
        didSet { markCustomAndPersist() }
    }

    @Published var floatingDepth: Double {
        didSet { markCustomAndPersist() }
    }

    @Published var motionStrength: Double {
        didSet { markCustomAndPersist() }
    }

    @Published var ambientBreathingEnabled: Bool {
        didSet { markCustomAndPersist() }
    }

    @Published var particlesEnabled: Bool {
        didSet { markCustomAndPersist() }
    }

    @Published var parallaxEnabled: Bool {
        didSet { markCustomAndPersist() }
    }

    @Published var advanced3DEnabled: Bool {
        didSet { markCustomAndPersist() }
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let launchEnvironment: [String: String]
    private var isApplyingValues = false

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = WorkbenchAppearancePreferences.storageKey,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        launchEnvironment = environment

        let snapshot = Self.loadSnapshot(from: defaults, key: storageKey)
        visualStyle = snapshot?.visualStyle ?? .precision
        appearanceMode = snapshot?.appearanceMode ?? .system
        currentPreset = snapshot?.preset ?? .balanced
        glassStrength = snapshot?.glassStrength ?? 0.46
        edgeGlowStrength = snapshot?.edgeGlowStrength ?? 0.16
        floatingDepth = snapshot?.floatingDepth ?? 0.30
        motionStrength = snapshot?.motionStrength ?? 0.46
        ambientBreathingEnabled = snapshot?.ambientBreathingEnabled ?? false
        particlesEnabled = snapshot?.particlesEnabled ?? false
        parallaxEnabled = snapshot?.parallaxEnabled ?? true
        advanced3DEnabled = snapshot?.advanced3DEnabled ?? false
        applyLaunchOverridesWithoutSaving()
    }

    var motionIntensityIsReduced: Bool {
        motionStrength < 0.05
    }

    var colorScheme: ColorScheme? {
        appearanceMode.colorScheme
    }

    var backgroundMotionEnabled: Bool {
        ambientBreathingEnabled || particlesEnabled
    }

    func applyPreset(_ preset: WorkbenchAppearancePreset) {
        guard preset != .custom else { return }
        let wasApplyingValues = isApplyingValues
        isApplyingValues = true
        defer {
            isApplyingValues = wasApplyingValues
            if !wasApplyingValues {
                persistIfReady()
            }
        }

        switch preset {
        case .pure:
            glassStrength = 0.06
            edgeGlowStrength = 0
            floatingDepth = 0.08
            motionStrength = 0.16
            ambientBreathingEnabled = false
            particlesEnabled = false
            parallaxEnabled = false
            advanced3DEnabled = false
        case .balanced:
            glassStrength = 0.46
            edgeGlowStrength = 0.16
            floatingDepth = 0.30
            motionStrength = 0.46
            ambientBreathingEnabled = false
            particlesEnabled = false
            parallaxEnabled = true
            advanced3DEnabled = false
        case .immersive:
            glassStrength = 0.68
            edgeGlowStrength = 0.38
            floatingDepth = 0.58
            motionStrength = 0.64
            ambientBreathingEnabled = true
            particlesEnabled = false
            parallaxEnabled = true
            advanced3DEnabled = true
        case .custom:
            break
        }
        currentPreset = preset
    }

    func resetToDefaults() {
        isApplyingValues = true
        visualStyle = .precision
        appearanceMode = .system
        applyPreset(.balanced)
        isApplyingValues = false
        persistIfReady()
    }

    private func markCustomAndPersist() {
        guard !isApplyingValues else { return }
        currentPreset = .custom
        persistIfReady()
    }

    private func persistIfReady() {
        guard !isApplyingValues else { return }
        let snapshot = Snapshot(
            schemaVersion: 1,
            visualStyle: visualStyle,
            appearanceMode: appearanceMode,
            preset: currentPreset,
            glassStrength: glassStrength,
            edgeGlowStrength: edgeGlowStrength,
            floatingDepth: floatingDepth,
            motionStrength: motionStrength,
            ambientBreathingEnabled: ambientBreathingEnabled,
            particlesEnabled: particlesEnabled,
            parallaxEnabled: parallaxEnabled,
            advanced3DEnabled: advanced3DEnabled
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func applyLaunchOverridesWithoutSaving() {
        let hasOverride =
            launchEnvironment["MRA_UI_VISUAL_STYLE"] != nil
            || launchEnvironment["MRA_UI_APPEARANCE_MODE"] != nil
            || launchEnvironment["MRA_UI_APPEARANCE_PRESET"] != nil
        guard hasOverride else { return }

        isApplyingValues = true
        defer { isApplyingValues = false }

        if let raw = launchEnvironment["MRA_UI_VISUAL_STYLE"],
           let value = WorkbenchVisualStyle(rawValue: raw) {
            visualStyle = value
        }
        if let raw = launchEnvironment["MRA_UI_APPEARANCE_MODE"],
           let value = WorkbenchAppearanceMode(rawValue: raw) {
            appearanceMode = value
        }
        if let raw = launchEnvironment["MRA_UI_APPEARANCE_PRESET"],
           let value = WorkbenchAppearancePreset(rawValue: raw),
           value != .custom {
            applyPreset(value)
        }
    }

    private static func loadSnapshot(
        from defaults: UserDefaults,
        key: String
    ) -> Snapshot? {
        guard
            let data = defaults.data(forKey: key),
            let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
            snapshot.schemaVersion == 1
        else {
            return nil
        }
        return snapshot
    }
}

private struct Snapshot: Codable {
    let schemaVersion: Int
    let visualStyle: WorkbenchVisualStyle
    let appearanceMode: WorkbenchAppearanceMode
    let preset: WorkbenchAppearancePreset
    let glassStrength: Double
    let edgeGlowStrength: Double
    let floatingDepth: Double
    let motionStrength: Double
    let ambientBreathingEnabled: Bool
    let particlesEnabled: Bool
    let parallaxEnabled: Bool
    let advanced3DEnabled: Bool
}

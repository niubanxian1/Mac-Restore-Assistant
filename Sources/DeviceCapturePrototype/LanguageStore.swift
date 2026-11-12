import Foundation
import SwiftUI

/// Presentation-only language preference. It never participates in device
/// selection, readiness, calibration, or command dispatch.
@MainActor
final class LanguageStore: ObservableObject {
    static let storageKey = "ui.languageMode"
    static let supportedModes = ["zh-Hans", "zh-Hant", "en", "ja", "ko"]

    @Published var mode: String {
        didSet {
            UserDefaults.standard.set(mode, forKey: Self.storageKey)
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.storageKey) ?? "zh-Hans"
        mode = Self.supportedModes.contains(saved) ? saved : "zh-Hans"
        if saved != mode { UserDefaults.standard.set(mode, forKey: Self.storageKey) }
    }

    var resolvedCode: String { mode }

    var locale: Locale { Locale(identifier: resolvedCode) }

    /// Chinese keeps the product name; every non-Chinese language uses the
    /// English product name.
    var appDisplayName: String {
        resolvedCode == "zh-Hans" || resolvedCode == "zh-Hant"
            ? "牛半仙Mac维修辅助工具"
            : "Mac Restore Assistant"
    }

    var modeLabel: String {
        switch mode {
        case "zh-Hans": return "简体中文"
        case "zh-Hant": return "繁體中文"
        case "en": return "English"
        case "ja": return "日本語"
        case "ko": return "한국어"
        default: return mode
        }
    }
}

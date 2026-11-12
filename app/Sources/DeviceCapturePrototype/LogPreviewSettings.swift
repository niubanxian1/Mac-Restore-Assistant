import Foundation
import Combine

enum LogPreviewScope: String, CaseIterable, Identifiable {
    case all = "完整原始"
    case selected = "当前设备"
    case unbound = "公共/未归属"
    var id: String { rawValue }
}

/// Preview-only filter. Save always uses the complete raw log.
/// Default is off; an existing user preference must not turn this on at first introduction
/// (this key was not previously written).
@MainActor
final class LogPreviewSettings: ObservableObject {
    static let enabledKey = "MRA.logPreviewFilterEnabled"
    static let scopeKey = "MRA.logPreviewFilterScope"

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled {
                // Turning off immediately returns to complete raw and drops any hidden filter.
                scope = .all
                defaults.set(LogPreviewScope.all.rawValue, forKey: Self.scopeKey)
            }
        }
    }

    @Published var scope: LogPreviewScope {
        didSet {
            if isEnabled {
                defaults.set(scope.rawValue, forKey: Self.scopeKey)
            }
        }
    }

    private let defaults: UserDefaults

    var effectiveScope: LogPreviewScope { isEnabled ? scope : .all }

    var caption: String { L10n.logPreviewCaption() }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // If the key was never written, default to off.
        let enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? false
        let initialScope: LogPreviewScope
        if enabled, let raw = defaults.string(forKey: Self.scopeKey),
           let stored = LogPreviewScope(rawValue: raw) {
            initialScope = stored
        } else {
            initialScope = .all
        }
        self.isEnabled = enabled
        self.scope = initialScope
    }
}

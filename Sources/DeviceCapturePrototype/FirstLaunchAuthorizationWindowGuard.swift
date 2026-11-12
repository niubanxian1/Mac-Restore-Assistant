import AppKit
import CoreGraphics
import Darwin

struct FirstLaunchAuthorizationWindowGuardPolicy {
    static func shouldDefer(hasQuarantine: Bool, alreadyHandled: Bool) -> Bool {
        hasQuarantine && !alreadyHandled
    }

    static func isAuthorizationPromptBundleIdentifier(_ identifier: String?) -> Bool {
        identifier == "com.apple.SecurityAgent"
            || identifier == "com.apple.LocalAuthentication.UIAgent"
    }

    static func hasVisibleAuthorizationWindow(
        ownerPIDs: Set<pid_t>,
        windows: [[String: Any]]
    ) -> Bool {
        guard !ownerPIDs.isEmpty else { return false }
        return windows.contains { window in
            let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            return ownerPID.map(ownerPIDs.contains) == true && alpha > 0
        }
    }
}

@MainActor
final class MRAApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        FirstLaunchAuthorizationWindowGuard.configureForLaunch()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FirstLaunchAuthorizationWindowGuard.beginDeferralIfNeeded()
    }
}

/// On the first launch of a quarantined build, Gatekeeper can launch the App
/// while SecurityAgent is asking for the administrator password. Keep this
/// App's regular window behind that authorization session, then restore it once
/// SecurityAgent exits. The App remains a normal responsive Dock application;
/// changing activation policy or hiding the process makes LaunchServices treat
/// the first launch as failed/not responding.
@MainActor
enum FirstLaunchAuthorizationWindowGuard {
    private static let handledKeyPrefix = "mra.firstLaunchAuthorizationWindowGuard.handled."
    private static let pollInterval: TimeInterval = 0.15
    private static let authorizationAbsencePolls = 4
    private static let noAuthorizationPromptTimeout: TimeInterval = 8
    private static let hardTimeout: TimeInterval = 180

    private static var configuredForLaunch = false
    private static var deferring = false
    private static var sawAuthorizationPrompt = false
    private static var authorizationAbsentCount = 0
    private static var launchTime = Date.distantPast

    static func configureForLaunch(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard
    ) {
        guard !configuredForLaunch else { return }
        configuredForLaunch = true
        launchTime = Date()

        let hasQuarantine = bundleHasQuarantine(bundle.bundleURL)
        let alreadyHandled = defaults.bool(forKey: handledKey(for: bundle))
        var shouldDefer = FirstLaunchAuthorizationWindowGuardPolicy.shouldDefer(
            hasQuarantine: hasQuarantine,
            alreadyHandled: alreadyHandled)
#if DEBUG
        if ProcessInfo.processInfo.environment["MRA_FORCE_FIRST_LAUNCH_GUARD"] == "1" {
            shouldDefer = true
        }
#endif
        deferring = shouldDefer
    }

    static func beginDeferralIfNeeded(
        defaults: UserDefaults = .standard
    ) {
        guard deferring else { return }
        sendWindowsBehindAuthorizationPrompt()
        DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) {
            pollAuthorizationPrompt(defaults: defaults)
        }
    }

    private static func pollAuthorizationPrompt(defaults: UserDefaults) {
        guard deferring else { return }
        sendWindowsBehindAuthorizationPrompt()

        if authorizationPromptIsVisible() {
            sawAuthorizationPrompt = true
            authorizationAbsentCount = 0
        } else if sawAuthorizationPrompt {
            authorizationAbsentCount += 1
            if authorizationAbsentCount >= authorizationAbsencePolls {
                restoreApplication(defaults: defaults)
                return
            }
        }

        let elapsed = Date().timeIntervalSince(launchTime)
        if !sawAuthorizationPrompt && elapsed >= noAuthorizationPromptTimeout {
            restoreApplication(defaults: defaults)
            return
        }
        if elapsed >= hardTimeout {
            restoreApplication(defaults: defaults)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) {
            pollAuthorizationPrompt(defaults: defaults)
        }
    }

    private static func sendWindowsBehindAuthorizationPrompt() {
        // Keep the process and windows alive so LaunchServices completes a
        // normal App check-in. Only move the window behind the system prompt.
        for window in NSApplication.shared.windows where window.canBecomeMain {
            window.orderBack(nil)
        }
        NSApplication.shared.deactivate()
    }

    private static func authorizationPromptIsVisible() -> Bool {
        let ownerPIDs = Set(
            NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.SecurityAgent").map(\.processIdentifier)
            + NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.LocalAuthentication.UIAgent").map(\.processIdentifier))
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID) as? [[String: Any]] ?? []
        return FirstLaunchAuthorizationWindowGuardPolicy.hasVisibleAuthorizationWindow(
            ownerPIDs: ownerPIDs,
            windows: windows)
    }

    private static func restoreApplication(defaults: UserDefaults) {
        guard deferring else { return }
        deferring = false
        defaults.set(true, forKey: handledKey(for: Bundle.main))
        for window in NSApplication.shared.windows where window.canBecomeMain {
            window.orderFrontRegardless()
            window.makeKey()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSRunningApplication.current.activate(options: [
                .activateAllWindows,
                .activateIgnoringOtherApps,
            ])
            NSApplication.shared.activate(ignoringOtherApps: true)
            for window in NSApplication.shared.windows where window.canBecomeMain {
                window.orderFrontRegardless()
                window.makeKey()
            }
            activateThroughLaunchServices()
        }
    }

    private static func activateThroughLaunchServices() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration) { application, _ in
                application?.activate(options: [.activateAllWindows])
            }
    }

    private static func handledKey(for bundle: Bundle) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "unknown"
        return handledKeyPrefix + version
    }

    private static func bundleHasQuarantine(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0
        }
    }
}

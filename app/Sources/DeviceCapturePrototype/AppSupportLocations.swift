import Foundation

/// Resolves the App's Application Support directory.
/// When `MRA_APPLICATION_SUPPORT_ROOT` is set (isolated screenshots / walkthroughs),
/// all user-facing store files go there instead of the real user profile.
enum AppSupportLocations {
    static var environmentOverride: String? {
        let value = ProcessInfo.processInfo.environment["MRA_APPLICATION_SUPPORT_ROOT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    static func directory() -> URL {
        if let override = environmentOverride {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("MRA_DeviceCapture_Prototype", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func calibrationURL() -> URL {
        directory().appendingPathComponent("calibration.json")
    }

    static func portHistoryURL() -> URL {
        directory().appendingPathComponent("port-history.json")
    }

    static func sessionRoot() -> URL {
        let url = directory().appendingPathComponent("Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

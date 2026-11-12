import Foundation
import AppKit

/// Launches the Owner-confirmed standalone calibrator (Hardware Preview B.1)
/// against an isolated home under this App's Application Support root.
/// Never points `MRA_HARDWARE_PREVIEW_HOME` at the default in-use
/// `~/Library/Application Support/Yifei.MacFlashAssistantHardwarePreview`.
@MainActor
final class CalibrationToolLauncher: ObservableObject {
    static let expectedVersion = "1.7-hardware-preview0.3.2-phase-b.1"
    static let previewDirName = "Yifei.MacFlashAssistantHardwarePreview"
    static let defaultAppName = "Mac Restore Assistant Hardware Preview.app"
    static let defaultRelativePath = "Documents/deepseek-harness/default-workspace/MacBook-hardware-preview-phase-b/dist-hardware-preview-phase-b/Mac Restore Assistant Hardware Preview.app"

    @Published var statusMessage = ""
    @Published var isRunning = false
    @Published var lastAppPath: String = ""

    private var process: Process?
    private var watcher: DispatchSourceFileSystemObject?
    private var directoryFD: Int32 = -1
    private var reloadHandler: (() -> Void)?

    static func hardwarePreviewHomeURL() -> URL {
        AppSupportLocations.directory().appendingPathComponent("hardware-preview-home", isDirectory: true)
    }

    static func previewSupportURL() -> URL {
        hardwarePreviewHomeURL().appendingPathComponent(previewDirName, isDirectory: true)
    }

    static func draftURL() -> URL {
        previewSupportURL().appendingPathComponent("draft.json")
    }

    static func adoptedLayoutURL() -> URL {
        AppSupportLocations.directory().appendingPathComponent("adopted-layout.json")
    }

    /// typo-tolerant Owner path (`dai` vs `de` in the ticket username).
    static func resolvedAppURL() -> URL? {
        if let override = ProcessInfo.processInfo.environment["MRA_HARDWARE_PREVIEW_APP"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        var homes: [String] = [NSHomeDirectory()]
        let current = NSHomeDirectory()
        if current.contains("niubanxiandetuzhichakanqi") {
            homes.append(current.replacingOccurrences(of: "niubanxiandetuzhichakanqi", with: "niubanxiandaiuzhichakanqi"))
        } else if current.contains("niubanxiandaiuzhichakanqi") {
            homes.append(current.replacingOccurrences(of: "niubanxiandaiuzhichakanqi", with: "niubanxiandetuzhichakanqi"))
        }
        for home in homes {
            let candidate = URL(fileURLWithPath: home).appendingPathComponent(defaultRelativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static func appVersion(at url: URL) -> String {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) else { return "" }
        return (info["CFBundleShortVersionString"] as? String) ?? ""
    }

    static func isConfirmedB1(at url: URL) -> Bool {
        appVersion(at: url) == expectedVersion
    }

    func attachReload(_ handler: @escaping () -> Void) {
        reloadHandler = handler
        startWatching()
        handler()
    }

    func launchStandaloneCalibrator() {
        guard let app = Self.resolvedAppURL() else {
            statusMessage = "未找到独立校准工具 Hardware Preview B.1。请确认成品路径。"
            return
        }
        let version = Self.appVersion(at: app)
        lastAppPath = app.path
        if version != Self.expectedVersion {
            statusMessage = "找到 \(app.lastPathComponent)，但版本是 \(version.isEmpty ? "未知" : version)，期望 \(Self.expectedVersion)。已停止启动，以免写到未确认的成品。"
            return
        }
        let home = Self.hardwarePreviewHomeURL()
        let support = Self.previewSupportURL()
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        } catch {
            statusMessage = "无法创建隔离校准目录：\(error.localizedDescription)"
            return
        }
        // Refuse to run if the home would resolve to the in-use default library.
        let defaultLibrary = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(Self.previewDirName)")
        let defaultResolved = defaultLibrary.standardizedFileURL.resolveSymlinksInPath()
        let isolatedResolved = support.standardizedFileURL.resolveSymlinksInPath()
        if isolatedResolved.path == defaultResolved.path {
            statusMessage = "拒绝启动：隔离目录解析到了日常 Hardware Preview 库。"
            return
        }
        if let running = process, running.isRunning {
            statusMessage = "校准工具已在隔离配置下运行。"
            return
        }
        let exe = app.appendingPathComponent("Contents/MacOS/Mac Restore Assistant Hardware Preview")
        let task = Process()
        task.executableURL = exe
        var env = ProcessInfo.processInfo.environment
        env["MRA_HARDWARE_PREVIEW_HOME"] = home.path
        task.environment = env
        task.currentDirectoryURL = app.deletingLastPathComponent()
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.statusMessage = "校准工具已退出；正在重新读取实际采用的布局。"
                self?.reloadHandler?()
            }
        }
        do {
            try task.run()
            process = task
            isRunning = true
            statusMessage = "已打开 Hardware Preview B.1（\(Self.expectedVersion)），使用隔离配置。"
            startWatching()
        } catch {
            statusMessage = "无法启动校准工具：\(error.localizedDescription)"
        }
    }

    func startWatching() {
        stopWatching()
        let directory = Self.previewSupportURL()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        directoryFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .link, .delete],
            queue: DispatchQueue.main)
        source.setEventHandler { [weak self] in
            self?.reloadHandler?()
        }
        source.setCancelHandler {
            close(fd)
        }
        watcher = source
        source.resume()
    }

    func stopWatching() {
        watcher?.cancel()
        watcher = nil
        directoryFD = -1
    }

    deinit {
        if directoryFD >= 0 { /* cancelled by stopWatching */ }
    }
}

private extension URL {
    func resolveSymlinksInPath() -> URL {
        URL(fileURLWithPath: (self.path as NSString).resolvingSymlinksInPath)
    }
}

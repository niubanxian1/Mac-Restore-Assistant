import Foundation
import AppKit
import SwiftUI

/// Concrete Apple Configurator paths verified on this product and the Owner Mac.
/// Do not use the old script's wildcard deletes.
enum ConfiguratorPathKind: String, Equatable {
    case caches = "Caches"
    case applicationSupport = "Application Support"
}

struct ConfiguratorTargetPath: Equatable, Identifiable {
    var id: String { path }
    var path: String
    var kind: ConfiguratorPathKind
    var displayName: String
    var isLegacy: Bool = false
}

enum ConfiguratorStepStatus: Equatable {
    case success
    case noMatch
    case failure
    case skipped
}

struct ConfiguratorStepResult: Equatable, Identifiable {
    var id: String { name }
    var name: String
    var status: ConfiguratorStepStatus
    var detail: String

    var succeeded: Bool { status == .success || status == .noMatch || status == .skipped }
    var statusText: String {
        switch status {
        case .success: return "成功"
        case .noMatch: return "无匹配"
        case .failure: return "失败"
        case .skipped: return "跳过"
        }
    }
}

enum ConfiguratorResetAction: Equatable {
    case reopen
    case cleanAndReset
}

protocol ConfiguratorProcessExecuting {
    func isRunning(processName: String) -> Bool
    func quit(processName: String) throws
    func waitForTermination(processName: String, timeout: TimeInterval) -> Bool
    func openApplication(at url: URL) throws
    func waitUntilRunning(processName: String, timeout: TimeInterval) -> Bool
    func bringToFront(processName: String) throws
}

protocol ConfiguratorFileOperating {
    func fileExists(atPath path: String) -> Bool
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func createDirectory(at url: URL) throws
    func copyItem(at src: URL, to dst: URL) throws
    func removeItem(at url: URL) throws
}

struct LiveConfiguratorProcessExecutor: ConfiguratorProcessExecuting {
    func isRunning(processName: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-x", processName]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    func quit(processName: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = [processName]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        // killall returns 1 when the process is not running; treat as already quit.
        if p.terminationStatus != 0 && isRunning(processName: processName) {
            throw NSError(domain: "ConfiguratorReset", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "未能退出 \(processName)（退出码 \(p.terminationStatus)）"])
        }
    }

    func waitForTermination(processName: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if !isRunning(processName: processName) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return !isRunning(processName: processName)
    }

    func openApplication(at url: URL) throws {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        let semaphore = DispatchSemaphore(value: 0)
        var openError: Error?
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, error in
            openError = error
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 15) == .timedOut {
            throw NSError(domain: "ConfiguratorReset", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "打开 Apple Configurator 超时"])
        }
        if let openError { throw openError }
    }

    func waitUntilRunning(processName: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if isRunning(processName: processName) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return isRunning(processName: processName)
    }

    func bringToFront(processName: String) throws {
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: ConfiguratorKnownLocations.bundleIdentifier
        ).first else {
            throw NSError(domain: "ConfiguratorReset", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "找不到运行中的 \(processName)，无法置前"])
        }
        guard app.activate(options: [.activateAllWindows]) else {
            throw NSError(domain: "ConfiguratorReset", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "已找到 \(processName)，但系统拒绝置前"])
        }
    }
}

struct FoundationConfiguratorFileOperating: ConfiguratorFileOperating {
    let fileManager: FileManager
    init(fileManager: FileManager = .default) { self.fileManager = fileManager }
    func fileExists(atPath path: String) -> Bool { fileManager.fileExists(atPath: path) }
    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
    }
    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
    func copyItem(at src: URL, to dst: URL) throws { try fileManager.copyItem(at: src, to: dst) }
    func removeItem(at url: URL) throws { try fileManager.removeItem(at: url) }
}

/// Reference-type mock so tests can inspect call counts after the model runs.
final class MockConfiguratorExecutor: ConfiguratorProcessExecuting {
    var running: Bool
    var quitShouldFail: Bool
    var openShouldFail: Bool
    var frontShouldFail: Bool
    private(set) var quitCount = 0
    private(set) var openCount = 0
    private(set) var frontCount = 0
    private(set) var waitTerminationCount = 0
    private(set) var waitRunningCount = 0
    private(set) var openedURL: URL?

    init(running: Bool = false, quitShouldFail: Bool = false, openShouldFail: Bool = false, frontShouldFail: Bool = false) {
        self.running = running
        self.quitShouldFail = quitShouldFail
        self.openShouldFail = openShouldFail
        self.frontShouldFail = frontShouldFail
    }

    func isRunning(processName: String) -> Bool {
        _ = processName
        return running
    }

    func quit(processName: String) throws {
        quitCount += 1
        if quitShouldFail {
            throw NSError(domain: "ConfiguratorReset", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "模拟：退出失败"])
        }
        running = false
        _ = processName
    }

    func waitForTermination(processName: String, timeout: TimeInterval) -> Bool {
        _ = processName
        _ = timeout
        waitTerminationCount += 1
        return !running
    }

    func openApplication(at url: URL) throws {
        openCount += 1
        openedURL = url
        if openShouldFail {
            throw NSError(domain: "ConfiguratorReset", code: 12,
                          userInfo: [NSLocalizedDescriptionKey: "模拟：打开失败"])
        }
        running = true
    }

    func waitUntilRunning(processName: String, timeout: TimeInterval) -> Bool {
        _ = processName
        _ = timeout
        waitRunningCount += 1
        return running
    }

    func bringToFront(processName: String) throws {
        frontCount += 1
        if frontShouldFail {
            throw NSError(domain: "ConfiguratorReset", code: 13,
                          userInfo: [NSLocalizedDescriptionKey: "模拟：置前失败"])
        }
        _ = processName
    }
}

enum ConfiguratorKnownLocations {
    static let processName = "Apple Configurator"
    static let bundleIdentifier = "com.apple.configurator.ui"
    static let defaultAppPath = "/Applications/Apple Configurator.app"

    /// Exact paths relative to a home directory. Wildcard-like legacy names
    /// are expanded through read-only directory enumeration before use.
    static func candidatePaths(home: URL) -> [ConfiguratorTargetPath] {
        let homePath = home.path
        return [
            ConfiguratorTargetPath(
                path: homePath + "/Library/Caches/com.apple.configurator.ui",
                kind: .caches,
                displayName: "Caches · com.apple.configurator.ui"),
            ConfiguratorTargetPath(
                path: homePath + "/Library/Containers/com.apple.configurator.ui/Data/Library/Caches",
                kind: .caches,
                displayName: "Caches · 容器 com.apple.configurator.ui"),
            ConfiguratorTargetPath(
                path: homePath + "/Library/Containers/com.apple.configurator.ui/Data/Library/Application Support",
                kind: .applicationSupport,
                displayName: "Application Support · 容器 com.apple.configurator.ui"),
            ConfiguratorTargetPath(
                path: homePath + "/Library/Application Support/Apple/Apple Configurator",
                kind: .applicationSupport,
                displayName: "Application Support · Apple Configurator（旧路径）",
                isLegacy: true),
            ConfiguratorTargetPath(
                path: homePath + "/Library/Application Support/Apple/Apple Configurator 2",
                kind: .applicationSupport,
                displayName: "Application Support · Apple Configurator 2（旧路径）",
                isLegacy: true),
        ]
    }

    static func discoverExistingTargets(
        home: URL,
        files: ConfiguratorFileOperating
    ) -> [ConfiguratorTargetPath] {
        var targets = candidatePaths(home: home).filter {
            hasContent(at: $0.path, files: files)
        }
        var paths = Set(targets.map(\.path))

        func appendLegacyMatches(
            directory: URL,
            prefixes: [String],
            kind: ConfiguratorPathKind,
            label: String
        ) {
            guard files.fileExists(atPath: directory.path),
                  let children = try? files.contentsOfDirectory(at: directory) else { return }
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = child.lastPathComponent
                guard prefixes.contains(where: { name.hasPrefix($0) }),
                      hasContent(at: child.path, files: files),
                      paths.insert(child.path).inserted else { continue }
                targets.append(ConfiguratorTargetPath(
                    path: child.path,
                    kind: kind,
                    displayName: "\(label) · \(name)（旧路径，精确展开）",
                    isLegacy: true))
            }
        }

        appendLegacyMatches(
            directory: home.appendingPathComponent("Library/Caches", isDirectory: true),
            prefixes: ["com.apple.AppleConfigurator"],
            kind: .caches,
            label: "Caches")
        appendLegacyMatches(
            directory: home.appendingPathComponent(
                "Library/Application Support/Apple", isDirectory: true),
            prefixes: ["Apple Configurator"],
            kind: .applicationSupport,
            label: "Application Support")

        return targets.sorted {
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.path < $1.path
        }
    }

    private static func hasContent(
        at path: String,
        files: ConfiguratorFileOperating
    ) -> Bool {
        guard files.fileExists(atPath: path) else { return false }
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return false
        }
        if !isDirectory.boolValue { return true }
        return !((try? files.contentsOfDirectory(at: url)) ?? []).isEmpty
    }
}

enum ConfiguratorPanelChoice: String, Equatable, CaseIterable {
    case ownerQuickReset
    case cleanAndRestart
    case reopenOnly
}

@MainActor
final class ConfiguratorResetModel: ObservableObject {
    @Published var includeApplicationSupport = false
    @Published var panelChoice: ConfiguratorPanelChoice = .cleanAndRestart
    @Published var preferredAction: ConfiguratorPanelChoice = .cleanAndRestart
    @Published var stepResults: [ConfiguratorStepResult] = []
    @Published var overallMessage = ""
    @Published var isBusy = false
    @Published var lastBackupURL: URL?

    let home: URL
    let appURL: URL
    let executor: ConfiguratorProcessExecuting
    let files: ConfiguratorFileOperating
    /// When true, never call the live executor; used by isolated acceptance.
    let simulationOnly: Bool

    static let preferenceKey = "MRA.configuratorMainAction.v2"

    init(home: URL,
         appURL: URL = URL(fileURLWithPath: ConfiguratorKnownLocations.defaultAppPath),
         executor: ConfiguratorProcessExecuting,
         files: ConfiguratorFileOperating = FoundationConfiguratorFileOperating(),
         simulationOnly: Bool = true) {
        self.home = home
        self.appURL = appURL
        self.executor = executor
        self.files = files
        self.simulationOnly = simulationOnly
        if let raw = UserDefaults.standard.string(forKey: Self.preferenceKey),
           let saved = ConfiguratorPanelChoice(rawValue: raw) {
            self.preferredAction = saved
        } else {
            self.preferredAction = .ownerQuickReset
        }
        self.panelChoice = self.preferredAction
    }

    func setPreferredAction(_ action: ConfiguratorPanelChoice) {
        preferredAction = action
        panelChoice = action
        UserDefaults.standard.set(action.rawValue, forKey: Self.preferenceKey)
    }

    var mainActionTitle: String {
        switch preferredAction {
        case .ownerQuickReset: return L10n.t("安全深度重置 Configurator")
        case .cleanAndRestart: return L10n.t("清理缓存并重启 Configurator")
        case .reopenOnly: return L10n.t("重新打开 Configurator")
        }
    }

    var cleanScopeSummary: String {
        "先只读盘点当前容器和旧路径，再清理已存在的精确 Caches 目标；Application Support 默认保留。"
    }

    var preferredActionSummary: String {
        switch preferredAction {
        case .ownerQuickReset:
            return "安全深度重置：退出、盘点当前与旧路径、清理精确 Caches，然后重新打开并验证置前。不会暂停 usbd，Application Support 默认保留。"
        case .cleanAndRestart:
            return cleanScopeSummary
        case .reopenOnly:
            return "重新打开会退出、再启动并置前 Apple Configurator。不会清理任何数据。"
        }
    }

    func runPreferredAction() {
        panelChoice = preferredAction
        executeSelectedPanelAction()
    }

    var processName: String { ConfiguratorKnownLocations.processName }

    var interruptWarning: String {
        "重新启动 Configurator 可能中断正在进行的刷机"
    }

    var processNotProofNote: String {
        "这里操作的是本机上的 Apple Configurator 软件，不是左侧对目标设备的「重启设备」。进程存在并不表示正在刷机，也不表示软件空闲。"
    }

    var cleanScopeTitle: String { "清理缓存并重启 Configurator" }
    var reopenChoiceTitle: String { "仅重新打开 Configurator" }
    var reopenChoiceNote: String { "保留缓存和用户数据" }

    var executeButtonTitle: String {
        switch panelChoice {
        case .ownerQuickReset: return "安全深度重置"
        case .cleanAndRestart: return "清理缓存并重启"
        case .reopenOnly: return "重新打开"
        }
    }

    /// Paths this run will clean when a cleanup level is executed.
    /// Application Support is never included unless the user also opts in.
    var defaultCleanTargetsThisRun: [ConfiguratorTargetPath] {
        let existing = cacheTargets
        return existing.isEmpty
            ? ConfiguratorKnownLocations.candidatePaths(home: home).filter { $0.kind == .caches }
            : existing
    }

    var listsExistingCachesOnly: Bool { !cacheTargets.isEmpty }

    func preparePanelDefaults() {
        panelChoice = preferredAction
        includeApplicationSupport = false
        stepResults = []
        overallMessage = ""
        lastBackupURL = nil
    }

    func executeSelectedPanelAction() {
        switch panelChoice {
        case .ownerQuickReset:
            performCleanAndReset()
        case .cleanAndRestart:
            performCleanAndReset()
        case .reopenOnly:
            performReopen()
        }
    }

    var reopenSummary: String {
        "重新打开会退出、再启动并置前 Apple Configurator。不会清理任何数据。"
    }

    var existingTargets: [ConfiguratorTargetPath] {
        ConfiguratorKnownLocations.discoverExistingTargets(home: home, files: files)
    }

    var cacheTargets: [ConfiguratorTargetPath] { existingTargets.filter { $0.kind == .caches } }
    var applicationSupportTargets: [ConfiguratorTargetPath] { existingTargets.filter { $0.kind == .applicationSupport } }

    var allStepsSucceeded: Bool {
        !stepResults.isEmpty && stepResults.allSatisfy(\.succeeded)
    }

    func performReopen() {
        guard !isBusy else { return }
        isBusy = true
        stepResults = []
        lastBackupURL = nil
        overallMessage = ""
        defer { isBusy = false }
        let quitOK = quitForRestart()
        guard quitOK else {
            overallMessage = "重新打开未完成：退出步骤失败。未清理数据，也不会把这次结果写成全部完成。"
            return
        }
        if openAndFront() {
            overallMessage = "已重新打开并置前 Apple Configurator。未清理数据。"
        } else {
            overallMessage = "重新打开或置前未成功。未清理数据。"
        }
    }

    func performCleanAndReset() {
        guard !isBusy else { return }
        isBusy = true
        stepResults = []
        lastBackupURL = nil
        overallMessage = ""
        defer { isBusy = false }

        let inventory = existingTargets
        let cacheCount = inventory.filter { $0.kind == .caches }.count
        let supportCount = inventory.filter { $0.kind == .applicationSupport }.count
        recordStep(
            name: "只读盘点",
            status: inventory.isEmpty ? .noMatch : .success,
            detail: inventory.isEmpty
                ? "当前容器和旧路径均无匹配；未删除任何内容。"
                : "发现 \(cacheCount) 个 Caches、\(supportCount) 个 Application Support 精确目标。")

        let quitOK = quitForRestart()
        guard quitOK else {
            _ = recordStep(
                name: "保留数据",
                status: .success,
                detail: "退出未完成，因此没有继续备份、删除或重新打开。")
            _ = tryBringToFrontAfterFailure()
            overallMessage = "清理未执行：退出步骤失败。不会在失败后继续删除文件，也不会把这次结果写成全部完成。"
            return
        }

        let targetsAfterQuit = existingTargets
        let caches = targetsAfterQuit.filter { $0.kind == .caches }
        let support = targetsAfterQuit.filter { $0.kind == .applicationSupport }

        if includeApplicationSupport {
            let backupOK = performBackup(targets: support)
            guard backupOK else {
                _ = tryOpenAndFrontAfterFailure()
                overallMessage = "已取消清理：Application Support 备份或校验失败，未删除任何目录。"
                return
            }
        } else if !support.isEmpty {
            _ = recordStep(
                name: "保留 Application Support",
                status: .skipped,
                detail: "发现 \(support.count) 个精确 Application Support 目标；本次未勾选，全部保留。")
        }

        var removable = caches
        if includeApplicationSupport { removable.append(contentsOf: support) }
        var removed: [String] = []
        var noMatch: [String] = []
        var failures: [String] = []
        for target in removable {
            guard files.fileExists(atPath: target.path) else {
                noMatch.append(target.path)
                continue
            }
            do {
                try files.removeItem(at: URL(fileURLWithPath: target.path))
                if files.fileExists(atPath: target.path) {
                    failures.append("\(target.path)：删除后仍存在")
                } else {
                    removed.append("\(target.kind.rawValue)：\(target.path)")
                }
            } catch {
                failures.append("\(target.path)：\(error.localizedDescription)")
            }
        }
        var cleanupDetails: [String] = []
        if !removed.isEmpty { cleanupDetails.append("已删除：\n" + removed.joined(separator: "\n")) }
        if !noMatch.isEmpty { cleanupDetails.append("执行时无匹配、未删除：\n" + noMatch.joined(separator: "\n")) }
        if !failures.isEmpty { cleanupDetails.append("删除失败：\n" + failures.joined(separator: "\n")) }
        if cleanupDetails.isEmpty { cleanupDetails.append("没有可清理的精确目标。") }
        let cleanupStatus: ConfiguratorStepStatus
        if !failures.isEmpty { cleanupStatus = .failure }
        else if removed.isEmpty { cleanupStatus = .noMatch }
        else { cleanupStatus = .success }
        recordStep(
            name: "精确清理",
            status: cleanupStatus,
            detail: cleanupDetails.joined(separator: "\n"))

        let reopened = openAndFront()
        if cleanupStatus == .failure {
            overallMessage = "清理未全部成功；未删除项已保留。请查看分步结果。"
        } else if reopened {
            if includeApplicationSupport {
                overallMessage = "精确清理与重新打开已完成。Application Support 已先保留副本，再按你的明确选择处理。"
            } else if cleanupStatus == .noMatch {
                overallMessage = "没有需要删除的精确匹配项；数据未改动，Apple Configurator 已重新打开并置前。"
            } else {
                overallMessage = "已清理精确 Caches、重新打开并置前 Apple Configurator。Application Support 未改动。"
            }
        } else {
            overallMessage = "清理结果已按步骤记录，但重新打开或置前未成功。"
        }
    }

    @discardableResult
    private func recordStep(
        name: String,
        status: ConfiguratorStepStatus,
        detail: String
    ) -> Bool {
        stepResults.append(ConfiguratorStepResult(name: name, status: status, detail: detail))
        return status != .failure
    }

    private func quitForRestart() -> Bool {
        guard executor.isRunning(processName: processName) else {
            return recordStep(
                name: "退出",
                status: .success,
                detail: "\(processName) 当时未运行，无需终止。")
        }
        do {
            try executor.quit(processName: processName)
        } catch {
            return recordStep(
                name: "退出",
                status: .failure,
                detail: error.localizedDescription)
        }
        guard executor.waitForTermination(processName: processName, timeout: 8) else {
            return recordStep(
                name: "退出",
                status: .failure,
                detail: "已请求退出，但 8 秒内仍检测到 \(processName)。不会升级为强制结束。")
        }
        return recordStep(
            name: "退出",
            status: .success,
            detail: "已确认 \(processName) 进程结束。")
    }

    private func performBackup(targets: [ConfiguratorTargetPath]) -> Bool {
        guard !targets.isEmpty else {
            return recordStep(
                name: "备份 Application Support",
                status: .noMatch,
                detail: "当前盘点的 Application Support 精确目标为空，无需备份。")
        }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        let backupRoot = home.appendingPathComponent(
            "Library/Application Support/MRA/ConfiguratorBackups/\(stamp)-\(UUID().uuidString.prefix(8))",
            isDirectory: true)
        do {
            try files.createDirectory(at: backupRoot)
            var copied: [String] = []
            for (index, target) in targets.enumerated() {
                let src = URL(fileURLWithPath: target.path, isDirectory: true)
                let safeName = target.kind.rawValue
                    .replacingOccurrences(of: " ", with: "-")
                let dst = backupRoot.appendingPathComponent(
                    String(format: "%02d-%@-%@", index + 1, safeName, target.isLegacy ? "legacy" : "container"),
                    isDirectory: true)
                try files.copyItem(at: src, to: dst)
                guard files.fileExists(atPath: dst.path) else {
                    throw NSError(
                        domain: "ConfiguratorReset",
                        code: 30,
                        userInfo: [NSLocalizedDescriptionKey: "副本未出现在 \(dst.path)"])
                }
                copied.append("\(target.path) → \(dst.path)")
            }
            lastBackupURL = backupRoot
            return recordStep(
                name: "备份 Application Support",
                status: .success,
                detail: "已保留 \(copied.count) 个可恢复副本：\n" + copied.joined(separator: "\n"))
        } catch {
            return recordStep(
                name: "备份 Application Support",
                status: .failure,
                detail: "\(error.localizedDescription)；未删除任何目录。")
        }
    }

    private func openAndFront() -> Bool {
        do {
            try executor.openApplication(at: appURL)
        } catch {
            return recordStep(
                name: "重新打开",
                status: .failure,
                detail: error.localizedDescription)
        }
        guard executor.waitUntilRunning(processName: processName, timeout: 8) else {
            return recordStep(
                name: "重新打开",
                status: .failure,
                detail: "已请求打开，但 8 秒内没有检测到运行的 \(processName)。")
        }
        guard recordStep(
            name: "重新打开",
            status: .success,
            detail: "已确认 \(processName) 正在运行。") else { return false }
        do {
            try executor.bringToFront(processName: processName)
            return recordStep(
                name: "置前",
                status: .success,
                detail: "系统已接受置前请求。")
        } catch {
            return recordStep(
                name: "置前",
                status: .failure,
                detail: error.localizedDescription)
        }
    }

    private func tryOpenAndFrontAfterFailure() {
        if executor.isRunning(processName: processName) {
            do {
                try executor.bringToFront(processName: processName)
                _ = recordStep(
                    name: "置前当前窗口",
                    status: .success,
                    detail: "备份失败后，已将仍在运行的 \(processName) 置前。")
            } catch {
                _ = recordStep(
                    name: "置前当前窗口",
                    status: .failure,
                    detail: error.localizedDescription)
            }
            return
        }
        if openAndFront() { return }
        _ = recordStep(
            name: "置前当前窗口",
            status: .skipped,
            detail: "未能确认 Configurator 已运行，无法置前。")
    }

    private func tryBringToFrontAfterFailure() {
        guard executor.isRunning(processName: processName) else { return }
        do {
            try executor.bringToFront(processName: processName)
            _ = recordStep(
                name: "置前当前窗口",
                status: .success,
                detail: "退出失败后，已将仍在运行的 \(processName) 置前。")
        } catch {
            _ = recordStep(
                name: "置前当前窗口",
                status: .failure,
                detail: error.localizedDescription)
        }
    }
}

struct ConfiguratorResetView: View {
    @ObservedObject var model: ConfiguratorResetModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("重置 Apple Configurator"))
                .font(.system(size: 17, weight: .semibold))
            Text(L10n.t(model.processNotProofNote))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.t(model.interruptWarning))
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                choiceRow(.ownerQuickReset,
                          title: L10n.t("安全深度重置 Configurator")) {
                    Text(L10n.t("退出后只读盘点当前容器和旧路径，只清理精确 Caches；Application Support 默认保留；不暂停 usbd；重新打开后验证置前。"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                choiceRow(.cleanAndRestart, title: L10n.t(model.cleanScopeTitle)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t(model.listsExistingCachesOnly ? "本次将清理以下已核实的 Caches 路径：" : "本次默认清理以下已核实的 Caches 路径（若存在）："))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        ForEach(model.defaultCleanTargetsThisRun) { item in
                            Text(item.path)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        Text(L10n.t("Application Support 中的用户数据默认保留。"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                choiceRow(.reopenOnly, title: L10n.t(model.reopenChoiceTitle)) {
                    Text(L10n.t(model.reopenChoiceNote))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if model.panelChoice != .reopenOnly {
                Toggle(
                    L10n.t("同时处理 Application Support（先保留可恢复副本）"),
                    isOn: $model.includeApplicationSupport)
                    .font(.system(size: 12))
                    .help(L10n.t("默认关闭；关闭时 Application Support 保持不变。"))
            }

            HStack(spacing: 10) {
                Button(L10n.t(model.executeButtonTitle)) {
                    model.executeSelectedPanelAction()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
                Button(L10n.t("取消")) { dismiss() }
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy)
                Spacer()
            }

            if !model.stepResults.isEmpty {
                GroupBox(L10n.t("分步结果")) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.stepResults) { step in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(L10n.t(step.name))：\(L10n.t(step.statusText))")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(color(for: step.status))
                                Text(step.detail)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !model.overallMessage.isEmpty {
                Text(L10n.t(model.overallMessage))
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let backup = model.lastBackupURL {
                Text("\(L10n.t("可恢复副本："))\(backup.path)")
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(minWidth: 520, minHeight: 420)
        .onAppear { model.preparePanelDefaults() }
    }

    private func color(for status: ConfiguratorStepStatus) -> Color {
        switch status {
        case .success: return .primary
        case .noMatch, .skipped: return .secondary
        case .failure: return .red
        }
    }

    private func choiceRow<Content: View>(_ choice: ConfiguratorPanelChoice,
                                          title: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        let selected = model.panelChoice == choice
        return Button {
            model.panelChoice = choice
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    content()
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
    }
}

extension ConfiguratorResetModel {
    static func makeFromEnvironment() -> ConfiguratorResetModel {
        let env = ProcessInfo.processInfo.environment
        let isolatedRoot = AppSupportLocations.environmentOverride
        let simulate = env["MRA_CONFIGURATOR_SIMULATE"] == "1" || isolatedRoot != nil
        let home: URL
        if let custom = env["MRA_CONFIGURATOR_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            home = URL(fileURLWithPath: custom, isDirectory: true)
        } else if simulate, let isolatedRoot, !isolatedRoot.isEmpty {
            home = URL(fileURLWithPath: isolatedRoot, isDirectory: true).appendingPathComponent("configurator-home", isDirectory: true)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
        }
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        if simulate {
            return ConfiguratorResetModel(
                home: home,
                executor: MockConfiguratorExecutor(running: false),
                simulationOnly: true)
        }
        return ConfiguratorResetModel(
            home: home,
            executor: LiveConfiguratorProcessExecutor(),
            simulationOnly: false)
    }
}

struct ConfiguratorSettingsView: View {
    @ObservedObject var model: ConfiguratorResetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("Apple Configurator"))
                .font(.system(size: 15, weight: .semibold))
            Text(L10n.t("主界面按钮行为"))
                .font(.system(size: 12, weight: .medium))
            HStack {
                Text(L10n.t("重置级别"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(L10n.t("最高级别 · 默认"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            Picker("", selection: Binding(
                get: { model.preferredAction },
                set: { model.setPreferredAction($0) }
            )) {
        Text(L10n.t("安全深度重置 Configurator"))
                    .tag(ConfiguratorPanelChoice.ownerQuickReset)
                Text(L10n.t("仅重新打开 Configurator")).tag(ConfiguratorPanelChoice.reopenOnly)
                Text(L10n.t("清理缓存并重启 Configurator")).tag(ConfiguratorPanelChoice.cleanAndRestart)
            }
            .pickerStyle(.radioGroup)
            Text(L10n.t(model.preferredActionSummary))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.t("默认选择安全深度重置；修改设置本身不会执行操作。"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
    }
}

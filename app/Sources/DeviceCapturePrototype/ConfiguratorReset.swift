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
}

struct ConfiguratorStepResult: Equatable, Identifiable {
    var id: String { name }
    var name: String
    var succeeded: Bool
    var detail: String
}

enum ConfiguratorResetAction: Equatable {
    case reopen
    case cleanAndReset
}

protocol ConfiguratorProcessExecuting {
    func isRunning(processName: String) -> Bool
    func quit(processName: String) throws
    func openApplication(at url: URL) throws
    func bringToFront(processName: String) throws
}

protocol ConfiguratorFileOperating {
    func fileExists(atPath path: String) -> Bool
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

    func bringToFront(processName: String) throws {
        _ = processName
        // Opening with activates=true already brings the app forward when it launches.
    }
}

struct FoundationConfiguratorFileOperating: ConfiguratorFileOperating {
    let fileManager: FileManager
    init(fileManager: FileManager = .default) { self.fileManager = fileManager }
    func fileExists(atPath path: String) -> Bool { fileManager.fileExists(atPath: path) }
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

    func openApplication(at url: URL) throws {
        openCount += 1
        openedURL = url
        if openShouldFail {
            throw NSError(domain: "ConfiguratorReset", code: 12,
                          userInfo: [NSLocalizedDescriptionKey: "模拟：打开失败"])
        }
        running = true
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

    /// Verified, exact paths relative to a home directory. No wildcards.
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
                displayName: "Application Support · Apple Configurator（旧路径，仅在存在时列出）"),
            ConfiguratorTargetPath(
                path: homePath + "/Library/Application Support/Apple/Apple Configurator 2",
                kind: .applicationSupport,
                displayName: "Application Support · Apple Configurator 2（旧路径，仅在存在时列出）"),
        ]
    }
}

enum ConfiguratorPanelChoice: String, Equatable, CaseIterable {
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

    static let preferenceKey = "MRA.configuratorMainAction"

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
            self.preferredAction = .cleanAndRestart
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
        case .cleanAndRestart: return L10n.t("清理并重启 Configurator")
        case .reopenOnly: return L10n.t("重新打开 Configurator")
        }
    }

    var cleanScopeSummary: String {
        "仅清理已存在的 Caches；Application Support 默认保留。"
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

    var cleanScopeTitle: String { "清理并重启 Configurator" }
    var reopenChoiceTitle: String { "仅重新打开 Configurator" }
    var reopenChoiceNote: String { "保留缓存和用户数据" }

    var executeButtonTitle: String {
        switch panelChoice {
        case .cleanAndRestart: return "清理并重启"
        case .reopenOnly: return "重新打开"
        }
    }

    /// Paths this run will clean when 「清理并重启」is executed with default options.
    /// Application Support is never included unless the user also opts in.
    var defaultCleanTargetsThisRun: [ConfiguratorTargetPath] {
        let knownCaches = ConfiguratorKnownLocations.candidatePaths(home: home).filter { $0.kind == .caches }
        let existing = cacheTargets
        return existing.isEmpty ? knownCaches : existing
    }

    var listsExistingCachesOnly: Bool { !cacheTargets.isEmpty }

    func preparePanelDefaults() {
        panelChoice = .cleanAndRestart
        includeApplicationSupport = false
        stepResults = []
        overallMessage = ""
        lastBackupURL = nil
    }

    func executeSelectedPanelAction() {
        switch panelChoice {
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
        ConfiguratorKnownLocations.candidatePaths(home: home).filter { files.fileExists(atPath: $0.path) }
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
        let quitOK = runStep(name: "退出") {
            if executor.isRunning(processName: processName) {
                try executor.quit(processName: processName)
                return "已请求退出 \(processName)"
            }
            return "当时未在运行，无需退出"
        }
        guard quitOK else {
            overallMessage = "重新打开未完成：退出步骤失败。未清理数据，也不会把这次结果写成全部完成。"
            return
        }
        let openOK = runStep(name: "重新打开") {
            try executor.openApplication(at: appURL)
            return "已请求打开 \(appURL.path)"
        }
        let frontOK = runStep(name: "置前") {
            try executor.bringToFront(processName: processName)
            return "已请求置前"
        }
        if openOK && frontOK {
            overallMessage = "已重新打开 Apple Configurator。未清理数据，也未重置 USB。"
        } else {
            overallMessage = "重新打开未全部成功。未清理数据，也未重置 USB。"
        }
    }

    func performCleanAndReset() {
        guard !isBusy else { return }
        isBusy = true
        stepResults = []
        lastBackupURL = nil
        overallMessage = ""
        defer { isBusy = false }

        let quitOK = runStep(name: "退出") {
            if executor.isRunning(processName: processName) {
                try executor.quit(processName: processName)
                return "已请求退出 \(processName)"
            }
            return "当时未在运行，无需退出"
        }
        guard quitOK else {
            overallMessage = "清理未执行：退出步骤失败。不会在失败后继续删除文件，也不会把这次结果写成全部完成。"
            return
        }

        if includeApplicationSupport {
            let backupOK = runStep(name: "备份 Application Support") {
                let targets = applicationSupportTargets
                if targets.isEmpty {
                    return "当前没有已存在的 Application Support 目录需要备份"
                }
                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
                let backupRoot = home.appendingPathComponent("MRA_Configurator_Backups/\(stamp)", isDirectory: true)
                try files.createDirectory(at: backupRoot)
                for target in targets {
                    let src = URL(fileURLWithPath: target.path)
                    let dst = backupRoot.appendingPathComponent(src.lastPathComponent, isDirectory: true)
                    try files.copyItem(at: src, to: dst)
                }
                lastBackupURL = backupRoot
                return "已保留可恢复副本：\(backupRoot.path)"
            }
            guard backupOK else {
                overallMessage = "已取消清理：Application Support 备份失败，未删除任何目录。"
                return
            }
        }

        let cleanupOK = runStep(name: "清理") {
            var removed: [String] = []
            var missing: [String] = []
            for target in cacheTargets {
                if files.fileExists(atPath: target.path) {
                    try files.removeItem(at: URL(fileURLWithPath: target.path))
                    removed.append("Caches：\(target.path)")
                } else {
                    missing.append(target.path)
                }
            }
            if includeApplicationSupport {
                for target in applicationSupportTargets {
                    if files.fileExists(atPath: target.path) {
                        try files.removeItem(at: URL(fileURLWithPath: target.path))
                        removed.append("Application Support：\(target.path)")
                    } else {
                        missing.append(target.path)
                    }
                }
            }
            var text = removed.isEmpty ? "没有需要删除的已存在目录" : "已删除：\n" + removed.joined(separator: "\n")
            if !includeApplicationSupport && !applicationSupportTargets.isEmpty {
                text += "\nApplication Support 已按默认保留，未删除。"
            }
            if !missing.isEmpty {
                text += "\n当时不存在、未删除：\n" + missing.joined(separator: "\n")
            }
            return text
        }
        guard cleanupOK else {
            overallMessage = "清理步骤失败。未重置 USB。请查看分步结果；不声称全部成功。"
            // Still try to reopen so the host app is not left quit if possible.
            _ = runStep(name: "重新打开") {
                try executor.openApplication(at: appURL)
                return "清理失败后仍尝试重新打开"
            }
            _ = runStep(name: "置前") {
                try executor.bringToFront(processName: processName)
                return "已请求置前"
            }
            return
        }

        let openOK = runStep(name: "重新打开") {
            try executor.openApplication(at: appURL)
            return "已请求打开 \(appURL.path)"
        }
        let frontOK = runStep(name: "置前") {
            try executor.bringToFront(processName: processName)
            return "已请求置前"
        }
        if cleanupOK && openOK && frontOK {
            if includeApplicationSupport {
                overallMessage = "清理与重新打开已完成。Application Support 已按你的明确选择处理，并已先保留副本。未重置 USB。"
            } else {
                overallMessage = "已清理 Caches 并重新打开。Application Support 未改动。未重置 USB。"
            }
        } else {
            overallMessage = "清理或重新打开未全部成功。未重置 USB。请查看分步结果。"
        }
    }

    @discardableResult
    private func runStep(name: String, work: () throws -> String) -> Bool {
        do {
            let detail = try work()
            stepResults.append(ConfiguratorStepResult(name: name, succeeded: true, detail: detail))
            return true
        } catch {
            stepResults.append(ConfiguratorStepResult(name: name, succeeded: false, detail: error.localizedDescription))
            return false
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
                        Toggle(L10n.t("同时重置 Application Support（将先保留可恢复副本）"), isOn: $model.includeApplicationSupport)
                            .font(.system(size: 12))
                    }
                }
                choiceRow(.reopenOnly, title: L10n.t(model.reopenChoiceTitle)) {
                    Text(L10n.t(model.reopenChoiceNote))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
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
                                Text("\(L10n.t(step.name))：\(step.succeeded ? L10n.t("成功") : L10n.t("失败"))")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(step.succeeded ? Color.primary : Color.red)
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
            Picker("", selection: Binding(
                get: { model.preferredAction },
                set: { model.setPreferredAction($0) }
            )) {
                Text(L10n.t("仅重新打开 Configurator")).tag(ConfiguratorPanelChoice.reopenOnly)
                Text(L10n.t("清理并重启 Configurator")).tag(ConfiguratorPanelChoice.cleanAndRestart)
            }
            .pickerStyle(.radioGroup)
            Text(L10n.t(model.cleanScopeSummary))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.t("选择后立即保存；修改设置本身不会执行操作。"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
    }
}

import Foundation
import Combine

struct HelperDestinations: Equatable {
    var helper: URL
    var backend: URL
    var plist: URL
    var socket: URL
    var logDirectory: URL
    var packageDirectory: URL

    static var system: HelperDestinations {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MRA Device Control", isDirectory: true)
        // Distribution packages carry the management scripts inside the App.
        // Fall back to the folder next to the App for older/test packages.
        let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("helper-management", isDirectory: true)
        let packageDirectory: URL
        if let bundled, FileManager.default.fileExists(atPath: bundled.path) {
            packageDirectory = bundled
        } else {
            packageDirectory = Bundle.main.bundleURL.deletingLastPathComponent()
        }
        return HelperDestinations(
            helper: URL(fileURLWithPath: "/Library/PrivilegedHelperTools/com.mra.devicecontrol.helper"),
            backend: URL(fileURLWithPath: "/Library/PrivilegedHelperTools/com.mra.direct_rid_dfu"),
            plist: URL(fileURLWithPath: "/Library/LaunchDaemons/com.mra.devicecontrol.helper.plist"),
            socket: URL(fileURLWithPath: "/var/run/com.mra.devicecontrol.helper.sock"),
            logDirectory: logs,
            packageDirectory: packageDirectory)
    }
}

struct CommandSpec: Equatable {
    var executable: URL
    var arguments: [String]
    var environment: [String: String]
    var requiresAdmin: Bool
}

struct CommandResult: Equatable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

protocol HelperCommandExecutor {
    func run(_ spec: CommandSpec) throws -> CommandResult
}

enum HelperCommandExecutorError: Error, LocalizedError {
    case missingMock
    var errorDescription: String? { "测试缺少命令替身，已拒绝回退真实系统命令。" }
}

/// Production executor. Tests must not use this type.
///
/// Management scripts touch /Library and launchd. Running them directly from
/// the GUI let the script's own `sudo` fail silently (no TTY). For admin work
/// we hand the exact command to `osascript do shell script … with administrator
/// privileges`, which presents the standard macOS authorization dialog to the
/// user. Non-admin commands still run directly.
struct ProcessHelperCommandExecutor: HelperCommandExecutor {
    func run(_ spec: CommandSpec) throws -> CommandResult {
        if spec.requiresAdmin {
            return try runWithAdministrator(spec)
        }
        let process = Process()
        process.executableURL = spec.executable
        process.arguments = spec.arguments
        var env = ProcessInfo.processInfo.environment
        for (k, v) in spec.environment { env[k] = v }
        process.environment = env
        let out = Pipe(); let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private func runWithAdministrator(_ spec: CommandSpec) throws -> CommandResult {
        let env = spec.environment
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(shellQuote($0.value))" }
            .joined(separator: " ")
        let arguments = spec.arguments.map(shellQuote).joined(separator: " ")
        let command = "\(env.isEmpty ? "" : env + " ") /usr/bin/env /bin/bash \(shellQuote(spec.executable.path))\(arguments.isEmpty ? "" : " " + arguments)"
        let script = "do shell script \(appleScriptString(command)) with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let out = Pipe(); let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

final class MockHelperCommandExecutor: HelperCommandExecutor {
    var runs: [CommandSpec] = []
    var handler: (CommandSpec) throws -> CommandResult = { _ in
        CommandResult(exitCode: 0, stdout: "MOCK_OK", stderr: "")
    }
    func run(_ spec: CommandSpec) throws -> CommandResult {
        runs.append(spec)
        return try handler(spec)
    }
}

struct HelperFileInfo: Equatable {
    var path: String
    var exists: Bool
    var sha256: String?
    var classification: HelperPayloadClass
    var teamIdentifier: String?
    var signatureStatus: String
}

enum HelperEnvironmentKind: String, Equatable {
    case notInstalled
    case currentHealthy
    case currentUnhealthy
    case knownLegacy
    case backendNeedsUpdate
    case unknown
    case mixedKnown
    case detectFailed
}

enum HelperManagementAction: String, Equatable {
    case install
    case repair
    case upgrade
    case uninstall
    case redetect
}

struct HelperEnvironmentSnapshot: Equatable {
    var kind: HelperEnvironmentKind
    var statusLine: String
    var statusColor: String // gray / green / orange / yellow / red
    var detailLines: [String]
    var allowedActions: [HelperManagementAction]
    var macosVersion: String
    var architecture: String
    var appMinOS: String
    var osCompatibility: String
    var helperVersion: String
    var socketState: String
    var serviceState: String
    var detectionError: String?

    /// Compact home-row wording. Healthy install uses the Owner-facing "Helper 已连接".
    var homeStatusText: String {
        switch kind {
        case .currentHealthy: return "Helper 已连接"
        case .notInstalled: return "Helper 未安装"
        case .currentUnhealthy: return "Helper 已安装，服务异常"
        case .knownLegacy: return "Helper 已安装已知旧版"
        case .backendNeedsUpdate: return "Helper · 后端待更新"
        case .unknown: return "Helper 状态未知"
        case .mixedKnown: return "Helper 文件不完整"
        case .detectFailed:
            return statusLine.hasPrefix("Helper") ? statusLine : "Helper · \(statusLine)"
        }
    }
}

enum HelperManagementPresentation {
    /// Install / repair / upgrade stay primary.
    /// When Helper is installed and is the current manageable version, Uninstall
    /// is also primary so the settings page can show 「卸载 Helper…」 directly.
    /// Uninstall is never mixed with Install.
    static func primaryActions(from allowed: [HelperManagementAction]) -> [HelperManagementAction] {
        var actions = allowed.filter { $0 == .install || $0 == .repair || $0 == .upgrade }
        if allowed.contains(.uninstall) && !allowed.contains(.install) {
            actions.append(.uninstall)
        }
        return actions
    }

    /// No management action is hidden under a secondary disclosure when Uninstall
    /// is a valid primary action. Install still suppresses Uninstall entirely.
    static func secondaryActions(from allowed: [HelperManagementAction]) -> [HelperManagementAction] {
        _ = allowed
        return []
    }
}

protocol HelperEnvironmentIO {
    func fileExists(at url: URL) -> Bool
    func sha256(of url: URL) throws -> String
    func teamIdentifier(of url: URL) -> String?
    func codesignVerify(of url: URL) -> String
    func launchctlPrint(label: String) -> String
    func socketListening(at url: URL) -> Bool
    func macosVersion() -> String
    func architecture() -> String
    func appMinOS() -> String
}

struct LiveHelperEnvironmentIO: HelperEnvironmentIO {
    func fileExists(at url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    func sha256(of url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256", url.path]
        let out = Pipe(); process.standardOutput = out; process.standardError = Pipe()
        try process.run(); process.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return text.split(separator: " ").first.map(String.init) ?? ""
    }
    func teamIdentifier(of url: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=4", url.path]
        let err = Pipe(); process.standardOutput = Pipe(); process.standardError = err
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        let text = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in text.split(separator: "\n") {
            if line.hasPrefix("TeamIdentifier=") {
                return String(line.dropFirst("TeamIdentifier=".count))
            }
        }
        return nil
    }
    func codesignVerify(of url: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--strict", url.path]
        process.standardOutput = Pipe(); process.standardError = Pipe()
        do { try process.run() } catch { return "未验证" }
        process.waitUntilExit()
        return process.terminationStatus == 0 ? "签名有效" : "签名校验未通过"
    }
    func launchctlPrint(label: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/\(label)"]
        let out = Pipe(); let err = Pipe()
        process.standardOutput = out; process.standardError = err
        do { try process.run() } catch { return "未获取" }
        process.waitUntilExit()
        let text = (String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            + (String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        return text
    }
    func socketListening(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
    func macosVersion() -> String { ProcessInfo.processInfo.operatingSystemVersionString }
    func architecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "未获取"
        #endif
    }
    func appMinOS() -> String {
        Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String ?? "未获取"
    }
}

final class MockHelperEnvironmentIO: HelperEnvironmentIO {
    var files: [String: (sha: String, team: String?, signature: String)] = [:]
    var launchctl = ""
    var socketIsListening = false
    var macos = "macOS 27.3"
    var arch = "arm64"
    var minOS = "27.2"
    func fileExists(at url: URL) -> Bool { files[url.path] != nil }
    func sha256(of url: URL) throws -> String {
        guard let f = files[url.path] else { throw NSError(domain: "mock", code: 1) }
        return f.sha
    }
    func teamIdentifier(of url: URL) -> String? { files[url.path]?.team }
    func codesignVerify(of url: URL) -> String { files[url.path]?.signature ?? "未验证" }
    func launchctlPrint(label: String) -> String { launchctl }
    func socketListening(at url: URL) -> Bool { socketIsListening }
    func macosVersion() -> String { macos }
    func architecture() -> String { arch }
    func appMinOS() -> String { minOS }
}

@MainActor
final class HelperEnvironmentModel: ObservableObject {
    @Published var snapshot: HelperEnvironmentSnapshot
    @Published var lastLog: String = ""
    @Published var isBusy: Bool = false
    @Published var managementMessage: String = ""

    let destinations: HelperDestinations
    private let io: HelperEnvironmentIO
    private let executor: HelperCommandExecutor?
    private let requireExecutor: Bool
    private var lastDetectAt: Date?

    init(destinations: HelperDestinations,
         io: HelperEnvironmentIO,
         executor: HelperCommandExecutor? = nil,
         requireExecutor: Bool = false) {
        self.destinations = destinations
        self.io = io
        self.executor = executor
        self.requireExecutor = requireExecutor
        self.snapshot = Self.blankSnapshot()
    }

    static func blankSnapshot() -> HelperEnvironmentSnapshot {
        HelperEnvironmentSnapshot(
            kind: .detectFailed,
            statusLine: "未检测",
            statusColor: "gray",
            detailLines: [],
            allowedActions: [.redetect],
            macosVersion: "未获取",
            architecture: "未获取",
            appMinOS: "未获取",
            osCompatibility: "未验证",
            helperVersion: "未获取",
            socketState: "未获取",
            serviceState: "未获取",
            detectionError: nil)
    }

    func redetect() {
        snapshot = detect()
        lastDetectAt = Date()
    }

    func detect() -> HelperEnvironmentSnapshot {
        let macosRaw = io.macosVersion()
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let buildToken = macosRaw.range(of: "[0-9]{2}[A-Za-z][0-9]{4,}[A-Za-z]?", options: .regularExpression).map { String(macosRaw[$0]) } ?? ""
        let macos = "\(osVersion.majorVersion).\(osVersion.minorVersion)" + (buildToken.isEmpty ? "" : " (Build \(buildToken))")
        let arch = io.architecture()
        let minOS = io.appMinOS()
        let compatible: String
        if minOS == "未获取" {
            compatible = "未验证"
        } else {
            compatible = L10n.helperCompatibility(minOS: minOS)
        }

        let helperInfo = inspect(url: destinations.helper, isHelper: true)
        let backendInfo = inspect(url: destinations.backend, isHelper: false)
        let plistInfo = inspectPlist()
        let serviceText = io.launchctlPrint(label: "com.mra.devicecontrol.helper")
        let servicePresent = serviceText.contains("pid =") || serviceText.contains("state =")
            || (!serviceText.contains("未获取") && !serviceText.lowercased().contains("could not find") && !serviceText.contains("Does Not Exist") && !serviceText.isEmpty && !serviceText.contains("Could not find service"))
        let serviceOK = servicePresent && !serviceText.lowercased().contains("does not exist") && !serviceText.contains("Could not find service")
        let socketOK = io.socketListening(at: destinations.socket)

        var details: [String] = []
        details.append("macOS：\(macos)")
        details.append("架构：\(arch)")
        details.append("App minOS：\(minOS)")
        details.append("系统兼容：\(compatible)")
        details.append("Helper 文件：\(describe(helperInfo))")
        details.append("backend 文件：\(describe(backendInfo))")
        details.append("plist：\(describe(plistInfo))")
        details.append("服务：\(serviceOK ? "已登记/可读取" : (serviceText.contains("未获取") ? "未获取" : "未运行或未登记"))")
        details.append("socket：\(socketOK ? "存在" : "未监听/不存在")")
        if helperInfo.teamIdentifier != nil {
            details.append("TeamIdentifier：\(helperInfo.teamIdentifier!)")
        } else if helperInfo.exists {
            details.append("TeamIdentifier：未获取")
        }

        let kind: HelperEnvironmentKind
        let actions: [HelperManagementAction]
        let line: String
        let color: String
        var error: String? = nil

        let present = [helperInfo, backendInfo, plistInfo].filter(\.exists)
        let unknownPresent = present.contains { file in
            if file.path == destinations.plist.path {
                return file.classification == .unknown
            }
            return file.classification == .unknown
        }

        if present.isEmpty {
            kind = .notInstalled
            actions = [.install, .redetect]
            line = "未安装 Helper"
            color = "gray"
        } else if unknownPresent {
            kind = .unknown
            actions = [.redetect]
            line = "发现未知 Helper 文件，未提供覆盖或删除"
            color = "red"
            details.append("未知文件仅可检测，不会覆盖或删除。")
        } else {
            let helperClass = helperInfo.exists ? helperInfo.classification : .missing
            let backendKnownLegacy = backendInfo.exists && KnownHelperManifest.knownLegacyBackendSHA256.contains(backendInfo.sha256 ?? "")
            let plistCurrent = plistInfo.exists && plistInfo.sha256 == KnownHelperManifest.expectedCurrentPlistSHA256
            let allKnownCurrent = present.allSatisfy { info in
                if info.path == destinations.helper.path { return info.classification == .current }
                if info.path == destinations.backend.path { return info.classification == .current || info.sha256 == KnownHelperManifest.expectedCurrentBackendSHA256 }
                if info.path == destinations.plist.path { return info.sha256 == KnownHelperManifest.expectedCurrentPlistSHA256 }
                return false
            }
            let helperLegacy = helperClass == .knownLegacy

            if helperClass == .current && backendKnownLegacy && plistCurrent {
                // The Helper itself is current and the plist is current, but
                // the installed backend is a known older payload. Do not
                // collapse this into "检测未完成" or "all latest".
                kind = .backendNeedsUpdate
                actions = [.upgrade, .redetect]
                line = "已安装 · 后端待更新"
                color = "orange"
                details.append("Helper 本体与 plist 为当前版本；backend 为已知旧版，需要升级。")
            } else if helperLegacy {
                // A known-legacy helper is an upgrade case even if companion
                // backend/plist already match the current payloads.
                kind = .knownLegacy
                actions = [.upgrade, .uninstall, .redetect]
                line = "已安装已知旧版 Helper"
                color = "yellow"
            } else if allKnownCurrent && helperInfo.exists && backendInfo.exists && plistInfo.exists {
                if serviceOK && socketOK {
                    kind = .currentHealthy
                    actions = [.redetect, .uninstall]
                    line = "已安装 · 已连接"
                    color = "green"
                } else {
                    kind = .currentUnhealthy
                    actions = [.repair, .redetect]
                    line = "当前载荷已安装，但服务或 socket 异常"
                    color = "orange"
                }
            } else if present.count < 3, present.allSatisfy({ $0.classification == .current || ($0.path == destinations.plist.path && $0.sha256 == KnownHelperManifest.expectedCurrentPlistSHA256) || ($0.path == destinations.backend.path && $0.sha256 == KnownHelperManifest.expectedCurrentBackendSHA256) || $0.classification == .knownLegacy }) {
                kind = .mixedKnown
                actions = [.repair, .redetect]
                line = "部分文件缺失（已知范围）"
                color = "orange"
            } else {
                kind = .detectFailed
                actions = [.redetect]
                line = "检测未完成"
                color = "gray"
                error = "无法完整归类当前安装"
            }
        }

        return HelperEnvironmentSnapshot(
            kind: kind,
            statusLine: line,
            statusColor: color,
            detailLines: details,
            allowedActions: actions,
            macosVersion: macos,
            architecture: arch,
            appMinOS: minOS,
            osCompatibility: compatible,
            helperVersion: helperInfo.exists ? (helperInfo.classification == .current ? "与内嵌 T1306Z 载荷匹配" : helperInfo.classification.rawValue) : "未安装",
            socketState: socketOK ? "存在" : "未监听/不存在",
            serviceState: serviceOK ? "已登记/可读取" : "未运行或未登记",
            detectionError: error)
    }

    private func classifyBackend(_ info: HelperFileInfo) -> HelperPayloadClass {
        guard let sha = info.sha256 else { return .missing }
        if sha == KnownHelperManifest.expectedCurrentBackendSHA256 { return .current }
        if KnownHelperManifest.knownLegacyBackendSHA256.contains(sha) { return .knownLegacy }
        return info.classification
    }

    private func inspect(url: URL, isHelper: Bool) -> HelperFileInfo {
        guard io.fileExists(at: url) else {
            return HelperFileInfo(path: url.path, exists: false, sha256: nil, classification: .missing, teamIdentifier: nil, signatureStatus: "未获取")
        }
        let sha = try? io.sha256(of: url)
        let classification: HelperPayloadClass
        if isHelper {
            classification = KnownHelperManifest.classifyHelper(sha256: sha)
        } else if sha == KnownHelperManifest.expectedCurrentBackendSHA256 {
            classification = .current
        } else if let sha, KnownHelperManifest.knownLegacyBackendSHA256.contains(sha) {
            classification = .knownLegacy
        } else if sha == nil {
            classification = .missing
        } else {
            classification = .unknown
        }
        return HelperFileInfo(path: url.path, exists: true, sha256: sha, classification: classification,
                              teamIdentifier: io.teamIdentifier(of: url),
                              signatureStatus: io.codesignVerify(of: url))
    }

    private func inspectPlist() -> HelperFileInfo {
        let url = destinations.plist
        guard io.fileExists(at: url) else {
            return HelperFileInfo(path: url.path, exists: false, sha256: nil, classification: .missing, teamIdentifier: nil, signatureStatus: "N/A")
        }
        let sha = try? io.sha256(of: url)
        let classification: HelperPayloadClass
        if sha == KnownHelperManifest.expectedCurrentPlistSHA256 {
            classification = .current
        } else if sha == nil {
            classification = .missing
        } else {
            // Plist may match a known pairing; only the exact T1306Z plist is "current".
            // Any other hash is treated as unknown so we never delete or overwrite it.
            classification = .unknown
        }
        return HelperFileInfo(path: url.path, exists: true, sha256: sha, classification: classification,
                              teamIdentifier: nil, signatureStatus: "N/A")
    }

    private func describe(_ info: HelperFileInfo) -> String {
        if !info.exists { return "不存在" }
        let hash = info.sha256.map { String($0.prefix(12)) + "…" } ?? "未获取"
        return "\(info.classification.rawValue) · \(hash) · \(info.signatureStatus)"
    }

    func perform(_ action: HelperManagementAction, quarantineConfirmed: Bool = false) {
        guard !isBusy else {
            managementMessage = "已有管理操作进行中。"
            return
        }
        if action == .redetect {
            redetect()
            return
        }
        guard snapshot.allowedActions.contains(action) else {
            managementMessage = "当前状态不提供该管理动作。"
            return
        }
        // The uninstall script performs its own stop/wait/rollback. Do not
        // refuse here just because the service or socket is still live.
        if !quarantineConfirmed && (action == .install || action == .repair || action == .upgrade) {
            // Caller must pass quarantineConfirmed after an explicit user confirmation
            // when a quarantine attribute is present. The test suite uses this flag.
        }
        guard let executor else {
            if requireExecutor {
                managementMessage = HelperCommandExecutorError.missingMock.localizedDescription
                return
            }
            managementMessage = "未配置命令执行器。"
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let scriptName: String
            switch action {
            case .install, .repair, .upgrade: scriptName = "install-mra-device-control.sh"
            case .uninstall: scriptName = "uninstall-mra-device-control.sh"
            case .redetect: return
            }
            let script = destinations.packageDirectory.appendingPathComponent(scriptName)
            var env: [String: String] = [
                "HELPER_DST": destinations.helper.path,
                "BACKEND_DST": destinations.backend.path,
                "PLIST_DST": destinations.plist.path,
                "SOCKET": destinations.socket.path,
                "RECORD_DIR": destinations.logDirectory.path,
                "MRA_APP_DIR": Bundle.main.bundleURL.path,
            ]
            if quarantineConfirmed {
                // The user already confirmed the quarantine prompt in the App.
                // The script's non-TTY path requires this exact value.
                env["MRA_QUARANTINE_CONFIRM"] = "yes"
            } else {
                env["MRA_REQUIRE_QUARANTINE_CONFIRM"] = "1"
            }
            let spec = CommandSpec(executable: script, arguments: [], environment: env, requiresAdmin: true)
            try FileManager.default.createDirectory(at: destinations.logDirectory, withIntermediateDirectories: true)
            let result = try executor.run(spec)
            lastLog = result.stdout + result.stderr
            let logFile = destinations.logDirectory.appendingPathComponent("helper-management.log")
            try? lastLog.data(using: .utf8)?.write(to: logFile, options: .atomic)
            if result.exitCode == 0 {
                managementMessage = "管理命令已完成。"
            } else {
                let tail = lastLog
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .suffix(4)
                    .joined(separator: "\n")
                managementMessage = "管理命令失败（exit \(result.exitCode)）。未自动重试。"
                    + (tail.isEmpty ? "" : "\n\(tail)")
            }
            redetect()
        } catch {
            managementMessage = "管理命令失败：\(error.localizedDescription)"
        }
    }
}

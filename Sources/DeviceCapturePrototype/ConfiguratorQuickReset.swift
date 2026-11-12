import Foundation
import AppKit
import MRAHelperProtocol

/// Exact command sequence from the Owner's desktop 「重置刷机软件.app」
/// (`main.scpt`). Do not add, remove, or reorder steps here.
struct ConfiguratorQuickResetCommand: Equatable {
    var name: String
    var shell: String
    var requiresAdministrator: Bool
}

@MainActor
final class ConfiguratorQuickReset: ObservableObject {
    struct StepResult: Identifiable, Equatable {
        var id: String { name }
        var name: String
        var succeeded: Bool
        var detail: String
    }

    /// Verbatim from the Owner app:
    /// killall 'Apple Configurator'; delay 1; rm Caches; rm Application Support;
    /// sudo killall -STOP -c usbd (administrator); delay 2; activate twice.
    static let commands: [ConfiguratorQuickResetCommand] = [
        ConfiguratorQuickResetCommand(
            name: "退出 Apple Configurator",
            shell: "killall 'Apple Configurator' 2>/dev/null || true",
            requiresAdministrator: false),
        ConfiguratorQuickResetCommand(
            name: "清理 Caches",
            shell: "rm -rf ~/Library/Caches/com.apple.AppleConfigurator* 2>/dev/null || true",
            requiresAdministrator: false),
        ConfiguratorQuickResetCommand(
            name: "清理 Application Support",
            shell: "rm -rf ~/Library/Application\\ Support/Apple/Apple\\ Configurator* 2>/dev/null || true",
            requiresAdministrator: false),
        ConfiguratorQuickResetCommand(
            name: "USB 重置",
            shell: "sudo killall -STOP -c usbd 2>/dev/null || true",
            requiresAdministrator: true),
    ]

    @Published private(set) var isRunning = false
    @Published private(set) var steps: [StepResult] = []
    @Published private(set) var message = ""

    /// Runs the Owner's exact sequence. The only administrator prompt is for
    /// the usbd step; it uses the same macOS authorization as Helper management.
    func run() async {
        guard !isRunning else { return }
        isRunning = true
        steps = []
        message = ""
        defer { isRunning = false }

        var failure: String?
        for (index, command) in Self.commands.enumerated() {
            let result: CommandResult
            do {
                result = command.requiresAdministrator
                    ? try await runUsbdViaHelper()
                    : try runShell(command.shell)
            } catch {
                steps.append(StepResult(name: command.name, succeeded: false,
                                        detail: error.localizedDescription))
                failure = "\(command.name)失败：\(error.localizedDescription)"
                break
            }
            let ok = result.exitCode == 0
            steps.append(StepResult(name: command.name, succeeded: ok,
                                    detail: ok ? (result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "完成" : result.stdout)
                                               : result.stderr))
            if !ok {
                failure = "\(command.name)失败：\(result.stderr)"
                break
            }
            if index == 0 { try? await Task.sleep(nanoseconds: 1_000_000_000) }
            if command.requiresAdministrator { try? await Task.sleep(nanoseconds: 2_000_000_000) }
        }

        // Even when a middle step fails (for example an old Helper without
        // resetUsbd), never leave Apple Configurator closed. Reopen and bring
        // it to the front, then report the failure honestly.
        let reopened = await reopenAppleConfigurator()
        if let failure {
            message = "重置未完成：\(failure)" + (reopened
                ? "；已重新打开 Apple Configurator。"
                : "；重新打开 Apple Configurator 也失败。")
            return
        }
        message = reopened
            ? "已完成：清理缓存 + USB重置 + 重启置顶"
            : "清理和 USB 重置已完成，但重新打开 Apple Configurator 失败。"
    }

    /// open -a → wait for the process → activate/置前, twice like the Owner
    /// script. Returns whether Apple Configurator is actually running/fronted.
    private func reopenAppleConfigurator() async -> Bool {
        var opened = false
        for attempt in 0..<2 {
            if let result = try? runShell("/usr/bin/open -a \"Apple Configurator\""),
               result.exitCode == 0 {
                opened = true
                break
            }
            if attempt == 0 { try? await Task.sleep(nanoseconds: 500_000_000) }
        }
        if !opened {
            if let result = try? runShell("/usr/bin/open -b com.apple.configurator.ui"),
               result.exitCode == 0 {
                opened = true
            }
        }
        guard opened else { return false }

        for _ in 0..<20 {
            if appleConfiguratorRunning() { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard appleConfiguratorRunning() else { return false }

        _ = try? runShell("/usr/bin/osascript -e 'tell application \"Apple Configurator\" to activate'")
        try? await Task.sleep(nanoseconds: 500_000_000)
        _ = try? runShell("/usr/bin/osascript -e 'tell application \"Apple Configurator\" to activate'")
        return appleConfiguratorRunning()
    }

    private func appleConfiguratorRunning() -> Bool {
        guard let result = try? runShell("/usr/bin/pgrep -x 'Apple Configurator' >/dev/null 2>&1") else {
            return false
        }
        return result.exitCode == 0
    }

    private struct CommandResult {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    private func runShell(_ command: String) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let out = Pipe(); let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
    }

    /// Fixed root action on the installed Helper. No per-click password.
    /// The Helper must expose 0.2.4 `resetUsbd`; older Helpers fail closed with
    /// an update message instead of falling back to an admin prompt.
    private func runUsbdViaHelper() async throws -> CommandResult {
        let status = await HelperClient().request(action: .status)
        guard status.ok else {
            throw NSError(domain: "ConfiguratorQuickReset", code: 20,
                          userInfo: [NSLocalizedDescriptionKey: "Helper 不可用（\(status.reason)）。请先在设置 → Helper 安装或更新。"])
        }
        guard status.helperVersion == mraHelperVersion else {
            throw NSError(domain: "ConfiguratorQuickReset", code: 21,
                          userInfo: [NSLocalizedDescriptionKey: "Helper 版本过旧（\(status.helperVersion)），请在设置 → Helper 升级到 \(mraHelperVersion)；升级只需一次管理员授权，之后重置不再输密码。"])
        }
        let response = await HelperClient().request(action: .resetUsbd)
        guard response.ok else {
            throw NSError(domain: "ConfiguratorQuickReset", code: 22,
                          userInfo: [NSLocalizedDescriptionKey: "Helper 执行 USB 重置失败：\(response.reason)"])
        }
        return CommandResult(exitCode: 0, stdout: response.stdout, stderr: response.stderr)
    }
}

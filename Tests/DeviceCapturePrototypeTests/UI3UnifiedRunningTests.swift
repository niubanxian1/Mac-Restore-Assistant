import XCTest
@testable import DeviceCapturePrototype

/// UI-3：统一 A/B 运行态、实时预览与终态的源码/契约守卫。
final class UI3UnifiedRunningTests: XCTestCase {
    private func read(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relative),
            encoding: .utf8)
    }

    private func source() throws -> String {
        try read("Sources/DeviceCapturePrototype/FirmwareRestoreWorkspaceView.swift")
    }

    func testUnifiedWorkspaceIsSharedByPrimaryAndSecondary() throws {
        let content = try source()
        XCTAssertTrue(content.contains("private func secondaryLiveLayout("))
        XCTAssertTrue(content.contains("ui3TaskWorkspace(task)"))
        XCTAssertTrue(content.contains("ui3TaskWorkspace(finished)"))
        XCTAssertTrue(content.contains("accessibilityIdentifier(\"secondary-live-task\")"))
    }

    func testFiveBandsExistWithoutFiveCards() throws {
        let content = try source()
        for token in [
            "ui3IdentityHeader", "ui3ProgressAndControls",
            "UI3LiveLogView", "ui3TerminalOutcome", "ui3TaskWorkspace"
        ] {
            XCTAssertTrue(content.contains(token), "missing \(token)")
        }
        XCTAssertTrue(content.contains("if !isTerminal {"))
        XCTAssertTrue(content.contains("if let outcome = task.outcome {"))
    }

    func testLiveLogReadsThePassedTaskOnly() throws {
        let content = try source()
        let childStart = content.range(of: "private struct UI3LiveLogView")!.lowerBound
        let child = String(content[childStart...])
        let end = child.range(of: "struct FirmwareRestoreWorkspaceView")!.lowerBound
        let body = String(child[..<end])
        XCTAssertTrue(body.contains("task.cfgutilOutputTail"))
        XCTAssertFalse(body.contains("restore.currentTask"))
        XCTAssertFalse(body.contains("restore.displayedTask"))
        XCTAssertTrue(body.contains("scrollPosition(id:"))
        XCTAssertTrue(body.contains("ui3-log-return-bottom"))
        XCTAssertTrue(body.contains("ui3-log-copy-preview"))
        XCTAssertTrue(body.contains("非完整原始日志"))
        XCTAssertTrue(body.contains("restore-live-output"))
    }

    func testTerminalBandIsReachableThroughFrozenSnapshots() throws {
        let content = try source()
        XCTAssertTrue(content.contains("ui3FinishedTaskForViewing"))
        XCTAssertTrue(content.contains("restore.lastCompletedTaskSnapshot"))
        XCTAssertTrue(content.contains("restore.lastSecondaryTaskSnapshot"))
        XCTAssertTrue(content.contains("viewedPortKey"))
        XCTAssertTrue(content.contains("viewedTaskID"))
        XCTAssertTrue(content.contains("ui3-terminal-back-to-prep"))
    }

    func testFrozenTerminalDurationAndExportOrder() throws {
        let content = try source()
        XCTAssertTrue(content.contains("ui3FrozenDurationText"))
        XCTAssertTrue(content.contains("task.lifecycle.processWallDurationSeconds"))
        XCTAssertTrue(content.contains("from: task.lifecycle.processLaunched"))
        XCTAssertTrue(content.contains("to: task.lifecycle.processExited"))
        XCTAssertTrue(content.contains("task.finishedAt"))
        let terminal = content.range(of: "private func ui3TerminalOutcome")!.lowerBound
        let tail = String(content[terminal...])
        let archive = tail.range(of: "if let archive = task.rawArchive")!.lowerBound
        let message = tail.range(of: "task.rawArchiveMessage", range: archive..<tail.endIndex)!.lowerBound
        let notSaved = tail.range(of: "!task.rawPersistencePolicy.saveThisRun", range: message..<tail.endIndex)!.lowerBound
        let writing = tail.range(of: "正在写入原始证据与历史记录", range: notSaved..<tail.endIndex)!.lowerBound
        XCTAssertLessThan(archive, message)
        XCTAssertLessThan(message, notSaved)
        XCTAssertLessThan(notSaved, writing)
    }

    func testSingleControlGroupAndAttemptBoundMutators() throws {
        let content = try source()
        let progress = content.range(of: "private func ui3ProgressAndControls")!.lowerBound
        let end = content.range(of: "private func ui3ProgressBar", range: progress..<content.endIndex)!.lowerBound
        let group = String(content[progress..<end])
        XCTAssertTrue(group.contains("restore-cancel-visible"))
        XCTAssertTrue(group.contains("restore-force-kill-visible"))
        XCTAssertTrue(content.contains("guard task.cancellationGraceExpired else { return false }"))
        XCTAssertTrue(content.contains("ui3RequestCancel(task, isPrimary: isPrimary)"))
        XCTAssertTrue(content.contains("ui3RequestForceKill(task, isPrimary: isPrimary)"))
        XCTAssertTrue(content.contains("pendingSecondaryCancelAttemptID = task.attemptID"))
        XCTAssertTrue(content.contains("pendingSecondaryForceKillAttemptID = task.attemptID"))
    }

    func testForceKillHasNoUIOwnGate() throws {
        let content = try source()
        XCTAssertFalse(content.contains("forceKillDeadline"))
    }

    func testResultPageFallbackAndNoModelChanges() throws {
        let content = try source()
        XCTAssertTrue(content.contains("当前没有可展示的 Restore 任务。"))
        let tokens = try read("Sources/DeviceCapturePrototype/MRAVisualTokens.swift")
        XCTAssertFalse(tokens.contains("terminalBackground"))
        XCTAssertFalse(content.contains("telemetryCyan"))
        XCTAssertFalse(content.contains("restore.selectTarget(id: targetID)"))
    }

    func testUI3KeepsRequiredIdentifiers() throws {
        let content = try source()
        for identifier in [
            "secondary-live-task", "restore-live-output",
            "restore-log-resizer", "restore-cancel-visible",
            "restore-force-kill-visible", "raw-export-button",
            "raw-export-button-b", "restore-preparation-cancel-pinned",
            "restore-finalizing-pinned"
        ] {
            XCTAssertTrue(content.contains(identifier), "missing id \(identifier)")
        }
    }
}

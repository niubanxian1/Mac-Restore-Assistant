import XCTest
@testable import DeviceCapturePrototype

/// UI-3.1：Owner 5 项微调 + 日志夹具门控的视图契约守卫。
final class UI3OwnerTuningTests: XCTestCase {
    private func read(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relative),
            encoding: .utf8)
    }
    private func view() throws -> String {
        try read("Sources/DeviceCapturePrototype/FirmwareRestoreWorkspaceView.swift")
    }
    private func workbench() throws -> String {
        try read("Sources/DeviceCapturePrototype/MinimalWorkbenchView.swift")
    }
    private func overview() throws -> String {
        try read("Sources/DeviceCapturePrototype/RestoreTaskOverviewView.swift")
    }
    private func fixture() throws -> String {
        try read("Sources/DeviceCapturePrototype/UIFixture.swift")
    }

    func testCanceledAutoReturnUsesReadOnlyLayout() throws {
        let content = try view()
        XCTAssertTrue(content.contains("finished.outcome != .canceled"))
        XCTAssertTrue(content.contains("ui3CanceledTaskForPreparation"))
        XCTAssertTrue(content.contains("canceledPreparationLayout("))
        XCTAssertTrue(content.contains("restartPrimaryWhileSecondary"))
        XCTAssertTrue(content.contains("targetIsSelected"))
        XCTAssertTrue(content.contains("restore.taskRegistry.activeCount < 2"))
        XCTAssertTrue(content.contains("restore.hardwareCompatibility.status == .compatible"))
        let start = content.range(of: "private func canceledPreparationLayout")!.lowerBound
        let end = content.range(of: "private var prepDivider", range: start..<content.endIndex)!.lowerBound
        let body = String(content[start..<end])
        XCTAssertFalse(body.contains("allowStart: false"))
        XCTAssertFalse(body.contains(".task"))
        XCTAssertFalse(body.contains("selectTarget"))
        XCTAssertFalse(body.contains("autoPrepareDraft"))
        XCTAssertFalse(body.contains("revalidateDraft"))
        XCTAssertTrue(body.contains("prepEffectiveFirmwareSection("))
        XCTAssertTrue(body.contains("ui3-canceled-prep"))
    }

    func testSuccessAndFailedStayTerminal() throws {
        let content = try view()
        XCTAssertTrue(content.contains("ui3FinishedTaskForViewing"))
        XCTAssertTrue(content.contains("ui3TerminalOutcome"))
        XCTAssertTrue(content.contains("finished.outcome != .canceled"))
    }

    func testCanceledResultExportFallback() throws {
        let content = try view()
        let start = content.range(of: "private func prepResultRow")!.lowerBound
        let body = String(content[start...])
        XCTAssertTrue(body.contains("if let archive = finished.rawArchive"))
        XCTAssertTrue(body.contains("finished.rawArchiveMessage"))
        XCTAssertTrue(body.contains("saveThisRun"))
        XCTAssertTrue(body.contains("正在整理原始日志，稍后可导出。"))
        XCTAssertTrue(body.contains("本次未保存完整原始日志。"))
    }

    func testEmptyOverviewIsHiddenAndSingleModeRemoved() throws {
        let workbench = try workbench()
        XCTAssertTrue(workbench.contains("if restore.isRestoreTaskActive"))
        XCTAssertTrue(workbench.contains("overview"))
        let overview = try overview()
        XCTAssertFalse(overview.contains("单任务模式"))
        XCTAssertTrue(overview.contains("双任务模式"))
        XCTAssertTrue(overview.contains("项活动"))
    }

    func testActionBarHasOneStatusLineAndAccessibleHelp() throws {
        let content = try view()
        XCTAssertTrue(content.contains("ui2-prep-raw-info"))
        XCTAssertTrue(content.contains(".help(rawLogExplanation(draftMessage))"))
        XCTAssertTrue(content.contains(".accessibilityValue(Text(statusAccessibilityValue(draftMessage)))"))
        XCTAssertTrue(content.contains("ui2-prep-action-bar"))
        XCTAssertTrue(content.contains("原始日志说明"))
        XCTAssertTrue(content.contains("只作用于下一次 Restore；关闭时不创建 raw/Staging 副本。"))
        XCTAssertTrue(content.contains("原始日志按当前保存设置写入此任务自己的目录；本任务不启动独立 RLM 采集。"))
        XCTAssertTrue(content.contains("if canStart {"))
        XCTAssertTrue(content.contains("let draftMessage = primaryMode"))
        XCTAssertTrue(content.contains("restore.firmwareDraftMessage(for: target)"))
    }

    func testRoleBadgeIsRemovedButL10nKeysRemain() throws {
        let content = try view()
        XCTAssertFalse(content.contains("L10n.t(isPrimary ? \"主任务\" : \"第二任务\")"))
        let l10n = try read("Sources/DeviceCapturePrototype/L10n.swift")
        XCTAssertTrue(l10n.contains("\"主任务\""))
        XCTAssertTrue(l10n.contains("\"第二任务\""))
    }

    func testSecondaryLabelsAreSingleLineButKeepTargetHelp() throws {
        let content = try workbench()
        XCTAssertTrue(content.contains("title: L10n.t(\"重启设备\"),"))
        XCTAssertTrue(content.contains("title: L10n.t(\"恢复模式\"),"))
        XCTAssertTrue(content.contains(".help(L10n.t(\"重启设备\") + controlTargetSuffix)"))
        XCTAssertTrue(content.contains(".help(L10n.t(\"进入恢复模式\") + controlTargetSuffix)"))
        XCTAssertTrue(content.contains("workbench-reboot"))
        XCTAssertTrue(content.contains("workbench-enter-recovery"))
    }

    func testFixtureLogLinesAreEnvGatedAndNormalPathStaysFiveLines() throws {
        let content = try fixture()
        XCTAssertTrue(content.contains("MRA_UI_RESTORE_LOG_LINES"))
        XCTAssertTrue(content.contains("TRIAL_LOG"))
        XCTAssertTrue(content.contains("for fraction in sequence"))
        XCTAssertTrue(content.contains("if testLineCount > 0"))
    }

    func testExistingIdentifiersArePreserved() throws {
        let content = try view()
        for identifier in [
            "secondary-live-task", "restore-live-output",
            "restore-cancel-visible", "restore-force-kill-visible",
            "raw-export-button", "raw-export-button-b",
            "ui2-prep-action-bar", "restore-save-raw-this-run",
            "restore-save-raw-this-run-secondary"
        ] {
            XCTAssertTrue(content.contains(identifier), "missing \(identifier)")
        }
    }
    func testUnverifiedCompatibilityCannotStartAndFailureIsVisible() throws {
        let model = try read("Sources/DeviceCapturePrototype/RestoreWorkspaceModel.swift")
        let start = model.range(of: "var canStartRestore")!.lowerBound
        let end = model.range(of: "var startDisabledReason", range: start..<model.endIndex)!.lowerBound
        let startBody = String(model[start..<end])
        XCTAssertTrue(startBody.contains("hardwareCompatibility.status == .compatible"))
        XCTAssertFalse(startBody.contains("hardwareCompatibility.status != .incompatible"))

        let content = try view()
        XCTAssertTrue(content.contains("restore.hardwareCompatibility.status == .compatible"))
        XCTAssertTrue(content.contains("restore.hardwareCompatibility.status == .unverified"))
        XCTAssertTrue(content.contains("ui2-prep-start-error"))
        XCTAssertTrue(content.contains("startFailureMessage"))
        XCTAssertTrue(content.contains("if !ok {"))
        XCTAssertTrue(content.contains("if !startFailureMessage.isEmpty"))
        XCTAssertTrue(content.contains("draft?.compatibility.status == .compatible"))
        XCTAssertTrue(content.contains("draft.compatibility.status == .unverified"))
    }

}

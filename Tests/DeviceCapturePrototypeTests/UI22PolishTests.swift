import XCTest
@testable import DeviceCapturePrototype

final class UI22PolishTests: XCTestCase {
    private func read(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relative),
            encoding: .utf8)
    }

    func testRepairCodeM1AndM2AreUnique() {
        XCTAssertEqual(RepairCodeCatalog.aNumber(cpid: 0x8103, bdid: 0x26), "A2337")
        XCTAssertEqual(RepairCodeCatalog.aNumber(cpid: 0x8112, bdid: 0x28), "A2681")
        XCTAssertNil(RepairCodeCatalog.aNumber(cpid: 0x1234, bdid: 0x99))
    }

    func testFollowLeftClearsExplicitViewedPort() throws {
        let view = try read("Sources/DeviceCapturePrototype/MinimalWorkbenchView.swift")
        let start = view.range(of: "onSelectPort: { port in")!.lowerBound
        let end = view.range(of: "},", range: start..<view.endIndex)!.lowerBound
        let body = String(view[start..<end])
        XCTAssertTrue(body.contains("observation.followLeftControl()"))
        XCTAssertTrue(body.contains("navigation.viewPort(nil)"))
        XCTAssertFalse(body.contains("navigation.viewPort(port.id)"))
    }

    func testLibrarySortAndContextMenuAreDisplayOnly() throws {
        let view = try read("Sources/DeviceCapturePrototype/FirmwareRestoreWorkspaceView.swift")
        XCTAssertTrue(view.contains("private func sortRank"))
        XCTAssertTrue(view.contains("guard entry.isRestoreEligible else { return 4 }"))
        XCTAssertTrue(view.range(of: "let target = viewedTarget")!.lowerBound
            < view.range(of: "let target = restore.selectedTarget")!.lowerBound)
        XCTAssertTrue(view.contains("case .compatible: return 1"))
        XCTAssertTrue(view.contains("case .unverified: return 2"))
        XCTAssertTrue(view.contains("设为本机型默认"))
        XCTAssertTrue(view.contains("设为全局默认"))
        XCTAssertTrue(view.contains("在 Finder 中显示"))
    }

    func testIdentityCopyFailureSummaryAndReconnectBar() throws {
        let view = try read("Sources/DeviceCapturePrototype/FirmwareRestoreWorkspaceView.swift")
        XCTAssertTrue(view.contains("identity-copy-toast"))
        XCTAssertTrue(view.contains("复制十六进制"))
        XCTAssertTrue(view.contains("复制十进制"))
        XCTAssertTrue(view.contains("ui3-copy-failure-summary"))
        XCTAssertTrue(view.contains("clear-invalid-firmware-default"))
        XCTAssertTrue(view.contains("清除失效默认"))
        XCTAssertTrue(view.contains("Text(L10n.t(target.displayName)\n                    + (repairCode.map"))
        XCTAssertFalse(view.contains("annotation: RepairCodeCatalog.aNumber"))
        XCTAssertTrue(view.contains("suffix(20)"))
        XCTAssertTrue(view.contains("Restore 完成提示音") || view.contains("ui.restoreCompletionSound"))
        let workbench = try read("Sources/DeviceCapturePrototype/MinimalWorkbenchView.swift")
        XCTAssertTrue(workbench.contains("device-telemetry-bar"))
        XCTAssertTrue(workbench.contains("近 1 分钟变化"))
        XCTAssertTrue(workbench.contains(">= 3"))
    }

    func testShortcutsAndSoundSetting() throws {
        let content = try read("Sources/DeviceCapturePrototype/ContentView.swift")
        XCTAssertTrue(content.contains(".keyboardShortcut(\"1\""))
        XCTAssertTrue(content.contains(".keyboardShortcut(\"2\""))
        XCTAssertTrue(content.contains(".keyboardShortcut(\"3\""))
        XCTAssertTrue(content.contains(".keyboardShortcut(\"r\""))
        XCTAssertTrue(content.contains("restore.startFirmwareDiscovery()"))
        XCTAssertFalse(content.contains("keyboardShortcut(.return"))
        let settings = try read("Sources/DeviceCapturePrototype/FirmwarePreferencesSettingsView.swift")
        XCTAssertTrue(settings.contains("restore-completion-sound-toggle"))
        XCTAssertTrue(settings.contains("ui.restoreCompletionSound"))
    }
    func testFollowLeftRunningPrefersViewedTarget() throws {
        let view = try read("Sources/DeviceCapturePrototype/FirmwareRestoreWorkspaceView.swift")
        XCTAssertTrue(view.contains("} else if let target = viewedTarget {\n                    if target.id == restore.currentTask?.target.id"))
        XCTAssertTrue(view.contains("} else if viewedTaskID == nil {\n                    emptyPortView"))
    }

    func testOverviewAllRowsClickable() throws {
        let overview = try read("Sources/DeviceCapturePrototype/RestoreTaskOverviewView.swift")
        XCTAssertFalse(overview.contains("if task.id == restore.currentTask?.id {"))
        XCTAssertTrue(overview.contains("onTapGesture"))
        XCTAssertTrue(overview.contains("onOpenTask(task.id)"))
        XCTAssertTrue(overview.contains("restore-overview-view-task"))
    }

}

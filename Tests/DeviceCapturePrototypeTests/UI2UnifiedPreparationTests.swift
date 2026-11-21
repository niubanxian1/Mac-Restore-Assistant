import XCTest
@testable import DeviceCapturePrototype

/// UI-2 统一 A/B Restore 准备态的结构、冻结与展示守卫。
final class UI2UnifiedPreparationTests: XCTestCase {

    func testFourSectionLayoutIsPresent() throws {
        let content = try source()
        XCTAssertTrue(content.contains(
            "private func devicePreparationLayout(target: RestoreTarget)"))
        XCTAssertTrue(content.contains("prepIdentitySection(target: target)"))
        XCTAssertTrue(content.contains("prepEffectiveFirmwareSection("))
        XCTAssertTrue(content.contains("prepFirmwareLibrarySection("))
        XCTAssertTrue(content.contains("prepActionBar("))
        XCTAssertTrue(content.contains("ui2-prep-identity"))
        XCTAssertTrue(content.contains("ui2-prep-effective-ipsw"))
        XCTAssertTrue(content.contains("ui2-prep-library"))
        XCTAssertTrue(content.contains("ui2-prep-action-bar"))
    }

    /// C6：issue 非空即显示，与是否已选固件无关；不允许静默回退。
    func testPreferenceIssueIsIndependentOfSelectedFirmware() throws {
        let content = try source()
        XCTAssertTrue(content.contains("prepPreferenceIssueBannerIfNeeded(summary, target: target)"))
        XCTAssertTrue(content.contains("if summary.showsPreferenceIssue"))
        XCTAssertTrue(content.contains("L10n.t(summary.preferenceIssue)"))
        XCTAssertTrue(content.contains(
            ".fixedSize(horizontal: false, vertical: true)"))

        let selectedWithIssue = UI2PreparationSummary(
            fileName: "G4_A_82003597_MacBookPro18,2.ipsw",
            versionText: "26.0.1 · 24A348",
            sourceText: "机型默认",
            preferenceIssue: "固件文件已移动、删除，或当前固件库尚未扫描到。")
        XCTAssertTrue(selectedWithIssue.showsPreferenceIssue)

        let noIssue = UI2PreparationSummary(
            fileName: "G4_A_82003597_MacBookPro18,2.ipsw",
            versionText: "26.0.1 · 24A348",
            sourceText: "机型默认",
            preferenceIssue: "")
        XCTAssertFalse(noIssue.showsPreferenceIssue)
    }

    /// C2/C3：A 手动优先；B 没有可信来源字段，固定 未获取。
    func testFirmwareSourceIsManualFirstForAAndNeverInventedForB() throws {
        let content = try source()
        let start = try XCTUnwrap(
            content.range(of: "private func prepSourceText(primaryMode: Bool)"))
        let end = try XCTUnwrap(
            content.range(
                of: "private func prepEffectiveFirmwareSection(",
                range: start.upperBound..<content.endIndex))
        let body = String(content[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(body.contains("guard primaryMode else { return L10n.t(\"未获取\") }"))
        XCTAssertTrue(body.contains(
            "restore.firmwareSelectionSource == .userManualSelected"))
        XCTAssertTrue(body.contains("firmwareSourceLabel(recommendation)"))
        XCTAssertFalse(body.contains("firmwareDraftMessage"))
        XCTAssertFalse(body.contains("libraryEntryID"))
    }

    func testBStatusMessageIsRenderedOnceOutsideSourceLabel() throws {
        let content = try source()
        XCTAssertTrue(content.contains("let draftMessage = primaryMode"))
        XCTAssertTrue(content.contains("restore.firmwareDraftMessage(for: target)"))
        // 来源标签只由 prepSourceText 生成，不接受 draft message。
        let sourceBodyStart = try XCTUnwrap(
            content.range(of: "private func prepSourceText(primaryMode: Bool)"))
        let sourceBodyEnd = try XCTUnwrap(
            content.range(
                of: "private func prepEffectiveFirmwareSection(",
                range: sourceBodyStart.upperBound..<content.endIndex))
        let body = content[sourceBodyStart.lowerBound..<sourceBodyEnd.lowerBound]
        XCTAssertFalse(body.contains("firmwareDraftMessage"))
    }

    func testPinnedActionBarEnumeratesAllBStartConditions() throws {
        let content = try source()
        XCTAssertTrue(content.contains("restore.canStartRestore"))
        XCTAssertTrue(content.contains("restore.taskRegistry.activeCount < 2"))
        XCTAssertTrue(content.contains("restore.taskRegistry.activeCount == 0"))
        XCTAssertTrue(content.contains("|| restore.currentTask != nil"))
        XCTAssertTrue(content.contains("!rlmConflict"))
        XCTAssertTrue(content.contains("prepRLMConflict"))
        XCTAssertTrue(content.contains("restore.startDisabledReason"))
        XCTAssertTrue(content.contains("已有两个 Restore 任务在执行。"))
        XCTAssertTrue(content.contains("另一台正在使用独立 RLM 日志，此设备将被拒绝启动。"))
        // 禁用时绝不能同时显示“准备完成”。
        XCTAssertTrue(content.contains("if canStart {\n                Text(L10n.t(\"固件准备完成，可启动此设备。\"))"))
    }

    func testExistingIdentifiersAndP2BStringsArePreserved() throws {
        let content = try source()
        for identifier in [
            "secondary-start-button",
            "restore-save-raw-this-run",
            "restore-save-raw-this-run-secondary",
            "p2b-second-device-draft",
            "p2b-active-task-bar",
            "restore-cancel-visible",
            "raw-export-button",
            "raw-export-button-b",
            "restore-live-output",
            "restore-log-resizer",
            "restore-preparation-cancel-pinned",
            "restore-finalizing-pinned",
        ] {
            XCTAssertTrue(content.contains(identifier), identifier)
        }
        XCTAssertTrue(content.contains("draftStatusText(status)"))
        XCTAssertTrue(content.contains("firmwareDraftMessage(for: target)"))
        XCTAssertTrue(content.contains("disabled(!canStart)"))
        XCTAssertTrue(content.contains("当前无法开始 Restore"))
        XCTAssertTrue(content.contains("showsActions: !restore.isRestoreTaskActive"))
        XCTAssertTrue(content.contains(".id(\"restore-firmware\")"))
        XCTAssertTrue(content.contains("scrollProxy.scrollTo(\"restore-firmware\""))
        XCTAssertTrue(content.contains("safeAreaInset(edge: .bottom, spacing: 0)"))
    }

    func testAAndBLibraryHighlightProjectTheSameModelReference() throws {
        let content = try source()
        XCTAssertTrue(content.contains("restore.firmwareLibraryEntryID"))
        XCTAssertTrue(content.contains("draft?.libraryEntryID"))
        XCTAssertTrue(content.contains("ui2-prep-library-row-"))
        XCTAssertTrue(content.contains("restore.selectFirmwareFromLibrary(id: entry.id)"))
        XCTAssertTrue(content.contains("restore.prepareFirmwareDraft("))
        XCTAssertTrue(content.contains("private struct UI2FirmwareLibraryList"))
        XCTAssertTrue(content.contains("@State private var query"))
        XCTAssertFalse(content.contains("@State private var selectedIPSW"))
        XCTAssertFalse(content.contains("@State private var defaultIPSW"))
        XCTAssertFalse(content.contains("recommendedFirmwareCache"))
    }

    func testFrozenConfirmationTokenIsTheOnlyDialogSource() throws {
        let content = try source()
        XCTAssertTrue(content.contains("restore.freezeRestoreConfirmation("))
        XCTAssertTrue(content.contains("pendingSecondaryTargetID = target.id"))
        XCTAssertTrue(content.contains("showSecondaryStartConfirmation = true"))
        XCTAssertTrue(content.contains("beginUnifiedRestoreAfterConfirmation"))
        XCTAssertTrue(content.contains("unifiedStartConfirmationMessage"))
        XCTAssertTrue(content.contains("restore.frozenRestoreConfirmation"))
        XCTAssertFalse(content.contains("restore.selectTarget(id: targetID)"))
    }

    func testUI2UsesTokensWithoutBorrowingUI3Telemetry() throws {
        let content = try source()
        XCTAssertTrue(content.contains("MRAVisualTokens.resolve("))
        XCTAssertTrue(content.contains("visual.canvasPrimary"))
        XCTAssertTrue(content.contains("visual.surfaceSubtle"))
        XCTAssertTrue(content.contains("visual.hairline"))
        XCTAssertFalse(content.contains("telemetryCyan"))
    }

    // MARK: - 工具

    private func source() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/FirmwareRestoreWorkspaceView.swift"),
            encoding: .utf8)
    }
}

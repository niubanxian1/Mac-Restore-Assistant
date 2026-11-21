import XCTest
@testable import DeviceCapturePrototype

final class WorkspaceLayoutTests: XCTestCase {
    func testMainWorkspaceHasThreeV220OwnerApprovedTabs() {
        XCTAssertEqual(
            PrimaryWorkspaceTab.allCases.map(\.title),
            ["端口与设备", "固件与恢复", "RLM 日志"])
    }

    func testFirmwareRestoreDomainDoesNotWriteControlOrObservationTargets() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let view = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/FirmwareRestoreWorkspaceView.swift"),
            encoding: .utf8)

        XCTAssertTrue(view.contains("RestoreWorkspaceModel"))
        XCTAssertFalse(view.contains("device.selectPort("))
        XCTAssertFalse(view.contains("selectedLiveKey ="))
        XCTAssertFalse(view.contains("pendingActionPort ="))
        XCTAssertFalse(view.contains("AXObserver"))
    }

    @MainActor
    func testUIFixtureForcesConfiguratorSimulation() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ConfiguratorFixturePolicy-\(UUID().uuidString)",
                isDirectory: true)
        let model = ConfiguratorResetModel.makeForUI(
            environment: ["MRA_UI_FIXTURE": "t532-main"],
            applicationSupportRoot: root)

        XCTAssertTrue(model.simulationOnly)
        XCTAssertTrue(model.executor is MockConfiguratorExecutor)
        XCTAssertEqual(
            model.home.standardizedFileURL,
            root.appendingPathComponent(
                "configurator-home",
                isDirectory: true)
                .standardizedFileURL)
    }

    func testPanoramaIsEmbeddedAndLegacySeparateWindowIsRemoved() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/MinimalWorkbenchView.swift"),
            encoding: .utf8)
        let app = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/App.swift"),
            encoding: .utf8)

        XCTAssertTrue(content.contains("PanoramaView("))
        XCTAssertTrue(content.contains("isEmbedded: true"))
        XCTAssertTrue(content.contains("emptyPrimaryText: treeEmptyStateText"))
        XCTAssertTrue(content.contains("ForEach(device.orderedDisplayPorts)"))
        XCTAssertFalse(app.contains("Window(\"接口与设备\""))
    }

    func testPortDeviceTabCombinesDetailAndPanoramaWithoutHiddenNavigation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/MinimalWorkbenchView.swift"),
            encoding: .utf8)

        XCTAssertTrue(content.contains("struct MinimalPortDeviceWorkspace: View"))
        XCTAssertTrue(content.contains("SelectedPortDetailPane("))
        XCTAssertTrue(content.contains("GeometryReader"))
        XCTAssertTrue(content.contains(".defaultScrollAnchor(.top)"))
        XCTAssertFalse(content.contains("VSplitView"))
        XCTAssertTrue(content.contains(
            ".accessibilityIdentifier(\"port-device-detail-scroll\")"))
        XCTAssertTrue(content.contains(
            ".accessibilityIdentifier(\"port-device-tree\")"))
        XCTAssertTrue(content.contains(
            "showPanoramaSummary: false"))
        XCTAssertFalse(content.contains("case panorama"))
    }

    func testCombinedTabKeepsExistingDetailTreeAndExportFunctions() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/MinimalWorkbenchView.swift"),
            encoding: .utf8)
        let panorama = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/PanoramaReadOnly.swift"),
            encoding: .utf8)

        XCTAssertTrue(content.contains("SelectedPortDetailPane("))
        XCTAssertTrue(content.contains("showPanoramaSummary: false"))
        XCTAssertTrue(content.contains("PanoramaView("))
        XCTAssertTrue(panorama.contains("Button(L10n.t(\"刷新\"))"))
        XCTAssertTrue(panorama.contains("Button(L10n.t(\"导出诊断 JSON\"))"))
        XCTAssertTrue(panorama.contains(
            "DisclosureGroup(L10n.t(\"原始只读属性\"))"))
    }

    func testPanoramaSelectionCannotMutateLeftControlTarget() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let panorama = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/PanoramaReadOnly.swift"),
            encoding: .utf8)

        XCTAssertFalse(panorama.contains("device.selectPort("))
        XCTAssertFalse(panorama.contains("selectedLiveKey ="))
        XCTAssertFalse(panorama.contains("pendingActionPort ="))
        XCTAssertTrue(panorama.contains("onUserSelection?()"))
    }

    func testUserTreeSelectionPausesDFUAutoNavigation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/MinimalWorkbenchView.swift"),
            encoding: .utf8)

        XCTAssertTrue(content.contains("onUserTreeSelection:"))
        XCTAssertTrue(content.contains("autoNavigationPaused = true"))
        XCTAssertTrue(content.contains("observation.followLeftControl()"))
        XCTAssertTrue(content.contains(
            "followsControlPort: observation.followsLeftControl"))
        XCTAssertTrue(content.contains(
            "restorePreparationActive:\n                restore.hasUserRestorePreparationContext"))
        XCTAssertTrue(content.contains(
            "settingsPresented: showSettings"))
        XCTAssertTrue(content.contains(
            "configuratorPresented: showConfiguratorStorage"))
    }

    func testDFUAutoNavigationCannotMutateRestoreSelection() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/MinimalWorkbenchView.swift"),
            encoding: .utf8)
        let navigation = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/WorkbenchNavigation.swift"),
            encoding: .utf8)

        let start = try XCTUnwrap(
            content.range(of: "private func navigateToRestore("))
        let end = try XCTUnwrap(
            content.range(
                of: "private func confirmationMessage(",
                range: start.upperBound..<content.endIndex))
        let navigationBody = content[start.lowerBound..<end.lowerBound]

        XCTAssertFalse(navigationBody.contains("restore."))
        XCTAssertFalse(content.contains(
            "|| restore.selectedTargetID != nil"))
        XCTAssertFalse(content.contains(
            "|| restore.firmwareURL != nil"))
        XCTAssertFalse(content.contains(
            "|| restore.firmwareLibraryEntryID != nil"))
        XCTAssertTrue(content.contains("WorkbenchNavigationContext("))
        XCTAssertTrue(navigation.contains("restoreTaskActive: Bool"))
    }

    func testAppUsesOneSingleWindowScene() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/App.swift"),
            encoding: .utf8)

        XCTAssertTrue(app.contains(
            "Window(\"牛半仙Mac维修辅助工具\", id: \"main\")"))
        XCTAssertFalse(app.contains("WindowGroup("))
    }

    func testTerminationGuardCoversWholeRestoreLifecycle() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let guardSource = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/FirstLaunchAuthorizationWindowGuard.swift"),
            encoding: .utf8)

        XCTAssertTrue(guardSource.contains(
            "restoreOwner?.isRestoreTaskActive == true"))
        XCTAssertFalse(guardSource.contains(
            "restoreOwner?.isRestoring == true"))
    }

    func testActiveRestoreUsesCompactLayoutAndPinnedCancel() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let view = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/FirmwareRestoreWorkspaceView.swift"),
            encoding: .utf8)

        XCTAssertTrue(view.contains("if restore.isRestoring {"))
        XCTAssertTrue(view.contains("viewedPortKey != nil"))
        XCTAssertTrue(view.contains(
            "if !restore.isRestoreTaskActive {\n                restore.refreshTargets()"))
        XCTAssertTrue(view.contains("restore-live-output"))
        XCTAssertTrue(view.contains("restore-log-resizer"))
        XCTAssertTrue(view.contains("restore-cancel-visible"))
        XCTAssertTrue(view.contains(
            "safeAreaInset(edge: .bottom, spacing: 0)"))
        XCTAssertTrue(view.contains(
            "preparationCancelInset"))
        XCTAssertTrue(view.contains(
            "restore.canCancelRestoreTask"))
        XCTAssertTrue(view.contains(
            "restore.isFinalizingRestoreEvidence"))
        XCTAssertTrue(view.contains(
            "restore-finalizing-pinned"))
        XCTAssertTrue(view.contains(
            "showsActions: !restore.isRestoreTaskActive"))
        XCTAssertTrue(view.contains("cfgutilOutputTail"))
        XCTAssertTrue(view.contains(
            "@AppStorage(\"ui.restoreLogPanelFraction\")"))
        XCTAssertTrue(view.contains("DragGesture(minimumDistance: 0)"))
        XCTAssertFalse(view.contains(
            "不会创建 raw，也不会启动 RLM"))
        XCTAssertTrue(view.contains(
            "RestoreLiveEvidenceCopy.panelDescription"))
    }

    func testRestoreWorkspacePresentsUniqueNavigationCandidateWithoutMutatingSelection() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let view = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/FirmwareRestoreWorkspaceView.swift"),
            encoding: .utf8)

        XCTAssertTrue(view.contains("@Binding var navigationPortID"))
        XCTAssertTrue(view.contains(".id(\"restore-firmware\")"))
        XCTAssertTrue(view.contains(
            "RestoreNavigationTargetResolver.uniqueTargetID("))
        XCTAssertTrue(view.contains(
            "scrollProxy.scrollTo(\"restore-firmware\""))
        XCTAssertFalse(view.contains("restore.selectBrowsePort(navigationPortID)"))
        XCTAssertFalse(view.contains("restore.selectTarget(id: targetID)"))
        XCTAssertTrue(view.contains("navigationCandidateTargetID"))
    }

    func testRestoreLogPaneFractionIsBoundedAcrossWindowHeights() {
        let regular = RestoreLogPaneMetrics.bounds(for: 600)
        XCTAssertGreaterThanOrEqual(regular.lowerBound, 0.2)
        XCTAssertLessThanOrEqual(regular.upperBound, 0.7)
        XCTAssertEqual(
            RestoreLogPaneMetrics.constrainedFraction(0.46, for: 600),
            0.46,
            accuracy: 0.0001)

        let compact = RestoreLogPaneMetrics.bounds(for: 360)
        XCTAssertGreaterThanOrEqual(compact.lowerBound, 0.2)
        XCTAssertLessThanOrEqual(compact.upperBound, 0.7)
        XCTAssertEqual(
            RestoreLogPaneMetrics.constrainedFraction(0.9, for: 360),
            compact.upperBound,
            accuracy: 0.0001)
        XCTAssertEqual(
            RestoreLogPaneMetrics.constrainedFraction(0.05, for: 360),
            compact.lowerBound,
            accuracy: 0.0001)
    }

    func testRestoreLogResizePersistsFractionAndDoesNotChangeTaskState() {
        let adjusted = RestoreLogPaneMetrics.adjustedFraction(
            startingAt: 0.46,
            translation: -60,
            availableHeight: 600)
        XCTAssertGreaterThan(adjusted, 0.46)
        XCTAssertLessThanOrEqual(adjusted, 0.7)

        let bounded = RestoreLogPaneMetrics.adjustedFraction(
            startingAt: 0.46,
            translation: 10_000,
            availableHeight: 600)
        XCTAssertEqual(
            bounded,
            Double(RestoreLogPaneMetrics.bounds(for: 600).lowerBound),
            accuracy: 0.0001)
    }

    func testTabVisibilityOnlyControlsPreviewPresentation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/ContentView.swift"),
            encoding: .utf8)

        XCTAssertTrue(content.contains(
            "capture.setPreviewVisible(tab == .logs)"))
        XCTAssertFalse(content.contains(
            "case .panorama:\n                            capture."))
    }

    func testPanoramaObservationLivesWithMainWorkspaceInsteadOfTabVisibility() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/ContentView.swift"),
            encoding: .utf8)
        let panorama = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/PanoramaReadOnly.swift"),
            encoding: .utf8)

        XCTAssertTrue(content.contains("panorama.startWatching(device: device)"))
        XCTAssertTrue(content.contains("panorama.stopWatching()"))
        XCTAssertFalse(panorama.contains(
            ".onAppear {\n                model.startWatching()"))
        XCTAssertFalse(panorama.contains(
            ".onDisappear { model.stopWatching() }"))
    }

    func testMainWindowMinimumContentHeightAllowsA920By680Window() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/App.swift"),
            encoding: .utf8)

        XCTAssertTrue(app.contains(
            ".frame(minWidth: 920, minHeight: 648)"))
    }

    func testLeftControlColumnScrollsAtCompactWindowHeight() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/MinimalWorkbenchView.swift"),
            encoding: .utf8)

        XCTAssertTrue(content.contains("ScrollView {"))
        XCTAssertTrue(content.contains("title: L10n.t(\"进入 DFU\")"))
        XCTAssertTrue(content.contains("title: L10n.t(\"重启设备\")"))
        XCTAssertTrue(content.contains("title: L10n.t(\"恢复模式\")"))
        XCTAssertTrue(content.contains("workbench-status-lamps"))
        // UI-1：左栏宽度改为 Token 常量（288/294，均在 Owner 的 280–310 区间）。
        XCTAssertTrue(content.contains(
            ".frame(width: compact\n                            ? visual.sidebarWidthCompact\n                            : visual.sidebarWidthRegular)"))
    }

    func testCompactWindowMinimumIsAppliedToTheNativeWindow() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/App.swift"),
            encoding: .utf8)

        XCTAssertTrue(app.contains(
            "window.minSize = NSSize(width: 920, height: 680)"))
    }

    func testWorkspaceTabControlUsesStableOwnerApprovedWidth() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/MinimalWorkbenchView.swift"),
            encoding: .utf8)

        XCTAssertTrue(content.contains(
            ".frame(minWidth: 292, idealWidth: 352, maxWidth: 390)"))
    }

    func testHeaderHasExactlyOneConfiguratorAction() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/MinimalWorkbenchView.swift"),
            encoding: .utf8)

        XCTAssertEqual(
            content.components(
                separatedBy: "Label(L10n.t(\"Configurator 存储\")").count - 1,
            1)
    }
}

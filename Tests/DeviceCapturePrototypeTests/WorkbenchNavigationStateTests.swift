import XCTest
@testable import DeviceCapturePrototype

/// P2-A1：REV2 工作台第一阶段（只读展示 / 导航隔离 / 历史摘要）的离线验证。
///
/// 说明：本仓库没有 SwiftUI 渲染测试宿主，导航隔离通过两层验证：
/// 1. `WorkbenchNavigationState` 的纯状态语义；
/// 2. 对新视图源码的静态约束（不得出现任何物理控制或取消调用）。
@MainActor
final class WorkbenchNavigationStateTests: XCTestCase {
    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(
            contentsOf: sourceRoot.appendingPathComponent(relative),
            encoding: .utf8)
    }

    /// 只保留代码行（去掉整行注释），避免文档注释里的"禁止词"造成误报。
    private func codeOnly(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("//")
            }
            .joined(separator: "\n")
    }

    // MARK: - 状态语义

    func testViewTaskSetsOnlyTaskState() {
        let state = WorkbenchNavigationState()
        let id = UUID()
        state.viewTask(id: id, portLabel: "左上")

        XCTAssertEqual(state.viewedTaskID, id)
        XCTAssertNil(state.viewedPortKey, "查看任务不得改变查看端口")
        XCTAssertEqual(state.viewedTaskPortLabel, "左上")
        XCTAssertTrue(state.isViewingTask(id))
        XCTAssertEqual(state.taskViewLabel, "左上")
    }

    func testViewPortAndViewTaskAreIndependent() {
        let state = WorkbenchNavigationState()
        state.viewPort("port-B")
        let id = UUID()
        state.viewTask(id: id, portLabel: "左上")

        XCTAssertEqual(state.viewedPortKey, "port-B")
        XCTAssertTrue(state.isViewingPort("port-B"))
        XCTAssertEqual(state.viewedTaskID, id)
    }

    func testViewPortClearsTaskOnlyWhenSwitchingPort() {
        let state = WorkbenchNavigationState()
        state.viewPort("port-A")
        let id = UUID()
        state.viewTask(id: id, portLabel: "左上")
        state.viewPort("port-A")
        XCTAssertEqual(state.viewedTaskID, id, "同端口不应清除任务查看")
        state.viewPort("port-B")
        XCTAssertNil(state.viewedTaskID, "切换端口应清除任务查看")
    }

    func testViewPortNilAlwaysClearsTaskView() {
        let state = WorkbenchNavigationState()
        let id = UUID()
        state.viewPort("port-A")
        state.viewTask(id: id, portLabel: "左上")
        state.viewPort(nil)
        XCTAssertNil(state.viewedTaskID)
        XCTAssertNil(state.viewedPortKey)
    }

    func testHistoryLookupIsEmptySafeAndRefusesNilPort() {
        XCTAssertNil(PortRecentTaskSummaryView.latest(
            [], matchingPortKey: "port-A", excludingTaskID: nil))
        XCTAssertNil(PortRecentTaskSummaryView.latest(
            [], matchingPortKey: nil, excludingTaskID: nil))
        let lookup = PortRecentTaskSummaryView.lookup(
            [], matchingPortKey: "port-A", excludingTaskID: nil)
        XCTAssertNil(lookup.record)
        XCTAssertFalse(lookup.isAmbiguous)
    }

    func testViewPortClearsTaskSelection() {
        let state = WorkbenchNavigationState()
        let id = UUID()
        state.viewTask(id: id, portLabel: "左上")
        state.viewPort("port-A")
        state.viewPort("port-B")

        XCTAssertNil(state.viewedTaskID)
        XCTAssertNil(state.taskViewLabel)
        XCTAssertEqual(state.viewedPortKey, "port-B")
        XCTAssertFalse(state.isViewingTask(id))
    }

    func testViewPortIsIdempotentForSameKey() {
        let state = WorkbenchNavigationState()
        let id = UUID()
        state.viewPort("port-A")
        state.viewTask(id: id, portLabel: "左上")
        state.viewPort("port-A")

        // 同端口只切查看态，不清除任务查看记录（避免闪烁）。
        XCTAssertEqual(state.viewedTaskID, id)
    }

    // MARK: - 端口历史归属

    func testAmbiguousPortOwnershipRefusesToGuess() {
        let older = record(portKey: "hostA|port1", minutesAgo: 30)
        let newer = record(portKey: "hostB|port1", minutesAgo: 5)
        let lookup = PortRecentTaskSummaryView.lookup(
            [older, newer], matchingPortKey: "port1", excludingTaskID: nil)

        XCTAssertNil(lookup.record)
        XCTAssertTrue(lookup.isAmbiguous)
    }

    func testUniquePortOwnershipPicksLatestByCompletion() {
        let older = record(portKey: "hostA|port1", minutesAgo: 30)
        let newer = record(portKey: "hostA|port1", minutesAgo: 5)
        let lookup = PortRecentTaskSummaryView.lookup(
            [older, newer], matchingPortKey: "port1", excludingTaskID: nil)

        XCTAssertEqual(lookup.record?.taskID, newer.taskID)
        XCTAssertFalse(lookup.isAmbiguous)
    }

    func testDifferentPortIsNeverMatched() {
        let other = record(portKey: "hostA|port2", minutesAgo: 5)
        let lookup = PortRecentTaskSummaryView.lookup(
            [other], matchingPortKey: "port1", excludingTaskID: nil)
        XCTAssertNil(lookup.record)
        XCTAssertFalse(lookup.isAmbiguous)
    }

    func testActiveTaskIsExcludedFromPortHistory() {
        let active = record(portKey: "hostA|port1", minutesAgo: 1)
        let older = record(portKey: "hostA|port1", minutesAgo: 40)
        let lookup = PortRecentTaskSummaryView.lookup(
            [active, older], matchingPortKey: "port1", excludingTaskID: active.taskID)

        XCTAssertEqual(lookup.record?.taskID, older.taskID)
    }

    private func record(
        portKey: String?,
        minutesAgo: Double
    ) -> RestoreHistoryRecord {
        let id = UUID()
        let completed = Date().addingTimeInterval(-minutesAgo * 60)
        let point = RestoreLifecycleTimePoint(
            wallTime: completed, monotonicNanoseconds: 0)
        let policy = RestoreRawPersistencePolicy(
            autoSaveDefault: false,
            saveThisRun: false,
            destinationDirectory: "",
            autoMonitorEnabled: false,
            spaceWarningThresholdBytes: nil,
            retentionPolicy: "none")
        return RestoreHistoryRecord(
            taskID: id,
            attemptID: id,
            operationType: .restore,
            deviceDisplayName: "MacBookPro18,2",
            modelFamilyKey: nil,
            hardwareBindingKey: HardwareBindingKey(
                productType: "Mac14,2",
                deviceClass: "j413ap",
                boardID: 1,
                chipID: 2),
            stablePortKey: portKey,
            firmwareLibraryEntryID: nil,
            firmwareFileName: "fixture.ipsw",
            ipswIdentity: nil,
            productVersion: nil,
            productBuild: nil,
            lifecycle: RestoreLifecycleTimes(userConfirmed: point),
            outcome: .success,
            errorClassification: .none,
            exitCode: 0,
            terminationReason: .exit,
            cancellationRequested: false,
            sentSignals: [],
            rawPersistencePolicy: policy,
            rawEvidenceStatus: .notRequested,
            rlmStatus: .notRequested,
            rlmOwnership: .notRequested,
            rlmFinalizedAt: nil,
            rlmDrainDurationSeconds: nil,
            recordSource: .unverified,
            verificationComplete: false)
    }

    // MARK: - 静态隔离约束

    func testNavigationStateHasNoDeviceControlDependency() throws {
        let text = codeOnly(try source(
            "Sources/DeviceCapturePrototype/WorkbenchNavigationState.swift"))
        XCTAssertFalse(text.contains("DeviceControlModel"))
        XCTAssertFalse(text.contains("selectedLiveKey"))
        XCTAssertFalse(text.contains("performDFU"))
        XCTAssertFalse(text.contains("RestoreWorkspaceModel"))
    }

    func testTaskOverviewNeverTouchesPhysicalControl() throws {
        let text = codeOnly(try source(
            "Sources/DeviceCapturePrototype/RestoreTaskOverviewView.swift"))
        XCTAssertFalse(text.contains("selectedLiveKey"))
        XCTAssertFalse(text.contains("selectLivePort"))
        XCTAssertFalse(text.contains("performDFU"))
        XCTAssertFalse(text.contains("performReboot"))
        XCTAssertFalse(text.contains("performRecovery"))
        XCTAssertFalse(text.contains("cancelRestore"))
        XCTAssertFalse(text.contains("forceKillRestore"))
        // 单任务事实：不得出现并发容量或双机示意。
        XCTAssertFalse(text.contains("2/2"))
        XCTAssertFalse(text.contains("并发容量"))
        XCTAssertFalse(text.contains("viewedPortKey"), "总览只查看任务，不得改查看端口")
    }

    func testHistorySummaryHasNoExecutableActions() throws {
        let text = codeOnly(try source(
            "Sources/DeviceCapturePrototype/PortRecentTaskSummaryView.swift"))
        XCTAssertFalse(text.contains("cancelRestore"))
        XCTAssertFalse(text.contains("forceKillRestore"))
        XCTAssertFalse(text.contains("beginRestoreAfterConfirmation"))
        XCTAssertFalse(text.contains("selectedLiveKey"))
        // 必须按端口键过滤，且排除当前活动任务。
        XCTAssertTrue(text.contains("stablePortKey"))
        XCTAssertTrue(text.contains("excludingTaskID"))
        XCTAssertTrue(text.contains("isAmbiguous"))
        XCTAssertTrue(text.contains("matchedKeys.count == 1"))
    }

    func testCancelConfirmationIsBoundToAttemptID() throws {
        let text = try source(
            "Sources/DeviceCapturePrototype/FirmwareRestoreWorkspaceView.swift")
        XCTAssertTrue(text.contains("pendingCancelAttemptID"))
        XCTAssertTrue(text.contains("restore.currentAttemptID == captured"))
        XCTAssertTrue(text.contains("confirmCancelRestore()"))
        XCTAssertTrue(text.contains("confirmForceKillRestore()"))
    }

    func testWorkbenchMountsOverviewAboveWorkspaceStage() throws {
        let text = try source(
            "Sources/DeviceCapturePrototype/MinimalWorkbenchView.swift")
        XCTAssertTrue(text.contains("RestoreTaskOverviewView("))
        XCTAssertTrue(text.contains("@StateObject private var navigation = WorkbenchNavigationState()"))
        // 总览点击只能切标签页，不得触碰物理控制。
        XCTAssertTrue(text.contains("onOpenTask: { _ in"))
    }

    func testRestoreViewShowsPerPortHistorySummary() throws {
        let text = try source(
            "Sources/DeviceCapturePrototype/FirmwareRestoreWorkspaceView.swift")
        XCTAssertTrue(text.contains("PortRecentTaskSummaryView("))
        XCTAssertTrue(text.contains("historyPortKey"))
    }

    func testControlButtonsCarryControlTargetSuffix() throws {
        let text = try source(
            "Sources/DeviceCapturePrototype/MinimalWorkbenchView.swift")
        for key in ["进入 DFU", "重启设备", "进入恢复模式"] {
            XCTAssertTrue(
                text.contains("L10n.t(\"\(key)\") + controlTargetSuffix"),
                "control button \(key) must name the control target")
        }
        // 风险说明是纯展示，不得新增发送门禁。
        XCTAssertTrue(text.contains("workbench-active-restore-risk-note"))
        XCTAssertFalse(text.contains("requireNamedRiskConfirmation"))
    }
}

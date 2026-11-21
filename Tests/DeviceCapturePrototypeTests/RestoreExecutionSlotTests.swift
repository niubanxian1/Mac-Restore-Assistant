import Foundation
import XCTest
@testable import DeviceCapturePrototype
import RestoreLogEngine

/// 切片 1：单机执行状态收拢到 `RestoreExecutionSlot` 的回归。
/// 不新增第二个 Restore；只验证槽所有权、投影绑定与生命周期不变。
@MainActor
final class RestoreExecutionSlotTests: XCTestCase {
    private let ecid: UInt64 = 0x12345670
    private var canonicalHex: String { String(format: "%016llX", ecid) }

    func testSlotOwnsAttemptTaskAndRunHandle() throws {
        let attempt = makeAttempt()
        let task = makeTask(attemptID: attempt.attemptID)
        let slot = RestoreExecutionSlot(attempt: attempt, task: task)
        XCTAssertEqual(slot.attemptID, attempt.attemptID)
        XCTAssertEqual(slot.attempt?.attemptID, attempt.attemptID)
        XCTAssertEqual(slot.task?.attemptID, task.attemptID)
        XCTAssertTrue(slot.isOccupied)

        slot.attempt = nil
        slot.task = nil
        XCTAssertFalse(slot.isOccupied)
    }

    func testModelProjectsTheSingleSlot() async throws {
        let engine = SlotFakeEngine()
        let (model, control) = makeModel(engine: engine)
        publishDevice(to: control)
        model.refreshTargets()
        model.selectTarget(id: canonicalHex)
        await model.loadFirmware(url: try firmwareURL())

        publishDevice(to: control)
        let start = Task { await model.testStartPrimaryThroughConfirmation() }
        try await waitUntil { model.isRestoring }
        let slot = try XCTUnwrap(model.executionSlot)
        XCTAssertEqual(slot.attemptID, model.activeAttempt?.attemptID)
        XCTAssertEqual(slot.attemptID, model.currentTask?.attemptID)
        XCTAssertEqual(slot.task?.attemptID, model.currentTask?.attemptID)

        model.cancelRestore()
        XCTAssertEqual(slot.task?.cancellationRequested, true,
                       "取消必须写入槽内的任务快照")
        engine.release(outcome: .canceled, exitCode: nil)
        _ = await start.value

        XCTAssertNil(model.activeAttempt)
        XCTAssertNil(model.currentTask)
        XCTAssertNil(model.executionSlot?.runTask)
        XCTAssertEqual(model.executionSlot?.attemptID, slot.attemptID,
                       "槽身份在收尾后保留，投影清空")
    }

    func testSecondStartWhileActiveIsRefusedWithoutReplacingSlot() async throws {
        let engine = SlotFakeEngine()
        let (model, control) = makeModel(engine: engine)
        publishDevice(to: control)
        model.refreshTargets()
        model.selectTarget(id: canonicalHex)
        await model.loadFirmware(url: try firmwareURL())

        publishDevice(to: control)
        let start = Task { await model.testStartPrimaryThroughConfirmation() }
        try await waitUntil { model.isRestoring }
        let slotID = try XCTUnwrap(model.executionSlot?.attemptID)

        await model.testStartPrimaryThroughConfirmation()
        XCTAssertFalse(model.errorMessage.isEmpty)
        XCTAssertEqual(engine.runCount, 1, "被拒绝的第二次启动不得再次调用引擎")
        XCTAssertEqual(model.executionSlot?.attemptID, slotID,
                       "被拒绝的第二次启动不得替换执行槽")
        XCTAssertEqual(model.activeAttempt?.attemptID, slotID)

        engine.release(outcome: .success, exitCode: 0)
        _ = await start.value
    }

    func testModelStoresExecutionFactsOnlyInTheSlot() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let model = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/RestoreWorkspaceModel.swift"),
            encoding: .utf8)
        XCTAssertFalse(model.contains("@Published private(set) var currentTask"))
        XCTAssertFalse(model.contains("@Published private(set) var activeAttempt"))
        XCTAssertTrue(model.contains("var currentTask: RestoreTaskSnapshot?"))
        XCTAssertTrue(model.contains("var activeAttempt: PendingRestoreAttempt?"))
        XCTAssertTrue(model.contains(
            "@Published private(set) var executionSlot: RestoreExecutionSlot?"))
        XCTAssertTrue(model.contains("get { executionSlot?.task }"))
        XCTAssertTrue(model.contains("get { executionSlot?.attempt }"))
        XCTAssertTrue(model.contains("get { executionSlot?.runTask }"))
    }

    // MARK: - 工具

    private func makeAttempt() -> PendingRestoreAttempt {
        let now = RestoreLifecycleClock.now()
        return PendingRestoreAttempt(
            attemptID: UUID(),
            taskID: UUID(),
            target: makeTarget(),
            canonicalECID: canonicalHex,
            stablePortKey: "host|left1",
            portDisplayName: "左侧上方",
            ipswURL: URL(fileURLWithPath: "/tmp/slot.ipsw"),
            ipswIdentity: nil,
            firmwareLibraryEntryID: nil,
            buildManifestSHA256: "",
            rawPersistencePolicy: RestoreRawPersistencePolicy(
                autoSaveDefault: false,
                saveThisRun: false,
                destinationDirectory: "",
                autoMonitorEnabled: false,
                spaceWarningThresholdBytes: nil,
                retentionPolicy: "none"),
            userConfirmedAt: now,
            stage: .waitingForFreshHeartbeat,
            lifecycle: RestoreLifecycleTimes(userConfirmed: now))
    }

    private func makeTask(attemptID: UUID) -> RestoreTaskSnapshot {
        RestoreTaskSnapshot(
            id: attemptID,
            attemptID: attemptID,
            target: makeTarget(),
            ipswURL: URL(fileURLWithPath: "/tmp/slot.ipsw"),
            ipswIdentity: nil,
            firmwareLibraryEntryID: nil,
            buildManifestSHA256: "",
            wholeFileSHA256: nil,
            rawOutputDirectory: nil,
            metadata: nil,
            compatibility: HardwareCompatibility(status: .unverified, message: ""),
            rlmStatus: .notRequested,
            rlmOwnership: .notRequested,
            rlmFinalizedAt: nil,
            rlmDrainDurationSeconds: nil,
            rlmRawLogURL: nil,
            rawPersistencePolicy: RestoreRawPersistencePolicy(
                autoSaveDefault: false,
                saveThisRun: false,
                destinationDirectory: "",
                autoMonitorEnabled: false,
                spaceWarningThresholdBytes: nil,
                retentionPolicy: "none"),
            rawEvidenceStatus: .notRequested,
            lifecycle: RestoreLifecycleTimes(userConfirmed: RestoreLifecycleClock.now()),
            attemptStage: .waitingForFreshHeartbeat,
            userConfirmedAt: Date(),
            phase: .userConfirmed,
            outcome: nil)
    }

    private func makeTarget() -> RestoreTarget {
        RestoreTarget(
            ecid: ecid,
            canonicalHex: canonicalHex,
            productType: "Mac14,2",
            deviceClass: "j413ap",
            boardID: 0x24,
            chipID: 0x8132,
            locationID: "01100000",
            connectionGeneration: 1,
            portKey: "left1",
            portDisplayName: "左侧上方",
            mode: .dfu,
            displayName: "MacBookPro18,2",
            machineIdentifier: "Mac14,2")
    }

    private func makeModel(engine: SlotFakeEngine) -> (RestoreWorkspaceModel, DeviceControlModel) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Slot-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let reader: (URL) throws -> IPSWMetadataReadResult = { _ in
            IPSWMetadataReadResult(
                validity: .valid,
                metadata: IPSWMetadata(
                    productTypes: ["Mac14,2"],
                    identities: [IPSWBuildIdentity(deviceClass: "j413ap", boardID: 0x24, chipID: 0x8132)],
                    productVersion: "14.0",
                    productBuild: "23A344"),
                error: nil)
        }
        let library = FirmwareLibraryStore(
            indexURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("SlotLib-\(UUID().uuidString).json"),
            metadataLoader: reader)
        let calibration = CalibrationStore(
            testingDocument: CalibrationDocument(models: [], ports: [], selectedPort: ""),
            hostModel: "MacTest,1",
            builtInLayout: nil)
        let device = DeviceControlModel(
            calibration: calibration,
            livePorts: [],
            helperAvailable: false,
            persistPortSelection: false,
            startLiveWork: false)
        let model = RestoreWorkspaceModel(
            capture: SlotFakeCapture(),
            engine: engine,
            outputRoot: root,
            maximumSnapshotAge: 1,
            heartbeatPollInterval: 0.005,
            observationHeartbeat: device.observationHeartbeat,
            portKeyResolver: { $0.locationID },
            portDisplayNameResolver: { "端口-\($0)" },
            metadataReader: reader,
            cfgutilURL: URL(fileURLWithPath: "/usr/bin/true"),
            firmwareLibrary: library,
            processLease: RestoreProcessLease(
                lockURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("SlotLease-\(UUID().uuidString).lease")))
        return (model, device)
    }

    private func publishDevice(to control: DeviceControlModel) {
        control.applyObservationResult(.success([makeObservedDevice()]), now: Date())
    }

    private func makeObservedDevice() -> ObservedDevice {
        ObservedDevice(
            id: "ecid:\(canonicalHex)",
            ecid: canonicalHex,
            mode: .dfu,
            locationID: "01100000",
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:\(canonicalHex)",
            modelIdentifier: "Mac14,2",
            chipID: 0x8132,
            boardID: 0x24,
            hardwareCode: "j413ap",
            productType: "Mac14,2")
    }

    private func firmwareURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("slot-\(UUID().uuidString).ipsw")
        try Data("slot".utf8).write(to: url)
        return url
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), "condition not met")
    }
}

@MainActor
private final class SlotFakeEngine: RestoreEngineRunning {
    var isRunning = false
    var cancellationGraceExpired = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var runCount = 0
    private var pendingOutcome: RestoreOutcome = .canceled
    private var pendingExit: Int32?

    func run(
        request: CfgutilRestoreRequest,
        launchPermitted: @escaping @MainActor () -> Bool,
        onUpdate: (@MainActor (RestoreOutputSnapshot) -> Void)?
    ) async -> CfgutilRestoreRunResult {
        runCount += 1
        guard launchPermitted() else {
            return result(outcome: .canceled)
        }
        isRunning = true
        var snapshot = RestoreOutputSnapshot()
        snapshot.processLaunched = RestoreLifecycleClock.now()
        snapshot.restoreActivityObserved = true
        snapshot.stepText = "RestoreOS"
        onUpdate?(snapshot)
        await withCheckedContinuation { continuation = $0 }
        isRunning = false
        return result(outcome: pendingOutcome, exitCode: pendingExit)
    }

    func cancel() {
        pendingOutcome = .canceled
        continuation?.resume()
        continuation = nil
    }

    func forceKill() {}

    func release(outcome: RestoreOutcome, exitCode: Int32?) {
        pendingOutcome = outcome
        pendingExit = exitCode
        continuation?.resume()
        continuation = nil
    }

    private func result(outcome: RestoreOutcome, exitCode: Int32? = nil) -> CfgutilRestoreRunResult {
        CfgutilRestoreRunResult(
            outcome: outcome,
            exitCode: exitCode,
            stdoutURL: nil,
            stderrURL: nil,
            stdoutSHA256: "",
            stderrSHA256: "",
            tailComplete: outcome != .unknown,
            cancellationRequested: outcome == .canceled,
            forcedKill: false,
            snapshot: RestoreOutputSnapshot())
    }
}

@MainActor
private final class SlotFakeCapture: RestoreCaptureLifecycle {
    var state: CaptureState = .idle
    var currentRawLogURL: URL? = nil
    func start(preCaptureContext: String?, automatic: Bool) { state = .recording }
    func stop() { state = .finalizing }
}

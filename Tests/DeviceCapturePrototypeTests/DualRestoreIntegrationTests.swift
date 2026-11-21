import Foundation
import XCTest
@testable import DeviceCapturePrototype
import RestoreLogEngine

/// 切片 2：真实产品模型 + 两套真实 `CfgutilRestoreEngine`（注入 spy launcher）
/// 的双任务离线集成验证。不调用真实 cfgutil，不操作硬件。
@MainActor
final class DualRestoreIntegrationTests: XCTestCase {
    private var launcherA: DualSpyLauncher!
    private var launcherB: DualSpyLauncher!
    private var model: RestoreWorkspaceModel!
    private var control: DeviceControlModel!
    private let ecidA = "0000000012345670"
    private let ecidB = "0000000012345671"
    private var directory: URL!
    private var history: RestoreHistoryStore!

    override func setUp() async throws {
        launcherA = DualSpyLauncher()
        launcherB = DualSpyLauncher()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Dual-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let reader: (URL) throws -> IPSWMetadataReadResult = { url in
            IPSWMetadataReadResult(
                validity: .valid,
                metadata: IPSWMetadata(
                    productTypes: ["Mac14,2"],
                    identities: [IPSWBuildIdentity(deviceClass: "j413ap", boardID: 0x24, chipID: 0x8132)],
                    productVersion: "14.0",
                    productBuild: "23A344"),
                error: nil,
                fileIdentity: try? IPSWMetadataReader.fileIdentity(
                    url: url, buildManifestSHA256: "dual-fixture"),
                buildManifestSHA256: "dual-fixture")
        }
        let library = FirmwareLibraryStore(
            indexURL: directory.appendingPathComponent("library.json"),
            metadataLoader: reader)
        let history = RestoreHistoryStore(
            fileURL: directory.appendingPathComponent("history.json"))
        self.history = history
        let calibration = CalibrationStore(
            testingDocument: CalibrationDocument(
                models: [],
                ports: [
                    PortCalibrationEntry(physicalPort: "left1", location: "01200000", label: "左侧上方", rid: "0", side: "左侧", controller: "AppleHPMDevice", portNumber: 1),
                    PortCalibrationEntry(physicalPort: "left2", location: "01100000", label: "左侧下方", rid: "1", side: "左侧", controller: "AppleHPMDevice", portNumber: 2),
                ],
                selectedPort: "AppleHPMDevice:2"),
            hostModel: "MacTest,1",
            builtInLayout: nil)
        control = DeviceControlModel(
            calibration: calibration,
            livePorts: [],
            helperAvailable: false,
            persistPortSelection: false,
            startLiveWork: false)
        let primaryEngine = CfgutilRestoreEngine(launcher: launcherA)
        model = RestoreWorkspaceModel(
            capture: DualFakeCapture(),
            engine: primaryEngine,
            outputRoot: directory,
            maximumSnapshotAge: 2,
            heartbeatPollInterval: 0.005,
            observationHeartbeat: control.observationHeartbeat,
            portKeyResolver: { $0.locationID },
            portDisplayNameResolver: { "端口-\($0)" },
            metadataReader: reader,
            cfgutilURL: URL(fileURLWithPath: "/usr/bin/true"),
            firmwareLibrary: library,
            historyStore: history,
            stablePortKeyProvider: { target in
                "host|\(target.portKey ?? "none")"
            },
            processLease: RestoreProcessLease(
                lockURL: directory.appendingPathComponent("machine.lease")),
            secondaryEngineFactory: { [weak self] in CfgutilRestoreEngine(launcher: self?.launcherB ?? DualSpyLauncher()) })
        publish([device(ecid: ecidA, location: "01100000")])
    }

    func testTwoRealEnginesOverlapAndLeaseHeldUntilLast() async throws {
        try await startPrimary()
        let b = try await makeSecondaryTarget()
        try await prepareDraft(for: b)
        let startedB = await self.model.testStartSecondaryThroughConfirmation(targetID: b.id)
        XCTAssertTrue(startedB)
        try await waitUntil { self.launcherB.launchCount == 1 }

        XCTAssertEqual(launcherA.launchCount, 1)
        XCTAssertEqual(launcherB.launchCount, 1)
        XCTAssertEqual(launcherA.request?.targetECID, 0x12345670)
        XCTAssertEqual(launcherB.request?.targetECID, 0x12345671)
        XCTAssertNotEqual(launcherA.request?.ipswURL, launcherB.request?.ipswURL)
        XCTAssertEqual(model.activeLeaseShareCount, 2)
        XCTAssertTrue(model.isMachineLeaseHeld)

        launcherA.complete(exitCode: 0)
        try await waitUntil { self.model.activeLeaseShareCount == 1 }
        XCTAssertTrue(model.isMachineLeaseHeld, "A 完成后 B 仍在运行，机器锁不得释放")

        launcherB.complete(exitCode: 1)
        try await waitUntil { self.model.activeLeaseShareCount == 0 }
        XCTAssertFalse(model.isMachineLeaseHeld)
        XCTAssertNotNil(model.lastCompletedTaskSnapshot)
        XCTAssertNotNil(model.lastSecondaryTaskSnapshot)
        XCTAssertNotEqual(
            model.lastCompletedTaskSnapshot?.attemptID,
            model.lastSecondaryTaskSnapshot?.attemptID)
        XCTAssertNil(model.lastSecondaryTaskSnapshot?.rawArchive,
                     "raw 关闭时不得生成 B 归档")
        let records = try await history.records()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(Set(records.map(\.attemptID)).count, 2,
                       "两台任务必须各自写入独立历史记录")
    }

    func testCancelingADoesNotSignalB() async throws {
        try await startPrimary()
        let b = try await makeSecondaryTarget()
        try await prepareDraft(for: b)
        let startedB = await self.model.testStartSecondaryThroughConfirmation(targetID: b.id)
        XCTAssertTrue(startedB)
        try await waitUntil { self.launcherA.launchCount == 1 && self.launcherB.launchCount == 1 }
        let attemptA = try XCTUnwrap(model.activeAttempt?.attemptID)

        model.cancelRestore(attemptID: attemptA)
        XCTAssertEqual(launcherA.lastProcess?.interruptCount, 1)
        XCTAssertEqual(launcherB.lastProcess?.interruptCount, 0)
        XCTAssertTrue(launcherB.lastProcess?.isRunning == true)

        launcherA.complete(exitCode: 130)
        try await waitUntil { self.model.activeLeaseShareCount == 1 }
        XCTAssertTrue(launcherB.lastProcess?.isRunning == true)
        launcherB.complete(exitCode: 0)
        try await waitUntil { self.model.activeLeaseShareCount == 0 }
    }

    func testSameDeviceOrPortOrSecondSecondaryIsRefused() async throws {
        try await startPrimary()
        let b = try await makeSecondaryTarget()
        try await prepareDraft(for: b)
        let startedB = await self.model.testStartSecondaryThroughConfirmation(targetID: b.id)
        XCTAssertTrue(startedB)
        try await waitUntil { self.launcherB.launchCount == 1 }

        // 第三个任务：已有两个活动任务。
        let third = await self.model.testStartSecondaryThroughConfirmation(targetID: b.id)
        XCTAssertFalse(third)
        // 同设备：A 的 ECID。
        let sameDevice = await self.model.testStartSecondaryThroughConfirmation(targetID: ecidA)
        XCTAssertFalse(sameDevice)

        launcherA.complete(exitCode: 0)
        launcherB.complete(exitCode: 0)
        try await waitUntil { self.model.activeLeaseShareCount == 0 }
    }

    func testSamePhysicalPortIsRefused() async throws {
        try await startPrimary()
        // B 使用与 A 相同的物理端口（同 location、不同 ECID）。
        publish([device(ecid: ecidA, location: "01100000"),
                 device(ecid: ecidB, location: "01100000")])
        model.refreshTargets()
        let deadline = Date().addingTimeInterval(2)
        var targetB: RestoreTarget?
        while Date() < deadline {
            targetB = model.availableTargets.first(where: { $0.canonicalHex == ecidB })
            if targetB != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let b = try XCTUnwrap(targetB)
        _ = await model.prepareFirmwareDraft(
            for: b, url: try firmware("b-same-port.ipsw"))
        let refused = await model.testStartSecondaryThroughConfirmation(targetID: b.id)
        XCTAssertFalse(refused)
        XCTAssertTrue(model.errorMessage.contains("同一物理端口"))
        XCTAssertEqual(launcherB.launchCount, 0)
        launcherA.complete(exitCode: 0)
        try await waitUntil { self.model.activeLeaseShareCount == 0 }
    }

    func testRLMCommitmentOnARefusesB() async throws {
        let coordinator = DualOwnedRLMCoordinator()
        model = makeModelWithCoordinator(coordinator)
        try await startPrimary()
        let b = try await makeSecondaryTarget()
        try await prepareDraft(for: b)
        let third = await self.model.testStartSecondaryThroughConfirmation(targetID: b.id)
        XCTAssertFalse(third)
        XCTAssertTrue(model.errorMessage.contains("RLM"))
        XCTAssertEqual(launcherB.launchCount, 0)
        XCTAssertFalse(model.hasSecondaryRestore)
        launcherA.complete(exitCode: 0)
        try await waitUntil { self.model.activeLeaseShareCount == 0 }
    }

    func testSameDeviceIsRefusedBeforeBActive() async throws {
        try await startPrimary()
        // 准备一个合法的 B 草稿，排除“草稿未就绪”导致的假通过。
        let b = try await makeSecondaryTarget()
        try await prepareDraft(for: b)
        let aTarget = try XCTUnwrap(model.currentTask?.target)
        let refused = await model.testStartSecondaryThroughConfirmation(
            targetID: aTarget.id)
        XCTAssertFalse(refused)
        XCTAssertTrue(model.errorMessage.contains("同一设备"))
        XCTAssertEqual(launcherB.launchCount, 0)
        launcherA.complete(exitCode: 0)
        try await waitUntil { self.model.activeLeaseShareCount == 0 }
    }

    func testDuplicateECIDObservationRefusesB() async throws {
        try await startPrimary()
        publish([device(ecid: ecidA, location: "01100000"),
                 device(ecid: ecidB, location: "01200000"),
                 device(ecid: ecidB, location: "02100000")])
        model.refreshTargets()
        let targetB = try await waitForTarget(ecidB)
        _ = await model.prepareFirmwareDraft(
            for: targetB, url: try firmware("b.ipsw"))
        let refused = await model.testStartSecondaryThroughConfirmation(targetID: targetB.id)
        XCTAssertFalse(refused)
        XCTAssertTrue(model.errorMessage.contains("不唯一"))
        XCTAssertEqual(launcherB.launchCount, 0)
        launcherA.complete(exitCode: 0)
        try await waitUntil { self.model.activeLeaseShareCount == 0 }
    }

    func testRLMCommitmentWindowRefusesB() async throws {
        let coordinator = DualBlockingRLMCoordinator()
        model = makeModelWithCoordinator(coordinator)
        publish([device(ecid: ecidA, location: "01100000")])
        model.refreshTargets()
        model.selectTarget(id: ecidA)
        await model.loadFirmware(url: try firmware("a.ipsw"))
        publish([device(ecid: ecidA, location: "01100000")])
        let start = Task { await model.testStartPrimaryThroughConfirmation() }
        try await waitUntil { self.model.currentTask?.attemptStage == .preparingRLM }
        let b = try await makeSecondaryTarget()
        try await prepareDraft(for: b)
        let refused = await model.testStartSecondaryThroughConfirmation(targetID: b.id)
        XCTAssertFalse(refused)
        XCTAssertTrue(model.errorMessage.contains("确认"))
        coordinator.release()
        try await waitUntil { self.launcherA.launchCount == 1 }
        launcherA.complete(exitCode: 0)
        _ = await start.value
        try await waitUntil { self.model.activeLeaseShareCount == 0 }
    }

    func testCancelingBDoesNotSignalA() async throws {
        try await startPrimary()
        let b = try await makeSecondaryTarget()
        try await prepareDraft(for: b)
        let startedB = await model.testStartSecondaryThroughConfirmation(targetID: b.id)
        XCTAssertTrue(startedB)
        try await waitUntil { self.launcherA.launchCount == 1 && self.launcherB.launchCount == 1 }
        let bID = try XCTUnwrap(model.secondaryAttemptID)

        model.cancelRestore(attemptID: bID)
        XCTAssertEqual(launcherB.lastProcess?.interruptCount, 1)
        XCTAssertEqual(launcherA.lastProcess?.interruptCount, 0)
        XCTAssertTrue(launcherA.lastProcess?.isRunning == true)

        launcherB.complete(exitCode: 130)
        try await waitUntil { self.model.activeLeaseShareCount == 1 }
        XCTAssertTrue(launcherA.lastProcess?.isRunning == true)
        launcherA.complete(exitCode: 0)
        try await waitUntil { self.model.activeLeaseShareCount == 0 }
    }

    func testPrimaryCannotStartWhileBIsActive() async throws {
        try await startPrimary()
        let b = try await makeSecondaryTarget()
        try await prepareDraft(for: b)
        let startedB = await model.testStartSecondaryThroughConfirmation(targetID: b.id)
        XCTAssertTrue(startedB)
        try await waitUntil { self.launcherB.launchCount == 1 }
        launcherA.complete(exitCode: 0)
        try await waitUntil { self.model.activeLeaseShareCount == 1 && self.model.currentTask == nil }

        // G2：B 仍在运行但首槽已空时，允许新首任务补位（容量 2）。
        let primaryRun = Task { @MainActor in
            await self.model.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { self.launcherA.launchCount == 2 }
        XCTAssertEqual(model.taskRegistry.activeCount, 2)
        launcherA.complete(exitCode: 0)
        await primaryRun.value

        launcherB.complete(exitCode: 0)
        try await waitUntil { self.model.activeLeaseShareCount == 0 }
    }

    func testRealOSProcessesOverlapAndSurvivePeers() async throws {
        let realA = DualRealLauncher()
        let realB = DualRealLauncher()
        let reader: (URL) throws -> IPSWMetadataReadResult = { url in
            IPSWMetadataReadResult(
                validity: .valid,
                metadata: IPSWMetadata(
                    productTypes: ["Mac14,2"],
                    identities: [IPSWBuildIdentity(deviceClass: "j413ap", boardID: 0x24, chipID: 0x8132)],
                    productVersion: "14.0",
                    productBuild: "23A344"),
                error: nil,
                fileIdentity: try? IPSWMetadataReader.fileIdentity(
                    url: url, buildManifestSHA256: "dual-fixture"),
                buildManifestSHA256: "dual-fixture")
        }
        let live = RestoreWorkspaceModel(
            capture: DualFakeCapture(),
            engine: CfgutilRestoreEngine(launcher: realA),
            outputRoot: directory,
            maximumSnapshotAge: 30,
            heartbeatPollInterval: 0.005,
            observationHeartbeat: control.observationHeartbeat,
            portKeyResolver: { $0.locationID },
            portDisplayNameResolver: { "端口-\($0)" },
            metadataReader: reader,
            cfgutilURL: URL(fileURLWithPath: "/usr/bin/true"),
            firmwareLibrary: FirmwareLibraryStore(
                indexURL: directory.appendingPathComponent("library-real.json"),
                metadataLoader: reader),
            historyStore: RestoreHistoryStore(
                fileURL: directory.appendingPathComponent("history-real.json")),
            stablePortKeyProvider: { target in "host|\(target.portKey ?? "none")" },
            processLease: RestoreProcessLease(
                lockURL: directory.appendingPathComponent("machine.lease")),
            secondaryEngineFactory: { CfgutilRestoreEngine(launcher: realB) })
        model = live
        try await startPrimary()
        let b = try await makeSecondaryTarget()
        try await prepareDraft(for: b)
        model.setRawSaveRequested(true, for: b)
        publish([device(ecid: ecidA, location: "01100000"),
                 device(ecid: ecidB, location: "01200000")])
        let startedB = await model.testStartSecondaryThroughConfirmation(targetID: b.id)
        XCTAssertTrue(startedB, "B refused: \(model.errorMessage)")
        try await waitUntil { realA.count == 1 && realB.count == 1 }
        try await waitUntil { realA.last?.isRunning == true && realB.last?.isRunning == true }

        let processA = try XCTUnwrap(realA.last)
        let processB = try XCTUnwrap(realB.last)
        XCTAssertGreaterThan(processA.pid, 0)
        XCTAssertGreaterThan(processB.pid, 0)
        XCTAssertNotEqual(processA.pid, processB.pid)
        XCTAssertLessThan(processA.startedAt, processB.startedAt)
        XCTAssertTrue(processA.isRunning, "B 启动时 A 的真实子进程必须仍在运行")
        XCTAssertTrue(processB.isRunning)

        processA.terminate()  // A 结束
        try await waitUntil { self.model.activeLeaseShareCount == 1 }
        XCTAssertTrue(processB.isRunning, "A 结束后 B 的真实子进程必须继续运行")
        XCTAssertTrue(model.isMachineLeaseHeld)

        let bID = try XCTUnwrap(model.secondaryAttemptID)
        model.cancelRestore(attemptID: bID)
        XCTAssertEqual(processB.interruptCount, 1)
        try await waitUntil { self.model.activeLeaseShareCount == 0 }
        XCTAssertFalse(model.isMachineLeaseHeld)
        // 清理由测试拥有的残留进程
        processA.forceKill()
        processB.forceKill()
    }

    func testBRawArchivesAndHistoryKeepsIt() async throws {
        model.setRawSaveRequestedThisRun(true)
        try await startPrimary()
        let b = try await makeSecondaryTarget()
        try await prepareDraft(for: b)
        model.setRawSaveRequested(true, for: b)
        publish([device(ecid: ecidA, location: "01100000"),
                 device(ecid: ecidB, location: "01200000")])
        let startedB = await model.testStartSecondaryThroughConfirmation(targetID: b.id)
        XCTAssertTrue(startedB, model.errorMessage)
        try await waitUntil { self.launcherA.launchCount == 1 && self.launcherB.launchCount == 1 }

        launcherA.complete(exitCode: 0)
        launcherB.complete(exitCode: 1)
        try await waitUntil {
            self.model.lastSecondaryTaskSnapshot != nil
                && self.model.activeLeaseShareCount == 0
        }
        let secondary = try XCTUnwrap(model.lastSecondaryTaskSnapshot)
        XCTAssertTrue(secondary.rawPersistencePolicy.saveThisRun)
        XCTAssertNotNil(secondary.rawArchive, secondary.rawArchiveMessage)
        let records = try await history.records()
        let record = try XCTUnwrap(records.first { $0.attemptID == secondary.attemptID })
        XCTAssertNotNil(record.rawArchive)
        XCTAssertNotEqual(record.attemptID, model.lastCompletedTaskSnapshot?.attemptID)

        // 实际导出 B 的归档（A/B 共用同一适配层），并做归属隔离检查。
        let bDestination = directory.appendingPathComponent("b-export.zip")
        let bExport = try model.exportRawArchive(
            attemptID: secondary.attemptID,
            to: bDestination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: bDestination.path))
        XCTAssertGreaterThan(bExport.bytes, 0)
        XCTAssertEqual(bExport.url, bDestination)

        let aSnapshot = try XCTUnwrap(model.lastCompletedTaskSnapshot)
        let aDestination = directory.appendingPathComponent("a-export.zip")
        let aExport = try model.exportRawArchive(
            attemptID: aSnapshot.attemptID,
            to: aDestination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: aDestination.path))
        XCTAssertGreaterThan(aExport.bytes, 0)
        XCTAssertNotEqual(bExport.sha256, aExport.sha256)
        XCTAssertThrowsError(try model.exportRawArchive(
            attemptID: UUID(),
            to: directory.appendingPathComponent("nope.zip"))) { error in
            guard case RestoreRawExportError.noArchive = error else {
                return XCTFail("unexpected \(error)")
            }
        }
    }


    func testForceKillAPrimaryKeepsBRunningAndEndsWithCleanLease() async throws {
        launcherA.ignoreSignals = true
        try await startPrimary()
        let b = try await makeSecondaryTarget()
        try await prepareDraft(for: b)
        publish([device(ecid: ecidA, location: "01100000"),
                 device(ecid: ecidB, location: "01200000")])
        let startedB = await model.testStartSecondaryThroughConfirmation(targetID: b.id)
        XCTAssertTrue(startedB, model.errorMessage)
        try await waitUntil { self.launcherA.launchCount == 1 && self.launcherB.launchCount == 1 }
        let aID = try XCTUnwrap(model.currentAttemptID)
        model.cancelRestore()
        model.forceKillRestore()
        try await waitUntil {
            self.model.lastCompletedTaskSnapshot?.attemptID == aID
                && self.model.lastCompletedTaskSnapshot?.outcome == .canceled
        }
        XCTAssertTrue(model.lastCompletedTaskSnapshot?.forcedKill == true)
        XCTAssertTrue(self.launcherB.lastProcess?.isRunning == true)
        self.launcherB.completeSuccess()
        try await waitUntil {
            self.model.lastSecondaryTaskSnapshot?.outcome == .success
                && self.model.activeLeaseShareCount == 0
        }
        XCTAssertEqual(model.taskRegistry.activeCount, 0)
        XCTAssertFalse(model.isMachineLeaseHeld)
    }

    func testForceKillBSecondaryKeepsARunningAndEndsWithCleanLease() async throws {
        launcherB.ignoreSignals = true
        try await startPrimary()
        let b = try await makeSecondaryTarget()
        try await prepareDraft(for: b)
        publish([device(ecid: ecidA, location: "01100000"),
                 device(ecid: ecidB, location: "01200000")])
        let startedB = await model.testStartSecondaryThroughConfirmation(targetID: b.id)
        XCTAssertTrue(startedB, model.errorMessage)
        try await waitUntil { self.launcherA.launchCount == 1 && self.launcherB.launchCount == 1 }
        let bID = try XCTUnwrap(model.secondaryAttemptID)
        model.cancelRestore(attemptID: bID)
        model.forceKillSecondaryRestore(attemptID: bID)
        try await waitUntil { self.model.lastSecondaryTaskSnapshot?.outcome == .canceled }
        XCTAssertTrue(model.lastSecondaryTaskSnapshot?.forcedKill == true)
        XCTAssertTrue(self.launcherA.lastProcess?.isRunning == true)
        self.launcherA.completeSuccess()
        try await waitUntil {
            self.model.lastCompletedTaskSnapshot?.outcome == .success
                && self.model.activeLeaseShareCount == 0
        }
        XCTAssertEqual(model.taskRegistry.activeCount, 0)
        XCTAssertFalse(model.isMachineLeaseHeld)
    }

    // MARK: - helpers

    private func modelLeaseURL() -> URL {
        directory.appendingPathComponent("machine.lease")
    }

    private func startPrimary() async throws {
        publish([device(ecid: ecidA, location: "01100000")])
        model.refreshTargets()
        model.selectTarget(id: ecidA)
        await model.loadFirmware(url: try firmware("a.ipsw"))
        publish([device(ecid: ecidA, location: "01100000")])
        let task = Task { await model.testStartPrimaryThroughConfirmation() }
        try await waitUntil { self.model.isRestoring }
        _ = task
    }

    private func makeSecondaryTarget() async throws -> RestoreTarget {
        publish([device(ecid: ecidA, location: "01100000"),
                 device(ecid: ecidB, location: "01200000")])
        model.refreshTargets()
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let b = model.availableTargets.first(where: { $0.canonicalHex == ecidB }) {
                return b
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw XCTSkip("second target not observed")
    }

    private func waitForTarget(_ ecid: String) async throws -> RestoreTarget {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let target = model.availableTargets.first(where: { $0.canonicalHex == ecid }) {
                return target
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw XCTSkip("target not observed")
    }

    private func prepareDraft(for target: RestoreTarget) async throws {
        let ok = await model.prepareFirmwareDraft(
            for: target, url: try firmware("b.ipsw"))
        XCTAssertTrue(ok)
        XCTAssertEqual(model.firmwareDraftStatus(for: target), .ready)
    }

    private func makeModelWithCoordinator(
        _ coordinator: any RestoreRLMPreparing
    ) -> RestoreWorkspaceModel {
        let primary = CfgutilRestoreEngine(launcher: launcherA)
        let reader: (URL) throws -> IPSWMetadataReadResult = { url in
            IPSWMetadataReadResult(
                validity: .valid,
                metadata: IPSWMetadata(
                    productTypes: ["Mac14,2"],
                    identities: [IPSWBuildIdentity(deviceClass: "j413ap", boardID: 0x24, chipID: 0x8132)],
                    productVersion: "14.0",
                    productBuild: "23A344"),
                error: nil,
                fileIdentity: try? IPSWMetadataReader.fileIdentity(
                    url: url, buildManifestSHA256: "dual-fixture"),
                buildManifestSHA256: "dual-fixture")
        }
        return RestoreWorkspaceModel(
            capture: DualFakeCapture(),
            engine: primary,
            outputRoot: directory,
            maximumSnapshotAge: 2,
            heartbeatPollInterval: 0.005,
            observationHeartbeat: control.observationHeartbeat,
            portKeyResolver: { $0.locationID },
            portDisplayNameResolver: { "端口-\($0)" },
            metadataReader: reader,
            cfgutilURL: URL(fileURLWithPath: "/usr/bin/true"),
            rlmCoordinator: coordinator,
            firmwareLibrary: FirmwareLibraryStore(
                indexURL: directory.appendingPathComponent("library2.json"),
                metadataLoader: reader),
            historyStore: RestoreHistoryStore(
                fileURL: directory.appendingPathComponent("history2.json")),
            stablePortKeyProvider: { target in
                "host|\(target.portKey ?? "none")"
            },
            processLease: RestoreProcessLease(lockURL: modelLeaseURL()),
            secondaryEngineFactory: { [weak self] in CfgutilRestoreEngine(launcher: self?.launcherB ?? DualSpyLauncher()) })
    }

    private func publish(_ devices: [ObservedDevice]) {
        control.applyObservationResult(.success(devices), now: Date())
    }

    private func device(ecid: String, location: String) -> ObservedDevice {
        ObservedDevice(
            id: "ecid:\(ecid)",
            ecid: ecid,
            mode: .dfu,
            locationID: location,
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:\(ecid)",
            modelIdentifier: "Mac14,2",
            chipID: 0x8132,
            boardID: 0x24,
            hardwareCode: "j413ap",
            productType: "Mac14,2")
    }

    private func firmware(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data("firmware".utf8).write(to: url)
        }
        return url
    }

    private func waitUntil(
        timeout: TimeInterval = 6,
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), "condition not met")
    }
}

@MainActor
final class DualSpyLauncher: CfgutilProcessLaunching {
    var ignoreSignals = false
    private(set) var launchCount = 0
    private(set) var request: CfgutilRestoreRequest?
    private(set) var lastProcess: DualSpyProcess?

    func launch(
        request: CfgutilRestoreRequest,
        onChunk: @escaping @Sendable (RestoreOutputChannel, Data) -> Void
    ) throws -> any CfgutilProcessRunning {
        launchCount += 1
        self.request = request
        let process = DualSpyProcess()
        process.ignoreSignals = ignoreSignals
        process.onChunk = onChunk
        process.targetECID = request.targetECID
        lastProcess = process
        return process
    }

    func complete(exitCode: Int32) {
        lastProcess?.complete(exitCode: exitCode)
    }

    func completeSuccess() {
        lastProcess?.completeSuccess()
    }
}

@MainActor
final class DualSpyProcess: CfgutilProcessRunning {
    var processLaunched: RestoreLifecycleTimePoint? = RestoreLifecycleClock.now()
    var ignoreSignals = false
    var onChunk: (@Sendable (RestoreOutputChannel, Data) -> Void)?
    var targetECID: UInt64 = 0
    private(set) var interruptCount = 0
    private var continuation: CheckedContinuation<CfgutilProcessCompletion, Never>?
    var isRunning = false

    func waitForCompletion(tailTimeout: TimeInterval) async -> CfgutilProcessCompletion {
        isRunning = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func interrupt() {
        interruptCount += 1
        guard !ignoreSignals else { return }
        complete(exitCode: 130)
    }

    func terminate() {
        guard !ignoreSignals else { return }
        complete(exitCode: 143)
    }
    func forceKill() { complete(exitCode: 137, forcedKill: true) }

    func completeSuccess() {
        onChunk?(.stdout, Data("Step = \"RestoreOS\"; Type = Step;\n".utf8))
        onChunk?(.stdout, Data("Restored System on Unknown device (ECID: \(targetECID)).\n".utf8))
        onChunk?(.stdout, Data(#"Operation "restore" succeeded on 1 devices."#.utf8))
        onChunk?(.stderr, Data("diagnostic stderr\n".utf8))
        complete(exitCode: 0)
    }

    func complete(exitCode: Int32, forcedKill: Bool = false) {
        guard isRunning, let continuation else { return }
        isRunning = false
        self.continuation = nil
        continuation.resume(returning: CfgutilProcessCompletion(
            exitCode: exitCode,
            stdoutEOF: true,
            stderrEOF: true,
            forcedKill: forcedKill,
            processExited: nil,
            bothStreamsEOF: nil,
            terminationReason: .exit))
    }
}

@MainActor
final class DualFakeCapture: RestoreCaptureLifecycle {
    var state: CaptureState = .idle
    var currentRawLogURL: URL? = nil
    func start(preCaptureContext: String?, automatic: Bool) { state = .recording }
    func stop() { state = .finalizing }
}

@MainActor
final class DualBlockingRLMCoordinator: RestoreRLMPreparing {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func prepare(taskID: UUID, canonicalECID: String) async -> RestoreRLMBinding {
        await prepare(taskID: taskID, canonicalECID: canonicalECID, saveRequested: false)
    }

    func prepare(
        taskID: UUID,
        canonicalECID: String,
        saveRequested: Bool
    ) async -> RestoreRLMBinding {
        if !released {
            await withCheckedContinuation { continuation = $0 }
        }
        return RestoreRLMBinding(
            taskID: taskID,
            canonicalECID: canonicalECID,
            status: .notRequested,
            rawLogURL: nil,
            startAt: Date(),
            endAt: nil,
            reason: "blocked",
            ownership: .notRequested)
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }

    func finish(taskID: UUID, outcome: RestoreOutcome) async {}
}

@MainActor
final class DualOwnedRLMCoordinator: RestoreRLMPreparing {
    func prepare(taskID: UUID, canonicalECID: String) async -> RestoreRLMBinding {
        await prepare(taskID: taskID, canonicalECID: canonicalECID, saveRequested: false)
    }

    func prepare(
        taskID: UUID,
        canonicalECID: String,
        saveRequested: Bool
    ) async -> RestoreRLMBinding {
        RestoreRLMBinding(
            taskID: taskID,
            canonicalECID: canonicalECID,
            status: .startedOwnedSession,
            rawLogURL: URL(fileURLWithPath: "/tmp/rlm.log"),
            startAt: Date(),
            endAt: nil,
            reason: "test-owned",
            ownership: .restoreOwned)
    }

    func finish(taskID: UUID, outcome: RestoreOutcome) async {}
}


@MainActor
final class DualRealLauncher: CfgutilProcessLaunching {
    private(set) var count = 0
    private(set) var last: DualRealProcess?
    func launch(
        request: CfgutilRestoreRequest,
        onChunk: @escaping @Sendable (RestoreOutputChannel, Data) -> Void
    ) throws -> any CfgutilProcessRunning {
        let process = DualRealProcess()
        do { try process.start() } catch {
            print("DUAL-REAL-LAUNCH-ERROR \(error)")
            throw error
        }
        count += 1
        last = process
        return process
    }
}

@MainActor
final class DualRealProcess: CfgutilProcessRunning {
    let process = Process()
    let startedAt = Date()
    private(set) var interruptCount = 0
    var pid: Int32 { process.processIdentifier }
    var isRunning: Bool { process.isRunning }
    var processLaunched: RestoreLifecycleTimePoint? { RestoreLifecycleClock.now() }

    func start() throws {
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["120"]
        try process.run()
    }

    func waitForCompletion(tailTimeout: TimeInterval) async -> CfgutilProcessCompletion {
        if process.isRunning {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in continuation.resume() }
            }
        }
        return CfgutilProcessCompletion(
            exitCode: process.terminationStatus,
            stdoutEOF: true,
            stderrEOF: true,
            forcedKill: false,
            processExited: nil,
            bothStreamsEOF: nil,
            terminationReason: .exit)
    }

    func interrupt() {
        interruptCount += 1
        process.interrupt()
    }

    func terminate() { process.terminate() }
    func forceKill() {
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
}

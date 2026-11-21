import Foundation
import XCTest
@testable import DeviceCapturePrototype
import RestoreLogEngine

@MainActor
final class RestoreWorkspaceModelTests: XCTestCase {
    private let ecid: UInt64 = 0x12345670

    func testPreflightRejectsStaleHeartbeatAndDoesNotLaunchCfgutil() async throws {
        let capture = WorkspaceFakeCapture(state: .idle)
        let engine = WorkspaceFakeEngine()
        let deviceControl = makeDeviceControl()
        let model = makeModel(
            capture: capture,
            engine: engine,
            deviceControl: deviceControl,
            maximumSnapshotAge: 0.08)
        publish(device(), to: deviceControl)
        model.refreshTargets()
        model.selectTarget(id: canonicalHex)
        await model.loadFirmware(url: try firmwareURL())
        try await Task.sleep(nanoseconds: 110_000_000)

        await model.testStartPrimaryThroughConfirmation()

        XCTAssertEqual(engine.requestCount, 0)
        XCTAssertTrue(
            model.lastCompletedTaskSnapshot?.failureText.contains("观察") == true)
        XCTAssertNil(model.currentTask)
    }

    func testStartFreezesTargetWhenHeartbeatLaterHasNoDevice() async throws {
        let capture = WorkspaceFakeCapture(state: .idle)
        let engine = WorkspaceFakeEngine()
        let deviceControl = makeDeviceControl()
        let model = makeModel(
            capture: capture,
            engine: engine,
            deviceControl: deviceControl)
        publish(device(), to: deviceControl)
        model.refreshTargets()
        model.selectTarget(id: canonicalHex)
        await model.loadFirmware(url: try firmwareURL())
        publish(device(), to: deviceControl)

        let run = Task { @MainActor in
            await model.testStartPrimaryThroughConfirmation()
        }
        for _ in 0..<200 where engine.request == nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        XCTAssertEqual(engine.request?.targetECID, ecid)
        XCTAssertEqual(engine.request?.arguments[3], String(ecid))
        XCTAssertEqual(model.activeAttempt?.canonicalECID, canonicalHex)
        XCTAssertTrue(model.isRestoreTaskActive)
        XCTAssertFalse(model.isRestoring)

        deviceControl.applyObservationResult(.success([]), now: Date())
        model.refreshTargets()
        XCTAssertEqual(model.activeAttempt?.target.canonicalHex, canonicalHex)

        engine.complete()
        await run.value
        XCTAssertNil(model.activeAttempt)
        XCTAssertEqual(model.lastCompletedTaskSnapshot?.target.canonicalHex, canonicalHex)
    }

    func testRawSaveRequestDoesNotStartOrJoinRLMButCfgutilStillRuns() async throws {
        let capture = WorkspaceFakeCapture(state: .stopping)
        let engine = WorkspaceFakeEngine()
        let deviceControl = makeDeviceControl()
        let rlmCoordinator = RestoreRLMCoordinator(
            capture: capture,
            startupTimeout: 0.01,
            drainTimeout: 0.01,
            pollInterval: 0.002)
        let model = makeModel(
            capture: capture,
            engine: engine,
            deviceControl: deviceControl,
            rlmCoordinator: rlmCoordinator)
        publish(device(), to: deviceControl)
        model.refreshTargets()
        model.selectTarget(id: canonicalHex)
        await model.loadFirmware(url: try firmwareURL())
        publish(device(), to: deviceControl)
        model.setRawSaveRequestedThisRun(true)
        let run = Task { @MainActor in
            await model.testStartPrimaryThroughConfirmation()
        }
        for _ in 0..<200 where engine.request == nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        XCTAssertEqual(capture.startCount, 0)
        XCTAssertEqual(model.currentTask?.rlmStatus, .notRequested)
        XCTAssertEqual(model.currentTask?.rlmOwnership, .notRequested)
        XCTAssertEqual(capture.startCount, 0)
        engine.complete()
        await run.value
        XCTAssertNotNil(model.lastCompletedTaskSnapshot?.outcome)
    }

    func testAutomaticSingleTargetDoesNotCountAsUserRestorePreparation() async throws {
        let capture = WorkspaceFakeCapture(state: .idle)
        let engine = WorkspaceFakeEngine()
        let deviceControl = makeDeviceControl()
        let model = makeModel(
            capture: capture,
            engine: engine,
            deviceControl: deviceControl)
        publish(device(), to: deviceControl)
        model.refreshTargets()

        XCTAssertNotNil(model.selectedTargetID)
        XCTAssertFalse(model.hasUserRestorePreparationContext)

        model.selectTarget(id: canonicalHex)
        XCTAssertTrue(model.hasUserRestorePreparationContext)

        await model.loadFirmware(url: try firmwareURL())
        XCTAssertTrue(model.hasUserRestorePreparationContext)
        let selectedTargetID = model.selectedTargetID
        let firmwareURL = model.firmwareURL

        model.resumeAutomaticNavigationAfterUserAction()

        XCTAssertFalse(model.hasUserRestorePreparationContext)
        XCTAssertEqual(model.selectedTargetID, selectedTargetID)
        XCTAssertEqual(model.firmwareURL, firmwareURL)
    }

    func testTerminalOutcomeDuringEvidenceFinalizationCannotBeCanceled() async throws {
        let capture = WorkspaceFakeCapture(state: .idle)
        let engine = WorkspaceFakeEngine()
        let deviceControl = makeDeviceControl()
        let rlmCoordinator = BlockingWorkspaceRLMCoordinator()
        let model = makeModel(
            capture: capture,
            engine: engine,
            deviceControl: deviceControl,
            rlmCoordinator: rlmCoordinator)
        publish(device(), to: deviceControl)
        model.refreshTargets()
        model.selectTarget(id: canonicalHex)
        await model.loadFirmware(url: try firmwareURL())
        publish(device(), to: deviceControl)

        let run = Task { @MainActor in
            await model.testStartPrimaryThroughConfirmation()
        }
        for _ in 0..<200 where engine.request == nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        engine.complete()
        for _ in 0..<200 where !rlmCoordinator.finishStarted {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        XCTAssertTrue(rlmCoordinator.finishStarted)
        XCTAssertTrue(model.isRestoreTaskActive)
        XCTAssertFalse(model.isRestoring)
        XCTAssertTrue(model.isFinalizingRestoreEvidence)
        XCTAssertFalse(model.canCancelRestoreTask)
        let cancellationBefore = model.currentTask?.cancellationRequested

        model.cancelRestore()

        XCTAssertEqual(
            model.currentTask?.cancellationRequested,
            cancellationBefore)

        rlmCoordinator.releaseFinish()
        await run.value
        XCTAssertNil(model.activeAttempt)
        XCTAssertFalse(model.isFinalizingRestoreEvidence)
    }

    func testTerminalOutcomeIsFrozenBeforeRawArchiveFinishes() async throws {
        let capture = WorkspaceFakeCapture(state: .idle)
        let engine = WorkspaceFakeEngine()
        let deviceControl = makeDeviceControl()
        let gate = RawArchiveObservationGate()
        let model = makeModel(
            capture: capture,
            engine: engine,
            deviceControl: deviceControl,
            rawArchiveObservationHook: {
                await gate.wait()
            })
        publish(device(), to: deviceControl)
        model.refreshTargets()
        model.selectTarget(id: canonicalHex)
        await model.loadFirmware(url: try firmwareURL())
        publish(device(), to: deviceControl)
        model.setRawSaveRequestedThisRun(true)

        let run = Task { @MainActor in
            await model.testStartPrimaryThroughConfirmation()
        }
        for _ in 0..<200 where engine.request == nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        engine.complete()
        for _ in 0..<200 where !gate.started {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        XCTAssertTrue(gate.started)
        XCTAssertEqual(model.currentTask?.outcome, .success)
        XCTAssertTrue(model.isRestoreTaskActive)
        XCTAssertFalse(model.isRestoring)
        XCTAssertTrue(model.isFinalizingRestoreEvidence)
        XCTAssertFalse(model.canCancelRestoreTask)
        let cancellationBefore = model.currentTask?.cancellationRequested

        model.cancelRestore()

        XCTAssertEqual(
            model.currentTask?.cancellationRequested,
            cancellationBefore)

        gate.release()
        await run.value
        XCTAssertNil(model.activeAttempt)
        XCTAssertFalse(model.isFinalizingRestoreEvidence)
    }

    private var canonicalHex: String {
        String(format: "%016llX", ecid)
    }

    private func makeModel(
        capture: WorkspaceFakeCapture,
        engine: WorkspaceFakeEngine,
        deviceControl: DeviceControlModel,
        maximumSnapshotAge: TimeInterval = 1,
        rlmCoordinator: (any RestoreRLMPreparing)? = nil,
        rawArchiveObservationHook: (@MainActor () async -> Void)? = nil,
        portKeyResolver: (@Sendable (ObservedDevice) -> String?)? = nil,
        stablePortKeyProvider: (@MainActor (RestoreTarget) -> String?)? = nil,
        metadataReaderOverride: ((URL) throws -> IPSWMetadataReadResult)? = nil,
        secondaryEngineFactory: (@MainActor () -> any RestoreEngineRunning)? = nil
    ) -> RestoreWorkspaceModel {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "RestoreWorkspaceModelTests-\(UUID().uuidString)",
                isDirectory: true)
        try? FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true)
        let metadataReader: (URL) throws -> IPSWMetadataReadResult = { url in
            IPSWMetadataReadResult(
                validity: .valid,
                metadata: IPSWMetadata(
                    productTypes: ["Mac14,2"],
                    identities: [
                        IPSWBuildIdentity(
                            deviceClass: "j413ap",
                            boardID: 0x24,
                            chipID: 0x8132)
                    ],
                    productVersion: "14.0",
                    productBuild: "23A344"),
                error: nil,
                fileIdentity: try? IPSWMetadataReader.fileIdentity(
                    url: url, buildManifestSHA256: "fixture-manifest"),
                buildManifestSHA256: "fixture-manifest")
        }
        let effectiveReader = metadataReaderOverride ?? metadataReader
        let firmwareLibrary = FirmwareLibraryStore(
            indexURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "RestoreWorkspaceModelFirmwareLibrary-\(UUID().uuidString).json"),
            metadataLoader: effectiveReader)
        return RestoreWorkspaceModel(
            capture: capture,
            engine: engine,
            outputRoot: root,
            maximumSnapshotAge: maximumSnapshotAge,
            heartbeatPollInterval: 0.005,
            observationHeartbeat: deviceControl.observationHeartbeat,
            portKeyResolver: portKeyResolver ?? { _ in "test-port" },
            portDisplayNameResolver: { _ in "测试端口" },
            metadataReader: effectiveReader,
            cfgutilURL: URL(fileURLWithPath: "/usr/bin/true"),
            rlmCoordinator: rlmCoordinator,
            firmwareLibrary: firmwareLibrary,
            rawArchiveObservationHook:
                rawArchiveObservationHook,
            stablePortKeyProvider: stablePortKeyProvider
                ?? { target in
                    "MacTest,1|builtin|" + (target.portKey ?? "unattributed")
                },
            processLease: RestoreProcessLease(
                lockURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "TestRestoreLease-\(UUID().uuidString).lock")),
            secondaryEngineFactory: secondaryEngineFactory ?? { CfgutilRestoreEngine() })
    }

    private func makeDeviceControl() -> DeviceControlModel {
        let store = CalibrationStore(
            testingDocument: CalibrationDocument(
                models: [],
                ports: [],
                selectedPort: ""),
            hostModel: "MacTest,1",
            builtInLayout: nil)
        return DeviceControlModel(
            calibration: store,
            livePorts: [],
            helperAvailable: false,
            persistPortSelection: false,
            startLiveWork: false)
    }

    private func publish(
        _ device: ObservedDevice,
        to model: DeviceControlModel
    ) {
        model.applyObservationResult(.success([device]), now: Date())
    }

    private func device() -> ObservedDevice {
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

    func testZeroTaskLeftPortCanBecomeFirstTaskThroughUnifiedEntry() async throws {
        let deviceControl = makeDeviceControl()
        let engine = WorkspaceFakeEngine()
        let model = makeModel(
            capture: WorkspaceFakeCapture(state: .idle),
            engine: engine, deviceControl: deviceControl,
            portKeyResolver: { observed in
                observed.locationID == "01100000" ? "left-port" : "right-port"
            })
        let left = device(ecid: 0x12345670, location: "01100000")
        let right = device(ecid: 0x12345671, location: "01200000")
        deviceControl.applyObservationResult(.success([left, right]), now: Date())
        model.refreshTargets()
        let target = try XCTUnwrap(model.availableTargets.first {
            $0.canonicalHex.uppercased().hasSuffix("12345670") })
        let prepared = await model.prepareFirmwareDraft(
            for: target, url: try firmwareURL())
        XCTAssertTrue(prepared)
        deviceControl.applyObservationResult(.success([left, right]), now: Date())
        XCTAssertTrue(model.freezeRestoreConfirmation(targetID: target.id))
        let run = Task { @MainActor in
            await model.beginUnifiedRestoreAfterConfirmation(targetID: target.id) }
        for _ in 0..<300 where engine.request == nil {
            try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(engine.request?.targetECID, 0x12345670)
        XCTAssertEqual(model.taskRegistry.activeCount, 1)
        engine.complete(); await run.value
        XCTAssertEqual(model.taskRegistry.activeCount, 0)
    }

    func testRightThenLeftBothEnginesReceiveOwnTarget() async throws {
        let deviceControl = makeDeviceControl()
        let p = WorkspaceFakeEngine(); let sEngine = WorkspaceFakeEngine()
        let model = makeModel(
            capture: WorkspaceFakeCapture(state: .idle),
            engine: p, deviceControl: deviceControl,
            portKeyResolver: { $0.locationID == "01100000" ? "left-port" : "right-port" },
            secondaryEngineFactory: { sEngine })
        let left = device(ecid: 0x12345670, location: "01100000")
        let right = device(ecid: 0x12345671, location: "01200000")
        deviceControl.applyObservationResult(.success([left, right]), now: Date())
        model.refreshTargets()
        let l = try XCTUnwrap(model.availableTargets.first {
            $0.canonicalHex.uppercased().hasSuffix("12345670") })
        let r = try XCTUnwrap(model.availableTargets.first {
            $0.canonicalHex.uppercased().hasSuffix("12345671") })
        let pl = await model.prepareFirmwareDraft(for: l, url: try firmwareURL())
        let pr = await model.prepareFirmwareDraft(for: r, url: try firmwareURL())
        XCTAssertTrue(pl); XCTAssertTrue(pr)
        XCTAssertTrue(model.freezeRestoreConfirmation(targetID: r.id))
        deviceControl.applyObservationResult(.success([left, right]), now: Date())
        let run = Task { @MainActor in
            await model.beginUnifiedRestoreAfterConfirmation(targetID: r.id) }
        for _ in 0..<300 where p.request == nil {
            try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(p.request?.targetECID, 0x12345671)
        let firstID = try XCTUnwrap(model.currentTask?.id)
        XCTAssertTrue(model.freezeRestoreConfirmation(targetID: l.id))
        deviceControl.applyObservationResult(.success([left, right]), now: Date())
        let second = Task { @MainActor in
            await model.beginUnifiedRestoreAfterConfirmation(targetID: l.id) }
        for _ in 0..<300 where sEngine.request == nil {
            try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(sEngine.request?.targetECID, 0x12345670)
        XCTAssertNotEqual(model.secondaryTask?.id, firstID)
        XCTAssertEqual(model.taskRegistry.activeCount, 2)
        sEngine.complete()
        for _ in 0..<300 where model.taskRegistry.activeCount > 1 {
            try await Task.sleep(nanoseconds: 5_000_000) }
        p.complete(); await run.value; await second.value
        XCTAssertEqual(model.taskRegistry.activeCount, 0)
    }



    func testSecondaryRejectsManifestDigestChangeWithSameFileIdentity() async throws {
        let deviceControl = makeDeviceControl()
        let primary = WorkspaceFakeEngine(); let secondary = WorkspaceFakeEngine()
        var forceNewManifest = false
        var bURL: URL?
        let reader: (URL) throws -> IPSWMetadataReadResult = { url in
            let base = try IPSWMetadataReader.fileIdentity(
                url: url, buildManifestSHA256: "manifest-A")
            let isB = forceNewManifest && bURL?.standardizedFileURL == url.standardizedFileURL
            let manifest = isB ? "manifest-B" : "manifest-A"
            let identity = IPSWFileIdentity(
                canonicalRealpath: base.canonicalRealpath, dev: base.dev,
                ino: base.ino, sizeBytes: base.sizeBytes,
                mtimeNs: base.mtimeNs, ctimeNs: base.ctimeNs,
                buildManifestSHA256: manifest)
            return IPSWMetadataReadResult(
                validity: .valid,
                metadata: IPSWMetadata(
                    productTypes: ["Mac14,2"],
                    identities: [IPSWBuildIdentity(
                        deviceClass: "j413ap", boardID: 0x24, chipID: 0x8132)],
                    productVersion: "14.0", productBuild: "23A344"),
                error: nil,
                fileIdentity: identity,
                buildManifestSHA256: manifest)
        }
        let model = makeModel(
            capture: WorkspaceFakeCapture(state: .idle),
            engine: primary, deviceControl: deviceControl,
            portKeyResolver: { $0.locationID == "01100000" ? "left-port" : "right-port" },
            metadataReaderOverride: reader,
            secondaryEngineFactory: { secondary })
        let left = device(ecid: 0x12345670, location: "01100000")
        let right = device(ecid: 0x12345671, location: "01200000")
        deviceControl.applyObservationResult(.success([left, right]), now: Date())
        model.refreshTargets()
        let l = try XCTUnwrap(model.availableTargets.first {
            $0.canonicalHex.uppercased().hasSuffix("12345670") })
        let r = try XCTUnwrap(model.availableTargets.first {
            $0.canonicalHex.uppercased().hasSuffix("12345671") })
        _ = await model.prepareFirmwareDraft(for: l, url: try firmwareURL())
        let bPath = try firmwareURL()
        bURL = bPath
        _ = await model.prepareFirmwareDraft(for: r, url: bPath)
        deviceControl.applyObservationResult(.success([left, right]), now: Date())
        XCTAssertTrue(model.freezeRestoreConfirmation(targetID: l.id))
        let firstRun = Task { @MainActor in
            await model.beginUnifiedRestoreAfterConfirmation(targetID: l.id) }
        for _ in 0..<300 where !primary.isRunning {
            try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(primary.isRunning)
        XCTAssertEqual(model.taskRegistry.activeCount, 1)
        deviceControl.applyObservationResult(.success([left, right]), now: Date())
        XCTAssertTrue(model.freezeRestoreConfirmation(targetID: r.id))
        forceNewManifest = true
        let rejected = await model.beginUnifiedRestoreAfterConfirmation(targetID: r.id)
        XCTAssertFalse(rejected)
        XCTAssertNil(secondary.request)
        XCTAssertTrue(primary.isRunning)
        XCTAssertEqual(model.taskRegistry.activeCount, 1)
        XCTAssertTrue(model.errorMessage.contains("BuildManifest"))
        primary.complete(); await firstRun.value
    }

    func testSecondaryRejectsReplacedIPSWWhilePrimaryKeepsRunning() async throws {
        let deviceControl = makeDeviceControl()
        let primary = WorkspaceFakeEngine(); let secondary = WorkspaceFakeEngine()
        let model = makeModel(
            capture: WorkspaceFakeCapture(state: .idle),
            engine: primary, deviceControl: deviceControl,
            portKeyResolver: { $0.locationID == "01100000" ? "left-port" : "right-port" },
            secondaryEngineFactory: { secondary })
        let left = device(ecid: 0x12345670, location: "01100000")
        let right = device(ecid: 0x12345671, location: "01200000")
        deviceControl.applyObservationResult(.success([left, right]), now: Date())
        model.refreshTargets()
        let l = try XCTUnwrap(model.availableTargets.first {
            $0.canonicalHex.uppercased().hasSuffix("12345670") })
        let r = try XCTUnwrap(model.availableTargets.first {
            $0.canonicalHex.uppercased().hasSuffix("12345671") })
        let pl = await model.prepareFirmwareDraft(for: l, url: try firmwareURL())
        let urlR = try firmwareURL()
        let pr = await model.prepareFirmwareDraft(for: r, url: urlR)
        XCTAssertTrue(pl); XCTAssertTrue(pr)
        XCTAssertTrue(model.freezeRestoreConfirmation(targetID: l.id))
        deviceControl.applyObservationResult(.success([left, right]), now: Date())
        let firstRun = Task { @MainActor in
            await model.beginUnifiedRestoreAfterConfirmation(targetID: l.id) }
        for _ in 0..<300 where primary.request == nil {
            try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(primary.isRunning)

        XCTAssertTrue(model.freezeRestoreConfirmation(targetID: r.id))
        try Data("replaced-secondary".utf8).write(to: urlR)
        let rejected = await model.beginUnifiedRestoreAfterConfirmation(targetID: r.id)
        XCTAssertFalse(rejected)
        XCTAssertNil(secondary.request)
        XCTAssertTrue(primary.isRunning, "首台必须继续运行")
        XCTAssertEqual(model.taskRegistry.activeCount, 1)
        primary.complete(); await firstRun.value
    }


    func testMissingBoardIDRejectsAndKeepsSelectedIPSW() async throws {
        let deviceControl = makeDeviceControl()
        let engine = WorkspaceFakeEngine()
        let model = makeModel(
            capture: WorkspaceFakeCapture(state: .idle),
            engine: engine, deviceControl: deviceControl,
            portKeyResolver: { _ in "left-port" })
        let left = deviceWithoutBoard(ecid: 0x12345670, location: "01100000")
        deviceControl.applyObservationResult(.success([left]), now: Date())
        model.refreshTargets()
        let target = try XCTUnwrap(model.availableTargets.first)
        let url = try firmwareURL()
        _ = await model.prepareFirmwareDraft(for: target, url: url)
        XCTAssertTrue(model.freezeRestoreConfirmation(targetID: target.id))
        let rejected = await model.beginUnifiedRestoreAfterConfirmation(targetID: target.id)
        XCTAssertFalse(rejected)
        XCTAssertEqual(engine.requestCount, 0)
        XCTAssertTrue(model.errorMessage.contains("BoardID"))
        XCTAssertEqual(model.firmwareURL?.standardizedFileURL, url.standardizedFileURL)
        XCTAssertNotNil(model.firmwareDraft(for: target))
    }

    func testConfirmationTokenRejectsReplacedIPSWBytes() async throws {
        let deviceControl = makeDeviceControl()
        let engine = WorkspaceFakeEngine()
        let model = makeModel(
            capture: WorkspaceFakeCapture(state: .idle),
            engine: engine, deviceControl: deviceControl,
            portKeyResolver: { _ in "left-port" })
        let left = device(ecid: 0x12345670, location: "01100000")
        deviceControl.applyObservationResult(.success([left]), now: Date())
        model.refreshTargets()
        let target = try XCTUnwrap(model.availableTargets.first)
        let url = try firmwareURL()
        let prepared = await model.prepareFirmwareDraft(for: target, url: url)
        XCTAssertTrue(prepared)
        XCTAssertTrue(model.freezeRestoreConfirmation(targetID: target.id))
        try Data("replaced-bytes".utf8).write(to: url)
        let rejected = await model.beginUnifiedRestoreAfterConfirmation(targetID: target.id)
        XCTAssertFalse(rejected)
        XCTAssertEqual(engine.requestCount, 0)
        XCTAssertTrue(model.errorMessage.contains("文件身份"))
    }

    func testUnifiedStartWithoutConfirmationIsRejectedBeforeEngine() async throws {
        let deviceControl = makeDeviceControl()
        let engine = WorkspaceFakeEngine()
        let model = makeModel(
            capture: WorkspaceFakeCapture(state: .idle),
            engine: engine, deviceControl: deviceControl,
            portKeyResolver: { _ in "left-port" })
        let left = device(ecid: 0x12345670, location: "01100000")
        deviceControl.applyObservationResult(.success([left]), now: Date())
        model.refreshTargets()
        let target = try XCTUnwrap(model.availableTargets.first)
        _ = await model.prepareFirmwareDraft(for: target, url: try firmwareURL())
        let rejected = await model.beginUnifiedRestoreAfterConfirmation(targetID: target.id)
        XCTAssertFalse(rejected)
        XCTAssertEqual(engine.requestCount, 0)
        XCTAssertNil(model.currentTask)
        XCTAssertTrue(model.errorMessage.contains("确认"))
    }


    func testStaleCancelUUIDCannotCancelReplacementTask() async throws {
        let deviceControl = makeDeviceControl()
        let engine = WorkspaceFakeEngine()
        let model = makeModel(
            capture: WorkspaceFakeCapture(state: .idle),
            engine: engine, deviceControl: deviceControl)
        publish(device(), to: deviceControl)
        model.refreshTargets()
        model.selectTarget(id: canonicalHex)
        await model.loadFirmware(url: try firmwareURL())
        publish(device(), to: deviceControl)

        let firstRun = Task { @MainActor in
            await model.testStartPrimaryThroughConfirmation() }
        for _ in 0..<200 where engine.request == nil {
            try await Task.sleep(nanoseconds: 5_000_000) }
        let staleID = try XCTUnwrap(model.currentAttemptID)
        engine.complete()
        await firstRun.value
        try await Task.sleep(nanoseconds: 50_000_000)

        publish(device(), to: deviceControl)
        model.selectTarget(id: canonicalHex)
        await model.loadFirmware(url: try firmwareURL())
        let secondRun = Task { @MainActor in
            await model.testStartPrimaryThroughConfirmation() }
        for _ in 0..<200 where engine.requestCount < 2 {
            try await Task.sleep(nanoseconds: 5_000_000) }
        let liveID = try XCTUnwrap(model.currentAttemptID)
        XCTAssertNotEqual(liveID, staleID)

        model.cancelRestore(attemptID: staleID)
        XCTAssertTrue(engine.isRunning, "旧 attempt UUID 不得取消补位新任务")
        XCTAssertEqual(model.currentAttemptID, liveID)
        engine.complete()
        await secondRun.value
    }

    func testRepeatedFinishReleasesRegistryAndLeaseOnlyOnce() async throws {
        let deviceControl = makeDeviceControl()
        let engine = WorkspaceFakeEngine()
        let model = makeModel(
            capture: WorkspaceFakeCapture(state: .idle),
            engine: engine, deviceControl: deviceControl)
        publish(device(), to: deviceControl)
        model.refreshTargets()
        model.selectTarget(id: canonicalHex)
        await model.loadFirmware(url: try firmwareURL())
        publish(device(), to: deviceControl)

        let run = Task { @MainActor in
            await model.testStartPrimaryThroughConfirmation() }
        for _ in 0..<200 where engine.request == nil {
            try await Task.sleep(nanoseconds: 5_000_000) }
        engine.complete()
        await run.value
        try await Task.sleep(nanoseconds: 80_000_000)

        engine.complete() // 重复 finish
        engine.complete()
        XCTAssertEqual(model.taskRegistry.activeCount, 0)
        XCTAssertEqual(model.activeLeaseShareCount, 0)
        XCTAssertFalse(model.isMachineLeaseHeld)
        XCTAssertNil(model.currentTask)
    }

    func testConfirmationTokenInvalidatesOnPolicyChangeAndCannotRepeat() async throws {
        let deviceControl = makeDeviceControl()
        let engine = WorkspaceFakeEngine()
        let model = makeModel(
            capture: WorkspaceFakeCapture(state: .idle),
            engine: engine, deviceControl: deviceControl,
            portKeyResolver: { _ in "left-port" })
        let left = device(ecid: 0x12345670, location: "01100000")
        deviceControl.applyObservationResult(.success([left]), now: Date())
        model.refreshTargets()
        let target = try XCTUnwrap(model.availableTargets.first)
        let prepared = await model.prepareFirmwareDraft(
            for: target, url: try firmwareURL())
        XCTAssertTrue(prepared)
        XCTAssertTrue(model.freezeRestoreConfirmation(targetID: target.id))
        model.setRawSaveRequestedThisRun(true)
        let rejected = await model.beginUnifiedRestoreAfterConfirmation(targetID: target.id)
        XCTAssertFalse(rejected)
        XCTAssertTrue(model.errorMessage.contains("确认对象"))
        XCTAssertEqual(engine.requestCount, 0)

        XCTAssertTrue(model.freezeRestoreConfirmation(targetID: target.id))
        let run = Task { @MainActor in
            await model.beginUnifiedRestoreAfterConfirmation(targetID: target.id) }
        for _ in 0..<300 where engine.request == nil {
            try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(engine.requestCount, 1)
        let repeated = await model.beginUnifiedRestoreAfterConfirmation(targetID: target.id)
        XCTAssertFalse(repeated)
        XCTAssertEqual(engine.requestCount, 1)
        engine.complete(); await run.value
    }

    func testTwoOccupiedRejectThirdAndEachUUIDHasOwnEngine() async throws {
        let deviceControl = makeDeviceControl()
        let primaryEngine = WorkspaceFakeEngine()
        let secondaryEngine = WorkspaceFakeEngine()
        let model = makeModel(
            capture: WorkspaceFakeCapture(state: .idle),
            engine: primaryEngine, deviceControl: deviceControl,
            portKeyResolver: { observed in
                switch observed.locationID {
                case "01100000": return "left-port"
                case "01200000": return "right-port"
                default: return "third-port"
                }
            },
            secondaryEngineFactory: { secondaryEngine })
        let left = device(ecid: 0x12345670, location: "01100000")
        let right = device(ecid: 0x12345671, location: "01200000")
        let thirdDevice = device(ecid: 0x12345672, location: "01300000")
        deviceControl.applyObservationResult(.success([left, right, thirdDevice]), now: Date())
        model.refreshTargets()
        let l = try XCTUnwrap(model.availableTargets.first {
            $0.canonicalHex.uppercased().hasSuffix("12345670") })
        let r = try XCTUnwrap(model.availableTargets.first {
            $0.canonicalHex.uppercased().hasSuffix("12345671") })
        let preparedL = await model.prepareFirmwareDraft(for: l, url: try firmwareURL())
        let preparedR = await model.prepareFirmwareDraft(for: r, url: try firmwareURL())
        XCTAssertTrue(preparedL); XCTAssertTrue(preparedR)
        deviceControl.applyObservationResult(.success([left, right, thirdDevice]), now: Date())

        XCTAssertTrue(model.freezeRestoreConfirmation(targetID: l.id))
        let firstRun = Task { @MainActor in
            await model.beginUnifiedRestoreAfterConfirmation(targetID: l.id) }
        for _ in 0..<300 where primaryEngine.request == nil {
            try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(model.taskRegistry.activeCount, 1)
        let firstID = try XCTUnwrap(model.currentTask?.id)
        deviceControl.applyObservationResult(.success([left, right, thirdDevice]), now: Date())
        XCTAssertTrue(model.freezeRestoreConfirmation(targetID: r.id))
        let secondRun = Task { @MainActor in
            await model.beginUnifiedRestoreAfterConfirmation(targetID: r.id) }
        for _ in 0..<300 where secondaryEngine.request == nil {
            try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(model.taskRegistry.activeCount, 2)
        XCTAssertNotEqual(model.secondaryTask?.id, firstID)
        XCTAssertEqual(secondaryEngine.request?.targetECID, 0x12345671)
        XCTAssertEqual(primaryEngine.request?.targetECID, 0x12345670)

        let third = try XCTUnwrap(model.availableTargets.first {
            $0.canonicalHex.uppercased().hasSuffix("12345672") })
        // 第三个只验证容量拒绝，不创建第三个引擎。
        let rejected = await model.beginUnifiedRestoreAfterConfirmation(targetID: third.id)
        XCTAssertFalse(rejected)
        XCTAssertEqual(model.taskRegistry.activeCount, 2)

        secondaryEngine.complete()
        for _ in 0..<300 where model.taskRegistry.activeCount > 1 {
            try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(model.taskRegistry.activeCount, 1)
        await secondRun.value
        primaryEngine.complete(); await firstRun.value
        XCTAssertEqual(model.taskRegistry.activeCount, 0)
    }

    func testDraftRefusesWhenStablePortKeyIsMissing() async throws {
        let capture = WorkspaceFakeCapture(state: .idle)
        let engine = WorkspaceFakeEngine()
        let deviceControl = makeDeviceControl()
        let model = makeModel(
            capture: capture, engine: engine, deviceControl: deviceControl,
            portKeyResolver: { _ in "left-port" },
            stablePortKeyProvider: { _ in nil })
        let only = device(ecid: 0x12345670, location: "01100000")
        deviceControl.applyObservationResult(.success([only]), now: Date())
        model.refreshTargets()
        let target = try XCTUnwrap(model.availableTargets.first)
        let ok = await model.prepareFirmwareDraft(
            for: target, url: try firmwareURL())
        XCTAssertFalse(ok)
        XCTAssertNil(model.firmwareDraft(for: target))
        XCTAssertTrue(model.firmwareDraftMessage.contains("稳定端口键"))
    }

    func testThirdDeviceRejectedAndArchiveReleaseRefillEndsWithCleanLease() async throws {
        let gateDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveGate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: gateDir, withIntermediateDirectories: true)
        let entered = gateDir.appendingPathComponent("entered")
        let release = gateDir.appendingPathComponent("release")
        defer { try? FileManager.default.removeItem(at: gateDir) }
        let deviceControl = makeDeviceControl()
        let primary = WorkspaceFakeEngine(); let secondary = WorkspaceFakeEngine()
        let model = makeModel(
            capture: WorkspaceFakeCapture(state: .idle),
            engine: primary, deviceControl: deviceControl,
            rawArchiveObservationHook: {
                FileManager.default.createFile(atPath: entered.path, contents: Data())
                while !FileManager.default.fileExists(atPath: release.path) {
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
            },
            portKeyResolver: { observed in
                switch observed.locationID {
                case "01100000": return "left-port"
                case "01200000": return "right-port"
                default: return "third-port"
                }
            },
            secondaryEngineFactory: { secondary })
        let left = device(ecid: 0x12345670, location: "01100000")
        let right = device(ecid: 0x12345671, location: "01200000")
        let thirdDevice = device(ecid: 0x12345672, location: "01300000")
        deviceControl.applyObservationResult(.success([left, right, thirdDevice]), now: Date())
        model.refreshTargets()
        let l = try XCTUnwrap(model.availableTargets.first {
            $0.canonicalHex.uppercased().hasSuffix("12345670") })
        let r = try XCTUnwrap(model.availableTargets.first {
            $0.canonicalHex.uppercased().hasSuffix("12345671") })
        let t = try XCTUnwrap(model.availableTargets.first {
            $0.canonicalHex.uppercased().hasSuffix("12345672") })
        _ = await model.prepareFirmwareDraft(for: l, url: try firmwareURL())
        _ = await model.prepareFirmwareDraft(for: r, url: try firmwareURL())
        _ = await model.prepareFirmwareDraft(for: t, url: try firmwareURL())
        deviceControl.applyObservationResult(.success([left, right, thirdDevice]), now: Date())
        XCTAssertTrue(model.freezeRestoreConfirmation(targetID: l.id))
        let firstRun = Task { @MainActor in
            await model.beginUnifiedRestoreAfterConfirmation(targetID: l.id) }
        for _ in 0..<300 where !primary.isRunning {
            try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(primary.isRunning)
        XCTAssertTrue(model.freezeRestoreConfirmation(targetID: r.id))
        deviceControl.applyObservationResult(.success([left, right, thirdDevice]), now: Date())
        let secondRun = Task { @MainActor in
            await model.beginUnifiedRestoreAfterConfirmation(targetID: r.id) }
        for _ in 0..<300 where secondary.request == nil {
            try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(model.taskRegistry.activeCount, 2)
        secondary.complete()
        for _ in 0..<600 where !FileManager.default.fileExists(atPath: entered.path) {
            try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: entered.path),
                      "archive barrier not entered")
        XCTAssertEqual(model.taskRegistry.activeCount, 2)
        XCTAssertEqual(model.activeLeaseShareCount, 2)

        XCTAssertTrue(model.freezeRestoreConfirmation(targetID: r.id))
        let samePort = await model.beginUnifiedRestoreAfterConfirmation(targetID: r.id)
        XCTAssertFalse(samePort)
        XCTAssertEqual(secondary.requestCount, 1, "B 不得额外启动引擎")

        XCTAssertTrue(model.freezeRestoreConfirmation(targetID: t.id))
        let third = await model.beginUnifiedRestoreAfterConfirmation(targetID: t.id)
        XCTAssertFalse(third)
        XCTAssertEqual(model.taskRegistry.activeCount, 2)
        XCTAssertEqual(model.activeLeaseShareCount, 2)

        FileManager.default.createFile(atPath: release.path, contents: Data())
        for _ in 0..<600 where model.taskRegistry.activeCount > 1 {
            try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(model.taskRegistry.activeCount, 1)
        XCTAssertEqual(model.activeLeaseShareCount, 1)
        XCTAssertTrue(primary.isRunning)

        // 空位补入第三台（新 B），沿用同一生产入口。
        XCTAssertTrue(model.freezeRestoreConfirmation(targetID: t.id))
        deviceControl.applyObservationResult(.success([left, right, thirdDevice]), now: Date())
        let refill = Task { @MainActor in
            await model.beginUnifiedRestoreAfterConfirmation(targetID: t.id) }
        for _ in 0..<300 where secondary.requestCount < 2 {
            try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(secondary.requestCount, 2)
        XCTAssertEqual(secondary.request?.targetECID, 0x12345672)
        XCTAssertEqual(model.taskRegistry.activeCount, 2)
        secondary.complete()
        for _ in 0..<300 where model.taskRegistry.activeCount > 1 {
            try await Task.sleep(nanoseconds: 5_000_000) }
        primary.complete(); await firstRun.value; await secondRun.value; await refill.value
        for _ in 0..<300 where model.activeLeaseShareCount > 0 {
            try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(model.taskRegistry.activeCount, 0)
        XCTAssertEqual(model.activeLeaseShareCount, 0)
        XCTAssertFalse(model.isMachineLeaseHeld)
    }

    private func deviceWithoutBoard(ecid: UInt64, location: String) -> ObservedDevice {
        let hex = String(format: "%016llX", ecid)
        return ObservedDevice(
            id: "ecid:\(hex)", ecid: hex, mode: .dfu,
            locationID: location,
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:\(hex)", modelIdentifier: "Mac14,2",
            chipID: 0x8132, boardID: nil, hardwareCode: "j413ap",
            productType: "Mac14,2")
    }

    private func device(ecid: UInt64, location: String) -> ObservedDevice {
        let hex = String(format: "%016llX", ecid)
        return ObservedDevice(
            id: "ecid:\(hex)", ecid: hex, mode: .dfu,
            locationID: location,
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:\(hex)", modelIdentifier: "Mac14,2",
            chipID: 0x8132, boardID: 0x24, hardwareCode: "j413ap",
            productType: "Mac14,2")
    }

    func testTwoStepStableDraftKeyAndRightPortFirst() async throws {
        let capture = WorkspaceFakeCapture(state: .idle)
        let engine = WorkspaceFakeEngine()
        let deviceControl = makeDeviceControl()
        let model = makeModel(
            capture: capture, engine: engine, deviceControl: deviceControl,
            portKeyResolver: { observed in
                observed.locationID == "01100000" ? "left-port" : "right-port"
            })
        let left = device(ecid: 0x12345670, location: "01100000")
        let right = device(ecid: 0x12345671, location: "01200000")
        let thirdDevice = device(ecid: 0x12345672, location: "01300000")
        deviceControl.applyObservationResult(.success([left, right, thirdDevice]), now: Date())
        model.refreshTargets()
        let target = try XCTUnwrap(model.availableTargets.first {
            $0.canonicalHex.uppercased().hasSuffix("12345671")
        })
        let ok = await model.prepareFirmwareDraft(for: target, url: try firmwareURL())
        XCTAssertTrue(ok, "prepareFirmwareDraft 返回 false")
        let before = try XCTUnwrap(
            model.firmwareDraft(for: target),
            "prepare 返回 true 但草稿不可读")
        let beforeKey = try XCTUnwrap(model.firmwareDraftKeyForTesting(target))
        XCTAssertTrue(
            model.firmwareDraftStatus(for: target)?.isReadyForHandoff == true,
            "第一步草稿未 ready")

        deviceControl.applyObservationResult(.success([left, right]), now: Date())
        try await Task.sleep(nanoseconds: 80_000_000)
        model.refreshTargets()
        let refreshed = try XCTUnwrap(model.availableTargets.first {
            $0.portKey == target.portKey
                && $0.canonicalHex.caseInsensitiveCompare(target.canonicalHex) == .orderedSame
        })
        let after = try XCTUnwrap(
            model.firmwareDraft(for: refreshed),
            "刷新后按端口+ECID 找不到草稿")
        XCTAssertEqual(after.id, before.id)
        XCTAssertEqual(model.firmwareDraftKeyForTesting(refreshed), beforeKey)
        XCTAssertEqual(after.fileIdentity, before.fileIdentity)
        XCTAssertTrue(
            model.firmwareDraftStatus(for: refreshed)?.isReadyForHandoff == true)

        deviceControl.applyObservationResult(.success([left, right]), now: Date())
        XCTAssertTrue(model.freezeRestoreConfirmation(targetID: refreshed.id))
        let run = Task { @MainActor in
            await model.beginUnifiedRestoreAfterConfirmation(targetID: refreshed.id)
        }
        for _ in 0..<300 where engine.request == nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(engine.request?.targetECID, 0x12345671)
        XCTAssertEqual(model.taskRegistry.activeCount, 1)
        engine.complete()
        await run.value
    }

    private func firmwareURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixture-\(UUID().uuidString).ipsw")
        XCTAssertTrue(FileManager.default.createFile(
            atPath: url.path,
            contents: Data("fixture".utf8)))
        return url
    }
}

@MainActor
private final class WorkspaceFakeEngine: RestoreEngineRunning {
    private(set) var requestCount = 0
    private(set) var request: CfgutilRestoreRequest?
    private var continuation: CheckedContinuation<Void, Never>?
    var cancellationGraceExpired = false
    var isRunning = false

    func run(
        request: CfgutilRestoreRequest,
        launchPermitted: @escaping @MainActor () -> Bool,
        onUpdate: (@MainActor (RestoreOutputSnapshot) -> Void)?
    ) async -> CfgutilRestoreRunResult {
        requestCount += 1
        self.request = request
        guard launchPermitted() else {
            return result(request: request, outcome: .canceled)
        }
        isRunning = true
        var snapshot = RestoreOutputSnapshot()
        snapshot.restoreActivityObserved = true
        snapshot.stepText = "RestoreOS"
        onUpdate?(snapshot)
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        isRunning = false
        snapshot.sawRestoredSystemForTarget = true
        snapshot.sawSuccessSummary = true
        return CfgutilRestoreRunResult(
            outcome: .success,
            exitCode: 0,
            stdoutURL: request.outputDirectory?.appendingPathComponent("stdout.raw"),
            stderrURL: request.outputDirectory?.appendingPathComponent("stderr.raw"),
            stdoutSHA256: String(repeating: "a", count: 64),
            stderrSHA256: String(repeating: "b", count: 64),
            tailComplete: true,
            cancellationRequested: false,
            forcedKill: false,
            snapshot: snapshot)
    }

    func cancel() {
        complete()
    }

    func forceKill() {}

    func complete() {
        continuation?.resume()
        continuation = nil
    }

    private func result(
        request: CfgutilRestoreRequest,
        outcome: RestoreOutcome
    ) -> CfgutilRestoreRunResult {
        CfgutilRestoreRunResult(
            outcome: outcome,
            exitCode: nil,
            stdoutURL: request.outputDirectory?.appendingPathComponent("stdout.raw"),
            stderrURL: request.outputDirectory?.appendingPathComponent("stderr.raw"),
            stdoutSHA256: "",
            stderrSHA256: "",
            tailComplete: false,
            cancellationRequested: outcome == .canceled,
            forcedKill: false,
            snapshot: RestoreOutputSnapshot())
    }
}

@MainActor
private final class WorkspaceFakeCapture: RestoreCaptureLifecycle {
    var state: CaptureState
    var currentRawLogURL: URL? = URL(fileURLWithPath: "/tmp/workspace-rlm.log")
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(state: CaptureState) {
        self.state = state
    }

    func start(preCaptureContext: String?, automatic: Bool) {
        startCount += 1
        state = .recording
    }

    func stop() {
        stopCount += 1
        state = .finalizing
    }
}

@MainActor
private final class BlockingWorkspaceRLMCoordinator:
    RestoreRLMPreparing {
    private(set) var finishStarted = false
    private var finishContinuation: CheckedContinuation<Void, Never>?

    func prepare(
        taskID: UUID,
        canonicalECID: String
    ) async -> RestoreRLMBinding {
        await prepare(
            taskID: taskID,
            canonicalECID: canonicalECID,
            saveRequested: false)
    }

    func prepare(
        taskID: UUID,
        canonicalECID: String,
        saveRequested: Bool
    ) async -> RestoreRLMBinding {
        RestoreRLMBinding(
            taskID: taskID,
            canonicalECID: canonicalECID,
            status: .notRequested,
            rawLogURL: nil,
            startAt: Date(),
            endAt: nil,
            reason: "test-not-requested",
            ownership: .notRequested)
    }

    func finish(
        taskID: UUID,
        outcome: RestoreOutcome
    ) async {
        finishStarted = true
        await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
    }

    func finalization(
        taskID: UUID,
        timeout: TimeInterval
    ) async -> RestoreRLMFinalization? {
        nil
    }

    func releaseFinish() {
        finishContinuation?.resume()
        finishContinuation = nil
    }
}

@MainActor
private final class RawArchiveObservationGate {
    private(set) var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

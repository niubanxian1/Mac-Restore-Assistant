import Foundation
import XCTest
@testable import DeviceCapturePrototype
import RestoreLogEngine

/// P2-B：第二台设备独立固件草稿的离线验证。
///
/// 覆盖：草稿状态机（同机/换机/重新枚举/文件变化/无效固件）、
/// 运行时为 B 准备草稿不改变 A 的活动任务与单任务选择状态。
@MainActor
final class P2BFirmwareDraftTests: XCTestCase {
    // MARK: - 草稿状态机

    func testDraftIsReadyForSameDeviceSameGeneration() {
        let target = makeTarget(hex: "12345670", generation: 3, location: "01100000")
        let draft = makeDraft(ecid: "12345670", generation: 3)
        XCTAssertEqual(
            RestoreFirmwareDraft.status(for: draft, target: target, fileUnchanged: true),
            .ready)
        XCTAssertTrue(RestoreFirmwareDraft.status(
            for: draft, target: target, fileUnchanged: true).isReadyForHandoff)
    }

    func testDraftRequiresReverificationWhenGenerationChanges() {
        let target = makeTarget(hex: "12345670", generation: 9, location: "01100000")
        let draft = makeDraft(ecid: "12345670", generation: 3)
        XCTAssertEqual(
            RestoreFirmwareDraft.status(for: draft, target: target, fileUnchanged: true),
            .requiresReverification)
    }

    func testDraftIsRejectedForAnotherDeviceOnSamePort() {
        let target = makeTarget(hex: "AAAAAAAA", generation: 3, location: "01100000")
        let draft = makeDraft(ecid: "12345670", generation: 3)
        XCTAssertEqual(
            RestoreFirmwareDraft.status(for: draft, target: target, fileUnchanged: true),
            .unusable(.deviceChanged))
    }

    func testDraftIsRejectedWhenNoReliableDeviceIsPresent() {
        let draft = makeDraft(ecid: "12345670", generation: 3)
        XCTAssertEqual(
            RestoreFirmwareDraft.status(for: draft, target: nil, fileUnchanged: true),
            .unusable(.deviceMissing))
    }

    func testDraftIsRejectedWhenFirmwareIsNotVerified() {
        let target = makeTarget(hex: "12345670", generation: 3, location: "01100000")
        var draft = makeDraft(ecid: "12345670", generation: 3)
        draft = RestoreFirmwareDraft(
            id: draft.id,
            stablePortKey: draft.stablePortKey,
            deviceECID: draft.deviceECID,
            connectionGeneration: draft.connectionGeneration,
            locationID: draft.locationID,
            deviceDisplayName: draft.deviceDisplayName,
            ipswURL: draft.ipswURL,
            libraryEntryID: draft.libraryEntryID,
            fileIdentity: draft.fileIdentity,
            productVersion: draft.productVersion,
            productBuild: draft.productBuild,
            validity: .unverified,
            compatibility: draft.compatibility,
            createdAt: draft.createdAt,
            updatedAt: draft.updatedAt,
            invalidation: nil)
        XCTAssertEqual(
            RestoreFirmwareDraft.status(for: draft, target: target, fileUnchanged: true),
            .unusable(.firmwareInvalid))
    }

    func testUnverifiedCompatibilityRequiresReverification() {
        let target = makeTarget(hex: "12345670", generation: 3, location: "01100000")
        var draft = makeDraft(ecid: "12345670", generation: 3)
        draft = RestoreFirmwareDraft(
            id: draft.id,
            stablePortKey: draft.stablePortKey,
            deviceECID: draft.deviceECID,
            connectionGeneration: draft.connectionGeneration,
            locationID: draft.locationID,
            deviceDisplayName: draft.deviceDisplayName,
            ipswURL: draft.ipswURL,
            libraryEntryID: draft.libraryEntryID,
            fileIdentity: draft.fileIdentity,
            productVersion: draft.productVersion,
            productBuild: draft.productBuild,
            validity: .valid,
            compatibility: HardwareCompatibility(
                status: .unverified, message: "未确认"),
            createdAt: draft.createdAt,
            updatedAt: draft.updatedAt,
            invalidation: nil)
        XCTAssertEqual(
            RestoreFirmwareDraft.status(for: draft, target: target, fileUnchanged: true),
            .ready)
    }

    func testDraftWithoutFileIdentityIsNotReady() {
        let target = makeTarget(hex: "12345670", generation: 3, location: "01100000")
        let draft = makeDraft(
            ecid: "12345670", generation: 3, identity: nil)
        XCTAssertEqual(
            RestoreFirmwareDraft.status(for: draft, target: target, fileUnchanged: true),
            .requiresReverification)
    }

    func testDraftIsRejectedWhenFirmwareFileChanges() {
        let target = makeTarget(hex: "12345670", generation: 3, location: "01100000")
        let draft = makeDraft(ecid: "12345670", generation: 3)
        XCTAssertEqual(
            RestoreFirmwareDraft.status(for: draft, target: target, fileUnchanged: false),
            .unusable(.fileChanged))
    }

    func testFileIdentityCheckDetectsReplacement() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("p2b-\(UUID().uuidString).ipsw")
        try Data("fixture".utf8).write(to: url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        let mtime = attributes[.modificationDate] as? Date ?? Date()
        let identity = IPSWFileIdentity(
            canonicalRealpath: url.path,
            dev: 0,
            ino: inode,
            sizeBytes: size,
            mtimeNs: Int64(mtime.timeIntervalSince1970) * 1_000_000_000,
            ctimeNs: Int64(mtime.timeIntervalSince1970) * 1_000_000_000,
            buildManifestSHA256: "")
        let draft = makeDraft(ecid: "12345670", generation: 3, url: url, identity: identity)
        XCTAssertTrue(draft.fileUnchangedOnDisk())

        try Data("fixture-changed".utf8).write(to: url)
        XCTAssertFalse(draft.fileUnchangedOnDisk())
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - 运行期隔离

    func testPreparingDraftForSecondDeviceLeavesActiveTaskUntouched() async throws {
        let capture = P2BFakeCapture(state: .idle)
        let engine = P2BFakeEngine()
        let (model, control) = makeModel(capture: capture, engine: engine)
        let a = makeDevice(hex: "12345670", location: "01100000", generation: 1)
        let b = makeDevice(hex: "12345671", location: "01200000", generation: 2)
        publish([a], to: control)
        let targetA = try await waitForTarget(model, hex: "12345670")
        model.selectTarget(id: targetA.id)
        await model.loadFirmware(url: try makeIPSW())
        let start = Task { await model.testStartPrimaryThroughConfirmation() }
        try await waitUntil { model.isRestoring }
        XCTAssertEqual(engine.requestCount, 1)

        let attemptBefore = model.activeAttempt?.attemptID
        let firmwareBefore = model.firmwareURL
        let targetBefore = model.selectedTarget?.id
        let taskUUIDBefore = model.currentTask?.id

        publish([a, b], to: control)
        let targetB = try await waitForTarget(model, hex: "12345671")
        let prepared = await model.prepareFirmwareDraft(
            for: targetB,
            url: try makeIPSW())
        XCTAssertTrue(prepared)

        XCTAssertEqual(model.activeAttempt?.attemptID, attemptBefore)
        XCTAssertEqual(model.firmwareURL, firmwareBefore)
        XCTAssertEqual(model.selectedTarget?.id, targetBefore)
        XCTAssertEqual(model.currentTask?.id, taskUUIDBefore)
        XCTAssertEqual(engine.requestCount, 1, "不得启动第二个 cfgutil")
        XCTAssertEqual(model.firmwareDraft(for: targetB)?.deviceECID.uppercased().hasSuffix("12345671"), true)
        XCTAssertEqual(model.firmwareDraftStatus(for: targetB), .ready)

        engine.complete()
        _ = await start.value
    }

    func testDraftIsNotInheritedByAnotherDeviceOnTheSamePort() async throws {
        let capture = P2BFakeCapture(state: .idle)
        let engine = P2BFakeEngine()
        let (model, control) = makeModel(capture: capture, engine: engine)
        let b = makeDevice(hex: "12345671", location: "01200000", generation: 2)
        publish([b], to: control)
        let targetB = try await waitForTarget(model, hex: "12345671")
        _ = await model.prepareFirmwareDraft(for: targetB, url: try makeIPSW())
        XCTAssertNotNil(model.firmwareDraft(for: targetB))

        let c = makeDevice(hex: "12345672", location: "01200000", generation: 3)
        publish([c], to: control)
        let targetC = try await waitForTarget(model, hex: "12345672")
        XCTAssertEqual(
            model.firmwareDraftStatus(for: targetC),
            .unusable(.deviceChanged))
    }

    // MARK: - Scope gate（执行层未被触碰）

    func testDraftCodeDoesNotReferenceExecutionState() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let model = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/RestoreWorkspaceModel.swift"),
            encoding: .utf8)
        let start = try XCTUnwrap(model.range(of: "func prepareFirmwareDraft("))
        let end = try XCTUnwrap(
            model.range(of: "func discardFirmwareDraft(", range: start.upperBound..<model.endIndex))
        let body = String(model[start.lowerBound..<end.lowerBound])
        for forbidden in [
            "beginRestoreAfterConfirmation", "restoreLease", "acquire(",
            "engine.", "activeAttempt", "firmwareURL =", "selectedTarget ="
        ] {
            XCTAssertFalse(body.contains(forbidden), "草稿路径不得触碰执行层：\(forbidden)")
        }
    }

    // MARK: - 工具

    private func makeModel(
        capture: P2BFakeCapture,
        engine: P2BFakeEngine
    ) -> (RestoreWorkspaceModel, DeviceControlModel) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("P2B-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        let reader: (URL) throws -> IPSWMetadataReadResult = { _ in
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
                error: nil)
        }
        let library = FirmwareLibraryStore(
            indexURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("P2B-Library-\(UUID().uuidString).json"),
            metadataLoader: reader)
        let store = CalibrationStore(
            testingDocument: CalibrationDocument(
                models: [], ports: [], selectedPort: ""),
            hostModel: "MacTest,1",
            builtInLayout: nil)
        let deviceControl = DeviceControlModel(
            calibration: store,
            livePorts: [],
            helperAvailable: false,
            persistPortSelection: false,
            startLiveWork: false)
        let model = RestoreWorkspaceModel(
            capture: capture,
            engine: engine,
            outputRoot: root,
            maximumSnapshotAge: 1,
            heartbeatPollInterval: 0.005,
            observationHeartbeat: deviceControl.observationHeartbeat,
            portKeyResolver: { observed in observed.locationID },
            portDisplayNameResolver: { key in "端口-\(key)" },
            metadataReader: reader,
            cfgutilURL: URL(fileURLWithPath: "/usr/bin/true"),
            rlmCoordinator: nil,
            firmwareLibrary: library,
            stablePortKeyProvider: { target in
                "host|\(target.portKey ?? "none")"
            },
            processLease: RestoreProcessLease(
                lockURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("P2B-\(UUID().uuidString).lock")))
        return (model, deviceControl)
    }

    private func publish(_ devices: [ObservedDevice], to control: DeviceControlModel) {
        control.applyObservationResult(.success(devices), now: Date())
    }

    private func makeDevice(
        hex: String,
        location: String,
        generation: UInt64
    ) -> ObservedDevice {
        ObservedDevice(
            id: "ecid:\(hex)",
            ecid: hex,
            mode: .dfu,
            locationID: location,
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:\(hex)",
            modelIdentifier: "Mac14,2",
            chipID: 0x8132,
            boardID: 0x24,
            hardwareCode: "j413ap",
            connectionGeneration: generation,
            productType: "Mac14,2")
    }

    private func makeTarget(
        hex: String,
        generation: UInt64,
        location: String
    ) -> RestoreTarget {
        RestoreTarget(
            ecid: UInt64(hex, radix: 16) ?? 0,
            canonicalHex: hex,
            productType: "Mac14,2",
            deviceClass: "j413ap",
            boardID: 0x24,
            chipID: 0x8132,
            locationID: location,
            connectionGeneration: generation,
            portKey: location,
            portDisplayName: "端口-\(location)",
            mode: .dfu,
            displayName: "MacBookPro18,2",
            machineIdentifier: "Mac14,2")
    }

    private func makeDraft(
        ecid: String,
        generation: UInt64,
        url: URL = URL(fileURLWithPath: "/tmp/p2b-draft.ipsw"),
        identity: IPSWFileIdentity? = IPSWFileIdentity(
            canonicalRealpath: "/tmp/p2b-draft.ipsw",
            dev: 0,
            ino: 1,
            sizeBytes: 7,
            mtimeNs: 0,
            ctimeNs: 0,
            buildManifestSHA256: "")
    ) -> RestoreFirmwareDraft {
        RestoreFirmwareDraft(
            id: UUID(),
            stablePortKey: "host|01100000",
            deviceECID: ecid,
            connectionGeneration: generation,
            locationID: "01100000",
            deviceDisplayName: "MacBookPro18,2",
            ipswURL: url,
            libraryEntryID: nil,
            fileIdentity: identity,
            productVersion: "14.0",
            productBuild: "23A344",
            validity: .valid,
            compatibility: HardwareCompatibility(
                status: .compatible,
                message: "兼容"),
            createdAt: Date(),
            updatedAt: Date(),
            invalidation: nil)
    }

    private func makeIPSW() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("p2b-\(UUID().uuidString).ipsw")
        try Data("fixture".utf8).write(to: url)
        return url
    }

    private func waitForTarget(
        _ model: RestoreWorkspaceModel,
        hex: String
    ) async throws -> RestoreTarget {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            model.refreshTargets()
            if let target = model.availableTargets.first(where: {
                $0.canonicalHex.uppercased().hasSuffix(hex.uppercased())
            }) {
                return target
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("target \(hex) not observed")
        throw CocoaError(.fileNoSuchFile)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), "condition not met within \(timeout)s")
    }
}

@MainActor
private final class P2BFakeEngine: RestoreEngineRunning {
    private(set) var requestCount = 0
    var cancellationGraceExpired = false
    var isRunning = false
    private var continuation: CheckedContinuation<Void, Never>?

    func run(
        request: CfgutilRestoreRequest,
        launchPermitted: @escaping @MainActor () -> Bool,
        onUpdate: (@MainActor (RestoreOutputSnapshot) -> Void)?
    ) async -> CfgutilRestoreRunResult {
        requestCount += 1
        guard launchPermitted() else {
            return CfgutilRestoreRunResult(
                outcome: .canceled,
                exitCode: nil,
                stdoutURL: nil,
                stderrURL: nil,
                stdoutSHA256: "",
                stderrSHA256: "",
                tailComplete: false,
                cancellationRequested: true,
                forcedKill: false,
                snapshot: RestoreOutputSnapshot())
        }
        isRunning = true
        var snapshot = RestoreOutputSnapshot()
        snapshot.processLaunched = RestoreLifecycleClock.now()
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

    func cancel() { complete() }
    func forceKill() {}
    func complete() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class P2BFakeCapture: RestoreCaptureLifecycle {
    var state: CaptureState
    var currentRawLogURL: URL? = URL(fileURLWithPath: "/tmp/p2b-rlm.log")

    init(state: CaptureState) {
        self.state = state
    }

    func start(preCaptureContext: String?, automatic: Bool) {
        state = .recording
    }

    func stop() {
        state = .finalizing
    }
}

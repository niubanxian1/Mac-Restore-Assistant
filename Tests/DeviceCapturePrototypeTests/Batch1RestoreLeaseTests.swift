import Combine
import Foundation
import XCTest
@testable import DeviceCapturePrototype
import RestoreLogEngine

@MainActor
final class Batch1RestoreLeaseTests: XCTestCase {
    private let ecidA: UInt64 = 0x12345670
    private let ecidB: UInt64 = 0x76543210

    func testL01LeaseExistsBeforeFirstAwait() async throws {
        let context = try makeContext()
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        // The production observer renews its heartbeat continuously. Refresh
        // the fixture immediately before the user action instead of leaving a
        // one-round snapshot to expire during asynchronous firmware preparation.
        context.publish([device(ecid: ecidA, location: "01100000")])

        let run = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil {
            context.coordinator.prepareCount == 1
        }

        XCTAssertTrue(context.workspace.restoreStartInFlight)
        XCTAssertEqual(context.workspace.activeAttempt?.launchPermitted, true)
        XCTAssertEqual(context.workspace.activeAttempt?.cancelRequested, false)
        XCTAssertTrue(context.workspace.isRestoreTaskActive)

        context.workspace.cancelRestore()
        context.coordinator.releasePrepare()
        await run.value
    }

    func testL02SecondStartIsRejectedWhileLeaseIsActive() async throws {
        let context = try makeContext()
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        context.publish([device(ecid: ecidA, location: "01100000")])

        let first = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.coordinator.prepareCount == 1 }
        let attemptID = try XCTUnwrap(context.workspace.activeAttempt?.attemptID)

        await context.workspace.testStartPrimaryThroughConfirmation()

        XCTAssertEqual(context.workspace.activeAttempt?.attemptID, attemptID)
        XCTAssertEqual(context.engine.runCount, 0)
        XCTAssertFalse(context.workspace.canStartRestore)

        context.workspace.cancelRestore()
        context.coordinator.releasePrepare()
        await first.value
    }

    func testL03LeaseFreezesTargetECIDPortAndIPSW() async throws {
        let context = try makeContext()
        let ipsw = try firmwareURL()
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: ipsw)
        context.publish([device(ecid: ecidA, location: "01100000")])

        let run = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.coordinator.prepareCount == 1 }
        let lease = try XCTUnwrap(context.workspace.activeAttempt)

        XCTAssertEqual(lease.target.canonicalHex, canonicalHex(ecidA))
        XCTAssertEqual(lease.canonicalECID, canonicalHex(ecidA))
        XCTAssertEqual(lease.stablePortKey, "synthetic-host|port-A")
        XCTAssertEqual(lease.portDisplayName, "左侧上方")
        XCTAssertEqual(lease.ipswURL.standardizedFileURL, ipsw.standardizedFileURL)

        context.workspace.cancelRestore()
        context.coordinator.releasePrepare()
        await run.value
    }

    func testL04BrowsePortSwitchDoesNotRedirectActiveLease() async throws {
        let context = try makeContext()
        context.publish([
            device(ecid: ecidA, location: "01100000"),
            device(ecid: ecidB, location: "02100000")
        ])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        context.publish([
            device(ecid: ecidA, location: "01100000"),
            device(ecid: ecidB, location: "02100000")
        ])

        let run = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.coordinator.prepareCount == 1 }
        let frozen = try XCTUnwrap(context.workspace.activeAttempt)

        context.workspace.selectBrowsePort("port-B")

        XCTAssertEqual(context.workspace.browsePortScope, "port-B")
        XCTAssertEqual(context.workspace.activeAttempt, frozen)
        XCTAssertEqual(context.workspace.activeAttempt?.canonicalECID, canonicalHex(ecidA))
        XCTAssertEqual(context.workspace.activeAttempt?.stablePortKey, "synthetic-host|port-A")

        context.workspace.cancelRestore()
        context.coordinator.releasePrepare()
        await run.value
    }

    func testL05ChangedOrMissingTargetCannotRedirectStart() async throws {
        let context = try makeContext(maximumSnapshotAge: 0.08)
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        try await Task.sleep(nanoseconds: 110_000_000)

        let run = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.workspace.activeAttempt != nil }
        context.workspace.selectBrowsePort("port-B")
        context.publish([device(ecid: ecidB, location: "02100000")])
        await run.value

        XCTAssertEqual(context.engine.runCount, 0)
        XCTAssertEqual(context.workspace.lastCompletedTaskSnapshot?.outcome, .failure)
        XCTAssertNil(context.workspace.activeAttempt)
    }

    func testL06StaleObservationTimesOutWithoutLaunch() async throws {
        let context = try makeContext(maximumSnapshotAge: 0.08)
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        try await Task.sleep(nanoseconds: 110_000_000)

        await context.workspace.testStartPrimaryThroughConfirmation()

        XCTAssertEqual(context.engine.runCount, 0)
        XCTAssertEqual(context.workspace.lastCompletedTaskSnapshot?.outcome, .failure)
        XCTAssertNil(context.workspace.activeAttempt)
        XCTAssertFalse(context.workspace.isRestoreTaskActive)
    }

    func testL07CancelDuringHeartbeatWaitIsIdempotentAndPreventsLaunch() async throws {
        let context = try makeContext(maximumSnapshotAge: 0.15)
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        try await Task.sleep(nanoseconds: 170_000_000)

        let run = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.workspace.activeAttempt != nil }

        context.workspace.cancelRestore()
        context.workspace.cancelRestore()

        XCTAssertEqual(context.workspace.activeAttempt?.cancelRequested, true)
        XCTAssertEqual(context.workspace.activeAttempt?.launchPermitted, false)
        await run.value
        XCTAssertEqual(context.engine.runCount, 0)
        XCTAssertEqual(context.workspace.lastCompletedTaskSnapshot?.outcome, .canceled)
    }

    func testL08CancelDuringRLMPreparationPreventsLaunch() async throws {
        let context = try makeContext()
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        context.publish([device(ecid: ecidA, location: "01100000")])

        let run = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.coordinator.prepareCount == 1 }

        context.workspace.cancelRestore()

        XCTAssertEqual(context.workspace.activeAttempt?.cancelRequested, true)
        XCTAssertEqual(context.workspace.activeAttempt?.launchPermitted, false)
        context.coordinator.releasePrepare()
        await run.value

        XCTAssertEqual(context.engine.runCount, 0)
        XCTAssertEqual(context.workspace.lastCompletedTaskSnapshot?.outcome, .canceled)
    }

    func testL09EngineRefusesLaunchWhenFinalPermitIsFalse() async throws {
        let launcher = Batch1CountingLauncher()
        let engine = CfgutilRestoreEngine(launcher: launcher)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("Batch1EngineGate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let result = await engine.run(
            request: CfgutilRestoreRequest(
                taskID: UUID(),
                executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                ipswURL: URL(fileURLWithPath: "/tmp/Test.ipsw"),
                targetECID: ecidA,
                outputDirectory: output),
            launchPermitted: { false },
            onUpdate: nil)

        XCTAssertEqual(result.outcome, .canceled)
        XCTAssertEqual(launcher.launchCount, 0)
        XCTAssertTrue(engine.cancellationRequested)
    }

    func testL10CancelAfterProcessStartUsesExistingGracefulPath() async throws {
        let context = try makeContext()
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        context.publish([device(ecid: ecidA, location: "01100000")])

        let run = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.coordinator.prepareCount == 1 }
        context.coordinator.releasePrepare()
        try await waitUntil { context.engine.isWaiting }

        context.workspace.cancelRestore()

        XCTAssertEqual(context.engine.cancelCount, 1)
        XCTAssertTrue(context.workspace.isRestoreTaskActive)
        context.engine.complete(outcome: .canceled)
        await run.value
        XCTAssertEqual(context.workspace.lastCompletedTaskSnapshot?.outcome, .canceled)
        XCTAssertFalse(context.workspace.isRestoreTaskActive)
    }

    func testL11OldAttemptCleanupCannotClearNewLease() async throws {
        let context = try makeContext(maximumSnapshotAge: 0.08)
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        try await Task.sleep(nanoseconds: 110_000_000)

        let first = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.workspace.activeAttempt != nil }
        let oldAttemptID = try XCTUnwrap(context.workspace.activeAttempt?.attemptID)
        context.workspace.cancelRestore()
        await first.value

        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        context.publish([device(ecid: ecidA, location: "01100000")])
        let second = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil {
            context.coordinator.prepareCount == 1
        }
        let newLease = try XCTUnwrap(context.workspace.activeAttempt)

        context.workspace.releaseAttemptIfCurrent(attemptID: oldAttemptID)

        XCTAssertEqual(context.workspace.activeAttempt, newLease)
        XCTAssertFalse(newLease.cancelRequested)
        context.workspace.cancelRestore()
        context.coordinator.releasePrepare()
        await second.value
    }

    func testL12ActiveStateIsContinuousAcrossLeasePrepareAndProcess() async throws {
        let context = try makeContext()
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        context.publish([device(ecid: ecidA, location: "01100000")])

        let run = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.coordinator.prepareCount == 1 }
        let attemptID = try XCTUnwrap(context.workspace.activeAttempt?.attemptID)
        let taskID = try XCTUnwrap(context.workspace.currentTask?.id)
        XCTAssertTrue(context.workspace.isRestoreTaskActive)

        context.coordinator.releasePrepare()
        try await waitUntil { context.engine.isRunning }
        XCTAssertTrue(context.workspace.isRestoreTaskActive)
        XCTAssertEqual(context.workspace.activeAttempt?.attemptID, attemptID)
        XCTAssertEqual(context.workspace.currentTask?.id, taskID)

        context.engine.complete(outcome: .success)
        await run.value
        XCTAssertFalse(context.workspace.isRestoreTaskActive)
        XCTAssertEqual(context.workspace.lastCompletedTaskSnapshot?.id, taskID)
    }

    func testP001BrowsePortSwitchClearsStalePendingSelectionAtomically() async throws {
        let context = try makeContext()
        context.publish([
            device(ecid: ecidA, location: "01100000"),
            device(ecid: ecidB, location: "02100000")
        ])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        await context.workspace.computeFirmwareSHA256()
        XCTAssertEqual(context.workspace.selectedTargetID, canonicalHex(ecidA))
        XCTAssertNotNil(context.workspace.firmwareURL)
        XCTAssertNotNil(context.workspace.firmwareMetadata)
        XCTAssertFalse(context.workspace.firmwareSHA256.isEmpty)

        context.workspace.selectBrowsePort("port-B")

        XCTAssertEqual(context.workspace.browsePortScope, "port-B")
        XCTAssertEqual(context.workspace.selectedTargetID, canonicalHex(ecidB))
        XCTAssertNil(context.workspace.lockedTarget)
        XCTAssertNil(context.workspace.firmwareURL)
        XCTAssertNil(context.workspace.firmwareMetadata)
        XCTAssertEqual(context.workspace.firmwareSHA256, "")
        XCTAssertEqual(context.workspace.firmwareValidity, .unverified)
        XCTAssertEqual(context.workspace.hardwareCompatibility.status, .unverified)
        XCTAssertFalse(context.workspace.canStartRestore)
    }

    func testP001MultipleTargetsAutoSelectFirstForRestorePreparation() {
        let context = try! makeContext()
        context.publish([
            device(ecid: ecidA, location: "01100000"),
            ObservedDevice(
                id: "ecid:\(canonicalHex(ecidB))",
                ecid: canonicalHex(ecidB),
                mode: .recovery,
                locationID: "01100001",
                product: "Recovery",
                serial: "ECID:\(canonicalHex(ecidB))")
        ])
        context.workspace.refreshTargets()

        XCTAssertNotNil(context.workspace.selectedTargetID)
        XCTAssertFalse(context.workspace.canStartRestore)
    }

    func testP001StableHeartbeatDoesNotRepublishRestoreProjection() throws {
        let context = try makeContext()
        let sample = device(ecid: ecidA, location: "01100000")
        context.publish([sample])
        context.workspace.refreshTargets()
        let signature = context.workspace.availableTargets
        var publishes = 0
        let cancellable = context.workspace.objectWillChange.sink {
            publishes += 1
        }

        context.publish([sample])

        withExtendedLifetime(cancellable) {
            XCTAssertEqual(publishes, 0)
            XCTAssertEqual(context.workspace.availableTargets, signature)
        }
    }

    func testP001ObservationFailureCannotLeaveAnOldTargetStartable() async throws {
        let context = try makeContext()
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())

        context.deviceControl.applyObservationResult(
            .failed("observation failed"),
            now: Date())
        context.workspace.refreshTargets()
        await context.workspace.testStartPrimaryThroughConfirmation()

        XCTAssertNil(context.workspace.selectedTarget)
        XCTAssertFalse(context.workspace.canStartRestore)
        XCTAssertEqual(context.engine.runCount, 0)
    }

    func testBatch1UIIsWiredToLeaseIdentityAndSharedCancelPath() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let view = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/FirmwareRestoreWorkspaceView.swift"),
            encoding: .utf8)
        let app = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/App.swift"),
            encoding: .utf8)

        XCTAssertTrue(view.contains("restore.activeAttempt"))
        XCTAssertTrue(view.contains("attempt.portDisplayName"))
        XCTAssertTrue(view.contains("attempt.canonicalECID"))
        XCTAssertTrue(view.contains("restore.cancelRestore()"))
        XCTAssertTrue(view.contains("restore.isRestoreTaskActive"))
        XCTAssertTrue(view.contains("取消恢复准备"))
        XCTAssertTrue(app.contains("observationHeartbeat: deviceModel.observationHeartbeat"))
        XCTAssertTrue(app.contains("deviceModel?.observedPortKey(for: device)"))
    }

    private func canonicalHex(_ value: UInt64) -> String {
        String(format: "%016llX", value)
    }

    private func device(ecid: UInt64, location: String) -> ObservedDevice {
        ObservedDevice(
            id: "ecid:\(canonicalHex(ecid))",
            ecid: canonicalHex(ecid),
            mode: .dfu,
            locationID: location,
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:\(canonicalHex(ecid))",
            modelIdentifier: "Mac14,2",
            chipID: 0x8132,
            boardID: 0x24,
            hardwareCode: "j413ap",
            productType: "Mac14,2")
    }

    private func firmwareURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("batch1-\(UUID().uuidString).ipsw")
        XCTAssertTrue(FileManager.default.createFile(
            atPath: url.path,
            contents: Data("fixture".utf8)))
        return url
    }

    private func makeContext(
        maximumSnapshotAge: TimeInterval = 1
    ) throws -> Batch1Context {
        let store = CalibrationStore(
            testingDocument: CalibrationDocument(
                models: [],
                ports: [],
                selectedPort: ""),
            hostModel: "MacTest,1",
            builtInLayout: nil)
        let deviceControl = DeviceControlModel(
            calibration: store,
            livePorts: [],
            helperAvailable: false,
            persistPortSelection: false,
            startLiveWork: false)
        let coordinator = Batch1RLMCoordinator()
        let engine = Batch1FakeEngine()
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("Batch1RestoreLeaseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let metadataReader: (URL) throws -> IPSWMetadataReadResult = { _ in
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
        let firmwareLibrary = FirmwareLibraryStore(
            indexURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "Batch1FirmwareLibrary-\(UUID().uuidString).json"),
            metadataLoader: metadataReader)
        let workspace = RestoreWorkspaceModel(
            capture: Batch1FakeCapture(),
            engine: engine,
            outputRoot: output,
            maximumSnapshotAge: maximumSnapshotAge,
            heartbeatPollInterval: 0.005,
            cancellationGraceDelay: 0.01,
            observationHeartbeat: deviceControl.observationHeartbeat,
            portKeyResolver: { device in
                switch device.locationID {
                case "01100000": return "port-A"
                case "02100000": return "port-B"
                default: return nil
                }
            },
            portDisplayNameResolver: { key in
                key == "port-A" ? "左侧上方" : "右侧"
            },
            metadataReader: metadataReader,
            cfgutilURL: URL(fileURLWithPath: "/usr/bin/true"),
            rlmCoordinator: coordinator,
            firmwareLibrary: firmwareLibrary,
            stablePortKeyProvider: { target in
                "synthetic-host|\(target.portKey ?? "unattributed")"
            },
            processLease: RestoreProcessLease(
                lockURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "TestRestoreLease-\(UUID().uuidString).lock")))
        return Batch1Context(
            deviceControl: deviceControl,
            workspace: workspace,
            engine: engine,
            coordinator: coordinator)
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for condition", file: file, line: line)
    }
}

@MainActor
private struct Batch1Context {
    let deviceControl: DeviceControlModel
    let workspace: RestoreWorkspaceModel
    let engine: Batch1FakeEngine
    let coordinator: Batch1RLMCoordinator

    func publish(_ devices: [ObservedDevice]) {
        deviceControl.applyObservationResult(.success(devices), now: Date())
    }
}

@MainActor
private final class Batch1FakeEngine: RestoreEngineRunning {
    private(set) var runCount = 0
    private(set) var cancelCount = 0
    private(set) var forceKillCount = 0
    private(set) var request: CfgutilRestoreRequest?
    private var continuation: CheckedContinuation<Void, Never>?
    var cancellationGraceExpired = false
    var isRunning = false
    var isWaiting = false
    private var completionOutcome: RestoreOutcome = .success

    func run(
        request: CfgutilRestoreRequest,
        launchPermitted: @escaping @MainActor () -> Bool,
        onUpdate: (@MainActor (RestoreOutputSnapshot) -> Void)?
    ) async -> CfgutilRestoreRunResult {
        runCount += 1
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
            self.isWaiting = true
        }
        isWaiting = false
        isRunning = false
        return result(request: request, outcome: completionOutcome)
    }

    func cancel() {
        cancelCount += 1
    }

    func forceKill() {
        forceKillCount += 1
    }

    func complete(outcome: RestoreOutcome) {
        guard let continuation else { return }
        completionOutcome = outcome
        self.continuation = nil
        isWaiting = false
        continuation.resume()
        isRunning = false
    }

    private func result(
        request: CfgutilRestoreRequest,
        outcome: RestoreOutcome
    ) -> CfgutilRestoreRunResult {
        CfgutilRestoreRunResult(
            outcome: outcome,
            exitCode: outcome == .success ? 0 : nil,
            stdoutURL: request.outputDirectory?.appendingPathComponent("stdout.raw"),
            stderrURL: request.outputDirectory?.appendingPathComponent("stderr.raw"),
            stdoutSHA256: outcome == .success ? String(repeating: "a", count: 64) : "",
            stderrSHA256: outcome == .success ? String(repeating: "b", count: 64) : "",
            tailComplete: outcome == .success,
            cancellationRequested: outcome == .canceled,
            forcedKill: false,
            snapshot: RestoreOutputSnapshot())
    }
}

@MainActor
private final class Batch1RLMCoordinator: RestoreRLMPreparing {
    private(set) var prepareCount = 0
    private(set) var finishCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func prepare(taskID: UUID, canonicalECID: String) async -> RestoreRLMBinding {
        prepareCount += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return RestoreRLMBinding(
            taskID: taskID,
            canonicalECID: canonicalECID,
            status: .unavailable,
            rawLogURL: nil,
            startAt: Date(),
            endAt: Date(),
            reason: "Batch 1 test coordinator")
    }

    func finish(taskID: UUID, outcome: RestoreOutcome) async {
        finishCount += 1
    }

    func releasePrepare() {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume()
    }
}

@MainActor
private final class Batch1FakeCapture: RestoreCaptureLifecycle {
    var state: CaptureState = .idle
    var currentRawLogURL: URL?

    func start(preCaptureContext: String?, automatic: Bool) {
        state = .recording
    }

    func stop() {
        state = .finalizing
    }
}

@MainActor
private final class Batch1CountingLauncher: CfgutilProcessLaunching {
    private(set) var launchCount = 0

    func launch(
        request: CfgutilRestoreRequest,
        onChunk: @escaping @Sendable (RestoreOutputChannel, Data) -> Void
    ) throws -> any CfgutilProcessRunning {
        launchCount += 1
        return Batch1ImmediateProcess()
    }
}

@MainActor
private final class Batch1ImmediateProcess: CfgutilProcessRunning {
    func waitForCompletion(tailTimeout: TimeInterval) async -> CfgutilProcessCompletion {
        CfgutilProcessCompletion(
            exitCode: 0,
            stdoutEOF: true,
            stderrEOF: true,
            forcedKill: false)
    }

    func interrupt() {}
    func terminate() {}
    func forceKill() {}
}

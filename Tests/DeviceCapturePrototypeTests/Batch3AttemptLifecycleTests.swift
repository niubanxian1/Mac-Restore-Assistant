import Foundation
import XCTest
@testable import DeviceCapturePrototype
import RestoreLogEngine

@MainActor
final class Batch3AttemptLifecycleTests: XCTestCase {
    private let ecidA: UInt64 = 0x0011223344556677
    private let ecidB: UInt64 = 0x0011223344556688

    func testAttemptExistsBeforeFirstAwaitAndFreezesPolicyAndTarget() async throws {
        let context = try makeContext()
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        context.workspace.setRawSaveRequestedThisRun(true)
        // The production observer renews continuously; refresh the fixture
        // immediately before the restore action.
        context.publish([device(ecid: ecidA, location: "01100000")])

        let run = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.rlm.prepareCount == 1 }
        XCTAssertEqual(context.rlm.lastSaveRequested, false)
        let attempt = try XCTUnwrap(context.workspace.activeAttempt)

        XCTAssertEqual(attempt.attemptID, context.workspace.currentAttemptID)
        XCTAssertEqual(attempt.target.canonicalHex, canonicalHex(ecidA))
        XCTAssertEqual(attempt.rawPersistencePolicy.saveThisRun, true)
        XCTAssertEqual(attempt.stage, .preparingRLM)
        XCTAssertNotNil(attempt.lifecycle.userConfirmed)
        XCTAssertNil(attempt.lifecycle.processLaunched)

        context.workspace.setRawSaveRequestedThisRun(false)
        XCTAssertEqual(
            context.workspace.activeAttempt?.rawPersistencePolicy.saveThisRun,
            true)
        context.workspace.cancelRestore()
        context.rlm.releasePrepare()
        await run.value
    }

    func testSecondStartIsRejectedWhileAttemptIsActive() async throws {
        let context = try makeContext()
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        context.publish([device(ecid: ecidA, location: "01100000")])

        let first = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.rlm.prepareCount == 1 }
        let attemptID = try XCTUnwrap(context.workspace.currentAttemptID)

        await context.workspace.testStartPrimaryThroughConfirmation()

        XCTAssertEqual(context.workspace.currentAttemptID, attemptID)
        XCTAssertEqual(context.engine.runCount, 0)
        context.workspace.cancelRestore()
        context.rlm.releasePrepare()
        await first.value
    }

    func testBrowsePortSwitchCannotRedirectAttempt() async throws {
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
        try await waitUntil { context.rlm.prepareCount == 1 }
        let frozen = try XCTUnwrap(context.workspace.activeAttempt)

        context.workspace.selectBrowsePort("port-B")

        XCTAssertEqual(context.workspace.activeAttempt, frozen)
        XCTAssertEqual(context.workspace.activeAttempt?.target.canonicalHex, canonicalHex(ecidA))
        XCTAssertEqual(context.workspace.activeAttempt?.stablePortKey, "synthetic-host|port-A")
        context.workspace.cancelRestore()
        context.rlm.releasePrepare()
        await run.value
    }

    func testCancelDuringHeartbeatWaitPreventsEngineAndRecordsPrelaunchCancel() async throws {
        let context = try makeContext(maximumSnapshotAge: 0.08)
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        try await Task.sleep(nanoseconds: 100_000_000)

        let run = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.workspace.activeAttempt != nil }
        context.workspace.cancelRestore()
        await run.value

        XCTAssertEqual(context.engine.runCount, 0)
        XCTAssertEqual(context.workspace.lastCompletedTaskSnapshot?.outcome, .canceled)
        XCTAssertNil(context.workspace.lastCompletedTaskSnapshot?.lifecycle.processLaunched)
        XCTAssertNil(context.workspace.activeAttempt)
        let history = try await context.history.records()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.outcome, .canceled)
        XCTAssertEqual(
            history.first?.errorClassification,
            .cancellationBeforeLaunch)
        XCTAssertNil(history.first?.lifecycle.processLaunched)
    }

    func testCancelDuringRLMPreparationPreventsEngine() async throws {
        let context = try makeContext()
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        context.publish([device(ecid: ecidA, location: "01100000")])

        let run = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.rlm.prepareCount == 1 }
        context.workspace.cancelRestore()
        context.rlm.releasePrepare()
        await run.value

        XCTAssertEqual(context.engine.runCount, 0)
        XCTAssertEqual(context.workspace.lastCompletedTaskSnapshot?.outcome, .canceled)
        XCTAssertNil(context.workspace.lastCompletedTaskSnapshot?.lifecycle.processLaunched)
    }

    func testFinalPermissionRevocationPreventsProcessLaunchTimestamp() async throws {
        let context = try makeContext()
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        context.publish([device(ecid: ecidA, location: "01100000")])

        let run = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.rlm.prepareCount == 1 }
        context.workspace.cancelRestore()
        context.rlm.releasePrepare()
        await run.value

        XCTAssertEqual(context.engine.runCount, 0)
        XCTAssertNil(context.workspace.lastCompletedTaskSnapshot?.lifecycle.processLaunched)
    }

    func testOldAttemptCleanupCannotClearNewAttempt() async throws {
        let context = try makeContext(maximumSnapshotAge: 0.08)
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        try await Task.sleep(nanoseconds: 100_000_000)

        let first = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.workspace.activeAttempt != nil }
        let oldID = try XCTUnwrap(context.workspace.currentAttemptID)
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
        try await waitUntil { context.rlm.prepareCount == 1 }
        let newAttempt = try XCTUnwrap(context.workspace.activeAttempt)

        context.workspace.releaseAttemptIfCurrent(attemptID: oldID)

        XCTAssertEqual(context.workspace.activeAttempt, newAttempt)
        XCTAssertFalse(newAttempt.cancelRequested)
        context.workspace.cancelRestore()
        context.rlm.releasePrepare()
        await second.value
    }

    func testActiveStateRemainsContinuousUntilFinalHistoryWrite() async throws {
        let context = try makeContext()
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        context.publish([device(ecid: ecidA, location: "01100000")])

        let run = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.rlm.prepareCount == 1 }
        let attemptID = try XCTUnwrap(context.workspace.currentAttemptID)
        XCTAssertTrue(context.workspace.isRestoreTaskActive)
        context.rlm.releasePrepare()
        try await waitUntil { context.engine.isWaiting }
        XCTAssertEqual(context.workspace.currentAttemptID, attemptID)
        XCTAssertTrue(context.workspace.isRestoreTaskActive)

        context.engine.complete(outcome: .success)
        await run.value

        XCTAssertNil(context.workspace.activeAttempt)
        XCTAssertFalse(context.workspace.isRestoreTaskActive)
        let history = try await context.history.records()
        XCTAssertEqual(history.first?.attemptID, attemptID)
        XCTAssertEqual(history.first?.outcome, .success)
    }

    func testAttemptPolicyUsesDefaultOffAndPerRunOverrideDoesNotChangePreferences() throws {
        let context = try makeContext()
        XCTAssertFalse(context.workspace.rawSaveRequestedThisRun)
        context.workspace.setRawSaveRequestedThisRun(true)
        XCTAssertTrue(context.workspace.rawSaveRequestedThisRun)
        XCTAssertFalse(
            context.rawPersistenceSettings.autoSaveRestoreRawLogs)
    }

    func testGlobalDefaultRefreshPreservesAnExplicitPerRunChoice() {
        let context = try! makeContext()
        XCTAssertFalse(context.workspace.rawSaveRequestedThisRun)

        context.rawPersistenceSettings.autoSaveRestoreRawLogs = true
        context.workspace.refreshRawSaveSelectionFromSettingsIfNeeded()
        XCTAssertTrue(context.workspace.rawSaveRequestedThisRun)

        context.workspace.setRawSaveRequestedThisRun(true)
        context.rawPersistenceSettings.autoSaveRestoreRawLogs = false
        context.workspace.refreshRawSaveSelectionFromSettingsIfNeeded()
        XCTAssertTrue(context.workspace.rawSaveRequestedThisRun)

        context.workspace.setRawSaveRequestedThisRun(false)
        context.rawPersistenceSettings.autoSaveRestoreRawLogs = true
        context.workspace.refreshRawSaveSelectionFromSettingsIfNeeded()
        XCTAssertFalse(context.workspace.rawSaveRequestedThisRun)
    }

    func testPerRunPersistenceControlDoesNotClaimRawSinkIsComplete() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(
                "Sources/DeviceCapturePrototype/FirmwareRestoreWorkspaceView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("restore-save-raw-this-run"))
        XCTAssertTrue(source.contains("setRawSaveRequested("))
        XCTAssertTrue(source.contains(
            "关闭时不创建 raw/Staging 副本"))
        XCTAssertFalse(source.contains("属于 Batch 4"))
    }

    func testBatch4SaveDisabledDoesNotCreateStagingDirectory() async throws {
        let context = try makeContext()
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        context.publish([device(ecid: ecidA, location: "01100000")])

        let run = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.rlm.prepareCount == 1 }

        XCTAssertNil(context.workspace.currentTask?.rawOutputDirectory)
        XCTAssertEqual(
            context.workspace.currentTask?.rawEvidenceStatus,
            .notSavedByChoice)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: context.workspace.outputRoot,
                includingPropertiesForKeys: nil,
                options: []).count,
            0)

        context.workspace.cancelRestore()
        context.rlm.releasePrepare()
        await run.value
    }

    func testBatch4SaveEnabledPassesOptionalStagingRequestOnlyForThatAttempt() async throws {
        let context = try makeContext()
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        context.workspace.setRawSaveRequestedThisRun(true)
        context.publish([device(ecid: ecidA, location: "01100000")])

        let run = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.rlm.prepareCount == 1 }
        context.rlm.releasePrepare()
        try await waitUntil { context.engine.isWaiting }

        XCTAssertNotNil(context.engine.request?.outputDirectory)
        XCTAssertEqual(
            context.workspace.currentTask?.rawPersistencePolicy
                .saveThisRun,
            true)
        XCTAssertFalse(
            context.rawPersistenceSettings.autoSaveRestoreRawLogs)

        context.engine.complete(outcome: .success)
        await run.value
        XCTAssertEqual(
            context.workspace.lastCompletedTaskSnapshot?.outcome,
            .success)
    }

    func testBatch4ArchiveFailureDoesNotRewriteRestoreOutcome() async throws {
        let context = try makeContext(
            rawArchivePublisher: Batch3ThrowingArchivePublisher())
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        context.workspace.setRawSaveRequestedThisRun(true)
        context.publish([device(ecid: ecidA, location: "01100000")])

        let run = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.rlm.prepareCount == 1 }
        context.rlm.releasePrepare()
        try await waitUntil { context.engine.isWaiting }
        let output = try XCTUnwrap(
            context.engine.request?.outputDirectory)
        try FileManager.default.createDirectory(
            at: output,
            withIntermediateDirectories: true)
        try Data("stdout\n".utf8).write(
            to: output.appendingPathComponent("stdout.raw"))
        try Data("stderr\n".utf8).write(
            to: output.appendingPathComponent("stderr.raw"))

        context.engine.complete(outcome: .success)
        await run.value

        XCTAssertEqual(
            context.workspace.lastCompletedTaskSnapshot?.outcome,
            .success)
        XCTAssertNil(
            context.workspace.lastCompletedTaskSnapshot?.rawArchive)
        XCTAssertTrue(
            context.workspace.lastCompletedTaskSnapshot?
                .rawArchiveMessage.contains("Restore 终态未改变")
                == true)
    }

    func testBatch4SuccessfulArchiveIsAttachedToCancellableAttemptHistory() async throws {
        let probe = Batch3ArchiveProbe()
        let context = try makeContext(
            rawArchivePublisher:
                Batch3RecordingArchivePublisher(probe: probe))
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        context.workspace.setRawSaveRequestedThisRun(true)
        context.publish([device(ecid: ecidA, location: "01100000")])

        let run = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.rlm.prepareCount == 1 }
        context.rlm.releasePrepare()
        try await waitUntil { context.engine.isWaiting }
        let output = try XCTUnwrap(
            context.engine.request?.outputDirectory)
        try FileManager.default.createDirectory(
            at: output,
            withIntermediateDirectories: true)
        try Data("stdout\n".utf8).write(
            to: output.appendingPathComponent("stdout.raw"))
        try Data("stderr\n".utf8).write(
            to: output.appendingPathComponent("stderr.raw"))

        context.engine.complete(outcome: .success)
        await run.value

        let archived = try XCTUnwrap(
            context.workspace.lastCompletedTaskSnapshot?.rawArchive)
        XCTAssertEqual(archived.taskID, context.workspace.lastCompletedTaskSnapshot?.id)
        let lastCandidate = await probe.lastCandidate()
        let candidate = try XCTUnwrap(lastCandidate)
        XCTAssertEqual(candidate.outcome, .success)
        XCTAssertTrue(candidate.rawWriteComplete)
        XCTAssertEqual(candidate.linkedTaskIDs.count, 1)
        let history = try await context.history.records()
        XCTAssertEqual(history.first?.rawArchive?.archiveID, archived.archiveID)
    }

    private func makeContext(
        maximumSnapshotAge: TimeInterval = 1,
        rawArchivePublisher:
            (any RestoreArchivePublishing)? = nil
    ) throws -> Batch3AttemptContext {
        let calibration = CalibrationStore(
            testingDocument: CalibrationDocument(
                models: [],
                ports: [],
                selectedPort: ""),
            hostModel: "MacTest,1",
            builtInLayout: nil)
        let deviceControl = DeviceControlModel(
            calibration: calibration,
            livePorts: [],
            helperAvailable: false,
            persistPortSelection: false,
            startLiveWork: false)
        let rlm = Batch3AttemptRLM()
        let engine = Batch3AttemptEngine()
        let history = RestoreHistoryStore(fileURL:
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "Batch3AttemptHistory-\(UUID().uuidString)",
                    isDirectory: true)
                .appendingPathComponent("history-v1.json"))
        let defaults = UserDefaults(
            suiteName: "Batch3AttemptPrefs-\(UUID().uuidString)")!
        let preferences = LogWorkspacePreferences(
            defaults: defaults,
            startingRoot: FileManager.default.temporaryDirectory)
        let rawPersistenceSettings =
            RestoreRawPersistenceSettings(defaults: defaults)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Batch3AttemptOutput-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: output,
            withIntermediateDirectories: true)
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
                    "Batch3AttemptFirmwareLibrary-\(UUID().uuidString).json"),
            metadataLoader: metadataReader)
        let workspace = RestoreWorkspaceModel(
            capture: Batch3AttemptCapture(),
            engine: engine,
            outputRoot: output,
            maximumSnapshotAge: maximumSnapshotAge,
            heartbeatPollInterval: 0.004,
            cancellationGraceDelay: 0.01,
            observationHeartbeat: deviceControl.observationHeartbeat,
            portKeyResolver: { device in
                device.locationID == "01100000" ? "port-A" : "port-B"
            },
            portDisplayNameResolver: { key in
                key == "port-A" ? "左侧上方" : "右侧"
            },
            metadataReader: metadataReader,
            cfgutilURL: URL(fileURLWithPath: "/usr/bin/true"),
            rlmCoordinator: rlm,
            firmwareLibrary: firmwareLibrary,
            historyStore: history,
            rawArchivePublisher: rawArchivePublisher,
            rawPersistenceDefaultsProvider: {
                RestoreRawPersistenceDefaults(
                    autoSaveDefault:
                        rawPersistenceSettings.autoSaveRestoreRawLogs,
                    destinationDirectory: preferences.rawLogDirectory,
                    autoMonitorEnabled: preferences.autoMonitorEnabled,
                    spaceWarningThresholdBytes: nil,
                    retentionPolicy: "manual")
            },
            stablePortKeyProvider: { _ in "synthetic-host|port-A" },
            processLease: RestoreProcessLease(
                lockURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "TestRestoreLease-\(UUID().uuidString).lock")))
        return Batch3AttemptContext(
            deviceControl: deviceControl,
            workspace: workspace,
            engine: engine,
            rlm: rlm,
            history: history,
            preferences: preferences,
            rawPersistenceSettings: rawPersistenceSettings)
    }

    private func canonicalHex(_ value: UInt64) -> String {
        String(format: "%016llX", value)
    }

    private func device(ecid: UInt64, location: String) -> ObservedDevice {
        let hex = canonicalHex(ecid)
        return ObservedDevice(
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
            productType: "Mac14,2")
    }

    private func firmwareURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("batch3-\(UUID().uuidString).ipsw")
        try Data("fixture".utf8).write(to: url)
        return url
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<250 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 4_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}

@MainActor
private struct Batch3AttemptContext {
    let deviceControl: DeviceControlModel
    let workspace: RestoreWorkspaceModel
    let engine: Batch3AttemptEngine
    let rlm: Batch3AttemptRLM
    let history: RestoreHistoryStore
    let preferences: LogWorkspacePreferences
    let rawPersistenceSettings: RestoreRawPersistenceSettings

    func publish(_ devices: [ObservedDevice]) {
        deviceControl.applyObservationResult(.success(devices), now: Date())
    }
}

@MainActor
private final class Batch3AttemptEngine: RestoreEngineRunning {
    private(set) var runCount = 0
    private(set) var cancelCount = 0
    private(set) var forceKillCount = 0
    private var continuation: CheckedContinuation<Void, Never>?
    var cancellationGraceExpired = false
    var isRunning = false
    var isWaiting = false
    private(set) var request: CfgutilRestoreRequest?
    private var outcome: RestoreOutcome = .success

    func run(
        request: CfgutilRestoreRequest,
        launchPermitted: @escaping @MainActor () -> Bool,
        onUpdate: (@MainActor (RestoreOutputSnapshot) -> Void)?
    ) async -> CfgutilRestoreRunResult {
        self.request = request
        runCount += 1
        guard launchPermitted() else {
            return result(request: request, outcome: .canceled, processStarted: false)
        }
        isRunning = true
        var snapshot = RestoreOutputSnapshot()
        snapshot.restoreActivityObserved = true
        snapshot.stepText = "RestoreOS"
        onUpdate?(snapshot)
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            isWaiting = true
        }
        isWaiting = false
        isRunning = false
        return result(request: request, outcome: outcome, processStarted: true)
    }

    func cancel() {
        cancelCount += 1
    }

    func forceKill() {
        forceKillCount += 1
    }

    func complete(outcome: RestoreOutcome) {
        self.outcome = outcome
        continuation?.resume()
        continuation = nil
    }

    private func result(
        request: CfgutilRestoreRequest,
        outcome: RestoreOutcome,
        processStarted: Bool
    ) -> CfgutilRestoreRunResult {
        let start = processStarted
            ? RestoreLifecycleTimePoint(
                wallTime: Date(),
                monotonicNanoseconds: 1_000)
            : nil
        let end = processStarted
            ? RestoreLifecycleTimePoint(
                wallTime: Date(),
                monotonicNanoseconds: 11_000)
            : nil
        let lifecycle = RestoreLifecycleTimes(
            userConfirmed: RestoreLifecycleTimePoint(
                wallTime: Date(),
                monotonicNanoseconds: 500),
            processLaunched: start,
            firstRestoreActivity: start,
            processExited: end,
            bothStreamsEOF: end,
            outcomeConfirmed: end,
            rlmFinalized: nil)
        return CfgutilRestoreRunResult(
            outcome: outcome,
            exitCode: outcome == .success ? 0 : nil,
            stdoutURL: request.outputDirectory?.appendingPathComponent("stdout.raw"),
            stderrURL: request.outputDirectory?.appendingPathComponent("stderr.raw"),
            stdoutSHA256: outcome == .success ? String(repeating: "a", count: 64) : "",
            stderrSHA256: outcome == .success ? String(repeating: "b", count: 64) : "",
            tailComplete: outcome == .success,
            cancellationRequested: outcome == .canceled,
            forcedKill: false,
            snapshot: RestoreOutputSnapshot(),
            lifecycle: lifecycle,
            terminationReason: processStarted ? .exit : .unknown,
            sentSignals: [])
    }
}

@MainActor
private final class Batch3AttemptRLM: RestoreRLMPreparing {
    private(set) var prepareCount = 0
    private(set) var finishCount = 0
    private(set) var lastSaveRequested: Bool?
    var onPrepare: (() -> Void)?
    private var continuation: CheckedContinuation<Void, Never>?

    func prepare(
        taskID: UUID,
        canonicalECID: String
    ) async -> RestoreRLMBinding {
        await prepare(
            taskID: taskID,
            canonicalECID: canonicalECID,
            saveRequested: true)
    }

    func prepare(
        taskID: UUID,
        canonicalECID: String,
        saveRequested: Bool
    ) async -> RestoreRLMBinding {
        prepareCount += 1
        lastSaveRequested = saveRequested
        onPrepare?()
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return RestoreRLMBinding(
            taskID: taskID,
            canonicalECID: canonicalECID,
            status: .notRequested,
            rawLogURL: nil,
            startAt: Date(),
            endAt: Date(),
            reason: "Batch 3 test",
            ownership: .notRequested)
    }

    func finish(taskID: UUID, outcome: RestoreOutcome) async {
        finishCount += 1
    }

    func releasePrepare() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class Batch3AttemptCapture: RestoreCaptureLifecycle {
    var state: CaptureState = .idle
    var currentRawLogURL: URL?
    func start(preCaptureContext: String?, automatic: Bool) {}
    func stop() {}
}

private struct Batch3ThrowingArchivePublisher:
    RestoreArchivePublishing {
    func publish(
        stagingDirectory: URL,
        destinationRoot: URL,
        candidate: RestoreArchiveCandidate
    ) async throws -> RestoreArchivePublication {
        throw RestoreLogRetentionError.unavailable
    }
}

private actor Batch3ArchiveProbe {
    private var candidate: RestoreArchiveCandidate?

    func record(_ candidate: RestoreArchiveCandidate) {
        self.candidate = candidate
    }

    func lastCandidate() -> RestoreArchiveCandidate? {
        candidate
    }
}

private struct Batch3RecordingArchivePublisher:
    RestoreArchivePublishing {
    let probe: Batch3ArchiveProbe

    func publish(
        stagingDirectory: URL,
        destinationRoot: URL,
        candidate: RestoreArchiveCandidate
    ) async throws -> RestoreArchivePublication {
        await probe.record(candidate)
        let manifestURL = stagingDirectory.appendingPathComponent(
            "manifest.json")
        let record = RestoreArchiveRecord(
            archiveID: "synthetic-archive",
            taskID: candidate.taskID,
            attemptID: candidate.attemptID,
            directoryPath: destinationRoot.path,
            manifestPath: manifestURL.path,
            manifestSHA256: String(repeating: "a", count: 64),
            outcome: candidate.outcome,
            modelFamilyKey:
                candidate.modelFamilyKey?.rawValue,
            publishedAt: Date(),
            directorySyncLevel: .full,
            localStagingRetained: true,
            baselineEligible: candidate.baselineEligible)
        return RestoreArchivePublication(
            archiveID: record.archiveID,
            finalDirectory: destinationRoot,
            incompleteDirectory:
                destinationRoot.appendingPathComponent(
                    ".incomplete-synthetic"),
            manifestURL: manifestURL,
            manifestSHA256: record.manifestSHA256,
            directorySyncLevel: .full,
            localStagingRetained: true,
            record: record)
    }
}

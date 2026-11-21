import Foundation
import XCTest
@testable import DeviceCapturePrototype
import RestoreLogEngine

@MainActor
final class Batch2RestoreWorkspaceIntegrationTests: XCTestCase {
    private let ecid: UInt64 = 0x12345670

    func testUniqueClassInfersCompatibleAndKeepsStartEnabled() async throws {
        let context = try await makeContext(contents: ["valid": ("27.0", "26A428")])
        let hex = String(format: "%016llX", 0x12345670)
        context.deviceControl.applyObservationResult(
            .success([
                ObservedDevice(
                    id: "ecid:\(hex)",
                    ecid: hex,
                    mode: .dfu,
                    locationID: "01100000",
                    product: "Apple Mobile Device (DFU Mode)",
                    serial: "ECID:\(hex)",
                    modelIdentifier: "Mac14,2",
                    chipID: 0x8132,
                    boardID: 0x24,
                    hardwareCode: nil,
                    productType: "Mac14,2")
            ]),
            now: Date())
        context.workspace.refreshTargets()
        await context.workspace.scanFirmwareDirectory(context.root)
        let entry = try XCTUnwrap(context.workspace.firmwareLibraryEntries.first)
        context.workspace.selectFirmwareFromLibrary(id: entry.id)

        XCTAssertEqual(context.workspace.hardwareCompatibility.status, .compatible)
        XCTAssertTrue(context.workspace.canStartRestore)
    }

    func testUnverifiedHardwareCompatibilityCannotStart() async throws {
        let context = try await makeContext(contents: ["valid": ("27.0", "26A428")])
        let hex = String(format: "%016llX", 0x12345670)
        context.deviceControl.applyObservationResult(
            .success([
                ObservedDevice(
                    id: "ecid:\(hex)",
                    ecid: hex,
                    mode: .dfu,
                    locationID: "01100000",
                    product: "Apple Mobile Device (DFU Mode)",
                    serial: "ECID:\(hex)",
                    modelIdentifier: "Mac14,2",
                    chipID: nil,
                    boardID: nil,
                    hardwareCode: "j413ap",
                    productType: "Mac14,2")
            ]),
            now: Date())
        context.workspace.refreshTargets()
        await context.workspace.scanFirmwareDirectory(context.root)
        let entry = try XCTUnwrap(context.workspace.firmwareLibraryEntries.first)
        context.workspace.selectFirmwareFromLibrary(id: entry.id)

        XCTAssertEqual(context.workspace.hardwareCompatibility.status, .unverified)
        XCTAssertFalse(context.workspace.canStartRestore)
    }

    func testDirectoryScanDoesNotAutoPickLocalNewestWithoutReliablePreference() async throws {
        let context = try await makeContext(contents: [
            "27.9": ("27.9", "26C99"),
            "27.10": ("27.10", "26C100")
        ])
        context.publishDevice()
        XCTAssertNotNil(context.workspace.selectedTarget)
        XCTAssertEqual(
            context.workspace.selectedTarget?.identityProvenance,
            .liveConfirmed)

        await context.workspace.scanFirmwareDirectory(context.root)

        XCTAssertEqual(context.workspace.firmwareSelectionSource, .none)
        XCTAssertNil(context.workspace.firmwareMetadata)
        XCTAssertNil(context.workspace.recommendedFirmware)
    }

    func testManualFirmwareSelectionSurvivesLibraryAndTargetRefresh() async throws {
        let context = try await makeContext(contents: [
            "14.0": ("14.0", "23A344"),
            "27.9": ("27.9", "26C99")
        ])
        context.publishDevice()
        await context.workspace.scanFirmwareDirectory(context.root)
        let manual = try XCTUnwrap(
            context.workspace.firmwareLibraryEntries.first {
                $0.metadata?.productVersion == "14.0"
            })

        context.workspace.selectFirmwareFromLibrary(id: manual.id)
        await context.workspace.refreshFirmwareLibrary()
        context.workspace.refreshTargets()

        XCTAssertEqual(context.workspace.firmwareSelectionSource, .userManualSelected)
        XCTAssertEqual(context.workspace.firmwareURL?.standardizedFileURL, manual.url.standardizedFileURL)

        context.workspace.restoreAutomaticRecommendation()
        XCTAssertEqual(context.workspace.firmwareSelectionSource, .none)
        XCTAssertNil(context.workspace.firmwareMetadata)
    }

    func testInvalidLibraryEntryCannotBecomeLaunchEligibleOrRecommendation() async throws {
        let context = try await makeContext(contents: [
            "valid": ("27.0", "26A428")
        ])
        let invalidURL = context.root.appendingPathComponent("invalid.ipsw")
        try Data("not-a-valid-fixture".utf8).write(to: invalidURL)
        context.publishDevice()

        await context.workspace.scanFirmwareDirectory(context.root)

        let invalidEntry = try XCTUnwrap(
            context.workspace.firmwareLibraryEntries.first {
                $0.url.standardizedFileURL == invalidURL.standardizedFileURL
            })
        let validEntry = try XCTUnwrap(
            context.workspace.firmwareLibraryEntries.first {
                $0.url.standardizedFileURL != invalidURL.standardizedFileURL
                    && $0.isRestoreEligible
            })
        XCTAssertFalse(invalidEntry.isRestoreEligible)
        context.workspace.selectFirmwareFromLibrary(id: validEntry.id)
        XCTAssertTrue(context.workspace.canStartRestore)

        context.workspace.selectFirmwareFromLibrary(id: invalidEntry.id)

        XCTAssertEqual(context.workspace.firmwareLibraryEntryID, invalidEntry.id)
        XCTAssertEqual(context.workspace.firmwareValidity, .invalid)
        XCTAssertFalse(context.workspace.canStartRestore)
        XCTAssertTrue(context.workspace.startDisabledReason.contains("无效"))
        XCTAssertFalse(
            context.workspace.confirmationWarning.contains("固件文件有效"))
        XCTAssertTrue(
            context.workspace.confirmationWarning.contains("不可用于 Restore")
                || context.workspace.confirmationWarning.contains("无效"))

        context.workspace.restoreAutomaticRecommendation()

        XCTAssertEqual(context.workspace.firmwareSelectionSource, .none)
        XCTAssertNil(context.workspace.recommendedFirmware)
        XCTAssertNil(context.workspace.firmwareLibraryEntryID)
    }

    func testStartupRevalidationRejectsReplacedIPSWBeforeEngineRun() async throws {
        let context = try await makeContext(contents: [
            "AAAA": ("14.0", "23A344")
        ])
        let url = try XCTUnwrap(context.root.children().first)
        let store = FirmwareLibraryStore(
            indexURL: context.root.appendingPathComponent("library.json"),
            metadataLoader: context.loader.load)
        let workspace = context.makeWorkspace(store: store)
        await workspace.loadFirmware(url: url)
        context.publishDevice(workspace: workspace)

        try Data("BBBB".utf8).write(to: url, options: .atomic)
        await workspace.testStartPrimaryThroughConfirmation()

        XCTAssertEqual(context.engine.runCount, 0)
        XCTAssertNil(workspace.currentTask)
        XCTAssertFalse(workspace.errorMessage.isEmpty)
        XCTAssertTrue(workspace.errorMessage.contains("IPSW"))
    }

    func testMissingFirmwareAtStartupFailsClosedBeforeEngineRun() async throws {
        let context = try await makeContext(contents: [
            "delete": ("14.0", "23A344")
        ])
        let url = try XCTUnwrap(context.root.children().first)
        let store = FirmwareLibraryStore(
            indexURL: context.root.appendingPathComponent("library.json"),
            metadataLoader: context.loader.load)
        let workspace = context.makeWorkspace(store: store)
        await workspace.loadFirmware(url: url)
        context.publishDevice(workspace: workspace)

        try FileManager.default.removeItem(at: url)
        await workspace.testStartPrimaryThroughConfirmation()

        XCTAssertEqual(context.engine.runCount, 0)
        XCTAssertNil(workspace.currentTask)
        XCTAssertFalse(workspace.errorMessage.isEmpty)
        XCTAssertTrue(workspace.errorMessage.contains("IPSW"))
    }

    func testBuildManifestAndWholeFileHashesArePresentedSeparately() async throws {
        let context = try await makeContext(contents: [
            "hash": ("14.0", "23A344")
        ])
        let url = try XCTUnwrap(context.root.children().first)
        await context.workspace.loadFirmware(url: url)
        await context.workspace.computeFirmwareSHA256()

        XCTAssertEqual(context.workspace.buildManifestSHA256.count, 64)
        XCTAssertEqual(context.workspace.firmwareSHA256.count, 64)
        XCTAssertNotEqual(
            context.workspace.buildManifestSHA256,
            context.workspace.firmwareSHA256)
        XCTAssertEqual(
            context.workspace.firmwareFileIdentity?.buildManifestSHA256,
            context.workspace.buildManifestSHA256)
    }

    func testModelDefaultPrecedesGlobalDefaultAndCurrentManualSelectionWins() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let preferences = FirmwarePreferencesStore(
            fileURL: root.appendingPathComponent("preferences.json"))
        let context = try await makeContext(
            contents: [
                "global": ("14.0", "23A344"),
                "model": ("27.0", "26A428")
            ],
            preferences: preferences)
        context.publishDevice()
        await context.workspace.scanFirmwareDirectory(context.root)

        let globalEntry = try XCTUnwrap(
            context.workspace.firmwareLibraryEntries.first {
                $0.metadata?.productVersion == "14.0"
            })
        let modelEntry = try XCTUnwrap(
            context.workspace.firmwareLibraryEntries.first {
                $0.metadata?.productVersion == "27.0"
            })
        let modelKey = try XCTUnwrap(
            ModelFamilyKey(rawValue: "Mac14,2"))

        context.workspace.setGlobalFirmwareDefault(entryID: globalEntry.id)
        await context.workspace.refreshFirmwarePreferenceResolutions()
        XCTAssertEqual(
            context.workspace.firmwareLibraryEntryID,
            globalEntry.id)

        context.workspace.setModelFirmwareDefault(
            entryID: modelEntry.id,
            modelFamilyKey: modelKey)
        await context.workspace.refreshFirmwarePreferenceResolutions()
        XCTAssertEqual(
            context.workspace.firmwareLibraryEntryID,
            modelEntry.id)
        XCTAssertEqual(
            context.workspace.recommendedFirmware?.tier,
            .tier2ModelDefault)

        context.workspace.selectFirmwareFromLibrary(id: globalEntry.id)
        context.workspace.firmwarePreferencesDidChange()
        XCTAssertEqual(
            context.workspace.firmwareLibraryEntryID,
            globalEntry.id)
        XCTAssertEqual(
            context.workspace.firmwareSelectionSource,
            .userManualSelected)
    }

    func testLastSelectedCompatibleFirmwareCanResumeAutomaticPreparation() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let preferences = FirmwarePreferencesStore(
            fileURL: root.appendingPathComponent("preferences.json"))
        let context = try await makeContext(
            contents: ["selected": ("14.0", "23A344")],
            preferences: preferences)
        context.publishDevice()
        await context.workspace.scanFirmwareDirectory(context.root)
        let selected = try XCTUnwrap(
            context.workspace.firmwareLibraryEntries.first)

        context.workspace.selectFirmwareFromLibrary(id: selected.id)
        context.workspace.restoreAutomaticRecommendation()
        await context.workspace.refreshFirmwarePreferenceResolutions()

        XCTAssertEqual(
            context.workspace.firmwareLibraryEntryID,
            selected.id)
        XCTAssertEqual(
            context.workspace.recommendedFirmware?.tier,
            .tier4LastSelectedCompatible)
    }

    func testInvalidDefaultDoesNotSilentlyFallBackToAnotherFirmware() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let preferences = FirmwarePreferencesStore(
            fileURL: root.appendingPathComponent("preferences.json"))
        let oldContext = try await makeContext(
            contents: ["old": ("14.0", "23A344")],
            preferences: preferences)
        oldContext.publishDevice()
        await oldContext.workspace.scanFirmwareDirectory(oldContext.root)
        let oldEntry = try XCTUnwrap(
            oldContext.workspace.firmwareLibraryEntries.first)
        preferences.setGlobalDefault(FirmwareReference(entry: oldEntry))

        let newContext = try await makeContext(
            contents: ["new": ("27.0", "26A428")],
            preferences: preferences)
        newContext.publishDevice()
        await newContext.workspace.scanFirmwareDirectory(newContext.root)

        XCTAssertNil(newContext.workspace.firmwareURL)
        XCTAssertNil(newContext.workspace.recommendedFirmware)
        XCTAssertFalse(newContext.workspace.firmwarePreferenceIssue.isEmpty)
    }

    func testFailedDefaultSaveDoesNotClaimSuccessInRestoreWhileModel() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let blocker = root.appendingPathComponent("preference-parent-file")
        try Data("blocker".utf8).write(to: blocker)
        let preferences = FirmwarePreferencesStore(
            fileURL: blocker.appendingPathComponent("preferences.json"))
        let context = try await makeContext(
            contents: ["fixture": ("27.0", "26A428")],
            preferences: preferences)
        context.publishDevice()
        await context.workspace.scanFirmwareDirectory(context.root)
        let selected = try XCTUnwrap(
            context.workspace.firmwareLibraryEntries.first)

        XCTAssertFalse(
            context.workspace.setGlobalFirmwareDefault(entryID: selected.id))
        XCTAssertNil(preferences.globalDefault)
        XCTAssertTrue(
            context.workspace.message.contains("未能保存")
                || context.workspace.message.contains("无法保存"))
    }

    func testDefaultSaveWithoutPreferenceStoreFailsInsteadOfClaimingSuccess() async throws {
        let context = try await makeContext(
            contents: ["fixture": ("27.0", "26A428")],
            preferences: nil)
        context.publishDevice()
        await context.workspace.scanFirmwareDirectory(context.root)
        let selected = try XCTUnwrap(
            context.workspace.firmwareLibraryEntries.first)

        XCTAssertFalse(
            context.workspace.setGlobalFirmwareDefault(entryID: selected.id))
        XCTAssertFalse(context.workspace.message.contains("已保存"))

        let modelKey = try XCTUnwrap(
            ModelFamilyKey(rawValue: "Mac14,2"))
        XCTAssertFalse(
            context.workspace.setModelFirmwareDefault(
                entryID: selected.id,
                modelFamilyKey: modelKey))
        XCTAssertFalse(context.workspace.message.contains("已保存"))
    }

    func testLastUsedIsRecordedOnlyAfterCfgutilActuallyLaunches() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let preferences = FirmwarePreferencesStore(
            fileURL: root.appendingPathComponent("preferences.json"))
        let context = try await makeContext(
            contents: ["fixture": ("27.0", "26A428")],
            preferences: preferences,
            publishLaunch: true)
        context.publishDevice()
        await context.workspace.scanFirmwareDirectory(context.root)
        let selected = try XCTUnwrap(
            context.workspace.firmwareLibraryEntries.first)
        context.workspace.selectFirmwareFromLibrary(id: selected.id)

        XCTAssertNil(preferences.lastUsed)
        XCTAssertTrue(preferences.recentUsed.isEmpty)

        await context.workspace.testStartPrimaryThroughConfirmation()

        XCTAssertEqual(preferences.lastUsed?.reference.entryID, selected.id)
        XCTAssertEqual(preferences.recentUsed.first?.reference.entryID, selected.id)
    }

    func testChangingPreferencesDuringRestoreDoesNotReplaceLockedIPSWOrTarget() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let preferences = FirmwarePreferencesStore(
            fileURL: root.appendingPathComponent("preferences.json"))
        let context = try await makeContext(
            contents: [
                "locked": ("27.0", "26A428"),
                "other": ("27.1", "26B100")
            ],
            preferences: preferences,
            publishLaunch: true,
            holdEngineUntilReleased: true)
        context.publishDevice()
        await context.workspace.scanFirmwareDirectory(context.root)
        let locked = try XCTUnwrap(
            context.workspace.firmwareLibraryEntries.first {
                $0.metadata?.productVersion == "27.0"
            })
        let other = try XCTUnwrap(
            context.workspace.firmwareLibraryEntries.first {
                $0.metadata?.productVersion == "27.1"
            })
        context.workspace.selectFirmwareFromLibrary(id: locked.id)
        // Keep the launch preview fresh even when the full suite is slow.
        context.publishDevice()
        let restoreTask = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }

        let deadline = Date().addingTimeInterval(12)
        while !context.engine.started && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(
            context.engine.started,
            "engine not started: err=\(context.workspace.errorMessage) "
                + "last=\(context.workspace.lastCompletedTaskSnapshot?.failureText ?? "")")
        let lockedURL = context.workspace.currentTask?.ipswURL
        let lockedTarget = context.workspace.currentTask?.target

        context.workspace.setGlobalFirmwareDefault(entryID: other.id)
        context.workspace.selectBrowsePort("port-B")

        XCTAssertEqual(context.workspace.currentTask?.ipswURL, lockedURL)
        XCTAssertEqual(context.workspace.currentTask?.target, lockedTarget)
        XCTAssertEqual(context.workspace.activeAttempt?.ipswURL, lockedURL)
        context.engine.release()
        await restoreTask.value
    }

    func testBatch2LibraryRecommendationAndRevalidationAreWired() throws {
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
        let model = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/RestoreWorkspaceModel.swift"),
            encoding: .utf8)
        let settings = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/FirmwarePreferencesSettingsView.swift"),
            encoding: .utf8)

        XCTAssertTrue(view.contains("loadFirmwareLibrary()"))
        XCTAssertTrue(view.contains("selectFirmwareFromLibrary"))
        XCTAssertTrue(
            view.contains("Recent used")
                || view.contains("最近使用"))
        XCTAssertTrue(view.contains("设为全局默认"))
        XCTAssertTrue(view.contains("设为当前机型默认"))
        XCTAssertTrue(view.contains("RestoreStageProgressView"))
        XCTAssertTrue(view.contains("BuildManifest SHA-256"))
        XCTAssertTrue(view.contains("完整 IPSW SHA-256"))
        XCTAssertTrue(view.contains(
            "restore.firmwareURL != nil,\n               restore.firmwareValidity == .valid"))
        XCTAssertTrue(app.contains("firmwareLibrary: firmwareLibrary"))
        XCTAssertTrue(app.contains("firmwarePreferences: firmwarePreferenceStore"))
        XCTAssertTrue(model.contains("expectedIPSWIdentity"))
        XCTAssertTrue(model.contains("IPSW 文件身份与已绑定元数据不一致"))
        XCTAssertTrue(
            settings.contains("recordSelection")
                || model.contains("recordManualFirmwareSelection"))
    }

    private func makeContext(
        contents: [String: (String, String)],
        preferences: FirmwarePreferencesStore? = nil,
        publishLaunch: Bool = false,
        holdEngineUntilReleased: Bool = false
    ) async throws -> Batch2WorkspaceContext {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Batch2Workspace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (content, values) in contents {
            try Data(content.utf8).write(
                to: root.appendingPathComponent("\(values.0).ipsw"))
        }
        let loader = Batch2WorkspaceLoader(valuesByContent: contents)
        let store = FirmwareLibraryStore(
            indexURL: root.appendingPathComponent("library.json"),
            metadataLoader: loader.load)
        let deviceControl = makeDeviceControl()
        let engine = Batch2WorkspaceEngine(
            publishLaunch: publishLaunch,
            holdUntilReleased: holdEngineUntilReleased)
        let workspace = RestoreWorkspaceModel(
            capture: Batch2WorkspaceCapture(),
            engine: engine,
            outputRoot: root.appendingPathComponent("tasks", isDirectory: true),
            maximumSnapshotAge: 30,
            heartbeatPollInterval: 0.005,
            cancellationGraceDelay: 0.01,
            observationHeartbeat: deviceControl.observationHeartbeat,
            portKeyResolver: { _ in "port-A" },
            portDisplayNameResolver: { _ in "左侧上方" },
            metadataReader: loader.load,
            cfgutilURL: URL(fileURLWithPath: "/usr/bin/true"),
            rlmCoordinator: Batch2WorkspaceRLM(),
            firmwareLibrary: store,
            firmwarePreferences: preferences,
            processLease: RestoreProcessLease(
                lockURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "TestRestoreLease-\(UUID().uuidString).lock"),
                checkOrphanCfgutil: false))
        return Batch2WorkspaceContext(
            root: root,
            loader: loader,
            deviceControl: deviceControl,
            engine: engine,
            preferences: preferences,
            workspace: workspace)
    }

    private func canonicalHex(_ value: UInt64) -> String {
        String(format: "%016llX", value)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Batch2Preferences-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true)
        return url
    }

    private func makeDeviceControl() -> DeviceControlModel {
        let calibration = CalibrationStore(
            testingDocument: CalibrationDocument(
                models: [],
                ports: [],
                selectedPort: ""),
            hostModel: "MacTest,1",
            builtInLayout: nil)
        return DeviceControlModel(
            calibration: calibration,
            livePorts: [],
            helperAvailable: false,
            persistPortSelection: false,
            startLiveWork: false)
    }
}

@MainActor
private struct Batch2WorkspaceContext {
    let root: URL
    let loader: Batch2WorkspaceLoader
    let deviceControl: DeviceControlModel
    let engine: Batch2WorkspaceEngine
    let preferences: FirmwarePreferencesStore?
    let workspace: RestoreWorkspaceModel

    func makeWorkspace(store: FirmwareLibraryStore) -> RestoreWorkspaceModel {
        RestoreWorkspaceModel(
            capture: Batch2WorkspaceCapture(),
            engine: engine,
            outputRoot: root.appendingPathComponent("tasks-\(UUID().uuidString)", isDirectory: true),
            maximumSnapshotAge: 30,
            heartbeatPollInterval: 0.005,
            cancellationGraceDelay: 0.01,
            observationHeartbeat: deviceControl.observationHeartbeat,
            portKeyResolver: { _ in "port-A" },
            portDisplayNameResolver: { _ in "左侧上方" },
            metadataReader: loader.load,
            cfgutilURL: URL(fileURLWithPath: "/usr/bin/true"),
            rlmCoordinator: Batch2WorkspaceRLM(),
            firmwareLibrary: store,
            firmwarePreferences: preferences,
            processLease: RestoreProcessLease(
                lockURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "TestRestoreLease-\(UUID().uuidString).lock"),
                checkOrphanCfgutil: false))
    }

    func publishDevice(workspace: RestoreWorkspaceModel? = nil) {
        let hex = String(format: "%016llX", 0x12345670)
        deviceControl.applyObservationResult(
            .success([
                ObservedDevice(
                    id: "ecid:\(hex)",
                    ecid: hex,
                    mode: .dfu,
                    locationID: "01100000",
                    product: "Apple Mobile Device (DFU Mode)",
                    serial: "ECID:\(hex)",
                    modelIdentifier: "Mac14,2",
                    chipID: 0x8132,
                    boardID: 0x24,
                    hardwareCode: "j413ap",
                    productType: "Mac14,2")
            ]),
            now: Date())
        (workspace ?? self.workspace).refreshTargets()
    }
}

private final class Batch2WorkspaceLoader {
    private let valuesByContent: [String: (String, String)]

    init(valuesByContent: [String: (String, String)]) {
        self.valuesByContent = valuesByContent
    }

    func load(url: URL) throws -> IPSWMetadataReadResult {
        let data = try Data(contentsOf: url)
        let content = String(decoding: data, as: UTF8.self)
        guard let values = valuesByContent[content] else {
            return IPSWMetadataReadResult(
                validity: .invalid,
                metadata: nil,
                error: "Unknown fixture content")
        }
        let manifestHash = IPSWMetadataReader.sha256Hex(
            Data("BuildManifest:\(content)".utf8))
        let identity = try IPSWMetadataReader.fileIdentity(
            url: url,
            buildManifestSHA256: manifestHash)
        return IPSWMetadataReadResult(
            validity: .valid,
            metadata: IPSWMetadata(
                productTypes: ["Mac14,2"],
                identities: [
                    IPSWBuildIdentity(
                        deviceClass: "j413ap",
                        boardID: 0x24,
                        chipID: 0x8132)
                ],
                productVersion: values.0,
                productBuild: values.1),
            error: nil,
            fileIdentity: identity,
            buildManifestSHA256: manifestHash,
            wholeFileSHA256: nil)
    }
}

@MainActor
private final class Batch2WorkspaceEngine: RestoreEngineRunning {
    private let publishLaunch: Bool
    private let holdUntilReleased: Bool
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private(set) var runCount = 0
    private(set) var started = false
    var cancellationGraceExpired = false
    var isRunning = false

    init(
        publishLaunch: Bool = false,
        holdUntilReleased: Bool = false
    ) {
        self.publishLaunch = publishLaunch
        self.holdUntilReleased = holdUntilReleased
    }

    func run(
        request: CfgutilRestoreRequest,
        launchPermitted: @escaping @MainActor () -> Bool,
        onUpdate: (@MainActor (RestoreOutputSnapshot) -> Void)?
    ) async -> CfgutilRestoreRunResult {
        runCount += 1
        started = true
        isRunning = true
        if publishLaunch {
            var snapshot = RestoreOutputSnapshot()
            snapshot.processLaunched = RestoreLifecycleClock.now()
            onUpdate?(snapshot)
        }
        if holdUntilReleased {
            await withCheckedContinuation {
                releaseContinuation = $0
            }
        }
        isRunning = false
        return CfgutilRestoreRunResult(
            outcome: .failure,
            exitCode: 1,
            stdoutURL: request.outputDirectory?.appendingPathComponent("stdout.raw"),
            stderrURL: request.outputDirectory?.appendingPathComponent("stderr.raw"),
            stdoutSHA256: "",
            stderrSHA256: "",
            tailComplete: false,
            cancellationRequested: false,
            forcedKill: false,
            snapshot: RestoreOutputSnapshot())
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func cancel() {
        release()
    }

    func forceKill() {
        release()
    }
}

@MainActor
private final class Batch2WorkspaceRLM: RestoreRLMPreparing {
    func prepare(taskID: UUID, canonicalECID: String) async -> RestoreRLMBinding {
        RestoreRLMBinding(
            taskID: taskID,
            canonicalECID: canonicalECID,
            status: .unavailable,
            rawLogURL: nil,
            startAt: Date(),
            endAt: Date(),
            reason: "Batch 2 test")
    }

    func finish(taskID: UUID, outcome: RestoreOutcome) async {}
}

@MainActor
private final class Batch2WorkspaceCapture: RestoreCaptureLifecycle {
    var state: CaptureState = .idle
    var currentRawLogURL: URL?
    func start(preCaptureContext: String?, automatic: Bool) {}
    func stop() {}
}

private extension URL {
    func children() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: self,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? [])
            .filter { $0.pathExtension == "ipsw" }
    }
}

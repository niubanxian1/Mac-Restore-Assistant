import Foundation
import MRAHelperProtocol
import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class WorkbenchIntegrationTests: XCTestCase {
    func testUIFixtureRuntimePolicyFailsClosedForHelperLoggingAndStorage() throws {
        let policy = UIFixtureRuntimePolicy(environment: [
            "MRA_UI_FIXTURE": "t532-main"
        ])

        XCTAssertTrue(policy.isActive)
        XCTAssertTrue(policy.usesSimulatedCapture)
        XCTAssertEqual(policy.helperSimulation, .currentHealthy)
        let supportRoot = try! XCTUnwrap(policy.applicationSupportRoot)
        XCTAssertTrue(
            supportRoot.standardizedFileURL.path.hasPrefix(
                FileManager.default.temporaryDirectory
                    .standardizedFileURL.path))

        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Sources/DeviceCapturePrototype/App.swift"),
            encoding: .utf8)
        XCTAssertTrue(app.contains("let fixtureRestoreEngineActive = UIFixture.isActive"))
        XCTAssertTrue(app.contains(
            "engine: fixtureRestoreEngineActive\n                ? UIFixture.makeRestoreEngine()\n                : nil"))
        XCTAssertTrue(app.contains(
            "cfgutilURL: fixtureRestoreEngineActive\n                ? URL(fileURLWithPath: \"/usr/bin/true\")\n                : nil"))
    }

    func testAppearanceDefaultsToPrecisionBalancedSystem() {
        let suite = "WorkbenchIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = WorkbenchAppearancePreferences(
            defaults: defaults,
            storageKey: "test")

        XCTAssertEqual(preferences.visualStyle, .precision)
        XCTAssertEqual(preferences.appearanceMode, .system)
        XCTAssertEqual(preferences.currentPreset, .balanced)
        XCTAssertGreaterThan(preferences.glassStrength, 0)
        XCTAssertFalse(preferences.ambientBreathingEnabled)
        XCTAssertFalse(preferences.particlesEnabled)
    }

    func testParameterChangeBecomesCustomAndPersists() {
        let suite = "WorkbenchIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = WorkbenchAppearancePreferences(
            defaults: defaults,
            storageKey: "test")
        first.glassStrength = 0.22
        XCTAssertEqual(first.currentPreset, .custom)

        let restored = WorkbenchAppearancePreferences(
            defaults: defaults,
            storageKey: "test")
        XCTAssertEqual(restored.currentPreset, .custom)
        XCTAssertEqual(restored.glassStrength, 0.22, accuracy: 0.0001)
    }

    func testResetRestoresPrecisionBalancedDefaults() {
        let suite = "WorkbenchIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = WorkbenchAppearancePreferences(
            defaults: defaults,
            storageKey: "test")
        preferences.visualStyle = .spatial
        preferences.appearanceMode = .dark
        preferences.applyPreset(.immersive)
        preferences.resetToDefaults()

        XCTAssertEqual(preferences.visualStyle, .precision)
        XCTAssertEqual(preferences.appearanceMode, .system)
        XCTAssertEqual(preferences.currentPreset, .balanced)
    }

    func testSystemAccessibilitySectionIsExplicitlyReadOnlyAndHasSettingsLink() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let view = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Sources/DeviceCapturePrototype/WorkbenchAppearanceSettingsView.swift"),
            encoding: .utf8)

        XCTAssertTrue(view.contains("系统状态（只读）"))
        XCTAssertTrue(view.contains("打开 macOS 辅助功能设置…"))
        XCTAssertTrue(view.contains("SystemAccessibilitySettings.open()"))
        XCTAssertTrue(view.contains("system-reduce-motion-status"))
        XCTAssertFalse(view.contains("systemReduceMotion || reduceMotion"))
    }

    func testLaunchOverridesDoNotPersistIntoUserDefaults() {
        let suite = "WorkbenchIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let overridden = WorkbenchAppearancePreferences(
            defaults: defaults,
            storageKey: "test",
            environment: [
                "MRA_UI_VISUAL_STYLE": "spatial",
                "MRA_UI_APPEARANCE_MODE": "dark",
                "MRA_UI_APPEARANCE_PRESET": "immersive"
            ])
        XCTAssertEqual(overridden.visualStyle, .spatial)
        XCTAssertEqual(overridden.appearanceMode, .dark)
        XCTAssertEqual(overridden.currentPreset, .immersive)
        XCTAssertNil(defaults.data(forKey: "test"))

        let restored = WorkbenchAppearancePreferences(
            defaults: defaults,
            storageKey: "test",
            environment: [:])
        XCTAssertEqual(restored.visualStyle, .precision)
        XCTAssertEqual(restored.appearanceMode, .system)
        XCTAssertEqual(restored.currentPreset, .balanced)
    }

    func testZeroAndReducedMotionProduceNonMovingTokens() {
        let zero = WorkbenchMotionTokens.make(
            motionStrength: 0,
            floatingDepth: 1,
            reduceMotion: false)
        let reduced = WorkbenchMotionTokens.make(
            motionStrength: 1,
            floatingDepth: 1,
            reduceMotion: true)

        XCTAssertEqual(zero.hoverLift, 0)
        XCTAssertEqual(zero.glowRadius, 54)
        XCTAssertEqual(zero.workspaceDamping, 1)
        XCTAssertEqual(reduced.hoverLift, 0)
        XCTAssertEqual(reduced.workspaceDamping, 1)
    }

    func testRestoreRunningFixtureProvidesValidBoundedMetadata() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "restore-fixture-\(UUID().uuidString).ipsw")
        try Data("fixture".utf8).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try UIFixture.readFirmwareMetadata(url: url)

        XCTAssertEqual(result.validity, .valid)
        XCTAssertEqual(result.metadata?.productTypes, ["MacBookPro18,2"])
        XCTAssertEqual(
            result.fileIdentity?.buildManifestSHA256,
            result.buildManifestSHA256)
        XCTAssertEqual(result.buildManifestSHA256.count, 64)
    }

    func testDFUNavigationAcceptsOnlyMatchingPortAfterArm() {
        let operationID = UUID()
        let now = Date()
        var coordinator = DFUAutoNavigationCoordinator()
        coordinator.arm(portID: "controller:2", now: now)

        let wrongPort = DFUConfirmationProjection(
            operationID: UUID(),
            targetPortKey: "controller:3",
            scope: .portTransition,
            reason: "wrong port",
            evidenceTime: 1,
            publishedAt: now.addingTimeInterval(1))
        XCTAssertEqual(
            coordinator.evaluate(
                wrongPort,
                currentControlPortID: "controller:2",
                autoNavigationPaused: false,
                importantContextActive: false),
            .none)

        let matching = DFUConfirmationProjection(
            operationID: operationID,
            targetPortKey: "controller:2",
            scope: .sameDevice,
            reason: "confirmed",
            evidenceTime: 2,
            publishedAt: now.addingTimeInterval(2))
        XCTAssertEqual(
            coordinator.evaluate(
                matching,
                currentControlPortID: "controller:2",
                autoNavigationPaused: false,
                importantContextActive: false),
            .navigate(portID: "controller:2", operationID: operationID))
        XCTAssertEqual(
            coordinator.evaluate(
                matching,
                currentControlPortID: "controller:2",
                autoNavigationPaused: false,
                importantContextActive: false),
            .none)
    }

    func testDFUNavigationUsesCueWhenUserContextIsImportant() {
        let operationID = UUID()
        let now = Date()
        var coordinator = DFUAutoNavigationCoordinator()
        coordinator.arm(portID: "controller:2", now: now)
        let event = DFUConfirmationProjection(
            operationID: operationID,
            targetPortKey: "controller:2",
            scope: .portTransition,
            reason: "confirmed",
            evidenceTime: 1,
            publishedAt: now.addingTimeInterval(1))

        XCTAssertEqual(
            coordinator.evaluate(
                event,
                currentControlPortID: "controller:2",
                autoNavigationPaused: true,
                importantContextActive: false),
            .cue(portID: "controller:2", operationID: operationID))
    }

    func testDeviceWorkspaceNavigationContextDoesNotDependOnAutoRestoreSelection() {
        let normal = WorkbenchNavigationContext(
            isDeviceWorkspace: true,
            restoreTaskActive: false,
            settingsPresented: false,
            configuratorPresented: false)
        XCTAssertFalse(normal.isImportant)

        let restoreActive = WorkbenchNavigationContext(
            isDeviceWorkspace: true,
            restoreTaskActive: true,
            settingsPresented: false,
            configuratorPresented: false)
        XCTAssertTrue(restoreActive.isImportant)
    }

    func testDFUAutoNavigationHonorsFixedObservationAndUserRestorePreparation() {
        let fixedObservation = WorkbenchNavigationContext(
            isDeviceWorkspace: true,
            restoreTaskActive: false,
            settingsPresented: false,
            configuratorPresented: false,
            followsControlPort: false,
            restorePreparationActive: false)
        XCTAssertTrue(fixedObservation.isImportant)

        let restorePreparation = WorkbenchNavigationContext(
            isDeviceWorkspace: true,
            restoreTaskActive: false,
            settingsPresented: false,
            configuratorPresented: false,
            followsControlPort: true,
            restorePreparationActive: true)
        XCTAssertTrue(restorePreparation.isImportant)

        let quietDefault = WorkbenchNavigationContext(
            isDeviceWorkspace: true,
            restoreTaskActive: false,
            settingsPresented: false,
            configuratorPresented: false,
            followsControlPort: true,
            restorePreparationActive: false)
        XCTAssertFalse(quietDefault.isImportant)
    }

    func testRestoreNavigationSelectsOnlyAUniqueTargetOnTheConfirmedPort() {
        let leftTarget = restoreTarget(
            ecid: 1,
            portKey: "controller:2")
        let rightTarget = restoreTarget(
            ecid: 2,
            portKey: "controller:3")

        XCTAssertEqual(
            RestoreNavigationTargetResolver.uniqueTargetID(
                in: [leftTarget, rightTarget],
                matchingPortID: "controller:2"),
            leftTarget.id)

        let secondLeftTarget = restoreTarget(
            ecid: 3,
            portKey: "controller:2")
        XCTAssertNil(
            RestoreNavigationTargetResolver.uniqueTargetID(
                in: [leftTarget, secondLeftTarget, rightTarget],
                matchingPortID: "controller:2"))
        XCTAssertNil(
            RestoreNavigationTargetResolver.uniqueTargetID(
                in: [leftTarget, rightTarget],
                matchingPortID: "controller:9"))
    }

    func testOldProjectionCannotNavigateNewRequest() {
        let now = Date()
        var coordinator = DFUAutoNavigationCoordinator()
        coordinator.arm(portID: "controller:2", now: now)
        let old = DFUConfirmationProjection(
            operationID: UUID(),
            targetPortKey: "controller:2",
            scope: .sameDevice,
            reason: "old",
            evidenceTime: 1,
            publishedAt: now.addingTimeInterval(-1))

        XCTAssertEqual(
            coordinator.evaluate(
                old,
                currentControlPortID: "controller:2",
                autoNavigationPaused: false,
                importantContextActive: false),
            .none)
    }

    func testPortSwitchBeforeConfirmationCancelsNavigation() {
        let operationID = UUID()
        let now = Date()
        var coordinator = DFUAutoNavigationCoordinator()
        coordinator.arm(portID: "controller:2", now: now)
        let event = DFUConfirmationProjection(
            operationID: operationID,
            targetPortKey: "controller:2",
            scope: .sameDevice,
            reason: "confirmed on the armed port",
            evidenceTime: 1,
            publishedAt: now.addingTimeInterval(1))

        XCTAssertEqual(
            coordinator.evaluate(
                event,
                currentControlPortID: "controller:3",
                autoNavigationPaused: false,
                importantContextActive: false),
            .none)
        XCTAssertEqual(
            coordinator.evaluate(
                event,
                currentControlPortID: "controller:2",
                autoNavigationPaused: false,
                importantContextActive: false),
            .none,
            "the stale arm must be canceled after the Control port changes")
    }

    func testDFUObservationProjectionDrivesNavigationEndToEnd() async throws {
        let calibration = UIFixture.makeCalibrationStore()
        let ports = UIFixture.ports()
        let lower = try XCTUnwrap(
            ports.first { $0.controller == "AppleHPMDevice" && $0.portNumber == 2 })
        let source = IntegrationObservationSource(devices: [
            ObservedDevice(
                id: "ecid:00C0FFEE00000001",
                ecid: "00C0FFEE00000001",
                mode: .connected,
                locationID: "01100000",
                product: "MacBook Pro",
                serial: "ECID:00C0FFEE00000001",
                modelIdentifier: "MacBookPro18,2")
        ])
        let device = DeviceControlModel(
            calibration: calibration,
            livePorts: ports,
            helperAvailable: true,
            sequenceDelaySeconds: 0.03,
            persistPortSelection: false,
            startLiveWork: false,
            requestHandler: { action, _, _, _, requestID in
                if action == .dfu {
                    source.devices = [
                        UIFixture.lowerDFUDevice()
                    ]
                }
                return HelperResponse(
                    requestID: requestID,
                    ok: true,
                    dispatchTruth: "REQUEST_SENT",
                    exitCode: 0,
                    reason: "",
                    helperVersion: "INTEGRATION-TEST")
            })
        defer { device.stopObservationForTests() }
        device.selectPort(lower)
        device.observationReadHandler = {
            .success(source.devices)
        }
        device.startObservationForTests(
            intervalNanoseconds: 20_000_000)
        try await Task.sleep(nanoseconds: 100_000_000)

        var coordinator = DFUAutoNavigationCoordinator()
        coordinator.arm(portID: lower.id)
        var capturedEvent: DFUConfirmationProjection?
        let projected = expectation(
            description: "DFU confirmation projection")
        let observer = NotificationCenter.default.addObserver(
            forName: .mraDFUConfirmationProjected,
            object: nil,
            queue: nil
        ) { notification in
            guard
                let event = notification.object
                    as? DFUConfirmationProjection,
                event.targetPortKey == lower.id
            else {
                return
            }
            capturedEvent = event
            projected.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        device.performDFU()
        await fulfillment(of: [projected], timeout: 3)

        let event = try XCTUnwrap(capturedEvent)
        XCTAssertEqual(event.scope, .sameDevice)
        XCTAssertEqual(
            coordinator.evaluate(
                event,
                currentControlPortID: lower.id,
                autoNavigationPaused: false,
                importantContextActive: false),
            .navigate(portID: lower.id, operationID: event.operationID))
    }

    private func restoreTarget(
        ecid: UInt64,
        portKey: String
    ) -> RestoreTarget {
        RestoreTarget(
            ecid: ecid,
            canonicalHex: String(format: "%016llX", ecid),
            productType: "MacBookPro18,2",
            deviceClass: "j314s",
            boardID: 0x24,
            chipID: 0x6001,
            locationID: "01100000",
            connectionGeneration: 1,
            portKey: portKey,
            portDisplayName: "左侧下方",
            mode: .dfu,
            displayName: "MacBook Pro")
    }
}

@MainActor
private final class IntegrationObservationSource {
    var devices: [ObservedDevice]

    init(devices: [ObservedDevice]) {
        self.devices = devices
    }
}

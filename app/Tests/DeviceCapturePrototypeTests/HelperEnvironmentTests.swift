import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class HelperEnvironmentTests: XCTestCase {
    private func dest(_ root: URL) -> HelperDestinations {
        HelperDestinations(
            helper: root.appendingPathComponent("helper"),
            backend: root.appendingPathComponent("backend"),
            plist: root.appendingPathComponent("plist"),
            socket: root.appendingPathComponent("sock"),
            logDirectory: root.appendingPathComponent("logs", isDirectory: true),
            packageDirectory: root)
    }

    private func model(root: URL, io: MockHelperEnvironmentIO, executor: MockHelperCommandExecutor) -> HelperEnvironmentModel {
        HelperEnvironmentModel(destinations: dest(root), io: io, executor: executor, requireExecutor: true)
    }

    func testNotInstalledOffersInstall() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("he-\(UUID().uuidString)")
        let io = MockHelperEnvironmentIO()
        let exec = MockHelperCommandExecutor()
        let model = model(root: root, io: io, executor: exec)
        model.redetect()
        XCTAssertEqual(model.snapshot.kind, .notInstalled)
        XCTAssertEqual(Set(model.snapshot.allowedActions), [.install, .redetect])
    }

    func testCurrentHealthyOffersUninstall() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("he-\(UUID().uuidString)")
        let io = MockHelperEnvironmentIO()
        io.files = [
            dest(root).helper.path: (KnownHelperManifest.expectedCurrentHelperSHA256, "6NFD357KL3", "签名有效"),
            dest(root).backend.path: (KnownHelperManifest.expectedCurrentBackendSHA256, "6NFD357KL3", "签名有效"),
            dest(root).plist.path: (KnownHelperManifest.expectedCurrentPlistSHA256, nil, "N/A"),
        ]
        io.launchctl = "state = running\npid = 123"
        io.socketIsListening = true
        let exec = MockHelperCommandExecutor()
        let model = model(root: root, io: io, executor: exec)
        model.redetect()
        XCTAssertEqual(model.snapshot.kind, .currentHealthy)
        XCTAssertEqual(model.snapshot.statusLine, "已安装 · 已连接")
        XCTAssertEqual(model.snapshot.homeStatusText, "Helper 已连接")
        XCTAssertEqual(Set(model.snapshot.allowedActions), [.redetect, .uninstall])
    }

    func testCurrentHelperWithKnownLegacyBackendShowsBackendUpdate() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("he-\(UUID().uuidString)")
        let io = MockHelperEnvironmentIO()
        io.files = [
            dest(root).helper.path: (KnownHelperManifest.expectedCurrentHelperSHA256, "6NFD357KL3", "签名有效"),
            dest(root).backend.path: (KnownHelperManifest.knownLegacyBackendSHA256.last!, "6NFD357KL3", "签名有效"),
            dest(root).plist.path: (KnownHelperManifest.expectedCurrentPlistSHA256, nil, "N/A"),
        ]
        io.launchctl = "state = running\npid = 123"
        io.socketIsListening = true
        let model = model(root: root, io: io, executor: MockHelperCommandExecutor())
        model.redetect()
        XCTAssertEqual(model.snapshot.kind, .backendNeedsUpdate)
        XCTAssertEqual(model.snapshot.homeStatusText, "Helper · 后端待更新")
        XCTAssertEqual(model.snapshot.statusColor, "orange")
        XCTAssertEqual(model.snapshot.statusLine, "已安装 · 后端待更新")
        XCTAssertTrue(model.snapshot.allowedActions.contains(.upgrade))
        XCTAssertTrue(model.snapshot.allowedActions.contains(.redetect))
        XCTAssertFalse(model.snapshot.allowedActions.contains(.install))
        XCTAssertNotEqual(model.snapshot.kind, .detectFailed)
    }

    func testCurrentUnhealthyOffersRepair() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("he-\(UUID().uuidString)")
        let io = MockHelperEnvironmentIO()
        io.files = [
            dest(root).helper.path: (KnownHelperManifest.expectedCurrentHelperSHA256, "6NFD357KL3", "签名有效"),
            dest(root).backend.path: (KnownHelperManifest.expectedCurrentBackendSHA256, "6NFD357KL3", "签名有效"),
            dest(root).plist.path: (KnownHelperManifest.expectedCurrentPlistSHA256, nil, "N/A"),
        ]
        io.launchctl = "Could not find service"
        io.socketIsListening = false
        let model = model(root: root, io: io, executor: MockHelperCommandExecutor())
        model.redetect()
        XCTAssertEqual(model.snapshot.kind, .currentUnhealthy)
        XCTAssertTrue(model.snapshot.allowedActions.contains(.repair))
    }

    func testKnownLegacyOffersUpgrade() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("he-\(UUID().uuidString)")
        let io = MockHelperEnvironmentIO()
        io.files = [
            dest(root).helper.path: (KnownHelperManifest.knownLegacyHelperSHA256[0], "6NFD357KL3", "签名有效"),
            dest(root).backend.path: (KnownHelperManifest.expectedCurrentBackendSHA256, "6NFD357KL3", "签名有效"),
            dest(root).plist.path: (KnownHelperManifest.expectedCurrentPlistSHA256, nil, "N/A"),
        ]
        let model = model(root: root, io: io, executor: MockHelperCommandExecutor())
        model.redetect()
        XCTAssertEqual(model.snapshot.kind, .knownLegacy)
        XCTAssertTrue(model.snapshot.allowedActions.contains(.upgrade))
        XCTAssertTrue(model.snapshot.allowedActions.contains(.uninstall))
        XCTAssertFalse(model.snapshot.allowedActions.contains(.install))
        let primary = HelperManagementPresentation.primaryActions(from: model.snapshot.allowedActions)
        XCTAssertTrue(primary.contains(.upgrade))
        XCTAssertTrue(primary.contains(.uninstall))

        // A live legacy service/socket must not block the uninstall action any
        // more; the script itself stops and waits before deleting.
        io.launchctl = "state = running\npid = 123"
        io.socketIsListening = true
        model.redetect()
        let exec = MockHelperCommandExecutor()
        let liveModel = HelperEnvironmentModel(destinations: dest(root), io: io, executor: exec, requireExecutor: true)
        liveModel.redetect()
        liveModel.perform(.uninstall, quarantineConfirmed: true)
        XCTAssertEqual(exec.runs.count, 1)
        XCTAssertEqual(exec.runs.first?.executable.lastPathComponent, "uninstall-mra-device-control.sh")
        XCTAssertTrue(exec.runs.first?.requiresAdmin == true)
    }

    func testUnknownFileOffersNoDestructiveAction() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("he-\(UUID().uuidString)")
        let io = MockHelperEnvironmentIO()
        io.files = [
            dest(root).helper.path: ("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", "UNKNOWNTEAM", "签名有效"),
        ]
        let exec = MockHelperCommandExecutor()
        let model = model(root: root, io: io, executor: exec)
        model.redetect()
        XCTAssertEqual(model.snapshot.kind, .unknown)
        XCTAssertEqual(model.snapshot.allowedActions, [.redetect])
        model.perform(.uninstall, quarantineConfirmed: true)
        XCTAssertTrue(exec.runs.isEmpty)
        model.perform(.upgrade, quarantineConfirmed: true)
        XCTAssertTrue(exec.runs.isEmpty)
    }

    func testQuarantineUnconfirmedStillInvokesExecutorWithFlagButInstallRequiresConfirmForCopy() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("he-\(UUID().uuidString)")
        let io = MockHelperEnvironmentIO()
        let exec = MockHelperCommandExecutor()
        var seenConfirmFlag: String?
        exec.handler = { spec in
            seenConfirmFlag = spec.environment["MRA_REQUIRE_QUARANTINE_CONFIRM"]
            return CommandResult(exitCode: 0, stdout: "OK", stderr: "")
        }
        let model = model(root: root, io: io, executor: exec)
        model.redetect()
        XCTAssertEqual(model.snapshot.kind, .notInstalled)
        model.perform(.install, quarantineConfirmed: false)
        XCTAssertEqual(exec.runs.count, 1)
        XCTAssertEqual(seenConfirmFlag, "1")
        XCTAssertEqual(exec.runs[0].environment["HELPER_DST"], dest(root).helper.path)
        XCTAssertFalse(dest(root).helper.path.hasPrefix("/Library/"))
    }

    func testMissingExecutorFailsClosedInTests() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("he-\(UUID().uuidString)")
        let io = MockHelperEnvironmentIO()
        let model = HelperEnvironmentModel(destinations: dest(root), io: io, executor: nil, requireExecutor: true)
        model.redetect()
        model.perform(.install, quarantineConfirmed: true)
        XCTAssertTrue(model.managementMessage.contains("替身") || model.managementMessage.contains("执行器"))
    }

    func testUninstallRunsScriptEvenWhenServiceOrSocketLive() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("he-\(UUID().uuidString)")
        let io = MockHelperEnvironmentIO()
        io.files = [
            dest(root).helper.path: (KnownHelperManifest.expectedCurrentHelperSHA256, "6NFD357KL3", "签名有效"),
            dest(root).backend.path: (KnownHelperManifest.expectedCurrentBackendSHA256, "6NFD357KL3", "签名有效"),
            dest(root).plist.path: (KnownHelperManifest.expectedCurrentPlistSHA256, nil, "N/A"),
        ]
        io.launchctl = "state = running\npid = 123"
        io.socketIsListening = true
        let exec = MockHelperCommandExecutor()
        let model = model(root: root, io: io, executor: exec)
        model.redetect()
        XCTAssertEqual(model.snapshot.kind, .currentHealthy)
        model.perform(.uninstall, quarantineConfirmed: true)
        XCTAssertEqual(exec.runs.count, 1)
        XCTAssertEqual(exec.runs.first?.executable.lastPathComponent, "uninstall-mra-device-control.sh")
        XCTAssertTrue(exec.runs.first?.requiresAdmin == true)
        XCTAssertFalse(model.managementMessage.contains("未删除"))
    }

    func testDetectionDoesNotRequestAdmin() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("he-\(UUID().uuidString)")
        let exec = MockHelperCommandExecutor()
        let model = model(root: root, io: MockHelperEnvironmentIO(), executor: exec)
        model.redetect()
        XCTAssertTrue(exec.runs.isEmpty, "detect must not invoke management commands")
    }
}

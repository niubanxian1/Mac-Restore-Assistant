import XCTest
@testable import DeviceCapturePrototype
import Darwin
import MRAHelperProtocol

@MainActor
final class HelperEnvironmentTests: XCTestCase {
    func testMissingManagementScriptFailsBeforeAuthorization() {
        let missing = URL(fileURLWithPath: "/tmp/mra-missing-\(UUID().uuidString)/uninstall.sh")
        let spec = CommandSpec(executable: missing, arguments: [], environment: [:], requiresAdmin: true)
        XCTAssertThrowsError(try ProcessHelperCommandExecutor().run(spec)) { error in
            XCTAssertTrue(error.localizedDescription.contains("重新打开"))
        }
    }

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
        XCTAssertTrue(model.snapshot.allowedActions.contains(.uninstall))
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
        XCTAssertTrue(model.snapshot.allowedActions.contains(.uninstall))
    }

    func testExitedServiceWithStaleSocketIsNotHealthy() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("he-\(UUID().uuidString)")
        let io = MockHelperEnvironmentIO()
        io.files = [
            dest(root).helper.path: (KnownHelperManifest.expectedCurrentHelperSHA256, "6NFD357KL3", "签名有效"),
            dest(root).backend.path: (KnownHelperManifest.expectedCurrentBackendSHA256, "", "签名有效"),
            dest(root).plist.path: (KnownHelperManifest.expectedCurrentPlistSHA256, nil, "N/A"),
        ]
        io.launchctl = "state = exited\nlast exit code = 1"
        io.socketIsListening = true
        let model = model(root: root, io: io, executor: MockHelperCommandExecutor())
        model.redetect()
        XCTAssertEqual(model.snapshot.kind, .currentUnhealthy)
        XCTAssertTrue(model.snapshot.allowedActions.contains(.uninstall))
    }

    func testLiveSocketProbeRejectsStaleSocketFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mra-stale-\(UUID().uuidString).sock")
        let fd = try bindUnixSocket(at: url, listening: false)
        close(fd)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(LiveHelperEnvironmentIO().socketListening(at: url))
    }

    func testLiveSocketProbeAcceptsListeningSocket() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mra-live-\(UUID().uuidString).sock")
        let fd = try bindUnixSocket(at: url, listening: true)
        defer {
            close(fd)
            try? FileManager.default.removeItem(at: url)
        }
        XCTAssertTrue(LiveHelperEnvironmentIO().socketListening(at: url))
    }

    func testKnownLegacyOffersUpgrade() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("he-\(UUID().uuidString)")
        let io = MockHelperEnvironmentIO()
        io.files = [
            dest(root).helper.path: (KnownHelperManifest.knownLegacyHelperSHA256[0], "6NFD357KL3", "签名有效"),
            dest(root).backend.path: (KnownHelperManifest.knownLegacyBackendSHA256[0], "6NFD357KL3", "签名有效"),
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

    func testInstallCompletionRefreshesDeviceConnectionWithoutRestart() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("he-\(UUID().uuidString)")
        let io = MockHelperEnvironmentIO()
        let exec = MockHelperCommandExecutor()
        let helper = model(root: root, io: io, executor: exec)
        helper.redetect()
        XCTAssertEqual(helper.snapshot.kind, .notInstalled)

        let responseExpected = expectation(description: "device Helper status refreshed")
        let document = CalibrationDocument(models: [], ports: [], selectedPort: "")
        let calibration = CalibrationStore(
            testingDocument: document,
            hostModel: "test",
            builtInLayout: nil,
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("helper-sync-calibration-\(UUID().uuidString).json"))
        let device = DeviceControlModel(
            calibration: calibration,
            helperAvailable: false,
            persistPortSelection: false,
            startLiveWork: false,
            requestHandler: { action, _, _, _, requestID in
                XCTAssertEqual(action, .status)
                responseExpected.fulfill()
                return HelperResponse(
                    requestID: requestID,
                    ok: true,
                    dispatchTruth: "NOT_DISPATCHED",
                    exitCode: nil,
                    reason: "READY",
                    helperVersion: "0.2.5")
            })
        XCTAssertFalse(device.helperAvailable)

        helper.bindDeviceConnection(device)
        exec.handler = { _ in
            io.files = [
                self.dest(root).helper.path: (
                    KnownHelperManifest.expectedCurrentHelperSHA256, "6NFD357KL3", "签名有效"),
                self.dest(root).backend.path: (
                    KnownHelperManifest.expectedCurrentBackendSHA256, "6NFD357KL3", "签名有效"),
                self.dest(root).plist.path: (
                    KnownHelperManifest.expectedCurrentPlistSHA256, nil, "N/A"),
            ]
            io.launchctl = "state = running\npid = 123"
            io.socketIsListening = true
            return CommandResult(exitCode: 0, stdout: "INSTALL_OK", stderr: "")
        }
        helper.perform(.install, quarantineConfirmed: true)

        await fulfillment(of: [responseExpected], timeout: 2)
        XCTAssertEqual(helper.snapshot.kind, .currentHealthy)
        XCTAssertTrue(device.helperAvailable)
        XCTAssertEqual(device.helperStatusText, "已连接 · 0.2.5")
    }

    func testSuccessfulHelperRefreshClearsStaleUnavailableFeedback() async {
        let document = CalibrationDocument(models: [], ports: [], selectedPort: "")
        let calibration = CalibrationStore(
            testingDocument: document,
            hostModel: "test",
            builtInLayout: nil,
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("helper-feedback-\(UUID().uuidString).json"))
        var helperReady = false
        let device = DeviceControlModel(
            calibration: calibration,
            helperAvailable: false,
            persistPortSelection: false,
            startLiveWork: false,
            requestHandler: { _, _, _, _, requestID in
                if helperReady {
                    return HelperResponse(
                        requestID: requestID, ok: true, dispatchTruth: "NOT_DISPATCHED",
                        exitCode: nil, reason: "READY", helperVersion: "0.2.5")
                }
                return HelperResponse(
                    requestID: requestID, ok: false, dispatchTruth: "NOT_DISPATCHED",
                    exitCode: nil, reason: "HELPER_UNAVAILABLE")
            })
        await device.refreshHelper()
        XCTAssertEqual(device.feedback.title, "Helper 不可用")

        helperReady = true
        await device.refreshHelper()
        XCTAssertTrue(device.helperAvailable)
        XCTAssertEqual(device.feedback.title, "等待操作")
        XCTAssertEqual(device.feedback.semantic, .idle)
    }

    private func bindUnixSocket(at url: URL, listening: Bool) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.ENFILE) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = Array(url.path.utf8)
        guard path.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            for index in path.indices { dst[index] = path[index] }
        }
        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        if listening, Darwin.listen(fd, 1) != 0 {
            let code = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return fd
    }
}

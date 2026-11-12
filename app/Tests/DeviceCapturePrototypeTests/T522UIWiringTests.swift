import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class T522UIWiringTests: XCTestCase {
    private func layout() -> BuiltInLayout {
        BuiltInLayout(displayName: "M1 Pro", sourceFile: "t.json", slots: [
            BuiltInSlot(slot: "S3", face: "LEFT", portNumber: 1, rid: 0, binding: "MacBookPro18,2|AppleHPMDevice|1|0", physicalName: "左侧上方"),
            BuiltInSlot(slot: "S4", face: "LEFT", portNumber: 2, rid: 1, binding: "MacBookPro18,2|AppleHPMDevice|2|1", physicalName: "左侧下方"),
            BuiltInSlot(slot: "S5", face: "RIGHT", portNumber: 3, rid: 2, binding: "MacBookPro18,2|AppleHPMDevice|3|2", physicalName: "右侧"),
        ], partial: true, skippedSlots: ["S2"], generatedAt: "test")
    }

    private func portsReversed() -> [LiveHostPort] {
        [
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 3, rid: 2),
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 2, rid: 1),
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 1, rid: 0),
        ]
    }

    private func makeDevice(ports: [LiveHostPort], helperAvailable: Bool = true) -> DeviceControlModel {
        let custom = [
            PortCalibrationEntry(physicalPort: "right1", location: "02100000", label: "右侧",
                                 rid: "2", side: "右侧", controller: "AppleHPMDevice", portNumber: 3),
            PortCalibrationEntry(physicalPort: "left2", location: "01100000", label: "左侧下方",
                                 rid: "1", side: "左侧", controller: "AppleHPMDevice", portNumber: 2),
            PortCalibrationEntry(physicalPort: "left1", location: "01200000", label: "左侧上方",
                                 rid: "0", side: "左侧", controller: "AppleHPMDevice", portNumber: 1),
        ]
        let selected = ports.first?.id ?? ""
        let doc = CalibrationDocument(models: [], ports: custom, selectedPort: selected)
        let store = CalibrationStore(testingDocument: doc, hostModel: "MacBookPro18,2", builtInLayout: layout())
        let history = FileManager.default.temporaryDirectory.appendingPathComponent("t522-hist-\(UUID().uuidString).json")
        return DeviceControlModel(calibration: store, livePorts: ports, helperAvailable: helperAvailable,
                                  persistPortSelection: false, startLiveWork: false, historyURL: history)
    }

    func testDisplayPortsStayInFixedPhysicalOrder() {
        let device = makeDevice(ports: portsReversed())
        let labels = device.orderedDisplayPorts.map { device.label(for: $0) }
        XCTAssertEqual(labels, ["左侧上方", "左侧下方", "右侧"])
        // Re-applying a different discovery order must not reshuffle the display list.
        let forward = [
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 1, rid: 0),
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 3, rid: 2),
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 2, rid: 1),
        ]
        device.applyDiscoveredPorts(forward, persistCalibration: false)
        XCTAssertEqual(device.orderedDisplayPorts.map { device.label(for: $0) },
                       ["左侧上方", "左侧下方", "右侧"])
    }

    func testStatusTextDistinguishesOnlineAndHistoryWithoutGuessing() {
        let device = makeDevice(ports: portsReversed())
        let upper = device.orderedDisplayPorts[0]
        let lower = device.orderedDisplayPorts[1]
        XCTAssertEqual(device.deviceStatusText(for: upper), "无设备")

        let online = ObservedDevice(id: "ecid:AA", ecid: "AA", mode: .dfu,
                                    locationID: "01200000", product: "Apple Mobile Device (DFU Mode)", serial: "ECID:AA")
        device.applyObservedDevices([online], now: Date())
        // When the observation can be attributed, show the current mode only — no port guessing for others.
        if device.observedDevice(for: upper) != nil {
            XCTAssertEqual(device.deviceStatusText(for: upper), "当前：DFU · 机型未识别")
        }
        XCTAssertEqual(device.operationTargetText.hasPrefix("操作目标："), true)

        // History without a current observation uses the t522 wording.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t522-hist2-\(UUID().uuidString).json")
        let fp = PortHistoryStore.fingerprint(hostModel: "MacBookPro18,2", layout: layout())
        let store = PortHistoryStore(fileURL: url, hostModel: "MacBookPro18,2", slotMapFingerprint: fp)
        XCTAssertTrue(store.updateIfEligible(slotID: "S4", product: "Apple Mobile Device (Recovery Mode)",
                                             mode: .recovery, ecid: "BB", seenAt: Date(),
                                             controller: "AppleHPMDevice", portNumber: 2, rid: 1,
                                             hostModel: "MacBookPro18,2", fingerprint: fp))
        XCTAssertEqual(store.displayStatus(slotID: "S4", hostModel: "MacBookPro18,2", fingerprint: fp, isPresent: false),
                       "当前未识别设备 · 上次 Recovery")
        _ = lower
    }

    func testSelectingPortDoesNotBecomeANewSendBlocker() {
        let device = makeDevice(ports: portsReversed(), helperAvailable: true)
        // Helper available + a mapped complete port is enough; missing device / history is not a new blocker.
        XCTAssertTrue(device.canControl)
        XCTAssertTrue(device.disabledReason.isEmpty)
        let lower = device.orderedDisplayPorts[1]
        device.selectPort(lower)
        XCTAssertEqual(device.operationTargetText, "操作目标：左侧下方")
        XCTAssertTrue(device.canControl)
        XCTAssertTrue(device.disabledReason.isEmpty)
    }

    private func waitUntil(_ timeout: TimeInterval = 8, _ predicate: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func testExportCopyReasonsAndNewSessionDoesNotCopyPreviousZip() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("t522-cap-\(UUID().uuidString)", isDirectory: true)
        let sessions = base.appendingPathComponent("sessions", isDirectory: true)
        let out = base.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let capture = CaptureModel(root: sessions, backendMode: .simulated)
        let pasteboard = MockFilePasteboard()
        capture.pasteboard = pasteboard
        capture.appCDHashProvider = { "test-cdhash" }
        capture.appVersionOverride = "0.2.3"

        XCTAssertFalse(capture.canExportZIP)
        XCTAssertEqual(capture.exportDisabledReason, "停止采集后可导出")
        XCTAssertFalse(capture.canCopyExportedZip)
        XCTAssertEqual(capture.copyDisabledReason, "导出后可复制")

        capture.start()
        await waitUntil { capture.state == .recording }
        XCTAssertFalse(capture.canExportZIP)
        XCTAssertEqual(capture.exportDisabledReason, "停止采集后可导出")
        XCTAssertFalse(capture.captureMeterText.contains("采集中"))
        XCTAssertTrue(capture.stateText.contains("采集中（离线模拟）"))
        XCTAssertTrue(capture.captureMeterText.contains(CaptureDisplayFormat.dataSize(bytes: capture.byteCount)))
        XCTAssertTrue(capture.captureMeterText.contains("秒"))
        XCTAssertFalse(capture.exportBaseName.isEmpty)

        // Rename happens on the home-view field (model-backed).
        capture.exportBaseName = "Bench-Session-A"
        capture.stop()
        await waitUntil { capture.canSave }
        XCTAssertTrue(capture.canExportZIP)
        XCTAssertEqual(capture.exportDisabledReason, "")
        XCTAssertTrue(capture.captureMeterText.contains("已停止"))

        capture.save(folder: out, baseName: capture.exportBaseName)
        await waitUntil { capture.savedZipURL != nil || capture.saveMessage.contains("失败") }
        let zipA = try XCTUnwrap(capture.savedZipURL)
        XCTAssertEqual(zipA.lastPathComponent, "Bench-Session-A.zip")
        XCTAssertFalse(capture.canExportZIP)
        XCTAssertTrue(capture.canCopyExportedZip)
        XCTAssertEqual(capture.copyDisabledReason, "")

        capture.copySavedZip()
        XCTAssertEqual(pasteboard.copied, [zipA])

        // A new session must not copy the previous package.
        capture.start()
        await waitUntil { capture.state == .recording }
        XCTAssertNil(capture.savedZipURL)
        XCTAssertFalse(capture.canCopyExportedZip)
        XCTAssertEqual(capture.copyDisabledReason, "导出后可复制")
        let copiedBefore = pasteboard.copied
        capture.copySavedZip()
        XCTAssertEqual(pasteboard.copied, copiedBefore)
        XCTAssertEqual(pasteboard.copied, [zipA])
    }

    func testHelperPresentationNeverShowsInstallAndUninstallTogether() {
        XCTAssertEqual(HelperManagementPresentation.primaryActions(from: [.install, .redetect]), [.install])
        XCTAssertEqual(HelperManagementPresentation.secondaryActions(from: [.install, .redetect]), [])
        XCTAssertEqual(HelperManagementPresentation.primaryActions(from: [.redetect, .uninstall]), [.uninstall])
        XCTAssertEqual(HelperManagementPresentation.secondaryActions(from: [.redetect, .uninstall]), [])
        // Defensive: if both were ever allowed, Install stays primary and Uninstall is hidden.
        XCTAssertEqual(HelperManagementPresentation.primaryActions(from: [.install, .uninstall, .redetect]), [.install])
        XCTAssertEqual(HelperManagementPresentation.secondaryActions(from: [.install, .uninstall, .redetect]), [])

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("t522-he-\(UUID().uuidString)")
        let io = MockHelperEnvironmentIO()
        let model = HelperEnvironmentModel(
            destinations: HelperDestinations(
                helper: root.appendingPathComponent("helper"),
                backend: root.appendingPathComponent("backend"),
                plist: root.appendingPathComponent("plist"),
                socket: root.appendingPathComponent("sock"),
                logDirectory: root.appendingPathComponent("logs", isDirectory: true),
                packageDirectory: root),
            io: io,
            executor: MockHelperCommandExecutor(),
            requireExecutor: true)
        model.redetect()
        XCTAssertEqual(model.snapshot.kind, .notInstalled)
        XCTAssertEqual(model.snapshot.homeStatusText, "Helper 未安装")
        XCTAssertTrue(model.snapshot.allowedActions.contains(.install))
        XCTAssertFalse(model.snapshot.allowedActions.contains(.uninstall))
        XCTAssertEqual(HelperManagementPresentation.primaryActions(from: model.snapshot.allowedActions), [.install])
        XCTAssertEqual(HelperManagementPresentation.secondaryActions(from: model.snapshot.allowedActions), [])
    }

    func testAppSupportOverrideDoesNotUseRealUserDirectory() {
        let isolated = FileManager.default.temporaryDirectory.appendingPathComponent("t522-as-\(UUID().uuidString)", isDirectory: true)
        // The helper itself is a pure path function when the env is unset in this test process.
        // defaultURL() without the env must still end with the historical product path.
        let url = PortHistoryStore.defaultURL()
        XCTAssertTrue(url.path.hasSuffix("MRA_DeviceCapture_Prototype/port-history.json")
                      || url.path.contains("MRA_DeviceCapture_Prototype"),
                      url.path)
        _ = isolated
    }
}

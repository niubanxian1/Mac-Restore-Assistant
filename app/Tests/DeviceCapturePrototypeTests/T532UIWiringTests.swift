import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class T532UIWiringTests: XCTestCase {
    private func layout() -> BuiltInLayout {
        BuiltInLayout(displayName: "M1 Pro", sourceFile: "t.json", slots: [
            BuiltInSlot(slot: "S3", face: "LEFT", portNumber: 1, rid: 0, binding: "MacBookPro18,2|AppleHPMDevice|1|0", physicalName: "左侧上方"),
            BuiltInSlot(slot: "S4", face: "LEFT", portNumber: 2, rid: 1, binding: "MacBookPro18,2|AppleHPMDevice|2|1", physicalName: "左侧下方"),
            BuiltInSlot(slot: "S5", face: "RIGHT", portNumber: 3, rid: 2, binding: "MacBookPro18,2|AppleHPMDevice|3|2", physicalName: "右侧"),
        ], partial: true, skippedSlots: ["S2"], generatedAt: "test")
    }

    private func ports() -> [LiveHostPort] {
        [
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 3, rid: 2),
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 2, rid: 1),
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 1, rid: 0),
        ]
    }

    private func makeDevice(helperAvailable: Bool = true) -> DeviceControlModel {
        let custom = [
            PortCalibrationEntry(physicalPort: "right1", location: "02100000", label: "右侧",
                                 rid: "2", side: "右侧", controller: "AppleHPMDevice", portNumber: 3),
            PortCalibrationEntry(physicalPort: "left2", location: "01100000", label: "左侧下方",
                                 rid: "1", side: "左侧", controller: "AppleHPMDevice", portNumber: 2),
            PortCalibrationEntry(physicalPort: "left1", location: "01200000", label: "左侧上方",
                                 rid: "0", side: "左侧", controller: "AppleHPMDevice", portNumber: 1),
        ]
        let doc = CalibrationDocument(models: [], ports: custom, selectedPort: "AppleHPMDevice:2")
        let store = CalibrationStore(testingDocument: doc, hostModel: "MacBookPro18,2", builtInLayout: layout())
        let history = FileManager.default.temporaryDirectory.appendingPathComponent("t532-hist-\(UUID().uuidString).json")
        return DeviceControlModel(calibration: store, livePorts: ports(), helperAvailable: helperAvailable,
                                  persistPortSelection: false, startLiveWork: false, historyURL: history)
    }

    func testPortSwitchFeedbackUsesPhysicalLabelsAndDoesNotSend() {
        let device = makeDevice()
        let upper = device.orderedDisplayPorts[0]
        let lower = device.orderedDisplayPorts[1]
        let right = device.orderedDisplayPorts[2]
        XCTAssertEqual(device.label(for: upper), "左侧上方")
        XCTAssertEqual(device.label(for: lower), "左侧下方")
        XCTAssertEqual(device.label(for: right), "右侧")

        device.selectPort(upper)
        XCTAssertEqual(device.feedback.title, "操作目标已切换：左侧上方")
        device.selectPort(lower)
        XCTAssertEqual(device.feedback.title, "操作目标已切换：左侧下方")
        device.selectPort(right)
        XCTAssertEqual(device.feedback.title, "操作目标已切换：右侧")
        XCTAssertTrue(device.canControl)
        XCTAssertFalse(device.actionInFlight)
        XCTAssertTrue(device.lastActionLog.isEmpty)
    }

    func testLeftPortDetailsRestoreHostFieldsWithoutTargetModel() {
        let device = makeDevice()
        let right = device.orderedDisplayPorts[2]
        device.selectPort(right)
        let detail = device.selectedHostPortDetail
        XCTAssertTrue(detail.hasSelection)
        XCTAssertEqual(detail.controllerText, "AppleHPMDevice")
        XCTAssertEqual(detail.portNumberText, "3")
        XCTAssertEqual(detail.ridText, "2")
        XCTAssertTrue(detail.slotText.contains("右侧"))
        XCTAssertFalse(detail.builtInCalibrationText.isEmpty)
        XCTAssertTrue(detail.adoptedCalibrationText.contains("实际采用"))
        XCTAssertEqual(detail.hostModelText, "MacBookPro18,2")
        XCTAssertFalse(detail.hostModelText.contains("DFU"))
    }

    func testRecognizedDFUWithUnknownModelIsNotShownAsNoDevice() {
        let device = makeDevice()
        let lower = device.orderedDisplayPorts[1]
        let right = device.orderedDisplayPorts[2]
        device.selectPort(lower)
        let dfu = ObservedDevice(id: "ecid:AA", ecid: "0011223344556677", mode: .dfu,
                                 locationID: "01100000", product: "Apple Mobile Device (DFU Mode)",
                                 serial: "ECID:0011223344556677")
        device.applyObservedDevices([dfu], now: Date())
        XCTAssertEqual(device.compactRowStatus(for: lower), "DFU · 机型未识别")
        XCTAssertEqual(device.compactRowTitle(for: lower), "左侧下方 · DFU · 机型未识别")
        XCTAssertEqual(device.deviceStatusText(for: lower), "当前：DFU · 机型未识别")
        XCTAssertEqual(device.selectedPortDetail.currentHeadline, "DFU · 机型未识别")
        XCTAssertFalse(device.selectedPortDetail.currentHeadline.contains("无设备"))
        XCTAssertFalse(device.compactRowStatus(for: lower).contains("无设备"))
        XCTAssertEqual(device.selectedPortDetail.ecid, "0011223344556677")
        XCTAssertNil(device.selectedPortDetail.serial, "USB ECID text must not be shown as 序列号 or a model")
        let rightNames = device.selectedPortDetail.technicalRows.map(\.name)
        XCTAssertFalse(rightNames.contains("控制器"))
        XCTAssertFalse(rightNames.contains("PortNumber"))
        XCTAssertFalse(rightNames.contains("RID"))

        device.selectPort(right)
        XCTAssertEqual(device.feedback.title, "操作目标已切换：右侧")
        XCTAssertEqual(device.selectedPortDetail.currentHeadline, "当前未识别到设备")
        XCTAssertNil(device.selectedPortDetail.ecid)
        XCTAssertNil(device.selectedPortDetail.serial)
        XCTAssertFalse(device.selectedPortDetail.hasCurrentDevice)
        XCTAssertTrue(device.selectedPortDetail.title.contains("右侧"))
        XCTAssertEqual(device.compactRowStatus(for: right), "未识别设备")
        XCTAssertTrue(device.canControl)
    }

    func testHeadlineNeverUsesUSBProductAsModel() {
        let headline = DeviceDisplayIdentity.currentHeadline(
            mode: .dfu, identifiedModel: "Apple Mobile Device (DFU Mode)")
        XCTAssertEqual(headline, "DFU · 机型未识别")
        XCTAssertEqual(DeviceDisplayIdentity.currentHeadline(mode: .dfu, identifiedModel: nil),
                       "DFU · 机型未识别")
        XCTAssertEqual(DeviceDisplayIdentity.currentHeadline(mode: nil, identifiedModel: nil),
                       "当前未识别到设备")
    }

    func testHelperUninstallIsPrimaryWhenCurrentHealthyAndHiddenWithInstall() {
        XCTAssertEqual(HelperManagementPresentation.primaryActions(from: [.redetect, .uninstall]), [.uninstall])
        XCTAssertEqual(HelperManagementPresentation.secondaryActions(from: [.redetect, .uninstall]), [])
        XCTAssertEqual(HelperManagementPresentation.primaryActions(from: [.install, .redetect]), [.install])
        XCTAssertEqual(HelperManagementPresentation.secondaryActions(from: [.install, .uninstall, .redetect]), [])

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("t532-he-\(UUID().uuidString)")
        let destinations = HelperDestinations(
            helper: root.appendingPathComponent("helper"),
            backend: root.appendingPathComponent("backend"),
            plist: root.appendingPathComponent("plist"),
            socket: root.appendingPathComponent("sock"),
            logDirectory: root.appendingPathComponent("logs", isDirectory: true),
            packageDirectory: root)
        let io = MockHelperEnvironmentIO()
        io.files[destinations.helper.path] = (
            KnownHelperManifest.expectedCurrentHelperSHA256, "6NFD357KL3", "签名有效")
        io.files[destinations.backend.path] = (
            KnownHelperManifest.expectedCurrentBackendSHA256, "6NFD357KL3", "签名有效")
        io.files[destinations.plist.path] = (
            KnownHelperManifest.expectedCurrentPlistSHA256, nil, "N/A")
        io.launchctl = "pid = 1\nstate = running"
        io.socketIsListening = true
        let model = HelperEnvironmentModel(
            destinations: destinations,
            io: io,
            executor: MockHelperCommandExecutor(),
            requireExecutor: true)
        model.redetect()
        XCTAssertEqual(model.snapshot.kind, .currentHealthy)
        XCTAssertTrue(model.snapshot.allowedActions.contains(.uninstall))
        XCTAssertFalse(model.snapshot.allowedActions.contains(.install))
        XCTAssertEqual(HelperManagementPresentation.primaryActions(from: model.snapshot.allowedActions), [.uninstall])
        XCTAssertEqual(HelperManagementPresentation.secondaryActions(from: model.snapshot.allowedActions), [])
    }

    func testSettingsTabsKeepFullTitlesAndEndWithAbout() {
        let titles = SettingsTab.allCases.map(\.title)
        XCTAssertEqual(titles, [
            "模型校准",
            "端口校准",
            "校准与位置图",
            "日志预览过滤",
            "语言",
            "Helper / 运行环境",
            "Apple Configurator",
            "关于软件",
        ])
        XCTAssertEqual(AboutSoftwareInfo.authorName, "刘海峰")
        XCTAssertEqual(AboutSoftwareInfo.email, "liuhaifeng2001522@gmail.com")
        XCTAssertFalse(AboutSoftwareInfo.email.contains("…"))
    }

    func testExportedEvidenceDoesNotContainPersonalContact() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("t532-zip-\(UUID().uuidString)", isDirectory: true)
        let out = base.appendingPathComponent("out", isDirectory: true)
        let sessions = base.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let capture = CaptureModel(root: sessions, backendMode: .simulated)
        capture.start()
        let startDeadline = Date().addingTimeInterval(8)
        while Date() < startDeadline && capture.state != .recording {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        capture.stop()
        let stopDeadline = Date().addingTimeInterval(8)
        while Date() < stopDeadline && !capture.canSave {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        capture.save(folder: out, baseName: "T532-Contact-Check")
        let saveDeadline = Date().addingTimeInterval(8)
        while Date() < saveDeadline && capture.savedZipURL == nil && !capture.saveMessage.contains("失败") {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let zip = try XCTUnwrap(capture.savedZipURL)
        var stats = ZipIOStats()
        let entries = try ZipStoreReader.listEntries(archive: zip, stats: &stats, hashContents: true)
        let forbidden = ["liuhaifeng2001522@gmail.com", "刘海峰", "微信.JPG", "关于软件"]
        for entry in entries {
            let name = entry.pathInZip
            for token in forbidden {
                XCTAssertFalse(name.contains(token), "evidence path leaked personal token \(token): \(name)")
            }
            if let data = try? unzipBytes(zip, name),
               let text = String(data: data, encoding: .utf8) {
                for token in forbidden {
                    XCTAssertFalse(text.contains(token), "evidence file \(name) leaked \(token)")
                }
            }
        }
    }

    func testHostCalibrationSummaryIsExactHitAndDoesNotFollowSelection() {
        let device = makeDevice()
        let expected = "主机 MacBookPro18,2 · 机型已精确校准"
        XCTAssertEqual(device.hostModelCalibrationKind, .exactVerifiedRecord)
        XCTAssertEqual(device.hostCalibrationSummaryText, expected)
        XCTAssertFalse(device.shouldOfferGoCalibrate)
        XCTAssertFalse(device.hostCalibrationSummaryText.contains("去校准"))
        XCTAssertFalse(device.hostCalibrationSummaryText.contains("三口已精确校准"))
        XCTAssertFalse(device.hostCalibrationSummaryText.contains("部分端口未确认"))
        XCTAssertEqual(device.goCalibrateSettingsTab, .model)
        XCTAssertFalse(DeviceControlModel.goCalibrateRequiresConfirmation)

        let canControlBefore = device.canControl
        XCTAssertEqual(canControlBefore, device.helperAvailable && device.portUsable && !device.actionInFlight)

        let upper = device.orderedDisplayPorts[0]
        let lower = device.orderedDisplayPorts[1]
        let right = device.orderedDisplayPorts[2]
        device.selectPort(upper)
        XCTAssertEqual(device.hostCalibrationSummaryText, expected)
        XCTAssertFalse(device.shouldOfferGoCalibrate)
        XCTAssertTrue(device.selectedHostPortDetail.slotText.contains("左侧上方"))
        XCTAssertEqual(device.feedback.title, "操作目标已切换：左侧上方")

        device.selectPort(lower)
        XCTAssertEqual(device.hostCalibrationSummaryText, expected)
        XCTAssertTrue(device.selectedHostPortDetail.slotText.contains("左侧下方"))

        device.selectPort(right)
        XCTAssertEqual(device.hostCalibrationSummaryText, expected)
        XCTAssertTrue(device.selectedHostPortDetail.slotText.contains("右侧"))
        XCTAssertEqual(device.canControl, canControlBefore)
        XCTAssertEqual(device.canControl, device.helperAvailable && device.portUsable && !device.actionInFlight)
    }

    func testHostCalibrationSummaryIgnoresTargetDevicePresence() {
        let device = makeDevice()
        let expected = "主机 MacBookPro18,2 · 机型已精确校准"
        let lower = device.orderedDisplayPorts[1]
        device.selectPort(lower)
        device.applyObservedDevices([
            ObservedDevice(id: "ecid:AA", ecid: "0011223344556677", mode: .dfu,
                           locationID: "01100000", product: "Apple Mobile Device (DFU Mode)",
                           serial: "ECID:0011223344556677")
        ], now: Date())
        XCTAssertEqual(device.hostCalibrationSummaryText, expected)
        XCTAssertFalse(device.shouldOfferGoCalibrate)
        device.applyObservedDevices([], now: Date())
        XCTAssertEqual(device.hostCalibrationSummaryText, expected)
        XCTAssertFalse(device.selectedPortDetail.hasCurrentDevice)
        XCTAssertTrue(device.canControl)
    }

    func testSameMoldReuseIsNotExactAndOffersGoCalibrate() {
        let shared = [SharedCandidate(models: ["Mac16,10", "Mac18,5"],
                                      basis: "BOTH REPORTS: same port/RID pattern; not auto-expanded without explicit alias")]
        let doc = CalibrationDocument(models: [], ports: [], selectedPort: "")
        let store = CalibrationStore(testingDocument: doc, hostModel: "Mac16,10",
                                     builtInLayout: nil, sharedLayoutCandidates: shared)
        let history = FileManager.default.temporaryDirectory.appendingPathComponent("t532-hist-\(UUID().uuidString).json")
        let device = DeviceControlModel(
            calibration: store, livePorts: [], helperAvailable: true,
            persistPortSelection: false, startLiveWork: false, historyURL: history)
        XCTAssertEqual(device.hostModelCalibrationKind, .sameMoldLayoutReuse)
        XCTAssertEqual(device.hostCalibrationSummaryText, "主机 Mac16,10 · 未精确校准（沿用同模具布局）")
        XCTAssertTrue(device.shouldOfferGoCalibrate)
        XCTAssertEqual(device.goCalibrateSettingsTab, .model)
        XCTAssertFalse(DeviceControlModel.goCalibrateRequiresConfirmation)
        XCTAssertFalse(device.hostCalibrationSummaryText.contains("机型已精确校准"))
        // Selection, if any, must not change the host-model line.
        device.selectedLiveKey = ""
        XCTAssertEqual(device.hostCalibrationSummaryText, "主机 Mac16,10 · 未精确校准（沿用同模具布局）")
        XCTAssertEqual(device.canControl, device.helperAvailable && device.portUsable && !device.actionInFlight)
    }

    func testExactHitWinsOverSameMoldCandidate() {
        let shared = [SharedCandidate(models: ["MacBookPro18,2", "MacBookPro18,3"],
                                      basis: "same 3-port pattern but different chassis; not auto-expanded")]
        let custom = [
            PortCalibrationEntry(physicalPort: "left1", location: "01200000", label: "左侧上方",
                                 rid: "0", side: "左侧", controller: "AppleHPMDevice", portNumber: 1),
        ]
        let doc = CalibrationDocument(models: [], ports: custom, selectedPort: "")
        let store = CalibrationStore(testingDocument: doc, hostModel: "MacBookPro18,2",
                                     builtInLayout: layout(), sharedLayoutCandidates: shared)
        let history = FileManager.default.temporaryDirectory.appendingPathComponent("t532-hist-\(UUID().uuidString).json")
        let device = DeviceControlModel(
            calibration: store,
            livePorts: [LiveHostPort(controller: "AppleHPMDevice", portNumber: 1, rid: 0)],
            helperAvailable: true, persistPortSelection: false, startLiveWork: false, historyURL: history)
        XCTAssertEqual(device.hostModelCalibrationKind, .exactVerifiedRecord)
        XCTAssertEqual(device.hostCalibrationSummaryText, "主机 MacBookPro18,2 · 机型已精确校准")
        XCTAssertFalse(device.shouldOfferGoCalibrate)
    }

    func testUnidentifiedHostModelIsUncalibratedAndOffersGoCalibrate() {
        let doc = CalibrationDocument(models: [], ports: [], selectedPort: "")
        let store = CalibrationStore(testingDocument: doc, hostModel: "unknown", builtInLayout: nil)
        let history = FileManager.default.temporaryDirectory.appendingPathComponent("t532-hist-\(UUID().uuidString).json")
        let device = DeviceControlModel(
            calibration: store, livePorts: [], helperAvailable: false,
            persistPortSelection: false, startLiveWork: false, historyURL: history)
        XCTAssertEqual(device.hostModelCalibrationKind, .unidentified)
        XCTAssertEqual(device.hostCalibrationSummaryText, "主机机型未识别 · 未校准")
        XCTAssertTrue(device.shouldOfferGoCalibrate)
        XCTAssertEqual(device.goCalibrateSettingsTab, .model)
        XCTAssertFalse(device.canControl)
        XCTAssertFalse(device.hostCalibrationSummaryText.contains("MacBookPro"))
    }

    func testKnownHostWithoutVerifiedOrSameMoldIsUncalibrated() {
        let doc = CalibrationDocument(models: [], ports: [], selectedPort: "")
        let store = CalibrationStore(testingDocument: doc, hostModel: "Mac14,2", builtInLayout: nil)
        let history = FileManager.default.temporaryDirectory.appendingPathComponent("t532-hist-\(UUID().uuidString).json")
        let device = DeviceControlModel(
            calibration: store,
            livePorts: [LiveHostPort(controller: "AppleHPMDevice", portNumber: 1, rid: 0)],
            helperAvailable: true, persistPortSelection: false, startLiveWork: false, historyURL: history)
        XCTAssertEqual(device.hostModelCalibrationKind, .uncalibrated)
        XCTAssertEqual(device.hostCalibrationSummaryText, "主机 Mac14,2 · 未校准")
        XCTAssertTrue(device.shouldOfferGoCalibrate)
        XCTAssertEqual(device.goCalibrateSettingsTab, .model)
        XCTAssertFalse(DeviceControlModel.goCalibrateRequiresConfirmation)
        device.selectedLiveKey = ""
        XCTAssertEqual(device.hostCalibrationSummaryText, "主机 Mac14,2 · 未校准")
    }

        private func unzipBytes(_ zip: URL, _ path: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", zip.path, path]
        let out = Pipe(); process.standardOutput = out; process.standardError = Pipe()
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "unzip \(path)")
        return out.fileHandleForReading.readDataToEndOfFile()
    }
}

import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class T523UIWiringTests: XCTestCase {
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
        let history = FileManager.default.temporaryDirectory.appendingPathComponent("t523-hist-\(UUID().uuidString).json")
        return DeviceControlModel(calibration: store, livePorts: ports(), helperAvailable: helperAvailable,
                                  persistPortSelection: false, startLiveWork: false, historyURL: history)
    }

    func testHintUsesSelectedPortAndRowOmitsLastHistory() {
        let device = makeDevice()
        let lower = device.orderedDisplayPorts[1]
        device.selectPort(lower)
        XCTAssertEqual(device.selectionHintText, "已选左侧下方，可进入 DFU 或重启")
        XCTAssertEqual(device.compactRowTitle(for: lower), "左侧下方 · 未识别设备")
        XCTAssertFalse(device.compactRowStatus(for: lower).contains("上次"))
        XCTAssertTrue(device.canControl)
    }

    func testDetailFollowsSelectionAndDoesNotKeepPreviousIdentity() {
        let device = makeDevice()
        let lower = device.orderedDisplayPorts[1]
        let right = device.orderedDisplayPorts[2]
        device.selectPort(lower)
        let dfu = ObservedDevice(id: "ecid:AA", ecid: "0012682E0CFB401E", mode: .dfu,
                                 locationID: "01100000", product: "Apple Mobile Device (DFU Mode)",
                                 serial: "ECID:0012682E0CFB401E")
        device.applyObservedDevices([dfu], now: Date())
        XCTAssertEqual(device.selectedPortDetail.currentHeadline, "DFU · 机型未识别")
        XCTAssertEqual(device.selectedPortDetail.ecid, "0012682E0CFB401E")
        XCTAssertNil(device.selectedPortDetail.serial, "USB ECID text must not be shown as 序列号")
        XCTAssertTrue(device.selectedPortDetail.title.contains("左侧下方"))
        XCTAssertTrue(device.selectedPortDetail.title.contains("设备详情"))

        device.selectPort(right)
        XCTAssertEqual(device.selectedPortDetail.currentHeadline, "当前未识别到设备")
        XCTAssertNil(device.selectedPortDetail.ecid)
        XCTAssertNil(device.selectedPortDetail.serial)
        XCTAssertTrue(device.selectedPortDetail.title.contains("右侧"))
        XCTAssertFalse(device.selectedPortDetail.hasCurrentDevice)
        // Selecting a port is not a send blocker.
        XCTAssertTrue(device.canControl)
    }

    func testSelectingPortDoesNotStartOrStopCapture() async throws {
        let device = makeDevice()
        let sessions = FileManager.default.temporaryDirectory.appendingPathComponent("t523-cap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let capture = CaptureModel(root: sessions, backendMode: .simulated)
        capture.start()
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline, capture.state != .recording {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(capture.state, .recording)
        let right = device.orderedDisplayPorts[2]
        device.selectPort(right)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(capture.state, .recording)
        XCTAssertFalse(capture.captureMeterText.contains("采集中"))
        XCTAssertTrue(capture.stateText.contains("采集中（离线模拟）"))
        capture.stop()
        device.selectPort(device.orderedDisplayPorts[0])
        XCTAssertTrue(device.canControl)
    }

    func testApplyObservedDevicesUpdatesDetailImmediatelyAndDoesNotQueryFromDetail() {
        let device = makeDevice()
        device.observationReadHandler = {
            XCTFail("detail/selection must not start a device query")
            return .success([])
        }
        let before = device.deviceQueryCount
        let lower = device.orderedDisplayPorts[1]
        device.selectPort(lower)
        let received = Date()
        device.applyObservedDevices([
            ObservedDevice(id: "ecid:AA", ecid: "AA", mode: .dfu, locationID: "01100000",
                           product: "Apple Mobile Device (DFU Mode)", serial: "ECID:AA"),
        ], now: received)
        let latency = Date().timeIntervalSince(received)
        XCTAssertLessThan(latency, 0.5)
        XCTAssertEqual(device.compactRowStatus(for: lower), "DFU · 机型未识别")
        XCTAssertEqual(device.selectedPortDetail.currentHeadline, "DFU · 机型未识别")
        XCTAssertEqual(device.deviceQueryCount, before)
        _ = device.selectedPortDetail
        _ = device.copySummaryText()
        XCTAssertEqual(device.deviceQueryCount, before)
    }

    func testIdleObservationDoesNotAddQueriesForDetailAccess() async {
        let device = makeDevice()
        var reads = 0
        device.observationReadHandler = {
            reads += 1
            return .success([])
        }
        device.startObservationForTests(intervalNanoseconds: 50_000_000)
        try? await Task.sleep(nanoseconds: 120_000_000)
        let mid = reads
        XCTAssertGreaterThanOrEqual(mid, 1)
        for _ in 0..<20 { _ = device.selectedPortDetail }
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(reads, mid, "Accessing the detail pane must not add device queries")
        device.stopObservationForTests()
    }
}

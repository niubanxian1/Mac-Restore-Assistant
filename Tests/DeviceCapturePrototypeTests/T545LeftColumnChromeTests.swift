import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class T545LeftColumnChromeTests: XCTestCase {
    private func layout() -> BuiltInLayout {
        BuiltInLayout(displayName: "M1 Pro MacBook Pro A2485 16英寸", sourceFile: "t.json", slots: [
            BuiltInSlot(slot: "S3", face: "LEFT", portNumber: 1, rid: 0, binding: "MacBookPro18,2|AppleHPMDevice|1|0", physicalName: "左侧上方"),
            BuiltInSlot(slot: "S4", face: "LEFT", portNumber: 2, rid: 1, binding: "MacBookPro18,2|AppleHPMDevice|2|1", physicalName: "左侧下方"),
            BuiltInSlot(slot: "S5", face: "RIGHT", portNumber: 3, rid: 2, binding: "MacBookPro18,2|AppleHPMDevice|3|2", physicalName: "右侧"),
        ], partial: true, skippedSlots: ["S2"], generatedAt: "test")
    }

    private func makeDevice() -> DeviceControlModel {
        let custom = [
            PortCalibrationEntry(physicalPort: "left2", location: "01100000", label: "左侧下方",
                                 rid: "1", side: "左侧", controller: "AppleHPMDevice", portNumber: 2),
        ]
        let doc = CalibrationDocument(models: [], ports: custom, selectedPort: "")
        let store = CalibrationStore(testingDocument: doc, hostModel: "MacBookPro18,2", builtInLayout: layout())
        let history = FileManager.default.temporaryDirectory.appendingPathComponent("t545-hist-\(UUID().uuidString).json")
        let ports = [
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 1, rid: 0),
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 2, rid: 1),
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 3, rid: 2),
        ]
        return DeviceControlModel(calibration: store, livePorts: ports, helperAvailable: true,
                                  persistPortSelection: false, startLiveWork: false, historyURL: history)
    }

    func testPersistentOperationTargetAndSwitchFeedback() {
        let device = makeDevice()
        XCTAssertEqual(device.feedback.title, "等待操作")
        XCTAssertEqual(device.feedback.detail, "选择物理端口后可执行设备控制。")

        let lower = device.orderedDisplayPorts[1]
        device.selectPort(lower)
        XCTAssertEqual(device.operationTargetText, "操作目标：左侧下方")
        XCTAssertEqual(device.feedback.title, "操作目标已切换：左侧下方")
        XCTAssertEqual(device.feedback.detail, "采集会话不会被清空；执行时使用当前端口/控制器/RID。")
        XCTAssertFalse(device.actionInFlight)
        XCTAssertTrue(device.lastActionLog.isEmpty)

        let right = device.orderedDisplayPorts[2]
        device.selectPort(right)
        XCTAssertEqual(device.operationTargetText, "操作目标：右侧")
        XCTAssertEqual(device.feedback.title, "操作目标已切换：右侧")
        XCTAssertEqual(device.operationTargetText, "操作目标：右侧")
    }

    func testDisclosureFieldsMatchOwnerCompactChromeWithoutTargetModel() {
        let device = makeDevice()
        let lower = device.orderedDisplayPorts[1]
        device.selectPort(lower)
        XCTAssertEqual(device.operationTargetText, "操作目标：左侧下方")
        let port = try! XCTUnwrap(device.selectedLivePort)
        let controllerLine = "控制器 \(port.controller) · PortNumber \(port.portNumber) · RID \(port.rid)"
        XCTAssertEqual(controllerLine, "控制器 AppleHPMDevice · PortNumber 2 · RID 1")
        XCTAssertTrue(device.builtInSlotSummary.contains("左侧下方"))
        XCTAssertTrue(device.builtInSlotSummary.contains("S4") || device.builtInSlotSummary.contains("left2"))
        XCTAssertTrue(device.selectedSourceText.hasPrefix("实际采用："))
        XCTAssertTrue(device.selectedModelSummary.hasPrefix("主机 MacBookPro18,2"))
        XCTAssertTrue(device.selectedModelSummary.contains("内置"))
        XCTAssertFalse(device.selectedModelSummary.contains("DFU"))
        XCTAssertFalse(device.selectedModelSummary.contains("Apple Mobile Device"))
    }
}

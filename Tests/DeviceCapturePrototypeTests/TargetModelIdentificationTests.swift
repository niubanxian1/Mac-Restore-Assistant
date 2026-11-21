import XCTest
@testable import DeviceCapturePrototype

/// Offline regression for the two target-identification records:
/// 1. a generic Mac USB node (product name "Mac"), and
/// 2. a DFU node that keeps mode + ECID and may carry model evidence.
@MainActor
final class TargetModelIdentificationTests: XCTestCase {
    func testSupplementalExactAndT2Candidates() {
        XCTAssertNotNil(TargetModelCatalog.supplementalNames["MacBookPro6,2"])
        XCTAssertEqual(TargetModelCatalog.identifier(from: "iBridge2,3"), "iBridge2,3")
        XCTAssertTrue(TargetModelCatalog.displayName(for: "iBridge2,3").contains("候选"))
        XCTAssertEqual(TargetModelCatalog.displayName(for: "iBridge2,15"), "iBridge2,15")
    }

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

    private func makeDevice() -> DeviceControlModel {
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
        let history = FileManager.default.temporaryDirectory
            .appendingPathComponent("target-model-hist-\(UUID().uuidString).json")
        return DeviceControlModel(calibration: store, livePorts: ports(), helperAvailable: true,
                                  persistPortSelection: false, startLiveWork: false,
                                  historyURL: history)
    }

    private func genericMac(location: String = "01100000") -> ObservedDevice {
        ObservedDevice(id: "usb:\(location):connected",
                       ecid: nil,
                       mode: .connected,
                       locationID: location,
                       product: "Mac",
                       serial: "SYNTHSERIAL0001")
    }

    func testGenericMacAttributedToSelectedPortIsConnectedNotDFU() {
        let device = makeDevice()
        let lower = device.orderedDisplayPorts[1]
        device.selectPort(lower)
        device.applyObservedDevices([genericMac()], now: Date())

        XCTAssertEqual(device.compactRowStatus(for: lower), "Mac 已连接 · 型号待确认")
        XCTAssertEqual(device.compactRowTitle(for: lower), "左侧下方 · Mac 已连接 · 型号待确认")
        XCTAssertEqual(device.deviceStatusText(for: lower), "当前：Mac 已连接 · 型号待确认")
        XCTAssertEqual(device.selectedPortDetail.currentHeadline, "Mac 已连接 · 型号待确认")
        XCTAssertFalse(device.selectedPortDetail.currentHeadline.contains("DFU"))
        XCTAssertNil(device.selectedPortDetail.ecid)
        XCTAssertEqual(device.selectedPortDetail.serial, "SYNTHSERIAL0001")
    }

    func testGenericMacDoesNotBorrowTheHostCalibrationModel() {
        let device = makeDevice()
        let lower = device.orderedDisplayPorts[1]
        device.selectPort(lower)
        device.applyObservedDevices([genericMac()], now: Date())

        // The fixture host model is MacBookPro18,2; the target must stay unknown.
        XCTAssertEqual(device.calibration.hostModel, "MacBookPro18,2")
        XCTAssertFalse(device.selectedPortDetail.currentHeadline.contains("MacBookPro18,2"))
        XCTAssertFalse(device.selectedPortDetail.currentHeadline.contains("MacBook Pro"))
    }

    func testUnattributedGenericMacIsNotShownOnTheSelectedPort() {
        let device = makeDevice()
        let lower = device.orderedDisplayPorts[1]
        device.selectPort(lower)
        // 09900000 is not a calibrated location: no trusted port attribution.
        device.applyObservedDevices([genericMac(location: "09900000")], now: Date())

        XCTAssertEqual(device.selectedPortDetail.currentHeadline, "当前未检测到目标设备")
        XCTAssertNil(device.selectedPortDetail.ecid)
        XCTAssertNil(device.selectedPortDetail.serial)
    }

    func testDFUModelEvidenceDrivesCurrentTitleButSameECIDCacheIsHistoricalOnly() {
        let device = makeDevice()
        let lower = device.orderedDisplayPorts[1]
        device.selectPort(lower)

        var evidenced = ObservedDevice(
            id: "ecid:00C0FFEE00000001",
            ecid: "00C0FFEE00000001",
            mode: .dfu,
            locationID: "01100000",
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:00C0FFEE00000001")
        evidenced.explicitMachineIdentifierRaw = "MacBookPro18,2"
        device.applyObservedDevices([evidenced], now: Date())
        XCTAssertEqual(device.selectedPortDetail.currentHeadline,
                       "MacBook Pro（16 英寸，2021 年） · DFU")
        XCTAssertEqual(device.selectedPortDetail.ecid, "00C0FFEE00000001")

        // Same ECID without current identity fields: the cache is a right-hand
        // historical hint and must not drive the current title.
        let withoutField = ObservedDevice(
            id: "ecid:00C0FFEE00000001",
            ecid: "00C0FFEE00000001",
            mode: .dfu,
            locationID: "01100000",
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:00C0FFEE00000001")
        device.applyObservedDevices([withoutField], now: Date())
        XCTAssertEqual(device.selectedPortDetail.currentHeadline,
                       "DFU · 当前无身份证据")
        XCTAssertEqual(device.selectedPortDetail.ecid, "00C0FFEE00000001")
        XCTAssertTrue(device.selectedPortDetail.technicalRows.contains {
            $0.group == "历史提示" && $0.value.contains("MacBookPro18,2")
        })
    }

    func testDFUWithoutEvidenceStaysUnknownModel() {
        let device = makeDevice()
        let lower = device.orderedDisplayPorts[1]
        device.selectPort(lower)
        let dfu = ObservedDevice(
            id: "ecid:00C0FFEE00000001",
            ecid: "00C0FFEE00000001",
            mode: .dfu,
            locationID: "01100000",
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:00C0FFEE00000001")
        device.applyObservedDevices([dfu], now: Date())
        XCTAssertEqual(device.selectedPortDetail.currentHeadline, "Mac DFU · 型号待确认")
        XCTAssertEqual(device.selectedPortDetail.ecid, "00C0FFEE00000001")
    }

    func testDesktopMacFamiliesHaveFriendlyNames() {
        XCTAssertEqual(TargetModelCatalog.displayName(for: "Mac16,10"), "Mac mini（M4，2024 年）")
        XCTAssertEqual(TargetModelCatalog.displayName(for: "Mac16,11"), "Mac mini（M4 Pro，2024 年）")
        XCTAssertEqual(TargetModelCatalog.displayName(for: "Mac15,14"), "Mac Studio（M3 Ultra，2025 年）")
        XCTAssertEqual(TargetModelCatalog.displayName(for: "Mac16,9"), "Mac Studio（M4 Max，2025 年）")
        XCTAssertEqual(TargetModelCatalog.displayName(for: "Mac14,8"), "Mac Pro（M2 Ultra，2023 年）")
        XCTAssertEqual(TargetModelCatalog.displayName(for: "Mac16,2"), "iMac（24 英寸，M4，2024 年，双接口）")
        XCTAssertEqual(TargetModelCatalog.displayName(for: "Mac16,3"), "iMac（24 英寸，M4，2024 年，四接口）")
    }

    func testDesktopMacFamiliesAcceptTheirIdentifiers() {
        for identifier in [
            "Macmini8,1", "Macmini9,1", "Mac14,3", "Mac14,12",
            "Mac13,1", "Mac13,2", "Mac14,13", "Mac14,14", "Mac15,14", "Mac16,9",
            "MacPro7,1", "Mac14,8",
            "iMacPro1,1", "iMac20,1", "iMac20,2", "iMac21,1", "iMac21,2",
            "Mac15,4", "Mac15,5", "Mac16,2", "Mac16,3",
        ] {
            XCTAssertEqual(TargetModelCatalog.identifier(from: identifier), identifier)
        }
    }
}

import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class PortDisplayObservationTests: XCTestCase {
    private func layout() -> BuiltInLayout {
        BuiltInLayout(displayName: "M1 Pro", sourceFile: "t.json", slots: [
            BuiltInSlot(slot: "S3", face: "LEFT", portNumber: 1, rid: 0, binding: "MacBookPro18,2|AppleHPMDevice|1|0", physicalName: "左侧上方"),
            BuiltInSlot(slot: "S4", face: "LEFT", portNumber: 2, rid: 1, binding: "MacBookPro18,2|AppleHPMDevice|2|1", physicalName: "左侧下方"),
            BuiltInSlot(slot: "S5", face: "RIGHT", portNumber: 3, rid: 2, binding: "MacBookPro18,2|AppleHPMDevice|3|2", physicalName: "右侧"),
        ], partial: true, skippedSlots: ["S2"], generatedAt: "test")
    }

    private func link(connected: Bool = true) -> HostPortLink {
        HostPortLink(
            connectionActive: connected,
            connectionCount: connected ? 4 : 0,
            connectType: connected ? 4 : 0,
            connectTypePublished: connected ? 4 : 0,
            superSpeedActive: false,
            activeCable: false,
            opticalCable: false,
            powerMode: 3,
            transportsProvisioned: connected ? ["CC", "USB2"] : [],
            transportsSupported: ["CC", "USB2", "USB3", "CIO", "DisplayPort"])
    }

    private func ports() -> [LiveHostPort] {
        [
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 3, rid: 2, link: link(connected: false)),
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 2, rid: 1, link: link()),
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 1, rid: 0, link: link(connected: false)),
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
            .appendingPathComponent("port-display-hist-\(UUID().uuidString).json")
        return DeviceControlModel(calibration: store, livePorts: ports(), helperAvailable: true,
                                  persistPortSelection: false, startLiveWork: false,
                                  historyURL: history)
    }

    private func row(_ detail: SelectedPortDetail, _ name: String) -> String? {
        detail.technicalRows.first { $0.name == name }?.value
    }

    func testControllerConnectionWithoutTargetIdentityIsNotNoDevice() {
        let device = makeDevice()
        let lower = device.orderedDisplayPorts[1]
        device.selectPort(lower)

        XCTAssertEqual(device.compactRowStatus(for: lower), "已连接")
        XCTAssertEqual(device.compactRowTitle(for: lower), "左侧下方 · 已连接")
        XCTAssertEqual(device.selectedPortDetail.currentHeadline, "设备身份暂未读取")
        XCTAssertTrue(device.selectedPortDetail.hasCurrentDevice)
        XCTAssertNil(device.selectedPortDetail.ecid)
        XCTAssertNil(device.selectedPortDetail.serial)
        XCTAssertFalse(device.selectedPortDetail.currentHeadline.contains("DFU"))
        XCTAssertFalse(device.selectedPortDetail.currentHeadline.contains("无设备"))
        XCTAssertFalse(device.selectedPortDetail.currentHeadline.contains("MacBook"))
    }

    func testTechnicalDetailsShowOnlyReadLinkFactsAndSeparateCapabilityFromRate() {
        let device = makeDevice()
        let lower = device.orderedDisplayPorts[1]
        device.selectPort(lower)
        let detail = device.selectedPortDetail

        XCTAssertEqual(row(detail, "当前协议"), "CC、USB2（已配置传输，观察）")
        XCTAssertEqual(row(detail, "线材标识"), "Active Cable：否；Optical Cable：否")
        XCTAssertEqual(row(detail, "线材/端口能力"),
                       "CC、USB2、USB3、CIO、DisplayPort（能力，不代表当前速率）")
        XCTAssertEqual(row(detail, "控制器连接状态"), "已连接")
        XCTAssertEqual(row(detail, "连接计数"), "4")
        XCTAssertNil(row(detail, "协商速率"), "no negotiated speed was read")
        XCTAssertNil(row(detail, "Hub 名称"), "no hub was read")
        // USB3/CIO capability nodes must not become a speed or Thunderbolt claim.
        XCTAssertFalse(detail.technicalRows.contains { $0.value.contains("Gb/s") })
        XCTAssertFalse(detail.technicalRows.contains { $0.value.localizedCaseInsensitiveContains("Thunderbolt") })
        XCTAssertFalse(detail.technicalRows.contains { $0.value.contains("雷电") })
    }

    func testReadDeviceAddsHubSpeedAndPathWithoutChangingTheConnectedTitle() {
        let device = makeDevice()
        let lower = device.orderedDisplayPorts[1]
        device.selectPort(lower)
        let mac = ObservedDevice(
            id: "usb:01100000:connected",
            ecid: nil,
            mode: .connected,
            locationID: "01100000",
            product: "Mac",
            serial: "F969W4L272",
            linkSpeedBps: 480_000_000,
            deviceSpeed: 2,
            usbSpeed: 3,
            usbPortType: 5,
            hubName: "USB2.0 Hub",
            topologyPath: "AppleT6000USBXHCI@01000000 → USB2.0 Hub → Mac")
        device.applyObservedDevices([mac], now: Date())
        let detail = device.selectedPortDetail

        XCTAssertEqual(detail.currentHeadline, "已连接 Mac · 具体机型未知")
        XCTAssertEqual(row(detail, "Hub 名称"), "USB2.0 Hub")
        XCTAssertEqual(row(detail, "协商速率"), "480 Mb/s")
        XCTAssertEqual(row(detail, "拓扑路径"), "AppleT6000USBXHCI@01000000 → USB2.0 Hub → Mac")
        XCTAssertEqual(row(detail, "当前协议"), "CC、USB2（已配置传输，观察）")
        XCTAssertEqual(row(detail, "线材/端口能力"),
                       "CC、USB2、USB3、CIO、DisplayPort（能力，不代表当前速率）")
    }

    func testLinkDisconnectClearsCurrentObservedDeviceBeforeNextUSBScan() {
        let device = makeDevice()
        let lower = device.orderedDisplayPorts[1]
        device.selectPort(lower)
        let mac = ObservedDevice(
            id: "usb:01100000:connected",
            ecid: nil,
            mode: .connected,
            locationID: "01100000",
            product: "Mac",
            serial: "F969W4L272")
        device.applyObservedDevices([mac], now: Date())
        XCTAssertEqual(device.compactRowStatus(for: lower), "已连接 Mac · 具体机型未知")

        let disconnected = [
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 3, rid: 2, link: link(connected: false)),
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 2, rid: 1, link: link(connected: false)),
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 1, rid: 0, link: link(connected: false)),
        ]
        device.applyDiscoveredPorts(disconnected, persistCalibration: false)

        let currentLower = device.orderedDisplayPorts[1]
        XCTAssertNil(device.observedDevice(for: currentLower))
        XCTAssertFalse(device.compactRowStatus(for: currentLower).contains("已连接 Mac"))
        XCTAssertFalse(device.selectedPortDetail.currentHeadline.contains("已连接 Mac"))
    }

    func testReadOnlyPortRefreshSkipsWhileActionInFlight() async {
        let device = makeDevice()
        let before = device.livePorts
        device.actionInFlight = true
        device.hostPortReadHandler = { .success([]) }

        await device.refreshPortsIfSafeForReadOnlyPolling()

        XCTAssertEqual(device.livePorts, before)
    }

    func testLiveFixtureLinksAttachToTheSamePortsAsTheTriplet() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ioreg-applehpm-owner-mac-m1max.txt")
        let text = try String(contentsOf: fixture, encoding: .utf8)
        let parsed = HostPortReader.parse(text)
        XCTAssertFalse(parsed.isEmpty)
        // Ports with a Port-USB-C node carry link facts. HostPortTextParser
        // also emits a legacy triplet from the fourth controller; the App
        // keeps that routing unchanged, so it has no link facts.
        let linked = parsed.filter { $0.rid != 5 }
        XCTAssertEqual(linked.count, 3)
        XCTAssertTrue(linked.allSatisfy { $0.link != nil })

        let port2 = parsed.first { $0.portNumber == 2 && $0.rid == 1 }
        XCTAssertTrue(port2?.link?.isConnected == true)
        XCTAssertEqual(port2?.link?.activeCable, true)
        XCTAssertEqual(port2?.link?.superSpeedActive, false)
        XCTAssertTrue(port2?.link?.transportsSupported.contains("USB3") == true)

        let port1 = parsed.first { $0.portNumber == 1 && $0.rid == 0 }
        XCTAssertEqual(port1?.link?.superSpeedActive, true)
        XCTAssertTrue(port1?.link?.transportsProvisioned.contains("USB3") == true)
    }
}

import XCTest
@testable import DeviceCapturePrototype

final class DeviceObserverTests: XCTestCase {
    func testThreeSampleDevicesParseModesAndIdentity() {
        let text = """
        +-o Apple Mobile Device (DFU Mode)@01100000
          | {
          |   "kUSBProductString" = "Apple Mobile Device (DFU Mode)"
          |   "USB Serial Number" = "SDOM:01 ECID:0011223344556677"
          |   "locationID" = 17825792
          | }
        +-o Apple Mobile Device (DFU Mode)@02100000
          | {
          |   "kUSBProductString" = "Apple Mobile Device (DFU Mode)"
          |   "USB Serial Number" = "SDOM:01 ECID:0011223344556677"
          |   "locationID" = 34603008
          | }
        +-o Apple Mobile Device (Recovery Mode)@03100000
          | {
          |   "kUSBProductString" = "Apple Mobile Device (Recovery Mode)"
          |   "USB Serial Number" = "SDOM:01 ECID:00AABBCCDDEEFF00"
          |   "locationID" = 51380224
          | }
        """
        let devices = ObservedDeviceReader.parse(text)
        XCTAssertEqual(devices.count, 3)
        XCTAssertEqual(devices.map(\.mode), [.dfu, .dfu, .recovery])
        XCTAssertEqual(devices[0].ecid, "0011223344556677")
        XCTAssertEqual(devices[1].locationID, "02100000")
        XCTAssertEqual(devices[2].displayIdentity, "Mac · Recovery · ECID 00AABBCCDDEEFF00")
    }

    func testGenericMacNodeIsConnectedNotDFUAndKeepsDescriptorEvidence() {
        // Captured shape from the M4 host: product name is exactly "Mac",
        // normal boot product id 6405, plain USB serial, location 01100000.
        let text = """
        +-o Mac@01100000  <class IOUSBHostDevice, id 0x10000695b>
          {
            "idProduct" = 6405
            "idVendor" = 1452
            "USB Product Name" = "Mac"
            "kUSBProductString" = "Mac"
            "locationID" = 17825792
            "kUSBSerialNumberString" = "F969W4L272"
            "USB Serial Number" = "F969W4L272"
          }
        """
        let devices = ObservedDeviceReader.parse(text)
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].mode, .connected)
        XCTAssertNil(devices[0].ecid)
        XCTAssertNil(devices[0].modelIdentifier)
        XCTAssertEqual(devices[0].locationID, "01100000")
        XCTAssertEqual(devices[0].product, "Mac")
        XCTAssertEqual(devices[0].serial, "F969W4L272")
        XCTAssertEqual(
            DeviceDisplayIdentity.currentHeadline(
                mode: devices[0].mode,
                identifiedModel: devices[0].modelIdentifier),
            "已连接 Mac · 具体机型未知")
    }

    func testDFUNodeKeepsModeAndECIDAndUsesOnlyExplicitModelEvidence() {
        let text = """
        +-o Apple Mobile Device (DFU Mode)@01100000  <class IOUSBHostDevice, id 0x100000001>
          {
            "idProduct" = 1281
            "idVendor" = 1452
            "USB Product Name" = "Apple Mobile Device (DFU Mode)"
            "deviceType" = "MacBookPro18,2"
            "USB Serial Number" = "CPID:6000 BDID:0E ECID:0011223344556677"
            "locationID" = 17825792
          }
        """
        let devices = ObservedDeviceReader.parse(text)
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].mode, .dfu)
        XCTAssertEqual(devices[0].ecid, "0011223344556677")
        XCTAssertEqual(devices[0].modelIdentifier, "MacBookPro18,2")
        XCTAssertEqual(
            DeviceDisplayIdentity.currentHeadline(
                mode: devices[0].mode,
                identifiedModel: devices[0].modelIdentifier),
            "MacBook Pro（16 英寸，2021 年） · DFU")
        XCTAssertEqual(
            DeviceDisplayIdentity.currentHeadline(
                mode: .dfu,
                identifiedModel: "Apple Mobile Device (DFU Mode)"),
            "DFU · 机型未识别")
    }

    func testCurrentDFUEnumerationIfPresent() throws {
        let devices = ObservedDeviceReader.read()
        guard let dfu = devices.first(where: { $0.mode == .dfu }) else {
            throw XCTSkip("当前没有 DFU 目标；仅做离线样本检查")
        }
        XCTAssertFalse(dfu.locationID.isEmpty)
        XCTAssertEqual(dfu.product, "Apple Mobile Device (DFU Mode)")
    }
}

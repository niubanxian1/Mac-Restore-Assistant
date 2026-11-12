import XCTest
@testable import DeviceCapturePrototype

final class TargetModelReadOnlyResolverTests: XCTestCase {
    private func device(ecid: String?, location: String, product: String = "Mac") -> ObservedDevice {
        ObservedDevice(id: "usb:\(location)", ecid: ecid, mode: .connected,
                       locationID: location, product: product, serial: "KWCXXY29HT")
    }

    func testCfgutilHintBindsMac1613ByECIDAndSource() {
        let text = "Type: Mac16,13\tECID: 0x61124360B801C\tUDID: N/A Location: 0x2100000 Name: N/A\n"
        let hints = TargetModelReadOnlyResolver.parse(text)
        XCTAssertEqual(hints, [.init(modelIdentifier: "Mac16,13", ecid: "00061124360B801C", locationID: "02100000")])
        let enriched = TargetModelReadOnlyResolver.enrich([
            device(ecid: "00061124360B801C", location: "02100000")
        ], hints: hints)
        XCTAssertEqual(enriched.first?.modelIdentifier, "Mac16,13")
        XCTAssertEqual(enriched.first?.modelSource, TargetModelReadOnlyResolver.source)
        XCTAssertEqual(TargetModelCatalog.displayName(for: "Mac16,13"), "MacBook Air（15 英寸，M4，2025 年）")
    }

    func testAnotherPortDoesNotInheritTheRightHandModel() {
        let text = "Type: Mac16,13\tECID: 0x61124360B801C\tUDID: N/A Location: 0x2100000 Name: N/A\n"
        let hints = TargetModelReadOnlyResolver.parse(text)
        let left = device(ecid: "0012682E0CFB401E", location: "01100000")
        let right = device(ecid: "00061124360B801C", location: "02100000")
        let enriched = TargetModelReadOnlyResolver.enrich([left, right], hints: hints)
        XCTAssertNil(enriched.first { $0.locationID == "01100000" }?.modelIdentifier)
        XCTAssertEqual(enriched.first { $0.locationID == "02100000" }?.modelIdentifier, "Mac16,13")
    }

    func testDifferentECIDOnSameLocationDoesNotInheritOldModel() {
        let hints = TargetModelReadOnlyResolver.parse(
            "Type: Mac16,12\tECID: 0x0011223344556677\tUDID: N/A Location: 0x2100000 Name: N/A\n")
        let newDevice = device(ecid: "00061124360B801C", location: "02100000")
        let enriched = TargetModelReadOnlyResolver.enrich([newDevice], hints: hints)
        XCTAssertNil(enriched.first?.modelIdentifier,
                     "a late old query at the same USB location must not lend its model to a different ECID")
        XCTAssertNil(enriched.first?.modelSource)
    }

    func testUnknownIdentityStartsAtMostOneBackgroundQuery() {
        TargetModelReadOnlyResolver.resetForTesting()
        let target = device(ecid: "00061124360B801C", location: "02100000")
        XCTAssertTrue(TargetModelReadOnlyResolver.shouldStartQuery(for: [target]))
        XCTAssertFalse(TargetModelReadOnlyResolver.shouldStartQuery(for: [target]))
        TargetModelReadOnlyResolver.resetForTesting()
    }

    func testUnresolvedIdentityCanBeRetriedAfterCooldown() {
        TargetModelReadOnlyResolver.resetForTesting()
        let target = device(ecid: "0012682E0CFB401E", location: "01100000")
        let t = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(TargetModelReadOnlyResolver.shouldStartQuery(for: [target], now: t))
        TargetModelReadOnlyResolver.finishQueryForTesting(hints: [])
        XCTAssertFalse(TargetModelReadOnlyResolver.shouldStartQuery(for: [target], now: t.addingTimeInterval(5)))
        XCTAssertTrue(TargetModelReadOnlyResolver.shouldStartQuery(for: [target], now: t.addingTimeInterval(31)))
        TargetModelReadOnlyResolver.resetForTesting()
    }

    func testGenericUSBProductIsNeverAcceptedAsModel() {
        XCTAssertNil(TargetModelCatalog.identifier(from: "Mac"))
        XCTAssertNil(TargetModelCatalog.identifier(from: "Apple Mobile Device (DFU Mode)"))
    }

    func testECIDlessNormalUSBUsesUniqueCfgutilLocationHint() {
        let text = "Type: Mac16,10\tECID: 0x1E253E2206401C\tUDID: N/A Location: 0x1100000 Name: N/A\n"
        let hints = TargetModelReadOnlyResolver.parse(text)
        let observed = device(ecid: nil, location: "01100000")
        let enriched = TargetModelReadOnlyResolver.enrich([observed], hints: hints)
        XCTAssertEqual(enriched.first?.modelIdentifier, "Mac16,10")
        XCTAssertEqual(enriched.first?.modelSource, TargetModelReadOnlyResolver.source)
    }

    func testECIDlessNormalUSBDoesNotUseAmbiguousLocationHints() {
        let hints = [
            TargetModelReadOnlyResolver.Hint(
                modelIdentifier: "Mac16,10", ecid: "0001", locationID: "01100000"),
            TargetModelReadOnlyResolver.Hint(
                modelIdentifier: "Mac16,11", ecid: "0002", locationID: "01100000"),
        ]
        let observed = device(ecid: nil, location: "01100000")
        let enriched = TargetModelReadOnlyResolver.enrich([observed], hints: hints)
        XCTAssertNil(enriched.first?.modelIdentifier)
    }

    func testAppleDebugUSBNodeBindsMac168FromCfgutilLocation() {
        let ioreg = """
        +-o Debug USB@01100000  <class IOUSBHostDevice, id 0x1000155a7>
          {
            "USB Product Name" = "Debug USB"
            "kUSBProductString" = "Debug USB"
            "idProduct" = 6273
            "idVendor" = 1452
            "locationID" = 17825792
          }
        """
        let observed = ObservedDeviceReader.parse(ioreg)
        XCTAssertEqual(observed.count, 1)
        XCTAssertEqual(observed.first?.mode, .connected)
        XCTAssertEqual(observed.first?.locationID, "01100000")
        XCTAssertNil(observed.first?.modelIdentifier)

        let hints = TargetModelReadOnlyResolver.parse(
            "Type: Mac16,8\tECID: 0x1C71662600801C\tUDID: N/A Location: 0x1100000 Name: N/A\n")
        let enriched = TargetModelReadOnlyResolver.enrich(observed, hints: hints)
        XCTAssertEqual(enriched.first?.modelIdentifier, "Mac16,8")
        XCTAssertEqual(
            DeviceDisplayIdentity.currentHeadline(
                mode: enriched.first?.mode ?? .unknown,
                identifiedModel: enriched.first?.modelIdentifier),
            "MacBook Pro（14 英寸，M4 Pro，2024 年） · 已连接")
    }
}

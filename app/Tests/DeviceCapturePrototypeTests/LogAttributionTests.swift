import XCTest
@testable import DeviceCapturePrototype

final class LogAttributionTests: XCTestCase {
    private let canonical = "0011223344556677"
    private let decimal = "4822678189205111"

    func testHexDecimalAndLeadingZeroFormsAreSameIdentity() {
        let lines = [
            "Device ECID=0x0011223344556677 entered DFU",
            "Device ECID:\(decimal) entered DFU",
            "Device ECID=00011223344556677 reconnected",
            "device ECID=0011223344556677 disconnected",
        ]
        for line in lines {
            XCTAssertTrue(LogAttribution.line(line, belongsTo: canonical), line)
        }
    }

    func testMultipleIdentitiesAreNeverAssignedToOneDevice() {
        let line = "Device ECID=0x\(canonical) also saw ECID=0x0011223344556677"
        XCTAssertFalse(LogAttribution.line(line, belongsTo: canonical))
        let unbound = LogAttribution.unbound([line], knownECIDs: [canonical, "0011223344556677"])
        XCTAssertEqual(unbound, [line])
    }

    func testSubstringIsNotAnIdentityMatch() {
        let lines = [
            "NOTECID=0x\(canonical) is not a labeled token",
            "configurator started restore",
            "device ECID=0x0011223344556677 entered DFU",
        ]
        XCTAssertFalse(LogAttribution.line(lines[0], belongsTo: canonical))
        XCTAssertFalse(LogAttribution.line(lines[2], belongsTo: canonical))
        XCTAssertEqual(LogAttribution.unbound(lines, knownECIDs: [canonical]), lines)
    }

    func testNoKnownECIDMeansEverythingIsUnbound() {
        let lines = ["one", "two"]
        XCTAssertEqual(LogAttribution.unbound(lines, knownECIDs: []), lines)
    }
}

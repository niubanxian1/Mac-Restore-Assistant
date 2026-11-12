import XCTest
import Foundation
import MRAHelperCore

final class HelperHostPortParserTests: XCTestCase {
    func testParseUsesAppleHPMMatchingServiceIdNotDeviceId() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ioreg-applehpm-owner-mac-m1max.txt")
        let text = try String(contentsOf: fixture, encoding: .utf8)
        let ports = HostPortTextParser.parse(text)
        XCTAssertFalse(ports.isEmpty, "expected live host ports in fixture")

        let right = ports.first { $0.rid == 2 && $0.portNumber == 3 }
        XCTAssertEqual(right?.controller.lowercased(), "100000763")
        XCTAssertFalse(ports.contains { $0.controller.lowercased() == "10000081e" })

        let leftLower = ports.first { $0.rid == 1 && $0.portNumber == 2 }
        XCTAssertEqual(leftLower?.controller.lowercased(), "100000760")
        XCTAssertFalse(ports.contains { $0.controller.lowercased() == "100000813" })
    }

    func testParseLegacyBareAppleHPMClassStillWorks() {
        let text = """
        +-o AppleHPM  <class AppleHPM, id 0x100000abc, registered, matched, active, busy 0 (0 ms), retain 8>
          |   "RID" = 4
          +-o Port-USB-C@1  <class AppleTCControllerType10, id 0x100000def, registered, matched, active, busy 0 (0 ms), retain 8>
            |   "BuiltIn" = Yes
            |   "PortNumber" = 7
        """
        let ports = HostPortTextParser.parse(text)
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].controller.lowercased(), "100000abc")
        XCTAssertEqual(ports[0].portNumber, 7)
        XCTAssertEqual(ports[0].rid, 4)
    }
}

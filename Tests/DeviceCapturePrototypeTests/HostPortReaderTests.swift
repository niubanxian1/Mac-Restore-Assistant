import XCTest
@testable import DeviceCapturePrototype
import Foundation

final class HostPortReaderTests: XCTestCase {
    func testParseUsesAppleHPMMatchingServiceIdNotDeviceId() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ioreg-applehpm-owner-mac-m1max.txt")
        let text = try String(contentsOf: fixture, encoding: .utf8)
        let ports = HostPortReader.parse(text)
        XCTAssertFalse(ports.isEmpty, "expected live host ports in fixture")

        // Right S5: parent AppleHPMARMI2C 100000763, child Device 10000081e must not be used.
        let right = ports.first { $0.rid == 2 && $0.portNumber == 3 }
        XCTAssertEqual(right?.controller.lowercased(), "100000763")
        XCTAssertFalse(ports.contains { $0.controller.lowercased() == "10000081e" })

        // Left-lower Air path: parent 100000760, not Device 100000813.
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
        let ports = HostPortReader.parse(text)
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].controller.lowercased(), "100000abc")
        XCTAssertEqual(ports[0].portNumber, 7)
        XCTAssertEqual(ports[0].rid, 4)
    }

    func testU1U2U3U4ParsesCompleteReadOnlyPortFacts() throws {
        let text = """
        +-o AppleHPMARMI2C  <class AppleHPMARMI2C, id 0x100000760, registered, matched, active, busy 0 (1 ms), retain 8>
          | {
          |   "RID" = 1
          | }
          +-o AppleHPMDevice@3F  <class AppleHPMDevice, id 0x100000813, registered, matched, active, busy 0 (1 ms), retain 8>
            | {
            | }
            +-o Port-USB-C@2  <class AppleTCControllerType10, id 0x100000820, registered, matched, active, busy 0 (1 ms), retain 8>
              | {
              |   "port-location" = <"left-front">
              |   "PortNumber" = 2
              |   "ParentBuiltInPortNumber" = 2
              |   "ParentBuiltInPortTypeDescription" = "USB-C"
              |   "ConnectionActive" = Yes
              |   "TransportsProvisioned" = ()
              |   "TransportsActive" = ("USB3")
              |   "Overcurrent Count" = 0
              |   "TransportsUnauthorized" = ()
              |   "AuthorizationRequired" = Yes
              |   "UserAuthorizationStatusDescription" = "No Action"
              |   "FeaturesSupported" = ("TRM","Power In")
              |   "FeaturesEnabled" = ("TRM")
              | }
              +-o USB3  <class IOPortTransportStateUSB3, id 0x10000201e, registered, matched, active, busy 0 (1 ms), retain 8>
              | {
              |   "TransportTypeDescription" = "USB3"
              |   "ParentBuiltInPortNumber" = 2
              |   "ParentBuiltInPortTypeDescription" = "USB-C"
              |   "DataRateDescription" = "5 Gbps"
              |   "SuperSpeedSignalingDescription" = "Gen 1"
              |   "Tunneled" = No
              |   "DataRoleDescription" = "Host"
              |   "Active" = Yes
              | }
              +-o DisplayPort  <class IOPortTransportStateDisplayPort, id 0x100002021, registered, matched, active, busy 0 (1 ms), retain 8>
                {
                  "TransportTypeDescription" = "DisplayPort"
                  "ParentBuiltInPortNumber" = 2
                  "ParentBuiltInPortTypeDescription" = "USB-C"
                  "LinkRateDescription" = "HBR3"
                  "Active" = No
                }
        """
        let ports = HostPortReader.parse(text)
        let link = try XCTUnwrap(ports.first { $0.portNumber == 2 }?.link)

        XCTAssertEqual(link.portLocation, "left-front")
        XCTAssertEqual(link.parentPortNumber, 2)
        XCTAssertEqual(link.parentPortTypeDescription, "USB-C")
        XCTAssertEqual(link.transportsProvisionedState, .provided([]))
        XCTAssertEqual(link.transportsSupportedState, .notProvided)
        XCTAssertEqual(link.transportsActiveState, .provided(["USB3"]))
        XCTAssertEqual(link.overcurrentCount, 0)
        XCTAssertEqual(link.transportsUnauthorized, .provided([]))
        XCTAssertEqual(link.authorizationRequired, true)
        XCTAssertEqual(link.userAuthorizationStatusDescription, "No Action")
        XCTAssertEqual(link.featuresSupported, .provided(["TRM", "Power In"]))
        XCTAssertEqual(link.featuresEnabled, .provided(["TRM"]))
        XCTAssertEqual(link.activeTransportDetails.count, 1)
        let activeTransport = try XCTUnwrap(link.activeTransportDetails.first)
        XCTAssertEqual(activeTransport.name, "USB3")
        XCTAssertEqual(activeTransport.dataRateDescription, "5 Gbps")
        XCTAssertEqual(activeTransport.superspeedSignalingDescription, "Gen 1")
        XCTAssertEqual(activeTransport.tunneled, false)
        XCTAssertEqual(activeTransport.dataRoleDescription, "Host")
    }

    func testU2MissingAndEmptyTransportListsRemainDistinct() {
        let text = """
        +-o AppleHPMARMI2C  <class AppleHPMARMI2C, id 0x100000760, registered, matched, active>
          | {
          |   "RID" = 1
          | }
          +-o Port-USB-C@2  <class AppleTCControllerType10, id 0x100000820>
            | {
            |   "PortNumber" = 2
            |   "TransportsProvisioned" = ()
            | }
        """
        let link = HostPortReader.parse(text).first?.link

        XCTAssertEqual(link?.transportsProvisionedState, .provided([]))
        XCTAssertEqual(link?.transportsSupportedState, .notProvided)
        XCTAssertEqual(link?.transportsActiveState, .notProvided)
    }

    func testU3TransportDetailsRemainIsolatedByControllerAndParentPort() throws {
        let text = """
        +-o AppleHPMARMI2C  <class AppleHPMARMI2C, id 0x100000760, registered, matched, active>
          | {
          |   "RID" = 1
          | }
          +-o Port-USB-C@2  <class AppleTCControllerType10, id 0x100000820>
            | {
            |   "PortNumber" = 2
            | }
            +-o USB3  <class IOPortTransportStateUSB3, id 0x10000201e>
              | {
              |   "TransportTypeDescription" = "USB3"
              |   "ParentBuiltInPortNumber" = 2
              |   "ParentBuiltInPortTypeDescription" = "USB-C"
              |   "DataRateDescription" = "5 Gbps"
              |   "Active" = Yes
              | }
        +-o AppleHPMARMI2C  <class AppleHPMARMI2C, id 0x100000763, registered, matched, active>
          | {
          |   "RID" = 2
          | }
          +-o Port-USB-C@2  <class AppleTCControllerType10, id 0x100000830>
            | {
            |   "PortNumber" = 2
            | }
            +-o DisplayPort  <class IOPortTransportStateDisplayPort, id 0x10000202f>
              | {
              |   "TransportTypeDescription" = "DisplayPort"
              |   "ParentBuiltInPortNumber" = 1
              |   "ParentBuiltInPortTypeDescription" = "USB-C"
              |   "LinkRateDescription" = "HBR3"
              |   "Active" = Yes
              | }
        """
        let parsed = HostPortReader.parse(text)
        XCTAssertEqual(
            parsed.map { "\($0.controller.lowercased()):\($0.portNumber):\($0.rid)" },
            ["100000760:2:1", "100000763:2:2"])
        let left = try XCTUnwrap(
            parsed.first { $0.controller.lowercased() == "100000760" }?.link)
        let right = try XCTUnwrap(
            parsed.first { $0.controller.lowercased() == "100000763" }?.link)
        XCTAssertEqual(left.activeTransportDetails.map(\.name), ["USB3"])
        XCTAssertEqual(left.activeTransportDetails.first?.dataRateDescription, "5 Gbps")
        XCTAssertTrue(right.activeTransportDetails.isEmpty)
    }
}

import XCTest
@testable import DeviceCapturePrototype

final class PortAssociationRegressionTests: XCTestCase {
    private let rightEntry = PortCalibrationEntry(
        physicalPort: "right1", location: "02100000", label: "右侧",
        rid: "2", side: "右侧")

    func testUSBLocation02100000RID2ResolvesToS5NotS3() {
        let live = [
            LiveHostPort(controller: "100000834", portNumber: 1, rid: 0), // S3
            LiveHostPort(controller: "10000081e", portNumber: 3, rid: 2), // S5
        ]
        let resolved = PortAssociationResolver.resolve(
            locationID: "02100000", calibratedPorts: [rightEntry], livePorts: live)
        XCTAssertEqual(resolved, "10000081e:3")
        XCTAssertNotEqual(resolved, "100000834:1")
    }

    func testLivePortOrderDoesNotChangeAssociation() {
        let live = [
            LiveHostPort(controller: "10000081e", portNumber: 3, rid: 2),
            LiveHostPort(controller: "100000834", portNumber: 1, rid: 0),
        ]
        XCTAssertEqual(PortAssociationResolver.resolve(
            locationID: "02100000", calibratedPorts: [rightEntry], livePorts: live),
            "10000081e:3")
    }

    func testDefaultRight1RIDIsCorrectedTo2() {
        let right = CalibrationDocument.initial.ports.first { $0.physicalPort == "right1" }
        XCTAssertEqual(right?.rid, "2")
        XCTAssertEqual(right?.location, "02100000")
        XCTAssertEqual(right?.label, "右侧")
        XCTAssertEqual(right?.side, "右侧")
    }

    func testAmbiguousOrUnknownLocationDoesNotFallbackToOrder() {
        let live = [LiveHostPort(controller: "100000834", portNumber: 1, rid: 0)]
        XCTAssertNil(PortAssociationResolver.resolve(
            locationID: "09999999", calibratedPorts: [rightEntry], livePorts: live))
    }
}

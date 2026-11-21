import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class RestoreTargetFallbackTests: XCTestCase {
    func testModelIdentifierFillsMissingProductType() {
        let device = ObservedDevice(
            id: "ecid:0011223344556677",
            ecid: "0011223344556677",
            mode: .dfu,
            locationID: "01200000",
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:0011223344556677",
            modelIdentifier: "MacBookAir10,1",
            chipID: 0x8103,
            boardID: 0x28,
            hardwareCode: "j274ap",
            productType: nil)
        let targets = RestoreSnapshotInspector.targets(from: [device])
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets[0].productType, "MacBookAir10,1")
        XCTAssertEqual(targets[0].machineIdentifier, "MacBookAir10,1")
    }
}

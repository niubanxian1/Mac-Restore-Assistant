import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class PortDeviceWorkspaceTests: XCTestCase {
    func testObservationDefaultsToFollowingControlAndCanBePinnedIndependently() {
        let defaults = UserDefaults(suiteName: "PortDeviceWorkspaceTests-\(UUID().uuidString)")!
        let model = PortDeviceWorkspaceModel(defaults: defaults)

        XCTAssertTrue(model.followsLeftControl)
        XCTAssertEqual(
            model.observationPortID(
                controlPortID: "controller:2",
                availablePortIDs: ["controller:2", "controller:3"]),
            "controller:2")

        model.setFixedObservationPort("controller:3")
        XCTAssertFalse(model.followsLeftControl)
        XCTAssertEqual(
            model.observationPortID(
                controlPortID: "controller:2",
                availablePortIDs: ["controller:2", "controller:3"]),
            "controller:3")

        model.followLeftControl()
        XCTAssertEqual(
            model.observationPortID(
                controlPortID: "controller:2",
                availablePortIDs: ["controller:2", "controller:3"]),
            "controller:2")
    }

    func testPinnedObservationNeverFallsBackToControlWhenItsPortDisappears() {
        let defaults = UserDefaults(suiteName: "PortDeviceWorkspaceTests-\(UUID().uuidString)")!
        let model = PortDeviceWorkspaceModel(defaults: defaults)
        model.setFixedObservationPort("controller:3")

        XCTAssertNil(
            model.observationPortID(
                controlPortID: "controller:2",
                availablePortIDs: ["controller:2"]))
    }

    func testDensityDefaultsToCommonAndPersistsAcrossModels() {
        let suite = "PortDeviceWorkspaceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let first = PortDeviceWorkspaceModel(defaults: defaults)
        XCTAssertEqual(first.density, .common)

        first.density = .all
        let second = PortDeviceWorkspaceModel(defaults: defaults)
        XCTAssertEqual(second.density, .all)
    }

    func testDensityPoliciesKeepIdentityVisibleWhileTechnicalDetailsFollowSelection() {
        XCTAssertTrue(PortDeviceDensityPolicy.visible(
            group: "设备身份", density: .simple))
        XCTAssertTrue(PortDeviceDensityPolicy.visible(
            group: "端口控制器", density: .common))
        XCTAssertFalse(PortDeviceDensityPolicy.visible(
            group: "端口控制器", density: .simple))
        XCTAssertFalse(PortDeviceDensityPolicy.visible(
            group: "传输子节点", density: .common))
        XCTAssertTrue(PortDeviceDensityPolicy.visible(
            group: "传输子节点", density: .all))
    }
}

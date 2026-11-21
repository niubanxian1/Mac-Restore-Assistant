import XCTest
@testable import DeviceCapturePrototype
import Foundation

@MainActor
final class BuiltInCalibrationTests: XCTestCase {
    func testCurrentHostExactLayoutSlots() throws {
        let host = BuiltInCalibration.currentHostModel()
        XCTAssertEqual(host, "MacBookPro18,2")
        let loaded = BuiltInCalibration.load()
        let layout = try XCTUnwrap(loaded.database[host])
        XCTAssertEqual(layout.displayName, "M1 Pro MacBook Pro A2485 16英寸")
        XCTAssertEqual(layout.slots.map(\.slot), ["S3", "S4", "S5"])
        XCTAssertEqual(layout.slots.map(\.portNumber), [1, 2, 3])
        XCTAssertEqual(layout.slots.map(\.rid), [0, 1, 2])
    }

    func testLiveHPMBindingMatchesArchivedPortAndRIDNotControllerID() {
        let live = HostPortReader.read()
        XCTAssertGreaterThanOrEqual(live.count, 3)
        let host = BuiltInCalibration.currentHostModel()
        let layout = BuiltInCalibration.load().database[host]!
        // Runtime controller IDs are not in the archive; matching is by
        // PortNumber + RID and does not depend on controller persistence.
        let matches = live.compactMap { p in
            layout.slots.first { $0.portNumber == p.portNumber && $0.rid == p.rid }
        }
        XCTAssertEqual(Set(matches.map(\.slot)), Set(["S3", "S4", "S5"]))
        XCTAssertFalse(live.contains { $0.controller.isEmpty })
    }

    func testCustomCalibrationFileIsNotOverwrittenByBuiltinLoad() {
        let store = CalibrationStore()
        XCTAssertNotNil(store.builtInLayout)
        let before = try? Data(contentsOf: calibrationURL())
        let customCount = store.ports.count
        _ = CalibrationStore()
        let after = try? Data(contentsOf: calibrationURL())
        XCTAssertEqual(before!, after!)
        XCTAssertEqual(store.ports.count, customCount)
    }

    private func calibrationURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MRA_DeviceCapture_Prototype/calibration.json")
    }
}

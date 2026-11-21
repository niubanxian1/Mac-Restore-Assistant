import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class PortSelectionFailClosedTests: XCTestCase {
    /// T08 — Port order changes must not affect an already saved target (S5).
    func testSavedTargetStableWhenLivePortOrderChanges() throws {
        let s3 = AcceptanceFixtures.slotS3
        let s4 = AcceptanceFixtures.slotS4
        let s5 = AcceptanceFixtures.slotS5
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mra022-t08-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let file = temp.appendingPathComponent("calibration.json")
        let device = AcceptanceModels.makeModel(
            ports: [s3, s4, s5],
            selected: s5.id,
            persistPortSelection: true,
            fileURL: file)
        XCTAssertEqual(device.selectedLiveKey, s5.id)
        device.applyDiscoveredPorts([s5, s4, s3], persistCalibration: true)
        XCTAssertEqual(device.selectedLiveKey, s5.id)
        device.applyDiscoveredPorts([s4, s3, s5], persistCalibration: true)
        XCTAssertEqual(device.selectedLiveKey, s5.id)
        XCTAssertEqual(device.selectedLivePort?.controller, s5.controller)
        XCTAssertEqual(device.selectedLivePort?.portNumber, s5.portNumber)
        XCTAssertEqual(device.selectedLivePort?.rid, s5.rid)
        XCTAssertEqual(device.calibration.selectedPort, s5.id)
    }

    /// T09 — If the preferred port disappears, do not auto-select the first remaining live port.
    func testPreferredPortMissingDoesNotSelectFirstLivePort() throws {
        let s3 = AcceptanceFixtures.slotS3
        let s4 = AcceptanceFixtures.slotS4
        let s5 = AcceptanceFixtures.slotS5
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mra022-t09-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let file = temp.appendingPathComponent("calibration.json")
        let device = AcceptanceModels.makeModel(
            ports: [s3, s4, s5],
            selected: s5.id,
            persistPortSelection: true,
            fileURL: file)
        XCTAssertEqual(device.selectedLiveKey, s5.id)
        let before = try? String(contentsOf: file, encoding: .utf8)
        device.applyDiscoveredPorts([s3, s4], persistCalibration: true)
        XCTAssertEqual(device.selectedLiveKey, "", "missing preferred port must not be replaced by the first remaining mapped port")
        XCTAssertNil(device.selectedLivePort)
        XCTAssertNotEqual(device.selectedLiveKey, s3.id)
        XCTAssertNotEqual(device.calibration.selectedPort, s3.id)
        XCTAssertTrue(device.mappingNote.contains("不会按列表顺序猜测") || device.mappingNote.contains("人工确认"))
        XCTAssertFalse(device.canControl)
        if FileManager.default.fileExists(atPath: file.path) {
            let after = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(after.contains(s3.id) && device.calibration.selectedPort == s3.id)
            if let before, before.contains(s5.id) {
                XCTAssertTrue(after.contains(s5.id) || device.calibration.selectedPort == s5.id || device.calibration.selectedPort != s3.id)
            }
        }
    }
}

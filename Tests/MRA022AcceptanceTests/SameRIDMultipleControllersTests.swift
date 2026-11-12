import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class SameRIDMultipleControllersTests: XCTestCase {
    /// T04 — Same RID on two controllers must be rejected; no silent selectedPort rewrite.
    func testSameRIDOnTwoControllersIsRejected() throws {
        let twins = AcceptanceFixtures.sameRIDTwoControllers
        let custom = [PortCalibrationEntry(
            physicalPort: "legacy", location: "01100000", label: "ambiguous",
            rid: "0", side: "左侧")]
        let document = CalibrationDocument(models: [], ports: custom, selectedPort: "legacy")
        // RID-only custom must be evaluated without a unique builtin slot
        // attaching one of the twins (the canonical S3 slot is also port 1 / RID 0).
        let device = AcceptanceModels.makeModel(
            ports: twins, document: document, selected: "legacy", layout: nil)
        XCTAssertEqual(device.selectedLiveKey, "")
        XCTAssertNil(device.selectedLivePort)
        XCTAssertFalse(device.isMapped(twins[0]))
        XCTAssertFalse(device.isMapped(twins[1]))
        XCTAssertFalse(device.canControl)
        XCTAssertTrue(device.mappingNote.contains("不会按列表顺序猜测") || device.mappingNote.contains("人工确认"))
        XCTAssertNotEqual(device.selectedLiveKey, twins[0].id)
        XCTAssertNotEqual(device.selectedLiveKey, twins[1].id)
    }

    /// T04 — A builtin slot must not attach to both controllers when portNumber+RID collide.
    func testBuiltinSlotConsidersControllerNotRIDAlone() {
        let layout = AcceptanceFixtures.macBookProLayout()
        let twin = LiveHostPort(controller: "100000999", portNumber: 1, rid: 0)
        let ports = [AcceptanceFixtures.slotS3, twin]
        let document = CalibrationDocument(models: [], ports: [], selectedPort: "")
        let device = AcceptanceModels.makeModel(
            ports: ports, document: document, selected: "", layout: layout)
        XCTAssertNil(device.uniquelyMappedBuiltInSlot(for: AcceptanceFixtures.slotS3))
        XCTAssertNil(device.uniquelyMappedBuiltInSlot(for: twin))
        XCTAssertEqual(device.selectedLiveKey, "")
        XCTAssertTrue(device.mappingNote.contains("不会按列表顺序猜测") || device.mappingNote.contains("人工确认") || device.mappingNote.contains("冲突"))
        XCTAssertFalse(device.canControl)
    }
}

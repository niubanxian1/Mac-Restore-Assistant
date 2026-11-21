import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class LegacyCalibrationMigrationTests: XCTestCase {
    /// T10 — Legacy right1 / 02100000 RID 0 must not map to S3.
    func testLegacyRight1RID0DoesNotMapToS3() throws {
        let document = try AcceptanceFixtures.loadDocument("legacy-right1-rid-0.json")
        let rightBefore = document.ports.first { $0.physicalPort == "right1" }
        XCTAssertEqual(rightBefore?.rid, "0")
        XCTAssertEqual(rightBefore?.location, "02100000")

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mra022-t10-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let file = temp.appendingPathComponent("calibration.json")
        let device = AcceptanceModels.makeModel(
            ports: AcceptanceFixtures.canonicalLivePorts,
            document: document,
            selected: document.selectedPort,
            fileURL: file)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MRA_DeviceCapture_Prototype/calibration.json")
        if let appSupport {
            XCTAssertNotEqual(file.standardizedFileURL, appSupport.standardizedFileURL)
        }

        let right = device.calibration.ports.first { $0.physicalPort == "right1" }
        XCTAssertEqual(right?.rid, "2", "old right1 RID 0 must be migrated away from S3")
        XCTAssertNotEqual(device.selectedLiveKey, AcceptanceFixtures.slotS3.id)
        XCTAssertNotEqual(device.selectedLivePort?.rid, 0)
        XCTAssertNotEqual(device.selectedLivePort?.portNumber, 1)
        if let live = device.selectedLivePort {
            XCTAssertEqual(live.id, AcceptanceFixtures.slotS5.id)
            XCTAssertEqual(live.rid, 2)
            XCTAssertEqual(live.portNumber, 3)
        }
        XCTAssertFalse(device.isMapped(AcceptanceFixtures.slotS3) && device.selectedLiveKey == AcceptanceFixtures.slotS3.id)
    }

    /// T10 — Loading the old row must migrate or surface an explicit prompt.
    func testLegacyRight1RID0MigrationOrPrompt() throws {
        let document = try AcceptanceFixtures.loadDocument("legacy-right1-rid-0.json")
        let store = AcceptanceFixtures.isolatedStore(document: document)
        XCTAssertEqual(store.ports.first { $0.physicalPort == "right1" }?.rid, "2")
        let note = store.saveMessage
        XCTAssertTrue(note.contains("RID 0") || note.contains("迁移") || note.contains("RID 2"),
                      "loading the old row must migrate or show an explicit prompt; note was: \(note)")
        XCTAssertTrue(note.contains("02100000") || note.contains("right1") || note.contains("S3") || note.contains("迁移"))
    }

    /// T10 contrast — corrected RID 2 still maps to S5.
    func testCorrectedRight1RID2StillMapsToS5() throws {
        let document = try AcceptanceFixtures.loadDocument("legacy-right1-rid-2-corrected.json")
        let rightBefore = document.ports.first { $0.physicalPort == "right1" }
        XCTAssertEqual(rightBefore?.rid, "2")
        let device = AcceptanceModels.makeModel(
            ports: AcceptanceFixtures.canonicalLivePorts,
            document: document,
            selected: document.selectedPort)
        let right = device.calibration.ports.first { $0.physicalPort == "right1" }
        XCTAssertEqual(right?.rid, "2")
        XCTAssertEqual(device.selectedLiveKey, AcceptanceFixtures.slotS5.id)
        XCTAssertEqual(device.selectedLivePort?.rid, 2)
        XCTAssertEqual(device.selectedLivePort?.portNumber, 3)
        XCTAssertEqual(device.selectedLivePort?.controller, AcceptanceFixtures.slotS5.controller)
        XCTAssertNotEqual(device.selectedLiveKey, AcceptanceFixtures.slotS3.id)
    }
}

import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class InAppModelCalibrationTests: XCTestCase {
    private func store(host: String = "MacBookPro18,2") -> CalibrationStore {
        let doc = CalibrationDocument(models: [], ports: [], selectedPort: "")
        return CalibrationStore(testingDocument: doc, hostModel: host, builtInLayout: nil)
    }

    private func slots() -> [CalibrationSlotDraft] {
        [
            CalibrationSlotDraft(id: "S1", face: "LEFT", label: "左侧上方"),
            CalibrationSlotDraft(id: "S2", face: "LEFT", label: "左侧下方"),
            CalibrationSlotDraft(id: "S3", face: "RIGHT", label: "右侧"),
        ]
    }

    private func source() -> SimulatedCalibrationObservationSource {
        SimulatedCalibrationObservationSource(ports: [
            CalibrationPortObservation(id: "c:1", controller: "c", portNumber: 1, rid: 0, connected: false, transports: ["CC", "USB2"]),
            CalibrationPortObservation(id: "c:2", controller: "c", portNumber: 2, rid: 1, connected: false, transports: ["CC", "USB2"]),
            CalibrationPortObservation(id: "c:3", controller: "c", portNumber: 3, rid: 2, connected: false, transports: ["CC", "USB2"]),
        ])
    }

    func testSimulatedSessionRequiresUniqueChangeAndProbeRemoval() {
        let sim = source()
        let session = InAppCalibrationSession(slots: slots(), source: sim)
        session.startSlot()
        XCTAssertEqual(session.step, .waitingForInsert)

        session.detectChange()
        XCTAssertEqual(session.step, .waitingForInsert)
        XCTAssertTrue(session.statusMessage.contains("0"))

        sim.setConnected("c:1", true)
        sim.setConnected("c:2", true)
        session.detectChange()
        XCTAssertEqual(session.step, .waitingForInsert)
        XCTAssertTrue(session.statusMessage.contains("多个"))

        sim.setConnected("c:2", false)
        session.detectChange()
        XCTAssertEqual(session.step, .waitingForRemoval)
        XCTAssertEqual(session.candidate?.portNumber, 1)

        session.confirmRemoved()
        XCTAssertEqual(session.step, .waitingForRemoval, "probe is still present")

        sim.setConnected("c:1", false)
        session.confirmRemoved()
        XCTAssertEqual(session.step, .readyToConfirm)

        session.confirmMapping()
        XCTAssertEqual(session.currentIndex, 1)
        XCTAssertEqual(session.associations["S1"]?.portNumber, 1)
        XCTAssertEqual(session.step, .waitingForInsert)
    }

    func testCompleteInAppCalibrationBecomesExactForTheHost() {
        let store = store()
        let sim = source()
        let session = InAppCalibrationSession(slots: slots(), source: sim)
        let ports = [("S1", "c:1"), ("S2", "c:2"), ("S3", "c:3")]
        for (index, pair) in ports.enumerated() {
            _ = index
            session.startSlot()
            sim.setConnected(pair.1, true)
            session.detectChange()
            sim.setConnected(pair.1, false)
            session.confirmRemoved()
            session.confirmMapping()
        }
        XCTAssertTrue(session.isComplete)
        XCTAssertTrue(session.canSaveExact)
        let layout = session.makeLayout(hostModel: store.hostModel, displayName: "本机校准")
        XCTAssertFalse(layout.partial)
        XCTAssertEqual(layout.slots.count, 3)
        XCTAssertEqual(layout.slots[0].portNumber, 1)
        XCTAssertEqual(layout.slots[0].rid, 0)

        store.applyInAppCalibration(layout: layout, displayName: "本机校准", complete: true)
        let device = DeviceControlModel(calibration: store, startLiveWork: false)
        XCTAssertEqual(store.adoptedOverlay?.source, .inAppCalibration)
        XCTAssertTrue(device.hasExactVerifiedHostCalibration)
        XCTAssertEqual(device.hostModelCalibrationKind, .exactVerifiedRecord)
        XCTAssertEqual(device.hostCalibrationSummaryText, "主机 MacBookPro18,2 · 机型已精确校准")
        XCTAssertEqual(device.hostCalibrationLampState, .calibrated)
        XCTAssertEqual(device.hostCalibrationLampState.color, "green")
    }

    func testSkippedSlotStaysCustomLayoutNotExact() {
        let store = store()
        let sim = source()
        let session = InAppCalibrationSession(slots: slots(), source: sim)
        session.startSlot()
        session.skipSlot()
        session.startSlot()
        sim.setConnected("c:2", true)
        session.detectChange()
        sim.setConnected("c:2", false)
        session.confirmRemoved()
        session.confirmMapping()
        session.startSlot()
        session.skipSlot()
        XCTAssertTrue(session.isComplete)
        XCTAssertFalse(session.canSaveExact)

        let layout = session.makeLayout(hostModel: store.hostModel, displayName: "自定义布局")
        store.applyInAppCalibration(layout: layout, displayName: "自定义布局", complete: session.canSaveExact)
        let device = DeviceControlModel(calibration: store, startLiveWork: false)
        XCTAssertEqual(store.adoptedOverlay?.source, .customLayout)
        XCTAssertFalse(device.hasExactVerifiedHostCalibration)
        XCTAssertEqual(device.hostModelCalibrationKind, .uncalibrated)
    }

    func testAddingModelStillDoesNotBecomeExactWithoutSlotCalibration() {
        let store = store()
        let device = DeviceControlModel(calibration: store, startLiveWork: false)
        store.addHostModel("Mac16,12")
        XCTAssertEqual(store.adoptedOverlay?.source, .addedModelOnly)
        XCTAssertFalse(device.hasExactVerifiedHostCalibration)
    }

    func testDraftRoundTripKeepsSlotAndFace() {
        let layout = BuiltInLayout(displayName: "x", sourceFile: "", slots: [
            BuiltInSlot(slot: "S1", face: "LEFT", portNumber: 1, rid: 0,
                        binding: "MacBookPro18,2|AppleHPMDevice|1|0", physicalName: "左侧上方"),
        ], partial: false, skippedSlots: [], generatedAt: "")
        let draft = CalibrationSlotDraft.from(layout)
        XCTAssertEqual(draft.count, 1)
        XCTAssertEqual(draft[0].displayName, "左侧上方")
        XCTAssertEqual(draft[0].face, "LEFT")
        XCTAssertEqual(draft[0].toBuiltInSlot(hostModel: "MacBookPro18,2").portNumber, 1)
    }
}

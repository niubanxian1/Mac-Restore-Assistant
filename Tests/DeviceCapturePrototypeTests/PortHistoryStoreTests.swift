import XCTest
@testable import DeviceCapturePrototype
import MRAHelperProtocol

final class PortHistoryStoreTests: XCTestCase {
    private func layout() -> BuiltInLayout {
        BuiltInLayout(
            displayName: "M1 Pro", sourceFile: "t.json",
            slots: [
                BuiltInSlot(slot: "S3", face: "LEFT", portNumber: 1, rid: 0,
                            binding: "MacBookPro18,2|AppleHPMDevice|1|0", physicalName: "左侧上方"),
                BuiltInSlot(slot: "S4", face: "LEFT", portNumber: 2, rid: 1,
                            binding: "MacBookPro18,2|AppleHPMDevice|2|1", physicalName: "左侧下方"),
                BuiltInSlot(slot: "S5", face: "RIGHT", portNumber: 3, rid: 2,
                            binding: "MacBookPro18,2|AppleHPMDevice|3|2", physicalName: "右侧"),
            ],
            partial: true, skippedSlots: ["S2"], generatedAt: "test")
    }

    private func store(host: String = "MacBookPro18,2", suffix: String = UUID().uuidString) -> (PortHistoryStore, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hist-\(suffix).json")
        try? FileManager.default.removeItem(at: url)
        let fp = PortHistoryStore.fingerprint(hostModel: host, layout: layout())
        return (PortHistoryStore(fileURL: url, hostModel: host, slotMapFingerprint: fp), url)
    }

    func testBuiltinMacBookPro182SlotTableMatchesT1306Z() throws {
        let loaded = BuiltInCalibration.load()
        let host = loaded.database["MacBookPro18,2"]
        XCTAssertNotNil(host)
        let slots = Dictionary(uniqueKeysWithValues: (host?.slots ?? []).map { ($0.slot, $0) })
        XCTAssertEqual(slots["S3"]?.physicalName, "左侧上方")
        XCTAssertEqual(slots["S3"]?.portNumber, 1)
        XCTAssertEqual(slots["S3"]?.rid, 0)
        XCTAssertEqual(slots["S4"]?.physicalName, "左侧下方")
        XCTAssertEqual(slots["S4"]?.portNumber, 2)
        XCTAssertEqual(slots["S4"]?.rid, 1)
        XCTAssertEqual(slots["S5"]?.physicalName, "右侧")
        XCTAssertEqual(slots["S5"]?.portNumber, 3)
        XCTAssertEqual(slots["S5"]?.rid, 2)
    }

    func testThreePortsShareRulesAndPersistAcrossRelaunch() {
        let (store, url) = store()
        let fp = store.document.slotMapFingerprint
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(store.updateIfEligible(slotID: "S3", product: "Apple Mobile Device (DFU Mode)",
                                             mode: .dfu, ecid: "AA", seenAt: now, controller: "c",
                                             portNumber: 1, rid: 0, hostModel: "MacBookPro18,2", fingerprint: fp))
        XCTAssertTrue(store.updateIfEligible(slotID: "S4", product: "Apple Mobile Device (Recovery Mode)",
                                             mode: .recovery, ecid: "BB", seenAt: now, controller: "c",
                                             portNumber: 2, rid: 1, hostModel: "MacBookPro18,2", fingerprint: fp))
        XCTAssertTrue(store.updateIfEligible(slotID: "S5", product: "Apple Mobile Device (DFU Mode)",
                                             mode: .dfu, ecid: "CC", seenAt: now, controller: "c",
                                             portNumber: 3, rid: 2, hostModel: "MacBookPro18,2", fingerprint: fp))
        XCTAssertEqual(store.displayStatus(slotID: "S3", hostModel: "MacBookPro18,2", fingerprint: fp, isPresent: false),
                       "当前未识别设备 · 上次 DFU")
        XCTAssertEqual(store.displayStatus(slotID: "S4", hostModel: "MacBookPro18,2", fingerprint: fp, isPresent: false),
                       "当前未识别设备 · 上次 Recovery")
        XCTAssertEqual(store.displayStatus(slotID: "S5", hostModel: "MacBookPro18,2", fingerprint: fp, isPresent: false),
                       "当前未识别设备 · 上次 DFU")
        XCTAssertEqual(store.displayStatus(slotID: "S3", hostModel: "MacBookPro18,2", fingerprint: fp, isPresent: false),
                       store.displayStatus(slotID: "S3", hostModel: "MacBookPro18,2", fingerprint: fp, isPresent: false))

        let reloaded = PortHistoryStore(fileURL: url, hostModel: "MacBookPro18,2", slotMapFingerprint: fp)
        XCTAssertEqual(reloaded.record(forSlot: "S3")?.lastECID, "AA")
        XCTAssertEqual(reloaded.record(forSlot: "S3")?.lastMode, "DFU")
        guard let reloadedSeen = reloaded.record(forSlot: "S3")?.lastSeenAt else {
            XCTFail("missing lastSeenAt after reload")
            return
        }
        XCTAssertEqual(reloadedSeen.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(reloaded.displayStatus(slotID: "S4", hostModel: "MacBookPro18,2", fingerprint: fp, isPresent: false),
                       "当前未识别设备 · 上次 Recovery")
        XCTAssertEqual(reloaded.displayStatus(slotID: "SX", hostModel: "MacBookPro18,2", fingerprint: fp, isPresent: false),
                       "无设备")
    }

    func testOrdinaryMacProductDoesNotOverwriteHistory() {
        let (store, _) = store()
        let fp = store.document.slotMapFingerprint
        let first = Date(timeIntervalSince1970: 100)
        XCTAssertTrue(store.updateIfEligible(slotID: "S3", product: "Apple Mobile Device (DFU Mode)",
                                             mode: .dfu, ecid: "AA", seenAt: first, controller: "c",
                                             portNumber: 1, rid: 0, hostModel: "MacBookPro18,2", fingerprint: fp))
        XCTAssertFalse(store.updateIfEligible(slotID: "S3", product: "MacBook Air",
                                              mode: .unknown, ecid: "ZZ", seenAt: Date(timeIntervalSince1970: 200),
                                              controller: "c", portNumber: 1, rid: 0,
                                              hostModel: "MacBookPro18,2", fingerprint: fp))
        XCTAssertEqual(store.record(forSlot: "S3")?.lastECID, "AA")
        XCTAssertEqual(store.record(forSlot: "S3")?.lastMode, "DFU")
        XCTAssertEqual(store.record(forSlot: "S3")?.lastSeenAt, first)
    }

    func testDisconnectDoesNotClearOrRewriteLastSeen() {
        let (store, _) = store()
        let fp = store.document.slotMapFingerprint
        let seen = Date(timeIntervalSince1970: 50)
        XCTAssertTrue(store.updateIfEligible(slotID: "S4", product: "Apple Mobile Device (DFU Mode)",
                                             mode: .dfu, ecid: "BB", seenAt: seen, controller: "c",
                                             portNumber: 2, rid: 1, hostModel: "MacBookPro18,2", fingerprint: fp))
        store.preserveOnDisconnect(slotID: "S4")
        XCTAssertEqual(store.record(forSlot: "S4")?.lastECID, "BB")
        XCTAssertEqual(store.record(forSlot: "S4")?.lastSeenAt, seen)
        XCTAssertEqual(store.displayStatus(slotID: "S4", hostModel: "MacBookPro18,2", fingerprint: fp, isPresent: false),
                       "当前未识别设备 · 上次 DFU")
    }

    func testHostOrMapChangeDoesNotReuseHistory() {
        let (store, url) = store()
        let fp = store.document.slotMapFingerprint
        XCTAssertTrue(store.updateIfEligible(slotID: "S3", product: "Apple Mobile Device (DFU Mode)",
                                             mode: .dfu, ecid: "AA", seenAt: Date(), controller: "c",
                                             portNumber: 1, rid: 0, hostModel: "MacBookPro18,2", fingerprint: fp))
        let other = PortHistoryStore(fileURL: url, hostModel: "Mac14,2", slotMapFingerprint: "other-map")
        XCTAssertNil(other.record(forSlot: "S3"))
        XCTAssertEqual(other.displayStatus(slotID: "S3", hostModel: "Mac14,2", fingerprint: "other-map", isPresent: false),
                       "无设备")
    }

    func testLegacyRight1RID0IsNotS3() {
        // Mapping table: RID 0 + PortNumber 1 is S3 (left upper), not right1.
        let slots = layout().slots
        XCTAssertEqual(slots.first { $0.rid == 0 && $0.portNumber == 1 }?.slot, "S3")
        XCTAssertEqual(slots.first { $0.slot == "S5" }?.rid, 2)
        XCTAssertNotEqual(slots.first { $0.slot == "S3" }?.face, "RIGHT")
    }

    func testCorruptHistoryIsUnavailableButDoesNotThrow() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hist-bad-\(UUID().uuidString).json")
        try Data("not-json".utf8).write(to: url)
        let fp = PortHistoryStore.fingerprint(hostModel: "MacBookPro18,2", layout: layout())
        let store = PortHistoryStore(fileURL: url, hostModel: "MacBookPro18,2", slotMapFingerprint: fp)
        XCTAssertTrue(store.isUnavailable)
        XCTAssertTrue(store.availabilityMessage.contains("不影响发送"))
        XCTAssertNil(store.record(forSlot: "S3"))
    }
}

@MainActor
final class PortHistoryAssociationTests: XCTestCase {
    private func makeDevice(historyURL: URL, ports: [LiveHostPort], layout: BuiltInLayout, selected: String) -> DeviceControlModel {
        let custom = [
            PortCalibrationEntry(physicalPort: "left1", location: "01200000", label: "左侧上方",
                                 rid: "0", side: "左侧", controller: ports[0].controller, portNumber: ports[0].portNumber),
            PortCalibrationEntry(physicalPort: "left2", location: "01100000", label: "左侧下方",
                                 rid: "1", side: "左侧", controller: ports[1].controller, portNumber: ports[1].portNumber),
            PortCalibrationEntry(physicalPort: "right1", location: "02100000", label: "右侧",
                                 rid: "2", side: "右侧", controller: ports[2].controller, portNumber: ports[2].portNumber),
        ]
        let doc = CalibrationDocument(models: [], ports: custom, selectedPort: selected)
        let store = CalibrationStore(testingDocument: doc, hostModel: "MacBookPro18,2", builtInLayout: layout)
        return DeviceControlModel(calibration: store, livePorts: ports, helperAvailable: true,
                                  persistPortSelection: false, startLiveWork: false, historyURL: historyURL)
    }

    private var layout: BuiltInLayout {
        BuiltInLayout(displayName: "M1 Pro", sourceFile: "t.json", slots: [
            BuiltInSlot(slot: "S3", face: "LEFT", portNumber: 1, rid: 0, binding: "MacBookPro18,2|AppleHPMDevice|1|0", physicalName: "左侧上方"),
            BuiltInSlot(slot: "S4", face: "LEFT", portNumber: 2, rid: 1, binding: "MacBookPro18,2|AppleHPMDevice|2|1", physicalName: "左侧下方"),
            BuiltInSlot(slot: "S5", face: "RIGHT", portNumber: 3, rid: 2, binding: "MacBookPro18,2|AppleHPMDevice|3|2", physicalName: "右侧"),
        ], partial: true, skippedSlots: ["S2"], generatedAt: "test")
    }

    private var ports: [LiveHostPort] {
        [
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 1, rid: 0),
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 2, rid: 1),
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 3, rid: 2),
        ]
    }

    private func device(product: String, mode: ObservedDeviceMode, location: String, ecid: String) -> ObservedDevice {
        ObservedDevice(id: "ecid:\(ecid)", ecid: ecid, mode: mode, locationID: location, product: product, serial: "ECID:\(ecid)")
    }

    func testUnboundObservationDoesNotUseSelectionOrListOrder() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("assoc-\(UUID().uuidString).json")
        let model = makeDevice(historyURL: url, ports: ports, layout: layout, selected: ports[2].id)
        let unbound = device(product: "Apple Mobile Device (DFU Mode)", mode: .dfu, location: "0ABC0000", ecid: "DEADBEEF")
        model.applyObservedDevices([unbound], now: Date())
        XCTAssertNil(model.portHistory.record(forSlot: "S3"))
        XCTAssertNil(model.portHistory.record(forSlot: "S4"))
        XCTAssertNil(model.portHistory.record(forSlot: "S5"))
        XCTAssertEqual(model.deviceStatusText(for: ports[2]), "无设备")
    }

    func testSingleValidSendAssociationCanWriteDisplayHistory() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("assoc2-\(UUID().uuidString).json")
        let model = makeDevice(historyURL: url, ports: ports, layout: layout, selected: ports[0].id)
        model.portHistory.recordDFUSend(slotID: "S3", operationID: "op1", sentAt: Date())
        let unbound = device(product: "Apple Mobile Device (DFU Mode)", mode: .dfu, location: "0ABC0000", ecid: "CAFE")
        model.applyObservedDevices([unbound], now: Date())
        XCTAssertEqual(model.portHistory.record(forSlot: "S3")?.lastECID, "CAFE")
        XCTAssertEqual(model.portHistory.record(forSlot: "S4"), nil)
    }

    func testMultiplePendingSendsDoNotGuessTheLastPort() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("assoc3-\(UUID().uuidString).json")
        let model = makeDevice(historyURL: url, ports: ports, layout: layout, selected: ports[0].id)
        let now = Date()
        model.portHistory.recordDFUSend(slotID: "S3", operationID: "op1", sentAt: now)
        model.portHistory.recordDFUSend(slotID: "S5", operationID: "op2", sentAt: now)
        let unbound = device(product: "Apple Mobile Device (DFU Mode)", mode: .dfu, location: "0ABC0000", ecid: "1111")
        model.applyObservedDevices([unbound], now: now)
        XCTAssertNil(model.portHistory.record(forSlot: "S3"))
        XCTAssertNil(model.portHistory.record(forSlot: "S5"))
        XCTAssertTrue(model.canControl)
    }

    func testExpiredAssociationDoesNotWriteHistory() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("assoc4-\(UUID().uuidString).json")
        let model = makeDevice(historyURL: url, ports: ports, layout: layout, selected: ports[0].id)
        model.portHistory.associationWindow = 1
        model.portHistory.recordDFUSend(slotID: "S3", operationID: "op1", sentAt: Date(timeIntervalSinceNow: -30))
        let unbound = device(product: "Apple Mobile Device (DFU Mode)", mode: .dfu, location: "0ABC0000", ecid: "2222")
        model.applyObservedDevices([unbound], now: Date())
        XCTAssertNil(model.portHistory.record(forSlot: "S3"))
    }

    func testCorruptHistoryDoesNotBlockSend() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("assoc5-\(UUID().uuidString).json")
        try? Data("nope".utf8).write(to: url)
        var sent = 0
        let custom = [
            PortCalibrationEntry(physicalPort: "left1", location: "01200000", label: "左侧上方",
                                 rid: "0", side: "左侧", controller: ports[0].controller, portNumber: 1),
        ]
        let doc = CalibrationDocument(models: [], ports: custom, selectedPort: ports[0].id)
        let store = CalibrationStore(testingDocument: doc, hostModel: "MacBookPro18,2", builtInLayout: layout)
        let model = DeviceControlModel(
            calibration: store, livePorts: [ports[0]], helperAvailable: true,
            persistPortSelection: false, startLiveWork: false,
            requestHandler: { action, _, _, _, requestID in
                sent += 1
                return HelperResponse(requestID: requestID, ok: true, dispatchTruth: "REQUEST_SENT",
                                      exitCode: 0, reason: "")
            },
            historyURL: url)
        model.selectPort(ports[0])
        XCTAssertTrue(model.canControl)
        XCTAssertTrue(model.portHistory.isUnavailable)
        model.performReboot()
        let deadline = Date().addingTimeInterval(2)
        while sent == 0 && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(sent, 1)
    }
}

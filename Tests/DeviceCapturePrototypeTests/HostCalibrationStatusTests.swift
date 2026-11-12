import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class HostCalibrationStatusTests: XCTestCase {
    private func layout() -> BuiltInLayout {
        BuiltInLayout(displayName: "M1 Pro", sourceFile: "t.json", slots: [
            BuiltInSlot(slot: "S3", face: "LEFT", portNumber: 1, rid: 0, binding: "MacBookPro18,2|AppleHPMDevice|1|0", physicalName: "左侧上方"),
            BuiltInSlot(slot: "S4", face: "LEFT", portNumber: 2, rid: 1, binding: "MacBookPro18,2|AppleHPMDevice|2|1", physicalName: "左侧下方"),
            BuiltInSlot(slot: "S5", face: "RIGHT", portNumber: 3, rid: 2, binding: "MacBookPro18,2|AppleHPMDevice|3|2", physicalName: "右侧"),
        ], partial: false, skippedSlots: [], generatedAt: "test")
    }

    private func ports() -> [LiveHostPort] {
        [
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 3, rid: 2),
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 2, rid: 1),
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 1, rid: 0),
        ]
    }

    private func makeDevice(host: String,
                            builtin: BuiltInLayout?,
                            layouts: [String: BuiltInLayout]? = nil,
                            ports livePorts: [LiveHostPort]? = nil,
                            shared: [SharedCandidate] = [],
                            overlay: AdoptedCalibrationOverlay? = nil) -> DeviceControlModel {
        let custom = [
            PortCalibrationEntry(physicalPort: "right1", location: "02100000", label: "右侧",
                                 rid: "2", side: "右侧", controller: "AppleHPMDevice", portNumber: 3),
            PortCalibrationEntry(physicalPort: "left2", location: "01100000", label: "左侧下方",
                                 rid: "1", side: "左侧", controller: "AppleHPMDevice", portNumber: 2),
            PortCalibrationEntry(physicalPort: "left1", location: "01200000", label: "左侧上方",
                                 rid: "0", side: "左侧", controller: "AppleHPMDevice", portNumber: 1),
        ]
        let doc = CalibrationDocument(models: [], ports: custom, selectedPort: "AppleHPMDevice:2")
        let store = CalibrationStore(testingDocument: doc, hostModel: host,
                                     builtInLayout: builtin,
                                     builtInLayouts: layouts,
                                     sharedLayoutCandidates: shared)
        store.adoptedOverlay = overlay
        let history = FileManager.default.temporaryDirectory
            .appendingPathComponent("host-status-\(UUID().uuidString).json")
        return DeviceControlModel(calibration: store, livePorts: livePorts ?? ports(), helperAvailable: true,
                                  persistPortSelection: false, startLiveWork: false,
                                  historyURL: history)
    }

    func testExactStatusDoesNotChangeWithSelectedPort() {
        let device = makeDevice(host: "MacBookPro18,2", builtin: layout())
        XCTAssertEqual(device.hostCalibrationSummaryText, "主机 MacBookPro18,2 · 机型已精确校准")
        XCTAssertEqual(device.hostCalibrationLampState, .calibrated)
        XCTAssertEqual(device.hostCalibrationLampState.text, "已校准")
        XCTAssertEqual(device.hostCalibrationLampState.color, "green")
        XCTAssertFalse(device.shouldOfferGoCalibrate)

        for port in device.orderedDisplayPorts {
            device.selectPort(port)
            XCTAssertEqual(device.hostCalibrationSummaryText,
                           "主机 MacBookPro18,2 · 机型已精确校准",
                           "host status must not follow the selected port")
            XCTAssertEqual(device.hostModelCalibrationKind, .exactVerifiedRecord)
            XCTAssertFalse(device.shouldOfferGoCalibrate)
        }
    }

    func testSameMoldAdoptedLayoutIsNotExact() {
        let hostLayout = layout()
        let sameMold = BuiltInLayout(displayName: "M1 Pro 14", sourceFile: "pack", slots: [
            BuiltInSlot(slot: "S1", face: "LEFT", portNumber: 1, rid: 0, binding: "MacBookPro18,3|AppleHPMDevice|1|0", physicalName: "左侧上方"),
        ], partial: false, skippedSlots: [], generatedAt: "pack")
        let overlay = AdoptedCalibrationOverlay(
            source: .appliedLayout,
            sourceHostModel: "MacBookPro18,3",
            sourceFile: "M1Pro-A2442.zip",
            displayName: "Mac Restore Assistant Hardware Preview · MacBookPro18,3",
            layout: sameMold,
            savedAt: "2026-11-11T05:00:00Z")
        let device = makeDevice(host: "MacBookPro18,2",
                                builtin: hostLayout,
                                shared: [SharedCandidate(models: ["MacBookPro18,2", "MacBookPro18,3"], basis: "same mold")],
                                overlay: overlay)
        for port in device.orderedDisplayPorts {
            device.selectPort(port)
            XCTAssertEqual(device.hostCalibrationSummaryText,
                           "主机 MacBookPro18,2 · 未精确校准（沿用同模具布局）")
            XCTAssertEqual(device.hostModelCalibrationKind, .sameMoldLayoutReuse)
            XCTAssertEqual(device.hostCalibrationLampState, .uncalibrated)
            XCTAssertEqual(device.hostCalibrationLampState.text, "未校准")
            XCTAssertEqual(device.hostCalibrationLampState.color, "orange")
            XCTAssertEqual(device.hostCalibrationLampHelp, "正在使用同模具布局，当前机型未经精确校准")
            XCTAssertTrue(device.shouldOfferGoCalibrate)
            XCTAssertEqual(device.goCalibrateSettingsTab, .model)
            XCTAssertFalse(DeviceControlModel.goCalibrateRequiresConfirmation)
        }
    }

    func testUnidentifiedHostStatusIsExplicit() {
        let device = makeDevice(host: "unknown", builtin: nil)
        XCTAssertEqual(device.hostCalibrationSummaryText, "主机机型未识别 · 未校准")
        XCTAssertEqual(device.hostModelCalibrationKind, .unidentified)
        XCTAssertEqual(device.hostCalibrationLampState, .unidentified)
        XCTAssertEqual(device.hostCalibrationLampState.text, "机型未识别")
        XCTAssertEqual(device.hostCalibrationLampState.color, "gray")
        XCTAssertTrue(device.shouldOfferGoCalibrate)
        XCTAssertEqual(device.goCalibrateSettingsTab, .model)
    }

    func testUncalibratedHostStatusIsNotExact() {
        let device = makeDevice(host: "Mac16,10", builtin: nil)
        XCTAssertEqual(device.hostCalibrationSummaryText, "主机 Mac16,10 · 未校准")
        XCTAssertEqual(device.hostModelCalibrationKind, .uncalibrated)
        XCTAssertEqual(device.hostCalibrationLampState, .noModel)
        XCTAssertEqual(device.hostCalibrationLampState.text, "无模型")
        XCTAssertEqual(device.hostCalibrationLampState.color, "gray")
        XCTAssertTrue(device.shouldOfferGoCalibrate)
    }

    func testA2485SameHostPackMatchingBuiltinIsStillExact() {
        // The A2485 report is MacBookPro18,2 with S3/S4/S5 = 1/0,2/1,3/2.
        let overlay = AdoptedCalibrationOverlay(
            source: .appliedLayout,
            sourceHostModel: "MacBookPro18,2",
            sourceFile: "M1 Pro MacBook Pro A2485 16英寸.zip",
            displayName: "M1 Pro MacBook Pro A2485 16英寸",
            layout: layout(),
            savedAt: "2026-11-11T05:00:00Z")
        let device = makeDevice(host: "MacBookPro18,2", builtin: layout(), overlay: overlay)
        XCTAssertTrue(device.hasExactVerifiedHostCalibration)
        XCTAssertEqual(device.hostCalibrationSummaryText, "主机 MacBookPro18,2 · 机型已精确校准")
        XCTAssertFalse(device.shouldOfferGoCalibrate)
    }

    func testLegacyEmptyPreviewToolSaveDoesNotHideBuiltinExact() {
        let staleLayout = BuiltInLayout(displayName: "", sourceFile: "draft.json", slots: [
            BuiltInSlot(slot: "L1", face: "LEFT", portNumber: nil, rid: nil, binding: "", physicalName: "左侧接口1"),
            BuiltInSlot(slot: "L2", face: "LEFT", portNumber: nil, rid: nil, binding: "", physicalName: "左侧接口2"),
            BuiltInSlot(slot: "R1", face: "RIGHT", portNumber: nil, rid: nil, binding: "", physicalName: "右侧接口1"),
        ], partial: false, skippedSlots: [], generatedAt: "2026-11-11T04:44:22+00:00")
        let overlay = AdoptedCalibrationOverlay(
            source: .previewToolSave,
            sourceHostModel: "",
            sourceFile: "draft.json",
            displayName: "",
            layout: staleLayout,
            savedAt: "2026-11-11T04:44:22+00:00")
        XCTAssertFalse(overlay.isUsableEffectiveRecord)
        let device = makeDevice(host: "MacBookPro18,2", builtin: layout(), overlay: overlay)
        XCTAssertTrue(device.hasExactVerifiedHostCalibration)
        XCTAssertEqual(device.hostCalibrationSummaryText, "主机 MacBookPro18,2 · 机型已精确校准")
    }

    func testStaleOverlayFileIsIgnoredOnStoreLoad() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("host-status-file-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let calibrationURL = directory.appendingPathComponent("calibration.json")
        let overlayURL = directory.appendingPathComponent("adopted-layout.json")
        let staleLayout = BuiltInLayout(displayName: "", sourceFile: "draft.json", slots: [
            BuiltInSlot(slot: "L1", face: "LEFT", portNumber: nil, rid: nil, binding: "", physicalName: "左侧接口1"),
        ], partial: false, skippedSlots: [], generatedAt: "")
        let stale = AdoptedCalibrationOverlay(
            source: .previewToolSave,
            sourceHostModel: "",
            sourceFile: "draft.json",
            displayName: "",
            layout: staleLayout,
            savedAt: "")
        try JSONEncoder().encode(stale).write(to: overlayURL, options: .atomic)

        let doc = CalibrationDocument(models: [], ports: [], selectedPort: "")
        let store = CalibrationStore(testingDocument: doc, hostModel: "MacBookPro18,2",
                                     builtInLayout: layout(), fileURL: calibrationURL)
        XCTAssertNil(store.adoptedOverlay, "stale empty previewToolSave must not become effective")
        let device = DeviceControlModel(calibration: store, startLiveWork: false)
        XCTAssertTrue(device.hasExactVerifiedHostCalibration)
        XCTAssertEqual(device.hostCalibrationSummaryText, "主机 MacBookPro18,2 · 机型已精确校准")
    }

    func testSameHostButDifferentMappingIsUncalibratedNotSameMold() {
        let different = BuiltInLayout(displayName: "manual", sourceFile: "", slots: [
            BuiltInSlot(slot: "S3", face: "LEFT", portNumber: 9, rid: 9, binding: "MacBookPro18,2|AppleHPMDevice|9|9", physicalName: "左侧上方"),
        ], partial: false, skippedSlots: [], generatedAt: "2026-11-11T05:00:00Z")
        let overlay = AdoptedCalibrationOverlay(
            source: .appliedLayout,
            sourceHostModel: "MacBookPro18,2",
            sourceFile: "manual.json",
            displayName: "manual",
            layout: different,
            savedAt: "2026-11-11T05:00:00Z")
        let device = makeDevice(host: "MacBookPro18,2", builtin: layout(), overlay: overlay)
        XCTAssertFalse(device.hasExactVerifiedHostCalibration)
        XCTAssertEqual(device.hostCalibrationSummaryText, "主机 MacBookPro18,2 · 未校准")
        XCTAssertTrue(device.shouldOfferGoCalibrate)
    }

    func testOwnerConfirmedSharedLayoutIsReusableButNotCalibrated() {
        let shared = SharedCandidate(
            models: ["MacBookPro18,1", "MacBookPro18,2"],
            basis: "OWNER CONFIRMED: A2485 16-inch same PortNumber/RID mapping",
            confirmed: true)
        let device = makeDevice(host: "MacBookPro18,1", builtin: nil,
                                layouts: ["MacBookPro18,2": layout()],
                                shared: [shared])
        XCTAssertEqual(device.hostModelCalibrationKind, .confirmedSharedLayout)
        XCTAssertEqual(device.hostCalibrationLampState, .uncalibrated)
        XCTAssertEqual(device.hostCalibrationLampState.text, "未校准")
        XCTAssertEqual(device.hostCalibrationLampState.color, "orange")
        XCTAssertEqual(device.hostCalibrationMatchDetail, "共享接口布局（未精确校准）")
        XCTAssertTrue(device.shouldOfferGoCalibrate)
        XCTAssertTrue(device.hostCalibrationSummaryText.contains("未精确校准（沿用已确认共享布局）"))
        // Reuse does not light the calibration lamp and does not follow the selected port.
        for port in device.orderedDisplayPorts {
            device.selectPort(port)
            XCTAssertEqual(device.hostCalibrationLampState, .uncalibrated)
            XCTAssertEqual(device.hostCalibrationMatchDetail, "共享接口布局（未精确校准）")
        }
    }

    func testAirM2ThroughM5ReuseIsConfirmedButNotExact() throws {
        let loaded = BuiltInCalibration.load()
        let airCandidate = try XCTUnwrap(loaded.shared.first {
            $0.confirmed == true && $0.models.contains("Mac14,2") && $0.models.contains("Mac17,4")
        })
        for model in ["Mac14,15", "Mac15,12", "Mac16,13", "Mac17,4"] {
            XCTAssertTrue(airCandidate.models.contains(model), model)
        }
        let doc = CalibrationDocument(models: [], ports: [], selectedPort: "")
        let store = CalibrationStore(
            testingDocument: doc,
            hostModel: "Mac16,13",
            builtInLayout: nil,
            builtInLayouts: loaded.database,
            sharedLayoutCandidates: loaded.shared)
        let device = DeviceControlModel(calibration: store, startLiveWork: false)
        XCTAssertEqual(device.hostModelCalibrationKind, .confirmedSharedLayout)
        XCTAssertEqual(device.hostCalibrationLampState, .uncalibrated)
        XCTAssertTrue(device.shouldOfferGoCalibrate)
    }

    func testSixteenInchM1ProThroughM5MaxReuseIsConfirmed() throws {
        let loaded = BuiltInCalibration.load()
        let candidate = try XCTUnwrap(loaded.shared.first {
            $0.confirmed == true &&
            $0.models.contains("MacBookPro18,1") &&
            $0.models.contains("Mac17,8")
        })
        for model in ["MacBookPro18,2", "Mac14,6", "Mac15,7", "Mac16,5", "Mac17,6"] {
            XCTAssertTrue(candidate.models.contains(model), model)
        }
        XCTAssertTrue(candidate.models.contains("Mac17,10"))
        XCTAssertTrue(candidate.models.contains("Mac17,12"))
        let doc = CalibrationDocument(models: [], ports: [], selectedPort: "")
        let store = CalibrationStore(
            testingDocument: doc,
            hostModel: "Mac17,8",
            builtInLayout: nil,
            builtInLayouts: loaded.database,
            sharedLayoutCandidates: loaded.shared)
        let device = DeviceControlModel(calibration: store, startLiveWork: false)
        XCTAssertEqual(device.hostModelCalibrationKind, .confirmedSharedLayout)
        XCTAssertEqual(device.hostCalibrationLampState, .uncalibrated)
        XCTAssertTrue(device.shouldOfferGoCalibrate)
    }

    func testM3BaseFourteenInchRequiresLayoutUntilTwoPortDataExists() throws {
        let loaded = BuiltInCalibration.load()
        let candidate = try XCTUnwrap(loaded.shared.first {
            $0.confirmed == true &&
            $0.models.contains("Mac15,3")
        })
        XCTAssertFalse(candidate.models.contains("Mac16,1"))
        XCTAssertFalse(candidate.models.contains("Mac17,2"))
        let doc = CalibrationDocument(models: [], ports: [], selectedPort: "")
        let store = CalibrationStore(
            testingDocument: doc,
            hostModel: "Mac15,3",
            builtInLayout: nil,
            builtInLayouts: loaded.database,
            sharedLayoutCandidates: loaded.shared)
        let device = DeviceControlModel(calibration: store, startLiveWork: false)
        XCTAssertEqual(device.hostCalibrationLampState, .noModel)
        XCTAssertTrue(device.shouldOfferGoCalibrate)
    }

    func testM4BaseFourteenInchReusesThreePortLayoutButIsNotExact() throws {
        let loaded = BuiltInCalibration.load()
        let candidate = try XCTUnwrap(loaded.shared.first {
            $0.confirmed == true &&
            $0.models.contains("Mac16,1") &&
            $0.models.contains("Mac16,8")
        })
        XCTAssertTrue(candidate.models.contains("Mac17,2"))
        XCTAssertTrue(candidate.models.contains("Mac17,7"))
        XCTAssertTrue(candidate.models.contains("Mac17,9"))
        XCTAssertTrue(candidate.models.contains("Mac17,11"))
        XCTAssertTrue(candidate.models.contains("Mac17,13"))
        XCTAssertTrue(candidate.models.contains("Mac18,1"))
        let doc = CalibrationDocument(models: [], ports: [], selectedPort: "")
        let store = CalibrationStore(
            testingDocument: doc,
            hostModel: "Mac16,1",
            builtInLayout: nil,
            builtInLayouts: loaded.database,
            sharedLayoutCandidates: loaded.shared)
        let device = DeviceControlModel(calibration: store, startLiveWork: false)
        XCTAssertEqual(device.hostModelCalibrationKind, .confirmedSharedLayout)
        XCTAssertEqual(device.hostCalibrationLampState, .uncalibrated)
        XCTAssertTrue(device.shouldOfferGoCalibrate)
    }

    func testDirectLayoutIsGreenAndSaysDirectMatchRegardlessOfDisplayName() {
        let device = makeDevice(host: "MacBookPro18,2", builtin: layout())
        XCTAssertEqual(device.hostCalibrationLampState, .calibrated)
        XCTAssertEqual(device.hostCalibrationMatchDetail, "本机型直接匹配")
        XCTAssertFalse(device.shouldOfferGoCalibrate)
        // The fixture display name says M1 Pro; the decision is by host id and
        // confirmed layout, not the display name.
        XCTAssertTrue(layout().displayName.contains("M1 Pro"))
    }

    func testExtraChargingHPMNodeDoesNotCreateLayoutConflict() {
        let magsafe = LiveHostPort(controller: "100000829", portNumber: 1, rid: 5)
        let device = makeDevice(host: "MacBookPro18,2", builtin: layout(),
                                ports: ports() + [magsafe])
        XCTAssertFalse(device.hostLayoutMappingConflict)
        XCTAssertEqual(device.hostCalibrationLampState, .calibrated)
        let comparison = device.hostLayoutMappingComparison
        XCTAssertEqual(comparison.expected, ["1:0", "2:1", "3:2"])
        XCTAssertEqual(comparison.actual, ["1:0", "2:1", "3:2"])
        XCTAssertFalse(comparison.actual.contains("1:5"))
        XCTAssertEqual(comparison.sourceFile, "t.json")
        XCTAssertTrue(comparison.layoutName.contains("M1 Pro"))
    }

    func testConfirmedSharedLayoutConflictShowsLayoutReview() {
        let badLayout = BuiltInLayout(displayName: "A2485 shared", sourceFile: "shared.json", slots: [
            BuiltInSlot(slot: "S3", face: "LEFT", portNumber: 1, rid: 0, binding: "MacBookPro18,2|AppleHPMDevice|1|0", physicalName: "左侧上方"),
            BuiltInSlot(slot: "S4", face: "LEFT", portNumber: 2, rid: 1, binding: "MacBookPro18,2|AppleHPMDevice|2|1", physicalName: "左侧下方"),
            BuiltInSlot(slot: "S5", face: "RIGHT", portNumber: 9, rid: 9, binding: "MacBookPro18,2|AppleHPMDevice|9|9", physicalName: "右侧"),
        ], partial: false, skippedSlots: [], generatedAt: "test")
        let shared = SharedCandidate(models: ["MacBookPro18,1", "MacBookPro18,2"],
                                     basis: "OWNER CONFIRMED", confirmed: true)
        let device = makeDevice(host: "MacBookPro18,1", builtin: nil,
                                layouts: ["MacBookPro18,2": badLayout],
                                shared: [shared])
        XCTAssertTrue(device.hostLayoutMappingConflict)
        XCTAssertEqual(device.hostCalibrationLampState, .layoutNeedsReview)
        XCTAssertEqual(device.hostCalibrationLampState.text, "布局待核对")
        XCTAssertEqual(device.hostCalibrationLampState.color, "orange")
        XCTAssertEqual(device.hostCalibrationMatchDetail, "布局待核对")
        XCTAssertTrue(device.hostLayoutMappingConflictDetail.contains("S5 9:9"))
        XCTAssertTrue(device.hostLayoutMappingConflictDetail.contains("3:2"))
        XCTAssertTrue(device.hostLayoutMappingConflictDetail.contains("仅实测"))
        XCTAssertFalse(device.shouldOfferGoCalibrate)
    }

    func testPerPortControllerRIDAndAdoptedSourceStayInPortDetails() {
        let device = makeDevice(host: "MacBookPro18,2", builtin: layout())
        let right = device.orderedDisplayPorts[2]
        device.selectPort(right)
        let hostDetail = device.selectedHostPortDetail
        XCTAssertEqual(hostDetail.controllerText, "AppleHPMDevice")
        XCTAssertEqual(hostDetail.portNumberText, "3")
        XCTAssertEqual(hostDetail.ridText, "2")
        XCTAssertTrue(hostDetail.adoptedCalibrationText.contains("实际采用"))
        // The bottom-line host status remains host-only.
        XCTAssertEqual(device.hostCalibrationSummaryText, "主机 MacBookPro18,2 · 机型已精确校准")
    }
}

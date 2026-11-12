import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class T542CalibrationToolTests: XCTestCase {
    private func layout18_2() -> BuiltInLayout {
        BuiltInLayout(displayName: "M1 Pro 16", sourceFile: "builtin.json", slots: [
            BuiltInSlot(slot: "S3", face: "LEFT", portNumber: 1, rid: 0, binding: "MacBookPro18,2|AppleHPMDevice|1|0", physicalName: "左侧上方"),
            BuiltInSlot(slot: "S4", face: "LEFT", portNumber: 2, rid: 1, binding: "MacBookPro18,2|AppleHPMDevice|2|1", physicalName: "左侧下方"),
            BuiltInSlot(slot: "S5", face: "RIGHT", portNumber: 3, rid: 2, binding: "MacBookPro18,2|AppleHPMDevice|3|2", physicalName: "右侧"),
        ], partial: true, skippedSlots: ["S2"], generatedAt: "builtin")
    }

    private func sameMold() -> [SharedCandidate] {
        [SharedCandidate(models: ["MacBookPro18,2", "MacBookPro18,3"], basis: "same mold")]
    }

    private func makeStore(host: String, builtin: BuiltInLayout?, shared: [SharedCandidate] = []) -> CalibrationStore {
        let doc = CalibrationDocument(models: [], ports: [], selectedPort: "")
        return CalibrationStore(testingDocument: doc, hostModel: host, builtInLayout: builtin, sharedLayoutCandidates: shared)
    }

    private func writeReport(host: String, associations: [String: String], name: String = "report.json") throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("t542-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        let slots = associations.keys.sorted().map { id -> [String: String] in
            ["slot_id": id, "face": "LEFT", "label": "槽位 \(id)"]
        }
        let payload: [String: Any] = [
            "app": "Mac Restore Assistant Hardware Preview",
            "version": "1.7-hardware-preview0.3.2-phase-b.1",
            "host": ["model": host],
            "associations": associations,
            "slots": slots,
            "skipped_slots": [],
            "partial": false,
            "generated_at": "2026-11-11T04:00:00+00:00",
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
        return url
    }

    func testBuiltinExactRemainsWithoutOverlay() {
        let store = makeStore(host: "MacBookPro18,2", builtin: layout18_2(), shared: sameMold())
        let device = DeviceControlModel(calibration: store, startLiveWork: false)
        XCTAssertTrue(device.hasExactVerifiedHostCalibration)
        XCTAssertEqual(device.hostModelCalibrationKind, .exactVerifiedRecord)
        XCTAssertEqual(device.hostCalibrationSummaryText, "主机 MacBookPro18,2 · 机型已精确校准")
        XCTAssertFalse(device.shouldOfferGoCalibrate)
    }

    func testAddingAModelDoesNotBecomeExact() {
        let store = makeStore(host: "MacBookPro18,2", builtin: layout18_2(), shared: sameMold())
        let device = DeviceControlModel(calibration: store, startLiveWork: false)
        store.addHostModel("Mac16,12")
        XCTAssertFalse(device.hasExactVerifiedHostCalibration)
        XCTAssertNotEqual(device.hostCalibrationSummaryText, "主机 MacBookPro18,2 · 机型已精确校准")
        XCTAssertFalse(device.hostCalibrationSummaryText.contains("本机型已精确校准"))
        XCTAssertTrue(device.shouldOfferGoCalibrate)
        XCTAssertEqual(store.adoptedOverlay?.source, .addedModelOnly)
    }

    func testImportingSameMoldPackIsReuseNotExact() throws {
        let store = makeStore(host: "MacBookPro18,2", builtin: layout18_2(), shared: sameMold())
        let device = DeviceControlModel(calibration: store, startLiveWork: false)
        XCTAssertTrue(device.hasExactVerifiedHostCalibration)
        let url = try writeReport(host: "MacBookPro18,3", associations: [
            "S1": "MacBookPro18,3|AppleHPMDevice|1|0",
            "S2": "MacBookPro18,3|AppleHPMDevice|2|1",
            "S3": "MacBookPro18,3|AppleHPMDevice|3|2",
        ], name: "M1Pro-A2442.json")
        _ = try store.importModelPack(from: url)
        store.applyImportedLayout()
        XCTAssertFalse(device.hasExactVerifiedHostCalibration)
        XCTAssertEqual(device.hostModelCalibrationKind, .sameMoldLayoutReuse)
        XCTAssertEqual(device.hostCalibrationSummaryText, "主机 MacBookPro18,2 · 未精确校准（沿用同模具布局）")
        XCTAssertTrue(device.shouldOfferGoCalibrate)
        XCTAssertEqual(store.adoptedOverlay?.source, .appliedLayout)
        XCTAssertEqual(store.adoptedOverlay?.sourceHostModel, "MacBookPro18,3")
        XCTAssertEqual(store.adoptedLayout?.slots.count, 3)
        XCTAssertTrue(store.saveMessage.contains("不会") || store.saveMessage.contains("套用"))
    }

    func testImportingUnrelatedPackIsUncalibratedNotExact() throws {
        let store = makeStore(host: "MacBookPro18,2", builtin: layout18_2(), shared: sameMold())
        let device = DeviceControlModel(calibration: store, startLiveWork: false)
        let url = try writeReport(host: "Mac16,10", associations: [
            "F1": "Mac16,10|AppleHPMDeviceHALType3|5|0",
        ], name: "Mac-mini-M4.json")
        _ = try store.importModelPack(from: url)
        XCTAssertFalse(device.hasExactVerifiedHostCalibration)
        XCTAssertEqual(device.hostModelCalibrationKind, .uncalibrated)
        XCTAssertEqual(device.hostCalibrationSummaryText, "主机 MacBookPro18,2 · 未校准")
        XCTAssertTrue(device.shouldOfferGoCalibrate)
        XCTAssertEqual(store.adoptedOverlay?.source, .importedPack)
    }

    func testReloadAfterSaveReadsAdoptedLayoutBack() throws {
        let store = makeStore(host: "MacBookPro18,2", builtin: layout18_2(), shared: sameMold())
        let url = try writeReport(host: "MacBookPro18,3", associations: [
            "S1": "MacBookPro18,3|AppleHPMDevice|1|0",
        ])
        store.addHostModel("MacBookPro18,3")
        _ = try store.importModelPack(from: url)
        store.applyImportedLayout()
        let file = store.adoptedLayoutFileURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        store.adoptedOverlay = nil
        store.reloadAdoptedOverlayFromDisk()
        XCTAssertEqual(store.adoptedOverlay?.sourceHostModel, "MacBookPro18,3")
        XCTAssertEqual(store.adoptedOverlay?.source, .appliedLayout)
        let device = DeviceControlModel(calibration: store, startLiveWork: false)
        XCTAssertEqual(device.hostCalibrationSummaryText, "主机 MacBookPro18,2 · 未精确校准（沿用同模具布局）")
    }

    func testMramodelpackIsRejectedAsUnsupportedV2Format() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("t542-pack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("sample.mramodelpack")
        try Data("placeholder".utf8).write(to: url)
        let store = makeStore(host: "MacBookPro18,2", builtin: layout18_2())
        XCTAssertThrowsError(try store.importModelPack(from: url)) { error in
            XCTAssertEqual(error as? HardwarePreviewPackError, .unsupportedModelPack)
        }
        XCTAssertNil(store.adoptedOverlay)
    }

    func testIsolatedWalkthroughWithCopiedDesktopSampleIfPresent() throws {
        let original = URL(fileURLWithPath: "/Users/niubanxiandetuzhichakanqi/Desktop/Mac 模型接口 校准数据/M1Pro MacBook Pro A2442 14英寸.zip")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: original.path), "桌面样例包不在本机；跳过复制走通")
        let isolated = FileManager.default.temporaryDirectory.appendingPathComponent("t542-walkthrough-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: isolated, withIntermediateDirectories: true)
        let copied = isolated.appendingPathComponent(original.lastPathComponent)
        try FileManager.default.copyItem(at: original, to: copied)
        let store = makeStore(host: "MacBookPro18,2", builtin: layout18_2(), shared: sameMold())
        let device = DeviceControlModel(calibration: store, startLiveWork: false)
        store.addHostModel("MacBookPro18,3")
        let report = try store.importModelPack(from: copied)
        store.applyImportedLayout()
        XCTAssertEqual(report.hostModel, "MacBookPro18,3")
        XCTAssertEqual(report.version, "1.7-hardware-preview0.3.2-phase-b.1")
        store.reloadAdoptedOverlayFromDisk()
        XCTAssertEqual(store.adoptedOverlay?.sourceHostModel, "MacBookPro18,3")
        XCTAssertFalse(device.hasExactVerifiedHostCalibration)
        XCTAssertEqual(device.hostCalibrationSummaryText, "主机 MacBookPro18,2 · 未精确校准（沿用同模具布局）")
        // Original must still exist and was only copied, not overwritten by this test.
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    func testConfirmedB1PathIfPresent() throws {
        guard let app = CalibrationToolLauncher.resolvedAppURL() else {
            throw XCTSkip("本机没有 B.1 成品路径")
        }
        XCTAssertTrue(CalibrationToolLauncher.isConfirmedB1(at: app))
        XCTAssertEqual(CalibrationToolLauncher.appVersion(at: app), CalibrationToolLauncher.expectedVersion)
        let isolated = CalibrationToolLauncher.previewSupportURL()
        let defaultLibrary = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Yifei.MacFlashAssistantHardwarePreview")
        XCTAssertNotEqual(isolated.standardizedFileURL.path, defaultLibrary.standardizedFileURL.path)
    }

    func testA3401IsInBuiltinModelLibrary() throws {
        let layout = try XCTUnwrap(BuiltInCalibration.load().database["Mac16,8"])
        XCTAssertEqual(layout.displayName, "M4 Pro MacBook Pro 14寸 A3401")
        XCTAssertEqual(layout.slots.map(\.slot), ["L1", "L2", "R1"])
        XCTAssertEqual(layout.slots.map(\.portNumber), [1, 2, 3])
        XCTAssertEqual(layout.slots.map(\.rid), [0, 1, 2])
        XCTAssertFalse(layout.partial)
    }

    func testExportedModelPackCanBeImportedAgain() throws {
        let layout = BuiltInLayout(
            displayName: "M4 Pro MacBook Pro 14寸 A3401",
            sourceFile: "M4 pro 14寸A3401.zip",
            slots: [
                BuiltInSlot(slot: "L1", face: "LEFT", portNumber: 1, rid: 0,
                            binding: "Mac16,8|AppleHPMDeviceHALType3|1|0", physicalName: "左侧 L1"),
                BuiltInSlot(slot: "L2", face: "LEFT", portNumber: 2, rid: 1,
                            binding: "Mac16,8|AppleHPMDeviceHALType3|2|1", physicalName: "左侧 L2"),
                BuiltInSlot(slot: "R1", face: "RIGHT", portNumber: 3, rid: 2,
                            binding: "Mac16,8|AppleHPMDeviceHALType3|3|2", physicalName: "右侧 R1"),
            ],
            partial: false,
            skippedSlots: [],
            generatedAt: "2026-11-12T08:46:42+00:00")
        let store = makeStore(host: "Mac16,8", builtin: layout)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("t542-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("A3401-export.zip")
        let report = try store.exportModelPack(to: destination, layout: layout)
        XCTAssertEqual(report.hostModel, "Mac16,8")
        XCTAssertEqual(report.slots.count, 3)

        let importedStore = makeStore(host: "TestHost", builtin: nil)
        let imported = try importedStore.importModelPack(from: destination)
        XCTAssertEqual(imported.hostModel, "Mac16,8")
        XCTAssertEqual(imported.associations["L1"], "Mac16,8|AppleHPMDeviceHALType3|1|0")
        XCTAssertEqual(imported.associations["R1"], "Mac16,8|AppleHPMDeviceHALType3|3|2")
        XCTAssertEqual(imported.partial, false)
    }
}

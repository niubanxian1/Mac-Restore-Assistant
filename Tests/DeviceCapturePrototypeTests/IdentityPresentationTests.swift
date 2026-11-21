import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class IdentityPresentationTests: XCTestCase {
    private let location = "01100000"

    private func makeModel() -> (DeviceControlModel, LiveHostPort) {
        let port = LiveHostPort(controller: "TestController", portNumber: 1, rid: 0)
        let calibration = PortCalibrationEntry(
            physicalPort: "test-port",
            location: location,
            label: "右侧",
            rid: "0",
            side: "右侧",
            controller: port.controller,
            portNumber: port.portNumber)
        let document = CalibrationDocument(
            models: [],
            ports: [calibration],
            selectedPort: port.id)
        let store = CalibrationStore(
            testingDocument: document,
            hostModel: "MacTest,1",
            builtInLayout: nil)
        let model = DeviceControlModel(
            calibration: store,
            livePorts: [port],
            helperAvailable: true,
            persistPortSelection: false,
            startLiveWork: false)
        model.selectPort(port)
        return (model, port)
    }

    private func observed(
        ecid: String? = nil,
        explicit: String? = nil,
        productType: String? = nil,
        cpid: Int? = nil,
        bdid: Int? = nil,
        cfgutilModel: String? = nil,
        cfgutilLocationMatched: Bool = false,
        registryID: String = "0x100",
        at locationValue: String? = nil
    ) -> ObservedDevice {
        let locationID = locationValue ?? location
        var device = ObservedDevice(
            id: ecid.map { "ecid:\($0)" } ?? "usb:\(locationID):dfu",
            ecid: ecid,
            mode: .dfu,
            locationID: locationID,
            product: "Apple Mobile Device (DFU Mode)",
            serial: ecid.map { "ECID:\($0)" } ?? "")
        device.chipID = cpid
        device.boardID = bdid
        device.registryID = registryID
        device.productType = productType
        device.explicitMachineIdentifierRaw = explicit
        device.cfgutilModelIdentifier = cfgutilModel
        device.cfgutilLocationMatched = cfgutilLocationMatched
        return device
    }

    func testExplicitIdentityProjectsAToLeftRowWithoutChangingControlTarget() {
        let (model, port) = makeModel()
        let selectedBefore = model.selectedLiveKey
        let canControlBefore = model.canControl
        model.applyObservedDevices([
            observed(ecid: "0011223344556677", explicit: "Mac16,8")
        ])
        let observed = try! XCTUnwrap(model.observedDevices.first)
        XCTAssertEqual(model.observedPortKey(for: observed), port.id)

        let projection = model.compactPortIdentity(for: port)
        XCTAssertTrue(projection.firstLine.contains("A3401"))
        XCTAssertTrue(projection.firstLine.contains("2024"))
        XCTAssertTrue(projection.secondLine.contains("DFU"))
        XCTAssertEqual(model.selectedLiveKey, selectedBefore)
        XCTAssertEqual(model.canControl, canControlBefore)
        XCTAssertTrue(model.observedDevices.first?.observationID.contains(":1") == true)
    }

    func testLocationOnlyCandidateProjectsAAndCandidateCount() {
        let (model, port) = makeModel()
        model.applyObservedDevices([
            observed(
                cfgutilModel: "Mac18,2",
                cfgutilLocationMatched: true)
        ])

        let projection = model.compactPortIdentity(for: port)
        XCTAssertTrue(projection.firstLine.contains("A3589"))
        XCTAssertTrue(projection.firstLine.contains("A3590"))
        XCTAssertTrue(projection.firstLine.contains("2026"))
        XCTAssertTrue(projection.secondLine.contains("候选"))
        XCTAssertEqual(model.observedDevices.first?.identityResolution?.state, .candidates)
    }

    func testConflictIsVisibleAndControlTargetRemainsSelected() {
        let (model, port) = makeModel()
        model.applyObservedDevices([
            observed(
                explicit: "Mac16,8",
                cpid: 24640,
                bdid: 6)
        ])
        let projection = model.compactPortIdentity(for: port)
        XCTAssertTrue(projection.firstLine.contains("身份冲突"))
        XCTAssertTrue(projection.secondLine.contains("身份冲突"))
        XCTAssertEqual(model.selectedLiveKey, port.id)
        XCTAssertEqual(
            model.observedDevices.first?.identityResolution?.state,
            .conflict)
    }

    func testSamePortReconnectIncrementsOnlyIdentityGeneration() {
        let (model, port) = makeModel()
        model.applyObservedDevices([
            observed(ecid: "0011223344556677", explicit: "Mac16,8", registryID: "0x100")
        ])
        let first = try! XCTUnwrap(model.observedDevices.first)

        model.applyObservedDevices([
            observed(ecid: "0011223344556677", explicit: "Mac16,7", registryID: "0x200")
        ])
        let second = try! XCTUnwrap(model.observedDevices.first)

        XCTAssertGreaterThan(second.connectionGeneration, first.connectionGeneration)
        XCTAssertNotEqual(second.observationID, first.observationID)
        XCTAssertEqual(second.modelIdentifier, "Mac16,7")
        XCTAssertEqual(model.selectedLiveKey, port.id)
    }

    func testSameECIDHistoryIsRightDetailOnly() {
        let (model, port) = makeModel()
        model.applyObservedDevices([
            observed(ecid: "0011223344556677", explicit: "Mac16,8")
        ])
        model.applyObservedDevices([
            observed(ecid: "0011223344556677")
        ])

        let observed = try! XCTUnwrap(model.observedDevices.first)
        XCTAssertEqual(observed.identityResolution?.state, .historicalHintOnly)
        XCTAssertNil(observed.modelIdentifier)
        let projection = model.compactPortIdentity(for: port)
        XCTAssertTrue(projection.firstLine.contains("A 型号未知"))
        XCTAssertTrue(projection.secondLine.contains("当前无身份证据"))
        let detail = model.selectedPortDetail
        XCTAssertTrue(detail.technicalRows.contains {
            $0.group == "历史提示" && $0.value.contains("Mac16,8")
        })
    }

    func testRightDetailShowsIdentityFieldsAndMissingEvidence() {
        let (model, _) = makeModel()
        model.applyObservedDevices([
            observed(
                ecid: "0011223344556677",
                productType: "iBridge2,14")
        ])
        let detail = model.selectedPortDetail
        let values = Dictionary(
            uniqueKeysWithValues: detail.technicalRows.map { ($0.name, $0.value) })
        XCTAssertEqual(values["A 型号"], "A2141")
        XCTAssertEqual(values["年份"], "2019")
        XCTAssertTrue(values["机型标识符"]?.contains("MacBookPro16,1") == true)
        XCTAssertTrue(values["iBridge"]?.contains("iBridge2,14") == true)
        XCTAssertEqual(values["CPID"], "未读取")
        XCTAssertEqual(values["BDID"], "未读取")
        XCTAssertEqual(values["ECID"], "0011223344556677")
    }

    func testPortListUsesEvidencePriorityWithoutChangingFixedControlOrder() {
        let store = UIFixture.makeCalibrationStore()
        let model = UIFixture.makeDevice(store: store)
        let fixed = model.orderedDisplayPorts.map { model.label(for: $0) }
        XCTAssertEqual(fixed, ["左侧上方", "左侧下方", "右侧"])

        let lower = observed(
            ecid: "0011223344556677",
            explicit: "Mac16,8",
            at: "01100000")
        let right = ObservedDevice(
            id: "ecid:00AABBCCDDEEFF00",
            ecid: "00AABBCCDDEEFF00",
            mode: .connected,
            locationID: "02100000",
            product: "Mac",
            serial: "ECID:00AABBCCDDEEFF00")
        model.applyObservedDevices([lower, right])

        XCTAssertEqual(
            model.priorityOrderedDisplayPorts.map { model.label(for: $0) },
            ["左侧下方", "右侧", "左侧上方"])
        XCTAssertEqual(
            model.priorityOrderedDisplayPorts.map {
                model.portListPriority(for: $0)
            },
            [.identifiedMac, .unknownMac, .noDevice])
        XCTAssertEqual(
            model.readonlyMainPortLabel(forUSBlocation: "0x01100000"),
            "左侧下方")
        XCTAssertNil(model.readonlyMainPortLabel(forUSBlocation: "0x09900000"))
    }
}

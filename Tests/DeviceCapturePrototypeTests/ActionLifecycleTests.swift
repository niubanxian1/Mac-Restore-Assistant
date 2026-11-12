import XCTest
@testable import DeviceCapturePrototype
import MRAHelperProtocol
import Foundation

@MainActor
final class ActionLifecycleTests: XCTestCase {
    private let portA = LiveHostPort(controller: "100000813", portNumber: 1, rid: 0)
    private let portB = LiveHostPort(controller: "10000081e", portNumber: 3, rid: 2)
    private let slotS3 = LiveHostPort(controller: "100000834", portNumber: 1, rid: 0)
    private let slotS5 = LiveHostPort(controller: "10000081e", portNumber: 3, rid: 2)

    func testSendTimeoutUnlocksAndDoesNotClaimDeviceSuccess() async throws {
        let pending = PendingResponses()
        defer { pending.completeAll() }
        let device = makeModel(ports: [portA], selected: portA.id, timeout: 0.2) { _, _, _, _, id in
            await pending.hang(id)
        }
        let frozenKey = device.selectedLiveKey
        XCTAssertTrue(device.canControl)
        device.performReboot()
        XCTAssertTrue(device.actionInFlight)
        XCTAssertFalse(device.canControl)
        XCTAssertFalse(device.canChangePortSelection)
        XCTAssertEqual(device.feedback.tone, .working)

        try await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertFalse(device.actionInFlight)
        XCTAssertTrue(device.canControl)
        XCTAssertTrue(device.canChangePortSelection)
        XCTAssertEqual(device.feedback.title, "请求超时，结果未确认")
        XCTAssertEqual(device.feedback.tone, .failure)
        XCTAssertTrue(device.feedback.detail.contains("未认定设备成功"))
        XCTAssertTrue(device.lastActionLog.contains("SEND_TIMEOUT"))
        XCTAssertEqual(device.selectedLiveKey, frozenKey)
    }

    func testSendTimeoutDoesNotAutoResend() async throws {
        let pending = PendingResponses()
        defer { pending.completeAll() }
        var sendCount = 0
        let device = makeModel(ports: [portA], selected: portA.id, timeout: 0.2) { _, _, _, _, id in
            sendCount += 1
            return await pending.hang(id)
        }
        device.performReboot()
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(device.feedback.title, "请求超时，结果未确认")
        XCTAssertEqual(sendCount, 1)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(sendCount, 1, "timeout must not auto-resend")
        XCTAssertFalse(device.actionInFlight)
    }

    func testLateResponseAfterTimeoutIsIgnored() async throws {
        let pending = PendingResponses()
        let device = makeModel(ports: [portA], selected: portA.id, timeout: 0.2) { _, _, _, _, id in
            await pending.hang(id)
        }
        device.performReboot()
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(device.feedback.title, "请求超时，结果未确认")

        pending.completeAll(ok: true, truth: "REQUEST_SENT")
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(device.feedback.title, "请求超时，结果未确认")
        XCTAssertFalse(device.feedback.title.contains("请求已发送"))
        XCTAssertTrue(device.lastActionLog.contains("ignored late response"))
        XCTAssertFalse(device.actionInFlight)
        XCTAssertTrue(device.canControl)
    }

    func testDFUSequenceTimeoutIgnoresBothLateSendsWhenBothAlreadyDispatched() async throws {
        let pending = PendingResponses()
        let device = makeModel(ports: [portA], selected: portA.id, timeout: 0.35, delay: 0.05) { _, _, _, _, id in
            await pending.hang(id)
        }
        device.performDFU()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(pending.count, 2, "with timeout > delay both sends should already be in flight")
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertFalse(device.actionInFlight)
        XCTAssertEqual(device.feedback.title, "请求超时，结果未确认")

        pending.completeAll(ok: true, truth: "REQUEST_SENT")
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(device.feedback.title, "请求超时，结果未确认")
        XCTAssertTrue(device.lastActionLog.contains("ignored late response"))
        XCTAssertFalse(device.actionInFlight)
        XCTAssertTrue(device.canControl)
    }

    func testShortTimeoutCancelsPendingSecondDFUSend() async throws {
        let pending = PendingResponses()
        defer { pending.completeAll() }
        var sendIDs: [String] = []
        let device = makeModel(ports: [portA], selected: portA.id, timeout: 0.2, delay: 1.5) { _, _, _, _, id in
            sendIDs.append(id)
            return await pending.hang(id)
        }
        device.performDFU()
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(device.feedback.title, "请求超时，结果未确认")
        XCTAssertFalse(device.actionInFlight)
        XCTAssertEqual(sendIDs.count, 1, "second send must be cancelled when timeout occurs before +1500ms")
        try await Task.sleep(nanoseconds: 1_700_000_000)
        XCTAssertEqual(sendIDs.count, 1, "no send may occur after the terminal timeout state")
        XCTAssertEqual(device.feedback.title, "请求超时，结果未确认")
    }

    func testFastSuccessIsNotOverwrittenByTimeout() async throws {
        let device = makeModel(ports: [portA], selected: portA.id, timeout: 0.35) { _, _, _, _, id in
            HelperResponse(requestID: id, ok: true, dispatchTruth: "REQUEST_SENT",
                           exitCode: 0, reason: "")
        }
        device.performReboot()
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(device.feedback.title, "请求已发送 · 结果未确认")
        XCTAssertFalse(device.actionInFlight)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(device.feedback.title, "请求已发送 · 结果未确认")
        XCTAssertFalse(device.lastActionLog.contains("SEND_TIMEOUT"))
    }

    func testSelectPortDuringInFlightIsIgnored() async throws {
        let pending = PendingResponses()
        defer { pending.completeAll() }
        let device = makeModel(ports: [portA, portB], selected: portA.id, timeout: 0.4) { _, _, _, _, id in
            await pending.hang(id)
        }
        device.performReboot()
        let title = device.feedback.title
        let key = device.selectedLiveKey
        XCTAssertEqual(key, portA.id)
        XCTAssertTrue(device.actionInFlight)

        device.selectPort(portB)
        XCTAssertEqual(device.selectedLiveKey, key)
        XCTAssertEqual(device.feedback.title, title)
        XCTAssertTrue(device.lastActionLog.contains("ignored port selection during in-flight action"))

        device.applyDiscoveredPorts([portB, portA], persistCalibration: false)
        XCTAssertEqual(device.selectedLiveKey, key)
    }

    func testDoesNotAutoSelectWhenMultipleMappedPortsExist() {
        let device = makeModel(ports: [portA, portB], selected: "")
        XCTAssertEqual(device.selectedLiveKey, "")
        XCTAssertNil(device.selectedLivePort)
        XCTAssertTrue(device.mappingNote.contains("不会按列表顺序猜测"))
        XCTAssertFalse(device.portUsable)
        XCTAssertFalse(device.canControl)
    }

    func testPreferredUniquePortIsKeptWhenSeveralAreMapped() {
        let device = makeModel(ports: [portA, portB], selected: portB.id)
        XCTAssertEqual(device.selectedLiveKey, portB.id)
        XCTAssertTrue(device.portUsable)
        XCTAssertTrue(device.canControl)
    }

    func testPortOrderChangeDoesNotAffectSavedTarget() {
        let device = makeModel(ports: [portA, portB], selected: portB.id)
        XCTAssertEqual(device.selectedLiveKey, portB.id)
        device.applyDiscoveredPorts([portB, portA], persistCalibration: false)
        XCTAssertEqual(device.selectedLiveKey, portB.id)
        device.applyDiscoveredPorts([portA, portB], persistCalibration: false)
        XCTAssertEqual(device.selectedLiveKey, portB.id)
        XCTAssertEqual(device.selectedLivePort?.controller, portB.controller)
        XCTAssertEqual(device.selectedLivePort?.portNumber, portB.portNumber)
        XCTAssertEqual(device.selectedLivePort?.rid, portB.rid)
    }

    func testPreferredPortDisappearsDoesNotSelectFirstRemaining() {
        let unmatched = LiveHostPort(controller: "100000900", portNumber: 9, rid: 9)
        let device = makeModel(ports: [portA, portB], selected: portB.id)
        XCTAssertEqual(device.selectedLiveKey, portB.id)
        device.applyDiscoveredPorts([portA, unmatched], persistCalibration: false)
        XCTAssertEqual(device.selectedLiveKey, "", "missing preferred port must not be replaced by the first remaining mapped port")
        XCTAssertNil(device.selectedLivePort)
        XCTAssertTrue(device.mappingNote.contains("不会按列表顺序猜测") || device.mappingNote.contains("人工确认"))
        XCTAssertFalse(device.canControl)
    }

    func testSingleMappedPortIsAutoSelected() {
        let unmatched = LiveHostPort(controller: "100000900", portNumber: 9, rid: 9)
        let device = makeModel(ports: [portA, unmatched], selected: "")
        XCTAssertEqual(device.selectedLiveKey, portA.id)
        XCTAssertTrue(device.canControl)
    }

    func testAmbiguousBuiltInSlotIsFailClosed() {
        let layout = BuiltInLayout(
            displayName: "Test Layout", sourceFile: "test.json",
            slots: [BuiltInSlot(slot: "S3", face: "LEFT", portNumber: 1, rid: 0,
                                binding: "port+rid", physicalName: "左下")],
            partial: false, skippedSlots: [], generatedAt: "test")
        let twin = LiveHostPort(controller: "100000999", portNumber: 1, rid: 0)
        let device = makeModel(ports: [portA, twin], custom: [], selected: "", layout: layout)
        XCTAssertNil(device.uniquelyMappedBuiltInSlot(for: portA))
        XCTAssertNil(device.uniquelyMappedBuiltInSlot(for: twin))
        XCTAssertEqual(device.selectedLiveKey, "")
        XCTAssertTrue(device.mappingNote.contains("不会按列表顺序猜测"))
    }

    func testAmbiguousLegacyRIDIsNotAutoSelected() {
        let custom = [PortCalibrationEntry(
            physicalPort: "left2", location: "01100000", label: "左侧下方",
            rid: "0", side: "左侧")]
        let twin = LiveHostPort(controller: "100000999", portNumber: 8, rid: 0)
        let device = makeModel(ports: [portA, twin], custom: custom, selected: "left2")
        XCTAssertEqual(device.selectedLiveKey, "")
        XCTAssertFalse(device.isMapped(portA))
        XCTAssertFalse(device.isMapped(twin))
    }

    func testIncompleteIdentityIsRejected() {
        let incomplete = LiveHostPort(controller: "", portNumber: 1, rid: 0)
        let custom = [PortCalibrationEntry(
            physicalPort: "left2", location: "01100000", label: "左侧下方",
            rid: "0", side: "左侧", controller: "", portNumber: 1)]
        let device = makeModel(ports: [incomplete], custom: custom, selected: "")
        XCTAssertFalse(device.isCompleteUniqueTarget(incomplete))
        XCTAssertEqual(device.selectedLiveKey, "")
        device.selectPort(incomplete)
        XCTAssertEqual(device.selectedLiveKey, "")
        XCTAssertEqual(device.feedback.title, "未选择端口")
        XCTAssertTrue(device.feedback.detail.contains("不会按列表顺序猜测"))
        XCTAssertFalse(device.portUsable)
    }

    func testManualSelectRequiresCompleteUniqueMappedPort() {
        let device = makeModel(ports: [portA, portB], selected: "")
        device.selectPort(portA)
        XCTAssertEqual(device.selectedLiveKey, portA.id)
        XCTAssertEqual(device.feedback.title, device.portSwitchFeedbackTitle(for: portA))
        XCTAssertTrue(device.feedback.title.hasPrefix("操作目标已切换："))
        XCTAssertTrue(device.canControl)
    }

    func testLegacyRight1RID0DoesNotMapToS3() {
        let custom = [PortCalibrationEntry(
            physicalPort: "right1", location: "02100000", label: "右侧",
            rid: "0", side: "右侧")]
        let layout = BuiltInLayout(
            displayName: "M1 Pro MacBook Pro A2485 16英寸", sourceFile: "test.json",
            slots: [
                BuiltInSlot(slot: "S3", face: "LEFT", portNumber: 1, rid: 0,
                            binding: "MacBookPro18,2|AppleHPMDevice|1|0", physicalName: "左侧上方"),
                BuiltInSlot(slot: "S4", face: "LEFT", portNumber: 2, rid: 1,
                            binding: "MacBookPro18,2|AppleHPMDevice|2|1", physicalName: "左侧下方"),
                BuiltInSlot(slot: "S5", face: "RIGHT", portNumber: 3, rid: 2,
                            binding: "MacBookPro18,2|AppleHPMDevice|3|2", physicalName: "右侧"),
            ],
            partial: false, skippedSlots: [], generatedAt: "test")
        let device = makeModel(ports: [slotS3, slotS5], custom: custom, selected: "right1", layout: layout)
        let right = device.calibration.ports.first { $0.physicalPort == "right1" }
        XCTAssertEqual(right?.rid, "2", "old right1 RID 0 must be migrated away from S3")
        XCTAssertNotEqual(device.selectedLiveKey, slotS3.id)
        XCTAssertNotEqual(device.selectedLivePort?.rid, 0)
        XCTAssertNotEqual(device.selectedLivePort?.portNumber, 1)
        if let live = device.selectedLivePort {
            XCTAssertEqual(live.id, slotS5.id)
            XCTAssertEqual(live.rid, 2)
            XCTAssertEqual(live.portNumber, 3)
        }
        let note = device.calibration.saveMessage + device.mappingNote
        XCTAssertTrue(note.contains("RID 0") || note.contains("迁移"),
                      "loading the old row must migrate or show an explicit prompt; note was: \(note)")
        XCTAssertFalse(device.isMapped(slotS3) && device.selectedLiveKey == slotS3.id)
    }

    // MARK: - Fixtures

    private func defaultCustom() -> [PortCalibrationEntry] {
        [
            PortCalibrationEntry(physicalPort: "left2", location: "01100000", label: "左侧下方",
                                 rid: "0", side: "左侧", controller: portA.controller, portNumber: portA.portNumber),
            PortCalibrationEntry(physicalPort: "right1", location: "02100000", label: "右侧",
                                 rid: "2", side: "右侧", controller: portB.controller, portNumber: portB.portNumber),
        ]
    }

    private func makeModel(ports: [LiveHostPort],
                           custom: [PortCalibrationEntry]? = nil,
                           selected: String,
                           layout: BuiltInLayout? = nil,
                           timeout: TimeInterval = 10,
                           delay: TimeInterval = 0.05,
                           handler: DeviceControlModel.HelperRequestHandler? = nil) -> DeviceControlModel {
        let doc = CalibrationDocument(models: [], ports: custom ?? defaultCustom(), selectedPort: selected)
        let store = CalibrationStore(testingDocument: doc, hostModel: "TestHost", builtInLayout: layout)
        return DeviceControlModel(
            calibration: store,
            livePorts: ports,
            helperAvailable: true,
            sendTimeout: timeout,
            sequenceDelaySeconds: delay,
            persistPortSelection: false,
            startLiveWork: false,
            requestHandler: handler
        )
    }
}

@MainActor
final class PendingResponses {
    private var waiting: [(String, CheckedContinuation<HelperResponse, Never>)] = []

    var count: Int { waiting.count }

    func hang(_ requestID: String) async -> HelperResponse {
        await withCheckedContinuation { waiting.append((requestID, $0)) }
    }

    func completeAll(ok: Bool = true, truth: String = "REQUEST_SENT") {
        let pending = waiting
        waiting.removeAll()
        for (id, continuation) in pending {
            continuation.resume(returning: HelperResponse(
                requestID: id, ok: ok, dispatchTruth: truth, exitCode: 0, reason: ""))
        }
    }
}

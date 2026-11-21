import XCTest
@testable import DeviceCapturePrototype
import MRAHelperProtocol

@MainActor
final class DualSendSequenceAcceptanceTests: XCTestCase {
    private let port = AcceptanceFixtures.slotS5

    /// T06 — Dual-send is exactly two, never a third, including after timeout/late response.
    func testDualSendIsExactlyTwoNeverAThird() async throws {
        let pending = AcceptancePendingResponses()
        var sends: [RecordedSend] = []
        let device = AcceptanceModels.makeModel(
            ports: [port], selected: port.id, timeout: 0.4, delay: 0.05
        ) { action, controller, portNumber, rid, id in
            sends.append(RecordedSend(action: action, controller: controller,
                                      portNumber: portNumber, rid: rid,
                                      requestID: id, at: Date()))
            return await pending.hang(id)
        }
        device.performDFU()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(sends.count, 2, "both planned sends should already be in flight")
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertFalse(device.actionInFlight)
        XCTAssertEqual(device.feedback.title, "请求超时，结果未确认")
        XCTAssertEqual(sends.count, 2)

        pending.completeAll(ok: true, truth: "REQUEST_SENT")
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(sends.count, 2, "late success must not cause a third send")
        XCTAssertEqual(device.feedback.title, "请求超时，结果未确认")
        XCTAssertEqual(Set(sends.map(\.controller)), [port.controller])
        XCTAssertEqual(Set(sends.map(\.portNumber)), [port.portNumber])
        XCTAssertEqual(Set(sends.map(\.rid)), [port.rid])
        XCTAssertEqual(Set(sends.map(\.action)), [.dfu])
    }

    /// T07 — Second send is scheduled ~1500 ms from the first send's start.
    func testSecondSendScheduledAbout1500msFromFirstStart() async throws {
        var sends: [RecordedSend] = []
        let device = AcceptanceModels.makeModel(
            ports: [port], selected: port.id,
            timeout: DeviceControlModel.defaultSendTimeout,
            delay: 1.5
        ) { action, controller, portNumber, rid, id in
            sends.append(RecordedSend(action: action, controller: controller,
                                      portNumber: portNumber, rid: rid,
                                      requestID: id, at: Date()))
            return HelperResponse(requestID: id, ok: true, dispatchTruth: "REQUEST_SENT",
                                  exitCode: 0, reason: "")
        }
        device.performDFU()
        try await Task.sleep(nanoseconds: 2_200_000_000)
        XCTAssertEqual(sends.count, 2, "default 10s timeout must still allow both planned shots")
        let gap = sends[1].at.timeIntervalSince(sends[0].at)
        XCTAssertGreaterThanOrEqual(gap, 1.30, "second start - first start was \(gap)")
        XCTAssertLessThanOrEqual(gap, 2.20, "second start - first start was \(gap)")
        XCTAssertFalse(device.actionInFlight)
        XCTAssertEqual(sends[0].controller, port.controller)
        XCTAssertEqual(sends[0].portNumber, port.portNumber)
        XCTAssertEqual(sends[0].rid, port.rid)
        XCTAssertEqual(sends[1].controller, port.controller)
        XCTAssertEqual(sends[1].portNumber, port.portNumber)
        XCTAssertEqual(sends[1].rid, port.rid)
    }

    /// T07 companion — the default 10s timeout is long enough for both planned shots.
    func testDefaultTimeoutAllowsBothPlannedSends() async throws {
        XCTAssertEqual(DeviceControlModel.defaultSendTimeout, 10)
        var sendCount = 0
        let device = AcceptanceModels.makeModel(
            ports: [port], selected: port.id,
            timeout: DeviceControlModel.defaultSendTimeout,
            delay: 1.5
        ) { _, _, _, _, id in
            sendCount += 1
            return HelperResponse(requestID: id, ok: true, dispatchTruth: "REQUEST_SENT",
                                  exitCode: 0, reason: "")
        }
        device.performDFU()
        try await Task.sleep(nanoseconds: 2_200_000_000)
        XCTAssertEqual(sendCount, 2)
        XCTAssertFalse(device.lastActionLog.contains("SEND_TIMEOUT"))
        XCTAssertFalse(device.actionInFlight)
    }

    /// CANCEL_PENDING_SECOND_SEND_IF_ALREADY_TERMINAL
    func testPendingSecondSendIsCancelledIfAlreadyTerminal() async throws {
        let pending = AcceptancePendingResponses()
        defer { pending.completeAll() }
        var sendIDs: [String] = []
        let device = AcceptanceModels.makeModel(
            ports: [port], selected: port.id, timeout: 0.2, delay: 1.5
        ) { _, _, _, _, id in
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
}

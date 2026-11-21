import XCTest
@testable import DeviceCapturePrototype
import MRAHelperProtocol

@MainActor
final class HelperRoundTripTimeoutTests: XCTestCase {
    private let port = AcceptanceFixtures.slotS5

    /// T01 — If Helper never returns, the App unlocks after a bounded timeout.
    func testHungHelperRoundTripUnlocksAfterTimeout() async throws {
        let pending = AcceptancePendingResponses()
        defer { pending.completeAll() }
        let device = AcceptanceModels.makeModel(
            ports: [port], selected: port.id, timeout: 0.2
        ) { _, _, _, _, id in
            await pending.hang(id)
        }
        let frozenKey = device.selectedLiveKey
        XCTAssertTrue(device.canControl)
        device.performReboot()
        XCTAssertTrue(device.actionInFlight)
        XCTAssertFalse(device.canControl)
        XCTAssertFalse(device.canChangePortSelection)

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

    /// T02 — Timeout must not auto-resend.
    func testTimeoutDoesNotAutoResend() async throws {
        let pending = AcceptancePendingResponses()
        defer { pending.completeAll() }
        var sendCount = 0
        let device = AcceptanceModels.makeModel(
            ports: [port], selected: port.id, timeout: 0.2
        ) { _, _, _, _, id in
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

    /// T03 — A late Helper success must not overwrite the timeout terminal state.
    func testLateResponseDoesNotOverwriteTimeoutTerminalState() async throws {
        let pending = AcceptancePendingResponses()
        let device = AcceptanceModels.makeModel(
            ports: [port], selected: port.id, timeout: 0.2
        ) { _, _, _, _, id in
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
}

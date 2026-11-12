import XCTest
@testable import DeviceCapturePrototype
import MRAHelperProtocol
import Foundation

final class RecoveryFailurePresentationTests: XCTestCase {
    private func response(stdout: String, stderr: String = "", exit: Int32? = 1) -> HelperResponse {
        HelperResponse(requestID: "42E5F711-79CF-4EBE-8871-675A61B8639F",
                       ok: false, dispatchTruth: "NOT_DISPATCHED", exitCode: exit,
                       reason: "BACKEND_FAILED", stdout: stdout, stderr: stderr,
                       helperVersion: "0.2.5")
    }

    func testReceiptAfterProgressTextIsParsed() {
        let text = "Rebooting target into DFU mode... {\"send_performed\":true,\"status\":\"BLOCKED\",\"reason\":\"DFU_COMMAND_FAILED\"}\nFailed to send VDM"
        let receipt = BackendActionReceipt.parse(stdout: text)
        XCTAssertEqual(receipt?.reason, "DFU_COMMAND_FAILED")
        XCTAssertEqual(receipt?.status, "BLOCKED")
    }

    func testPreSendRejectionUsesBackendJSONAndDoesNotClaimSent() {
        let stdout = """
        Preparing target...
        {"rid_selective":true,"requested_rid":1,"candidate_service_count":0,"selected_rid":-1,"built_in":false,"port_usb_c":false,"send_performed":false,"status":"BLOCKED","reason":"PRE_BOUNDARY_FAILURE","dfu_success":false}
        """
        let diagnosis = RecoveryFailurePresentation.make(for: response(stdout: stdout, exit: 2))
        XCTAssertEqual(diagnosis.phase, "发送前被拒绝")
        XCTAssertEqual(diagnosis.isDispatched, false)
        XCTAssertEqual(diagnosis.title, "发送前被拒绝")
        XCTAssertTrue(diagnosis.sentence.contains("未发送"))
        XCTAssertFalse(diagnosis.sentence.contains("动作已开始"))
        XCTAssertTrue(diagnosis.technical.contains("exit=2"))
        XCTAssertTrue(diagnosis.technical.contains("status=BLOCKED"))
        XCTAssertTrue(diagnosis.technical.contains("send_performed=false"))
        XCTAssertTrue(diagnosis.technical.contains("PRE_BOUNDARY_FAILURE"))
        XCTAssertTrue(diagnosis.technical.contains("stdout=Preparing target"))
    }

    func testPostDispatchFailureIsNotReportedAsNotDispatched() {
        let stdout = """
        Putting target into serial mode... OK
        {"rid_selective":true,"requested_rid":1,"candidate_service_count":1,"selected_rid":1,"built_in":false,"port_usb_c":false,"send_performed":true,"status":"BLOCKED","reason":"RECOVERY_COMMAND_FAILED","dfu_success":false}
        """
        let diagnosis = RecoveryFailurePresentation.make(for: response(stdout: stdout))
        XCTAssertEqual(diagnosis.phase, "动作已开始、后续失败")
        XCTAssertEqual(diagnosis.isDispatched, true)
        XCTAssertEqual(diagnosis.title, "已发送 · 后续失败")
        XCTAssertTrue(diagnosis.sentence.contains("动作已开始"))
        XCTAssertFalse(diagnosis.sentence.contains("未发送"))
        XCTAssertTrue(diagnosis.technical.contains("send_performed=true"))
        XCTAssertTrue(diagnosis.technical.contains("RECOVERY_COMMAND_FAILED"))
        XCTAssertTrue(diagnosis.technical.contains("candidate_service_count=1"))
    }

    func testFalseSendPerformedWithRecoveryCommandFailureIsNotPreSend() {
        let stdout = """
        Rebooting target into normal mode... OK
        Waiting for connection.... Connected
        Putting target into serial mode... OK
        Putting local end into serial mode... Failed (DVEn return=-1, IOKit=0x08, write=0x00, reg9=-1 invalid).
        {"rid_selective":true,"requested_rid":1,"candidate_service_count":1,"selected_rid":1,"built_in":true,"port_usb_c":true,"send_performed":false,"status":"BLOCKED","reason":"RECOVERY_COMMAND_FAILED","dfu_success":false}
        """
        let diagnosis = RecoveryFailurePresentation.make(for: response(stdout: stdout, exit: 1))
        XCTAssertEqual(diagnosis.phase, "主机端串口启用失败；恢复界面未确认")
        XCTAssertNil(diagnosis.isDispatched)
        XCTAssertEqual(diagnosis.title, "目标已提交 · 主机端串口启用失败")
        XCTAssertEqual(diagnosis.sentence, "目标重启与 serial 步骤已提交；主机端串口启用失败；恢复界面未确认")
        XCTAssertFalse(diagnosis.sentence.contains("发送前被拒绝"))
        XCTAssertFalse(diagnosis.sentence.contains("已进入恢复"))
        XCTAssertTrue(diagnosis.technical.contains("Rebooting target into normal mode"))
        XCTAssertTrue(diagnosis.technical.contains("dv_en="))
        XCTAssertTrue(diagnosis.technical.contains("DVEn return=-1"))
        XCTAssertTrue(diagnosis.technical.contains("send_performed=false"))
        XCTAssertTrue(diagnosis.technical.contains("Rebooting target into normal mode"))
    }

    func testExplicitPreBoundaryReasonStillMeansNotSent() {
        let stdout = """
        {"rid_selective":true,"requested_rid":1,"candidate_service_count":0,"selected_rid":-1,"send_performed":false,"status":"BLOCKED","reason":"PRE_BOUNDARY_FAILURE"}
        """
        let diagnosis = RecoveryFailurePresentation.make(for: response(stdout: stdout, exit: 2))
        XCTAssertEqual(diagnosis.phase, "发送前被拒绝")
        XCTAssertEqual(diagnosis.isDispatched, false)
        XCTAssertTrue(diagnosis.sentence.contains("未发送"))
    }

    func testMissingReceiptIsRecordedAsUnknownNotAsNotDispatched() {
        let diagnosis = RecoveryFailurePresentation.make(for: response(stdout: "", exit: 1))
        XCTAssertEqual(diagnosis.phase, "发送状态未确认")
        XCTAssertNil(diagnosis.isDispatched)
        XCTAssertEqual(diagnosis.title, "结果未确认")
        XCTAssertTrue(diagnosis.sentence.contains("本次原因未取得"))
        XCTAssertFalse(diagnosis.sentence.contains("未发送"))
        XCTAssertTrue(diagnosis.technical.contains("stdout="))
        XCTAssertTrue(diagnosis.technical.contains("stderr="))
    }
}

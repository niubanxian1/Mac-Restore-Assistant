import Foundation
import MRAHelperProtocol

/// The backend writes its authoritative result as one JSON line on stdout.
/// Helper currently collapses a non-zero backend exit with empty stderr into
/// `BACKEND_FAILED`; this parser lets the App recover the real phase/reason.
struct BackendActionReceipt: Equatable {
    var status: String?
    var reason: String?
    var sendPerformed: Bool?
    var ridSelective: Bool?
    var requestedRID: Int?
    var selectedRID: Int?
    var candidateServiceCount: Int?
    var rawJSON: String

    static func parse(stdout: String) -> BackendActionReceipt? {
        for line in stdout.split(separator: "\n").reversed() {
            guard let start = line.firstIndex(of: "{"), let end = line.lastIndex(of: "}"), start <= end else { continue }
            let trimmed = String(line[start...end])
            guard
                  let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            return BackendActionReceipt(
                status: object["status"] as? String,
                reason: object["reason"] as? String,
                sendPerformed: object["send_performed"] as? Bool,
                ridSelective: object["rid_selective"] as? Bool,
                requestedRID: object["requested_rid"] as? Int,
                selectedRID: object["selected_rid"] as? Int,
                candidateServiceCount: object["candidate_service_count"] as? Int,
                rawJSON: trimmed)
        }
        return nil
    }
}

struct RecoveryFailurePresentation: Equatable {
    var title: String
    var sentence: String
    var phase: String
    var technical: String
    var isDispatched: Bool?

    static func make(for response: HelperResponse) -> RecoveryFailurePresentation {
        let receipt = BackendActionReceipt.parse(stdout: response.stdout)
        let sendState = receipt?.sendPerformed
        let reasonCode = receipt?.reason ?? response.reason
        // Only explicit backend pre-boundary reasons justify "not sent".
        // `send_performed=false` alone is not enough: the b031 backend can
        // report RECOVERY_COMMAND_FAILED after reboot/serial VDMs were sent.
        let explicitPreSend = ["PRE_BOUNDARY_FAILURE", "TRIPLET_REQUIRED", "UNKNOWN_COMMAND"]
            .contains(reasonCode)
        let stdout = response.stdout
        let targetRebootOK = stdout.contains("Rebooting target into normal mode... OK")
        let targetSerialOK = stdout.contains("Putting target into serial mode... OK")
        let localSerialFailed = stdout.contains("Putting local end into serial mode... Failed")
        let localDVEnStage = targetRebootOK && targetSerialOK && localSerialFailed
        let phase: String
        if localDVEnStage {
            phase = "主机端串口启用失败；恢复界面未确认"
        } else if let sendState {
            if sendState {
                phase = "动作已开始、后续失败"
            } else if explicitPreSend {
                phase = "发送前被拒绝"
            } else {
                phase = "发送状态未确认"
            }
        } else if response.dispatchTruth == "REQUEST_SENT" {
            phase = "动作已开始、后续失败"
        } else {
            phase = "发送状态未确认"
        }
        let reasonText = readableReason(reasonCode)
        let dispatched: Bool? = localDVEnStage ? nil
            : (sendState == true ? true : (explicitPreSend ? false : nil))
        let sentence: String
        if localDVEnStage {
            sentence = "目标重启与 serial 步骤已提交；主机端串口启用失败；恢复界面未确认"
        } else if receipt == nil {
            if response.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && response.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sentence = "本次原因未取得：后端返回失败，但没有保存 stdout/stderr 回执；无法判断是否已发送。"
            } else {
                sentence = "本次原因未取得：后端回执无法解析；无法判断是否已发送。"
            }
        } else if sendState == true {
            sentence = "动作已开始，后端后续失败：\(reasonText)；设备状态未确认。"
        } else if sendState == false && explicitPreSend {
            sentence = "发送前被拒绝：\(reasonText)；未发送。"
        } else if sendState == false {
            sentence = "恢复命令失败，是否已发送未确认。"
        } else {
            sentence = "后端返回失败，但回执未标明是否已发送；结果未确认。"
        }
        let title: String
        if localDVEnStage {
            title = "目标已提交 · 主机端串口启用失败"
        } else {
            switch phase {
            case "发送前被拒绝": title = "发送前被拒绝"
            case "动作已开始、后续失败": title = "已发送 · 后续失败"
            default: title = "结果未确认"
            }
        }
        let exit = response.exitCode.map(String.init) ?? "—"
        let status = receipt?.status ?? "UNKNOWN"
        let sent = sendState.map { $0 ? "true" : "false" } ?? "UNKNOWN"
        let candidates = receipt?.candidateServiceCount.map(String.init) ?? "—"
        let dvEnRaw = stdout.split(separator: "\n")
            .map(String.init)
            .first { $0.contains("DVEn return=") } ?? "—"
        let technical = """
        request=\(response.requestID)
        helper=\(response.helperVersion) exit=\(exit) dispatch=\(response.dispatchTruth)
        phase=\(phase) status=\(status) send_performed=\(sent) reason=\(reasonCode)
        candidate_service_count=\(candidates) requested_rid=\(receipt?.requestedRID.map(String.init) ?? "—") selected_rid=\(receipt?.selectedRID.map(String.init) ?? "—")
        dv_en=\(dvEnRaw)
        stdout=\(response.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        stderr=\(response.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        """
        return RecoveryFailurePresentation(title: title, sentence: sentence, phase: phase,
                                           technical: technical, isDispatched: dispatched)
    }

    private static func readableReason(_ code: String) -> String {
        switch code {
        case "PRE_BOUNDARY_FAILURE": return "端口/RID 预检失败"
        case "TRIPLET_REQUIRED": return "端口/RID 参数不完整"
        case "UNKNOWN_COMMAND": return "后端不支持该命令"
        case "RECOVERY_COMMAND_FAILED": return "恢复命令执行失败"
        case "REBOOT_COMMAND_FAILED": return "重启命令执行失败"
        case "DFU_COMMAND_FAILED": return "DFU 命令执行失败"
        case "BACKEND_FAILED": return "后端失败（未给出具体阶段）"
        case "": return "后端未给出原因"
        default: return code
        }
    }
}

import Foundation

/// P2-A2：工作台的"查看状态"。
///
/// 只保存**看什么**，绝不参与**发什么**：
/// - `viewedPortKey`：要查看的物理端口（`LiveHostPort.id`）。视图区域据此显示设备信息。
/// - `viewedTaskID`：要查看的任务 UUID。
/// 物理控制目标仍由 `DeviceControlModel.selectedLiveKey` 唯一决定，本类型不引用设备模型。
@MainActor
final class WorkbenchNavigationState: ObservableObject {
    @Published private(set) var viewedPortKey: String?
    @Published private(set) var viewedTaskID: UUID?
    @Published private(set) var viewedTaskPortLabel: String?

    /// 查看某个任务：只改变查看状态，不改变查看端口。
    func viewTask(id: UUID, portLabel: String?) {
        viewedTaskID = id
        viewedTaskPortLabel = portLabel
    }

    /// 查看某个物理端口（`LiveHostPort.id`）；`nil` 表示跟随物理控制端口。
    func viewPort(_ livePortID: String?) {
        let normalized = (livePortID?.isEmpty == true) ? nil : livePortID
        if normalized != nil, normalized == viewedPortKey {
            return
        }
        viewedPortKey = normalized
        viewedTaskID = nil
        viewedTaskPortLabel = nil
    }

    func clearTaskView() {
        viewedTaskID = nil
        viewedTaskPortLabel = nil
    }

    func isViewingTask(_ id: UUID) -> Bool {
        viewedTaskID == id
    }

    func isViewingPort(_ livePortID: String) -> Bool {
        viewedPortKey == livePortID
    }

    var taskViewLabel: String? {
        guard viewedTaskID != nil else { return nil }
        return viewedTaskPortLabel
    }
}

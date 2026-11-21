import Foundation

/// 切片 1：单机 Restore 执行槽。
///
/// 目标是把"某一 attempt 的执行事实"收拢到一个独立对象中：
/// - 不可变 attempt UUID（槽身份）
/// - `PendingRestoreAttempt`（冻结的设备/固件/raw 策略快照）
/// - `RestoreTaskSnapshot`（UI 投影与结果）
/// - 该槽自己的 `runTask`
///
/// 切片 1 只允许存在一个槽；`RestoreWorkspaceModel.activeAttempt` /
/// `currentTask` / `runTask` 是对该槽的兼容投影，明确绑定 `executionSlot`。
@MainActor
final class RestoreExecutionSlot {
    let attemptID: UUID
    var attempt: PendingRestoreAttempt?
    var task: RestoreTaskSnapshot?
    var runTask: Task<Void, Never>?

    init(
        attempt: PendingRestoreAttempt,
        task: RestoreTaskSnapshot
    ) {
        self.attemptID = attempt.attemptID
        self.attempt = attempt
        self.task = task
    }

    var isOccupied: Bool {
        attempt != nil || task != nil || runTask != nil
    }
}

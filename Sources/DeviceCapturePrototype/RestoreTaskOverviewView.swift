import SwiftUI

/// P2-A1：REV2 工作台右侧顶部的 Restore 任务总览。
///
/// 当前产品仍是单任务（`SERIAL_RESTORE_ONLY`），因此这里**只显示真实存在的那一个任务**；
/// 不显示并发容量、不显示 "2/2"、不提供任何第二任务的假入口。
/// 点击"查看任务"只更新 `WorkbenchNavigationState`，绝不触碰物理控制目标。
struct RestoreTaskOverviewView: View {
    @ObservedObject var restore: RestoreWorkspaceModel
    @ObservedObject var navigation: WorkbenchNavigationState
    let palette: WorkbenchPalette
    let increaseContrast: Bool
    let onOpenTask: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            palette.panel.opacity(increaseContrast ? 1 : 0.72),
            in: RoundedRectangle(
                cornerRadius: palette.panelRadius,
                style: .continuous)
        )
        .accessibilityIdentifier("restore-task-overview")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(L10n.t("Restore 任务总览"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.primaryText)
            Spacer(minLength: 8)
            Text(activitySummary)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(palette.tertiaryText)
                .accessibilityIdentifier("restore-overview-activity-count")
        }
    }

    private var activitySummary: String {
        let tasks = activeTasks
        let count = "\(tasks.count)"
        let viewing = tasks.contains { navigation.isViewingTask($0.id) }
        if tasks.count > 1 {
            return count + " " + L10n.t("项活动")
                + " · " + L10n.t("双任务模式")
        }
        if viewing {
            return count + " " + L10n.t("项活动")
                + " · " + L10n.t("正在查看")
        }
        return count + " " + L10n.t("项活动")
    }

    private var activeTasks: [RestoreTaskSnapshot] {
        [restore.currentTask, restore.secondaryTask].compactMap { $0 }
    }

    private var activeTask: RestoreTaskSnapshot? {
        restore.currentTask
    }

    @ViewBuilder
    private var content: some View {
        if !activeTasks.isEmpty {
            VStack(spacing: 4) {
                ForEach(activeTasks) { task in
                    taskRow(task)
                }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.tertiaryText)
                Text(L10n.t("当前没有活动 Restore"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                palette.panelMuted.opacity(increaseContrast ? 1 : 0.6),
                in: RoundedRectangle(
                    cornerRadius: palette.controlRadius,
                    style: .continuous)
            )
            .accessibilityIdentifier("restore-overview-empty")
        }
    }

    private func taskRow(_ task: RestoreTaskSnapshot) -> some View {
        let progress = RestoreStageProgressPresentation(task: task)
        let viewed = navigation.isViewingTask(task.id)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(identityLine(task))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Text(task.ipswURL.lastPathComponent)
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(stateTitle(task))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(stateTone(task))
                    .lineLimit(1)
                Text(L10n.t("本阶段") + " \(stageText(progress)) · " + L10n.t("整体未知"))
                    .font(.system(size: 9))
                    .foregroundStyle(palette.tertiaryText)
                    .lineLimit(1)
            }
            Button {
                navigation.viewTask(
                    id: task.id,
                    portLabel: task.target.portDisplayName)
                onOpenTask(task.id)
            } label: {
                HStack(spacing: 3) {
                    Text(L10n.t(viewed ? "正在查看" : "查看任务"))
                        .font(.system(size: 9.5, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(palette.accent)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("restore-overview-view-task")
            .accessibilityLabel(L10n.t("查看任务"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            viewed
                ? palette.accent.opacity(increaseContrast ? 0.22 : 0.12)
                : palette.panelMuted.opacity(increaseContrast ? 1 : 0.6),
            in: RoundedRectangle(
                cornerRadius: palette.controlRadius,
                style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            navigation.viewTask(id: task.id, portLabel: task.target.portDisplayName)
            onOpenTask(task.id)
        }
        .accessibilityIdentifier("restore-overview-active-task")
    }

    private func identityLine(_ task: RestoreTaskSnapshot) -> String {
        let port = task.target.portDisplayName
        let device = task.target.displayIdentity
        return port.isEmpty ? device : "\(port) · \(device)"
    }

    private func stateTitle(_ task: RestoreTaskSnapshot) -> String {
        if let outcome = task.outcome {
            switch outcome {
            case .success: return L10n.t("完成") + " · " + L10n.t("Restore 成功")
            case .failure: return L10n.t("失败") + " · " + L10n.t("Restore 失败")
            case .canceled: return L10n.t("已取消")
            case .unknown: return L10n.t("结果未知")
            }
        }
        if task.cancellationRequested { return L10n.t("取消处理中") }
        if restore.isFinalizingRestoreEvidence { return "FINALIZING" }
        switch task.phase {
        case .userConfirmed: return L10n.t("准备中")
        case .processStarted, .restoreActivityObserved: return L10n.t("执行中")
        case .terminal: return L10n.t("结束处理中")
        }
    }

    private func stateTone(_ task: RestoreTaskSnapshot) -> Color {
        if let outcome = task.outcome {
            switch outcome {
            case .success: return palette.success
            case .failure: return palette.danger
            case .canceled: return palette.warning
            case .unknown: return palette.tertiaryText
            }
        }
        if task.cancellationRequested { return palette.warning }
        return palette.accent
    }

    private func stageText(_ presentation: RestoreStageProgressPresentation) -> String {
        guard let fraction = presentation.stageFraction else {
            return "未知"
        }
        return "\(Int((fraction * 100).rounded()))%"
    }
}

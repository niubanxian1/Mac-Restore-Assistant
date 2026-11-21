import Foundation
import SwiftUI

struct RestoreStageProgressPresentation: Equatable {
    let stageFraction: Double?
    let isIndeterminate: Bool
    let phaseText: String
    let usesCurrentStagePrefix: Bool
    let stepCompleted: Bool
    let detailText: String
    let overallText: String

    init(task: RestoreTaskSnapshot) {
        self.init(
            stageFraction: task.stageFraction,
            stepText: task.stepText,
            stepCompleted: task.stepCompleted,
            outcome: task.outcome,
            processStarted: task.processStartedAt != nil)
    }

    init(
        stageFraction rawFraction: Double?,
        stepText: String,
        stepCompleted: Bool = false,
        outcome: RestoreOutcome?,
        processStarted: Bool
    ) {
        let trustedFraction = rawFraction.flatMap { value in
            !stepText.isEmpty
                && value.isFinite
                && (0...1).contains(value)
                ? min(max(value, 0), 1)
                : nil
        }

        if outcome != nil {
            stageFraction = nil
            isIndeterminate = false
            phaseText = "Restore 已结束"
            usesCurrentStagePrefix = false
            self.stepCompleted = false
            detailText = stepText.isEmpty
                ? "设备操作已结束，结果来自 cfgutil 终态。"
                : stepText
            overallText = "Restore 终态：\(outcome?.rawValue ?? "UNKNOWN")"
        } else if !processStarted {
            stageFraction = nil
            isIndeterminate = true
            phaseText = "Restore 准备中"
            usesCurrentStagePrefix = false
            self.stepCompleted = false
            detailText = stepText.isEmpty
                ? "等待 cfgutil 真实阶段输出。"
                : stepText
            overallText = "整体进度：未知"
        } else if stepCompleted {
            stageFraction = nil
            isIndeterminate = false
            phaseText = stepText.isEmpty
                ? "当前阶段已完成"
                : stepText
            usesCurrentStagePrefix = false
            self.stepCompleted = true
            detailText = "cfgutil 已报告当前阶段完成，等待下一阶段真实输出。"
            overallText = "整体进度：未知"
        } else {
            stageFraction = trustedFraction
            isIndeterminate = trustedFraction == nil
            phaseText = stepText.isEmpty ? "等待真实活动" : stepText
            usesCurrentStagePrefix = !stepText.isEmpty
            self.stepCompleted = false
            detailText = stepText.isEmpty
                ? "cfgutil 尚未报告可识别的阶段。"
                : "该百分比只对应当前 Step，不能推导整体完成情况。"
            overallText = "整体进度：未知"
        }
    }

    var percentageText: String? {
        guard let stageFraction else { return nil }
        let percentage = stageFraction * 100
        if abs(percentage - percentage.rounded()) < 0.05 {
            return "\(Int(percentage.rounded()))%"
        }
        return String(format: "%.1f%%", percentage)
    }

}

struct RestoreStageProgressView: View {
    let task: RestoreTaskSnapshot

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentation: RestoreStageProgressPresentation {
        RestoreStageProgressPresentation(task: task)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(
                    presentation.usesCurrentStagePrefix
                        ? L10n.currentRestoreStage(
                            presentation.phaseText)
                        : L10n.t(presentation.phaseText))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let percentage = presentation.percentageText {
                    Text(percentage)
                        .font(.system(
                            size: 12,
                            weight: .semibold,
                            design: .monospaced))
                        .monospacedDigit()
                }
            }

            Group {
                if let fraction = presentation.stageFraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                } else if presentation.isIndeterminate {
                    if reduceMotion {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.16))
                            .clipShape(Capsule())
                            .accessibilityHidden(true)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                    }
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.16))
                        .frame(height: 4)
                        .clipShape(Capsule())
                }
            }
            .frame(height: 8)

            Text(L10n.t(presentation.detailText))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(L10n.t(presentation.overallText))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(
                    presentation.overallText.hasPrefix("整体进度")
                        ? "restore-overall-progress-unknown"
                        : "restore-terminal-outcome")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            L10n.t(
                "Restore 阶段：\(presentation.usesCurrentStagePrefix ? L10n.currentRestoreStage(presentation.phaseText) : presentation.phaseText)；"
                    + (presentation.percentageText.map {
                        "当前阶段 \($0)；"
                    } ?? "")
                    + presentation.overallText))
        .accessibilityIdentifier("restore-stage-progress")
    }
}

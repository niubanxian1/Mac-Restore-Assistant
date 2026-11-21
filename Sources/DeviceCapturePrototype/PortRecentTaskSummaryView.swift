import SwiftUI

/// P2-A1：单个物理端口的"上一项 Restore"摘要（REV2 决策 B）。
///
/// 数据来自既有 `RestoreHistoryStore`（只读、不改格式），按 `stablePortKey` 过滤：
/// - 只读摘要，默认一行；展开后是只读明细。
/// - **没有任何取消、强杀、擦除或重试操作**：历史任务不可执行。
/// - 与当前接入设备分开显示：当前设备在准备区，上一项结果只在此卡片。
struct PortRecentTaskSummaryView: View {
    /// 端口的 `RestoreTarget.portKey`（历史记录里是 `hostFingerprint|portKey`，按后缀匹配）。
    let portKey: String?
    /// 当前该端口是否接入了一台设备（用于区分"已离开此口"与"本口最近任务"）。
    let hasCurrentDevice: Bool
    /// 当前活动任务 ID；历史卡片永不对它提供操作，仅用于避免把活动任务当历史。
    let currentActiveTaskID: UUID?
    let palette: WorkbenchPalette
    let increaseContrast: Bool

    @State private var record: RestoreHistoryRecord?
    @State private var isAmbiguous = false
    @State private var expanded = false

    var body: some View {
        Group {
            if isAmbiguous {
                ambiguityNotice
            } else if let record {
                card(record)
            }
        }
        .task(id: reloadKey) {
            await load()
        }
        .accessibilityIdentifier("restore-port-history")
    }

    /// 端口或活动任务变化都要重新取历史：任务收尾后 `currentActiveTaskID` 变为 nil，
    /// 刚完成的那条记录必须能立刻出现在"端口历史"里。
    private var reloadKey: String {
        "\(portKey ?? "")|\(currentActiveTaskID?.uuidString ?? "")"
    }

    // MARK: - 数据

    /// 端口历史查询结果：唯一归属才返回记录，否则明确标记歧义。
    struct Lookup {
        let record: RestoreHistoryRecord?
        let isAmbiguous: Bool
    }

    /// 纯函数：按完整 `stablePortKey` 归一化后只认唯一归属。
    ///
    /// 传入的是 `RestoreTarget.portKey`（不含 host 指纹）。历史里存的是
    /// `hostFingerprint|portKey`；若后缀匹配到**多个不同的完整键**，说明无法唯一定位
    /// 物理端口，此时返回歧义而不是猜测。
    static func lookup(
        _ records: [RestoreHistoryRecord],
        matchingPortKey key: String?,
        excludingTaskID: UUID?
    ) -> Lookup {
        guard let key, !key.isEmpty else { return Lookup(record: nil, isAmbiguous: false) }
        var matchedKeys = Set<String>()
        var matches: [RestoreHistoryRecord] = []
        for record in records {
            guard record.operationType == .restore else { continue }
            guard record.taskID != excludingTaskID else { continue }
            guard let stable = record.stablePortKey else { continue }
            guard stable == key || stable.hasSuffix("|\(key)") else { continue }
            matchedKeys.insert(stable)
            matches.append(record)
        }
        guard !matches.isEmpty else { return Lookup(record: nil, isAmbiguous: false) }
        guard matchedKeys.count == 1 else {
            return Lookup(record: nil, isAmbiguous: true)
        }
        let latest = matches.max { lhs, rhs in
            completionDate(lhs) < completionDate(rhs)
        }
        return Lookup(record: latest, isAmbiguous: false)
    }

    static func latest(
        _ records: [RestoreHistoryRecord],
        matchingPortKey key: String?,
        excludingTaskID: UUID?
    ) -> RestoreHistoryRecord? {
        lookup(records, matchingPortKey: key, excludingTaskID: excludingTaskID).record
    }

    static func completionDate(_ record: RestoreHistoryRecord) -> Date {
        if let confirmed = record.lifecycle.outcomeConfirmed?.wallTime {
            return confirmed
        }
        if let exited = record.lifecycle.processExited?.wallTime {
            return exited
        }
        return record.lifecycle.userConfirmed.wallTime
    }

    private func load() async {
        guard let key = portKey, !key.isEmpty else {
            record = nil
            isAmbiguous = false
            return
        }
        let store = RestoreHistoryStore()
        let records = (try? await store.records()) ?? []
        let result = Self.lookup(
            records,
            matchingPortKey: key,
            excludingTaskID: currentActiveTaskID)
        record = result.record
        isAmbiguous = result.isAmbiguous
    }

    // MARK: - 呈现

    private var ambiguityNotice: some View {
        HStack(spacing: 6) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.warning)
            Text(L10n.t("端口归属待确认，未显示历史"))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            palette.panelMuted.opacity(increaseContrast ? 1 : 0.55),
            in: RoundedRectangle(
                cornerRadius: palette.controlRadius,
                style: .continuous)
        )
        .accessibilityIdentifier("restore-port-history-ambiguous")
    }

    private func card(_ record: RestoreHistoryRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(hasCurrentDevice
                    ? L10n.t("上一项任务") + " · " + L10n.t("端口历史")
                    : L10n.t("本口最近任务"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
                Spacer(minLength: 6)
                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Text(L10n.t(expanded ? "收起历史" : "查看历史"))
                            .font(.system(size: 9.5, weight: .medium))
                        Image(systemName: expanded ? "chevron.up" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("restore-history-disclosure")
            }

            HStack(spacing: 6) {
                Image(systemName: outcomeSymbol(record.outcome))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(outcomeTone(record.outcome))
                Text(record.deviceDisplayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Text(outcomeTitle(record.outcome))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(outcomeTone(record.outcome))
                    .lineLimit(1)
                Spacer(minLength: 4)
            }

            Text(summaryLine(record))
                .font(.system(size: 9.5))
                .foregroundStyle(palette.tertiaryText)
                .lineLimit(1)

            if expanded {
                detailGrid(record)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            palette.panelMuted.opacity(increaseContrast ? 1 : 0.55),
            in: RoundedRectangle(
                cornerRadius: palette.controlRadius,
                style: .continuous)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: palette.controlRadius,
                style: .continuous)
                .strokeBorder(
                    palette.separator,
                    style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
        )
        .accessibilityIdentifier("restore-port-history-summary")
    }

    private func detailGrid(_ record: RestoreHistoryRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            detailRow("固件", record.firmwareFileName)
            detailRow("结果", "\(record.outcome.rawValue) / \(record.errorClassification.rawValue)")
            detailRow("退出", record.exitCode.map(String.init) ?? L10n.t("未记录"))
            detailRow("原始日志", record.rawEvidenceStatus.rawValue)
            detailRow("完成时间", formatted(record))
            detailRow("尝试", String(record.taskID.uuidString.prefix(8)))
            Text(L10n.t("历史任务不可取消、不可擦除；仅用于核对。"))
                .font(.system(size: 9))
                .foregroundStyle(palette.tertiaryText)
                .padding(.top, 2)
        }
        .accessibilityIdentifier("restore-history-details")
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(L10n.t(title))
                .font(.system(size: 9))
                .foregroundStyle(palette.tertiaryText)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.system(size: 9.5))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func summaryLine(_ record: RestoreHistoryRecord) -> String {
        let time = formatted(record)
        let attempt = String(record.taskID.uuidString.prefix(4))
        return "\(time) " + L10n.t("完成")
            + " · " + L10n.t("尝试") + " …\(attempt) · \(record.firmwareFileName)"
    }

    private func formatted(_ record: RestoreHistoryRecord) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Self.completionDate(record))
    }

    private func outcomeTitle(_ outcome: RestoreOutcome) -> String {
        switch outcome {
        case .success: return L10n.t("Restore 成功")
        case .failure: return L10n.t("Restore 失败")
        case .canceled: return L10n.t("Restore 已取消")
        case .unknown: return L10n.t("结果未知")
        }
    }

    private func outcomeSymbol(_ outcome: RestoreOutcome) -> String {
        switch outcome {
        case .success: return "checkmark.circle"
        case .failure: return "xmark.octagon"
        case .canceled: return "slash.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    private func outcomeTone(_ outcome: RestoreOutcome) -> Color {
        switch outcome {
        case .success: return palette.success
        case .failure: return palette.danger
        case .canceled: return palette.warning
        case .unknown: return palette.tertiaryText
        }
    }
}

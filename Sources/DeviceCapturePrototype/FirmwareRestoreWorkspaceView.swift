import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum RestoreLiveEvidenceCopy {
    static let panelDescription =
        "此面板仅展示当前 cfgutil 子进程的有界内存输出；原始日志保存和 RLM 状态以锁定任务摘要为准。"
}

struct RestoreLogPaneMetrics {
    static let defaultFraction = 0.46

    static func bounds(for availableHeight: CGFloat) -> ClosedRange<CGFloat> {
        let height = max(availableHeight, 1)
        let minimumHeight = min(132, max(72, height * 0.24))
        let reservedHeight = min(190, height * 0.42)
        let maximumHeight = max(minimumHeight, height - reservedHeight)
        return (minimumHeight / height)...(maximumHeight / height)
    }

    static func constrainedFraction(
        _ fraction: Double,
        for availableHeight: CGFloat
    ) -> CGFloat {
        let bounds = bounds(for: availableHeight)
        return min(max(CGFloat(fraction), bounds.lowerBound), bounds.upperBound)
    }

    static func adjustedFraction(
        startingAt start: Double,
        translation: CGFloat,
        availableHeight: CGFloat
    ) -> Double {
        let height = max(availableHeight, 1)
        let delta = -translation / height
        let bounds = bounds(for: height)
        return Double(
            min(max(CGFloat(start) + delta, bounds.lowerBound), bounds.upperBound))
    }
}

/// UI-2 统一准备态的纯展示摘要。不保存任何选择状态，也不参与推荐/校验。
struct UI2PreparationSummary: Equatable {
    let fileName: String?
    let versionText: String?
    let sourceText: String?
    let preferenceIssue: String

    var showsPreferenceIssue: Bool { !preferenceIssue.isEmpty }
}

/// UI-2 固件库列表：自带搜索状态，只过滤已展示数组，不参与任何模型选择。
private struct UI2FirmwareLibraryList: View {
    let entries: [FirmwareLibraryEntry]
    let target: RestoreTarget
    let highlightID: UUID?
    let primaryMode: Bool
    let sourceText: String?
    let isRestoreTaskActive: Bool
    let visual: MRAVisualTokens
    let isScanning: Bool
    let onSelect: (FirmwareLibraryEntry) -> Void
    let onPrepare: (FirmwareLibraryEntry) -> Void
    let onAddDirectory: () -> Void
    let onRescan: () -> Void
    let onSetModelDefault: (FirmwareLibraryEntry) -> Void
    let onSetGlobalDefault: (FirmwareLibraryEntry) -> Void

    @State private var query = ""

    private var visibleEntries: [FirmwareLibraryEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = q.isEmpty ? entries : entries.filter { entry in
            let fields = [
                entry.url.lastPathComponent,
                entry.metadata?.productVersion ?? "",
                entry.metadata?.productBuild ?? ""
            ]
            return fields.contains {
                $0.localizedCaseInsensitiveContains(q)
            }
        }
        return filtered.sorted { lhs, rhs in
            let left = sortRank(lhs)
            let right = sortRank(rhs)
            if left != right { return left < right }
            return lhs.url.lastPathComponent.localizedStandardCompare(
                rhs.url.lastPathComponent) == .orderedAscending
        }
    }

    private func sortRank(_ entry: FirmwareLibraryEntry) -> Int {
        if entry.id == highlightID { return 0 }
        guard entry.isRestoreEligible else { return 4 }
        switch compatibility(for: entry).status {
        case .compatible: return 1
        case .unverified: return 2
        case .incompatible: return 3
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(L10n.t("本地固件库"))
                    .font(MRAFont.label(11))
                    .tracking(0.35)
                    .foregroundStyle(visual.textSecondary)
                    .accessibilityIdentifier("ui2-prep-library")
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(visual.textTertiary)
                    TextField(L10n.t("搜索 IPSW…"), text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(width: 112)
                }
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(visual.surfaceSubtle, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(visual.hairline, lineWidth: 1)
                }
                .accessibilityIdentifier("ui2-prep-library-search")
                if isScanning {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 14, height: 14)
                        .accessibilityIdentifier("ui2-prep-library-scanning")
                }
                Button(L10n.t("添加目录…"), action: onAddDirectory)
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(visual.accentPrimary)
                    .disabled(isScanning)
                    .accessibilityIdentifier("ui2-prep-library-add")
                Button(L10n.t("重新扫描"), action: onRescan)
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(visual.accentPrimary)
                    .disabled(isScanning)
                    .accessibilityIdentifier("ui2-prep-library-rescan")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)

            header

            if visibleEntries.isEmpty {
                Text(query.trimmingCharacters(
                    in: .whitespacesAndNewlines).isEmpty
                    ? L10n.t("固件库为空。")
                    : L10n.t("没有匹配的 IPSW。"))
                    .font(.system(size: 11))
                    .foregroundStyle(visual.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleEntries) { entry in
                            row(entry)
                            Rectangle()
                                .fill(visual.hairline)
                                .frame(height: 1)
                                .opacity(0.7)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("").frame(width: 22)
            Text(L10n.t("IPSW 文件"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.t("版本 / Build"))
                .frame(width: 100, alignment: .leading)
            Text(L10n.t("兼容性"))
                .frame(width: 76, alignment: .leading)
            Text(L10n.t("来源"))
                .frame(width: 76, alignment: .leading)
        }
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(visual.textTertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(visual.surfaceSubtle.opacity(0.55))
        .overlay(alignment: .bottom) {
            Rectangle().fill(visual.hairline).frame(height: 1)
        }
    }

    private func row(_ entry: FirmwareLibraryEntry) -> some View {
        let compatibility = compatibility(for: entry)
        let highlighted = entry.id == highlightID
        let clickable = primaryMode
            ? !isRestoreTaskActive
            : (entry.isRestoreEligible
                && compatibility.status != .incompatible)
        let version = versionText(
            entry.metadata?.productVersion,
            entry.metadata?.productBuild) ?? L10n.t("未获取")
        let rowSource: String
        if highlighted {
            rowSource = primaryMode
                ? (sourceText ?? L10n.t("未获取"))
                : L10n.t("未获取")
        } else {
            rowSource = "—"
        }
        return Button {
            guard clickable else { return }
            if primaryMode {
                onSelect(entry)
            } else {
                onPrepare(entry)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName:
                    highlighted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        highlighted
                            ? visual.accentPrimary
                            : visual.textTertiary.opacity(0.5))
                    .frame(width: 22)
                Text(entry.url.lastPathComponent)
                    .font(.system(
                        size: 11.5,
                        weight: highlighted ? .semibold : .regular))
                    .foregroundStyle(
                        clickable ? visual.textPrimary : visual.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(entry.url.lastPathComponent)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(version)
                    .font(MRAFont.mono(10.5))
                    .foregroundStyle(visual.textSecondary)
                    .lineLimit(1)
                    .frame(width: 100, alignment: .leading)
                Text(compatibilityLabel(compatibility.status))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(
                        compatibilityTone(compatibility.status))
                    .lineLimit(1)
                    .frame(width: 76, alignment: .leading)
                Text(rowSource)
                    .font(.system(size: 10))
                    .foregroundStyle(visual.textTertiary)
                    .lineLimit(1)
                    .frame(width: 76, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(highlighted ? visual.surfaceSubtle : .clear)
            .overlay(alignment: .leading) {
                if highlighted {
                    Rectangle()
                        .fill(visual.accentPrimary)
                        .frame(width: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!clickable)
        .contextMenu {
            let canDefault = entry.isRestoreEligible
                && compatibility.status != .incompatible
            Button(L10n.t("设为本机型默认")) {
                onSetModelDefault(entry)
            }
            .disabled(!canDefault)
            Button(L10n.t("设为全局默认")) {
                onSetGlobalDefault(entry)
            }
            .disabled(!canDefault)
            Divider()
            Button(L10n.t("在 Finder 中显示")) {
                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            }
            .disabled(!FileManager.default.fileExists(atPath: entry.url.path))
        }
        .accessibilityIdentifier(
            "ui2-prep-library-row-\(entry.id.uuidString)")
        .accessibilityLabel(entry.url.lastPathComponent)
    }

    private func compatibility(
        for entry: FirmwareLibraryEntry
    ) -> HardwareCompatibility {
        guard let metadata = entry.metadata else {
            return HardwareCompatibility(status: .unverified, message: "")
        }
        return IPSWCompatibilityEvaluator.evaluate(
            metadata: metadata,
            target: RestoreTargetIdentity(
                productType: target.productType,
                deviceClass: target.deviceClass,
                boardID: target.boardID,
                chipID: target.chipID))
    }

    private func compatibilityLabel(
        _ status: HardwareCompatibilityStatus
    ) -> String {
        switch status {
        case .compatible: return L10n.t("兼容")
        case .unverified: return L10n.t("未验证")
        case .incompatible: return L10n.t("不兼容")
        }
    }

    private func compatibilityTone(
        _ status: HardwareCompatibilityStatus
    ) -> Color {
        switch status {
        case .compatible: return visual.stateSuccess
        case .unverified: return visual.stateDFU
        case .incompatible: return visual.stateError
        }
    }

    private func versionText(
        _ version: String?,
        _ build: String?
    ) -> String? {
        guard version != nil || build != nil else { return nil }
        return (version ?? L10n.t("版本未知"))
            + " · " + (build ?? L10n.t("Build 未知"))
    }
}


private enum UI3RunningColors {
    static let terminalBackground = Color(
        .sRGB, red: 11 / 255, green: 13 / 255, blue: 17 / 255)
    static let terminalText = Color(
        .sRGB, red: 215 / 255, green: 222 / 255, blue: 232 / 255)
    static let progress = Color(
        .sRGB, red: 34 / 255, green: 211 / 255, blue: 238 / 255)
}

/// UI-3 实时 cfgutil 预览。只展示当前任务的有界内存尾部；不是完整原始日志。
private struct UI3LiveLogView: View {
    let task: RestoreTaskSnapshot
    let visual: MRAVisualTokens

    @State private var autoFollow = true
    @State private var scrollPosition: Int?
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if task.cfgutilOutputTail.isEmpty {
                        Text(L10n.t(
                            task.processStartedAt == nil
                                ? "cfgutil 尚未实际启动；当前没有子进程输出。"
                                : "等待 cfgutil 输出…"))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(
                                UI3RunningColors.terminalText.opacity(0.55))
                            .padding(.vertical, 6)
                    } else {
                        ForEach(
                            Array(task.cfgutilOutputTail.enumerated()),
                            id: \.offset
                        ) { index, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.system(
                                    size: 11.5,
                                    design: .monospaced))
                                .foregroundStyle(UI3RunningColors.terminalText)
                                .textSelection(.enabled)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading)
                                .id(index)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(UI3RunningColors.terminalBackground)
            .scrollIndicators(.visible)
            .scrollPosition(id: $scrollPosition, anchor: .bottom)
            .onAppear {
                autoFollow = true
                if let last = task.cfgutilOutputTail.indices.last {
                    DispatchQueue.main.async {
                        scrollPosition = last
                    }
                }
            }
            .onChange(of: task.cfgutilOutputSequence) { _, _ in
                guard autoFollow,
                      let last = task.cfgutilOutputTail.indices.last
                else { return }
                scrollPosition = last
            }
            .onChange(of: scrollPosition) { _, newValue in
                guard let last = task.cfgutilOutputTail.indices.last else {
                    return
                }
                autoFollow = (newValue == last)
            }
            .overlay(alignment: .bottomTrailing) {
                if !autoFollow && !task.cfgutilOutputTail.isEmpty {
                    Button(L10n.t("回到底部")) {
                        autoFollow = true
                        if let last = task.cfgutilOutputTail.indices.last {
                            scrollPosition = last
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(7)
                    .accessibilityIdentifier("ui3-log-return-bottom")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .background(UI3RunningColors.terminalBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(visual.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("restore-live-output")
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "terminal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(UI3RunningColors.progress)
            Text(L10n.t("实时日志预览"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(UI3RunningColors.terminalText)
            Text(L10n.t("cfgutil 内存尾部 · 非完整原始日志"))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(UI3RunningColors.terminalText.opacity(0.55))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(task.cfgutilOutputTail.count)")
                .font(MRAFont.mono(9.5))
                .foregroundStyle(UI3RunningColors.terminalText.opacity(0.55))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(UI3RunningColors.terminalBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(UI3RunningColors.terminalText.opacity(0.12))
                .frame(height: 1)
        }
        .accessibilityIdentifier("ui3-log-header")
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(L10n.t("仅展示有界内存尾部；完整原始日志请使用 Raw 保存/归档导出。"))
                .font(.system(size: 9))
                .foregroundStyle(UI3RunningColors.terminalText.opacity(0.55))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(L10n.t(copied ? "已复制当前预览" : "复制当前预览")) {
                copyPreview()
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(task.cfgutilOutputTail.isEmpty)
            .accessibilityIdentifier("ui3-log-copy-preview")
        }
        .padding(.horizontal, 9)
        .padding(.top, 4)
        .padding(.bottom, 7)
        .background(UI3RunningColors.terminalBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(UI3RunningColors.terminalText.opacity(0.12))
                .frame(height: 1)
        }
    }

    private func copyPreview() {
        let text = task.cfgutilOutputTail.joined(separator: "\n")
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            copied = false
        }
    }
}


struct FirmwareRestoreWorkspaceView: View {
    @EnvironmentObject private var device: DeviceControlModel
    @EnvironmentObject private var restore: RestoreWorkspaceModel
    @EnvironmentObject private var rawPersistenceSettings:
        RestoreRawPersistenceSettings
    @EnvironmentObject private var appearance: WorkbenchAppearancePreferences
    @Environment(\.colorScheme) private var colorScheme
    @Binding var navigationPortID: String?
    /// P2-B：当前查看中的第二台设备（非活动 Restore 目标时为非 nil）。
    var viewedTarget: RestoreTarget? = nil
    var viewedPortKey: String? = nil
    var viewedTaskID: UUID? = nil
    let palette: WorkbenchPalette
    let increaseContrast: Bool
    @AppStorage("ui.restoreLogPanelFraction")
    private var restoreLogPanelFraction = RestoreLogPaneMetrics.defaultFraction
    @State private var showFileImporter = false
    @State private var showStartConfirmation = false
    @State private var showCancelConfirmation = false
    @State private var showForceKillConfirmation = false
    @State private var pendingCancelAttemptID: UUID?
    @State private var pendingForceKillAttemptID: UUID?
    @State private var showSecondaryForceKillConfirmation = false
    @State private var pendingSecondaryForceKillAttemptID: UUID?
    @State private var secondaryForceKillDeviceLabel = ""
    @State private var secondaryForceKillPortLabel = ""
    @State private var restoreActionFeedback: String?
    @State private var startFailureMessage = ""
    @AppStorage("ui.restoreCompletionSound") private var completionSoundEnabled = true
    @State private var lastPlayedSoundTaskID: UUID?
    @State private var copiedIdentityNotice = ""
    @State private var copyNoticeTask: Task<Void, Never>?
    @State private var showSecondaryStartConfirmation = false
    @State private var pendingSecondaryTargetID: String?
    @State private var pendingPrimaryTargetID: String?
    @State private var showSecondaryCancelConfirmation = false
    @State private var pendingSecondaryCancelAttemptID: UUID?
    @State private var secondaryCancelDeviceLabel = ""
    @State private var secondaryCancelPortLabel = ""
    @State private var rawExportFeedback = ""
    @State private var showRawExportFeedback = false
    @State private var restoreLogDragStartFraction: Double?
    @State private var restoreLogResizerHovered = false
    @State private var ui3DismissedFinishedTaskID: UUID?
    @State private var navigationContextPortID: String?
    @State private var navigationCandidateTargetID: String?

    private var ipswType: UTType {
        UTType(filenameExtension: "ipsw") ?? .data
    }

    /// UI-2 直接复用 UI-1 的 V2 Token（`.precision` 为规范基线，其余样式沿用 palette）。
    private var visual: MRAVisualTokens {
        MRAVisualTokens.resolve(
            style: appearance.visualStyle,
            scheme: colorScheme,
            palette: palette)
    }

    var body: some View {
        Group {
            if restore.isRestoring {
                if let taskID = viewedTaskID {
                    if taskID == restore.currentTask?.id,
                       let task = restore.currentTask {
                        secondaryLiveLayout(task, target: task.target)
                    } else if let secondary = restore.secondaryTask,
                              secondary.attemptID == taskID {
                        secondaryLiveLayout(secondary, target: secondary.target)
                    } else if let canceled = ui3CanceledTaskForPreparation {
                        canceledPreparationLayout(
                            target: canceled.target,
                            canceled: canceled)
                    } else if let finished = ui3FinishedTaskForViewing {
                        ui3TaskWorkspace(finished)
                    } else {
                        activeRestoreLayout
                    }
                } else if viewedPortKey != nil {
                    if let target = viewedTarget {
                        if target.id == restore.currentTask?.target.id,
                           let task = restore.currentTask {
                            secondaryLiveLayout(task, target: target)
                        } else if let secondary = restore.secondaryTask,
                                  secondary.target.id == target.id {
                            secondaryLiveLayout(secondary, target: target)
                        } else if let canceled = ui3CanceledTaskForPreparation {
                            canceledPreparationLayout(
                                target: canceled.target,
                                canceled: canceled)
                        } else if let finished = ui3FinishedTaskForViewing {
                            ui3TaskWorkspace(finished)
                        } else {
                            devicePreparationLayout(target: target)
                        }
                    } else if let canceled = ui3CanceledTaskForPreparation {
                        canceledPreparationLayout(
                            target: canceled.target,
                            canceled: canceled)
                    } else if let finished = ui3FinishedTaskForViewing {
                        ui3TaskWorkspace(finished)
                    } else {
                        emptyPortView
                    }
                } else if let target = viewedTarget {
                    if target.id == restore.currentTask?.target.id,
                       let task = restore.currentTask {
                        secondaryLiveLayout(task, target: target)
                    } else if let secondary = restore.secondaryTask,
                              secondary.target.id == target.id {
                        secondaryLiveLayout(secondary, target: target)
                    } else if let canceled = ui3CanceledTaskForPreparation {
                        canceledPreparationLayout(
                            target: canceled.target,
                            canceled: canceled)
                    } else if let finished = ui3FinishedTaskForViewing {
                        ui3TaskWorkspace(finished)
                    } else {
                        devicePreparationLayout(target: target)
                    }
                } else if viewedTaskID == nil {
                    emptyPortView
                } else if let task = restore.currentTask {
                    secondaryLiveLayout(task, target: task.target)
                } else {
                    activeRestoreLayout
                }
            } else if let canceled = ui3CanceledTaskForPreparation {
                canceledPreparationLayout(
                    target: canceled.target,
                    canceled: canceled)
            } else if let finished = ui3FinishedTaskForViewing {
                ui3TaskWorkspace(finished)
            } else if viewedPortKey != nil,
                      viewedTaskID == nil {
                if let target = viewedTarget {
                    devicePreparationLayout(target: target)
                } else {
                    emptyPortView
                }
            } else if viewedTaskID == nil,
                      let target = viewedTarget {
                devicePreparationLayout(target: target)
            } else if viewedPortKey != nil,
                      viewedTaskID == nil,
                      let target = restore.selectedTarget {
                devicePreparationLayout(target: target)
            } else if viewedTaskID == nil {
                emptyPortView
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let viewedTarget,
                               restore.firmwareDraft(for: viewedTarget) != nil {
                                savedDraftSection(target: viewedTarget)
                            }
                            targetSection
                                .id("restore-target")
                            navigationCandidateSection
                            firmwareSection
                                .id("restore-firmware")
                            confirmationSection
                            currentTaskSection(
                                showsActions: !restore.isRestoreTaskActive)
                            PortRecentTaskSummaryView(
                                portKey: historyPortKey,
                                hasCurrentDevice: restore.selectedTarget != nil,
                                currentActiveTaskID: restore.currentAttemptID,
                                palette: palette,
                                increaseContrast: increaseContrast)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onAppear {
                        consumeNavigationRequest(scrollProxy: proxy)
                    }
                    .onChange(of: navigationPortID) { _, _ in
                        consumeNavigationRequest(scrollProxy: proxy)
                    }
                    .onChange(of: restore.availableTargets) { _, _ in
                        consumeNavigationRequest(scrollProxy: proxy)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if restore.canCancelRestoreTask {
                            preparationCancelInset
                        } else if restore.isFinalizingRestoreEvidence {
                            finalizingEvidenceInset
                        }
                    }
                }
            }
        }
        .onAppear {
            restore.refreshRawSaveSelectionFromSettingsIfNeeded()
            if !restore.isRestoreTaskActive {
                restore.refreshTargets()
            }
        }
        .onChange(of: viewedPortKey) { _, _ in
            ui3DismissedFinishedTaskID = nil
            startFailureMessage = ""
        }
        .onChange(of: viewedTaskID) { _, _ in
            ui3DismissedFinishedTaskID = nil
            startFailureMessage = ""
        }
        .onChange(of: restore.selectedTargetID) { _, _ in
            startFailureMessage = ""
        }
        .onChange(of: restore.isRestoreTaskActive) { _, active in
            if !active { restore.resumeDeferredFirmwareDiscoveryIfNeeded() }
        }
        .onChange(of: restore.lastCompletedTaskSnapshot?.id) { _, _ in
            guard completionSoundEnabled,
                  let finished = restore.lastCompletedTaskSnapshot,
                  finished.id != lastPlayedSoundTaskID,
                  finished.outcome == .success || finished.outcome == .failure else {
                return
            }
            lastPlayedSoundTaskID = finished.id
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
        .onChange(
            of: rawPersistenceSettings.autoSaveRestoreRawLogs
        ) { _, _ in
            restore.refreshRawSaveSelectionFromSettingsIfNeeded()
        }
        .task {
            await restore.loadRestoreHistory()
            await restore.loadFirmwareLibrary()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [ipswType],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await restore.loadFirmware(url: url) }
        }
        .overlay(alignment: .bottom) {
            if let restoreActionFeedback {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(restoreActionFeedback)
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(2)
                    Spacer(minLength: 6)
                    Button(L10n.t("关闭")) {
                        self.restoreActionFeedback = nil
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.orange.opacity(0.45)))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .accessibilityIdentifier("restore-action-feedback")
            }
        }
        .alert(L10n.t("确认抹除并恢复？"), isPresented: $showStartConfirmation) {
            Button(L10n.t("抹除并恢复"), role: .destructive) {
                if let targetID = pendingPrimaryTargetID {
                    Task { _ = await restore.beginUnifiedRestoreAfterConfirmation(
                        targetID: targetID) }
                }
            }
            Button(L10n.t("取消"), role: .cancel) {}
        } message: {
            confirmationMessage
        }
        .confirmationDialog(
            L10n.t("正在执行固件恢复，请求取消可能中断写入并导致设备停留在恢复/DFU 模式，确定请求取消吗？"),
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.t("请求取消恢复"), role: .destructive) {
                confirmCancelRestore()
            }
            Button(L10n.t("继续等待"), role: .cancel) {}
        }
        .confirmationDialog(
            L10n.t("强制结束无响应进程会中断当前写入，原始输出可能不完整。确定继续吗？"),
            isPresented: $showForceKillConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.t("强制结束"), role: .destructive) {
                confirmForceKillRestore()
            }
            Button(L10n.t("取消"), role: .cancel) {}
        }
        .confirmationDialog(
            L10n.t("强制结束 \(secondaryForceKillDeviceLabel) 的 Restore？仅作用于冻结的次任务，不影响另一台。"),
            isPresented: $showSecondaryForceKillConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.t("强制结束 \(secondaryForceKillDeviceLabel)"), role: .destructive) {
                guard let captured = pendingSecondaryForceKillAttemptID else { return }
                pendingSecondaryForceKillAttemptID = nil
                restore.forceKillSecondaryRestore(attemptID: captured)
            }
            Button(L10n.t("取消"), role: .cancel) {}
        }
        .confirmationDialog(
            unifiedStartConfirmationTitle,
            isPresented: $showSecondaryStartConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.t("开始此设备的 Restore")) {
                startSecondaryConfirmed()
            }
            Button(L10n.t("取消"), role: .cancel) {
                restore.invalidateRestoreConfirmation()
            }
        } message: {
            Text(unifiedStartConfirmationMessage)
        }
        .alert(L10n.t("原始日志导出"), isPresented: $showRawExportFeedback) {
            Button(L10n.t("好"), role: .cancel) {}
        } message: {
            Text(rawExportFeedback)
        }
        .confirmationDialog(
            L10n.t("取消 \(secondaryCancelDeviceLabel) 的 Restore？仅作用于打开弹窗时冻结的任务，不影响另一台。"),
            isPresented: $showSecondaryCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.t("请求取消 \(secondaryCancelDeviceLabel)"), role: .destructive) {
                confirmSecondaryCancel()
            }
            Button(L10n.t("继续等待"), role: .cancel) {}
        }
    }

    private var unifiedStartConfirmationTitle: String {
        guard let token = restore.frozenRestoreConfirmation else {
            return L10n.t("开始此设备的 Restore？")
        }
        let target = restore.availableTargets.first {
            $0.id == token.targetID
        }
        return L10n.t("开始此设备的 Restore？") + "\n"
            + (target?.portDisplayName ?? token.portKey ?? "")
            + " · ECID " + token.canonicalECID
            + "\n" + token.ipswURL.lastPathComponent
    }

    /// 冻结端口/ECID/IPSW 已由标题读自 `restore.frozenRestoreConfirmation`；
    /// 这里只补充擦除风险，不重复、不编造任何身份值。
    private var unifiedStartConfirmationMessage: String {
        L10n.t("Restore 会抹除目标 Mac 上的数据。本工具不会自动开始，也不会检测到设备后自动刷机。")
    }

    private func exportRawArchive(attemptID: UUID) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.zip]
        if UIFixture.isActive, let isolatedRoot = UIFixture.isolatedRoot {
            panel.directoryURL = isolatedRoot
        }
        panel.nameFieldStringValue =
            "MRA-Restore-raw-\(attemptID.uuidString.prefix(8)).zip"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let result = try restore.exportRawArchive(
                    attemptID: attemptID,
                    to: url)
                rawExportFeedback = L10n.t(
                    "已导出到 \(result.url.path)（\(result.bytes) 字节，SHA-256 \(result.sha256.prefix(12))…）")
            } catch {
                rawExportFeedback = error.localizedDescription
            }
            showRawExportFeedback = true
        }
    }

    private func startSecondaryConfirmed() {
        guard let targetID = pendingSecondaryTargetID else {
            UIFixture.debugEvent("B_CONFIRM_ACTION_ENTER", "target=nil")
            startFailureMessage = L10n.t("目标已变化，未启动 Restore。")
            return
        }
        UIFixture.debugEvent("B_CONFIRM_ACTION_ENTER", "target=\(targetID)")
        pendingSecondaryTargetID = nil
        startFailureMessage = ""
        Task { @MainActor in
            UIFixture.debugEvent("B_START_HANDLER_ENTER", "target=\(targetID)")
            let ok = await restore.beginUnifiedRestoreAfterConfirmation(
                targetID: targetID)
            if !ok {
                startFailureMessage = restore.errorMessage.isEmpty
                    ? L10n.t("Restore 未能启动，请检查目标设备与固件兼容性。")
                    : restore.errorMessage
            } else {
                startFailureMessage = ""
            }
            let count = (restore.currentTask == nil ? 0 : 1)
                + (restore.secondaryTask == nil ? 0 : 1)
            UIFixture.debugEvent(
                "B_START_HANDLER_RESULT",
                "ok=\(ok) count=\(count) shares=\(restore.activeLeaseShareCount) err=\(restore.errorMessage.prefix(80))")
        }
    }

    private func confirmSecondaryCancel() {
        guard let captured = pendingSecondaryCancelAttemptID else { return }
        pendingSecondaryCancelAttemptID = nil
        guard restore.secondaryAttemptID == captured
                || restore.secondaryTask?.attemptID == captured else {
            restoreActionFeedback = L10n.t("任务已变化，取消未执行。")
            return
        }
        restore.cancelRestore(attemptID: captured)
    }

    /// P2-A1：取消/强杀以"打开确认时捕获的 attempt UUID"为准，
    /// 确认期间任务变化则拒绝执行，避免打到别的任务。
    private func confirmCancelRestore() {
        guard let captured = pendingCancelAttemptID else { return }
        guard restore.currentAttemptID == captured,
              restore.canCancelRestoreTask else {
            restoreActionFeedback = L10n.t("任务已变化，取消未执行")
            pendingCancelAttemptID = nil
            return
        }
        restore.cancelRestore()
        pendingCancelAttemptID = nil
    }

    private func confirmForceKillRestore() {
        guard let captured = pendingForceKillAttemptID else { return }
        // `isRestoreTaskActive` 在 FINALIZING 期间仍为 true；强杀必须要求进程仍在运行
        // 且结果尚未落定，否则只给明确反馈，绝不触发。
        guard restore.currentAttemptID == captured,
              restore.isRestoring,
              restore.canCancelRestoreTask else {
            restoreActionFeedback = L10n.t("任务已结束，强杀未执行")
            pendingForceKillAttemptID = nil
            return
        }
        restore.forceKillRestore()
        pendingForceKillAttemptID = nil
    }

    private var historyPortKey: String? {
        restore.currentTask?.target.portKey ?? restore.selectedTarget?.portKey
    }

    private func consumeNavigationRequest(
        scrollProxy: ScrollViewProxy
    ) {
        guard !restore.isRestoreTaskActive,
              let navigationPortID else {
            return
        }
        restore.refreshTargets()
        navigationContextPortID = navigationPortID
        navigationCandidateTargetID = RestoreNavigationTargetResolver.uniqueTargetID(
            in: restore.navigationTargetInventory,
            matchingPortID: navigationPortID)
        self.navigationPortID = nil
        scrollToFirmwarePreparation(scrollProxy: scrollProxy)
    }

    private func scrollToFirmwarePreparation(
        scrollProxy: ScrollViewProxy
    ) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.16)) {
                scrollProxy.scrollTo("restore-firmware", anchor: .top)
            }
        }
    }

    // MARK: - P2-B 第二台设备的独立固件草稿

    private func draftStatusText(
        _ status: RestoreFirmwareDraftStatus?
    ) -> String {
        guard let status else { return L10n.t("还没有为这台设备准备固件。") }
        switch status {
        case .ready:
            if restore.isRestoreTaskActive {
                return L10n.t("固件准备完成，可启动此设备；另一台继续运行。")
            }
            return L10n.t("固件准备完成，可启动此设备。")
        case .requiresReverification:
            return L10n.t("状态已变化，需重新核验后才能使用。")
        case .unusable(let reason):
            switch reason {
            case .deviceMissing:
                return L10n.t("当前未检测到可靠设备身份，不能确认固件归属。")
            case .deviceChanged:
                return L10n.t("该草稿属于另一台设备，不可用于当前设备。")
            case .connectionChanged:
                return L10n.t("设备连接代际已变化，需重新核验。")
            case .fileChanged:
                return L10n.t("固件文件已被替换或移动，需重新选择。")
            case .firmwareInvalid:
                return L10n.t("固件未通过验证，不能用于启动。")
            case .compatibilityUnverified:
                return L10n.t("兼容性未确认，需人工核验后才能使用。")
            case .ownershipAmbiguous:
                return L10n.t("端口归属不唯一，不能自动绑定该草稿。")
            }
        }
    }

    private func secondaryCompatibleEntries(
        for target: RestoreTarget
    ) -> [FirmwareLibraryEntry] {
        let identity = RestoreTargetIdentity(
            productType: target.productType,
            deviceClass: target.deviceClass,
            boardID: target.boardID,
            chipID: target.chipID)
        return restore.firmwareLibraryEntries.filter { entry in
            guard entry.isRestoreEligible,
                  FileManager.default.isReadableFile(atPath: entry.url.path),
                  let metadata = entry.metadata else { return false }
            return IPSWCompatibilityEvaluator.evaluate(
                metadata: metadata,
                target: identity).status != .incompatible
        }
    }

    private var emptyPortView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "cable.connector.slash")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(L10n.t("该物理端口当前没有已连接的设备。"))
                .font(.system(size: 14, weight: .semibold))
            Text(L10n.t("左侧选中端口与右侧身份严格对应；不会回落到其他接口的设备。"))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .accessibilityIdentifier("restore-empty-port")
    }

    @ViewBuilder
    private func devicePreparationLayout(target: RestoreTarget) -> some View {
        if let secondary = restore.secondaryTask {
            secondaryLiveLayout(secondary, target: target)
        } else {
        let draft = restore.firmwareDraft(for: target)
        let status = restore.firmwareDraftStatus(for: target)
        let primaryMode = restore.currentTask == nil
            && restore.secondaryTask == nil
        let summary = prepSummary(
            target: target,
            draft: draft,
            primaryMode: primaryMode)
            VStack(spacing: 0) {
                if let active = restore.currentTask {
                    prepActiveTaskBar(active)
                }
                prepIdentitySection(target: target)
                prepDivider
                prepEffectiveFirmwareSection(
                    target: target,
                    draft: draft,
                    primaryMode: primaryMode,
                    summary: summary)
                prepDivider
                prepFirmwareLibrarySection(
                    target: target,
                    draft: draft,
                    primaryMode: primaryMode,
                    summary: summary)
                prepDivider
                prepActionBar(
                    target: target,
                    draft: draft,
                    status: status,
                    primaryMode: primaryMode,
                    summary: summary)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading)
            .background(visual.canvasPrimary)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("p2b-second-device-draft")
            .task(id: target.id) {
                if restore.currentTask == nil, restore.secondaryTask == nil {
                    restore.selectTarget(id: target.id)
                } else {
                    _ = restore.revalidateDraftIfSameDevice(for: target)
                    await restore.autoPrepareDraft(for: target)
                }
            }
            .onChange(of: target.connectionGeneration) { _, _ in
                _ = restore.revalidateDraftIfSameDevice(for: target)
            }
        }
    }

    /// UI-3.1：CANCELED 的只读准备态。绕开 devicePreparationLayout 的
    /// secondaryTask 抢占与 .task（selectTarget/autoPrepareDraft/revalidate）。
    private func canceledPreparationLayout(
        target: RestoreTarget,
        canceled: RestoreTaskSnapshot
    ) -> some View {
        let isPrimaryTask = canceled.attemptID
            == restore.lastCompletedTaskSnapshot?.attemptID
        let draft = restore.firmwareDraft(for: target)
        let status = restore.firmwareDraftStatus(for: target)
        let summary = prepSummary(
            target: target,
            draft: draft,
            primaryMode: isPrimaryTask)
        return VStack(spacing: 0) {
            prepIdentitySection(target: target)
            prepDivider
            prepEffectiveFirmwareSection(
                target: target,
                draft: draft,
                primaryMode: isPrimaryTask,
                summary: summary)
            prepDivider
            prepFirmwareLibrarySection(
                target: target,
                draft: draft,
                primaryMode: isPrimaryTask,
                summary: summary)
            prepDivider
            prepActionBar(
                target: target,
                draft: draft,
                status: status,
                primaryMode: isPrimaryTask,
                summary: summary)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading)
        .background(visual.canvasPrimary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ui3-canceled-prep")
    }

    private var prepDivider: some View {
        Rectangle()
            .fill(visual.hairline)
            .frame(height: visual.dividerThickness)
    }

    // MARK: - UI-2 四段式统一准备态

    private func prepActiveTaskBar(_ active: RestoreTaskSnapshot) -> some View {
        let progress = RestoreStageProgressPresentation(task: active)
        return HStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(visual.stateDFU)
            Text(L10n.t("A 正在 Restore") + " · "
                + active.target.portDisplayName + " · "
                + L10n.t(progress.phaseText))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(visual.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if restore.canCancelRestoreTask {
                Button(L10n.t("取消 A 的 Restore…")) {
                    pendingCancelAttemptID = restore.currentAttemptID
                    showCancelConfirmation = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("restore-cancel-visible")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(visual.stateDFU.opacity(0.10))
        .overlay(alignment: .bottom) {
            Rectangle().fill(visual.hairline).frame(height: 1)
        }
        .accessibilityIdentifier("p2b-active-task-bar")
    }

    private func prepIdentitySection(target: RestoreTarget) -> some View {
        let port = device.orderedDisplayPorts.first {
            $0.id == target.portKey
        }
        let repairCode = RepairCodeCatalog.aNumber(
            cpid: target.chipID,
            bdid: target.boardID)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(L10n.localizedPortName(target.portDisplayName))
                    .font(MRAFont.title(14))
                    .foregroundStyle(visual.textPrimary)
                    .lineLimit(1)
                    .accessibilityIdentifier("ui2-prep-identity")
                Text("·")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(visual.textTertiary)
                Text(L10n.t(target.displayName)
                    + (repairCode.map { " (\($0))" } ?? ""))
                    .font(MRAFont.body(13))
                    .foregroundStyle(visual.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
                prepModeBadge(target.mode)
                Spacer(minLength: 4)
            }
            HStack(spacing: 12) {
                prepMonoField(
                    "ECID",
                    target.canonicalHex,
                    emphasized: true,
                    copyValue: target.canonicalHex,
                    decimalValue: UInt64(target.canonicalHex, radix: 16)
                        .map(String.init))
                prepMonoField(
                    "BoardID",
                    hexOrMissing(target.boardID),
                    copyValue: target.boardID.map { String(format: "0x%X", $0) })
                prepMonoField(
                    "ChipID",
                    hexOrMissing(target.chipID),
                    copyValue: target.chipID.map { String(format: "0x%X", $0) })
                prepMonoField(
                    "PortNumber",
                    port.map { "\($0.portNumber)" } ?? missingValue)
                prepMonoField("RID", port.map { "\($0.rid)" } ?? missingValue)
                Spacer(minLength: 0)
            }
            if !copiedIdentityNotice.isEmpty {
                Text(L10n.t("已复制") + " " + copiedIdentityNotice)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(visual.stateSuccess)
                    .accessibilityIdentifier("identity-copy-toast")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func prepModeBadge(_ mode: ObservedDeviceMode) -> some View {
        let tone: Color
        switch mode {
        case .dfu: tone = visual.stateDFU
        case .recovery: tone = visual.accentPrimary
        case .connected: tone = visual.stateSuccess
        case .unknown: tone = visual.stateNeutral
        }
        return Text(L10n.t(mode.title))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tone)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(tone.opacity(0.12), in: Capsule())
    }

    private func prepMonoField(
        _ label: String,
        _ value: String,
        emphasized: Bool = false,
        copyValue: String? = nil,
        decimalValue: String? = nil,
        annotation: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(visual.textTertiary)
                .lineLimit(1)
            Text(value)
                .font(MRAFont.mono(MRAFont.monoSmallSize))
                .foregroundStyle(
                    emphasized ? visual.textPrimary : visual.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .textSelection(.enabled)
            if let annotation {
                Text(annotation)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(visual.textTertiary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard let copyValue else { return }
            copyIdentity(label, copyValue)
        }
        .contextMenu {
            if let copyValue, let decimalValue {
                Button(L10n.t("复制十六进制")) { copyIdentity(label, copyValue) }
                Button(L10n.t("复制十进制")) { copyIdentity(label, decimalValue) }
            } else if let copyValue {
                Button(L10n.t("复制")) { copyIdentity(label, copyValue) }
            }
        }
        .accessibilityIdentifier("identity-field-\(label)")
    }

    private func copyIdentity(_ label: String, _ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copiedIdentityNotice = label
        copyNoticeTask?.cancel()
        copyNoticeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            copiedIdentityNotice = ""
        }
    }

    private var missingValue: String { L10n.t("未获取") }

    private func hexOrMissing(_ value: Int?) -> String {
        guard let value else { return missingValue }
        return String(format: "0x%X", value)
    }

    private func prepSummary(
        target: RestoreTarget,
        draft: RestoreFirmwareDraft?,
        primaryMode: Bool
    ) -> UI2PreparationSummary {
        if primaryMode {
            return UI2PreparationSummary(
                fileName: restore.firmwareURL?.lastPathComponent,
                versionText: prepVersionText(
                    restore.firmwareMetadata?.productVersion,
                    restore.firmwareMetadata?.productBuild),
                sourceText: prepSourceText(primaryMode: true),
                preferenceIssue: restore.firmwarePreferenceIssue)
        }
        return UI2PreparationSummary(
            fileName: draft?.firmwareDisplayName,
            versionText: prepVersionText(
                draft?.productVersion,
                draft?.productBuild),
            sourceText: L10n.t("未获取"),
            preferenceIssue: restore.firmwarePreferenceIssue)
    }

    private func prepVersionText(
        _ version: String?,
        _ build: String?
    ) -> String? {
        guard version != nil || build != nil else { return nil }
        return (version ?? L10n.t("版本未知"))
            + " · " + (build ?? L10n.t("Build 未知"))
    }

    /// A 来源必须 manual-first；B 没有可信来源字段，固定 `未获取`。
    private func prepSourceText(primaryMode: Bool) -> String {
        guard primaryMode else { return L10n.t("未获取") }
        if restore.firmwareSelectionSource == .userManualSelected {
            return L10n.t("手动选择")
        }
        if let recommendation = restore.recommendedFirmware {
            return firmwareSourceLabel(recommendation)
        }
        return L10n.t("未获取")
    }

    private func prepEffectiveFirmwareSection(
        target: RestoreTarget,
        draft: RestoreFirmwareDraft?,
        primaryMode: Bool,
        summary: UI2PreparationSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(L10n.t("当前生效固件"))
                    .font(MRAFont.label(11))
                    .tracking(0.35)
                    .foregroundStyle(visual.textSecondary)
                    .accessibilityIdentifier("ui2-prep-effective-ipsw")
                Spacer(minLength: 4)
                if primaryMode {
                    Button(L10n.t("手动选择 IPSW…")) {
                        showFileImporter = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(
                        restore.isRestoreTaskActive
                            || restore.isLoadingFirmware)
                    if restore.firmwareSelectionSource == .userManualSelected {
                        Button(L10n.t("恢复自动推荐")) {
                            restore.restoreAutomaticRecommendation()
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 10.5, weight: .medium))
                        .disabled(restore.isRestoreTaskActive)
                    }
                } else {
                    Button(L10n.t("手动选择 IPSW…")) {
                        chooseDraftFirmware(for: target)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(
                        restore.isTaskActive(for: target)
                            || restore.isLoadingFirmware)
                }
            }

            prepPreferenceIssueBannerIfNeeded(summary, target: target)

            if let fileName = summary.fileName {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fileName)
                        .font(MRAFont.title(14))
                        .foregroundStyle(visual.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .help(fileName)
                    HStack(spacing: 6) {
                        if let versionText = summary.versionText {
                            Text(versionText)
                                .font(MRAFont.mono(11))
                                .foregroundStyle(visual.textSecondary)
                        }
                        if let sourceText = summary.sourceText {
                            prepTag(
                                L10n.t("来源") + " " + sourceText,
                                tone: visual.textTertiary)
                        }
                        if primaryMode {
                            prepTag(
                                prepValidityLabel(restore.firmwareValidity),
                                tone: prepValidityTone(restore.firmwareValidity))
                            prepTag(
                                prepCompatibilityLabel(
                                    restore.hardwareCompatibility.status),
                                tone: prepCompatibilityTone(
                                    restore.hardwareCompatibility.status))
                        } else if let draft {
                            prepTag(
                                prepValidityLabel(draft.validity),
                                tone: prepValidityTone(draft.validity))
                            prepTag(
                                prepCompatibilityLabel(draft.compatibility.status),
                                tone: prepCompatibilityTone(
                                    draft.compatibility.status))
                        }
                        Spacer(minLength: 0)
                    }
                    let compatibilityMessage = primaryMode
                        ? restore.hardwareCompatibility.message
                        : (draft?.compatibility.message ?? "")
                    if !compatibilityMessage.isEmpty {
                        Text(L10n.t(compatibilityMessage))
                            .font(.system(size: 10.5))
                            .foregroundStyle(
                                primaryMode
                                    ? prepCompatibilityTone(
                                        restore.hardwareCompatibility.status)
                                    : prepCompatibilityTone(
                                        draft?.compatibility.status ?? .unverified))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let reference = restore.successDurationReference(
                        for: target,
                        productVersion: primaryMode
                            ? restore.firmwareMetadata?.productVersion
                            : draft?.productVersion,
                        productBuild: primaryMode
                            ? restore.firmwareMetadata?.productBuild
                            : draft?.productBuild) {
                        Text(L10n.t("参考上次成功") + " " + durationText(reference.seconds))
                            .font(MRAFont.mono(10))
                            .foregroundStyle(visual.textTertiary)
                            .help(referenceHelp(reference))
                            .accessibilityIdentifier("restore-success-reference")
                    }
                }
            } else {
                Text(primaryMode
                    ? L10n.t("尚未选择固件；请从下方固件库选择。")
                    : L10n.t("还没有为这台设备准备固件。"))
                    .font(MRAFont.body(12))
                    .foregroundStyle(visual.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let finished = restore.lastSecondaryTaskSnapshot,
               finished.target.id == target.id {
                secondaryResultCard(finished)
            } else if let finished = restore.lastCompletedTaskSnapshot,
                      finished.target.id == target.id {
                primaryResultCard(finished)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func prepPreferenceIssueBannerIfNeeded(
        _ summary: UI2PreparationSummary,
        target: RestoreTarget
    ) -> some View {
        if summary.showsPreferenceIssue {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(visual.stateError)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("默认固件不可用"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(visual.stateError)
                    Text(L10n.t(summary.preferenceIssue))
                        .font(.system(size: 11))
                        .foregroundStyle(visual.stateError)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.t("请重新选择 IPSW，或恢复自动推荐。"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(visual.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L10n.t("清除失效默认")) {
                        if summary.preferenceIssue.contains("全局") {
                            restore.clearGlobalFirmwareDefault()
                        } else if let key = ModelFamilyKey.resolve(
                            identity: target.firmwareIdentity) {
                            restore.clearModelFirmwareDefault(for: key)
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10.5, weight: .medium))
                    .accessibilityIdentifier("clear-invalid-firmware-default")
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(
                visual.stateError.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        visual.stateError.opacity(0.25),
                        lineWidth: 1)
            }
            .accessibilityIdentifier("ui2-prep-preference-issue")
        }
    }

    private func prepTag(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(tone)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(
                tone.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 3))
            .lineLimit(1)
    }

    private func prepValidityLabel(_ validity: IPSWFileValidity) -> String {
        switch validity {
        case .valid: return L10n.t("有效")
        case .unverified: return L10n.t("未验证")
        case .invalid: return L10n.t("无效")
        }
    }

    private func prepValidityTone(_ validity: IPSWFileValidity) -> Color {
        switch validity {
        case .valid: return visual.stateSuccess
        case .unverified: return visual.stateDFU
        case .invalid: return visual.stateError
        }
    }

    private func prepCompatibilityTone(
        _ status: HardwareCompatibilityStatus
    ) -> Color {
        switch status {
        case .compatible: return visual.stateSuccess
        case .unverified: return visual.stateDFU
        case .incompatible: return visual.stateError
        }
    }

    private func prepFirmwareLibrarySection(
        target: RestoreTarget,
        draft: RestoreFirmwareDraft?,
        primaryMode: Bool,
        summary: UI2PreparationSummary
    ) -> some View {
        let highlightID = primaryMode
            ? restore.firmwareLibraryEntryID
            : draft?.libraryEntryID
        return UI2FirmwareLibraryList(
            entries: restore.firmwareLibraryEntries,
            target: target,
            highlightID: highlightID,
            primaryMode: primaryMode,
            sourceText: summary.sourceText,
            isRestoreTaskActive: restore.isRestoreTaskActive,
            visual: visual,
            isScanning: restore.isFirmwareDiscoveryActive,
            onSelect: { entry in
                restore.selectFirmwareFromLibrary(id: entry.id)
            },
            onPrepare: { entry in
                Task { @MainActor in
                    _ = await restore.prepareFirmwareDraft(
                        for: target,
                        url: entry.url)
                }
            },
            onAddDirectory: { chooseFirmwareDirectory() },
            onRescan: { restore.startFirmwareDiscovery() },
            onSetModelDefault: { entry in
                if let key = ModelFamilyKey.resolve(
                    identity: target.firmwareIdentity) {
                    _ = restore.setModelFirmwareDefault(
                        entryID: entry.id,
                        modelFamilyKey: key)
                }
            },
            onSetGlobalDefault: { entry in
                _ = restore.setGlobalFirmwareDefault(entryID: entry.id)
            })
        .frame(maxHeight: .infinity)
    }

    private func prepCompatibilityLabel(
        _ status: HardwareCompatibilityStatus
    ) -> String {
        switch status {
        case .compatible: return L10n.t("兼容")
        case .unverified: return L10n.t("未验证")
        case .incompatible: return L10n.t("不兼容")
        }
    }

    private var prepRLMConflict: Bool {
        restore.currentTask.map { current in
            current.rlmOwnership != .notRequested
                || current.rlmStatus == .recordingReused
                || current.rlmStatus == .startedOwnedSession
                || current.rlmRawLogURL != nil
        } ?? false
    }

    private func rawLogExplanation(_ draftMessage: String) -> String {
        var parts = [
            L10n.t("只作用于下一次 Restore；关闭时不创建 raw/Staging 副本。"),
            L10n.t("原始日志按当前保存设置写入此任务自己的目录；本任务不启动独立 RLM 采集。")
        ]
        if !draftMessage.isEmpty { parts.append(draftMessage) }
        if !restore.errorMessage.isEmpty { parts.append(restore.errorMessage) }
        return parts.joined(separator: "\n")
    }

    private func statusAccessibilityValue(_ draftMessage: String) -> String {
        [restore.errorMessage, draftMessage]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func prepActionBar(
        target: RestoreTarget,
        draft: RestoreFirmwareDraft?,
        status: RestoreFirmwareDraftStatus?,
        primaryMode: Bool,
        summary: UI2PreparationSummary,
        allowStart: Bool = true
    ) -> some View {
        let rlmConflict = prepRLMConflict
        let targetIsSelected = restore.selectedTarget?.id == target.id
        let restartPrimaryWhileSecondary = allowStart
            && primaryMode
            && restore.currentTask == nil
            && restore.secondaryTask != nil
            && targetIsSelected
            && restore.availableTargets.contains { $0.id == target.id }
            && restore.firmwareURL != nil
            && restore.firmwareValidity == .valid
            && restore.firmwareFileIdentity != nil
            && restore.hardwareCompatibility.status == .compatible
            && restore.taskRegistry.activeCount < 2
            && !restore.isLoadingFirmware
        let canStart: Bool
        if !allowStart {
            canStart = false
        } else if primaryMode {
            canStart = targetIsSelected
                && (restore.canStartRestore
                    || restartPrimaryWhileSecondary)
                && restore.taskRegistry.activeCount < 2
                && restore.hardwareCompatibility.status == .compatible
        } else {
            canStart = status == .ready
                && draft?.compatibility.status == .compatible
                && restore.taskRegistry.activeCount < 2
                && (restore.taskRegistry.activeCount == 0
                    || restore.currentTask != nil)
                && !rlmConflict
        }
        let reason = allowStart
            ? prepBlockedReason(
                target: target,
                status: status,
                primaryMode: primaryMode,
                rlmConflict: rlmConflict)
            : L10n.t("任务已结束，请返回准备态确认后重新开始。")
        let draftMessage = primaryMode
            ? ""
            : restore.firmwareDraftMessage(for: target)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle(
                    L10n.t("保存本次 Restore 原始日志"),
                    isOn: Binding(
                        get: { restore.rawSaveRequested(for: target) },
                        set: { restore.setRawSaveRequested($0, for: target) }))
                    .toggleStyle(.checkbox)
                    .disabled(restore.isTaskActive(for: target))
                    .accessibilityIdentifier(
                        primaryMode
                            ? "restore-save-raw-this-run"
                            : "restore-save-raw-this-run-secondary")
                Image(systemName: "info.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(visual.textTertiary)
                    .help(rawLogExplanation(draftMessage))
                    .accessibilityLabel(L10n.t("原始日志说明"))
                    .accessibilityIdentifier("ui2-prep-raw-info")
                Spacer(minLength: 6)
                Button {
                    startFailureMessage = ""
                    guard restore.freezeRestoreConfirmation(
                        targetID: target.id) else {
                        startFailureMessage = restore.errorMessage.isEmpty
                            ? L10n.t("Restore 未能启动，请检查目标设备与固件兼容性。")
                            : restore.errorMessage
                        return
                    }
                    pendingSecondaryTargetID = target.id
                    showSecondaryStartConfirmation = true
                } label: {
                    Label(
                        L10n.t(canStart
                            ? "开始 Restore…"
                            : "当前无法开始 Restore"),
                        systemImage: canStart ? "play.fill" : "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canStart)
                .accessibilityIdentifier("secondary-start-button")
            }
            if canStart {
                Text(L10n.t("固件准备完成，可启动此设备。"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(visual.stateSuccess)
                    .lineLimit(1)
                    .help(statusAccessibilityValue(draftMessage))
                    .accessibilityValue(Text(statusAccessibilityValue(draftMessage)))
                    .accessibilityIdentifier("ui2-prep-action-bar")
            } else {
                Text(reason)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(visual.stateDFU)
                    .lineLimit(1)
                    .help(statusAccessibilityValue(draftMessage))
                    .accessibilityValue(Text(statusAccessibilityValue(draftMessage)))
                    .accessibilityIdentifier("ui2-prep-action-bar")
            }
            if !startFailureMessage.isEmpty {
                Text(L10n.t(startFailureMessage))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(visual.stateError)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ui2-prep-start-error")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(visual.surfaceSubtle)
        .overlay(alignment: .top) {
            Rectangle().fill(visual.hairlineStrong).frame(height: 1)
        }
    }

    private func unverifiedCompatibilityReason(target: RestoreTarget) -> String {
        var missing: [String] = []
        if target.productType == nil { missing.append("ProductType") }
        if target.deviceClass == nil { missing.append("DeviceClass") }
        if target.boardID == nil { missing.append("BoardID") }
        if target.chipID == nil { missing.append("ChipID") }
        if missing.isEmpty {
            return L10n.t("兼容性未验证，不能开始 Restore；请检查固件与设备身份。")
        }
        return L10n.t("兼容性未验证，缺少：")
            + missing.joined(separator: "、")
            + L10n.t("；不能开始 Restore。")
    }

    private func prepBlockedReason(
        target: RestoreTarget,
        status: RestoreFirmwareDraftStatus?,
        primaryMode: Bool,
        rlmConflict: Bool
    ) -> String {
        if primaryMode {
            let reason = restore.startDisabledReason
            if !reason.isEmpty { return L10n.t(reason) }
            if restore.hardwareCompatibility.status == .unverified {
                return unverifiedCompatibilityReason(target: target)
            }
            if restore.taskRegistry.activeCount >= 2 {
                return L10n.t("已有两个 Restore 任务在执行。")
            }
            return L10n.t("当前无法开始 Restore")
        }
        if let status, status != .ready {
            return draftStatusText(status)
        }
        if restore.taskRegistry.activeCount >= 2 {
            return L10n.t("已有两个 Restore 任务在执行。")
        }
        if restore.taskRegistry.activeCount > 0,
           restore.currentTask == nil {
            return L10n.t("需要 A 已越过目标/日志确认、B 草稿 ready、设备与端口唯一。")
        }
        if rlmConflict {
            return L10n.t("另一台正在使用独立 RLM 日志，此设备将被拒绝启动。")
        }
        if let draft = restore.firmwareDraft(for: target) {
            if draft.compatibility.status == .unverified {
                return unverifiedCompatibilityReason(target: target)
            }
            if draft.compatibility.status == .incompatible {
                return L10n.t(draft.compatibility.message)
            }
            if draft.validity != .valid {
                return L10n.t("固件未通过验证，不能用于启动。")
            }
        }
        return L10n.t("需要 A 已越过目标/日志确认、B 草稿 ready、设备与端口唯一。")
    }


    @ViewBuilder
    private func primaryResultCard(_ finished: RestoreTaskSnapshot) -> some View {
        prepResultRow(finished, exportIdentifier: "raw-export-button")
    }

    @ViewBuilder
    private func secondaryResultCard(_ finished: RestoreTaskSnapshot) -> some View {
        prepResultRow(finished, exportIdentifier: "raw-export-button-b")
    }

    /// UI-2：结果条保留原信息与导出入口，但改为 1px 分隔的紧凑行，不再套卡片。
    private func prepResultRow(
        _ finished: RestoreTaskSnapshot,
        exportIdentifier: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(L10n.t("设备最近结果"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(visual.textSecondary)
                .lineLimit(1)
            Text(L10n.t(
                "任务 \(finished.attemptID.uuidString.prefix(8)) · \(finished.outcome?.rawValue ?? "UNKNOWN")"))
                .font(MRAFont.mono(10))
                .foregroundStyle(visual.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let archive = finished.rawArchive {
                Button(L10n.t("导出原始日志…")) {
                    exportRawArchive(attemptID: archive.attemptID)
                }
                .buttonStyle(.link)
                .font(.system(size: 10, weight: .medium))
                .accessibilityIdentifier(exportIdentifier)
                .help(archive.directoryPath)
            } else if !finished.rawArchiveMessage.isEmpty {
                Text(L10n.t(finished.rawArchiveMessage))
                    .font(.system(size: 9.5))
                    .foregroundStyle(visual.stateDFU)
                    .lineLimit(1)
            } else if !finished.rawPersistencePolicy.saveThisRun {
                Text(L10n.t("本次未保存完整原始日志。"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(visual.textTertiary)
                    .lineLimit(1)
            } else {
                Text(L10n.t("正在整理原始日志，稍后可导出。"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(visual.stateDFU)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .top) {
            Rectangle().fill(visual.hairline).frame(height: 1)
        }
    }

    private func secondaryLiveLayout(
        _ task: RestoreTaskSnapshot,
        target: RestoreTarget
    ) -> some View {
        ui3TaskWorkspace(task)
    }

    /// 纯 View 路由：任务结束后通过“查看任务”（viewedTaskID）或查看对应
    /// 物理端口（viewedPortKey）回看冻结终态；不改变任何设备/任务状态。
    private var ui3FinishedTaskForViewing: RestoreTaskSnapshot? {
        let candidates = [
            restore.lastCompletedTaskSnapshot,
            restore.lastSecondaryTaskSnapshot,
            restore.currentTask,
            restore.secondaryTask
        ].compactMap { $0 }
        var match: RestoreTaskSnapshot?
        if let id = viewedTaskID {
            match = candidates.first {
                $0.id == id && $0.outcome != nil
            }
        }
        if match == nil, let portKey = viewedPortKey {
            match = candidates.first {
                $0.outcome != nil && $0.target.portKey == portKey
            }
        }
        guard let finished = match,
              finished.outcome != .canceled,
              ui3DismissedFinishedTaskID != finished.id else { return nil }
        return finished
    }

    /// CANCELED 已在底层确认结束：自动回到该端口的只读准备态，不重用
    /// devicePreparationLayout（避免 secondaryTask 抢占与 .task 模型副作用）。
    private var ui3CanceledTaskForPreparation: RestoreTaskSnapshot? {
        let canceled = [
            restore.lastCompletedTaskSnapshot,
            restore.lastSecondaryTaskSnapshot
        ].compactMap { $0 }.filter { $0.outcome == .canceled }
        if let id = viewedTaskID,
           let match = canceled.first(where: { $0.id == id }) {
            return match
        }
        if let portKey = viewedPortKey,
           let match = canceled.first(where: {
               $0.target.portKey == portKey
           }) {
            return match
        }
        return nil
    }

    /// UI-3：A/B 共用的统一运行/终态工作台。
    private func ui3TaskWorkspace(_ task: RestoreTaskSnapshot) -> some View {
        let isPrimary = ui3IsPrimary(task)
        let isTerminal = task.outcome != nil
        return VStack(spacing: 0) {
            ui3IdentityHeader(task)
            ui3Divider
            if !isTerminal {
                ui3ProgressAndControls(task, isPrimary: isPrimary)
                ui3Divider
                UI3LiveLogView(task: task, visual: visual)
                    .id(task.attemptID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                UI3LiveLogView(task: task, visual: visual)
                    .id(task.attemptID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ui3TerminalOutcome(task, isPrimary: isPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading)
        .background(visual.canvasPrimary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("secondary-live-task")
    }

    private var ui3Divider: some View {
        Rectangle()
            .fill(visual.hairline)
            .frame(height: visual.dividerThickness)
    }

    private func ui3IdentityHeader(
        _ task: RestoreTaskSnapshot
    ) -> some View {
        let port = device.orderedDisplayPorts.first {
            $0.id == task.target.portKey
        }
        let slot = port.flatMap {
            device.uniquelyMappedBuiltInSlot(for: $0)?.slot
        }
        let portTitle = slot
            ?? L10n.localizedPortName(task.target.portDisplayName)
        let version = ui3VersionText(task)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Text(portTitle)
                    .font(MRAFont.title(14))
                    .foregroundStyle(visual.textPrimary)
                    .lineLimit(1)
                Text("·")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(visual.textTertiary)
                Text(L10n.t(task.target.displayName))
                    .font(MRAFont.body(13))
                    .foregroundStyle(visual.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
                prepModeBadge(task.target.mode)
                ui3StateBadge(task)
                Spacer(minLength: 4)
            }
            HStack(spacing: 10) {
                Text("ECID " + task.target.canonicalHex)
                    .font(MRAFont.mono(11.5))
                    .foregroundStyle(visual.textPrimary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                Text(task.ipswURL.lastPathComponent)
                    .font(MRAFont.mono(10.5))
                    .foregroundStyle(visual.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(task.ipswURL.lastPathComponent)
                    .textSelection(.enabled)
                if let version {
                    Text(version)
                        .font(MRAFont.mono(10))
                        .foregroundStyle(visual.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button {
                    copyAttemptUUID(task.attemptID)
                } label: {
                    HStack(spacing: 3) {
                        Text("ATTEMPT "
                            + String(task.attemptID.uuidString.prefix(8)))
                            .font(MRAFont.mono(10))
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(visual.textTertiary)
                }
                .buttonStyle(.plain)
                .help(L10n.t("复制完整 attempt UUID")
                    + ": " + task.attemptID.uuidString)
                .accessibilityLabel(L10n.t("复制完整 attempt UUID"))
                .accessibilityIdentifier("ui3-copy-attempt-uuid")
            }
            ui3TaskDetails(task)
        }
        .padding(.horizontal, 14)
        .padding(.top, 7)
        .padding(.bottom, 5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ui3-task-identity")
    }

    private func ui3IsPrimary(_ task: RestoreTaskSnapshot) -> Bool {
        if let current = restore.currentAttemptID {
            return task.attemptID == current
        }
        if let last = restore.lastCompletedTaskSnapshot {
            return task.attemptID == last.attemptID
        }
        return true
    }

    private func ui3FrozenDurationText(
        _ task: RestoreTaskSnapshot
    ) -> String {
        if let seconds = task.lifecycle.processWallDurationSeconds {
            return durationText(seconds)
        }
        if let seconds = RestoreLifecycleClock.seconds(
            from: task.lifecycle.processLaunched,
            to: task.lifecycle.processExited) {
            return durationText(seconds)
        }
        if let finished = task.finishedAt {
            let start = task.processStartedAt ?? task.userConfirmedAt
            return durationText(max(0, finished.timeIntervalSince(start)))
        }
        return L10n.t("未获取")
    }

    private func ui3VersionText(_ task: RestoreTaskSnapshot) -> String? {
        let version = task.metadata?.productVersion
        let build = task.metadata?.productBuild
        guard version != nil || build != nil else { return nil }
        return (version ?? L10n.t("版本未知"))
            + " · " + (build ?? L10n.t("Build 未知"))
    }

    private func ui3TaskDetails(_ task: RestoreTaskSnapshot) -> some View {
        DisclosureGroup(L10n.t("任务详情")) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ATTEMPT " + task.attemptID.uuidString)
                Text(L10n.t(
                    "RLM：\(L10n.t(rlmTitle(task.rlmStatus))) · 真实阶段：\(ui3PhaseTitle(task))"))
                if !task.buildManifestSHA256.isEmpty {
                    Text("BuildManifest SHA-256: \(task.buildManifestSHA256)")
                }
                if let whole = task.wholeFileSHA256, !whole.isEmpty {
                    Text("IPSW SHA-256: \(whole)")
                }
                Text(L10n.t(
                    task.rawPersistencePolicy.saveThisRun
                        ? "本次原始日志：已请求保存"
                        : "本次原始日志：未保存"))
                Text(L10n.t(
                    "控制目标不会被左侧端口或右侧查看端口切换"))
            }
            .font(MRAFont.mono(9.5))
            .foregroundStyle(visual.textSecondary)
            .textSelection(.enabled)
            .padding(.top, 4)
            .accessibilityIdentifier("ui3-task-details")
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(visual.textTertiary)
    }

    private func ui3StateBadge(_ task: RestoreTaskSnapshot) -> some View {
        if let outcome = task.outcome {
            return AnyView(ui3OutcomeBadge(outcome))
        }
        let text: String
        let tone: Color
        if task.cancellationRequested {
            text = L10n.t("正在取消")
            tone = visual.stateDFU
        } else {
            text = L10n.t(ui3PhaseTitle(task))
            tone = UI3RunningColors.progress
        }
        return AnyView(
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tone)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(tone.opacity(0.12), in: Capsule()))
    }

    private func ui3OutcomeBadge(_ outcome: RestoreOutcome) -> some View {
        let text: String
        let tone: Color
        switch outcome {
        case .success:
            text = "SUCCESS"; tone = visual.stateSuccess
        case .failure:
            text = "FAILED"; tone = visual.stateError
        case .canceled:
            text = "CANCELED"; tone = visual.textSecondary
        case .unknown:
            text = "UNKNOWN"; tone = visual.stateDFU
        }
        return Text(text)
            .font(MRAFont.mono(10))
            .foregroundStyle(tone)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(tone.opacity(0.12), in: Capsule())
    }

    private func ui3PhaseTitle(_ task: RestoreTaskSnapshot) -> String {
        if task.processStartedAt == nil {
            return task.cancellationRequested
                ? "正在取消恢复准备"
                : "恢复启动准备中"
        }
        return phaseTitle(task.phase)
    }

    private func ui3ProgressAndControls(
        _ task: RestoreTaskSnapshot,
        isPrimary: Bool
    ) -> some View {
        let progress = RestoreStageProgressPresentation(task: task)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                Text(L10n.t(progress.phaseText))
                    .font(MRAFont.label(12))
                    .foregroundStyle(visual.textPrimary)
                    .lineLimit(1)
                ui3ProgressBar(progress)
                if let fraction = progress.stageFraction {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(MRAFont.mono(11))
                        .foregroundStyle(UI3RunningColors.progress)
                        .monospacedDigit()
                } else {
                    Text(L10n.t("进行中"))
                        .font(MRAFont.mono(10.5))
                        .foregroundStyle(UI3RunningColors.progress)
                }
                Spacer(minLength: 4)
                HStack(spacing: 3) {
                    Text(L10n.t("已执行"))
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(runDurationText(task))
                    }
                }
                .font(MRAFont.mono(10.5))
                .foregroundStyle(visual.textSecondary)
                if let reference = restore.successDurationReference(
                    for: task.target,
                    metadata: task.metadata) {
                    Text(L10n.t("参考上次成功") + " " + durationText(reference.seconds))
                        .font(MRAFont.mono(10))
                        .foregroundStyle(UI3RunningColors.progress)
                        .help(referenceHelp(reference))
                        .accessibilityIdentifier("ui3-success-reference")
                }
            }
            if let fraction = progress.stageFraction,
               fraction == 0,
               task.stepText.localizedCaseInsensitiveContains("安装系统")
                || task.stepText.localizedCaseInsensitiveContains("Installing system") {
                Text(L10n.t("正在解压/校验固件，首次进度更新可能需要数分钟…"))
                    .font(.system(size: 10))
                    .foregroundStyle(UI3RunningColors.terminalText.opacity(0.62))
                    .accessibilityIdentifier("ui3-zero-percent-hint")
            }
            if !progress.detailText.isEmpty {
                Text(L10n.t(progress.detailText))
                    .font(.system(size: 10))
                    .foregroundStyle(visual.textTertiary)
                    .lineLimit(2)
            }
            HStack(spacing: 7) {
                Text(ui3ControlHint(task))
                    .font(.system(size: 10))
                    .foregroundStyle(
                        task.cancellationRequested
                            ? visual.stateDFU
                            : visual.textTertiary)
                    .lineLimit(2)
                Spacer(minLength: 4)
                if ui3CanCancel(task, isPrimary: isPrimary) {
                    Button(L10n.t("取消 Restore…")) {
                        ui3RequestCancel(task, isPrimary: isPrimary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(visual.stateError)
                    .accessibilityIdentifier("restore-cancel-visible")
                }
                if ui3ShowsForceKill(task, isPrimary: isPrimary) {
                    Button(L10n.t("强制结束…")) {
                        ui3RequestForceKill(task, isPrimary: isPrimary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(visual.stateError)
                    .accessibilityIdentifier("restore-force-kill-visible")
                }
                if let directory = task.rawOutputDirectory {
                    Button(L10n.t("打开原始日志目录")) {
                        NSWorkspace.shared.open(directory)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!FileManager.default.fileExists(atPath: directory.path))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ui3-task-progress")
    }

    @ViewBuilder
    private func ui3ProgressBar(
        _ progress: RestoreStageProgressPresentation
    ) -> some View {
        if let fraction = progress.stageFraction {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(visual.hairline)
                    Capsule()
                        .fill(UI3RunningColors.progress)
                        .frame(
                            width: max(
                                2,
                                geo.size.width * CGFloat(fraction)))
                }
            }
            .frame(height: 5)
            .frame(maxWidth: 250)
        } else if progress.isIndeterminate {
            ProgressView()
                .progressViewStyle(.linear)
                .tint(UI3RunningColors.progress)
                .frame(maxWidth: 250)
        } else {
            Capsule()
                .fill(visual.hairline)
                .frame(height: 5)
                .frame(maxWidth: 250)
        }
    }

    private func ui3ControlHint(_ task: RestoreTaskSnapshot) -> String {
        if task.cancellationRequested {
            return L10n.t("正在取消：已发送中断信号，等待进程退出…")
        }
        return L10n.t(
            task.processStartedAt == nil
                ? "Restore 启动准备中；cfgutil 尚未确认运行。"
                : "Restore 正在执行；取消入口保持可见。")
    }

    private func ui3CanCancel(
        _ task: RestoreTaskSnapshot,
        isPrimary: Bool
    ) -> Bool {
        if isPrimary {
            return task.attemptID == restore.currentAttemptID
                && restore.canCancelRestoreTask
        }
        return task.outcome == nil
            && task.attemptID == restore.secondaryTask?.attemptID
    }

    private func ui3ShowsForceKill(
        _ task: RestoreTaskSnapshot,
        isPrimary: Bool
    ) -> Bool {
        guard task.cancellationGraceExpired else { return false }
        if isPrimary {
            return restore.isRestoring
                && restore.canCancelRestoreTask
        }
        return task.outcome == nil
    }

    private func ui3RequestCancel(
        _ task: RestoreTaskSnapshot,
        isPrimary: Bool
    ) {
        if isPrimary {
            pendingCancelAttemptID = task.attemptID
            showCancelConfirmation = true
        } else {
            pendingSecondaryCancelAttemptID = task.attemptID
            secondaryCancelDeviceLabel = task.target.displayName
            secondaryCancelPortLabel = task.target.portDisplayName
            showSecondaryCancelConfirmation = true
        }
    }

    private func ui3RequestForceKill(
        _ task: RestoreTaskSnapshot,
        isPrimary: Bool
    ) {
        if isPrimary {
            pendingForceKillAttemptID = task.attemptID
            showForceKillConfirmation = true
        } else {
            pendingSecondaryForceKillAttemptID = task.attemptID
            secondaryForceKillDeviceLabel = task.target.displayName
            secondaryForceKillPortLabel = task.target.portDisplayName
            showSecondaryForceKillConfirmation = true
        }
    }

    @ViewBuilder
    private func ui3TerminalOutcome(
        _ task: RestoreTaskSnapshot,
        isPrimary: Bool
    ) -> some View {
        if let outcome = task.outcome {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    ui3OutcomeBadge(outcome)
                    HStack(spacing: 3) {
                        Text(L10n.t("执行耗时"))
                        Text(ui3FrozenDurationText(task))
                    }
                    .font(MRAFont.mono(10.5))
                    .foregroundStyle(visual.textSecondary)
                    if let exit = task.exitCode {
                        Text("exit \(exit)")
                            .font(MRAFont.mono(10))
                            .foregroundStyle(
                                outcome == .success
                                    ? visual.stateSuccess
                                    : visual.stateError)
                    }
                    Spacer(minLength: 4)
                    if let archive = task.rawArchive {
                        Button(L10n.t("导出原始日志…")) {
                            exportRawArchive(attemptID: archive.attemptID)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier(
                            isPrimary
                                ? "raw-export-button"
                                : "raw-export-button-b")
                    }
                    if let directory = task.rawOutputDirectory {
                        Button(L10n.t("打开原始日志目录")) {
                            NSWorkspace.shared.open(directory)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!FileManager.default.fileExists(
                            atPath: directory.path))
                    }
                    if outcome == .failure {
                        Button(L10n.t("复制失败摘要")) {
                            copyFailureSummary(task)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("ui3-copy-failure-summary")
                    }
                    Button(L10n.t("返回准备")) {
                        ui3DismissedFinishedTaskID = task.id
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("ui3-terminal-back-to-prep")
                }
                if outcome == .failure {
                    HStack(spacing: 5) {
                        Text(L10n.t("失败阶段：") + ui3PhaseTitle(task))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(visual.stateError)
                        Text(task.failureText.isEmpty
                            ? L10n.t("未提供更多失败原因。")
                            : task.failureText)
                            .font(MRAFont.mono(10))
                            .foregroundStyle(visual.stateError)
                            .textSelection(.enabled)
                            .lineLimit(3)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else if outcome == .canceled {
                    Text(L10n.t("取消已确认；任务已结束。"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(visual.textSecondary)
                } else if outcome == .unknown {
                    Text(L10n.t("底层未给出可判定的终态；请以原始日志与归档为准。"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(visual.stateDFU)
                } else {
                    Text(L10n.t("任务已完成。"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(visual.stateSuccess)
                }
                if !task.failureText.isEmpty && outcome != .failure {
                    Text(task.failureText)
                        .font(MRAFont.mono(10))
                        .foregroundStyle(visual.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    Text("ATTEMPT " + task.attemptID.uuidString)
                        .font(MRAFont.mono(9.5))
                        .foregroundStyle(visual.textTertiary)
                        .textSelection(.enabled)
                    if let archive = task.rawArchive {
                        Text(archive.directoryPath)
                            .font(MRAFont.mono(9.5))
                            .foregroundStyle(visual.textTertiary)
                            .lineLimit(1)
                            .help(archive.directoryPath)
                    } else if !task.rawArchiveMessage.isEmpty {
                        Text(L10n.t(task.rawArchiveMessage))
                            .font(.system(size: 9.5))
                            .foregroundStyle(visual.stateDFU)
                            .lineLimit(2)
                    } else if !task.rawPersistencePolicy.saveThisRun {
                        Text(L10n.t("本次未保存完整原始日志。"))
                            .font(.system(size: 9.5))
                            .foregroundStyle(visual.textTertiary)
                    } else {
                        Text(L10n.t("正在写入原始证据与历史记录，导出暂不可用。"))
                            .font(.system(size: 9.5))
                            .foregroundStyle(visual.stateDFU)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(visual.surfaceSubtle)
            .overlay(alignment: .top) {
                Rectangle().fill(visual.hairlineStrong).frame(height: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ui3-terminal-outcome")
        }
    }

    private func copyFailureSummary(_ task: RestoreTaskSnapshot) {
        let target = task.target
        let aNumber = RepairCodeCatalog.aNumber(
            cpid: target.chipID,
            bdid: target.boardID)
        var lines = [
            "MRA Restore FAILED summary",
            "Model: \(target.displayName)" +
                (aNumber.map { " / \($0)" } ?? ""),
            "ProductType: \(target.productType ?? "未获取")",
            "ECID: \(target.canonicalHex)",
            "BoardID: \(target.boardID.map { String(format: "0x%X", $0) } ?? "未获取")",
            "ChipID: \(target.chipID.map { String(format: "0x%X", $0) } ?? "未获取")",
            "IPSW: \(task.ipswURL.lastPathComponent)",
            "Version/Build: \((task.metadata?.productVersion ?? "未获取")) / \((task.metadata?.productBuild ?? "未获取"))",
            "Failure stage: \(ui3PhaseTitle(task))",
            "Failure: \(task.failureText.isEmpty ? "未提供更多失败原因。" : task.failureText)",
            "Exit code: \(task.exitCode.map(String.init) ?? "未获取")"
        ]
        let tail = task.cfgutilOutputTail.suffix(20)
        if !tail.isEmpty {
            lines.append("Preview tail (last 20 lines):")
            lines.append(contentsOf: tail)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            lines.joined(separator: "\n"),
            forType: .string)
    }

    private func copyAttemptUUID(_ id: UUID) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id.uuidString, forType: .string)
    }


    private func savedDraftSection(target: RestoreTarget) -> some View {
        let draft = restore.firmwareDraft(for: target)
        let status = restore.firmwareDraftStatus(for: target)
        return sectionCard(title: L10n.t("已保存的 B 固件草稿")) {
            VStack(alignment: .leading, spacing: 6) {
                if let draft {
                    Text(draft.firmwareDisplayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(draftStatusText(status))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button(L10n.t("重新核验并载入")) {
                            Task { @MainActor in
                                restore.selectTarget(id: target.id)
                                guard restore.selectedTarget?.id == target.id else {
                                    restoreActionFeedback = L10n.t(
                                        "目标设备已变化，未载入草稿。")
                                    return
                                }
                                await restore.loadFirmware(url: draft.ipswURL)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            restore.isRestoreTaskActive
                                || (status != .ready
                                    && status != .requiresReverification))
                        Button(L10n.t("清除草稿")) {
                            restore.discardFirmwareDraft(for: target)
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                }
            }
        }
    }

    private func firmwareSourceLabel(_ recommendation: FirmwareRecommendation) -> String {
        switch recommendation.source {
        case .modelDefault: return L10n.t("机型默认")
        case .globalDefault, .unknownIdentityGlobalDefault: return L10n.t("全局默认")
        case .recentUsedCompatible: return L10n.t("最近使用")
        case .lastSelectedCompatible: return L10n.t("上次选择")
        case .userManualSelection: return L10n.t("手动选择")
        }
    }

    private func chooseDraftFirmware(for target: RestoreTarget) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [ipswType]
        panel.prompt = L10n.t("选择")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            await restore.prepareFirmwareDraft(for: target, url: url)
        }
    }

    @ViewBuilder
    private var navigationCandidateSection: some View {
        if let navigationContextPortID {
            let candidate = navigationCandidateTargetID.flatMap { targetID in
                restore.navigationTargetInventory.first {
                    $0.id == targetID
                }
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.down.right.circle")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("已确认 DFU，可继续准备 Restore"))
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(
                        L10n.t("操作端口：")
                        + navigationPortName(for: navigationContextPortID))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if let candidate {
                        Text(L10n.t(candidate.displayIdentity))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if restore.selectedTargetID == candidate.id {
                            Text(L10n.t("目标已选中；请选择本地 IPSW。"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        } else {
                            Button(L10n.t("准备此目标")) {
                                restore.selectTarget(id: candidate.id)
                                self.navigationCandidateTargetID = nil
                                self.navigationContextPortID = nil
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        Text(L10n.t("该物理端口已确认出现 DFU；尚无可唯一归属的 Restore 目标，请等待观察刷新。"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    self.navigationContextPortID = nil
                    self.navigationCandidateTargetID = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("关闭提示"))
            }
            .padding(10)
            .background(
                Color.accentColor.opacity(0.075),
                in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(
                        Color.accentColor.opacity(0.20),
                        lineWidth: 0.7)
            }
        }
    }

    private func navigationPortName(for portID: String) -> String {
        device.orderedDisplayPorts
            .first(where: { $0.id == portID })
            .map { L10n.localizedPortName(device.label(for: $0)) }
            ?? L10n.t("端口身份待确认")
    }

    private var activeRestoreLayout: some View {
        if restore.currentTask == nil, let secondary = restore.secondaryTask {
            return AnyView(secondaryLiveLayout(
                secondary,
                target: secondary.target))
        }
        if let viewedTarget,
           viewedTarget.id != restore.currentTask?.target.id {
            return AnyView(devicePreparationLayout(target: viewedTarget))
        }
        return AnyView(activeRestoreLayoutCore)
    }

    private var activeRestoreLayoutCore: some View {
        if let task = restore.currentTask ?? restore.displayedTask {
            return AnyView(ui3TaskWorkspace(task))
        }
        return AnyView(
            Text(L10n.t("当前没有可展示的 Restore 任务。"))
                .font(.system(size: 12))
                .foregroundStyle(visual.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity))
    }

    private func restoreLogResizeHandle(
        currentFraction: CGFloat,
        availableHeight: CGFloat
    ) -> some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(
                    restoreLogResizerHovered
                        ? Color.accentColor.opacity(0.7)
                        : Color.secondary.opacity(0.34))
                .frame(
                    width: restoreLogResizerHovered ? 44 : 36,
                    height: 3)
        }
        .frame(height: 10)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if restoreLogDragStartFraction == nil {
                        restoreLogDragStartFraction = restoreLogPanelFraction
                    }
                    restoreLogPanelFraction = RestoreLogPaneMetrics
                        .adjustedFraction(
                            startingAt: restoreLogDragStartFraction
                                ?? restoreLogPanelFraction,
                            translation: value.translation.height,
                            availableHeight: availableHeight)
                }
                .onEnded { _ in
                    restoreLogDragStartFraction = nil
                })
        .onHover { hovering in
            guard restoreLogResizerHovered != hovering else { return }
            restoreLogResizerHovered = hovering
            if hovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if restoreLogResizerHovered {
                restoreLogResizerHovered = false
                NSCursor.pop()
            }
        }
        .help(L10n.t("Restore 实时输出"))
        .accessibilityElement()
        .accessibilityLabel(L10n.t("Restore 实时输出"))
        .accessibilityValue("\(Int((currentFraction * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            let step: Double
            switch direction {
            case .increment:
                step = 0.05
            case .decrement:
                step = -0.05
            @unknown default:
                return
            }
            restoreLogPanelFraction = RestoreLogPaneMetrics.adjustedFraction(
                startingAt: restoreLogPanelFraction + step,
                translation: 0,
                availableHeight: availableHeight)
        }
        .accessibilityIdentifier("restore-log-resizer")
    }

    private func activeTaskIdentityBar(
        _ task: RestoreTaskSnapshot
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("锁定的 Restore 目标"))
                    .font(.system(size: 11, weight: .semibold))
                Text(L10n.t(task.target.displayIdentity))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                Text(L10n.t(
                    "\(task.target.portDescription) · ECID \(task.target.canonicalHex)"))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            statusBadge(
                currentPhaseTitle(task),
                tone: restore.isRestoring
                    ? .accentColor
                    : .orange)
        }
    }

    private func activeTaskSupportingDetails(
        _ task: RestoreTaskSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                Label(
                    task.ipswURL.lastPathComponent,
                    systemImage: "shippingbox")
                    .lineLimit(1)
                Text(L10n.t(
                    task.rawPersistencePolicy.saveThisRun
                        ? "本次原始日志：已请求保存"
                        : "本次原始日志：未保存"))
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)

            DisclosureGroup(
                L10n.t("查看锁定目标与本次日志策略")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(
                        "控制目标不会被左侧端口或右侧查看端口切换"))
                    Text(L10n.t(
                        "Restore 尝试：\(task.attemptID.uuidString)"))
                    Text(L10n.t(
                        "RLM：\(rlmTitle(task.rlmStatus)) · 真实阶段：\(currentPhaseTitle(task))"))
                    if !task.buildManifestSHA256.isEmpty {
                        Text("BuildManifest SHA-256: \(task.buildManifestSHA256)")
                    }
                    if let whole = task.wholeFileSHA256, !whole.isEmpty {
                        Text("IPSW SHA-256: \(whole)")
                    }
                }
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 5)
            }
            .font(.system(size: 10.5, weight: .medium))

            if !task.failureText.isEmpty {
                Text(task.failureText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .lineLimit(5)
            }
        }
    }

    private var restoreLiveOutputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Label(
                    L10n.t("Restore 实时输出"),
                    systemImage: "terminal")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(L10n.t("cfgutil 内存尾部"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(L10n.t(RestoreLiveEvidenceCopy.panelDescription))
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        if let task = restore.currentTask,
                           !task.cfgutilOutputTail.isEmpty {
                            ForEach(
                                Array(task.cfgutilOutputTail.enumerated()),
                                id: \.offset
                            ) { index, line in
                                Text(line.isEmpty ? " " : line)
                                    .font(.system(
                                        size: 9.7,
                                        design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading)
                                    .id(index)
                            }
                        } else {
                            Text(L10n.t(
                                restore.isRestoring
                                    ? "等待 cfgutil 输出…"
                                    : "cfgutil 尚未实际启动；当前没有子进程输出。"))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(9)
                }
                .background(
                    Color(nsColor: .textBackgroundColor)
                        .opacity(0.34),
                    in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            Color.secondary.opacity(0.16),
                            lineWidth: 0.7)
                }
                .onChange(
                    of: restore.currentTask?.cfgutilOutputSequence
                ) { _, sequence in
                    guard sequence != nil,
                          let count = restore.currentTask?
                            .cfgutilOutputTail.count,
                          count > 0 else {
                        return
                    }
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
        .accessibilityIdentifier("restore-live-output")
    }

    private var preparationCancelInset: some View {
        activeCancelBar
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
            .overlay(alignment: .top) {
                Divider()
            }
            .accessibilityIdentifier("restore-preparation-cancel-pinned")
    }

    private var finalizingEvidenceInset: some View {
        HStack(spacing: 8) {
            Label(
                L10n.t("Restore 已结束，正在写入日志与历史记录；此阶段不可取消。"),
                systemImage: "clock.arrow.circlepath")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
        .accessibilityIdentifier("restore-finalizing-pinned")
    }

    private var activeCancelBar: some View {
        HStack(spacing: 8) {
            Text(L10n.t(
                restore.currentTask?.cancellationRequested == true
                    ? "正在取消：已发送中断信号，等待进程退出…"
                    : (restore.isRestoring
                        ? "Restore 正在执行；取消入口保持可见。"
                        : "Restore 启动准备中；cfgutil 尚未确认运行。")))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 6)
            if restore.canCancelRestoreTask,
               let task = restore.currentTask {
                Button(L10n.t(task.cancellationRequested
                    ? "取消请求已发送"
                    : (task.processStartedAt == nil
                        ? "取消恢复准备…"
                        : "取消恢复…"))) {
                    pendingCancelAttemptID = restore.currentAttemptID
                    showCancelConfirmation = true
                }
                .buttonStyle(.bordered)
                .disabled(task.cancellationRequested)
                .accessibilityIdentifier("restore-cancel-visible")
            }
            if restore.isRestoring,
               restore.currentTask?.cancellationGraceExpired == true {
                Button(L10n.t("强制结束无响应进程…")) {
                    pendingForceKillAttemptID = restore.currentAttemptID
                    showForceKillConfirmation = true
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            if let directory = restore.currentTask?.rawOutputDirectory {
                Button(L10n.t("打开本次原始日志目录")) {
                    NSWorkspace.shared.open(directory)
                }
                .buttonStyle(.bordered)
                .disabled(!FileManager.default.fileExists(atPath: directory.path))
            }
        }
    }

    private var targetSection: some View {
        sectionCard(title: "1  Restore 目标") {
            HStack(spacing: 10) {
                Picker(
                    L10n.t("Restore 浏览端口"),
                    selection: Binding(
                        get: { restore.browsePortScope },
                        set: { restore.selectBrowsePort($0) })
                ) {
                    Text(L10n.t("全部可见端口"))
                        .tag(Optional<String>.none)
                    ForEach(restore.availableBrowsePorts) { port in
                        Text(L10n.t(port.displayName))
                            .tag(Optional(port.key))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

                if restore.activeAttempt != nil {
                    Text(L10n.t("任务启动中 · 浏览端口不会改变冻结目标"))
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }

            if let attempt = restore.activeAttempt {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(attempt.target.displayIdentity))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.t(
                        "\(attempt.portDisplayName) · ECID \(attempt.canonicalECID) · 任务期间目标已锁定"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 10) {
                    Picker(
                        L10n.t("DFU / Recovery 目标"),
                        selection: Binding(
                            get: { restore.selectedTargetID },
                            set: {
                                if let id = $0 {
                                    restore.selectTarget(id: id)
                                }
                            })
                    ) {
                        if restore.availableTargets.isEmpty {
                            Text(L10n.t("未发现 DFU / Recovery 目标"))
                                .tag(Optional<String>.none)
                        }
                        ForEach(restore.availableTargets) { target in
                            Text(L10n.t(target.displayIdentity))
                                .tag(Optional(target.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(L10n.t("刷新")) {
                        restore.refreshTargets()
                    }
                    .buttonStyle(.bordered)
                }
                if let target = restore.selectedTarget {
                    Text(L10n.t(
                        "\(target.productType ?? "ProductType 未知") · \(target.portDescription)"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var firmwareSection: some View {
        sectionCard(title: "2  本地 IPSW") {
            HStack(spacing: 8) {
                Button(L10n.t("选择本地 IPSW…")) {
                    showFileImporter = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(restore.isRestoreTaskActive || restore.isLoadingFirmware)

                Button(L10n.t("选择固件文件夹…")) {
                    chooseFirmwareDirectory()
                }
                .buttonStyle(.bordered)
                .disabled(restore.isRestoreTaskActive || restore.isLoadingFirmware)

                Spacer(minLength: 0)
            }

            if !restore.firmwareLibraryEntries.isEmpty {
                HStack(spacing: 8) {
                    Picker(
                        L10n.t("固件库"),
                        selection: Binding(
                            get: { restore.firmwareLibraryEntryID },
                            set: { id in
                                if let id {
                                    restore.selectFirmwareFromLibrary(id: id)
                                }
                            })
                    ) {
                        ForEach(restore.firmwareLibraryEntries) { entry in
                            Text(entryLabel(entry))
                                .tag(Optional(entry.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(restore.isRestoreTaskActive || restore.isLoadingFirmware)

                    Button(L10n.t("刷新固件库")) {
                        Task { await restore.refreshFirmwareLibrary() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(restore.isRestoreTaskActive || restore.isLoadingFirmware)
                }
            }

            HStack(spacing: 8) {
                Menu {
                    if restore.recentFirmwareUses.isEmpty {
                        Text(L10n.t("尚无最近使用记录"))
                    } else {
                        ForEach(restore.recentFirmwareUses) { use in
                            Button(
                                "\(use.reference.fileName) · \(use.reference.versionLabel) · \(use.modelFamilyKey?.rawValue ?? L10n.t("机型未知"))"
                            ) {
                                _ = restore.useFirmwareReference(
                                    use.reference)
                            }
                            .disabled(
                                restore.resolveFirmwareReference(
                                    use.reference)?.isUsable != true)
                        }
                    }
                } label: {
                    Label(L10n.t("最近使用"), systemImage: "clock.arrow.circlepath")
                }
                .menuStyle(.borderlessButton)
                .disabled(restore.isRestoreTaskActive)

                Button(L10n.t("设为全局默认")) {
                    _ = restore.setSelectedFirmwareAsGlobalDefault()
                }
                .buttonStyle(.bordered)
                .disabled(
                    restore.isRestoreTaskActive
                        || restore.firmwareLibraryEntryID == nil
                        || restore.firmwareValidity != .valid)

                Button(L10n.t("设为当前机型默认")) {
                    _ = restore.setSelectedFirmwareAsModelDefault()
                }
                .buttonStyle(.bordered)
                .disabled(
                    restore.isRestoreTaskActive
                        || restore.firmwareLibraryEntryID == nil
                        || restore.firmwareValidity != .valid
                        || restore.selectedTarget.map {
                            ModelFamilyKey.resolve(
                                identity: $0.firmwareIdentity) == nil
                        } ?? true)
                Spacer(minLength: 0)
            }
            .font(.system(size: 10))

            if !restore.firmwarePreferenceIssue.isEmpty {
                Label(
                    L10n.t(restore.firmwarePreferenceIssue),
                    systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if restore.firmwareSelectionSource != .none {
                HStack(spacing: 8) {
                    statusBadge(
                        L10n.t(selectionSourceTitle),
                        tone: restore.firmwareSelectionSource == .userManualSelected
                            ? .blue
                            : .secondary)
                    if let recommendation = restore.recommendedFirmware {
                        if let tier = recommendation.tier {
                            statusBadge(
                                "Tier \(tier.rawValue)",
                                tone: .secondary)
                        }
                        Text(L10n.t(trustTitle(recommendation.trust)))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        if recommendation.requiresManualConfirmation {
                            statusBadge(
                                L10n.t("需人工确认"),
                                tone: .orange)
                        }
                    }
                    if restore.firmwareSelectionSource == .userManualSelected {
                        Button(L10n.t("恢复自动推荐")) {
                            restore.restoreAutomaticRecommendation()
                        }
                        .buttonStyle(.link)
                    }
                }
            }

            if let recommendation = restore.recommendedFirmware {
                Text(L10n.t(recommendation.basis))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let url = restore.firmwareURL {
                VStack(alignment: .leading, spacing: 5) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        statusBadge(
                            restore.firmwareValidity.rawValue,
                            tone: validityTone)
                        statusBadge(
                            restore.hardwareCompatibility.status.rawValue,
                            tone: compatibilityTone)
                        if restore.isLoadingFirmware {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if let metadata = restore.firmwareMetadata {
                        Text(L10n.t(
                            "版本 \(metadata.productVersion ?? "未知") · Build \(metadata.productBuild ?? "未知")"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Text(L10n.t(restore.hardwareCompatibility.message))
                        .font(.system(size: 11))
                        .foregroundStyle(compatibilityTone)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.t("Apple 签名状态：未知（仅验证本地硬件 Manifest）"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if !restore.buildManifestSHA256.isEmpty {
                        Text("BuildManifest SHA-256: \(restore.buildManifestSHA256)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        Button(L10n.t("校验完整 IPSW SHA-256…")) {
                            Task { await restore.computeFirmwareSHA256() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(restore.isComputingHash || restore.isLoadingFirmware)
                        if restore.isComputingHash {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if !restore.firmwareSHA256.isEmpty {
                        Text("完整 IPSW SHA-256: \(restore.firmwareSHA256)")
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                }
            }

            if !restore.firmwareCandidates.isEmpty {
                Text(L10n.t("文件夹内发现 \(restore.firmwareCandidates.count) 个 IPSW"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if !restore.firmwareLibraryMessage.isEmpty {
                Text(L10n.t(restore.firmwareLibraryMessage))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var confirmationSection: some View {
        sectionCard(title: "3  开始恢复") {
            if restore.firmwareURL != nil,
               restore.firmwareValidity == .valid,
               restore.hardwareCompatibility.status == .unverified {
                Label(
                    L10n.t(restore.confirmationWarning),
                    systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle(
                L10n.t("保存本次 Restore 原始日志"),
                isOn: Binding(
                    get: { restore.rawSaveRequested(for: restore.selectedTarget) },
                    set: { restore.setRawSaveRequested($0, for: restore.selectedTarget) })
            )
            .toggleStyle(.checkbox)
            .disabled(restore.isTaskActive(for: restore.selectedTarget))
            .accessibilityIdentifier("restore-save-raw-this-run")
            Text(L10n.t(
                "此选择只作用于下一次 Restore，不改变全局默认。关闭时不会创建 Restore raw、Staging 或隐藏副本。"))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button(L10n.t("确认擦除数据并恢复…")) {
                    guard let targetID = restore.selectedTarget?.id,
                          restore.freezeRestoreConfirmation(targetID: targetID) else {
                        return
                    }
                    pendingPrimaryTargetID = targetID
                    showStartConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!restore.canStartRestore)

                if !restore.isRestoreTaskActive && !restore.startDisabledReason.isEmpty {
                    Text(L10n.t(restore.startDisabledReason))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(L10n.t("Restore 会抹除目标 Mac 上的数据。本工具不会自动开始，也不会检测到设备后自动刷机。"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !restore.restoreHistoryMessage.isEmpty {
                Text(L10n.t(restore.restoreHistoryMessage))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func currentTaskSection(
        showsActions: Bool = true
    ) -> some View {
        sectionCard(title: "4  当前任务") {
            if let task = restore.displayedTask {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t(task.target.displayIdentity))
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(2)
                            Text(L10n.t(task.ipswURL.lastPathComponent))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(L10n.t(currentPhaseTitle(task)))
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }

                    if let attempt = restore.activeAttempt,
                       task.processStartedAt == nil {
                        Text(L10n.t("准备阶段：\(attemptStageTitle(attempt.stage))"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    RestoreStageProgressView(task: task)

                    if task.processStartedAt != nil {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(L10n.t("运行：\(runDurationText(task))"))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let outcome = task.outcome {
                        HStack(spacing: 8) {
                            statusBadge(outcome.rawValue, tone: outcomeTone(outcome))
                            Text(L10n.t("退出码：\(task.exitCode.map(String.init) ?? "未知")"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(L10n.t(task.tailComplete ? "stdout/stderr 尾部已收齐" : "输出尾部不完整"))
                                .font(.system(size: 11))
                                .foregroundStyle(
                                    task.tailComplete ? Color.secondary : Color.orange)
                        }
                    }

                    Text(L10n.t("RLM 日志：\(rlmTitle(task.rlmStatus))"))
                        .font(.system(size: 11))
                        .foregroundStyle(task.rlmStatus == .unavailable ? .orange : .secondary)
                    if let raw = task.rlmRawLogURL {
                        Text(raw.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }

                    Text(L10n.t(
                        task.rawPersistencePolicy.saveThisRun
                            ? "本次已请求保存完整原始日志。"
                            : "本次未保存完整原始日志；结束后可能无法补导出。"))
                        .font(.system(size: 10))
                        .foregroundStyle(
                            task.rawPersistencePolicy.saveThisRun
                                ? Color.secondary
                                : Color.orange)
                    if task.rawPersistencePolicy.saveThisRun
                        || task.rawEvidenceStatus
                            != .notSavedByChoice {
                        Text(L10n.t(
                            "原始证据：\(rawEvidenceTitle(task.rawEvidenceStatus))"))
                            .font(.system(size: 10))
                            .foregroundStyle(
                                task.rawEvidenceStatus == .complete
                                    ? Color.secondary
                                    : Color.orange)
                    }
                    if !task.rawArchiveMessage.isEmpty {
                        Text(L10n.t(task.rawArchiveMessage))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    if let archive = task.rawArchive {
                        Button(L10n.t("导出原始日志…")) {
                            exportRawArchive(attemptID: archive.attemptID)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("raw-export-button")
                    }

                    if restore.restoreHistoryStatistics.hasTrustedDuration {
                        let average = restore.restoreHistoryStatistics.averageDurationSeconds ?? 0
                        let median = restore.restoreHistoryStatistics.medianDurationSeconds ?? 0
                        Text(L10n.t(
                            "可信历史参考：平均 \(durationText(average)) · 中位 \(durationText(median)) · 样本 \(restore.restoreHistoryStatistics.trustedRuntimeSampleCount)"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else if task.outcome != nil {
                        Text(L10n.t("同机型同固件暂无可信耗时参考"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    if !task.failureText.isEmpty {
                        Text(task.failureText)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .lineLimit(6)
                    }

                    if showsActions {
                        HStack(spacing: 8) {
                            if restore.canCancelRestoreTask {
                                Button(L10n.t(task.cancellationRequested
                                    ? "取消请求已发送"
                                    : (task.processStartedAt == nil ? "取消恢复准备…" : "取消恢复…"))) {
                                    pendingCancelAttemptID = restore.currentAttemptID
                                    showCancelConfirmation = true
                                }
                                .buttonStyle(.bordered)
                                .disabled(task.cancellationRequested)
                            }
                            if restore.isRestoring && task.cancellationGraceExpired {
                                Button(L10n.t("强制结束无响应进程…")) {
                                    pendingForceKillAttemptID = restore.currentAttemptID
                                    showForceKillConfirmation = true
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                            if let directory = task.rawOutputDirectory {
                                Button(L10n.t("打开本次原始日志目录")) {
                                    NSWorkspace.shared.open(directory)
                                }
                                .buttonStyle(.bordered)
                                .disabled(!FileManager.default.fileExists(atPath: directory.path))
                            }
                        }
                    }
                }
            } else {
                Text(L10n.t("暂无恢复任务"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if !restore.errorMessage.isEmpty {
                Text(L10n.t(restore.errorMessage))
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !restore.message.isEmpty, restore.displayedTask == nil {
                Text(L10n.t(restore.message))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var confirmationMessage: Text {
        guard let target = restore.selectedTarget else {
            return Text(L10n.t("请先选择 Restore 目标。"))
        }
        return Text(L10n.t("""
        目标：\(target.displayName)
        ECID：\(target.canonicalHex)
        端口：\(target.portDescription)
        IPSW：\(restore.firmwareURL?.lastPathComponent ?? "未选择")

        \(restore.confirmationWarning)

        \(restore.rawSaveRequestedThisRun
            ? "本次将保存完整原始日志；保存失败只影响证据完整性，不改写 Restore 结果。"
            : "本次完整原始日志不会保存，结束后可能无法补导出。Restore 执行、状态、结果和取消不受影响。")

        这将抹除目标 Mac 上的所有数据，且不可撤销。
        """))
    }

    private func sectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L10n.t(title))
                .font(.system(size: 13, weight: .semibold))
            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1))
    }

    private func statusBadge(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(tone.opacity(0.12)))
            .foregroundStyle(tone)
    }

    private var validityTone: Color {
        switch restore.firmwareValidity {
        case .valid: return .secondary
        case .unverified: return .orange
        case .invalid: return .red
        }
    }

    private var compatibilityTone: Color {
        switch restore.hardwareCompatibility.status {
        case .compatible: return .green
        case .unverified: return .orange
        case .incompatible: return .red
        }
    }

    private func outcomeTone(_ outcome: RestoreOutcome) -> Color {
        switch outcome {
        case .success: return .green
        case .failure: return .red
        case .canceled: return .orange
        case .unknown: return .secondary
        }
    }

    private func phaseTitle(_ phase: RestoreTaskPhase) -> String {
        switch phase {
        case .userConfirmed: return "已确认，准备采集"
        case .processStarted: return "cfgutil 已启动"
        case .restoreActivityObserved: return "已观察到恢复活动"
        case .terminal: return "任务已结束"
        }
    }

    private func currentPhaseTitle(_ task: RestoreTaskSnapshot) -> String {
        if let attempt = restore.activeAttempt,
           task.processStartedAt == nil {
            return attempt.cancelRequested
                ? "正在取消恢复准备"
                : "恢复启动准备中"
        }
        return phaseTitle(task.phase)
    }

    private func attemptStageTitle(_ stage: PendingRestoreAttemptStage) -> String {
        switch stage {
        case .userConfirmed:
            return "已创建恢复尝试"
        case .waitingForFreshHeartbeat:
            return "等待新鲜设备观察"
        case .validatingPreflight:
            return "复验冻结目标、端口与 IPSW"
        case .preparingRLM:
            return "准备日志会话"
        case .readyToLaunch:
            return "提交最终启动许可"
        case .processLaunching:
            return "启动 cfgutil"
        case .processRunning:
            return "cfgutil 运行中"
        case .processExited:
            return "进程已退出，等待双流收尾"
        case .bothStreamsEOF:
            return "双流 EOF 已完成"
        case .outcomeConfirmed:
            return "结果已确认"
        case .finalizingEvidence:
            return "写入轻量历史与证据状态"
        case .completed:
            return "任务完成"
        }
    }

    private func rlmTitle(_ status: RestoreRLMLogStatus) -> String {
        switch status {
        case .recordingReused: return "复用当前录制会话"
        case .startedOwnedSession: return "已由本任务启动单一会话"
        case .notRequested: return "未请求 Restore 自有日志"
        case .unavailable: return "不可用（不阻断 cfgutil）"
        case .completedWithPartialEvidence: return "已写入；完整性仍需验证"
        }
    }

    private func rawEvidenceTitle(
        _ status: RestoreRawEvidenceStatus
    ) -> String {
        switch status {
        case .notRequested:
            return "未请求"
        case .notSavedByChoice:
            return "按用户选择未保存"
        case .pendingBatch4:
            return "兼容旧记录"
        case .complete:
            return "完整并已校验"
        case .incompleteProtected:
            return "不完整，已保护"
        case .unavailable:
            return "不可用"
        }
    }

    private var selectionSourceTitle: String {
        switch restore.firmwareSelectionSource {
        case .none: return "未选择固件来源"
        case .systemRecommended: return "系统自动推荐"
        case .userManualSelected: return "用户手动选择"
        }
    }

    private func trustTitle(_ trust: FirmwareRecognitionTrust) -> String {
        switch trust {
        case .recentUserUsage: return "最近实际启动记录"
        case .explicitUserDefault: return "用户显式默认"
        case .previousUserSelection: return "上次手动选择"
        case .manualUserSelection: return "用户手动选择"
        }
    }

    private func entryLabel(_ entry: FirmwareLibraryEntry) -> String {
        let state: String
        if let accessState = entry.accessState {
            switch accessState {
            case .unreadable: state = "无法读取"
            case .cloudNotDownloaded: state = "iCloud 未下载"
            }
        } else {
            switch entry.state {
            case .available: state = "可用"
            case .missing: state = "文件丢失"
            case .ambiguous: state = "重定位有歧义"
            case .invalid: state = "无效"
            }
        }
        let version = entry.metadata?.productVersion ?? "未知版本"
        let build = entry.metadata?.productBuild ?? "未知 Build"
        return L10n.t(
            "\(entry.url.lastPathComponent) · \(version) · \(build) · \(state)")
    }

    private func runDurationText(_ task: RestoreTaskSnapshot) -> String {
        let seconds: TimeInterval
        if let duration = task.lifecycle.processWallDurationSeconds {
            seconds = duration
        } else if let launched = task.lifecycle.processLaunched {
            let now = RestoreLifecycleClock.now()
            seconds = RestoreLifecycleClock.seconds(
                from: launched,
                to: now) ?? 0
        } else {
            return L10n.t("尚未启动")
        }
        return durationText(seconds)
    }

    private func referenceHelp(_ reference: RestoreSuccessDurationReference) -> String {
        let firmware = [reference.firmwareVersion, reference.firmwareBuild]
            .compactMap { $0 }.joined(separator: " · ")
        switch reference.priority {
        case .sameECIDAndFirmware:
            return L10n.t("同 ECID 同固件") + (firmware.isEmpty ? "" : " · " + firmware)
        case .sameModelAndFirmware:
            return L10n.t("同机型同固件") + (firmware.isEmpty ? "" : " · " + firmware)
        case .sameModelRecent:
            return L10n.t("同机型最近成功") + (firmware.isEmpty ? "" : " · " + firmware)
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func chooseFirmwareDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.t("选择")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await restore.scanFirmwareDirectory(url) }
    }
}

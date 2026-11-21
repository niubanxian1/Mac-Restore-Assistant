import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RestoreLogEngine

struct LogCaptureWorkspaceView: View {
    @EnvironmentObject private var capture: CaptureModel
    @EnvironmentObject private var preferences: LogWorkspacePreferences
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var previewSettings: LogPreviewSettings

    @State private var searchText = ""
    @State private var previewPaused = false
    @State private var showAdvancedSettings = false
    @State private var previewFilter: PreviewFilter = .all

    private enum PreviewFilter: String, CaseIterable, Identifiable {
        case all
        case errors
        var id: String { rawValue }
        var title: String { self == .all ? "全部" : "仅看报错" }
    }

    private var filteredPreview: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = capture.previewLines
        if previewFilter == .errors {
            lines = lines.filter(LogErrorClueClassifier.isErrorLine)
        }
        guard !query.isEmpty else { return lines }
        return lines.filter {
            $0.localizedCaseInsensitiveContains(query)
        }
    }

    private var errorSummary: LogErrorClueSummary {
        LogErrorClueClassifier.summarize(capture.previewLines)
    }

    private var rawDirectoryExists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: preferences.rawLogDirectory,
            isDirectory: &isDirectory) && isDirectory.boolValue
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    compactControlBar
                    telemetryBar
                    if !errorSummary.isEmpty { errorClueBar }
                    previewSection
                    importSection
                    saveAndExportSection
                    advancedSettings
                }
                .padding(12)
            }
            Divider()
            bottomActionBar
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            if capture.isExporting || capture.exportProgress != nil {
                Divider()
                exportProgressPanel
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            }
        }
        .onAppear { capture.setPreviewVisible(true) }
        .onDisappear { capture.setPreviewVisible(false) }
    }

    private var compactControlBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(stateColor)
                .frame(width: 7, height: 7)
            Text(L10n.t(capture.stateText))
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
            Image(systemName: "info.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .help(L10n.t(monitorSummary) + "\n" + L10n.t("日志是 Apple Configurator / DeviceService 的系统采集范围，可能包含多台设备；当前左侧设备选择不决定日志归属。"))
                .accessibilityLabel(L10n.t("采集说明"))
            Spacer(minLength: 6)
            Toggle(L10n.t("自动监控 Restore 开始"), isOn: Binding(
                get: { preferences.autoMonitorEnabled },
                set: { capture.setAutoMonitorEnabled($0) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(capture.isCapturing)
                .accessibilityIdentifier("auto-monitor-restore")
            captureButton
        }
        .accessibilityIdentifier("rlm-control-header")
    }

    private var telemetryBar: some View {
        HStack(spacing: 12) {
            Text(CaptureDisplayFormat.duration(seconds: capture.elapsedSeconds))
            Text("·")
            Text(CaptureDisplayFormat.dataSize(bytes: Int64(capture.byteCount)))
            Text("·")
            Text("\(capture.lineCount) " + L10n.t("行"))
            Text("·")
            Text("\(errorSummary.hitCount) " + L10n.t("命中报错"))
            Spacer(minLength: 0)
            Text(L10n.t("内存预览 · 非完整原始日志"))
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        .lineLimit(1)
        .accessibilityIdentifier("rlm-telemetry-bar")
    }

    private var errorClueBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
            Text(L10n.t("线索：") + errorSummary.groups.map {
                "\($0.title) \($0.count)"
            }.joined(separator: " · "))
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
            Text(L10n.t("仅基于日志原文关键词归类，不替代实测诊断"))
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(L10n.t(previewFilter == .errors ? "查看全部" : "仅看报错")) {
                previewFilter = previewFilter == .errors ? .all : .errors
            }
            .buttonStyle(.borderless)
            .font(.system(size: 10, weight: .medium))
            .accessibilityIdentifier("rlm-error-clue-filter")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("rlm-error-clue-bar")
    }

    @ViewBuilder
    private var captureButton: some View {
        if capture.isCapturing {
            Button(L10n.t("停止采集")) { capture.stop() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(capture.state == .stopping || capture.state == .finalizing)
                .accessibilityIdentifier("capture-stop")
        } else {
            Button(L10n.t("开始采集")) { capture.start() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(capture.state == .finalizing || capture.isDiscarding)
                .accessibilityIdentifier("capture-start")
        }
    }

    private var statePill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(stateColor)
                .frame(width: 7, height: 7)
            Text(L10n.t(capture.stateText))
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.secondary.opacity(0.10)))
    }

    private var stateColor: Color {
        switch capture.state {
        case .recording: return .green
        case .starting, .stopping, .finalizing: return .accentColor
        case .failed, .interrupted: return .orange
        default: return .secondary
        }
    }

    private var monitorSummary: String {
        if capture.isCapturing { return "采集中 · 监听已暂停" }
        if capture.isListening {
            return capture.monitorState == "WAITING_FOR_RESTORE"
                ? "监听中 · 等待 Configurator Restore"
                : "监听中 · \(capture.monitorState)"
        }
        return preferences.autoMonitorEnabled
            ? "自动监控已开启，但当前未监听"
            : "未监听 · 手动采集仍可用"
    }

    private var monitorColor: Color {
        capture.monitorError.isEmpty
            ? (capture.isListening ? .green : .secondary)
            : .orange
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    previewTitle
                    Spacer(minLength: 8)
                    previewTools
                }
                VStack(alignment: .leading, spacing: 7) {
                    previewTitle
                    HStack(spacing: 8) { previewTools }
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if filteredPreview.isEmpty {
                            Text(L10n.t(capture.previewLines.isEmpty ? "尚无日志内容" : "搜索没有匹配项"))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.55))
                                .padding(8)
                        } else {
                            ForEach(Array(filteredPreview.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.92))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(minHeight: 190, idealHeight: 300, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 11/255, green: 13/255, blue: 17/255)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.10)))
                .onChange(of: filteredPreview.count) { _, count in
                    guard preferences.previewAutoScroll,
                          !previewPaused,
                          count > 0 else { return }
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
            if capture.previewTruncated {
                Text(L10n.t("预览已截取末尾；采集和保存始终使用完整原始日志。"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var previewTitle: some View {
        HStack(spacing: 8) {
            Text(L10n.t("终端预览"))
                .font(.system(size: 12, weight: .semibold))
            Text("\(L10n.t("最多")) \(preferences.previewLineLimit) \(L10n.t("行 · 完整原始日志不受影响"))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var previewTools: some View {
        HStack(spacing: 7) {
            Picker("", selection: $previewFilter) {
                ForEach(PreviewFilter.allCases) { filter in
                    Text(L10n.t(filter.title)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 128)
            .accessibilityIdentifier("rlm-preview-filter")
            TextField(L10n.t("搜索"), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 100, idealWidth: 150, maxWidth: 190)
            Toggle(L10n.t("自动滚动"), isOn: $preferences.previewAutoScroll)
                .toggleStyle(.switch)
                .controlSize(.small)
            Button(L10n.t(previewPaused ? "继续预览" : "暂停预览")) {
                previewPaused.toggle()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button(L10n.t("复制预览")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(filteredPreview.joined(separator: "\n"), forType: .string)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(filteredPreview.isEmpty)
        }
    }

    private var bottomActionBar: some View {
        HStack(spacing: 8) {
            Button(L10n.t("在 Finder 中打开原始目录")) {
                NSWorkspace.shared.open(
                    URL(fileURLWithPath: preferences.rawLogDirectory,
                        isDirectory: true))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!rawDirectoryExists)
            .help(rawDirectoryExists
                ? preferences.rawLogDirectory
                : L10n.t("原始日志目录不存在"))
            .accessibilityIdentifier("rlm-open-raw-directory")
            Spacer(minLength: 6)
            Button(L10n.t("导出 .log…")) { chooseRawExportDestination() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!capture.canStartRawExport)
            Button(L10n.t("导出本次证据包")) {
                capture.exportEvidencePackage(
                    directory: URL(fileURLWithPath: preferences.evidencePackageDirectory,
                                   isDirectory: true),
                    baseName: effectiveBaseName)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!capture.canExportEvidencePackage)
        }
        .accessibilityIdentifier("rlm-bottom-actions")
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(L10n.t("历史日志分析"))
                    .font(.system(size: 14, weight: .semibold))
                Text(L10n.t(capture.importState.title))
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.10)))
                Spacer()
                Button(L10n.t("导入历史 .log…")) { chooseHistoricalLog() }
                    .buttonStyle(.bordered)
                    .disabled(capture.importState == .analyzing)
                if capture.importedDiagnosticURL != nil {
                    Button(L10n.t("打开诊断报告")) {
                        if let url = capture.importedDiagnosticURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            Text(L10n.t(capture.importStatus))
                .font(.system(size: 11))
                .foregroundStyle(capture.importState == .failed ? .orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let analysis = capture.importedAnalysis {
                HStack(spacing: 18) {
                    Text("\(L10n.t("原始")) \(CaptureDisplayFormat.dataSize(bytes: Int64(analysis.rawBytes)))")
                    Text("\(L10n.t("行数")) \(analysis.rawLines)")
                    Text("\(L10n.t("终态")) \(analysis.terminalKind.rawValue.uppercased())")
                    Text("\(L10n.t("保留")) \(analysis.keptLines) / \(L10n.t("丢弃")) \(analysis.droppedLines)")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var saveAndExportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(L10n.t("文件名"))
                    .font(.system(size: 12, weight: .medium))
                TextField(L10n.t("默认文件名"), text: $capture.exportBaseName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Spacer(minLength: 8)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    savePendingButtons
                    rawExportButtons
                    packageExportButtons
                    if capture.isExporting {
                        Button(L10n.t("取消导出")) { capture.cancelExport() }
                            .buttonStyle(.bordered)
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { savePendingButtons }
                    HStack { rawExportButtons }
                    HStack { packageExportButtons }
                    if capture.isExporting {
                        Button(L10n.t("取消导出")) { capture.cancelExport() }
                    }
                }
            }

            if !capture.saveMessage.isEmpty {
                Text(L10n.t(capture.saveMessage))
                    .font(.system(size: 11))
                    .foregroundStyle(capture.saveMessage.contains("失败") || capture.saveMessage.contains("取消")
                                     ? .orange : .secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !capture.captureError.isEmpty {
                Text(L10n.t(capture.captureError))
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 14) {
                Text("\(L10n.t("原始日志："))\(preferences.rawLogDirectory)")
                    .lineLimit(1).truncationMode(.middle)
                Text("\(L10n.t("证据包："))\(preferences.evidencePackageDirectory)")
                    .lineLimit(1).truncationMode(.middle)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var savePendingButtons: some View {
        if capture.canSave {
            Button(L10n.t("保存原始日志")) {
                capture.saveRawLog()
            }
            .buttonStyle(.borderedProminent)
            .disabled(capture.isExporting || capture.isDiscarding)
            Button(L10n.t("丢弃本次日志")) {
                capture.discardUnsavedSession()
            }
            .buttonStyle(.bordered)
            .disabled(!capture.canDiscardUnsavedSession)
        }
    }

    @ViewBuilder
    private var rawExportButtons: some View {
        Button(L10n.t("导出 .log…")) { chooseRawExportDestination() }
            .buttonStyle(.bordered)
            .disabled(!capture.canStartRawExport)
        if capture.lastRawExportURL != nil {
            Button(L10n.t("打开日志位置")) { capture.openLastRawExport() }
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var packageExportButtons: some View {
        Button(L10n.t("导出本次证据包")) {
            capture.exportEvidencePackage(
                directory: URL(fileURLWithPath: preferences.evidencePackageDirectory, isDirectory: true),
                baseName: effectiveBaseName)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!capture.canExportEvidencePackage)
        Button(L10n.t("证据包另存为…")) { chooseEvidencePackageDestination() }
            .buttonStyle(.bordered)
            .disabled(!capture.canExportEvidencePackage)
        if capture.lastEvidencePackageURL != nil {
            Button(L10n.t("打开证据包位置")) { capture.openLastEvidencePackage() }
                .buttonStyle(.bordered)
        }
    }

    private var effectiveBaseName: String {
        let value = capture.exportBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? preferences.defaultFileBaseName : value
    }

    private var advancedSettings: some View {
        DisclosureGroup(L10n.t("日志与导出设置"), isExpanded: $showAdvancedSettings) {
            VStack(alignment: .leading, spacing: 10) {
                settingPathRow(
                    title: "原始日志默认目录",
                    path: preferences.rawLogDirectory,
                    choose: chooseRawDirectory,
                    reveal: { revealPath(preferences.rawLogDirectory) })
                settingPathRow(
                    title: "证据包默认目录",
                    path: preferences.evidencePackageDirectory,
                    choose: choosePackageDirectory,
                    reveal: { revealPath(preferences.evidencePackageDirectory) })
                HStack(spacing: 14) {
                    Stepper(
                        "\(L10n.t("预览行数")) \(preferences.previewLineLimit)",
                        value: $preferences.previewLineLimit,
                        in: 20...1000,
                        step: 20)
                    TextField(L10n.t("默认文件名"), text: $preferences.defaultFileBaseName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                }
                Divider()
                Toggle(L10n.t("证据包包含 timeline.json"), isOn: $capture.includeTimeline)
                Toggle(L10n.t("证据包包含 diagnostic_summary.md"), isOn: $capture.includeDiagnosticSummary)
                Toggle(L10n.t("证据包包含实际捕获的 updater output"), isOn: $capture.includeUpdaterOutput)
                Divider()
                HStack {
                    Toggle(L10n.t("启用预览过滤（仅预览，不改原始日志）"), isOn: $previewSettings.isEnabled)
                    if previewSettings.isEnabled {
                        Picker(L10n.t("范围"), selection: $previewSettings.scope) {
                            ForEach(LogPreviewScope.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .frame(maxWidth: 220)
                    }
                }
            }
            .padding(.top, 8)
        }
        .font(.system(size: 12))
    }

    private func settingPathRow(
        title: String,
        path: String,
        choose: @escaping () -> Void,
        reveal: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(L10n.t(title))
                .frame(width: 118, alignment: .leading)
            Text(path)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(path)
            Spacer(minLength: 8)
            Button(L10n.t("选择…"), action: choose).buttonStyle(.bordered).controlSize(.small)
            Button(L10n.t("显示"), action: reveal).buttonStyle(.bordered).controlSize(.small)
        }
    }

    @ViewBuilder
    private var exportProgressPanel: some View {
        if let progress = capture.exportProgress {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(L10n.t(progress.operation == .rawLog ? "原始日志导出" : "证据包导出"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.t(progress.stage.displayName))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if capture.isExporting {
                        Button(L10n.t("取消")) { capture.cancelExport() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
                HStack(spacing: 16) {
                    if let processed = progress.processedBytes,
                       let total = progress.totalBytes, total > 0 {
                        Text("\(CaptureDisplayFormat.dataSize(bytes: processed)) / \(CaptureDisplayFormat.dataSize(bytes: total))")
                    } else {
                        Text(L10n.t("当前阶段工作量无法可靠计算"))
                    }
                    Text(String(format: "%.1f", progress.elapsedSeconds) + " " + L10n.t("秒"))
                    if let speed = progress.bytesPerSecond, speed > 0 {
                        Text("\(CaptureDisplayFormat.dataSize(bytes: Int64(speed)))/\(L10n.t("秒"))")
                    }
                    if let fraction = progress.fraction {
                        Text(String(format: "%.0f%%", fraction * 100))
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                if !progress.message.isEmpty {
                    Text(L10n.t(progress.message))
                        .font(.system(size: 11))
                        .foregroundStyle(progress.stage == .failed ? .orange : .secondary)
                }
                HStack(spacing: 10) {
                    if let url = capture.lastRawExportURL {
                        Button(L10n.t("复制日志路径")) { capture.copyPath(url) }
                        Button(L10n.t("打开日志位置")) { capture.openLastRawExport() }
                    }
                    if let url = capture.lastEvidencePackageURL {
                        Button(L10n.t("复制证据包路径")) { capture.copyPath(url) }
                        Button(L10n.t("打开证据包位置")) { capture.openLastEvidencePackage() }
                    }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
            }
        }
    }

    private func chooseHistoricalLog() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .log, .json]
        panel.prompt = "分析"
        panel.message = "选择历史原始日志进行只读分析"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        capture.importHistoricalLog(url: url)
    }

    private func chooseRawDirectory() {
        chooseDirectory(
            title: "选择原始日志默认目录",
            current: preferences.rawLogDirectory
        ) { preferences.rawLogDirectory = $0.path }
    }

    private func choosePackageDirectory() {
        chooseDirectory(
            title: "选择证据包默认目录",
            current: preferences.evidencePackageDirectory
        ) { preferences.evidencePackageDirectory = $0.path }
    }

    private func chooseRawExportDestination() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.log]
        panel.directoryURL = URL(fileURLWithPath: preferences.rawLogDirectory, isDirectory: true)
        panel.nameFieldStringValue = effectiveBaseName + ".log"
        panel.prompt = "导出"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        capture.saveRawLog(
            directory: url.deletingLastPathComponent(),
            baseName: url.deletingPathExtension().lastPathComponent)
    }

    private func chooseEvidencePackageDestination() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.zip]
        panel.directoryURL = URL(fileURLWithPath: preferences.evidencePackageDirectory, isDirectory: true)
        panel.nameFieldStringValue = effectiveBaseName + ".zip"
        panel.prompt = "导出"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        capture.exportEvidencePackage(
            directory: url.deletingLastPathComponent(),
            baseName: url.deletingPathExtension().lastPathComponent)
    }

    private func chooseDirectory(
        title: String,
        current: String,
        completion: @escaping (URL) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = title
        panel.directoryURL = URL(fileURLWithPath: current, isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        completion(url)
    }

    private func revealPath(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}

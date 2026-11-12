import SwiftUI
import AppKit
import RestoreLogEngine

/// D0 harness. It exists only to prove the engine can be driven from a UI.
/// All capture, state, and evidence logic stays inside RestoreLogEngine;
/// F07 adds only destination choice, naming, export, copy and reveal.
/// Bridges the app's shutdown into the view model. SwiftUI gives no dependable
/// "about to quit" hook that can await work, so we take it from AppKit and hold
/// termination open until the capture we own has actually stopped.
final class RLMAppTermination: NSObject, NSApplicationDelegate {
    /// Set by the view model while it is alive.
    private static weak var owner: MonitorViewModel?
    static func register(_ model: MonitorViewModel) { owner = model }

    /// Closing the last window is a real quit, not an invisible background
    /// monitor. This prevents the old "window closed but DFU observer still
    /// running" ambiguity.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = Self.owner else { return .terminateNow }
        model.beginTermination()
        guard model.needsTerminationDecision else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = "RLM 仍在采集或等待保存决定"
        alert.informativeText = "请选择安全结束方式。取消会保留当前采集。"
        alert.addButton(withTitle: "保存并退出")
        alert.addButton(withTitle: "丢弃并退出")
        alert.addButton(withTitle: "取消")
        let choice = alert.runModal()
        if choice == .alertThirdButtonReturn {
            model.cancelTermination()
            return .terminateCancel
        }
        Task { @MainActor in
            await model.shutdownForTermination(save: choice == .alertFirstButtonReturn)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct RLMApp: App {
    @NSApplicationDelegateAdaptor(RLMAppTermination.self) private var termination
    @StateObject private var model = MonitorViewModel()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(model)
                .frame(minWidth: 1100, idealWidth: 1200, minHeight: 720, idealHeight: 800)
        }
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class MonitorViewModel: ObservableObject {
    /// Shared cancellation token for a package transaction. The builder runs on a
/// detached task, so Swift Task cancellation alone does not reach it.
final class PackageCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

enum Phase: String {
        case idle = "准备开始监控"
        case starting = "正在启动日志监控…"
        case recording = "正在监控"
        case stopping = "正在停止…"
        case decisionPending = "采集已停止，等待保存或丢弃"
        case saving = "正在保存…"
        case saved = "日志已保存"
        case discarded = "本次日志已丢弃"
        case failed = "未完成"
    }

    enum SaveDecision: String {
        case notDecided = "NOT_DECIDED"
        case saved = "SAVED"
        case discarded = "DISCARDED"
    }

    private static let destinationKey = "F07.exportDirectory"
    private static let baseNameKey = "F07.baseName"
    private static let autoMonitorKey = "RLM.autoMonitorRestore"
    private static let packageDirectoryKey = "RLM.packageDirectory"
    private static let packageTemplateKey = "RLM.packageNameTemplate"
    private static let packageTimelineKey = "RLM.packageIncludeTimeline"
    private static let packageSummaryKey = "RLM.packageIncludeSummary"
    private static let packageUpdaterKey = "RLM.packageIncludeUpdaterOutput"
    private static let namingStyleKey = "RLM.sessionNamingStyle"
    private static let rawSaveDirectoryKey = "RLM.rawSaveDirectory"
    private static let legacySuiteName = "io.github.niubanxian1.restorelogmonitor.rawmvp"

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var detail = "请先启动监控，再开始 Apple Configurator 刷机。"
    /// `nil` means "not measured yet", which the view renders as 统计中.
    /// It is deliberately not `0`: an unmeasured counter must never look like a
    /// measured zero (a restore can be running while the file is still empty).
    @Published private(set) var eventCount: Int?
    @Published private(set) var byteCount: Int?
    @Published private(set) var rawLogPath = "—"

    // MARK: F07
    @Published private(set) var exportDirectory: String
    @Published private(set) var rawSaveDirectory: String
    @Published var baseName: String {
        didSet { UserDefaults.standard.set(baseName, forKey: Self.baseNameKey) }
    }
    @Published private(set) var exportedURL: URL?
    @Published private(set) var rawExportBusy = false
    @Published private(set) var exportStatus = "保存后会自动导出到上面的位置。"
    @Published private(set) var lastSessionIsPartial = false
    @Published private(set) var rawSavedURL: URL?
    @Published private(set) var pathMigrationNotice: String?
    var hasRecentSession: Bool { latestSavedSource != nil }
    var recentSessionPath: String { rawLogPath == "—" ? "—" : rawLogPath }

    // MARK: - Save/export progress (real stage + bytes)
    @Published private(set) var saveStage = ""
    @Published private(set) var saveProcessedBytes: Int64 = 0
    @Published private(set) var saveTotalBytes: Int64 = 0
    @Published private(set) var saveElapsedSeconds: Double = 0
    @Published private(set) var saveBytesPerSecond: Double = 0
    @Published private(set) var saveFraction: Double = 0
    @Published private(set) var analysisDeferredForCurrentSession = false
    @Published private(set) var packageStage = ""
    @Published private(set) var packageElapsedSeconds: Double = 0
    private var packageStartedAt = Date()
    private var packageTask: Task<Void, Never>?
    private var packageCancelFlag: PackageCancelFlag?
    @Published private(set) var namingStyle: SessionNamingStyle = .automaticConcise
    @Published private(set) var sessionNamePreview = "—"
    @Published private(set) var namingConflict = false
    private var frozenSessionName: String?
    private var namingRefreshTick = 0
    private var saveStartedAt = Date()
    private var lastProgressUIRefresh = Date.distantPast

    // MARK: - Restore monitor / selective save / on-demand package
    @Published private(set) var autoMonitorEnabled = false
    @Published private(set) var monitorState = "OFF"
    @Published private(set) var isListening = false
    @Published private(set) var listenStarting = false
    @Published private(set) var listenError: String?
    @Published private(set) var saveDecision: SaveDecision = .notDecided
    @Published private(set) var packageDirectory: String
    @Published var packageTemplate: String {
        didSet { UserDefaults.standard.set(packageTemplate, forKey: Self.packageTemplateKey) }
    }
    @Published var packageIncludeTimeline: Bool {
        didSet { UserDefaults.standard.set(packageIncludeTimeline, forKey: Self.packageTimelineKey) }
    }
    @Published var packageIncludeSummary: Bool {
        didSet { UserDefaults.standard.set(packageIncludeSummary, forKey: Self.packageSummaryKey) }
    }
    @Published var packageIncludeUpdaterOutput: Bool {
        didSet { UserDefaults.standard.set(packageIncludeUpdaterOutput, forKey: Self.packageUpdaterKey) }
    }
    @Published private(set) var packagePreview = "—"
    @Published private(set) var evidencePackageState = "NOT_REQUESTED"
    @Published private(set) var evidencePackagePath = "—"
    @Published private(set) var evidencePackageStatus = "需要时手动导出本次证据包。"

    private var restoreMonitor: RestoreStartMonitor?
    private var latestSavedSource: SessionPackageSource?
    private var pendingSessionID: UUID?
    private var pendingRawPath: String?
    private var pendingDiagnosticURL: URL?

    // MARK: - 014H imported evidence workflow
    enum ImportState: String {
        case idle = "未导入"
        case analyzing = "分析中…"
        case completed = "分析完成"
        case failed = "分析失败"
    }

    @Published private(set) var importState: ImportState = .idle
    @Published private(set) var importedFileName = "—"
    @Published private(set) var importedFileSize = "—"
    @Published private(set) var importedAnalysis: ImportedDiagnosticAnalysis?
    @Published private(set) var importStatus = "选择已有的 Restore 原始日志；只读分析，不修改原始文件。"

    private var importedRawURL: URL?
    private var importedDiagnosticURL: URL?
    private var importTask: Task<Void, Never>?

    private var engine: CaptureCoordinator?
    private var sessionID: UUID?
    /// Read-only projection of the growing raw log. It never touches session
    /// state, so the UI timer cannot advance the F05/A10 lifecycle.
    private var statsTask: Task<Void, Never>?
    /// Invalidates in-flight snapshots. Bumped on every phase change so a status
    /// read that started before a stop can never overwrite the final numbers —
    /// the same stale-write discipline A10 established for getStatus.
    private var statsGeneration = 0

    // MARK: - Optional Restore-start monitor (no DFU trigger)

    /// Set at the first hint of termination; blocks new automatic sessions.
    private var terminating = false

    private static func isTestResidualPath(_ path: String) -> Bool {
        // Only our known legacy test exports are treated as residue. A real
        // user may legitimately use a directory named "test" or a test HOME.
        path.contains("RLM_RAW_MVP_20261108T2030Z/test/")
            || path.contains("/test/export_final")
            || path.contains("/test/export")
    }

    init() {
        let defaults = UserDefaults.standard
        let legacy = UserDefaults(suiteName: Self.legacySuiteName)
        func stringSetting(_ key: String) -> String? {
            if let v = defaults.string(forKey: key), !v.isEmpty { return v }
            if let v = legacy?.string(forKey: key), !v.isEmpty {
                defaults.set(v, forKey: key)
                return v
            }
            return nil
        }
        let stored = stringSetting(Self.destinationKey)
        let defaultExportDirectory: String
        if let stored, !stored.isEmpty {
            defaultExportDirectory = stored
        } else {
            defaultExportDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop/Restore Logs", isDirectory: true).path
        }
        // A path created by our own MVP tests is not a user preference.
        // Keep the legacy value intact, but start the new candidate on a safe
        // desktop default and tell the user which path was ignored.
        let safeExportDirectory: String
        if Self.isTestResidualPath(defaultExportDirectory) {
            pathMigrationNotice = "已忽略测试残留导出路径，请重新选择：\(defaultExportDirectory)"
            safeExportDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop/Restore Logs", isDirectory: true).path
        } else {
            safeExportDirectory = defaultExportDirectory
        }
        exportDirectory = safeExportDirectory
        // Only a default path is created at launch. A persisted custom path
        // that disappeared must surface as an invalid path instead of being
        // silently recreated at a guessed location.
        if stored == nil || stored?.isEmpty == true || Self.isTestResidualPath(stored ?? "") {
            try? FileManager.default.createDirectory(
                atPath: safeExportDirectory, withIntermediateDirectories: true)
        }
        let defaultRawSaveDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/Restore Logs", isDirectory: true).path
        let storedRaw = stringSetting(Self.rawSaveDirectoryKey)
        if let storedRaw, !storedRaw.isEmpty, !Self.isTestResidualPath(storedRaw) {
            rawSaveDirectory = storedRaw
        } else {
            rawSaveDirectory = defaultRawSaveDirectory
            try? FileManager.default.createDirectory(
                atPath: defaultRawSaveDirectory, withIntermediateDirectories: true)
        }
        baseName = stringSetting(Self.baseNameKey) ?? ""

        let pkgDir = stringSetting(Self.packageDirectoryKey)
        packageDirectory = (pkgDir?.isEmpty == false) ? pkgDir! : FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/RLM Evidence", isDirectory: true).path
        packageTemplate = stringSetting(Self.packageTemplateKey) ?? SessionPackageNaming.rawDefaultTemplate
        packageIncludeTimeline = defaults.object(forKey: Self.packageTimelineKey) == nil
            ? true : defaults.bool(forKey: Self.packageTimelineKey)
        packageIncludeSummary = defaults.object(forKey: Self.packageSummaryKey) == nil
            ? true : defaults.bool(forKey: Self.packageSummaryKey)
        packageIncludeUpdaterOutput = defaults.object(forKey: Self.packageUpdaterKey) == nil
            ? true : defaults.bool(forKey: Self.packageUpdaterKey)
        if defaults.object(forKey: Self.autoMonitorKey) == nil,
           legacy?.object(forKey: Self.autoMonitorKey) == nil {
            // Raw MVP: begin in passive listening mode on first launch.
            autoMonitorEnabled = true
            defaults.set(true, forKey: Self.autoMonitorKey)
        } else if defaults.object(forKey: Self.autoMonitorKey) == nil,
                  let legacyValue = legacy?.object(forKey: Self.autoMonitorKey) as? Bool {
            autoMonitorEnabled = legacyValue
            defaults.set(legacyValue, forKey: Self.autoMonitorKey)
        } else {
            autoMonitorEnabled = defaults.bool(forKey: Self.autoMonitorKey)
        }
        if let rawStyle = stringSetting(Self.namingStyleKey),
           let style = SessionNamingStyle(rawValue: rawStyle) {
            namingStyle = style
        }

        RLMAppTermination.register(self)
        Task { [weak self] in await self?.loadLatestSavedSession() }
        startRestoreMonitorIfNeeded()
    }

    /// True while this app owns a capture or an unresolved save/discard decision.
    var ownsAnActiveCapture: Bool {
        switch phase {
        case .starting, .recording, .stopping, .decisionPending, .saving: return true
        default: return false
        }
    }

    var needsTerminationDecision: Bool { ownsAnActiveCapture }

    /// Called from the termination delegate before any awaiting begins.
    func beginTermination() {
        terminating = true
        stopRestoreMonitor()
    }

    /// User cancelled the quit prompt. Keep the capture and do not lose data.
    func cancelTermination() {
        terminating = false
        if !ownsAnActiveCapture { startRestoreMonitorIfNeeded() }
    }

    /// Stops the capture we own and waits for the child to actually exit.
    /// save=true commits raw; save=false discards only this session.
    @MainActor
    func shutdownForTermination(save: Bool) async {
        statsTask?.cancel()
        statsTask = nil
        // Do not let a quit race a start/stop/finalize transition. Wait for a
        // stable, owned phase before deciding; never silently orphan the child.
        for _ in 0..<50 {
            switch phase {
            case .starting, .stopping, .saving:
                try? await Task.sleep(nanoseconds: 100_000_000)
            default:
                break
            }
            if phase != .starting && phase != .stopping && phase != .saving { break }
        }
        do {
            if phase == .recording, let engine, let sessionID {
                _ = try await engine.stopCapture(sessionID: sessionID)
            }
            if phase == .recording || phase == .decisionPending {
                if save {
                    try await finalizePendingSession()
                } else {
                    try await discardCurrentSession()
                }
            }
        } catch {
            phase = .failed
            detail = "应用退出前处理失败：\(error)"
        }
    }

    deinit {
        restoreMonitor?.stop()
        restoreMonitor = nil
    }

    func setAutoMonitorEnabled(_ enabled: Bool) {
        if enabled {
            startListening()
        } else {
            stopListening()
        }
    }

    /// The main “开始监听” action. It must start the real RestoreStartMonitor,
    /// which owns the passive `/usr/bin/log stream` process.
    func startListening() {
        guard !listenStarting, !isListening, !terminating else { return }
        switch phase {
        case .idle, .saved, .discarded, .failed:
            break
        default:
            listenError = "当前采集尚未结束；请先处理当前任务，再开始监听。"
            return
        }
        autoMonitorEnabled = true
        UserDefaults.standard.set(true, forKey: Self.autoMonitorKey)
        listenStarting = true
        listenError = nil
        Task { @MainActor in
            await Task.yield()
            self.startRestoreMonitorIfNeeded()
            self.listenStarting = false
            if !self.isListening && self.listenError == nil {
                self.listenError = "监听未启动：当前状态不允许。"
            }
        }
    }

    /// Stop only the passive listener. Never stop/discard an active capture or
    /// unsaved pending session.
    func stopListening() {
        listenStarting = false
        listenError = nil
        stopRestoreMonitor()
        isListening = false
        autoMonitorEnabled = false
        UserDefaults.standard.set(false, forKey: Self.autoMonitorKey)
        monitorState = "OFF"
    }

    private func startRestoreMonitorIfNeeded() {
        guard autoMonitorEnabled, !terminating, restoreMonitor == nil else { return }
        switch phase {
        case .idle, .saved, .discarded, .failed: break
        default: return
        }
        let monitor = RestoreStartMonitor(
            onStart: { [weak self] context in
                DispatchQueue.main.async { self?.handleRestoreStarted(context: context) }
            },
            onFailure: { [weak self] reason in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.restoreMonitor?.stop()
                    self.restoreMonitor = nil
                    self.monitorState = "FAILED"
                    self.isListening = false
                    self.autoMonitorEnabled = false
                    UserDefaults.standard.set(false, forKey: Self.autoMonitorKey)
                    self.listenError = "监听失败：\(reason)"
                    self.detail = "Restore 监控不可用：\(reason)；手动采集仍可用。"
                }
            }
        )
        do {
            try monitor.start()
            restoreMonitor = monitor
            isListening = true
            listenStarting = false
            listenError = nil
            monitorState = "WAITING_FOR_RESTORE"
        } catch {
            isListening = false
            autoMonitorEnabled = false
            UserDefaults.standard.set(false, forKey: Self.autoMonitorKey)
            listenError = "监听启动失败：\(error.localizedDescription)"
            monitorState = "FAILED"
            detail = "Restore 监控启动失败：\(error)；手动采集仍可用。"
        }
    }

    private func stopRestoreMonitor() {
        restoreMonitor?.stop()
        restoreMonitor = nil
        isListening = false
        listenStarting = false
        if autoMonitorEnabled { monitorState = "OFF" }
    }

    private func restartMonitorAfterDecision() {
        guard autoMonitorEnabled, !terminating else { return }
        startRestoreMonitorIfNeeded()
    }

    private func handleRestoreStarted(context: String) {
        guard autoMonitorEnabled, !terminating else { return }
        switch phase {
        case .idle, .saved, .discarded, .failed:
            monitorState = "TRIGGERED"
            start(preCaptureContext: context, automatic: true)
        default:
            // Manual/other capture already owns the session; never double-start.
            break
        }
    }

    private func makeEngine() throws -> CaptureCoordinator {
        let root = try EvidenceStore.defaultRoot()
        return CaptureCoordinator(backend: ProcessLogCaptureBackend(), store: EvidenceStore(root: root))
    }

    private func loadLatestSavedSession() async {
        guard let root = try? EvidenceStore.defaultRoot(),
              let latest = try? EvidenceStore(root: root).latestSavedSession() else { return }
        latestSavedSource = SessionEvidencePackage.source(record: latest.record, directory: latest.directory)
        let inherited = SessionEvidencePackage.displayName(for: latest.record)
        frozenSessionName = inherited
        if namingStyle == .custom {
            sessionNamePreview = ExportNaming.sanitizedBase(baseName)
        } else {
            sessionNamePreview = inherited
        }
        if rawLogPath == "—" {
            rawLogPath = latest.directory.appendingPathComponent("restore.log").path
            lastSessionIsPartial = latest.record.captureState != .savedVerified
        }
        updatePackagePreview()
    }

    private func updatePackagePreview() {
        guard let source = latestSavedSource else { packagePreview = "—"; return }
        packagePreview = packageBaseName(for: source) + ".zip"
    }

    private func packageBaseName(for source: SessionPackageSource) -> String {
        SessionEvidencePackage.packageName(
            template: packageTemplate,
            source: source,
            terminal: "UNKNOWN"
        )
    }

    var packageDirectoryIssue: String? { directoryIssue(packageDirectory) }

    func setNamingStyle(_ style: SessionNamingStyle) {
        namingStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: Self.namingStyleKey)
        refreshNamingPreview()
    }

    func setCustomSessionName(_ value: String) {
        baseName = value
        namingStyle = .custom
        UserDefaults.standard.set(namingStyle.rawValue, forKey: Self.namingStyleKey)
        sessionNamePreview = ExportNaming.sanitizedBase(value)
    }

    /// Recompute display name from immutable raw; never from later devices.
    private func refreshNamingPreview() {
        guard rawLogPath != "—", FileManager.default.fileExists(atPath: rawLogPath) else {
            sessionNamePreview = "—"
            return
        }
        let path = rawLogPath
        Task.detached(priority: .utility) { [weak self] in
            let evidence = SessionNamingReader.read(rawURL: URL(fileURLWithPath: path), includeTerminal: false)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.namingConflict = evidence.conflict
                if self.namingStyle == .custom {
                    self.sessionNamePreview = ExportNaming.sanitizedBase(self.baseName)
                } else {
                    self.sessionNamePreview = SessionNamingReader.makeName(style: self.namingStyle, evidence: evidence)
                }
            }
        }
    }

    private func resolvedSessionName() -> String? {
        if namingStyle == .custom {
            let value = ExportNaming.sanitizedBase(baseName)
            return value.isEmpty ? nil : value
        }
        if sessionNamePreview == "—" || sessionNamePreview.isEmpty { return nil }
        return ExportNaming.sanitizedBase(sessionNamePreview)
    }

    /// F07-02 — live preview of the name the export will use.
    var fileNamePreview: String {
        ExportNaming.fileName(
            base: frozenSessionName ?? (namingStyle == .custom ? baseName : (sessionNamePreview == "—" ? "Session" : sessionNamePreview)),
            at: Date(),
            sessionID: sessionID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            isPartial: lastSessionIsPartial)
            .replacingOccurrences(of: "00000000", with: "SESSION")
    }

    // MARK: - 014H import / package export

    /// Import an existing raw log and run the already verified DiagnosticLogBuilder
    /// off the main actor. No capture session is started and no device is touched.
    func importLogAndAnalyze() {
        guard importState != .analyzing else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "分析"
        panel.message = "选择一份已有的 Restore 原始日志（restore.log / unified.ndjson）"
        panel.allowedFileTypes = ["log", "ndjson", "json", "txt"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        analyzeImported(rawURL: url)
    }

    private func analyzeImported(rawURL: URL) {
        importState = .analyzing
        importStatus = "正在分析 \(rawURL.lastPathComponent)…"
        importedFileName = rawURL.lastPathComponent
        importedFileSize = Self.displayBytes(
            (try? FileManager.default.attributesOfItem(atPath: rawURL.path)[.size] as? NSNumber)?.intValue
        )
        importedAnalysis = nil
        importedRawURL = rawURL
        importedDiagnosticURL = nil
        evidencePackagePath = "—"
        evidencePackageState = "NOT_REQUESTED"
        evidencePackageStatus = "分析完成后可导出完整证据包。"

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RestoreLogMonitor-Imported-\(UUID().uuidString)", isDirectory: true)
        let diagnosticURL = tempDir.appendingPathComponent("diagnostic.log")

        importTask = Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ImportedDiagnosticAnalyzer.analyze(rawURL: rawURL, diagnosticURL: diagnosticURL)
                }.value
                guard let self else { return }
                self.importedAnalysis = result
                self.importState = .completed
                self.importStatus = "分析完成；诊断报告已生成。"
                self.importedDiagnosticURL = diagnosticURL
                self.evidencePackageStatus = "可导出：原始日志 + 完整诊断 + 时间线/错误上下文 + 元数据 + SHA-256 清单。"
            } catch {
                guard let self else { return }
                self.importState = .failed
                self.importStatus = "分析失败：\(error.localizedDescription)"
                self.importedAnalysis = nil
                self.importedDiagnosticURL = nil
                self.importedRawURL = nil
            }
        }
    }

    func openImportedDiagnostic() {
        guard let url = importedDiagnosticURL,
              FileManager.default.fileExists(atPath: url.path) else {
            evidencePackageStatus = "打开失败：诊断报告不存在。"
            return
        }
        NSWorkspace.shared.open(url)
        evidencePackageStatus = "已打开完整诊断报告：\(url.lastPathComponent)"
    }

    /// One-click evidence package for an imported historical log. It uses the
    /// same independent package directory/template settings as current sessions.
    func exportImportedEvidencePackage() {
        guard let analysis = importedAnalysis,
              let rawURL = importedRawURL,
              let diagnosticURL = importedDiagnosticURL,
              FileManager.default.fileExists(atPath: diagnosticURL.path) else {
            evidencePackageState = "FAILED"
            evidencePackageStatus = "导出失败：请先完成一次成功的日志分析。"
            return
        }
        let identity = SessionEvidencePackage.identity(fromRawURL: rawURL)
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let context = SessionPackageNamingContext(
            date: String(format: "%04d%02d%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0),
            time: String(format: "%02d%02d%02d", comps.hour ?? 0, comps.minute ?? 0, comps.second ?? 0),
            model: identity.model ?? "UNKNOWN",
            ecid: identity.ecid ?? "UNKNOWN",
            restoreStatus: analysis.terminalKind.rawValue,
            sessionID: "IMPORTED"
        )
        try? FileManager.default.createDirectory(atPath: packageDirectory, withIntermediateDirectories: true)
        let defaultName = SessionPackageNaming.expand(template: packageTemplate, context: context)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.prompt = "导出"
        panel.message = "导出历史日志证据包（可临时修改名称/位置）"
        panel.directoryURL = URL(fileURLWithPath: packageDirectory)
        let defaultURL = URL(fileURLWithPath: packageDirectory).appendingPathComponent(defaultName)
        panel.nameFieldStringValue = Self.uniquePackageURL(defaultURL).lastPathComponent
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        let destination = Self.uniquePackageURL(Self.ensureZipExtension(chosen))
        let stageDirectory = destination.deletingLastPathComponent()
            .appendingPathComponent(".rlm-package-stage-\(UUID().uuidString)", isDirectory: true)
        evidencePackageState = "GENERATING"
        evidencePackageStatus = "正在生成证据包…"
        packageCancelFlag?.cancel()
        let cancelFlag = PackageCancelFlag()
        packageCancelFlag = cancelFlag
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let package = try ImportedEvidencePackageBuilder.build(
                        rawURL: rawURL,
                        diagnosticURL: diagnosticURL,
                        analysis: analysis,
                        destination: stageDirectory,
                        shouldCancel: { cancelFlag.isCancelled }
                    )
                    return try EvidencePackageArchive.archive(
                        packageDirectory: URL(fileURLWithPath: package.directoryPath),
                        destination: destination,
                        archiveRootName: defaultName,
                        shouldCancel: { cancelFlag.isCancelled }
                    )
                }.value
                self.evidencePackagePath = result.archiveURL.path
                self.evidencePackageState = "COMPLETED"
                self.evidencePackageStatus = "已导出证据包：\(result.archiveURL.path)"
                NSWorkspace.shared.activateFileViewerSelecting([result.archiveURL])
            } catch {
                self.evidencePackageState = "FAILED"
                self.evidencePackageStatus = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    func openEvidencePackageFolder() {
        let path = evidencePackagePath
        guard path != "—" else {
            evidencePackageStatus = "打开失败：尚未导出证据包。"
            return
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            evidencePackageStatus = "打开失败：证据包目录不存在。"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        evidencePackageStatus = "已在 Finder 中打开证据包。"
    }

    private static func displayBytes(_ value: Int?) -> String {
        guard let value else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    private static func packageTimestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    /// F07-01 — native folder picker. Cancelling leaves the setting untouched.
    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "选择日志导出位置"
        panel.directoryURL = URL(fileURLWithPath: exportDirectory)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportDirectory = url.path
        UserDefaults.standard.set(url.path, forKey: Self.destinationKey)
        exportedURL = nil
        exportStatus = "保存位置已更新。"
    }

    func chooseRawSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "选择原始日志自动保存目录"
        panel.directoryURL = URL(fileURLWithPath: rawSaveDirectory)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rawSaveDirectory = url.path
        UserDefaults.standard.set(url.path, forKey: Self.rawSaveDirectoryKey)
        pathMigrationNotice = nil
        exportStatus = "原始日志自动保存目录已更新：\\(url.path)"
    }

    var rawSaveDirectoryIssue: String? { directoryIssue(rawSaveDirectory) }
    var exportDirectoryIssue: String? { directoryIssue(exportDirectory) }

    private func directoryIssue(_ path: String) -> String? {
        if Self.isTestResidualPath(path) { return "测试残留路径；请重新选择正式保存目录。" }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            if !isDir.boolValue { return "该路径不是文件夹。" }
            if !FileManager.default.isWritableFile(atPath: path) { return "该目录不可写，请重新选择。" }
            return nil
        }
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) { return "父目录不存在，请重新选择。" }
        if !FileManager.default.isWritableFile(atPath: parent.path) { return "父目录不可写，请重新选择。" }
        return nil
    }

    // MARK: - Evidence package settings (independent from raw log settings)

    func choosePackageDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "选择证据包默认导出位置"
        panel.directoryURL = URL(fileURLWithPath: packageDirectory)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        packageDirectory = url.path
        UserDefaults.standard.set(url.path, forKey: Self.packageDirectoryKey)
        evidencePackageStatus = "证据包默认位置已更新。"
        updatePackagePreview()
    }

    func refreshPackagePreview() {
        updatePackagePreview()
    }

    func setPackageTemplate(_ value: String) {
        packageTemplate = value
        updatePackagePreview()
    }

    /// Session package source for current/recent saved capture. No import
    /// file picker is used here.
    func currentPackageSource() -> SessionPackageSource? {
        latestSavedSource
    }

    func exportCurrentEvidencePackage(saveAs: Bool = false) {
        guard let source = latestSavedSource else {
            evidencePackageState = "FAILED"
            evidencePackageStatus = "导出失败：还没有已保存的采集会话。"
            return
        }
        guard phase != .recording, phase != .starting, phase != .stopping,
              phase != .saving, phase != .decisionPending else {
            evidencePackageState = "FAILED"
            evidencePackageStatus = "导出失败：请先结束并处理当前采集。"
            return
        }
        if let issue = packageDirectoryIssue {
            evidencePackageState = "FAILED"
            evidencePackageStatus = "导出失败：\(issue)"
            return
        }
        let base = packageBaseName(for: source)
        let dir = URL(fileURLWithPath: packageDirectory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            evidencePackageState = "FAILED"
            evidencePackageStatus = "导出失败：无法创建证据包目录：\(error.localizedDescription)"
            return
        }
        let destination: URL
        if saveAs {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.prompt = "导出"
            panel.message = "导出本次证据包；临时名称只影响本次导出"
            panel.directoryURL = dir
            panel.nameFieldStringValue = Self.uniquePackageURL(
                dir.appendingPathComponent(base + ".zip")
            ).lastPathComponent
            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            destination = Self.uniquePackageURL(Self.ensureZipExtension(chosen))
        } else {
            destination = Self.uniquePackageURL(dir.appendingPathComponent(base + ".zip"))
        }
        evidencePackageState = "GENERATING"
        evidencePackageStatus = "正在打包：\(base).zip"
        packageStage = "PACKAGING"
        let rootName = base
        let options = RawEvidencePackageOptions(
            includeTimeline: packageIncludeTimeline,
            includeSummary: packageIncludeSummary,
            includeUpdaterOutput: packageIncludeUpdaterOutput
        )
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try RawEvidencePackageBuilder.build(
                        source: source,
                        destination: destination,
                        archiveRootName: rootName,
                        options: options
                    )
                }.value
                self.evidencePackagePath = result.archiveURL.path
                self.evidencePackageState = "COMPLETED"
                let included = result.includedAttachments.joined(separator: ", ")
                let skipped = result.skippedAttachments
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)：\($0.value)" }
                    .joined(separator: "；")
                self.evidencePackageStatus = "已导出证据包：\(result.archiveURL.lastPathComponent)（ZIP 与 SHA-256 已校验）\n附件：\(included.isEmpty ? "无" : included)\(skipped.isEmpty ? "" : "；未包含：\(skipped)")"
                self.packageStage = ""
                NSWorkspace.shared.activateFileViewerSelecting([result.archiveURL])
            } catch let error as RawEvidencePackageError {
                self.evidencePackageState = "FAILED"
                self.evidencePackageStatus = "导出失败（原始日志保留）：\(error.localizedDescription)"
                self.packageStage = ""
            } catch {
                self.evidencePackageState = "FAILED"
                self.evidencePackageStatus = "导出失败（原始日志保留）：\(error.localizedDescription)"
                self.packageStage = ""
            }
        }
    }

    private static func ensureZipExtension(_ url: URL) -> URL {
        url.pathExtension.lowercased() == "zip" ? url : url.appendingPathExtension("zip")
    }

    private static func uniquePackageURL(_ chosen: URL) -> URL {
        var candidate = chosen
        var suffix = 2
        let stem = chosen.deletingPathExtension().lastPathComponent
        let ext = chosen.pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
            candidate = chosen.deletingLastPathComponent().appendingPathComponent(name)
            suffix += 1
        }
        return candidate
    }

    func start(preCaptureContext: String? = nil, automatic: Bool = false) {
        switch phase {
        case .idle, .saved, .discarded, .failed: break
        default: return
        }
        if automatic {
            stopRestoreMonitor()
        }
        phase = .starting
        monitorState = automatic ? "TRIGGERED" : (isListening ? "WAITING_FOR_RESTORE" : "OFF")
        detail = automatic ? "检测到 Restore 开始，正在启动采集…" : "初始化本次会话…"
        exportedURL = nil
        exportStatus = "采集进行中；结束后由你选择保存或丢弃。"
        evidencePackageState = "NOT_REQUESTED"
        evidencePackagePath = "—"
        evidencePackageStatus = "需要时手动导出本次证据包。"
        saveDecision = .notDecided
        saveStage = ""
        saveProcessedBytes = 0
        saveTotalBytes = 0
        saveElapsedSeconds = 0
        saveBytesPerSecond = 0
        saveFraction = 0
        analysisDeferredForCurrentSession = false
        packageStage = ""
        frozenSessionName = nil
        sessionNamePreview = "—"
        namingConflict = false
        Task {
            do {
                let engine = try makeEngine()
                self.engine = engine
                let handle = try await engine.beginCapture(
                    config: CaptureConfig(
                        outputDirectory: URL(fileURLWithPath: self.handleDirectory()),
                        ecidHint: nil,
                        preCaptureContext: preCaptureContext
                    )
                )
                self.sessionID = handle.sessionID
                self.pendingSessionID = nil
                self.rawLogPath = handle.rawLogPath
                self.eventCount = nil
                self.byteCount = nil
                self.saveDecision = .notDecided
                self.phase = .recording
                self.detail = "采集进程已启动（PID \(handle.backendPID)）。"
                self.refreshNamingPreview()
                self.startStatsStream(path: handle.rawLogPath)
            } catch {
                self.phase = .failed
                self.detail = "启动失败：\(error)"
                self.restartMonitorAfterDecision()
            }
        }
    }

    /// Manual stop: stop the owned child first, then ask save/discard. No
    /// finalization and no package are performed here.
    func stopCaptureForDecision() {
        guard phase == .recording, let engine, let sessionID else { return }
        statsGeneration += 1
        statsTask?.cancel()
        statsTask = nil
        phase = .stopping
        detail = "正在停止采集进程…"
        Task {
            do {
                _ = try await engine.stopCapture(sessionID: sessionID)
                self.pendingSessionID = sessionID
                self.pendingRawPath = self.rawLogPath
                self.pendingDiagnosticURL = URL(fileURLWithPath: self.rawLogPath)
                    .deletingLastPathComponent()
                    .appendingPathComponent("diagnostic.log")
                self.phase = .decisionPending
                self.detail = "采集已停止。请选择保存本次日志或丢弃本次日志。"
            } catch {
                self.phase = .failed
                self.detail = "停止失败：\(error)"
                self.restartMonitorAfterDecision()
            }
        }
    }

    func savePendingSession() {
        Task {
            do {
                try await finalizePendingSession()
            } catch {
                self.phase = .failed
                self.detail = "保存失败：\(error)"
                self.restartMonitorAfterDecision()
            }
        }
    }

    @MainActor
    private func finalizePendingSession() async throws {
        guard let engine, let sid = pendingSessionID ?? sessionID else {
            throw CaptureError.noActiveSession
        }
        phase = .saving
        saveStartedAt = Date()
        saveProcessedBytes = 0
        saveTotalBytes = 0
        saveElapsedSeconds = 0
        saveBytesPerSecond = 0
        saveFraction = 0
        saveStage = "PREPARING"
        detail = "正在保存原始日志（不运行完整诊断）…"
        // Final freeze: rescan immutable raw at the save boundary so the name
        // cannot be changed by a later device or by a stale live preview.
        if rawLogPath != "—" {
            let evidence = SessionNamingReader.read(rawURL: URL(fileURLWithPath: rawLogPath))
            namingConflict = evidence.conflict
            if namingStyle != .custom {
                sessionNamePreview = SessionNamingReader.makeName(style: namingStyle, evidence: evidence)
            }
        }
        if namingConflict && namingStyle != .custom {
            phase = .decisionPending
            detail = "检测到多设备身份冲突；请选择自定义名称后再保存。"
            return
        }
        let finalName = resolvedSessionName()
            ?? "Session-\(ExportNaming.shortSessionID(sid))"
        frozenSessionName = ExportNaming.sanitizedBase(finalName)
        let exported = try await engine.finalize(
            sessionID: sid,
            mode: .saveOnly,
            displayName: frozenSessionName,
            progress: { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.saveStage = progress.stage
                    self.saveElapsedSeconds = progress.elapsedSeconds
                    if progress.totalBytes > 0 {
                        self.saveProcessedBytes = progress.processedBytes
                        self.saveTotalBytes = progress.totalBytes
                        let ratio = progress.totalBytes > 0
                            ? min(1, max(0, Double(progress.processedBytes) / Double(progress.totalBytes)))
                            : 0
                        let stageRatio: Double = progress.stage == "HASHING_RAW" ? 0.65 * ratio : 0.65
                        self.saveFraction = max(self.saveFraction, stageRatio)
                        self.saveBytesPerSecond = progress.elapsedSeconds > 0.001
                            ? Double(progress.processedBytes) / progress.elapsedSeconds : 0
                    }
                }
            })
        let directory = URL(fileURLWithPath: rawLogPath).deletingLastPathComponent()
        let source = SessionEvidencePackage.source(record: exported.record, directory: directory)
        latestSavedSource = source
        lastSessionIsPartial = exported.record.captureState != .savedVerified
        analysisDeferredForCurrentSession = exported.record.analysisDeferred == true
        pendingSessionID = nil
        pendingRawPath = nil
        pendingDiagnosticURL = nil
        sessionID = nil
        saveDecision = .saved
        eventCount = nil
        byteCount = exported.record.files.first { $0.role == "raw-log" }?.byteSize ?? 0
        saveStage = "COMPLETE"
        saveFraction = 1
        phase = .saved
        detail = analysisDeferredForCurrentSession
            ? "原始日志已保存并校验；诊断分析将在你主动分析或导出证据包时进行。"
            : "原始日志已保存并校验。"
        updatePackagePreview()
        archiveRawAfterSave(record: exported.record)
        restartMonitorAfterDecision()
    }

    func discardPendingSession() {
        Task {
            do {
                try await discardCurrentSession()
            } catch {
                phase = .failed
                detail = "丢弃失败，临时采集数据仍保留：\(error)"
                restartMonitorAfterDecision()
            }
        }
    }

    @MainActor
    private func discardCurrentSession() async throws {
        guard let engine, let sid = pendingSessionID ?? sessionID else {
            throw CaptureError.noActiveSession
        }
        _ = try await engine.discard(sessionID: sid)
        pendingSessionID = nil
        pendingRawPath = nil
        pendingDiagnosticURL = nil
        sessionID = nil
        rawLogPath = "—"
        eventCount = nil
        byteCount = nil
        saveDecision = .discarded
        phase = .discarded
        detail = "本次日志已丢弃；其他会话与历史证据未受影响。"
        exportStatus = "本次日志未保存。"
        restartMonitorAfterDecision()
    }

    /// F07 — publish a verified derivative copy. The authoritative evidence in
    /// Application Support is only ever read, never moved or rewritten.
    private func exportDerivative(record: SessionRecord) {
        guard let raw = record.files.first(where: { $0.role == "raw-log" }) else {
            exportStatus = "保存失败：会话中找不到原始日志。"
            return
        }
        let sourceURL = URL(fileURLWithPath: rawLogPath)
        let destination = URL(fileURLWithPath: exportDirectory)
        let request = ExportRequest(
            sourceURL: sourceURL,
            destinationDirectory: destination,
            baseName: frozenSessionName ?? record.sessionDisplayName ?? baseName,
            sessionID: record.sessionID,
            isPartial: record.captureState != .savedVerified,
            expectedSourceSHA256: raw.sha256)
        saveStage = "COPYING_AND_VERIFYING_RAW"
        saveProcessedBytes = 0
        saveTotalBytes = Int64(raw.byteSize)
        saveFraction = max(saveFraction, 0.65)
        saveStartedAt = Date()
        exportStatus = "正在复制并校验原始日志…"
        // Hashing and copying happen on the exporter actor, never on the main thread.
        Task {
            do {
                let outcome = try await LogExporter().export(request) { done, total in
                    if done == total || done % (16 * 1024 * 1024) == 0 {
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.saveStage = "COPYING_AND_VERIFYING_RAW"
                            self.saveProcessedBytes = done
                            self.saveTotalBytes = total
                            self.saveElapsedSeconds = Date().timeIntervalSince(self.saveStartedAt)
                            let ratio = total > 0 ? min(1, max(0, Double(done) / Double(total))) : 0
                            self.saveFraction = max(self.saveFraction, 0.65 + 0.35 * ratio)
                            self.saveBytesPerSecond = self.saveElapsedSeconds > 0.001 ? Double(done) / self.saveElapsedSeconds : 0
                        }
                    }
                }
                self.exportedURL = outcome.url
                self.exportStatus = "已保存：\(outcome.url.lastPathComponent)"
                self.saveStage = "COMPLETE"
                self.saveFraction = 1
                self.saveElapsedSeconds = Date().timeIntervalSince(self.saveStartedAt)
            } catch let error as LogExportError {
                self.exportedURL = nil
                self.exportStatus = "导出失败：\(error.description)"
            } catch {
                self.exportedURL = nil
                self.exportStatus = "导出失败：\(error)"
            }
        }
    }


    /// Clipboard source kind for explicit exportStatus labeling (DIAGNOSTIC_STATUS_SEPARATION).
    private enum CopyFileSource {
        case diagnostic
        case exportedRaw   // verified export derivative
        case boundRaw      // session-bound restore.log
    }

    /// MVP — explicit raw-only export. This path never touches diagnostic
    /// cache, importer, package builder or ZIP archive.
    func exportRawLog() {
        guard let source = latestSavedSource else {
            exportStatus = "导出失败：请先保存一次原始日志。"
            return
        }
        exportRaw(source: source, directory: exportDirectory, automatic: false)
    }

    private func archiveRawAfterSave(record: SessionRecord) {
        guard let source = latestSavedSource else { return }
        let destination = rawSaveDirectory
        guard directoryIssue(destination) == nil else {
            exportStatus = "原始日志已内部保存；自动保存目录无效：\(directoryIssue(destination) ?? "")"
            return
        }
        exportRaw(source: source, directory: destination, automatic: true)
    }

    private func exportRaw(source: SessionPackageSource, directory: String, automatic: Bool) {
        guard !rawExportBusy else { return }
        guard let raw = source.record.files.first(where: { $0.role == "raw-log" }),
              FileManager.default.fileExists(atPath: source.rawURL.path) else {
            exportStatus = "导出失败：找不到原始日志。"
            return
        }
        if let issue = directoryIssue(directory) {
            exportStatus = "导出失败：\(issue)"
            return
        }
        let destination = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            exportStatus = "导出失败：无法创建目录：\(error.localizedDescription)"
            return
        }
        rawExportBusy = true
        exportStatus = automatic ? "正在自动保存原始日志…" : "正在导出原始日志…"
        let isPartial = source.record.captureState != .savedVerified
        let requestBaseName: String
        let override: String?
        if namingStyle == .custom {
            let sanitized = ExportNaming.sanitizedBase(baseName)
            requestBaseName = sanitized.isEmpty ? "Session" : sanitized
            override = nil
        } else {
            requestBaseName = "Session"
            override = ExportNaming.rawMVPSessionFileName(
                at: Date(), sessionID: source.record.sessionID, isPartial: isPartial
            )
        }
        let request = ExportRequest(
            sourceURL: source.rawURL,
            destinationDirectory: destination,
            baseName: requestBaseName,
            sessionID: source.record.sessionID,
            isPartial: isPartial,
            expectedSourceSHA256: raw.sha256,
            fileNameOverride: override
        )
        Task {
            do {
                let outcome = try await LogExporter().export(request)
                self.rawSavedURL = outcome.url
                if automatic {
                    self.exportStatus = "原始日志已自动保存：\(outcome.url.path)"
                } else {
                    self.exportedURL = outcome.url
                    self.exportStatus = outcome.isPartial
                        ? "已导出原始日志（PARTIAL）：\(outcome.url.lastPathComponent)"
                        : "已导出原始日志：\(outcome.url.lastPathComponent)"
                }
            } catch let error as LogExportError {
                self.exportStatus = "导出失败（原始日志保留）：\(error.description)"
            } catch {
                self.exportStatus = "导出失败（原始日志保留）：\(error)"
            }
            self.rawExportBusy = false
        }
    }

    var rawExportPreview: String {
        let id = latestSavedSource?.record.sessionID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let partial = latestSavedSource?.record.captureState != .savedVerified
        if namingStyle == .custom {
            let base = ExportNaming.sanitizedBase(baseName)
            return ExportNaming.fileName(base: base.isEmpty ? "Session" : base, at: Date(), sessionID: id, isPartial: partial)
                .replacingOccurrences(of: "00000000", with: "SESSION")
        }
        return ExportNaming.rawMVPSessionFileName(at: Date(), sessionID: id, isPartial: partial)
            .replacingOccurrences(of: "00000000", with: "SESSION")
    }

    func copyPath(_ path: String) {
        guard path != "—", !path.isEmpty else { exportStatus = "没有可复制的路径。"; return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        exportStatus = "已复制完整路径：\(path)"
    }

    func revealPath(_ path: String) {
        guard path != "—", !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    func openRawSaveDirectory() {
        revealPath(rawSaveDirectory)
    }

    func openRecentSessionDirectory() {
        guard rawLogPath != "—" else { exportStatus = "没有最近 Session。"; return }
        let dir = URL(fileURLWithPath: rawLogPath).deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: dir.path) else {
            exportStatus = "最近 Session 目录不存在。"; return
        }
        NSWorkspace.shared.open(dir)
        exportStatus = "已打开最近 Session 目录：\(dir.path)"
    }

    func copyRawLogFile() {
        guard rawLogPath != "—", FileManager.default.fileExists(atPath: rawLogPath) else {
            exportStatus = "复制失败：没有原始日志。"; return
        }
        let url = URL(fileURLWithPath: rawLogPath)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
        exportStatus = "已复制原始日志文件：\(url.lastPathComponent)"
    }

    func openRawExportDirectory() {
        let url = URL(fileURLWithPath: exportDirectory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
            exportStatus = "已打开原始日志导出目录：\(url.path)"
        } catch {
            exportStatus = "打开目录失败：\(error.localizedDescription)"
        }
    }

    /// F07-03 / FIX-001 — put the FILE on the clipboard, not a path string and not the text.
    /// Prefer session `diagnostic.log` when that file already exists; otherwise the verified
    /// export (`exportedURL`) or the bound session `restore.log`. Never load full text into
    /// the pasteboard. Refuse while capturing. Never pick newest-on-disk.
    /// Fallback to raw/export MUST label exportStatus with 「原始/导出」 (no silent fallback).
    func copyLog() {
        if ownsAnActiveCapture || phase == .saving {
            exportStatus = "复制失败：采集进行中，请先结束采集再复制文件。"
            return
        }
        guard let resolved = resolveCopyFileURL() else { return }
        let url = resolved.url
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attrs?[.size] as? NSNumber, size.intValue == 0 {
            exportStatus = "复制失败：日志为空，没有可复制的内容。"
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let ok = pasteboard.writeObjects([url as NSURL])
        guard ok else {
            exportStatus = "复制失败：系统拒绝了写入剪贴板。"
            return
        }
        let readBack = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        let match = readBack.contains { $0.standardizedFileURL.path == url.standardizedFileURL.path }
        guard match else {
            exportStatus = "复制失败：剪贴板写入或回读校验未通过。"
            return
        }
        switch resolved.source {
        case .diagnostic:
            exportStatus = "已复制诊断日志文件：\(url.lastPathComponent)"
        case .exportedRaw:
            exportStatus = "已复制导出日志文件（原始/导出）：\(url.lastPathComponent)"
        case .boundRaw:
            exportStatus = "已复制原始日志文件（原始/导出）：\(url.lastPathComponent)"
        }
    }

    /// FIX-001 source selection (session-bound only; no newest-mtime heuristic).
    /// Order: existing `diagnostic.log` → verified `exportedURL` → session `restore.log`.
    private func resolveCopyFileURL() -> (url: URL, source: CopyFileSource)? {
        let fm = FileManager.default
        if let diagnostic = existingDiagnosticLogURL() {
            return (diagnostic, .diagnostic)
        }
        if let exportedURL {
            if fm.fileExists(atPath: exportedURL.path) {
                return (exportedURL, .exportedRaw)
            }
            self.exportedURL = nil
            exportStatus = "复制失败：导出文件已不存在。"
            return nil
        }
        if rawLogPath != "—", fm.fileExists(atPath: rawLogPath) {
            // Explicit old-session / post-capture compat: bound restore.log only.
            return (URL(fileURLWithPath: rawLogPath), .boundRaw)
        }
        exportStatus = "复制失败：还没有可复制的导出文件。"
        return nil
    }

    /// Prefer `diagnostic.log` only when the file is already present beside the
    /// verified export or inside the bound session directory (FIX-002 may create it later).
    private func existingDiagnosticLogURL() -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let exportedURL {
            candidates.append(exportedURL.deletingLastPathComponent().appendingPathComponent("diagnostic.log"))
        }
        if rawLogPath != "—" {
            candidates.append(
                URL(fileURLWithPath: rawLogPath)
                    .deletingLastPathComponent()
                    .appendingPathComponent("diagnostic.log")
            )
        }
        for url in candidates where fm.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }


    /// F07-04 — reveal the exported file, never the evidence store.
    func revealLog() {
        guard let url = exportedURL, FileManager.default.fileExists(atPath: url.path) else {
            exportStatus = "打开文件夹失败：导出文件已不存在。"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        exportStatus = "已在 Finder 中定位：\(url.lastPathComponent)"
    }

    /// Poll a read-only projection of the growing raw log while recording.
    ///
    /// Only the bytes appended since the previous tick are read, so a 6.8 MB log
    /// is read once in total rather than once per tick, and the file I/O happens
    /// on the projector actor — never on the SwiftUI main thread.
    private func startStatsStream(path: String) {
        statsGeneration += 1
        let generation = statsGeneration
        statsTask?.cancel()
        let projector = LiveCaptureStats()
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                let snapshot = await projector.snapshot(forPath: path)
                guard let self,
                      self.statsGeneration == generation,
                      self.phase == .recording
                else { return }
                // Unreadable file => unknown, never a confident zero.
                self.byteCount = snapshot.isAvailable ? snapshot.byteCount : nil
                self.eventCount = snapshot.isAvailable ? snapshot.eventCount : nil
                self.namingRefreshTick += 1
                if self.namingRefreshTick % 3 == 0 {
                    self.refreshNamingPreview()
                }
                do {
                    try await Task.sleep(nanoseconds: 700_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func handleDirectory() -> String {
        FileManager.default.temporaryDirectory.path
    }
}

struct MainWindowView: View {
    @EnvironmentObject private var model: MonitorViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            leftWorkspace
                .frame(minWidth: 640, maxWidth: .infinity, alignment: .topLeading)

            Divider()

            ScrollView {
                settingsPanel
            }
            .frame(width: 430, alignment: .topLeading)
        }
        .padding(26)
        .frame(minWidth: 1100, idealWidth: 1200, minHeight: 720, idealHeight: 800)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Left: listening / capture workspace

    private var leftWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("RLM Raw MVP")
                    .font(.system(size: 26, weight: .semibold))
                Spacer()
                Text(model.phase.rawValue)
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
            }
            Text(model.detail)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("一键监听")
                                .font(.system(size: 20, weight: .semibold))
                            Text(listenerStatusText)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(listenerStatusColor)
                                .lineLimit(2)
                        }
                        Spacer()
                        Toggle("自动监听 Restore", isOn: Binding(
                            get: { model.autoMonitorEnabled },
                            set: { model.setAutoMonitorEnabled($0) }))
                            .toggleStyle(.switch)
                            .font(.system(size: 16))
                            .disabled(model.ownsAnActiveCapture || model.listenStarting)
                            .accessibilityIdentifier("auto-monitor-restore")
                    }
                    if let error = model.listenError {
                        Text(error)
                            .font(.system(size: 15))
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("listen-error")
                    }
                    Button(action: toggleListening) {
                        Text(listenButtonTitle)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.isListening ? .red : .accentColor)
                    .controlSize(.large)
                    .disabled(model.listenStarting || (!model.isListening && model.ownsAnActiveCapture))
                    .accessibilityIdentifier("toggle-listening")
                }
                .padding(10)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("当前采集")
                            .font(.system(size: 20, weight: .semibold))
                        Spacer()
                        Text(model.phase.rawValue)
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    }
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                        GridRow {
                            Text("采集位置").foregroundStyle(.secondary).font(.system(size: 16))
                            pathRow(model.rawLogPath, id: "current-path")
                        }
                        GridRow {
                            Text("相关事件").foregroundStyle(.secondary).font(.system(size: 16))
                            Text(eventCountText).font(.system(size: 16, design: .monospaced))
                        }
                        GridRow {
                            Text("日志大小").foregroundStyle(.secondary).font(.system(size: 16))
                            Text(byteCountText).font(.system(size: 16, design: .monospaced))
                        }
                    }
                    HStack(spacing: 10) {
                        Button(action: manualCaptureAction) {
                            Text(manualCaptureTitle)
                                .font(.system(size: 17, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(model.phase == .starting || model.phase == .stopping || model.phase == .saving || model.phase == .decisionPending)
                        .accessibilityIdentifier(model.phase == .recording ? "stop-capture" : "start-capture")
                    }
                    if model.phase == .decisionPending {
                        HStack(spacing: 10) {
                            Button("保存原始日志") { model.savePendingSession() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .frame(minHeight: 48)
                                .accessibilityIdentifier("save-capture")
                            Button("丢弃本次日志") { model.discardPendingSession() }
                                .controlSize(.large)
                                .frame(minHeight: 48)
                                .accessibilityIdentifier("discard-capture")
                        }
                    }
                    Text("手动采集是备用路径；不会触发任何设备写操作。")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("最近一次 Session")
                            .font(.system(size: 20, weight: .semibold))
                        Spacer()
                        Text(model.hasRecentSession ? (model.lastSessionIsPartial ? "历史 PARTIAL" : "历史 COMPLETE") : "无历史")
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundStyle(model.hasRecentSession && model.lastSessionIsPartial ? .orange : .secondary)
                    }
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                        GridRow {
                            Text("最近 Session").foregroundStyle(.secondary).font(.system(size: 16))
                            pathRow(model.hasRecentSession ? model.rawLogPath : "—", id: "recent-path")
                        }
                        GridRow {
                            Text("最近保存完整性").foregroundStyle(.secondary).font(.system(size: 16))
                            Text(model.hasRecentSession ? (model.lastSessionIsPartial ? "PARTIAL" : "COMPLETE") : "—")
                                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                .foregroundStyle(model.hasRecentSession && model.lastSessionIsPartial ? .orange : .secondary)
                        }
                    }
                    HStack(spacing: 10) {
                        Button("打开最近日志目录") { model.openRecentSessionDirectory() }
                            .controlSize(.large)
                            .accessibilityIdentifier("open-recent-session-directory")
                            .disabled(!model.hasRecentSession)
                        Button("复制原始日志文件") { model.copyRawLogFile() }
                            .controlSize(.large)
                            .accessibilityIdentifier("copy-raw-log")
                            .disabled(!model.hasRecentSession)
                        Spacer()
                    }
                }
                .padding(10)
            }

            HStack(spacing: 10) {
                Button("导出原始日志") { model.exportRawLog() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(minHeight: 48)
                    .disabled(model.rawExportBusy || !model.hasRecentSession || model.phase == .saving || model.phase == .recording || model.phase == .decisionPending)
                    .accessibilityIdentifier("export-raw-log")
                Button("打开导出目录") { model.openRawExportDirectory() }
                    .controlSize(.large)
                    .frame(minHeight: 48)
                    .accessibilityIdentifier("open-raw-log-directory")
                if model.rawExportBusy { ProgressView().controlSize(.small) }
                Spacer()
            }
            HStack(spacing: 10) {
                Button("导出本次证据包") { model.exportCurrentEvidencePackage() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(minHeight: 48)
                    .disabled(model.evidencePackageState == "GENERATING" || !model.hasRecentSession || model.phase == .saving || model.phase == .recording || model.phase == .decisionPending)
                    .accessibilityIdentifier("export-evidence-package")
                Button("另存证据包…") { model.exportCurrentEvidencePackage(saveAs: true) }
                    .controlSize(.large)
                    .frame(minHeight: 48)
                    .disabled(model.evidencePackageState == "GENERATING" || !model.hasRecentSession || model.phase == .saving || model.phase == .recording || model.phase == .decisionPending)
                    .accessibilityIdentifier("export-evidence-package-save-as")
                Button("打开证据包") { model.openEvidencePackageFolder() }
                    .controlSize(.large)
                    .frame(minHeight: 48)
                    .disabled(!model.evidencePackagePath.hasSuffix(".zip"))
                    .accessibilityIdentifier("open-evidence-package")
                Spacer()
            }
            Text(model.exportStatus)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(model.evidencePackageStatus)
                .font(.system(size: 15, weight: model.evidencePackageState == "FAILED" ? .semibold : .regular))
                .foregroundStyle(model.evidencePackageState == "FAILED" ? .orange : .secondary)
                .lineLimit(3)
                .accessibilityIdentifier("evidence-package-status")
            Spacer(minLength: 4)
        }
    }

    private func pathRow(_ path: String, id: String) -> some View {
        HStack(spacing: 6) {
            Text(path)
                .font(.system(size: 13, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(path)
                .accessibilityIdentifier(id)
            Button("复制") { model.copyPath(path) }
                .buttonStyle(.borderless)
            Button("显示") { model.revealPath(path) }
                .buttonStyle(.borderless)
        }
    }

    private var listenerStatusText: String {
        if model.listenStarting { return "正在启动监听…" }
        if let error = model.listenError { return error }
        if model.isListening {
            return model.monitorState == "WAITING_FOR_RESTORE" ? "监听中 · 等待 Restore" : "监听中 · \(model.monitorState)"
        }
        return "未监听 · 手动采集仍可用"
    }

    private var listenerStatusColor: Color {
        if model.listenError != nil { return .orange }
        return model.isListening ? .green : .secondary
    }

    private var listenButtonTitle: String {
        if model.listenStarting { return "正在启动…" }
        return model.isListening ? "停止监听" : "开始监听"
    }

    private func toggleListening() {
        if model.isListening {
            model.stopListening()
        } else {
            model.startListening()
        }
    }

    private var manualCaptureTitle: String {
        switch model.phase {
        case .recording: return "结束采集"
        case .starting: return "正在启动…"
        case .stopping: return "正在结束…"
        case .saving: return "正在保存…"
        default: return "手动开始采集"
        }
    }

    private func manualCaptureAction() {
        switch model.phase {
        case .recording: model.stopCaptureForDecision()
        case .idle, .saved, .discarded, .failed: model.start()
        default: break
        }
    }

    // MARK: - Right: settings

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设置")
                .font(.system(size: 24, weight: .semibold))
            Text("设置会立即持久化；不会修改已保存的历史原始日志。")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("原始日志自动保存目录")
                        .font(.system(size: 16, weight: .semibold))
                    HStack(spacing: 8) {
                        Text(model.rawSaveDirectory)
                            .font(.system(size: 13, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(model.rawSaveDirectory)
                            .accessibilityIdentifier("raw-save-directory")
                        Button("选择…") { model.chooseRawSaveDirectory() }
                            .controlSize(.large)
                            .accessibilityIdentifier("choose-raw-save-directory")
                    }
                    if let issue = model.rawSaveDirectoryIssue {
                        Text(issue).font(.system(size: 14)).foregroundStyle(.orange)
                            .accessibilityIdentifier("raw-save-directory-issue")
                    }
                    Button("打开保存目录") { model.openRawSaveDirectory() }
                        .controlSize(.large)
                }.padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("一键导出目录")
                        .font(.system(size: 16, weight: .semibold))
                    HStack(spacing: 8) {
                        Text(model.exportDirectory)
                            .font(.system(size: 13, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(model.exportDirectory)
                            .accessibilityIdentifier("export-directory")
                        Button("选择…") { model.chooseDestination() }
                            .controlSize(.large)
                            .accessibilityIdentifier("choose-export-directory")
                    }
                    if let issue = model.exportDirectoryIssue {
                        Text(issue).font(.system(size: 14)).foregroundStyle(.orange)
                            .accessibilityIdentifier("export-directory-issue")
                    }
                    Button("打开导出目录") { model.openRawExportDirectory() }
                        .controlSize(.large)
                }.padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("命名方式").font(.system(size: 16, weight: .semibold))
                    Picker("", selection: Binding(
                        get: { model.namingStyle },
                        set: { model.setNamingStyle($0) })) {
                        ForEach(SessionNamingStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.large)
                    .accessibilityIdentifier("session-naming-style")
                    if model.namingStyle == .custom {
                        TextField("自定义名称", text: Binding(
                            get: { model.baseName },
                            set: { model.setCustomSessionName($0) }))
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                            .accessibilityIdentifier("session-name")
                    }
                    Text("导出文件名预览")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text(model.rawExportPreview)
                        .font(.system(size: 13, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(model.rawExportPreview)
                        .accessibilityIdentifier("export-file-preview")
                }.padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("证据包设置")
                        .font(.system(size: 16, weight: .semibold))
                    Text("包内必选内容（不可取消）")
                        .font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("原始日志  restore.log（必选）")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text("ALWAYS")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("package-required-raw")
                    Text("同时必含：session.json、SHA256SUMS.txt")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Divider()
                    Text("证据包与原始日志目录、导出目录彼此独立；不自动生成。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text(model.packageDirectory)
                            .font(.system(size: 13, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(model.packageDirectory)
                            .accessibilityIdentifier("package-directory")
                        Button("选择…") { model.choosePackageDirectory() }
                            .controlSize(.large)
                            .accessibilityIdentifier("choose-package-directory")
                    }
                    if let issue = model.packageDirectoryIssue {
                        Text(issue).font(.system(size: 14)).foregroundStyle(.orange)
                            .accessibilityIdentifier("package-directory-issue")
                    }
                    TextField("证据包名称模板", text: Binding(
                        get: { model.packageTemplate },
                        set: { model.setPackageTemplate($0) }))
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .accessibilityIdentifier("package-template")
                    Text("默认名：RLM-Evidence-Session-{session_id_short}")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(model.packagePreview)
                        .font(.system(size: 13, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("package-preview")
                    Divider()
                    Text("可选附件（来源必须与本次 raw 一致）")
                        .font(.system(size: 14, weight: .semibold))
                    Toggle("Checkpoint 时间线  timeline.json", isOn: $model.packageIncludeTimeline)
                        .toggleStyle(.switch)
                        .font(.system(size: 14))
                        .accessibilityIdentifier("package-include-timeline")
                    Toggle("故障分析摘要  diagnostic_summary.md", isOn: $model.packageIncludeSummary)
                        .toggleStyle(.switch)
                        .font(.system(size: 14))
                        .accessibilityIdentifier("package-include-summary")
                    Toggle("固件更新器输出  updater_output.log（仅实际捕获）", isOn: $model.packageIncludeUpdaterOutput)
                        .toggleStyle(.switch)
                        .font(.system(size: 14))
                        .accessibilityIdentifier("package-include-updater")
                    Text("默认全选；缺失的附件会明确标记为未捕获/不可用，不影响基础 raw 包。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("打开证据包目录") { model.revealPath(model.packageDirectory) }
                        .controlSize(.large)
                        .accessibilityIdentifier("open-package-directory")
                }.padding(8)
            }

            if let notice = model.pathMigrationNotice {
                Text(notice)
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("path-migration-notice")
            }
            Spacer(minLength: 0)
            Text("原始日志只保存在本机；导出使用源 SHA-256 校验，防覆盖。")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A counter that has not been measured yet reads 统计中, not 0. Showing 0
    /// would claim "measured and empty", which is exactly the false statement the
    /// original bug produced while megabytes were being captured.
    private static func mb(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "— MB" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
    }

    private static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "— MB/s" }
        return String(format: "%.1f MB/s", bytesPerSecond / 1_048_576.0)
    }

    private var eventCountText: String {
        if model.analysisDeferredForCurrentSession { return "待分析" }
        return model.eventCount.map { "\($0)" } ?? "统计中"
    }

    private var byteCountText: String {
        model.byteCount.map { "\($0) B" } ?? "统计中"
    }

    private var buttonTitle: String {
        switch model.phase {
        case .idle, .saved, .discarded, .failed: return "开始采集"
        case .recording: return "结束采集"
        case .starting: return "正在启动…"
        case .stopping: return "正在停止…"
        case .decisionPending: return "等待保存或丢弃"
        case .saving: return "正在保存…"
        }
    }
}

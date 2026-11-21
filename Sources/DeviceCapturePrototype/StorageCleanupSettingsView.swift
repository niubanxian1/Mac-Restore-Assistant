import AppKit
import SwiftUI

struct StorageCleanupSettingsView: View {
    @EnvironmentObject private var logPreferences:
        LogWorkspacePreferences
    @EnvironmentObject private var rawPersistenceSettings:
        RestoreRawPersistenceSettings
    @EnvironmentObject private var restore:
        RestoreWorkspaceModel
    @State private var preview: RestoreStoragePreview?
    @State private var isScanning = false
    @State private var showConfirmation = false
    @State private var message = ""
    @State private var cleanupReport: RestoreLogCleanupReport?
    @State private var archives: [RestoreArchiveRecord] = []
    @State private var lockedArchiveIDs: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.t("Restore 原始日志存储"))
                    .font(.system(size: 18, weight: .semibold))
                Text(L10n.t(
                    "默认不长期保存完整原始日志。自动监控 Restore、自动保存原始日志和保存本次日志是三个独立选择。"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                GroupBox(L10n.t("保存设置")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(
                            L10n.t("自动保存 Restore 原始日志"),
                            isOn:
                                $rawPersistenceSettings
                                    .autoSaveRestoreRawLogs)
                            .accessibilityIdentifier(
                                "restore-auto-save-raw")
                        Text(L10n.t(
                            "新安装默认关闭。关闭时 Restore 照常执行，但结束后可能无法补导出本次完整原始日志。"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        directoryRow(
                            title: L10n.t("cfgutil 原始日志保存位置"),
                            path:
                                logPreferences.rawLogDirectory,
                            actionTitle: L10n.t("更改…")) {
                                chooseDirectory(
                                    current:
                                        logPreferences.rawLogDirectory
                                ) {
                                    logPreferences.rawLogDirectory = $0.path
                                }
                            }
                        directoryRow(
                            title: L10n.t("证据包保存位置"),
                            path:
                                logPreferences.evidencePackageDirectory,
                            actionTitle: L10n.t("更改…")) {
                                chooseDirectory(
                                    current:
                                        logPreferences
                                            .evidencePackageDirectory
                                ) {
                                    logPreferences.evidencePackageDirectory =
                                        $0.path
                                }
                            }

                        Text(L10n.t(
                            "RLM 系统原始日志（固定本机目录）"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        HStack {
                            Text(L10n.t("空间提醒"))
                            Spacer()
                            TextField(
                                "",
                                value:
                                    $rawPersistenceSettings
                                        .spaceWarningThresholdBytes,
                                format: .number)
                                .frame(width: 150)
                            Text(L10n.t("字节"))
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text(L10n.t("异常原始日志保留天数"))
                            Spacer()
                            Stepper(
                                "\(rawPersistenceSettings.retentionDays)",
                                value:
                                    $rawPersistenceSettings
                                        .retentionDays,
                                in: 1...365)
                        }
                        HStack {
                            Text(L10n.t("日志总预算"))
                            Spacer()
                            TextField(
                                "",
                                value:
                                    $rawPersistenceSettings
                                        .retentionBytes,
                                format: .number)
                                .frame(width: 150)
                            Text(L10n.t("字节"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                }

                GroupBox(L10n.t("空间统计与清理预览")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button(L10n.t("扫描日志占用")) {
                                scan()
                            }
                            .disabled(isScanning)
                            if isScanning {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Spacer()
                        }

                        if let preview {
                            Text(L10n.t(
                                "文件：\(preview.items.count) · 内容大小：\(sizeText(preview.logicalBytes)) · 磁盘占用：\(sizeText(preview.allocatedBytes)) · 可清理候选：\(preview.candidateCount)"))
                                .font(.system(size: 11))
                            ForEach(
                                RestoreLogCategory.allCases,
                                id: \.rawValue
                            ) { category in
                                let entries = preview.items.filter {
                                    $0.category == category
                                }
                                if !entries.isEmpty {
                                    HStack {
                                        Text(
                                            L10n.t(categoryTitle(category)))
                                        Spacer()
                                        Text(
                                            "\(entries.count) · \(sizeText(entries.reduce(0) { $0 + $1.identity.sizeBytes }))")
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.system(size: 11))
                                }
                            }
                            Button(L10n.t("预览并确认清理…")) {
                                showConfirmation = true
                            }
                            .disabled(preview.candidateCount == 0)
                        } else {
                            Text(L10n.t(
                                "尚未扫描。清理前必须查看分类预览并再次确认。"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        if !message.isEmpty {
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        if let cleanupReport {
                            Text(L10n.t(
                                "已删除：\(cleanupReport.deletedCount) · 跳过：\(cleanupReport.skippedCount) · 已删除文件分配量：\(sizeText(cleanupReport.allocatedBytesReleased))"))
                                .font(.system(size: 11))
                        }
                    }
                    .padding(8)
                }

                GroupBox(L10n.t("可信成功基准与手动锁定")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.t(
                            "每机型最多保留两份可信成功基准。手动锁定项占用名额，自动替换不会删除锁定项。"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        let eligible = archives.filter(\.baselineEligible)
                        if eligible.isEmpty {
                            Text(L10n.t("暂无有资格成为可信成功基准的完整归档。"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(
                                eligible.suffix(20),
                                id: \.archiveID
                            ) { archive in
                                Toggle(
                                    L10n.t(
                                        "\(archive.modelFamilyKey ?? "未知") · \(archive.outcome.rawValue) · \(archive.archiveID.prefix(8))"),
                                    isOn: Binding(
                                        get: {
                                            lockedArchiveIDs.contains(
                                                archive.archiveID)
                                        },
                                        set: { locked in
                                            toggleLock(
                                                archive.archiveID,
                                                locked: locked)
                                        }))
                                    .font(.system(size: 11))
                            }
                        }
                    }
                    .padding(8)
                }
            }
            .padding(18)
        }
        .onAppear {
            loadArchives()
            if preview == nil {
                scan()
            }
        }
        .confirmationDialog(
            L10n.t("确认清理日志"),
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.t("删除已列出的可清理候选"), role: .destructive) {
                performCleanup()
            }
            Button(L10n.t("取消"), role: .cancel) {}
        } message: {
            Text(L10n.t(
                "只处理当前预览中的可清理候选；锁定项、成功基准、证据包、未知来源、活动或状态已变化的文件会被跳过。不会删除 Configurator、IPSW 或客户数据。"))
        }
    }

    private func directoryRow(
        title: String,
        path: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.t(title))
                .font(.system(size: 11, weight: .medium))
            HStack {
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
    }

    private func scan() {
        guard !isScanning else { return }
        isScanning = true
        message = ""
        let roots = storageRoots
        let retentionDays =
            rawPersistenceSettings.retentionDays
        let activeAttemptIDs =
            currentActiveAttemptIDs
        Task {
            do {
                let value = try await RestoreLogStorageCatalog()
                    .preview(
                        roots: roots,
                        retentionDays: retentionDays,
                        activeAttemptIDs:
                            activeAttemptIDs)
                await MainActor.run {
                    preview = value
                    let warning =
                        rawPersistenceSettings
                            .spaceWarningThresholdBytes
                    let budget =
                        rawPersistenceSettings.retentionBytes
                    if !value.scanComplete {
                        message = L10n.t(
                            "日志空间未完整统计；权限失败、离线卷或不可读位置不会被当作可清理项。")
                    } else if value.allocatedBytes
                        > min(warning, budget) {
                        message = L10n.t(
                            "日志磁盘占用已超过空间提醒或总预算；请查看分类预览后手动确认清理。")
                    } else {
                        message = L10n.t(
                            "扫描完成；未执行任何删除。")
                    }
                    isScanning = false
                }
            } catch {
                await MainActor.run {
                    message = L10n.t(
                        "日志空间未完整统计：\(error.localizedDescription)")
                    isScanning = false
                }
            }
        }
    }

    private func performCleanup() {
        guard let preview else { return }
        guard restore.currentAttemptID == nil else {
            message = L10n.t(
                "有 Restore 正在准备或运行；结束当前任务前不会清理日志。")
            return
        }
        message = L10n.t("正在重新核验清理候选…")
        let roots = storageRoots
        let retentionDays =
            rawPersistenceSettings.retentionDays
        Task { @MainActor in
            do {
                let current = try await RestoreLogStorageCatalog()
                    .preview(
                        roots: roots,
                        retentionDays: retentionDays,
                        activeAttemptIDs:
                            currentActiveAttemptIDs)
                guard current.scanComplete else {
                    throw RestoreLogRetentionError
                        .verificationFailed(
                            "STORAGE_SCAN_INCOMPLETE")
                }
                let currentByKey = Dictionary(
                    uniqueKeysWithValues: current.items.map {
                        ("\($0.identity.device):\($0.identity.inode)", $0)
                    })
                let freshCandidates = preview.items.compactMap {
                    item -> RestoreStorageItem? in
                    guard !item.protected,
                          let fresh = currentByKey[
                            "\(item.identity.device):\(item.identity.inode)"],
                          !fresh.protected,
                          fresh.identity.device
                            == item.identity.device,
                          fresh.identity.inode
                            == item.identity.inode,
                          fresh.identity.modifiedNanoseconds
                            == item.identity.modifiedNanoseconds,
                          fresh.identity.changedNanoseconds
                            == item.identity.changedNanoseconds else {
                        return nil
                    }
                    return fresh
                }
                let freshPreview = RestoreStoragePreview(
                    items: freshCandidates,
                    managedRoots: current.managedRoots,
                    scanComplete: current.scanComplete,
                    issues: current.issues)
                let scanner = RestoreLogStorageCatalog()
                let report = try await RestoreLogCleanupService()
                    .execute(
                        preview: freshPreview,
                        confirmed: true,
                        protectionAtDeleteTime: { url in
                            do {
                                let activeIDs =
                                    await MainActor.run {
                                        currentActiveAttemptIDs
                                    }
                                let latest = try await scanner.preview(
                                    roots: roots,
                                    retentionDays: retentionDays,
                                    activeAttemptIDs:
                                        activeIDs)
                                guard latest.scanComplete else {
                                    return true
                                }
                                guard let match = latest.items.first(
                                    where: {
                                        $0.url.standardizedFileURL.path
                                            == url.standardizedFileURL.path
                                    }) else {
                                    return true
                                }
                                return match.protected
                            } catch {
                                return true
                            }
                        })
                await MainActor.run {
                    cleanupReport = report
                    message = L10n.t(
                        "清理已结束；未删除的候选保留在日志目录。")
                    isScanning = false
                    self.preview = nil
                }
                scan()
            } catch {
                await MainActor.run {
                    message = L10n.t(
                        "清理未完成：\(error.localizedDescription)")
                    isScanning = false
                }
            }
        }
    }

    private func loadArchives() {
        Task {
            let values =
                (try? await RestoreLogRetentionStore.shared.archives())
                ?? []
            let locks =
                (try? await RestoreLogRetentionStore.shared
                    .manuallyLockedArchiveIDs())
                ?? []
            await MainActor.run {
                archives = values
                lockedArchiveIDs = locks
            }
        }
    }

    private func toggleLock(
        _ archiveID: String,
        locked: Bool
    ) {
        Task {
            do {
                try await RestoreLogRetentionStore.shared
                    .setArchiveLocked(
                        archiveID: archiveID,
                        locked: locked)
                await MainActor.run {
                    if locked {
                        lockedArchiveIDs.insert(archiveID)
                    } else {
                        lockedArchiveIDs.remove(archiveID)
                    }
                    message = L10n.t(
                        locked ? "已手动锁定。" : "已取消手动锁定。")
                    preview = nil
                }
                scan()
            } catch {
                await MainActor.run {
                    message = L10n.t(
                        "锁定状态未保存：\(error.localizedDescription)")
                    loadArchives()
                }
            }
        }
    }

    private var storageRoots: RestoreManagedStorageRoots {
        let appSupport = AppSupportLocations.directory()
        return RestoreManagedStorageRoots(
            rawArchives: URL(
                fileURLWithPath:
                    logPreferences.rawLogDirectory,
                isDirectory: true),
            localStaging: appSupport.appendingPathComponent(
                "RestoreStaging",
                isDirectory: true),
            rlmSessions: AppSupportLocations.sessionRoot(),
            evidencePackages: URL(
                fileURLWithPath:
                    logPreferences.evidencePackageDirectory,
                isDirectory: true),
            history: appSupport.appendingPathComponent(
                "RestoreHistory",
                isDirectory: true))
    }

    private var currentActiveAttemptIDs: Set<UUID> {
        Set(
            [restore.currentAttemptID]
                .compactMap { $0 })
    }

    private func categoryTitle(
        _ category: RestoreLogCategory
    ) -> String {
        switch category {
        case .activeFinalizing:
            return "活动及收尾"
        case .manualLockedOrExported:
            return "手动锁定、导出或未知保护"
        case .trustedSuccessBaseline:
            return "可信成功基准"
        case .taskSummaryHistory:
            return "任务摘要与历史索引"
        case .unownedFailureOrUnknown:
            return "失败与异常日志"
        case .ordinaryRaw:
            return "普通 cfgutil 原始输出"
        case .cleanupEligibleRLMOrTemporary:
            return "可清理 RLM 会话与临时数据"
        }
    }

    private func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: .file)
    }

    private func chooseDirectory(
        current: String,
        assign: @escaping (URL) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(
            fileURLWithPath: current,
            isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            assign(url)
        }
    }
}

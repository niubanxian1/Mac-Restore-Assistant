import AppKit
import SwiftUI

struct FirmwarePreferencesSettingsView: View {
    @EnvironmentObject private var restore: RestoreWorkspaceModel
    @EnvironmentObject private var preferences: FirmwarePreferencesStore
    @EnvironmentObject private var appearance: WorkbenchAppearancePreferences
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    @State private var newModelKey = ""
    @State private var newModelEntryID: UUID?
    @AppStorage("ui.restoreCompletionSound") private var completionSoundEnabled = true

    private var palette: WorkbenchPalette {
        appearance.visualStyle.palette(for: colorScheme)
    }

    private var eligibleEntries: [FirmwareLibraryEntry] {
        restore.firmwareLibraryEntries.filter(\.isRestoreEligible)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Toggle(L10n.t("Restore 完成提示音"),
                       isOn: $completionSoundEnabled)
                    .font(.system(size: 10.5))
                    .accessibilityIdentifier("restore-completion-sound-toggle")
                librarySection
                globalDefaultSection
                modelDefaultsSection
                recentUsesSection
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            await restore.loadFirmwareLibrary()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("固件偏好"))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.primaryText)
            Text(L10n.t(
                "偏好只决定 Restore 准备时的候选固件，不会自动开始刷机，也不会绕过文件身份、BuildManifest 与兼容性复验。"))
                .font(.system(size: 10.5))
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var librarySection: some View {
        settingsGroup(L10n.t("本地固件库")) {
            HStack(spacing: 8) {
                Label(
                    "\(eligibleEntries.count) \(L10n.t("个可用固件"))",
                    systemImage: "shippingbox")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                if restore.isFirmwareDiscoveryActive {
                    ProgressView().controlSize(.mini)
                }
                Button(L10n.t("添加固件文件夹…")) {
                    chooseFirmwareDirectory()
                }
                .buttonStyle(.bordered)
                .disabled(restore.isRestoreTaskActive)
                Button(L10n.t("重新扫描")) {
                    restore.startFirmwareDiscovery()
                }
                .buttonStyle(.bordered)
                .disabled(restore.isRestoreTaskActive
                    || restore.isFirmwareDiscoveryActive)
            }
            Toggle(L10n.t("启动时自动扫描本机 IPSW"),
                   isOn: $restore.autoScanFirmwareOnLaunch)
                .font(.system(size: 10.5))
                .accessibilityIdentifier("firmware-auto-scan-toggle")
            if !restore.firmwareLibraryRoots.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("已添加的固件目录"))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(palette.tertiaryText)
                    ForEach(restore.firmwareLibraryRoots, id: \.self) { root in
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.system(size: 9.5))
                                .foregroundStyle(palette.tertiaryText)
                            Text(root.path)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(palette.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                Task { await restore.removeFirmwareDirectory(root) }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .disabled(restore.isRestoreTaskActive)
                            .accessibilityIdentifier(
                                "firmware-remove-root-\(root.lastPathComponent)")
                        }
                    }
                }
            }
            if !restore.firmwareLibraryMessage.isEmpty {
                Text(L10n.t(restore.firmwareLibraryMessage))
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let loadError = preferences.loadError {
                HStack(alignment: .top, spacing: 8) {
                    statusLine(
                        message: loadError,
                        state: .invalid)
                    if preferences.canResetUnreadablePreferences {
                        Spacer()
                        Button(L10n.t("备份并重置固件偏好…")) {
                            _ = preferences.resetAfterUnreadableFile()
                            restore.firmwarePreferencesDidChange()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var globalDefaultSection: some View {
        settingsGroup(L10n.t("全局默认固件")) {
            firmwareReferenceRow(
                reference: preferences.globalDefault,
                emptyText: L10n.t("尚未设置全局默认"),
                changeMenu: {
                    firmwarePickerMenu(
                        title: L10n.t("选择全局默认固件"),
                        selection: { id in
                            _ = restore.setGlobalFirmwareDefault(entryID: id)
                        })
                },
                clearAction: preferences.globalDefault == nil
                    ? nil
                    : { restore.clearGlobalFirmwareDefault() })
            Text(L10n.t(
                "全局默认只是跨机型首选。机型专属默认优先于全局默认；兼容性不足时仍需人工确认。"))
                .font(.system(size: 9.2))
                .foregroundStyle(palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modelDefaultsSection: some View {
        settingsGroup(L10n.t("机型默认固件")) {
            if preferences.modelDefaults.isEmpty {
                emptyRow(L10n.t("尚未配置机型默认固件"))
            } else {
                ForEach(
                    preferences.modelDefaults.keys.sorted(),
                    id: \.self
                ) { rawKey in
                    modelDefaultRow(rawKey: rawKey)
                    if rawKey != preferences.modelDefaults.keys.sorted().last {
                        Divider()
                            .overlay(palette.separator)
                    }
                }
            }

            Divider()
                .overlay(palette.separator)

            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.t("添加机型默认固件"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                HStack(spacing: 8) {
                    TextField(
                        L10n.t("机型标识符，例如 MacBookPro18,2"),
                        text: $newModelKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10.5, design: .monospaced))
                    firmwarePickerMenu(
                        title: newModelEntryID == nil
                            ? L10n.t("选择固件")
                            : L10n.t("已选择固件"),
                        selection: { newModelEntryID = $0 })
                    Button(L10n.t("添加")) {
                        guard let key = validatedModelKey,
                              let entryID = newModelEntryID,
                              restore.setModelFirmwareDefault(
                                entryID: entryID,
                                modelFamilyKey: key) else {
                            return
                        }
                        newModelKey = ""
                        newModelEntryID = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        preferences.persistenceIsBlocked
                            || validatedModelKey == nil
                            || newModelEntryID == nil)
                }
                if let targetKey = currentTargetModelKey {
                    Button(
                        L10n.t("使用当前设备机型：")
                            + targetKey.rawValue
                    ) {
                        newModelKey = targetKey.rawValue
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 9.5))
                }
                if !newModelKey.isEmpty && validatedModelKey == nil {
                    Text(L10n.t("该机型标识符不在内置可靠机型目录中。"))
                        .font(.system(size: 9.2))
                        .foregroundStyle(palette.warning)
                }
            }
        }
    }

    private var recentUsesSection: some View {
        settingsGroup(L10n.t("最近使用")) {
            if preferences.recentUsed.isEmpty {
                emptyRow(L10n.t("尚无实际启动过 Restore 的固件记录"))
            } else {
                ForEach(
                    Array(preferences.recentUsed.prefix(
                        FirmwarePreferencesStore.maximumRecentUses))
                ) { use in
                    HStack(alignment: .top, spacing: 9) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(use.reference.fileName)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(palette.primaryText)
                                .lineLimit(2)
                            Text("\(use.reference.versionLabel) · \(use.modelFamilyKey?.rawValue ?? L10n.t("机型未知"))")
                                .font(.system(
                                    size: 9,
                                    weight: .medium,
                                    design: .monospaced))
                                .foregroundStyle(palette.tertiaryText)
                            if let resolution =
                                    restore.resolveFirmwareReference(
                                        use.reference) {
                                statusLine(
                                    message: resolution.message,
                                    state: resolution.state)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(use.usedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 8.8))
                            .foregroundStyle(palette.tertiaryText)
                        Button(L10n.t("使用")) {
                            _ = restore.useFirmwareReference(use.reference)
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            restore.isRestoreTaskActive
                                || restore.resolveFirmwareReference(
                                    use.reference)?.isUsable != true)
                    }
                    if use.id != preferences.recentUsed.prefix(
                        FirmwarePreferencesStore.maximumRecentUses).last?.id {
                        Divider()
                            .overlay(palette.separator)
                    }
                }
            }
        }
    }

    private func modelDefaultRow(rawKey: String) -> some View {
        let key = ModelFamilyKey(rawValue: rawKey)
        let reference = key.flatMap {
            preferences.modelDefault(for: $0)
        }
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(rawKey)
                    .font(.system(
                        size: 10.8,
                        weight: .semibold,
                        design: .monospaced))
                    .foregroundStyle(palette.primaryText)
                Spacer()
                if let key {
                    firmwarePickerMenu(
                        title: L10n.t("更换"),
                        selection: { entryID in
                            _ = restore.setModelFirmwareDefault(
                                entryID: entryID,
                                modelFamilyKey: key)
                        })
                    Button(L10n.t("删除")) {
                        restore.clearModelFirmwareDefault(for: key)
                    }
                    .buttonStyle(.bordered)
                    .disabled(preferences.persistenceIsBlocked)
                }
            }
            if let reference {
                Text(reference.fileName)
                    .font(.system(size: 9.8))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(2)
                if let resolution =
                        restore.resolveFirmwareReference(reference) {
                    statusLine(
                        message: resolution.message,
                        state: resolution.state)
                }
            }
        }
    }

    private func firmwareReferenceRow(
        reference: FirmwareReference?,
        emptyText: String,
        @ViewBuilder changeMenu: () -> some View,
        clearAction: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    if let reference {
                        Text(reference.fileName)
                            .font(.system(size: 10.8, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                            .lineLimit(2)
                        Text(reference.versionLabel)
                            .font(.system(
                                size: 9.2,
                                weight: .medium,
                                design: .monospaced))
                            .foregroundStyle(palette.secondaryText)
                    } else {
                        Text(emptyText)
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.tertiaryText)
                    }
                }
                Spacer()
                changeMenu()
                if let clearAction {
                    Button(L10n.t("清除"), action: clearAction)
                        .buttonStyle(.bordered)
                        .disabled(preferences.persistenceIsBlocked)
                }
            }
            if let reference,
               let resolution =
                    restore.resolveFirmwareReference(reference) {
                statusLine(
                    message: resolution.message,
                    state: resolution.state)
            }
        }
    }

    private func firmwarePickerMenu(
        title: String,
        selection: @escaping (UUID) -> Void
    ) -> some View {
        Menu {
            if eligibleEntries.isEmpty {
                Text(L10n.t("没有通过验证的可用固件"))
            } else {
                ForEach(eligibleEntries) { entry in
                    Button(
                        "\(entry.url.lastPathComponent) · \(entry.metadata?.productVersion ?? L10n.t("未知版本"))"
                    ) {
                        selection(entry.id)
                    }
                }
            }
        } label: {
            Label(title, systemImage: "chevron.up.chevron.down")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(preferences.persistenceIsBlocked)
    }

    private func statusLine(
        message: String,
        state: FirmwareReferenceState
    ) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Circle()
                .fill(statusColor(state))
                .frame(width: 4, height: 4)
                .padding(.top, 4)
            Text(L10n.t(message))
                .font(.system(size: 9.1))
                .foregroundStyle(
                    state == .available
                        ? palette.secondaryText
                        : palette.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusColor(_ state: FirmwareReferenceState) -> Color {
        switch state {
        case .available: return palette.success
        case .missing, .modified, .ambiguous:
            return palette.warning
        case .invalid, .unreadable, .cloudNotDownloaded:
            return palette.danger
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(L10n.t(text))
            .font(.system(size: 10))
            .foregroundStyle(palette.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
    }

    private var validatedModelKey: ModelFamilyKey? {
        let normalized = newModelKey.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              TargetModelCatalog.identifier(from: normalized) != nil else {
            return nil
        }
        return ModelFamilyKey(rawValue: normalized)
    }

    private var currentTargetModelKey: ModelFamilyKey? {
        restore.selectedTarget.flatMap {
            ModelFamilyKey.resolve(identity: $0.firmwareIdentity)
        }
    }

    private func chooseFirmwareDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.t("选择")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await restore.scanFirmwareDirectory(url)
        }
    }

    private func settingsGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t(title))
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.35)
                .foregroundStyle(palette.secondaryText)
            VStack(alignment: .leading, spacing: 9) {
                content()
            }
            .padding(11)
            .background(
                palette.panel,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        contrast == .increased
                            ? palette.strongSeparator
                            : palette.separator,
                        lineWidth: contrast == .increased ? 1.1 : 0.65)
            }
        }
    }
}

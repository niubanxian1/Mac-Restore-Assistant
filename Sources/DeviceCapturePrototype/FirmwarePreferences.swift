import Combine
import CryptoKit
import Foundation

struct FirmwareReference: Codable, Equatable, Hashable, Identifiable, Sendable {
    let entryID: UUID
    let canonicalPath: String
    let fileName: String
    let fileIdentity: IPSWFileIdentity?
    let metadata: IPSWMetadata?
    let recordedAt: Date

    var id: UUID { entryID }

    init(
        entry: FirmwareLibraryEntry,
        recordedAt: Date = Date()
    ) {
        self.init(
            entryID: entry.id,
            url: entry.url,
            fileIdentity: entry.fileIdentity,
            metadata: entry.metadata,
            recordedAt: recordedAt)
    }

    init(
        entryID: UUID,
        url: URL,
        fileIdentity: IPSWFileIdentity?,
        metadata: IPSWMetadata?,
        recordedAt: Date = Date()
    ) {
        self.entryID = entryID
        canonicalPath = fileIdentity?.canonicalRealpath
            ?? url.resolvingSymlinksInPath().standardizedFileURL.path
        fileName = url.lastPathComponent
        self.fileIdentity = fileIdentity
        self.metadata = metadata
        self.recordedAt = recordedAt
    }

    var versionLabel: String {
        let version = metadata?.productVersion ?? "未知版本"
        let build = metadata?.productBuild ?? "未知 Build"
        return "\(version) · \(build)"
    }

    var cacheKey: String {
        guard let fileIdentity else {
            return ["\(entryID.uuidString)", canonicalPath].joined(separator: "|")
        }
        return [
            entryID.uuidString,
            fileIdentity.canonicalRealpath,
            String(fileIdentity.dev),
            String(fileIdentity.ino),
            String(fileIdentity.sizeBytes),
            String(fileIdentity.mtimeNs),
            String(fileIdentity.ctimeNs),
            fileIdentity.buildManifestSHA256
        ].joined(separator: "|")
    }

    static func syntheticEntryID(
        identity: IPSWFileIdentity
    ) -> UUID {
        let key = [
            identity.canonicalRealpath,
            String(identity.dev),
            String(identity.ino),
            String(identity.sizeBytes),
            String(identity.mtimeNs),
            String(identity.ctimeNs),
            identity.buildManifestSHA256
        ].joined(separator: "|")
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

struct FirmwareSelectionRecord: Codable, Equatable, Sendable {
    let reference: FirmwareReference
    let modelFamilyKey: ModelFamilyKey?
    let selectedAt: Date
}

struct FirmwareUseRecord: Codable, Equatable, Identifiable, Sendable {
    let reference: FirmwareReference
    let modelFamilyKey: ModelFamilyKey?
    let usedAt: Date

    var id: String {
        [
            reference.entryID.uuidString,
            modelFamilyKey?.rawValue ?? "UNKNOWN"
        ].joined(separator: "|")
    }
}

enum FirmwareReferenceState: String, Codable, Equatable, Sendable {
    case available
    case missing
    case modified
    case ambiguous
    case invalid
    case unreadable
    case cloudNotDownloaded
}

struct FirmwareReferenceResolution: Equatable, Sendable {
    let reference: FirmwareReference
    let entry: FirmwareLibraryEntry?
    let state: FirmwareReferenceState
    let message: String

    var isUsable: Bool {
        state == .available && entry?.isRestoreEligible == true
    }
}

enum FirmwareReferenceResolver {
    static func resolve(
        _ reference: FirmwareReference,
        in entries: [FirmwareLibraryEntry]
    ) -> FirmwareReferenceResolution {
        let exactEntry = entries.first {
            $0.id == reference.entryID
        }
        let identityMatches = entries.filter {
            reference.fileIdentity != nil
                && $0.fileIdentity == reference.fileIdentity
        }
        let pathMatches = entries.filter {
            $0.url.resolvingSymlinksInPath().standardizedFileURL.path
                == reference.canonicalPath
                || $0.fileIdentity?.canonicalRealpath == reference.canonicalPath
        }

        let entry: FirmwareLibraryEntry?
        if let exactEntry {
            entry = exactEntry
        } else if identityMatches.count == 1 {
            entry = identityMatches[0]
        } else if identityMatches.count > 1 {
            return FirmwareReferenceResolution(
                reference: reference,
                entry: nil,
                state: .ambiguous,
                message: "固件库中有多个条目具有相同文件身份，无法确认引用。")
        } else if pathMatches.count == 1 {
            entry = pathMatches[0]
        } else if pathMatches.count > 1 {
            return FirmwareReferenceResolution(
                reference: reference,
                entry: nil,
                state: .ambiguous,
                message: "固件库中有多个条目对应同一路径，无法确认引用。")
        } else {
            return FirmwareReferenceResolution(
                reference: reference,
                entry: nil,
                state: .missing,
                message: "固件文件已移动、删除，或当前固件库尚未扫描到。")
        }

        guard let entry else {
            return FirmwareReferenceResolution(
                reference: reference,
                entry: nil,
                state: .missing,
                message: "固件文件已移动、删除，或当前固件库尚未扫描到。")
        }
        if let accessState = entry.accessState {
            switch accessState {
            case .cloudNotDownloaded:
                return FirmwareReferenceResolution(
                    reference: reference,
                    entry: entry,
                    state: .cloudNotDownloaded,
                    message: "该固件是 iCloud 占位文件，请先下载到本机。")
            case .unreadable:
                return FirmwareReferenceResolution(
                    reference: reference,
                    entry: entry,
                    state: .unreadable,
                    message: entry.errorMessage
                        ?? "该固件当前无法读取。")
            }
        }
        if entry.state == .missing {
            return FirmwareReferenceResolution(
                reference: reference,
                entry: entry,
                state: .missing,
                message: "固件文件已移动或删除。")
        }
        if entry.state == .ambiguous {
            return FirmwareReferenceResolution(
                reference: reference,
                entry: entry,
                state: .ambiguous,
                message: entry.errorMessage
                    ?? "固件文件存在多个重定位候选，需人工确认。")
        }
        if let expected = reference.fileIdentity,
           entry.fileIdentity != expected {
            return FirmwareReferenceResolution(
                reference: reference,
                entry: entry,
                state: .modified,
                message: "固件文件身份已变化，原偏好不会自动替换为另一份文件。")
        }
        if entry.state != .available
            || entry.validity != .valid
            || entry.fileIdentity == nil {
            return FirmwareReferenceResolution(
                reference: reference,
                entry: entry,
                state: .invalid,
                message: entry.errorMessage
                    ?? "固件已损坏或缺少有效 BuildManifest。")
        }
        return FirmwareReferenceResolution(
            reference: reference,
            entry: entry,
            state: .available,
            message: "固件文件身份与固件库记录一致。")
    }
}

@MainActor
final class FirmwarePreferencesStore: ObservableObject {
    private struct Document: Codable {
        var schemaVersion: Int
        var globalDefault: FirmwareReference?
        var modelDefaults: [String: FirmwareReference]
        var lastSelected: FirmwareSelectionRecord?
        var lastUsed: FirmwareUseRecord?
        var recentUsed: [FirmwareUseRecord]
    }

    static let schemaVersion = 1
    static let maximumRecentUses = 12

    @Published private(set) var globalDefault: FirmwareReference?
    @Published private(set) var modelDefaults: [String: FirmwareReference]
    @Published private(set) var lastSelected: FirmwareSelectionRecord?
    @Published private(set) var lastUsed: FirmwareUseRecord?
    @Published private(set) var recentUsed: [FirmwareUseRecord]
    @Published private(set) var loadError: String?

    let fileURL: URL
    private let fileManager: FileManager
    private var persistenceBlocked: Bool

    var persistenceIsBlocked: Bool { persistenceBlocked }
    var canResetUnreadablePreferences: Bool { persistenceBlocked }

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL
            ?? AppSupportLocations.directory()
                .appendingPathComponent(
                    "FirmwarePreferences",
                    isDirectory: true)
                .appendingPathComponent("preferences-v1.json")

        if let data = try? Data(contentsOf: self.fileURL),
           let document = try? Self.decoder.decode(
                Document.self,
                from: data),
           document.schemaVersion == Self.schemaVersion {
            globalDefault = document.globalDefault
            var normalizedModelDefaults: [String: FirmwareReference] = [:]
            var hasSemanticDamage = false
            for (rawKey, reference) in document.modelDefaults {
                guard TargetModelCatalog.identifier(from: rawKey) != nil,
                      let normalizedKey = ModelFamilyKey(
                        rawValue: rawKey)?.rawValue else {
                    hasSemanticDamage = true
                    continue
                }
                if let existing = normalizedModelDefaults[normalizedKey],
                   existing != reference {
                    hasSemanticDamage = true
                } else {
                    normalizedModelDefaults[normalizedKey] = reference
                }
            }
            modelDefaults = hasSemanticDamage
                ? [:]
                : normalizedModelDefaults
            lastSelected = document.lastSelected
            lastUsed = document.lastUsed
            recentUsed = Self.boundedRecentUses(document.recentUsed)
            loadError = hasSemanticDamage
                ? "固件偏好包含无效机型键；已保留原文件，等待备份重置。"
                : nil
            persistenceBlocked = hasSemanticDamage
        } else if fileManager.fileExists(atPath: self.fileURL.path) {
            globalDefault = nil
            modelDefaults = [:]
            lastSelected = nil
            lastUsed = nil
            recentUsed = []
            loadError = "固件偏好文件无法读取；已保留原文件，等待用户重新设置。"
            persistenceBlocked = true
        } else {
            globalDefault = nil
            modelDefaults = [:]
            lastSelected = nil
            lastUsed = nil
            recentUsed = []
            loadError = nil
            persistenceBlocked = false
        }
    }

    @discardableResult
    func setGlobalDefault(_ reference: FirmwareReference) -> Bool {
        guard !persistenceBlocked else { return false }
        let previous = globalDefault
        globalDefault = reference
        guard persist() else {
            globalDefault = previous
            return false
        }
        return true
    }

    @discardableResult
    func clearGlobalDefault() -> Bool {
        guard !persistenceBlocked else { return false }
        let previous = globalDefault
        globalDefault = nil
        guard persist() else {
            globalDefault = previous
            return false
        }
        return true
    }

    @discardableResult
    func setModelDefault(
        _ reference: FirmwareReference,
        for modelFamilyKey: ModelFamilyKey
    ) -> Bool {
        guard !persistenceBlocked else { return false }
        guard TargetModelCatalog.identifier(
            from: modelFamilyKey.rawValue) != nil else {
            loadError = "机型键不在内置可靠机型目录中，未保存。"
            return false
        }
        let previous = modelDefaults
        modelDefaults[modelFamilyKey.rawValue] = reference
        guard persist() else {
            modelDefaults = previous
            return false
        }
        return true
    }

    @discardableResult
    func clearModelDefault(for modelFamilyKey: ModelFamilyKey) -> Bool {
        guard !persistenceBlocked else { return false }
        let previous = modelDefaults
        modelDefaults.removeValue(forKey: modelFamilyKey.rawValue)
        guard persist() else {
            modelDefaults = previous
            return false
        }
        return true
    }

    /// 内容身份未变、仅 ctime 变化时，刷新偏好中的引用身份。
    /// 不改变内容校验规则：inode、size、mtime、BuildManifest 摘要任一变化都不更新。
    @discardableResult
    func reconcileStaleIdentitiesIfContentUnchanged(
        in entries: [FirmwareLibraryEntry]
    ) -> Bool {
        guard !persistenceBlocked else { return false }
        func contentEquivalent(_ a: IPSWFileIdentity?, _ b: IPSWFileIdentity?) -> Bool {
            guard let a, let b else { return false }
            return a.dev == b.dev
                && a.ino == b.ino
                && a.sizeBytes == b.sizeBytes
                && a.mtimeNs == b.mtimeNs
                && a.buildManifestSHA256 == b.buildManifestSHA256
                && a.canonicalRealpath == b.canonicalRealpath
        }
        var changed = false
        if let ref = globalDefault,
           let entry = entries.first(where: { $0.id == ref.entryID }),
           ref.fileIdentity != entry.fileIdentity,
           contentEquivalent(ref.fileIdentity, entry.fileIdentity) {
            globalDefault = FirmwareReference(entry: entry)
            changed = true
        }
        for (key, ref) in modelDefaults {
            guard let entry = entries.first(where: { $0.id == ref.entryID }),
                  ref.fileIdentity != entry.fileIdentity,
                  contentEquivalent(ref.fileIdentity, entry.fileIdentity) else {
                continue
            }
            modelDefaults[key] = FirmwareReference(entry: entry)
            changed = true
        }
        if changed { _ = persist() }
        return changed
    }

    func modelDefault(for modelFamilyKey: ModelFamilyKey) -> FirmwareReference? {
        modelDefaults[modelFamilyKey.rawValue]
    }

    @discardableResult
    func recordSelection(
        _ reference: FirmwareReference,
        modelFamilyKey: ModelFamilyKey?,
        at date: Date = Date()
    ) -> Bool {
        guard !persistenceBlocked else { return false }
        let previous = lastSelected
        lastSelected = FirmwareSelectionRecord(
            reference: reference,
            modelFamilyKey: modelFamilyKey,
            selectedAt: date)
        guard persist() else {
            lastSelected = previous
            return false
        }
        return true
    }

    @discardableResult
    func recordUsed(
        _ reference: FirmwareReference,
        modelFamilyKey: ModelFamilyKey?,
        at date: Date = Date()
    ) -> Bool {
        guard !persistenceBlocked else { return false }
        let previousLastUsed = lastUsed
        let previousRecent = recentUsed
        let record = FirmwareUseRecord(
            reference: reference,
            modelFamilyKey: modelFamilyKey,
            usedAt: date)
        lastUsed = record
        recentUsed.removeAll {
            $0.reference.entryID == record.reference.entryID
                && $0.modelFamilyKey == record.modelFamilyKey
        }
        recentUsed.insert(record, at: 0)
        recentUsed = Array(recentUsed.prefix(Self.maximumRecentUses))
        guard persist() else {
            lastUsed = previousLastUsed
            recentUsed = previousRecent
            return false
        }
        return true
    }

    func recentUses(
        matching modelFamilyKey: ModelFamilyKey?
    ) -> [FirmwareUseRecord] {
        guard let modelFamilyKey else { return [] }
        return recentUsed.filter {
            $0.modelFamilyKey == modelFamilyKey
        }
    }

    func resolve(
        _ reference: FirmwareReference?,
        in entries: [FirmwareLibraryEntry]
    ) -> FirmwareReferenceResolution? {
        guard let reference else { return nil }
        return FirmwareReferenceResolver.resolve(reference, in: entries)
    }

    @discardableResult
    func resetAfterUnreadableFile() -> Bool {
        guard persistenceBlocked else { return true }
        let directory = fileURL.deletingLastPathComponent()
        let previousGlobalDefault = globalDefault
        let previousModelDefaults = modelDefaults
        let previousLastSelected = lastSelected
        let previousLastUsed = lastUsed
        let previousRecentUsed = recentUsed
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: fileURL.path) {
                let backup = directory.appendingPathComponent(
                    "preferences-v1-unreadable-\(UUID().uuidString).json")
                try fileManager.copyItem(at: fileURL, to: backup)
            }
            globalDefault = nil
            modelDefaults = [:]
            lastSelected = nil
            lastUsed = nil
            recentUsed = []
            persistenceBlocked = false
            loadError = nil
            guard persist() else {
                let saveError = loadError ?? "固件偏好重置写入失败。"
                globalDefault = previousGlobalDefault
                modelDefaults = previousModelDefaults
                lastSelected = previousLastSelected
                lastUsed = previousLastUsed
                recentUsed = previousRecentUsed
                persistenceBlocked = true
                loadError =
                    "备份并重置固件偏好失败；已保留原文件。"
                    + saveError
                return false
            }
            return true
        } catch {
            globalDefault = previousGlobalDefault
            modelDefaults = previousModelDefaults
            lastSelected = previousLastSelected
            lastUsed = previousLastUsed
            recentUsed = previousRecentUsed
            persistenceBlocked = true
            loadError =
                "损坏的固件偏好文件无法备份，未执行重置：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    private func persist() -> Bool {
        guard !persistenceBlocked else { return false }
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true)
            let document = Document(
                schemaVersion: Self.schemaVersion,
                globalDefault: globalDefault,
                modelDefaults: modelDefaults,
                lastSelected: lastSelected,
                lastUsed: lastUsed,
                recentUsed: recentUsed)
            let data = try Self.encoder.encode(document)
            try data.write(to: fileURL, options: .atomic)
            loadError = nil
            return true
        } catch {
            loadError = "固件偏好未能保存：\(error.localizedDescription)"
            return false
        }
    }

    private static func boundedRecentUses(
        _ records: [FirmwareUseRecord]
    ) -> [FirmwareUseRecord] {
        var seen = Set<String>()
        return records
            .sorted { $0.usedAt > $1.usedAt }
            .filter { seen.insert($0.id).inserted }
            .prefix(maximumRecentUses)
            .map { $0 }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        JSONDecoder()
    }
}

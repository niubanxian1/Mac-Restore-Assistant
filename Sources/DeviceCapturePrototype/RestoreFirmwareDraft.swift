import Foundation

/// P2-B：第二台设备的独立固件草稿。
///
/// 草稿只描述"准备"，不是执行快照：
/// - 它不会成为 `PendingRestoreAttempt`，不会获取租约、不会启动 cfgutil。
/// - 它与 `stablePortKey` + 设备连接代际 + 固件文件身份绑定。
/// - 设备身份不可确认、同口换机、重新枚举或文件被替换时，状态会降级，
///   由界面明确提示"不可直接用于当前设备"，而不是静默沿用。
enum RestoreFirmwareDraftInvalidation: String, Equatable, Codable, Sendable {
    case deviceChanged
    case deviceMissing
    case connectionChanged
    case fileChanged
    case firmwareInvalid
    case compatibilityUnverified
    case ownershipAmbiguous
}

enum RestoreFirmwareDraftStatus: Equatable, Sendable {
    case ready
    case requiresReverification
    case unusable(RestoreFirmwareDraftInvalidation)

    var isReadyForHandoff: Bool {
        if case .ready = self { return true }
        return false
    }

    var invalidation: RestoreFirmwareDraftInvalidation? {
        if case .unusable(let reason) = self { return reason }
        return nil
    }
}

struct RestoreFirmwareDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    let stablePortKey: String
    let deviceECID: String
    var connectionGeneration: UInt64
    let locationID: String
    let deviceDisplayName: String
    let ipswURL: URL
    let libraryEntryID: UUID?
    let fileIdentity: IPSWFileIdentity?
    let productVersion: String?
    let productBuild: String?
    let validity: IPSWFileValidity
    let compatibility: HardwareCompatibility
    let createdAt: Date
    var updatedAt: Date
    var invalidation: RestoreFirmwareDraftInvalidation?

    var firmwareDisplayName: String {
        ipswURL.lastPathComponent
    }

    var versionDisplay: String {
        let version = productVersion ?? "版本未知"
        let build = productBuild.map { " (\($0))" } ?? ""
        return version + build
    }

    /// 只读状态判定：既不修改草稿，也不触发任何设备或进程行为。
    static func status(
        for draft: RestoreFirmwareDraft,
        target: RestoreTarget?,
        fileUnchanged: Bool
    ) -> RestoreFirmwareDraftStatus {
        guard let target else {
            return .unusable(.deviceMissing)
        }
        guard !draft.deviceECID.isEmpty,
              draft.deviceECID.lowercased() == target.canonicalHex.lowercased() else {
            return .unusable(.deviceChanged)
        }
        if let invalidation = draft.invalidation {
            return .unusable(invalidation)
        }
        if draft.connectionGeneration != target.connectionGeneration {
            return .requiresReverification
        }
        guard draft.validity == .valid else {
            return .unusable(.firmwareInvalid)
        }
        switch draft.compatibility.status {
        case .incompatible:
            return .unusable(.firmwareInvalid)
        case .unverified:
            // 仅 ProductType 匹配、缺少 BoardID/ChipID 时允许人工确认后继续；
            // 明确不兼容仍由上面的 incompatible 分支拒绝。
            break
        case .compatible:
            break
        }
        // 没有文件身份就没有可核验的同一性；不冒充 ready。
        guard draft.fileIdentity != nil else {
            return .requiresReverification
        }
        guard fileUnchanged else {
            return .unusable(.fileChanged)
        }
        return .ready
    }

    /// 廉价文件同一性检查：inode、大小、mtime（秒）与创建时记录一致。
    /// 不重新哈希整份 IPSW；真正的启动前验证仍由既有启动流程完成。
    func fileUnchangedOnDisk() -> Bool {
        guard let identity = fileIdentity else { return false }
        guard let attributes = try? FileManager.default
            .attributesOfItem(atPath: ipswURL.path) else {
            return false
        }
        let size = (attributes[.size] as? NSNumber)?.uint64Value
        guard size == identity.sizeBytes else { return false }
        if let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
           inode != identity.ino {
            return false
        }
        if let mtime = attributes[.modificationDate] as? Date {
            let seconds = Int64(mtime.timeIntervalSince1970)
            if seconds != identity.mtimeNs / 1_000_000_000 {
                return false
            }
        }
        return true
    }
}

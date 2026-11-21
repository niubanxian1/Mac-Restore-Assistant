import Foundation

enum DeviceIdentityProvenance: String, Codable, Equatable, Hashable, Sendable {
    case liveConfirmed
    case portHistoryAssisted
    case unverifiedGeneric
}

struct FirmwareTargetIdentity: Codable, Equatable, Hashable, Sendable {
    let productType: String?
    let machineIdentifier: String?
    let deviceClass: String?
    let boardID: Int?
    let chipID: Int?
    let provenance: DeviceIdentityProvenance
}

struct ModelFamilyKey: Codable, Equatable, Hashable, Sendable {
    let rawValue: String

    init?(rawValue: String) {
        let normalized = Self.normalize(rawValue)
        guard !normalized.isEmpty else { return nil }
        self.rawValue = normalized
    }

    static func resolve(identity: FirmwareTargetIdentity) -> ModelFamilyKey? {
        guard identity.provenance == .liveConfirmed else { return nil }
        if let productType = identity.productType,
           TargetModelCatalog.identifier(from: productType) != nil,
           let key = ModelFamilyKey(rawValue: productType) {
            return key
        }
        guard let machineIdentifier = identity.machineIdentifier,
              TargetModelCatalog.identifier(from: machineIdentifier) != nil else {
            return nil
        }
        return ModelFamilyKey(rawValue: machineIdentifier)
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }
}

struct HardwareBindingKey: Codable, Equatable, Hashable, Sendable {
    let productType: String?
    let deviceClass: String?
    let boardID: Int?
    let chipID: Int?

    static func resolve(identity: FirmwareTargetIdentity) -> HardwareBindingKey {
        HardwareBindingKey(
            productType: normalized(identity.productType),
            deviceClass: normalized(identity.deviceClass),
            boardID: identity.boardID,
            chipID: identity.chipID)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized.uppercased()
    }
}

enum FirmwareSelectionSource: String, Codable, Equatable, Sendable {
    case none
    case systemRecommended
    case userManualSelected
}

enum FirmwareRecognitionSource: String, Codable, Equatable, Sendable {
    case recentUsedCompatible
    case modelDefault
    case globalDefault
    case lastSelectedCompatible
    case unknownIdentityGlobalDefault
    case userManualSelection
}

enum FirmwareRecognitionTrust: String, Codable, Equatable, Sendable {
    case recentUserUsage
    case explicitUserDefault
    case previousUserSelection
    case manualUserSelection
}

enum FirmwareRecommendationTier: Int, Codable, Equatable, Sendable {
    case tier1RecentUsedCompatible = 1
    case tier2ModelDefault = 2
    case tier3GlobalDefault = 3
    case tier4LastSelectedCompatible = 4
}

enum FirmwareUsageRecordSource: String, Codable, Equatable, Sendable {
    case nativeV1703Verified
    case bootstrapCandidate1702
    case unverified
}

struct FirmwareUsageRecord: Equatable, Sendable {
    let candidateID: UUID
    let modelFamilyKey: ModelFamilyKey
    let outcome: RestoreOutcome
    let source: FirmwareUsageRecordSource
    let verificationComplete: Bool
    let occurredAt: Date
}

struct FirmwareRecommendationCandidate: Equatable, Sendable {
    let entry: FirmwareLibraryEntry
    let compatibility: HardwareCompatibility

    var id: UUID { entry.id }
    var metadata: IPSWMetadata? { entry.metadata }
    var validity: IPSWFileValidity { entry.validity }
}

struct FirmwareRecommendationRequest: Equatable, Sendable {
    let target: FirmwareTargetIdentity
    let candidates: [FirmwareRecommendationCandidate]
    let recentSuccessfulUses: [FirmwareUsageRecord]
    let recentUsedCandidateIDs: [UUID]
    let lastSelectedCandidateID: UUID?
    let modelDefaultCandidateID: UUID?
    let modelDefaultIsConfigured: Bool
    let globalDefaultCandidateID: UUID?
    let globalDefaultIsConfigured: Bool
    let manualCandidateID: UUID?

    init(
        target: FirmwareTargetIdentity,
        candidates: [FirmwareRecommendationCandidate],
        recentSuccessfulUses: [FirmwareUsageRecord] = [],
        recentUsedCandidateIDs: [UUID] = [],
        lastSelectedCandidateID: UUID? = nil,
        modelDefaultCandidateID: UUID? = nil,
        modelDefaultIsConfigured: Bool? = nil,
        globalDefaultCandidateID: UUID? = nil,
        globalDefaultIsConfigured: Bool? = nil,
        manualCandidateID: UUID? = nil
    ) {
        self.target = target
        self.candidates = candidates
        self.recentSuccessfulUses = recentSuccessfulUses
        self.recentUsedCandidateIDs = recentUsedCandidateIDs
        self.lastSelectedCandidateID = lastSelectedCandidateID
        self.modelDefaultCandidateID = modelDefaultCandidateID
        self.modelDefaultIsConfigured =
            modelDefaultIsConfigured
                ?? (modelDefaultCandidateID != nil)
        self.globalDefaultCandidateID = globalDefaultCandidateID
        self.globalDefaultIsConfigured =
            globalDefaultIsConfigured
                ?? (globalDefaultCandidateID != nil)
        self.manualCandidateID = manualCandidateID
    }
}

struct FirmwareRecommendation: Equatable, Sendable {
    let candidate: FirmwareRecommendationCandidate
    let tier: FirmwareRecommendationTier?
    let source: FirmwareRecognitionSource
    let trust: FirmwareRecognitionTrust
    let selectionSource: FirmwareSelectionSource
    let modelFamilyKey: ModelFamilyKey?
    let hardwareBindingKey: HardwareBindingKey
    let requiresManualConfirmation: Bool
    let basis: String
}

struct FirmwareRecommendationEngine: Sendable {
    func recommend(
        _ request: FirmwareRecommendationRequest
    ) -> FirmwareRecommendation? {
        if let manualID = request.manualCandidateID,
           let manual = request.candidates.first(where: { $0.id == manualID }) {
            return FirmwareRecommendation(
                candidate: manual,
                tier: nil,
                source: .userManualSelection,
                trust: .manualUserSelection,
                selectionSource: .userManualSelected,
                modelFamilyKey: ModelFamilyKey.resolve(identity: request.target),
                hardwareBindingKey: HardwareBindingKey.resolve(identity: request.target),
                requiresManualConfirmation: true,
                basis: "用户手动选择的 IPSW；后台刷新不得覆盖。")
        }

        let usable = request.candidates.filter {
            $0.entry.state == .available
                && $0.validity == .valid
                && $0.compatibility.status != .incompatible
        }
        let modelFamilyKey = ModelFamilyKey.resolve(identity: request.target)

        guard let modelFamilyKey else {
            guard let globalID = request.globalDefaultCandidateID,
                  let global = usable.first(where: { $0.id == globalID }) else {
                return nil
            }
            return recommendation(
                candidate: global,
                tier: .tier3GlobalDefault,
                source: .unknownIdentityGlobalDefault,
                trust: .explicitUserDefault,
                selectionSource: .systemRecommended,
                modelFamilyKey: nil,
                target: request.target,
                requiresManualConfirmation: true,
                basis: "机型身份未知；仅预选用户显式设置的全局默认固件，需人工确认。")
        }

        let modelDefaultIsConfigured =
            request.modelDefaultIsConfigured
                || request.modelDefaultCandidateID != nil
        if modelDefaultIsConfigured {
            guard let modelDefaultID = request.modelDefaultCandidateID,
                  let candidate = usable.first(where: {
                      $0.id == modelDefaultID
                  }) else {
                return nil
            }
            return recommendation(
                candidate: candidate,
                tier: .tier2ModelDefault,
                source: .modelDefault,
                trust: .explicitUserDefault,
                selectionSource: .systemRecommended,
                modelFamilyKey: modelFamilyKey,
                target: request.target,
                requiresManualConfirmation: candidate.compatibility.status != .compatible,
                basis: "同一机型显式设置的机型默认固件。")
        }

        let globalDefaultIsConfigured =
            request.globalDefaultIsConfigured
                || request.globalDefaultCandidateID != nil
        if globalDefaultIsConfigured {
            guard let globalID = request.globalDefaultCandidateID,
                  let candidate = usable.first(where: {
                      $0.id == globalID
                  }) else {
                return nil
            }
            return recommendation(
                candidate: candidate,
                tier: .tier3GlobalDefault,
                source: .globalDefault,
                trust: .explicitUserDefault,
                selectionSource: .systemRecommended,
                modelFamilyKey: modelFamilyKey,
                target: request.target,
                requiresManualConfirmation: candidate.compatibility.status != .compatible,
                basis: "用户显式设置的全局默认固件。")
        }

        if let recent = request.recentUsedCandidateIDs.compactMap({
            id in usable.first {
                $0.id == id && $0.compatibility.status == .compatible
            }
        }).first {
            return recommendation(
                candidate: recent,
                tier: .tier1RecentUsedCompatible,
                source: .recentUsedCompatible,
                trust: .recentUserUsage,
                selectionSource: .systemRecommended,
                modelFamilyKey: modelFamilyKey,
                target: request.target,
                requiresManualConfirmation: false,
                basis: "同一机型最近实际启动过 Restore 的兼容固件；仅作为本次准备候选。")
        }

        if let lastSelectedID = request.lastSelectedCandidateID,
           let lastSelected = usable.first(where: {
               $0.id == lastSelectedID
                   && $0.compatibility.status == .compatible
           }) {
            return recommendation(
                candidate: lastSelected,
                tier: .tier4LastSelectedCompatible,
                source: .lastSelectedCompatible,
                trust: .previousUserSelection,
                selectionSource: .systemRecommended,
                modelFamilyKey: modelFamilyKey,
                target: request.target,
                requiresManualConfirmation: false,
                basis: "恢复上次手动选择且与当前机型兼容的固件；未配置更高优先级默认。")
        }

        return nil
    }

    static func sortCandidatesByVersion(
        _ candidates: [FirmwareRecommendationCandidate]
    ) -> [FirmwareRecommendationCandidate] {
        candidates.sorted {
            compareCandidateVersion($0, $1) == .orderedDescending
        }
    }

    static func sortTierFourCandidates(
        _ candidates: [FirmwareRecommendationCandidate]
    ) -> [FirmwareRecommendationCandidate] {
        candidates.sorted {
            let leftCompatibility = $0.compatibility.status
            let rightCompatibility = $1.compatibility.status
            if leftCompatibility != rightCompatibility {
                return leftCompatibility == .compatible
            }
            return compareCandidateVersion($0, $1) == .orderedDescending
        }
    }

    static func compareVersionStrings(
        _ lhs: String,
        _ rhs: String
    ) -> ComparisonResult {
        let left = versionTokens(lhs)
        let right = versionTokens(rhs)
        for index in 0..<min(left.count, right.count) {
            let comparison = left[index].compare(right[index])
            if comparison != .orderedSame { return comparison }
        }
        if left.count == right.count { return .orderedSame }
        return left.count < right.count
            ? .orderedAscending
            : .orderedDescending
    }

    private func recommendation(
        candidate: FirmwareRecommendationCandidate,
        tier: FirmwareRecommendationTier,
        source: FirmwareRecognitionSource,
        trust: FirmwareRecognitionTrust,
        selectionSource: FirmwareSelectionSource,
        modelFamilyKey: ModelFamilyKey?,
        target: FirmwareTargetIdentity,
        requiresManualConfirmation: Bool,
        basis: String
    ) -> FirmwareRecommendation {
        FirmwareRecommendation(
            candidate: candidate,
            tier: tier,
            source: source,
            trust: trust,
            selectionSource: selectionSource,
            modelFamilyKey: modelFamilyKey,
            hardwareBindingKey: HardwareBindingKey.resolve(identity: target),
            requiresManualConfirmation: requiresManualConfirmation,
            basis: basis)
    }

    private static func compareCandidateVersion(
        _ lhs: FirmwareRecommendationCandidate,
        _ rhs: FirmwareRecommendationCandidate
    ) -> ComparisonResult {
        let versionComparison = compareOptionalVersion(
            lhs.metadata?.productVersion,
            rhs.metadata?.productVersion)
        if versionComparison != .orderedSame { return versionComparison }
        let buildComparison = compareOptionalVersion(
            lhs.metadata?.productBuild,
            rhs.metadata?.productBuild)
        if buildComparison != .orderedSame { return buildComparison }
        return lhs.entry.url.standardizedFileURL.path
            .localizedStandardCompare(rhs.entry.url.standardizedFileURL.path)
    }

    private static func compareOptionalVersion(
        _ lhs: String?,
        _ rhs: String?
    ) -> ComparisonResult {
        switch (lhs, rhs) {
        case (.some(let left), .some(let right)):
            return compareVersionStrings(left, right)
        case (.some, .none):
            return .orderedDescending
        case (.none, .some):
            return .orderedAscending
        case (.none, .none):
            return .orderedSame
        }
    }

    private enum VersionToken: Equatable {
        case number(String)
        case text(String)

        func compare(_ other: VersionToken) -> ComparisonResult {
            switch (self, other) {
            case (.number(let left), .number(let right)):
                let normalizedLeft = left.drop {
                    $0 == "0"
                }
                let normalizedRight = right.drop {
                    $0 == "0"
                }
                if normalizedLeft.count != normalizedRight.count {
                    return normalizedLeft.count < normalizedRight.count
                        ? .orderedAscending
                        : .orderedDescending
                }
                if normalizedLeft == normalizedRight {
                    return .orderedSame
                }
                return normalizedLeft < normalizedRight
                    ? .orderedAscending
                    : .orderedDescending
            case (.text(let left), .text(let right)):
                if left == right { return .orderedSame }
                return left < right
                    ? .orderedAscending
                    : .orderedDescending
            case (.number, .text):
                return .orderedDescending
            case (.text, .number):
                return .orderedAscending
            }
        }
    }

    private static func versionTokens(_ value: String) -> [VersionToken] {
        var tokens: [VersionToken] = []
        var current = ""
        var currentIsNumber: Bool?

        func flush() {
            guard !current.isEmpty, let currentIsNumber else { return }
            tokens.append(
                currentIsNumber
                    ? .number(current)
                    : .text(current.lowercased()))
            current = ""
        }

        for scalar in value.unicodeScalars {
            if CharacterSet.decimalDigits.contains(scalar) {
                if currentIsNumber == false { flush() }
                currentIsNumber = true
                current.unicodeScalars.append(scalar)
            } else if CharacterSet.letters.contains(scalar) {
                if currentIsNumber == true { flush() }
                currentIsNumber = false
                current.unicodeScalars.append(scalar)
            } else {
                flush()
                currentIsNumber = nil
            }
        }
        flush()
        return tokens
    }
}

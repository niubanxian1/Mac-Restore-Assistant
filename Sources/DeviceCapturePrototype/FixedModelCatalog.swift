import Foundation

/// Fixed-version public-device-table lookup for already registered USB fields.
///
/// This is display-only evidence. Matching a public table entry does not claim
/// that the device was hardware-validated by this application.
enum FixedModelCatalog {
    struct Candidate: Codable, Hashable, Equatable {
        let classification: String
        let productType: String
        let hardwareCode: String
        let cpid: Int?
        let bdid: Int?
        let description: String
        let modelIdentifier: String
        let marketingName: String
        let aNumbers: String
        let source: String
        let verification: String

        enum CodingKeys: String, CodingKey {
            case classification
            case productType = "product_type"
            case hardwareCode = "hardware_code"
            case cpid
            case bdid
            case description
            case modelIdentifier = "model_identifier"
            case marketingName = "marketing_name"
            case aNumbers = "a_numbers"
            case source
            case verification
        }
    }

    enum Resolution: Equatable {
        case matched(Candidate)
        case candidates([Candidate])
        case conflict([Candidate])
        case unknown
    }

    static let sourceLabel =
        "固定版 libirecovery 公开资料候选（未经本机实机验证）"

    static let candidates: [Candidate] = MacIdentityCatalog.builtIn
        .hardwareRecords
        .map { hardware in
            let matchingRecord = MacIdentityCatalog.builtIn.records(
                forModelIdentifier: hardware.modelIdentifier
            ).first
            return Candidate(
                classification: hardware.classification,
                productType: hardware.productType,
                hardwareCode: hardware.hardwareCode,
                cpid: hardware.cpid,
                bdid: hardware.bdid,
                description: hardware.classification,
                modelIdentifier: hardware.modelIdentifier,
                marketingName: matchingRecord?.marketingName ?? hardware.modelIdentifier,
                aNumbers: matchingRecord?.aNumbers.joined(separator: " / ") ?? "",
                source: hardware.source,
                verification: hardware.verification)
        }

    static func candidate(for modelIdentifier: String) -> Candidate? {
        candidates.first { $0.modelIdentifier == modelIdentifier }
    }

    static func resolve(
        productType: String?,
        hardwareCode: String?,
        cpid: Int?,
        bdid: Int?
    ) -> Resolution {
        let product = productType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hardware = hardwareCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        var evidenceSets: [[Candidate]] = []
        var weakChipMatches: [Candidate] = []
        if !product.isEmpty {
            evidenceSets.append(candidates.filter {
                $0.productType.caseInsensitiveCompare(product) == .orderedSame
            })
        }
        if !hardware.isEmpty {
            evidenceSets.append(candidates.filter { $0.hardwareCode == hardware })
        }
        if let cpid, let bdid {
            evidenceSets.append(candidates.filter {
                $0.cpid == cpid && $0.bdid == bdid
            })
        } else if let cpid {
            // A chip family alone is not enough to select a model.
            weakChipMatches = candidates.filter { $0.cpid == cpid }
        }

        evidenceSets.removeAll(where: \.isEmpty)
        guard !evidenceSets.isEmpty else {
            return weakChipMatches.isEmpty ? .unknown : .candidates(weakChipMatches)
        }

        let union = unique(evidenceSets.flatMap { $0 })
        guard !union.isEmpty else { return .unknown }
        var intersection = evidenceSets[0]
        for set in evidenceSets.dropFirst() {
            let keys = Set(set.map(identityKey))
            intersection = intersection.filter { keys.contains(identityKey($0)) }
        }
        guard !intersection.isEmpty else {
            return evidenceSets.count > 1 ? .conflict(union) : .candidates(union)
        }
        let deduplicated = unique(intersection)
        if deduplicated.count == 1, let only = deduplicated.first {
            return .matched(only)
        }
        return .candidates(deduplicated)
    }

    private static func unique(_ values: [Candidate]) -> [Candidate] {
        var seen = Set<String>()
        return values.filter {
            seen.insert(identityKey($0))
                .inserted
        }
    }

    private static func identityKey(_ candidate: Candidate) -> String {
        "\(candidate.modelIdentifier)|\(candidate.productType)|\(candidate.hardwareCode)"
    }
}

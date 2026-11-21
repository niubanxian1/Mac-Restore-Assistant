import Foundation

enum MacIdentityState: String, Codable, Hashable {
    case confirmedCurrent = "confirmed_current"
    case uniqueCurrentMatch = "unique_current_match"
    case candidates
    case conflict
    case unknown
    case historicalHintOnly = "historical_hint_only"
}

enum MacIdentityField: String, Codable, Hashable {
    case explicitMachineIdentifier = "explicit_machine_identifier"
    case productType = "product_type"
    case hardwareCode = "hardware_code"
    case cpidBDID = "cpid_bdid"
    case cpidOnly = "cpid_only"
    case cfgutilECID = "cfgutil_ecid"
    case cfgutilLocation = "cfgutil_location"
    case ecid
    case mode
    case port
    case historicalCache = "historical_cache"
}

enum MacIdentityEvidenceQuality: String, Codable, Hashable {
    case direct
    case matched
    case candidate
    case context
    case historical
}

struct MacIdentityEvidence: Codable, Hashable {
    let evidenceID: String
    let field: MacIdentityField
    let rawValue: String
    let normalizedValue: String?
    let source: String
    let capturedAt: Date
    let connectionGeneration: UInt64
    let observationID: String
    let quality: MacIdentityEvidenceQuality
}

struct HistoricalIdentityHint: Codable, Hashable {
    let modelIdentifier: String
    let capturedAt: Date
    let source: String
}

struct MacIdentityObservation: Equatable {
    var observationID: String
    var connectionGeneration: UInt64
    var capturedAt: Date
    var mode: String?
    var currentECID: String?
    var explicitMachineIdentifier: String?
    var productType: String?
    var hardwareCode: String?
    var cpid: Int?
    var bdid: Int?
    var cfgutilModelIdentifier: String?
    var cfgutilECID: String?
    var cfgutilLocationMatched: Bool
    var historicalHint: HistoricalIdentityHint?

    init(
        observationID: String,
        connectionGeneration: UInt64,
        capturedAt: Date,
        mode: String? = nil,
        currentECID: String? = nil,
        explicitMachineIdentifier: String? = nil,
        productType: String? = nil,
        hardwareCode: String? = nil,
        cpid: Int? = nil,
        bdid: Int? = nil,
        cfgutilModelIdentifier: String? = nil,
        cfgutilECID: String? = nil,
        cfgutilLocationMatched: Bool = false,
        historicalHint: HistoricalIdentityHint? = nil
    ) {
        self.observationID = observationID
        self.connectionGeneration = connectionGeneration
        self.capturedAt = capturedAt
        self.mode = mode
        self.currentECID = currentECID
        self.explicitMachineIdentifier = explicitMachineIdentifier
        self.productType = productType
        self.hardwareCode = hardwareCode
        self.cpid = cpid
        self.bdid = bdid
        self.cfgutilModelIdentifier = cfgutilModelIdentifier
        self.cfgutilECID = cfgutilECID
        self.cfgutilLocationMatched = cfgutilLocationMatched
        self.historicalHint = historicalHint
    }
}

struct ResolvedMacIdentity: Hashable {
    var state: MacIdentityState
    var records: [MacCatalogRecord]
    var hardwareRecords: [MacHardwareIdentityRecord]
    var commonANumbers: [String]
    var candidateANumbers: [String]
    var commonYears: [Int]
    var candidateYears: [Int]
    var commonCategory: MacDeviceCategory?
    var commonSeries: String?
    var commonSizeLabel: String?
    var commonChip: String?
    var evidence: [MacIdentityEvidence]
    var conflictFields: [String]
    var sourceSummary: [String]
    var historicalHint: HistoricalIdentityHint?

    static let unknown = ResolvedMacIdentity(
        state: .unknown,
        records: [],
        hardwareRecords: [],
        commonANumbers: [],
        candidateANumbers: [],
        commonYears: [],
        candidateYears: [],
        commonCategory: nil,
        commonSeries: nil,
        commonSizeLabel: nil,
        commonChip: nil,
        evidence: [],
        conflictFields: [],
        sourceSummary: [],
        historicalHint: nil)

    var modelIdentifiers: [String] {
        Array(Set(records.map(\.modelIdentifier))).sorted()
    }

    var primaryModelIdentifier: String? {
        guard state == .confirmedCurrent || state == .uniqueCurrentMatch,
              modelIdentifiers.count == 1 else { return nil }
        return modelIdentifiers[0]
    }

    var isCandidate: Bool {
        state == .candidates
    }

    func withHistoricalHint(_ hint: HistoricalIdentityHint?) -> ResolvedMacIdentity {
        var copy = self
        copy.historicalHint = hint
        return copy
    }
}

enum MacIdentityResolver {
    private struct MatchSet {
        let field: MacIdentityField
        let records: [MacCatalogRecord]
        let hardwareRecords: [MacHardwareIdentityRecord]
        let strong: Bool
        let detail: String
        let quality: MacIdentityEvidenceQuality
    }

    static func resolve(
        observation: MacIdentityObservation,
        catalog: MacIdentityCatalog = .builtIn
    ) -> ResolvedMacIdentity {
        var sets: [MatchSet] = []
        var evidence: [MacIdentityEvidence] = []

        func appendEvidence(
            _ field: MacIdentityField,
            raw: String,
            normalized: String?,
            source: String,
            quality: MacIdentityEvidenceQuality
        ) {
            let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return }
            evidence.append(MacIdentityEvidence(
                evidenceID: "\(observation.observationID):\(field.rawValue)",
                field: field,
                rawValue: raw,
                normalizedValue: normalized,
                source: source,
                capturedAt: observation.capturedAt,
                connectionGeneration: observation.connectionGeneration,
                observationID: observation.observationID,
                quality: quality))
        }

        if let mode = observation.mode, !mode.isEmpty {
            appendEvidence(.mode, raw: mode, normalized: mode,
                           source: "current USB mode", quality: .context)
        }
        if let ecid = observation.currentECID, !ecid.isEmpty {
            appendEvidence(.ecid, raw: ecid, normalized: ecid.uppercased(),
                           source: "current USB ECID", quality: .context)
        }

        if let raw = observation.explicitMachineIdentifier,
           let identifier = normalizedModelIdentifier(raw),
           !identifier.hasPrefix("iBridge") {
            let records = catalog.records(forModelIdentifier: identifier)
            if !records.isEmpty {
                sets.append(MatchSet(
                    field: .explicitMachineIdentifier,
                    records: records,
                    hardwareRecords: catalog.hardware(forModelIdentifier: identifier),
                    strong: true,
                    detail: "当前 USB：machine=\(identifier)",
                    quality: .direct))
            }
            appendEvidence(.explicitMachineIdentifier, raw: raw,
                           normalized: identifier,
                           source: "current USB explicit machine field",
                           quality: .direct)
        }

        if let raw = observation.productType,
           let hard = catalog.hardware(forProductType: raw) {
            let records = catalog.records(forModelIdentifier: hard.modelIdentifier)
            if !records.isEmpty {
                sets.append(MatchSet(
                    field: .productType,
                    records: records,
                    hardwareRecords: [hard],
                    strong: true,
                    detail: "当前 USB：ProductType=\(hard.productType)",
                    quality: .matched))
            }
            appendEvidence(.productType, raw: raw, normalized: hard.productType,
                           source: "current USB ProductType; fixed libirecovery table",
                           quality: .matched)
        }

        if let raw = observation.hardwareCode,
           let hard = catalog.hardware(forCode: raw) {
            let records = catalog.records(forModelIdentifier: hard.modelIdentifier)
            if !records.isEmpty {
                sets.append(MatchSet(
                    field: .hardwareCode,
                    records: records,
                    hardwareRecords: [hard],
                    strong: true,
                    detail: "当前 USB：HardwareCode=\(hard.hardwareCode)",
                    quality: .matched))
            }
            appendEvidence(.hardwareCode, raw: raw, normalized: hard.hardwareCode,
                           source: "current USB HardwareCode; fixed libirecovery table",
                           quality: .matched)
        }

        if let cpid = observation.cpid, let bdid = observation.bdid,
           let hard = catalog.hardware(cpid: cpid, bdid: bdid) {
            let records = catalog.records(forModelIdentifier: hard.modelIdentifier)
            if !records.isEmpty {
                sets.append(MatchSet(
                    field: .cpidBDID,
                    records: records,
                    hardwareRecords: [hard],
                    strong: true,
                    detail: String(format: "当前 USB：CPID=0x%04X / BDID=0x%02X", cpid, bdid),
                    quality: .matched))
            }
            appendEvidence(
                .cpidBDID,
                raw: String(format: "0x%04X/0x%02X", cpid, bdid),
                normalized: String(format: "%04X:%02X", cpid, bdid),
                source: "current USB CPID/BDID; fixed libirecovery table",
                quality: .matched)
        } else if let cpid = observation.cpid {
            let hardware = catalog.hardware(cpid: cpid)
            let records = recordsFor(hardware: hardware, catalog: catalog)
            if !records.isEmpty {
                sets.append(MatchSet(
                    field: .cpidOnly,
                    records: records,
                    hardwareRecords: hardware,
                    strong: false,
                    detail: String(format: "当前 USB：仅 CPID=0x%04X", cpid),
                    quality: .candidate))
            }
            appendEvidence(
                .cpidOnly,
                raw: String(format: "0x%04X", cpid),
                normalized: String(format: "%04X", cpid),
                source: "current USB CPID only",
                quality: .candidate)
        }

        if let raw = observation.cfgutilModelIdentifier,
           let identifier = normalizedModelIdentifier(raw) {
            let ecidMatches = currentECIDMatches(
                current: observation.currentECID,
                cfgutil: observation.cfgutilECID)
            let hasCurrentECID = !(observation.currentECID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ?? true)
            let accepted = ecidMatches
                || (observation.cfgutilLocationMatched && !hasCurrentECID)
            if accepted {
                let records = catalog.records(forModelIdentifier: identifier)
                if !records.isEmpty {
                    sets.append(MatchSet(
                        field: ecidMatches ? .cfgutilECID : .cfgutilLocation,
                        records: records,
                        hardwareRecords: catalog.hardware(forModelIdentifier: identifier),
                        strong: ecidMatches,
                        detail: ecidMatches
                            ? "当前 cfgutil：Type=\(identifier)，ECID 与当前 USB 一致"
                            : "当前 cfgutil：Type=\(identifier)，仅 location 关联",
                        quality: ecidMatches ? .matched : .candidate))
                }
                appendEvidence(
                    ecidMatches ? .cfgutilECID : .cfgutilLocation,
                    raw: raw,
                    normalized: identifier,
                    source: ecidMatches
                        ? "current cfgutil ECID match"
                        : "current cfgutil location-only",
                    quality: ecidMatches ? .matched : .candidate)
            }
        }

        guard !sets.isEmpty else {
            var result = ResolvedMacIdentity.unknown
            result.evidence = evidence
            if let historical = observation.historicalHint {
                result.state = .historicalHintOnly
                result.historicalHint = historical
                result.sourceSummary = ["同 ECID 历史提示：\(historical.modelIdentifier)，不参与当前确认"]
            }
            return result
        }

        let allRecords = uniqueRecords(sets.flatMap(\.records))
        var intersection = sets[0].records
        for set in sets.dropFirst() {
            let ids = Set(set.records.map(\.recordID))
            intersection = intersection.filter { ids.contains($0.recordID) }
        }

        if intersection.isEmpty {
            return ResolvedMacIdentity(
                state: .conflict,
                records: allRecords,
                hardwareRecords: uniqueHardware(sets.flatMap(\.hardwareRecords)),
                commonANumbers: [],
                candidateANumbers: sortedUnion(allRecords.flatMap(\.aNumbers)),
                commonYears: [],
                candidateYears: Array(Set(allRecords.map(\.year))).sorted(),
                commonCategory: nil,
                commonSeries: nil,
                commonSizeLabel: nil,
                commonChip: nil,
                evidence: evidence,
                conflictFields: sets.map { $0.field.rawValue },
                sourceSummary: sets.map(\.detail) +
                    ["当前非空身份字段无法求交；未选择任一机型。"],
                historicalHint: observation.historicalHint)
        }

        let identifiers = Set(intersection.map(\.modelIdentifier))
        let hasDirect = sets.contains { $0.field == .explicitMachineIdentifier }
        let hasStrong = sets.contains(where: \.strong)
        let state: MacIdentityState
        if identifiers.count == 1 {
            if hasDirect {
                state = .confirmedCurrent
            } else if hasStrong {
                state = .uniqueCurrentMatch
            } else {
                state = .candidates
            }
        } else {
            state = .candidates
        }

        var sources = sets.map(\.detail)
        sources.append("机型资料：维修表 \(intersection.map(\.recordID).joined(separator: " / "))")
        if !intersection.isEmpty {
            sources.append("固定资料：libirecovery@\(catalog.upstreamCommit)")
        }

        return ResolvedMacIdentity(
            state: state,
            records: intersection,
            hardwareRecords: uniqueHardware(sets.flatMap(\.hardwareRecords)),
            commonANumbers: commonValues(intersection.map { Set($0.aNumbers) }),
            candidateANumbers: sortedUnion(intersection.flatMap(\.aNumbers)),
            commonYears: commonValues(intersection.map { Set([$0.year]) }),
            candidateYears: Array(Set(intersection.map(\.year))).sorted(),
            commonCategory: commonValue(intersection.map(\.category)),
            commonSeries: commonValue(intersection.map(\.series)),
            commonSizeLabel: commonOptionalValue(intersection.map(\.sizeLabel)),
            commonChip: commonOptionalValue(intersection.map(\.chip)),
            evidence: evidence,
            conflictFields: [],
            sourceSummary: sources,
            historicalHint: observation.historicalHint)
    }

    static func resolve(
        device: ObservedDevice,
        historicalHint: HistoricalIdentityHint?,
        catalog: MacIdentityCatalog = .builtIn
    ) -> ResolvedMacIdentity {
        resolve(
            observation: MacIdentityObservation(
                observationID: device.observationID.isEmpty
                    ? "usb:\(device.locationID):\(device.mode.rawValue)"
                    : device.observationID,
                connectionGeneration: device.connectionGeneration,
                capturedAt: device.identityCapturedAt,
                mode: device.mode.title,
                currentECID: device.ecid,
                explicitMachineIdentifier: device.explicitMachineIdentifierRaw,
                productType: device.productType,
                hardwareCode: device.hardwareCode,
                cpid: device.chipID,
                bdid: device.boardID,
                cfgutilModelIdentifier: device.cfgutilModelIdentifier,
                cfgutilECID: device.cfgutilECID,
                cfgutilLocationMatched: device.cfgutilLocationMatched,
                historicalHint: historicalHint),
            catalog: catalog)
    }

    private static func recordsFor(
        hardware: [MacHardwareIdentityRecord],
        catalog: MacIdentityCatalog
    ) -> [MacCatalogRecord] {
        uniqueRecords(hardware.flatMap {
            catalog.records(forModelIdentifier: $0.modelIdentifier)
        })
    }

    private static func currentECIDMatches(current: String?, cfgutil: String?) -> Bool {
        guard let current, !current.isEmpty, let cfgutil, !cfgutil.isEmpty else {
            return false
        }
        return current.caseInsensitiveCompare(cfgutil) == .orderedSame
    }

    private static func normalizedModelIdentifier(_ raw: String) -> String? {
        TargetModelCatalog.identifier(from: raw)
    }

    private static func uniqueRecords(_ records: [MacCatalogRecord]) -> [MacCatalogRecord] {
        var seen = Set<String>()
        return records.filter { seen.insert($0.recordID).inserted }
    }

    private static func uniqueHardware(
        _ records: [MacHardwareIdentityRecord]
    ) -> [MacHardwareIdentityRecord] {
        var seen = Set<String>()
        return records.filter { seen.insert($0.hardwareProfileID).inserted }
    }

    private static func sortedUnion(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }

    private static func commonValues<T: Hashable>(_ sets: [Set<T>]) -> [T] {
        guard var common = sets.first else { return [] }
        for set in sets.dropFirst() { common.formIntersection(set) }
        return common.sorted { String(describing: $0) < String(describing: $1) }
    }

    private static func commonValue<T: Hashable>(_ values: [T]) -> T? {
        guard let first = values.first,
              values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private static func commonOptionalValue<T: Hashable>(_ values: [T?]) -> T? {
        guard let first = values.first,
              first != nil,
              values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }
}

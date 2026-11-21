import Foundation

enum MacDeviceCategory: String, Codable, Hashable {
    case notebook
    case desktop
    case unknown
}

struct MacCatalogRecord: Codable, Hashable {
    let recordID: String
    let modelIdentifier: String
    let marketingName: String
    let aNumbers: [String]
    let aNumbersRaw: String
    let aNumbersState: String
    let year: Int
    let productLine: String
    let family: String
    let category: MacDeviceCategory
    let series: String
    let sizeLabel: String?
    let sizeState: String
    let sizeSourceRaw: String
    let chip: String?
    let chipState: String
    let chipRaw: String
    let cpuGPURaw: String
    let originalMacOSRaw: String
    let maxMacOSRaw: String
    let recommendedOSRaw: String
    let architecture: String
    let architectureState: String
    let architectureRaw: String
    let architectureSourceOverrideRaw: String?
    let emc: String
    let verification: String
    let verificationRaw: String
    let notesRaw: String
    let fastIdentityLabelRaw: String
    let sourceIDs: [String]
    let uncertainties: [String]

    enum CodingKeys: String, CodingKey {
        case recordID = "record_id"
        case modelIdentifier = "model_identifier"
        case marketingName = "marketing_name"
        case aNumbers = "a_numbers"
        case aNumbersRaw = "a_numbers_raw"
        case aNumbersState = "a_numbers_state"
        case year
        case productLine = "product_line"
        case family
        case category
        case series
        case sizeLabel = "size_label"
        case sizeState = "size_state"
        case sizeSourceRaw = "size_source_raw"
        case chip
        case chipState = "chip_state"
        case chipRaw = "chip_raw"
        case cpuGPURaw = "cpu_gpu_raw"
        case originalMacOSRaw = "original_macos_raw"
        case maxMacOSRaw = "max_macos_raw"
        case recommendedOSRaw = "recommended_os_raw"
        case architecture
        case architectureState = "architecture_state"
        case architectureRaw = "architecture_raw"
        case architectureSourceOverrideRaw = "architecture_source_override_raw"
        case emc
        case verification
        case verificationRaw = "verification_raw"
        case notesRaw = "notes_raw"
        case fastIdentityLabelRaw = "fast_identity_label_raw"
        case sourceIDs = "source_ids"
        case uncertainties
    }
}

struct MacHardwareIdentityRecord: Codable, Hashable {
    let hardwareProfileID: String
    let productType: String
    let bridgeProductType: String?
    let hardwareCode: String
    let cpid: Int?
    let bdid: Int?
    let classification: String
    let modelIdentifier: String
    let source: String
    let verification: String

    enum CodingKeys: String, CodingKey {
        case hardwareProfileID = "hardware_profile_id"
        case productType = "product_type"
        case bridgeProductType = "bridge_product_type"
        case hardwareCode = "hardware_code"
        case cpid
        case bdid
        case classification
        case modelIdentifier = "model_identifier"
        case source
        case verification
    }
}

/// Fixed, display-only identity data. It is never consulted by device control.
struct MacIdentityCatalog: Equatable {
    private struct ModelFile: Codable {
        let schemaVersion: Int
        let sourceSHA256: [String: String]
        let records: [MacCatalogRecord]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case sourceSHA256 = "source_sha256"
            case records
        }
    }

    private struct HardwareFile: Codable {
        let schemaVersion: Int
        let upstreamCommit: String
        let sourceSHA256: [String: String]
        let records: [MacHardwareIdentityRecord]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case upstreamCommit = "upstream_commit"
            case sourceSHA256 = "source_sha256"
            case records
        }
    }

    let records: [MacCatalogRecord]
    let hardwareRecords: [MacHardwareIdentityRecord]
    let modelSourceSHA256: [String: String]
    let hardwareSourceSHA256: [String: String]
    let upstreamCommit: String

    private let recordsByModelIdentifier: [String: [MacCatalogRecord]]
    private let recordsByANumber: [String: [MacCatalogRecord]]
    private let hardwareByProductType: [String: MacHardwareIdentityRecord]
    private let hardwareByCode: [String: MacHardwareIdentityRecord]
    private let hardwareByCPIDBDID: [String: MacHardwareIdentityRecord]
    private let hardwareByCPID: [String: [MacHardwareIdentityRecord]]

    static let builtIn: MacIdentityCatalog = loadBuiltIn()

    init(
        records: [MacCatalogRecord],
        hardwareRecords: [MacHardwareIdentityRecord],
        modelSourceSHA256: [String: String] = [:],
        hardwareSourceSHA256: [String: String] = [:],
        upstreamCommit: String = "3301fe7d834a485b368cd7edf20f7535d6d598b4"
    ) {
        self.records = records
        self.hardwareRecords = hardwareRecords
        self.modelSourceSHA256 = modelSourceSHA256
        self.hardwareSourceSHA256 = hardwareSourceSHA256
        self.upstreamCommit = upstreamCommit
        self.recordsByModelIdentifier = Dictionary(
            grouping: records,
            by: { $0.modelIdentifier.uppercased() })
        self.recordsByANumber = Dictionary(
            grouping: records.flatMap { record in
                record.aNumbers.map { ($0.uppercased(), record) }
            },
            by: \.0)
            .mapValues { $0.map(\.1) }
        self.hardwareByProductType = Dictionary(
            hardwareRecords.map { ($0.productType.uppercased(), $0) },
            uniquingKeysWith: { first, _ in first })
        self.hardwareByCode = Dictionary(
            hardwareRecords.map { ($0.hardwareCode.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first })
        self.hardwareByCPIDBDID = Dictionary(
            hardwareRecords.compactMap { record -> (String, MacHardwareIdentityRecord)? in
                guard let cpid = record.cpid, let bdid = record.bdid else { return nil }
                return (Self.chipKey(cpid: cpid, bdid: bdid), record)
            },
            uniquingKeysWith: { first, _ in first })
        self.hardwareByCPID = Dictionary(
            grouping: hardwareRecords.compactMap { record in
                record.cpid.map { (String($0), record) }
            },
            by: \.0)
            .mapValues { $0.map(\.1) }
    }

    func records(forModelIdentifier identifier: String) -> [MacCatalogRecord] {
        recordsByModelIdentifier[identifier.uppercased()] ?? []
    }

    func records(forANumber aNumber: String) -> [MacCatalogRecord] {
        recordsByANumber[aNumber.uppercased()] ?? []
    }

    func hardware(forProductType productType: String) -> MacHardwareIdentityRecord? {
        hardwareByProductType[productType.uppercased()]
    }

    func hardware(forCode code: String) -> MacHardwareIdentityRecord? {
        hardwareByCode[code.lowercased()]
    }

    func hardware(cpid: Int, bdid: Int) -> MacHardwareIdentityRecord? {
        hardwareByCPIDBDID[Self.chipKey(cpid: cpid, bdid: bdid)]
    }

    func hardware(cpid: Int) -> [MacHardwareIdentityRecord] {
        hardwareByCPID[String(cpid)] ?? []
    }

    func hardware(forModelIdentifier identifier: String) -> [MacHardwareIdentityRecord] {
        hardwareRecords.filter {
            $0.modelIdentifier.caseInsensitiveCompare(identifier) == .orderedSame
        }
    }

    private static func chipKey(cpid: Int, bdid: Int) -> String {
        String(format: "%08X:%04X", cpid, bdid)
    }

    private static func loadBuiltIn() -> MacIdentityCatalog {
        let bundles = [Bundle.main, Bundle.module]
        guard let modelURL = resourceURL(
                name: "mac-model-catalog.v2",
                extension: "json",
                bundles: bundles
              ),
              let hardwareURL = resourceURL(
                name: "mac-hardware-identity.v1",
                extension: "json",
                bundles: bundles
              ),
              let modelData = try? Data(contentsOf: modelURL),
              let hardwareData = try? Data(contentsOf: hardwareURL),
              let modelFile = try? JSONDecoder().decode(ModelFile.self, from: modelData),
              let hardwareFile = try? JSONDecoder().decode(HardwareFile.self, from: hardwareData),
              modelFile.schemaVersion == 2,
              hardwareFile.schemaVersion == 1,
              hardwareFile.upstreamCommit ==
                "3301fe7d834a485b368cd7edf20f7535d6d598b4",
              modelFile.records.count == 166,
              Set(modelFile.records.map(\.modelIdentifier)).count == 144,
              Set(modelFile.records.flatMap(\.aNumbers)).count == 92,
              hardwareFile.records.count == 82 else {
            return MacIdentityCatalog(records: [], hardwareRecords: [])
        }
        return MacIdentityCatalog(
            records: modelFile.records,
            hardwareRecords: hardwareFile.records,
            modelSourceSHA256: modelFile.sourceSHA256,
            hardwareSourceSHA256: hardwareFile.sourceSHA256,
            upstreamCommit: hardwareFile.upstreamCommit)
    }

    private static func resourceURL(
        name: String,
        extension ext: String,
        bundles: [Bundle]
    ) -> URL? {
        for bundle in bundles {
            if let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }
}

import CryptoKit
import Darwin
import Foundation

enum IPSWFileValidity: String, Codable, Equatable, Hashable, Sendable {
    case valid = "VALID"
    case invalid = "INVALID"
    case unverified = "UNVERIFIED"
}

enum HardwareCompatibilityStatus: String, Codable, Equatable, Hashable, Sendable {
    case compatible = "COMPATIBLE"
    case incompatible = "INCOMPATIBLE"
    case unverified = "UNVERIFIED"
}

struct HardwareCompatibility: Codable, Equatable, Hashable, Sendable {
    let status: HardwareCompatibilityStatus
    let message: String
}

struct RestoreTargetIdentity: Codable, Equatable, Hashable, Sendable {
    let productType: String?
    let deviceClass: String?
    let boardID: Int?
    let chipID: Int?
}

struct IPSWBuildIdentity: Codable, Equatable, Hashable, Sendable {
    let deviceClass: String?
    let boardID: Int?
    let chipID: Int?
}

struct IPSWMetadata: Codable, Equatable, Hashable, Sendable {
    let productTypes: [String]
    let identities: [IPSWBuildIdentity]
    let productVersion: String?
    let productBuild: String?

    var deviceClasses: [String] {
        Array(Set(identities.compactMap(\.deviceClass))).sorted()
    }

    var boardChipPairs: [String] {
        identities.compactMap { identity in
            guard let board = identity.boardID, let chip = identity.chipID else { return nil }
            return String(format: "0x%X/0x%X", board, chip)
        }
    }
}

struct IPSWFileIdentity: Codable, Equatable, Hashable, Sendable {
    let canonicalRealpath: String
    let dev: UInt64
    let ino: UInt64
    let sizeBytes: UInt64
    let mtimeNs: Int64
    let ctimeNs: Int64
    let buildManifestSHA256: String
}

struct IPSWMetadataReadResult: Equatable, Sendable {
    let validity: IPSWFileValidity
    let metadata: IPSWMetadata?
    let error: String?
    let fileIdentity: IPSWFileIdentity?
    let buildManifestSHA256: String
    let wholeFileSHA256: String?

    init(
        validity: IPSWFileValidity,
        metadata: IPSWMetadata?,
        error: String?,
        fileIdentity: IPSWFileIdentity? = nil,
        buildManifestSHA256: String = "",
        wholeFileSHA256: String? = nil
    ) {
        self.validity = validity
        self.metadata = metadata
        self.error = error
        self.fileIdentity = fileIdentity
        self.buildManifestSHA256 = buildManifestSHA256
        self.wholeFileSHA256 = wholeFileSHA256
    }
}

enum IPSWIdentityVerification: Equatable, Sendable {
    case valid(identity: IPSWFileIdentity, metadata: IPSWMetadata)
    case changed(actual: IPSWFileIdentity)
    case invalid(reason: String)
}

enum IPSWMetadataError: Error, LocalizedError {
    case cannotRead(String)
    case metadataTooLarge
    case invalidManifest

    var errorDescription: String? {
        switch self {
        case .cannotRead(let reason): return reason
        case .metadataTooLarge: return "BuildManifest.plist exceeds the bounded read limit."
        case .invalidManifest: return "BuildManifest.plist has no usable supported products or identities."
        }
    }
}

enum IPSWMetadataReader {
    static let maximumManifestBytes = 32 * 1024 * 1024
    static let metadataReadTimeout: TimeInterval = 8

    static func read(url: URL) throws -> IPSWMetadataReadResult {
        let before = try statFingerprint(url)
        let manifestData = try boundedMember(
            archive: url,
            member: "BuildManifest.plist",
            limit: maximumManifestBytes)
        guard let manifestData,
              let manifestPlist = try? PropertyListSerialization.propertyList(
                from: manifestData,
                options: [],
                format: nil),
              let manifest = manifestPlist as? [String: Any] else {
            return IPSWMetadataReadResult(
                validity: .invalid,
                metadata: nil,
                error: "BuildManifest.plist is missing or invalid.",
                buildManifestSHA256: manifestData.map(sha256Hex) ?? "")
        }
        let manifestSHA256 = sha256Hex(manifestData)

        let products = stringArray(manifest["SupportedProductTypes"])
        let identities = buildIdentities(manifest["BuildIdentities"])
        guard !products.isEmpty || !identities.isEmpty else {
            return IPSWMetadataReadResult(
                validity: .invalid,
                metadata: nil,
                error: IPSWMetadataError.invalidManifest.localizedDescription,
                buildManifestSHA256: manifestSHA256)
        }

        let systemData = try? boundedMember(
            archive: url,
            member: "SystemVersion.plist",
            limit: 1024 * 1024)
        let system = systemData.flatMap { data -> [String: Any]? in
            guard let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil) else { return nil }
            return plist as? [String: Any]
        }

        let after = try statFingerprint(url)
        guard before == after else {
            return IPSWMetadataReadResult(
                validity: .invalid,
                metadata: nil,
                error: "IPSW changed while metadata was being read.",
                buildManifestSHA256: manifestSHA256)
        }
        let identity = after.withBuildManifestSHA256(manifestSHA256)

        let version = text(manifest["ProductVersion"])
            ?? text(system?["ProductVersion"])
        let build = text(manifest["ProductBuildVersion"])
            ?? text(system?["ProductBuildVersion"])
        return IPSWMetadataReadResult(
            validity: .valid,
            metadata: IPSWMetadata(
                productTypes: products,
                identities: identities,
                productVersion: version,
                productBuild: build),
            error: nil,
            fileIdentity: identity,
            buildManifestSHA256: manifestSHA256,
            wholeFileSHA256: nil)
    }

    static func fileIdentity(
        url: URL,
        buildManifestSHA256: String
    ) throws -> IPSWFileIdentity {
        try statFingerprint(url)
            .withBuildManifestSHA256(buildManifestSHA256)
    }

    static func verifyIdentity(
        url: URL,
        expected: IPSWFileIdentity
    ) throws -> IPSWIdentityVerification {
        let result = try read(url: url)
        guard result.validity == .valid,
              let metadata = result.metadata,
              let actual = result.fileIdentity else {
            return .invalid(
                reason: result.error
                    ?? "IPSW metadata could not be revalidated.")
        }
        guard actual == expected else {
            return .changed(actual: actual)
        }
        return .valid(identity: actual, metadata: metadata)
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private struct StatFingerprint: Equatable {
        let canonicalRealpath: String
        let dev: UInt64
        let ino: UInt64
        let sizeBytes: UInt64
        let mtimeNs: Int64
        let ctimeNs: Int64

        func withBuildManifestSHA256(_ digest: String) -> IPSWFileIdentity {
            IPSWFileIdentity(
                canonicalRealpath: canonicalRealpath,
                dev: dev,
                ino: ino,
                sizeBytes: sizeBytes,
                mtimeNs: mtimeNs,
                ctimeNs: ctimeNs,
                buildManifestSHA256: digest)
        }
    }

    private static func statFingerprint(_ url: URL) throws -> StatFingerprint {
        let canonicalPath = try canonicalRealpath(url)
        var fileStat = stat()
        let status = canonicalPath.withCString {
            Darwin.lstat($0, &fileStat)
        }
        guard status == 0 else {
            throw POSIXError(
                POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard (fileStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw IPSWMetadataError.cannotRead(
                "Selected IPSW is not a regular file.")
        }
        return StatFingerprint(
            canonicalRealpath: canonicalPath,
            dev: UInt64(fileStat.st_dev),
            ino: UInt64(fileStat.st_ino),
            sizeBytes: UInt64(fileStat.st_size),
            mtimeNs: nanoseconds(
                seconds: fileStat.st_mtimespec.tv_sec,
                nanoseconds: fileStat.st_mtimespec.tv_nsec),
            ctimeNs: nanoseconds(
                seconds: fileStat.st_ctimespec.tv_sec,
                nanoseconds: fileStat.st_ctimespec.tv_nsec))
    }

    private static func canonicalRealpath(_ url: URL) throws -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let resolved = buffer.withUnsafeMutableBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return false }
            return url.withUnsafeFileSystemRepresentation { source in
                guard let source else { return false }
                return Darwin.realpath(source, base) != nil
            }
        }
        guard resolved else {
            throw POSIXError(
                POSIXErrorCode(rawValue: errno) ?? .ENOENT)
        }
        return String(cString: buffer)
    }

    private static func nanoseconds(
        seconds: Int,
        nanoseconds: Int
    ) -> Int64 {
        Int64(seconds) * 1_000_000_000 + Int64(nanoseconds)
    }

    private static func boundedMember(
        archive: URL,
        member: String,
        limit: Int
    ) throws -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archive.path, member]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()

        let finished = DispatchSemaphore(value: 0)
        let stateLock = NSLock()
        var outputData = Data()
        var exceededLimit = false
        DispatchQueue.global(qos: .utility).async {
            defer { finished.signal() }
            while true {
                let chunk = try? output.fileHandleForReading.read(upToCount: 65_536)
                guard let chunk, !chunk.isEmpty else { break }
                stateLock.lock()
                if outputData.count + chunk.count > limit {
                    exceededLimit = true
                    stateLock.unlock()
                    process.terminate()
                    break
                }
                outputData.append(chunk)
                stateLock.unlock()
            }
        }
        if finished.wait(timeout: .now() + metadataReadTimeout) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 1)
            try? output.fileHandleForReading.close()
            throw IPSWMetadataError.cannotRead(
                "Timed out while reading \(member) from the IPSW.")
        }
        process.waitUntilExit()
        stateLock.lock()
        let data = outputData
        let tooLarge = exceededLimit
        stateLock.unlock()
        if tooLarge {
            throw IPSWMetadataError.metadataTooLarge
        }
        return process.terminationStatus == 0 ? data : nil
    }

    private static func buildIdentities(_ value: Any?) -> [IPSWBuildIdentity] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            let info = row["Info"] as? [String: Any] ?? [:]
            let deviceClass = text(info["DeviceClass"])?.lowercased()
            let board = int(row["ApBoardID"]) ?? int(info["ApBoardID"])
            let chip = int(row["ApChipID"]) ?? int(info["ApChipID"])
            guard deviceClass != nil || board != nil || chip != nil else { return nil }
            return IPSWBuildIdentity(
                deviceClass: deviceClass,
                boardID: board,
                chipID: chip)
        }
    }

    private static func stringArray(_ value: Any?) -> [String] {
        guard let values = value as? [Any] else { return [] }
        return Array(Set(values.compactMap(text))).sorted()
    }

    private static func text(_ value: Any?) -> String? {
        guard let value else { return nil }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        guard let text = text(value) else { return nil }
        if text.lowercased().hasPrefix("0x") {
            return Int(text.dropFirst(2), radix: 16)
        }
        return Int(text, radix: 10)
    }
}

enum IPSWCompatibilityEvaluator {
    static func evaluate(
        metadata: IPSWMetadata,
        target: RestoreTargetIdentity
    ) -> HardwareCompatibility {
        let product = target.productType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let product, !product.isEmpty,
           !metadata.productTypes.contains(product) {
            return HardwareCompatibility(
                status: .incompatible,
                message: "目标 ProductType 不在固件支持列表中。")
        }

        if let board = target.boardID, let chip = target.chipID {
            guard !metadata.identities.isEmpty else {
                return HardwareCompatibility(
                    status: .unverified,
                    message: "固件缺少 BuildIdentity；不能判定精确硬件兼容性，需人工确认。")
            }
            let matching = metadata.identities.filter {
                $0.boardID == board && $0.chipID == chip
            }
            guard !matching.isEmpty else {
                return HardwareCompatibility(
                    status: .incompatible,
                    message: "同一 BuildIdentity 中没有目标 BoardID/ChipID。")
            }
            if let targetClass = normalized(target.deviceClass) {
                let classMatches = matching.contains {
                    normalized($0.deviceClass) == targetClass
                }
                guard classMatches else {
                    return HardwareCompatibility(
                        status: .incompatible,
                        message: "目标 DeviceClass 与同一 BuildIdentity 不一致。")
                }
                return HardwareCompatibility(
                    status: .compatible,
                    message: "ProductType、DeviceClass 与 BoardID/ChipID 均精确匹配。")
            }
            let classes = Set(matching.compactMap {
                normalized($0.deviceClass)
            })
            if !matching.isEmpty,
               matching.allSatisfy({ normalized($0.deviceClass) != nil }),
               classes.count == 1,
               let deviceClass = classes.first {
                return HardwareCompatibility(
                    status: .compatible,
                    message: "BoardID/ChipID 精确匹配；DeviceClass 由唯一 BuildIdentity 补齐（\(deviceClass)）。")
            }
            return HardwareCompatibility(
                status: .unverified,
                message: classes.count > 1
                    ? "硬件配对命中，但固件存在多个 DeviceClass；需人工确认。"
                    : "硬件配对命中，但目标 DeviceClass 未读取；需人工确认。")
        }

        guard product != nil else {
            return HardwareCompatibility(
                status: .unverified,
                message: "目标硬件身份不足，无法检查精确 BuildIdentity。")
        }
        return HardwareCompatibility(
            status: .unverified,
            message: "固件支持该 ProductType，但缺少 BoardID/ChipID；需人工确认。")
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}

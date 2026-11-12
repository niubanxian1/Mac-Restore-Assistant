import Foundation
import Darwin

public enum EvidencePackageArchiveError: Error, LocalizedError {
    case destinationExists(String)
    case archiveFailed(String)
    case verifyFailed(String)
    case publishFailed(String)

    public var errorDescription: String? {
        switch self {
        case .destinationExists(let p): return "证据包已存在，未覆盖：\(p)"
        case .archiveFailed(let m): return "打包失败：\(m)"
        case .verifyFailed(let m): return "证据包校验失败：\(m)"
        case .publishFailed(let m): return "证据包发布失败：\(m)"
        }
    }
}

public struct EvidencePackageArchiveResult: Sendable, Equatable {
    public let archiveURL: URL
    public let sha256: String
    public let byteSize: Int
}

/// Build a .zip from an already verified package directory. The package
/// directory remains a private staging object; only the verified archive is
/// published, using RENAME_EXCL (no overwrite).
public enum EvidencePackageArchive {
    private static let RENAME_EXCL: Int32 = 0x00000004

    public static func archive(
        packageDirectory: URL,
        destination: URL,
        archiveRootName: String? = nil,
        shouldCancel: (@Sendable () -> Bool)? = nil
    ) throws -> EvidencePackageArchiveResult {
        if shouldCancel?() == true { throw CancellationError() }
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else {
            throw EvidencePackageArchiveError.destinationExists(destination.path)
        }
        let parent = destination.deletingLastPathComponent()
        var wrapper: URL?
        var sourceDirectory = packageDirectory
        if let archiveRootName, !archiveRootName.isEmpty {
            let root = parent.appendingPathComponent(".rlm-archive-root-\(UUID().uuidString)", isDirectory: true)
            let named = root.appendingPathComponent(archiveRootName, isDirectory: true)
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            do {
                try fm.moveItem(at: packageDirectory, to: named)
            } catch {
                try? fm.removeItem(at: root)
                throw EvidencePackageArchiveError.archiveFailed("归档根目录准备失败：\(error.localizedDescription)")
            }
            wrapper = root
            sourceDirectory = named
        }
        let stage = parent.appendingPathComponent(".rlm-package-stage-\(UUID().uuidString).zip")
        defer {
            // The staging payload is owned by this transaction. Only clean it
            // after a verified publication; otherwise leave it for inspection.
        }
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--norsrc", "--keepParent", sourceDirectory.path, stage.path]
        ditto.standardOutput = FileHandle.nullDevice
        ditto.standardError = Pipe()
        do { try ditto.run() } catch {
            throw EvidencePackageArchiveError.archiveFailed(String(describing: error))
        }
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw EvidencePackageArchiveError.archiveFailed("ditto exit \(ditto.terminationStatus)")
        }
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-t", stage.path]
        unzip.standardOutput = FileHandle.nullDevice
        unzip.standardError = Pipe()
        do { try unzip.run() } catch {
            throw EvidencePackageArchiveError.verifyFailed(String(describing: error))
        }
        unzip.waitUntilExit()
        if shouldCancel?() == true { throw CancellationError() }
        guard unzip.terminationStatus == 0 else {
            throw EvidencePackageArchiveError.verifyFailed("unzip -t exit \(unzip.terminationStatus)")
        }
        let digest = try Integrity.sha256(ofFileAt: stage)
        let attrs = try? fm.attributesOfItem(atPath: stage.path)
        let bytes = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        let rc = stage.path.withCString { from in
            destination.path.withCString { to in
                renamex_np(from, to, UInt32(RENAME_EXCL))
            }
        }
        guard rc == 0 else {
            throw EvidencePackageArchiveError.publishFailed("renamex_np errno \(errno)")
        }
        // The package directory was the verified staging input; it is safe to
        // remove only after the archive was published. Failure here leaves the
        // archive published and reports; it never deletes raw.
        try? fm.removeItem(at: packageDirectory)
        if let wrapper { try? fm.removeItem(at: wrapper) }
        return EvidencePackageArchiveResult(archiveURL: destination, sha256: digest, byteSize: bytes)
    }
}

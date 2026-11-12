import Foundation
import CryptoKit
import RestoreLogEngine

struct SessionZipManifestFile: Codable, Equatable {
    var role: String
    var relativePath: String
    var size: Int64
    var sha256: String
}

struct SessionZipManifest: Codable, Equatable {
    var schemaVersion: Int
    var sessionID: String
    var generatedAt: String
    var appVersion: String
    var exporterAppCDHash: String
    var manifestCoverage: String
    var files: [SessionZipManifestFile]
}

struct SessionZipExportRequest {
    var source: SessionPackageSource
    var destination: URL
    var appVersion: String
    var appCDHash: String
    var generatedAt: Date = Date()
    var zip64Threshold: UInt64 = ZipStoreWriter.defaultZip64Threshold
}

struct SessionZipExportResult {
    var zipURL: URL
    var manifest: SessionZipManifest
    var stats: ZipIOStats
    var entries: [ZipWrittenEntry]
}

enum SessionZipExportError: Error, LocalizedError {
    case notFinalized
    case missingRaw
    case destinationExists(String)
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notFinalized: return "只能从已停止并完成 finalize 的同一会话导出。"
        case .missingRaw: return "缺少已 finalize 的原始日志。"
        case .destinationExists: return "目标文件已存在：请改名或选择其他文件夹；不会静默覆盖。"
        case .cancelled: return "导出已取消"
        case .failed(let m): return m
        }
    }
}

enum SessionZipExporter {
    static let manifestSchemaVersion = 1

    static func export(_ request: SessionZipExportRequest,
                       shouldCancel: () -> Bool = { false },
                       progress: ((String, Double?) -> Void)? = nil) throws -> SessionZipExportResult {
        let source = request.source
        guard source.record.files.contains(where: { $0.role == "raw-log" }) else {
            throw SessionZipExportError.missingRaw
        }
        guard FileManager.default.fileExists(atPath: source.rawURL.path) else {
            throw SessionZipExportError.missingRaw
        }
        if FileManager.default.fileExists(atPath: request.destination.path) {
            throw SessionZipExportError.destinationExists(request.destination.path)
        }

        var packEntries: [ZipEntrySpec] = []

        let rawFile = source.record.files.first { $0.role == "raw-log" }!
        packEntries.append(ZipEntrySpec(
            pathInZip: "logs/restore.log",
            fileURL: source.rawURL,
            data: nil,
            storedSHA256: rawFile.sha256))
        // Manifest entry added after we confirm the streamed hash.

        let evidencePointer = """
        {\n  "role": "raw-log",\n  "relativePath": "logs/restore.log",\n  "size": \(rawFile.byteSize),\n  "sha256": "\(rawFile.sha256)"\n}\n
        """

        // Copy all finalized evidence except the raw-log entity. Rewrite references
        // so they point at logs/restore.log instead of embedding a second copy.
        for file in source.record.files where file.role != "raw-log" {
            let src = source.directory.appendingPathComponent(file.relativePath)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            var data = try Data(contentsOf: src)
            if isTextualEvidence(name: file.relativePath) {
                data = rewriteRawLogReferences(in: data, raw: rawFile)
            }
            let path = "evidence/\(file.relativePath)"
            packEntries.append(ZipEntrySpec(pathInZip: path, fileURL: nil, data: data, storedSHA256: nil))
        }

        let pointerData = Data(evidencePointer.utf8)
        packEntries.append(ZipEntrySpec(pathInZip: "evidence/raw-log-pointer.json", fileURL: nil, data: pointerData, storedSHA256: nil))

        let generatedAt = iso8601(request.generatedAt)
        let readme = """
        MRA Device Control 采集导出

        这是一次已停止并完成 finalize 的采集会话导出包。

        - 完整原始日志：logs/restore.log（包内仅此一份）
        - 证据文件：evidence/（与该次采集同一会话）
        - 会话 ID：\(source.record.sessionID.uuidString)
        - 导出应用版本：\(request.appVersion)
        - 导出应用 CDHash：\(request.appCDHash)

        证据中对原始日志的引用通过相对路径、大小与 SHA-256 指向 logs/restore.log，不再保存第二份同等字节的原始日志。
        MANIFEST.json 列出除其自身以外的全部内容文件（含本 README）。
        """
        packEntries.append(ZipEntrySpec(pathInZip: "README.txt", fileURL: nil, data: Data(readme.utf8), storedSHA256: nil))

        // Placeholder for MANIFEST — built after we know all content hashes.
        // We first hash small in-memory entries; the raw log hash is reused from finalize
        // and confirmed during the single streaming write.
        // Two-phase: write content entries using a writer that returns hashes, but
        // MANIFEST must be inside the same ZIP. Compute hashes of in-memory items now,
        // use finalized raw hash, then add MANIFEST last (no self hash).
        var preFiles: [SessionZipManifestFile] = [
            SessionZipManifestFile(role: "raw-log", relativePath: "logs/restore.log",
                                   size: Int64(rawFile.byteSize), sha256: rawFile.sha256)
        ]
        for entry in packEntries where entry.pathInZip != "logs/restore.log" {
            let data = entry.data ?? Data()
            let sha = sha256hex(data)
            let role = roleForPath(entry.pathInZip)
            preFiles.append(SessionZipManifestFile(role: role, relativePath: entry.pathInZip,
                                                   size: Int64(data.count), sha256: sha))
            if entry.storedSHA256 == nil {
                // stamp computed hash so the writer still verifies
            }
        }
        // Re-stamp in-memory entries with computed hashes for writer verification
        packEntries = packEntries.map { spec in
            var copy = spec
            if let data = spec.data {
                copy.storedSHA256 = sha256hex(data)
            }
            return copy
        }

        let manifest = SessionZipManifest(
            schemaVersion: manifestSchemaVersion,
            sessionID: source.record.sessionID.uuidString,
            generatedAt: generatedAt,
            appVersion: request.appVersion,
            exporterAppCDHash: request.appCDHash,
            manifestCoverage: "MANIFEST.json lists every content file in this archive except itself. It does not include its own hash.",
            files: preFiles.sorted { $0.relativePath < $1.relativePath }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let manifestData = try encoder.encode(manifest)
        packEntries.insert(ZipEntrySpec(pathInZip: "MANIFEST.json", fileURL: nil, data: manifestData, storedSHA256: sha256hex(manifestData)), at: 0)

        if shouldCancel() { throw SessionZipExportError.cancelled }

        let writer = ZipStoreWriter(zip64Threshold: request.zip64Threshold)
        do {
            let written = try writer.write(entries: packEntries, to: request.destination, shouldCancel: shouldCancel, progress: progress)
            // Confirm raw-log hash in the archive matches finalize + manifest.
            if let raw = written.first(where: { $0.pathInZip == "logs/restore.log" }) {
                if raw.sha256 != rawFile.sha256 {
                    try? FileManager.default.removeItem(at: request.destination)
                    throw SessionZipExportError.failed("包内原始日志哈希与 finalize 记录不一致")
                }
            }
            return SessionZipExportResult(zipURL: request.destination, manifest: manifest, stats: writer.stats, entries: written)
        } catch let error as ZipStoreError {
            switch error {
            case .destinationExists(let p): throw SessionZipExportError.destinationExists(p)
            case .cancelled: throw SessionZipExportError.cancelled
            default: throw SessionZipExportError.failed(error.localizedDescription)
            }
        }
    }

    private static func isTextualEvidence(name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".json") || lower.hasSuffix(".txt") || lower.hasSuffix(".md")
            || lower.hasSuffix(".ini") || lower.hasSuffix(".log")
    }

    private static func rewriteRawLogReferences(in data: Data, raw: EvidenceFile) -> Data {
        guard var text = String(data: data, encoding: .utf8) else { return data }
        // Point relative path mentions of the session restore.log entity to logs/restore.log.
        text = text.replacingOccurrences(of: "\"relativePath\" : \"restore.log\"", with: "\"relativePath\" : \"logs/restore.log\"")
        text = text.replacingOccurrences(of: "\"relativePath\":\"restore.log\"", with: "\"relativePath\":\"logs/restore.log\"")
        text = text.replacingOccurrences(of: "  restore.log", with: "  logs/restore.log")
        _ = raw
        return Data(text.utf8)
    }

    private static func roleForPath(_ path: String) -> String {
        if path == "README.txt" { return "readme" }
        if path == "MANIFEST.json" { return "manifest" }
        if path == "logs/restore.log" { return "raw-log" }
        if path == "evidence/raw-log-pointer.json" { return "raw-log-pointer" }
        if path.hasPrefix("evidence/") {
            return "evidence"
        }
        return "other"
    }

    private static func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private static func sha256hex(_ data: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}


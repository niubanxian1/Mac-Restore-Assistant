import Foundation
import CryptoKit

struct RestoreRawExportResult: Equatable {
    let url: URL
    let bytes: Int64
    let sha256: String
}

enum RestoreRawExportError: Error, LocalizedError {
    case noArchive
    case attemptMismatch
    case archiveMissing(String)
    case manifestInvalid(String)
    case archiveChanged(String)
    case destinationInvalid(String)
    case publishFailed(String)

    var errorDescription: String? {
        switch self {
        case .noArchive:
            return "该任务没有可导出的原始日志归档。"
        case .attemptMismatch:
            return "归档不属于该 Restore 任务，已拒绝导出。"
        case .archiveMissing(let path):
            return "找不到归档目录：\(path)"
        case .manifestInvalid(let reason):
            return "归档清单无效：\(reason)"
        case .archiveChanged(let reason):
            return "归档内容与清单不一致：\(reason)"
        case .destinationInvalid(let path):
            return "导出位置不可用：\(path)"
        case .publishFailed(let reason):
            return "导出失败：\(reason)"
        }
    }
}

/// 复用现有归档结构，把 `RestoreArchiveRecord` 的目录原样封装为 ZIP。
/// 不移动/删除归档；导出前后校验清单与文件哈希。
enum RestoreRawArchiveExporter {
    static func export(
        archive: RestoreArchiveRecord,
        attemptID: UUID,
        destination: URL
    ) throws -> RestoreRawExportResult {
        guard archive.attemptID == attemptID else {
            throw RestoreRawExportError.attemptMismatch
        }
        let directory = URL(fileURLWithPath: archive.directoryPath,
                            isDirectory: true)
        let manifestURL = URL(fileURLWithPath: archive.manifestPath)
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path),
              fm.fileExists(atPath: manifestURL.path) else {
            throw RestoreRawExportError.archiveMissing(directory.path)
        }
        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL)
        } catch {
            throw RestoreRawExportError.manifestInvalid(error.localizedDescription)
        }
        guard sha256(manifestData) == archive.manifestSHA256 else {
            throw RestoreRawExportError.manifestInvalid("清单 SHA-256 不符")
        }
        let manifest: RestoreArchiveManifest
        do {
            manifest = try JSONDecoder().decode(
                RestoreArchiveManifest.self,
                from: manifestData)
        } catch {
            throw RestoreRawExportError.manifestInvalid("无法解析清单")
        }
        guard manifest.attemptID == attemptID,
              manifest.archiveID == archive.archiveID else {
            throw RestoreRawExportError.attemptMismatch
        }
        for file in manifest.files {
            let url = directory.appendingPathComponent(file.relativePath)
            guard let data = try? Data(contentsOf: url),
                  Int64(data.count) == file.sizeBytes,
                  sha256(data) == file.sha256 else {
                throw RestoreRawExportError.archiveChanged(file.relativePath)
            }
        }
        let parent = destination.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parent.path) else {
            throw RestoreRawExportError.destinationInvalid(parent.path)
        }
        let temp = parent.appendingPathComponent(
            ".mra-restore-raw-\(UUID().uuidString).zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c", "-k", "--sequesterRsrc", "--keepParent",
            directory.path, temp.path,
        ]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw RestoreRawExportError.publishFailed(error.localizedDescription)
        }
        guard process.terminationStatus == 0,
              let data = try? Data(contentsOf: temp) else {
            try? fm.removeItem(at: temp)
            throw RestoreRawExportError.publishFailed("ZIP 生成失败")
        }
        do {
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: temp, to: destination)
        } catch {
            try? fm.removeItem(at: temp)
            throw RestoreRawExportError.publishFailed(error.localizedDescription)
        }
        return RestoreRawExportResult(
            url: destination,
            bytes: Int64(data.count),
            sha256: sha256(data))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

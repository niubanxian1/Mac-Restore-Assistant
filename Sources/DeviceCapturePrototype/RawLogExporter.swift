import Foundation
import CryptoKit
import Darwin

struct RawLogExportRequest {
    var sourceURL: URL
    var destinationDirectory: URL
    var baseName: String
    var sessionID: UUID
    var isPartial: Bool
    var expectedSourceSHA256: String
}

struct RawLogExportResult: Equatable {
    var url: URL
    var bytes: Int64
    var sha256: String
}

enum RawLogExportError: Error, LocalizedError {
    case sourceMissing(String)
    case sourceChanged
    case sourceDigestMismatch(expected: String, actual: String)
    case destinationUnavailable(String)
    case publishFailed(String)
    case verifyFailed(String)

    var errorDescription: String? {
        switch self {
        case .sourceMissing(let path):
            return "找不到原始日志：\(path)"
        case .sourceChanged:
            return "导出期间原始日志发生变化，已拒绝发布。"
        case .sourceDigestMismatch(let expected, let actual):
            return "原始日志哈希不符（期望 \(expected.prefix(12))…，实际 \(actual.prefix(12))…）"
        case .destinationUnavailable(let path):
            return "导出目录不可用：\(path)"
        case .publishFailed(let reason):
            return "发布原始日志失败：\(reason)"
        case .verifyFailed(let reason):
            return "原始日志副本校验失败：\(reason)"
        }
    }
}

enum RawLogExporter {
    private static let renameExclusive: UInt32 = 0x00000004

    static func export(
        _ request: RawLogExportRequest,
        shouldCancel: @escaping @Sendable () -> Bool = { false },
        progress: (@Sendable (LogExportProgress) -> Void)? = nil
    ) throws -> RawLogExportResult {
        let started = Date()
        let fm = FileManager.default
        guard fm.isReadableFile(atPath: request.sourceURL.path) else {
            throw RawLogExportError.sourceMissing(request.sourceURL.path)
        }
        do {
            try fm.createDirectory(at: request.destinationDirectory, withIntermediateDirectories: true)
        } catch {
            throw RawLogExportError.destinationUnavailable(request.destinationDirectory.path)
        }
        let sourceBefore = identity(of: request.sourceURL)
        let total = sourceBefore.size
        progress?(LogExportProgress(
            operation: .rawLog,
            stage: .validatingRaw,
            processedBytes: 0,
            totalBytes: total,
            elapsedSeconds: 0,
            bytesPerSecond: nil,
            isIndeterminate: false))

        if shouldCancel() { throw CancellationError() }
        let temp = request.destinationDirectory.appendingPathComponent(
            ".mra-raw-export-\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: temp.path, contents: nil) else {
            throw RawLogExportError.destinationUnavailable(temp.path)
        }
        defer {
            if fm.fileExists(atPath: temp.path) {
                try? fm.removeItem(at: temp)
            }
        }
        guard let input = try? FileHandle(forReadingFrom: request.sourceURL),
              let output = try? FileHandle(forWritingTo: temp) else {
            throw RawLogExportError.destinationUnavailable(temp.path)
        }
        defer {
            try? input.close()
            try? output.close()
        }

        var hasher = SHA256()
        var copied: Int64 = 0
        while true {
            if shouldCancel() { throw CancellationError() }
            let chunk = try autoreleasepool {
                try input.read(upToCount: 1024 * 1024) ?? Data()
            }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            try output.write(contentsOf: chunk)
            copied += Int64(chunk.count)
            let elapsed = max(0.000_001, Date().timeIntervalSince(started))
            progress?(LogExportProgress(
                operation: .rawLog,
                stage: .copyingRaw,
                processedBytes: copied,
                totalBytes: total,
                elapsedSeconds: elapsed,
                bytesPerSecond: Double(copied) / elapsed,
                isIndeterminate: false))
        }
        try output.synchronize()
        let actualSource = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actualSource == request.expectedSourceSHA256 else {
            throw RawLogExportError.sourceDigestMismatch(
                expected: request.expectedSourceSHA256, actual: actualSource)
        }
        let sourceAfter = identity(of: request.sourceURL)
        guard sourceBefore == sourceAfter, copied == total else {
            throw RawLogExportError.sourceChanged
        }

        progress?(LogExportProgress(
            operation: .rawLog,
            stage: .verifyingArchive,
            processedBytes: 0,
            totalBytes: copied,
            elapsedSeconds: Date().timeIntervalSince(started),
            bytesPerSecond: nil,
            isIndeterminate: false))
        let copiedSHA = try hashFile(temp) { done in
            if shouldCancel() { throw CancellationError() }
            let elapsed = max(0.000_001, Date().timeIntervalSince(started))
            progress?(LogExportProgress(
                operation: .rawLog,
                stage: .verifyingArchive,
                processedBytes: done,
                totalBytes: copied,
                elapsedSeconds: elapsed,
                bytesPerSecond: Double(copied) / elapsed,
                isIndeterminate: false))
        }
        guard copiedSHA == actualSource else {
            throw RawLogExportError.verifyFailed("临时副本 SHA-256 与来源不一致")
        }
        if shouldCancel() { throw CancellationError() }

        progress?(LogExportProgress(
            operation: .rawLog,
            stage: .publishing,
            processedBytes: copied,
            totalBytes: copied,
            elapsedSeconds: Date().timeIntervalSince(started),
            bytesPerSecond: nil,
            isIndeterminate: true))
        let destination = try uniqueDestination(request: request)
        let rc = temp.path.withCString { from in
            destination.path.withCString { to in
                renamex_np(from, to, renameExclusive)
            }
        }
        guard rc == 0 else {
            throw RawLogExportError.publishFailed("renamex_np errno \(errno)")
        }
        progress?(LogExportProgress(
            operation: .rawLog,
            stage: .complete,
            processedBytes: copied,
            totalBytes: copied,
            elapsedSeconds: Date().timeIntervalSince(started),
            bytesPerSecond: nil,
            isIndeterminate: false))
        return RawLogExportResult(url: destination, bytes: copied, sha256: copiedSHA)
    }

    private struct FileIdentity: Equatable {
        let size: Int64
        let modified: Date?
        let inode: UInt64
    }

    private static func identity(of url: URL) -> FileIdentity {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = attrs?[.modificationDate] as? Date
        var st = stat()
        let inode = url.path.withCString { stat($0, &st) == 0 } ? UInt64(st.st_ino) : 0
        return FileIdentity(size: size, modified: modified, inode: inode)
    }

    private static func hashFile(
        _ url: URL,
        progress: (Int64) throws -> Void
    ) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw RawLogExportError.verifyFailed("无法读取临时副本")
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        var done: Int64 = 0
        while true {
            try progress(done)
            let chunk = try autoreleasepool {
                try handle.read(upToCount: 1024 * 1024) ?? Data()
            }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            done += Int64(chunk.count)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func uniqueDestination(request: RawLogExportRequest) throws -> URL {
        let base = sanitizedBase(request.baseName)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let session = String(request.sessionID.uuidString.prefix(8)).uppercased()
        let tail = request.isPartial ? "_PARTIAL" : ""
        let stem = "\(base)_\(formatter.string(from: Date()))_\(session)\(tail)"
        for index in 1...999 {
            let name = index == 1 ? "\(stem).log" : "\(stem)-\(index).log"
            let candidate = request.destinationDirectory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        throw RawLogExportError.publishFailed("同名日志过多，未覆盖任何文件")
    }

    private static func sanitizedBase(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasSuffix(".log") { text.removeLast(4) }
        if text.isEmpty { text = "MRA-Restore" }
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        text = text.components(separatedBy: bad).joined(separator: "_")
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))
        return String(text.prefix(80))
    }
}

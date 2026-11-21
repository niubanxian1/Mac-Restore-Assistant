import Foundation
import Combine

@MainActor
final class LogWorkspacePreferences: ObservableObject {
    private enum Key {
        static let autoMonitor = "MRA.log.autoMonitorRestore"
        static let rawDirectory = "MRA.log.rawExportDirectory"
        static let packageDirectory = "MRA.log.evidencePackageDirectory"
        static let defaultBaseName = "MRA.log.defaultBaseName"
        static let previewAutoScroll = "MRA.log.previewAutoScroll"
        static let previewLineLimit = "MRA.log.previewLineLimit"
    }

    @Published var autoMonitorEnabled: Bool {
        didSet { defaults.set(autoMonitorEnabled, forKey: Key.autoMonitor) }
    }
    @Published var rawLogDirectory: String {
        didSet { defaults.set(rawLogDirectory, forKey: Key.rawDirectory) }
    }
    @Published var evidencePackageDirectory: String {
        didSet { defaults.set(evidencePackageDirectory, forKey: Key.packageDirectory) }
    }
    @Published var defaultFileBaseName: String {
        didSet { defaults.set(defaultFileBaseName, forKey: Key.defaultBaseName) }
    }
    @Published var previewAutoScroll: Bool {
        didSet { defaults.set(previewAutoScroll, forKey: Key.previewAutoScroll) }
    }
    @Published var previewLineLimit: Int {
        didSet {
            let clamped = min(1000, max(20, previewLineLimit))
            if clamped != previewLineLimit {
                previewLineLimit = clamped
                return
            }
            defaults.set(previewLineLimit, forKey: Key.previewLineLimit)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, startingRoot: URL? = nil) {
        self.defaults = defaults
        let root = startingRoot
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        autoMonitorEnabled = defaults.object(forKey: Key.autoMonitor) as? Bool ?? false
        rawLogDirectory = defaults.string(forKey: Key.rawDirectory)
            ?? root.appendingPathComponent("牛半仙日志/原始日志", isDirectory: true).path
        evidencePackageDirectory = defaults.string(forKey: Key.packageDirectory)
            ?? root.appendingPathComponent("牛半仙日志/证据包", isDirectory: true).path
        defaultFileBaseName = defaults.string(forKey: Key.defaultBaseName) ?? "MRA-Restore"
        previewAutoScroll = defaults.object(forKey: Key.previewAutoScroll) as? Bool ?? true
        previewLineLimit = defaults.object(forKey: Key.previewLineLimit) as? Int ?? 240
    }
}

struct IncrementalLogProjectionSnapshot: Equatable, Sendable {
    let byteCount: Int
    let lineCount: Int
    let previewLines: [String]
    let available: Bool
}

/// Cursor-based read-only projection for one growing raw log.
///
/// The UI timer only consumes bytes appended since the previous look. It never
/// reclassifies the whole file and never advances the capture coordinator state.
actor IncrementalLogProjection {
    private struct Cursor {
        var offset = 0
        var lineCount = 0
        var carry = Data()
        var previewLines: [String] = []
    }

    private var cursors: [String: Cursor] = [:]

    func snapshot(path: URL, maxPreviewLines: Int) -> IncrementalLogProjectionSnapshot {
        let key = path.standardizedFileURL.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: key),
              let sizeNumber = attrs[.size] as? NSNumber else {
            return IncrementalLogProjectionSnapshot(
                byteCount: 0, lineCount: 0, previewLines: [], available: false)
        }
        let size = sizeNumber.intValue
        var cursor = cursors[key] ?? Cursor()
        if size < cursor.offset {
            cursor = Cursor()
        }
        guard let handle = try? FileHandle(forReadingFrom: path) else {
            return IncrementalLogProjectionSnapshot(
                byteCount: size,
                lineCount: cursor.lineCount,
                previewLines: cursor.previewLines,
                available: false)
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: UInt64(cursor.offset))
            var remaining = size - cursor.offset
            while remaining > 0 {
                let count = min(remaining, 1024 * 1024)
                guard let chunk = try autoreleasepool(invoking: {
                    try handle.read(upToCount: count)
                }), !chunk.isEmpty else {
                    throw CocoaError(.fileReadUnknown)
                }
                cursor.offset += chunk.count
                remaining -= chunk.count
                cursor.carry.append(chunk)
                consumeCompleteLines(
                    cursor: &cursor,
                    maxPreviewLines: max(1, maxPreviewLines))
                if cursor.carry.count > 8 * 1024 * 1024 {
                    // A pathological single line is preview-truncated but still
                    // counted in full by byteCount; raw evidence remains untouched.
                    cursor.carry = Data(cursor.carry.suffix(64 * 1024))
                }
            }
            cursor.previewLines = Array(cursor.previewLines.suffix(max(1, maxPreviewLines)))
            cursors[key] = cursor
            return IncrementalLogProjectionSnapshot(
                byteCount: size,
                lineCount: cursor.lineCount,
                previewLines: cursor.previewLines,
                available: true)
        } catch {
            return IncrementalLogProjectionSnapshot(
                byteCount: size,
                lineCount: cursor.lineCount,
                previewLines: cursor.previewLines,
                available: false)
        }
    }

    func forget(path: URL) {
        cursors[path.standardizedFileURL.path] = nil
    }

    private func consumeCompleteLines(cursor: inout Cursor, maxPreviewLines: Int) {
        while let newline = cursor.carry.firstIndex(of: 0x0A) {
            let lineData = cursor.carry[..<newline]
            cursor.carry = Data(cursor.carry[cursor.carry.index(after: newline)...])
            cursor.lineCount += 1
            let line = String(decoding: lineData, as: UTF8.self)
            cursor.previewLines.append(line)
            if cursor.previewLines.count > maxPreviewLines * 2 {
                cursor.previewLines.removeFirst(cursor.previewLines.count - maxPreviewLines)
            }
        }
    }
}

enum LogExportOperation: String, Sendable, Hashable {
    case rawLog
    case evidencePackage
}

enum LogExportStage: String, Sendable {
    case preparing
    case validatingRaw
    case copyingRaw
    case generatingAttachments
    case writingMetadata
    case packagingZIP
    case verifyingArchive
    case publishing
    case complete
    case failed
    case cancelled

    var displayName: String {
        switch self {
        case .preparing: return "准备导出"
        case .validatingRaw: return "校验原始日志"
        case .copyingRaw: return "复制原始日志"
        case .generatingAttachments: return "生成诊断附件"
        case .writingMetadata: return "生成哈希与元数据"
        case .packagingZIP: return "封装 ZIP"
        case .verifyingArchive: return "验证 ZIP"
        case .publishing: return "发布文件"
        case .complete: return "完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }
}

struct LogExportProgress: Equatable, Sendable {
    var operation: LogExportOperation
    var stage: LogExportStage
    var processedBytes: Int64?
    var totalBytes: Int64?
    var elapsedSeconds: Double
    var bytesPerSecond: Double?
    var isIndeterminate: Bool
    var message: String = ""

    var fraction: Double? {
        guard !isIndeterminate,
              let processedBytes,
              let totalBytes,
              totalBytes > 0 else { return nil }
        return min(1, max(0, Double(processedBytes) / Double(totalBytes)))
    }
}

final class ExportCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

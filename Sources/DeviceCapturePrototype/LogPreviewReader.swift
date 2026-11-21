import Foundation

struct LogPreviewSnapshot: Equatable {
    var lines: [String]
    var truncated: Bool
    var sourceBytes: Int
}

enum LogPreviewReader {
    static let defaultMaxBytes = 256 * 1024
    static let defaultMaxLines = 200

    /// Bounded tail read. Does not load the whole file into a String.
    static func tail(url: URL,
                     maxBytes: Int = defaultMaxBytes,
                     maxLines: Int = defaultMaxLines) -> LogPreviewSnapshot {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return LogPreviewSnapshot(lines: [], truncated: false, sourceBytes: 0)
        }
        defer { try? handle.close() }
        let size: Int
        do {
            let end = try handle.seekToEnd()
            size = Int(end)
        } catch {
            return LogPreviewSnapshot(lines: [], truncated: false, sourceBytes: 0)
        }
        if size == 0 {
            return LogPreviewSnapshot(lines: [], truncated: false, sourceBytes: 0)
        }
        let window = min(maxBytes, size)
        let start = UInt64(size - window)
        do { try handle.seek(toOffset: start) } catch {
            return LogPreviewSnapshot(lines: [], truncated: size > 0, sourceBytes: size)
        }
        let data = handle.readData(ofLength: window)
        var payload = data
        var truncated = start > 0
        if start > 0, let firstNL = payload.firstIndex(of: 0x0A) {
            payload = payload.dropFirst(firstNL + 1)
            truncated = true
        } else if start > 0 {
            // Mid-character / mid-line start without a newline; do not pretend this is complete.
            truncated = true
        }
        let text = String(decoding: payload, as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        if lines.count > maxLines {
            lines = Array(lines.suffix(maxLines))
            truncated = true
        }
        return LogPreviewSnapshot(lines: lines, truncated: truncated, sourceBytes: size)
    }
}

import Foundation
import CryptoKit
import Darwin

/// Independent, read-only integrity checks. These never trust the write path
/// that produced the file: they re-open it and hash the bytes on disk.
public enum Integrity {
    public static func sha256(ofFileAt url: URL) throws -> String {
        try sha256(ofFileAt: url, progress: nil)
    }

    /// Streaming SHA-256 with optional real byte progress. The chunk remains
    /// bounded at 1 MiB; progress is reported at most once per chunk.
    public static func sha256(
        ofFileAt url: URL,
        progress: (@Sendable (Int64, Int64) -> Void)?
    ) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let total = Int64((attrs?[.size] as? NSNumber)?.int64Value ?? 0)
        var hasher = SHA256()
        var done: Int64 = 0
        progress?(0, total)
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            done += Int64(chunk.count)
            progress?(done, total)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func byteSize(ofFileAt url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }

    /// P0-10: stream line count — never `Data(contentsOf:)` whole file into RSS.
    public static func lineCount(ofFileAt url: URL) throws -> Int {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var lines = 0
        var pending = false
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            if chunk.isEmpty { continue }
            let found: (newlines: Int, lastByte: UInt8) = chunk.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return (0, 0) }
                var p = base
                var remaining = raw.count
                var count = 0
                while remaining > 0 {
                    guard let hit = memchr(p, 0x0A, remaining) else { break }
                    count += 1
                    let hitPtr = UnsafeRawPointer(hit)
                    let advance = Int(bitPattern: hitPtr) - Int(bitPattern: p) + 1
                    p = hitPtr.advanced(by: 1)
                    remaining -= advance
                }
                return (count, raw.last ?? 0)
            }
            lines += found.newlines
            pending = found.lastByte != 0x0A
        }
        if pending { lines += 1 }
        return lines
    }

    /// Stream lines, retaining at most `maxRetainBytes` per line unless
    /// `shouldRetainFull` returns true for the retained prefix (then buffer up to maxLineBytes).
    /// P0-10 RSS: uses a reusable read buffer (no per-chunk `Data`) and skips long noise tails.
    public static func forEachLineDataBounded(
        url: URL,
        bufferSize: Int = 1 << 20,
        maxLineBytes: Int = 1 << 20,
        maxRetainBytes: Int,
        shouldRetainFull: (_ prefix: UnsafeRawBufferPointer) -> Bool,
        onLine: (_ lineNumber: Int, _ lineBytes: UnsafeRawBufferPointer, _ fullByteCount: Int) throws -> Void
    ) throws {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { throw CocoaError(.fileReadNoPermission) }
        defer { close(fd) }
        // Hint the kernel not to keep the file in the local buffer cache of this fd.
        _ = fcntl(fd, F_NOCACHE, 1)

        let readBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { readBuf.deallocate() }

        var lineBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: max(maxRetainBytes, 1))
        var lineCap = max(maxRetainBytes, 1)
        defer { lineBuf.deallocate() }
        var lineLen = 0
        var fullCount = 0
        var retainingFull = false
        var skippingTail = false
        var lineNo = 0

        func ensureLineCap(_ need: Int) {
            guard need > lineCap else { return }
            var newCap = lineCap
            while newCap < need { newCap *= 2 }
            let nb = UnsafeMutablePointer<UInt8>.allocate(capacity: newCap)
            if lineLen > 0 {
                nb.assign(from: lineBuf, count: lineLen)
            }
            lineBuf.deallocate()
            lineBuf = nb
            lineCap = newCap
        }

        func emit() throws {
            lineNo += 1
            let view = UnsafeRawBufferPointer(start: lineBuf, count: lineLen)
            try onLine(lineNo, view, fullCount)
            lineLen = 0
            fullCount = 0
            retainingFull = false
            skippingTail = false
        }

        /// P0-10/006: bulk memchr/memcpy path — same semantics as prior per-byte consume,
        /// but avoids Swift debug per-byte call overhead on multi‑MiB lines.
        func consumeRange(_ base: UnsafePointer<UInt8>, _ len: Int) throws {
            var i = 0
            while i < len {
                if skippingTail {
                    // Count until NL without retaining.
                    if let nl = memchr(base + i, Int32(0x0A), len - i) {
                        let off = UnsafePointer<UInt8>(nl.assumingMemoryBound(to: UInt8.self)) - (base + i)
                        fullCount += off
                        if fullCount > maxLineBytes {
                            throw DiagnosticResourceError.lineTooLong(line: lineNo + 1, bytes: fullCount, limit: maxLineBytes)
                        }
                        i += off
                        // NL
                        if fullCount > maxLineBytes {
                            throw DiagnosticResourceError.lineTooLong(line: lineNo + 1, bytes: fullCount, limit: maxLineBytes)
                        }
                        try emit()
                        i += 1
                        continue
                    } else {
                        fullCount += (len - i)
                        if fullCount > maxLineBytes {
                            throw DiagnosticResourceError.lineTooLong(line: lineNo + 1, bytes: fullCount, limit: maxLineBytes)
                        }
                        return
                    }
                }

                // Find next NL in remaining input.
                let remain = len - i
                let nlPtr = memchr(base + i, Int32(0x0A), remain)
                let chunkEnd: Int
                let hitNL: Bool
                if let nl = nlPtr {
                    chunkEnd = UnsafePointer<UInt8>(nl.assumingMemoryBound(to: UInt8.self)) - (base + i)
                    hitNL = true
                } else {
                    chunkEnd = remain
                    hitNL = false
                }

                var pos = 0
                while pos < chunkEnd {
                    if retainingFull {
                        let take = chunkEnd - pos
                        ensureLineCap(lineLen + take)
                        memcpy(lineBuf + lineLen, base + i + pos, take)
                        lineLen += take
                        fullCount += take
                        if fullCount > maxLineBytes {
                            throw DiagnosticResourceError.lineTooLong(line: lineNo + 1, bytes: fullCount, limit: maxLineBytes)
                        }
                        pos = chunkEnd
                        break
                    }
                    // Filling toward maxRetainBytes
                    let room = maxRetainBytes - lineLen
                    if room <= 0 {
                        // Should have decided retain/skip already; treat as skip.
                        skippingTail = true
                        break
                    }
                    let take = min(room, chunkEnd - pos)
                    memcpy(lineBuf + lineLen, base + i + pos, take)
                    lineLen += take
                    fullCount += take
                    if fullCount > maxLineBytes {
                        throw DiagnosticResourceError.lineTooLong(line: lineNo + 1, bytes: fullCount, limit: maxLineBytes)
                    }
                    pos += take
                    if lineLen == maxRetainBytes {
                        let prefix = UnsafeRawBufferPointer(start: lineBuf, count: lineLen)
                        if shouldRetainFull(prefix) {
                            retainingFull = true
                        } else {
                            skippingTail = true
                            // Remaining bytes in this chunk before NL are tail — count only.
                            let tail = chunkEnd - pos
                            if tail > 0 {
                                fullCount += tail
                                if fullCount > maxLineBytes {
                                    throw DiagnosticResourceError.lineTooLong(line: lineNo + 1, bytes: fullCount, limit: maxLineBytes)
                                }
                                pos = chunkEnd
                            }
                            break
                        }
                    }
                }

                i += chunkEnd
                if hitNL {
                    if fullCount > maxLineBytes {
                        throw DiagnosticResourceError.lineTooLong(line: lineNo + 1, bytes: fullCount, limit: maxLineBytes)
                    }
                    try emit()
                    i += 1
                }
            }
        }

        while true {
            let n = read(fd, readBuf, bufferSize)
            if n < 0 {
                throw CocoaError(.fileReadUnknown)
            }
            if n == 0 { break }
            try consumeRange(readBuf, n)
        }
        if fullCount > 0 || lineLen > 0 {
            if fullCount > maxLineBytes {
                throw DiagnosticResourceError.lineTooLong(line: lineNo + 1, bytes: fullCount, limit: maxLineBytes)
            }
            try emit()
        }
    }

    /// Stream each complete UTF-8 line as raw bytes (1-based). Throws on oversize line.
    /// P0-10: reuses one growable line buffer and a fixed read buffer (no per-chunk `Data`).
    public static func forEachLineData(
        url: URL,
        bufferSize: Int = 1 << 20,
        maxLineBytes: Int = 1 << 20,
        onLine: (_ lineNumber: Int, _ lineBytes: UnsafeRawBufferPointer) throws -> Void
    ) throws {
        try forEachLineDataBounded(
            url: url,
            bufferSize: bufferSize,
            maxLineBytes: maxLineBytes,
            maxRetainBytes: maxLineBytes,
            shouldRetainFull: { _ in true },
            onLine: { lineNo, bytes, _ in try onLine(lineNo, bytes) }
        )
    }

    /// Stream each complete UTF-8 line (1-based). Throws on oversize line.
    public static func forEachLine(
        url: URL,
        bufferSize: Int = 1 << 20,
        maxLineBytes: Int = 1 << 20,
        onLine: (_ lineNumber: Int, _ line: String) throws -> Void
    ) throws {
        try forEachLineData(url: url, bufferSize: bufferSize, maxLineBytes: maxLineBytes) { lineNo, lineBytes in
            try onLine(lineNo, String(decoding: lineBytes, as: UTF8.self))
        }
    }
}

/// P0-10 resource hard-fail surface for diagnostic streaming.
public enum DiagnosticResourceError: Error, CustomStringConvertible, Sendable {
    case rawTooLarge(bytes: Int, limit: Int)
    case lineTooLong(line: Int, bytes: Int, limit: Int)
    case timeBudgetExceeded(seconds: Double, limit: Double)
    case cancelled

    public var description: String {
        switch self {
        case let .rawTooLarge(b, lim): return "rawTooLarge bytes=\(b) limit=\(lim)"
        case let .lineTooLong(l, b, lim): return "lineTooLong line=\(l) bytes=\(b) limit=\(lim)"
        case let .timeBudgetExceeded(s, lim): return "timeBudgetExceeded seconds=\(s) limit=\(lim)"
        case .cancelled: return "cancelled"
        }
    }
}

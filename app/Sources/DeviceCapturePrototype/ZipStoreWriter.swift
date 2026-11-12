import Foundation
import CryptoKit
import zlib

struct ZipIOStats: Equatable {
    var sourceBytesRead: Int64 = 0
    var diskBytesWritten: Int64 = 0
    var verifyBytesRead: Int64 = 0
    var sourceReadPasses: Int = 0
    var archiveWritePasses: Int = 0
    var verifyReadPasses: Int = 0
}

struct ZipEntrySpec {
    var pathInZip: String
    var fileURL: URL?
    var data: Data?
    var storedSHA256: String? // if known, verified during the single source read
}

struct ZipWrittenEntry: Equatable {
    var pathInZip: String
    var size: Int64
    var sha256: String
    var crc32: UInt32
}

enum ZipStoreError: Error, LocalizedError {
    case destinationExists(String)
    case cancelled
    case sourceMissing(String)
    case hashMismatch(String)
    case writeFailed(String)
    case verifyFailed(String)
    case publishFailed(String)
    case unsupportedName(String)

    var errorDescription: String? {
        switch self {
        case .destinationExists(let p): return "目标已存在，未覆盖：\(p)"
        case .cancelled: return "导出已取消"
        case .sourceMissing(let p): return "找不到源文件：\(p)"
        case .hashMismatch(let p): return "封装过程中哈希不一致：\(p)"
        case .writeFailed(let m): return "写入失败：\(m)"
        case .verifyFailed(let m): return "ZIP 校验失败：\(m)"
        case .publishFailed(let m): return "提交失败：\(m)"
        case .unsupportedName(let n): return "不支持的条目名：\(n)"
        }
    }
}

/// Streaming ZIP writer. Entries are stored (method 0). ZIP64 is used when a
/// size or offset meets `zip64Threshold` (default 4 GiB).
final class ZipStoreWriter {
    static let defaultZip64Threshold: UInt64 = 4_294_967_295
    private static let RENAME_EXCL: Int32 = 0x00000004

    var zip64Threshold: UInt64
    private(set) var stats = ZipIOStats()

    init(zip64Threshold: UInt64 = ZipStoreWriter.defaultZip64Threshold) {
        self.zip64Threshold = zip64Threshold
    }

    @discardableResult
    func write(entries: [ZipEntrySpec],
               to destination: URL,
               shouldCancel: () -> Bool = { false },
               progress: ((String, Double?) -> Void)? = nil) throws -> [ZipWrittenEntry] {
        stats = ZipIOStats()
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else {
            throw ZipStoreError.destinationExists(destination.path)
        }
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let temp = parent.appendingPathComponent(".mra-export-\(UUID().uuidString).zip.tmp")
        do {
            let result = try writeTemporary(entries: entries, temp: temp, shouldCancel: shouldCancel, progress: progress)
            if shouldCancel() {
                try? fm.removeItem(at: temp)
                throw ZipStoreError.cancelled
            }
            progress?("正在验证", nil)
            try ZipStoreReader.verify(archive: temp, expected: result, stats: &stats)
            if shouldCancel() {
                try? fm.removeItem(at: temp)
                throw ZipStoreError.cancelled
            }
            let rc = temp.path.withCString { from in
                destination.path.withCString { to in
                    renamex_np(from, to, UInt32(Self.RENAME_EXCL))
                }
            }
            if rc != 0 {
                try? fm.removeItem(at: temp)
                if errno == EEXIST {
                    throw ZipStoreError.destinationExists(destination.path)
                }
                throw ZipStoreError.publishFailed("renamex_np errno \(errno)")
            }
            return result
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    private struct CentralItem {
        var name: Data
        var crc: UInt32
        var size: UInt64
        var localOffset: UInt64
        var sha256: String
    }

    private func writeTemporary(entries: [ZipEntrySpec],
                                temp: URL,
                                shouldCancel: () -> Bool,
                                progress: ((String, Double?) -> Void)?) throws -> [ZipWrittenEntry] {
        FileManager.default.createFile(atPath: temp.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: temp) else {
            throw ZipStoreError.writeFailed("无法创建临时 ZIP")
        }
        defer { try? handle.close() }
        stats.archiveWritePasses += 1
        var central: [CentralItem] = []
        var written: [ZipWrittenEntry] = []
        for (index, entry) in entries.enumerated() {
            if shouldCancel() { throw ZipStoreError.cancelled }
            progress?("正在封装", entries.isEmpty ? nil : Double(index) / Double(entries.count))
            let nameData = try utf8Name(entry.pathInZip)
            let localOffset = try currentOffset(handle)
            let (size, crc, sha) = try writeLocalEntry(entry: entry, name: nameData, handle: handle, shouldCancel: shouldCancel)
            central.append(CentralItem(name: nameData, crc: crc, size: size, localOffset: localOffset, sha256: sha))
            written.append(ZipWrittenEntry(pathInZip: entry.pathInZip, size: Int64(size), sha256: sha, crc32: crc))
        }
        let cdStart = try currentOffset(handle)
        for item in central {
            try writeCentralDirectory(item: item, handle: handle)
        }
        let cdSize = try currentOffset(handle) - cdStart
        try writeEndRecords(count: UInt64(central.count), cdSize: cdSize, cdStart: cdStart, handle: handle)
        try handle.synchronize()
        return written
    }

    private func utf8Name(_ path: String) throws -> Data {
        if path.isEmpty || path.hasPrefix("/") || path.contains("..") {
            throw ZipStoreError.unsupportedName(path)
        }
        guard let data = path.data(using: .utf8) else { throw ZipStoreError.unsupportedName(path) }
        return data
    }

    private func currentOffset(_ handle: FileHandle) throws -> UInt64 {
        try handle.offset()
    }

    private func writeLocalEntry(entry: ZipEntrySpec,
                                 name: Data,
                                 handle: FileHandle,
                                 shouldCancel: () -> Bool) throws -> (UInt64, UInt32, String) {
        let sourceURL = entry.fileURL
        let sourceData = entry.data
        let declaredSize: UInt64
        if let sourceURL {
            let attrs = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
            declaredSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        } else if let sourceData {
            declaredSize = UInt64(sourceData.count)
        } else {
            throw ZipStoreError.sourceMissing(entry.pathInZip)
        }
        let useZIP64 = declaredSize > zip64Threshold
        var local = Data()
        local.appendUInt32(0x04034b50)
        local.appendUInt16(useZIP64 ? 45 : 20)
        local.appendUInt16(1 << 11) // UTF-8 name
        local.appendUInt16(0) // stored
        local.appendUInt16(0) // time
        local.appendUInt16(0) // date
        // CRC and sizes filled after data if we used a placeholder; we know size, but not CRC yet.
        // Write a placeholder header, stream data, then patch CRC/sizes.
        let crcPlaceholder = local.count
        local.appendUInt32(0)
        if useZIP64 {
            local.appendUInt32(0xFFFFFFFF)
            local.appendUInt32(0xFFFFFFFF)
        } else {
            local.appendUInt32(UInt32(declaredSize))
            local.appendUInt32(UInt32(declaredSize))
        }
        local.appendUInt16(UInt16(name.count))
        let extra: Data = useZIP64 ? zip64Extra(size: declaredSize, offset: nil) : Data()
        local.appendUInt16(UInt16(extra.count))
        local.append(name)
        local.append(extra)
        try handle.write(contentsOf: local)
        stats.diskBytesWritten += Int64(local.count)

        var crc: UInt32 = 0
        var hasher = SHA256()
        var copied: UInt64 = 0
        if let sourceURL {
            stats.sourceReadPasses += 1
            guard let reader = try? FileHandle(forReadingFrom: sourceURL) else {
                throw ZipStoreError.sourceMissing(sourceURL.path)
            }
            defer { try? reader.close() }
            while true {
                if shouldCancel() { throw ZipStoreError.cancelled }
                let chunk = reader.readData(ofLength: 1024 * 1024)
                if chunk.isEmpty { break }
                crc = crc32update(crc, chunk)
                hasher.update(data: chunk)
                try handle.write(contentsOf: chunk)
                copied += UInt64(chunk.count)
                stats.sourceBytesRead += Int64(chunk.count)
                stats.diskBytesWritten += Int64(chunk.count)
            }
        } else if let sourceData {
            crc = crc32update(0, sourceData)
            hasher.update(data: sourceData)
            try handle.write(contentsOf: sourceData)
            copied = UInt64(sourceData.count)
            stats.diskBytesWritten += Int64(sourceData.count)
        }
        if copied != declaredSize {
            throw ZipStoreError.writeFailed("\(entry.pathInZip) 大小在封装期间发生变化")
        }
        let sha = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        if let expected = entry.storedSHA256, expected != sha {
            throw ZipStoreError.hashMismatch(entry.pathInZip)
        }
        // Patch CRC in the local header.
        let headerStart = try currentOffset(handle) - copied - UInt64(local.count)
        try handle.seek(toOffset: headerStart + UInt64(crcPlaceholder))
        var patch = Data(); patch.appendUInt32(crc)
        try handle.write(contentsOf: patch)
        try handle.seekToEnd()
        return (copied, crc, sha)
    }

    private func zip64Extra(size: UInt64, offset: UInt64?) -> Data {
        var extra = Data()
        extra.appendUInt16(0x0001)
        var body = Data()
        body.appendUInt64(size)
        body.appendUInt64(size)
        if let offset {
            body.appendUInt64(offset)
        }
        extra.appendUInt16(UInt16(body.count))
        extra.append(body)
        return extra
    }

    private func writeCentralDirectory(item: CentralItem, handle: FileHandle) throws {
        let useZIP64 = item.size > zip64Threshold || item.localOffset > zip64Threshold
        var data = Data()
        data.appendUInt32(0x02014b50)
        data.appendUInt16(useZIP64 ? 45 : 20) // made by
        data.appendUInt16(useZIP64 ? 45 : 20) // needed
        data.appendUInt16(1 << 11)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt32(item.crc)
        if useZIP64 {
            data.appendUInt32(0xFFFFFFFF)
            data.appendUInt32(0xFFFFFFFF)
        } else {
            data.appendUInt32(UInt32(item.size))
            data.appendUInt32(UInt32(item.size))
        }
        data.appendUInt16(UInt16(item.name.count))
        let extra: Data = useZIP64 ? zip64Extra(size: item.size, offset: item.localOffset > zip64Threshold || item.size > zip64Threshold ? item.localOffset : nil) : Data()
        // Always include offset in CD ZIP64 extra when using ZIP64.
        let cdExtra: Data
        if useZIP64 {
            var body = Data()
            body.appendUInt64(item.size)
            body.appendUInt64(item.size)
            body.appendUInt64(item.localOffset)
            var extra = Data()
            extra.appendUInt16(0x0001)
            extra.appendUInt16(UInt16(body.count))
            extra.append(body)
            cdExtra = extra
        } else {
            cdExtra = Data()
        }
        data.appendUInt16(UInt16(cdExtra.count))
        data.appendUInt16(0) // comment
        data.appendUInt16(0) // disk
        data.appendUInt16(0) // int attr
        data.appendUInt32(0) // ext attr
        data.appendUInt32(useZIP64 ? 0xFFFFFFFF : UInt32(item.localOffset))
        data.append(item.name)
        data.append(cdExtra)
        try handle.write(contentsOf: data)
        stats.diskBytesWritten += Int64(data.count)
        _ = extra
    }

    private func writeEndRecords(count: UInt64, cdSize: UInt64, cdStart: UInt64, handle: FileHandle) throws {
        let needZIP64 = count > 0xFFFF || cdSize > zip64Threshold || cdStart > zip64Threshold
        if needZIP64 {
            let eocd64Offset = try currentOffset(handle)
            var rec = Data()
            rec.appendUInt32(0x06064b50)
            rec.appendUInt64(44) // size of remaining record
            rec.appendUInt16(45)
            rec.appendUInt16(45)
            rec.appendUInt32(0)
            rec.appendUInt32(0)
            rec.appendUInt64(count)
            rec.appendUInt64(count)
            rec.appendUInt64(cdSize)
            rec.appendUInt64(cdStart)
            try handle.write(contentsOf: rec)
            stats.diskBytesWritten += Int64(rec.count)
            var loc = Data()
            loc.appendUInt32(0x07064b50)
            loc.appendUInt32(0)
            loc.appendUInt64(eocd64Offset)
            loc.appendUInt32(1)
            try handle.write(contentsOf: loc)
            stats.diskBytesWritten += Int64(loc.count)
        }
        var end = Data()
        end.appendUInt32(0x06054b50)
        end.appendUInt16(0)
        end.appendUInt16(0)
        end.appendUInt16(needZIP64 ? 0xFFFF : UInt16(count))
        end.appendUInt16(needZIP64 ? 0xFFFF : UInt16(count))
        end.appendUInt32(needZIP64 ? 0xFFFFFFFF : UInt32(cdSize))
        end.appendUInt32(needZIP64 ? 0xFFFFFFFF : UInt32(cdStart))
        end.appendUInt16(0)
        try handle.write(contentsOf: end)
        stats.diskBytesWritten += Int64(end.count)
    }
}

enum ZipStoreReader {
    static func verify(archive: URL, expected: [ZipWrittenEntry], stats: inout ZipIOStats) throws {
        stats.verifyReadPasses += 1
        let list = try listEntries(archive: archive, stats: &stats, hashContents: true)
        if list.count != expected.count {
            throw ZipStoreError.verifyFailed("条目数量不符：\(list.count) vs \(expected.count)")
        }
        for (got, exp) in zip(list, expected) {
            if got.pathInZip != exp.pathInZip || got.size != exp.size || got.sha256 != exp.sha256 {
                throw ZipStoreError.verifyFailed("条目不符：\(got.pathInZip)")
            }
        }
    }

    static func listEntries(archive: URL, stats: inout ZipIOStats, hashContents: Bool) throws -> [ZipWrittenEntry] {
        guard let handle = try? FileHandle(forReadingFrom: archive) else {
            throw ZipStoreError.verifyFailed("无法读取 ZIP")
        }
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        // Find EOCD: last 22+ bytes. Search back a small window (no comment in our writer).
        let window = min(size, UInt64(22 + 1024))
        try handle.seek(toOffset: size - window)
        let tail = handle.readDataToEndOfFile()
        stats.verifyBytesRead += Int64(tail.count)
        guard let eocdAt = lastOccurrence(of: 0x06054b50, in: tail) else {
            throw ZipStoreError.verifyFailed("找不到 EOCD")
        }
        let eocd = tail.subdata(in: eocdAt..<(eocdAt + 22))
        var cdStart: UInt64 = UInt64(eocd.u32(16))
        var cdSize: UInt64 = UInt64(eocd.u32(12))
        var count: UInt64 = UInt64(eocd.u16(10))
        if cdStart == 0xFFFFFFFF || cdSize == 0xFFFFFFFF || count == 0xFFFF {
            // ZIP64 locator is immediately before EOCD
            let locatorStart = (size - window) + UInt64(eocdAt) - 20
            try handle.seek(toOffset: locatorStart)
            let loc = handle.readData(ofLength: 20)
            stats.verifyBytesRead += Int64(loc.count)
            guard loc.u32(0) == 0x07064b50 else { throw ZipStoreError.verifyFailed("找不到 ZIP64 locator") }
            let eocd64 = loc.u64(8)
            try handle.seek(toOffset: eocd64)
            let rec = handle.readData(ofLength: 56)
            stats.verifyBytesRead += Int64(rec.count)
            guard rec.u32(0) == 0x06064b50 else { throw ZipStoreError.verifyFailed("找不到 ZIP64 EOCD") }
            count = rec.u64(32)
            cdSize = rec.u64(40)
            cdStart = rec.u64(48)
        }
        try handle.seek(toOffset: cdStart)
        let cd = handle.readData(ofLength: Int(cdSize))
        stats.verifyBytesRead += Int64(cd.count)
        var entries: [ZipWrittenEntry] = []
        var offset = 0
        for _ in 0..<count {
            guard cd.u32(offset) == 0x02014b50 else { throw ZipStoreError.verifyFailed("中央目录签名错误") }
            let flags = cd.u16(offset + 8)
            _ = flags
            let method = cd.u16(offset + 10)
            let crc = cd.u32(offset + 16)
            var comp = UInt64(cd.u32(offset + 20))
            var uncomp = UInt64(cd.u32(offset + 24))
            let nameLen = Int(cd.u16(offset + 28))
            let extraLen = Int(cd.u16(offset + 30))
            let commentLen = Int(cd.u16(offset + 32))
            var localOff = UInt64(cd.u32(offset + 42))
            let name = String(data: cd.subdata(in: (offset + 46)..<(offset + 46 + nameLen)), encoding: .utf8) ?? ""
            let extra = cd.subdata(in: (offset + 46 + nameLen)..<(offset + 46 + nameLen + extraLen))
            parseZip64Extra(extra, size: &uncomp, compressed: &comp, localOffset: &localOff)
            if method != 0 {
                throw ZipStoreError.verifyFailed("不支持的压缩方法 \(method)：\(name)")
            }
            var sha = ""
            if hashContents {
                sha = try hashLocalFile(handle: handle, localOffset: localOff, expectedSize: uncomp, expectedCRC: crc, stats: &stats)
            }
            entries.append(ZipWrittenEntry(pathInZip: name, size: Int64(uncomp), sha256: sha, crc32: crc))
            offset += 46 + nameLen + extraLen + commentLen
        }
        return entries
    }

    private static func hashLocalFile(handle: FileHandle, localOffset: UInt64, expectedSize: UInt64, expectedCRC: UInt32, stats: inout ZipIOStats) throws -> String {
        try handle.seek(toOffset: localOffset)
        let header = handle.readData(ofLength: 30)
        stats.verifyBytesRead += Int64(header.count)
        guard header.u32(0) == 0x04034b50 else { throw ZipStoreError.verifyFailed("本地头签名错误") }
        let nameLen = Int(header.u16(26))
        let extraLen = Int(header.u16(28))
        let skip = handle.readData(ofLength: nameLen + extraLen)
        stats.verifyBytesRead += Int64(skip.count)
        var remain = expectedSize
        var hasher = SHA256()
        var crc: UInt32 = 0
        while remain > 0 {
            let n = Int(min(remain, 1024 * 1024))
            let chunk = handle.readData(ofLength: n)
            if chunk.count != n { throw ZipStoreError.verifyFailed("条目数据不完整") }
            hasher.update(data: chunk)
            crc = crc32update(crc, chunk)
            stats.verifyBytesRead += Int64(chunk.count)
            remain -= UInt64(n)
        }
        if crc != expectedCRC { throw ZipStoreError.verifyFailed("CRC32 不一致") }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func parseZip64Extra(_ extra: Data, size: inout UInt64, compressed: inout UInt64, localOffset: inout UInt64) {
        var i = 0
        while i + 4 <= extra.count {
            let id = extra.u16(i)
            let len = Int(extra.u16(i + 2))
            let start = i + 4
            if id == 0x0001, start + len <= extra.count {
                var p = start
                if size == 0xFFFFFFFF, p + 8 <= start + len { size = extra.u64(p); p += 8 }
                if compressed == 0xFFFFFFFF, p + 8 <= start + len { compressed = extra.u64(p); p += 8 }
                if localOffset == 0xFFFFFFFF, p + 8 <= start + len { localOffset = extra.u64(p) }
            }
            i = start + len
        }
    }

    private static func lastOccurrence(of signature: UInt32, in data: Data) -> Int? {
        if data.count < 4 { return nil }
        var i = data.count - 4
        while true {
            if data.u32(i) == signature { return i }
            if i == 0 { return nil }
            i -= 1
        }
    }
}

func crc32update(_ crc: UInt32, _ data: Data) -> UInt32 {
    data.withUnsafeBytes { raw in
        let ptr = raw.bindMemory(to: UInt8.self)
        return UInt32(crc32(uLong(crc), ptr.baseAddress, uInt(ptr.count)))
    }
}

private extension Data {
    mutating func appendUInt16(_ v: UInt16) {
        var le = v.littleEndian
        append(Data(bytes: &le, count: 2))
    }
    mutating func appendUInt32(_ v: UInt32) {
        var le = v.littleEndian
        append(Data(bytes: &le, count: 4))
    }
    mutating func appendUInt64(_ v: UInt64) {
        var le = v.littleEndian
        append(Data(bytes: &le, count: 8))
    }
    func u16(_ o: Int) -> UInt16 {
        UInt16(self[o]) | UInt16(self[o + 1]) << 8
    }
    func u32(_ o: Int) -> UInt32 {
        UInt32(self[o]) | UInt32(self[o + 1]) << 8 | UInt32(self[o + 2]) << 16 | UInt32(self[o + 3]) << 24
    }
    func u64(_ o: Int) -> UInt64 {
        UInt64(u32(o)) | UInt64(u32(o + 4)) << 32
    }
}

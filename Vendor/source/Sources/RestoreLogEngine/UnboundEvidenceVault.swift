import Foundation
import CryptoKit
import Darwin

/// P0-N1 offline Capture-First vault. DEFAULT OFF — not used by production App/CLI.
/// Never fabricates ECID. Never claims REAL_CONFIGURATOR / REAL_MCDP29xx.
public actor UnboundEvidenceVault {
    public enum Label: String, Codable, Sendable {
        case capturedEmptyObservation = "CAPTURED_EMPTY_OBSERVATION"
        case capturedPartial = "CAPTURED_PARTIAL"
        case capturedCompleteUnbound = "CAPTURED_COMPLETE_UNBOUND"
        case rejectedSymlink = "REJECTED_SYMLINK"
        case rejectedType = "REJECTED_TYPE"
        case limitExceeded = "LIMIT_EXCEEDED"
        case miss = "MISS"
    }

    public struct Entry: Codable, Sendable, Equatable {
        public var sourceDir: String
        public var label: Label
        public var capturedBytes: Int
        public var fileCount: Int
        public var sha256: String?
        public var note: String
    }

    private let root: URL
    private var entries: [Entry] = []
    private var writeAllowed = true
    private var sessionBytes = 0
    public let maxBytesPerFile: Int
    public let maxSessionBytes: Int
    public let maxFilesPerDir: Int

    public init(
        root: URL,
        maxBytesPerFile: Int = 8 * 1024 * 1024,
        maxSessionBytes: Int = 64 * 1024 * 1024,
        maxFilesPerDir: Int = 64
    ) {
        self.root = root
        self.maxBytesPerFile = maxBytesPerFile
        self.maxSessionBytes = maxSessionBytes
        self.maxFilesPerDir = maxFilesPerDir
    }

    public func arm() { writeAllowed = true }
    public func seal() { writeAllowed = false }

    public func currentEntries() -> [Entry] { entries }

    public func ingestDirectory(_ source: URL) async -> Entry {
        guard writeAllowed else {
            let e = Entry(sourceDir: source.path, label: .miss, capturedBytes: 0, fileCount: 0, sha256: nil, note: "sealed")
            entries.append(e); return e
        }
        let fd = open(source.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            let e = Entry(sourceDir: source.path, label: .rejectedSymlink, capturedBytes: 0, fileCount: 0, sha256: nil, note: "top-symlink-or-unreadable")
            entries.append(e); return e
        }
        close(fd)
        let dest = root.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        try? FileManager.default.createDirectory(at: dest.appendingPathComponent("bytes"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dest.appendingPathComponent("meta"), withIntermediateDirectories: true)

        var files: [URL] = []
        var omitted = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        if let en = FileManager.default.enumerator(at: source, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            for case let f as URL in en {
                let vals = try? f.resourceValues(forKeys: Set(keys))
                if vals?.isSymbolicLink == true { omitted += 1; continue }
                if vals?.isDirectory == true { continue }
                if vals?.isRegularFile == true {
                    if files.count >= maxFilesPerDir { omitted += 1; continue }
                    files.append(f)
                }
            }
        }
        if files.isEmpty {
            let label: Label = omitted > 0 ? .rejectedType : .capturedEmptyObservation
            let e = Entry(sourceDir: source.path, label: label, capturedBytes: 0, fileCount: 0, sha256: nil, note: omitted > 0 ? "nonregular-only" : "empty-observation-not-target-empty-inference")
            try? JSONEncoder().encode(e).write(to: dest.appendingPathComponent("meta/observation.json"), options: .atomic)
            entries.append(e); return e
        }
        var bytes = 0
        var copied = 0
        var hasher = SHA256()
        var truncated = false
        for f in files {
            if !writeAllowed { truncated = true; break }
            if sessionBytes + bytes >= maxSessionBytes { truncated = true; break }
            let fd = open(f.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { omitted += 1; continue }
            defer { close(fd) }
            var st = stat(); guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { omitted += 1; continue }
            let cap = min(maxBytesPerFile, maxSessionBytes - sessionBytes - bytes)
            var buf = [UInt8](repeating: 0, count: 64 * 1024)
            var got = 0
            let outURL = dest.appendingPathComponent("bytes").appendingPathComponent(f.lastPathComponent)
            FileManager.default.createFile(atPath: outURL.path, contents: nil)
            let out = try? FileHandle(forWritingTo: outURL)
            while got < cap {
                let n = read(fd, &buf, min(buf.count, cap - got))
                if n <= 0 { break }
                let slice = Data(buf[0..<n])
                hasher.update(data: slice)
                try? out?.write(contentsOf: slice)
                got += n
            }
            try? out?.close()
            var end = stat(); _ = fstat(fd, &end)
            if Int(st.st_size) > got || Int(end.st_size) != Int(st.st_size) { truncated = true }
            bytes += got; copied += 1
        }
        sessionBytes += bytes
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let label: Label
        if truncated || omitted > 0 { label = bytes > 0 ? .capturedPartial : .limitExceeded }
        else { label = .capturedCompleteUnbound }
        let e = Entry(sourceDir: source.path, label: label, capturedBytes: bytes, fileCount: copied, sha256: bytes > 0 ? digest : nil, note: "unbound-capture-offline-synth")
        try? JSONEncoder().encode(e).write(to: dest.appendingPathComponent("meta/integrity.json"), options: .atomic)
        entries.append(e)
        return e
    }
}

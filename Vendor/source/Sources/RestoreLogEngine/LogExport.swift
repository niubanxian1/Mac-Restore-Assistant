import Foundation
import CryptoKit

/// F07 — read-only export of an already-finalized session.
///
/// Boundaries this type enforces:
///   * the source evidence is opened read-only and is never moved, renamed,
///     truncated or appended to;
///   * the export is a *derivative copy*, published only after its bytes and
///     SHA-256 match the source's recorded digest;
///   * publication never overwrites an existing file, even under a concurrent
///     race — the last step is an atomic `link()` which fails when the target
///     exists.
///
/// `EXPORT_CREATED != SOURCE_EVIDENCE_VERIFIED`: this type refuses to produce a
/// file it could not verify, but it never upgrades the export into authority.
public enum LogExportError: Error, Equatable, CustomStringConvertible {
    case sourceMissing(String)
    case sourceUnreadable(String)
    case sourceDigestMismatch(expected: String, actual: String)
    case destinationNotADirectory(String)
    case destinationUnavailable(String)
    case destinationNotWritable(String)
    case writeFailed(String)
    case sizeMismatch(expected: Int, actual: Int)
    case copyDigestMismatch(expected: String, actual: String)
    case sourceChangedDuringCopy
    case nameCollisionUnresolved(attempts: Int)
    case directoryIdentityChanged(String)
    case tempNameReplaced(String)
    case publishedObjectMismatch(String)
    case finalContentMismatch(String)
    case publishedFileLeftBehind(String)

    public var description: String {
        switch self {
        case .sourceMissing(let p): return "来源日志不存在：\(p)"
        case .sourceUnreadable(let p): return "来源日志无法读取：\(p)"
        case .sourceDigestMismatch(let e, let a): return "来源日志哈希不符（期望 \(e.prefix(12))…，实际 \(a.prefix(12))…）"
        case .destinationNotADirectory(let p): return "保存位置不是文件夹：\(p)"
        case .destinationUnavailable(let p): return "保存位置不可用：\(p)"
        case .destinationNotWritable(let p): return "保存位置不可写：\(p)"
        case .writeFailed(let m): return "写入失败：\(m)"
        case .sizeMismatch(let e, let a): return "导出大小不符（期望 \(e)，实际 \(a)）"
        case .copyDigestMismatch(let e, let a): return "导出副本哈希不符（期望 \(e.prefix(12))…，实际 \(a.prefix(12))…）"
        case .sourceChangedDuringCopy: return "复制期间来源日志发生变化，已拒绝发布"
        case .nameCollisionUnresolved(let n): return "同名文件过多（已尝试 \(n) 次），未覆盖任何文件"
        case .directoryIdentityChanged(let p): return "保存位置在导出期间发生变化，已撤回本次导出：\(p)"
        case .tempNameReplaced(let p): return "临时文件名称已被外部替换，已拒绝导出：\(p)"
        case .publishedObjectMismatch(let p): return "发布的文件不是本次写入的对象，已撤回：\(p)"
        case .finalContentMismatch(let p): return "导出文件内容校验不一致：\(p)"
        case .publishedFileLeftBehind(let p): return "已发布的文件无法安全撤回，已保留并报告：\(p)"
        }
    }
}

/// Pure naming rules. Kept separate from I/O so they can be tested exhaustively.
public enum ExportNaming {
    public static let defaultBaseName = "Configurator"
    public static let maxBaseLength = 60

    /// The user's text is only ever a *component*, never a path.
    /// Separators, traversal, control characters and leading dots are removed.
    public static func sanitizedBase(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "\0", with: "")
        // path separators and the macOS legacy separator
        for bad in ["/", "\\", ":"] {
            s = s.replacingOccurrences(of: bad, with: "-")
        }
        // strip control characters (including newlines/tabs)
        s = String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        // collapse whitespace runs
        s = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // no leading dots (hidden files) and no traversal fragments
        while s.hasPrefix(".") { s.removeFirst() }
        while s.contains("..") { s = s.replacingOccurrences(of: "..", with: ".") }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))
        if s.isEmpty { return defaultBaseName }
        if s.count > maxBaseLength { s = String(s.prefix(maxBaseLength)) }
        return s.isEmpty ? defaultBaseName : s
    }

    /// Eight hex characters from the session UUID — traceable back to the full id,
    /// and never a four-character random suffix.
    public static func shortSessionID(_ id: UUID) -> String {
        String(id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).uppercased()
    }

    public static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: date)
    }

    /// `{name}_{YYYYMMDD}_{HHmmss}_{SHORT}[_PARTIAL].log`
    public static func fileName(
        base: String,
        at date: Date,
        sessionID: UUID,
        isPartial: Bool,
        timeZone: TimeZone = .current
    ) -> String {
        let stem = sanitizedBase(base)
        let tail = isPartial ? "_PARTIAL" : ""
        return "\(stem)_\(timestamp(date, timeZone: timeZone))_\(shortSessionID(sessionID))\(tail).log"
    }

    /// Raw MVP name: `Session-<id8>-<timestamp>[_PARTIAL].log`.
    /// Identity-uncertain sessions remain traceable by Session ID.
    public static func rawMVPSessionFileName(
        at date: Date,
        sessionID: UUID,
        isPartial: Bool,
        timeZone: TimeZone = .current
    ) -> String {
        let tail = isPartial ? "_PARTIAL" : ""
        return "Session-\(shortSessionID(sessionID))-\(timestamp(date, timeZone: timeZone))\(tail).log"
    }
}

public struct ExportRequest: Sendable {
    public let sourceURL: URL
    public let destinationDirectory: URL
    public let baseName: String
    public let sessionID: UUID
    public let isPartial: Bool
    /// The digest recorded when the session was finalized. The export must match
    /// it, so a source that changed after finalization is refused.
    public let expectedSourceSHA256: String
    public let now: Date
    public let maxCollisionSuffix: Int
    /// Optional already-composed safe filename, for the raw-only MVP naming.
    public let fileNameOverride: String?

    public init(
        sourceURL: URL,
        destinationDirectory: URL,
        baseName: String,
        sessionID: UUID,
        isPartial: Bool,
        expectedSourceSHA256: String,
        now: Date = Date(),
        maxCollisionSuffix: Int = 999,
        fileNameOverride: String? = nil
    ) {
        self.sourceURL = sourceURL
        self.destinationDirectory = destinationDirectory
        self.baseName = baseName
        self.sessionID = sessionID
        self.isPartial = isPartial
        self.expectedSourceSHA256 = expectedSourceSHA256
        self.now = now
        self.maxCollisionSuffix = maxCollisionSuffix
        self.fileNameOverride = fileNameOverride
    }
}

public struct ExportOutcome: Sendable, Equatable {
    public let url: URL
    public let byteCount: Int
    public let sha256: String
    public let isPartial: Bool
    public let collisionIndex: Int
}

/// `RENAME_EXCL` from macOS `sys/stdio.h` (0x00000004): refuse an existing
/// destination. Declared locally because the C macro is not always imported.
private let RENAME_EXCL: Int32 = 0x00000004

public actor LogExporter {
    public init() {}

    /// Identity of the object this transaction WROTE, captured from the writing
    /// descriptor — never derived from a path or a name.
    private struct FileIdentity: Equatable {
        let dev: dev_t
        let ino: ino_t
    }

    /// A directory descriptor plus the object identity it was bound to.
    private struct PinnedDirectory {
        let fd: Int32
        let dev: dev_t
        let ino: ino_t
    }

    public func export(
        _ request: ExportRequest,
        progress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) throws -> ExportOutcome {
        let fm = FileManager.default
        let source = request.sourceURL

        guard fm.fileExists(atPath: source.path) else {
            throw LogExportError.sourceMissing(source.path)
        }
        guard fm.isReadableFile(atPath: source.path) else {
            throw LogExportError.sourceUnreadable(source.path)
        }

        let sourceDigest = try Integrity.sha256(ofFileAt: source, progress: progress)
        guard sourceDigest == request.expectedSourceSHA256 else {
            throw LogExportError.sourceDigestMismatch(
                expected: request.expectedSourceSHA256, actual: sourceDigest)
        }

        // The destination is bound once, as an object.
        let pinned = try openPinnedDirectory(request.destinationDirectory)
        defer { close(pinned.fd) }

        // ---- H01-A-CLEANUP: the temp never lives in the user-visible directory ----
        // Everything the transaction must later delete lives in a directory this
        // transaction created, so no unlink is ever issued against a name in the
        // destination the user (or anything else) can write to.
        let stageName = ".rlm-stage-\(UUID().uuidString)"
        guard mkdirat(pinned.fd, stageName, 0o700) == 0 else {
            throw LogExportError.destinationNotWritable(stageName)
        }
        let stageFD = stageName.withCString {
            openat(pinned.fd, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        }
        guard stageFD >= 0 else {
            // RESIDUAL-CLOSEOUT: the staging directory is left in place. Reporting
            // it beats deleting a name we can no longer prove we own.
            throw LogExportError.destinationUnavailable(stageName)
        }
        defer {
            close(stageFD)
            // RESIDUAL-CLOSEOUT: this transaction NEVER deletes its staging
            // directory — not on success, not on failure. That removes the last
            // name-based delete from the export entirely, including the rmdir whose
            // guard a same-UID process could race by swapping the stage name. The
            // cost is a `.rlm-stage-<uuid>` directory left behind: EMPTY after a
            // successful export, holding the payload after a failed one. Both forms
            // are Owner-approved and are inventoried by the A11 validator, which now
            // counts them instead of missing them.
        }

        let tempName = "payload.tmp"
        let tempFD = tempName.withCString {
            openat(stageFD, $0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        }
        guard tempFD >= 0 else {
            throw LogExportError.writeFailed("无法创建临时文件（errno \(errno)）")
        }
        defer { close(tempFD) }

        let ownedIdentity: FileIdentity? = identity(ofFD: tempFD)

        // FAILURE_CLEANUP_POLICY=B: this transaction never deletes a name it cannot
        // prove it owns. On a failed export the staging directory and its payload
        // are LEFT IN PLACE and reported; an operator can see and remove them. This
        // is the Owner-approved trade: a visible, named residual instead of an
        // unprovable, race-prone deletion.

        let sourceAttrs = try? fm.attributesOfItem(atPath: source.path)
        let sourceBytesForProgress = Int64((sourceAttrs?[.size] as? NSNumber)?.int64Value ?? 0)
        let copy = try streamCopy(from: source, toFD: tempFD, totalBytes: sourceBytesForProgress, progress: progress)

        try verifyName(tempName, fd: stageFD, expected: ownedIdentity,
                       error: .tempNameReplaced(tempName))

        let sourceBytes = (try? fm.attributesOfItem(atPath: source.path))
            .flatMap { ($0[.size] as? NSNumber)?.intValue } ?? -2
        guard copy.bytes == sourceBytes else {
            throw LogExportError.sizeMismatch(expected: sourceBytes, actual: copy.bytes)
        }
        guard copy.digest == sourceDigest else {
            throw LogExportError.copyDigestMismatch(expected: sourceDigest, actual: copy.digest)
        }
        let afterDigest = try Integrity.sha256(ofFileAt: source)
        guard afterDigest == sourceDigest else { throw LogExportError.sourceChangedDuringCopy }

        let baseName: String
        if let override = request.fileNameOverride,
           override.hasSuffix(".log"),
           !override.contains("/"),
           !override.contains("\\"),
           !override.contains("..") {
            baseName = override
        } else {
            baseName = ExportNaming.fileName(
                base: request.baseName, at: request.now,
                sessionID: request.sessionID, isPartial: request.isPartial)
        }

        // Publication links from the staging descriptor into the destination. After
        // this point there is deliberately NO name-based unlink against the
        // destination: if ownership cannot be proven, the file is left in place and
        // reported instead of being deleted.
        let (finalName, index) = try publish(tempName: tempName, stageFD: stageFD,
                                             baseName: baseName, in: pinned,
                                             maxSuffix: request.maxCollisionSuffix)
        do {
            try verifyName(finalName, fd: pinned.fd, expected: ownedIdentity,
                           error: .publishedObjectMismatch(finalName))
            try ensureDestinationStillMatches(path: request.destinationDirectory.path, pinned: pinned)
            let published = try readBack(name: finalName, in: pinned)
            guard published.bytes == copy.bytes, published.digest == copy.digest else {
                throw LogExportError.finalContentMismatch(finalName)
            }
        } catch {
            // Fail closed WITHOUT deleting: we cannot prove the destination name is
            // still ours at unlink time, so we refuse to touch it.
            throw LogExportError.publishedFileLeftBehind(finalName)
        }

        // The token stays set: the deferred cleanup still has to remove OUR temp
        // inside the staging dir, and the staging dir itself is only removable once
        // it is empty. Clearing it here leaks both (this is the second time this
        // exact line has caused that, so it is now spelled out).
        return ExportOutcome(url: request.destinationDirectory.appendingPathComponent(finalName),
                             byteCount: copy.bytes, sha256: copy.digest,
                             isPartial: request.isPartial, collisionIndex: index)
    }

    // MARK: - identity

    private func identity(ofFD fd: Int32) -> FileIdentity? {
        var st = stat()
        guard fstat(fd, &st) == 0 else { return nil }
        return FileIdentity(dev: st.st_dev, ino: st.st_ino)
    }

    /// Verify that `name` in the pinned directory names exactly `expected` and is
    /// a regular file. Name → object, never name → string comparison.
    private func verifyName(_ name: String, fd: Int32,
                            expected: FileIdentity?, error: LogExportError) throws {
        guard let expected else { throw error }
        var st = stat()
        let rc = name.withCString { fstatat(fd, $0, &st, AT_SYMLINK_NOFOLLOW) }
        guard rc == 0 else { throw error }
        guard (st.st_mode & S_IFMT) == S_IFREG else { throw error }
        guard st.st_dev == expected.dev, st.st_ino == expected.ino else { throw error }
    }


    private func openPinnedDirectory(_ url: URL) throws -> PinnedDirectory {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            guard isDir.boolValue else {
                throw LogExportError.destinationNotADirectory(url.path)
            }
        } else {
            do {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                throw LogExportError.destinationUnavailable(url.path)
            }
        }
        let fd = url.path.withCString { open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC) }
        guard fd >= 0 else {
            throw errno == ENOTDIR
                ? LogExportError.destinationNotADirectory(url.path)
                : LogExportError.destinationUnavailable(url.path)
        }
        var st = stat()
        guard fstat(fd, &st) == 0 else {
            close(fd)
            throw LogExportError.destinationUnavailable(url.path)
        }
        return PinnedDirectory(fd: fd, dev: st.st_dev, ino: st.st_ino)
    }

    private func ensureDestinationStillMatches(path: String, pinned: PinnedDirectory) throws {
        var st = stat()
        guard stat(path, &st) == 0 else {
            throw LogExportError.directoryIdentityChanged(path)
        }
        guard st.st_dev == pinned.dev, st.st_ino == pinned.ino else {
            throw LogExportError.directoryIdentityChanged(path)
        }
    }

    /// Read the published file back through the pinned descriptor and hash what a
    /// reader would actually receive.
    private func readBack(name: String, in pinned: PinnedDirectory) throws -> (digest: String, bytes: Int) {
        let fd = name.withCString { openat(pinned.fd, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { throw LogExportError.finalContentMismatch(name) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var hasher = SHA256()
        var total = 0
        do {
            while true {
                let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
                total += chunk.count
            }
        } catch {
            throw LogExportError.finalContentMismatch(name)
        }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), total)
    }

    // MARK: - internals

    /// Copy the source into the descriptor we opened inside the pinned directory.
    private func streamCopy(
        from source: URL,
        toFD fd: Int32,
        totalBytes: Int64,
        progress: (@Sendable (Int64, Int64) -> Void)?
    ) throws -> (digest: String, bytes: Int) {
        do {
            guard let input = FileHandle(forReadingAtPath: source.path) else {
                throw LogExportError.sourceUnreadable(source.path)
            }
            defer { try? input.close() }
            let output = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
            var wrote = 0
            var hasher = SHA256()
            while true {
                let chunk = try input.read(upToCount: 1 << 20) ?? Data()
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
                try output.write(contentsOf: chunk)
                wrote += chunk.count
                progress?(Int64(wrote), totalBytes)
            }
            try output.synchronize()
            return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), wrote)
        } catch let known as LogExportError {
            throw known
        } catch {
            throw LogExportError.writeFailed(String(describing: error))
        }
    }

    /// Atomic, non-overwriting publication.
    ///
    /// `renameatx_np(..., RENAME_EXCL)` moves the payload NAME out of the staging
    /// directory into the destination. Two consequences matter:
    ///   * EEXIST refuses an existing destination, so nothing is overwritten;
    ///   * the staging directory is left EMPTY by the rename itself, so the
    ///     success path needs no unlink at all — the last name-based deletion in
    ///     the transaction disappears.
    /// `RENAME_EXCL` is `0x00000004` (macOS `sys/stdio.h`). There is deliberately
    /// NO fallback to a plain `rename()`, which would clobber the destination.
    private func publish(tempName: String, stageFD: Int32, baseName: String,
                         in pinned: PinnedDirectory, maxSuffix: Int) throws -> (String, Int) {
        let ext = (baseName as NSString).pathExtension
        let stem = (baseName as NSString).deletingPathExtension
        func candidate(_ index: Int) -> String {
            index <= 1 ? baseName : "\(stem)-\(index).\(ext)"
        }
        for index in 1...max(1, maxSuffix) {
            let name = candidate(index)
            let rc = tempName.withCString { from in
                name.withCString { to in
                    renameatx_np(stageFD, from, pinned.fd, to, UInt32(RENAME_EXCL))
                }
            }
            if rc == 0 { return (name, index) }
            if errno == EEXIST { continue }
            throw LogExportError.writeFailed("无法发布文件（errno \(errno)）")
        }
        throw LogExportError.nameCollisionUnresolved(attempts: maxSuffix)
    }
}

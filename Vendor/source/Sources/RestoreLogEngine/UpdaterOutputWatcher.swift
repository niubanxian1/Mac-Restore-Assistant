import Foundation
import CryptoKit
import Darwin
import Dispatch

/// RLM 1.2 P0 corrective — preemptive transient `/tmp/updater_output-*` snapshotter.
/// Starts with capture begin (NOT on `Wrote updater output`). Never mutates host
/// originals. Never writes into restore.log. Synth races must not set
/// `REAL_UPDATER_BODY_CAPTURED=YES`.
public actor UpdaterOutputWatcher {
    public struct Config: Sendable {
        public var watchRoot: URL
        public var sessionEvidenceRoot: URL
        public var sessionID: UUID
        public var ecidHint: String?
        /// Nonce planted by this session; directories containing it are bound.
        public var sessionNonce: String
        public var pollIntervalNanoseconds: UInt64
        public var maxBytesPerFile: Int
        public var maxFilesPerDir: Int
        public var maxSessionBytes: Int
        public var maxDirs: Int
        public var maxRecords: Int
        public var maxWatchDurationNanoseconds: UInt64
        public var stabilityWindowNanoseconds: UInt64
        public var namePrefix: String
        public var readyTimeoutNanoseconds: UInt64

        public init(
            watchRoot: URL = URL(fileURLWithPath: "/tmp", isDirectory: true),
            sessionEvidenceRoot: URL,
            sessionID: UUID,
            ecidHint: String? = nil,
            sessionNonce: String = UUID().uuidString,
            pollIntervalNanoseconds: UInt64 = 50_000_000,
            maxBytesPerFile: Int = 8 * 1024 * 1024,
            maxFilesPerDir: Int = 64,
            maxSessionBytes: Int = 64 * 1024 * 1024,
            maxDirs: Int = 128,
            maxRecords: Int = 256,
            maxWatchDurationNanoseconds: UInt64 = 2 * 60 * 60 * 1_000_000_000,
            stabilityWindowNanoseconds: UInt64 = 80_000_000,
            namePrefix: String = "updater_output-",
            readyTimeoutNanoseconds: UInt64 = 2_000_000_000
        ) {
            self.watchRoot = watchRoot
            self.sessionEvidenceRoot = sessionEvidenceRoot
            self.sessionID = sessionID
            self.ecidHint = ecidHint
            self.sessionNonce = sessionNonce
            self.pollIntervalNanoseconds = pollIntervalNanoseconds
            self.maxBytesPerFile = maxBytesPerFile
            self.maxFilesPerDir = maxFilesPerDir
            self.maxSessionBytes = maxSessionBytes
            self.maxDirs = maxDirs
            self.maxRecords = maxRecords
            self.maxWatchDurationNanoseconds = maxWatchDurationNanoseconds
            self.stabilityWindowNanoseconds = stabilityWindowNanoseconds
            self.namePrefix = namePrefix
            self.readyTimeoutNanoseconds = readyTimeoutNanoseconds
        }
    }

    public enum BindingState: String, Codable, Sendable, Equatable {
        case unbound
        case bound
        case quarantined
    }

    public enum CaptureCompleteness: String, Codable, Sendable {
        case complete
        case partial
        case truncated
        case limitExceeded
        case emptyDirectory
        case miss
        case quarantined
    }

    public struct CaptureRecord: Codable, Sendable, Equatable {
        public var sourcePath: String
        public var destPath: String?
        /// Source file SHA-256 when fully readable/verifiable; nil if unverifiable.
        public var originalSHA256: String?
        public var sourceSHA256: String?
        public var sourceHashVerifiable: Bool
        public var capturedSHA256: String?
        public var capturedBytes: Int
        public var fileCount: Int
        public var omittedFileCount: Int
        public var empty: Bool
        public var completeness: CaptureCompleteness
        public var timingNote: String
        public var boundToSession: Bool
        public var bindingState: BindingState
        public var quarantined: Bool
        public var realUpdaterBodyCaptured: String
        public var hostOutputBodyEverExisted: String
        /// P0-05: directory inventory observed stable & fully listed (independent of bytes copied).
        public var sourceInventoryComplete: Bool
        /// P0-STOP: true if this record was cut short by stop barrier.
        public var stoppedDuringCapture: Bool

        public init(
            sourcePath: String,
            destPath: String? = nil,
            originalSHA256: String? = nil,
            sourceSHA256: String? = nil,
            sourceHashVerifiable: Bool = false,
            capturedSHA256: String? = nil,
            capturedBytes: Int = 0,
            fileCount: Int = 0,
            omittedFileCount: Int = 0,
            empty: Bool = false,
            completeness: CaptureCompleteness,
            timingNote: String,
            boundToSession: Bool,
            bindingState: BindingState,
            quarantined: Bool,
            realUpdaterBodyCaptured: String = "NO",
            hostOutputBodyEverExisted: String = "UNVERIFIED",
            sourceInventoryComplete: Bool = true,
            stoppedDuringCapture: Bool = false
        ) {
            self.sourcePath = sourcePath
            self.destPath = destPath
            self.originalSHA256 = originalSHA256
            self.sourceSHA256 = sourceSHA256
            self.sourceHashVerifiable = sourceHashVerifiable
            self.capturedSHA256 = capturedSHA256
            self.capturedBytes = capturedBytes
            self.fileCount = fileCount
            self.omittedFileCount = omittedFileCount
            self.empty = empty
            self.completeness = completeness
            self.timingNote = timingNote
            self.boundToSession = boundToSession
            self.bindingState = bindingState
            self.quarantined = quarantined
            self.realUpdaterBodyCaptured = realUpdaterBodyCaptured
            self.hostOutputBodyEverExisted = hostOutputBodyEverExisted
            self.sourceInventoryComplete = sourceInventoryComplete
            self.stoppedDuringCapture = stoppedDuringCapture
        }

        enum CodingKeys: String, CodingKey {
            case sourcePath, destPath, originalSHA256, sourceSHA256, sourceHashVerifiable
            case capturedSHA256, capturedBytes, fileCount, omittedFileCount, empty
            case completeness, timingNote, boundToSession, bindingState, quarantined
            case realUpdaterBodyCaptured, hostOutputBodyEverExisted
            case sourceInventoryComplete, stoppedDuringCapture
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sourcePath = try c.decode(String.self, forKey: .sourcePath)
            destPath = try c.decodeIfPresent(String.self, forKey: .destPath)
            originalSHA256 = try c.decodeIfPresent(String.self, forKey: .originalSHA256)
            sourceSHA256 = try c.decodeIfPresent(String.self, forKey: .sourceSHA256)
            sourceHashVerifiable = try c.decodeIfPresent(Bool.self, forKey: .sourceHashVerifiable) ?? false
            capturedSHA256 = try c.decodeIfPresent(String.self, forKey: .capturedSHA256)
            capturedBytes = try c.decodeIfPresent(Int.self, forKey: .capturedBytes) ?? 0
            fileCount = try c.decodeIfPresent(Int.self, forKey: .fileCount) ?? 0
            omittedFileCount = try c.decodeIfPresent(Int.self, forKey: .omittedFileCount) ?? 0
            empty = try c.decodeIfPresent(Bool.self, forKey: .empty) ?? false
            completeness = try c.decode(CaptureCompleteness.self, forKey: .completeness)
            timingNote = try c.decode(String.self, forKey: .timingNote)
            boundToSession = try c.decode(Bool.self, forKey: .boundToSession)
            bindingState = try c.decode(BindingState.self, forKey: .bindingState)
            quarantined = try c.decodeIfPresent(Bool.self, forKey: .quarantined) ?? false
            realUpdaterBodyCaptured = try c.decodeIfPresent(String.self, forKey: .realUpdaterBodyCaptured) ?? "NO"
            hostOutputBodyEverExisted = try c.decodeIfPresent(String.self, forKey: .hostOutputBodyEverExisted) ?? "UNVERIFIED"
            sourceInventoryComplete = try c.decodeIfPresent(Bool.self, forKey: .sourceInventoryComplete) ?? true
            stoppedDuringCapture = try c.decodeIfPresent(Bool.self, forKey: .stoppedDuringCapture) ?? false
        }
    }

    public struct Snapshot: Sendable, Equatable {
        public var earlyWatcherStarted: Bool
        public var readyBarrierPassed: Bool
        public var records: [CaptureRecord]
        public var attempted: Bool
        public var failedReason: String?
        public var sessionBytesCaptured: Int
        public var dirsSeen: Int
        public var stoppedAtCutoff: Bool
    }

    public struct ReadyResult: Sendable {
        public var ok: Bool
        public var firstPollAt: Date?
        public var error: String?
    }

    private let config: Config
    private var running = false
    private var stoppedCutoff = false
    private var pollTask: Task<Void, Never>?
    private var seenDirs: Set<String> = []
    private var boundDirKeys: Set<String> = []
    private var records: [CaptureRecord] = []
    private var earlyStarted = false
    private var readyBarrierPassed = false
    private var failedReason: String?
    private var startedAt: Date = .distantPast
    private var sessionBytesCaptured = 0
    private var dirWatchFD: Int32 = -1
    private var dirSource: DispatchSourceFileSystemObject?
    private var fsEventCoalesceTask: Task<Void, Never>?
    /// P0-STOP: after false, no new discovery/copy writes are permitted.
    private var writeAllowed = true
    private var stopGeneration: UInt64 = 0
    private var inFlightSnapshots = 0

    public init(config: Config) {
        self.config = config
    }

    /// Start polling + directory FS notifications. Does not return until the first
    /// poll completes (ready barrier) or timeout/error.
    public func startAndAwaitReady() async -> ReadyResult {
        guard !running else {
            return ReadyResult(ok: readyBarrierPassed, firstPollAt: startedAt, error: readyBarrierPassed ? nil : "already-running-not-ready")
        }
        running = true
        writeAllowed = true
        earlyStarted = true
        startedAt = Date()
        stoppedCutoff = false
        installDirectoryWatch()
        // Immediate first poll = ready barrier.
        await pollOnce(mode: .full)
        readyBarrierPassed = failedReason == nil
        if !readyBarrierPassed {
            let err = failedReason ?? "ready-poll-failed"
            await stopInternal(finalSweep: false)
            return ReadyResult(ok: false, firstPollAt: nil, error: err)
        }
        let firstAt = Date()
        pollTask = Task { [weak self] in
            while let self, await self.running {
                let started = await self.startedAt
                let maxNs = await self.config.maxWatchDurationNanoseconds
                if Date().timeIntervalSince(started) * 1_000_000_000 > Double(maxNs) {
                    await self.markFailed("max-watch-duration-exceeded")
                    break
                }
                await self.pollOnce(mode: .full)
                do {
                    try await Task.sleep(nanoseconds: await self.config.pollIntervalNanoseconds)
                } catch {
                    break
                }
            }
        }
        return ReadyResult(ok: true, firstPollAt: firstAt, error: nil)
    }

    /// Compatibility: start without awaiting (tests that call start then pollOnce).
    public func start() async {
        _ = await startAndAwaitReady()
    }

    /// Stop watcher at session cutoff. Residual flush only for already-bound dirs.
    public func stop(cutoff: Bool = true) async -> Snapshot {
        stoppedCutoff = cutoff
        return await stopInternal(finalSweep: true)
    }

    private func stopInternal(finalSweep: Bool) async -> Snapshot {
        // P0-STOP: barrier first — forbid new copies before cancel/join.
        writeAllowed = false
        running = false
        stopGeneration &+= 1
        let task = pollTask
        pollTask = nil
        task?.cancel()
        fsEventCoalesceTask?.cancel()
        fsEventCoalesceTask = nil
        teardownDirectoryWatch()
        // Join in-flight poll loop (cancellation propagates via Task.sleep / checks).
        if let task {
            await task.value
        }
        // Drain any snapshot still finishing cooperative cancel.
        var spins = 0
        while inFlightSnapshots > 0 && spins < 2000 {
            try? await Task.sleep(nanoseconds: 1_000_000)
            spins += 1
        }
        // Owner: stop return ⇒ 0 new evidence bytes. Skip residual copy sweep.
        _ = finalSweep
        return Snapshot(
            earlyWatcherStarted: earlyStarted,
            readyBarrierPassed: readyBarrierPassed,
            records: records,
            attempted: earlyStarted,
            failedReason: failedReason,
            sessionBytesCaptured: sessionBytesCaptured,
            dirsSeen: seenDirs.count,
            stoppedAtCutoff: stoppedCutoff
        )
    }

    /// Test hook: force one poll cycle (full discovery).
    public func pollOncePublic() async {
        await pollOnce(mode: .full)
    }

    public func currentSnapshot() -> Snapshot {
        Snapshot(
            earlyWatcherStarted: earlyStarted,
            readyBarrierPassed: readyBarrierPassed,
            records: records,
            attempted: earlyStarted,
            failedReason: failedReason,
            sessionBytesCaptured: sessionBytesCaptured,
            dirsSeen: seenDirs.count,
            stoppedAtCutoff: stoppedCutoff
        )
    }

    private enum PollMode {
        case full
        case boundOnly
    }

    private func markFailed(_ reason: String) {
        failedReason = reason
        running = false
    }

    private func isRunnable() -> Bool { running && writeAllowed }

    private func installDirectoryWatch() {
        let path = config.watchRoot.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        dirWatchFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete, .link, .attrib],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.handleFSEvent() }
        }
        source.setCancelHandler {
            close(fd)
        }
        dirSource = source
        source.resume()
    }

    private func teardownDirectoryWatch() {
        dirSource?.cancel()
        dirSource = nil
        dirWatchFD = -1
    }

    private func handleFSEvent() async {
        guard running else { return }
        // Coalesce bursts; poll promptly for ephemeral create→delete.
        fsEventCoalesceTask?.cancel()
        fsEventCoalesceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 2_000_000)
            } catch { return }
            guard let self else { return }
            let ok = await self.isRunnable()
            guard ok else { return }
            await self.pollOnce(mode: .full)
        }
    }

    /// Open directory with O_DIRECTORY|O_NOFOLLOW. Returns nil + reason on reject.
    private func openSourceDirectoryNoFollow(_ path: String) -> (fd: Int32, reason: String?) {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd >= 0 { return (fd, nil) }
        let e = errno
        if e == ELOOP || e == ENOTDIR {
            return (-1, "rejected-top-symlink-or-non-dir")
        }
        if e == EACCES || e == EPERM {
            return (-1, "dir-unreadable")
        }
        return (-1, "dir-open-failed-errno-\(e)")
    }


    /// P0-05: timing notes that mean the snapshot observed an unstable/racy inventory.
    /// Such records stay non-complete forever for this sourcePath (no post-race heal).
    private func isRaceTaintedCapture(_ rec: CaptureRecord) -> Bool {
        let note = rec.timingNote
        if note.contains("inventory-changed") { return true }
        if note.contains("sibling-vanished") { return true }
        if note.contains("partial-growing") { return true }
        if note.contains("stop-barrier-mid-copy") { return true }
        if note.contains("vanished-during-stability") { return true }
        if note.contains("race-latch-frozen") { return true }
        if (rec.completeness == .partial || rec.completeness == .truncated)
            && note.contains("during-stability")
        {
            return true
        }
        return false
    }

    private func pollOnce(mode: PollMode) async {
        // After stop barrier, freeze records — no discovery and no re-snapshot updates.
        guard writeAllowed else { return }
        let fm = FileManager.default
        guard let kids = try? fm.contentsOfDirectory(
            at: config.watchRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            // X5 / Agent C: mid-run fault must stop the poll loop, not silently continue.
            markFailed("watchRoot unreadable")
            return
        }
        if seenDirs.count >= config.maxDirs || records.count >= config.maxRecords {
            markFailed(failedReason ?? "dir-or-record-cap")
            return
        }
        for url in kids {
            let name = url.lastPathComponent
            guard name.hasPrefix(config.namePrefix) else { continue }
            let std = url.standardizedFileURL
            // P0-05: reject top-level symlink / non-dir via O_NOFOLLOW|O_DIRECTORY.
            let opened = openSourceDirectoryNoFollow(std.path)
            if opened.fd < 0 {
                let reason = opened.reason ?? "dir-open-failed"
                let key = std.path
                if !seenDirs.contains(key) && mode == .full && writeAllowed {
                    seenDirs.insert(key)
                    let completeness: CaptureCompleteness = reason.hasPrefix("dir-unreadable") ? .partial : .miss
                    records.append(CaptureRecord(
                        sourcePath: key,
                        completeness: completeness,
                        timingNote: reason,
                        boundToSession: false,
                        bindingState: .unbound,
                        quarantined: false,
                        sourceInventoryComplete: false
                    ))
                }
                continue
            }
            close(opened.fd)

            // P0-10: skip only clearly stale pre-session debris (>1s before start) UNLESS
            // modified after startedAt (active restore touching old dir). Never silent zero.
            if let values = try? std.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]) {
                let created = values.creationDate
                let modified = values.contentModificationDate
                let stamp = created ?? modified
                let touchedAfterStart = (modified.map { $0 >= startedAt.addingTimeInterval(-0.05) } ?? false)
                if let stamp, stamp < startedAt.addingTimeInterval(-1), !touchedAfterStart {
                    continue
                }
            }

            let key = std.path
            if mode == .boundOnly && !boundDirKeys.contains(key) {
                continue
            }

            if seenDirs.contains(key) {
                if let idx = records.firstIndex(where: { $0.sourcePath == key }) {
                    let prior = records[idx]
                    let c = prior.completeness
                    // P0-05 residual (audit005 / 006): race-tainted partials must NOT be healed
                    // to .complete by a later pollOnce once inventory/stop notes are latched.
                    if isRaceTaintedCapture(prior) {
                        continue
                    }
                    // Re-check growing dirs and prior complete snapshots (sibling files may appear).
                    if c == .partial || c == .emptyDirectory || c == .truncated
                        || c == .complete || c == .limitExceeded || c == .miss
                    {
                        if let updated = await snapshotDirectory(url, prior: prior) {
                            // Belt-and-suspenders: never upgrade a race-tainted prior to .complete.
                            if isRaceTaintedCapture(prior) && updated.completeness == .complete {
                                var frozen = prior
                                if !frozen.timingNote.contains("race-latch-frozen") {
                                    frozen.timingNote = prior.timingNote + "|race-latch-frozen"
                                }
                                records[idx] = frozen
                            } else {
                                records[idx] = updated
                            }
                        }
                    }
                }
                continue
            }

            if seenDirs.count >= config.maxDirs || records.count >= config.maxRecords {
                markFailed(failedReason ?? "dir-or-record-cap")
                break
            }
            seenDirs.insert(key)
            if let rec = await snapshotDirectory(url, prior: nil) {
                if rec.bindingState == .bound {
                    boundDirKeys.insert(key)
                }
                records.append(rec)
            }
        }
    }

    /// P0-10: nonce marker read is bounded (≤4 KiB), O_NOFOLLOW, regular-file only.
    /// Never `Data(contentsOf:)` an attacker-controlled marker into RSS.
    private static let nonceReadLimit = 4 * 1024

    private func readNonceMarkerBounded(_ marker: URL) -> String? {
        let path = marker.path
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { return nil }
        guard (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        // P0-10 / Agent C: oversized marker is a non-match — do not stream hundreds of MiB.
        if st.st_size > off_t(Self.nonceReadLimit) { return nil }
        var buf = [UInt8](repeating: 0, count: Self.nonceReadLimit)
        let n = read(fd, &buf, Self.nonceReadLimit)
        guard n > 0 else { return nil }
        // Probe one more byte; if present, oversize under us → non-match.
        var probe: UInt8 = 0
        if read(fd, &probe, 1) > 0 { return nil }
        return String(decoding: buf[0..<n], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func evaluateBinding(_ source: URL) -> BindingState {
        let name = source.lastPathComponent
        let sid = config.sessionID.uuidString.uppercased()
        if name.uppercased().contains(sid) { return .bound }
        if let ecid = config.ecidHint, !ecid.isEmpty, name.contains(ecid) { return .bound }
        // Recognize session nonce in directory name or planted marker file (bounded).
        if !config.sessionNonce.isEmpty {
            if name.contains(config.sessionNonce) { return .bound }
            let marker = source.appendingPathComponent(".rlm_session_nonce")
            if let token = readNonceMarkerBounded(marker), token == config.sessionNonce {
                return .bound
            }
        }
        // Unknown: empty → unbound (ignore carefully); non-empty → quarantined.
        // Cap enumeration so a huge foreign tree cannot unbounded-accumulate URLs.
        let fm = FileManager.default
        let enumCap = 256
        var seen = 0
        if let en = fm.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
            for case let f as URL in en {
                seen += 1
                if seen > enumCap { return .quarantined }
                let vals = try? f.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
                if vals?.isSymbolicLink == true { return .quarantined }
                if vals?.isRegularFile == true {
                    let sz = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    if sz > 0 { return .quarantined }
                }
            }
        }
        return .unbound
    }

    private func snapshotDirectory(_ source: URL, prior: CaptureRecord?) async -> CaptureRecord? {
        inFlightSnapshots += 1
        defer { inFlightSnapshots = max(0, inFlightSnapshots - 1) }
        let fm = FileManager.default
        let source = source.standardizedFileURL
        let binding = evaluateBinding(source)
        let destRoot = config.sessionEvidenceRoot.standardizedFileURL.appendingPathComponent(
            source.lastPathComponent,
            isDirectory: true
        )

        if binding == .unbound {
            // Empty unknown — note only, no body copy, do not claim miss of foreign body.
            return CaptureRecord(
                sourcePath: source.path,
                destPath: nil,
                originalSHA256: nil,
                sourceSHA256: nil,
                sourceHashVerifiable: false,
                capturedSHA256: nil,
                capturedBytes: 0,
                fileCount: 0,
                omittedFileCount: 0,
                empty: true,
                completeness: .emptyDirectory,
                timingNote: "unbound-empty-ignored",
                boundToSession: false,
                bindingState: .unbound,
                quarantined: false,
                realUpdaterBodyCaptured: "NO",
                hostOutputBodyEverExisted: "UNVERIFIED"
            )
        }

        if binding == .quarantined {
            let rec = CaptureRecord(
                sourcePath: source.path,
                destPath: nil,
                originalSHA256: nil,
                sourceSHA256: nil,
                sourceHashVerifiable: false,
                capturedSHA256: nil,
                capturedBytes: 0,
                fileCount: 0,
                omittedFileCount: 0,
                empty: true,
                completeness: .quarantined,
                timingNote: "unbound-quarantine",
                boundToSession: false,
                bindingState: .quarantined,
                quarantined: true,
                realUpdaterBodyCaptured: "NO",
                hostOutputBodyEverExisted: "UNVERIFIED"
            )
            try? fm.createDirectory(at: config.sessionEvidenceRoot, withIntermediateDirectories: true)
            let q = config.sessionEvidenceRoot.appendingPathComponent("QUARANTINED_\(source.lastPathComponent).txt")
            try? Data("quarantined unbound updater_output dir: \(source.path)\n".utf8)
                .write(to: q, options: .atomic)
            return rec
        }

        if sessionBytesCaptured >= config.maxSessionBytes {
            return CaptureRecord(
                sourcePath: source.path,
                destPath: nil,
                originalSHA256: nil,
                sourceSHA256: nil,
                sourceHashVerifiable: false,
                capturedSHA256: nil,
                capturedBytes: 0,
                fileCount: 0,
                omittedFileCount: 0,
                empty: false,
                completeness: .limitExceeded,
                timingNote: "session-byte-cap",
                boundToSession: true,
                bindingState: .bound,
                quarantined: false,
                realUpdaterBodyCaptured: "NO",
                hostOutputBodyEverExisted: "UNVERIFIED"
            )
        }

        if !writeAllowed {
            return prior
        }

        try? fm.createDirectory(at: config.sessionEvidenceRoot, withIntermediateDirectories: true)
        try? fm.createDirectory(at: destRoot, withIntermediateDirectories: true)

        // Re-verify directory with O_NOFOLLOW before treating as empty/complete.
        let dirOpen = openSourceDirectoryNoFollow(source.path)
        if dirOpen.fd < 0 {
            let reason = dirOpen.reason ?? "dir-open-failed"
            let completeness: CaptureCompleteness = reason.hasPrefix("dir-unreadable") ? .partial : .miss
            return CaptureRecord(
                sourcePath: source.path,
                destPath: destRoot.path,
                completeness: completeness,
                timingNote: reason,
                boundToSession: true,
                bindingState: .bound,
                quarantined: false,
                sourceInventoryComplete: false
            )
        }
        close(dirOpen.fd)

        // Enumerate files; reject symlinks (do not follow).
        // P0-10: apply maxFilesPerDir during walk — never accumulate all URLs first.
        // Returns scanFailed=true when enumerator could not be created (≠ empty).
        func enumerateFiles() -> (files: [URL], omitted: Int, hitFileCap: Bool, scanFailed: Bool) {
            var files: [URL] = []
            var omitted = 0
            var hitFileCap = false
            let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
            guard let kids = fm.enumerator(at: source, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
                return ([], 0, false, true)
            }
            for case let f as URL in kids {
                let fStd = f.standardizedFileURL
                let vals = try? fStd.resourceValues(forKeys: Set(keys))
                if vals?.isSymbolicLink == true {
                    omitted += 1
                    continue
                }
                if vals?.isDirectory == true { continue }
                if vals?.isRegularFile == true {
                    if files.count >= config.maxFilesPerDir {
                        omitted += 1
                        hitFileCap = true
                        continue
                    }
                    files.append(fStd)
                }
            }
            return (files, omitted, hitFileCap, false)
        }

        var enumerated = enumerateFiles()
        if enumerated.scanFailed {
            return CaptureRecord(
                sourcePath: source.path,
                destPath: destRoot.path,
                omittedFileCount: 0,
                empty: false,
                completeness: .partial,
                timingNote: "scan-failed-unreadable",
                boundToSession: true,
                bindingState: .bound,
                quarantined: false,
                sourceInventoryComplete: false
            )
        }
        var files = enumerated.files
        var omitted = enumerated.omitted
        var hitFileCap = enumerated.hitFileCap
        let firstPaths = Set(files.map(\.path))

        if files.isEmpty {
            // True empty only: open succeeded, enumeration succeeded, zero regular files.
            // If only omitted symlinks → partial, not emptyDirectory.
            if omitted > 0 {
                return CaptureRecord(
                    sourcePath: source.path,
                    destPath: destRoot.path,
                    omittedFileCount: omitted,
                    empty: false,
                    completeness: .partial,
                    timingNote: "symlink-or-nonregular-only",
                    boundToSession: true,
                    bindingState: .bound,
                    quarantined: false,
                    sourceInventoryComplete: true
                )
            }
            let marker = destRoot.appendingPathComponent("EMPTY_STAGING.marker")
            let meta = """
            empty=YES
            source=\(source.path)
            session=\(config.sessionID.uuidString)
            HOST_OUTPUT_DIRECTORY_FOUND=YES_EMPTY_DIRECTORY
            HOST_OUTPUT_BODY_EVER_EXISTED=UNVERIFIED
            REAL_UPDATER_BODY_CAPTURED=NO
            """
            try? Data(meta.utf8).write(to: marker, options: .atomic)
            return CaptureRecord(
                sourcePath: source.path,
                destPath: destRoot.path,
                omittedFileCount: omitted,
                empty: true,
                completeness: hitFileCap ? .limitExceeded : .emptyDirectory,
                timingNote: prior?.timingNote ?? "empty-se-or-dir",
                boundToSession: true,
                bindingState: .bound,
                quarantined: false,
                sourceInventoryComplete: true
            )
        }

        // Stability: wait briefly then re-stat sizes; cancel must abort.
        var sizeMap: [String: Int] = [:]
        for f in files {
            sizeMap[f.path] = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        // Prefer cooperative stop barrier over ambient Task cancellation (poll loop
        // cancel must not erase an in-flight external pollOncePublic snapshot).
        let genAtSleep = stopGeneration
        do {
            try await Task.sleep(nanoseconds: config.stabilityWindowNanoseconds)
        } catch is CancellationError {
            if !writeAllowed || stopGeneration != genAtSleep {
                return prior
            }
            // Spurious cancel while still armed — continue snapshot.
        } catch {
            return CaptureRecord(
                sourcePath: source.path,
                destPath: destRoot.path,
                completeness: .partial,
                timingNote: "stability-sleep-error",
                boundToSession: true,
                bindingState: .bound,
                quarantined: false,
                sourceInventoryComplete: false,
                stoppedDuringCapture: true
            )
        }
        if !writeAllowed {
            return prior // do not clobber a successful prior snapshot with a zero-byte stop stub
        }
        // Re-enumerate after stability so siblings created mid-snapshot are counted for caps.
        enumerated = enumerateFiles()
        if enumerated.scanFailed {
            return CaptureRecord(
                sourcePath: source.path,
                destPath: destRoot.path,
                completeness: .partial,
                timingNote: "scan-failed-after-stability",
                boundToSession: true,
                bindingState: .bound,
                quarantined: false,
                sourceInventoryComplete: false
            )
        }
        files = enumerated.files
        omitted = enumerated.omitted
        hitFileCap = enumerated.hitFileCap
        let secondPaths = Set(files.map(\.path))
        let vanished = firstPaths.subtracting(secondPaths)
        let appeared = secondPaths.subtracting(firstPaths)
        var inventoryChanged = !vanished.isEmpty || !appeared.isEmpty
        if !vanished.isEmpty {
            omitted += vanished.count
        }
        // Dir vanished during stability / blind zone — honest miss, never silent complete.
        if files.isEmpty {
            return CaptureRecord(
                sourcePath: source.path,
                destPath: destRoot.path,
                omittedFileCount: omitted,
                empty: true,
                completeness: .miss,
                timingNote: inventoryChanged ? "sibling-vanished-during-stability" : "vanished-during-stability-or-blind-zone",
                boundToSession: true,
                bindingState: .bound,
                quarantined: false,
                sourceInventoryComplete: false
            )
        }
        var stable = !inventoryChanged
        for f in files {
            let sz = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if sizeMap[f.path] != sz {
                stable = false
                inventoryChanged = true
            }
        }

        var copiedBytes = 0
        var shaList: [String] = []
        var sourceSHAList: [String] = []
        var anyTruncated = false
        var anyUnverifiableSource = false
        var copiedFileCount = 0
        var firstSourceSHA: String?
        var firstCapturedSHA: String?
        var hitSessionByteCap = false

        var stoppedMid = false
        for f in files {
            if !writeAllowed {
                anyUnverifiableSource = true
                stoppedMid = true
                break
            }
            let fStd = f.standardizedFileURL
            let rel = relativePath(of: fStd, under: source)
            guard !rel.isEmpty else { continue }
            let dest = destRoot.appendingPathComponent(rel)
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

            let remainingSession = config.maxSessionBytes - sessionBytesCaptured - copiedBytes
            if remainingSession <= 0 {
                anyTruncated = true
                hitSessionByteCap = true
                omitted += 1
                break
            }
            let fileCap = min(config.maxBytesPerFile, remainingSession)
            guard let copyResult = copyFileNoFollow(
                from: fStd,
                to: dest,
                maxBytes: fileCap
            ) else {
                // P0-05: unreadable / symlink-open-fail / irregular — disclose omit, never complete.
                anyUnverifiableSource = true
                omitted += 1
                continue
            }
            copiedBytes += copyResult.capturedBytes
            copiedFileCount += 1
            shaList.append("\(copyResult.capturedSHA256)  \(rel)")
            if firstCapturedSHA == nil { firstCapturedSHA = copyResult.capturedSHA256 }
            if copyResult.truncated || copyResult.sourceHashVerifiable == false {
                if copyResult.truncated { anyTruncated = true }
                if !copyResult.sourceHashVerifiable { anyUnverifiableSource = true }
                sourceSHAList.append("UNVERIFIABLE  \(rel)")
                firstSourceSHA = nil
            } else if let s = copyResult.sourceSHA256 {
                sourceSHAList.append("\(s)  \(rel)")
                if firstSourceSHA == nil {
                    firstSourceSHA = s
                }
            }
        }

        sessionBytesCaptured += copiedBytes

        let sumsURL = destRoot.appendingPathComponent("CAPTURE_SHA256SUMS.txt")
        try? Data((shaList.joined(separator: "\n") + "\n").utf8).write(to: sumsURL, options: .atomic)
        let srcSumsURL = destRoot.appendingPathComponent("SOURCE_SHA256SUMS.txt")
        try? Data((sourceSHAList.joined(separator: "\n") + "\n").utf8).write(to: srcSumsURL, options: .atomic)

        // P0-05: NEVER .complete when any omit / unreadable / truncate / cap / unstable / inventory change.
        let completeness: CaptureCompleteness
        if hitFileCap || hitSessionByteCap {
            completeness = .limitExceeded
        } else if anyTruncated {
            completeness = .truncated
        } else if omitted > 0 || anyUnverifiableSource || inventoryChanged || stoppedMid {
            completeness = .partial
        } else if !stable {
            completeness = .partial
        } else if copiedBytes == 0 && !files.isEmpty {
            completeness = .miss
        } else {
            completeness = .complete
        }

        let inventoryComplete = !inventoryChanged && stable && !enumerated.scanFailed && !stoppedMid
        // Directory-level source hash only when fully complete & verifiable & single file.
        let sourceFullyVerifiable =
            completeness == .complete
            && omitted == 0
            && !anyUnverifiableSource
            && !anyTruncated
            && stable
            && inventoryComplete
            && copiedFileCount > 0
            && !stoppedMid
        let directorySourceSHA: String? = (sourceFullyVerifiable && copiedFileCount == 1) ? firstSourceSHA : nil

        let bodyExisted = copiedBytes > 0 ? "YES_BYTES_OBSERVED_SYNTH_OR_HOST" : "UNVERIFIED"
        let metaURL = destRoot.appendingPathComponent("UPDATER_OUTPUT_CAPTURE.json")
        let note: String
        if stoppedMid {
            note = "stop-barrier-mid-copy"
        } else if inventoryChanged {
            note = "inventory-changed-during-stability"
        } else if !stable {
            note = "partial-growing"
        } else if anyTruncated {
            note = "truncated-copy"
        } else if hitFileCap || hitSessionByteCap {
            note = "limit-exceeded"
        } else if omitted > 0 || anyUnverifiableSource {
            note = "partial-omitted"
        } else {
            note = "stable-copy"
        }
        let rec = CaptureRecord(
            sourcePath: source.path,
            destPath: destRoot.path,
            originalSHA256: directorySourceSHA,
            sourceSHA256: directorySourceSHA,
            sourceHashVerifiable: sourceFullyVerifiable,
            capturedSHA256: firstCapturedSHA,
            capturedBytes: copiedBytes,
            fileCount: copiedFileCount,
            omittedFileCount: omitted,
            empty: false,
            completeness: completeness,
            timingNote: note,
            boundToSession: true,
            bindingState: .bound,
            quarantined: false,
            realUpdaterBodyCaptured: "NO",
            hostOutputBodyEverExisted: bodyExisted,
            sourceInventoryComplete: inventoryComplete && completeness == .complete,
            stoppedDuringCapture: stoppedMid
        )
        if let enc = try? JSONEncoder().encode(rec) {
            try? enc.write(to: metaURL, options: .atomic)
        }
        return rec
    }

    private struct CopyResult {
        var capturedBytes: Int
        var capturedSHA256: String
        var sourceSHA256: String?
        var sourceHashVerifiable: Bool
        var truncated: Bool
        var initialSize: Int
        var endSize: Int
        var sourceChanged: Bool
    }

    /// Open with O_NOFOLLOW, fstat before+after on same fd, compare bytesRead vs size.
    private func copyFileNoFollow(from src: URL, to dest: URL, maxBytes: Int) -> CopyResult? {
        if !writeAllowed { return nil }
        let path = src.path
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            return nil
        }
        defer { close(fd) }

        var st = stat()
        guard fstat(fd, &st) == 0 else { return nil }
        guard (st.st_mode & S_IFMT) == S_IFREG else { return nil }

        let initialSize = Int(st.st_size)
        let initialDev = st.st_dev
        let initialIno = st.st_ino
        let capped = initialSize > maxBytes
        // Cap path: stream at most maxBytes; source hash never authoritative.
        var truncated = capped
        var sourceChanged = false

        var capturedHasher = SHA256()
        var sourceHasher = SHA256()
        var capturedTotal = 0
        var bytesRead = 0
        let chunkSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        FileManager.default.createFile(atPath: dest.path, contents: nil, attributes: nil)
        guard let out = try? FileHandle(forWritingTo: dest) else { return nil }
        defer { try? out.close() }

        while true {
            if !writeAllowed {
                truncated = true
                sourceChanged = true
                break
            }
            let room = maxBytes - capturedTotal
            if room <= 0 {
                truncated = true
                break
            }
            let toRead = min(chunkSize, room)
            let n = read(fd, &buffer, toRead)
            if n < 0 { return nil }
            if n == 0 { break }
            bytesRead += n
            let slice = Data(buffer[0..<n])
            sourceHasher.update(data: slice)
            capturedHasher.update(data: slice)
            try? out.write(contentsOf: slice)
            capturedTotal += n
            if capped && capturedTotal >= maxBytes {
                truncated = true
                break
            }
        }

        // End fstat on same fd — detect shrink/grow/replace.
        var end = stat()
        guard fstat(fd, &end) == 0 else {
            truncated = true
            sourceChanged = true
            let capDigest = capturedHasher.finalize().map { String(format: "%02x", $0) }.joined()
            return CopyResult(
                capturedBytes: capturedTotal,
                capturedSHA256: capDigest,
                sourceSHA256: nil,
                sourceHashVerifiable: false,
                truncated: true,
                initialSize: initialSize,
                endSize: -1,
                sourceChanged: true
            )
        }
        let endSize = Int(end.st_size)
        if end.st_dev != initialDev || end.st_ino != initialIno {
            sourceChanged = true
            truncated = true
        }
        if endSize != initialSize {
            sourceChanged = true
            truncated = true
        }
        // Unexpected early EOF without cap → shrink/race.
        if !capped && bytesRead < initialSize {
            sourceChanged = true
            truncated = true
        }
        // Growth: unread bytes remain.
        if !capped && !sourceChanged {
            let probe = read(fd, &buffer, 1)
            if probe > 0 {
                sourceChanged = true
                truncated = true
            }
        }

        let verifiable = !truncated && !sourceChanged && !capped
            && bytesRead == initialSize && endSize == initialSize
            && capturedTotal == initialSize

        let capDigest = capturedHasher.finalize().map { String(format: "%02x", $0) }.joined()
        let srcDigest: String? = verifiable
            ? sourceHasher.finalize().map { String(format: "%02x", $0) }.joined()
            : nil
        return CopyResult(
            capturedBytes: capturedTotal,
            capturedSHA256: capDigest,
            sourceSHA256: srcDigest,
            sourceHashVerifiable: verifiable,
            truncated: truncated || sourceChanged,
            initialSize: initialSize,
            endSize: endSize,
            sourceChanged: sourceChanged
        )
    }

    private func relativePath(of file: URL, under root: URL) -> String {
        let filePath = file.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if filePath.hasPrefix(prefix) {
            return String(filePath.dropFirst(prefix.count))
        }
        let anchor = root.lastPathComponent
        let comps = file.standardizedFileURL.pathComponents
        if let idx = comps.lastIndex(of: anchor), comps.index(after: idx) < comps.endIndex {
            return comps[comps.index(after: idx)...].joined(separator: "/")
        }
        return file.lastPathComponent
    }
}

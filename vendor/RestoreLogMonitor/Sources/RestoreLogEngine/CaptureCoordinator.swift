import Foundation

/// Owns exactly one capture session at a time and is the only place that may
/// change session state. Presentation layers read `CaptureStatus`; they never
/// start processes, parse logs, or decide success.
public actor CaptureCoordinator: CaptureEngine {
    private struct ActiveSession {
        let id: UUID
        let paths: SessionPaths
        let config: CaptureConfig
        let backendKind: String
        var backendExecutable: String
        var state: CaptureState
        let startedAt: Date
        var endedAt: Date?
        var backendHandle: BackendHandle?
        var stopReason: StopReason?
        var exitCode: Int32?
        var errorReason: String?
        var updaterWatcher: UpdaterOutputWatcher?
        var updaterSnapshot: UpdaterOutputWatcher.Snapshot?
        var guardTask: Task<Void, Never>?
    }

    private let backend: LogCaptureBackend
    private let store: EvidenceStore
    private var session: ActiveSession?

    public init(backend: LogCaptureBackend, store: EvidenceStore) {
        self.backend = backend
        self.store = store
    }

    // MARK: - Lifecycle

    public func beginCapture(config: CaptureConfig) async throws -> SessionHandle {
        if let current = session, !current.state.acceptsNewSession {
            throw CaptureError.invalidTransition(from: current.state, to: .starting)
        }
        // Replace prior session: stop any leftover watcher/guard first.
        if let prior = session {
            prior.guardTask?.cancel()
            if let w = prior.updaterWatcher { _ = await w.stop(cutoff: true) }
        }

        let id = UUID()
        let paths = try store.createSession(id: id)
        let startedAt = Date()
        var active = ActiveSession(
            id: id,
            paths: paths,
            config: config,
            backendKind: backend.kind,
            backendExecutable: "/usr/bin/log",
            state: .starting,
            startedAt: startedAt,
            endedAt: nil,
            backendHandle: nil,
            stopReason: nil,
            exitCode: nil,
            errorReason: nil,
            updaterWatcher: nil,
            updaterSnapshot: nil,
            guardTask: nil
        )
        session = active

        // Optional bounded pre-capture context is stored beside raw, never prepended.
        if let context = config.preCaptureContext, !context.isEmpty {
            do {
                try Data(context.utf8).write(to: paths.preCaptureContextURL, options: .atomic)
            } catch {
                active.state = .failed
                active.endedAt = Date()
                active.errorReason = "pre-capture context write failed: \(error)"
                session = active
                throw CaptureError.outputDirectoryNotWritable(paths.preCaptureContextURL.path)
            }
        }

        // P0-02: construct + start watcher and await ready barrier BEFORE backend.start().
        let watcher = UpdaterOutputWatcher(
            config: .init(
                watchRoot: config.updaterWatchRoot,
                sessionEvidenceRoot: paths.updaterOutputRootURL,
                sessionID: id,
                ecidHint: config.ecidHint
            )
        )
        active.updaterWatcher = watcher
        session = active
        let ready = await watcher.startAndAwaitReady()
        if !ready.ok {
            // X5: do not leave an unready backend running (never started), and
            // clean the abandoned .partial session directory so residue does not accumulate.
            _ = await watcher.stop(cutoff: true)
            active.state = .failed
            active.endedAt = Date()
            active.errorReason = "updater watcher ready barrier failed: \(ready.error ?? "unknown")"
            active.updaterWatcher = nil
            session = nil
            try? FileManager.default.removeItem(at: paths.directory)
            throw CaptureError.watcherNotReady(ready.error ?? "unknown")
        }

        do {
            let handle = try await backend.start(
                config: config,
                rawLogURL: paths.rawLogURL,
                stderrURL: paths.stderrLogURL
            )
            active.backendHandle = handle
            active.backendExecutable = handle.executablePath
            active.state = .recording
            active.guardTask = startResourceGuard(sessionID: id)
            session = active

            return SessionHandle(
                sessionID: id,
                outputDirectory: paths.directory.path,
                rawLogPath: paths.rawLogURL.path,
                stderrLogPath: paths.stderrLogURL.path,
                backendPID: handle.pid,
                startedAtUTC: startedAt
            )
        } catch {
            // Cleanup watcher on backend failure.
            _ = await watcher.stop(cutoff: true)
            active.updaterWatcher = nil
            active.state = .failed
            active.endedAt = Date()
            active.errorReason = String(describing: error)
            session = active
            throw CaptureError.backendStartFailed(String(describing: error))
        }
    }

    public func getStatus(sessionID: UUID) async throws -> CaptureStatus {
        guard let snapshot = session, snapshot.id == sessionID else {
            throw CaptureError.sessionNotFound(sessionID)
        }

        var running = false
        if let handle = snapshot.backendHandle {
            running = await backend.isRunning(handle: handle)
            if !running {
                let code = await backend.waitForExit(handle: handle)
                // F05 — re-read the session AFTER both suspensions. A concurrent
                // stopCapture may have advanced it to STOPPING/FINALIZING while we
                // were awaiting; writing the pre-await copy back would clobber
                // that newer state and fabricate an INTERRUPTED that never
                // happened. Only a session still in .recording may be declared
                // interrupted.
                if var latest = session, latest.id == sessionID, latest.state == .recording {
                    latest.exitCode = code
                    latest.endedAt = Date()
                    latest.stopReason = .processExited
                    latest.state = .interrupted
                    session = latest
                }
            }
        }

        guard let active = session, active.id == sessionID else {
            throw CaptureError.sessionNotFound(sessionID)
        }

        let events = Self.scanEvents(paths: active.paths)
        let bytes = (try? Integrity.byteSize(ofFileAt: active.paths.rawLogURL)) ?? 0
        let lines = (try? Integrity.lineCount(ofFileAt: active.paths.rawLogURL)) ?? 0

        return CaptureStatus(
            sessionID: active.id,
            state: active.state,
            health: Self.health(state: active.state, running: running, eventCount: events.count),
            coverage: events.isEmpty ? .unverified : .partial,
            startedAtUTC: active.startedAt,
            endedAtUTC: active.endedAt,
            rawByteCount: bytes,
            rawLineCount: lines,
            capturedEventCount: events.count,
            backendPID: active.backendHandle?.pid
        )
    }

    public func stopCapture(sessionID: UUID) async throws -> StopResult {
        try await stopCapture(sessionID: sessionID, reason: .userRequested)
    }

    /// Internal/guard entry point. The public user stop always maps to
    /// USER_REQUESTED; a resource stop records RESOURCE_LIMIT so it can never
    /// be presented as a user action.
    public func stopCapture(sessionID: UUID, reason: StopReason) async throws -> StopResult {
        guard var active = session, active.id == sessionID else {
            throw CaptureError.sessionNotFound(sessionID)
        }
        guard active.state == .recording else {
            throw CaptureError.invalidTransition(from: active.state, to: .stopping)
        }

        active.guardTask?.cancel()
        active.guardTask = nil
        active.state = .stopping
        session = active

        // P0-04: stop watcher at cutoff BEFORE/with stop — no post-stop capture into session.
        if let watcher = active.updaterWatcher {
            active.updaterSnapshot = await watcher.stop(cutoff: true)
            active.updaterWatcher = nil
            session = active
        }

        if let handle = active.backendHandle {
            await backend.requestTermination(handle: handle)
            active.exitCode = await backend.waitForExit(handle: handle)
        }
        active.stopReason = reason
        active.endedAt = Date()
        active.state = .finalizing
        session = active

        return StopResult(
            sessionID: sessionID,
            reason: reason,
            exitCode: active.exitCode,
            durationSeconds: (active.endedAt ?? Date()).timeIntervalSince(active.startedAt)
        )
    }

    /// Explicit discard after a stop. Only this session's own `.partial`
    /// directory may be removed. Other sessions, saved logs and history are
    /// never referenced.
    public func discard(sessionID: UUID) async throws -> DiscardResult {
        guard var active = session, active.id == sessionID else {
            throw CaptureError.sessionNotFound(sessionID)
        }
        guard active.state == .finalizing || active.state == .interrupted || active.state == .failed else {
            throw CaptureError.invalidTransition(from: active.state, to: .idle)
        }
        if let handle = active.backendHandle, await backend.isRunning(handle: handle) {
            throw CaptureError.invalidTransition(from: active.state, to: .stopping)
        }
        active.guardTask?.cancel()
        active.guardTask = nil
        if let watcher = active.updaterWatcher {
            _ = await watcher.stop(cutoff: true)
            active.updaterWatcher = nil
        }
        let dir = active.paths.directory.standardizedFileURL
        let root = store.root.standardizedFileURL
        let expected = root.appendingPathComponent("\(sessionID.uuidString).partial", isDirectory: true).standardizedFileURL
        guard dir == expected,
              dir.path.hasPrefix(root.path + "/") else {
            throw CaptureError.outputDirectoryNotWritable(dir.path)
        }
        do {
            try FileManager.default.removeItem(at: dir)
        } catch {
            throw CaptureError.outputDirectoryNotWritable(dir.path)
        }
        session = nil
        return DiscardResult(sessionID: sessionID, removedDirectory: dir.path)
    }

    // MARK: - Finalization

    public func finalize(sessionID: UUID) async throws -> ExportResult {
        try await finalize(sessionID: sessionID, mode: .withDiagnostic, progress: nil)
    }

    /// Save-only mode hashes the immutable raw and writes necessary metadata
    /// without parsing JSON, classifying events, or generating diagnostic.log.
    /// `.withDiagnostic` preserves the 014G/014H analysis semantics.
    public func finalize(
        sessionID: UUID,
        mode: FinalizeMode,
        displayName: String? = nil,
        progress: (@Sendable (FinalizeProgress) -> Void)? = nil
    ) async throws -> ExportResult {
        let started = Date()
        let isSaveOnly = mode == .saveOnly
        guard var active = session, active.id == sessionID else {
            throw CaptureError.sessionNotFound(sessionID)
        }
        // F05 — an INTERRUPTED session still owns the bytes it managed to
        // capture. It is admitted here as a SALVAGE entry so that evidence can
        // be committed, but it is never treated as a normal stop: the terminal
        // state below can only ever be SAVED_PARTIAL or ERROR, never
        // SAVED_VERIFIED, and the record carries the interruption in
        // errorReason / missingEvidence.
        guard active.state == .finalizing || active.state == .interrupted else {
            throw CaptureError.invalidTransition(from: active.state, to: .finalizing)
        }
        let isSalvage = active.state == .interrupted
        active.guardTask?.cancel()
        active.guardTask = nil

        let paths = active.paths
        progress?(FinalizeProgress(stage: "PREPARING", processedBytes: 0, totalBytes: 0, elapsedSeconds: Date().timeIntervalSince(started)))
        let events = isSaveOnly ? [] : Self.scanEvents(paths: paths)

        // Watcher should already be stopped at stopCapture cutoff. If still present
        // (interrupted/salvage path), stop with bound-only residual flush.
        var updaterSnapshot: UpdaterOutputWatcher.Snapshot? = active.updaterSnapshot
        if let watcher = active.updaterWatcher {
            updaterSnapshot = await watcher.stop(cutoff: true)
            active.updaterWatcher = nil
            active.updaterSnapshot = updaterSnapshot
            session = active
        }

        var files: [EvidenceFile] = []
        var missingEvidence: [String] = []
        // F03b — `verified` must be EARNED, never assumed. `.unchecked` is the
        // only honest starting point; this becomes `.verified` below, and only
        // after the checksum manifest has been written and re-verified from disk.
        var integrity: IntegrityStatus = .unchecked
        // DIAGNOSTIC_STATUS_SEPARATION — diagnostic outcome is independent of raw integrity.
        var diagnosticStatus: DiagnosticStatus = .unchecked

        do {
            // FIX-002: hash immutable raw first; never rewrite restore.log.
            let rawSize = try Integrity.byteSize(ofFileAt: paths.rawLogURL)
            let rawHash = try Integrity.sha256(ofFileAt: paths.rawLogURL) { done, total in
                progress?(FinalizeProgress(
                    stage: "HASHING_RAW",
                    processedBytes: done,
                    totalBytes: total,
                    elapsedSeconds: Date().timeIntervalSince(started)
                ))
            }
            files.append(
                EvidenceFile(role: "raw-log", relativePath: "restore.log", byteSize: rawSize, sha256: rawHash)
            )
            if FileManager.default.fileExists(atPath: paths.stderrLogURL.path) {
                let errSize = try Integrity.byteSize(ofFileAt: paths.stderrLogURL)
                let errHash = try Integrity.sha256(ofFileAt: paths.stderrLogURL)
                files.append(
                    EvidenceFile(
                        role: "capture-stderr",
                        relativePath: "capture-stderr.log",
                        byteSize: errSize,
                        sha256: errHash
                    )
                )
            }
            if FileManager.default.fileExists(atPath: paths.preCaptureContextURL.path) {
                let preSize = try Integrity.byteSize(ofFileAt: paths.preCaptureContextURL)
                let preHash = try Integrity.sha256(ofFileAt: paths.preCaptureContextURL)
                files.append(
                    EvidenceFile(
                        role: "pre-capture-context",
                        relativePath: "pre-capture-context.log",
                        byteSize: preSize,
                        sha256: preHash
                    )
                )
                missingEvidence.append("Pre-capture context is a bounded separate file; raw starts after the trigger")
            }
        } catch {
            integrity = .failed
            diagnosticStatus = .skipped
            missingEvidence.append("Raw log unreadable: \(error)")
        }

        if integrity != .failed && !isSaveOnly {
            progress?(FinalizeProgress(stage: "BUILDING_DIAGNOSTIC", processedBytes: 0, totalBytes: 0, elapsedSeconds: Date().timeIntervalSince(started)))
            do {
                // Sibling diagnostic.log is a derived view; raw stays authoritative.
                // Failure here must NOT flip integrityStatus to .failed.
                _ = try DiagnosticLogBuilder.build(fromRaw: paths.rawLogURL, to: paths.diagnosticLogURL)
                let diagSize = try Integrity.byteSize(ofFileAt: paths.diagnosticLogURL)
                let diagHash = try Integrity.sha256(ofFileAt: paths.diagnosticLogURL)
                files.append(
                    EvidenceFile(
                        role: "diagnostic-log",
                        relativePath: "diagnostic.log",
                        byteSize: diagSize,
                        sha256: diagHash
                    )
                )
                diagnosticStatus = .ok
            } catch {
                diagnosticStatus = .failed
                missingEvidence.append("Diagnostic log failed: \(error)")
                // Do not register a fake diagnostic checksum entry.
            }
        }

        if isSaveOnly {
            diagnosticStatus = .skipped
            missingEvidence.append("Diagnostic analysis deferred until explicit analysis/export")
        }
        progress?(FinalizeProgress(stage: "WRITING_METADATA", processedBytes: 0, totalBytes: 0, elapsedSeconds: Date().timeIntervalSince(started)))
        // Register updater-output artifacts actually present (never invent body).
        let updaterFields = Self.ingestUpdaterArtifacts(
            paths: paths,
            snapshot: updaterSnapshot,
            files: &files,
            missingEvidence: &missingEvidence
        )

        if isSaveOnly {
            missingEvidence.append("Event scan deferred until explicit analysis/export")
        } else if events.isEmpty {
            missingEvidence.append("No verified restore event")
        }
        missingEvidence.append("System archive not collected (archive collection is D4 scope)")
        if active.exitCode == nil {
            missingEvidence.append("Capture process exit not observed")
        }
        if active.stopReason == .resourceLimit {
            missingEvidence.append("Capture stopped by resource limit (duration/disk/RSS)")
        }

        // F05 — salvage metadata. An interrupted session must describe what was
        // actually observed and what could not be: the real interrupt reason,
        // the known observation window (startedAtUTC/endedAtUTC are already on
        // the session), and the fact that continuity was never verified. The
        // exit status stays UNKNOWN when it was not observed; it is never
        // upgraded to a normal end.
        if isSalvage {
            if active.errorReason == nil {
                if let code = active.exitCode {
                    active.errorReason = "capture process exited unexpectedly (exit status \(code))"
                } else {
                    active.errorReason = "capture process exited unexpectedly (exit status unknown)"
                }
            }
            missingEvidence.append("Session interrupted: capture process exited before finalization")
            missingEvidence.append("Capture continuity not verified: observation ended at interruption")
        }

        let coverage: CoverageStatus = (isSaveOnly || events.isEmpty) ? .unverified : .partial
        let archiveStatus: ArchiveStatus = .notRequested

        // F03a — commit protocol. The raw-evidence checksum manifest must be
        // written AND proven from disk before any metadata that could claim
        // `verified` is published. Order:
        //   WRITES_COMPLETE (guaranteed by the FINALIZING contract)
        //   -> HASH_COMPUTED -> MANIFEST_WRITTEN -> READBACK_VERIFIED
        //   -> METADATA_COMMITTED.
        // A failure here publishes nothing: the raw evidence is left untouched
        // and the session directory simply has no completion marker.
        if integrity != .failed {
            let sums = files.map { "\($0.sha256)  \($0.relativePath)" }
                .joined(separator: "\n") + "\n"
            do {
                try Data(sums.utf8).write(to: paths.sha256SumsURL, options: .atomic)
                try Self.verifyChecksumFile(paths: paths, expected: files)
                integrity = .verified
            } catch {
                active.state = .failed
                active.endedAt = active.endedAt ?? Date()
                active.errorReason = "integrity verification failed: \(error)"
                session = active
                throw CaptureError.integrityCheckFailed(String(describing: error))
            }
        }

        // SAVED_VERIFIED is deliberately unreachable in D0: it would require a
        // collected archive *and* a positive event count. Integrity alone is
        // never enough to call a capture verified.
        let terminalState: CaptureState
        if integrity == .failed {
            terminalState = .failed
        } else if coverage == .unverified || archiveStatus != .collected {
            terminalState = .savedPartial
        } else {
            terminalState = .savedVerified
        }

        let command = [active.backendExecutable] + active.config.profile.commandArguments
        // An interrupted acquisition is degraded by definition, even when the
        // bytes that did land hash correctly. Integrity is not continuity.
        // Diagnostic failure degrades session health; it does not fail raw integrity.
        let captureHealth: CaptureHealth
        if isSalvage || diagnosticStatus == .failed {
            captureHealth = .degraded
        } else {
            captureHealth = Self.health(state: terminalState, running: false, eventCount: events.count)
        }
        let record = SessionRecord(
            sessionID: active.id,
            sessionDisplayName: displayName,
            captureState: terminalState,
            captureHealth: captureHealth,
            startedAtUTC: Self.iso8601(active.startedAt),
            endedAtUTC: active.endedAt.map(Self.iso8601),
            captureProfile: active.config.profile.id,
            captureCommand: command,
            captureBackend: active.backendKind,
            eventCount: events.count,
            coverageStatus: coverage,
            archiveStatus: archiveStatus,
            integrityStatus: integrity,
            diagnosticStatus: diagnosticStatus,
            analysisDeferred: isSaveOnly ? true : false,
            updaterOutputStatus: updaterFields.status,
            updaterStdoutPresent: updaterFields.stdoutPresent,
            earlyWatcherStarted: updaterFields.earlyWatcherStarted,
            firstFatalCheckpoint: updaterFields.firstFatalCheckpoint,
            updaterReturnCode: updaterFields.updaterReturnCode,
            hardwareRootCause: "UNVERIFIED",
            updaterStatusLayers: updaterFields.layers,
            files: files,
            missingEvidence: missingEvidence,
            errorReason: active.errorReason
        )

        // F03a — metadata is the completion marker for this export, so it is
        // committed LAST.
        do {
            try store.writeJSON(record, to: paths.sessionJSONURL)
        } catch {
            // Never leave a metadata file that could be mistaken for a finished,
            // verified export. Only a regular file is removed; any other kind of
            // obstacle at that path is left exactly as found.
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(
                atPath: paths.sessionJSONURL.path,
                isDirectory: &isDirectory
            ), !isDirectory.boolValue {
                try? FileManager.default.removeItem(at: paths.sessionJSONURL)
            }
            active.state = .failed
            active.endedAt = active.endedAt ?? Date()
            active.errorReason = "metadata commit failed: \(error)"
            session = active
            throw error
        }

        active.state = terminalState
        session = active

        progress?(FinalizeProgress(stage: "COMPLETE", processedBytes: 0, totalBytes: 0, elapsedSeconds: Date().timeIntervalSince(started)))
        return ExportResult(
            sessionID: active.id,
            record: record,
            sessionJSONPath: paths.sessionJSONURL.path,
            sha256SumsPath: paths.sha256SumsURL.path
        )
    }

    public func getEventSummary(sessionID: UUID) async throws -> EventSummary {
        guard let active = session, active.id == sessionID else {
            throw CaptureError.sessionNotFound(sessionID)
        }
        let events = Self.scanEvents(paths: active.paths)
        var counts: [String: Int] = [:]
        for event in events {
            let key = event.tier?.rawValue ?? "UNCLASSIFIED"
            counts[key, default: 0] += 1
        }
        // P0-10: do not reload entire raw for terminal probe; use already-scanned events.
        let terminalHit = events.contains { ev in
            EventTaxonomy.terminalEventDetected(inLogText: ev.rawLine)
        }
        return EventSummary(
            sessionID: sessionID,
            totalEvents: events.count,
            countsByTier: counts,
            taxonomyVersion: EventTaxonomy.version,
            terminalEventDetected: terminalHit
        )
    }

    // MARK: - Resource guard

    private func startResourceGuard(sessionID: UUID) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let interval = await self.guardInterval(sessionID: sessionID)
                if interval <= 0 { return }
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch { return }
                if Task.isCancelled { return }
                let stop = await self.guardTick(sessionID: sessionID)
                if stop { return }
            }
        }
    }

    private func guardInterval(sessionID: UUID) -> Double {
        guard let active = session, active.id == sessionID else { return 0 }
        return max(1, active.config.limits.sampleIntervalSeconds)
    }

    /// Returns true when the guard itself requested a stop (task should end).
    private func guardTick(sessionID: UUID) async -> Bool {
        guard let active = session, active.id == sessionID, active.state == .recording else { return true }
        let limits = active.config.limits
        if Date().timeIntervalSince(active.startedAt) >= limits.maxDurationSeconds {
            try? await stopCapture(sessionID: sessionID, reason: .resourceLimit)
            return true
        }
        if let free = Self.freeDiskBytes(at: active.paths.directory), free < limits.minFreeDiskBytes {
            try? await stopCapture(sessionID: sessionID, reason: .resourceLimit)
            return true
        }
        if let pid = active.backendHandle?.pid,
           let rss = Self.residentBytes(pid: pid),
           rss > limits.maxResidentBytes {
            try? await stopCapture(sessionID: sessionID, reason: .resourceLimit)
            return true
        }
        return false
    }

    private static func freeDiskBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// `ps` is a read-only host probe; it is never a device command. CPU is not
    /// read here because a short CPU peak must not stop a restore capture.
    private static func residentBytes(pid: Int32) -> Int64? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-o", "rss=", "-p", "\(pid)"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let kb = Int64(text) else { return nil }
            return kb * 1024
        } catch { return nil }
    }

    // MARK: - Helpers

    /// Re-reads the checksum file and recomputes every hash from disk. A
    /// mismatch fails finalization instead of being logged and ignored.
    ///
    /// Visibility is `internal` (not `private`) so the tamper-detection path can
    /// be driven directly by tests against real on-disk bytes. This is a
    /// visibility change only; behaviour is unchanged.
    static func verifyChecksumFile(paths: SessionPaths, expected: [EvidenceFile]) throws {
        let text = try String(contentsOf: paths.sha256SumsURL, encoding: .utf8)
        var seen = Set<String>()
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            let recordedHash = String(parts[0])
            let relative = parts[1].trimmingCharacters(in: .whitespaces)
            let url = paths.directory.appendingPathComponent(relative)
            let actual = try Integrity.sha256(ofFileAt: url)
            guard actual == recordedHash else {
                throw CaptureError.integrityCheckFailed("hash mismatch for \(relative)")
            }
            seen.insert(relative)
        }
        for file in expected where !seen.contains(file.relativePath) {
            throw CaptureError.integrityCheckFailed("checksum entry missing for \(file.relativePath)")
        }
    }

        private static func scanEvents(paths: SessionPaths) -> [CaptureEvent] {
        guard FileManager.default.fileExists(atPath: paths.rawLogURL.path) else { return [] }
        var events: [CaptureEvent] = []
        do {
            try Integrity.forEachLine(url: paths.rawLogURL) { _, raw in
                guard let rule = EventTaxonomy.classify(raw) else { return }
                let parsed = LogLineParser.parse(raw)
                events.append(
                    CaptureEvent(
                        timestampUTC: parsed.timestampUTC ?? Date(),
                        process: parsed.process,
                        rawLine: raw,
                        taxonomyID: rule.id,
                        tier: rule.tier
                    )
                )
            }
        } catch {
            return events
        }
        return events
    }

private static func health(state: CaptureState, running: Bool, eventCount: Int) -> CaptureHealth {
        switch state {
        case .recording:
            if !running { return .degraded }
            return eventCount > 0 ? .healthy : .unconfirmed
        case .failed, .interrupted:
            return .degraded
        default:
            return .unconfirmed
        }
    }


    private struct UpdaterIngest {
        var status: UpdaterOutputStatus
        var stdoutPresent: UpdaterStdoutPresence
        var earlyWatcherStarted: Bool
        var firstFatalCheckpoint: String?
        var updaterReturnCode: String?
        var layers: UpdaterSessionSummary?
    }

    /// P0-STATUS: order-independent reduce. Empty cannot erase proven body.
    public static func reduceUpdaterStatus(
        records: [UpdaterOutputWatcher.CaptureRecord],
        failedReason: String?,
        earlyWatcherStarted: Bool
    ) -> UpdaterSessionSummary {
        // Merge by sourcePath: worst completeness + max bytes + OR quarantine.
        struct Acc {
            var rec: UpdaterOutputWatcher.CaptureRecord
        }
        var byPath: [String: Acc] = [:]
        for r in records {
            let key = r.sourcePath
            if var existing = byPath[key] {
                if r.capturedBytes > existing.rec.capturedBytes {
                    existing.rec.capturedBytes = r.capturedBytes
                    existing.rec.capturedSHA256 = r.capturedSHA256
                    existing.rec.fileCount = max(existing.rec.fileCount, r.fileCount)
                }
                existing.rec.omittedFileCount = max(existing.rec.omittedFileCount, r.omittedFileCount)
                existing.rec.quarantined = existing.rec.quarantined || r.quarantined
                if r.bindingState == .quarantined { existing.rec.bindingState = .quarantined }
                // Worst completeness lattice
                existing.rec.completeness = worseCompleteness(existing.rec.completeness, r.completeness)
                existing.rec.empty = existing.rec.empty && r.empty && r.capturedBytes == 0 && existing.rec.capturedBytes == 0
                existing.rec.sourceHashVerifiable = existing.rec.sourceHashVerifiable && r.sourceHashVerifiable
                if r.stoppedDuringCapture { existing.rec.stoppedDuringCapture = true }
                if !r.sourceInventoryComplete { existing.rec.sourceInventoryComplete = false }
                byPath[key] = existing
            } else {
                byPath[key] = Acc(rec: r)
            }
        }
        let merged = byPath.values.map(\.rec).sorted { $0.sourcePath < $1.sourcePath }

        var dirsObserved: [String] = []
        var emptyDirs: [String] = []
        var unreadableDirs: [String] = []
        var boundDirs: [String] = []
        var unboundDirs: [String] = []
        var quarantinedDirs: [String] = []
        var filesObserved = 0
        var bytesTotal = 0
        var anyComplete = false
        var anyPartial = false
        var anyProven = false
        var missing: [String] = []
        var hasFailed = failedReason != nil && !(failedReason?.isEmpty ?? true)
        var hasQuarantine = false
        var hasBoundBody = false
        var hasEmptyBound = false
        var hasMiss = false
        var hasUnbound = false

        if let reason = failedReason, !reason.isEmpty {
            missing.append("Updater watcher abnormal exit/failure: \(reason) — possible lost updater evidence")
        }

        for rec in merged {
            dirsObserved.append(rec.sourcePath)
            filesObserved += rec.fileCount
            bytesTotal += rec.capturedBytes
            if rec.timingNote.contains("dir-unreadable") || rec.timingNote.contains("scan-failed") {
                unreadableDirs.append(rec.sourcePath)
            }
            if rec.quarantined || rec.bindingState == .quarantined {
                quarantinedDirs.append(rec.sourcePath)
                hasQuarantine = true
                missing.append("Updater output quarantined (unbound): \(rec.sourcePath)")
                continue
            }
            if rec.bindingState == .unbound {
                unboundDirs.append(rec.sourcePath)
                hasUnbound = true
                missing.append("Updater dir unbound (no ecidHint/nonce/session-UUID match): \(rec.sourcePath)")
                continue
            }
            // Bound
            boundDirs.append(rec.sourcePath)
            if rec.capturedBytes > 0 {
                hasBoundBody = true
                anyProven = true
            }
            if rec.empty && rec.capturedBytes == 0 && rec.completeness == .emptyDirectory {
                emptyDirs.append(rec.sourcePath)
                hasEmptyBound = true
                missing.append("Updater output empty staging: \(rec.sourcePath)")
            } else if rec.completeness == .truncated || rec.completeness == .limitExceeded || rec.completeness == .partial || rec.stoppedDuringCapture {
                anyPartial = true
                if rec.completeness == .truncated {
                    missing.append("Updater output truncated (source larger than cap): \(rec.sourcePath)")
                }
                if rec.completeness == .limitExceeded {
                    missing.append("Updater output limit exceeded (files/bytes): \(rec.sourcePath) omitted=\(rec.omittedFileCount)")
                }
                if rec.omittedFileCount > 0 {
                    missing.append("Updater output omitted files disclosed: \(rec.omittedFileCount) at \(rec.sourcePath)")
                }
                if !rec.sourceHashVerifiable {
                    missing.append("Updater source SHA unverifiable: \(rec.sourcePath)")
                }
            } else if rec.completeness == .complete {
                if !rec.sourceHashVerifiable || rec.omittedFileCount > 0 || !rec.sourceInventoryComplete {
                    anyPartial = true
                    missing.append("Updater claimed complete but source unverifiable/omitted=\(rec.omittedFileCount): \(rec.sourcePath)")
                } else {
                    anyComplete = true
                    anyProven = true
                }
            } else if rec.completeness == .miss {
                hasMiss = true
                missing.append("Updater output miss (blind zone / gone): \(rec.sourcePath)")
            }
        }

        // Lattice join (highest wins) — NEVER last-wins; empty cannot erase proven body.
        let status: UpdaterOutputStatus
        let stdout: UpdaterStdoutPresence
        if hasFailed && !anyProven {
            status = .failed
            stdout = .no
        } else if hasBoundBody && hasQuarantine {
            // Foreign quarantine must not erase own body.
            status = anyComplete && !anyPartial ? .capturedComplete : .capturedPartial
            stdout = .yes
        } else if hasQuarantine && !hasBoundBody {
            status = .quarantined
            stdout = .unverified
        } else if anyPartial || (hasBoundBody && !anyComplete) {
            status = .capturedPartial
            stdout = .yes
        } else if anyComplete {
            status = .capturedComplete
            stdout = .yes
        } else if hasEmptyBound && !hasBoundBody {
            status = .emptyDirectory
            stdout = .emptyDir
        } else if hasMiss && !hasBoundBody {
            status = .miss
            stdout = .no
        } else if earlyWatcherStarted && merged.isEmpty {
            status = hasFailed ? .failed : .miss
            stdout = .no
            if !hasFailed {
                missing.append("Updater output: no updater_output-* observed during session")
            }
        } else if hasUnbound && !hasBoundBody && !hasQuarantine {
            status = .miss
            stdout = .no
        } else if !earlyWatcherStarted {
            status = .notAttempted
            stdout = .unverified
        } else {
            status = .miss
            stdout = .no
        }

        let rollup: AttributionRollup
        if !boundDirs.isEmpty && (!unboundDirs.isEmpty || !quarantinedDirs.isEmpty) {
            rollup = .mixed
        } else if !boundDirs.isEmpty {
            rollup = .bound
        } else if !quarantinedDirs.isEmpty {
            rollup = .conflict
        } else if !unboundDirs.isEmpty {
            rollup = .unbound
        } else {
            rollup = .none
        }

        let missingSorted = Array(Set(missing)).sorted()
        return UpdaterSessionSummary(
            updaterOutputStatus: status,
            stdoutPresent: stdout,
            summaryDerivationVersion: "status-reduce-v1",
            observation: SourceObservation(
                dirsObserved: dirsObserved.sorted(),
                filesObservedCount: filesObserved,
                emptyDirs: emptyDirs.sorted(),
                unreadableDirs: unreadableDirs.sorted()
            ),
            integrity: CaptureIntegrityLayer(
                capturedBytesTotal: bytesTotal,
                anyCompleteBody: anyComplete,
                anyPartialBody: anyPartial,
                anyProvenBody: anyProven
            ),
            attribution: AttributionLayer(
                boundDirs: boundDirs.sorted(),
                unboundDirs: unboundDirs.sorted(),
                quarantinedDirs: quarantinedDirs.sorted(),
                conflictDirs: [],
                rollup: rollup
            ),
            missingEvidence: missingSorted
        )
    }

    private static func worseCompleteness(
        _ a: UpdaterOutputWatcher.CaptureCompleteness,
        _ b: UpdaterOutputWatcher.CaptureCompleteness
    ) -> UpdaterOutputWatcher.CaptureCompleteness {
        let rank: [UpdaterOutputWatcher.CaptureCompleteness: Int] = [
            .miss: 0,
            .emptyDirectory: 1,
            .complete: 2,
            .partial: 3,
            .truncated: 4,
            .limitExceeded: 5,
            .quarantined: 6,
        ]
        return (rank[a] ?? 0) >= (rank[b] ?? 0) ? a : b
    }

    private static func ingestUpdaterArtifacts(
        paths: SessionPaths,
        snapshot: UpdaterOutputWatcher.Snapshot?,
        files: inout [EvidenceFile],
        missingEvidence: inout [String]
    ) -> UpdaterIngest {
        let fm = FileManager.default
        let early = snapshot?.earlyWatcherStarted ?? false
        let finalSummary: UpdaterSessionSummary = {
            if let snap = snapshot {
                return reduceUpdaterStatus(
                    records: snap.records,
                    failedReason: snap.failedReason,
                    earlyWatcherStarted: early
                )
            }
            return UpdaterSessionSummary(
                updaterOutputStatus: .notAttempted,
                stdoutPresent: .unverified
            )
        }()

        missingEvidence.append(contentsOf: finalSummary.missingEvidence)

        // Hash only files under listed dest paths / evidence root that belong to snapshot records.
        // P0-STOP belt: if records empty but tree non-empty → disclose orphan / failed.
        let root = paths.updaterOutputRootURL.standardizedFileURL
        var allowedPrefixes: [String] = []
        if let snap = snapshot {
            for rec in snap.records {
                if let dest = rec.destPath, !dest.isEmpty {
                    let p = dest.hasSuffix("/") ? dest : dest + "/"
                    allowedPrefixes.append(p)
                }
            }
        }
        var orphanBytes = 0
        if fm.fileExists(atPath: root.path) {
            if let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let file as URL in en {
                    let file = file.standardizedFileURL
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: file.path, isDirectory: &isDir), !isDir.boolValue else { continue }
                    let underAllowed: Bool
                    if allowedPrefixes.isEmpty {
                        // Quarantine notes / coverage may still exist; allow root-level meta only.
                        underAllowed = file.deletingLastPathComponent().path == root.path
                    } else {
                        underAllowed = allowedPrefixes.contains { file.path.hasPrefix($0) } || file.deletingLastPathComponent().path == root.path
                    }
                    if !underAllowed {
                        if let sz = try? Integrity.byteSize(ofFileAt: file) {
                            orphanBytes += sz
                        }
                        continue
                    }
                    guard let size = try? Integrity.byteSize(ofFileAt: file),
                          let hash = try? Integrity.sha256(ofFileAt: file) else { continue }
                    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
                    guard file.path.hasPrefix(rootPath) else { continue }
                    let rel = "updater-output/" + String(file.path.dropFirst(rootPath.count))
                    files.append(EvidenceFile(role: "updater-output", relativePath: rel, byteSize: size, sha256: hash))
                }
            }
        }
        var status = finalSummary.updaterOutputStatus
        if orphanBytes > 0 && (snapshot?.records.isEmpty ?? true) {
            missingEvidence.append("post-stop-or-orphan-files bytes=\(orphanBytes)")
            if status == .miss || status == .notAttempted {
                status = .failed
            }
        }

        let coverage = """
        EARLY_WATCHER_STARTED=\(early ? "YES" : "NO")
        UPDATER_OUTPUT_STATUS=\(status.rawValue)
        UPDATER_STDOUT_PRESENT=\(finalSummary.stdoutPresent.rawValue)
        SUMMARY_DERIVATION=\(finalSummary.summaryDerivationVersion)
        HOST_OUTPUT_BODY_EVER_EXISTED=UNVERIFIED
        REAL_UPDATER_BODY_CAPTURED=NO
        HARDWARE_ROOT_CAUSE=UNVERIFIED
        BINDING_AUTHORITY=SESSION_UUID_NAME_OR_ECID_HINT_OR_NONCE
        PRODUCTION_BINDING_WITHOUT_ECID_OR_NONCE=UNBOUND_OR_QUARANTINED
        OFFLINE_SYNTH_SUCCESS_NE_REAL_CONFIGURATOR_BODY=YES
        """
        try? Data(coverage.utf8).write(to: paths.evidenceCoverageURL, options: .atomic)
        if let size = try? Integrity.byteSize(ofFileAt: paths.evidenceCoverageURL),
           let hash = try? Integrity.sha256(ofFileAt: paths.evidenceCoverageURL) {
            files.append(
                EvidenceFile(
                    role: "evidence-coverage",
                    relativePath: "EVIDENCE_COVERAGE.ini",
                    byteSize: size,
                    sha256: hash
                )
            )
        }

        if let snap = snapshot, let data = try? JSONEncoder().encode(snap.records) {
            try? data.write(to: paths.updaterOutputCaptureJSONURL, options: .atomic)
            if let size = try? Integrity.byteSize(ofFileAt: paths.updaterOutputCaptureJSONURL),
               let hash = try? Integrity.sha256(ofFileAt: paths.updaterOutputCaptureJSONURL) {
                files.append(
                    EvidenceFile(
                        role: "updater-capture-meta",
                        relativePath: "UPDATER_OUTPUT_CAPTURE.json",
                        byteSize: size,
                        sha256: hash
                    )
                )
            }
        }

        var layers = finalSummary
        layers.updaterOutputStatus = status

        return UpdaterIngest(
            status: status,
            stdoutPresent: layers.stdoutPresent,
            earlyWatcherStarted: early,
            firstFatalCheckpoint: nil,
            updaterReturnCode: nil,
            layers: layers
        )
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func iso8601(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }
}

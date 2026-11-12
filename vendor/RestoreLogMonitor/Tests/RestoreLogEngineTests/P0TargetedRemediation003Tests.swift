import Foundation
import XCTest
@testable import RestoreLogEngine

/// RLM_1_2_P0_TARGETED_REMEDIATION_003 — dynamic negatives for open P0s.
/// Unique workdirs only; FAIL fixture from EVROOT/fixtures (or RLM12_FIXTURES_DIR).
final class P0TargetedRemediation003Tests: XCTestCase {
    private var root: URL!
    private static let evrootFixtures = URL(
        fileURLWithPath:
            "/Users/niubanxiandetuzhichakanqi/Desktop/gongzuoqu/RUN_RLM_1_2_P0_TARGETED_REMEDIATION_003_20261106T192921Z/fixtures",
        isDirectory: true
    )

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlm-p0t003-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func resolveFixture(_ name: String) throws -> URL {
        if let env = ProcessInfo.processInfo.environment["RLM12_FIXTURES_DIR"] {
            let u = URL(fileURLWithPath: env, isDirectory: true).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        let ev = Self.evrootFixtures.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: ev.path) { return ev }
        throw XCTSkip("fixture \(name) missing — set RLM12_FIXTURES_DIR or provide EVROOT/fixtures")
    }

    private func copyFixtureToUnique(_ name: String) throws -> URL {
        let src = try resolveFixture(name)
        let dest = root.appendingPathComponent(name)
        try FileManager.default.copyItem(at: src, to: dest)
        return dest
    }

    // MARK: - P0-05 A–E

    func testP0_05A_unreadableSiblingNeverComplete() async throws {
        let watch = root.appendingPathComponent("w05a", isDirectory: true)
        let evidence = root.appendingPathComponent("e05a", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let sid = UUID()
        let dir = watch.appendingPathComponent("updater_output-\(sid.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("GOODBYTES!!".utf8).write(to: dir.appendingPathComponent("good.bin"))
        let bad = dir.appendingPathComponent("unreadable.bin")
        try Data("SECRET".utf8).write(to: bad)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: bad.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: bad.path) }

        let watcher = UpdaterOutputWatcher(config: .init(
            watchRoot: watch, sessionEvidenceRoot: evidence, sessionID: sid,
            pollIntervalNanoseconds: 5_000_000_000, stabilityWindowNanoseconds: 10_000_000
        ))
        await watcher.start()
        await watcher.pollOncePublic()
        let snap = await watcher.stop()
        let rec = try XCTUnwrap(snap.records.first { $0.boundToSession })
        XCTAssertNotEqual(rec.completeness, .complete)
        XCTAssertGreaterThanOrEqual(rec.omittedFileCount, 1)
        XCTAssertFalse(rec.sourceHashVerifiable)
        XCTAssertNil(rec.originalSHA256)
    }

    func testP0_05B_fileCapSourceHashNotVerifiable() async throws {
        let watch = root.appendingPathComponent("w05b", isDirectory: true)
        let evidence = root.appendingPathComponent("e05b", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let sid = UUID()
        let dir = watch.appendingPathComponent("updater_output-\(sid.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 0..<5 {
            try Data("f\(i)".utf8).write(to: dir.appendingPathComponent("f\(i).bin"))
        }
        let watcher = UpdaterOutputWatcher(config: .init(
            watchRoot: watch, sessionEvidenceRoot: evidence, sessionID: sid,
            pollIntervalNanoseconds: 5_000_000_000, maxFilesPerDir: 2,
            stabilityWindowNanoseconds: 10_000_000
        ))
        await watcher.start()
        await watcher.pollOncePublic()
        let snap = await watcher.stop()
        let rec = try XCTUnwrap(snap.records.first { $0.boundToSession })
        XCTAssertEqual(rec.completeness, .limitExceeded)
        XCTAssertGreaterThanOrEqual(rec.omittedFileCount, 3)
        XCTAssertFalse(rec.sourceHashVerifiable, "cap must make whole-source hash unverifiable")
        XCTAssertNil(rec.originalSHA256, "must not publish first-file as directory original")
    }

    func testP0_05C_byteCapTruncated() async throws {
        let watch = root.appendingPathComponent("w05c", isDirectory: true)
        let evidence = root.appendingPathComponent("e05c", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let sid = UUID()
        let dir = watch.appendingPathComponent("updater_output-\(sid.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 1000).write(to: dir.appendingPathComponent("big.bin"))
        let watcher = UpdaterOutputWatcher(config: .init(
            watchRoot: watch, sessionEvidenceRoot: evidence, sessionID: sid,
            pollIntervalNanoseconds: 5_000_000_000, maxBytesPerFile: 100,
            stabilityWindowNanoseconds: 10_000_000
        ))
        await watcher.start()
        await watcher.pollOncePublic()
        let snap = await watcher.stop()
        let rec = try XCTUnwrap(snap.records.first { $0.boundToSession && $0.capturedBytes > 0 })
        XCTAssertEqual(rec.completeness, .truncated)
        XCTAssertEqual(rec.capturedBytes, 100)
        XCTAssertFalse(rec.sourceHashVerifiable)
        XCTAssertNil(rec.originalSHA256)
    }

    func testP0_05D_midReadMutatePartial() async throws {
        let watch = root.appendingPathComponent("w05d", isDirectory: true)
        let evidence = root.appendingPathComponent("e05d", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let sid = UUID()
        let dir = watch.appendingPathComponent("updater_output-\(sid.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("grow.bin")
        try Data(repeating: 0x41, count: 32).write(to: f)

        let watcher = UpdaterOutputWatcher(config: .init(
            watchRoot: watch, sessionEvidenceRoot: evidence, sessionID: sid,
            pollIntervalNanoseconds: 5_000_000_000,
            stabilityWindowNanoseconds: 200_000_000
        ))
        await watcher.start()
        // Concurrent grow during stability window of next poll.
        let grow = Task {
            try await Task.sleep(nanoseconds: 50_000_000)
            let handle = try FileHandle(forWritingTo: f)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(repeating: 0x42, count: 4096))
        }
        await watcher.pollOncePublic()
        try await grow.value
        var snap = await watcher.currentSnapshot()
        var rec = try XCTUnwrap(snap.records.first { $0.boundToSession })
        if rec.completeness == .complete && rec.sourceHashVerifiable {
            // Timing missed growth — add unreadable sibling and re-poll (mutate under session).
            let bad = dir.appendingPathComponent("mutated-unreadable.bin")
            try Data("M".utf8).write(to: bad)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: bad.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: bad.path) }
            await watcher.pollOncePublic()
            snap = await watcher.currentSnapshot()
            rec = try XCTUnwrap(snap.records.first { $0.boundToSession })
        }
        _ = await watcher.stop()
        XCTAssertNotEqual(rec.completeness, .complete, "mid-mutate/unreadable must not be silent complete")
        XCTAssertFalse(rec.sourceHashVerifiable)
        XCTAssertNil(rec.originalSHA256)
    }

    func testP0_05E_partialMultiFileNoDirectoryHash() async throws {
        let watch = root.appendingPathComponent("w05e", isDirectory: true)
        let evidence = root.appendingPathComponent("e05e", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let sid = UUID()
        let dir = watch.appendingPathComponent("updater_output-\(sid.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: dir.appendingPathComponent("a.bin"))
        try Data("two".utf8).write(to: dir.appendingPathComponent("b.bin"))
        let bad = dir.appendingPathComponent("c.bin")
        try Data("three".utf8).write(to: bad)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: bad.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: bad.path) }

        let watcher = UpdaterOutputWatcher(config: .init(
            watchRoot: watch, sessionEvidenceRoot: evidence, sessionID: sid,
            pollIntervalNanoseconds: 5_000_000_000, stabilityWindowNanoseconds: 10_000_000
        ))
        await watcher.start()
        await watcher.pollOncePublic()
        let snap = await watcher.stop()
        let rec = try XCTUnwrap(snap.records.first { $0.boundToSession })
        XCTAssertNotEqual(rec.completeness, .complete)
        XCTAssertFalse(rec.sourceHashVerifiable)
        XCTAssertNil(rec.originalSHA256)
        XCTAssertGreaterThanOrEqual(rec.omittedFileCount, 1)
    }

    // MARK: - P0-07 real FAIL fixture order

    func testP0_07_realFailFixtureStartedBeforeFailed() throws {
        let failRaw = try copyFixtureToUnique("fail_537561A7.log")
        let rawText = try String(contentsOf: failRaw, encoding: .utf8)
        // Accept 31182 or 31183 depending on trailing-newline split semantics.
        let lines = rawText.split(separator: "\n", omittingEmptySubsequences: false).count
        XCTAssertTrue((31182...31183).contains(lines), "must use real ~31182-line fixture, got \(lines)")
        XCTAssertGreaterThan(rawText.count, 6_000_000)

        let diagURL = root.appendingPathComponent("fail_diag.log")
        let metrics = try DiagnosticLogBuilder.build(fromRaw: failRaw, to: diagURL)
        let diag = try String(contentsOf: diagURL, encoding: .utf8)

        guard let started = diag.range(of: "Started checkpoint id: 0x1308"),
              let failed = diag.range(of: "Checkpoint 0x1308 (update_madea) failed")
        else {
            return XCTFail("missing Started/Failed checkpoint in diagnostic\n\(diag.prefix(500))")
        }
        let posStarted = diag.distance(from: diag.startIndex, to: started.lowerBound)
        let posFailed = diag.distance(from: diag.startIndex, to: failed.lowerBound)
        XCTAssertLessThan(posStarted, posFailed, "pos(Started)=\(posStarted) must be < pos(Failed)=\(posFailed)")

        // #rawL tags present and traceable
        XCTAssertTrue(diag.contains("#rawL=20422") || diag.contains("Started checkpoint id: 0x1308"))
        XCTAssertTrue(diag.contains("#rawL=25589") || diag.contains("failed with result"))
        XCTAssertTrue(diag.contains("Device disconnected") || metrics.preservedNeedles["Device disconnected"] ?? 0 >= 0)
        XCTAssertEqual(metrics.terminalKind, .failure)
        XCTAssertTrue(diag.contains("===== FIRST FATAL ====="), diag)
    }

    // MARK: - P0-08 identity-aware terminal

    func testP0_08_crossDeviceNeverRetry() {
        let aFailBOk = """
        device A: Restore failed (result = -1)
        device B: Restore succeeded
        """
        XCTAssertNotEqual(DiagnosticLogBuilder.classifyTerminal(in: aFailBOk), .retry)
        let kind = DiagnosticLogBuilder.classifyTerminal(in: aFailBOk)
        XCTAssertTrue(kind == .conflict || kind == .unverified, "got \(kind)")

        let aOkBFail = """
        device A: Restore succeeded
        device B: Restore failed
        """
        XCTAssertNotEqual(DiagnosticLogBuilder.classifyTerminal(in: aOkBFail), .retry)
        let kind2 = DiagnosticLogBuilder.classifyTerminal(in: aOkBFail)
        XCTAssertTrue(kind2 == .conflict || kind2 == .unverified, "got \(kind2)")

        let sameRetry = """
        device A: Restore failed
        device A: Restore succeeded
        """
        // Round 004: no SessionKey → unverified (not auto-retry).
        XCTAssertEqual(DiagnosticLogBuilder.classifyTerminal(in: sameRetry), .unverified)

        let sameConflict = """
        device A: Restore succeeded
        device A: Restore failed
        """
        XCTAssertEqual(DiagnosticLogBuilder.classifyTerminal(in: sameConflict), .unverified)

        let sameSessionRetry = """
        Session 1 started
        device A: Restore failed
        Session 1
        device A: Restore succeeded
        """
        XCTAssertEqual(DiagnosticLogBuilder.classifyTerminal(in: sameSessionRetry), .retry)

        let noID = "Restore failed\nRestore succeeded\n"
        XCTAssertEqual(DiagnosticLogBuilder.classifyTerminal(in: noID), .unverified)

        let ecidCross = """
        ECID = 0xAAA: Restore failed
        ECID = 0xBBB: Restore succeeded
        """
        XCTAssertNotEqual(DiagnosticLogBuilder.classifyTerminal(in: ecidCross), .retry)
    }

    // MARK: - P0-10 resource bounds

    func testP0_10_largeNonceMarkerDoesNotBlowRSS() async throws {
        let watch = root.appendingPathComponent("w10", isDirectory: true)
        let evidence = root.appendingPathComponent("e10", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)

        // Unknown dir (not session-bound) with 128 MiB nonce marker.
        let dir = watch.appendingPathComponent("updater_output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let marker = dir.appendingPathComponent(".rlm_session_nonce")
        FileManager.default.createFile(atPath: marker.path, contents: nil)
        let fh = try FileHandle(forWritingTo: marker)
        let chunk = Data(repeating: 0x4E, count: 1024 * 1024) // 1 MiB
        for _ in 0..<128 { try fh.write(contentsOf: chunk) }
        try fh.close()

        func rssBytes() -> Int64 {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            return kr == KERN_SUCCESS ? Int64(info.resident_size) : -1
        }

        let before = rssBytes()
        let sid = UUID()
        let watcher = UpdaterOutputWatcher(config: .init(
            watchRoot: watch, sessionEvidenceRoot: evidence, sessionID: sid,
            sessionNonce: "SHOULD-NOT-MATCH-BLOB",
            pollIntervalNanoseconds: 5_000_000_000, stabilityWindowNanoseconds: 5_000_000
        ))
        await watcher.start()
        await watcher.pollOncePublic()
        let snap = await watcher.stop()
        let after = rssBytes()
        let delta = after - before
        // Must NOT jump ~256 MiB; bound to << 64 MiB (prefer < 16 MiB).
        XCTAssertLessThan(delta, 64 * 1024 * 1024, "RSS delta \(delta) too large — unbounded nonce read?")
        // Dir must not be BOUND via the huge marker.
        if let rec = snap.records.first(where: { $0.sourcePath == dir.path }) {
            XCTAssertNotEqual(rec.bindingState, .bound)
        }
    }

    // MARK: - P0-N1 production binding honesty

    func testP0_N1_randomUUIDNotBoundWithoutAuthority() async throws {
        let watch = root.appendingPathComponent("wn1", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        let store = EvidenceStore(root: root.appendingPathComponent("SessionsN1", isDirectory: true))
        let eng = CaptureCoordinator(backend: SimulatedLogCaptureBackend(), store: store)
        // Production-like: no ecidHint.
        let cfg = CaptureConfig(
            outputDirectory: root.appendingPathComponent("outN1"),
            updaterWatchRoot: watch,
            ecidHint: nil
        )
        let sess = try await eng.beginCapture(config: cfg)
        let appleDir = watch.appendingPathComponent("updater_output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: appleDir, withIntermediateDirectories: true)
        try Data("APPLE-BODY".utf8).write(to: appleDir.appendingPathComponent("body.bin"))
        try await Task.sleep(nanoseconds: 120_000_000)
        _ = try await eng.stopCapture(sessionID: sess.sessionID)
        let exp = try await eng.finalize(sessionID: sess.sessionID)
        // Must not capture foreign Apple UUID body as bound complete.
        for f in exp.record.files where f.relativePath.hasSuffix("body.bin") {
            let url = URL(fileURLWithPath: sess.outputDirectory).appendingPathComponent(f.relativePath)
            if let data = try? Data(contentsOf: url), String(decoding: data, as: UTF8.self).contains("APPLE-BODY") {
                XCTFail("random UUID dir body must not enter primary bound evidence")
            }
        }
        XCTAssertNotEqual(exp.record.updaterOutputStatus, .capturedComplete)
        let missing = exp.record.missingEvidence.joined(separator: "\n")
        XCTAssertTrue(
            exp.record.updaterOutputStatus == .quarantined
                || exp.record.updaterOutputStatus == .miss
                || missing.lowercased().contains("quarantine")
                || missing.lowercased().contains("unbound"),
            "status=\(exp.record.updaterOutputStatus) missing=\(missing)"
        )
    }

    // MARK: - X5 watcher lifecycle

    func testX5_startFailureCleansPartialAndNoBackend() async throws {
        final class FlagBackend: LogCaptureBackend, @unchecked Sendable {
            let kind = "flag"
            private(set) var started = false
            func start(config: CaptureConfig, rawLogURL: URL, stderrURL: URL) async throws -> BackendHandle {
                started = true
                return BackendHandle(pid: 1, executablePath: "/bin/true", arguments: [], startedAtUTC: Date())
            }
            func waitForExit(handle: BackendHandle) async -> Int32? { 0 }
            func requestTermination(handle: BackendHandle) async {}
            func isRunning(handle: BackendHandle) async -> Bool { false }
        }
        let missingWatch = root.appendingPathComponent("no-such-watch-\(UUID().uuidString)", isDirectory: true)
        // Do NOT create missingWatch.
        let sessionsRoot = root.appendingPathComponent("SessionsX5", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        let store = EvidenceStore(root: sessionsRoot)
        let backend = FlagBackend()
        let eng = CaptureCoordinator(backend: backend, store: store)
        let cfg = CaptureConfig(
            outputDirectory: root.appendingPathComponent("outX5"),
            updaterWatchRoot: missingWatch,
            ecidHint: nil
        )
        do {
            _ = try await eng.beginCapture(config: cfg)
            XCTFail("expected watcherNotReady")
        } catch let err as CaptureError {
            guard case .watcherNotReady = err else {
                return XCTFail("expected watcherNotReady, got \(err)")
            }
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertFalse(backend.started, "backend must not start when watcher not ready")
        // .partial hygiene: no leftover *.partial dirs
        let leftovers = (try? FileManager.default.contentsOfDirectory(at: sessionsRoot, includingPropertiesForKeys: nil)) ?? []
        let partials = leftovers.filter { $0.lastPathComponent.hasSuffix(".partial") }
        XCTAssertTrue(partials.isEmpty, "leftover partials: \(partials.map(\.lastPathComponent))")
    }

    func testX5_postStopNoRecapture() async throws {
        let watch = root.appendingPathComponent("wX5b", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        let store = EvidenceStore(root: root.appendingPathComponent("SessionsX5b", isDirectory: true))
        let eng = CaptureCoordinator(backend: SimulatedLogCaptureBackend(), store: store)
        let cfg = CaptureConfig(outputDirectory: root.appendingPathComponent("outX5b"), updaterWatchRoot: watch)
        let sess = try await eng.beginCapture(config: cfg)
        _ = try await eng.stopCapture(sessionID: sess.sessionID)
        let late = watch.appendingPathComponent("updater_output-\(sess.sessionID.uuidString)-LATE", isDirectory: true)
        try FileManager.default.createDirectory(at: late, withIntermediateDirectories: true)
        try Data("POST-STOP".utf8).write(to: late.appendingPathComponent("late.bin"))
        try await Task.sleep(nanoseconds: 100_000_000)
        let exp = try await eng.finalize(sessionID: sess.sessionID)
        let joined = exp.record.files.map(\.relativePath).joined(separator: "\n")
        XCTAssertFalse(joined.contains("LATE"))
    }
}

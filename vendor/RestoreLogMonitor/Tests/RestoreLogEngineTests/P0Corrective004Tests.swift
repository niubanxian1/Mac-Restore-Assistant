import Foundation
import XCTest
@testable import RestoreLogEngine

/// RLM_1_2_P0_CORRECTIVE_AND_CAPTURE_004 — adversarial negatives + gates.
final class P0Corrective004Tests: XCTestCase {
    private var root: URL!
    private static let rem003Fixtures = URL(
        fileURLWithPath: "/Users/niubanxiandetuzhichakanqi/Desktop/gongzuoqu/RUN_RLM_1_2_P0_TARGETED_REMEDIATION_003_20261106T192921Z/fixtures",
        isDirectory: true
    )
    private static let readit = URL(
        fileURLWithPath: "/Users/niubanxiandetuzhichakanqi/Desktop/gongzuoqu/RUN_RLM_1_2_INDEPENDENT_REAUDIT_003_20261106T115930Z",
        isDirectory: true
    )

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlm-p0c004-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func resolveFailFixture() throws -> URL {
        if let env = ProcessInfo.processInfo.environment["RLM12_FIXTURES_DIR"] {
            let u = URL(fileURLWithPath: env).appendingPathComponent("fail_537561A7.log")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        let candidates = [
            Self.rem003Fixtures.appendingPathComponent("fail_537561A7.log"),
            Self.readit.appendingPathComponent("fixtures/fail_537561A7.log"),
        ]
        for c in candidates where FileManager.default.fileExists(atPath: c.path) { return c }
        throw XCTSkip("FAIL fixture missing")
    }

    // MARK: - P0-05

    func testP0_05_shrinkDuringCopyNeverComplete() async throws {
        let watch = root.appendingPathComponent("w05shrink", isDirectory: true)
        let evidence = root.appendingPathComponent("e05shrink", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let sid = UUID()
        let dir = watch.appendingPathComponent("updater_output-\(sid.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let big = dir.appendingPathComponent("payload.bin")
        // 4 MiB zeros
        let size = 4 * 1024 * 1024
        FileManager.default.createFile(atPath: big.path, contents: nil)
        let fh = try FileHandle(forWritingTo: big)
        try fh.truncate(atOffset: UInt64(size))
        try fh.close()

        let watcher = UpdaterOutputWatcher(config: .init(
            watchRoot: watch, sessionEvidenceRoot: evidence, sessionID: sid,
            pollIntervalNanoseconds: 5_000_000_000,
            maxBytesPerFile: 64 * 1024 * 1024,
            stabilityWindowNanoseconds: 150_000_000
        ))
        await watcher.start()
        // Shrink during stability / copy window.
        let shrink = Task {
            try await Task.sleep(nanoseconds: 40_000_000)
            let h = try FileHandle(forWritingTo: big)
            try h.truncate(atOffset: 1 * 1024 * 1024)
            try h.close()
        }
        await watcher.pollOncePublic()
        try await shrink.value
        let snap = await watcher.stop()
        let rec = try XCTUnwrap(snap.records.first { $0.boundToSession })
        XCTAssertNotEqual(rec.completeness, .complete, "shrink must not be complete")
        XCTAssertFalse(rec.sourceHashVerifiable)
        XCTAssertNil(rec.originalSHA256)
    }

    func testP0_05_siblingVanishNeverComplete() async throws {
        let watch = root.appendingPathComponent("w05vanish", isDirectory: true)
        let evidence = root.appendingPathComponent("e05vanish", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let sid = UUID()
        let dir = watch.appendingPathComponent("updater_output-\(sid.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("KEEP".utf8).write(to: dir.appendingPathComponent("keep.bin"))
        let vanish = dir.appendingPathComponent("vanish.bin")
        try Data("GONE".utf8).write(to: vanish)

        let watcher = UpdaterOutputWatcher(config: .init(
            watchRoot: watch, sessionEvidenceRoot: evidence, sessionID: sid,
            pollIntervalNanoseconds: 5_000_000_000,
            stabilityWindowNanoseconds: 120_000_000
        ))
        await watcher.start()
        let del = Task {
            try await Task.sleep(nanoseconds: 30_000_000)
            try FileManager.default.removeItem(at: vanish)
        }
        await watcher.pollOncePublic()
        try await del.value
        let snap = await watcher.stop()
        let rec = try XCTUnwrap(snap.records.first { $0.boundToSession })
        XCTAssertNotEqual(rec.completeness, .complete)
        XCTAssertFalse(rec.sourceInventoryComplete || rec.completeness == .complete)
    }

    func testP0_05_topSymlinkRejected() async throws {
        let watch = root.appendingPathComponent("w05sym", isDirectory: true)
        let evidence = root.appendingPathComponent("e05sym", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("LEAK".utf8).write(to: outside.appendingPathComponent("secret.bin"))
        let sid = UUID()
        let link = watch.appendingPathComponent("updater_output-\(sid.uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let watcher = UpdaterOutputWatcher(config: .init(
            watchRoot: watch, sessionEvidenceRoot: evidence, sessionID: sid,
            pollIntervalNanoseconds: 5_000_000_000,
            stabilityWindowNanoseconds: 10_000_000
        ))
        await watcher.start()
        await watcher.pollOncePublic()
        let snap = await watcher.stop()
        XCTAssertFalse(snap.records.contains { $0.completeness == .complete && $0.capturedBytes > 0 })
        XCTAssertFalse(snap.records.contains { $0.completeness == .emptyDirectory && $0.boundToSession })
        // Must not copy secret into evidence via symlink follow
        let leak = evidence.path
        let en = FileManager.default.enumerator(atPath: leak)
        var foundSecret = false
        while let p = en?.nextObject() as? String {
            if p.contains("secret") { foundSecret = true }
        }
        XCTAssertFalse(foundSecret)
    }

    func testP0_05_unreadableDirNotEmptyDirectory() async throws {
        let watch = root.appendingPathComponent("w05unr", isDirectory: true)
        let evidence = root.appendingPathComponent("e05unr", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let sid = UUID()
        let dir = watch.appendingPathComponent("updater_output-\(sid.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("X".utf8).write(to: dir.appendingPathComponent("x.bin"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }

        let watcher = UpdaterOutputWatcher(config: .init(
            watchRoot: watch, sessionEvidenceRoot: evidence, sessionID: sid,
            pollIntervalNanoseconds: 5_000_000_000,
            stabilityWindowNanoseconds: 10_000_000
        ))
        await watcher.start()
        await watcher.pollOncePublic()
        let snap = await watcher.stop()
        // May or may not see dir depending on listing; if seen, must not be emptyDirectory complete claim of emptiness falsely
        if let rec = snap.records.first(where: { $0.sourcePath == dir.path }) {
            XCTAssertNotEqual(rec.completeness, .emptyDirectory)
        }
    }

    // MARK: - P0-STOP

    func testP0_STOP_barrier100LargeCopy() async throws {
        let trials = 100
        var postStopBytes = 0
        for i in 0..<trials {
            let watch = root.appendingPathComponent("wstop\(i)", isDirectory: true)
            let evidence = root.appendingPathComponent("estop\(i)", isDirectory: true)
            try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
            let sid = UUID()
            let dir = watch.appendingPathComponent("updater_output-\(sid.uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let big = dir.appendingPathComponent("big.bin")
            FileManager.default.createFile(atPath: big.path, contents: nil)
            let fh = try FileHandle(forWritingTo: big)
            try fh.truncate(atOffset: 32 * 1024 * 1024) // 32 MiB
            try fh.close()

            let watcher = UpdaterOutputWatcher(config: .init(
                watchRoot: watch, sessionEvidenceRoot: evidence, sessionID: sid,
                pollIntervalNanoseconds: 10_000_000,
                maxBytesPerFile: 64 * 1024 * 1024,
                stabilityWindowNanoseconds: 5_000_000
            ))
            await watcher.start()
            // Kick poll then immediately stop (race).
            let poll = Task { await watcher.pollOncePublic() }
            try await Task.sleep(nanoseconds: 2_000_000)
            _ = await watcher.stop(cutoff: true)
            await poll.value
            // Measure evidence tree bytes after stop returned; wait briefly for any illegal late write.
            try await Task.sleep(nanoseconds: 20_000_000)
            let before = directoryByteSize(evidence)
            try await Task.sleep(nanoseconds: 50_000_000)
            let after = directoryByteSize(evidence)
            let delta = max(0, after - before)
            postStopBytes += delta
        }
        XCTAssertEqual(postStopBytes, 0, "POST_STOP_WRITE_BYTES_AFTER_STOP_RETURN must be 0; got \(postStopBytes)")
    }

    private func directoryByteSize(_ url: URL) -> Int {
        var total = 0
        if let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
            for case let f as URL in en {
                let vals = try? f.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if vals?.isRegularFile == true {
                    total += vals?.fileSize ?? 0
                }
            }
        }
        return total
    }

    // MARK: - P0-STATUS

    func testP0_STATUS_reduceOrderIndependent() throws {
        let sid = UUID()
        let complete = UpdaterOutputWatcher.CaptureRecord(
            sourcePath: "/tmp/updater_output-\(sid.uuidString)",
            destPath: "/ev/a",
            originalSHA256: "abc",
            sourceSHA256: "abc",
            sourceHashVerifiable: true,
            capturedSHA256: "abc",
            capturedBytes: 100,
            fileCount: 1,
            omittedFileCount: 0,
            empty: false,
            completeness: .complete,
            timingNote: "stable-copy",
            boundToSession: true,
            bindingState: .bound,
            quarantined: false,
            sourceInventoryComplete: true
        )
        let emptyLink = UpdaterOutputWatcher.CaptureRecord(
            sourcePath: "/tmp/updater_output-\(sid.uuidString)-LINK",
            destPath: "/ev/link",
            capturedBytes: 0,
            fileCount: 0,
            empty: true,
            completeness: .emptyDirectory,
            timingNote: "empty",
            boundToSession: true,
            bindingState: .bound,
            quarantined: false
        )
        let foreign = UpdaterOutputWatcher.CaptureRecord(
            sourcePath: "/tmp/updater_output-FOREIGN",
            completeness: .quarantined,
            timingNote: "unbound-quarantine",
            boundToSession: false,
            bindingState: .quarantined,
            quarantined: true
        )
        var results: [UpdaterOutputStatus] = []
        for _ in 0..<100 {
            var recs = [complete, emptyLink, foreign]
            recs.shuffle()
            let summary = CaptureCoordinator.reduceUpdaterStatus(records: recs, failedReason: nil, earlyWatcherStarted: true)
            results.append(summary.updaterOutputStatus)
            XCTAssertNotEqual(summary.updaterOutputStatus, .emptyDirectory)
            XCTAssertNotEqual(summary.updaterOutputStatus, .quarantined)
            XCTAssertTrue(summary.integrity.anyProvenBody)
        }
        XCTAssertEqual(Set(results).count, 1, "reduce must be deterministic across shuffles")
    }

    // MARK: - P0-08

    func testP0_08_falseRetryMatrix() {
        let cases: [(String, Set<DiagnosticLogBuilder.RestoreTerminalKind>)] = [
            ("device A: Restore failed\ndevice B: Restore failed\ndevice A: Restore succeeded", [.conflict, .unverified]),
            ("Restore session 1 ECID=0xAAA Restore failed\nRestore session 2 ECID=0xAAA Restore succeeded", [.conflict, .unverified]),
            ("Session 1 started ECID=0xAAA Restore failed\nSession 2 started ECID=0xAAA Restore succeeded", [.conflict, .unverified]),
            ("device with error: Restore failed\ndevice with retry: Restore succeeded", [.unverified, .conflict]),
            ("ECID=0xAAA Restore failed\nRestore failed\nECID=0xAAA Restore succeeded", [.unverified, .conflict]),
            ("Created state machine for device with ECID=0x1\nRestore failed\nRestore succeeded", [.unverified, .conflict]),
            ("device A: Restore failed\ndevice A: Restore succeeded\nretrying restore\ndevice A: Restore succeeded", [.retry, .success, .unverified]),
            ("device A: Restore failed\ndevice A: Restore succeeded", [.unverified]), // same device, no session → unverified
        ]
        var falseRetry = 0
        for (text, allowed) in cases {
            let kind = DiagnosticLogBuilder.classifyTerminal(in: text)
            if kind == .retry && !allowed.contains(.retry) {
                falseRetry += 1
                XCTFail("FALSE_RETRY for: \(text.prefix(60))… got retry")
            }
            XCTAssertTrue(allowed.contains(kind), "got \(kind) for \(text.prefix(40)) allowed=\(allowed)")
        }
        XCTAssertEqual(falseRetry, 0)

        // device with must not parse as device:with
        XCTAssertNil(DiagnosticLogBuilder.deviceIdentity(from: "device with error"))
        XCTAssertEqual(DiagnosticLogBuilder.deviceIdentity(from: "device with ECID=0xABC"), "ecid:0xabc")
        XCTAssertEqual(DiagnosticLogBuilder.deviceIdentity(from: "device A: hello"), "device:a")
    }

    func testP0_08_sameSessionExplicitRetryAllowed() {
        let text = """
        Session 1 started
        ECID=0xAAA Restore failed
        Session 1
        retrying restore
        ECID=0xAAA Restore succeeded
        """
        let kind = DiagnosticLogBuilder.classifyTerminal(in: text)
        // Same session keys + fail then success → retry
        XCTAssertEqual(kind, .retry)
    }

    // MARK: - P0-07 regression

    func testP0_07_chronoStartedBeforeFailed() throws {
        let src = try resolveFailFixture()
        let dest = root.appendingPathComponent("fail_copy.log")
        try FileManager.default.copyItem(at: src, to: dest)
        let diag = root.appendingPathComponent("fail_diag.log")
        let metrics = try DiagnosticLogBuilder.build(fromRaw: dest, to: diag)
        XCTAssertEqual(metrics.terminalKind, .failure)
        let text = try String(contentsOf: diag, encoding: .utf8)
        // Find in RESTORE TIMELINE section before FIRST FATAL if possible
        let timeline: String
        if let r1 = text.range(of: "===== RESTORE TIMELINE ====="),
           let r2 = text.range(of: "===== FIRST FATAL =====") {
            timeline = String(text[r1.lowerBound..<r2.lowerBound])
        } else {
            timeline = text
        }
        func rawL(_ needle: String) -> Int? {
            guard let line = timeline.components(separatedBy: "\n").first(where: { $0.contains(needle) && $0.contains("#rawL=") }) else { return nil }
            guard let r = line.range(of: #"#rawL=(\d+)"#, options: .regularExpression) else { return nil }
            return Int(String(line[r]).split(separator: "=").last!)
        }
        let started = try XCTUnwrap(rawL("Started checkpoint 0x1308") ?? rawL("Started Checkpoint 0x1308") ?? rawL("0x1308"))
        // Prefer explicit failed line
        let failed = try XCTUnwrap(
            rawL("Checkpoint 0x1308 failed")
            ?? timeline.components(separatedBy: "\n").compactMap { line -> Int? in
                guard line.lowercased().contains("0x1308"), line.lowercased().contains("fail"), line.contains("#rawL=") else { return nil }
                guard let r = line.range(of: #"#rawL=(\d+)"#, options: .regularExpression) else { return nil }
                return Int(String(line[r]).split(separator: "=").last!)
            }.first
        )
        XCTAssertLessThan(started, failed, "Started must precede Failed in chrono timeline")
    }

    // MARK: - P0-10 streaming smoke

    func testP0_10_lineCountStreams() throws {
        let f = root.appendingPathComponent("lines.bin")
        var data = Data()
        for i in 0..<10000 {
            data.append(contentsOf: "line-\(i)\n".utf8)
        }
        try data.write(to: f)
        XCTAssertEqual(try Integrity.lineCount(ofFileAt: f), 10000)
    }

    func testP0_10_buildDoesNotRequireFullDataContentsOfAPI() throws {
        // Functional: build a medium file via streaming path.
        let f = root.appendingPathComponent("med.log")
        var s = ""
        for i in 0..<5000 {
            if i == 100 { s += "Restore failed AMRestoreErrorDomain\n" }
            else if i == 200 { s += "update_mcdp29xx something\n" }
            else { s += "noise CFPrefs line \(i)\n" }
        }
        try Data(s.utf8).write(to: f)
        let diag = root.appendingPathComponent("med.diag")
        let m = try DiagnosticLogBuilder.build(fromRaw: f, to: diag)
        XCTAssertGreaterThan(m.rawLines, 1000)
        XCTAssertEqual(m.terminalKind, .failure)
        XCTAssertLessThan(m.diagnosticBytes, m.rawBytes)
    }

    // MARK: - N1 offline prototype


    func testP0_10_perf256MiBIfEnvSet() throws {
        guard let path = ProcessInfo.processInfo.environment["RLM_PERF_256_PATH"] else {
            throw XCTSkip("set RLM_PERF_256_PATH to run 256MiB perf")
        }
        let raw = URL(fileURLWithPath: path)
        let diag = root.appendingPathComponent("perf256.diag.log")
        let t0 = Date()
        do {
            let m = try DiagnosticLogBuilder.build(fromRaw: raw, to: diag)
            let secs = Date().timeIntervalSince(t0)
            let out = """
            PERF256_SECONDS=\(String(format: "%.3f", secs))
            PERF256_RAW_BYTES=\(m.rawBytes)
            PERF256_RAW_LINES=\(m.rawLines)
            PERF256_DIAG_BYTES=\(m.diagnosticBytes)
            PERF256_KEPT=\(m.keptLines)
            PERF256_TERMINAL=\(m.terminalKind.rawValue)
            PERF256_CONFIG=\(ProcessInfo.processInfo.environment["RLM_PERF_CONFIG"] ?? "unknown")
            PERF256_STATUS=COMPLETED
            """
            print(out)
            if let report = ProcessInfo.processInfo.environment["RLM_PERF_256_REPORT"] {
                try out.write(toFile: report, atomically: true, encoding: .utf8)
            }
        } catch {
            let secs = Date().timeIntervalSince(t0)
            let out = """
            PERF256_SECONDS=\(String(format: "%.3f", secs))
            PERF256_STATUS=ERROR
            PERF256_ERROR=\(error)
            PERF256_CONFIG=\(ProcessInfo.processInfo.environment["RLM_PERF_CONFIG"] ?? "unknown")
            """
            print(out)
            if let report = ProcessInfo.processInfo.environment["RLM_PERF_256_REPORT"] {
                try out.write(toFile: report, atomically: true, encoding: .utf8)
            }
            throw error
        }
    }

    func testN1_unboundCaptureOffline() async throws {
        let watch = root.appendingPathComponent("n1w", isDirectory: true)
        let vaultRoot = root.appendingPathComponent("n1v", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        let dir = watch.appendingPathComponent("updater_output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("BODY".utf8).write(to: dir.appendingPathComponent("body.bin"))

        let vault = UnboundEvidenceVault(root: vaultRoot)
        let snap = UpdaterOutputSnapshotter(config: .init(watchRoot: watch, vaultRoot: vaultRoot, pollIntervalNanoseconds: 10_000_000), vault: vault)
        await snap.startWatch()
        try await Task.sleep(nanoseconds: 80_000_000)
        await snap.stop()
        let entries = await snap.entries()
        XCTAssertFalse(entries.isEmpty)
        XCTAssertEqual(entries.first?.label, .capturedCompleteUnbound)
        let attr = LateAttributionEngine.attribute(sourceDirName: dir.lastPathComponent)
        XCTAssertEqual(attr.decision, .unbound)
        XCTAssertEqual(attr.realConfiguratorBodyCaptured, "NO")
        XCTAssertEqual(attr.realMcdp29xxBodyCaptured, "NO")
    }

    func testN1_stopBarrierZeroPostWrite() async throws {
        let watch = root.appendingPathComponent("n1stop", isDirectory: true)
        let vaultRoot = root.appendingPathComponent("n1stopv", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        let vault = UnboundEvidenceVault(root: vaultRoot)
        let snap = UpdaterOutputSnapshotter(config: .init(watchRoot: watch, vaultRoot: vaultRoot, pollIntervalNanoseconds: 5_000_000), vault: vault)
        await snap.startWatch()
        await snap.stop()
        let before = directoryByteSize(vaultRoot)
        // Create dir after stop — must not be ingested
        let dir = watch.appendingPathComponent("updater_output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 0x11, count: 1024).write(to: dir.appendingPathComponent("late.bin"))
        try await Task.sleep(nanoseconds: 50_000_000)
        let after = directoryByteSize(vaultRoot)
        XCTAssertEqual(after, before)
    }

    /// 006 / audit005 residual: after inventory-changed partial, a later pollOnce must NOT heal to .complete.
    func testP0_05_postRaceRepollDoesNotHealToComplete() async throws {
        let watch = root.appendingPathComponent("w05latch", isDirectory: true)
        let evidence = root.appendingPathComponent("e05latch", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let sid = UUID()
        let dir = watch.appendingPathComponent("updater_output-\(sid.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let keep = dir.appendingPathComponent("keep.bin")
        let vanish = dir.appendingPathComponent("vanish.bin")
        try Data("KEEP-BODY".utf8).write(to: keep)
        try Data("VANISH-BODY".utf8).write(to: vanish)

        let watcher = UpdaterOutputWatcher(config: .init(
            watchRoot: watch, sessionEvidenceRoot: evidence, sessionID: sid,
            pollIntervalNanoseconds: 5_000_000_000,
            stabilityWindowNanoseconds: 120_000_000
        ))
        await watcher.start()
        let del = Task {
            try await Task.sleep(nanoseconds: 30_000_000)
            try FileManager.default.removeItem(at: vanish)
        }
        await watcher.pollOncePublic()
        try await del.value
        // Second poll — previously healed remnant to .complete; must stay latched non-complete.
        await watcher.pollOncePublic()
        await watcher.pollOncePublic()
        let snap = await watcher.stop()
        let rec = try XCTUnwrap(snap.records.first { $0.boundToSession || $0.sourcePath.contains("updater_output") })
        XCTAssertNotEqual(rec.completeness, .complete, "post-race re-poll must not heal to complete; note=\(rec.timingNote)")
        XCTAssertFalse(rec.sourceHashVerifiable)
        XCTAssertTrue(
            rec.timingNote.contains("inventory-changed")
                || rec.timingNote.contains("sibling-vanished")
                || rec.timingNote.contains("race-latch")
                || rec.completeness == .partial
                || rec.completeness == .miss
                || rec.completeness == .truncated,
            "expected race latch provenance note=\(rec.timingNote) completeness=\(rec.completeness)"
        )
    }

}

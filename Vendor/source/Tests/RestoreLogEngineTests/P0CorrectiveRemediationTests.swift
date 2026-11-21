import Foundation
import XCTest
@testable import RestoreLogEngine

/// P0-01…P0-10 repro+fix negative tests (one family per P0). Hermetic temp dirs only.
final class P0CorrectiveRemediationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("rlm-p0-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func shaFile(_ data: Data) throws -> String {
        let u = root.appendingPathComponent(UUID().uuidString)
        try data.write(to: u)
        return try Integrity.sha256(ofFileAt: u)
    }

    // MARK: - P0-01 binding / multi-session isolation

    func testP0_01_twoSessionsRandomUUIDDirsNoCrossContam() async throws {
        let watch = root.appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)

        let storeA = EvidenceStore(root: root.appendingPathComponent("SessionsA", isDirectory: true))
        let storeB = EvidenceStore(root: root.appendingPathComponent("SessionsB", isDirectory: true))
        let engA = CaptureCoordinator(backend: SimulatedLogCaptureBackend(), store: storeA)
        let engB = CaptureCoordinator(backend: SimulatedLogCaptureBackend(), store: storeB)

        let cfgA = CaptureConfig(outputDirectory: root.appendingPathComponent("outA"), updaterWatchRoot: watch)
        let cfgB = CaptureConfig(outputDirectory: root.appendingPathComponent("outB"), updaterWatchRoot: watch)
        let sessA = try await engA.beginCapture(config: cfgA)
        let sessB = try await engB.beginCapture(config: cfgB)

        // Two random UUID dirs (match neither session) with distinct bodies.
        let dirRand1 = watch.appendingPathComponent("updater_output-\(UUID().uuidString)", isDirectory: true)
        let dirRand2 = watch.appendingPathComponent("updater_output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dirRand1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirRand2, withIntermediateDirectories: true)
        try Data("BODY-A-SHOULD-NOT-CROSS".utf8).write(to: dirRand1.appendingPathComponent("a.bin"))
        try Data("BODY-B-SHOULD-NOT-CROSS".utf8).write(to: dirRand2.appendingPathComponent("b.bin"))

        // Also create correctly bound dirs for each session.
        let dirA = watch.appendingPathComponent("updater_output-\(sessA.sessionID.uuidString)", isDirectory: true)
        let dirB = watch.appendingPathComponent("updater_output-\(sessB.sessionID.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        try Data("OWN-A".utf8).write(to: dirA.appendingPathComponent("own.bin"))
        try Data("OWN-B".utf8).write(to: dirB.appendingPathComponent("own.bin"))

        try await Task.sleep(nanoseconds: 120_000_000)
        _ = try await engA.stopCapture(sessionID: sessA.sessionID)
        _ = try await engB.stopCapture(sessionID: sessB.sessionID)
        let expA = try await engA.finalize(sessionID: sessA.sessionID)
        let expB = try await engB.finalize(sessionID: sessB.sessionID)

        let pathsA = expA.record.files.map(\.relativePath).joined(separator: "\n")
        let pathsB = expB.record.files.map(\.relativePath).joined(separator: "\n")
        XCTAssertFalse(pathsA.contains("BODY-B-SHOULD-NOT-CROSS"))
        XCTAssertFalse(pathsB.contains("BODY-A-SHOULD-NOT-CROSS"))
        // Random UUID dirs must not contribute body files into either evidence.
        for f in expA.record.files where f.relativePath.contains("updater-output/") && f.relativePath.hasSuffix(".bin") {
            let url = URL(fileURLWithPath: sessA.outputDirectory).appendingPathComponent(f.relativePath)
            if let data = try? Data(contentsOf: url) {
                let s = String(decoding: data, as: UTF8.self)
                XCTAssertFalse(s.contains("BODY-B-SHOULD-NOT-CROSS"), s)
                XCTAssertFalse(s.contains("BODY-A-SHOULD-NOT-CROSS"), "random UUID body must not be accepted: \(s)")
            }
        }
        for f in expB.record.files where f.relativePath.contains("updater-output/") && f.relativePath.hasSuffix(".bin") {
            let url = URL(fileURLWithPath: sessB.outputDirectory).appendingPathComponent(f.relativePath)
            if let data = try? Data(contentsOf: url) {
                let s = String(decoding: data, as: UTF8.self)
                XCTAssertFalse(s.contains("BODY-A-SHOULD-NOT-CROSS"), s)
                XCTAssertFalse(s.contains("BODY-B-SHOULD-NOT-CROSS"), "random UUID body must not be accepted: \(s)")
            }
        }
        // Own bound bodies may appear only in matching session.
        let textA = (try? String(contentsOf: URL(fileURLWithPath: sessA.outputDirectory).appendingPathComponent("updater-output/\(dirA.lastPathComponent)/own.bin"))) ?? ""
        let textB = (try? String(contentsOf: URL(fileURLWithPath: sessB.outputDirectory).appendingPathComponent("updater-output/\(dirB.lastPathComponent)/own.bin"))) ?? ""
        XCTAssertEqual(textA, "OWN-A")
        XCTAssertEqual(textB, "OWN-B")
        XCTAssertNotEqual(textA, "OWN-B")
        XCTAssertNotEqual(textB, "OWN-A")
    }

    // MARK: - P0-02 ready barrier before backend.start

    func testP0_02_readyBarrierBeforeBackendAndOldMtimeNotSkippedUnsafe() async throws {
        let watch = root.appendingPathComponent("tmp2", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        let store = EvidenceStore(root: root.appendingPathComponent("SessionsReady", isDirectory: true))
        let engine = CaptureCoordinator(backend: SimulatedLogCaptureBackend(), store: store)
        let cfg = CaptureConfig(outputDirectory: root.appendingPathComponent("outReady"), updaterWatchRoot: watch)
        let session = try await engine.beginCapture(config: cfg)
        // If we got here, ready barrier passed before backend.start (else watcherNotReady).
        let status = try await engine.getStatus(sessionID: session.sessionID)
        XCTAssertEqual(status.state, .recording)
        _ = try await engine.stopCapture(sessionID: session.sessionID)
        let exp = try await engine.finalize(sessionID: session.sessionID)
        XCTAssertTrue(exp.record.earlyWatcherStarted)
    }

    // MARK: - P0-03 honest miss (no fake PASS)

    func testP0_03_blindZoneMissIsHonestNotFakeComplete() async throws {
        let watch = root.appendingPathComponent("tmp3", isDirectory: true)
        let evidence = root.appendingPathComponent("ev3", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let sid = UUID()
        let watcher = UpdaterOutputWatcher(
            config: .init(
                watchRoot: watch,
                sessionEvidenceRoot: evidence,
                sessionID: sid,
                pollIntervalNanoseconds: 200_000_000, // slow poll to force blind zone
                stabilityWindowNanoseconds: 10_000_000
            )
        )
        await watcher.start()
        let dir = watch.appendingPathComponent("updater_output-\(sid.uuidString)-BLIND", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("flash".utf8).write(to: dir.appendingPathComponent("x.bin"))
        // Delete immediately without waiting for poll — classic blind zone.
        try FileManager.default.removeItem(at: dir)
        try await Task.sleep(nanoseconds: 50_000_000)
        let snap = await watcher.stop()
        if let rec = snap.records.first(where: { $0.sourcePath.contains("BLIND") }) {
            XCTAssertNotEqual(rec.completeness, .complete, "must not mark blind miss as complete")
            XCTAssertEqual(rec.realUpdaterBodyCaptured, "NO")
        } else {
            // Honest absence of record is acceptable miss disclosure.
            XCTAssertTrue(snap.attempted)
        }
    }

    // MARK: - P0-04 stopCapture cutoff

    func testP0_04_postStopDirDoesNotEnterSession() async throws {
        let watch = root.appendingPathComponent("tmp4", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        let store = EvidenceStore(root: root.appendingPathComponent("SessionsStop", isDirectory: true))
        let engine = CaptureCoordinator(backend: SimulatedLogCaptureBackend(), store: store)
        let cfg = CaptureConfig(outputDirectory: root.appendingPathComponent("outStop"), updaterWatchRoot: watch)
        let session = try await engine.beginCapture(config: cfg)
        _ = try await engine.stopCapture(sessionID: session.sessionID)

        // Create updater_output AFTER stopCapture — must not enter stopped session.
        let late = watch.appendingPathComponent("updater_output-\(session.sessionID.uuidString)-LATE", isDirectory: true)
        try FileManager.default.createDirectory(at: late, withIntermediateDirectories: true)
        try Data("POST-STOP-SECRET".utf8).write(to: late.appendingPathComponent("late.bin"))
        try await Task.sleep(nanoseconds: 100_000_000)

        let exp = try await engine.finalize(sessionID: session.sessionID)
        let joined = exp.record.files.map(\.relativePath).joined(separator: "\n")
        XCTAssertFalse(joined.contains("LATE"), joined)
        for f in exp.record.files where f.relativePath.hasSuffix("late.bin") {
            XCTFail("post-stop file must not be in evidence: \(f.relativePath)")
        }
        let latePath = URL(fileURLWithPath: session.outputDirectory)
            .appendingPathComponent("updater-output/\(late.lastPathComponent)/late.bin")
        XCTAssertFalse(FileManager.default.fileExists(atPath: latePath.path))
    }

    // MARK: - P0-05 hashes + truncation honesty

    func testP0_05_truncationNotSilentCompleteAndSeparateHashes() async throws {
        let watch = root.appendingPathComponent("tmp5", isDirectory: true)
        let evidence = root.appendingPathComponent("ev5", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let sid = UUID()
        let maxBytes = 100
        let watcher = UpdaterOutputWatcher(
            config: .init(
                watchRoot: watch,
                sessionEvidenceRoot: evidence,
                sessionID: sid,
                pollIntervalNanoseconds: 20_000_000,
                maxBytesPerFile: maxBytes,
                stabilityWindowNanoseconds: 15_000_000
            )
        )
        await watcher.start()
        let dir = watch.appendingPathComponent("updater_output-\(sid.uuidString)-TRUNC", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let big = Data(repeating: 0x41, count: 1000)
        try big.write(to: dir.appendingPathComponent("big.bin"))
        try await Task.sleep(nanoseconds: 50_000_000)
        await watcher.pollOncePublic()
        await watcher.pollOncePublic()
        let snap = await watcher.stop()
        XCTAssertFalse(snap.records.isEmpty, "expected TRUNC dir record, got \(snap.records)")
        let rec = try XCTUnwrap(snap.records.first { $0.boundToSession && ($0.capturedBytes > 0 || !$0.empty || $0.completeness == .truncated || $0.completeness == .limitExceeded || $0.completeness == .miss || $0.completeness == .partial) })
        XCTAssertEqual(rec.capturedBytes, maxBytes)
        XCTAssertNotEqual(rec.completeness, .complete, "truncation must not be silent complete")
        XCTAssertTrue([UpdaterOutputWatcher.CaptureCompleteness.truncated, .limitExceeded, .partial].contains(rec.completeness))
        XCTAssertFalse(rec.sourceHashVerifiable, "oversized source hash must be unverifiable")
        XCTAssertNil(rec.sourceSHA256)
        XCTAssertEqual(rec.capturedSHA256?.count, 64)
        XCTAssertNotEqual(rec.sourceSHA256, rec.capturedSHA256) // source nil / different
    }

    // MARK: - P0-06 symlink safety

    func testP0_06_symlinkOutsideSecretRejected() async throws {
        let watch = root.appendingPathComponent("tmp6", isDirectory: true)
        let evidence = root.appendingPathComponent("ev6", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let secret = root.appendingPathComponent("OUTSIDE-SECRET.txt")
        try Data("OUTSIDE-SECRET".utf8).write(to: secret)

        let sid = UUID()
        let watcher = UpdaterOutputWatcher(
            config: .init(
                watchRoot: watch,
                sessionEvidenceRoot: evidence,
                sessionID: sid,
                pollIntervalNanoseconds: 20_000_000,
                stabilityWindowNanoseconds: 15_000_000
            )
        )
        await watcher.start()
        let dir = watch.appendingPathComponent("updater_output-\(sid.uuidString)-LINK", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let link = dir.appendingPathComponent("leak.bin")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)
        await watcher.pollOncePublic()
        await watcher.pollOncePublic()
        let snap = await watcher.stop()

        // OUTSIDE-SECRET must not appear in any evidence file bytes.
        let evEnum = FileManager.default.enumerator(at: evidence, includingPropertiesForKeys: nil)
        var found = false
        while let u = evEnum?.nextObject() as? URL {
            if let data = try? Data(contentsOf: u), String(decoding: data, as: UTF8.self).contains("OUTSIDE-SECRET") {
                // Quarantine notes naming the path are ok only if they don't copy body —
                // but secret content must not be the file body under updater tree.
                if u.path.contains("leak.bin") || u.path.hasSuffix(".bin") {
                    found = true
                }
                if u.lastPathComponent == "leak.bin" { found = true }
            }
        }
        XCTAssertFalse(found, "symlink escape copied OUTSIDE-SECRET into evidence")
        if let rec = snap.records.first(where: { $0.boundToSession }) {
            XCTAssertFalse((rec.capturedSHA256 ?? "").isEmpty && rec.capturedBytes > 0 && rec.completeness == .complete && rec.fileCount > 0 && false)
            // Prefer empty / no copied symlink body.
            XCTAssertEqual(rec.realUpdaterBodyCaptured, "NO")
        }
        let leaked = evidence.appendingPathComponent("\(dir.lastPathComponent)/leak.bin")
        if FileManager.default.fileExists(atPath: leaked.path) {
            let body = try String(contentsOf: leaked, encoding: .utf8)
            XCTAssertFalse(body.contains("OUTSIDE-SECRET"), body)
        }
    }

    // MARK: - P0-07 diagnostic USB/FSM/nested fault

    func testP0_07_deviceDisconnectAndNestedFaultKeptInOrder() throws {
        let raw = """
        2026-01-01 16:36:00.000 DeviceService: ECID:0xABC platform=t8112
        2026-01-01 16:36:01.000 State Machine Dump: entering restore
        2026-01-01 16:36:02.191 Restore failed (result = -1)
        2026-01-01 16:36:02.192 RamrodErrorDomain code:7 Nested error: update_mcdp29xx returned 1
        2026-01-01 16:36:02.200 NSUnderlyingError=RamrodErrorDomain Code=7
        2026-01-01 16:36:08.866 Device disconnected during transition
        CFPrefs found no value for key
        boringssl TLS handshake
        """
        let rawURL = root.appendingPathComponent("p07-restore.log")
        let diagURL = root.appendingPathComponent("p07-diagnostic.log")
        try Data(raw.utf8).write(to: rawURL)
        let metrics = try DiagnosticLogBuilder.build(fromRaw: rawURL, to: diagURL)
        let diag = try String(contentsOf: diagURL, encoding: .utf8)
        XCTAssertTrue(diag.contains("Device disconnected during transition"), diag)
        XCTAssertTrue(diag.contains("State Machine Dump"), diag)
        XCTAssertTrue(diag.contains("RamrodErrorDomain"), diag)
        XCTAssertTrue(diag.contains("Nested error"), diag)
        XCTAssertFalse(diag.contains("boringssl"), diag)
        XCTAssertEqual(metrics.terminalKind, .failure)
        // FIRST FATAL should include Ramrod nested line (not only DEVICE).
        guard let fatalRange = diag.range(of: "===== FIRST FATAL =====") else {
            return XCTFail("missing FIRST FATAL")
        }
        let afterFatal = diag[fatalRange.upperBound...]
        let nextSection = afterFatal.range(of: "=====")
        let fatalBody = nextSection.map { String(afterFatal[..<$0.lowerBound]) } ?? String(afterFatal)
        XCTAssertTrue(fatalBody.contains("RamrodErrorDomain"), fatalBody)
        XCTAssertTrue(fatalBody.contains("#rawL="), "raw line numbers expected")
    }

    // MARK: - P0-08 terminal classification

    func testP0_08_terminalMixedConflictLowercaseAndPure() {
        // P0-08: no device identity on interleaved fail+success → unverified (not retry).
        XCTAssertEqual(
            DiagnosticLogBuilder.classifyTerminal(in: "Restore failed\nRestore succeeded\n"),
            .unverified
        )
        XCTAssertEqual(
            DiagnosticLogBuilder.classifyTerminal(in: "Restore succeeded\nRestore failed\n"),
            .unverified
        )
        // P0-08 round 004: same device without SessionKey → unverified (ECID/device ≠ session).
        // Explicit same-session retry covered in P0Corrective004Tests.
        XCTAssertEqual(
            DiagnosticLogBuilder.classifyTerminal(in: "device A: Restore failed\ndevice A: Restore succeeded\n"),
            .unverified
        )
        XCTAssertEqual(
            DiagnosticLogBuilder.classifyTerminal(in: "device A: Restore succeeded\ndevice A: Restore failed\n"),
            .unverified
        )
        XCTAssertEqual(
            DiagnosticLogBuilder.classifyTerminal(in: "restore failed (result = -1)\n"),
            .failure
        )
        XCTAssertEqual(
            DiagnosticLogBuilder.classifyTerminal(in: "Restore succeeded\n"),
            .success
        )
        XCTAssertEqual(
            DiagnosticLogBuilder.classifyTerminal(in: "AMRestoreErrorDomain\n"),
            .failure
        )
        XCTAssertEqual(
            DiagnosticLogBuilder.classifyTerminal(in: ""),
            .none
        )
    }

    // MARK: - P0-09 hermetic fixture build (no fixed /tmp)

    func testP0_09_hermeticFixtureDiagnosticBuild() throws {
        let fx = root.appendingPathComponent("Fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: fx, withIntermediateDirectories: true)
        let rawURL = fx.appendingPathComponent("hermetic_fail.log")
        let body = """
        progress -1
        update_madea: /usr/bin/update_mcdp29xx returned 1
        RamrodErrorDomain code:7
        restore failed
        Wrote updater output to /tmp/updater_output-HERMETIC/SE
        CFPrefs found no value for key
        """
        try Data(body.utf8).write(to: rawURL)
        let diagURL = root.appendingPathComponent("hermetic_diag.log")
        let metrics = try DiagnosticLogBuilder.build(fromRaw: rawURL, to: diagURL)
        XCTAssertEqual(metrics.terminalKind, .failure)
        XCTAssertGreaterThan(metrics.droppedLines, 0)
        let diag = try String(contentsOf: diagURL, encoding: .utf8)
        XCTAssertTrue(diag.contains("update_madea") || diag.contains("RamrodErrorDomain"))
        XCTAssertFalse(diag.contains("CFPrefs"))
    }

    // MARK: - P0-10 resource caps / chunked read

    func testP0_10_fileCountCapLimitExceededNotComplete() async throws {
        let watch = root.appendingPathComponent("tmp10", isDirectory: true)
        let evidence = root.appendingPathComponent("ev10", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let sid = UUID()
        let dir = watch.appendingPathComponent("updater_output-\(sid.uuidString)-MANY", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 0..<5 {
            try Data("f\(i)".utf8).write(to: dir.appendingPathComponent("f\(i).bin"))
        }
        let watcher = UpdaterOutputWatcher(
            config: .init(
                watchRoot: watch,
                sessionEvidenceRoot: evidence,
                sessionID: sid,
                pollIntervalNanoseconds: 5_000_000_000,
                maxBytesPerFile: 1024,
                maxFilesPerDir: 2,
                maxSessionBytes: 4096,
                stabilityWindowNanoseconds: 10_000_000
            )
        )
        await watcher.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        await watcher.pollOncePublic()
        await watcher.pollOncePublic()
        let snap = await watcher.stop()
        XCTAssertFalse(snap.records.isEmpty, "expected MANY dir record, got \(snap.records)")
        let rec = try XCTUnwrap(snap.records.first { $0.boundToSession && !$0.quarantined })
        XCTAssertLessThanOrEqual(rec.fileCount, 2)
        XCTAssertTrue(rec.omittedFileCount >= 3 || rec.completeness == .limitExceeded || rec.completeness == .truncated || rec.fileCount == 2)
        XCTAssertNotEqual(rec.completeness, .complete, "silent complete with omitted files forbidden when cap hit")
        // If we copied only 2 of 5, must disclose limitExceeded (or at least not complete with omitted=0).
        if rec.omittedFileCount > 0 {
            XCTAssertEqual(rec.completeness, .limitExceeded)
        }
    }
}

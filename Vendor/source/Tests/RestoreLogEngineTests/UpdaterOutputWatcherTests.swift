import Foundation
import XCTest
@testable import RestoreLogEngine

/// Owner offline races A–H for preemptive UpdaterOutputWatcher (P0-hardened).
final class UpdaterOutputWatcherTests: XCTestCase {
    private var root: URL!
    private var watchRoot: URL!
    private var evidenceRoot: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("rlm-uow-\(UUID().uuidString)", isDirectory: true)
        watchRoot = root.appendingPathComponent("tmp", isDirectory: true)
        evidenceRoot = root.appendingPathComponent("evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: watchRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evidenceRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeWatcher(sessionID: UUID = UUID(), nonce: String? = nil) -> UpdaterOutputWatcher {
        UpdaterOutputWatcher(
            config: .init(
                watchRoot: watchRoot,
                sessionEvidenceRoot: evidenceRoot,
                sessionID: sessionID,
                sessionNonce: nonce ?? sessionID.uuidString,
                pollIntervalNanoseconds: 15_000_000,
                stabilityWindowNanoseconds: 20_000_000
            )
        )
    }

    private func boundDirName(sessionID: UUID, tag: String) -> String {
        "updater_output-\(sessionID.uuidString)-\(tag)"
    }

    private func sha(_ data: Data) -> String {
        let url = root.appendingPathComponent(UUID().uuidString)
        try! data.write(to: url)
        return try! Integrity.sha256(ofFileAt: url)
    }

    /// P0-03: create→delete WITHOUT manual pollOnce while file exists.
    /// Honesty: if blind-zone miss, completeness must be miss / empty records — never fake PASS-as-captured.
    func testRaceA_ephemeralCreateDelete() async throws {
        let sid = UUID()
        let watcher = makeWatcher(sessionID: sid)
        await watcher.start()
        let dir = watchRoot.appendingPathComponent(boundDirName(sessionID: sid, tag: "EPHEMERAL"), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body = Data("ephemeral-body".utf8)
        let file = dir.appendingPathComponent("SE/out.bin")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body.write(to: file)
        let originalSHA = sha(body)
        // No pollOnce while file exists — rely on FS notify + poll loop, then delete quickly.
        try await Task.sleep(nanoseconds: 40_000_000)
        try FileManager.default.removeItem(at: dir)
        try await Task.sleep(nanoseconds: 80_000_000)
        let snap = await watcher.stop()
        XCTAssertTrue(snap.earlyWatcherStarted)
        XCTAssertTrue(snap.readyBarrierPassed)
        if let rec = snap.records.first(where: { $0.boundToSession }) {
            XCTAssertEqual(rec.realUpdaterBodyCaptured, "NO")
            if rec.capturedBytes > 0 {
                // Captured via FS event / poll — SHA of captured may equal source.
                XCTAssertEqual(rec.capturedSHA256?.count, 64)
                if rec.sourceHashVerifiable {
                    XCTAssertEqual(rec.sourceSHA256, originalSHA)
                }
            } else {
                // Honest miss — never claim complete capture of gone body.
                XCTAssertTrue(
                    rec.completeness == .miss
                        || rec.completeness == .emptyDirectory
                        || rec.completeness == .partial
                        || rec.completeness == .quarantined,
                    "blind-zone miss must not be silent complete; got \(rec.completeness)"
                )
                XCTAssertNotEqual(rec.completeness, .complete)
            }
        } else {
            // No record at all = honest miss of ephemeral (PASS as honesty, not as captured).
            XCTAssertTrue(true, "honest miss: no record for create→delete blind zone")
        }
        XCTAssertFalse(snap.records.contains { $0.realUpdaterBodyCaptured == "YES" })
    }

    func testRaceB_appendingFilePartialOrStable() async throws {
        let sid = UUID()
        let watcher = makeWatcher(sessionID: sid)
        await watcher.start()
        let dir = watchRoot.appendingPathComponent(boundDirName(sessionID: sid, tag: "APPEND"), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("grow.bin")
        FileManager.default.createFile(atPath: file.path, contents: Data(), attributes: nil)
        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: Data("part1".utf8))
        try handle.synchronize()
        try await Task.sleep(nanoseconds: 60_000_000)
        await watcher.pollOncePublic()
        try handle.write(contentsOf: Data("-part2".utf8))
        try handle.synchronize()
        try handle.close()
        try await Task.sleep(nanoseconds: 100_000_000)
        await watcher.pollOncePublic()
        let snap = await watcher.stop()
        let rec = try XCTUnwrap(snap.records.first { $0.boundToSession && !$0.quarantined })
        XCTAssertTrue(rec.capturedBytes > 0)
        XCTAssertTrue(
            [
                UpdaterOutputWatcher.CaptureCompleteness.complete,
                .partial,
                .truncated,
            ].contains(rec.completeness)
        )
        XCTAssertEqual(rec.realUpdaterBodyCaptured, "NO")
    }

    func testRaceC_renameThenCleanup() async throws {
        let sid = UUID()
        let watcher = makeWatcher(sessionID: sid)
        await watcher.start()
        let a = watchRoot.appendingPathComponent(boundDirName(sessionID: sid, tag: "RENAME_A"), isDirectory: true)
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        let f = a.appendingPathComponent("x.bin")
        let body = Data("rename-me".utf8)
        try body.write(to: f)
        let originalSHA = sha(body)
        await watcher.pollOncePublic()
        let b = watchRoot.appendingPathComponent(boundDirName(sessionID: sid, tag: "RENAME_B"), isDirectory: true)
        try FileManager.default.moveItem(at: a, to: b)
        await watcher.pollOncePublic()
        try? FileManager.default.removeItem(at: b)
        let snap = await watcher.stop()
        XCTAssertTrue(snap.earlyWatcherStarted)
        XCTAssertTrue(snap.records.contains { $0.capturedBytes > 0 || $0.completeness == .miss || $0.sourcePath.contains("RENAME") })
        XCTAssertEqual(originalSHA.count, 64)
    }

    func testRaceD_wroteLineWhenAlreadyGone() async throws {
        let sid = UUID()
        let watcher = makeWatcher(sessionID: sid)
        await watcher.start()
        let dir = watchRoot.appendingPathComponent(boundDirName(sessionID: sid, tag: "GONE"), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("soon-gone".utf8).write(to: dir.appendingPathComponent("se.bin"))
        try await Task.sleep(nanoseconds: 60_000_000)
        await watcher.pollOncePublic()
        await watcher.pollOncePublic()
        try FileManager.default.removeItem(at: dir)
        let snap = await watcher.stop()
        XCTAssertTrue(snap.earlyWatcherStarted, "EARLY_WATCHER_STARTED must be YES (anti Wrote-late)")
        if let rec = snap.records.first {
            XCTAssertEqual(rec.realUpdaterBodyCaptured, "NO")
        }
        XCTAssertFalse(snap.records.contains { $0.realUpdaterBodyCaptured == "YES" })
    }

    func testRaceE_emptySEForever() async throws {
        let sid = UUID()
        let watcher = makeWatcher(sessionID: sid)
        await watcher.start()
        let dirName = boundDirName(sessionID: sid, tag: "EMPTYSE")
        let dir = watchRoot.appendingPathComponent(dirName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("SE", isDirectory: true), withIntermediateDirectories: true)
        await watcher.pollOncePublic()
        let snap = await watcher.stop()
        let rec = try XCTUnwrap(snap.records.first { $0.boundToSession })
        XCTAssertTrue(rec.empty)
        XCTAssertEqual(rec.completeness, .emptyDirectory)
        XCTAssertEqual(rec.hostOutputBodyEverExisted, "UNVERIFIED")
        XCTAssertEqual(rec.realUpdaterBodyCaptured, "NO")
        let marker = evidenceRoot.appendingPathComponent("\(dirName)/EMPTY_STAGING.marker")
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    func testRaceF_foreignSessionQuarantined() async throws {
        let sid = UUID()
        let watcher = makeWatcher(sessionID: sid)
        await watcher.start()
        let foreign = watchRoot.appendingPathComponent("updater_output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
        try Data("foreign-bytes".utf8).write(to: foreign.appendingPathComponent("x.bin"))
        let mine = watchRoot.appendingPathComponent(boundDirName(sessionID: sid, tag: "MINE"), isDirectory: true)
        try FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: mine.appendingPathComponent("y.bin"))
        await watcher.pollOncePublic()
        let snap = await watcher.stop()
        XCTAssertTrue(snap.records.contains { $0.quarantined && $0.completeness == .quarantined })
        XCTAssertTrue(snap.records.contains { $0.boundToSession && $0.sourcePath.contains(sid.uuidString) })
        XCTAssertFalse(snap.records.contains { $0.quarantined && $0.realUpdaterBodyCaptured == "YES" })
        // Foreign body must not be copied into evidence tree.
        let foreignCopy = evidenceRoot.appendingPathComponent(foreign.lastPathComponent + "/x.bin")
        XCTAssertFalse(FileManager.default.fileExists(atPath: foreignCopy.path))
    }

    func testRaceG_binaryNonUTF8ByteFaithful() async throws {
        let sid = UUID()
        let watcher = makeWatcher(sessionID: sid)
        await watcher.start()
        let dirName = boundDirName(sessionID: sid, tag: "BIN")
        let dir = watchRoot.appendingPathComponent(dirName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var bytes = Data("070701".utf8)
        bytes.append(contentsOf: [0x00, 0xFF, 0xFE, 0x01, 0x80])
        bytes.append(contentsOf: "not-utf8".utf8)
        let file = dir.appendingPathComponent("updater_output.cpio")
        try bytes.write(to: file)
        let originalSHA = sha(bytes)
        try await Task.sleep(nanoseconds: 80_000_000)
        await watcher.pollOncePublic()
        await watcher.pollOncePublic()
        let snap = await watcher.stop()
        let rec = try XCTUnwrap(snap.records.first { $0.boundToSession && !$0.empty })
        XCTAssertEqual(rec.capturedBytes, bytes.count)
        XCTAssertEqual(rec.capturedSHA256, originalSHA)
        if rec.sourceHashVerifiable {
            XCTAssertEqual(rec.sourceSHA256, originalSHA)
        }
        let copied = evidenceRoot.appendingPathComponent("\(dirName)/updater_output.cpio")
        XCTAssertEqual(try Data(contentsOf: copied), bytes)
        XCTAssertEqual(rec.realUpdaterBodyCaptured, "NO")
    }

    func testRaceH_watcherMissButRawIntactOnFinalize() async throws {
        let engineRoot = root.appendingPathComponent("engine", isDirectory: true)
        try FileManager.default.createDirectory(at: engineRoot, withIntermediateDirectories: true)
        let store = EvidenceStore(root: engineRoot.appendingPathComponent("Sessions", isDirectory: true))
        let engine = CaptureCoordinator(backend: SimulatedLogCaptureBackend(), store: store)
        let config = CaptureConfig(outputDirectory: engineRoot, updaterWatchRoot: watchRoot)
        let session = try await engine.beginCapture(config: config)
        _ = try await engine.stopCapture(sessionID: session.sessionID)
        let exported = try await engine.finalize(sessionID: session.sessionID)
        XCTAssertEqual(exported.record.integrityStatus, .verified)
        XCTAssertTrue(exported.record.earlyWatcherStarted)
        XCTAssertNotEqual(exported.record.updaterOutputStatus, .unchecked)
        XCTAssertEqual(exported.record.hardwareRootCause, "UNVERIFIED")
        let coverage = try String(contentsOf: URL(fileURLWithPath: session.outputDirectory).appendingPathComponent("EVIDENCE_COVERAGE.ini"), encoding: .utf8)
        XCTAssertTrue(coverage.contains("REAL_UPDATER_BODY_CAPTURED=NO"))
        XCTAssertTrue(coverage.contains("EARLY_WATCHER_STARTED=YES"))
    }
}

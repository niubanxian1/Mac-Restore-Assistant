import Foundation
import XCTest
@testable import RestoreLogEngine

/// Merged by Writer for RLM_1_2_P0_PERFORMANCE_AND_SOURCE_005.
/// Spec: workers/C/C_X1_HARNESS_SPEC.md
///
/// Full CaptureCoordinator X1 × 100 with disk session.json checks.
final class P0Performance005X1Tests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlm-x1-005-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var outDir: URL? {
        guard let p = ProcessInfo.processInfo.environment["RLM12_X1_OUT_DIR"], !p.isEmpty else { return nil }
        return URL(fileURLWithPath: p, isDirectory: true)
    }

    private func evidenceContains(_ sessionDir: URL, _ needle: String) -> Bool {
        guard let en = FileManager.default.enumerator(
            at: sessionDir,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) else { return false }
        for case let u as URL in en {
            guard (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > 4_000_000 { continue }
            if let d = try? Data(contentsOf: u), String(decoding: d, as: UTF8.self).contains(needle) {
                return true
            }
        }
        return false
    }

    private func loadSessionJSON(at url: URL) throws -> SessionRecord {
        let data = try Data(contentsOf: url)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(SessionRecord.self, from: data)
    }

    private func x1Iteration(_ index: Int) async throws -> [String: Any] {
        let iterRoot = root.appendingPathComponent("x1-\(index)", isDirectory: true)
        let watch = iterRoot.appendingPathComponent("watch", isDirectory: true)
        let outside = iterRoot.appendingPathComponent("outside", isDirectory: true)
        let sa = iterRoot.appendingPathComponent("storeA", isDirectory: true)
        let sb = iterRoot.appendingPathComponent("storeB", isDirectory: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sa, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sb, withIntermediateDirectories: true)
        try Data("LEAK-SECRET-BYTES".utf8).write(to: outside.appendingPathComponent("secret.bin"))

        let a = CaptureCoordinator(backend: SimulatedLogCaptureBackend(), store: EvidenceStore(root: sa))
        let b = CaptureCoordinator(backend: SimulatedLogCaptureBackend(), store: EvidenceStore(root: sb))

        let ha = try await a.beginCapture(config: CaptureConfig(outputDirectory: iterRoot, updaterWatchRoot: watch))
        let hb = try await b.beginCapture(config: CaptureConfig(outputDirectory: iterRoot, updaterWatchRoot: watch))

        let da = watch.appendingPathComponent("updater_output-\(ha.sessionID.uuidString)", isDirectory: true)
        let db = watch.appendingPathComponent("updater_output-\(hb.sessionID.uuidString)", isDirectory: true)
        let dr = watch.appendingPathComponent("updater_output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: da, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: db, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dr, withIntermediateDirectories: true)
        try Data("A-ONLY-BODY".utf8).write(to: da.appendingPathComponent("a.bin"))
        try Data("B-ONLY-BODY".utf8).write(to: db.appendingPathComponent("b.bin"))
        try Data("RANDOM-SECRET-BODY".utf8).write(to: dr.appendingPathComponent("r.bin"))

        let link = watch.appendingPathComponent("updater_output-\(ha.sessionID.uuidString)-LINK", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: da.appendingPathComponent("dirlink"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(
            at: da.appendingPathComponent("filelink"),
            withDestinationURL: outside.appendingPathComponent("secret.bin")
        )

        try await Task.sleep(nanoseconds: 900_000_000)
        _ = try await a.stopCapture(sessionID: ha.sessionID)
        _ = try await b.stopCapture(sessionID: hb.sessionID)
        let ea = try await a.finalize(sessionID: ha.sessionID)
        let eb = try await b.finalize(sessionID: hb.sessionID)

        let adir = URL(fileURLWithPath: ha.outputDirectory)
        let bdir = URL(fileURLWithPath: hb.outputDirectory)

        let aJSONURL = adir.appendingPathComponent("session.json")
        let bJSONURL = bdir.appendingPathComponent("session.json")
        let aDisk = try loadSessionJSON(at: aJSONURL)
        let bDisk = try loadSessionJSON(at: bJSONURL)

        let aOwn = evidenceContains(adir, "A-ONLY-BODY")
        let bOwn = evidenceContains(bdir, "B-ONLY-BODY")
        let aContainsB = evidenceContains(adir, "B-ONLY-BODY")
        let bContainsA = evidenceContains(bdir, "A-ONLY-BODY")
        let aRandom = evidenceContains(adir, "RANDOM-SECRET-BODY")
        let bRandom = evidenceContains(bdir, "RANDOM-SECRET-BODY")
        let aLeak = evidenceContains(adir, "LEAK-SECRET-BYTES")
        let bLeak = evidenceContains(bdir, "LEAK-SECRET-BYTES")

        let diskMismatchA =
            aDisk.updaterOutputStatus != ea.record.updaterOutputStatus
            || aDisk.files.count != ea.record.files.count
        let diskMismatchB =
            bDisk.updaterOutputStatus != eb.record.updaterOutputStatus
            || bDisk.files.count != eb.record.files.count

        // Persist copies for Orch when env set.
        if let out = outDir {
            let dest = out.appendingPathComponent("iters/i=\(index)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: aJSONURL, to: dest.appendingPathComponent("sessionA.json"))
            try? FileManager.default.copyItem(at: bJSONURL, to: dest.appendingPathComponent("sessionB.json"))
        }

        // Critical STATUS invariants (fail the XCTest, not only JSON counters).
        if aOwn {
            XCTAssertNotEqual(
                aDisk.updaterOutputStatus, .emptyDirectory,
                "iter \(index): emptyDirectory must not erase A-ONLY body"
            )
            if let layers = aDisk.updaterStatusLayers {
                XCTAssertTrue(layers.integrity.anyProvenBody, "iter \(index): layers.anyProvenBody")
            }
        }
        if bOwn {
            XCTAssertNotEqual(
                bDisk.updaterOutputStatus, .quarantined,
                "iter \(index): quarantine-only must not erase B-ONLY body"
            )
            XCTAssertNotEqual(bDisk.updaterOutputStatus, .emptyDirectory)
        }
        XCTAssertFalse(aContainsB)
        XCTAssertFalse(bContainsA)
        XCTAssertFalse(aLeak)
        XCTAssertFalse(bLeak)
        XCTAssertTrue(aOwn)
        XCTAssertTrue(bOwn)
        XCTAssertFalse(diskMismatchA)
        XCTAssertFalse(diskMismatchB)

        // File count / size: every session.json file entry must exist on disk with matching size.
        for (label, dir, rec) in [("A", adir, aDisk), ("B", bdir, bDisk)] {
            for f in rec.files {
                let u = dir.appendingPathComponent(f.relativePath)
                var isDir: ObjCBool = false
                XCTAssertTrue(
                    FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir) && !isDir.boolValue,
                    "iter \(index) \(label) missing \(f.relativePath)"
                )
                let sz = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
                XCTAssertEqual(sz, f.byteSize, "iter \(index) \(label) size mismatch \(f.relativePath)")
            }
        }

        return [
            "index": index,
            "a_status": aDisk.updaterOutputStatus.rawValue,
            "b_status": bDisk.updaterOutputStatus.rawValue,
            "a_own": aOwn, "b_own": bOwn,
            "a_contains_b": aContainsB, "b_contains_a": bContainsA,
            "a_contains_random": aRandom, "b_contains_random": bRandom,
            "a_symlink_escape": aLeak, "b_symlink_escape": bLeak,
            "a_empty_with_body": aOwn && aDisk.updaterOutputStatus == .emptyDirectory,
            "b_quarantine_with_body": bOwn && bDisk.updaterOutputStatus == .quarantined,
            "session_json_disk_mismatch": diskMismatchA || diskMismatchB,
            "a_file_count": aDisk.files.count,
            "b_file_count": bDisk.files.count,
            "a_layers_version": aDisk.updaterStatusLayers?.summaryDerivationVersion as Any,
            "b_layers_version": bDisk.updaterStatusLayers?.summaryDerivationVersion as Any,
        ]
    }

    func testX1_coordinatorMultiSession100_persistsSessionJSON() async throws {
        var rows: [[String: Any]] = []
        for i in 0..<100 {
            do {
                rows.append(try await x1Iteration(i))
            } catch {
                rows.append(["index": i, "error": String(describing: error)])
                XCTFail("iter \(i) error: \(error)")
            }
        }

        let errors = rows.filter { $0["error"] != nil }.count
        let cross = rows.filter { ($0["a_contains_b"] as? Bool == true) || ($0["b_contains_a"] as? Bool == true) }.count
        let random = rows.filter {
            // Bound contamination: presence under A/B trees may be OK only if unbound vault —
            // for this synth, treat any RANDOM-SECRET in A/B evidence as contamination signal
            // unless Writer documents unbound isolation path. Spec default: count as fail.
            ($0["a_contains_random"] as? Bool == true) || ($0["b_contains_random"] as? Bool == true)
        }.count
        let leak = rows.filter { ($0["a_symlink_escape"] as? Bool == true) || ($0["b_symlink_escape"] as? Bool == true) }.count
        let ownMiss = rows.filter { ($0["a_own"] as? Bool != true) || ($0["b_own"] as? Bool != true) }.count
        let aEmptyBody = rows.filter { $0["a_empty_with_body"] as? Bool == true }.count
        let bQuarBody = rows.filter { $0["b_quarantine_with_body"] as? Bool == true }.count
        let diskMis = rows.filter { $0["session_json_disk_mismatch"] as? Bool == true }.count
        let aStatuses = Dictionary(grouping: rows.compactMap { $0["a_status"] as? String }, by: { $0 }).mapValues(\.count)
        let bStatuses = Dictionary(grouping: rows.compactMap { $0["b_status"] as? String }, by: { $0 }).mapValues(\.count)

        let summary: [String: Any] = [
            "task_id": "RLM_1_2_P0_PERFORMANCE_AND_SOURCE_005",
            "iterations": rows.count,
            "errors": errors,
            "cross_contamination_iterations": cross,
            "random_uuid_contamination_iterations": random,
            "symlink_escape_iterations": leak,
            "own_body_missing_iterations": ownMiss,
            "a_emptyDirectory_with_body_iterations": aEmptyBody,
            "b_quarantine_only_with_body_iterations": bQuarBody,
            "session_json_disk_mismatch_iterations": diskMis,
            "a_status_distribution": aStatuses,
            "b_status_distribution": bStatuses,
            "SESSION_STATE_LAST_WINS_COUNT": max(0, aStatuses.count - 1) + max(0, bStatuses.count - 1),
            "rows": rows,
        ]

        XCTAssertEqual(errors, 0)
        XCTAssertEqual(cross, 0)
        XCTAssertEqual(leak, 0)
        XCTAssertEqual(ownMiss, 0)
        XCTAssertEqual(aEmptyBody, 0)
        XCTAssertEqual(bQuarBody, 0)
        XCTAssertEqual(diskMis, 0)
        XCTAssertEqual(aStatuses.count, 1, "A status must be deterministic across 100; got \(aStatuses)")
        XCTAssertEqual(bStatuses.count, 1, "B status must be deterministic across 100; got \(bStatuses)")
        // Random: if product quarantines into session tree, Writer must tighten assertion;
        // default fail keeps Owner contract honest.
        XCTAssertEqual(random, 0, "random UUID body must not contaminate A/B bound evidence")

        if let out = outDir {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: out.appendingPathComponent("x1_100_results.json"))
        }
    }
}

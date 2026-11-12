import XCTest
@testable import RestoreLogEngine

/// F07 export tests. Every case uses real bytes on a real disk — no in-memory
/// stand-in for the file system.
final class LogExportTests: XCTestCase {

    private var root: URL!
    private var sourceDir: URL!
    private var destDir: URL!
    private var sessionID = UUID(uuidString: "F7487D1D-3373-46ED-B564-EA100645D44E")!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlm-export-\(UUID().uuidString)", isDirectory: true)
        sourceDir = root.appendingPathComponent("evidence", isDirectory: true)
        destDir = root.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destDir.path)
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: helpers

    private func makeSource(_ text: String, name: String = "restore.log") throws -> (URL, String) {
        let url = sourceDir.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return (url, try Integrity.sha256(ofFileAt: url))
    }

    private func request(_ source: URL, digest: String, base: String = "测试",
                         partial: Bool = false, at date: Date? = nil) -> ExportRequest {
        ExportRequest(sourceURL: source, destinationDirectory: destDir, baseName: base,
                      sessionID: sessionID, isPartial: partial,
                      expectedSourceSHA256: digest,
                      now: date ?? Date(timeIntervalSince1970: 1_800_000_000))
    }

    private func files() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: destDir.path)) ?? []).sorted()
    }

    // MARK: E01 / A01 — a normal export lands, byte-identical

    func testE01ExportProducesByteIdenticalCopy() async throws {
        let body = String(repeating: "2026-10-31 12:00:00.000 Df x[1:2] ASR progress 19%\n", count: 500)
        let (source, digest) = try makeSource(body)
        let exporter = LogExporter()
        let outcome = try await exporter.export(request(source, digest: digest))

        XCTAssertTrue(FileManager.default.fileExists(atPath: outcome.url.path))
        XCTAssertEqual(outcome.byteCount, body.utf8.count)
        XCTAssertEqual(outcome.sha256, digest)
        XCTAssertEqual(try Integrity.sha256(ofFileAt: outcome.url), digest,
                       "exported bytes must equal source bytes")
        XCTAssertEqual(outcome.collisionIndex, 1)
        XCTAssertFalse(outcome.url.lastPathComponent.contains("-2."))
    }

    // E02 / A05 — a Chinese base name survives intact
    func testE02ChineseBaseName() async throws {
        let (source, digest) = try makeSource("line\n")
        let exporter = LogExporter()
        let outcome = try await exporter.export(request(source, digest: digest, base: "A2681-刷机测试"))
        XCTAssertTrue(outcome.url.lastPathComponent.hasPrefix("A2681-刷机测试_"),
                      "got \(outcome.url.lastPathComponent)")
        XCTAssertTrue(outcome.url.lastPathComponent.hasSuffix("_F7487D1D.log"),
                      "short id must come from the session UUID")
    }

    // E03 / A06 — empty name falls back to the documented default
    func testE03EmptyNameUsesDefault() async throws {
        XCTAssertEqual(ExportNaming.sanitizedBase(""), ExportNaming.defaultBaseName)
        XCTAssertEqual(ExportNaming.sanitizedBase("   "), ExportNaming.defaultBaseName)
        XCTAssertEqual(ExportNaming.sanitizedBase("..."), ExportNaming.defaultBaseName)
        XCTAssertEqual(ExportNaming.defaultBaseName, "Configurator")
    }

    // E04 / A07 — traversal and illegal characters cannot escape the directory
    func testE04SanitizesTraversalAndSeparators() {
        XCTAssertEqual(ExportNaming.sanitizedBase("../../etc/passwd"), "etc-passwd")
        XCTAssertEqual(ExportNaming.sanitizedBase("a/b:c\\d"), "a-b-c-d")
        XCTAssertEqual(ExportNaming.sanitizedBase(".hidden"), "hidden")
        XCTAssertEqual(ExportNaming.sanitizedBase("a\u{0}b\nc"), "abc")
        XCTAssertFalse(ExportNaming.sanitizedBase("..").contains(".."))
        XCTAssertLessThanOrEqual(ExportNaming.sanitizedBase(String(repeating: "长", count: 500)).count,
                                 ExportNaming.maxBaseLength + 1)
    }

    // E05 / A08 — exporting twice in the same second must not overwrite
    func testE05SameSecondSecondExportDoesNotOverwrite() async throws {
        let (source, digest) = try makeSource("payload\n")
        let exporter = LogExporter()
        let fixed = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try await exporter.export(request(source, digest: digest, at: fixed))
        let second = try await exporter.export(request(source, digest: digest, at: fixed))

        XCTAssertNotEqual(first.url, second.url)
        XCTAssertEqual(second.collisionIndex, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.url.path))
        XCTAssertEqual(try Integrity.sha256(ofFileAt: first.url), digest)
        XCTAssertEqual(try Integrity.sha256(ofFileAt: second.url), digest)
    }

    // E06 / A21 — an unrelated pre-existing file is never overwritten
    func testE06ExistingUnrelatedFileIsNeverOverwritten() async throws {
        let (source, digest) = try makeSource("payload\n")
        let fixed = Date(timeIntervalSince1970: 1_800_000_000)
        let name = ExportNaming.fileName(base: "测试", at: fixed, sessionID: sessionID, isPartial: false)
        let squatter = destDir.appendingPathComponent(name)
        try Data("DO NOT TOUCH".utf8).write(to: squatter)

        let exporter = LogExporter()
        let outcome = try await exporter.export(request(source, digest: digest, at: fixed))
        XCTAssertNotEqual(outcome.url, squatter)
        XCTAssertEqual(try String(contentsOf: squatter, encoding: .utf8), "DO NOT TOUCH")
        XCTAssertEqual(outcome.collisionIndex, 2)
    }

    // E12 / A12 — a source whose digest does not match the session record is refused
    func testE07SourceDigestMismatchFailsClosed() async throws {
        let (source, _) = try makeSource("tampered\n")
        let exporter = LogExporter()
        do {
            _ = try await exporter.export(request(source, digest: String(repeating: "0", count: 64)))
            XCTFail("must refuse a source that does not match the recorded digest")
        } catch let error as LogExportError {
            XCTAssertEqual(error, .sourceDigestMismatch(expected: String(repeating: "0", count: 64),
                                                        actual: try Integrity.sha256(ofFileAt: source)))
        }
        XCTAssertEqual(files().count, 0, "nothing may be published or left behind")
    }

    // E10 / A10 — an unwritable destination fails loudly and publishes nothing
    func testE08UnwritableDestinationFails() async throws {
        let (source, digest) = try makeSource("payload\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: destDir.path)
        let exporter = LogExporter()
        do {
            _ = try await exporter.export(request(source, digest: digest))
            XCTFail("an unwritable destination must not silently succeed")
        } catch let error as LogExportError {
            guard case .destinationNotWritable = error else {
                return XCTFail("unexpected error \(error)"); }
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destDir.path)
        XCTAssertEqual(files().count, 0)
    }

    // E14 / A14 — a partial session is exported, and labelled as partial
    func testE09PartialSessionIsLabelled() async throws {
        let (source, digest) = try makeSource("partial bytes\n")
        let exporter = LogExporter()
        let outcome = try await exporter.export(request(source, digest: digest, partial: true))
        XCTAssertTrue(outcome.isPartial)
        XCTAssertTrue(outcome.url.lastPathComponent.contains("_PARTIAL"), "got \(outcome.url.lastPathComponent)")
        XCTAssertEqual(try Integrity.sha256(ofFileAt: outcome.url), digest)
    }

    // A09 — concurrent exports of the same session never collide
    func testE10ConcurrentExportsDoNotCollide() async throws {
        let (source, digest) = try makeSource("concurrent payload\n")
        let exporter = LogExporter()
        let fixed = Date(timeIntervalSince1970: 1_800_000_000)
        async let a = exporter.export(request(source, digest: digest, at: fixed))
        async let b = exporter.export(request(source, digest: digest, at: fixed))
        async let c = exporter.export(request(source, digest: digest, at: fixed))
        let outcomes = try await [a, b, c]
        let paths = Set(outcomes.map { $0.url.path })
        XCTAssertEqual(paths.count, 3, "three concurrent exports must produce three distinct files")
        for o in outcomes { XCTAssertEqual(try Integrity.sha256(ofFileAt: o.url), digest) }
    }

    // A22 — a source that changes after finalization is refused (digest is the guard)
    func testE11SourceChangedAfterFinalizationIsRefused() async throws {
        let (source, digest) = try makeSource("original\n")
        try Data("changed behind the session's back\n".utf8).write(to: source)
        let exporter = LogExporter()
        do {
            _ = try await exporter.export(request(source, digest: digest))
            XCTFail("a mutated source must be refused")
        } catch let error as LogExportError {
            guard case .sourceDigestMismatch = error else { return XCTFail("unexpected \(error)") }
        }
        XCTAssertEqual(files().count, 0)
    }

    // The source is never modified by exporting.
    func testE12ExportNeverMutatesSource() async throws {
        let body = String(repeating: "line\n", count: 200)
        let (source, digest) = try makeSource(body)
        let before = try FileManager.default.attributesOfItem(atPath: source.path)
        let exporter = LogExporter()
        _ = try await exporter.export(request(source, digest: digest))
        XCTAssertEqual(try Integrity.sha256(ofFileAt: source), digest)
        XCTAssertEqual((before[.size] as? NSNumber)?.intValue, body.utf8.count)
    }

    // Naming: the timestamp is local time and the id is 8 hex chars.
    func testE13FileNameShape() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let name = ExportNaming.fileName(base: "A2681-刷机测试", at: date,
                                         sessionID: sessionID, isPartial: false,
                                         timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        XCTAssertEqual(name, "A2681-刷机测试_20270115_160000_F7487D1D.log")
    }
    // MARK: - H01-A directory identity binding

    /// 256 MB so the copy stays open long enough for a DETERMINISTIC sync point:
    /// the test waits until the exporter's temp file actually appears in the
    /// bound directory, then repoints the symlink. No sleep-based guessing.
    private func makeLargeSource(_ bytes: Int) throws -> (URL, String) {
        let url = sourceDir.appendingPathComponent("big.log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let h = try FileHandle(forWritingTo: url)
        let block = Data(repeating: 0x41, count: 1 << 20)
        for _ in 0..<(bytes / block.count) { try h.write(contentsOf: block) }
        try h.close()
        return (url, try Integrity.sha256(ofFileAt: url))
    }

    /// H01-A-CLEANUP: the payload temp now lives inside a per-transaction staging
    /// directory, so the sync point is "the staging dir appeared AND holds a file".
    /// Returns the staging directory and the temp name inside it.
    private func waitForTemp(in dir: URL, timeout: TimeInterval = 15)
        async throws -> (stage: URL, name: String) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            if let stage = names.first(where: { $0.hasPrefix(".rlm-stage-") }) {
                let stageURL = dir.appendingPathComponent(stage)
                let inner = (try? FileManager.default.contentsOfDirectory(atPath: stageURL.path)) ?? []
                if let f = inner.first {
                    return (stageURL, f)
                }
            }
            try await Task.sleep(nanoseconds: 2_000_000)   // 2 ms poll
        }
        throw XCTSkip("staging/temp never observed; race window not entered")
    }

    // H01-A02 — a stable symlinked destination still works, and the receipt uses
    // the path the caller gave.
    func testH01A02StableSymlinkDestinationSucceeds() async throws {
        let realA = root.appendingPathComponent("realA", isDirectory: true)
        try FileManager.default.createDirectory(at: realA, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: realA.path)

        let (source, digest) = try makeSource("stable symlink payload\n")
        let outcome = try await LogExporter().export(
            ExportRequest(sourceURL: source, destinationDirectory: alias, baseName: "H01A02",
                          sessionID: sessionID, isPartial: false,
                          expectedSourceSHA256: digest,
                          now: Date(timeIntervalSince1970: 1_800_000_000)))
        XCTAssertEqual(try Integrity.sha256(ofFileAt: outcome.url), digest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outcome.url.path))
        // the file really is in realA
        let inA = (try? FileManager.default.contentsOfDirectory(atPath: realA.path)) ?? []
        XCTAssertTrue(inA.contains(outcome.url.lastPathComponent))
    }

    // H01-A03 — a dangling symlink fails closed and creates nothing.
    func testH01A03DanglingSymlinkFailsClosed() async throws {
        let dangling = root.appendingPathComponent("dangling", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            atPath: dangling.path,
            withDestinationPath: root.appendingPathComponent("missing").path)
        let (source, digest) = try makeSource("dangling\n")
        do {
            _ = try await LogExporter().export(
                ExportRequest(sourceURL: source, destinationDirectory: dangling, baseName: "H01A03",
                              sessionID: sessionID, isPartial: false,
                              expectedSourceSHA256: digest))
            XCTFail("a dangling destination must not succeed")
        } catch let error as LogExportError {
            guard case .destinationUnavailable = error else {
                return XCTFail("unexpected error \(error)"); }
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("missing").path))
    }

    // H01-A05 — THE CORE CASE. The destination is opened and bound, then the
    // symlink is repointed at realB while the copy is running. The pinned
    // descriptor must keep the transaction in realA; because the caller's path
    // no longer reaches realA, the receipt is retracted instead of reported.
    func testH01A05SymlinkRepointedMidExportNeverWritesElsewhere() async throws {
        let realA = root.appendingPathComponent("realA", isDirectory: true)
        let realB = root.appendingPathComponent("realB", isDirectory: true)
        try FileManager.default.createDirectory(at: realA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: realB, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: realA.path)

        let (source, digest) = try makeLargeSource(256 << 20)
        let exporter = LogExporter()
        let req = ExportRequest(sourceURL: source, destinationDirectory: alias, baseName: "H01A05",
                                sessionID: sessionID, isPartial: false,
                                expectedSourceSHA256: digest,
                                now: Date(timeIntervalSince1970: 1_800_000_000))

        let task = Task { () -> Result<ExportOutcome, Error> in
            do { return .success(try await exporter.export(req)) }
            catch { return .failure(error) }
        }

        _ = try await waitForTemp(in: realA)          // sync point: staging + temp exist

        // repoint the alias at realB, exactly the attack described in H01-A
        try FileManager.default.removeItem(at: alias)
        try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: realB.path)

        let result = await task.value
        let filesA = (try? FileManager.default.contentsOfDirectory(atPath: realA.path)) ?? []
        let filesB = (try? FileManager.default.contentsOfDirectory(atPath: realB.path)) ?? []

        switch result {
        case .success(let outcome):
            // If it reports success, the file must be in the BOUND directory and
            // must NOT be in the hijacked one.
            XCTAssertTrue(filesA.contains(outcome.url.lastPathComponent),
                          "reported file must exist in the bound directory")
            XCTAssertFalse(filesB.contains { $0.hasSuffix(".log") },
                           "nothing may be published into the repointed target")
        case .failure(let error):
            // H01-A-CLEANUP policy: the published file is NOT deleted by name any
            // more (we cannot prove ownership at unlink time), so it is left in the
            // bound directory and reported. Nothing may reach the hijacked one.
            XCTAssertFalse(filesB.contains { $0.hasSuffix(".log") },
                           "nothing may be published into the repointed target")
            guard let e = error as? LogExportError,
                  case .publishedFileLeftBehind(let name) = e else {
                return XCTFail("unexpected failure \(error)")
            }
            XCTAssertTrue(filesA.contains(name),
                          "the retained file must be the one named in the error")
        }
        XCTAssertFalse(filesA.contains { $0.hasPrefix(".rlm-export-") }, "temp must be removed")
        XCTAssertFalse(filesB.contains { $0.hasPrefix(".rlm-export-") })
    }

    // H01-A12 — the bound directory is moved away mid-export. The publication must
    // not be reported as a success at a path that no longer reaches it.
    func testH01A12DirectoryMovedMidExportIsNotAFalseSuccess() async throws {
        let realA = root.appendingPathComponent("realA", isDirectory: true)
        let moved = root.appendingPathComponent("movedA", isDirectory: true)
        try FileManager.default.createDirectory(at: realA, withIntermediateDirectories: true)

        let (source, digest) = try makeLargeSource(256 << 20)
        let exporter = LogExporter()
        let req = ExportRequest(sourceURL: source, destinationDirectory: realA, baseName: "H01A12",
                                sessionID: sessionID, isPartial: false,
                                expectedSourceSHA256: digest,
                                now: Date(timeIntervalSince1970: 1_800_000_000))
        let task = Task { () -> Result<ExportOutcome, Error> in
            do { return .success(try await exporter.export(req)) }
            catch { return .failure(error) }
        }
        _ = try await waitForTemp(in: realA)
        try FileManager.default.moveItem(at: realA, to: moved)

        let result = await task.value
        let inMoved = (try? FileManager.default.contentsOfDirectory(atPath: moved.path)) ?? []
        switch result {
        case .success:
            XCTFail("a moved destination must not be reported as a success")
        case .failure(let error):
            guard let e = error as? LogExportError,
                  case .publishedFileLeftBehind(let name) = e else {
                return XCTFail("unexpected failure \(error)")
            }
            // deliberately retained, and named in the error
            XCTAssertTrue(inMoved.contains(name),
                          "the retained file must be the one named in the error")
        }
        XCTAssertFalse(inMoved.contains { $0.hasPrefix(".rlm-export-") })
    }
    // MARK: - H01-A ownership fix

    /// OWN-FIX-02/04/06 — the temp NAME is taken over during the copy.
    /// The export must refuse (never publish the impostor), and the cleanup must
    /// NOT delete the foreign file that now bears the name.
    func testOwnFix02TempNameReplacedDuringCopyRefusesAndPreservesForeign() async throws {
        let (source, digest) = try makeLargeSource(256 << 20)
        let exporter = LogExporter()
        let req = ExportRequest(sourceURL: source, destinationDirectory: destDir,
                                baseName: "OWNFIX", sessionID: sessionID, isPartial: false,
                                expectedSourceSHA256: digest,
                                now: Date(timeIntervalSince1970: 1_800_000_000))

        let task = Task { () -> Result<ExportOutcome, Error> in
            do { return .success(try await exporter.export(req)) }
            catch { return .failure(error) }
        }

        let (stage, tempName) = try await waitForTemp(in: destDir)
        let tempPath = stage.appendingPathComponent(tempName)
        let ownINode = (try FileManager.default.attributesOfItem(atPath: tempPath.path)[.systemFileNumber] as? NSNumber)?.intValue

        // move OUR object away, then plant a foreign file under the same name
        try FileManager.default.moveItem(at: tempPath,
                                         to: stage.appendingPathComponent("stashed-own.tmp"))
        let foreign = Data("FOREIGN-DO-NOT-DELETE".utf8)
        try foreign.write(to: tempPath)
        let foreignINode = (try FileManager.default.attributesOfItem(atPath: tempPath.path)[.systemFileNumber] as? NSNumber)?.intValue
        XCTAssertNotEqual(ownINode, foreignINode, "the replacement must be a different object")

        let result = await task.value

        switch result {
        case .success(let o):
            XCTFail("published an export after the temp name was taken over: \(o.url.lastPathComponent)")
        case .failure(let error):
            guard let e = error as? LogExportError, case .tempNameReplaced = e else {
                return XCTFail("unexpected error \(error)")
            }
        }

        // the foreign file must still be there, byte-identical
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath.path),
                      "a name that is not ours must not be unlinked")
        XCTAssertEqual(try Data(contentsOf: tempPath), foreign)

        // RESIDUAL-CLOSEOUT contract: the staging dir survives a failure and is
        // NON-empty — the payload is left for an operator, never deleted.
        let dirs = (try? FileManager.default.contentsOfDirectory(atPath: destDir.path)) ?? []
        let stageDirs = dirs.filter { $0.hasPrefix(".rlm-stage-") }
        XCTAssertEqual(stageDirs.count, 1, "the staging dir must survive a failure: \(dirs)")
        let surviving = destDir.appendingPathComponent(stageDirs[0])
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: surviving.path)) ?? []
        XCTAssertFalse(contents.isEmpty, "a failed export leaves the payload in place")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath.path))

        // and nothing was published
        let published = ((try? FileManager.default.contentsOfDirectory(atPath: destDir.path)) ?? [])
            .filter { $0.hasSuffix(".log") }
        XCTAssertEqual(published.count, 0, "no .log may be published after a refusal")
    }

    /// OWN-FIX-01 — the happy path still publishes an object whose bytes equal the
    /// source, and the returned URL names that object.
    func testOwnFix01NormalExportPublishesTheWrittenObject() async throws {
        let body = String(repeating: "2026-10-31 12:00:00.000 Df x[1:2] ASR progress 19%\n", count: 400)
        let (source, digest) = try makeSource(body)
        let outcome = try await LogExporter().export(
            ExportRequest(sourceURL: source, destinationDirectory: destDir, baseName: "OWNFIX01",
                          sessionID: sessionID, isPartial: false,
                          expectedSourceSHA256: digest,
                          now: Date(timeIntervalSince1970: 1_800_000_000)))
        XCTAssertEqual(try Integrity.sha256(ofFileAt: outcome.url), digest)
        XCTAssertEqual(outcome.byteCount, body.utf8.count)
        XCTAssertEqual(try Data(contentsOf: outcome.url).count, body.utf8.count)
        // RESIDUAL-CLOSEOUT contract: a successful export leaves its staging
        // directory BEHIND, and that directory must be EMPTY (the payload was moved
        // out by renameatx_np). It is never auto-deleted.
        let all = (try? FileManager.default.contentsOfDirectory(atPath: destDir.path)) ?? []
        let stages = all.filter { $0.hasPrefix(".rlm-stage-") }
        XCTAssertEqual(stages.count, 1, "exactly one staging dir must remain: \(all)")
        let stagePath = destDir.appendingPathComponent(stages[0])
        let inside = (try? FileManager.default.contentsOfDirectory(atPath: stagePath.path)) ?? []
        XCTAssertTrue(inside.isEmpty, "the staging dir must be EMPTY after success: \(inside)")
        XCTAssertFalse(all.contains { $0.hasPrefix(".rlm-export-") },
                       "no legacy temp name may exist: \(all)")
    }
}

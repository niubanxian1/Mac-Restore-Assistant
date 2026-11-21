import XCTest
@testable import RestoreLogEngine

final class DiagnosticLogBuilderTests: XCTestCase {
    private func fixtureURL(_ name: String) throws -> URL {
        let candidates: [URL?] = [
            Bundle.module.url(forResource: name, withExtension: "log"),
            Bundle.module.url(forResource: name, withExtension: "log", subdirectory: "Fixtures"),
            Bundle.module.resourceURL?.appendingPathComponent("Fixtures/\(name).log"),
            Bundle.module.resourceURL?.appendingPathComponent("\(name).log"),
        ]
        if let url = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return url
        }
        XCTFail("missing fixture \(name).log in \(String(describing: Bundle.module.resourceURL))")
        return URL(fileURLWithPath: "/dev/null")
    }

    func testDG03_successTerminalsPreservedAndNoiseDropped() throws {
        let raw = try fixtureURL("fx_ok_compact")
        let rawBefore = try Data(contentsOf: raw)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("diag-ok-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: out) }
        let metrics = try DiagnosticLogBuilder.build(fromRaw: raw, to: out)
        let rawAfter = try Data(contentsOf: raw)
        XCTAssertEqual(rawBefore, rawAfter, "raw must stay immutable")
        XCTAssertEqual(metrics.terminalKind, .success)
        let diag = try String(contentsOf: out, encoding: .utf8)
        XCTAssertTrue(diag.lowercased().contains("restore succeeded"))
        XCTAssertTrue(diag.lowercased().contains("was successful"))
        XCTAssertTrue(diag.contains("progress -1"))
        XCTAssertFalse(diag.contains("found no value for key"))
        XCTAssertFalse(diag.contains("CFPrefs"))
        XCTAssertFalse(diag.lowercased().contains("chip is damaged"))
        XCTAssertFalse(diag.lowercased().contains("芯片损坏"))
        XCTAssertGreaterThan(metrics.droppedLines, 0)
    }

    func testDG04_05_failureTerminalsPreservedProgressNotAlone() throws {
        let raw = try fixtureURL("fx_fail_compact")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("diag-fail-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: out) }
        let metrics = try DiagnosticLogBuilder.build(fromRaw: raw, to: out)
        XCTAssertEqual(metrics.terminalKind, .failure)
        let diag = try String(contentsOf: out, encoding: .utf8)
        XCTAssertTrue(diag.contains("Restore failed"))
        XCTAssertTrue(diag.contains("AMRestoreErrorDomain"))
        XCTAssertTrue(diag.contains("RamrodErrorDomain"))
        XCTAssertTrue(diag.contains("progress -1"))
        // Mid progress -1 must remain CONTEXT; classifier still failure due to allowlist
        let onlyProgress = "DeviceService (MobileDevice): operation 4 progress -1\n"
        XCTAssertEqual(DiagnosticLogBuilder.classifyTerminal(in: onlyProgress), .none)
        XCTAssertTrue(DiagnosticLogBuilder.progressMinusOneAloneWouldBeFalseFailure(in: onlyProgress + "noise\n"))
    }

    func testDG06_progressThenSuccessIsSuccess() throws {
        let text = """
        progress -1
        progress -1
        Restore succeeded
        """
        XCTAssertEqual(DiagnosticLogBuilder.classifyTerminal(in: text), .success)
    }

    func testDG08_emptyIsNone() throws {
        let raw = try fixtureURL("fx_empty")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("diag-empty-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: out) }
        let metrics = try DiagnosticLogBuilder.build(fromRaw: raw, to: out)
        XCTAssertEqual(metrics.terminalKind, .none)
        XCTAssertEqual(metrics.rawLines, 0)
    }

    func testFinalizeRegistersDiagnosticWithoutTouchingRaw() throws {
        // Build a minimal session directory as EvidenceStore would.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rlm-fix002-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = EvidenceStore(root: root)
        let paths = try store.createSession(id: UUID())
        let compact = try Data(contentsOf: fixtureURL("fx_fail_compact"))
        try compact.write(to: paths.rawLogURL)
        let rawHashBefore = try Integrity.sha256(ofFileAt: paths.rawLogURL)

        let metrics = try DiagnosticLogBuilder.build(fromRaw: paths.rawLogURL, to: paths.diagnosticLogURL)
        XCTAssertEqual(try Integrity.sha256(ofFileAt: paths.rawLogURL), rawHashBefore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.diagnosticLogURL.path))
        XCTAssertEqual(metrics.terminalKind, .failure)

        let diagHash = try Integrity.sha256(ofFileAt: paths.diagnosticLogURL)
        let files = [
            EvidenceFile(role: "raw-log", relativePath: "restore.log", byteSize: compact.count, sha256: rawHashBefore),
            EvidenceFile(role: "diagnostic-log", relativePath: "diagnostic.log", byteSize: try Integrity.byteSize(ofFileAt: paths.diagnosticLogURL), sha256: diagHash),
        ]
        let sums = files.map { "\($0.sha256)  \($0.relativePath)" }.joined(separator: "\n") + "\n"
        try Data(sums.utf8).write(to: paths.sha256SumsURL, options: .atomic)
        try CaptureCoordinator.verifyChecksumFile(paths: paths, expected: files)

        let record = SessionRecord(
            sessionID: UUID(),
            captureState: .savedPartial,
            captureHealth: .unconfirmed,
            startedAtUTC: nil,
            endedAtUTC: nil,
            captureProfile: "test",
            captureCommand: ["test"],
            captureBackend: "test",
            eventCount: 0,
            coverageStatus: .partial,
            archiveStatus: .notRequested,
            integrityStatus: .verified,
            diagnosticStatus: .ok,
            files: files,
            missingEvidence: [],
            errorReason: nil
        )
        try store.writeJSON(record, to: paths.sessionJSONURL)
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: Data(contentsOf: paths.sessionJSONURL))
        XCTAssertTrue(decoded.files.contains { $0.relativePath == "diagnostic.log" })
        XCTAssertTrue(decoded.files.contains { $0.relativePath == "restore.log" })
    }

    func testTaxonomyTerminalRulesPresent() {
        XCTAssertNotNil(EventTaxonomy.classify("Restore failed (result = -1)"))
        XCTAssertEqual(EventTaxonomy.classify("Restore failed (result = -1)")?.id, "restore.terminal.failure")
        XCTAssertEqual(EventTaxonomy.classify("Restore succeeded")?.id, "restore.terminal.success")
        XCTAssertTrue(EventTaxonomy.terminalEventDetected(inLogText: "foo Restore succeeded bar"))
        XCTAssertFalse(EventTaxonomy.terminalEventDetected(inLogText: "only progress -1 here"))
    }

    func testRLM12_deviceServiceTLSDroppedButMadeaKept() throws {
        let raw = """
        DeviceService: boringssl TLS handshake packet
        DeviceService (MobileDevice): nw_endpoint_handler TLS
        update_madea: /usr/bin/update_mcdp29xx returned 1
        RamrodErrorDomain code:7
        Restore failed (result = -1)
        Wrote updater output to /tmp/updater_output-TEST/SE
        progress -1
        CFURLResolveBookmarkData spam
        """
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rlm12-denoise-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let rawURL = dir.appendingPathComponent("restore.log")
        let diagURL = dir.appendingPathComponent("diagnostic.log")
        try Data(raw.utf8).write(to: rawURL)
        let metrics = try DiagnosticLogBuilder.build(fromRaw: rawURL, to: diagURL)
        let diag = try String(contentsOf: diagURL, encoding: .utf8)
        XCTAssertFalse(diag.contains("boringssl"), diag)
        XCTAssertFalse(diag.contains("nw_endpoint_handler"), diag)
        XCTAssertFalse(diag.contains("CFURLResolveBookmarkData"), diag)
        XCTAssertTrue(diag.contains("update_madea"), diag)
        XCTAssertTrue(diag.contains("Restore failed"), diag)
        XCTAssertTrue(diag.contains("Wrote updater output"), diag)
        XCTAssertTrue(diag.contains("===== FIRST FATAL ====="), diag)
        XCTAssertEqual(metrics.terminalKind, .failure)
        XCTAssertFalse(DiagnosticLogBuilder.shouldKeep("DeviceService: boringssl TLS handshake packet"))
        XCTAssertTrue(DiagnosticLogBuilder.shouldKeep("update_madea failed"))
    }

    func testRLM12_bareDeviceServiceNoLongerContext() {
        XCTAssertFalse(DiagnosticLogBuilder.contextNeedles.contains("DeviceService"))
        XCTAssertFalse(DiagnosticLogBuilder.contextNeedles.contains("InternetService"))
        XCTAssertFalse(DiagnosticLogBuilder.isContext("DeviceService only line"))
    }
}

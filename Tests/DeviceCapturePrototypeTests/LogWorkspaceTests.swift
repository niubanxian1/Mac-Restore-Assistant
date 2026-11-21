import XCTest
@testable import DeviceCapturePrototype
import CryptoKit
import RestoreLogEngine

@MainActor
final class LogWorkspacePreferencesTests: XCTestCase {
    func testPreferencesPersistIndependentExportDirectoriesAndPreviewSettings() {
        let suiteName = "mra-log-preferences-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = LogWorkspacePreferences(defaults: defaults, startingRoot: URL(fileURLWithPath: "/tmp/mra-start"))
        first.autoMonitorEnabled = true
        first.rawLogDirectory = "/tmp/raw-logs"
        first.evidencePackageDirectory = "/tmp/evidence"
        first.defaultFileBaseName = "Bench"
        first.previewAutoScroll = false
        first.previewLineLimit = 320

        let second = LogWorkspacePreferences(defaults: defaults, startingRoot: URL(fileURLWithPath: "/tmp/mra-start"))
        XCTAssertTrue(second.autoMonitorEnabled)
        XCTAssertEqual(second.rawLogDirectory, "/tmp/raw-logs")
        XCTAssertEqual(second.evidencePackageDirectory, "/tmp/evidence")
        XCTAssertEqual(second.defaultFileBaseName, "Bench")
        XCTAssertFalse(second.previewAutoScroll)
        XCTAssertEqual(second.previewLineLimit, 320)
    }
}

final class IncrementalLogProjectionTests: XCTestCase {
    func testProjectionReadsOnlyAppendedBytesAndKeepsBoundedPreview() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mra-projection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("restore.log")
        try Data("one\ntwo\n".utf8).write(to: url)

        let projection = IncrementalLogProjection()
        let first = await projection.snapshot(path: url, maxPreviewLines: 2)
        XCTAssertEqual(first.byteCount, 8)
        XCTAssertEqual(first.lineCount, 2)
        XCTAssertEqual(first.previewLines, ["one", "two"])
        XCTAssertTrue(first.available)

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("three\n".utf8))
        try handle.close()

        let second = await projection.snapshot(path: url, maxPreviewLines: 2)
        XCTAssertEqual(second.byteCount, 14)
        XCTAssertEqual(second.lineCount, 3)
        XCTAssertEqual(second.previewLines, ["two", "three"])
        XCTAssertTrue(second.available)
    }

    func testProjectionDoesNotReportFabricatedPercentWithoutKnownTotal() {
        let progress = LogExportProgress(
            operation: .evidencePackage,
            stage: .verifyingArchive,
            processedBytes: 12,
            totalBytes: 0,
            elapsedSeconds: 1,
            isIndeterminate: true)
        XCTAssertNil(progress.fraction)
        XCTAssertTrue(progress.isIndeterminate)
    }
}

final class ZipProgressTests: XCTestCase {
    func testZipWriterReportsByteProgressRatherThanEntryIndexOnly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mra-zip-progress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("restore.log")
        FileManager.default.createFile(atPath: source.path, contents: nil)
        let handle = try FileHandle(forWritingTo: source)
        let chunk = Data(repeating: 0x41, count: 1024 * 1024)
        for _ in 0..<3 { try handle.write(contentsOf: chunk) }
        try handle.close()

        let destination = root.appendingPathComponent("out.zip")
        let writer = ZipStoreWriter()
        var byteUpdates: [Int64] = []
        _ = try writer.write(
            entries: [ZipEntrySpec(pathInZip: "logs/restore.log", fileURL: source,
                                   data: nil, storedSHA256: nil)],
            to: destination,
            detailedProgress: { update in
                if update.stage == .packagingZIP {
                    byteUpdates.append(update.processedBytes)
                }
            })
        XCTAssertGreaterThan(byteUpdates.count, 1)
        XCTAssertEqual(byteUpdates, byteUpdates.sorted())
        XCTAssertEqual(byteUpdates.last, 3 * 1024 * 1024)
    }
}

final class RawLogExporterTests: XCTestCase {
    private func sourceFile(bytes: Int) throws -> (root: URL, source: URL, sha: String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mra-raw-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("restore.log")
        let handle = FileManager.default.createFile(atPath: source.path, contents: nil)
        XCTAssertTrue(handle)
        let writer = try FileHandle(forWritingTo: source)
        let chunk = Data(repeating: 0x42, count: 1024 * 1024)
        for _ in 0..<bytes / chunk.count { try writer.write(contentsOf: chunk) }
        try writer.close()
        return (root, source, try Integrity.sha256(ofFileAt: source))
    }

    func testRawExportPublishesVerifiedByteIdenticalCopyWithStageProgress() throws {
        let fixture = try sourceFile(bytes: 4 * 1024 * 1024)
        let out = fixture.root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var events: [LogExportProgress] = []
        let result = try RawLogExporter.export(
            RawLogExportRequest(
                sourceURL: fixture.source,
                destinationDirectory: out,
                baseName: "Bench",
                sessionID: UUID(),
                isPartial: true,
                expectedSourceSHA256: fixture.sha),
            shouldCancel: { false },
            progress: { events.append($0) })

        XCTAssertEqual(try Integrity.sha256(ofFileAt: result.url), fixture.sha)
        XCTAssertEqual(try Integrity.sha256(ofFileAt: fixture.source), fixture.sha)
        XCTAssertTrue(events.contains { $0.stage == .validatingRaw })
        XCTAssertTrue(events.contains { $0.stage == .copyingRaw })
        XCTAssertTrue(events.contains { $0.stage == .verifyingArchive })
        XCTAssertEqual(events.last?.stage, .complete)
    }

    func testRawExportCancellationKeepsSourceAndPublishesNothing() throws {
        let fixture = try sourceFile(bytes: 2 * 1024 * 1024)
        let out = fixture.root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var copiedBytes: Int64 = 0
        XCTAssertThrowsError(try RawLogExporter.export(
            RawLogExportRequest(
                sourceURL: fixture.source,
                destinationDirectory: out,
                baseName: "Cancelled",
                sessionID: UUID(),
                isPartial: true,
                expectedSourceSHA256: fixture.sha),
            shouldCancel: { copiedBytes > 0 },
            progress: { update in
                if update.stage == .copyingRaw { copiedBytes = update.processedBytes ?? 0 }
            })) { error in
                XCTAssertTrue(error is CancellationError)
            }

        XCTAssertEqual(try Integrity.sha256(ofFileAt: fixture.source), fixture.sha)
        let files = try FileManager.default.contentsOfDirectory(atPath: out.path)
        XCTAssertFalse(files.contains { $0.hasSuffix(".log") })
    }

    func testRepeatedRawExportUsesDistinctDestinationsWithoutOverwriting() throws {
        let fixture = try sourceFile(bytes: 256 * 1024)
        let out = fixture.root.appendingPathComponent("repeat", isDirectory: true)
        let request = RawLogExportRequest(
            sourceURL: fixture.source,
            destinationDirectory: out,
            baseName: "repeat",
            sessionID: UUID(),
            isPartial: true,
            expectedSourceSHA256: fixture.sha)
        let first = try RawLogExporter.export(request)
        let firstHash = try Integrity.sha256(ofFileAt: first.url)
        let second = try RawLogExporter.export(request)
        XCTAssertNotEqual(first.url, second.url)
        XCTAssertEqual(try Integrity.sha256(ofFileAt: first.url), firstHash)
        XCTAssertEqual(try Integrity.sha256(ofFileAt: second.url), fixture.sha)
    }
}

@MainActor
final class EvidencePackageProgressTests: XCTestCase {
    func testEvidencePackageProgressUsesRawByteCountNotOnlyEntryIndex() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mra-package-progress-\(UUID().uuidString)", isDirectory: true)
        let session = root.appendingPathComponent("session", isDirectory: true)
        let output = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let raw = session.appendingPathComponent("restore.log")
        let payload = Data(repeating: 0x31, count: 2 * 1024 * 1024)
        try payload.write(to: raw)
        let rawSHA = try Integrity.sha256(ofFileAt: raw)
        let id = UUID()
        let record = SessionRecord(
            sessionID: id,
            captureState: .savedPartial,
            captureHealth: .healthy,
            startedAtUTC: nil,
            endedAtUTC: nil,
            captureProfile: "test",
            captureCommand: [],
            captureBackend: "simulated",
            eventCount: 0,
            coverageStatus: .unverified,
            archiveStatus: .notRequested,
            integrityStatus: .verified,
            files: [EvidenceFile(role: "raw-log", relativePath: "restore.log",
                                 byteSize: payload.count, sha256: rawSHA)],
            missingEvidence: [],
            errorReason: nil)
        let source = SessionPackageSource(record: record, directory: session)
        var byteEvents: [Int64] = []
        _ = try SessionZipExporter.export(
            SessionZipExportRequest(
                source: source,
                destination: output.appendingPathComponent("evidence.zip"),
                appVersion: "1.0.4",
                appCDHash: "TEST"),
            options: .rawOnly,
            detailedProgress: { update in
                if update.stage == .packagingZIP {
                    byteEvents.append(update.processedBytes)
                }
            })
        XCTAssertGreaterThan(byteEvents.count, 1)
        XCTAssertEqual(byteEvents, byteEvents.sorted())
        XCTAssertGreaterThan(byteEvents.last ?? 0, Int64(payload.count))
    }

    func testOptionalTimelineAndSummaryComeFromThePackagedRaw() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mra-package-attachments-\(UUID().uuidString)", isDirectory: true)
        let session = root.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let raw = session.appendingPathComponent("restore.log")
        let text = """
        2026-11-13 10:00:00.000 I DeviceService ACURestoreFirmwareCommand
        2026-11-13 10:00:01.000 I AMPDevices checkpoint id: 123
        2026-11-13 10:00:02.000 I DeviceService restore complete
        """
        try Data(text.utf8).write(to: raw)
        let rawSHA = try Integrity.sha256(ofFileAt: raw)
        let record = SessionRecord(
            sessionID: UUID(),
            captureState: .savedPartial,
            captureHealth: .healthy,
            startedAtUTC: nil,
            endedAtUTC: nil,
            captureProfile: "test",
            captureCommand: [],
            captureBackend: "simulated",
            eventCount: 3,
            coverageStatus: .partial,
            archiveStatus: .notRequested,
            integrityStatus: .verified,
            files: [EvidenceFile(role: "raw-log", relativePath: "restore.log",
                                 byteSize: text.utf8.count, sha256: rawSHA)],
            missingEvidence: [],
            errorReason: nil)
        let destination = root.appendingPathComponent("attachments.zip")
        _ = try SessionZipExporter.export(
            SessionZipExportRequest(
                source: SessionPackageSource(record: record, directory: session),
                destination: destination,
                appVersion: "1.0.4",
                appCDHash: "TEST"),
            options: .allSourceBound)
        var stats = ZipIOStats()
        let entries = try ZipStoreReader.listEntries(
            archive: destination, stats: &stats, hashContents: true)
        let names = Set(entries.map(\.pathInZip))
        XCTAssertTrue(names.contains("evidence/timeline.json"))
        XCTAssertTrue(names.contains("evidence/diagnostic_summary.md"))
        let timeline = try JSONSerialization.jsonObject(
            with: unzipBytes(destination, "evidence/timeline.json")) as? [String: Any]
        XCTAssertEqual(timeline?["source_raw_sha256"] as? String, rawSHA)
    }

    private func unzipBytes(_ zip: URL, _ path: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", zip.path, path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return output.fileHandleForReading.readDataToEndOfFile()
    }
}

@MainActor
final class CaptureLogWorkflowTests: XCTestCase {
    private func waitUntil(_ timeout: TimeInterval = 12, _ predicate: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func testRawLogExportAndEvidencePackageRemainIndependentOperations() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mra-log-workflow-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let rawOut = root.appendingPathComponent("raw", isDirectory: true)
        let packageOut = root.appendingPathComponent("package", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rawOut, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packageOut, withIntermediateDirectories: true)
        let suite = "mra-log-workflow-defaults-\(UUID().uuidString)"
        let preferences = LogWorkspacePreferences(
            defaults: UserDefaults(suiteName: suite)!,
            startingRoot: root)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        preferences.rawLogDirectory = rawOut.path
        preferences.evidencePackageDirectory = packageOut.path

        let capture = CaptureModel(root: sessions, backendMode: .simulated, preferences: preferences)
        capture.exportBaseName = "Bench"
        capture.appVersionOverride = "1.0.4"
        capture.appCDHashProvider = { "TESTCDHASH" }
        let threadResults = ThreadResultBox()
        capture.exportThreadProbe = { operation, isMainThread in
            threadResults.append(operation: operation, isMainThread: isMainThread)
        }
        capture.start()
        await waitUntil { capture.state == .recording }
        capture.stop()
        await waitUntil { capture.canSave }
        XCTAssertTrue(capture.canSave)

        capture.saveRawLog()
        await waitUntil { capture.lastRawExportURL != nil || capture.exportProgress?.stage == .failed }
        let raw = try XCTUnwrap(capture.lastRawExportURL, capture.saveMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path))
        let rawSize = (try FileManager.default.attributesOfItem(atPath: raw.path)[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(rawSize, 0)
        XCTAssertNil(capture.lastEvidencePackageURL)
        let packageFilesBefore = try FileManager.default.contentsOfDirectory(atPath: packageOut.path)
        XCTAssertTrue(packageFilesBefore.isEmpty, "saving raw must not generate an evidence package")

        capture.includeTimeline = false
        capture.includeDiagnosticSummary = false
        capture.includeUpdaterOutput = false
        capture.exportEvidencePackage(directory: packageOut, baseName: "Bench")
        await waitUntil { capture.lastEvidencePackageURL != nil || capture.exportProgress?.stage == .failed }
        let package = try XCTUnwrap(capture.lastEvidencePackageURL, capture.saveMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path))
        let recorded = threadResults.values
        XCTAssertEqual(Set(recorded.map(\.0)), Set([.rawLog, .evidencePackage]))
        XCTAssertFalse(recorded.contains { $0.1 }, "disk export must not run on the main thread")
    }

    func testSecondExportIsRejectedWhileAnExportIsAlreadyRunning() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mra-export-guard-\(UUID().uuidString)", isDirectory: true)
        let capture = CaptureModel(root: root, backendMode: .simulated)
        capture.isExporting = true
        XCTAssertFalse(capture.canStartRawExport)
        XCTAssertFalse(capture.canExportEvidencePackage)
        capture.saveRawLog(directory: root, baseName: "duplicate")
        capture.exportEvidencePackage(directory: root, baseName: "duplicate")
        XCTAssertNil(capture.exportProgress)
        XCTAssertFalse(capture.isRawExporting)
        XCTAssertFalse(capture.isPackageExporting)
    }

    func testHistoricalLogImportIsReadOnlyAndProducesAnalysis() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mra-import-workflow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let raw = root.appendingPathComponent("history.log")
        let text = """
        2026-11-13 10:00:00.000 I DeviceService ACURestoreFirmwareCommand
        2026-11-13 10:00:01.000 E AMRestoreErrorDomain -1 restore failed
        """
        try Data(text.utf8).write(to: raw)
        let before = try Integrity.sha256(ofFileAt: raw)
        let capture = CaptureModel(
            root: root.appendingPathComponent("sessions", isDirectory: true),
            backendMode: .simulated,
            preferences: LogWorkspacePreferences(
                defaults: UserDefaults(suiteName: "mra-import-\(UUID().uuidString)")!,
                startingRoot: root))
        capture.importHistoricalLog(url: raw)
        await waitUntil { capture.importState == .completed || capture.importState == .failed }
        XCTAssertEqual(capture.importState, .completed, capture.importStatus)
        XCTAssertNotNil(capture.importedAnalysis)
        XCTAssertEqual(try Integrity.sha256(ofFileAt: raw), before)
    }

    func testAutoMonitorToggleStartsAndStopsWithoutSavingEvidence() {
        let capture = CaptureModel(
            root: FileManager.default.temporaryDirectory.appendingPathComponent(
                "mra-auto-monitor-\(UUID().uuidString)", isDirectory: true),
            backendMode: .simulated,
            preferences: LogWorkspacePreferences(
                defaults: UserDefaults(suiteName: "mra-auto-monitor-\(UUID().uuidString)")!,
                startingRoot: FileManager.default.temporaryDirectory))
        var starts = 0
        capture.restoreMonitorStartProbe = { starts += 1 }
        capture.setAutoMonitorEnabled(true)
        XCTAssertEqual(starts, 1)
        XCTAssertTrue(capture.workspacePreferences.autoMonitorEnabled)
        XCTAssertTrue(capture.isListening)
        XCTAssertNil(capture.savedZipURL)
        XCTAssertNil(capture.savedLogURL)
        capture.setAutoMonitorEnabled(false)
        XCTAssertFalse(capture.workspacePreferences.autoMonitorEnabled)
        XCTAssertFalse(capture.isListening)
    }
}

private final class ThreadResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [(LogExportOperation, Bool)] = []

    func append(operation: LogExportOperation, isMainThread: Bool) {
        lock.lock()
        stored.append((operation, isMainThread))
        lock.unlock()
    }

    var values: [(LogExportOperation, Bool)] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

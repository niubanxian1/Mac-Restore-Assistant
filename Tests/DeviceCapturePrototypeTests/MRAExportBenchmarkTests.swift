import XCTest
@testable import DeviceCapturePrototype
import RestoreLogEngine

final class MRAExportBenchmarkTests: XCTestCase {
    func testBenchmarkLargeExportIfRequested() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["MRA_RUN_EXPORT_BENCHMARK"] == "1",
              let sourcePath = env["MRA_BENCHMARK_SOURCE"] else {
            throw XCTSkip("set MRA_RUN_EXPORT_BENCHMARK=1 and MRA_BENCHMARK_SOURCE")
        }
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let variant = env["MRA_BENCHMARK_VARIANT"] ?? "all"
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mra-benchmark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceBytes = try Integrity.byteSize(ofFileAt: sourceURL)
        let sourceSHA = try Integrity.sha256(ofFileAt: sourceURL)
        let sessionID = UUID()
        let rawEvidence = EvidenceFile(
            role: "raw-log",
            relativePath: "restore.log",
            byteSize: sourceBytes,
            sha256: sourceSHA)
        let record = SessionRecord(
            sessionID: sessionID,
            captureState: .savedPartial,
            captureHealth: .healthy,
            startedAtUTC: nil,
            endedAtUTC: nil,
            captureProfile: "benchmark",
            captureCommand: [],
            captureBackend: "benchmark",
            eventCount: 0,
            coverageStatus: .unverified,
            archiveStatus: .notRequested,
            integrityStatus: .verified,
            files: [rawEvidence],
            missingEvidence: [],
            errorReason: nil)
        let sessionDirectory = root.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let linkedRaw = sessionDirectory.appendingPathComponent("restore.log")
        do {
            try FileManager.default.linkItem(at: sourceURL, to: linkedRaw)
        } catch {
            try FileManager.default.copyItem(at: sourceURL, to: linkedRaw)
        }
        let packageSource = SessionPackageSource(record: record, directory: sessionDirectory)

        let newRawDirectory = root.appendingPathComponent("new-raw", isDirectory: true)
        try FileManager.default.createDirectory(at: newRawDirectory, withIntermediateDirectories: true)
        let newRaw = variant == "all" || variant == "new-raw"
            ? try measureRawNew(sourceURL, sourceSHA, sessionID, newRawDirectory)
            : nil

        let oldRawDirectory = root.appendingPathComponent("old-raw", isDirectory: true)
        try FileManager.default.createDirectory(at: oldRawDirectory, withIntermediateDirectories: true)
        let oldRaw = variant == "all" || variant == "old-raw"
            ? try await measureRawOld(sourceURL, sourceSHA, sessionID, oldRawDirectory)
            : nil

        let newZIP = root.appendingPathComponent("new-evidence.zip")
        let newPackage = variant == "all" || variant == "new-zip"
            ? try measurePackageNew(source: packageSource, destination: newZIP)
            : nil

        let oldPackageRoot = root.appendingPathComponent("old-package", isDirectory: true)
        try FileManager.default.createDirectory(at: oldPackageRoot, withIntermediateDirectories: true)
        let oldPackage = variant == "all" || variant == "old-zip"
            ? try measurePackageOld(
                source: packageSource,
                destination: oldPackageRoot.appendingPathComponent("evidence.zip"))
            : nil

        var result: [String: Any] = [
            "source_bytes": sourceBytes,
            "source_sha256": sourceSHA,
            "variant": variant
        ]
        if let newRaw {
            result["new_raw_seconds"] = newRaw.seconds
            result["new_raw_mib_per_second"] = newRaw.mibPerSecond
            result["new_raw_stages"] = newRaw.stages
        }
        if let oldRaw {
            result["old_raw_seconds"] = oldRaw
            result["old_raw_mib_per_second"] = Double(sourceBytes) / 1_048_576.0 / oldRaw
        }
        if let newPackage {
            result["new_zip_seconds"] = newPackage.seconds
            result["new_zip_mib_per_second"] = newPackage.mibPerSecond
            result["new_zip_stages"] = newPackage.stages
        }
        if let oldPackage {
            result["old_zip_seconds"] = oldPackage
            result["old_zip_mib_per_second"] = Double(sourceBytes) / 1_048_576.0 / oldPackage
        }
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.prettyPrinted, .sortedKeys])
        let output = String(decoding: data, as: UTF8.self)
        print("MRA_BENCHMARK_JSON_BEGIN")
        print(output)
        print("MRA_BENCHMARK_JSON_END")
        if let resultPath = env["MRA_BENCHMARK_RESULT_PATH"], !resultPath.isEmpty {
            try data.write(to: URL(fileURLWithPath: resultPath), options: .atomic)
        }
    }

    private func measureRawNew(
        _ source: URL,
        _ sha: String,
        _ sessionID: UUID,
        _ directory: URL
    ) throws -> (seconds: Double, mibPerSecond: Double, stages: [String]) {
        let lock = NSLock()
        var stages: [String] = []
        let started = Date()
        _ = try RawLogExporter.export(
            RawLogExportRequest(
                sourceURL: source,
                destinationDirectory: directory,
                baseName: "benchmark-new",
                sessionID: sessionID,
                isPartial: true,
                expectedSourceSHA256: sha),
            progress: { update in
                lock.lock()
                if stages.last != update.stage.rawValue {
                    stages.append(update.stage.rawValue)
                }
                lock.unlock()
            })
        let seconds = Date().timeIntervalSince(started)
        lock.lock()
        defer { lock.unlock() }
        return (
            seconds,
            Double(try Integrity.byteSize(ofFileAt: source)) / 1_048_576.0 / seconds,
            stages)
    }

    private func measureRawOld(
        _ source: URL,
        _ sha: String,
        _ sessionID: UUID,
        _ directory: URL
    ) async throws -> Double {
        let started = Date()
        _ = try await LogExporter().export(
            ExportRequest(
                sourceURL: source,
                destinationDirectory: directory,
                baseName: "benchmark-old",
                sessionID: sessionID,
                isPartial: true,
                expectedSourceSHA256: sha))
        return Date().timeIntervalSince(started)
    }

    private func measurePackageNew(
        source: SessionPackageSource,
        destination: URL
    ) throws -> (seconds: Double, mibPerSecond: Double, stages: [String]) {
        let lock = NSLock()
        var stages: [String] = []
        let started = Date()
        _ = try SessionZipExporter.export(
            SessionZipExportRequest(
                source: source,
                destination: destination,
                appVersion: "1.0.4-benchmark",
                appCDHash: "BENCHMARK"),
            options: .rawOnly,
            detailedProgress: { update in
                lock.lock()
                if stages.last != update.stage.rawValue {
                    stages.append(update.stage.rawValue)
                }
                lock.unlock()
            })
        let seconds = Date().timeIntervalSince(started)
        lock.lock()
        defer { lock.unlock() }
        return (
            seconds,
            Double(try Integrity.byteSize(ofFileAt: source.rawURL)) / 1_048_576.0 / seconds,
            stages)
    }

    private func measurePackageOld(
        source: SessionPackageSource,
        destination: URL
    ) throws -> Double {
        let started = Date()
        _ = try RawEvidencePackageBuilder.build(
            source: source,
            destination: destination,
            archiveRootName: "benchmark-old",
            options: RawEvidencePackageOptions(
                includeTimeline: false,
                includeSummary: false,
                includeUpdaterOutput: false))
        return Date().timeIntervalSince(started)
    }
}

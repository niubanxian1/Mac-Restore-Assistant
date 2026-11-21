import Foundation
import XCTest
@testable import DeviceCapturePrototype

final class Batch3RestoreHistoryStoreTests: XCTestCase {
    private let wallOrigin = Date(timeIntervalSince1970: 1_800_000_000)

    func testCreateAndReloadAcrossStoreRestart() async throws {
        let url = temporaryHistoryURL()
        let store = RestoreHistoryStore(fileURL: url)
        let record = makeRecord(taskID: UUID(), outcome: .success, durationSeconds: 10)

        try await store.upsert(record)
        let reloaded = RestoreHistoryStore(fileURL: url)
        let reloadedRecords = try await reloaded.records()

        XCTAssertEqual(reloadedRecords, [record])
    }

    func testSchemaOneHistoryRemainsReadableAndMigratesOnNextWrite() async throws {
        let url = temporaryHistoryURL()
        let store = RestoreHistoryStore(fileURL: url)
        let record = makeRecord(
            taskID: UUID(),
            outcome: .success,
            durationSeconds: 10)
        try await store.upsert(record)
        var text = try String(contentsOf: url, encoding: .utf8)
        text = text.replacingOccurrences(
            of: #""schemaVersion" : 2"#,
            with: #""schemaVersion" : 1"#)
        try Data(text.utf8).write(to: url, options: .atomic)

        let migrated = RestoreHistoryStore(fileURL: url)
        let migratedRecords = try await migrated.records()
        XCTAssertEqual(migratedRecords, [record])
        try await migrated.upsert(record)
        let rewritten = try String(
            contentsOf: url,
            encoding: .utf8)
        XCTAssertTrue(rewritten.contains(#""schemaVersion" : 2"#))
    }

    func testSameTaskIsIdempotentAndUpdatesWithoutDuplicateRows() async throws {
        let store = RestoreHistoryStore(fileURL: temporaryHistoryURL())
        let taskID = UUID()
        let first = makeRecord(taskID: taskID, outcome: .unknown, durationSeconds: 8)
        var second = first
        second.outcome = .success
        second.lifecycle.outcomeConfirmed = point(ns: 12_000)
        second.verificationComplete = true

        try await store.upsert(first)
        try await store.upsert(second)
        let rows = try await store.records()

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.outcome, .success)
        XCTAssertTrue(rows.first?.verificationComplete == true)
    }

    func testConcurrentDistinctTaskWritesAreSerialized() async throws {
        let store = RestoreHistoryStore(fileURL: temporaryHistoryURL())
        let records = (0..<20).map {
            makeRecord(
                taskID: UUID(),
                outcome: $0.isMultiple(of: 2) ? .success : .failure,
                durationSeconds: Double($0 + 1))
        }

        await withTaskGroup(of: Void.self) { group in
            for record in records {
                group.addTask {
                    try? await store.upsert(record)
                }
            }
        }

        let stored = try await store.records()
        XCTAssertEqual(stored.count, records.count)
    }

    func testUnknownSchemaIsNeverOverwritten() async throws {
        let url = temporaryHistoryURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let original = Data(#"{"schemaVersion":99,"records":[]}"#.utf8)
        try original.write(to: url)
        let store = RestoreHistoryStore(fileURL: url)

        do {
            _ = try await store.records()
            XCTFail("Expected unsupported schema")
        } catch RestoreHistoryStoreError.unsupportedSchema(99) {
            // Expected.
        }

        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testCorruptHistoryIsUnavailableWithoutBecomingWritable() async throws {
        let url = temporaryHistoryURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let corrupt = Data("{not-json".utf8)
        try corrupt.write(to: url)
        let store = RestoreHistoryStore(fileURL: url)

        do {
            _ = try await store.records()
            XCTFail("Expected corrupt history error")
        } catch RestoreHistoryStoreError.corrupt {
            // Expected.
        }

        do {
            try await store.upsert(makeRecord(
                taskID: UUID(),
                outcome: .success,
                durationSeconds: 2))
            XCTFail("Corrupt history must not be overwritten")
        } catch RestoreHistoryStoreError.unavailable {
            // Expected.
        }
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testStatisticsKeepAllFourOutcomeCounts() async throws {
        let store = RestoreHistoryStore(fileURL: temporaryHistoryURL())
        try await store.upsert(makeRecord(taskID: UUID(), outcome: .success, durationSeconds: 10))
        try await store.upsert(makeRecord(taskID: UUID(), outcome: .failure, durationSeconds: 20))
        try await store.upsert(makeRecord(taskID: UUID(), outcome: .canceled, durationSeconds: nil))
        try await store.upsert(makeRecord(taskID: UUID(), outcome: .unknown, durationSeconds: nil))

        let stats = try await store.statistics(
            modelFamilyKey: ModelFamilyKey(rawValue: "Mac14,2"),
            productBuild: "23A344")

        XCTAssertEqual(stats.totalRestoreCount, 4)
        XCTAssertEqual(stats.successCount, 1)
        XCTAssertEqual(stats.failureCount, 1)
        XCTAssertEqual(stats.canceledCount, 1)
        XCTAssertEqual(stats.unknownCount, 1)
    }

    func testAverageAndMedianUseOnlyCompleteTrustedSuccesses() async throws {
        let store = RestoreHistoryStore(fileURL: temporaryHistoryURL())
        for duration in [10.0, 20.0, 100.0] {
            try await store.upsert(makeRecord(
                taskID: UUID(),
                outcome: .success,
                durationSeconds: duration))
        }
        var untrusted = makeRecord(taskID: UUID(), outcome: .success, durationSeconds: 1_000)
        untrusted.recordSource = .bootstrapCandidate1702
        untrusted.verificationComplete = false
        try await store.upsert(untrusted)
        try await store.upsert(makeRecord(taskID: UUID(), outcome: .canceled, durationSeconds: nil))

        let stats = try await store.statistics(
            modelFamilyKey: ModelFamilyKey(rawValue: "Mac14,2"),
            productBuild: "23A344")

        XCTAssertEqual(stats.trustedRuntimeSampleCount, 3)
        XCTAssertEqual(stats.averageDurationSeconds ?? -1, 130.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(stats.medianDurationSeconds, 20)
    }

    func testPrelaunchCancelDoesNotEnterRuntimeStatistics() async throws {
        let store = RestoreHistoryStore(fileURL: temporaryHistoryURL())
        var canceled = makeRecord(
            taskID: UUID(),
            outcome: .canceled,
            durationSeconds: nil)
        canceled.lifecycle.processLaunched = nil
        canceled.lifecycle.processExited = nil
        canceled.lifecycle.bothStreamsEOF = nil
        try await store.upsert(canceled)
        let stats = try await store.statistics(
            modelFamilyKey: ModelFamilyKey(rawValue: "Mac14,2"),
            productBuild: "23A344")
        XCTAssertEqual(stats.trustedRuntimeSampleCount, 0)
        XCTAssertNil(stats.averageDurationSeconds)
        XCTAssertNil(stats.medianDurationSeconds)
    }

    func testSerializedHistoryContainsNoRawLogBody() async throws {
        let url = temporaryHistoryURL()
        let store = RestoreHistoryStore(fileURL: url)
        var record = makeRecord(taskID: UUID(), outcome: .failure, durationSeconds: 5)
        record.failureSummary = "cfgutil: error: fixture only"
        try await store.upsert(record)
        let text = try String(contentsOf: url, encoding: .utf8)

        XCTAssertFalse(text.contains("stdout.raw"))
        XCTAssertFalse(text.contains("stderr.raw"))
        XCTAssertFalse(text.contains("Restored System on"))
        XCTAssertLessThan(text.utf8.count, 16_384)
    }

    func testRLMFinalizationCanUpdateExistingAttemptWithoutRawBody() async throws {
        let store = RestoreHistoryStore(fileURL: temporaryHistoryURL())
        let record = makeRecord(taskID: UUID(), outcome: .success, durationSeconds: 10)
        try await store.upsert(record)

        try await store.updateRLMFinalization(
            attemptID: record.attemptID,
            finalizedAt: point(ns: 30_000),
            drainDurationSeconds: 2.5)

        let rows = try await store.records()
        let updated = try XCTUnwrap(rows.first)
        XCTAssertEqual(updated.lifecycle.rlmFinalized?.monotonicNanoseconds, 30_000)
        XCTAssertEqual(updated.rlmDrainDurationSeconds ?? -1, 2.5, accuracy: 0.000_001)
    }

    func testHistoryUsageProviderReturnsOnlyNativeVerifiedSuccesses() async throws {
        let store = RestoreHistoryStore(fileURL: temporaryHistoryURL())
        let verified = makeRecord(taskID: UUID(), outcome: .success, durationSeconds: 10)
        var bootstrap = makeRecord(taskID: UUID(), outcome: .success, durationSeconds: 20)
        bootstrap.recordSource = .bootstrapCandidate1702
        bootstrap.verificationComplete = false
        try await store.upsert(verified)
        try await store.upsert(bootstrap)

        let usages = try await store.firmwareUsageRecords()

        XCTAssertEqual(usages.count, 1)
        XCTAssertEqual(usages.first?.candidateID, verified.firmwareLibraryEntryID)
        XCTAssertEqual(usages.first?.source, .nativeV1703Verified)
        XCTAssertTrue(usages.first?.verificationComplete == true)
    }

    private func makeRecord(
        taskID: UUID,
        outcome: RestoreOutcome,
        durationSeconds: Double?
    ) -> RestoreHistoryRecord {
        let launchNanoseconds: UInt64 = 1_000_000_000
        let launched = durationSeconds.map {
            point(ns: launchNanoseconds, wallDelta: Double($0))
        }
        let exited = durationSeconds.map {
            point(ns: launchNanoseconds + UInt64($0 * 1_000_000_000))
        }
        let lifecycle = RestoreLifecycleTimes(
            userConfirmed: point(ns: 500),
            processLaunched: launched,
            firstRestoreActivity: launched,
            processExited: exited,
            bothStreamsEOF: exited,
            outcomeConfirmed: exited,
            rlmFinalized: nil)
        return RestoreHistoryRecord(
            taskID: taskID,
            attemptID: taskID,
            operationType: .restore,
            deviceDisplayName: "Synthetic Mac",
            modelFamilyKey: ModelFamilyKey(rawValue: "Mac14,2"),
            hardwareBindingKey: HardwareBindingKey(
                productType: "Mac14,2",
                deviceClass: "j413ap",
                boardID: 0x24,
                chipID: 0x8132),
            stablePortKey: "synthetic-host|port-A",
            firmwareLibraryEntryID: UUID(),
            firmwareFileName: "Synthetic.ipsw",
            ipswIdentity: nil,
            productVersion: "14.0",
            productBuild: "23A344",
            lifecycle: lifecycle,
            outcome: outcome,
            errorClassification: outcome == .failure ? .explicitFailure : .none,
            exitCode: outcome == .success ? 0 : nil,
            terminationReason: .unknown,
            cancellationRequested: outcome == .canceled,
            sentSignals: [],
            rawPersistencePolicy: RestoreRawPersistencePolicy(
                autoSaveDefault: false,
                saveThisRun: false,
                destinationDirectory: "/tmp/logs",
                autoMonitorEnabled: false,
                spaceWarningThresholdBytes: nil,
                retentionPolicy: "manual"),
            rawEvidenceStatus: .pendingBatch4,
            rlmStatus: .notRequested,
            rlmOwnership: .notRequested,
            rlmFinalizedAt: nil,
            rlmDrainDurationSeconds: nil,
            recordSource: .nativeV1703Verified,
            verificationComplete: outcome == .success && durationSeconds != nil)
    }

    private func point(
        ns: UInt64,
        wallDelta: TimeInterval = 0
    ) -> RestoreLifecycleTimePoint {
        RestoreLifecycleTimePoint(
            wallTime: wallOrigin.addingTimeInterval(wallDelta),
            monotonicNanoseconds: ns)
    }

    private func temporaryHistoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Batch3History-\(UUID().uuidString)",
                isDirectory: true)
            .appendingPathComponent("history-v1.json")
    }
}

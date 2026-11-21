import Foundation
import XCTest
@testable import DeviceCapturePrototype

final class Batch4RetentionCleanupTests: XCTestCase {
    func testTwoBaselinesPerModelWithLocksAndOldEvidencePreservedOnFailure() {
        let model = try! XCTUnwrap(
            ModelFamilyKey(rawValue: "Mac14,2"))
        let first = baseline("1", model: model, locked: false, day: 1)
        let second = baseline("2", model: model, locked: false, day: 2)
        let third = baseline("3", model: model, locked: false, day: 3)

        let decision = RestoreSuccessBaselinePolicy.decide(
            candidateID: third.id,
            modelFamilyKey: model,
            existing: [first, second],
            candidateEligible: true)

        XCTAssertEqual(decision.removeIDs, [first.id])
        XCTAssertEqual(decision.retainIDs, [second.id, third.id])

        let lockedFirst = baseline("1", model: model, locked: true, day: 1)
        let lockedSecond = baseline("2", model: model, locked: true, day: 2)
        let noReplacement = RestoreSuccessBaselinePolicy.decide(
            candidateID: third.id,
            modelFamilyKey: model,
            existing: [lockedFirst, lockedSecond],
            candidateEligible: true)
        XCTAssertTrue(noReplacement.removeIDs.isEmpty)
        XCTAssertEqual(noReplacement.retainIDs.count, 2)
    }

    func testManualArchiveLockPersistsAndOccupiesBaselineSlot() async throws {
        let root = try temporaryDirectory()
        let store = RestoreLogRetentionStore(
            fileURL: root.appendingPathComponent("retention.json"))
        let model = try XCTUnwrap(
            ModelFamilyKey(rawValue: "Mac14,2"))
        let taskID = UUID()
        let candidate = RestoreArchiveCandidate(
            taskID: taskID,
            attemptID: taskID,
            targetDisplayName: "Synthetic Mac",
            modelFamilyKey: model,
            modelYear: "2022",
            productVersion: "14.0",
            productBuild: "23A344",
            outcome: .success,
            liveConfirmed: true,
            tailComplete: true,
            rawWriteComplete: true,
            summaryComplete: true,
            manuallyLocked: false,
            linkedTaskIDs: [taskID],
            linkedRLMSessionID: "SESSION-1",
            generatedAt: Date())
        let record = RestoreArchiveRecord(
            archiveID: "archive-locked",
            taskID: taskID,
            attemptID: taskID,
            directoryPath: root.appendingPathComponent(
                "archive-locked").path,
            manifestPath: root.appendingPathComponent(
                "archive-locked/manifest.json").path,
            manifestSHA256: String(repeating: "a", count: 64),
            outcome: .success,
            modelFamilyKey: model.rawValue,
            publishedAt: Date(),
            directorySyncLevel: .full,
            localStagingRetained: false,
            baselineEligible: true)

        try await store.registerArchive(record, candidate: candidate)
        try await store.setArchiveLocked(
            archiveID: record.archiveID,
            locked: true)

        let restarted = RestoreLogRetentionStore(
            fileURL: root.appendingPathComponent("retention.json"))
        let locked = try await restarted.manuallyLockedArchiveIDs()
        let baselines = try await restarted.baselines()
        XCTAssertEqual(locked, [record.archiveID])
        XCTAssertEqual(baselines.count, 1)
        XCTAssertTrue(baselines[0].manuallyLocked)
    }

    func testSessionProtectionUsesWholeSessionAndUnknownIsProtected() {
        let failed = RestoreRLMSessionProtection(
            sessionID: "SESSION-FAIL",
            ownership: .restoreOwned,
            linkedTaskIDs: [UUID(), UUID()],
            linkedTaskOutcomes: [.success, .failure],
            manuallyLocked: false,
            hasExportedBundle: false,
            recording: false,
            finalizing: false,
            historyComplete: true)
        XCTAssertEqual(
            RestoreRLMSessionProtectionPolicy.evaluate(failed).status,
            .protected)

        let unknown = RestoreRLMSessionProtection(
            sessionID: "SESSION-UNKNOWN",
            ownership: .unavailable,
            linkedTaskIDs: [],
            linkedTaskOutcomes: [],
            manuallyLocked: false,
            hasExportedBundle: false,
            recording: false,
            finalizing: false,
            historyComplete: false)
        let result = RestoreRLMSessionProtectionPolicy.evaluate(unknown)
        XCTAssertEqual(result.status, .protectedUnknown)
        XCTAssertEqual(result.reason, "PROTECTED_UNKNOWN")
    }

    func testOwnedDrainSessionRemainsActiveUntilItsOwnerFinalizes() async throws {
        let root = try temporaryDirectory()
        let sessionID = "SESSION-DRAIN"
        let ownerTaskID = UUID()
        let store = RestoreLogRetentionStore(
            fileURL: root.appendingPathComponent("retention.json"))
        try await store.registerSessionProtection(
            RestoreRLMSessionProtection(
                sessionID: sessionID,
                ownership: .restoreOwned,
                linkedTaskIDs: [ownerTaskID],
                linkedTaskOutcomes: [.success],
                manuallyLocked: false,
                hasExportedBundle: false,
                recording: true,
                finalizing: true,
                historyComplete: false,
                lifecycleOwnerTaskID: ownerTaskID))

        let active = try await store.sessions().first
        let evaluation = try XCTUnwrap(active)
        XCTAssertEqual(
            RestoreRLMSessionProtectionPolicy.evaluate(evaluation).reason,
            "RECORDING")
        let roots = try makeEmptyStorageRoots(root: root)
        let sessionDirectory = roots.rlmSessions
            .appendingPathComponent(
                sessionID,
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionDirectory,
            withIntermediateDirectories: true)
        let sessionLog = sessionDirectory
            .appendingPathComponent("raw.log")
        try Data("rlm".utf8).write(to: sessionLog)
        let storage = try await RestoreLogStorageCatalog(
            retentionStore: store)
            .preview(roots: roots, retentionDays: 30)
        let activeStorage = try XCTUnwrap(
            storage.items.first {
                $0.url.standardizedFileURL.path
                    == sessionLog.standardizedFileURL.path
            })
        XCTAssertTrue(activeStorage.protected)
        XCTAssertEqual(
            activeStorage.category,
            .activeFinalizing)

        try await store.resolveOwnedSessionFinalization(
            sessionID: sessionID,
            taskID: UUID(),
            finalized: true)
        let sessionsAfterWrongOwner = try await store.sessions()
        let wrongOwner = try XCTUnwrap(
            sessionsAfterWrongOwner.first)
        XCTAssertEqual(
            RestoreRLMSessionProtectionPolicy.evaluate(wrongOwner).reason,
            "RECORDING")

        try await store.resolveOwnedSessionFinalization(
            sessionID: sessionID,
            taskID: ownerTaskID,
            finalized: false)
        let sessionsAfterTimeout = try await store.sessions()
        let timedOut = try XCTUnwrap(
            sessionsAfterTimeout.first)
        XCTAssertEqual(
            RestoreRLMSessionProtectionPolicy.evaluate(timedOut).status,
            .protected)

        try await store.resolveOwnedSessionFinalization(
            sessionID: sessionID,
            taskID: ownerTaskID,
            finalized: true)
        let sessionsAfterFinalization =
            try await store.sessions()
        let finalized = try XCTUnwrap(
            sessionsAfterFinalization.first)
        XCTAssertEqual(
            RestoreRLMSessionProtectionPolicy.evaluate(finalized).status,
            .eligible)
    }

    func testExportRegistrationPersistsDigestAndSurvivesRestart() async throws {
        let root = try temporaryDirectory()
        let zip = root.appendingPathComponent("evidence.zip")
        try Data("zip fixture".utf8).write(to: zip)
        let registryURL = root.appendingPathComponent("retention.json")
        let registry = RestoreLogRetentionStore(fileURL: registryURL)
        let taskID = UUID()

        let record = try await registry.registerExport(
            exportURL: zip,
            linkedSessionID: "SESSION-1",
            linkedTaskIDs: [taskID])
        XCTAssertEqual(record.zipSHA256.count, 64)
        XCTAssertEqual(record.linkedTaskIDs, [taskID])

        let restarted = RestoreLogRetentionStore(fileURL: registryURL)
        let records = try await restarted.exports()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].exportID, record.exportID)
        XCTAssertEqual(records[0].zipSHA256, record.zipSHA256)
        XCTAssertEqual(records[0].linkedSessionID, "SESSION-1")
        XCTAssertEqual(records[0].linkedTaskIDs, [taskID])
        XCTAssertTrue(records[0].protected)
    }

    func testUnknownRetentionSchemaIsNeverOverwritten() async throws {
        let root = try temporaryDirectory()
        let registryURL = root.appendingPathComponent("retention.json")
        let original = Data(
            #"{"schemaVersion":99,"archives":[],"baselines":[],"exports":[],"sessions":[]}"#.utf8)
        try original.write(to: registryURL)
        let registry = RestoreLogRetentionStore(fileURL: registryURL)

        do {
            _ = try await registry.exports()
            XCTFail("Expected unsupported schema")
        } catch RestoreLogRetentionError.unsupportedSchema(99) {
            // Expected.
        }
        XCTAssertEqual(
            try Data(contentsOf: registryURL),
            original)
    }

    func testRetentionWriteFailureRollsBackTheWholeDocument() async throws {
        let root = try temporaryDirectory()
        let registryURL = root.appendingPathComponent("retention.json")
        let backupURL = root.appendingPathComponent("retention.backup.json")
        let store = RestoreLogRetentionStore(fileURL: registryURL)
        let model = try XCTUnwrap(
            ModelFamilyKey(rawValue: "Mac14,2"))
        let first = archiveRecord(
            id: "a1",
            model: model,
            day: 1)
        let second = archiveRecord(
            id: "a2",
            model: model,
            day: 2)
        let third = archiveRecord(
            id: "a3",
            model: model,
            day: 3)
        try await store.registerArchive(
            first,
            candidate: eligibleCandidate(
                for: first,
                model: model))
        try await store.registerArchive(
            second,
            candidate: eligibleCandidate(
                for: second,
                model: model))

        try FileManager.default.moveItem(
            at: registryURL,
            to: backupURL)
        try FileManager.default.createDirectory(
            at: registryURL,
            withIntermediateDirectories: false)
        do {
            try await store.registerArchive(
                third,
                candidate: eligibleCandidate(
                    for: third,
                    model: model))
            XCTFail("The invalid index path must fail the write")
        } catch {
            // Expected.
        }
        let afterFailure = try await store.baselines()
        XCTAssertEqual(
            Set(afterFailure.map(\.archiveID)),
            [first.archiveID, second.archiveID])

        try FileManager.default.removeItem(at: registryURL)
        try FileManager.default.moveItem(
            at: backupURL,
            to: registryURL)
        try await store.setArchiveLocked(
            archiveID: second.archiveID,
            locked: true)

        let restarted = RestoreLogRetentionStore(
            fileURL: registryURL)
        let persisted = try await restarted.baselines()
        XCTAssertFalse(persisted.contains {
            $0.archiveID == third.archiveID
        })
        XCTAssertTrue(persisted.contains {
            $0.archiveID == second.archiveID
                && $0.manuallyLocked
        })
    }

    func testFailedExportRegistrationUsesPendingFailClosedMarker() async throws {
        let root = try temporaryDirectory()
        let zip = root.appendingPathComponent("evidence.zip")
        try Data("zip fixture".utf8).write(to: zip)
        let registryURL = root.appendingPathComponent("retention.json")
        let taskID = UUID()
        let failingStore = RestoreLogRetentionStore(
            fileURL: registryURL)
        try FileManager.default.createDirectory(
            at: registryURL,
            withIntermediateDirectories: false)

        do {
            _ = try await failingStore.registerExportWithFallback(
                exportURL: zip,
                linkedSessionID: "SESSION-EXPORT",
                linkedTaskIDs: [taskID])
            XCTFail("Expected protected registration to fail")
        } catch {
            // Expected. The fallback marker must remain on disk.
        }
        let pendingAfterFailure =
            try await failingStore.pendingExportCount()
        XCTAssertEqual(pendingAfterFailure, 1)

        try FileManager.default.removeItem(at: registryURL)
        let recoveryStore = RestoreLogRetentionStore(
            fileURL: registryURL)
        let roots = try makeEmptyStorageRoots(root: root)
        let blocked = try await RestoreLogStorageCatalog(
            retentionStore: recoveryStore)
            .preview(roots: roots, retentionDays: 30)
        XCTAssertFalse(blocked.scanComplete)
        XCTAssertTrue(blocked.issues.contains {
            $0.contains("pending retry")
        })

        let recovered = try await recoveryStore
            .recoverPendingExports()
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(
            recovered[0].linkedSessionID,
            "SESSION-EXPORT")
        let pendingAfterRecovery =
            try await recoveryStore.pendingExportCount()
        XCTAssertEqual(pendingAfterRecovery, 0)
        let persisted = try await RestoreLogRetentionStore(
            fileURL: registryURL)
            .exports()
        XCTAssertEqual(persisted.count, 1)
    }

    func testDualExportProtectionFailureLatchesCleanupClosedInMemory() async throws {
        let root = try temporaryDirectory()
        let zip = root.appendingPathComponent("evidence.zip")
        try Data("zip fixture".utf8).write(to: zip)
        let blockedParent =
            root.appendingPathComponent("blocked-parent")
        try Data("not a directory".utf8).write(
            to: blockedParent)
        let registryURL = blockedParent
            .appendingPathComponent("retention.json")
        let store = RestoreLogRetentionStore(
            fileURL: registryURL)

        do {
            _ = try await store.registerExportWithFallback(
                exportURL: zip,
                linkedSessionID: "SESSION-EXPORT",
                linkedTaskIDs: [UUID()])
            XCTFail("Both registration and fallback must fail")
        } catch RestoreLogRetentionError
            .pendingExportProtectionNotPersisted {
            // Expected.
        }

        let failClosed =
            await store.exportProtectionIsFailClosed()
        XCTAssertTrue(failClosed)
        let pendingCount =
            try await store.pendingExportCount()
        XCTAssertEqual(pendingCount, 0)

        let roots = try makeEmptyStorageRoots(root: root)
        let preview = try await RestoreLogStorageCatalog(
            retentionStore: store)
            .preview(roots: roots, retentionDays: 30)
        XCTAssertFalse(preview.scanComplete)
        XCTAssertEqual(preview.candidateCount, 0)
        XCTAssertTrue(preview.issues.contains {
            $0.contains("failed closed in this process")
        })
    }

    func testStorageCatalogProtectsEvidenceHistoryStagingAndUnknownRLMBundles() async throws {
        let root = try temporaryDirectory()
        let raw = root.appendingPathComponent("raw", isDirectory: true)
        let staging = root.appendingPathComponent(
            "staging",
            isDirectory: true)
        let rlm = root.appendingPathComponent("rlm", isDirectory: true)
        let evidence = root.appendingPathComponent(
            "evidence",
            isDirectory: true)
        let history = root.appendingPathComponent(
            "history",
            isDirectory: true)
        for directory in [raw, staging, rlm, evidence, history] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true)
        }
        let activeAttemptID = UUID()
        let activeStaging = staging.appendingPathComponent(
            activeAttemptID.uuidString,
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: activeStaging,
            withIntermediateDirectories: false)
        try Data("raw".utf8).write(
            to: raw.appendingPathComponent("unknown.raw"))
        try Data("stage".utf8).write(
            to: activeStaging.appendingPathComponent("stdout.raw"))
        let session = rlm.appendingPathComponent(
            "SESSION-UNKNOWN",
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: session,
            withIntermediateDirectories: true)
        try Data("rlm".utf8).write(
            to: session.appendingPathComponent("raw.log"))
        try Data("zip".utf8).write(
            to: evidence.appendingPathComponent("evidence.zip"))
        try Data("history".utf8).write(
            to: history.appendingPathComponent("history.json"))
        let store = RestoreLogRetentionStore(
            fileURL: root.appendingPathComponent("retention.json"))

        let preview = try await RestoreLogStorageCatalog(
            retentionStore: store)
            .preview(
                roots: RestoreManagedStorageRoots(
                    rawArchives: raw,
                    localStaging: staging,
                    rlmSessions: rlm,
                    evidencePackages: evidence,
                    history: history),
                retentionDays: 30,
                activeAttemptIDs: [activeAttemptID])

        XCTAssertEqual(preview.candidateCount, 0)
        XCTAssertTrue(preview.items.contains {
            $0.category == .activeFinalizing
        })
        XCTAssertTrue(preview.items.contains {
            $0.category == .manualLockedOrExported
                && $0.reason == "USER_EVIDENCE_PACKAGE"
        })
        XCTAssertTrue(preview.items.contains {
            $0.category == .manualLockedOrExported
                && $0.reason == "PROTECTED_UNKNOWN"
        })
        XCTAssertTrue(preview.items.contains {
            $0.category == .taskSummaryHistory
        })
        XCTAssertTrue(preview.items.contains {
            $0.category == .unownedFailureOrUnknown
                && $0.reason == "PROTECTED_UNKNOWN"
        })
    }

    func testInactiveStagingGetsAConfirmedCleanupLifecycle() async throws {
        let root = try temporaryDirectory()
        let raw = root.appendingPathComponent("raw", isDirectory: true)
        let staging = root.appendingPathComponent(
            "staging",
            isDirectory: true)
        let rlm = root.appendingPathComponent("rlm", isDirectory: true)
        let evidence = root.appendingPathComponent(
            "evidence",
            isDirectory: true)
        let history = root.appendingPathComponent(
            "history",
            isDirectory: true)
        for directory in [raw, staging, rlm, evidence, history] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true)
        }
        let attemptID = UUID()
        let attempt = staging.appendingPathComponent(
            attemptID.uuidString,
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: attempt,
            withIntermediateDirectories: false)
        let rawFile = attempt.appendingPathComponent("stdout.raw")
        try Data("partial".utf8).write(to: rawFile)
        try FileManager.default.setAttributes(
            [
                .modificationDate:
                    Date(timeIntervalSinceNow: -31 * 86_400)
            ],
            ofItemAtPath: rawFile.path)
        let roots = RestoreManagedStorageRoots(
            rawArchives: raw,
            localStaging: staging,
            rlmSessions: rlm,
            evidencePackages: evidence,
            history: history)
        let store = RestoreLogRetentionStore(
            fileURL: root.appendingPathComponent("retention.json"))

        let inactive = try await RestoreLogStorageCatalog(
            retentionStore: store)
            .preview(
                roots: roots,
                retentionDays: 30,
                activeAttemptIDs: [])
        let inactiveItem = try XCTUnwrap(
            inactive.items.first {
                $0.url.standardizedFileURL.path
                    == rawFile.standardizedFileURL.path
            })
        XCTAssertFalse(inactiveItem.protected)
        XCTAssertEqual(
            inactiveItem.category,
            .cleanupEligibleRLMOrTemporary)

        let active = try await RestoreLogStorageCatalog(
            retentionStore: store)
            .preview(
                roots: roots,
                retentionDays: 30,
                activeAttemptIDs: [attemptID])
        let activeItem = try XCTUnwrap(
            active.items.first {
                $0.url.standardizedFileURL.path
                    == rawFile.standardizedFileURL.path
            })
        XCTAssertTrue(activeItem.protected)
        XCTAssertEqual(activeItem.category, .activeFinalizing)
    }

    func testUnsafeManagedRootMakesTheScanIncomplete() async throws {
        let root = try temporaryDirectory()
        let notDirectory =
            root.appendingPathComponent("not-a-directory")
        try Data("fixture".utf8).write(to: notDirectory)
        let empty = root.appendingPathComponent(
            "empty",
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: empty,
            withIntermediateDirectories: false)
        let store = RestoreLogRetentionStore(
            fileURL: root.appendingPathComponent("retention.json"))

        let preview = try await RestoreLogStorageCatalog(
            retentionStore: store)
            .preview(
                roots: RestoreManagedStorageRoots(
                    rawArchives: notDirectory,
                    localStaging: empty,
                    rlmSessions: empty,
                    evidencePackages: empty,
                    history: empty),
                retentionDays: 30)

        XCTAssertFalse(preview.scanComplete)
        XCTAssertEqual(preview.candidateCount, 0)
        XCTAssertTrue(preview.issues.contains {
            $0.contains("not a safe directory")
        })
    }

    func testCleanupRequiresConfirmationAndSkipsTOCTOUChange() async throws {
        let root = try temporaryDirectory()
        let managed = root.appendingPathComponent("Managed", isDirectory: true)
        try FileManager.default.createDirectory(
            at: managed,
            withIntermediateDirectories: true)
        let first = managed.appendingPathComponent("first.raw")
        let second = managed.appendingPathComponent("second.raw")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let scanner = RestoreLogStorageScanner()
        let descriptors = [
            RestoreManagedLogFile(
                url: first,
                category: .ordinaryRaw,
                protected: false,
                reason: ""),
            RestoreManagedLogFile(
                url: second,
                category: .ordinaryRaw,
                protected: false,
                reason: "")
        ]
        let preview = try scanner.preview(
            managedRoots: [managed],
            files: descriptors)
        XCTAssertEqual(preview.candidateCount, 2)

        let noConfirmation = try await RestoreLogCleanupService().execute(
            preview: preview,
            confirmed: false,
            protectionAtDeleteTime: { _ in false })
        XCTAssertEqual(noConfirmation.deletedCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))

        try FileManager.default.removeItem(at: second)
        try Data("replacement".utf8).write(to: second)

        let result = try await RestoreLogCleanupService().execute(
            preview: preview,
            confirmed: true,
            protectionAtDeleteTime: { _ in false })

        XCTAssertEqual(result.deletedCount, 1)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testCleanupRechecksIdentityAfterProtectionCallback() async throws {
        let root = try temporaryDirectory()
        let managed = root.appendingPathComponent(
            "Managed",
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: managed,
            withIntermediateDirectories: true)
        let file = managed.appendingPathComponent("replace-during-check.raw")
        try Data("original".utf8).write(to: file)
        let preview = try RestoreLogStorageScanner().preview(
            managedRoots: [managed],
            files: [RestoreManagedLogFile(
                url: file,
                category: .ordinaryRaw,
                protected: false,
                reason: "")])

        let result = try await RestoreLogCleanupService().execute(
            preview: preview,
            confirmed: true,
            protectionAtDeleteTime: { url in
                try? FileManager.default.removeItem(at: url)
                try? Data("replacement".utf8).write(to: url)
                return false
            })

        XCTAssertEqual(result.deletedCount, 0)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(
            try String(contentsOf: file, encoding: .utf8),
            "replacement")
    }

    func testCleanupRejectsSymlinkAndRootEscape() throws {
        let root = try temporaryDirectory()
        let managed = root.appendingPathComponent("Managed", isDirectory: true)
        let outside = root.appendingPathComponent("outside.raw")
        try FileManager.default.createDirectory(
            at: managed,
            withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: outside)
        let link = managed.appendingPathComponent("link.raw")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: outside)
        let scanner = RestoreLogStorageScanner()

        XCTAssertThrowsError(try scanner.preview(
            managedRoots: [managed],
            files: [RestoreManagedLogFile(
                url: link,
                category: .ordinaryRaw,
                protected: false,
                reason: "")]))
        XCTAssertThrowsError(try scanner.preview(
            managedRoots: [managed],
            files: [RestoreManagedLogFile(
                url: outside,
                category: .ordinaryRaw,
                protected: false,
                reason: "")]))

        let realParent = root.appendingPathComponent(
            "real-parent",
            isDirectory: true)
        let realLogs = realParent.appendingPathComponent(
            "logs",
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: realLogs,
            withIntermediateDirectories: true)
        let nested = realLogs.appendingPathComponent("nested.raw")
        try Data("nested".utf8).write(to: nested)
        let linkedParent = root.appendingPathComponent("linked-parent")
        try FileManager.default.createSymbolicLink(
            at: linkedParent,
            withDestinationURL: realParent)
        let escapingDirectory = managed
            .appendingPathComponent("outside-link")
        try FileManager.default.createSymbolicLink(
            at: escapingDirectory,
            withDestinationURL: realLogs)
        XCTAssertThrowsError(try scanner.preview(
            managedRoots: [managed],
            files: [RestoreManagedLogFile(
                url: escapingDirectory
                    .appendingPathComponent("nested.raw"),
                category: .ordinaryRaw,
                protected: false,
                reason: "")]))
        let aliasedRoot = linkedParent
            .appendingPathComponent("logs", isDirectory: true)
        let aliasedFile = aliasedRoot
            .appendingPathComponent("nested.raw")
        let aliasedPreview = try scanner.preview(
            managedRoots: [aliasedRoot],
            files: [RestoreManagedLogFile(
                url: aliasedFile,
                category: .ordinaryRaw,
                protected: false,
                reason: "")])
        XCTAssertEqual(aliasedPreview.items.count, 1)
    }

    func testSameInodeUsesHighestProtectionPriorityAcrossCategories() throws {
        let root = try temporaryDirectory()
        let directory = root.appendingPathComponent("Managed", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("shared.raw")
        try Data("shared".utf8).write(to: file)
        let hardLink = directory.appendingPathComponent("shared-link.raw")
        try FileManager.default.linkItem(at: file, to: hardLink)

        let preview = try RestoreLogStorageScanner().preview(
            managedRoots: [directory],
            files: [
                RestoreManagedLogFile(
                    url: file,
                    category: .ordinaryRaw,
                    protected: false,
                    reason: ""),
                RestoreManagedLogFile(
                    url: hardLink,
                    category: .trustedSuccessBaseline,
                    protected: true,
                    reason: "BASELINE")
            ])

        XCTAssertEqual(preview.items.count, 1)
        XCTAssertEqual(preview.items[0].category, .trustedSuccessBaseline)
        XCTAssertTrue(preview.items[0].protected)
        XCTAssertEqual(preview.candidateCount, 0)
    }

    private func makeEmptyStorageRoots(
        root: URL
    ) throws -> RestoreManagedStorageRoots {
        let raw = root.appendingPathComponent(
            "empty-raw",
            isDirectory: true)
        let staging = root.appendingPathComponent(
            "empty-staging",
            isDirectory: true)
        let rlm = root.appendingPathComponent(
            "empty-rlm",
            isDirectory: true)
        let evidence = root.appendingPathComponent(
            "empty-evidence",
            isDirectory: true)
        let history = root.appendingPathComponent(
            "empty-history",
            isDirectory: true)
        for directory in [raw, staging, rlm, evidence, history] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true)
        }
        return RestoreManagedStorageRoots(
            rawArchives: raw,
            localStaging: staging,
            rlmSessions: rlm,
            evidencePackages: evidence,
            history: history)
    }

    private func archiveRecord(
        id: String,
        model: ModelFamilyKey,
        day: Int
    ) -> RestoreArchiveRecord {
        let taskID = UUID()
        return RestoreArchiveRecord(
            archiveID: id,
            taskID: taskID,
            attemptID: taskID,
            directoryPath: "/tmp/\(id)",
            manifestPath: "/tmp/\(id)/manifest.json",
            manifestSHA256: String(repeating: "a", count: 64),
            outcome: .success,
            modelFamilyKey: model.rawValue,
            publishedAt: Date(
                timeIntervalSince1970:
                    Double(day) * 86_400),
            directorySyncLevel: .full,
            localStagingRetained: false,
            baselineEligible: true)
    }

    private func eligibleCandidate(
        for record: RestoreArchiveRecord,
        model: ModelFamilyKey
    ) -> RestoreArchiveCandidate {
        RestoreArchiveCandidate(
            taskID: record.taskID,
            attemptID: record.attemptID,
            targetDisplayName: "Synthetic Mac",
            modelFamilyKey: model,
            modelYear: "2022",
            productVersion: "14.0",
            productBuild: "23A344",
            outcome: .success,
            liveConfirmed: true,
            tailComplete: true,
            rawWriteComplete: true,
            summaryComplete: true,
            manuallyLocked: false,
            linkedTaskIDs: [record.taskID],
            linkedRLMSessionID: "SESSION-1",
            generatedAt: record.publishedAt)
    }

    private func baseline(
        _ suffix: String,
        model: ModelFamilyKey,
        locked: Bool,
        day: Int
    ) -> RestoreSuccessBaseline {
        RestoreSuccessBaseline(
            id: "baseline-\(suffix)",
            archiveID: "archive-\(suffix)",
            modelFamilyKey: model,
            createdAt: Date(timeIntervalSince1970: Double(day) * 86_400),
            manuallyLocked: locked)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Batch4Cleanup-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

import Foundation
import XCTest
@testable import DeviceCapturePrototype

final class Batch4ArchiveTests: XCTestCase {
    func testSafePublisherCopiesVerifiesAndPublishesWithoutOverwriting() async throws {
        let fixture = try makeFixture()
        let manager = RestoreLogRetentionManager(
            localStagingRoot: fixture.stagingRoot,
            retentionManifestURL: fixture.retentionURL,
            directorySynchronizer: .simulated(.full))
        let candidate = candidate(outcome: .success)

        let publication = try await manager.publish(
            stagingDirectory: fixture.staging,
            destinationRoot: fixture.destination,
            candidate: candidate)

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: publication.finalDirectory.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: publication.manifestURL.path))
        XCTAssertEqual(publication.directorySyncLevel, .full)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: publication.incompleteDirectory.path))

        let manifest = try JSONDecoder().decode(
            RestoreArchiveManifest.self,
            from: Data(contentsOf: publication.manifestURL))
        XCTAssertEqual(manifest.taskID, candidate.taskID)
        XCTAssertEqual(manifest.files.map(\.relativePath).sorted(), [
            "stderr.raw",
            "stdout.raw",
            "task-summary.json"
        ])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.staging.path))

        try FileManager.default.createDirectory(
            at: fixture.staging,
            withIntermediateDirectories: true)
        try Data("stdout fixture\n".utf8).write(
            to: fixture.staging.appendingPathComponent("stdout.raw"))
        try Data("stderr fixture\n".utf8).write(
            to: fixture.staging.appendingPathComponent("stderr.raw"))
        let second = try await manager.publish(
            stagingDirectory: fixture.staging,
            destinationRoot: fixture.destination,
            candidate: candidate)
        XCTAssertNotEqual(
            second.finalDirectory,
            publication.finalDirectory)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: publication.finalDirectory.path))
    }

    func testUnsupportedDirectorySyncPublishesAndRetainsCompleteLocalStaging() async throws {
        let fixture = try makeFixture()
        let manager = RestoreLogRetentionManager(
            localStagingRoot: fixture.stagingRoot,
            retentionManifestURL: fixture.retentionURL,
            directorySynchronizer: .simulated(
                .unsupported(errno: ENOTSUP)))

        let publication = try await manager.publish(
            stagingDirectory: fixture.staging,
            destinationRoot: fixture.destination,
            candidate: candidate(outcome: .failure))

        XCTAssertEqual(
            publication.directorySyncLevel,
            .unsupported(errno: ENOTSUP))
        XCTAssertTrue(publication.localStagingRetained)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.staging
                    .appendingPathComponent("stdout.raw").path))
    }

    func testFailedDirectorySyncNeverClaimsFullDurabilityAndRetainsStaging() async throws {
        let fixture = try makeFixture()
        let manager = RestoreLogRetentionManager(
            localStagingRoot: fixture.stagingRoot,
            retentionManifestURL: fixture.retentionURL,
            directorySynchronizer: .simulated(
                .failed(errno: EIO)))

        let publication = try await manager.publish(
            stagingDirectory: fixture.staging,
            destinationRoot: fixture.destination,
            candidate: candidate(outcome: .success))

        XCTAssertEqual(
            publication.directorySyncLevel,
            .failed(errno: EIO))
        XCTAssertFalse(publication.directorySyncLevel.isDurable)
        XCTAssertTrue(publication.localStagingRetained)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.staging
                    .appendingPathComponent("stderr.raw").path))
    }

    func testMissingRequiredRawFileFailsBeforePublishing() async throws {
        let fixture = try makeFixture()
        try FileManager.default.removeItem(
            at: fixture.staging.appendingPathComponent("stdout.raw"))
        let manager = RestoreLogRetentionManager(
            localStagingRoot: fixture.stagingRoot,
            retentionManifestURL: fixture.retentionURL,
            directorySynchronizer: .simulated(.full))

        do {
            _ = try await manager.publish(
                stagingDirectory: fixture.staging,
                destinationRoot: fixture.destination,
                candidate: candidate(outcome: .success))
            XCTFail("Missing raw file must not publish")
        } catch RestoreLogRetentionError.missingRequiredFile(
            let name) {
            XCTAssertEqual(name, "stdout.raw")
        }
        let destinationEntries =
            try FileManager.default.contentsOfDirectory(
                at: fixture.destination,
                includingPropertiesForKeys: nil,
                options: [])
        XCTAssertTrue(destinationEntries.isEmpty)
    }

    func testPublishedArchiveWithoutIndexIsRecoveredAndIncompleteIsIgnored() async throws {
        let fixture = try makeFixture()
        let manager = RestoreLogRetentionManager(
            localStagingRoot: fixture.stagingRoot,
            retentionManifestURL: fixture.retentionURL,
            directorySynchronizer: .simulated(.standard))
        let publication = try await manager.publish(
            stagingDirectory: fixture.staging,
            destinationRoot: fixture.destination,
            candidate: candidate(outcome: .success))
        try FileManager.default.removeItem(at: fixture.retentionURL)

        let incomplete = fixture.destination
            .appendingPathComponent(
                ".incomplete-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: incomplete,
            withIntermediateDirectories: true)
        try Data("unknown but harmless".utf8).write(
            to: fixture.destination
                .appendingPathComponent("zzz-unknown.txt"))
        let unsafeArchive = fixture.destination
            .appendingPathComponent(
                "zzzz-unsafe",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: unsafeArchive,
            withIntermediateDirectories: false)
        let outsideManifest = fixture.destination
            .deletingLastPathComponent()
            .appendingPathComponent("outside-manifest.json")
        try Data("{}".utf8).write(to: outsideManifest)
        try FileManager.default.createSymbolicLink(
            at: unsafeArchive.appendingPathComponent(
                "manifest.json"),
            withDestinationURL: outsideManifest)

        let restarted = RestoreLogRetentionManager(
            localStagingRoot: fixture.stagingRoot,
            retentionManifestURL: fixture.retentionURL,
            directorySynchronizer: .simulated(.full))
        let recovered = try await restarted.recoverPublishedArchives(
            destinationRoot: fixture.destination)

        XCTAssertEqual(recovered.map(\.archiveID), [publication.archiveID])
        XCTAssertFalse(recovered.contains {
            URL(fileURLWithPath: $0.directoryPath)
                .lastPathComponent
                .hasPrefix(".incomplete-")
        })
        let restoredBaselines =
            try await RestoreLogRetentionStore(
                fileURL: fixture.retentionURL)
                .baselines()
        XCTAssertTrue(restoredBaselines.contains {
            $0.archiveID == publication.archiveID
        })
    }

    func testArchiveNameIsNFCBoundedSafeAndKeepsTailIdentity() {
        let name = RestoreLogArchiveNaming.directoryName(
            candidate: RestoreArchiveCandidate(
                taskID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                attemptID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                targetDisplayName: String(repeating: "非常长的机型/名称 ", count: 40),
                modelFamilyKey: ModelFamilyKey(rawValue: "Mac14,2/unsafe"),
                modelYear: "2022/危险",
                productVersion: "14.0?",
                productBuild: "23A344/unsafe",
                outcome: .success,
                liveConfirmed: true,
                tailComplete: true,
                rawWriteComplete: true,
                summaryComplete: true,
                manuallyLocked: false,
                linkedTaskIDs: [],
                linkedRLMSessionID: nil,
                generatedAt: Date(timeIntervalSince1970: 1_800_000_000)))

        XCTAssertLessThanOrEqual(name.utf8.count, 180)
        XCTAssertFalse(name.contains("/"))
        XCTAssertTrue(name.hasSuffix("SUCCESS_AAAAAAAA"))
        XCTAssertEqual(name, name.precomposedStringWithCanonicalMapping)
    }

    func testTaskSummaryIsRegeneratedForTheCurrentCandidate() async throws {
        let fixture = try makeFixture()
        let manager = RestoreLogRetentionManager(
            localStagingRoot: fixture.stagingRoot,
            retentionManifestURL: fixture.retentionURL,
            directorySynchronizer: .simulated(.full))
        let candidate = candidate(outcome: .success)
        try Data(
            #"{"taskID":"stale","rawWriteComplete":true}"#.utf8)
            .write(
                to: fixture.staging
                    .appendingPathComponent("task-summary.json"))

        let publication = try await manager.publish(
            stagingDirectory: fixture.staging,
            destinationRoot: fixture.destination,
            candidate: candidate)
        let summaryURL = publication.finalDirectory
            .appendingPathComponent("task-summary.json")
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: summaryURL))
                as? [String: Any])

        XCTAssertEqual(
            object["taskID"] as? String,
            candidate.taskID.uuidString)
        XCTAssertEqual(
            object["rawWriteComplete"] as? Bool,
            candidate.rawWriteComplete)
    }

    func testIndexFailureKeepsCompleteLocalStaging() async throws {
        let fixture = try makeFixture()
        try FileManager.default.createDirectory(
            at: fixture.retentionURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: fixture.retentionURL,
            withIntermediateDirectories: false)
        let manager = RestoreLogRetentionManager(
            localStagingRoot: fixture.stagingRoot,
            retentionManifestURL: fixture.retentionURL,
            directorySynchronizer: .simulated(.full))

        do {
            _ = try await manager.publish(
                stagingDirectory: fixture.staging,
                destinationRoot: fixture.destination,
                candidate: candidate(outcome: .success))
            XCTFail("An unusable retention index must report failure")
        } catch {
            // Expected: the published archive remains recoverable, while the
            // complete local staging must also remain available.
        }

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.staging
                    .appendingPathComponent("stdout.raw").path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.staging
                    .appendingPathComponent("stderr.raw").path))
    }

    func testRecoveredFailureCannotBecomeTrustedBaseline() async throws {
        let fixture = try makeFixture()
        let manager = RestoreLogRetentionManager(
            localStagingRoot: fixture.stagingRoot,
            retentionManifestURL: fixture.retentionURL,
            directorySynchronizer: .simulated(.full))
        let publication = try await manager.publish(
            stagingDirectory: fixture.staging,
            destinationRoot: fixture.destination,
            candidate: candidate(outcome: .failure))
        try FileManager.default.removeItem(at: fixture.retentionURL)

        let recovered = try await RestoreLogRetentionManager(
            localStagingRoot: fixture.stagingRoot,
            retentionManifestURL: fixture.retentionURL,
            directorySynchronizer: .simulated(.full))
            .recoverPublishedArchives(
                destinationRoot: fixture.destination)

        let record = try XCTUnwrap(
            recovered.first {
                $0.archiveID == publication.archiveID
            })
        XCTAssertEqual(record.outcome, .failure)
        XCTAssertFalse(record.baselineEligible)
    }

    func testApplicationStartupWiresPublishedArchiveRecovery() throws {
        let sourceURL = URL(
            fileURLWithPath:
                FileManager.default.currentDirectoryPath)
            .appendingPathComponent(
                "Sources/DeviceCapturePrototype/App.swift")
        let source = try String(
            contentsOf: sourceURL,
            encoding: .utf8)

        XCTAssertTrue(source.contains(
            "recoverPublishedArchives"))
        XCTAssertTrue(source.contains(
            "recoverPendingExports"))
        XCTAssertTrue(source.contains(
            "RestoreLogRetentionManager"))
    }

    func testEvidenceExportFailureUsesPersistentFallbackAndVisibleError() throws {
        let sourceURL = URL(
            fileURLWithPath:
                FileManager.default.currentDirectoryPath)
            .appendingPathComponent(
                "Sources/DeviceCapturePrototype/ContentView.swift")
        let source = try String(
            contentsOf: sourceURL,
            encoding: .utf8)

        XCTAssertTrue(source.contains(
            "registerExportWithFallback"))
        XCTAssertTrue(source.contains(
            "日志清理保持关闭"))
        XCTAssertFalse(source.contains(
            "try? await RestoreLogRetentionStore.shared"))
    }

    private func candidate(
        outcome: RestoreOutcome
    ) -> RestoreArchiveCandidate {
        RestoreArchiveCandidate(
            taskID: UUID(),
            attemptID: UUID(),
            targetDisplayName: "Synthetic Mac",
            modelFamilyKey: ModelFamilyKey(rawValue: "Mac14,2"),
            modelYear: "2022",
            productVersion: "14.0",
            productBuild: "23A344",
            outcome: outcome,
            liveConfirmed: true,
            tailComplete: true,
            rawWriteComplete: true,
            summaryComplete: true,
            manuallyLocked: false,
            linkedTaskIDs: [],
            linkedRLMSessionID: "SESSION-1",
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    private func makeFixture() throws -> (
        stagingRoot: URL,
        staging: URL,
        destination: URL,
        retentionURL: URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Batch4Archive-\(UUID().uuidString)",
                isDirectory: true)
        let stagingRoot = root.appendingPathComponent(
            "RestoreStaging",
            isDirectory: true)
        let staging = stagingRoot.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true)
        let destination = root.appendingPathComponent(
            "Published",
            isDirectory: true)
        let retention = root.appendingPathComponent(
            "RestoreHistory/retention-manifest-v1.json")
        try FileManager.default.createDirectory(
            at: staging,
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true)
        try Data("stdout fixture\n".utf8).write(
            to: staging.appendingPathComponent("stdout.raw"))
        try Data("stderr fixture\n".utf8).write(
            to: staging.appendingPathComponent("stderr.raw"))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return (stagingRoot, staging, destination, retention)
    }
}

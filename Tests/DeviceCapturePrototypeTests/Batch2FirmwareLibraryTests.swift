import Foundation
import XCTest
@testable import DeviceCapturePrototype

final class Batch2FirmwareLibraryTests: XCTestCase {
    func testIncompleteScanDoesNotPruneMissingEntry() async throws {
        let root = try temporaryDirectory()
        let ipsw = root.appendingPathComponent("deleted-incomplete.ipsw")
        try Data("x".utf8).write(to: ipsw)
        let indexPath = root.appendingPathComponent("library.json")
        let loader = FirmwareLibraryFixtureLoader(
            metadata: metadata(productVersion: "27.0", build: "26A428"))
        let first = FirmwareLibraryStore(indexURL: indexPath, metadataLoader: loader.load)
        _ = try await first.addDirectory(root)
        try FileManager.default.removeItem(at: ipsw)
        try Data("a".utf8).write(to: root.appendingPathComponent("a.txt"))
        try Data("b".utf8).write(to: root.appendingPathComponent("b.txt"))
        let bounded = FirmwareLibraryStore(
            indexURL: indexPath,
            metadataLoader: loader.load,
            discoveryLimits: FirmwareLibraryDiscoveryLimits(
                maximumDepth: 1,
                maximumVisitedEntries: 1,
                maximumIPSWs: 10))
        let result = try await bounded.refresh(pruneMissing: true)
        XCTAssertTrue(result.scanIncomplete)
        XCTAssertFalse(result.entries.isEmpty)
    }

    func testPruneMissingRemovesDeletedEntry() async throws {
        let root = try temporaryDirectory()
        let ipsw = root.appendingPathComponent("deleted.ipsw")
        try Data("deleted".utf8).write(to: ipsw)
        let store = FirmwareLibraryStore(
            indexURL: root.appendingPathComponent("library.json"),
            metadataLoader: FirmwareLibraryFixtureLoader(
                metadata: metadata(productVersion: "27.0", build: "26A428")).load)
        _ = try await store.addDirectory(root)
        try FileManager.default.removeItem(at: ipsw)
        let result = try await store.refresh(pruneMissing: true)
        XCTAssertTrue(result.entries.isEmpty)
    }

    func testDirectoryScanRecursivelyIndexesIPSWInNestedFolders() async throws {
        let root = try temporaryDirectory()
        let nested = root.appendingPathComponent("Firmware/Nested", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nested,
            withIntermediateDirectories: true)
        let rootIPSW = root.appendingPathComponent("Root.ipsw")
        let nestedIPSW = nested.appendingPathComponent("Nested.ipsw")
        try Data("root".utf8).write(to: rootIPSW)
        try Data("nested".utf8).write(to: nestedIPSW)
        try Data("not firmware".utf8).write(
            to: nested.appendingPathComponent("notes.txt"))

        let loader = FirmwareLibraryFixtureLoader(
            metadataByContent: [
                "root": metadata(productVersion: "14.0", build: "23A344"),
                "nested": metadata(productVersion: "14.1", build: "23B100")
            ])
        let store = FirmwareLibraryStore(
            indexURL: root.appendingPathComponent("library.json"),
            metadataLoader: loader.load)

        let result = try await store.addDirectory(root)

        XCTAssertEqual(result.indexedCount, 2)
        XCTAssertEqual(
            Set(result.entries.map { $0.url.standardizedFileURL }),
            Set([rootIPSW.standardizedFileURL, nestedIPSW.standardizedFileURL]))
        XCTAssertFalse(
            result.entries.contains {
                $0.url.lastPathComponent == "notes.txt"
            })
    }

    func testUnchangedStatReusesMetadataCacheAndMtimeChangeReparses() async throws {
        let root = try temporaryDirectory()
        let ipsw = root.appendingPathComponent("UniversalMac_27.0_Restore.ipsw")
        try Data("cached".utf8).write(to: ipsw)
        let loader = FirmwareLibraryFixtureLoader(
            metadata: metadata(productVersion: "27.0", build: "26A428"))
        let store = FirmwareLibraryStore(
            indexURL: root.appendingPathComponent("library.json"),
            metadataLoader: loader.load)

        _ = try await store.addDirectory(root)
        XCTAssertEqual(loader.loadCount, 1)

        _ = try await store.refresh()
        XCTAssertEqual(loader.loadCount, 1, "unchanged stat must reuse cache")

        try Data("cached2".utf8).write(to: ipsw)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(2)],
            ofItemAtPath: ipsw.path)
        _ = try await store.refresh()
        XCTAssertEqual(loader.loadCount, 2, "mtime change must reparse")
    }

    func testICloudPlaceholderIsReportedWithoutReadingTheFile() async throws {
        let root = try temporaryDirectory()
        let placeholder = root.appendingPathComponent(
            ".UniversalMac_27.0_Restore.ipsw.icloud")
        try Data("iCloud placeholder".utf8).write(to: placeholder)
        let loader = FirmwareLibraryFixtureLoader(metadataByContent: [:])
        let store = FirmwareLibraryStore(
            indexURL: root.appendingPathComponent("library.json"),
            metadataLoader: loader.load)

        let result = try await store.addDirectory(root)
        let entry = try XCTUnwrap(result.entries.first)

        XCTAssertEqual(result.discoveredCount, 1)
        XCTAssertEqual(result.indexedCount, 0)
        XCTAssertEqual(result.cloudNotDownloadedCount, 1)
        XCTAssertEqual(entry.url.standardizedFileURL, placeholder.standardizedFileURL)
        XCTAssertEqual(loader.loadCount, 0, "iCloud placeholder must not be opened")
        XCTAssertEqual(entry.state, .invalid)
        XCTAssertEqual(entry.accessState, .cloudNotDownloaded)
        XCTAssertEqual(entry.validity, .unverified)
    }

    func testAddDirectoryDepthLimitDoesNotMarkUnseenIPSWMissing() async throws {
        let root = try temporaryDirectory()
        let firstDirectory = root.appendingPathComponent("Level1", isDirectory: true)
        let secondDirectory = firstDirectory.appendingPathComponent(
            "Level2",
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: secondDirectory,
            withIntermediateDirectories: true)
        let deepIPSW = secondDirectory.appendingPathComponent("Deep.ipsw")
        let indexPath = root.appendingPathComponent("library.json")
        let loader = FirmwareLibraryFixtureLoader(
            metadata: metadata(productVersion: "27.0", build: "26A428"))
        try Data("deep".utf8).write(to: deepIPSW)

        let firstStore = FirmwareLibraryStore(
            indexURL: indexPath,
            metadataLoader: loader.load)
        let initial = try await firstStore.addDirectory(root)
        let entryID = try XCTUnwrap(initial.entries.first?.id)

        let boundedStore = FirmwareLibraryStore(
            indexURL: indexPath,
            metadataLoader: loader.load,
            discoveryLimits: FirmwareLibraryDiscoveryLimits(
                maximumDepth: 1,
                maximumVisitedEntries: 100,
                maximumIPSWs: 100))
        let result = try await boundedStore.addDirectory(root)
        let entry = try XCTUnwrap(result.entries.first { $0.id == entryID })

        XCTAssertTrue(result.scanLimitReached)
        XCTAssertTrue(result.scanIncomplete)
        XCTAssertEqual(result.discoveredCount, 0)
        XCTAssertEqual(entry.state, .available)
        XCTAssertEqual(entry.url.standardizedFileURL, deepIPSW.standardizedFileURL)
    }

    func testAddDirectoryEntryLimitDoesNotMarkUnseenIPSWMissing() async throws {
        let root = try temporaryDirectory()
        let first = root.appendingPathComponent("a-first.ipsw")
        let second = root.appendingPathComponent("z-second.ipsw")
        let indexPath = root.appendingPathComponent("library.json")
        let loader = FirmwareLibraryFixtureLoader(
            metadataByContent: [
                "first": metadata(productVersion: "27.0", build: "26A428"),
                "second": metadata(productVersion: "27.1", build: "26B100")
            ])
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let firstStore = FirmwareLibraryStore(
            indexURL: indexPath,
            metadataLoader: loader.load)
        let initial = try await firstStore.addDirectory(root)
        let secondID = try XCTUnwrap(
            initial.entries.first { $0.url == second }?.id)

        let boundedStore = FirmwareLibraryStore(
            indexURL: indexPath,
            metadataLoader: loader.load,
            discoveryLimits: FirmwareLibraryDiscoveryLimits(
                maximumDepth: 4,
                maximumVisitedEntries: 1,
                maximumIPSWs: 100))
        let result = try await boundedStore.addDirectory(root)
        let unseen = try XCTUnwrap(result.entries.first { $0.id == secondID })

        XCTAssertTrue(result.scanLimitReached)
        XCTAssertTrue(result.scanIncomplete)
        XCTAssertEqual(result.discoveredCount, 1)
        XCTAssertEqual(unseen.state, .available)
    }

    func testAddFileDoesNotMarkUnobservedNestedEntryMissing() async throws {
        let root = try temporaryDirectory()
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nested,
            withIntermediateDirectories: true)
        let selected = root.appendingPathComponent("selected.ipsw")
        let nestedIPSW = nested.appendingPathComponent("nested.ipsw")
        try Data("selected".utf8).write(to: selected)
        try Data("nested".utf8).write(to: nestedIPSW)
        let loader = FirmwareLibraryFixtureLoader(
            metadataByContent: [
                "selected": metadata(productVersion: "27.0", build: "26A428"),
                "nested": metadata(productVersion: "27.1", build: "26B100")
            ])
        let store = FirmwareLibraryStore(
            indexURL: root.appendingPathComponent("library.json"),
            metadataLoader: loader.load)

        let initial = try await store.addDirectory(root)
        let nestedID = try XCTUnwrap(
            initial.entries.first { $0.url == nestedIPSW }?.id)
        _ = try await store.addFile(selected)
        let entries = await store.allEntries()
        let nestedEntry = try XCTUnwrap(entries.first { $0.id == nestedID })

        XCTAssertEqual(nestedEntry.state, .available)
    }

    func testAddDirectoryUnreadableSubdirectoryDoesNotMarkKnownEntryMissing()
        async throws {
        let root = try temporaryDirectory()
        let locked = root.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(
            at: locked,
            withIntermediateDirectories: true)
        let visible = root.appendingPathComponent("visible.ipsw")
        let hidden = locked.appendingPathComponent("hidden.ipsw")
        let indexPath = root.appendingPathComponent("library.json")
        let loader = FirmwareLibraryFixtureLoader(
            metadataByContent: [
                "visible": metadata(productVersion: "27.0", build: "26A428"),
                "hidden": metadata(productVersion: "27.1", build: "26B100")
            ])
        try Data("visible".utf8).write(to: visible)
        try Data("hidden".utf8).write(to: hidden)

        let firstStore = FirmwareLibraryStore(
            indexURL: indexPath,
            metadataLoader: loader.load)
        let initial = try await firstStore.addDirectory(root)
        let hiddenID = try XCTUnwrap(
            initial.entries.first { $0.url == hidden }?.id)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0],
            ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: locked.path)
        }

        let secondStore = FirmwareLibraryStore(
            indexURL: indexPath,
            metadataLoader: loader.load)
        let result = try await secondStore.addDirectory(root)
        let hiddenEntry = try XCTUnwrap(
            result.entries.first { $0.id == hiddenID })

        XCTAssertGreaterThanOrEqual(result.unreadableDirectoryCount, 1)
        XCTAssertTrue(result.scanIncomplete)
        XCTAssertNotEqual(hiddenEntry.state, .missing)
        XCTAssertEqual(hiddenEntry.accessState, .unreadable)
    }

    func testDirectoryEntryPropertyFailureMakesScanIncomplete() async throws {
        let root = try temporaryDirectory()
        let valid = root.appendingPathComponent("valid.ipsw")
        let broken = root.appendingPathComponent("broken.ipsw")
        let indexPath = root.appendingPathComponent("library.json")
        let loader = FirmwareLibraryFixtureLoader(
            metadataByContent: [
                "valid": metadata(productVersion: "27.0", build: "26A428"),
                "broken": metadata(productVersion: "27.1", build: "26B100")
            ])
        try Data("valid".utf8).write(to: valid)
        try Data("broken".utf8).write(to: broken)

        let firstStore = FirmwareLibraryStore(
            indexURL: indexPath,
            metadataLoader: loader.load)
        _ = try await firstStore.addDirectory(root)
        let secondStore = FirmwareLibraryStore(
            indexURL: indexPath,
            metadataLoader: loader.load,
            directoryEntryPropertyReader: { url in
                if url.lastPathComponent == "broken.ipsw" {
                    throw CocoaError(.fileReadNoPermission)
                }
                return try inspectFirmwareDirectoryEntryProperties(url)
            })

        let result = try await secondStore.addDirectory(root)

        XCTAssertEqual(result.attributeReadFailureCount, 1)
        XCTAssertTrue(result.scanIncomplete)
    }

    func testVisitedEntryLimitStopsRecursiveScanAndReportsTruncation() async throws {
        let root = try temporaryDirectory()
        let deepDirectory = root.appendingPathComponent(
            "000-unrelated-deep",
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: deepDirectory,
            withIntermediateDirectories: true)
        try Data("deep".utf8).write(
            to: deepDirectory.appendingPathComponent("deep.txt"))
        let rootIPSW = root.appendingPathComponent("zzz-root.ipsw")
        try Data("root".utf8).write(to: rootIPSW)
        let loader = FirmwareLibraryFixtureLoader(
            metadata: metadata(productVersion: "27.0", build: "26A428"))
        let store = FirmwareLibraryStore(
            indexURL: root.appendingPathComponent("library.json"),
            metadataLoader: loader.load,
            discoveryLimits: FirmwareLibraryDiscoveryLimits(
                maximumDepth: 4,
                maximumVisitedEntries: 2,
                maximumIPSWs: 100))

        let result = try await store.addDirectory(root)

        XCTAssertEqual(result.visitedEntryCount, 2)
        XCTAssertEqual(result.discoveredCount, 1)
        XCTAssertEqual(
            result.entries.first?.url.standardizedFileURL,
            rootIPSW.standardizedFileURL)
        XCTAssertTrue(result.scanLimitReached)
        XCTAssertTrue(result.scanIncomplete)
    }

    func testMoveAndRenameRelocatesAfterStoreRestart() async throws {
        let root = try temporaryDirectory()
        let originalDirectory = root.appendingPathComponent(
            "Original",
            isDirectory: true)
        let destinationDirectory = root.appendingPathComponent(
            "Archive/Nested",
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: originalDirectory,
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true)
        let original = originalDirectory.appendingPathComponent("Firmware.ipsw")
        let renamed = destinationDirectory.appendingPathComponent(
            "UniversalMac_Renamed.ipsw")
        let indexPath = root.appendingPathComponent("library.json")
        let loader = FirmwareLibraryFixtureLoader(
            metadata: metadata(productVersion: "27.0", build: "26A428"))
        try Data("firmware".utf8).write(to: original)

        let firstStore = FirmwareLibraryStore(
            indexURL: indexPath,
            metadataLoader: loader.load)
        let initial = try await firstStore.addDirectory(root)
        let entryID = try XCTUnwrap(initial.entries.first?.id)
        try FileManager.default.moveItem(at: original, to: renamed)

        let restartedStore = FirmwareLibraryStore(
            indexURL: indexPath,
            metadataLoader: loader.load)
        _ = try await restartedStore.loadEntries()
        let result = try await restartedStore.refresh()
        let relocated = try XCTUnwrap(
            result.entries.first { $0.id == entryID })

        XCTAssertEqual(result.relocatedEntryIDs, [entryID])
        XCTAssertEqual(relocated.state, .available)
        XCTAssertEqual(relocated.url.standardizedFileURL, renamed.standardizedFileURL)
    }

    func testPreferenceReferenceRevalidationDetectsInPlaceContentChange() async throws {
        let root = try temporaryDirectory()
        let url = root.appendingPathComponent("preference.ipsw")
        try Data("original".utf8).write(to: url)
        let loader: (URL) throws -> IPSWMetadataReadResult = { url in
            let data = try Data(contentsOf: url)
            let content = String(decoding: data, as: UTF8.self)
            let manifest = IPSWMetadataReader.sha256Hex(
                Data("manifest:\(content)".utf8))
            let identity = try IPSWMetadataReader.fileIdentity(
                url: url,
                buildManifestSHA256: manifest)
            return IPSWMetadataReadResult(
                validity: .valid,
                metadata: self.metadata(
                    productVersion: "27.0",
                    build: "26A428"),
                error: nil,
                fileIdentity: identity,
                buildManifestSHA256: manifest,
                wholeFileSHA256: nil)
        }
        let store = FirmwareLibraryStore(
            indexURL: root.appendingPathComponent("library.json"),
            metadataLoader: loader)
        let entry = try await store.addFile(url)
        let reference = FirmwareReference(entry: entry)

        try Data("changed".utf8).write(to: url, options: .atomic)
        let resolution = await store.revalidateReference(reference)

        XCTAssertEqual(resolution.state, .modified)
        XCTAssertFalse(resolution.isUsable)
        XCTAssertTrue(resolution.message.contains("身份"))
    }

    func testDirectoryScanSeparatesValidInvalidUnreadableAndICloudFiles() async throws {
        let root = try temporaryDirectory()
        let valid = root.appendingPathComponent("valid.ipsw")
        let invalid = root.appendingPathComponent("invalid.ipsw")
        let unreadable = root.appendingPathComponent("unreadable.ipsw")
        let cloud = root.appendingPathComponent("cloud.ipsw")
        try Data("valid".utf8).write(to: valid)
        try Data("invalid".utf8).write(to: invalid)
        try Data("unreadable".utf8).write(to: unreadable)
        try Data("cloud".utf8).write(to: cloud)
        try Data("not firmware".utf8).write(
            to: root.appendingPathComponent("notes.txt"))

        let loader = FirmwareLibraryFixtureLoader(
            metadataByContent: [
                "valid": metadata(productVersion: "14.0", build: "23A344")
            ])
        let store = FirmwareLibraryStore(
            indexURL: root.appendingPathComponent("library.json"),
            metadataLoader: loader.load,
            fileAccessInspector: { url in
                switch url.lastPathComponent {
                case "unreadable.ipsw":
                    return .unreadable("Permission denied while opening IPSW.")
                case "cloud.ipsw":
                    return .cloudNotDownloaded(
                        "IPSW is an iCloud placeholder and is not downloaded.")
                default:
                    return .readable
                }
            },
            ignoreSystemTemporaryRoot: false)

        let result = try await store.addDirectory(root)

        XCTAssertEqual(result.discoveredCount, 4)
        XCTAssertEqual(result.indexedCount, 1)
        XCTAssertEqual(result.invalidCount, 1)
        XCTAssertEqual(result.unreadableCount, 1)
        XCTAssertEqual(result.cloudNotDownloadedCount, 1)
        XCTAssertEqual(
            try XCTUnwrap(result.entries.first { $0.url == valid }).state,
            .available)
        XCTAssertEqual(
            try XCTUnwrap(result.entries.first { $0.url == invalid }).state,
            .invalid)
        XCTAssertNil(
            try XCTUnwrap(result.entries.first { $0.url == invalid }).accessState)
        XCTAssertEqual(
            try XCTUnwrap(result.entries.first { $0.url == unreadable }).state,
            .invalid)
        XCTAssertEqual(
            try XCTUnwrap(result.entries.first { $0.url == unreadable }).accessState,
            .unreadable)
        XCTAssertEqual(
            try XCTUnwrap(result.entries.first { $0.url == cloud }).state,
            .invalid)
        XCTAssertEqual(
            try XCTUnwrap(result.entries.first { $0.url == cloud }).accessState,
            .cloudNotDownloaded)
    }

    func testLoadingLibraryMarksDisappearedFileMissing() async throws {
        let root = try temporaryDirectory()
        let ipsw = root.appendingPathComponent("disappeared.ipsw")
        try Data("firmware".utf8).write(to: ipsw)
        let index = root.appendingPathComponent("library.json")
        let loader = FirmwareLibraryFixtureLoader(
            metadata: metadata(productVersion: "14.0", build: "23A344"))
        let first = FirmwareLibraryStore(
            indexURL: index,
            metadataLoader: loader.load,
            ignoreSystemTemporaryRoot: false)
        _ = try await first.addDirectory(root)
        try FileManager.default.removeItem(at: ipsw)

        let second = FirmwareLibraryStore(
            indexURL: index,
            metadataLoader: loader.load,
            ignoreSystemTemporaryRoot: false)
        let entries = try await second.loadEntries()

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].state, .missing)
    }

    func testLoadingLibraryIgnoresLegacySystemTemporaryTestRoot() async throws {
        let root = try temporaryDirectory()
        let indexPath = root.appendingPathComponent("library.json")
        let temporaryRoot = FileManager.default.temporaryDirectory
            .standardizedFileURL
        let temporaryIPSW = temporaryRoot.appendingPathComponent(
            "legacy-test-\(UUID().uuidString).ipsw")
        let entry = FirmwareLibraryEntry(
            id: UUID(),
            url: temporaryIPSW,
            state: .available,
            addedAt: Date(),
            lastSeenAt: Date(),
            fileIdentity: nil,
            metadata: metadata(productVersion: "14.0", build: "23A344"),
            validity: .valid,
            errorMessage: nil,
            wholeFileSHA256: nil,
            duplicateEntryIDs: [])
        try writeLegacyDocument(
            roots: [temporaryRoot],
            entries: [entry],
            to: indexPath)

        let store = FirmwareLibraryStore(
            indexURL: indexPath,
            metadataLoader: FirmwareLibraryFixtureLoader(
                metadata: metadata(productVersion: "14.0", build: "23A344")).load,
            ignoreSystemTemporaryRoot: true)
        let entries = try await store.loadEntries()
        let ignoredCount = await store.ignoredTemporaryEntryCount()

        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(ignoredCount, 1)
    }

    func testNewIndexRemainsReadableByLegacyCandidateSchema() async throws {
        let root = try temporaryDirectory()
        let valid = root.appendingPathComponent("valid.ipsw")
        let unreadable = root.appendingPathComponent("unreadable.ipsw")
        let cloud = root.appendingPathComponent("cloud.ipsw")
        let indexPath = root.appendingPathComponent("library.json")
        let loader = FirmwareLibraryFixtureLoader(
            metadataByContent: [
                "valid": metadata(productVersion: "27.0", build: "26A428")
            ])
        try Data("valid".utf8).write(to: valid)
        try Data("unreadable".utf8).write(to: unreadable)
        try Data("cloud".utf8).write(to: cloud)
        let store = FirmwareLibraryStore(
            indexURL: indexPath,
            metadataLoader: loader.load,
            fileAccessInspector: { url in
                if url.lastPathComponent == "unreadable.ipsw" {
                    return .unreadable("permission denied")
                }
                if url.lastPathComponent == "cloud.ipsw" {
                    return .cloudNotDownloaded("not downloaded")
                }
                return .readable
            },
            ignoreSystemTemporaryRoot: false)
        _ = try await store.addDirectory(root)

        let data = try Data(contentsOf: indexPath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacy = try decoder.decode(
            LegacyFirmwareLibraryDocument.self,
            from: data)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        let persistedEntries = try XCTUnwrap(
            object["entries"] as? [[String: Any]])
        let persistedStates = Set(
            persistedEntries.compactMap { $0["state"] as? String })

        XCTAssertEqual(legacy.schemaVersion, 1)
        XCTAssertEqual(legacy.entries.count, 3)
        XCTAssertEqual(
            legacy.entries.filter { $0.state == .invalid }.count,
            2)
        XCTAssertEqual(
            legacy.entries.filter { $0.state == .available }.count,
            1)
        XCTAssertEqual(
            persistedStates,
            Set(["available", "invalid"]))
    }

    func testIndexPersistsAcrossStoreRestartWithoutComputingWholeFileHash() async throws {
        let root = try temporaryDirectory()
        let ipsw = root.appendingPathComponent("Mac14,2-27.10.ipsw")
        try Data("27.10".utf8).write(to: ipsw)
        let index = root.appendingPathComponent("library.json")
        let loader = FirmwareLibraryFixtureLoader(
            metadata: metadata(productVersion: "27.10", build: "26C100"))
        let firstStore = FirmwareLibraryStore(indexURL: index, metadataLoader: loader.load)

        let first = try await firstStore.addDirectory(root)
        XCTAssertEqual(first.indexedCount, 1)
        XCTAssertNil(first.entries.first?.wholeFileSHA256)

        let secondStore = FirmwareLibraryStore(indexURL: index, metadataLoader: loader.load)
        let restored = try await secondStore.loadEntries()
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].url.standardizedFileURL, ipsw.standardizedFileURL)
        XCTAssertEqual(restored[0].metadata?.productVersion, "27.10")
        XCTAssertNil(restored[0].wholeFileSHA256)
    }

    func testAddingSamePathTwiceDoesNotCreateDuplicateEntry() async throws {
        let root = try temporaryDirectory()
        let ipsw = root.appendingPathComponent("same.ipsw")
        try Data("same".utf8).write(to: ipsw)
        let store = FirmwareLibraryStore(
            indexURL: root.appendingPathComponent("library.json"),
            metadataLoader: FirmwareLibraryFixtureLoader(
                metadata: metadata(productVersion: "14.0", build: "23A344")).load)

        _ = try await store.addFile(ipsw)
        _ = try await store.addFile(ipsw)
        let entries = await store.allEntries()

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].duplicateEntryIDs, [])
    }

    func testAddingOneFileKeepsPreviouslyIndexedSiblingAvailable() async throws {
        let root = try temporaryDirectory()
        let first = root.appendingPathComponent("first.ipsw")
        let second = root.appendingPathComponent("second.ipsw")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        let loader = FirmwareLibraryFixtureLoader(metadataByContent: [
            "first": metadata(productVersion: "14.0", build: "23A344"),
            "second": metadata(productVersion: "14.1", build: "23B100")
        ])
        let store = FirmwareLibraryStore(
            indexURL: root.appendingPathComponent("library.json"),
            metadataLoader: loader.load)
        _ = try await store.addFile(first)
        _ = try await store.addFile(second)
        let entries = await store.allEntries()

        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.state == .available })
    }

    func testAddingFileDoesNotMarkEntriesFromOtherDirectoriesMissing() async throws {
        let root = try temporaryDirectory()
        let firstDirectory = root.appendingPathComponent("First", isDirectory: true)
        let secondDirectory = root.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let first = firstDirectory.appendingPathComponent("first.ipsw")
        let second = secondDirectory.appendingPathComponent("second.ipsw")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        let store = FirmwareLibraryStore(
            indexURL: root.appendingPathComponent("library.json"),
            metadataLoader: FirmwareLibraryFixtureLoader(metadata: metadata(
                productVersion: "14.0",
                build: "23A344")).load)
        _ = try await store.addFile(first)
        _ = try await store.addFile(second)

        let entries = await store.allEntries()

        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.state == .available })
    }

    func testSameNamedFilesWithDifferentManifestRemainDistinct() async throws {
        let root = try temporaryDirectory()
        let folderA = root.appendingPathComponent("A", isDirectory: true)
        let folderB = root.appendingPathComponent("B", isDirectory: true)
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
        let first = folderA.appendingPathComponent("Firmware.ipsw")
        let second = folderB.appendingPathComponent("Firmware.ipsw")
        try Data("A".utf8).write(to: first)
        try Data("B".utf8).write(to: second)
        let loader = FirmwareLibraryFixtureLoader(metadataByContent: [
            "A": metadata(productVersion: "14.0", build: "23A344"),
            "B": metadata(productVersion: "14.1", build: "23B100")
        ])
        let store = FirmwareLibraryStore(
            indexURL: root.appendingPathComponent("library.json"),
            metadataLoader: loader.load)

        _ = try await store.addDirectory(folderA)
        _ = try await store.addDirectory(folderB)
        let entries = await store.allEntries()

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.compactMap { $0.metadata?.productBuild }), ["23A344", "23B100"])
        XCTAssertTrue(entries.allSatisfy { $0.duplicateEntryIDs.isEmpty })
    }

    func testMovedIPSWRelocatesOnlyWhenTheMatchIsUnique() async throws {
        let root = try temporaryDirectory()
        let originalDirectory = root.appendingPathComponent("Original", isDirectory: true)
        let movedDirectory = root.appendingPathComponent("Moved", isDirectory: true)
        try FileManager.default.createDirectory(at: originalDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: movedDirectory, withIntermediateDirectories: true)
        let original = originalDirectory.appendingPathComponent("Firmware.ipsw")
        let moved = movedDirectory.appendingPathComponent("Renamed.ipsw")
        try Data("same-ipsw".utf8).write(to: original)
        let loader = FirmwareLibraryFixtureLoader(
            metadata: metadata(productVersion: "14.0", build: "23A344"))
        let store = FirmwareLibraryStore(
            indexURL: root.appendingPathComponent("library.json"),
            metadataLoader: loader.load)
        let initial = try await store.addDirectory(originalDirectory)
        let entryID = try XCTUnwrap(initial.entries.first?.id)

        try FileManager.default.moveItem(at: original, to: moved)
        let result = try await store.refresh(additionalDirectories: [movedDirectory])
        let entries = await store.allEntries()
        let relocated = try XCTUnwrap(entries.first { $0.id == entryID })

        XCTAssertEqual(result.relocatedEntryIDs, [entryID])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(relocated.url.standardizedFileURL, moved.standardizedFileURL)
        XCTAssertEqual(relocated.state, .available)
    }

    func testMultipleRelocationCandidatesAreAmbiguousAndNeverAutoSelected() async throws {
        let root = try temporaryDirectory()
        let originalDirectory = root.appendingPathComponent("Original", isDirectory: true)
        let copyA = root.appendingPathComponent("CopyA", isDirectory: true)
        let copyB = root.appendingPathComponent("CopyB", isDirectory: true)
        for directory in [originalDirectory, copyA, copyB] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let original = originalDirectory.appendingPathComponent("Firmware.ipsw")
        try Data("duplicate-ipsw".utf8).write(to: original)
        let loader = FirmwareLibraryFixtureLoader(
            metadata: metadata(productVersion: "14.0", build: "23A344"))
        let store = FirmwareLibraryStore(
            indexURL: root.appendingPathComponent("library.json"),
            metadataLoader: loader.load)
        let initial = try await store.addDirectory(originalDirectory)
        let entryID = try XCTUnwrap(initial.entries.first?.id)
        try FileManager.default.copyItem(
            at: original,
            to: copyA.appendingPathComponent("Firmware.ipsw"))
        try FileManager.default.copyItem(
            at: original,
            to: copyB.appendingPathComponent("Firmware.ipsw"))
        try FileManager.default.removeItem(at: original)

        let result = try await store.refresh(additionalDirectories: [copyA, copyB])
        let entries = await store.allEntries()
        let originalEntry = try XCTUnwrap(entries.first { $0.id == entryID })

        XCTAssertEqual(result.ambiguousEntryIDs, [entryID])
        XCTAssertEqual(originalEntry.state, .ambiguous)
        XCTAssertTrue(result.entries.contains { $0.state == .available })
        XCTAssertEqual(result.entries.filter { $0.state == .available }.count, 2)
    }

    func testQuerySupportsModelFamilyAndNumericVersionSelection() async throws {
        let root = try temporaryDirectory()
        let old = root.appendingPathComponent("old.ipsw")
        let new = root.appendingPathComponent("new.ipsw")
        try Data("old".utf8).write(to: old)
        try Data("new".utf8).write(to: new)
        let loader = FirmwareLibraryFixtureLoader(metadataByContent: [
            "old": metadata(productVersion: "27.9", build: "26C99"),
            "new": metadata(productVersion: "27.10", build: "26C100")
        ])
        let store = FirmwareLibraryStore(
            indexURL: root.appendingPathComponent("library.json"),
            metadataLoader: loader.load)
        _ = try await store.addDirectory(root)

        let matches = await store.query(
            FirmwareLibraryQuery(
                modelFamilyKey: try XCTUnwrap(ModelFamilyKey(rawValue: "Mac14,2")),
                productVersion: nil))

        XCTAssertEqual(matches.count, 2)
        let buildMatches = await store.query(
            FirmwareLibraryQuery(
                productBuild: "26C100",
                productType: "Mac14,2",
                states: [.available]))
        XCTAssertEqual(buildMatches.count, 1)
        XCTAssertEqual(buildMatches[0].metadata?.productVersion, "27.10")
        XCTAssertEqual(
            FirmwareRecommendationEngine.sortCandidatesByVersion(matches.map {
                FirmwareRecommendationCandidate(entry: $0, compatibility: unverified)
            }).first?.metadata?.productVersion,
            "27.10")
    }

    func testDeletedIndexedFileBecomesExplicitlyUnavailable() async throws {
        let root = try temporaryDirectory()
        let ipsw = root.appendingPathComponent("deleted.ipsw")
        try Data("delete".utf8).write(to: ipsw)
        let store = FirmwareLibraryStore(
            indexURL: root.appendingPathComponent("library.json"),
            metadataLoader: FirmwareLibraryFixtureLoader(
                metadata: metadata(productVersion: "14.0", build: "23A344")).load)
        let initial = try await store.addDirectory(root)
        try FileManager.default.removeItem(at: ipsw)

        _ = try await store.refresh()
        let entries = await store.allEntries()

        XCTAssertEqual(initial.indexedCount, 1)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].state, .missing)
    }

    private var unverified: HardwareCompatibility {
        HardwareCompatibility(status: .unverified, message: "test")
    }

    private func metadata(productVersion: String, build: String) -> IPSWMetadata {
        IPSWMetadata(
            productTypes: ["Mac14,2"],
            identities: [
                IPSWBuildIdentity(
                    deviceClass: "j413ap",
                    boardID: 0x24,
                    chipID: 0x8132)
            ],
            productVersion: productVersion,
            productBuild: build)
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Batch2FirmwareLibrary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeLegacyDocument(
        roots: [URL],
        entries: [FirmwareLibraryEntry],
        to url: URL
    ) throws {
        struct LegacyDocument: Encodable {
            let schemaVersion: Int
            let searchRoots: [URL]
            let entries: [LegacyFirmwareLibraryEntry]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let legacyEntries = entries.map { entry in
            LegacyFirmwareLibraryEntry(
                id: entry.id,
                url: entry.url,
                state: LegacyFirmwareLibraryEntryState(
                    rawValue: entry.state.rawValue)!,
                addedAt: entry.addedAt,
                lastSeenAt: entry.lastSeenAt,
                fileIdentity: entry.fileIdentity,
                metadata: entry.metadata,
                validity: entry.validity,
                errorMessage: entry.errorMessage,
                wholeFileSHA256: entry.wholeFileSHA256,
                duplicateEntryIDs: entry.duplicateEntryIDs)
        }
        try encoder.encode(
            LegacyDocument(
                schemaVersion: 1,
                searchRoots: roots,
                entries: legacyEntries))
            .write(to: url, options: .atomic)
    }
}

private final class FirmwareLibraryFixtureLoader {
    private let metadataByContent: [String: IPSWMetadata]
    private let defaultMetadata: IPSWMetadata?

    init(metadata: IPSWMetadata) {
        self.metadataByContent = [:]
        self.defaultMetadata = metadata
    }

    init(metadataByContent: [String: IPSWMetadata]) {
        self.metadataByContent = metadataByContent
        self.defaultMetadata = nil
    }

    private(set) var loadCount = 0

    func load(url: URL) throws -> IPSWMetadataReadResult {
        loadCount += 1
        let data = try Data(contentsOf: url)
        let content = String(decoding: data, as: UTF8.self)
        guard let metadata = metadataByContent[content] ?? defaultMetadata else {
            return IPSWMetadataReadResult(
                validity: .invalid,
                metadata: nil,
                error: "No fixture metadata")
        }
        let manifestHash = IPSWMetadataReader.sha256Hex(data)
        let identity = try IPSWMetadataReader.fileIdentity(
            url: url,
            buildManifestSHA256: manifestHash)
        return IPSWMetadataReadResult(
            validity: .valid,
            metadata: metadata,
            error: nil,
            fileIdentity: identity,
            buildManifestSHA256: manifestHash,
            wholeFileSHA256: nil)
    }
}

private enum LegacyFirmwareLibraryEntryState: String, Codable {
    case available
    case missing
    case ambiguous
    case invalid
}

private struct LegacyFirmwareLibraryEntry: Codable {
    let id: UUID
    let url: URL
    let state: LegacyFirmwareLibraryEntryState
    let addedAt: Date
    let lastSeenAt: Date
    let fileIdentity: IPSWFileIdentity?
    let metadata: IPSWMetadata?
    let validity: IPSWFileValidity
    let errorMessage: String?
    let wholeFileSHA256: String?
    let duplicateEntryIDs: [UUID]
}

private struct LegacyFirmwareLibraryDocument: Codable {
    let schemaVersion: Int
    let searchRoots: [URL]
    let entries: [LegacyFirmwareLibraryEntry]
}

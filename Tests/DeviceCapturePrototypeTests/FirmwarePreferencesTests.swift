import Foundation
import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class FirmwarePreferencesTests: XCTestCase {
    func testPreferencesPersistAcrossRestartWithoutMixingLastSelectedAndLastUsed() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let preferencesURL = root.appendingPathComponent("preferences.json")
        let first = entry(version: "27.0", build: "26A428")
        let second = entry(version: "27.1", build: "26B100")
        let firstReference = FirmwareReference(entry: first)
        let secondReference = FirmwareReference(entry: second)
        let model = try XCTUnwrap(ModelFamilyKey(rawValue: "Mac14,2"))

        let store = FirmwarePreferencesStore(fileURL: preferencesURL)
        store.setGlobalDefault(firstReference)
        store.setModelDefault(secondReference, for: model)
        store.recordSelection(firstReference, modelFamilyKey: model)

        XCTAssertNil(store.lastUsed)
        XCTAssertTrue(store.recentUsed.isEmpty)

        store.recordUsed(secondReference, modelFamilyKey: model)

        let restored = FirmwarePreferencesStore(fileURL: preferencesURL)
        XCTAssertEqual(restored.globalDefault, firstReference)
        XCTAssertEqual(restored.modelDefault(for: model), secondReference)
        XCTAssertEqual(restored.lastSelected?.reference, firstReference)
        XCTAssertEqual(restored.lastUsed?.reference, secondReference)
        XCTAssertEqual(restored.recentUsed.first?.reference, secondReference)
    }

    func testUnreadablePreferencesRemainUntouchedUntilExplicitBackupAndReset() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let preferencesURL = root.appendingPathComponent("preferences.json")
        let corrupt = Data("{not-valid-json".utf8)
        try corrupt.write(to: preferencesURL)

        let store = FirmwarePreferencesStore(fileURL: preferencesURL)
        XCTAssertNotNil(store.loadError)
        store.setGlobalDefault(FirmwareReference(entry: entry()))

        XCTAssertEqual(try Data(contentsOf: preferencesURL), corrupt)
        XCTAssertTrue(store.resetAfterUnreadableFile())
        XCTAssertNil(store.loadError)
        XCTAssertFalse(
            try Data(contentsOf: preferencesURL).isEmpty)
        let backups = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("unreadable") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: backups[0]), corrupt)
    }

    func testResetWriteFailureRestoresBlockedStateAndPreservesRecoveryPath() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let preferencesURL = root.appendingPathComponent(
            "preferences.json",
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: preferencesURL,
            withIntermediateDirectories: false)

        let store = FirmwarePreferencesStore(fileURL: preferencesURL)

        XCTAssertTrue(store.persistenceIsBlocked)
        XCTAssertTrue(store.canResetUnreadablePreferences)
        XCTAssertFalse(store.resetAfterUnreadableFile())
        XCTAssertTrue(store.persistenceIsBlocked)
        XCTAssertTrue(store.canResetUnreadablePreferences)
        XCTAssertNotNil(store.loadError)
    }

    func testPersistenceFailureRollsBackAndReportsAnOrdinarySaveError() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let blocker = root.appendingPathComponent("not-a-directory")
        try Data("blocker".utf8).write(to: blocker)
        let preferencesURL = blocker.appendingPathComponent("preferences.json")
        let store = FirmwarePreferencesStore(fileURL: preferencesURL)
        let reference = FirmwareReference(entry: entry())

        XCTAssertFalse(store.setGlobalDefault(reference))
        XCTAssertNil(store.globalDefault)
        XCTAssertNotNil(store.loadError)
        XCTAssertFalse(store.canResetUnreadablePreferences)
    }

    func testSemanticallyInvalidModelKeyPreservesFileAndRequiresExplicitReset() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let preferencesURL = root.appendingPathComponent("preferences.json")
        let reference = FirmwareReference(entry: entry())
        let document = FirmwarePreferencesTestDocument(
            schemaVersion: FirmwarePreferencesStore.schemaVersion,
            globalDefault: nil,
            modelDefaults: ["Not A Verified Model": reference],
            lastSelected: nil,
            lastUsed: nil,
            recentUsed: [])
        let original = try JSONEncoder().encode(document)
        try original.write(to: preferencesURL)

        let store = FirmwarePreferencesStore(fileURL: preferencesURL)

        XCTAssertTrue(store.modelDefaults.isEmpty)
        XCTAssertNotNil(store.loadError)
        XCTAssertTrue(store.canResetUnreadablePreferences)
        XCTAssertFalse(store.setGlobalDefault(reference))
        XCTAssertEqual(try Data(contentsOf: preferencesURL), original)
    }

    func testMixedCasePersistedModelKeyUsesTheNormalizedModelIdentity() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let preferencesURL = root.appendingPathComponent("preferences.json")
        let reference = FirmwareReference(entry: entry())
        let document = FirmwarePreferencesTestDocument(
            schemaVersion: FirmwarePreferencesStore.schemaVersion,
            globalDefault: nil,
            modelDefaults: ["Mac14,2": reference],
            lastSelected: nil,
            lastUsed: nil,
            recentUsed: [])
        try JSONEncoder().encode(document).write(to: preferencesURL)

        let store = FirmwarePreferencesStore(fileURL: preferencesURL)
        let key = try XCTUnwrap(ModelFamilyKey(rawValue: "Mac14,2"))

        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.modelDefault(for: key), reference)
        XCTAssertEqual(store.modelDefaults.keys.sorted(), ["MAC14,2"])
    }

    func testConflictingCaseVariantsOfModelDefaultsBlockWritesWithoutOverwriting() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let preferencesURL = root.appendingPathComponent("preferences.json")
        let first = FirmwareReference(entry: entry(version: "27.0"))
        let second = FirmwareReference(entry: entry(version: "27.1"))
        let document = FirmwarePreferencesTestDocument(
            schemaVersion: FirmwarePreferencesStore.schemaVersion,
            globalDefault: nil,
            modelDefaults: [
                "Mac14,2": first,
                "MAC14,2": second
            ],
            lastSelected: nil,
            lastUsed: nil,
            recentUsed: [])
        let original = try JSONEncoder().encode(document)
        try original.write(to: preferencesURL)

        let store = FirmwarePreferencesStore(fileURL: preferencesURL)

        XCTAssertTrue(store.modelDefaults.isEmpty)
        XCTAssertTrue(store.persistenceIsBlocked)
        XCTAssertTrue(store.canResetUnreadablePreferences)
        XCTAssertNotNil(store.loadError)
        XCTAssertFalse(store.setGlobalDefault(first))
        XCTAssertEqual(try Data(contentsOf: preferencesURL), original)
    }

    func testRecentUseListIsBoundedDeduplicatedAndModelScoped() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FirmwarePreferencesStore(
            fileURL: root.appendingPathComponent("preferences.json"))
        let model = try XCTUnwrap(ModelFamilyKey(rawValue: "Mac14,2"))
        let otherModel = try XCTUnwrap(
            ModelFamilyKey(rawValue: "MacBookPro18,2"))
        let entries = (0..<15).map {
            entry(version: "27.\($0)", build: "26A\($0)")
        }

        for (index, item) in entries.enumerated() {
            store.recordUsed(
                FirmwareReference(entry: item),
                modelFamilyKey: index.isMultiple(of: 2)
                    ? model
                    : otherModel,
                at: Date(timeIntervalSince1970: Double(index)))
        }
        store.recordUsed(
            FirmwareReference(entry: entries[0]),
            modelFamilyKey: model,
            at: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(
            store.recentUsed.count,
            FirmwarePreferencesStore.maximumRecentUses)
        XCTAssertEqual(store.recentUsed.first?.reference.entryID, entries[0].id)
        XCTAssertEqual(
            store.recentUsed.filter { $0.reference.entryID == entries[0].id }.count,
            1)
        XCTAssertEqual(store.recentUses(matching: model).count, 7)
        XCTAssertTrue(
            store.recentUses(matching: model).allSatisfy {
                $0.modelFamilyKey == model
            })
    }

    func testReferenceResolverDistinguishesAvailableModifiedMissingCloudAndInvalid() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FirmwarePreferencesStore(
            fileURL: root.appendingPathComponent("preferences.json"))
        let available = entry(version: "27.0", build: "26A428")
        let reference = FirmwareReference(entry: available)

        XCTAssertEqual(
            store.resolve(reference, in: [available])?.state,
            .available)
        XCTAssertEqual(
            store.resolve(reference, in: [])?.state,
            .missing)

        var modified = available
        modified.fileIdentity = identity(
            path: "/tmp/modified.ipsw",
            size: 999,
            manifest: "modified")
        XCTAssertEqual(
            store.resolve(reference, in: [modified])?.state,
            .modified)

        var cloud = available
        cloud.state = .invalid
        cloud.accessState = .cloudNotDownloaded
        cloud.validity = .unverified
        XCTAssertEqual(
            store.resolve(reference, in: [cloud])?.state,
            .cloudNotDownloaded)

        var invalid = available
        invalid.state = .invalid
        invalid.validity = .invalid
        XCTAssertEqual(
            store.resolve(reference, in: [invalid])?.state,
            .invalid)
    }

    func testSyntheticReferenceIDIsStableAndIdentitySpecific() {
        let first = identity(
            path: "/tmp/first.ipsw",
            size: 100,
            manifest: "A")
        let same = identity(
            path: "/tmp/first.ipsw",
            size: 100,
            manifest: "A")
        let changed = identity(
            path: "/tmp/first.ipsw",
            size: 101,
            manifest: "A")

        XCTAssertEqual(
            FirmwareReference.syntheticEntryID(identity: first),
            FirmwareReference.syntheticEntryID(identity: same))
        XCTAssertNotEqual(
            FirmwareReference.syntheticEntryID(identity: first),
            FirmwareReference.syntheticEntryID(identity: changed))
    }

    func testSystemAccessibilityDestinationsPreferVerifiedLegacyAlias() {
        let values = SystemAccessibilitySettings.candidateURLs
            .map(\.absoluteString)
        XCTAssertEqual(
            values,
            [
                SystemAccessibilitySettings.preferredURLString,
                SystemAccessibilitySettings.fallbackURLString
            ])
        XCTAssertTrue(
            values[0].contains("universalaccess"))
        XCTAssertEqual(
            values[0],
            "x-apple.systempreferences:com.apple.preference.universalaccess")
        XCTAssertTrue(
            values[1].contains("Accessibility-Settings.extension"))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "FirmwarePreferences-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true)
        return url
    }

    private func entry(
        version: String = "27.0",
        build: String = "26A428"
    ) -> FirmwareLibraryEntry {
        let id = UUID()
        let path = "/tmp/\(id.uuidString).ipsw"
        return FirmwareLibraryEntry(
            id: id,
            url: URL(fileURLWithPath: path),
            state: .available,
            addedAt: Date(timeIntervalSince1970: 1),
            lastSeenAt: Date(timeIntervalSince1970: 2),
            fileIdentity: identity(
                path: path,
                size: 1024,
                manifest: "manifest-\(version)-\(build)"),
            metadata: IPSWMetadata(
                productTypes: ["Mac14,2"],
                identities: [
                    IPSWBuildIdentity(
                        deviceClass: "j413ap",
                        boardID: 0x24,
                        chipID: 0x8132)
                ],
                productVersion: version,
                productBuild: build),
            validity: .valid,
            errorMessage: nil,
            wholeFileSHA256: nil,
            duplicateEntryIDs: [])
    }

    private func identity(
        path: String,
        size: UInt64,
        manifest: String
    ) -> IPSWFileIdentity {
        IPSWFileIdentity(
            canonicalRealpath: path,
            dev: 1,
            ino: UInt64(abs(path.hashValue)),
            sizeBytes: size,
            mtimeNs: Int64(size),
            ctimeNs: Int64(size),
            buildManifestSHA256: IPSWMetadataReader.sha256Hex(
                Data(manifest.utf8)))
    }
}

private struct FirmwarePreferencesTestDocument: Codable {
    let schemaVersion: Int
    let globalDefault: FirmwareReference?
    let modelDefaults: [String: FirmwareReference]
    let lastSelected: FirmwareSelectionRecord?
    let lastUsed: FirmwareUseRecord?
    let recentUsed: [FirmwareUseRecord]
}

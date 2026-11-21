import Foundation
import XCTest
@testable import DeviceCapturePrototype

final class Batch5ConfiguratorStorageTests: XCTestCase {
    private let root = URL(
        fileURLWithPath: "/fixture/configurator",
        isDirectory: true)

    func testReadableDirectoryReportsLogicalAndAllocatedBytes() async {
        let fileA = child("a.log")
        let directory = child("nested")
        let fileB = child("nested/b.log")
        let reader = FixtureFileReader(
            metadata: [
                path(root): .directory(device: 7, inode: 1),
                path(fileA): .regular(
                    logical: 100,
                    allocated: 4096,
                    device: 7,
                    inode: 2),
                path(directory): .directory(device: 7, inode: 3),
                path(fileB): .regular(
                    logical: 50,
                    allocated: 8192,
                    device: 7,
                    inode: 4),
            ],
            children: [
                path(root): [fileA, directory],
                path(directory): [fileB],
            ])
        let scanner = scanner(reader: reader)

        let snapshot = await scanner.scan()

        XCTAssertEqual(snapshot.completeness, .complete)
        XCTAssertEqual(snapshot.roots[0].status, .complete)
        XCTAssertEqual(snapshot.roots[0].logicalBytes, 150)
        XCTAssertEqual(snapshot.roots[0].allocatedBytes, 12_288)
        XCTAssertEqual(snapshot.roots[0].fileCount, 2)
    }

    func testMissingDirectoryIsDistinctFromZeroBytes() async {
        let reader = FixtureFileReader(
            metadata: [path(root): .failure(.notFound)],
            children: [:])

        let snapshot = await scanner(reader: reader).scan()

        XCTAssertEqual(snapshot.roots[0].status, .missing)
        XCTAssertNil(snapshot.roots[0].logicalBytes)
        XCTAssertNil(snapshot.roots[0].allocatedBytes)
    }

    func testSuccessfulEmptyDirectoryReportsZero() async {
        let reader = FixtureFileReader(
            metadata: [path(root): .directory(device: 1, inode: 1)],
            children: [path(root): []])

        let snapshot = await scanner(reader: reader).scan()

        XCTAssertEqual(snapshot.roots[0].status, .empty)
        XCTAssertEqual(snapshot.roots[0].logicalBytes, 0)
        XCTAssertEqual(snapshot.roots[0].allocatedBytes, 0)
        XCTAssertEqual(snapshot.roots[0].fileCount, 0)
    }

    func testEPERMRootIsPermissionLimitedAndNotZero() async {
        let reader = FixtureFileReader(
            metadata: [path(root): .failure(.permissionDenied)],
            children: [:])

        let snapshot = await scanner(reader: reader).scan()

        XCTAssertEqual(snapshot.roots[0].status, .permissionDenied)
        XCTAssertNil(snapshot.roots[0].logicalBytes)
        XCTAssertEqual(
            snapshot.roots[0].issues.first?.kind,
            .permissionDenied)
        XCTAssertEqual(snapshot.completeness, .permissionLimited)
    }

    func testEACCESNestedDirectoryProducesPartialReadable() async {
        let known = child("known.log")
        let denied = child("protected")
        let reader = FixtureFileReader(
            metadata: [
                path(root): .directory(device: 2, inode: 1),
                path(known): .regular(
                    logical: 32,
                    allocated: 4096,
                    device: 2,
                    inode: 2),
                path(denied): .directory(device: 2, inode: 3),
            ],
            children: [
                path(root): [known, denied],
            ],
            childErrors: [
                path(denied): .accessDenied,
            ])

        let snapshot = await scanner(reader: reader).scan()

        XCTAssertEqual(snapshot.roots[0].status, .partialReadable)
        XCTAssertEqual(snapshot.roots[0].logicalBytes, 32)
        XCTAssertEqual(snapshot.roots[0].allocatedBytes, 4096)
        XCTAssertTrue(
            snapshot.roots[0].issues.contains {
                $0.kind == .permissionDenied
            })
        XCTAssertEqual(snapshot.completeness, .permissionLimited)
        XCTAssertNil(snapshot.totalLogicalBytes)
        XCTAssertNil(snapshot.totalAllocatedBytes)
    }

    func testNestedPermissionDenialWithoutVisibleFilesIsNotZero() async {
        let denied = child("protected")
        let reader = FixtureFileReader(
            metadata: [
                path(root): .directory(device: 2, inode: 1),
                path(denied): .directory(device: 2, inode: 3),
            ],
            children: [
                path(root): [denied],
            ],
            childErrors: [
                path(denied): .accessDenied,
            ])

        let snapshot = await scanner(reader: reader).scan()

        XCTAssertEqual(snapshot.roots[0].status, .permissionDenied)
        XCTAssertNil(snapshot.roots[0].logicalBytes)
        XCTAssertNil(snapshot.roots[0].allocatedBytes)
        XCTAssertNil(snapshot.totalLogicalBytes)
        XCTAssertNil(snapshot.totalAllocatedBytes)
        XCTAssertEqual(snapshot.completeness, .permissionLimited)
    }

    func testEntryLimitStopsEnumerationAtTheConfiguredBound() async {
        let files = (0..<4).map { child("\($0).log") }
        var metadata = [
            path(root): FixtureFileBuilder.directory(
                device: 8,
                inode: 1),
        ]
        for (index, file) in files.enumerated() {
            metadata[path(file)] = .regular(
                logical: Int64(index + 1),
                allocated: 4096,
                device: 8,
                inode: UInt64(index + 2))
        }
        let reader = FixtureFileReader(
            metadata: metadata,
            children: [path(root): files])

        let snapshot = await scanner(
            reader: reader,
            maximumEntriesPerRoot: 2).scan()

        XCTAssertEqual(reader.enumeratedChildCount, 2)
        XCTAssertEqual(snapshot.roots[0].status, .partialReadable)
        XCTAssertEqual(snapshot.roots[0].fileCount, 2)
        XCTAssertTrue(
            snapshot.roots[0].issues.contains {
                $0.kind == .limitReached
            })
        XCTAssertNil(snapshot.totalLogicalBytes)
    }

    func testDepthLimitDoesNotEnumerateBlockedDirectory() async {
        let levelOne = child("level-one")
        let levelTwo = child("level-one/level-two")
        let reader = FixtureFileReader(
            metadata: [
                path(root): .directory(device: 8, inode: 1),
                path(levelOne): .directory(device: 8, inode: 2),
                path(levelTwo): .directory(device: 8, inode: 3),
            ],
            children: [
                path(root): [levelOne],
                path(levelOne): [levelTwo],
                path(levelTwo): [],
            ])
        let scanner = ConfiguratorStorageScanner(
            rootDiscoverer: StaticRootDiscoverer(roots: [
                ConfiguratorStorageRoot(
                    url: root,
                    kind: .groupContainer,
                    displayName: "fixture"),
            ]),
            fileReader: reader,
            processDiscoverer: StaticProcessDiscoverer(names: []),
            maximumDepth: 1)

        let snapshot = await scanner.scan()

        XCTAssertEqual(
            reader.enumeratedDirectories,
            [path(root), path(levelOne)])
        XCTAssertTrue(
            snapshot.roots[0].issues.contains {
                $0.kind == .limitReached
                    && $0.detail == "DEPTH_LIMIT"
            })
        XCTAssertNil(snapshot.totalLogicalBytes)
    }

    func testPartiallyReadableSiblingDoesNotDiscardKnownUsage() async {
        let known = child("a.log")
        let failed = child("failed")
        let reader = FixtureFileReader(
            metadata: [
                path(root): .directory(device: 3, inode: 1),
                path(known): .regular(
                    logical: 20,
                    allocated: 2048,
                    device: 3,
                    inode: 2),
                path(failed): .directory(device: 3, inode: 3),
            ],
            children: [path(root): [known, failed]],
            childErrors: [path(failed): .failed])

        let snapshot = await scanner(reader: reader).scan()

        XCTAssertEqual(snapshot.roots[0].status, .partialReadable)
        XCTAssertEqual(snapshot.roots[0].logicalBytes, 20)
        XCTAssertTrue(
            snapshot.roots[0].issues.contains {
                $0.kind == .scanFailed
            })
        XCTAssertEqual(snapshot.completeness, .partial)
    }

    func testExactProcessNamesDistinguishRunningAndStopped() async {
        let reader = emptyReader()
        let processes = StaticProcessDiscoverer(
            names: [
                "/Applications/Apple Configurator.app/Contents/MacOS/Apple Configurator",
                "/Applications/Apple Configurator.app/Contents/Frameworks/ConfigurationUtilityKit.framework/Versions/A/XPCServices/com.apple.configurator.xpc.DeviceService.xpc/Contents/MacOS/com.apple.configurator.xpc.DeviceService",
                "/Applications/Apple Configurator.app/Contents/Frameworks/ConfigurationUtilityKit.framework/Versions/A/XPCServices/com.apple.configurator.xpc.InternetService.xpc/Contents/MacOS/com.apple.configurator.xpc.InternetService",
                "/Applications/Apple Configurator.app/Contents/Frameworks/ConfigurationUtilityKit.framework/Versions/A/XPCServices/com.apple.configurator.xpc.MigrationService.xpc/Contents/MacOS/com.apple.configurator.xpc.MigrationService",
                "/Applications/Apple Configurator.app/Contents/Frameworks/ConfigurationUtilityKit.framework/Versions/A/XPCServices/com.apple.configurator.xpc.SmartHubService.xpc/Contents/MacOS/com.apple.configurator.xpc.SmartHubService",
            ])

        let snapshot = await scanner(
            reader: reader,
            processes: processes).scan()

        XCTAssertEqual(
            snapshot.processes.first {
                $0.key == .appleConfigurator
            }?.status,
            .running)
        XCTAssertEqual(
            snapshot.processes.first {
                $0.key == .deviceService
            }?.status,
            .running)
        XCTAssertEqual(
            snapshot.processes.first {
                $0.key == .internetService
            }?.status,
            .running)
        XCTAssertEqual(
            snapshot.processes.first {
                $0.key == .migrationService
            }?.status,
            .running)
        XCTAssertEqual(
            snapshot.processes.first {
                $0.key == .smartHubService
            }?.status,
            .running)
    }

    func testProcessNameFalsePositiveIsIgnored() async {
        let processes = StaticProcessDiscoverer(
            names: [
                "/tmp/DeviceService",
                "/tmp/InternetService",
                "/tmp/MigrationService",
                "/tmp/SmartHubService",
                "/tmp/com.apple.configurator.xpc.DeviceService",
                "/Applications/Apple Configurator.app/Contents/MacOS/apple configurator",
                "/Applications/Apple Configurator.app/Contents/MacOS/deviceservice",
                "Apple Configurator Beta",
                "com.apple.configurator.xpc.DeviceService.bak",
                "com.apple.configurator.xpc.InternetService.disabled",
                "com.apple.configurator.xpc.MigrationService.helper",
                "com.apple.configurator.xpc.SmartHubService.backup",
                "DeviceServiceHelper",
                "MyMigrationServiceProxy",
                "SmartHubServiceDebug",
            ])

        let snapshot = await scanner(
            reader: emptyReader(),
            processes: processes).scan()

        XCTAssertTrue(
            snapshot.processes.allSatisfy {
                $0.status == .notRunning
            })
    }

    func testLegacyShortProcessNamesRemainCompatible() async {
        let processes = StaticProcessDiscoverer(
            names: [
                "/Applications/Apple Configurator.app/Contents/MacOS/Apple Configurator",
                "/Applications/Apple Configurator.app/Contents/MacOS/DeviceService",
                "/Applications/Apple Configurator.app/Contents/MacOS/InternetService",
                "/Applications/Apple Configurator.app/Contents/MacOS/MigrationService",
                "/Applications/Apple Configurator.app/Contents/MacOS/SmartHubService",
            ])

        let snapshot = await scanner(
            reader: emptyReader(),
            processes: processes).scan()

        XCTAssertTrue(
            snapshot.processes.allSatisfy {
                $0.status == .running
            })
    }

    func testReferenceLabBlueprintsAndIPSWAreExcluded() async {
        let referenceLab = child("AppleConfiguratorReferenceLab")
        let blueprints = child("Blueprints")
        let ipsw = child("Firmware.ipsw")
        let visible = child("visible.tmp")
        let reader = FixtureFileReader(
            metadata: [
                path(root): .directory(device: 4, inode: 1),
                path(referenceLab): .directory(device: 4, inode: 2),
                path(blueprints): .directory(device: 4, inode: 3),
                path(ipsw): .regular(
                    logical: 10_000,
                    allocated: 12_288,
                    device: 4,
                    inode: 4),
                path(visible): .regular(
                    logical: 5,
                    allocated: 4096,
                    device: 4,
                    inode: 5),
            ],
            children: [
                path(root): [
                    referenceLab,
                    blueprints,
                    ipsw,
                    visible,
                ],
            ])

        let snapshot = await scanner(reader: reader).scan()

        XCTAssertEqual(snapshot.roots[0].logicalBytes, 5)
        XCTAssertEqual(snapshot.roots[0].fileCount, 1)
        XCTAssertEqual(snapshot.roots[0].excludedEntryCount, 3)
    }

    func testScanDoesNotDeleteSyntheticFiles() async throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Batch5Scanner-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporary,
            withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: temporary)
        }
        let file = temporary.appendingPathComponent("keep.log")
        try Data("read only".utf8).write(to: file)
        let scanner = ConfiguratorStorageScanner(
            rootDiscoverer: StaticRootDiscoverer(roots: [
                ConfiguratorStorageRoot(
                    url: temporary,
                    kind: .userCache,
                    displayName: "fixture"),
            ]),
            fileReader: ConfiguratorStorageLiveFileReader(),
            processDiscoverer: StaticProcessDiscoverer(names: []))

        _ = await scanner.scan()

        XCTAssertEqual(
            try Data(contentsOf: file),
            Data("read only".utf8))
    }

    func testDirectoryChangingDuringScanIsReported() async {
        let disappearing = child("disappearing.log")
        let reader = FixtureFileReader(
            metadata: [
                path(root): .directory(device: 5, inode: 1),
                path(disappearing): .failure(.notFoundAfterListing),
            ],
            children: [path(root): [disappearing]])

        let snapshot = await scanner(reader: reader).scan()

        XCTAssertEqual(snapshot.roots[0].status, .partialReadable)
        XCTAssertTrue(
            snapshot.roots[0].issues.contains {
                $0.kind == .changedDuringScan
            })
    }

    func testDirectoryIdentityMismatchIsRejectedBeforeTraversal() async {
        let reader = FixtureFileReader(
            metadata: [
                path(root): .directory(device: 9, inode: 1),
            ],
            children: [path(root): []],
            childIdentityMismatches: [path(root)])

        let snapshot = await scanner(reader: reader).scan()

        XCTAssertEqual(reader.enumeratedChildCount, 0)
        XCTAssertEqual(snapshot.roots[0].status, .partialReadable)
        XCTAssertTrue(
            snapshot.roots[0].issues.contains {
                $0.kind == .changedDuringScan
            })
        XCTAssertNil(snapshot.totalLogicalBytes)
    }

    func testOpeningDirectoryAfterSymlinkReplacementIsRejected() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Batch5Symlink-\(UUID().uuidString)",
                isDirectory: true)
        let moved = temporary.appendingPathComponent(
            "moved",
            isDirectory: true)
        let directory = temporary.appendingPathComponent(
            "approved",
            isDirectory: true)
        let outside = temporary.appendingPathComponent(
            "outside",
            isDirectory: true)
        let sentinel = outside.appendingPathComponent("sentinel.log")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: sentinel)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: temporary)
        }
        let reader = ConfiguratorStorageLiveFileReader()
        let original = try reader.metadata(at: directory)
        try FileManager.default.moveItem(at: directory, to: moved)
        try FileManager.default.createSymbolicLink(
            at: directory,
            withDestinationURL: outside)
        var observedError: Error?

        XCTAssertThrowsError(
            _ = try reader.openDirectory(
                at: directory,
                expectedDevice: original.device,
                expectedInode: original.inode)
        ) { error in
            observedError = error
        }
        XCTAssertEqual(
            observedError as? ConfiguratorStorageReadFailure,
            .changedDuringScan)
    }

    func testOpenedDirectoryDescriptorDoesNotFollowLaterPathSwap() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Batch5Descriptor-\(UUID().uuidString)",
                isDirectory: true)
        let moved = temporary.appendingPathComponent(
            "moved",
            isDirectory: true)
        let directory = temporary.appendingPathComponent(
            "approved",
            isDirectory: true)
        let nested = directory.appendingPathComponent(
            "nested",
            isDirectory: true)
        let outside = temporary.appendingPathComponent(
            "outside",
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: nested,
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: true)
        try Data("inside".utf8).write(
            to: directory.appendingPathComponent("inside.log"))
        try Data("nested".utf8).write(
            to: nested.appendingPathComponent("inside-nested.log"))
        try Data("outside".utf8).write(
            to: outside.appendingPathComponent("outside-sentinel.log"))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: temporary)
        }

        let reader = ConfiguratorStorageLiveFileReader()
        let original = try reader.metadata(at: directory)
        let opened = try reader.openDirectory(
            at: directory,
            expectedDevice: original.device,
            expectedInode: original.inode)

        try FileManager.default.moveItem(at: directory, to: moved)
        try FileManager.default.createSymbolicLink(
            at: directory,
            withDestinationURL: outside)

        var rootNames: Set<String> = []
        var nestedMetadata: ConfiguratorStorageFileMetadata?
        try opened.readChildren { name, metadata in
            rootNames.insert(name)
            if name == "nested" {
                nestedMetadata = metadata
            }
            return true
        }

        XCTAssertEqual(
            rootNames,
            Set(["inside.log", "nested"]))
        XCTAssertFalse(rootNames.contains("outside-sentinel.log"))

        let metadata = try XCTUnwrap(nestedMetadata)
        var nestedNames: Set<String> = []
        try opened.withChildDirectory(
            named: "nested",
            metadata: metadata
        ) { child in
            try child.readChildren { name, _ in
                nestedNames.insert(name)
                return true
            }
        }

        XCTAssertEqual(
            nestedNames,
            Set(["inside-nested.log"]))
        XCTAssertFalse(
            nestedNames.contains("outside-sentinel.log"))
    }

    func testUnexpectedRootFailureIsNotReportedAsZero() async {
        let reader = FixtureFileReader(
            metadata: [path(root): .failure(.unexpected)],
            children: [:])

        let snapshot = await scanner(reader: reader).scan()

        XCTAssertEqual(snapshot.roots[0].status, .failed)
        XCTAssertNil(snapshot.roots[0].logicalBytes)
        XCTAssertEqual(snapshot.completeness, .failed)
    }

    func testFailedAndEmptyRootsRemainPartialWithoutMisleadingTotal() async {
        let failedRoot = child("failed")
        let emptyRoot = child("empty")
        let reader = FixtureFileReader(
            metadata: [
                path(emptyRoot): .directory(
                    device: 10,
                    inode: 2),
                path(failedRoot): .failure(.unexpected),
            ],
            children: [path(emptyRoot): []])
        let scanner = ConfiguratorStorageScanner(
            rootDiscoverer: StaticRootDiscoverer(roots: [
                ConfiguratorStorageRoot(
                    url: emptyRoot,
                    kind: .appContainer,
                    displayName: "empty"),
                ConfiguratorStorageRoot(
                    url: failedRoot,
                    kind: .appContainer,
                    displayName: "failed"),
            ]),
            fileReader: reader,
            processDiscoverer: StaticProcessDiscoverer(names: []))

        let snapshot = await scanner.scan()

        XCTAssertEqual(snapshot.completeness, .partial)
        XCTAssertNil(snapshot.totalLogicalBytes)
        XCTAssertNil(snapshot.totalAllocatedBytes)
    }

    func testUnknownProcessQueryDoesNotInventProcessState() async {
        let snapshot = await scanner(
            reader: emptyReader(),
            processes: StaticProcessDiscoverer(names: nil)).scan()

        XCTAssertTrue(
            snapshot.processes.allSatisfy {
                $0.status == .unknown
            })
    }

    func testRootDiscoveryOnlyReturnsConfiguratorNamedLocations() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Batch5Roots-\(UUID().uuidString)",
                isDirectory: true)
        let group = temporary.appendingPathComponent(
            "Library/Group Containers/K36BKF7T3D.group.com.apple.configurator",
            isDirectory: true)
        let matchingContainer = temporary.appendingPathComponent(
            "Library/Containers/com.apple.configurator.ui",
            isDirectory: true)
        let unrelatedContainer = temporary.appendingPathComponent(
            "Library/Containers/com.example.unrelated",
            isDirectory: true)
        let groupNameLookalike = temporary.appendingPathComponent(
            "Library/Containers/not-group.com.apple.configurator.fake",
            isDirectory: true)
        let matchingFile = temporary.appendingPathComponent(
            "Library/Containers/com.apple.configurator.file",
            isDirectory: false)
        let matchingSymlink = temporary.appendingPathComponent(
            "Library/Containers/com.apple.configurator.symlink",
            isDirectory: false)
        let uppercaseContainer = temporary.appendingPathComponent(
            "Library/Containers/COM.APPLE.CONFIGURATOR.UPPER",
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: group,
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: matchingContainer,
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: unrelatedContainer,
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: groupNameLookalike,
            withIntermediateDirectories: true)
        try Data("not a container".utf8).write(to: matchingFile)
        try FileManager.default.createSymbolicLink(
            at: matchingSymlink,
            withDestinationURL: unrelatedContainer)
        try FileManager.default.createDirectory(
            at: uppercaseContainer,
            withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: temporary)
        }

        let discovery = ConfiguratorStorageLiveRootDiscoverer(
            homeDirectory: temporary,
            includeDarwinUserDirectories: false).discover()
        let paths = Set(discovery.roots.map {
            $0.url.standardizedFileURL.path
        })

        XCTAssertTrue(paths.contains(group.standardizedFileURL.path))
        XCTAssertTrue(
            paths.contains(matchingContainer.standardizedFileURL.path))
        XCTAssertFalse(
            paths.contains(unrelatedContainer.standardizedFileURL.path))
        XCTAssertFalse(
            paths.contains(groupNameLookalike.standardizedFileURL.path))
        XCTAssertFalse(
            paths.contains(matchingFile.standardizedFileURL.path))
        XCTAssertFalse(
            paths.contains(matchingSymlink.standardizedFileURL.path))
        XCTAssertFalse(
            paths.contains(uppercaseContainer.standardizedFileURL.path))
    }

    func testRootDiscoveryStopsAtItsEntryBudget() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Batch5RootLimit-\(UUID().uuidString)",
                isDirectory: true)
        let containers = temporary.appendingPathComponent(
            "Library/Containers",
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: containers,
            withIntermediateDirectories: true)
        for index in 0..<4 {
            try FileManager.default.createDirectory(
                at: containers.appendingPathComponent(
                    "com.example.fixture-\(index)",
                    isDirectory: true),
                withIntermediateDirectories: false)
        }
        addTeardownBlock {
            try? FileManager.default.removeItem(at: temporary)
        }

        let discovery = ConfiguratorStorageLiveRootDiscoverer(
            homeDirectory: temporary,
            includeDarwinUserDirectories: false,
            maximumEntriesPerParent: 1,
            maximumMatchingRoots: 1).discover()

        XCTAssertTrue(
            discovery.issues.contains {
                $0.kind == .limitReached
                    && $0.detail == "DISCOVERY_ENTRY_LIMIT"
            })
    }

    func testRootDiscoveryStopsAtItsMatchingRootBudget() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Batch5RootMatchLimit-\(UUID().uuidString)",
                isDirectory: true)
        let containers = temporary.appendingPathComponent(
            "Library/Containers",
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: containers,
            withIntermediateDirectories: true)
        for name in [
            "com.apple.configurator.ui",
            "com.apple.configurator.xpc.DeviceService",
            "com.apple.configurator.xpc.InternetService",
        ] {
            try FileManager.default.createDirectory(
                at: containers.appendingPathComponent(
                    name,
                    isDirectory: true),
                withIntermediateDirectories: false)
        }
        addTeardownBlock {
            try? FileManager.default.removeItem(at: temporary)
        }

        let discovery = ConfiguratorStorageLiveRootDiscoverer(
            homeDirectory: temporary,
            includeDarwinUserDirectories: false,
            maximumEntriesPerParent: 100,
            maximumMatchingRoots: 1).discover()

        XCTAssertTrue(
            discovery.issues.contains {
                $0.kind == .limitReached
                    && $0.detail == "DISCOVERY_ROOT_LIMIT"
            })
    }

    func testBatch5VersionMetadataUsesPlanBAndBuildNumber() throws {
        let url = appRoot.appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil)
        let plist = try XCTUnwrap(object as? [String: Any])

        XCTAssertEqual(AboutSoftwareInfo.productVersion, "1.0.7.2")
        XCTAssertEqual(
            plist["CFBundleShortVersionString"] as? String,
            "1.0.8-rc")
        XCTAssertEqual(
            plist["CFBundleVersion"] as? String,
            "20261121.1400")
        XCTAssertEqual(
            plist["CFBundleIdentifier"] as? String,
            "com.mra.devicecontrol.prototype")
        XCTAssertGreaterThan(
            try buildComponents("20261121.1400"),
            try buildComponents("20261115.1500"))
    }

    func testConfiguratorReadOnlyUIKeepsDestructiveActionDisabled() throws {
        let content = try String(
            contentsOf: sourceRoot.appendingPathComponent("ContentView.swift"),
            encoding: .utf8)
        let scanner = try String(
            contentsOf: sourceRoot.appendingPathComponent(
                "ConfiguratorStorageScanner.swift"),
            encoding: .utf8)

        XCTAssertTrue(
            content.contains(
                "ConfiguratorStorageReadOnlyView(model: configuratorReset)"))
        XCTAssertTrue(scanner.contains("待白名单核验授权"))
        XCTAssertFalse(scanner.contains("removeItem"))
        XCTAssertFalse(scanner.contains("delete"))
    }

    private func scanner(
        reader: FixtureFileReader,
        processes: StaticProcessDiscoverer =
            StaticProcessDiscoverer(names: []),
        maximumEntriesPerRoot: Int = 100_000
    ) -> ConfiguratorStorageScanner {
        ConfiguratorStorageScanner(
            rootDiscoverer: StaticRootDiscoverer(roots: [
                ConfiguratorStorageRoot(
                    url: root,
                    kind: .groupContainer,
                    displayName: "fixture"),
            ]),
            fileReader: reader,
            processDiscoverer: processes,
            maximumEntriesPerRoot: maximumEntriesPerRoot)
    }

    private func emptyReader() -> FixtureFileReader {
        FixtureFileReader(
            metadata: [
                path(root): .directory(device: 1, inode: 1),
            ],
            children: [path(root): []])
    }

    private func child(_ relative: String) -> URL {
        root.appendingPathComponent(relative)
    }

    private func path(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func buildComponents(_ value: String) throws -> Int {
        try value.split(separator: ".").map {
            try XCTUnwrap(Int($0))
        }.enumerated().reduce(0) { result, item in
            result + item.element * (item.offset == 0
                ? 10_000
                : 1)
        }
    }

    private var appRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var sourceRoot: URL {
        appRoot
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent(
                "DeviceCapturePrototype",
                isDirectory: true)
    }
}

private typealias FixtureFileFailure =
    ConfiguratorStorageReadFailure

private enum FixtureFileBuilder {
    case directory(device: UInt64, inode: UInt64)
    case regular(
        logical: Int64,
        allocated: Int64,
        device: UInt64,
        inode: UInt64)
    case failure(FixtureFileFailure)
}

private final class FixtureFileReader:
    ConfiguratorStorageFileReading,
    @unchecked Sendable
{
    private let metadata: [String: FixtureFileBuilder]
    private let children: [String: [URL]]
    private let childErrors: [String: FixtureFileFailure]
    private let childIdentityMismatches: Set<String>
    private(set) var enumeratedChildCount = 0
    private(set) var enumeratedDirectories: [String] = []

    init(
        metadata: [String: FixtureFileBuilder],
        children: [String: [URL]],
        childErrors: [String: FixtureFileFailure] = [:],
        childIdentityMismatches: Set<String> = []
    ) {
        self.metadata = metadata
        self.children = children
        self.childErrors = childErrors
        self.childIdentityMismatches = childIdentityMismatches
    }

    func metadata(at url: URL) throws -> ConfiguratorStorageFileMetadata {
        switch metadata[url.standardizedFileURL.path] {
        case let .directory(device, inode):
            return ConfiguratorStorageFileMetadata(
                kind: .directory,
                logicalBytes: 0,
                allocatedBytes: 0,
                device: device,
                inode: inode)
        case let .regular(logical, allocated, device, inode):
            return ConfiguratorStorageFileMetadata(
                kind: .regularFile,
                logicalBytes: logical,
                allocatedBytes: allocated,
                device: device,
                inode: inode)
        case let .failure(error):
            throw error
        case nil:
            throw FixtureFileFailure.unexpected
        }
    }

    func openDirectory(
        at url: URL,
        expectedDevice: UInt64,
        expectedInode: UInt64
    ) throws -> any ConfiguratorStorageDirectoryReading {
        let value = try metadata(at: url)
        guard value.kind == .directory,
              value.device == expectedDevice,
              value.inode == expectedInode else {
            throw FixtureFileFailure.changedDuringScan
        }
        if childIdentityMismatches.contains(
            url.standardizedFileURL.path) {
            throw FixtureFileFailure.changedDuringScan
        }
        return FixtureDirectoryReader(owner: self, url: url)
    }

    fileprivate func readChildren(
        of url: URL,
        visit: (String, ConfiguratorStorageFileMetadata) throws -> Bool
    ) throws {
        enumeratedDirectories.append(
            url.standardizedFileURL.path)
        if let error = childErrors[url.standardizedFileURL.path] {
            throw error
        }
        guard let value = children[url.standardizedFileURL.path] else {
            throw FixtureFileFailure.unexpected
        }
        for child in value {
            enumeratedChildCount += 1
            let childMetadata = try metadata(at: child)
            guard try visit(
                child.lastPathComponent,
                childMetadata) else { return }
        }
    }

    fileprivate func childDirectory(
        of url: URL,
        named name: String,
        metadata: ConfiguratorStorageFileMetadata
    ) throws -> any ConfiguratorStorageDirectoryReading {
        let child = url.appendingPathComponent(name)
        if childIdentityMismatches.contains(
            child.standardizedFileURL.path) {
            throw FixtureFileFailure.changedDuringScan
        }
        let current = try self.metadata(at: child)
        guard current.kind == .directory,
              current.device == metadata.device,
              current.inode == metadata.inode else {
            throw FixtureFileFailure.changedDuringScan
        }
        return FixtureDirectoryReader(owner: self, url: child)
    }
}

private final class FixtureDirectoryReader:
    ConfiguratorStorageDirectoryReading
{
    let url: URL
    private let owner: FixtureFileReader

    init(owner: FixtureFileReader, url: URL) {
        self.owner = owner
        self.url = url
    }

    func readChildren(
        visit: (String, ConfiguratorStorageFileMetadata) throws -> Bool
    ) throws {
        try owner.readChildren(of: url, visit: visit)
    }

    func withChildDirectory(
        named name: String,
        metadata: ConfiguratorStorageFileMetadata,
        body: (any ConfiguratorStorageDirectoryReading) throws -> Void
    ) throws {
        let child = try owner.childDirectory(
            of: url,
            named: name,
            metadata: metadata)
        try body(child)
    }
}

private struct StaticRootDiscoverer:
    ConfiguratorStorageRootDiscovering
{
    let roots: [ConfiguratorStorageRoot]
    var issues: [ConfiguratorStorageAccessIssue] = []

    func discover() -> ConfiguratorStorageRootDiscovery {
        ConfiguratorStorageRootDiscovery(
            roots: roots,
            issues: issues)
    }
}

private struct StaticProcessDiscoverer:
    ConfiguratorProcessDiscovering
{
    let names: [String]?

    func processNames() -> [String]? {
        names
    }
}

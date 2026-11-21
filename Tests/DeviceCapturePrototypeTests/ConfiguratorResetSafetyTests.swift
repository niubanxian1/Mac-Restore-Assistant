import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class ConfiguratorResetSafetyTests: XCTestCase {
    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("cfg-safety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func makeModel(
        home: URL,
        executor: MockConfiguratorExecutor
    ) -> ConfiguratorResetModel {
        ConfiguratorResetModel(
            home: home,
            appURL: URL(fileURLWithPath: "/tmp/Configurator.app", isDirectory: true),
            executor: executor,
            simulationOnly: true)
    }

    func testNoMatchingPathReportsNoMatchAndDoesNotInventCleanup() throws {
        let home = try makeHome()
        let executor = MockConfiguratorExecutor(running: true)
        let model = makeModel(home: home, executor: executor)

        model.performCleanAndReset()

        XCTAssertEqual(model.stepResults.first { $0.name == "只读盘点" }?.status, .noMatch)
        XCTAssertEqual(model.stepResults.first { $0.name == "精确清理" }?.status, .noMatch)
        XCTAssertEqual(executor.waitTerminationCount, 1)
        XCTAssertEqual(executor.waitRunningCount, 1)
        XCTAssertEqual(executor.frontCount, 1)
        XCTAssertTrue(model.overallMessage.contains("没有需要删除"))
        XCTAssertFalse(model.overallMessage.localizedCaseInsensitiveContains("usbd"))
    }

    func testExactCurrentContainerCacheIsRemovedAndApplicationSupportIsPreserved() throws {
        let home = try makeHome()
        let cache = home.appendingPathComponent(
            "Library/Containers/com.apple.configurator.ui/Data/Library/Caches",
            isDirectory: true)
        let support = home.appendingPathComponent(
            "Library/Containers/com.apple.configurator.ui/Data/Library/Application Support",
            isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try "cache".write(to: cache.appendingPathComponent("cache.bin"), atomically: true, encoding: .utf8)
        try "keep".write(to: support.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)

        let executor = MockConfiguratorExecutor(running: true)
        let model = makeModel(home: home, executor: executor)
        model.performCleanAndReset()

        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: support.appendingPathComponent("keep.txt").path))
        XCTAssertEqual(model.stepResults.first { $0.name == "精确清理" }?.status, .success)
        XCTAssertEqual(model.stepResults.first { $0.name == "保留 Application Support" }?.status, .skipped)
        XCTAssertNil(model.lastBackupURL)
    }

    func testLegacyWildcardIsExpandedToExactExistingDirectoriesOnly() throws {
        let home = try makeHome()
        let legacyCache = home.appendingPathComponent(
            "Library/Caches/com.apple.AppleConfigurator.legacy-test",
            isDirectory: true)
        let legacySupport = home.appendingPathComponent(
            "Library/Application Support/Apple/Apple Configurator.legacy-test",
            isDirectory: true)
        let unrelated = home.appendingPathComponent(
            "Library/Caches/com.example.AppleConfiguratorUnrelatedKeep",
            isDirectory: true)
        for url in [legacyCache, legacySupport, unrelated] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try "item".write(
                to: url.appendingPathComponent("item.txt"),
                atomically: true,
                encoding: .utf8)
        }

        let targets = ConfiguratorKnownLocations.discoverExistingTargets(
            home: home,
            files: FoundationConfiguratorFileOperating())

        let targetPaths = Set(targets.map {
            URL(fileURLWithPath: $0.path).standardizedFileURL.path
        })
        XCTAssertTrue(targetPaths.contains(legacyCache.standardizedFileURL.path))
        XCTAssertTrue(targetPaths.contains(legacySupport.standardizedFileURL.path))
        XCTAssertFalse(targetPaths.contains(unrelated.standardizedFileURL.path))
        XCTAssertTrue(targets.allSatisfy { !$0.path.contains("*") })
    }

    func testApplicationSupportIsBackedUpBeforeExplicitDeletion() throws {
        let home = try makeHome()
        let support = home.appendingPathComponent(
            "Library/Containers/com.apple.configurator.ui/Data/Library/Application Support",
            isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try "restore-record".write(
            to: support.appendingPathComponent("record.txt"),
            atomically: true,
            encoding: .utf8)

        let model = makeModel(home: home, executor: MockConfiguratorExecutor(running: true))
        model.includeApplicationSupport = true
        model.performCleanAndReset()

        XCTAssertFalse(FileManager.default.fileExists(atPath: support.path))
        let backup = try XCTUnwrap(model.lastBackupURL)
        let backupFiles = FileManager.default.enumerator(
            at: backup,
            includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        XCTAssertTrue(backupFiles.contains { $0.lastPathComponent == "record.txt" })
        XCTAssertEqual(model.stepResults.first { $0.name == "备份 Application Support" }?.status, .success)
    }

    func testQuitFailureStopsBeforeDeletionAndKeepsAppFronted() throws {
        let home = try makeHome()
        let cache = home.appendingPathComponent(
            "Library/Containers/com.apple.configurator.ui/Data/Library/Caches",
            isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let executor = MockConfiguratorExecutor(running: true, quitShouldFail: true)
        let model = makeModel(home: home, executor: executor)

        model.performCleanAndReset()

        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertEqual(executor.openCount, 0)
        XCTAssertEqual(executor.frontCount, 1)
        XCTAssertEqual(model.stepResults.first { $0.name == "退出" }?.status, .failure)
        XCTAssertTrue(model.overallMessage.contains("退出步骤失败"))
    }

    func testOpenOrFrontFailureCannotBeReportedAsComplete() throws {
        let home = try makeHome()
        let openFailExecutor = MockConfiguratorExecutor(running: false, openShouldFail: true)
        let openFailModel = makeModel(home: home, executor: openFailExecutor)
        openFailModel.performCleanAndReset()
        XCTAssertFalse(openFailModel.allStepsSucceeded)
        XCTAssertEqual(
            openFailModel.stepResults.first { $0.name == "重新打开" }?.status,
            .failure)
        XCTAssertTrue(openFailModel.overallMessage.contains("未成功"))

        let frontFailExecutor = MockConfiguratorExecutor(running: true, frontShouldFail: true)
        let frontFailModel = makeModel(home: home, executor: frontFailExecutor)
        frontFailModel.performReopen()
        XCTAssertFalse(frontFailModel.allStepsSucceeded)
        XCTAssertEqual(
            frontFailModel.stepResults.first { $0.name == "置前" }?.status,
            .failure)
    }

    func testAppSourcesNoLongerContainLegacyUSBStopExecution() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DeviceCapturePrototype")
        let swiftFiles = [
            "ConfiguratorReset.swift",
            "ContentView.swift",
        ].map { sourceRoot.appendingPathComponent($0) }

        for file in swiftFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains("killall -STOP"), file.lastPathComponent)
            XCTAssertFalse(text.contains("resetUsbd"), file.lastPathComponent)
        }
    }
}

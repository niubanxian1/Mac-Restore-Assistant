import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class ConfiguratorResetTests: XCTestCase {
    private func makeHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cfg-home-\(UUID().uuidString)", isDirectory: true)
        let caches = url.appendingPathComponent("Library/Caches/com.apple.configurator.ui", isDirectory: true)
        let containerCaches = url.appendingPathComponent("Library/Containers/com.apple.configurator.ui/Data/Library/Caches", isDirectory: true)
        let appSupport = url.appendingPathComponent("Library/Containers/com.apple.configurator.ui/Data/Library/Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: containerCaches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try "cache".write(to: caches.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
        try "support".write(to: appSupport.appendingPathComponent("prefs.txt"), atomically: true, encoding: .utf8)
        return url
    }

    func testReopenDoesNotCleanData() throws {
        let home = try makeHome()
        let executor = MockConfiguratorExecutor(running: true)
        let model = ConfiguratorResetModel(
            home: home,
            appURL: URL(fileURLWithPath: "/tmp/FakeConfigurator.app"),
            executor: executor,
            simulationOnly: true)
        XCTAssertEqual(model.cacheTargets.count, 2)
        XCTAssertEqual(model.applicationSupportTargets.count, 1)
        model.performReopen()
        XCTAssertEqual(executor.quitCount, 1)
        XCTAssertEqual(executor.openCount, 1)
        XCTAssertTrue(model.allStepsSucceeded)
        XCTAssertFalse(model.overallMessage.contains("USB 已重置"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/com.apple.configurator.ui/c.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Containers/com.apple.configurator.ui/Data/Library/Application Support/prefs.txt").path))
    }

    func testCleanDefaultKeepsApplicationSupportAndSucceeds() throws {
        let home = try makeHome()
        let executor = MockConfiguratorExecutor(running: true)
        let model = ConfiguratorResetModel(home: home, appURL: URL(fileURLWithPath: "/tmp/FakeConfigurator.app"), executor: executor, simulationOnly: true)
        XCTAssertFalse(model.includeApplicationSupport)
        model.performCleanAndReset()
        XCTAssertTrue(model.allStepsSucceeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/com.apple.configurator.ui").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Containers/com.apple.configurator.ui/Data/Library/Application Support/prefs.txt").path))
        XCTAssertTrue(model.overallMessage.contains("Application Support 未改动") || model.overallMessage.contains("未改动"))
        XCTAssertFalse(model.overallMessage.contains("USB 已重置"))
        XCTAssertTrue(model.stepResults.contains { $0.name == "退出" && $0.succeeded })
        XCTAssertTrue(model.stepResults.contains { $0.name == "清理" && $0.succeeded })
        XCTAssertTrue(model.stepResults.contains { $0.name == "重新打开" && $0.succeeded })
    }

    func testApplicationSupportRequiresExplicitChoiceAndKeepsBackup() throws {
        let home = try makeHome()
        let executor = MockConfiguratorExecutor(running: false)
        let model = ConfiguratorResetModel(home: home, appURL: URL(fileURLWithPath: "/tmp/FakeConfigurator.app"), executor: executor, simulationOnly: true)
        model.includeApplicationSupport = true
        model.performCleanAndReset()
        XCTAssertTrue(model.allStepsSucceeded)
        let support = home.appendingPathComponent("Library/Containers/com.apple.configurator.ui/Data/Library/Application Support/prefs.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.path))
        let backup = try XCTUnwrap(model.lastBackupURL)
        let found = FileManager.default.enumerator(at: backup, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }.map(\.lastPathComponent) ?? []
        XCTAssertTrue(found.contains("prefs.txt"))
    }

    func testFailedQuitIsNotReportedAsAllSuccessAndDoesNotDelete() throws {
        let home = try makeHome()
        let executor = MockConfiguratorExecutor(running: true, quitShouldFail: true)
        let model = ConfiguratorResetModel(home: home, appURL: URL(fileURLWithPath: "/tmp/FakeConfigurator.app"), executor: executor, simulationOnly: true)
        model.performCleanAndReset()
        XCTAssertFalse(model.allStepsSucceeded)
        XCTAssertEqual(executor.openCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/com.apple.configurator.ui/c.txt").path))
        XCTAssertTrue(model.stepResults.contains { $0.name == "退出" && $0.succeeded == false })
        XCTAssertTrue(model.overallMessage.contains("退出步骤失败"))
        XCTAssertFalse(model.overallMessage.contains("已完成") && model.allStepsSucceeded)
    }

    func testPartialOpenFailureIsNotAllSuccess() throws {
        let home = try makeHome()
        let executor = MockConfiguratorExecutor(running: false, openShouldFail: true)
        let model = ConfiguratorResetModel(home: home, appURL: URL(fileURLWithPath: "/tmp/FakeConfigurator.app"), executor: executor, simulationOnly: true)
        model.performCleanAndReset()
        XCTAssertFalse(model.allStepsSucceeded)
        XCTAssertTrue(model.stepResults.contains { $0.name == "清理" && $0.succeeded })
        XCTAssertTrue(model.stepResults.contains { $0.name == "重新打开" && $0.succeeded == false })
        XCTAssertTrue(model.overallMessage.contains("未全部成功") || model.overallMessage.contains("失败"))
        XCTAssertFalse(model.overallMessage.contains("USB 已重置"))
    }

    func testKnownPathsAreExactAndDistinguishCachesFromApplicationSupport() {
        let home = URL(fileURLWithPath: "/tmp/example-home")
        let paths = ConfiguratorKnownLocations.candidatePaths(home: home)
        XCTAssertTrue(paths.allSatisfy { !$0.path.contains("*") })
        XCTAssertTrue(paths.contains { $0.kind == .caches && $0.path.hasSuffix("/Library/Caches/com.apple.configurator.ui") })
        XCTAssertTrue(paths.contains { $0.kind == .applicationSupport && $0.path.contains("Application Support") })
        XCTAssertFalse(paths.contains { $0.path.lowercased().contains("usbd") })
    }

    func testPanelDefaultDoesNotExecuteAndKeepsApplicationSupportOff() throws {
        let home = try makeHome()
        let executor = MockConfiguratorExecutor(running: true)
        let model = ConfiguratorResetModel(home: home, appURL: URL(fileURLWithPath: "/tmp/FakeConfigurator.app"), executor: executor, simulationOnly: true)
        XCTAssertEqual(model.panelChoice, .cleanAndRestart)
        XCTAssertFalse(model.includeApplicationSupport)
        XCTAssertEqual(model.executeButtonTitle, "清理并重启")
        XCTAssertEqual(model.interruptWarning, "重新启动 Configurator 可能中断正在进行的刷机")
        model.includeApplicationSupport = true
        model.panelChoice = .reopenOnly
        model.preparePanelDefaults()
        XCTAssertEqual(model.panelChoice, .cleanAndRestart)
        XCTAssertFalse(model.includeApplicationSupport)
        XCTAssertEqual(executor.quitCount, 0)
        XCTAssertEqual(executor.openCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/com.apple.configurator.ui/c.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Containers/com.apple.configurator.ui/Data/Library/Application Support/prefs.txt").path))
    }

    func testSelectingCleanAndRestartDoesNotAutoEnableApplicationSupport() throws {
        let home = try makeHome()
        let executor = MockConfiguratorExecutor(running: false)
        let model = ConfiguratorResetModel(home: home, appURL: URL(fileURLWithPath: "/tmp/FakeConfigurator.app"), executor: executor, simulationOnly: true)
        model.preparePanelDefaults()
        model.panelChoice = .reopenOnly
        model.panelChoice = .cleanAndRestart
        XCTAssertFalse(model.includeApplicationSupport)
        XCTAssertEqual(model.executeButtonTitle, "清理并重启")
        XCTAssertEqual(executor.quitCount, 0)
        XCTAssertEqual(executor.openCount, 0)
    }

    func testExecuteSelectedCleanAndRestartKeepsApplicationSupportByDefault() throws {
        let home = try makeHome()
        let executor = MockConfiguratorExecutor(running: true)
        let model = ConfiguratorResetModel(home: home, appURL: URL(fileURLWithPath: "/tmp/FakeConfigurator.app"), executor: executor, simulationOnly: true)
        model.preparePanelDefaults()
        XCTAssertEqual(model.panelChoice, .cleanAndRestart)
        XCTAssertFalse(model.includeApplicationSupport)
        model.executeSelectedPanelAction()
        XCTAssertTrue(model.allStepsSucceeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/com.apple.configurator.ui").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Containers/com.apple.configurator.ui/Data/Library/Application Support/prefs.txt").path))
        XCTAssertGreaterThan(executor.quitCount, 0)
        XCTAssertGreaterThan(executor.openCount, 0)
    }

    func testExecuteSelectedReopenOnlyDoesNotCleanCachesOrUserData() throws {
        let home = try makeHome()
        let executor = MockConfiguratorExecutor(running: true)
        let model = ConfiguratorResetModel(home: home, appURL: URL(fileURLWithPath: "/tmp/FakeConfigurator.app"), executor: executor, simulationOnly: true)
        model.preparePanelDefaults()
        model.panelChoice = .reopenOnly
        XCTAssertEqual(model.executeButtonTitle, "重新打开")
        model.executeSelectedPanelAction()
        XCTAssertTrue(model.allStepsSucceeded)
        XCTAssertEqual(executor.quitCount, 1)
        XCTAssertEqual(executor.openCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/com.apple.configurator.ui/c.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Containers/com.apple.configurator.ui/Data/Library/Application Support/prefs.txt").path))
        XCTAssertFalse(model.overallMessage.contains("USB 已重置"))
    }
}

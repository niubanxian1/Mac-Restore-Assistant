import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class ConfiguratorPreferenceTests: XCTestCase {
    private var saved: String?

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.string(forKey: ConfiguratorResetModel.preferenceKey)
        UserDefaults.standard.removeObject(forKey: ConfiguratorResetModel.preferenceKey)
    }

    override func tearDown() {
        if let saved {
            UserDefaults.standard.set(saved, forKey: ConfiguratorResetModel.preferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: ConfiguratorResetModel.preferenceKey)
        }
        super.tearDown()
    }

    private func makeModel(_ executor: MockConfiguratorExecutor) -> ConfiguratorResetModel {
        ConfiguratorResetModel(home: FileManager.default.temporaryDirectory,
                               executor: executor,
                               simulationOnly: true)
    }

    func testDefaultIsCleanAndRestart() {
        XCTAssertEqual(makeModel(MockConfiguratorExecutor()).preferredAction, .cleanAndRestart)
    }

    func testPreferencePersistsAcrossModelInstances() {
        let first = makeModel(MockConfiguratorExecutor())
        first.setPreferredAction(.reopenOnly)
        XCTAssertEqual(UserDefaults.standard.string(forKey: ConfiguratorResetModel.preferenceKey), "reopenOnly")
        XCTAssertEqual(makeModel(MockConfiguratorExecutor()).preferredAction, .reopenOnly)
    }

    func testReopenRunsExactlyOneReopenSequence() {
        let executor = MockConfiguratorExecutor(running: true)
        let model = makeModel(executor)
        model.setPreferredAction(.reopenOnly)
        model.runPreferredAction()
        XCTAssertEqual(executor.quitCount, 1)
        XCTAssertEqual(executor.openCount, 1)
        XCTAssertEqual(executor.frontCount, 1)
    }

    func testCleanRunsExactlyOneCleanSequenceWithoutApplicationSupport() {
        let executor = MockConfiguratorExecutor(running: true)
        let model = makeModel(executor)
        model.setPreferredAction(.cleanAndRestart)
        model.runPreferredAction()
        XCTAssertEqual(executor.quitCount, 1)
        XCTAssertEqual(executor.openCount, 1)
        XCTAssertEqual(executor.frontCount, 1)
        XCTAssertFalse(model.includeApplicationSupport)
    }
}

import XCTest
import MRAHelperProtocol
@testable import MRAHelperCore

final class HelperUnsignedBypassTests: XCTestCase {
    func testProductionSocketIgnoresUnsignedTestEnvironment() {
        let allowed = MRAHelperCore.allowsUnsignedTestBypass(
            environment: ["MRA_HELPER_ALLOW_UNSIGNED_TEST": "1"],
            socketPath: mraHelperSocketPath,
            productionSocketPath: mraHelperSocketPath,
            testingBuild: false)
        XCTAssertFalse(allowed, "production path must not honor unsigned-test bypass")
    }

    func testProductionBuildIgnoresBypassEvenOnATestSocket() {
        let allowed = MRAHelperCore.allowsUnsignedTestBypass(
            environment: ["MRA_HELPER_ALLOW_UNSIGNED_TEST": "1"],
            socketPath: "/tmp/mra-helper-test.sock",
            productionSocketPath: mraHelperSocketPath,
            testingBuild: false)
        XCTAssertFalse(allowed, "a production build must not honor the bypass on any socket")
    }

    func testTestingBuildMayBypassOnlyOnNonProductionSocket() {
        XCTAssertTrue(MRAHelperCore.allowsUnsignedTestBypass(
            environment: ["MRA_HELPER_ALLOW_UNSIGNED_TEST": "1"],
            socketPath: "/tmp/mra-helper-test.sock",
            productionSocketPath: mraHelperSocketPath,
            testingBuild: true))
        XCTAssertFalse(MRAHelperCore.allowsUnsignedTestBypass(
            environment: ["MRA_HELPER_ALLOW_UNSIGNED_TEST": "1"],
            socketPath: mraHelperSocketPath,
            productionSocketPath: mraHelperSocketPath,
            testingBuild: true),
            "even a test build must not bypass auth on the production socket")
        XCTAssertFalse(MRAHelperCore.allowsUnsignedTestBypass(
            environment: [:],
            socketPath: "/tmp/mra-helper-test.sock",
            productionSocketPath: mraHelperSocketPath,
            testingBuild: true),
            "bypass still requires the explicit test environment variable")
    }
}

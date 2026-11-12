import XCTest
import MRAHelperProtocol
@testable import MRAHelperCore

final class HelperSocketAndAuthAcceptanceTests: XCTestCase {
    /// Socket permissions: production desired mode is owner+group only, never world-writable.
    func testDesiredSocketModeIsNotWorldWritable() {
        XCTAssertEqual(MRAHelperCore.desiredSocketPOSIXMode, 0o660)
        XCTAssertEqual(MRAHelperCore.desiredSocketPOSIXMode & 0o007, 0, "other must have no access")
        XCTAssertNotEqual(MRAHelperCore.desiredSocketPOSIXMode, 0o666)
        XCTAssertNotEqual(MRAHelperCore.desiredSocketPOSIXMode, 0o777)
    }

    /// Apply path via MRAHelperCore (temp file, never the installed helper or production socket).
    func testApplySocketPermissionsPathUsesDesiredMode() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("mra022-sock-\(UUID().uuidString).sock").path
        FileManager.default.createFile(atPath: path, contents: Data(), attributes: [
            .posixPermissions: 0o666
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        try MRAHelperCore.applySocketPermissions(path: path)
        let mode = try MRAHelperCore.posixMode(at: path)
        XCTAssertEqual(mode & 0o007, 0, "socket must not be world-accessible, mode=\(String(mode, radix: 8))")
        XCTAssertEqual(mode, 0o660, "expected 0660, got \(String(mode, radix: 8))")
        XCTAssertNotEqual(path, mraHelperSocketPath)
    }

    /// T12 — Production helper path ignores MRA_HELPER_ALLOW_UNSIGNED_TEST.
    func testProductionHelperPathIgnoresUnsignedTestEnvironment() {
        XCTAssertEqual(mraHelperSocketPath, "/var/run/com.mra.devicecontrol.helper.sock")
        let production = MRAHelperCore.allowsUnsignedTestBypass(
            environment: ["MRA_HELPER_ALLOW_UNSIGNED_TEST": "1"],
            socketPath: mraHelperSocketPath,
            productionSocketPath: mraHelperSocketPath,
            testingBuild: false)
        XCTAssertFalse(production, "production path must not honor unsigned-test bypass")

        let productionBuildOnTestSocket = MRAHelperCore.allowsUnsignedTestBypass(
            environment: ["MRA_HELPER_ALLOW_UNSIGNED_TEST": "1"],
            socketPath: "/tmp/mra-helper-acceptance.sock",
            productionSocketPath: mraHelperSocketPath,
            testingBuild: false)
        XCTAssertFalse(productionBuildOnTestSocket, "a production build must not honor the bypass on any socket")

        XCTAssertFalse(MRAHelperCore.allowsUnsignedTestBypass(
            environment: ["MRA_HELPER_ALLOW_UNSIGNED_TEST": "1"],
            socketPath: mraHelperSocketPath,
            productionSocketPath: mraHelperSocketPath,
            testingBuild: true),
            "even a test build must not bypass auth on the production socket")
    }
}

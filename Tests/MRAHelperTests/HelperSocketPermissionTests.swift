import XCTest
@testable import MRAHelperCore

final class HelperSocketPermissionTests: XCTestCase {
    func testDesiredSocketModeIsOwnerAndGroupOnly() {
        XCTAssertEqual(MRAHelperCore.desiredSocketPOSIXMode, 0o660)
        XCTAssertEqual(MRAHelperCore.desiredSocketPOSIXMode & 0o007, 0,
                       "other must have no access")
        XCTAssertNotEqual(MRAHelperCore.desiredSocketPOSIXMode, 0o666)
    }

    func testApplySocketPermissionsDoesNotLeaveWorldWritable() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("mra-helper-sock-test-\(UUID().uuidString).sock").path
        FileManager.default.createFile(atPath: path, contents: Data(), attributes: [
            .posixPermissions: 0o666
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        try MRAHelperCore.applySocketPermissions(path: path)
        let mode = try MRAHelperCore.posixMode(at: path)
        XCTAssertEqual(mode & 0o007, 0, "socket must not be world-accessible, mode=\(String(mode, radix: 8))")
        XCTAssertEqual(mode, 0o660, "expected 0660, got \(String(mode, radix: 8))")
    }
}

import XCTest
import MRAHelperProtocol
@testable import MRAHelperCore

final class HelperTripletDispatchTests: XCTestCase {
    func testBackendArgumentsIncludeControllerPortNumberAndRID() {
        let args = MRAHelperCore.backendArguments(
            action: "dfu", controller: "100000813", portNumber: 2, rid: 1)
        XCTAssertEqual(args, [
            "dfu",
            "--controller", "100000813",
            "--port-number", "2",
            "--rid", "1",
        ])
    }

    func testRebootAndProbeAlsoForwardTheFullTriplet() {
        for action in ["reboot", "probe"] {
            let args = MRAHelperCore.backendArguments(
                action: action, controller: "10000081e", portNumber: 3, rid: 2)
            XCTAssertEqual(args.first, action)
            XCTAssertEqual(args, [
                action,
                "--controller", "10000081e",
                "--port-number", "3",
                "--rid", "2",
            ])
        }
    }

    func testRIDOnlyArgumentListIsRejectedAsInsufficient() {
        let args = MRAHelperCore.backendArguments(
            action: "dfu", controller: "100000813", portNumber: 2, rid: 1)
        XCTAssertFalse(
            args == ["dfu", "--rid", "1"],
            "Helper must not drop controller and PortNumber at the last hop")
    }

    func testStubBackendReceivesFullTriplet() throws {
        let stub = try Self.stubPath()
        let result = MRAHelperCore.runBackend(
            action: "dfu",
            controller: "100000813",
            portNumber: 2,
            rid: 1,
            backendPath: stub)
        XCTAssertEqual(result.0, 0, "stdout=\(result.1) stderr=\(result.2)")
        XCTAssertTrue(result.1.contains("controller=100000813"), result.1)
        XCTAssertTrue(result.1.contains("port-number=2"), result.1)
        XCTAssertTrue(result.1.contains("rid=1"), result.1)
        XCTAssertTrue(result.1.contains("send_performed=false"), result.1)
    }

    func testStubBackendFailClosesWhenSameRIDHasTwoControllers() throws {
        let stub = try Self.stubPath()
        var env = ProcessInfo.processInfo.environment
        env["MRA_STUB_AMBIGUOUS"] = "1"
        let result = Self.runBackendWithEnv(
            action: "dfu",
            controller: "100000813",
            portNumber: 2,
            rid: 1,
            backendPath: stub,
            environment: env)
        XCTAssertNotEqual(result.0, 0)
        let combined = result.1 + result.2
        XCTAssertTrue(combined.contains("RID_SERVICE_AMBIGUOUS"), combined)
        let deniedSend = combined.contains("send_performed=false") || combined.contains("\"send_performed\":false")
        XCTAssertTrue(deniedSend, combined)
        XCTAssertFalse(combined.contains("send_performed=true") || combined.contains("\"send_performed\":true"), combined)
    }

    private static func stubPath() throws -> String {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/stub_direct_rid_dfu.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: here.path), here.path)
        return here.path
    }

    private static func runBackendWithEnv(
        action: String,
        controller: String,
        portNumber: Int,
        rid: Int,
        backendPath: String,
        environment: [String: String]
    ) -> (Int32, String, String) {
        guard FileManager.default.isExecutableFile(atPath: backendPath) else {
            return (-1, "", "BACKEND_MISSING")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: backendPath)
        process.arguments = MRAHelperCore.backendArguments(
            action: action, controller: controller, portNumber: portNumber, rid: rid)
        process.environment = environment
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do { try process.run() } catch { return (-1, "", "BACKEND_SPAWN_FAILED") }
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }
}

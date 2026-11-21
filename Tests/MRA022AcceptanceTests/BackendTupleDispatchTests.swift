import XCTest
@testable import DeviceCapturePrototype
import MRAHelperProtocol
@testable import MRAHelperCore

@MainActor
final class BackendTupleDispatchTests: XCTestCase {
    /// T05 — Helper → backend argv is the full controller / PortNumber / RID triplet.
    func testBackendReceivesControllerPortNumberAndRID() throws {
        let args = MRAHelperCore.backendArguments(
            action: "dfu", controller: "100000813", portNumber: 2, rid: 1)
        XCTAssertEqual(args, [
            "dfu",
            mraBackendControllerFlag, "100000813",
            mraBackendPortNumberFlag, "2",
            mraBackendRIDFlag, "1",
        ])
        XCTAssertEqual(mraBackendControllerFlag, "--controller")
        XCTAssertEqual(mraBackendPortNumberFlag, "--port-number")
        XCTAssertEqual(mraBackendRIDFlag, "--rid")
        XCTAssertNotEqual(args, ["dfu", "--rid", "1"])

        let stub = AcceptanceFixtures.fixture("stub_direct_rid_dfu.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: stub.path), stub.path)
        let result = MRAHelperCore.runBackend(
            action: "dfu", controller: "100000813", portNumber: 2, rid: 1,
            backendPath: stub.path)
        XCTAssertEqual(result.0, 0, "stdout=\(result.1) stderr=\(result.2)")
        XCTAssertTrue(result.1.contains("controller=100000813"), result.1)
        XCTAssertTrue(result.1.contains("port-number=2"), result.1)
        XCTAssertTrue(result.1.contains("rid=1"), result.1)
        XCTAssertTrue(result.1.contains("send_performed=false"), result.1)
    }

    /// T05 — App-level dispatch forwards the same unique triplet to the Helper handler.
    func testAppDispatchForwardsFullTriplet() async throws {
        let port = AcceptanceFixtures.slotS5
        var recorded: [RecordedSend] = []
        let device = AcceptanceModels.makeModel(
            ports: [port], selected: port.id, timeout: 2
        ) { action, controller, portNumber, rid, id in
            recorded.append(RecordedSend(action: action, controller: controller,
                                         portNumber: portNumber, rid: rid,
                                         requestID: id, at: Date()))
            return HelperResponse(requestID: id, ok: true, dispatchTruth: "REQUEST_SENT",
                                  exitCode: 0, reason: "")
        }
        device.performReboot()
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded[0].action, .reboot)
        XCTAssertEqual(recorded[0].controller, port.controller)
        XCTAssertEqual(recorded[0].portNumber, port.portNumber)
        XCTAssertEqual(recorded[0].rid, port.rid)
        XCTAssertFalse(recorded[0].controller.isEmpty)
        XCTAssertGreaterThanOrEqual(recorded[0].portNumber, 0)
        XCTAssertGreaterThanOrEqual(recorded[0].rid, 0)
    }

    /// T05 / T04 companion — incomplete identity is rejected; ambiguous same-RID is fail-closed at the stub.
    func testIncompleteOrAmbiguousTripletIsFailClosed() throws {
        let incomplete = LiveHostPort(controller: "", portNumber: 1, rid: 0)
        let device = AcceptanceModels.makeModel(ports: [incomplete], selected: "")
        XCTAssertFalse(device.isCompleteUniqueTarget(incomplete))
        XCTAssertEqual(device.selectedLiveKey, "")
        device.selectPort(incomplete)
        XCTAssertEqual(device.selectedLiveKey, "")
        XCTAssertFalse(device.portUsable)

        let stub = AcceptanceFixtures.fixture("stub_direct_rid_dfu.sh")
        var env = ProcessInfo.processInfo.environment
        env["MRA_STUB_AMBIGUOUS"] = "1"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: stub.path)
        process.arguments = MRAHelperCore.backendArguments(
            action: "dfu", controller: "100000813", portNumber: 2, rid: 1)
        process.environment = env
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertNotEqual(process.terminationStatus, 0)
        let combined = stdout + stderr
        XCTAssertTrue(combined.contains("RID_SERVICE_AMBIGUOUS"), combined)
        XCTAssertTrue(combined.contains("send_performed=false") || combined.contains("\"send_performed\":false"), combined)
        XCTAssertFalse(combined.contains("send_performed=true") || combined.contains("\"send_performed\":true"), combined)
    }
}

import XCTest

final class InstallerScriptAcceptanceTests: XCTestCase {
    private var sealedRoot: String {
        "/Users/Shared/MRA_DEVICE_CONTROL_RELEASE_0.2.2_20261110T1145Z"
    }

    private func runCase(_ name: String) throws -> ScriptRun {
        let script = AcceptanceFixtures.script("run_script_acceptance.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: script.path), script.path)
        let evidenceDir = ProcessInfo.processInfo.environment["ACCEPTANCE_EVIDENCE_DIR"]
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("mra022-script-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: evidenceDir, withIntermediateDirectories: true)
        let evidenceFile = URL(fileURLWithPath: evidenceDir).appendingPathComponent("\(name).txt").path
        var environment: [String: String] = [
            "WT_ROOT": AcceptanceFixtures.packageRoot.path,
            "FIXTURES_ROOT": AcceptanceFixtures.testsRoot.appendingPathComponent("Fixtures").path,
            "SEALED_ROOT": sealedRoot,
            "EVIDENCE_DIR": evidenceDir,
        ]
        if FileManager.default.fileExists(atPath: AcceptanceFixtures.testsRoot.appendingPathComponent("Fixtures").path) == false,
           let bundled = Bundle.module.resourceURL?.appendingPathComponent("Fixtures") {
            environment["FIXTURES_ROOT"] = bundled.path
        }
        let result = try ScriptHarness.run(
            script: script,
            arguments: [name, evidenceFile],
            environment: environment)
        if result.exitCode != 0 || !result.output.contains("CASE_RESULT=PASS") {
            XCTFail("case \(name) failed (exit \(result.exitCode)):\n\(result.output)")
        }
        return result
    }

    /// T11 RED baseline — pre-minos installer does not emit STOP_QUARANTINED_PACKAGE.
    func testPrefixedInstallerLacksQuarantineAbort() throws {
        let result = try runCase("red-quarantine")
        XCTAssertTrue(result.output.contains("RED_QUARANTINE=YES"), result.output)
        XCTAssertFalse(result.output.contains("STOP_QUARANTINED_PACKAGE"), result.output)
        XCTAssertTrue(result.output.contains("CASE_RESULT=PASS"), result.output)
    }

    /// T11 — Unconfirmed quarantine must not copy or delete system files.
    func testUnconfirmedQuarantineDoesNotCopyOrDeleteSystemFiles() throws {
        let result = try runCase("green-quarantine")
        XCTAssertTrue(result.output.contains("STOP_QUARANTINED_PACKAGE"), result.output)
        XCTAssertTrue(result.output.contains("GREEN_QUARANTINE=YES"), result.output)
        XCTAssertFalse(result.output.contains("INSTALL_OK"), result.output)
        XCTAssertTrue(result.output.contains("OWNER_HELPER_UNCHANGED=YES"), result.output)
    }

    /// T11 — Dry-run with quarantine present also stops and does not copy/delete.
    func testDryRunQuarantineDoesNotCopyOrDeleteSystemFiles() throws {
        let result = try runCase("green-quarantine-dry-run")
        XCTAssertTrue(result.output.contains("STOP_QUARANTINED_PACKAGE"), result.output)
        XCTAssertTrue(result.output.contains("GREEN_QUARANTINE=YES"), result.output)
        XCTAssertFalse(result.output.contains("INSTALL_OK"), result.output)
    }

    /// T13 RED baseline — unsafe uninstall deletes files even when a service may still be live.
    func testUnsafeUninstallDeletesWhileServiceLive() throws {
        let result = try runCase("red-uninstall")
        XCTAssertTrue(result.output.contains("RED_uninstall=YES") || result.output.contains("RED_UNINSTALL=YES") || result.output.contains("RED_uninstall=YES"), result.output)
        XCTAssertTrue(result.output.contains("UNSAFE_UNINSTALL_DELETED") || result.output.contains("RED_uninstall=YES"), result.output)
    }

    /// T13 RED baseline — unsafe rollback deletes files while a service may still be live.
    func testUnsafeRollbackDeletesWhileServiceLive() throws {
        let result = try runCase("red-rollback")
        XCTAssertTrue(result.output.contains("RED_rollback=YES"), result.output)
    }

    /// T13 — Uninstall must not delete files if the service is still live.
    func testUninstallDoesNotDeleteWhenServiceStillLive() throws {
        let result = try runCase("green-uninstall-service")
        XCTAssertTrue(result.output.contains("DELETE_ABORTED_SERVICE_STILL_RUNNING"), result.output)
        XCTAssertTrue(result.output.contains("NO_FILES_DELETED"), result.output)
        XCTAssertTrue(result.output.contains("GREEN_UNINSTALL_service=YES"), result.output)
    }

    /// T13 — Uninstall must not delete files if a helper process is still live.
    func testUninstallDoesNotDeleteWhenProcessStillLive() throws {
        let result = try runCase("green-uninstall-process")
        XCTAssertTrue(result.output.contains("DELETE_ABORTED_PROCESS_STILL_RUNNING"), result.output)
        XCTAssertTrue(result.output.contains("NO_FILES_DELETED"), result.output)
    }

    /// T13 — Uninstall must not delete files if a socket listener is still live.
    func testUninstallDoesNotDeleteWhenSocketStillListening() throws {
        let result = try runCase("green-uninstall-socket")
        XCTAssertTrue(result.output.contains("DELETE_ABORTED_SOCKET_STILL_LISTENING"), result.output)
        XCTAssertTrue(result.output.contains("NO_FILES_DELETED"), result.output)
    }
}

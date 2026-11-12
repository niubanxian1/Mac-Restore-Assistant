import XCTest

final class InstallerScriptAcceptanceTests: XCTestCase {
    private var sealedRoot = ""

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mra-sealed-current-\(UUID().uuidString)")
        let app = root.appendingPathComponent("MRA Device Control Prototype.app")
        let contents = app.appendingPathComponent("Contents")
        let resources = contents.appendingPathComponent("Resources")
        let macos = contents.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let packageRoot = AcceptanceFixtures.packageRoot
        try copy(packageRoot.appendingPathComponent(".build/debug/DeviceCapturePrototype"),
                 to: macos.appendingPathComponent("DeviceCapturePrototype"))
        try copy(packageRoot.appendingPathComponent("Info.plist"),
                 to: contents.appendingPathComponent("Info.plist"))
        try copy(packageRoot.appendingPathComponent("Resources/mra-helper"),
                 to: resources.appendingPathComponent("mra-helper"))
        try copy(packageRoot.appendingPathComponent("Resources/direct_rid_dfu"),
                 to: resources.appendingPathComponent("direct_rid_dfu"))
        try copy(packageRoot.appendingPathComponent("com.mra.devicecontrol.helper.plist"),
                 to: root.appendingPathComponent("com.mra.devicecontrol.helper.plist"))
        sealedRoot = root.path
    }

    override func tearDownWithError() throws {
        if !sealedRoot.isEmpty {
            try? FileManager.default.removeItem(atPath: sealedRoot)
        }
    }

    private func copy(_ source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw NSError(domain: "InstallerScriptAcceptanceTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "missing fixture: \(source.path)"])
        }
        try FileManager.default.copyItem(at: source, to: destination)
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

    func testT1205ZCanBeUpgradedOffline() throws {
        let result = try runCase("green-install-t1205z-dry-run")
        XCTAssertTrue(result.output.contains("EXISTING_INSTALL=KNOWN"), result.output)
        XCTAssertTrue(result.output.contains("DRY_RUN_OK"), result.output)
        XCTAssertFalse(result.output.contains("STOP_UNKNOWN_VERSION"), result.output)
    }

    func testT1205ZCanBeUninstalledOffline() throws {
        let result = try runCase("green-uninstall-t1205z-dry-run")
        XCTAssertTrue(result.output.contains("DRY_RUN_OK"), result.output)
        XCTAssertFalse(result.output.contains("STOP_UNKNOWN_VERSION"), result.output)
    }

    func testT1306ZCanBeUpgradedOffline() throws {
        let result = try runCase("green-install-t1306z-dry-run")
        XCTAssertTrue(result.output.contains("EXISTING_INSTALL=KNOWN"), result.output)
        XCTAssertTrue(result.output.contains("DRY_RUN_OK"), result.output)
        XCTAssertFalse(result.output.contains("STOP_UNKNOWN_VERSION"), result.output)
    }

    func testT1306ZCanBeUninstalledOffline() throws {
        let result = try runCase("green-uninstall-t1306z-dry-run")
        XCTAssertTrue(result.output.contains("DRY_RUN_OK"), result.output)
        XCTAssertFalse(result.output.contains("STOP_UNKNOWN_VERSION"), result.output)
    }

    func testSuccessfulUninstallRemovesStaleSocket() throws {
        let result = try runCase("green-uninstall-stale-socket")
        XCTAssertTrue(result.output.contains("STALE_SOCKET_REMOVED"), result.output)
        XCTAssertTrue(result.output.contains("UNINSTALL_OK"), result.output)
        XCTAssertFalse(result.output.contains("REMAINS_SOCKET"), result.output)
    }

    func testInstallerDryRunWorksWithoutVtool() throws {
        let result = try runCase("green-install-no-vtool-dry-run")
        XCTAssertTrue(result.output.contains("MINOS_CONSISTENT=YES"), result.output)
        XCTAssertTrue(result.output.contains("DRY_RUN_OK"), result.output)
        XCTAssertFalse(result.output.contains("could not read minos"), result.output)
    }

    func testReadOnlyQuarantinedAppStagesPayloadInsteadOfChangingSource() throws {
        let result = try runCase("green-quarantine-stage-fallback")
        XCTAssertTrue(result.output.contains("QUARANTINE_STAGED_PAYLOAD=YES"), result.output)
        XCTAssertTrue(result.output.contains("QUARANTINE_CLEARED=YES"), result.output)
        XCTAssertTrue(result.output.contains("STAGED_PAYLOAD_VERIFIED=YES"), result.output)
        XCTAssertTrue(result.output.contains("SOURCE_APP_UNCHANGED=YES"), result.output)
        XCTAssertFalse(result.output.contains("failed to clear quarantine on"), result.output)
    }

    func testMissingDestinationDirectoriesAreCreated() throws {
        let result = try runCase("green-missing-destination-directories")
        XCTAssertTrue(result.output.contains("DESTINATION_DIRECTORIES_READY=YES"), result.output)
        XCTAssertFalse(result.output.contains("No such file or directory"), result.output)
    }
}

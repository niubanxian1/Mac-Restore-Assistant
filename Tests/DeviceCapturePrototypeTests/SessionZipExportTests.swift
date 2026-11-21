import XCTest
@testable import DeviceCapturePrototype
import MRAHelperProtocol
import RestoreLogEngine

@MainActor
final class SessionZipExportTests: XCTestCase {
    private func waitUntil(_ timeout: TimeInterval = 8, _ predicate: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func testSingleZipIntegrityAndNoSidecarLog() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("zip-exp-\(UUID().uuidString)", isDirectory: true)
        let out = base.appendingPathComponent("out", isDirectory: true)
        let sessions = base.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let capture = CaptureModel(root: sessions, backendMode: .simulated)
        capture.appCDHashProvider = { "abcd1234testcdhash" }
        capture.appVersionOverride = "0.2.3"
        capture.start()
        await waitUntil { capture.state == .recording }
        capture.stop()
        await waitUntil { capture.canSave }
        capture.save(folder: out, baseName: "M2-Air-Test")
        await waitUntil { capture.savedZipURL != nil || capture.saveMessage.contains("失败") }
        let zip = try XCTUnwrap(capture.savedZipURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.appendingPathComponent("M2-Air-Test.log").path),
                       "must not write a sidecar .log")
        XCTAssertEqual(capture.lastExportManifest?.exporterAppCDHash, "abcd1234testcdhash")
        XCTAssertEqual(capture.lastExportManifest?.appVersion, "0.2.3")

        var stats = ZipIOStats()
        let entries = try ZipStoreReader.listEntries(archive: zip, stats: &stats, hashContents: true)
        let names = Set(entries.map(\.pathInZip))
        XCTAssertTrue(names.contains("MANIFEST.json"))
        XCTAssertTrue(names.contains("README.txt"))
        XCTAssertTrue(names.contains("logs/restore.log"))
        XCTAssertTrue(names.contains("evidence/raw-log-pointer.json"))
        let rawCopies = entries.filter { $0.pathInZip.hasSuffix("restore.log") || $0.pathInZip.hasSuffix("restore.log") }
        XCTAssertEqual(entries.filter { $0.pathInZip.hasSuffix("restore.log") }.count, 1)

        let raw = entries.first { $0.pathInZip == "logs/restore.log" }!
        let pointer = entries.first { $0.pathInZip == "evidence/raw-log-pointer.json" }!
        XCTAssertTrue(String(data: try unzipBytes(zip, "evidence/raw-log-pointer.json"), encoding: .utf8)?.contains(raw.sha256) == true)
        let manifestData = try unzipBytes(zip, "MANIFEST.json")
        let manifest = try JSONDecoder().decode(SessionZipManifest.self, from: manifestData)
        XCTAssertFalse(manifest.files.contains(where: { $0.relativePath == "MANIFEST.json" }))
        let listedRaw = manifest.files.first { $0.relativePath == "logs/restore.log" }
        XCTAssertEqual(listedRaw?.sha256, raw.sha256)
        XCTAssertEqual(listedRaw?.size, raw.size)
        XCTAssertEqual(listedRaw?.role, "raw-log")
        XCTAssertNotNil(manifest.files.first { $0.relativePath == "README.txt" })
        if let stats = capture.lastExportStats {
            XCTAssertEqual(stats.archiveWritePasses, 1)
            XCTAssertGreaterThan(stats.sourceReadPasses, 0)
            XCTAssertGreaterThan(stats.verifyReadPasses, 0)
            XCTAssertGreaterThan(stats.sourceBytesRead, 0)
        }

        capture.save(folder: out, baseName: "M2-Air-Test")
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(capture.saveMessage.contains("已存在"), capture.saveMessage)
        _ = pointer
        _ = rawCopies
        _ = names
    }

    func testCancelCleansTempAndFailureLeavesNoHalfZip() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("zip-cancel-\(UUID().uuidString)", isDirectory: true)
        let out = base.appendingPathComponent("out", isDirectory: true)
        let sessions = base.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let capture = CaptureModel(root: sessions, backendMode: .simulated)
        capture.appCDHashProvider = { "test" }
        capture.start()
        await waitUntil { capture.state == .recording }
        capture.stop()
        await waitUntil { capture.canSave }
        capture.packageBuildOverride = { _, dest, _ in
            throw SessionZipExportError.failed("simulated failure")
        }
        capture.save(folder: out, baseName: "Broken")
        await waitUntil(8) { capture.saveMessage.contains("失败") || capture.saveMessage.contains("simulated") }
        XCTAssertNil(capture.savedZipURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.appendingPathComponent("Broken.zip").path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: out.path)
        XCTAssertFalse(leftovers.contains { $0.hasSuffix(".zip") || $0.contains(".tmp") }, leftovers.joined(separator: ","))
        XCTAssertTrue(capture.canSave)
    }

    func testCopyZipUsesFileURL() {
        let pasteboard = MockFilePasteboard()
        let capture = CaptureModel(root: FileManager.default.temporaryDirectory.appendingPathComponent("x-\(UUID().uuidString)"), backendMode: .simulated)
        capture.pasteboard = pasteboard
        let zip = FileManager.default.temporaryDirectory.appendingPathComponent("copy-\(UUID().uuidString).zip")
        FileManager.default.createFile(atPath: zip.path, contents: Data("z".utf8))
        capture.savedZipURL = zip
        capture.copySavedZip()
        XCTAssertEqual(pasteboard.copied, [zip])
        pasteboard.shouldFail = true
        capture.copySavedZip()
        XCTAssertTrue(capture.saveMessage.contains("复制失败"))
        XCTAssertEqual(capture.savedZipURL, zip)
    }

    func testZip64ThresholdProducesReadableArchive() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zip64-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("big.bin")
        // 2 MiB payload with a 1 MiB ZIP64 threshold to exercise ZIP64 headers without a 4 GiB file.
        let payload = Data(repeating: 0x5A, count: 2 * 1024 * 1024)
        try payload.write(to: source)
        let dest = dir.appendingPathComponent("out.zip")
        let writer = ZipStoreWriter(zip64Threshold: 1 * 1024 * 1024)
        let start = Date()
        let written = try writer.write(entries: [
            ZipEntrySpec(pathInZip: "logs/restore.log", fileURL: source, data: nil, storedSHA256: nil),
            ZipEntrySpec(pathInZip: "README.txt", fileURL: nil, data: Data("hi".utf8), storedSHA256: nil),
        ], to: dest)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(written.first { $0.pathInZip == "logs/restore.log" }?.size, Int64(payload.count))
        XCTAssertEqual(writer.stats.archiveWritePasses, 1)
        XCTAssertEqual(writer.stats.sourceBytesRead, Int64(payload.count) + 0) // file only in source read; README is also counted
        var stats = ZipIOStats()
        let listed = try ZipStoreReader.listEntries(archive: dest, stats: &stats, hashContents: true)
        XCTAssertEqual(listed.first { $0.pathInZip == "logs/restore.log" }?.sha256,
                       written.first { $0.pathInZip == "logs/restore.log" }?.sha256)
        XCTAssertGreaterThan(stats.verifyBytesRead, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("restore.log").path),
                       "verification must not spill a second log onto disk")
        // Record fixture stats for the report.
        let record = dir.appendingPathComponent("STAT.txt")
        let text = "fixture_bytes=\(payload.count)\nelapsed_s=\(elapsed)\nsource_bytes_read=\(writer.stats.sourceBytesRead)\ndisk_bytes_written=\(writer.stats.diskBytesWritten)\nverify_bytes_read=\(writer.stats.verifyBytesRead)\nsource_read_passes=\(writer.stats.sourceReadPasses)\narchive_write_passes=\(writer.stats.archiveWritePasses)\nverify_read_passes=\(writer.stats.verifyReadPasses)\nzip64_threshold=1048576\n"
        try text.write(to: record, atomically: true, encoding: .utf8)
        print(text)
    }

    func testWriteDeliverySampleZipIfRequested() async throws {
        guard let destDir = ProcessInfo.processInfo.environment["MRA_SAMPLE_ZIP_DIR"], !destDir.isEmpty else {
            return
        }
        let cdhash = ProcessInfo.processInfo.environment["MRA_SAMPLE_APP_CDHASH"] ?? "UNVERIFIED"
        XCTAssertNotEqual(cdhash, "UNVERIFIED")
        XCTAssertNotEqual(cdhash, "abcd1234testcdhash")
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("zip-sample-\(UUID().uuidString)", isDirectory: true)
        let out = URL(fileURLWithPath: destDir, isDirectory: true)
        let sessions = base.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let capture = CaptureModel(root: sessions, backendMode: .simulated)
        capture.appCDHashProvider = { cdhash }
        capture.appVersionOverride = "0.2.3"
        capture.start()
        await waitUntil { capture.state == .recording }
        capture.stop()
        await waitUntil { capture.canSave }
        capture.save(folder: out, baseName: "MRA-0.2.3-sample")
        await waitUntil { capture.savedZipURL != nil || capture.saveMessage.contains("失败") }
        let zip = try XCTUnwrap(capture.savedZipURL)
        XCTAssertEqual(capture.lastExportManifest?.exporterAppCDHash, cdhash)
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.appendingPathComponent("MRA-0.2.3-sample.log").path))
        if let stats = capture.lastExportStats {
            let text = "fixture=simulated-session\n" +
                "source_bytes_read=\(stats.sourceBytesRead)\n" +
                "disk_bytes_written=\(stats.diskBytesWritten)\n" +
                "verify_bytes_read=\(stats.verifyBytesRead)\n" +
                "source_read_passes=\(stats.sourceReadPasses)\n" +
                "archive_write_passes=\(stats.archiveWritePasses)\n" +
                "verify_read_passes=\(stats.verifyReadPasses)\n" +
                "exporterAppCDHash=\(cdhash)\n" +
                "zip=\(zip.path)\n"
            try text.write(to: out.appendingPathComponent("SAMPLE_EXPORT_STATS.txt"), atomically: true, encoding: .utf8)
        }
    }


    func testT519PreserveFinalizedLogThenExport() async throws {
        guard let destDir = ProcessInfo.processInfo.environment["MRA_T519_ZIP_DIR"], !destDir.isEmpty else {
            return
        }
        let cdhash = ProcessInfo.processInfo.environment["MRA_SAMPLE_APP_CDHASH"] ?? "2ad087246a95b91a9fee0abe32201f4934d098d4"
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("t519-\(UUID().uuidString)", isDirectory: true)
        let out = URL(fileURLWithPath: destDir, isDirectory: true)
        let sessions = base.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let capture = CaptureModel(root: sessions, backendMode: .simulated)
        capture.appCDHashProvider = { cdhash }
        capture.appVersionOverride = "0.2.3"
        capture.start()
        await waitUntil { capture.state == .recording }
        capture.stop()
        await waitUntil { capture.canSave }
        capture.save(folder: out, baseName: "T519-independent")
        await waitUntil { capture.savedZipURL != nil || capture.saveMessage.contains("失败") }
        let zip = try XCTUnwrap(capture.savedZipURL)
        // After finalize+export, the session workspace still holds the finalized raw log.
        let hint = capture.sessionFolderHint
        XCTAssertNotEqual(hint, "尚无采集会话")
        let sessionDir = URL(fileURLWithPath: hint, isDirectory: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: sessionDir.path)
        let rawName = names.first(where: { $0 == "restore.log" || $0.hasSuffix("/restore.log") }) ?? names.first(where: { $0.hasSuffix(".log") && $0.contains("restore") })
        XCTAssertNotNil(rawName, "session workspace listing: \(names.joined(separator: ","))")
        let raw = sessionDir.appendingPathComponent(rawName!)
        let copy = out.appendingPathComponent("finalized-session-restore.log")
        try FileManager.default.copyItem(at: raw, to: copy)
        try names.sorted().joined(separator: "\n").write(to: out.appendingPathComponent("session-workspace-listing.txt"), atomically: true, encoding: .utf8)
        try hint.write(to: out.appendingPathComponent("session-dir.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
    }

    private func unzipBytes(_ zip: URL, _ path: String) throws -> Data {
        var stats = ZipIOStats()
        // Use unzip -p for convenience in tests of small files.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", zip.path, path]
        let out = Pipe(); process.standardOutput = out; process.standardError = Pipe()
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "unzip \(path)")
        _ = stats
        return out.fileHandleForReading.readDataToEndOfFile()
    }
}

@MainActor
final class SendPathRegressionTests: XCTestCase {
    func testDFUAndRebootDoNotDependOnHistoryOrEnvironment() async throws {
        let port = LiveHostPort(controller: "AppleHPMDevice", portNumber: 1, rid: 0)
        let custom = [PortCalibrationEntry(physicalPort: "left1", location: "01200000", label: "左侧上方",
                                           rid: "0", side: "左侧", controller: port.controller, portNumber: 1)]
        let layout = BuiltInLayout(displayName: "t", sourceFile: "t", slots: [
            BuiltInSlot(slot: "S3", face: "LEFT", portNumber: 1, rid: 0, binding: "x", physicalName: "左侧上方")
        ], partial: false, skippedSlots: [], generatedAt: "t")
        let doc = CalibrationDocument(models: [], ports: custom, selectedPort: port.id)
        let store = CalibrationStore(testingDocument: doc, hostModel: "MacBookPro18,2", builtInLayout: layout)
        var actions: [HelperAction] = []
        let model = DeviceControlModel(
            calibration: store, livePorts: [port], helperAvailable: true,
            sequenceDelaySeconds: 0.01, persistPortSelection: false, startLiveWork: false,
            requestHandler: { action, controller, portNumber, rid, requestID in
                actions.append(action)
                XCTAssertEqual(controller, "AppleHPMDevice")
                XCTAssertEqual(portNumber, 1)
                XCTAssertEqual(rid, 0)
                return HelperResponse(requestID: requestID, ok: true, dispatchTruth: "REQUEST_SENT", exitCode: 0, reason: "")
            })
        // History missing, no device enumerated, helper-environment unread: send still allowed.
        XCTAssertTrue(model.canControl)
        XCTAssertEqual(model.deviceStatusText(for: port), "无设备")
        model.performReboot()
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(actions, [.reboot])
        model.performDFU()
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertGreaterThanOrEqual(actions.filter { $0 == .dfu }.count, 1)
        XCTAssertTrue(model.disabledReason.isEmpty || model.actionInFlight || !model.canControl)
    }

    func testDFUButtonSendsBothAttemptsToFrozenPortWhenTargetDisappearsAndReturns() async throws {
        let port = LiveHostPort(controller: "100000760", portNumber: 2, rid: 1)
        let custom = [PortCalibrationEntry(physicalPort: "left2", location: "01100000", label: "左侧下方",
                                           rid: "1", side: "左侧", controller: port.controller, portNumber: 2)]
        let layout = BuiltInLayout(displayName: "t", sourceFile: "t", slots: [
            BuiltInSlot(slot: "S4", face: "LEFT", portNumber: 2, rid: 1, binding: "x", physicalName: "左侧下方")
        ], partial: false, skippedSlots: [], generatedAt: "t")
        let doc = CalibrationDocument(models: [], ports: custom, selectedPort: port.id)
        let store = CalibrationStore(testingDocument: doc, hostModel: "MacBookPro18,2", builtInLayout: layout)
        var calls: [(id: String, action: HelperAction, controller: String, port: Int, rid: Int)] = []
        var device: DeviceControlModel!
        device = DeviceControlModel(
            calibration: store, livePorts: [port], helperAvailable: true,
            sequenceDelaySeconds: 0.2, persistPortSelection: false, startLiveWork: false,
            requestHandler: { action, controller, portNumber, rid, requestID in
                calls.append((requestID, action, controller, portNumber, rid))
                if calls.count == 1 {
                    // The target vanishes immediately after the first attempt.
                    device.applyObservedDevices([])
                    device.applyDiscoveredPorts([port], persistCalibration: false)
                    return HelperResponse(requestID: requestID, ok: false,
                                          dispatchTruth: "NOT_DISPATCHED", exitCode: 1,
                                          reason: "BACKEND_FAILED", stdout: "", stderr: "")
                }
                // Still the same physical port; target identity remains absent.
                XCTAssertEqual(device.selectedLiveKey, port.id)
                XCTAssertNil(device.observedDevice(for: port))
                return HelperResponse(requestID: requestID, ok: true,
                                      dispatchTruth: "REQUEST_SENT", exitCode: 0, reason: "")
            })
        XCTAssertTrue(device.canControl, "Helper + unique physical port is enough; no Mac/ECID/mode")
        XCTAssertNil(device.observedDevice(for: port))
        XCTAssertEqual(device.orderedDisplayPorts.count, 1)
        device.performDFU()
        try? await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(calls.count, 2, "exactly two DFU attempts")
        XCTAssertEqual(Set(calls.map(\.id)).count, 2, "two distinct requestIDs")
        XCTAssertTrue(calls.allSatisfy { $0.action == .dfu })
        XCTAssertTrue(calls.allSatisfy { $0.controller == port.controller && $0.port == port.portNumber && $0.rid == port.rid },
                      "both attempts must stay on the clicked physical port")
        XCTAssertEqual(device.feedback.title, "后端确认提交 · 结果未确认")
        XCTAssertTrue(device.lastActionLog.contains("attempted=true"))
        XCTAssertTrue(device.lastActionLog.contains("backend_called=true"))
        XCTAssertFalse(device.lastActionLog.contains("未成功发送"))
    }
}

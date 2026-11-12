import XCTest
@testable import DeviceCapturePrototype
import RestoreLogEngine

@MainActor
final class CaptureSaveTests: XCTestCase {
    private func waitUntil(_ timeout: TimeInterval = 8, _ predicate: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func testManualCaptureDualSaveAndDuplicateName() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("MRA-prototype-test-\(UUID().uuidString)", isDirectory: true)
        let out = base.appendingPathComponent("out", isDirectory: true)
        let sessions = base.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

        let capture = CaptureModel(root: sessions, backendMode: .simulated)
        capture.start()
        await waitUntil { capture.state == .recording }
        XCTAssertEqual(capture.state, .recording, capture.captureError)

        capture.stop()
        await waitUntil { capture.canSave }
        XCTAssertTrue(capture.canSave, capture.captureError)

        capture.appCDHashProvider = { "test-cdhash" }
        capture.appVersionOverride = "0.2.3"
        capture.save(folder: out, baseName: "M2-Air-Test")
        await waitUntil { capture.savedZipURL != nil || capture.saveMessage.contains("失败") }
        XCTAssertNotNil(capture.savedZipURL)
        XCTAssertNil(capture.savedLogURL)

        let zip = try XCTUnwrap(capture.savedZipURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.appendingPathComponent("M2-Air-Test.log").path))

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-p", zip.path, "logs/restore.log"]
        let pipe = Pipe()
        unzip.standardOutput = pipe
        unzip.standardError = Pipe()
        try unzip.run()
        unzip.waitUntilExit()
        XCTAssertEqual(unzip.terminationStatus, 0)
        let zipRaw = pipe.fileHandleForReading.readDataToEndOfFile()
        XCTAssertFalse(zipRaw.isEmpty)
        let listed = capture.lastExportManifest?.files.first { $0.relativePath == "logs/restore.log" }
        XCTAssertEqual(listed?.sha256, capture.lastExportStats != nil ? listed?.sha256 : listed?.sha256)
        XCTAssertEqual(Int(listed?.size ?? 0), zipRaw.count, "清单中的原始日志大小必须与包内 logs/restore.log 一致")

        capture.save(folder: out, baseName: "M2-Air-Test")
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(capture.saveMessage.contains("已存在"), capture.saveMessage)
    }

    func testCancelKeepsFinalizedSessionRetryable() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("MRA-prototype-cancel-\(UUID().uuidString)", isDirectory: true)
        let sessions = base.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let capture = CaptureModel(root: sessions, backendMode: .simulated)
        capture.start()
        await waitUntil { capture.state == .recording }
        capture.stop()
        await waitUntil { capture.canSave }
        XCTAssertTrue(capture.canSave)
        // Opening and cancelling a sheet does not discard the session.
        capture.openSaveSheet()
        XCTAssertTrue(capture.saveSheetRequested)
        XCTAssertTrue(capture.canSave)
        XCTAssertEqual(capture.savedZipURL, nil)
    }
}

@MainActor
final class PartialSaveTests: XCTestCase {
    func testPackageFailureStillReportsRawSuccess() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("MRA-prototype-partial-\(UUID().uuidString)", isDirectory: true)
        let out = base.appendingPathComponent("out", isDirectory: true)
        let sessions = base.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let capture = CaptureModel(root: sessions, backendMode: .simulated)
        capture.start()
        let deadline = Date().addingTimeInterval(8)
        while capture.state != .recording && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        capture.stop()
        let stopDeadline = Date().addingTimeInterval(8)
        while !capture.canSave && Date() < stopDeadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        capture.packageBuildOverride = { _, _, _ in
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "simulated package failure"])
        }
        capture.save(folder: out, baseName: "Partial")
        let saveDeadline = Date().addingTimeInterval(8)
        while capture.savedZipURL == nil && !capture.saveMessage.contains("失败") && Date() < saveDeadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertNil(capture.savedZipURL)
        XCTAssertNil(capture.savedLogURL)
        XCTAssertTrue(capture.saveMessage.contains("失败") || capture.saveMessage.contains("证据包"), capture.saveMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.appendingPathComponent("Partial.zip").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.appendingPathComponent("Partial.log").path))
        XCTAssertTrue(capture.canSave)
    }
}

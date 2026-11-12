import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class T544DiscardCaptureTests: XCTestCase {
    private func waitUntil(_ timeout: TimeInterval = 8, _ predicate: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func isolatedRoots() throws -> (base: URL, sessions: URL, kept: URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("MRA-t544-\(UUID().uuidString)", isDirectory: true)
        let sessions = base.appendingPathComponent("sessions", isDirectory: true)
        let kept = base.appendingPathComponent("kept", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
        return (base, sessions, kept)
    }

    func testDiscardButtonDisabledWhenIdle() {
        let capture = CaptureModel(root: FileManager.default.temporaryDirectory.appendingPathComponent("t544-idle-\(UUID().uuidString)", isDirectory: true), backendMode: .simulated)
        XCTAssertFalse(capture.isCapturing)
        XCTAssertFalse(capture.canDiscardUnsavedSession)
        XCTAssertEqual(capture.discardButtonTitle, "作废本次日志")
    }

    func testStartThenDiscardStopsBackendRemovesTempAndAllowsNewStart() async throws {
        let roots = try isolatedRoots()
        let sibling = roots.kept.appendingPathComponent("already-saved.zip")
        try Data("saved-zip".utf8).write(to: sibling)
        let otherSession = roots.sessions.appendingPathComponent("other-session.partial", isDirectory: true)
        try FileManager.default.createDirectory(at: otherSession, withIntermediateDirectories: true)
        let marker = otherSession.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: marker)

        let capture = CaptureModel(root: roots.sessions, backendMode: .simulated)
        XCTAssertFalse(capture.canDiscardUnsavedSession)
        capture.start()
        await waitUntil { capture.state == .recording }
        XCTAssertEqual(capture.state, .recording, capture.captureError)
        XCTAssertTrue(capture.canDiscardUnsavedSession)
        XCTAssertEqual(capture.discardButtonTitle, "作废并停止")
        let sessionDir = try XCTUnwrap(capture.currentSessionDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionDir.path))
        XCTAssertNotEqual(sessionDir.lastPathComponent, otherSession.lastPathComponent)
        let bytesWhileRecording = capture.byteCount

        capture.discardUnsavedSession()
        XCTAssertEqual(capture.state, .stopping)
        await waitUntil(12) { capture.saveMessage == "本次日志已作废，采集已停止" || !capture.captureError.isEmpty }

        XCTAssertEqual(capture.saveMessage, "本次日志已作废，采集已停止", capture.captureError)
        XCTAssertTrue(capture.captureError.isEmpty)
        XCTAssertEqual(capture.state, .idle)
        XCTAssertFalse(capture.isCapturing)
        XCTAssertEqual(capture.byteCount, 0)
        XCTAssertEqual(capture.durationText, "0秒")
        XCTAssertFalse(capture.canDiscardUnsavedSession)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionDir.path), "本次临时会话目录应已删除")
        let bytesAfter = capture.byteCount
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(capture.byteCount, bytesAfter, "作废后字节数不得再增长")
        XCTAssertEqual(capture.state, .idle)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path), "不得删除已保存的 ZIP")
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "不得删除其他会话")

        capture.start()
        await waitUntil { capture.state == .recording }
        XCTAssertEqual(capture.state, .recording, capture.captureError)
        let newDir = try XCTUnwrap(capture.currentSessionDirectory)
        XCTAssertNotEqual(newDir.path, sessionDir.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newDir.path))
        capture.stop()
        await waitUntil { capture.canSave }
        XCTAssertTrue(capture.canSave)
        XCTAssertEqual(capture.discardButtonTitle, "作废本次日志")
        XCTAssertTrue(capture.canDiscardUnsavedSession)
        _ = bytesWhileRecording
    }

    func testDiscardAfterStopCleansUnexportedSession() async throws {
        let roots = try isolatedRoots()
        let capture = CaptureModel(root: roots.sessions, backendMode: .simulated)
        capture.start()
        await waitUntil { capture.state == .recording }
        capture.stop()
        await waitUntil { capture.canSave }
        XCTAssertTrue(capture.canSave)
        XCTAssertEqual(capture.discardButtonTitle, "作废本次日志")
        let sessionDir = try XCTUnwrap(capture.currentSessionDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionDir.path))
        capture.discardUnsavedSession()
        await waitUntil(12) { capture.saveMessage == "本次日志已作废，采集已停止" || !capture.captureError.isEmpty }
        XCTAssertEqual(capture.saveMessage, "本次日志已作废，采集已停止", capture.captureError)
        XCTAssertEqual(capture.state, .idle)
        XCTAssertEqual(capture.byteCount, 0)
        XCTAssertEqual(capture.durationText, "0秒")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionDir.path))
    }

    func testDiscardDisabledDuringExport() async throws {
        let roots = try isolatedRoots()
        let capture = CaptureModel(root: roots.sessions, backendMode: .simulated)
        capture.start()
        await waitUntil { capture.state == .recording }
        capture.stop()
        await waitUntil { capture.canSave }
        capture.isExporting = true
        XCTAssertFalse(capture.canDiscardUnsavedSession)
        capture.isExporting = false
        XCTAssertTrue(capture.canDiscardUnsavedSession)
        capture.appCDHashProvider = { "test-cdhash" }
        capture.appVersionOverride = "0.2.3"
        capture.save(folder: roots.kept, baseName: "KeepMe")
        await waitUntil { capture.savedZipURL != nil || capture.saveMessage.contains("失败") }
        let zip = try XCTUnwrap(capture.savedZipURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path))
        XCTAssertFalse(capture.canDiscardUnsavedSession)
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path))
    }
}

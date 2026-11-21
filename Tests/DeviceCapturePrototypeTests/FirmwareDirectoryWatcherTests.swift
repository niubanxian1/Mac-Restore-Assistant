import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class FirmwareDirectoryWatcherTests: XCTestCase {
    func testDirectoryWriteTriggersDebouncedCallback() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FW-Watcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let watcher = FirmwareDirectoryWatcher()
        let expectation = expectation(description: "directory event")
        watcher.onChange = { expectation.fulfill() }
        watcher.update(roots: [root])
        try Data("new".utf8).write(to: root.appendingPathComponent("new.ipsw"))
        await fulfillment(of: [expectation], timeout: 4)
        watcher.stop()
    }
}

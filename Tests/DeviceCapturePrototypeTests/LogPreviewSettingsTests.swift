import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class LogPreviewSettingsTests: XCTestCase {
    func testDefaultsOffAndDoesNotInheritHiddenFilter() {
        let suite = UserDefaults(suiteName: "mra-preview-\(UUID().uuidString)")!
        suite.removePersistentDomain(forName: suite.dictionaryRepresentation().keys.isEmpty
                                    ? "mra-preview-empty" : "mra-preview-\(UUID().uuidString)")
        // Fresh suite has no keys.
        let fresh = UserDefaults(suiteName: "mra-preview-fresh-\(UUID().uuidString)")!
        let settings = LogPreviewSettings(defaults: fresh)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(settings.effectiveScope, .all)
        settings.isEnabled = true
        settings.scope = .unbound
        XCTAssertEqual(settings.effectiveScope, .unbound)
        settings.isEnabled = false
        XCTAssertEqual(settings.effectiveScope, .all)
        XCTAssertEqual(settings.scope, .all)
    }

    func testBoundedTailDoesNotLoadWholeFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString).log")
        var text = ""
        for i in 0..<5000 {
            text += "LINE-\(i)-\(String(repeating: "x", count: 80))\n"
        }
        try text.data(using: .utf8)!.write(to: url)
        let snap = LogPreviewReader.tail(url: url, maxBytes: 8 * 1024, maxLines: 200)
        XCTAssertTrue(snap.truncated)
        XCTAssertLessThanOrEqual(snap.lines.count, 200)
        XCTAssertTrue(snap.lines.last?.contains("LINE-4999") == true)
        XCTAssertFalse(snap.lines.contains(where: { $0.contains("LINE-0-") }))
    }
}

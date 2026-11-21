import XCTest
@testable import DeviceCapturePrototype

final class RLMLogSlimTests: XCTestCase {
    func testClassifierIsKeywordOnlyAndGroupsClues() {
        let lines = [
            "normal boot line",
            "DCP error: link training failed",
            "NAND timeout while probing",
            "SEP panic: fault",
            "unrelated message"
        ]
        let summary = LogErrorClueClassifier.summarize(lines)
        XCTAssertEqual(summary.hitCount, 3)
        XCTAssertTrue(summary.groups.contains { $0.title == "HDMI/DCP/Retimer" && $0.count == 1 })
        XCTAssertTrue(summary.groups.contains { $0.title == "NAND/NVMe" && $0.count == 1 })
        XCTAssertTrue(summary.groups.contains { $0.title == "SEP" && $0.count == 1 })
        XCTAssertFalse(LogErrorClueClassifier.isErrorLine("normal boot line"))
    }

    func testEmptyAndBoundedInput() {
        XCTAssertTrue(LogErrorClueClassifier.summarize([]).isEmpty)
        let many = Array(repeating: "error: bounded", count: 30_000)
        let summary = LogErrorClueClassifier.summarize(many)
        XCTAssertLessThanOrEqual(summary.hitCount, LogErrorClueClassifier.maximumLines)
    }

    private func read(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testSlimViewContract() throws {
        let view = try read("Sources/DeviceCapturePrototype/LogCaptureWorkspaceView.swift")
        XCTAssertTrue(view.contains("rlm-control-header"))
        XCTAssertTrue(view.contains("rlm-telemetry-bar"))
        XCTAssertTrue(view.contains("rlm-error-clue-bar"))
        XCTAssertTrue(view.contains("rlm-preview-filter"))
        XCTAssertTrue(view.contains("rlm-bottom-actions"))
        XCTAssertTrue(view.contains("Color(red: 11/255, green: 13/255, blue: 17/255)"))
        XCTAssertTrue(view.contains("在 Finder 中打开原始目录"))
        XCTAssertFalse(view.contains("private var liveCards"))
        XCTAssertFalse(view.contains("Text(L10n.t(\"日志抓取\"))"))
    }
}

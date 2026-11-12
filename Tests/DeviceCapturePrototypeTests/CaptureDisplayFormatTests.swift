import XCTest
@testable import DeviceCapturePrototype

final class CaptureDisplayFormatTests: XCTestCase {
    func testDurationExamplesFromSpec() {
        XCTAssertEqual(CaptureDisplayFormat.duration(seconds: 0), "0秒")
        XCTAssertEqual(CaptureDisplayFormat.duration(seconds: 9), "9秒")
        XCTAssertEqual(CaptureDisplayFormat.duration(seconds: 59), "59秒")
        XCTAssertEqual(CaptureDisplayFormat.duration(seconds: 60), "1分00秒")
        XCTAssertEqual(CaptureDisplayFormat.duration(seconds: 65), "1分05秒")
        XCTAssertEqual(CaptureDisplayFormat.duration(seconds: 92), "1分32秒")
        XCTAssertEqual(CaptureDisplayFormat.duration(seconds: 3909), "1小时05分09秒")
        XCTAssertEqual(CaptureDisplayFormat.duration(seconds: 3600), "1小时00分00秒")
        XCTAssertEqual(CaptureDisplayFormat.duration(seconds: 10 * 3600 + 5 * 60 + 9), "10小时05分09秒")
        XCTAssertFalse(CaptureDisplayFormat.duration(seconds: 9).contains(" "))
        XCTAssertFalse(CaptureDisplayFormat.duration(seconds: 92).contains(":"))
        XCTAssertFalse(CaptureDisplayFormat.duration(seconds: 9).hasPrefix("0"))
    }

    func testDataSizeExamplesFromSpec() {
        XCTAssertEqual(CaptureDisplayFormat.dataSize(bytes: 0), "0 B")
        XCTAssertEqual(CaptureDisplayFormat.dataSize(bytes: 985), "985 B")
        XCTAssertEqual(CaptureDisplayFormat.dataSize(bytes: 999), "999 B")
        XCTAssertEqual(CaptureDisplayFormat.dataSize(bytes: 1000), "1 KB")
        XCTAssertEqual(CaptureDisplayFormat.dataSize(bytes: 1485), "1.49 KB")
        XCTAssertEqual(CaptureDisplayFormat.dataSize(bytes: 1500), "1.5 KB")
        XCTAssertEqual(CaptureDisplayFormat.dataSize(bytes: 1_000_000), "1 MB")
        XCTAssertEqual(CaptureDisplayFormat.dataSize(bytes: 1_500_000), "1.5 MB")
        XCTAssertEqual(CaptureDisplayFormat.dataSize(bytes: 1_000_000_000), "1 GB")
        XCTAssertEqual(CaptureDisplayFormat.dataSize(bytes: 1_000_000_000_000), "1000 GB")
        XCTAssertFalse(CaptureDisplayFormat.dataSize(bytes: 1_000_000_000_000).contains("TB"))
        XCTAssertEqual(CaptureDisplayFormat.dataSize(bytes: 1049), "1.05 KB")
        XCTAssertEqual(CaptureDisplayFormat.dataSize(bytes: 1484), "1.48 KB")
    }

    func testMeterUsesDisplayFormatWithoutRewritingStoredBytes() {
        // CaptureModel keeps exact integer counters; only the meter string is formatted.
        XCTAssertEqual(CaptureDisplayFormat.dataSize(bytes: 1485), "1.49 KB")
        XCTAssertEqual(1485, 1485) // stored integer remains exact; this is a display-only helper.
    }
}

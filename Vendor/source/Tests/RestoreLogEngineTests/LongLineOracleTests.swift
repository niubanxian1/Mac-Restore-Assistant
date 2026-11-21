import XCTest
import Foundation
@testable import RestoreLogEngine

/// RLM_1_2_LONG_LINE_RECALL_AND_N1_SOURCE_006 — long-line FN closure vs FullScanOracle.
final class LongLineOracleTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ll006-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func writeLog(_ name: String, _ body: Data) throws -> URL {
        let u = tmp.appendingPathComponent(name)
        try body.write(to: u)
        return u
    }

    private func pad(_ n: Int, _ byte: UInt8 = 0x58) -> Data { // 'X'
        Data(repeating: byte, count: n)
    }

    private func assertBuildKeepsNeedle(raw: URL, needle: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let diag = tmp.appendingPathComponent("diag-\(UUID().uuidString).log")
        let metrics = try DiagnosticLogBuilder.build(fromRaw: raw, to: diag)
        let text = try String(contentsOf: diag, encoding: .utf8)
        XCTAssertTrue(text.contains(needle) || text.lowercased().contains(needle.lowercased()),
                      "diagnostic missing needle \(needle); kept=\(metrics.keptLines)", file: file, line: line)
        let oracle = try FullScanOracle.analyze(rawURL: raw)
        let productRawLs = Set(FullScanOracle.extractRawLineNumbers(fromDiagnostic: text))
        // Chrono section may duplicate thematic — compare unique kept set vs oracle.
        XCTAssertEqual(productRawLs, Set(oracle.keptRawLineNumbers),
                       "Oracle kept rawL mismatch product=\(productRawLs.sorted()) oracle=\(oracle.keptRawLineNumbers)",
                       file: file, line: line)
        XCTAssertEqual(metrics.terminalKind.rawValue, oracle.terminalKindName,
                       "terminal mismatch", file: file, line: line)
    }

    func testCase01_needleAt2047() throws {
        var d = pad(2047)
        d.append(contentsOf: "RamrodErrorDomain code:7".utf8)
        d.append(0x0A)
        let raw = try writeLog("c01.log", d)
        try assertBuildKeepsNeedle(raw: raw, needle: "RamrodErrorDomain")
        XCTAssertTrue(DiagnosticLogBuilder.shouldKeep(String(decoding: d.dropLast(), as: UTF8.self)))
    }

    func testCase02_needleAt2048() throws {
        var d = pad(2048)
        d.append(contentsOf: "AMRestoreErrorDomain Error Domain=AMRestoreErrorDomain Code=-1".utf8)
        d.append(0x0A)
        let raw = try writeLog("c02.log", d)
        try assertBuildKeepsNeedle(raw: raw, needle: "AMRestoreErrorDomain")
    }

    func testCase03_needleStraddle2048() throws {
        // RamrodErrorDomain (17) starts at 2040 → straddles 2047|2048
        var d = pad(2040)
        d.append(contentsOf: "RamrodErrorDomain code:7".utf8)
        d.append(0x0A)
        let raw = try writeLog("c03.log", d)
        try assertBuildKeepsNeedle(raw: raw, needle: "RamrodErrorDomain")
    }

    func testCase04_needleAt4096() throws {
        var d = pad(4096)
        d.append(contentsOf: "update_mcdp29xx returned 1".utf8)
        d.append(0x0A)
        let raw = try writeLog("c04.log", d)
        try assertBuildKeepsNeedle(raw: raw, needle: "update_mcdp29xx")
    }

    func testCase05_needleAt16384() throws {
        var d = pad(16384)
        d.append(contentsOf: "Checkpoint 0x1308: Failed".utf8)
        d.append(0x0A)
        let raw = try writeLog("c05.log", d)
        try assertBuildKeepsNeedle(raw: raw, needle: "Checkpoint")
        XCTAssertTrue(DiagnosticLogBuilder.isFatalSignal(String(decoding: d.dropLast(), as: UTF8.self)))
    }

    func testCase05b_needleAt65536() throws {
        var d = pad(65536)
        d.append(contentsOf: "Device disconnected during transition".utf8)
        d.append(0x0A)
        let raw = try writeLog("c05b.log", d)
        try assertBuildKeepsNeedle(raw: raw, needle: "Device disconnected")
    }

    func testCase06_nestedErrorsAfterPad() throws {
        var d = pad(3000)
        d.append(contentsOf: "Nested error: NSUnderlyingError RamrodErrorDomain code:7 AMRestoreErrorDomain Code=-1".utf8)
        d.append(0x0A)
        let raw = try writeLog("c06.log", d)
        try assertBuildKeepsNeedle(raw: raw, needle: "RamrodErrorDomain")
        let line = String(decoding: d.dropLast(), as: UTF8.self)
        XCTAssertTrue(DiagnosticLogBuilder.isFaultContext(line))
        XCTAssertTrue(DiagnosticLogBuilder.isFatalSignal(line))
    }

    func testCase07_mixedSuccessFailureIdentity() throws {
        let body = "device ECID=0xABCDEF: Restore succeeded; later Restore failed; SessionID=S1\n"
        let raw = try writeLog("c07.log", Data(body.utf8))
        let diag = tmp.appendingPathComponent("c07.diag.log")
        let metrics = try DiagnosticLogBuilder.build(fromRaw: raw, to: diag)
        XCTAssertGreaterThan(metrics.keptLines, 0)
        let oracle = try FullScanOracle.analyze(rawURL: raw)
        XCTAssertEqual(metrics.terminalKind.rawValue, oracle.terminalKindName)
        // Must not invent retry solely from ECID; classifyTerminal rules unchanged.
        XCTAssertNotEqual(metrics.terminalKind, .none)
    }

    func testCase08_utf8BoundaryThenNeedle() throws {
        // 3-byte UTF-8 未 (E6 9C AA) straddling 2047|2048, then ASCII needle.
        var d = pad(2046)
        d.append(contentsOf: "未".utf8) // 3 bytes → occupies 2046,2047,2048
        d.append(contentsOf: " AMRestoreErrorDomain Code=-1".utf8)
        d.append(0x0A)
        let raw = try writeLog("c08.log", d)
        try assertBuildKeepsNeedle(raw: raw, needle: "AMRestoreErrorDomain")
    }

    func testCase09_noFinalNewline() throws {
        var d = pad(3000)
        d.append(contentsOf: "RamrodErrorDomain code:7".utf8)
        // no 0x0A
        let raw = try writeLog("c09.log", d)
        try assertBuildKeepsNeedle(raw: raw, needle: "RamrodErrorDomain")
    }

    func testCase10a_illegalUTF8PlusLateNeedle() throws {
        var d = pad(2500)
        d.append(contentsOf: [0xFF, 0xFE, 0xFD]) // illegal
        d.append(contentsOf: " AMRestoreErrorDomain".utf8)
        d.append(0x0A)
        let raw = try writeLog("c10a.log", d)
        try assertBuildKeepsNeedle(raw: raw, needle: "AMRestoreErrorDomain")
    }

    func testCase10b_oversizeLineThrows() throws {
        let limit = DiagnosticLogBuilder.maxLineBytesDefault
        var d = pad(limit + 1)
        d.append(0x0A)
        let raw = try writeLog("c10b.log", d)
        let diag = tmp.appendingPathComponent("c10b.diag.log")
        XCTAssertThrowsError(try DiagnosticLogBuilder.build(fromRaw: raw, to: diag)) { err in
            guard let e = err as? DiagnosticResourceError else {
                XCTFail("expected DiagnosticResourceError got \(err)")
                return
            }
            if case .lineTooLong = e { return }
            XCTFail("expected lineTooLong got \(e)")
        }
    }

    func testPublicShouldKeep_lateNeedleNoLongerFN() {
        let late = String(repeating: "Z", count: 2100) + " AMRestoreErrorDomain Code=-1"
        XCTAssertTrue(DiagnosticLogBuilder.shouldKeep(late), "2048 prefix FN must be closed")
        let early = "AMRestoreErrorDomain Code=-1"
        XCTAssertTrue(DiagnosticLogBuilder.shouldKeep(early))
    }

    func testOracleMatch_mixedLateAndNoise() throws {
        var body = Data()
        body.append(pad(100))
        body.append(contentsOf: "CFPrefs found no value for key".utf8)
        body.append(pad(200))
        body.append(0x0A)
        body.append(pad(5000))
        body.append(contentsOf: "update_mcdp29xx returned 1".utf8)
        body.append(0x0A)
        body.append(contentsOf: "Restore failed\n".utf8)
        let raw = try writeLog("mixed.log", body)
        let diag = tmp.appendingPathComponent("mixed.diag.log")
        let metrics = try DiagnosticLogBuilder.build(fromRaw: raw, to: diag)
        let text = try String(contentsOf: diag, encoding: .utf8)
        XCTAssertTrue(text.contains("update_mcdp29xx"))
        XCTAssertTrue(text.contains("Restore failed"))
        let oracle = try FullScanOracle.analyze(rawURL: raw)
        XCTAssertEqual(Set(FullScanOracle.extractRawLineNumbers(fromDiagnostic: text)), Set(oracle.keptRawLineNumbers))
        XCTAssertEqual(metrics.terminalKind.rawValue, oracle.terminalKindName)
        XCTAssertGreaterThanOrEqual(metrics.keptLines, 2)
    }
}

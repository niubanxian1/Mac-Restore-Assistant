import XCTest
@testable import DeviceCapturePrototype

/// Real DFU nodes expose CPID/BDID in the USB serial, not as top-level fields.
final class DFUUSBIdentityParserTests: XCTestCase {
    private let m1Serial =
        "SDOM:01 CPID:8103 CPRV:11 CPFM:03 SCEP:01 BDID:26 ECID:00C0FFEE00000010 IBFL:3C SRTG:[iBoot-5540.0.0.400.2]"
    private let m2Serial =
        "SDOM:01 CPID:8112 CPRV:11 CPFM:03 SCEP:01 BDID:28 ECID:00C0FFEE00000001 IBFL:3C SRTG:[iBoot-6821.0.0.200.16]"

    func testM1SerialParsesChipAndBoard() {
        XCTAssertEqual(
            DFUUSBIdentityParser.field(topLevelRaw: nil, serial: m1Serial, label: "CPID"),
            0x8103)
        XCTAssertEqual(
            DFUUSBIdentityParser.field(topLevelRaw: nil, serial: m1Serial, label: "BDID"),
            0x26)
    }

    func testM2SerialParsesChipAndBoard() {
        XCTAssertEqual(
            DFUUSBIdentityParser.field(topLevelRaw: nil, serial: m2Serial, label: "CPID"),
            0x8112)
        XCTAssertEqual(
            DFUUSBIdentityParser.field(topLevelRaw: nil, serial: m2Serial, label: "BDID"),
            0x28)
    }

    func testMissingOrInvalidLabelsReturnNil() {
        XCTAssertNil(DFUUSBIdentityParser.labelledHex("CPID", in: "SDOM:01 ECID:00C0FFEE00000010"))
        XCTAssertNil(DFUUSBIdentityParser.labelledHex("CPID", in: "CPID:"))
        XCTAssertNil(DFUUSBIdentityParser.labelledHex("CPID", in: "CPID:GG"))
        XCTAssertNil(DFUUSBIdentityParser.labelledHex("BDID", in: "SDOM:01 BDID:0x26"))
        XCTAssertNil(DFUUSBIdentityParser.labelledHex("CPID", in: "BDID:26"))
        XCTAssertNil(DFUUSBIdentityParser.labelledHex("CPID", in: "CPID:FFFFFFFFFFFFFFFFFFFF"))
        XCTAssertNil(DFUUSBIdentityParser.labelledHex("CPID", in: "CPID:123456"))
        XCTAssertNil(DFUUSBIdentityParser.labelledHex("BDID", in: "BDID:100"))
    }

    func testTopLevelValueWinsAndInvalidTopLevelDoesNotFallBack() {
        XCTAssertEqual(
            DFUUSBIdentityParser.field(topLevelRaw: "0x1234", serial: m1Serial, label: "CPID"),
            0x1234)
        XCTAssertEqual(
            DFUUSBIdentityParser.field(topLevelRaw: "24640", serial: m1Serial, label: "CPID"),
            24640)
        XCTAssertNil(
            DFUUSBIdentityParser.field(topLevelRaw: "70000", serial: m1Serial, label: "CPID"))
        XCTAssertNil(
            DFUUSBIdentityParser.field(topLevelRaw: "not-hex", serial: m1Serial, label: "CPID"))
        XCTAssertNil(
            DFUUSBIdentityParser.field(topLevelRaw: "", serial: m1Serial, label: "CPID"))
    }

    func testCaseInsensitiveLabelAndWhitespace() {
        XCTAssertEqual(
            DFUUSBIdentityParser.labelledHex("cpid", in: "  cpid:8103\tbdid:26  "),
            0x8103)
        XCTAssertEqual(
            DFUUSBIdentityParser.labelledHex("BDID", in: "  cpid:8103\tbdid:26  "),
            0x26)
    }
}

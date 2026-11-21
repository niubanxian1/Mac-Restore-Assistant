import XCTest
@testable import DeviceCapturePrototype

final class MacIdentityCatalogTests: XCTestCase {
    func testBundledCatalogHasFixedCoverage() {
        let catalog = MacIdentityCatalog.builtIn
        XCTAssertEqual(catalog.records.count, 166)
        XCTAssertEqual(Set(catalog.records.map(\.modelIdentifier)).count, 144)
        XCTAssertEqual(Set(catalog.records.flatMap(\.aNumbers)).count, 92)
        XCTAssertEqual(catalog.hardwareRecords.count, 82)
        XCTAssertEqual(
            catalog.upstreamCommit,
            "3301fe7d834a485b368cd7edf20f7535d6d598b4")
    }

    func testA2141KeepsBothIdentifiers() {
        let records = MacIdentityCatalog.builtIn.records(forANumber: "A2141")
        XCTAssertEqual(
            Set(records.map(\.modelIdentifier)),
            Set(["MacBookPro16,1", "MacBookPro16,4"]))
        XCTAssertEqual(Set(records.map(\.year)), Set([2019]))
    }

    func testMac18AndMac14OverridesAreExplicit() {
        let catalog = MacIdentityCatalog.builtIn
        let mac18 = catalog.records(forModelIdentifier: "Mac18,2")
        XCTAssertEqual(mac18.count, 2)
        XCTAssertTrue(mac18.allSatisfy { $0.aNumbers == ["A3589", "A3590"] })
        XCTAssertTrue(mac18.allSatisfy { $0.aNumbersState == "pending" })

        let mac14 = catalog.records(forModelIdentifier: "Mac14,8")
        XCTAssertEqual(mac14.count, 2)
        XCTAssertTrue(mac14.allSatisfy { $0.architecture == "apple_silicon" })
        XCTAssertTrue(mac14.allSatisfy { $0.architectureRaw == "Intel" })
        XCTAssertTrue(mac14.allSatisfy {
            $0.architectureSourceOverrideRaw == "Intel"
        })
    }

    func testHardwareIndexesAreEvidenceSpecific() {
        let catalog = MacIdentityCatalog.builtIn
        XCTAssertEqual(
            catalog.hardware(forProductType: "iBridge2,14")?.modelIdentifier,
            "MacBookPro16,1")
        XCTAssertEqual(
            catalog.hardware(forCode: "j215ap")?.modelIdentifier,
            "MacBookPro16,4")
        XCTAssertEqual(
            catalog.hardware(cpid: 0x6031, bdid: 0x44)?.modelIdentifier,
            "Mac15,8")
        XCTAssertGreaterThan(catalog.hardware(cpid: 0x8012).count, 1)
    }
}

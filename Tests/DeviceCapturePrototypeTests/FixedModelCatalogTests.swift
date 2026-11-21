import XCTest
@testable import DeviceCapturePrototype

final class FixedModelCatalogTests: XCTestCase {
    func testBundledCatalogContainsAllFixedVersionCandidates() {
        XCTAssertEqual(FixedModelCatalog.candidates.count, 82)
    }

    func testExplicitProductTypeResolvesOneFixedCatalogCandidate() {
        let result = FixedModelCatalog.resolve(
            productType: "Mac15,7",
            hardwareCode: nil,
            cpid: nil,
            bdid: nil)
        guard case .matched(let candidate) = result else {
            return XCTFail("expected one exact ProductType candidate")
        }
        XCTAssertEqual(candidate.modelIdentifier, "Mac15,7")
        XCTAssertEqual(candidate.classification, "Apple Silicon")
        XCTAssertTrue(candidate.source.contains("3301fe7d"))
    }

    func testChipAndBoardIDsMustBeCombinedForFixedCatalogResolution() {
        XCTAssertEqual(
            FixedModelCatalog.resolve(
                productType: nil,
                hardwareCode: nil,
                cpid: 0x6031,
                bdid: 0x44),
            .matched(FixedModelCatalog.candidate(for: "Mac15,8")!))

        guard case .candidates(let chipOnly) = FixedModelCatalog.resolve(
            productType: nil,
            hardwareCode: nil,
            cpid: 0x6031,
            bdid: nil) else {
            return XCTFail("CPID alone must remain a candidate set")
        }
        XCTAssertGreaterThan(chipOnly.count, 1)
    }

    func testConflictingExplicitProductAndBoardEvidenceIsNotResolved() {
        guard case .conflict(let values) = FixedModelCatalog.resolve(
            productType: "Mac16,8",
            hardwareCode: nil,
            cpid: 0x6040,
            bdid: 0x06) else {
            return XCTFail("conflicting evidence must stay unresolved")
        }
        XCTAssertTrue(values.contains { $0.modelIdentifier == "Mac16,8" })
        XCTAssertTrue(values.contains { $0.modelIdentifier == "Mac16,7" })
    }

    func testWeakChipOnlyEvidenceDoesNotOverrideExplicitProductType() {
        guard case .matched(let candidate) = FixedModelCatalog.resolve(
            productType: "Mac15,3",
            hardwareCode: nil,
            cpid: 0x6031,
            bdid: nil) else {
            return XCTFail("an explicit ProductType must not be replaced by chip-only evidence")
        }
        XCTAssertEqual(candidate.modelIdentifier, "Mac15,3")
    }

    func testUSBPropertiesCanUniquelyMatchFromCPIDAndBDID() {
        let text = """
        +-o Apple Mobile Device (DFU Mode)@01100000  <class IOUSBHostDevice, id 0x100>
          {
            "USB Product Name" = "Apple Mobile Device (DFU Mode)"
            "idProduct" = 4737
            "idVendor" = 1452
            "locationID" = 17825792
            "CPID" = 24640
            "BDID" = 4
          }
        """
        let observed = ObservedDeviceReader.parse(text)
        XCTAssertEqual(observed.count, 1)
        XCTAssertEqual(observed.first?.modelIdentifier, "Mac16,8")
        XCTAssertFalse(observed.first?.modelIsCandidate == true)
        XCTAssertEqual(observed.first?.identityResolution?.state, .uniqueCurrentMatch)
        XCTAssertTrue(observed.first?.modelSource?.contains("libirecovery@3301fe7d") == true)
        XCTAssertEqual(
            DeviceDisplayIdentity.currentHeadline(
                mode: .dfu,
                identifiedModel: observed.first?.modelIdentifier,
                modelIsCandidate: observed.first?.modelIsCandidate == true),
            "MacBook Pro（14 英寸，M4 Pro，2024 年） · DFU")
    }
}

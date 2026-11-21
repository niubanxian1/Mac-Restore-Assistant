import XCTest
@testable import DeviceCapturePrototype

final class MacIdentityResolverTests: XCTestCase {
    private let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func observation(
        explicit: String? = nil,
        productType: String? = nil,
        hardwareCode: String? = nil,
        cpid: Int? = nil,
        bdid: Int? = nil,
        currentECID: String? = nil,
        cfgutilModel: String? = nil,
        cfgutilECID: String? = nil,
        locationMatched: Bool = false,
        historical: HistoricalIdentityHint? = nil
    ) -> MacIdentityObservation {
        MacIdentityObservation(
            observationID: "obs-current",
            connectionGeneration: 7,
            capturedAt: capturedAt,
            mode: "DFU",
            currentECID: currentECID,
            explicitMachineIdentifier: explicit,
            productType: productType,
            hardwareCode: hardwareCode,
            cpid: cpid,
            bdid: bdid,
            cfgutilModelIdentifier: cfgutilModel,
            cfgutilECID: cfgutilECID,
            cfgutilLocationMatched: locationMatched,
            historicalHint: historical)
    }

    func testExplicitCurrentMachineIdentifierIsConfirmed() {
        let result = MacIdentityResolver.resolve(
            observation: observation(explicit: "Mac16,8"))
        XCTAssertEqual(result.state, .confirmedCurrent)
        XCTAssertEqual(result.modelIdentifiers, ["Mac16,8"])
        XCTAssertEqual(result.commonANumbers, ["A3401"])
        XCTAssertEqual(result.commonYears, [2024])
        XCTAssertEqual(result.evidence.first {
            $0.field == .explicitMachineIdentifier
        }?.connectionGeneration, 7)
    }

    func testGenericMacWithOnlyECIDAndModeStaysUnknown() {
        let result = MacIdentityResolver.resolve(
            observation: observation(currentECID: "0011223344556677"))
        XCTAssertEqual(result.state, .unknown)
        XCTAssertNil(result.primaryModelIdentifier)
        XCTAssertEqual(result.evidence.map(\.field).contains(.ecid), true)
        XCTAssertEqual(result.evidence.map(\.field).contains(.mode), true)
    }

    func testIBridgeUniqueMatchProjectsCommonAAndYear() {
        let result = MacIdentityResolver.resolve(
            observation: observation(productType: "iBridge2,14"))
        XCTAssertEqual(result.state, .uniqueCurrentMatch)
        XCTAssertEqual(result.primaryModelIdentifier, "MacBookPro16,1")
        XCTAssertEqual(result.commonANumbers, ["A2141"])
        XCTAssertEqual(result.commonYears, [2019])
        XCTAssertEqual(result.hardwareRecords.first?.classification, "T2")
    }

    func testIBridgeAndHardwareCodeConflictStaysUnresolved() {
        let result = MacIdentityResolver.resolve(
            observation: observation(
                productType: "iBridge2,14",
                hardwareCode: "j215ap"))
        XCTAssertEqual(result.state, .conflict)
        XCTAssertNil(result.primaryModelIdentifier)
        XCTAssertGreaterThanOrEqual(result.conflictFields.count, 2)
        XCTAssertTrue(result.sourceSummary.contains {
            $0.contains("无法求交")
        })
    }

    func testCPIDOnlyRemainsCandidates() {
        let result = MacIdentityResolver.resolve(
            observation: observation(cpid: 0x8012))
        XCTAssertEqual(result.state, .candidates)
        XCTAssertNil(result.primaryModelIdentifier)
        XCTAssertGreaterThan(result.modelIdentifiers.count, 1)
    }

    func testCPIDAndBDIDCanUniquelyMatch() {
        let result = MacIdentityResolver.resolve(
            observation: observation(cpid: 0x6031, bdid: 0x44))
        XCTAssertEqual(result.state, .uniqueCurrentMatch)
        XCTAssertEqual(result.primaryModelIdentifier, "Mac15,8")
    }

    func testUniqueModelHeadlinePrefersOwnerFacingCanonicalName() {
        let result = MacIdentityResolver.resolve(
            observation: observation(cpid: 24640, bdid: 4))
        XCTAssertEqual(
            DeviceDisplayIdentity.currentHeadline(mode: .dfu, resolution: result),
            "MacBook Pro（14 英寸，M4 Pro，2024 年） · DFU · 唯一匹配")
    }

    func testExplicitModelConflictingWithCPIDAndBDIDIsConflict() {
        let result = MacIdentityResolver.resolve(
            observation: observation(
                explicit: "Mac16,8",
                cpid: 24640,
                bdid: 6))
        XCTAssertEqual(result.state, .conflict)
        XCTAssertNil(result.primaryModelIdentifier)
        XCTAssertTrue(result.modelIdentifiers.contains("Mac16,8"))
        XCTAssertTrue(result.modelIdentifiers.contains("Mac16,7"))
    }

    func testCfgutilECIDMatchIsStrongButLocationOnlyIsCandidate() {
        let matched = MacIdentityResolver.resolve(
            observation: observation(
                currentECID: "0011223344556677",
                cfgutilModel: "Mac16,13",
                cfgutilECID: "0011223344556677"))
        XCTAssertEqual(matched.state, .uniqueCurrentMatch)
        XCTAssertEqual(matched.primaryModelIdentifier, "Mac16,13")

        let locationOnly = MacIdentityResolver.resolve(
            observation: observation(
                cfgutilModel: "Mac18,2",
                cfgutilECID: "0011223344556677",
                locationMatched: true))
        XCTAssertEqual(locationOnly.state, .candidates)
        XCTAssertNil(locationOnly.primaryModelIdentifier)
        XCTAssertEqual(locationOnly.commonANumbers, ["A3589", "A3590"])
        XCTAssertEqual(locationOnly.commonYears, [2026])
    }

    func testHistoricalCacheNeverDrivesCurrentIdentity() {
        let hint = HistoricalIdentityHint(
            modelIdentifier: "MacBookPro16,1",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            source: "prior same ECID")
        let result = MacIdentityResolver.resolve(
            observation: observation(
                currentECID: "0011223344556677",
                historical: hint))
        XCTAssertEqual(result.state, .historicalHintOnly)
        XCTAssertNil(result.primaryModelIdentifier)
        XCTAssertEqual(result.historicalHint, hint)
        XCTAssertEqual(result.commonANumbers, [])
    }

    func testDifferentCfgutilECIDIsIgnoredOnSameLocation() {
        let result = MacIdentityResolver.resolve(
            observation: observation(
                currentECID: "0011223344556677",
                cfgutilModel: "Mac16,13",
                cfgutilECID: "00AABBCCDDEEFF",
                locationMatched: true))
        XCTAssertEqual(result.state, .unknown)
        XCTAssertNil(result.primaryModelIdentifier)
    }
}

import Foundation
import XCTest
@testable import DeviceCapturePrototype

final class Batch2FirmwareRecommendationTests: XCTestCase {
    private let engine = FirmwareRecommendationEngine()
    private let model = "Mac14,2"

    func testModelFamilyKeyDoesNotSplitWhenOptionalHardwareFieldsAppear() throws {
        let incomplete = try identity(
            productType: model,
            deviceClass: nil,
            boardID: nil,
            chipID: nil)
        let complete = try identity(
            productType: model,
            deviceClass: "j413ap",
            boardID: 0x24,
            chipID: 0x8132)

        XCTAssertEqual(
            ModelFamilyKey.resolve(identity: incomplete),
            ModelFamilyKey.resolve(identity: complete))
        XCTAssertNotEqual(
            HardwareBindingKey.resolve(identity: incomplete),
            HardwareBindingKey.resolve(identity: complete))
    }

    func testHardwareBindingSeparatesSameProductTypeWithDifferentBoardOrChip() throws {
        let first = try identity(
            productType: model,
            deviceClass: "j413ap",
            boardID: 0x24,
            chipID: 0x8112)
        let second = try identity(
            productType: model,
            deviceClass: "j413ap",
            boardID: 0x25,
            chipID: 0x8112)

        XCTAssertEqual(
            ModelFamilyKey.resolve(identity: first),
            ModelFamilyKey.resolve(identity: second))
        XCTAssertNotEqual(
            HardwareBindingKey.resolve(identity: first),
            HardwareBindingKey.resolve(identity: second))
    }

    func testUnknownIdentityNeverAutoSelectsTierFourCandidate() throws {
        let target = try identity(productType: nil, provenance: .unverifiedGeneric)
        let candidates = [
            candidate(version: "27.10", build: "26C100", status: .unverified),
            candidate(version: "27.9", build: "26C99", status: .compatible)
        ]

        let recommendation = engine.recommend(
            FirmwareRecommendationRequest(
                target: target,
                candidates: candidates,
                recentSuccessfulUses: [],
                modelDefaultCandidateID: nil,
                globalDefaultCandidateID: nil,
                manualCandidateID: nil))

        XCTAssertNil(recommendation)
    }

    func testUnknownIdentityMayUseExplicitGlobalDefaultWithManualConfirmation() throws {
        let target = try identity(productType: nil, provenance: .portHistoryAssisted)
        let global = candidate(version: "14.0", build: "23A344", status: .unverified)

        let recommendation = engine.recommend(
            FirmwareRecommendationRequest(
                target: target,
                candidates: [global],
                recentSuccessfulUses: [],
                modelDefaultCandidateID: nil,
                globalDefaultCandidateID: global.id,
                manualCandidateID: nil))

        XCTAssertEqual(recommendation?.tier, .tier3GlobalDefault)
        XCTAssertEqual(recommendation?.selectionSource, .systemRecommended)
        XCTAssertEqual(recommendation?.requiresManualConfirmation, true)
    }

    func testUnknownIdentityNeverUsesAModelDefault() throws {
        let target = try identity(
            productType: nil,
            provenance: .unverifiedGeneric)
        let candidate = candidate(
            version: "27.0",
            build: "26A428",
            status: .compatible)
        let request = FirmwareRecommendationRequest(
            target: target,
            candidates: [candidate],
            modelDefaultCandidateID: candidate.id,
            modelDefaultIsConfigured: true)

        XCTAssertNil(engine.recommend(request))
    }

    func testGenericProductLabelFallsBackOnlyToVerifiedMachineIdentifier() {
        let validMachine = FirmwareTargetIdentity(
            productType: "Apple Mobile Device",
            machineIdentifier: "Mac14,2",
            deviceClass: "j413ap",
            boardID: 0x24,
            chipID: 0x8132,
            provenance: .liveConfirmed)
        XCTAssertEqual(
            ModelFamilyKey.resolve(identity: validMachine)?.rawValue,
            "MAC14,2")

        let invalid = FirmwareTargetIdentity(
            productType: "Generic Mac",
            machineIdentifier: "Unknown",
            deviceClass: nil,
            boardID: nil,
            chipID: nil,
            provenance: .liveConfirmed)
        XCTAssertNil(ModelFamilyKey.resolve(identity: invalid))
    }

    func testOwnerPriorityUsesModelDefaultBeforeGlobalAndRecentUse() throws {
        let target = try identity(productType: model)
        let verified = candidate(version: "27.9", build: "26C99", status: .compatible)
        let modelDefault = candidate(version: "27.10", build: "26C100", status: .compatible)
        let globalDefault = candidate(version: "27.11", build: "26C101", status: .compatible)
        let local = candidate(version: "27.12", build: "26C102", status: .compatible)
        let request = FirmwareRecommendationRequest(
            target: target,
            candidates: [local, globalDefault, modelDefault, verified],
            recentUsedCandidateIDs: [verified.id, local.id],
            lastSelectedCandidateID: local.id,
            modelDefaultCandidateID: modelDefault.id,
            globalDefaultCandidateID: globalDefault.id,
            manualCandidateID: nil)

        XCTAssertEqual(engine.recommend(request)?.candidate.id, modelDefault.id)
        XCTAssertEqual(engine.recommend(request)?.tier, .tier2ModelDefault)

        let withoutVerified = FirmwareRecommendationRequest(
            target: target,
            candidates: [local, globalDefault, modelDefault],
            recentSuccessfulUses: [],
            modelDefaultCandidateID: modelDefault.id,
            globalDefaultCandidateID: globalDefault.id,
            manualCandidateID: nil)
        XCTAssertEqual(engine.recommend(withoutVerified)?.candidate.id, modelDefault.id)
        XCTAssertEqual(engine.recommend(withoutVerified)?.tier, .tier2ModelDefault)

        let withoutModelDefault = FirmwareRecommendationRequest(
            target: target,
            candidates: [local, globalDefault],
            recentSuccessfulUses: [],
            modelDefaultCandidateID: nil,
            globalDefaultCandidateID: globalDefault.id,
            manualCandidateID: nil)
        XCTAssertEqual(engine.recommend(withoutModelDefault)?.candidate.id, globalDefault.id)
        XCTAssertEqual(engine.recommend(withoutModelDefault)?.tier, .tier3GlobalDefault)

        let noReliableCandidate = FirmwareRecommendationRequest(
            target: target,
            candidates: [local],
            recentSuccessfulUses: [],
            modelDefaultCandidateID: nil,
            globalDefaultCandidateID: nil,
            manualCandidateID: nil)
        XCTAssertNil(engine.recommend(noReliableCandidate))
    }

    func testUnverifiedHistoryWithoutRecentLaunchDoesNotAutoSelect() throws {
        let target = try identity(productType: model)
        let newer = candidate(version: "27.10", build: "26C100", status: .compatible)
        let older = candidate(version: "27.9", build: "26C99", status: .compatible)
        let request = FirmwareRecommendationRequest(
            target: target,
            candidates: [newer, older],
            recentSuccessfulUses: [
                usage(candidateID: older.id, source: .bootstrapCandidate1702),
                usage(candidateID: newer.id, source: .unverified)
            ],
            modelDefaultCandidateID: nil,
            globalDefaultCandidateID: nil,
            manualCandidateID: nil)

        XCTAssertNil(engine.recommend(request))
    }

    func testIncompleteNativeHistoryCannotBecomeTierOne() throws {
        let target = try identity(productType: model)
        let historic = candidate(version: "27.9", build: "26C99", status: .compatible)
        let fallback = candidate(version: "27.10", build: "26C100", status: .compatible)
        let request = FirmwareRecommendationRequest(
            target: target,
            candidates: [historic, fallback],
            recentSuccessfulUses: [
                FirmwareUsageRecord(
                    candidateID: historic.id,
                    modelFamilyKey: ModelFamilyKey(rawValue: model)!,
                    outcome: .success,
                    source: .nativeV1703Verified,
                    verificationComplete: false,
                    occurredAt: Date(timeIntervalSince1970: 500))
            ],
            modelDefaultCandidateID: nil,
            globalDefaultCandidateID: nil,
            manualCandidateID: nil)

        XCTAssertNil(engine.recommend(request))
    }

    func testLocalCandidatesDoNotAutoSelectButVersionSortingRemains() throws {
        let target = try identity(productType: model)
        let version10 = candidate(version: "27.10", build: "26C100", status: .unverified)
        let version9 = candidate(version: "27.9", build: "26C99", status: .unverified)
        let compatibleOlder = candidate(version: "26.4", build: "25E241", status: .compatible)
        let request = FirmwareRecommendationRequest(
            target: target,
            candidates: [version9, version10, compatibleOlder],
            recentSuccessfulUses: [],
            modelDefaultCandidateID: nil,
            globalDefaultCandidateID: nil,
            manualCandidateID: nil)

        XCTAssertNil(engine.recommend(request))
        let numericOrder = FirmwareRecommendationEngine.sortCandidatesByVersion(
            [version9, version10])
        XCTAssertEqual(numericOrder.map { $0.metadata?.productVersion }, ["27.10", "27.9"])
    }

    func testIncompatibleAndInvalidCandidatesAreFilteredBeforeTierSelection() throws {
        let target = try identity(productType: model)
        let verifiedButInvalid = candidate(
            version: "27.10",
            build: "26C100",
            status: .compatible,
            validity: .invalid)
        let defaultButIncompatible = candidate(
            version: "27.9",
            build: "26C99",
            status: .incompatible)
        let usable = candidate(version: "26.4", build: "25E241", status: .unverified)
        let request = FirmwareRecommendationRequest(
            target: target,
            candidates: [verifiedButInvalid, defaultButIncompatible, usable],
            recentSuccessfulUses: [
                usage(candidateID: verifiedButInvalid.id, source: .nativeV1703Verified)
            ],
            modelDefaultCandidateID: defaultButIncompatible.id,
            globalDefaultCandidateID: nil,
            manualCandidateID: nil)

        XCTAssertNil(engine.recommend(request))
    }

    func testMissingBuildIdentityNeverBecomesVerifiedCompatibility() throws {
        let target = try identity(productType: model)
        let metadata = IPSWMetadata(
            productTypes: [model],
            identities: [],
            productVersion: "14.0",
            productBuild: "23A344")
        let compatibility = IPSWCompatibilityEvaluator.evaluate(
            metadata: metadata,
            target: RestoreTargetIdentity(
                productType: target.productType,
                deviceClass: target.deviceClass,
                boardID: target.boardID,
                chipID: target.chipID))
        let candidate = FirmwareRecommendationCandidate(
            entry: FirmwareLibraryEntry(
                id: UUID(),
                url: URL(fileURLWithPath: "/tmp/missing-identity.ipsw"),
                state: .available,
                addedAt: Date(timeIntervalSince1970: 1),
                lastSeenAt: Date(timeIntervalSince1970: 2),
                fileIdentity: nil,
                metadata: metadata,
                validity: .valid,
                errorMessage: nil,
                wholeFileSHA256: nil,
                duplicateEntryIDs: []),
            compatibility: compatibility)

        let recommendation = engine.recommend(
            FirmwareRecommendationRequest(
                target: target,
                candidates: [candidate],
                recentSuccessfulUses: [],
                modelDefaultCandidateID: nil,
                globalDefaultCandidateID: nil,
                manualCandidateID: nil))

        XCTAssertEqual(compatibility.status, .unverified)
        XCTAssertNil(recommendation)
    }

    func testManualSelectionCannotBeReplacedByAutomaticRecommendation() throws {
        let target = try identity(productType: model)
        let automatic = candidate(version: "27.10", build: "26C100", status: .compatible)
        let manual = candidate(version: "14.0", build: "23A344", status: .unverified)
        let request = FirmwareRecommendationRequest(
            target: target,
            candidates: [automatic, manual],
            recentSuccessfulUses: [],
            modelDefaultCandidateID: automatic.id,
            globalDefaultCandidateID: nil,
            manualCandidateID: manual.id)

        let recommendation = engine.recommend(request)

        XCTAssertEqual(recommendation?.candidate.id, manual.id)
        XCTAssertEqual(recommendation?.selectionSource, .userManualSelected)
        XCTAssertEqual(recommendation?.requiresManualConfirmation, true)
    }

    func testRecentUsedCompatiblePrecedesLastSelectedAndRequiresCompatibility() throws {
        let target = try identity(productType: model)
        let recentCompatible = candidate(
            version: "27.9",
            build: "26C99",
            status: .compatible)
        let previousSelected = candidate(
            version: "27.10",
            build: "26C100",
            status: .compatible)
        let recentUnverified = candidate(
            version: "27.11",
            build: "26C101",
            status: .unverified)
        let request = FirmwareRecommendationRequest(
            target: target,
            candidates: [
                recentCompatible,
                previousSelected,
                recentUnverified
            ],
            recentUsedCandidateIDs: [
                recentUnverified.id,
                recentCompatible.id
            ],
            lastSelectedCandidateID: previousSelected.id)

        let recommendation = engine.recommend(request)
        XCTAssertEqual(recommendation?.candidate.id, recentCompatible.id)
        XCTAssertEqual(recommendation?.tier, .tier1RecentUsedCompatible)

        let lastOnly = FirmwareRecommendationRequest(
            target: target,
            candidates: [previousSelected],
            lastSelectedCandidateID: previousSelected.id)
        XCTAssertEqual(
            engine.recommend(lastOnly)?.tier,
            .tier4LastSelectedCompatible)
    }

    func testConfiguredUnavailableModelDefaultBlocksGlobalAndRecentFallback() throws {
        let target = try identity(productType: model)
        let missingDefaultID = UUID()
        let global = candidate(
            version: "27.9",
            build: "26C99",
            status: .compatible)
        let recent = candidate(
            version: "27.8",
            build: "26C98",
            status: .compatible)
        let request = FirmwareRecommendationRequest(
            target: target,
            candidates: [global, recent],
            recentUsedCandidateIDs: [recent.id],
            modelDefaultCandidateID: missingDefaultID,
            modelDefaultIsConfigured: true,
            globalDefaultCandidateID: global.id)

        XCTAssertNil(engine.recommend(request))
    }

    func testConfiguredUnavailableGlobalDefaultBlocksRecentFallback() throws {
        let target = try identity(productType: model)
        let recent = candidate(
            version: "27.8",
            build: "26C98",
            status: .compatible)
        let request = FirmwareRecommendationRequest(
            target: target,
            candidates: [recent],
            recentUsedCandidateIDs: [recent.id],
            globalDefaultCandidateID: UUID(),
            globalDefaultIsConfigured: true)

        XCTAssertNil(engine.recommend(request))
    }

    func testManualSelectionStillWinsWhenDefaultIsConfiguredButUnavailable() throws {
        let target = try identity(productType: model)
        let manual = candidate(
            version: "27.0",
            build: "26A428",
            status: .unverified)
        let request = FirmwareRecommendationRequest(
            target: target,
            candidates: [manual],
            modelDefaultCandidateID: UUID(),
            modelDefaultIsConfigured: true,
            manualCandidateID: manual.id)

        XCTAssertEqual(
            engine.recommend(request)?.candidate.id,
            manual.id)
        XCTAssertEqual(
            engine.recommend(request)?.source,
            .userManualSelection)
    }

    func testSemanticVersionComparisonAlsoHandlesBuildSuffixNumbers() {
        XCTAssertEqual(
            FirmwareRecommendationEngine.compareVersionStrings("27.10", "27.9"),
            .orderedDescending)
        XCTAssertEqual(
            FirmwareRecommendationEngine.compareVersionStrings("26C100", "26C99"),
            .orderedDescending)
        XCTAssertEqual(
            FirmwareRecommendationEngine.compareVersionStrings("27.09", "27.9"),
            .orderedSame)
    }

    private func identity(
        productType: String?,
        deviceClass: String? = "j413ap",
        boardID: Int? = 0x24,
        chipID: Int? = 0x8132,
        provenance: DeviceIdentityProvenance = .liveConfirmed
    ) throws -> FirmwareTargetIdentity {
        FirmwareTargetIdentity(
            productType: productType,
            machineIdentifier: productType,
            deviceClass: deviceClass,
            boardID: boardID,
            chipID: chipID,
            provenance: provenance)
    }

    private func candidate(
        version: String,
        build: String,
        status: HardwareCompatibilityStatus,
        validity: IPSWFileValidity = .valid
    ) -> FirmwareRecommendationCandidate {
        FirmwareRecommendationCandidate(
            entry: FirmwareLibraryEntry(
                id: UUID(),
                url: URL(fileURLWithPath: "/tmp/\(version).ipsw"),
                state: .available,
                addedAt: Date(timeIntervalSince1970: 1),
                lastSeenAt: Date(timeIntervalSince1970: 2),
                fileIdentity: nil,
                metadata: IPSWMetadata(
                    productTypes: [model],
                    identities: [
                        IPSWBuildIdentity(
                            deviceClass: "j413ap",
                            boardID: 0x24,
                            chipID: 0x8132)
                    ],
                    productVersion: version,
                    productBuild: build),
                validity: validity,
                errorMessage: nil,
                wholeFileSHA256: nil,
                duplicateEntryIDs: []),
            compatibility: HardwareCompatibility(status: status, message: "test"))
    }

    private func usage(
        candidateID: UUID,
        source: FirmwareUsageRecordSource
    ) -> FirmwareUsageRecord {
        FirmwareUsageRecord(
            candidateID: candidateID,
            modelFamilyKey: ModelFamilyKey(rawValue: model)!,
            outcome: .success,
            source: source,
            verificationComplete: source == .nativeV1703Verified,
            occurredAt: Date(timeIntervalSince1970: source == .nativeV1703Verified ? 200 : 300))
    }
}

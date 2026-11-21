import Foundation
import XCTest
@testable import DeviceCapturePrototype

final class RestoreSuccessDurationMatcherTests: XCTestCase {
    func testPriorityECIDThenModelThenRecent() {
        let target = RestoreTarget(
            ecid: 0x1111, canonicalHex: "0000000000001111",
            productType: "Mac14,2", deviceClass: "j413ap",
            boardID: 0x28, chipID: 0x8112, locationID: "x",
            connectionGeneration: 0, portKey: "p", portDisplayName: "S5",
            mode: .dfu, displayName: "Mac14,2")
        let sameECID = record(ecid: "0000000000001111", version: "27.0", build: "A", seconds: 100, date: 1)
        let sameModel = record(ecid: "0000000000002222", version: "27.0", build: "A", seconds: 200, date: 2)
        let recent = record(ecid: "0000000000003333", version: "26.0", build: "B", seconds: 300, date: 3)
        let match = RestoreSuccessDurationMatcher.match(
            records: [recent, sameModel, sameECID],
            target: target, productVersion: "27.0", productBuild: "A")
        XCTAssertEqual(match?.seconds, 100)
        XCTAssertEqual(match?.priority, .sameECIDAndFirmware)

        let modelMatch = RestoreSuccessDurationMatcher.match(
            records: [recent, sameModel],
            target: target, productVersion: "27.0", productBuild: "A")
        XCTAssertEqual(modelMatch?.seconds, 200)
        XCTAssertEqual(modelMatch?.priority, .sameModelAndFirmware)

        let recentMatch = RestoreSuccessDurationMatcher.match(
            records: [recent], target: target, productVersion: "27.0", productBuild: "A")
        XCTAssertEqual(recentMatch?.seconds, 300)
        XCTAssertEqual(recentMatch?.priority, .sameModelRecent)
    }

    private func record(ecid: String, version: String, build: String, seconds: Double, date: TimeInterval) -> RestoreHistoryRecord {
        let launched = RestoreLifecycleTimePoint(wallTime: Date(timeIntervalSince1970: date), monotonicNanoseconds: 1_000_000_000)
        let exited = RestoreLifecycleTimePoint(wallTime: Date(timeIntervalSince1970: date + seconds), monotonicNanoseconds: 1_000_000_000 + UInt64(seconds * 1_000_000_000))
        return RestoreHistoryRecord(
            taskID: UUID(), attemptID: UUID(), operationType: .restore,
            deviceDisplayName: "Mac14,2", modelFamilyKey: ModelFamilyKey(rawValue: "Mac14,2"),
            hardwareBindingKey: HardwareBindingKey(productType: "Mac14,2", deviceClass: "j413ap", boardID: 0x28, chipID: 0x8112),
            stablePortKey: "p", firmwareLibraryEntryID: nil, firmwareFileName: "x.ipsw", ipswIdentity: nil,
            productVersion: version, productBuild: build, deviceECID: ecid,
            lifecycle: RestoreLifecycleTimes(userConfirmed: launched, processLaunched: launched, firstRestoreActivity: launched, processExited: exited, bothStreamsEOF: exited, outcomeConfirmed: exited, rlmFinalized: nil),
            outcome: .success, errorClassification: .none, exitCode: 0, terminationReason: .exit,
            cancellationRequested: false, sentSignals: [],
            rawPersistencePolicy: RestoreRawPersistencePolicy(autoSaveDefault: false, saveThisRun: false, destinationDirectory: "/tmp", autoMonitorEnabled: false, spaceWarningThresholdBytes: nil, retentionPolicy: "manual"),
            rawEvidenceStatus: .notRequested, rlmStatus: .notRequested, rlmOwnership: .notRequested,
            rlmFinalizedAt: nil, rlmDrainDurationSeconds: nil,
            recordSource: .nativeV1703Verified, verificationComplete: true)
    }
}

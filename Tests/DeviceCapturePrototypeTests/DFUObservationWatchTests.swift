import Foundation
import XCTest
@testable import DeviceCapturePrototype

final class DFUObservationWatchTests: XCTestCase {
    private let target = "100000760:2"
    private let other = "100000763:3"

    private func baseline(
        at: TimeInterval = 9.8,
        port: String? = "__TARGET_PORT__",
        mode: DFUObservationMode = .absent,
        ecid: String? = nil,
        registryID: String? = nil
    ) -> DFUObservationBatch {
        DFUObservationBatch(
            batchID: 1,
            readStartedAt: at - 0.2,
            readCompletedAt: at,
            isValid: true,
            portKey: port == "__TARGET_PORT__" ? target : port,
            mode: mode,
            ecid: ecid,
            registryID: registryID)
    }

    private func sample(
        completedAt: TimeInterval,
        startedAt: TimeInterval? = nil,
        port: String? = "__TARGET_PORT__",
        mode: DFUObservationMode = .dfu,
        ecid: String? = nil,
        registryID: String? = nil,
        valid: Bool = true,
        batchID: UInt64 = 2
    ) -> DFUObservationBatch {
        DFUObservationBatch(
            batchID: batchID,
            readStartedAt: startedAt ?? completedAt,
            readCompletedAt: completedAt,
            isValid: valid,
            portKey: port == "__TARGET_PORT__" ? target : port,
            mode: mode,
            ecid: ecid,
            registryID: registryID)
    }

    private func makeWatch(
        baseline: DFUObservationBatch?,
        clickedAt: TimeInterval = 10
    ) -> DFUObservationWatch {
        DFUObservationWatch(
            operationID: UUID(),
            targetPortKey: target,
            clickedAt: clickedAt,
            baseline: baseline)
    }

    private func dispatch(
        _ watch: inout DFUObservationWatch,
        id: String = "req-1",
        at: TimeInterval = 10,
        confirmed: Bool = true
    ) {
        _ = watch.noteDispatch(
            requestID: id,
            dispatchedAt: at,
            confirmedSubmit: confirmed,
            responseAt: at + 0.4)
    }

    private func final(
        _ watch: inout DFUObservationWatch,
        at: TimeInterval = 25
    ) -> DFUEvaluation {
        watch.finalize(at: at)
    }

    private func assertEvaluation(
        _ evaluation: DFUEvaluation,
        result: DFUConfirmationResult,
        scope: DFUConfirmationScope = .none,
        reasonContains: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(evaluation.result, result, file: file, line: line)
        XCTAssertEqual(evaluation.scope, scope, file: file, line: line)
        XCTAssertTrue(
            evaluation.reason.localizedCaseInsensitiveContains(reasonContains),
            "reason was: \(evaluation.reason)",
            file: file,
            line: line)
    }

    func testM01_OfflineTargetEntersDFUOnSamePort() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 11))
        assertEvaluation(
            final(&watch),
            result: .confirmed,
            scope: .portTransition,
            reasonContains: "post-dispatch DFU transition")
    }

    func testM02_ConnectedSameECIDEntersDFU() {
        var watch = makeWatch(baseline: baseline(mode: .connected, ecid: "A"))
        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 11.2, ecid: "A"))
        assertEvaluation(
            final(&watch),
            result: .confirmed,
            scope: .sameDevice,
            reasonContains: "matching ECID")
    }

    func testM03_AlreadyInDFUBeforeSend() {
        var watch = makeWatch(baseline: baseline(mode: .dfu, ecid: "A"))
        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 11, ecid: "A"))
        assertEvaluation(
            final(&watch),
            result: .observed,
            reasonContains: "already DFU")
    }

    func testM04_DFUOnDifferentPortIgnored() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 11, port: other))
        assertEvaluation(
            final(&watch),
            result: .unknown,
            reasonContains: "another physical port")
    }

    func testM05_PreDispatchSampleArrivingLateIgnored() {
        var watch = makeWatch(baseline: nil)
        dispatch(&watch)
        _ = watch.observe(sample(
            completedAt: 11,
            startedAt: 9.9))
        assertEvaluation(
            final(&watch),
            result: .unknown,
            reasonContains: "without qualified DFU evidence")
    }

    func testM06_RecoveryAfterObserverReadFailure() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch)
        _ = watch.observe(sample(
            completedAt: 10.7,
            mode: .unknown,
            valid: false))
        _ = watch.observe(sample(completedAt: 11.3, batchID: 3))
        assertEvaluation(
            final(&watch),
            result: .confirmed,
            scope: .portTransition,
            reasonContains: "post-dispatch DFU transition")
    }

    func testM07_UnattributedDFUIgnored() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 11, port: nil))
        assertEvaluation(
            final(&watch),
            result: .unknown,
            reasonContains: "exactly one physical port")
    }

    func testM08_NoDFUWithinWindowTimesOutUnknown() {
        var watch = makeWatch(baseline: baseline(mode: .connected))
        dispatch(&watch)
        assertEvaluation(
            final(&watch, at: 25.1),
            result: .unknown,
            reasonContains: "without qualified DFU evidence")
    }

    func testM09_DisconnectAfterConfirmationPreservesHistorySeparately() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 11))
        let settled = watch.observe(sample(
            completedAt: 12,
            mode: .absent,
            batchID: 3))
        XCTAssertEqual(settled.result, .confirmed)
        XCTAssertEqual(settled.scope, .portTransition)
        XCTAssertEqual(settled.currentTargetState, .absent)
    }

    func testM10_TwoDevicesOnlyFrozenPortConfirmed() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 10.6, port: other))
        _ = watch.observe(sample(completedAt: 11.4, batchID: 3))
        assertEvaluation(
            final(&watch),
            result: .confirmed,
            scope: .portTransition,
            reasonContains: "post-dispatch DFU transition")
    }

    func testM11_RecoveryDescriptorDoesNotConfirmDFU() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 11, mode: .recovery))
        assertEvaluation(
            final(&watch),
            result: .unknown,
            reasonContains: "without qualified DFU evidence")
    }

    func testM12_ConnectedModeDoesNotConfirmDFU() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 11, mode: .connected))
        assertEvaluation(
            final(&watch),
            result: .unknown,
            reasonContains: "without qualified DFU evidence")
    }

    func testM13_FastDFUAppearsBeforeHelperReceipt() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch, confirmed: false)
        _ = watch.observe(sample(completedAt: 10.2))
        dispatch(&watch, confirmed: true)
        assertEvaluation(
            final(&watch),
            result: .confirmed,
            scope: .portTransition,
            reasonContains: "post-dispatch DFU transition")
    }

    func testM14_DFUAfterWindowExpiryIgnored() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 25.1))
        assertEvaluation(
            final(&watch, at: 25.2),
            result: .unknown,
            reasonContains: "without qualified DFU evidence")
    }

    func testM15_NoValidBaselineButCurrentDFU() {
        var watch = makeWatch(baseline: nil)
        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 11))
        assertEvaluation(
            final(&watch),
            result: .observed,
            reasonContains: "baseline unavailable")
    }

    func testM16_SamePortECIDConflictABRejected() {
        var watch = makeWatch(baseline: baseline(mode: .connected, ecid: "A"))
        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 11, ecid: "B"))
        assertEvaluation(
            final(&watch),
            result: .observed,
            reasonContains: "conflicting ECID")
    }

    func testM17_StaleBaselineRejectedForConfirmation() {
        var watch = makeWatch(baseline: baseline(at: -3_590))
        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 11))
        assertEvaluation(
            final(&watch),
            result: .observed,
            reasonContains: "baseline is stale")
    }

    func testM18_GenerationResetAcrossIdentityAllowed() {
        var watch = makeWatch(baseline: baseline(
            mode: .connected,
            ecid: "A",
            registryID: "1"))
        dispatch(&watch)
        _ = watch.observe(sample(
            completedAt: 11,
            ecid: "A",
            registryID: "2"))
        assertEvaluation(
            final(&watch),
            result: .confirmed,
            scope: .sameDevice,
            reasonContains: "matching ECID")
    }

    func testM19_ObservedBeforeReceiptCachedAndConfirmedOnReceipt() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch, confirmed: false)
        _ = watch.observe(sample(completedAt: 10.8))
        let beforeReceipt = watch.evaluation
        XCTAssertEqual(beforeReceipt.result, .observed)
        dispatch(&watch, confirmed: true)
        assertEvaluation(
            final(&watch),
            result: .confirmed,
            scope: .portTransition,
            reasonContains: "post-dispatch DFU transition")
    }

    func testM20_NoConfirmedSubmitNeverConfirmsDFU() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch, confirmed: false)
        _ = watch.observe(sample(completedAt: 11))
        assertEvaluation(
            final(&watch),
            result: .observed,
            reasonContains: "before a confirmed command receipt")
    }

    func testM21_CrossDispatchBoundarySampleExcluded() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch)
        _ = watch.observe(sample(
            completedAt: 10.5,
            startedAt: 9.9))
        assertEvaluation(
            final(&watch),
            result: .unknown,
            reasonContains: "without qualified DFU evidence")
    }

    func testM22_KnownBaselineMissingDFUECIDYieldsPortTransition() {
        var watch = makeWatch(baseline: baseline(mode: .connected, ecid: "A"))
        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 11))
        assertEvaluation(
            final(&watch),
            result: .confirmed,
            scope: .portTransition,
            reasonContains: "device identity not proven")
    }

    func testM23_EmptyBaselineToDFUYieldsPortTransition() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 11, ecid: "B"))
        assertEvaluation(
            final(&watch),
            result: .confirmed,
            scope: .portTransition,
            reasonContains: "device identity not proven")
    }

    func testM24_MultipleDFUIdentitiesOnSamePortRejected() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 10.6, ecid: "A"))
        _ = watch.observe(sample(
            completedAt: 10.9,
            ecid: "B",
            batchID: 3))
        assertEvaluation(
            final(&watch),
            result: .observed,
            reasonContains: "multiple DFU identities")
    }

    func testM25_TransientConflictingECIDBOnSamePortRejected() {
        var watch = makeWatch(baseline: baseline(mode: .connected, ecid: "A"))
        dispatch(&watch)
        _ = watch.observe(sample(
            completedAt: 10.5,
            mode: .connected,
            ecid: "B"))
        _ = watch.observe(sample(
            completedAt: 11.2,
            ecid: "B",
            batchID: 3))
        assertEvaluation(
            final(&watch),
            result: .observed,
            reasonContains: "conflicting ECID")
    }

    func testM26_SimultaneousDFUOnSelectedAndOtherPort() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 10.4, port: other))
        _ = watch.observe(sample(completedAt: 10.9, batchID: 3))
        assertEvaluation(
            final(&watch),
            result: .confirmed,
            scope: .portTransition,
            reasonContains: "post-dispatch DFU transition")
    }

    func testM27_DFUOnlyOnOtherPortKeepsUnknown() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 11, port: other))
        assertEvaluation(
            final(&watch),
            result: .unknown,
            reasonContains: "another physical port")
    }

    func testM28_StaleOperationSamplesAndCallbacksDropped() {
        let oldID = UUID()
        let newID = UUID()
        var oldWatch = makeWatch(baseline: baseline())
        oldWatch.operationID = oldID
        dispatch(&oldWatch)
        var newWatch = makeWatch(baseline: baseline(at: 19.8), clickedAt: 20)
        newWatch.operationID = newID
        dispatch(&newWatch, at: 20)
        var router = DFUObservationRouter()
        router.begin(oldWatch)
        XCTAssertNotNil(router.observe(
            operationID: oldID,
            batch: sample(completedAt: 11)))
        router.begin(newWatch)
        XCTAssertNil(router.observe(
            operationID: oldID,
            batch: sample(completedAt: 21)))
        XCTAssertNotNil(router.observe(
            operationID: newID,
            batch: sample(completedAt: 21.2, batchID: 4)))
    }

    func testM29_PostTimeoutSampleNeverConfirmsHistory() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch)
        _ = watch.noteActionTerminal(at: 15.1)
        _ = watch.observe(sample(completedAt: 16.1))
        assertEvaluation(
            final(&watch, at: 16.2),
            result: .unknown,
            reasonContains: "without qualified DFU evidence")
    }

    func testM30_SingleConfirmedSubmitInDualSendSufficient() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch, id: "req-1", confirmed: true)
        dispatch(&watch, id: "req-2", at: 11.5, confirmed: false)
        _ = watch.observe(sample(completedAt: 12))
        assertEvaluation(
            final(&watch),
            result: .confirmed,
            scope: .portTransition,
            reasonContains: "post-dispatch DFU transition")
    }

    func testM31_ZeroConfirmedSubmitInDualSendBlocksConfirm() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch, id: "req-1", confirmed: false)
        dispatch(&watch, id: "req-2", at: 11.5, confirmed: false)
        _ = watch.observe(sample(completedAt: 12))
        assertEvaluation(
            final(&watch),
            result: .observed,
            reasonContains: "before a confirmed command receipt")
    }

    func testM32_SameECIDOnDifferentPortRejected() {
        var watch = makeWatch(baseline: baseline(mode: .connected, ecid: "A"))
        dispatch(&watch)
        _ = watch.observe(sample(
            completedAt: 11,
            port: other,
            ecid: "A"))
        assertEvaluation(
            final(&watch),
            result: .unknown,
            reasonContains: "another physical port")
    }

    func testM33_PostConfirmationDisconnectPreservesOutcome() {
        var watch = makeWatch(baseline: baseline(mode: .connected, ecid: "A"))
        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 10.8, ecid: "A"))
        let evaluation = watch.observe(sample(
            completedAt: 12,
            mode: .absent,
            batchID: 3))
        XCTAssertEqual(evaluation.result, .confirmed)
        XCTAssertEqual(evaluation.scope, .sameDevice)
        XCTAssertEqual(evaluation.currentTargetState, .absent)
    }

    func testM34_OperationRouterIsolatesNewOperationFromOldWatch() throws {
        let first = UUID()
        let second = UUID()
        var oldWatch = makeWatch(baseline: baseline())
        oldWatch.operationID = first
        dispatch(&oldWatch)
        var newWatch = makeWatch(baseline: baseline(at: 19.8), clickedAt: 20)
        newWatch.operationID = second
        dispatch(&newWatch, at: 20)
        var router = DFUObservationRouter()
        router.begin(oldWatch)
        XCTAssertNotNil(router.observe(
            operationID: first,
            batch: sample(completedAt: 11)))
        router.begin(newWatch)
        XCTAssertNil(router.observe(
            operationID: first,
            batch: sample(completedAt: 21)))
        _ = router.observe(
            operationID: second,
            batch: sample(completedAt: 21.2, batchID: 4))
        assertEvaluation(
            try XCTUnwrap(router.finalize(operationID: second, at: 25)),
            result: .confirmed,
            scope: .portTransition,
            reasonContains: "post-dispatch DFU transition")
    }

    func testEX01_PathBBatchReplayExcludesCrossDispatchSample() {
        var watch = makeWatch(
            baseline: baseline(at: 0, mode: .connected, ecid: "A"),
            clickedAt: 0)
        _ = watch.observe(sample(
            completedAt: 0.5,
            startedAt: 0.05))
        _ = watch.observe(sample(
            completedAt: 1.45,
            startedAt: 1.40,
            ecid: "A",
            batchID: 3))
        dispatch(&watch, at: 0.10, confirmed: true)
        assertEvaluation(
            final(&watch, at: 2.5),
            result: .confirmed,
            scope: .sameDevice,
            reasonContains: "matching ECID")
    }

    func testEX02_ThreeSyntheticM2RunsReplayAsSameDevice() {
        let runs: [(baseline: TimeInterval, first: TimeInterval, stable: TimeInterval)] = [
            (-0.195, 1.607, 3.406),
            (-0.127, 1.483, 3.286),
            (-0.0004, 1.415, 3.203),
        ]
        for (index, run) in runs.enumerated() {
            var watch = makeWatch(
                baseline: baseline(at: run.baseline, mode: .connected, ecid: "SYNTH"),
                clickedAt: 0)
            dispatch(&watch, at: 0.10)
            _ = watch.observe(sample(
                completedAt: run.first,
                ecid: "SYNTH",
                batchID: UInt64(10 + index)))
            _ = watch.observe(sample(
                completedAt: run.stable,
                ecid: "SYNTH",
                batchID: UInt64(20 + index)))
            let result = final(&watch, at: 5)
            XCTAssertEqual(result.result, .confirmed, "run \(index + 1)")
            XCTAssertEqual(result.scope, .sameDevice, "run \(index + 1)")
        }
    }

    func testEX03_NoReceiptNeverConfirmsAfterWindow() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch, at: 10.1, confirmed: false)
        _ = watch.observe(sample(completedAt: 11))
        let result = watch.expireIfNeeded(at: 25.1)
        assertEvaluation(
            result,
            result: .observed,
            reasonContains: "before a confirmed command receipt")
    }

    func testEX04_ConfirmedOutcomeSurvivesLaterExpiry() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 11))
        _ = watch.observe(sample(completedAt: 12, batchID: 3))
        let expired = watch.expireIfNeeded(at: 30)
        XCTAssertEqual(expired.result, .confirmed)
    }

    func testEX05_NewOperationInvalidatesOnlyOldWatch() {
        let oldID = UUID()
        let newID = UUID()
        var oldWatch = makeWatch(baseline: baseline())
        oldWatch.operationID = oldID
        dispatch(&oldWatch)
        var newWatch = makeWatch(baseline: baseline(at: 19.8), clickedAt: 20)
        newWatch.operationID = newID
        dispatch(&newWatch, at: 20)
        var router = DFUObservationRouter()
        router.begin(oldWatch)
        router.begin(newWatch)
        XCTAssertNil(router.observe(
            operationID: oldID,
            batch: sample(completedAt: 21)))
        XCTAssertNotNil(router.observe(
            operationID: newID,
            batch: sample(completedAt: 21.2, batchID: 4)))
    }

    func testEX06_InvalidObserverReadsDoNotFabricateEvidence() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch)
        _ = watch.observe(sample(
            completedAt: 10.5,
            mode: .dfu,
            valid: false))
        let evaluation = watch.expireIfNeeded(at: 25.1)
        assertEvaluation(
            evaluation,
            result: .unknown,
            reasonContains: "without qualified DFU evidence")
        XCTAssertEqual(evaluation.currentTargetState, .unknown)
    }

    func testEX07_WindowExpiresWithoutNewSnapshots() {
        var watch = makeWatch(baseline: baseline())
        dispatch(&watch, at: 10.1, confirmed: true)
        let evaluation = watch.expireIfNeeded(at: 25.1)
        assertEvaluation(
            evaluation,
            result: .unknown,
            reasonContains: "without qualified DFU evidence")
    }

    func testUI01_ConfirmedEvaluationProjectsExactlyOnce() {
        var watch = makeWatch(baseline: baseline())
        let operationID = watch.operationID
        var events: [DFUConfirmationProjection] = []
        let observer = NotificationCenter.default.addObserver(
            forName: .mraDFUConfirmationProjected,
            object: nil,
            queue: nil
        ) { notification in
            guard
                let event = notification.object
                    as? DFUConfirmationProjection,
                event.operationID == operationID
            else {
                return
            }
            events.append(event)
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        dispatch(&watch)
        _ = watch.observe(sample(completedAt: 11))
        _ = watch.observe(sample(completedAt: 12, batchID: 3))
        _ = watch.observe(sample(completedAt: 13, batchID: 4))
        _ = final(&watch, at: 25)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.targetPortKey, target)
        XCTAssertEqual(events.first?.scope, .portTransition)
    }
}

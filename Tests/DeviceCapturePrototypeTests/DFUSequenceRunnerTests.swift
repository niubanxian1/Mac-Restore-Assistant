import XCTest
@testable import DeviceCapturePrototype
import MRAHelperProtocol

final class DFUSequenceRunnerTests: XCTestCase {
    private let target = DFUSequenceTarget(controller: "100000813", portNumber: 2, rid: 1)

    func testShortFirstCompletesAndSecondStartsNear1500ms() async {
        let lock = NSLock()
        var calls: [(id: String, at: Date, target: DFUSequenceTarget)] = []
        let runner = DFUSequenceRunner { id, target in
            lock.lock(); calls.append((id, Date(), target)); lock.unlock()
            return HelperResponse(requestID: id, ok: true, dispatchTruth: "REQUEST_SENT",
                                  exitCode: 0, reason: "")
        }
        let start = Date()
        let result = await runner.run(sequenceID: "seq-short", target: target, startedAt: start)
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(Set(calls.map(\.id)), ["seq-short-1", "seq-short-2"])
        XCTAssertTrue(calls.allSatisfy { $0.target == target })
        XCTAssertEqual(result.first.requestID, "seq-short-1")
        XCTAssertEqual(result.second.requestID, "seq-short-2")
        let secondDelay = result.second.dispatchedAt.timeIntervalSince(start)
        XCTAssertGreaterThan(secondDelay, 1.30)
        XCTAssertLessThan(secondDelay, 2.20, "second send was serialized or badly delayed")
        XCTAssertEqual(result.second.response.dispatchTruth, "REQUEST_SENT")
    }

    func testLongFirstDoesNotQueueSecondBehindFirstProcess() async {
        let lock = NSLock()
        var firstStarted: Date?
        var secondStarted: Date?
        let runner = DFUSequenceRunner { id, _ in
            if id.hasSuffix("-1") {
                lock.lock(); firstStarted = Date(); lock.unlock()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            } else {
                lock.lock(); secondStarted = Date(); lock.unlock()
            }
            return HelperResponse(requestID: id, ok: true, dispatchTruth: "REQUEST_SENT",
                                  exitCode: 0, reason: "")
        }
        let start = Date()
        let result = await runner.run(sequenceID: "seq-long", target: target, startedAt: start)
        let firstAt = try? XCTUnwrap(firstStarted)
        let secondAt = try? XCTUnwrap(secondStarted)
        XCTAssertNotNil(firstAt)
        XCTAssertNotNil(secondAt)
        let delta = secondAt!.timeIntervalSince(firstAt!)
        XCTAssertGreaterThan(delta, 1.30)
        XCTAssertLessThan(delta, 2.20, "second waited for first backend completion")
        XCTAssertEqual(result.second.response.dispatchTruth, "REQUEST_SENT")
    }

    func testFirstBackendFailureDoesNotCancelSecond() async {
        let lock = NSLock()
        var ids: [String] = []
        let runner = DFUSequenceRunner { id, _ in
            lock.lock(); ids.append(id); lock.unlock()
            if id.hasSuffix("-1") {
                return HelperResponse(requestID: id, ok: false, dispatchTruth: "NOT_DISPATCHED",
                                      exitCode: 1, reason: "BACKEND_FAILED")
            }
            return HelperResponse(requestID: id, ok: true, dispatchTruth: "REQUEST_SENT",
                                  exitCode: 0, reason: "")
        }
        let result = await runner.run(sequenceID: "seq-fail", target: target)
        XCTAssertEqual(ids, ["seq-fail-1", "seq-fail-2"])
        XCTAssertFalse(result.first.response.ok)
        XCTAssertTrue(result.second.response.ok)
        XCTAssertEqual(result.second.response.dispatchTruth, "REQUEST_SENT")
    }

    func testNoThirdSendAndFrozenTarget() async {
        let lock = NSLock()
        var calls: [(String, DFUSequenceTarget)] = []
        let runner = DFUSequenceRunner { id, target in
            lock.lock(); calls.append((id, target)); lock.unlock()
            return HelperResponse(requestID: id, ok: true, dispatchTruth: "REQUEST_SENT",
                                  exitCode: 0, reason: "")
        }
        let frozen = target
        let result = await runner.run(sequenceID: "seq-once", target: frozen)
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls.allSatisfy { $0.1 == frozen })
        XCTAssertEqual(result.target, frozen)
    }
}

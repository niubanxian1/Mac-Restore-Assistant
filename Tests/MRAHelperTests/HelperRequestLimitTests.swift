import XCTest
@testable import MRAHelperCore

final class HelperRequestLimitTests: XCTestCase {
    func testMaxRequestBytesIsCappedAndFinite() {
        XCTAssertEqual(MRAHelperCore.maxRequestBytes, 64 * 1024)
        XCTAssertGreaterThan(MRAHelperCore.maxRequestBytes, 0)
        XCTAssertLessThanOrEqual(MRAHelperCore.maxRequestBytes, 64 * 1024)
    }

    func testOversizedChunkWithoutNewlineIsRejected() {
        var buffer = Data()
        let incoming = Data(repeating: 0x41, count: MRAHelperCore.maxRequestBytes + 1)
        let result = MRAHelperCore.accumulateRequest(buffer: &buffer, incoming: incoming)
        XCTAssertEqual(result, .tooLarge)
    }

    func testNewlineAfterTheLimitIsRejected() {
        var buffer = Data()
        var incoming = Data(repeating: 0x41, count: MRAHelperCore.maxRequestBytes + 1)
        incoming.append(0x0A)
        let result = MRAHelperCore.accumulateRequest(buffer: &buffer, incoming: incoming)
        XCTAssertEqual(result, .tooLarge)
    }

    func testLineExactlyAtTheLimitIsAccepted() {
        var buffer = Data()
        var incoming = Data(repeating: 0x41, count: MRAHelperCore.maxRequestBytes)
        incoming[incoming.count - 1] = 0x0A
        let result = MRAHelperCore.accumulateRequest(buffer: &buffer, incoming: incoming)
        guard case .complete(let line) = result else {
            return XCTFail("expected complete, got \(result)")
        }
        XCTAssertEqual(line.count, MRAHelperCore.maxRequestBytes - 1)
        XCTAssertFalse(line.contains(0x0A))
    }

    func testNormalJSONLineIsAccepted() {
        var buffer = Data()
        let json = "{\"action\":\"status\",\"requestID\":\"r1\",\"controller\":\"c\",\"portNumber\":1,\"rid\":1}\n"
        let result = MRAHelperCore.accumulateRequest(buffer: &buffer, incoming: Data(json.utf8))
        guard case .complete(let line) = result else {
            return XCTFail("expected complete, got \(result)")
        }
        XCTAssertTrue(String(data: line, encoding: .utf8)?.contains("requestID") == true)
    }

    func testSplitChunksStayUnderTheLimitUntilComplete() {
        var buffer = Data()
        XCTAssertEqual(
            MRAHelperCore.accumulateRequest(buffer: &buffer, incoming: Data("{\"action\"".utf8)),
            .needMore)
        let result = MRAHelperCore.accumulateRequest(buffer: &buffer, incoming: Data(":\"status\"}\n".utf8))
        guard case .complete = result else {
            return XCTFail("expected complete, got \(result)")
        }
    }

    func testReadTimesOutAtTheDeadline() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(
            MRAHelperCore.readHasTimedOut(
                startedAt: start,
                now: start.addingTimeInterval(MRAHelperCore.connectionReadTimeout - 0.01)))
        XCTAssertTrue(
            MRAHelperCore.readHasTimedOut(
                startedAt: start,
                now: start.addingTimeInterval(MRAHelperCore.connectionReadTimeout)))
    }

    func testLimiterRejectsConnectionsAboveTheCap() {
        let limiter = MRAHelperCore.ConnectionLimiter(maxConcurrent: 2)
        XCTAssertTrue(limiter.tryBegin())
        XCTAssertTrue(limiter.tryBegin())
        XCTAssertFalse(limiter.tryBegin(), "third connection must be rejected at capacity 2")
        limiter.end()
        XCTAssertTrue(limiter.tryBegin(), "a slot must free after end()")
    }

    func testDefaultConnectionCapIsFiniteAndMatchesListenBacklog() {
        XCTAssertEqual(MRAHelperCore.maxConcurrentConnections, 8)
    }
}

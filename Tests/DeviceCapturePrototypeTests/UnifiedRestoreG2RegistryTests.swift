import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class UnifiedRestoreG2RegistryTests: XCTestCase {
    func testCapacityTwoAcceptsTwoDistinctAttemptsAndRejectsThird() throws {
        let registry = RestoreTaskRegistry(capacity: 2)
        let a = UUID(), b = UUID(), c = UUID()
        try registry.reserve(
            attemptID: a,
            canonicalECID: "0000000000000001",
            portKey: "left-top")
        try registry.reserve(
            attemptID: b,
            canonicalECID: "0000000000000002",
            portKey: "right-top")
        XCTAssertEqual(registry.activeCount, 2)
        XCTAssertThrowsError(try registry.reserve(
            attemptID: c,
            canonicalECID: "0000000000000003",
            portKey: "left-bottom")) {
            XCTAssertEqual(
                $0 as? RestoreTaskAdmissionError,
                .capacityExceeded(limit: 2))
        }
        XCTAssertEqual(registry.activeCount, 2)
    }

    func testDuplicateECIDAndPortAreRejectedWithoutLeakingSlots() throws {
        let registry = RestoreTaskRegistry(capacity: 2)
        try registry.reserve(
            attemptID: UUID(),
            canonicalECID: "0000000000000001",
            portKey: "left-top")
        XCTAssertThrowsError(try registry.reserve(
            attemptID: UUID(),
            canonicalECID: "0000000000000001",
            portKey: "right-top")) {
            XCTAssertEqual($0 as? RestoreTaskAdmissionError, .duplicateECID)
        }
        XCTAssertThrowsError(try registry.reserve(
            attemptID: UUID(),
            canonicalECID: "0000000000000002",
            portKey: "left-top")) {
            XCTAssertEqual($0 as? RestoreTaskAdmissionError, .duplicatePort)
        }
        XCTAssertEqual(registry.activeCount, 1)
    }
}

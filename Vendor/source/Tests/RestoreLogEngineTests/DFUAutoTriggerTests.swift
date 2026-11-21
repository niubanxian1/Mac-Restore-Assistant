import XCTest
@testable import RestoreLogEngine

final class DFUAutoTriggerTests: XCTestCase {

    // AUTO-01 / AUTO-02
    func testAUTO01FirstDFUCandidateRequestsStart() {
        var t = DFUAutoTrigger()
        XCTAssertEqual(t.observeDFUCandidate(registryEntryID: 1, ecid: "A"),
                       .startCapture(trigger: "first-dfu-candidate"))
        XCTAssertEqual(t.state, .startPending)
    }

    // AUTO-05 / AUTO-06
    func testAUTO05DuplicateNotificationDoesNotRestart() {
        var t = DFUAutoTrigger()
        _ = t.observeDFUCandidate(registryEntryID: 1, ecid: "A")
        t.captureDidStart()
        XCTAssertEqual(t.observeDFUCandidate(registryEntryID: 1, ecid: "A"),
                       .ignore(reason: "already capturing"))
        XCTAssertEqual(t.state, .capturing)
    }

    // AUTO-07
    func testAUTO07EventDuringPendingStartIsIgnored() {
        var t = DFUAutoTrigger()
        _ = t.observeDFUCandidate(registryEntryID: 1, ecid: "A")
        XCTAssertEqual(t.observeDFUCandidate(registryEntryID: 1, ecid: "A"),
                       .ignore(reason: "start already pending"))
    }

    // AUTO-09 / AUTO-17
    func testAUTO09RemovalDoesNotStopCapture() {
        var t = DFUAutoTrigger()
        _ = t.observeDFUCandidate(registryEntryID: 1, ecid: "A")
        t.captureDidStart()
        XCTAssertEqual(t.deviceRemoved(registryEntryID: 1),
                       .ignore(reason: "removal does not affect capture"))
        XCTAssertEqual(t.state, .capturing, "a USB drop must never end a capture")
    }

    // AUTO-10
    func testAUTO10RegistryIDChangeDoesNotCreateSecondSession() {
        var t = DFUAutoTrigger()
        _ = t.observeDFUCandidate(registryEntryID: 1, ecid: "A")
        t.captureDidStart()
        _ = t.deviceRemoved(registryEntryID: 1)
        // Re-enumeration arrives with a new registry id, same ECID.
        XCTAssertEqual(t.observeDFUCandidate(registryEntryID: 2, ecid: "A"),
                       .ignore(reason: "already capturing"))
    }

    // AUTO-12
    func testAUTO12TwoDFUCandidatesAreAmbiguous() {
        var t = DFUAutoTrigger()
        _ = t.observeDFUCandidate(registryEntryID: 1, ecid: "A")
        XCTAssertEqual(t.observeDFUCandidateWhileOthersPresent(registryEntryID: 2, ecid: "B"),
                       .ambiguousDevices(count: 2))
    }

    // AUTO-11
    func testAUTO11MissingECIDDoesNotInventIdentity() {
        var t = DFUAutoTrigger()
        XCTAssertEqual(t.observeDFUCandidate(registryEntryID: 7, ecid: nil),
                       .startCapture(trigger: "first-dfu-candidate"))
        XCTAssertNil(t.presentDFU[7] ?? nil)
    }

    // AUTO-13
    func testAUTO13ManualStopSuppressesWhileDeviceStaysInDFU() {
        var t = DFUAutoTrigger()
        _ = t.observeDFUCandidate(registryEntryID: 1, ecid: "A")
        t.captureDidStart()
        t.manualStopRequested()
        XCTAssertEqual(t.state, .stopPending)
        t.manualStopCompleted()
        XCTAssertEqual(t.state, .suppressedUntilRearm)
        // The device is still in DFU to this day; it must not reopen a session.
        XCTAssertEqual(t.observeDFUCandidate(registryEntryID: 1, ecid: "A"),
                       .ignore(reason: "suppressed until rearm"))
    }

    // AUTO-14 / AUTO-20
    func testAUTO14LateEventAfterManualStopDoesNotRestart() {
        var t = DFUAutoTrigger()
        _ = t.observeDFUCandidate(registryEntryID: 1, ecid: "A")
        t.captureDidStart()
        t.manualStopRequested(); t.manualStopCompleted()
        _ = t.deviceRemoved(registryEntryID: 1)
        XCTAssertEqual(t.observeDFUCandidate(registryEntryID: 9, ecid: "A"),
                       .ignore(reason: "suppressed until rearm"))
    }

    // AUTO-19
    func testAUTO19ExplicitRearmAllowsANewEpisode() {
        var t = DFUAutoTrigger()
        _ = t.observeDFUCandidate(registryEntryID: 1, ecid: "A")
        t.captureDidStart()
        t.manualStopRequested(); t.manualStopCompleted()
        t.rearm()
        XCTAssertEqual(t.state, .idle)
        XCTAssertEqual(t.observeDFUCandidate(registryEntryID: 5, ecid: "C"),
                       .startCapture(trigger: "first-dfu-candidate"))
    }

    // AUTO-15
    func testAUTO15FailedStartReturnsToIdleAndIsNotSilent() {
        var t = DFUAutoTrigger()
        _ = t.observeDFUCandidate(registryEntryID: 1, ecid: "A")
        t.captureFailedToStart()
        XCTAssertEqual(t.state, .idle)
    }

    // AUTO-18
    func testAUTO18ManualStartRacingWithAutoDoesNotDoubleSession() {
        var t = DFUAutoTrigger()
        _ = t.observeDFUCandidate(registryEntryID: 1, ecid: "A")   // auto asked
        t.captureDidStart()                                        // manual started it
        XCTAssertEqual(t.observeDFUCandidate(registryEntryID: 1, ecid: "A"),
                       .ignore(reason: "already capturing"))
        XCTAssertEqual(t.state, .capturing)
    }

    // AUTO-21
    func testAUTO21NoAutomaticRetryAfterFailure() {
        var t = DFUAutoTrigger()
        _ = t.observeDFUCandidate(registryEntryID: 1, ecid: "A")
        t.captureFailedToStart()
        XCTAssertEqual(t.state, .idle, "the trigger does not retry by itself")
        XCTAssertEqual(t.observeDFUCandidate(registryEntryID: 1, ecid: "A").isStartRequested,
                       true, "a fresh observation may ask again — the caller decides")
    }
}

private extension DFUAutoTrigger.Decision {
    var isStartRequested: Bool { if case .startCapture = self { return true }; return false }
}

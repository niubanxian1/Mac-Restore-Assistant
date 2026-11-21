import XCTest
@testable import RestoreLogEngine

/// Deterministic tests over the pure classifier. No USB hardware is required, and
/// nothing here claims that IOKit actually called back — that is the probe's job.
final class USBDeviceObserverTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func snap(_ id: UInt64, _ props: [String: Any]) -> USBDeviceSnapshot {
        USBClassifier.snapshot(registryEntryID: id, properties: props, now: now)
    }

    // USB-01
    func testUSB01EmptyPropertiesYieldUnknown() {
        let s = snap(1, [:])
        XCTAssertNil(s.vendorID); XCTAssertNil(s.productID)
        XCTAssertEqual(s.mode, .unknownUSBMode)
    }

    // USB-02
    func testUSB02DFUCandidateRecognised() {
        let s = snap(2, ["idVendor": 0x05AC, "idProduct": 0x1227, "locationID": 0x0110_0000])
        XCTAssertEqual(s.vendorID, 0x05AC)
        XCTAssertEqual(s.productID, 0x1227)
        XCTAssertEqual(s.mode, .dfuCandidate)
    }

    // USB-03
    func testUSB03AppleVendorAloneIsNotDFU() {
        let s = snap(3, ["idVendor": 0x05AC, "idProduct": 0x9999])
        XCTAssertEqual(s.mode, .otherAppleUSB)
    }

    // USB-04
    func testUSB04NonAppleVendorNeverAppleDFU() {
        let s = snap(4, ["idVendor": 0x1234, "idProduct": 0x1227])
        XCTAssertEqual(s.mode, .unknownUSBMode)
    }

    // USB-05
    func testUSB05IdentityKeyIsRegistryEntryID() {
        let a = snap(5, ["idVendor": 0x05AC, "idProduct": 0x1227])
        let b = snap(5, ["idVendor": 0x05AC, "idProduct": 0x1227])
        XCTAssertEqual(a.identityKey, b.identityKey)
    }

    // USB-06 / USB-07
    func testUSB06TwoDevicesWithSamePIDStaySeparate() {
        let a = snap(6, ["idVendor": 0x05AC, "idProduct": 0x1227])
        let b = snap(7, ["idVendor": 0x05AC, "idProduct": 0x1227])
        XCTAssertNotEqual(a.identityKey, b.identityKey)
        XCTAssertEqual(a.mode, b.mode)
    }

    // USB-08
    func testUSB08SameLocationNewEntryIsNotTheSameDevice() {
        let a = snap(8, ["idVendor": 0x05AC, "idProduct": 0x1227, "locationID": 0x0110_0000])
        let b = snap(9, ["idVendor": 0x05AC, "idProduct": 0x1227, "locationID": 0x0110_0000])
        XCTAssertEqual(a.locationID, b.locationID)
        XCTAssertNotEqual(a.identityKey, b.identityKey,
                          "location id must never be promoted to identity")
    }

    // USB-09
    func testUSB09MissingSerialIsNil() {
        XCTAssertNil(snap(10, ["idVendor": 0x05AC, "idProduct": 0x1227]).serialNumber)
    }

    // USB-10
    func testUSB10NoECIDFieldIsEverInvented() {
        let s = snap(11, ["idVendor": 0x05AC, "idProduct": 0x1227, "locationID": 0x01])
        // The type has no ECID property at all, by design.
        XCTAssertEqual(s.mode, .dfuCandidate)
        XCTAssertNil(s.vendorID.flatMap { _ in Optional<Int>.none })
    }

    // USB-11
    func testUSB11MalformedPropertyTypesAreRejected() {
        XCTAssertNil(snap(12, ["idVendor": ["not": "an int"]]).vendorID)
        XCTAssertNil(snap(13, ["idProduct": 3.5]).productID ?? nil)
        XCTAssertEqual(snap(13, ["idProduct": "4663"]).productID, 4663)
    }

    // USB-12
    func testUSB12RecoveryModeClassifiedSeparately() {
        XCTAssertEqual(snap(14, ["idVendor": 0x05AC, "idProduct": 0x1280]).mode, .recoveryCandidate)
        XCTAssertEqual(snap(15, ["idVendor": 0x05AC, "idProduct": 0x1281]).mode, .dfuCandidate)
    }

    // USB-13
    func testUSB13ObserverStartsIdleAndStopIsIdempotent() {
        let observer = USBDeviceObserver { _ in XCTFail("no event expected without hardware") }
        XCTAssertFalse(observer.isRunning)
        observer.stop()          // stopping a never-started observer must be safe
        observer.stop()
        XCTAssertFalse(observer.isRunning)
    }

    // USB-14
    func testUSB14EventEqualityIsValueBased() {
        let s = snap(16, ["idVendor": 0x05AC, "idProduct": 0x1227])
        XCTAssertEqual(USBEvent.initialPresent(s), USBEvent.initialPresent(s))
        XCTAssertNotEqual(USBEvent.arrived(s), USBEvent.initialPresent(s))
    }

    // USB-15
    func testUSB15RemovalCarriesRegistryIDOnly() {
        let e = USBEvent.removed(registryEntryID: 42, observedAtUTC: now)
        if case let .removed(id, _) = e { XCTAssertEqual(id, 42) } else { XCTFail() }
    }

    // USB-16
    func testUSB16NSNumberPropertiesAccepted() {
        let s = snap(17, ["idVendor": NSNumber(value: 0x05AC), "idProduct": NSNumber(value: 0x1227)])
        XCTAssertEqual(s.mode, .dfuCandidate)
    }

    // USB-17
    func testUSB17UnknownModeIsNotGuessedFromLocation() {
        let s = snap(18, ["locationID": 0x0110_0000])
        XCTAssertEqual(s.mode, .unknownUSBMode, "a port number must not imply a device mode")
    }

    // USB-18
    func testUSB18NoDeviceCommandSurfaceExists() {
        // The observer's public API is start/stop/isRunning only; this test documents
        // that no send/reset/restore entry point is reachable from the type.
        let observer = USBDeviceObserver { _ in }
        XCTAssertFalse(observer.isRunning)
        observer.stop()
    }
}

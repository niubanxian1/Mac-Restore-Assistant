import XCTest
@testable import DeviceCapturePrototype

final class USBConnectionTimelineTests: XCTestCase {
    private let session = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let batch = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func observation(
        sequence: UInt64,
        direction: USBConnectionTimelineDirection,
        at seconds: TimeInterval,
        registryID: UInt64?,
        ecid: String? = "0011223344556677",
        mode: USBConnectionTimelineMode = .dfu,
        portKey: String? = "left2",
        location: String? = "01100000"
    ) -> USBConnectionTimelineObservation {
        USBConnectionTimelineObservation(
            sessionID: session,
            sequence: sequence,
            batchID: batch,
            observedAtUTC: Date(timeIntervalSince1970: 1_800_000_000 + seconds),
            monotonicSeconds: seconds,
            direction: direction,
            registryEntryID: registryID,
            locationID: location,
            mode: mode,
            vendorID: 0x05AC,
            productID: mode == .dfu ? 0x1281 : 0x1280,
            ecid: ecid,
            productName: mode == .dfu ? "Apple Mobile Device (DFU Mode)" : "Mac",
            deviceClass: 0,
            assignment: USBPortTimelineAssignment(
                portKey: portKey,
                portLabel: portKey == nil ? nil : "左侧下方",
                evidence: portKey == nil ? "USB location 未获可信端口归属" : "精确校准",
                isConfirmed: portKey != nil),
            retainedAttributes: false)
    }

    private func tracker() -> USBConnectionTimelineTracker {
        var tracker = USBConnectionTimelineTracker()
        tracker.beginSession(
            id: session,
            wallTime: Date(timeIntervalSince1970: 1_800_000_000),
            monotonicSeconds: 0)
        tracker.setCoverage(.complete)
        return tracker
    }

    func testSinglePortTraceDeliversResidenceIntervalAndCounts() throws {
        var tracker = tracker()
        tracker.ingest([
            observation(sequence: 1, direction: .arrived, at: 1, registryID: 1001),
            observation(sequence: 2, direction: .removed, at: 4, registryID: 1001),
            observation(
                sequence: 3,
                direction: .arrived,
                at: 7,
                registryID: 1002,
                ecid: "0011223344556677",
                mode: .recovery),
        ])

        let snapshot = tracker.snapshot(
            for: "left2",
            label: "左侧下方",
            nowMonotonicSeconds: 9,
            nowWallTime: Date(timeIntervalSince1970: 1_800_000_009))

        XCTAssertEqual(try XCTUnwrap(snapshot.currentResidenceSeconds), 2, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(snapshot.lastResidenceSeconds), 3, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(snapshot.lastReappearanceGapSeconds), 3, accuracy: 0.001)
        XCTAssertEqual(snapshot.portReappearancesIn60Seconds, 1)
        XCTAssertEqual(snapshot.sameMachineReenumerationsIn60Seconds, 1)
        XCTAssertEqual(snapshot.recentEvents.count, 3)

        let expired = tracker.snapshot(
            for: "left2",
            label: "左侧下方",
            nowMonotonicSeconds: 67,
            nowWallTime: Date(timeIntervalSince1970: 1_800_000_067))
        XCTAssertEqual(expired.portReappearancesIn60Seconds, 0)
    }

    func testDifferentKnownECIDCountsPortReturnButNotSameMachine() {
        var tracker = tracker()
        tracker.ingest([
            observation(sequence: 1, direction: .arrived, at: 1, registryID: 2001, ecid: "AAAAAAAAAAAAAAAA"),
            observation(sequence: 2, direction: .removed, at: 2, registryID: 2001, ecid: "AAAAAAAAAAAAAAAA"),
            observation(sequence: 3, direction: .arrived, at: 3, registryID: 2002, ecid: "BBBBBBBBBBBBBBBB"),
        ])

        let snapshot = tracker.snapshot(
            for: "left2",
            label: "左侧下方",
            nowMonotonicSeconds: 4,
            nowWallTime: Date())
        XCTAssertEqual(snapshot.portReappearancesIn60Seconds, 1)
        XCTAssertEqual(snapshot.sameMachineReenumerationsIn60Seconds, 0)
        XCTAssertEqual(snapshot.lastReconnectionIdentity, .changedMachine)
    }

    func testMissingECIDKeepsSameMachineResultUnknown() {
        var tracker = tracker()
        tracker.ingest([
            observation(sequence: 1, direction: .arrived, at: 1, registryID: 2101, ecid: nil),
            observation(sequence: 2, direction: .removed, at: 2, registryID: 2101, ecid: nil),
            observation(sequence: 3, direction: .arrived, at: 3, registryID: 2102, ecid: nil),
        ])

        let snapshot = tracker.snapshot(
            for: "left2",
            label: "左侧下方",
            nowMonotonicSeconds: 4,
            nowWallTime: Date())
        XCTAssertEqual(snapshot.portReappearancesIn60Seconds, 1)
        XCTAssertNil(snapshot.sameMachineReenumerationsIn60Seconds)
        XCTAssertEqual(snapshot.lastReconnectionIdentity, .unknown)
    }

    func testInitialPresenceHasUnknownAppearanceStartAndNoHistoryCount() throws {
        var tracker = tracker()
        tracker.ingest([
            observation(sequence: 1, direction: .initialPresent, at: 1, registryID: 3001)
        ])

        let snapshot = tracker.snapshot(
            for: "left2",
            label: "左侧下方",
            nowMonotonicSeconds: 10,
            nowWallTime: Date())
        XCTAssertNil(snapshot.currentResidenceSeconds)
        XCTAssertEqual(try XCTUnwrap(snapshot.observedAtLeastSeconds), 10, accuracy: 0.001)
        XCTAssertEqual(snapshot.currentPresence?.startKind, .sessionStart)
        XCTAssertTrue(snapshot.recentEvents.isEmpty)
        XCTAssertEqual(snapshot.portReappearancesIn60Seconds, 0)
    }

    func testDuplicateArrivalAndOrphanRemovalDoNotFabricateIntervals() {
        var tracker = tracker()
        tracker.ingest([
            observation(sequence: 1, direction: .arrived, at: 1, registryID: 4001),
            observation(sequence: 2, direction: .arrived, at: 2, registryID: 4001),
            observation(sequence: 3, direction: .removed, at: 3, registryID: 4999),
        ])

        let snapshot = tracker.snapshot(
            for: "left2",
            label: "左侧下方",
            nowMonotonicSeconds: 4,
            nowWallTime: Date())
        XCTAssertEqual(snapshot.recentEvents.count, 2)
        XCTAssertNil(snapshot.lastResidenceSeconds)
        XCTAssertTrue(snapshot.isIncomplete)
        XCTAssertTrue(snapshot.incompleteReasons.contains(.unmatchedRemoval))
    }

    func testRegistrationFailureMarksSessionIncompleteWithoutDroppingControlEvents() {
        var tracker = tracker()
        tracker.setCoverage(.incomplete(.terminatedRegistrationFailed))
        tracker.ingest([
            observation(sequence: 1, direction: .arrived, at: 1, registryID: 5001)
        ])
        let snapshot = tracker.snapshot(
            for: "left2",
            label: "左侧下方",
            nowMonotonicSeconds: 2,
            nowWallTime: Date())

        XCTAssertEqual(snapshot.recentEvents.count, 1)
        XCTAssertTrue(snapshot.isIncomplete)
        XCTAssertTrue(snapshot.incompleteReasons.contains(.terminatedRegistrationFailed))
    }

    func testClearWhileActiveResetsBaselineWithoutInventingAnAppearance() {
        var tracker = tracker()
        tracker.ingest([
            observation(sequence: 1, direction: .arrived, at: 1, registryID: 6001)
        ])
        tracker.clear(portKey: "left2", monotonicSeconds: 5, wallTime: Date())
        tracker.ingest([
            observation(sequence: 2, direction: .removed, at: 8, registryID: 6001)
        ])
        let snapshot = tracker.snapshot(
            for: "left2",
            label: "左侧下方",
            nowMonotonicSeconds: 9,
            nowWallTime: Date())

        XCTAssertNil(snapshot.lastResidenceSeconds)
        XCTAssertEqual(snapshot.timelineOrigin, .clearedAt(5))
        XCTAssertTrue(snapshot.recentEvents.allSatisfy { $0.monotonicSeconds >= 5 })
    }

    func testPortsAreIsolatedAndHistoryIsBounded() {
        var tracker = tracker()
        tracker.ingest([
            observation(sequence: 1, direction: .arrived, at: 1, registryID: 7001, portKey: "left1"),
            observation(sequence: 2, direction: .arrived, at: 1, registryID: 7002, portKey: "left2"),
        ])
        let left1 = tracker.snapshot(for: "left1", label: "左侧上方",
                                     nowMonotonicSeconds: 2, nowWallTime: Date())
        let left2 = tracker.snapshot(for: "left2", label: "左侧下方",
                                     nowMonotonicSeconds: 2, nowWallTime: Date())

        XCTAssertEqual(left1.currentPresence?.registryEntryID, 7001)
        XCTAssertEqual(left2.currentPresence?.registryEntryID, 7002)
        XCTAssertEqual(left1.recentEvents.count, 1)
        XCTAssertEqual(left2.recentEvents.count, 1)
    }

    func testUnknownOwnershipIsRetainedButNeverPromotedToAPort() {
        var tracker = tracker()
        tracker.ingest([
            observation(sequence: 1, direction: .arrived, at: 1, registryID: 8001,
                        portKey: nil, location: "03100000")
        ])

        let left2 = tracker.snapshot(for: "left2", label: "左侧下方",
                                     nowMonotonicSeconds: 2, nowWallTime: Date())
        XCTAssertTrue(left2.recentEvents.isEmpty)
        XCTAssertNil(left2.currentPresence)
        XCTAssertEqual(tracker.unownedEvents(limit: 10).count, 1)
        XCTAssertTrue(tracker.unownedEvents(limit: 10)[0].assignment.evidence.contains("未获可信"))
    }

    func testLocationNormalizerKeepsDecimalAndHexStringsDistinct() {
        XCTAssertEqual(
            USBTimelineLocationNormalizer.normalize(NSNumber(value: 17_825_792)),
            "01100000")
        XCTAssertEqual(
            USBTimelineLocationNormalizer.normalize("0x01100000"),
            "01100000")
        XCTAssertEqual(
            USBTimelineLocationNormalizer.normalize("17825792"),
            "01100000")
        XCTAssertEqual(
            USBTimelineLocationNormalizer.normalize("0110000A"),
            "0110000A")
        XCTAssertEqual(
            USBTimelineLocationNormalizer.normalize("01100000"),
            "01100000")
    }

    func testModeChangeIsReportedWithoutChangingSameMachineClassification() {
        var tracker = tracker()
        tracker.ingest([
            observation(sequence: 1, direction: .arrived, at: 1, registryID: 9001, mode: .dfu),
            observation(sequence: 2, direction: .removed, at: 2, registryID: 9001, mode: .dfu),
            observation(sequence: 3, direction: .arrived, at: 3, registryID: 9002, mode: .recovery),
        ])
        let snapshot = tracker.snapshot(
            for: "left2",
            label: "左侧下方",
            nowMonotonicSeconds: 4,
            nowWallTime: Date())

        XCTAssertEqual(snapshot.lastReconnectionIdentity, .sameMachine)
        XCTAssertEqual(snapshot.recentEvents.first?.modeTransition, .changedMode)
    }

    func testMultipleActiveInstancesWithholdSingleCurrentAttribution() {
        var tracker = tracker()
        tracker.ingest([
            observation(sequence: 1, direction: .arrived, at: 1, registryID: 9101),
            observation(sequence: 2, direction: .arrived, at: 2, registryID: 9102),
        ])
        let snapshot = tracker.snapshot(
            for: "left2",
            label: "左侧下方",
            nowMonotonicSeconds: 3,
            nowWallTime: Date())

        XCTAssertNil(snapshot.currentPresence)
        XCTAssertNil(snapshot.currentResidenceSeconds)
        XCTAssertEqual(snapshot.activeInstanceCount, 2)
        XCTAssertTrue(snapshot.incompleteReasons.contains(.multipleActiveInstances))
    }

    func testHistoryAndReappearanceBuffersAreBoundedAndMarkedIncomplete() {
        var tracker = USBConnectionTimelineTracker(
            maxEventsPerPort: 10,
            maxReappearancesPerPort: 60)
        tracker.beginSession(
            id: session,
            wallTime: Date(),
            monotonicSeconds: 0)
        tracker.setCoverage(.complete)
        var observations: [USBConnectionTimelineObservation] = []
        for index in 0..<10 {
            let id = UInt64(10_000 + index)
            let start = Double(index * 2 + 1)
            observations.append(observation(
                sequence: UInt64(index * 2 + 1),
                direction: .arrived,
                at: start,
                registryID: id))
            observations.append(observation(
                sequence: UInt64(index * 2 + 2),
                direction: .removed,
                at: start + 0.2,
                registryID: id))
        }
        tracker.ingest(observations)
        let snapshot = tracker.snapshot(
            for: "left2",
            label: "左侧下方",
            nowMonotonicSeconds: 25,
            nowWallTime: Date())

        XCTAssertEqual(snapshot.recentEvents.count, 10)
        XCTAssertTrue(snapshot.isIncomplete)
        XCTAssertTrue(snapshot.incompleteReasons.contains(.historyOverflow))
        XCTAssertGreaterThan(snapshot.droppedEventCount, 0)
    }

    func testCopyTextUsesSameSnapshotAndExplicitTimeZone() {
        var tracker = tracker()
        tracker.ingest([
            observation(sequence: 1, direction: .arrived, at: 1, registryID: 9201)
        ])
        let snapshot = tracker.snapshot(
            for: "left2",
            label: "左侧下方",
            nowMonotonicSeconds: 2,
            nowWallTime: Date())
        let timeZone = try! XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let eventLine = USBConnectionTimelineFormatter.eventLine(
            try! XCTUnwrap(snapshot.recentEvents.first),
            timeZone: timeZone)
        let copy = USBConnectionTimelineFormatter.copyText(
            snapshot,
            timeZone: timeZone)

        XCTAssertTrue(eventLine.contains("+08:00"))
        XCTAssertTrue(copy.contains("Asia/Shanghai"))
        XCTAssertTrue(copy.contains(eventLine))
        XCTAssertFalse(copy.contains("当前驻留：未知"))
    }

    func testEnglishCopyUsesLocalizedTimingLabels() {
        let key = "ui.languageMode"
        let original = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set("en", forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        var tracker = tracker()
        tracker.ingest([
            observation(
                sequence: 1,
                direction: .arrived,
                at: 1,
                registryID: 9202)
        ])
        let copied = USBConnectionTimelineFormatter.copyText(
            tracker.snapshot(
                for: "left2",
                label: "左侧下方",
                nowMonotonicSeconds: 3,
                nowWallTime: Date()),
            timeZone: TimeZone(secondsFromGMT: 0)!)

        XCTAssertTrue(copied.contains("Current: DFU"))
        XCTAssertTrue(copied.contains("Current residence: 00:02.000"))
        XCTAssertTrue(
            copied.contains(
                "Port reappearances in the last 60 seconds: 0 times"))
        XCTAssertFalse(copied.contains("当前驻留"))
        XCTAssertFalse(copied.contains("最近 60 秒"))
    }
}

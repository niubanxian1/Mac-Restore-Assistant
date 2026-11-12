import XCTest
@testable import DeviceCapturePrototype

final class ConnectionChangeLogTests: XCTestCase {
    private func port(_ key: String, label: String, present: Bool, mode: ObservedDeviceMode? = nil, ecid: String? = nil) -> LocatedPortState {
        LocatedPortState(portKey: key, portLabel: label, present: present, mode: mode, ecid: ecid)
    }

    private func snapshot(ports: [LocatedPortState], unlocated: [UnlocatedDeviceState] = [], valid: Bool = true) -> PortConnectionSnapshot {
        PortConnectionSnapshot(isValid: valid, ports: Dictionary(uniqueKeysWithValues: ports.map { ($0.portKey, $0) }), unlocated: unlocated)
    }

    func testFirstSnapshotIsBaselineNotAnInsertEvent() {
        var engine = ConnectionChangeEngine()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let first = snapshot(ports: [
            port("right", label: "右侧", present: true, mode: .dfu, ecid: "AA"),
        ])
        let result = engine.ingest(first, at: t0)
        XCTAssertTrue(result.addedOrUpdated.isEmpty)
        XCTAssertTrue(engine.events.isEmpty)
        XCTAssertTrue(engine.eventsForPort("right").isEmpty)
    }

    func testRepeatedRefreshDoesNotAddRows() {
        var engine = ConnectionChangeEngine()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let snap = snapshot(ports: [
            port("right", label: "右侧", present: true, mode: .dfu, ecid: "AA"),
            port("left2", label: "左侧下方", present: false),
        ])
        _ = engine.ingest(snap, at: t0)
        let again = engine.ingest(snap, at: t0.addingTimeInterval(1))
        XCTAssertTrue(again.addedOrUpdated.isEmpty)
        XCTAssertTrue(engine.events.isEmpty)
    }

    func testFailedReadIsNotUnplug() {
        var engine = ConnectionChangeEngine()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let present = snapshot(ports: [port("right", label: "右侧", present: true, mode: .dfu, ecid: "AA")])
        _ = engine.ingest(present, at: t0)
        let appeared = snapshot(ports: [
            port("right", label: "右侧", present: true, mode: .dfu, ecid: "AA"),
            port("left2", label: "左侧下方", present: true, mode: .recovery, ecid: "BB"),
        ])
        _ = engine.ingest(appeared, at: t0.addingTimeInterval(2))
        XCTAssertEqual(engine.events.count, 1)
        let failed = engine.ingest(.failed(), at: t0.addingTimeInterval(3))
        XCTAssertTrue(failed.addedOrUpdated.isEmpty)
        XCTAssertEqual(engine.events.count, 1)
        XCTAssertFalse(engine.events.contains { $0.fact.contains("未枚举") })
    }

    func testUniqueChangeAndReconnectDurationWithECID() {
        var engine = ConnectionChangeEngine()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let emptyRight = port("right", label: "右侧", present: false)
        let emptyLeft = port("left2", label: "左侧下方", present: false)
        _ = engine.ingest(snapshot(ports: [emptyRight, emptyLeft]), at: t0)

        let appear = engine.ingest(snapshot(ports: [
            port("right", label: "右侧", present: true, mode: .dfu, ecid: "AA"),
            emptyLeft,
        ]), at: t0.addingTimeInterval(5))
        XCTAssertEqual(appear.uniqueChangedPortKey, "right")
        XCTAssertEqual(appear.addedOrUpdated.count, 1)
        XCTAssertTrue(appear.addedOrUpdated[0].isUniqueInterfaceChange)
        XCTAssertEqual(appear.addedOrUpdated[0].fact, "新出现 DFU 设备")
        XCTAssertEqual(appear.addedOrUpdated[0].portLabel, "右侧")

        let gone = engine.ingest(snapshot(ports: [emptyRight, emptyLeft]), at: t0.addingTimeInterval(10))
        XCTAssertEqual(gone.addedOrUpdated[0].fact, "设备暂时未枚举到")
        XCTAssertFalse(gone.addedOrUpdated[0].fact.contains("失败"))
        XCTAssertFalse(gone.addedOrUpdated[0].fact.contains("刷机"))

        let back = engine.ingest(snapshot(ports: [
            port("right", label: "右侧", present: true, mode: .recovery, ecid: "AA"),
            emptyLeft,
        ]), at: t0.addingTimeInterval(14.8))
        XCTAssertEqual(back.addedOrUpdated.count, 1)
        XCTAssertEqual(back.addedOrUpdated[0].fact, "同一设备于 4.8 秒后以 Recovery 重新出现")
        XCTAssertFalse(back.addedOrUpdated[0].fact.contains("完成"))
        XCTAssertEqual(engine.eventsForPort("right", limit: 3).count, 3)
        XCTAssertEqual(engine.eventsForPort("right", limit: 3).first?.fact, "同一设备于 4.8 秒后以 Recovery 重新出现")
    }

    func testReconnectWithoutECIDUsesPortWording() {
        var engine = ConnectionChangeEngine()
        let t0 = Date(timeIntervalSince1970: 2_000)
        let empty = port("right", label: "右侧", present: false)
        _ = engine.ingest(snapshot(ports: [empty]), at: t0)
        _ = engine.ingest(snapshot(ports: [port("right", label: "右侧", present: true, mode: .dfu, ecid: nil)]), at: t0.addingTimeInterval(1))
        _ = engine.ingest(snapshot(ports: [empty]), at: t0.addingTimeInterval(2))
        let back = engine.ingest(snapshot(ports: [port("right", label: "右侧", present: true, mode: .recovery, ecid: nil)]), at: t0.addingTimeInterval(5.2))
        XCTAssertEqual(back.addedOrUpdated[0].fact, "右侧于 3.2 秒后再次出现设备")
        XCTAssertFalse(back.addedOrUpdated[0].fact.contains("同一设备"))
    }

    func testSameDeviceRequiresECIDMatch() {
        var engine = ConnectionChangeEngine()
        let t0 = Date(timeIntervalSince1970: 3_000)
        let empty = port("right", label: "右侧", present: false)
        _ = engine.ingest(snapshot(ports: [empty]), at: t0)
        _ = engine.ingest(snapshot(ports: [port("right", label: "右侧", present: true, mode: .dfu, ecid: "AA")]), at: t0.addingTimeInterval(1))
        _ = engine.ingest(snapshot(ports: [empty]), at: t0.addingTimeInterval(2))
        let back = engine.ingest(snapshot(ports: [port("right", label: "右侧", present: true, mode: .recovery, ecid: "BB")]), at: t0.addingTimeInterval(4))
        XCTAssertEqual(back.addedOrUpdated[0].fact, "右侧于 2.0 秒后再次出现设备")
        XCTAssertFalse(back.addedOrUpdated[0].fact.contains("同一设备"))
    }

    func testUnclearPortDoesNotBorrowSelectedPort() {
        var engine = ConnectionChangeEngine()
        let t0 = Date(timeIntervalSince1970: 4_000)
        let left = port("left2", label: "左侧下方", present: false)
        _ = engine.ingest(snapshot(ports: [left]), at: t0)
        let result = engine.ingest(snapshot(ports: [left], unlocated: [
            UnlocatedDeviceState(id: "ecid:CC", mode: .dfu, ecid: "CC"),
        ]), at: t0.addingTimeInterval(1))
        XCTAssertEqual(result.addedOrUpdated.count, 1)
        XCTAssertEqual(result.addedOrUpdated[0].portLabel, "端口未确认")
        XCTAssertNil(result.addedOrUpdated[0].portKey)
        XCTAssertNotEqual(result.addedOrUpdated[0].portLabel, "左侧下方")
        XCTAssertTrue(engine.eventsForPort("left2").isEmpty)
    }

    func testTwoPortsChangingTogetherAreNotUnique() {
        var engine = ConnectionChangeEngine()
        let t0 = Date(timeIntervalSince1970: 5_000)
        let right = port("right", label: "右侧", present: false)
        let left = port("left2", label: "左侧下方", present: false)
        _ = engine.ingest(snapshot(ports: [right, left]), at: t0)
        let result = engine.ingest(snapshot(ports: [
            port("right", label: "右侧", present: true, mode: .dfu, ecid: "AA"),
            port("left2", label: "左侧下方", present: true, mode: .recovery, ecid: "BB"),
        ]), at: t0.addingTimeInterval(1))
        XCTAssertNil(result.uniqueChangedPortKey)
        XCTAssertEqual(result.changedPortKeys.sorted(), ["left2", "right"])
        XCTAssertEqual(result.addedOrUpdated.count, 2)
        XCTAssertTrue(result.addedOrUpdated.allSatisfy { $0.isUniqueInterfaceChange == false })
    }

    func testIdentityFillInDoesNotCreateASecondInterfaceChange() {
        var engine = ConnectionChangeEngine()
        let t0 = Date(timeIntervalSince1970: 6_000)
        let empty = port("right", label: "右侧", present: false)
        _ = engine.ingest(snapshot(ports: [empty]), at: t0)
        let first = engine.ingest(snapshot(ports: [
            port("right", label: "右侧", present: true, mode: nil, ecid: nil),
        ]), at: t0.addingTimeInterval(1))
        XCTAssertEqual(first.addedOrUpdated[0].fact, "设备插入")
        XCTAssertEqual(engine.events.count, 1)
        let filled = engine.ingest(snapshot(ports: [
            port("right", label: "右侧", present: true, mode: .dfu, ecid: "AA"),
        ]), at: t0.addingTimeInterval(1.2))
        XCTAssertEqual(engine.events.count, 1)
        XCTAssertEqual(engine.events[0].fact, "新出现 DFU 设备")
        XCTAssertEqual(engine.events[0].ecid, "AA")
        XCTAssertEqual(filled.addedOrUpdated.count, 1)
    }

    func testMaxThreeNewestFirstForOnePort() {
        var engine = ConnectionChangeEngine()
        let t0 = Date(timeIntervalSince1970: 7_000)
        var snap = snapshot(ports: [port("right", label: "右侧", present: false)])
        _ = engine.ingest(snap, at: t0)
        for i in 1...4 {
            snap = snapshot(ports: [port("right", label: "右侧", present: i % 2 == 1, mode: .dfu, ecid: "AA")])
            _ = engine.ingest(snap, at: t0.addingTimeInterval(Double(i)))
        }
        let shown = engine.eventsForPort("right", limit: 3)
        XCTAssertEqual(shown.count, 3)
        XCTAssertTrue(shown[0].timestamp >= shown[1].timestamp)
        XCTAssertTrue(shown[1].timestamp >= shown[2].timestamp)
        XCTAssertGreaterThan(engine.events.filter { $0.portKey == "right" }.count, 3)
    }
}

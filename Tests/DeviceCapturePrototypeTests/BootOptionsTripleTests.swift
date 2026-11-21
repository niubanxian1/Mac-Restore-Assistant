import XCTest
@testable import DeviceCapturePrototype
import MRAHelperProtocol

@MainActor
final class BootOptionsTripleTests: XCTestCase {
    func testRecoveryGuidanceOmitsGearInstructionInEveryLanguage() {
        let port = LiveHostPort(controller: "100000763", portNumber: 3, rid: 2)
        let model = makeModel(port: port) { _, _, _, _, requestID in
            HelperResponse(requestID: requestID, ok: true, dispatchTruth: "REQUEST_SENT",
                           exitCode: 0, reason: "REBOOT_REQUESTED")
        }
        let defaults = UserDefaults.standard
        let prior = defaults.object(forKey: "ui.languageMode")
        defer {
            if let prior {
                defaults.set(prior, forKey: "ui.languageMode")
            } else {
                defaults.removeObject(forKey: "ui.languageMode")
            }
        }

        let forbidden = ["齿轮", "齒輪", "gear", "歯車", "톱니", "Options", "オプション", "옵션"]
        for code in ["zh-Hans", "zh-Hant", "en", "ja", "ko"] {
            defaults.set(code, forKey: "ui.languageMode")
            let copy = L10n.t(model.recoveryReason)
            for phrase in forbidden {
                XCTAssertFalse(copy.localizedCaseInsensitiveContains(phrase),
                               "\(code) recovery guidance still contains \(phrase): \(copy)")
            }
        }
    }

    private func makeModel(
        port: LiveHostPort,
        handler: @escaping DeviceControlModel.HelperRequestHandler
    ) -> DeviceControlModel {
        let custom = [PortCalibrationEntry(physicalPort: "right1", location: "02100000", label: "右侧",
                                           rid: String(port.rid), side: "右侧",
                                           controller: port.controller, portNumber: port.portNumber)]
        let layout = BuiltInLayout(displayName: "test", sourceFile: "test", slots: [
            BuiltInSlot(slot: "S5", face: "RIGHT", portNumber: port.portNumber, rid: port.rid,
                        binding: "test", physicalName: "右侧")
        ], partial: false, skippedSlots: [], generatedAt: "test")
        let doc = CalibrationDocument(models: [], ports: custom, selectedPort: port.id)
        let store = CalibrationStore(testingDocument: doc, hostModel: "MacBookPro18,2", builtInLayout: layout)
        return DeviceControlModel(
            calibration: store, livePorts: [port], helperAvailable: true,
            sequenceDelaySeconds: 0.01, persistPortSelection: false, startLiveWork: false,
            requestHandler: handler)
    }

    func testFiveRebootsUseScheduleAndSameTargetAndNoSecondGroup() async throws {
        let port = LiveHostPort(controller: "100000763", portNumber: 3, rid: 2)
        var calls: [(Date, String, DFUSequenceTarget)] = []
        var actions: [HelperAction] = []
        var first = true
        let model = makeModel(port: port) { action, controller, portNumber, rid, requestID in
            actions.append(action)
            calls.append((Date(), requestID, DFUSequenceTarget(controller: controller,
                                                               portNumber: portNumber, rid: rid)))
            if first {
                first = false
                // Deliberately keep the first backend call long: the second
                // and third sends must start from the same absolute schedule.
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
            return HelperResponse(requestID: requestID, ok: true, dispatchTruth: "REQUEST_SENT",
                                  exitCode: 0, reason: "REBOOT_REQUESTED")
        }
        XCTAssertTrue(model.canControl)
        model.performRecoveryMode()
        model.performRecoveryMode() // must not open a second group
        try? await Task.sleep(nanoseconds: 200_000_000)
        model.applyObservedDevices([])
        model.applyDiscoveredPorts([port], persistCalibration: false)
        try? await Task.sleep(nanoseconds: 15_500_000_000)

        XCTAssertEqual(calls.count, 5, "exactly five attempts; running click must not add a group")
        let target = DFUSequenceTarget(controller: port.controller, portNumber: port.portNumber, rid: port.rid)
        XCTAssertTrue(calls.allSatisfy { $0.2 == target })
        XCTAssertEqual(Set(calls.map(\.1)).count, 5, "each attempt needs its own requestID")
        XCTAssertEqual(model.bootOptionsTestAttempted, 5)
        XCTAssertTrue(actions.allSatisfy { $0 == .reboot }, "recovery entry must use ordinary reboots only: \(actions)")
        XCTAssertFalse(actions.contains(.recovery))
        XCTAssertEqual(model.feedback.title, "恢复模式请求已完成")
        XCTAssertTrue(model.lastActionLog.contains("backend_start"))
        XCTAssertTrue(model.lastActionLog.contains("attempt=5/5"))
        let intervals = (1..<calls.count).map { calls[$0].0.timeIntervalSince(calls[$0 - 1].0) }
        for (index, interval) in intervals.enumerated() {
            XCTAssertEqual(interval, 3.0, accuracy: 0.55,
                           "attempt \(index + 2) not on the absolute 3s schedule")
        }
    }

    func testHostPortDisappearsStopsPendingAttemptsWithoutSwitching() async throws {
        let port = LiveHostPort(controller: "100000763", portNumber: 3, rid: 2)
        var calls: [String] = []
        let model = makeModel(port: port) { _, _, _, _, requestID in
            calls.append(requestID)
            return HelperResponse(requestID: requestID, ok: true, dispatchTruth: "REQUEST_SENT",
                                  exitCode: 0, reason: "REBOOT_REQUESTED")
        }
        model.performTestBootOptionsTriple()
        try? await Task.sleep(nanoseconds: 150_000_000)
        let other = LiveHostPort(controller: "100000999", portNumber: 9, rid: 9)
        model.applyDiscoveredPorts([other], persistCalibration: false)
        try? await Task.sleep(nanoseconds: 3_800_000_000)
        XCTAssertEqual(calls.count, 1, "lost original host port must stop pending attempts")
        XCTAssertEqual(model.bootOptionsTestAttempted, 1)
        XCTAssertEqual(model.bootOptionsTestStatusText, "已停止：主机侧无法唯一定位原端口")
        XCTAssertFalse(model.lastActionLog.contains("100000999"))
    }

    func testStopCancelsOnlyPendingAttempts() async throws {
        let port = LiveHostPort(controller: "100000763", portNumber: 3, rid: 2)
        var calls: [String] = []
        let model = makeModel(port: port) { _, _, _, _, requestID in
            calls.append(requestID)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return HelperResponse(requestID: requestID, ok: true, dispatchTruth: "REQUEST_SENT",
                                  exitCode: 0, reason: "REBOOT_REQUESTED")
        }
        model.performTestBootOptionsTriple()
        try? await Task.sleep(nanoseconds: 200_000_000)
        model.stopPendingBootOptionsTest()
        try? await Task.sleep(nanoseconds: 2_400_000_000)
        XCTAssertEqual(calls.count, 1, "stopping must cancel the two pending attempts")
        XCTAssertEqual(model.bootOptionsTestAttempted, 1)
        XCTAssertEqual(model.feedback.title, "已停止尚未发起的请求")
        XCTAssertTrue(model.feedback.detail.contains("未发起的请求已取消"))
    }
}

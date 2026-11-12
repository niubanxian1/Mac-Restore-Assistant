import XCTest
@testable import DeviceCapturePrototype

final class LanguageRenderingRegressionTests: XCTestCase {
    private var saved: String?
    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.string(forKey: LanguageStore.storageKey)
    }
    override func tearDown() {
        if let saved { UserDefaults.standard.set(saved, forKey: LanguageStore.storageKey) }
        else { UserDefaults.standard.removeObject(forKey: LanguageStore.storageKey) }
        super.tearDown()
    }

    func testActionLabelsAreFullyLocalized() {
        let expected: [String: (String, String, String)] = [
            "en": ("Enter DFU", "Restart Device", "Recovery"),
            "zh-Hant": ("進入 DFU", "重新啟動裝置", "恢復模式"),
            "ja": ("DFU に入る", "デバイスを再起動", "リカバリ"),
            "ko": ("DFU 진입", "기기 재시작", "복구 모드"),
        ]
        for (code, values) in expected {
            UserDefaults.standard.set(code, forKey: LanguageStore.storageKey)
            XCTAssertEqual(L10n.t("进入 DFU"), values.0)
            XCTAssertEqual(L10n.t("重启设备"), values.1)
            XCTAssertEqual(L10n.t("恢复模式"), values.2)
        }
    }

    func testDefaultPortRowIsLocalizedButCustomNameIsPreserved() {
        UserDefaults.standard.set("en", forKey: LanguageStore.storageKey)
        XCTAssertEqual(L10n.portRowTitle(label: "左侧上方", status: "已连接"), "Upper Left · Connected")
        XCTAssertEqual(L10n.portRowTitle(label: "客户自定义口", status: "已连接"), "客户自定义口 · Connected")
        XCTAssertEqual(L10n.localizedPortName("左侧下方"), "Lower Left")
        XCTAssertEqual(L10n.localizedPortName("客户自定义口"), "客户自定义口")
    }
    func testCaptureDurationUsesSelectedLanguage() {
        UserDefaults.standard.set("en", forKey: LanguageStore.storageKey)
        XCTAssertEqual(CaptureDisplayFormat.duration(seconds: 0), "0s")
        UserDefaults.standard.set("ko", forKey: LanguageStore.storageKey)
        XCTAssertEqual(CaptureDisplayFormat.duration(seconds: 0), "0초")
        UserDefaults.standard.set("ja", forKey: LanguageStore.storageKey)
        XCTAssertEqual(CaptureDisplayFormat.duration(seconds: 0), "0秒")
    }

    func testPortLocationUsesStructuredSideAndNeverUsesLabel() {
        UserDefaults.standard.set("en", forKey: LanguageStore.storageKey)
        XCTAssertEqual(L10n.portLocation(side: "左侧", location: "01100000"), "Location: Left · 01100000")
        XCTAssertEqual(L10n.portLocation(side: "", location: ""), "Location: Unknown")
        XCTAssertEqual(L10n.portLocation(side: "custom", location: "01100000"), "Location: Unknown")
        let entry = PortCalibrationEntry(physicalPort: "left1", location: "01200000", label: "左侧上方", rid: "0", side: "左侧")
        XCTAssertEqual(entry.label, "左侧上方")
    }

    @MainActor
    func testCaptureMeterUsesCurrentLanguageWithoutCachedDurationText() throws {
        let original = UserDefaults.standard.string(forKey: LanguageStore.storageKey)
        defer { if let original { UserDefaults.standard.set(original, forKey: LanguageStore.storageKey) } else { UserDefaults.standard.removeObject(forKey: LanguageStore.storageKey) } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mra-meter-\(UUID().uuidString)", isDirectory: true)
        let capture = CaptureModel(root: root, backendMode: .simulated)
        UserDefaults.standard.set("zh-Hans", forKey: LanguageStore.storageKey)
        XCTAssertTrue(capture.captureMeterText.hasPrefix("0秒 · 0 B"))
        UserDefaults.standard.set("en", forKey: LanguageStore.storageKey)
        XCTAssertTrue(capture.captureMeterText.hasPrefix("0s · 0 B"))
    }

    @MainActor
    func testLanguageModeDoesNotChangeSelectedPortOrFeedbackSemantics() {
        let saved = UserDefaults.standard.string(forKey: LanguageStore.storageKey)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: LanguageStore.storageKey) } else { UserDefaults.standard.removeObject(forKey: LanguageStore.storageKey) } }
        let doc = CalibrationDocument(models: [], ports: [], selectedPort: "")
        let store = CalibrationStore(testingDocument: doc, hostModel: "MacBookPro18,2", builtInLayout: nil)
        let history = FileManager.default.temporaryDirectory.appendingPathComponent("lang-port-\(UUID().uuidString).json")
        let ports = [LiveHostPort(controller: "AppleHPMDevice", portNumber: 1, rid: 0)]
        let device = DeviceControlModel(calibration: store, livePorts: ports, helperAvailable: true,
                                        persistPortSelection: false, startLiveWork: false, historyURL: history)
        UserDefaults.standard.set("zh-Hans", forKey: LanguageStore.storageKey)
        if let port = device.orderedDisplayPorts.first { device.selectPort(port) }
        let selected = device.selectedLiveKey
        let feedback = device.feedback.title
        UserDefaults.standard.set("en", forKey: LanguageStore.storageKey)
        XCTAssertEqual(device.selectedLiveKey, selected)
        XCTAssertEqual(device.feedback.title, feedback)
    }

    @MainActor
    func testLanguageModeDoesNotRestartSimulatedCapture() async throws {
        let saved = UserDefaults.standard.string(forKey: LanguageStore.storageKey)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: LanguageStore.storageKey) } else { UserDefaults.standard.removeObject(forKey: LanguageStore.storageKey) } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lang-capture-\(UUID().uuidString)", isDirectory: true)
        let capture = CaptureModel(root: root, backendMode: .simulated)
        UserDefaults.standard.set("zh-Hans", forKey: LanguageStore.storageKey)
        capture.start()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && capture.state != .recording { try? await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(capture.state, .recording)
        UserDefaults.standard.set("en", forKey: LanguageStore.storageKey)
        XCTAssertEqual(capture.state, .recording)
        capture.stop()
    }

}

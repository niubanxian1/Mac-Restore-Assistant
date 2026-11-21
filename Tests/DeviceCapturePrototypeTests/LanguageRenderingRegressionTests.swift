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
            "en": ("Enter DFU", "Restart Device", "Enter Recovery"),
            "zh-Hant": ("進入 DFU", "重新啟動裝置", "進入復原模式"),
            "ja": ("DFU に入る", "デバイスを再起動", "リカバリモードへ"),
            "ko": ("DFU 진입", "기기 재시작", "복구 모드 진입"),
        ]
        for (code, values) in expected {
            UserDefaults.standard.set(code, forKey: LanguageStore.storageKey)
            XCTAssertEqual(L10n.t("进入 DFU"), values.0)
            XCTAssertEqual(L10n.t("重启设备"), values.1)
            XCTAssertEqual(L10n.t("进入恢复模式"), values.2)
        }
    }

    func testWorkbenchAndAppearanceCoreKeysDoNotFallBackToChinese() {
        let keys = [
            "端口与设备", "固件与恢复", "RLM 日志", "物理端口", "快捷控制",
            "进入 DFU", "重启设备", "进入恢复模式", "模拟环境",
            "外观与动效", "实时预览", "预设", "视觉方向", "玻璃材质强度",
            "边缘光效", "空间悬浮深度", "动效强度", "环境呼吸",
            "粒子背景", "视差与局部高光", "高级 3D", "恢复默认",
            "锁定的 Restore 目标", "Restore 实时输出",
            "cfgutil 内存尾部",
            "此面板仅展示当前 cfgutil 子进程的有界内存输出；原始日志保存和 RLM 状态以锁定任务摘要为准。",
            "只读盘点 Configurator 存储；不提供未授权清理",
            "查看目标与控制目标、Restore 锁定目标相互独立",
            "Restore 任务保持独立运行；切换查看工作区不会改变锁定目标。",
            "关闭提示",
            "减少动态效果",
            "降低透明度",
            "提高对比度",
            "自动导航",
            "恢复自动导航",
            "固件偏好",
            "本地固件库",
            "全局默认固件",
            "机型默认固件",
            "最近使用",
            "设为全局默认",
            "设为当前机型默认",
            "macOS 系统辅助功能",
            "系统状态（只读）",
            "打开 macOS 辅助功能设置…",
            "Restore 准备中",
            "Restore 已结束",
            "整体进度：未知",
            "该百分比只对应当前 Step，不能推导整体完成情况。",
            "cfgutil 已报告当前阶段完成，等待下一阶段真实输出。"
        ]
        let original = UserDefaults.standard.string(forKey: LanguageStore.storageKey)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: LanguageStore.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: LanguageStore.storageKey)
            }
        }
        for code in ["en", "zh-Hant", "ja", "ko"] {
            UserDefaults.standard.set(code, forKey: LanguageStore.storageKey)
            for key in keys {
                XCTAssertNotEqual(
                    L10n.t(key),
                    key,
                    "\(code) missing workbench translation for \(key)")
            }
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

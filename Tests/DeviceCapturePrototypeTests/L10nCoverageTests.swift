import XCTest
@testable import DeviceCapturePrototype

final class L10nCoverageTests: XCTestCase {
    @MainActor func testLegacySystemPreferenceMigratesToChinese() {
        let defaults = UserDefaults.standard
        let prior = defaults.object(forKey: LanguageStore.storageKey)
        defer { if let prior { defaults.set(prior, forKey: LanguageStore.storageKey) } else { defaults.removeObject(forKey: LanguageStore.storageKey) } }
        defaults.set("system", forKey: LanguageStore.storageKey)
        let store = LanguageStore()
        XCTAssertEqual(store.mode, "zh-Hans")
        XCTAssertEqual(L10n.code(), "zh-Hans")
        XCTAssertFalse(LanguageStore.supportedModes.contains("system"))
    }

    func testPortSwitchFeedbackTranslatesInFiveLanguages() {
        let defaults = UserDefaults.standard
        let prior = defaults.object(forKey: "ui.languageMode")
        defer { if let prior { defaults.set(prior, forKey: "ui.languageMode") } else { defaults.removeObject(forKey: "ui.languageMode") } }
        let expected = ["zh-Hans": "操作目标已切换", "zh-Hant": "操作目標已切換", "en": "Operation target changed", "ja": "操作対象を変更", "ko": "작업 대상 변경"]
        for (code, title) in expected {
            defaults.set(code, forKey: "ui.languageMode")
            XCTAssertTrue(L10n.t("操作目标已切换：右侧").contains(title), code)
            if code != "zh-Hans" { XCTAssertNotEqual(L10n.t("采集会话不会被清空；执行时使用当前端口/控制器/RID。"), "采集会话不会被清空；执行时使用当前端口/控制器/RID。", code) }
        }
    }

    func testSentUnconfirmedDetailInAllLanguages() {
        let defaults = UserDefaults.standard
        let old = defaults.object(forKey: "ui.languageMode")
        defer { if let old { defaults.set(old, forKey: "ui.languageMode") } else { defaults.removeObject(forKey: "ui.languageMode") } }
        let source = "Helper 已提交请求；设备是否进入目标模式未确认。未知结果"
        for code in ["zh-Hant", "en", "ja", "ko"] {
            defaults.set(code, forKey: "ui.languageMode")
            let output = L10n.t(source)
            XCTAssertFalse(output.contains("设备是否进入"), code)
            XCTAssertFalse(output.contains("未知结果"), code)
        }
    }

    func testDFUResultShownInScreenshotHasCompleteTranslation() {
        let defaults = UserDefaults.standard
        let prior = defaults.object(forKey: "ui.languageMode")
        defer { if let prior { defaults.set(prior, forKey: "ui.languageMode") } else { defaults.removeObject(forKey: "ui.languageMode") } }
        let title = "后端确认提交 · 结果未确认"
        let detail = "已尝试 2/2；后端调用 2/2；后端确认提交 2/2；不认定设备成功。"
        let expected = ["en": "Backend submitted · result unconfirmed", "ja": "バックエンドが送信を確認・結果未確認", "ko": "백엔드 전송 확인 · 결과 미확인", "zh-Hant": "後端確認提交 · 結果未確認"]
        for (code, translated) in expected {
            defaults.set(code, forKey: "ui.languageMode")
            XCTAssertEqual(L10n.t(title), translated, code)
            XCTAssertFalse(L10n.t(detail).contains("后端"), code)
            XCTAssertFalse(L10n.t(detail).contains("已尝试"), code)
            XCTAssertTrue(L10n.t(detail).contains("2/2"), code)
        }
    }

    func testModelCalibrationCoreKeysDoNotFallBackToChinese() {
        let keys = ["模型校准", "布局槽位", "按槽位校准", "全部槽位已完成", "确认映射", "校准完成"]
        let original = UserDefaults.standard.string(forKey: LanguageStore.storageKey)
        defer { UserDefaults.standard.set(original, forKey: LanguageStore.storageKey) }
        for code in ["en", "zh-Hant", "ja", "ko"] {
            UserDefaults.standard.set(code, forKey: LanguageStore.storageKey)
            for key in keys {
                XCTAssertNotEqual(L10n.t(key), key, "\(code) missing model-calibration translation for \(key)")
            }
        }
    }

    func testLanguageSwitchDoesNotChangeFeedbackSemantic() {
        let feedback = ControlFeedback(title: "恢复模式进行中", detail: "", tone: .working, semantic: .requestSent)
        XCTAssertEqual(feedback.semantic, .requestSent)
        UserDefaults.standard.set("en", forKey: LanguageStore.storageKey)
        XCTAssertEqual(feedback.semantic, .requestSent)
        UserDefaults.standard.set("zh-Hans", forKey: LanguageStore.storageKey)
    }
}

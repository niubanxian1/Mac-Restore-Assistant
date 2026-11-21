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

    func testLogWorkspaceCoreKeysDoNotFallBackToChinese() {
        let keys = [
            "日志抓取", "RLM 日志", "自动监控 Restore 开始", "开始采集", "停止采集",
            "实时日志预览", "自动滚动", "暂停预览", "复制预览",
            "历史日志分析", "导入历史 .log…", "保存原始日志", "丢弃本次日志",
            "导出 .log…", "导出本次证据包", "证据包另存为…", "取消导出",
            "原始日志导出", "证据包导出", "复制原始日志", "生成诊断附件",
            "封装 ZIP", "验证 ZIP", "当前阶段工作量无法可靠计算",
            "采集中（离线模拟）", "采集中（真实日志）", "已停止，等待保存",
            "证据包已生成并校验。", "导出已取消；原始日志保留。"
        ]
        let original = UserDefaults.standard.string(forKey: LanguageStore.storageKey)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: LanguageStore.storageKey) }
            else { UserDefaults.standard.removeObject(forKey: LanguageStore.storageKey) }
        }
        for code in ["en", "zh-Hant", "ja", "ko"] {
            UserDefaults.standard.set(code, forKey: LanguageStore.storageKey)
            for key in keys {
                XCTAssertNotEqual(
                    L10n.t(key),
                    key,
                    "\(code) missing log-workspace translation for \(key)")
            }
        }
    }


    func testG3G4UnifiedRestoreKeysTranslateInAllSupportedLanguages() {
        let keys = [
            "设备最近结果", "导出原始日志…", "保存本次 Restore 原始日志",
            "只作用于下一次 Restore；关闭时不创建 raw/Staging 副本。",
            "固件准备完成，可启动此设备。",
            "固件准备完成，可启动此设备；另一台继续运行。",
            "当前无法启动此设备的 Restore", "设备 · 固件准备", "设备身份",
            "设备的固件草稿", "为此设备选择 IPSW…", "设备的日志策略",
            "原始日志按当前保存设置写入此任务自己的目录；本任务不启动独立 RLM 采集。",
            "开始此设备的 Restore…",
            "此设备拥有独立 ECID、端口、固件、进程、取消与结果；请确认后启动。",
            "另一台正在使用独立 RLM 日志，此设备将被拒绝启动。",
            "设备 · Restore 进行中", "设备与固件", "执行状态",
            "取消此设备的 Restore…",
            "为这台设备选择的固件只保存为独立草稿；另一台运行时也可手动启动，两台独立执行，不自动排队或重试。",
            "取消对象已变化，取消未执行。",
            "次任务引擎句柄已释放，取消未送达；请等待终态或使用强杀。",
            "正在取消次任务：已发送中断信号，等待进程退出…",
            "强杀对象已变化或尚未请求取消，强杀未执行。",
            "已对次任务发送强制结束信号。",
            "当前任务已结束或不可取消，取消未执行。",
            "取消已请求，正在等待进程退出…",
            "强杀不可用：任务已结束、未请求取消或进程已退出。",
            "次任务仍未退出，可使用强制结束。",
            "正在取消：已发送中断信号，等待进程退出…",
            "强制结束次任务…",
        ]
        let original = UserDefaults.standard.string(forKey: LanguageStore.storageKey)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: LanguageStore.storageKey) }
            else { UserDefaults.standard.removeObject(forKey: LanguageStore.storageKey) }
        }
        for code in ["en", "zh-Hant", "ja", "ko"] {
            UserDefaults.standard.set(code, forKey: LanguageStore.storageKey)
            for key in keys {
                XCTAssertNotEqual(L10n.t(key), key,
                    "\(code) missing unified-restore translation for \(key)")
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

    func testConfiguratorResetSafetyKeysTranslateInAllSupportedLanguages() {
        let keys = [
            "安全深度重置 Configurator",
            "清理缓存并重启 Configurator",
            "只读盘点",
            "精确清理",
            "备份 Application Support",
            "置前当前窗口",
            "无匹配",
            "跳过",
        ]
        let original = UserDefaults.standard.string(forKey: LanguageStore.storageKey)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: LanguageStore.storageKey) }
            else { UserDefaults.standard.removeObject(forKey: LanguageStore.storageKey) }
        }
        for code in ["en", "zh-Hant", "ja", "ko"] {
            UserDefaults.standard.set(code, forKey: LanguageStore.storageKey)
            for key in keys {
                XCTAssertNotEqual(
                    L10n.t(key),
                    key,
                    "\(code) missing Configurator safety translation for \(key)")
            }
        }
    }

    func testConfiguratorReadOnlyStorageKeysTranslateInAllLanguages() {
        let keys = [
            "Configurator 存储只读盘点",
            "仅扫描明确的 Configurator Group Container、App Container、用户缓存和临时目录；不扫描整个 /var/folders、IPSW、Blueprints、客户数据或未知目录。",
            "刷新只读盘点",
            "相关进程",
            "部分系统区域无法枚举；已知值不会显示为 0 B。",
            "等待只读盘点…",
            "清理 Configurator 数据",
            "待白名单核验授权",
            "本页只读。不会删除、移动或写入 Configurator 容器、缓存、Blueprints 或其他用户文件。",
            "已排除",
            "个 Reference Lab、Blueprints、IPSW 或未知类型条目。",
            "扫描完成",
            "部分权限受限",
            "部分可读",
            "扫描失败",
            "目录不存在",
            "权限受限，无法枚举内部占用",
            "已成功扫描 · 0 B",
            "内容大小：",
            "磁盘占用：",
            "运行中",
            "未运行",
            "未知",
            "磁盘",
            "已知至少",
        ]
        let original = UserDefaults.standard.string(
            forKey: LanguageStore.storageKey)
        defer {
            if let original {
                UserDefaults.standard.set(
                    original,
                    forKey: LanguageStore.storageKey)
            } else {
                UserDefaults.standard.removeObject(
                    forKey: LanguageStore.storageKey)
            }
        }
        for code in ["en", "zh-Hant", "ja", "ko"] {
            UserDefaults.standard.set(
                code,
                forKey: LanguageStore.storageKey)
            for key in keys {
                XCTAssertNotNil(
                    L10n.batch13[code]?[key],
                    "\(code) missing explicit Configurator storage translation for \(key)")
                XCTAssertFalse(
                    L10n.t(key).isEmpty,
                    "\(code) returned an empty Configurator storage translation for \(key)")
            }
        }
    }

    func testIdentityAndPanoramaKeysTranslateInAllSupportedLanguages() {
        let keys = [
            "A 型号未知",
            "身份冲突",
            "当前无身份证据",
            "识别状态",
            "设备类别",
            "机型标识符",
            "物理归属未证实",
            "原始 USB 拓扑",
            "物理端口待确认",
            "选中端口",
            "端口已连接 · 设备身份未读取",
            "Helper 已安装 · 调用未授权",
            "Helper 可用 · 签名授权通过",
            "同端口只读 USB 全景",
        ]
        let original = UserDefaults.standard.string(forKey: LanguageStore.storageKey)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: LanguageStore.storageKey) }
            else { UserDefaults.standard.removeObject(forKey: LanguageStore.storageKey) }
        }
        for code in ["en", "zh-Hant", "ja", "ko"] {
            UserDefaults.standard.set(code, forKey: LanguageStore.storageKey)
            for key in keys {
                XCTAssertNotEqual(
                    L10n.t(key),
                    key,
                    "\(code) missing identity/panorama translation for \(key)")
            }
        }
    }

    func testUSBConnectionTimingKeysTranslateInAllSupportedLanguages() {
        let keys = [
            "USB 时序观察",
            "设备控制调用不可用",
            "接口与设备",
            "Mac DFU · 型号待确认",
            "Mac Recovery · 型号待确认",
            "Mac 已连接 · 型号待确认",
            "Mac 未知模式 · 型号待确认",
            "未知模式",
            "当前：",
            "次",
            "controller + PortNumber + RID + USB location 精确校准一致",
            "USB location 未获可信端口归属",
            "未检测到目标 Mac",
            "端口链路有连接；未枚举到目标设备",
            "当前没有目标设备",
            "当前观察未知",
            "USB 设备已连接 · 身份待识别",
            "当前未检测到目标设备",
            "观察不完整；缺失区间不计算精确次数",
            "复制当前口时序",
            "清零当前口统计",
            "最近 10 条真实出现/消失",
            "当前未见可归属于此口的 USB 设备",
            "最近 60 秒端口再出现：",
            "同机重枚举：未知",
            "最近 USB 系统通知：",
            "同模式再枚举",
            "模式改变",
            "未归属 USB 时序（最近 10 条）",
        ]
        let original = UserDefaults.standard.string(forKey: LanguageStore.storageKey)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: LanguageStore.storageKey) }
            else { UserDefaults.standard.removeObject(forKey: LanguageStore.storageKey) }
        }
        for code in ["en", "zh-Hant", "ja", "ko"] {
            UserDefaults.standard.set(code, forKey: LanguageStore.storageKey)
            for key in keys {
                XCTAssertNotEqual(
                    L10n.t(key),
                    key,
                    "\(code) missing USB timing translation for \(key)")
            }
        }
    }

    func testFirmwareRestoreCoreKeysTranslateInAllSupportedLanguages() {
        let keys = [
            "固件与恢复",
            "Restore 目标",
            "本地 IPSW",
            "选择本地 IPSW…",
            "选择固件文件夹…",
            "确认擦除数据并恢复…",
            "当前任务",
            "整体进度：未知",
            "暂无恢复任务",
            "请求取消恢复",
            "强制结束无响应进程…",
            "打开本次原始日志目录",
            "确认抹除并恢复？",
            "抹除并恢复",
            "固件库",
            "刷新固件库",
            "恢复自动推荐",
            "校验完整 IPSW SHA-256…",
            "未选择固件来源",
            "系统自动推荐",
            "用户手动选择",
            "已验证恢复记录",
            "用户显式默认",
            "本地元数据推断",
            "需人工确认",
            "无法读取",
            "iCloud 未下载",
            "已确认 DFU，可继续准备 Restore",
            "操作端口：",
            "目标已选中；请选择本地 IPSW。",
            "准备此目标",
            "该物理端口已确认出现 DFU；尚无可唯一归属的 Restore 目标，请等待观察刷新。",
            "关闭提示",
            "端口身份待确认",
        ]
        let original = UserDefaults.standard.string(forKey: LanguageStore.storageKey)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: LanguageStore.storageKey) }
            else { UserDefaults.standard.removeObject(forKey: LanguageStore.storageKey) }
        }
        for code in ["en", "zh-Hant", "ja", "ko"] {
            UserDefaults.standard.set(code, forKey: LanguageStore.storageKey)
            for key in keys {
                XCTAssertNotEqual(
                    L10n.t(key),
                    key,
                    "\(code) missing firmware/restore translation for \(key)")
            }
        }
    }

    /// UI-1：左栏遥测与状态药丸新增键必须四语齐备（不含 zh-Hans 源文）。
    func testUI1TelemetryKeysTranslateInAllSupportedLanguages() {
        let keys = ["未获取", "正常", "端口遥测", "只读"]
        let original = UserDefaults.standard.string(
            forKey: LanguageStore.storageKey)
        defer {
            if let original {
                UserDefaults.standard.set(
                    original,
                    forKey: LanguageStore.storageKey)
            } else {
                UserDefaults.standard.removeObject(
                    forKey: LanguageStore.storageKey)
            }
        }
        for code in ["en", "zh-Hant", "ja", "ko"] {
            UserDefaults.standard.set(
                code,
                forKey: LanguageStore.storageKey)
            for key in keys {
                XCTAssertNotEqual(
                    L10n.t(key),
                    key,
                    "\(code) missing UI-1 translation for \(key)")
            }
        }
    }

    /// UI-2：统一准备态新增文案必须四语齐备（不含 zh-Hans 源文）。
    func testUI2UnifiedPreparationKeysTranslateInAllSupportedLanguages() {
        let keys = [
            "当前生效固件", "手动选择 IPSW…", "搜索 IPSW…", "IPSW 文件",
            "版本 / Build", "兼容性", "来源", "手动选择", "机型默认",
            "全局默认", "上次选择", "开始 Restore…", "当前无法开始 Restore",
            "默认固件不可用", "请重新选择 IPSW，或恢复自动推荐。",
            "已有两个 Restore 任务在执行。", "兼容", "不兼容", "未验证",
            "有效", "无效", "固件库为空。", "没有匹配的 IPSW。",
            "Restore 会抹除目标 Mac 上的数据。本工具不会自动开始，也不会检测到设备后自动刷机。",
        ]
        let original = UserDefaults.standard.string(
            forKey: LanguageStore.storageKey)
        defer {
            if let original {
                UserDefaults.standard.set(
                    original, forKey: LanguageStore.storageKey)
            } else {
                UserDefaults.standard.removeObject(
                    forKey: LanguageStore.storageKey)
            }
        }
        for code in ["en", "zh-Hant", "ja", "ko"] {
            UserDefaults.standard.set(code, forKey: LanguageStore.storageKey)
            for key in keys {
                XCTAssertNotEqual(
                    L10n.t(key),
                    key,
                    "\(code) missing UI-2 translation for \(key)")
            }
        }
    }

    func testUI3UnifiedRunningKeysTranslateInAllSupportedLanguages() {
        let keys = [
            "实时日志预览",
            "cfgutil 内存尾部 · 非完整原始日志",
            "回到底部",
            "复制当前预览",
            "已复制当前预览",
            "仅展示有界内存尾部；完整原始日志请使用 Raw 保存/归档导出。",
            "任务详情",
            "复制完整 attempt UUID",
            "主任务",
            "第二任务",
            "正在取消",
            "进行中",
            "已执行",
            "强制结束…",
            "打开原始日志目录",
            "正在取消：已发送中断信号，等待进程退出…",
            "Restore 启动准备中；cfgutil 尚未确认运行。",
            "Restore 正在执行；取消入口保持可见。",
            "执行耗时",
            "失败阶段：",
            "未提供更多失败原因。",
            "取消已确认；任务已结束。",
            "底层未给出可判定的终态；请以原始日志与归档为准。",
            "任务已完成。",
            "本次未保存完整原始日志。",
            "正在写入原始证据与历史记录，导出暂不可用。",
            "返回准备",
            "当前没有可展示的 Restore 任务。",
            "取消 Restore…",
            "尚未启动",
            "原始日志说明",
            "正在整理原始日志，稍后可导出。",
            "任务已结束，请返回准备态确认后重新开始。",
            "兼容性未验证，缺少：",
            "；不能开始 Restore。",
            "兼容性未验证，不能开始 Restore；请检查固件与设备身份。",
            "Restore 未能启动，请检查目标设备与固件兼容性。",
            "目标已变化，未启动 Restore。",
            "正在扫描本地 IPSW…",
            "仅看报错",
            "尚未选择固件；请从下方固件库选择。",
            "参考上次成功",
            "同 ECID 同固件",
            "正在解压/校验固件，首次进度更新可能需要数分钟…",
            "清除失效默认",
            "查看全部",
            "命中报错",
            "终端预览",
            "在 Finder 中打开原始目录",
            "仅基于日志原文关键词归类，不替代实测诊断",
            "设为本机型默认",
            "设为全局默认",
            "在 Finder 中显示",
            "复制十六进制",
            "复制十进制",
            "复制失败摘要",
            "Restore 完成提示音",
            "近 1 分钟变化",
            "归属冲突",
            "异常 · 过流",
            "扫描完成。",
            "添加目录…",
            "重新扫描",
            "启动时自动扫描本机 IPSW",
            "已添加的固件目录",
            "添加固件文件夹…",
            "固件扫描已取消。",
            "Restore 进行中，自动固件扫描已延后。",
            "扫描完成（部分目录受权限或上限限制）。",
            "已移除固件目录；文件本身未删除。",
        ]
        let original = UserDefaults.standard.string(
            forKey: LanguageStore.storageKey)
        defer {
            if let original {
                UserDefaults.standard.set(
                    original, forKey: LanguageStore.storageKey)
            } else {
                UserDefaults.standard.removeObject(
                    forKey: LanguageStore.storageKey)
            }
        }
        for code in ["en", "zh-Hant", "ja", "ko"] {
            UserDefaults.standard.set(code, forKey: LanguageStore.storageKey)
            for key in keys {
                XCTAssertNotEqual(
                    L10n.t(key),
                    key,
                    "\(code) missing UI-3 translation for \(key)")
            }
        }
    }
}

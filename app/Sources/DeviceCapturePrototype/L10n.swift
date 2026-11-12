import Foundation

/// Small presentation-only translator for dynamic strings that are not
/// SwiftUI LocalizedStringKey literals. Static literals use Localizable.strings.
enum L10n {
    static func code() -> String {
        let saved = UserDefaults.standard.string(forKey: "ui.languageMode") ?? "zh-Hans"
        return ["zh-Hans", "zh-Hant", "en", "ja", "ko"].contains(saved) ? saved : "zh-Hans"
    }

    static func t(_ source: String) -> String {
        let code = code()
        if code == "zh-Hans" { return source }
        let feedbackTitles: [String: [String: String]] = [
            "双发序列进行中": ["zh-Hant":"雙發序列進行中", "en":"DFU sequence in progress", "ja":"DFU シーケンス実行中", "ko":"DFU 전송 진행 중"],
            "恢复模式进行中": ["zh-Hant":"恢復模式進行中", "en":"Recovery in progress", "ja":"リカバリ実行中", "ko":"복구 모드 진행 중"],
            "测试组运行中": ["zh-Hant":"測試組執行中", "en":"Request sequence in progress", "ja":"リクエスト実行中", "ko":"요청 진행 중"],
            "已停止：主机侧无法唯一定位原端口": ["zh-Hant":"已停止：主機端無法唯一定位原連接埠", "en":"Stopped: original host port cannot be uniquely identified", "ja":"停止：元のホストポートを一意に特定できません", "ko":"중지됨: 원래 호스트 포트를 식별할 수 없음"],
            "恢复模式请求已完成，请查看目标 Mac 是否出现齿轮『选项』": ["zh-Hant":"恢復模式要求已完成，請查看目標 Mac 是否出現齒輪「選項」", "en":"Recovery requests complete. Check the target Mac for the gear icon labeled Options.", "ja":"リカバリのリクエストが完了しました。対象 Mac に歯車の「オプション」が表示されるか確認してください。", "ko":"복구 요청이 완료되었습니다. 대상 Mac에 톱니바퀴 모양의 ‘옵션’이 표시되는지 확인하세요."],
            "已停止尚未发起的请求": ["zh-Hant":"已停止尚未發起的要求", "en":"Pending requests stopped", "ja":"未送信のリクエストを停止しました", "ko":"대기 중인 요청을 중지했습니다"],
            "请求超时，结果未确认": ["zh-Hant":"要求逾時，結果未確認", "en":"Request timed out · result unconfirmed", "ja":"リクエストがタイムアウト・結果未確認", "ko":"요청 시간 초과 · 결과 미확인"],
            "未发送": ["zh-Hant":"未傳送", "en":"Not sent", "ja":"未送信", "ko":"전송되지 않음"],
            "观察到 DFU": ["zh-Hant":"已觀察到 DFU", "en":"DFU observed", "ja":"DFU を検出", "ko":"DFU 감지됨"],
            "设备已进入 DFU": ["zh-Hant":"裝置已進入 DFU", "en":"Device entered DFU", "ja":"デバイスが DFU に入りました", "ko":"기기가 DFU에 진입했습니다"],
            "设备当前在 DFU": ["zh-Hant":"裝置目前處於 DFU", "en":"Device is in DFU", "ja":"デバイスは DFU 状態です", "ko":"기기가 DFU 상태입니다"],
            "被动 USB 观察已看到 DFU；这不等于恢复/刷机成功。": ["zh-Hant":"被動 USB 觀察已看到 DFU；這不代表還原成功。", "en":"DFU was observed over USB; this does not mean a restore succeeded.", "ja":"USB で DFU を検出しました。復元の成功を意味するものではありません。", "ko":"USB에서 DFU가 감지되었습니다. 복원 성공을 의미하지는 않습니다."],
            "本次点击不会另开一组；等待五次尝试结束或停止尚未发起的请求。": ["zh-Hant":"本次點擊不會另開一組；等待五次嘗試結束或停止尚未發起的要求。", "en":"No new sequence was started. Wait for five attempts or stop pending requests.", "ja":"新しいシーケンスは開始されません。5 回の試行が終わるまで待つか、未送信のリクエストを停止してください。", "ko":"새 시퀀스는 시작되지 않습니다. 5회 시도를 기다리거나 대기 중인 요청을 중지하세요."],
            "主机侧无法唯一定位所选物理端口；未换口、未广播。": ["zh-Hant":"主機端無法唯一定位所選實體連接埠；未換連接埠、未廣播。", "en":"The selected host port could not be uniquely identified; no other port was used and no broadcast was sent.", "ja":"選択したホストポートを一意に特定できません。ポート変更やブロードキャストは行っていません。", "ko":"선택한 호스트 포트를 식별할 수 없습니다. 다른 포트를 사용하거나 브로드캐스트하지 않았습니다."],
            "端口身份不完整或不唯一，已拒绝发送。": ["zh-Hant":"連接埠身分不完整或不唯一，已拒絕傳送。", "en":"Port identity is incomplete or ambiguous; the request was not sent.", "ja":"ポートの識別情報が不完全または一意でないため、送信しませんでした。", "ko":"포트 식별 정보가 불완전하거나 모호하여 전송하지 않았습니다."],
            "固定同一端口，0/3/6/9/12 秒各一次普通重启；15 秒窗口结束；不调用 reboot serial/DVEn，不自动宣告恢复。": ["zh-Hant":"固定同一連接埠，在 0/3/6/9/12 秒各傳送一次一般重新啟動；不呼叫 reboot serial/DVEn，也不自動宣告恢復成功。", "en":"Five normal restarts target the same port at 0/3/6/9/12 seconds. No reboot serial/DVEn is used; Recovery is not automatically confirmed.", "ja":"同じポートに 0/3/6/9/12 秒で通常の再起動を送信します。reboot serial/DVEn は使用せず、リカバリを自動的に確定しません。", "ko":"동일한 포트에 0/3/6/9/12초에 일반 재시작을 전송합니다. reboot serial/DVEn을 사용하지 않으며 복구 성공을 자동으로 확정하지 않습니다."],
            "Helper 未在时限内返回；未认定设备成功。界面已解锁，可再次操作。迟到的响应将被忽略。尚未发出的后续发送已取消。": ["zh-Hant":"Helper 未在時限內回應；未確認裝置成功。介面已解鎖，可再次操作。遲到的回應將被忽略，尚未發送的後續要求已取消。", "en":"The Helper did not respond in time. Device success is unconfirmed. The interface is unlocked; late responses are ignored and pending sends are cancelled.", "ja":"Helper が制限時間内に応答しませんでした。デバイスの成功は未確認です。操作は再開できます。遅れた応答は無視され、未送信の要求はキャンセルされます。", "ko":"Helper가 제한 시간 내에 응답하지 않았습니다. 기기 성공 여부는 확인되지 않았습니다. 화면이 잠금 해제되며 늦은 응답은 무시되고 대기 중인 전송은 취소됩니다."],
            "后端确认提交 · 结果未确认": ["zh-Hant":"後端確認提交 · 結果未確認", "en":"Backend submitted · result unconfirmed", "ja":"バックエンドが送信を確認・結果未確認", "ko":"백엔드 전송 확인 · 결과 미확인"],
            "DFU 命令返回失败 · 设备结果未确认": ["zh-Hant":"DFU 命令回報失敗 · 裝置結果未確認", "en":"DFU command failed · device result unconfirmed", "ja":"DFU コマンドが失敗・デバイスの状態は未確認", "ko":"DFU 명령 실패 · 기기 결과 미확인"],
            "已尝试 · 后端未确认提交": ["zh-Hant":"已嘗試 · 後端未確認提交", "en":"Attempted · backend submission unconfirmed", "ja":"試行済み・バックエンド送信は未確認", "ko":"시도함 · 백엔드 전송 미확인"],
            "已尝试 · 结果未知": ["zh-Hant":"已嘗試 · 結果未知", "en":"Attempted · result unknown", "ja":"試行済み・結果不明", "ko":"시도함 · 결과 알 수 없음"],
            "未尝试": ["zh-Hant":"未嘗試", "en":"Not attempted", "ja":"未試行", "ko":"시도하지 않음"]
        ]
        if let title = feedbackTitles[source]?[code] { return title }
        let dfuPattern = #"^已尝试 ([0-9]+)/2；后端调用 ([0-9]+)/2；后端确认提交 ([0-9]+)/2；不认定设备成功。(.*)$"#
        if let regex = try? NSRegularExpression(pattern: dfuPattern),
           let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
           let a = Range(match.range(at: 1), in: source),
           let b = Range(match.range(at: 2), in: source),
           let c = Range(match.range(at: 3), in: source),
           let r = Range(match.range(at: 4), in: source) {
            let templates = [
                "zh-Hant": "已嘗試 %@/2；後端呼叫 %@/2；後端確認提交 %@/2；不代表裝置成功。%@",
                "en": "Attempted %@/2; backend calls %@/2; confirmed submissions %@/2; device success is not confirmed. %@",
                "ja": "試行 %@/2、バックエンド呼び出し %@/2、送信確認 %@/2。デバイスの成功は未確認です。%@",
                "ko": "시도 %@/2, 백엔드 호출 %@/2, 전송 확인 %@/2. 기기 성공 여부는 확인되지 않았습니다. %@"
            ]
            if let template = templates[code] {
                return String(format: template, String(source[a]), String(source[b]), String(source[c]), String(source[r]))
            }
        }
        let recoveryPatterns: [(String, [String: String])] = [
            (#"^已尝试 ([0-9]+)/([0-9]+)；未换口、未广播。$"#, ["zh-Hant":"已嘗試 %@/%@；未換連接埠、未廣播。", "en":"Attempted %@/%@; no port change or broadcast.", "ja":"試行 %@/%@。ポート変更・ブロードキャストなし。", "ko":"시도 %@/%@. 포트 변경 및 브로드캐스트 없음."]),
            (#"^已尝试 ([0-9]+)/([0-9]+)；15 秒窗口结束；固定原端口；不自动宣告已进入恢复模式。$"#, ["zh-Hant":"已嘗試 %@/%@；15 秒視窗結束；使用原連接埠；不自動確認恢復模式。", "en":"Attempted %@/%@; the 15-second window ended. The original port was used; Recovery is not automatically confirmed.", "ja":"試行 %@/%@。15 秒間が終了しました。元のポートを使用し、リカバリへの移行は自動判定しません。", "ko":"시도 %@/%@. 15초가 지났습니다. 원래 포트를 사용했으며 복구 모드 진입을 자동으로 확정하지 않습니다."]),
            (#"^已尝试 ([0-9]+)/([0-9]+)；未发起的请求已取消，未换口、未广播。$"#, ["zh-Hant":"已嘗試 %@/%@；未發起的要求已取消，未換連接埠、未廣播。", "en":"Attempted %@/%@; pending requests were cancelled, with no port change or broadcast.", "ja":"試行 %@/%@。未送信の要求はキャンセルされ、ポート変更やブロードキャストはありません。", "ko":"시도 %@/%@. 대기 중인 요청은 취소되었으며 포트 변경이나 브로드캐스트는 없었습니다."])
        ]
        for (pattern, templates) in recoveryPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
               let first = Range(match.range(at: 1), in: source),
               let second = Range(match.range(at: 2), in: source),
               let template = templates[code] {
                return String(format: template, String(source[first]), String(source[second]))
            }
        }
        let sentPrefix = "Helper 已提交请求；设备是否进入目标模式未确认。"
        if source.hasPrefix(sentPrefix) {
            let suffix = String(source.dropFirst(sentPrefix.count))
            let templates = [
                "zh-Hant": "Helper 已提交要求；尚未確認裝置是否進入目標模式。",
                "en": "The Helper submitted the request; the device's target mode is unconfirmed. ",
                "ja": "Helper はリクエストを送信しました。デバイスが対象モードに入ったかは未確認です。",
                "ko": "Helper가 요청을 제출했습니다. 기기가 대상 모드에 진입했는지는 확인되지 않았습니다. "
            ]
            let unknown = ["zh-Hant": "未知結果", "en": "Unknown result", "ja": "結果不明", "ko": "결과 알 수 없음"]
            if let prefix = templates[code] {
                return prefix + (suffix == "未知结果" ? (unknown[code] ?? suffix) : t(suffix))
            }
        }
        let switchPrefix = "操作目标已切换："
        if source.hasPrefix(switchPrefix) {
            let port = String(source.dropFirst(switchPrefix.count))
            let templates = [
                "zh-Hant": "操作目標已切換：%@",
                "en": "Operation target changed: %@",
                "ja": "操作対象を変更：%@",
                "ko": "작업 대상 변경: %@"
            ]
            if let template = templates[code] {
                return String(format: template, t(port))
            }
        }
        // Exact full-sentence lookup must precede token replacement. Otherwise
        // short boolean/token rules can corrupt natural-language paragraphs.
        if let exact = exact[code]?[source] { return exact }
        for map in [mainFix, techFix, helperFix, settingsFix, configFix, batch1, batch2, batch3, batch4, batch5, batch6, batch7] {
            if let exact = map[code]?[source] { return exact }
        }
        var result = source
        for (zh, translated) in mainFix[code] ?? [:] {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        for (zh, translated) in techFix[code] ?? [:] {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        for (zh, translated) in helperFix[code] ?? [:] {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        for (zh, translated) in exact[code] ?? [:] {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        for (zh, translated) in tokens[code] ?? [:] where zh.count > 1 {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        for (zh, translated) in moduleA[code] ?? [:] {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        for (zh, translated) in moduleB[code] ?? [:] {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        for (zh, translated) in moduleC[code] ?? [:] {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        for (zh, translated) in batch1[code] ?? [:] {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        for (zh, translated) in batch2[code] ?? [:] {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        for (zh, translated) in batch3[code] ?? [:] {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        for (zh, translated) in batch4[code] ?? [:] {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        for (zh, translated) in batch5[code] ?? [:] {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        for (zh, translated) in batch6[code] ?? [:] {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        for (zh, translated) in batch7[code] ?? [:] {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        return result
    }

    private static let exact: [String: [String: String]] = [
        "en": [
            "请求发送中":"Sending request","请求已发送 · 结果未确认":"Request sent · result unconfirmed","未发送/失败":"Not sent / failed",
            "读取的 USB 产品名":"USB product name read","自定义校准":"Custom calibration",
            "实际采用：自定义校准（controller + PortNumber）":"In use: Custom calibration (controller + PortNumber)",
            "进入 DFU": "Enter DFU", "重启设备": "Restart Device", "恢复模式": "Recovery", "Helper 不可用": "Helper unavailable",
            "不可用 · 调用者签名未获许可": "Unavailable · caller signature not authorized",
            "执行设置中选择的 Apple Configurator 操作": "Run the Apple Configurator action selected in Settings",
            "已连接 Mac · 具体机型未知": "Connected Mac · Model unknown",
            "设备身份暂未读取": "Device identity not read yet",
            "端口控制器已确认连接；USB/Configurator 目标身份暂未读取": "Port controller connected; USB/Configurator target identity not read",
            "本次打开后暂无连接变化": "No connection changes since launch",
            "当前没有额外的连接路径信息": "No additional connection path details",
            "当前未识别到设备，没有可展示的连接路径": "No device identified; no connection path to show",
            "无设备": "No device",
            "等待操作": "Waiting",
            "选择物理端口后可执行设备控制。": "Select a physical port to enable device control.",
            "空闲": "Idle",
            "停止采集后可导出": "Stop capture to export",
            "导出后可复制": "Export the ZIP first, then copy it.",
            "序列号": "Serial",
            "已连接": "Connected",
            "未识别设备": "Unidentified device",
            "左侧上方": "Upper Left", "左侧下方": "Lower Left", "右侧": "Right",
            "控制器": "Controller", "端口": "Port", "主机校准": "Host calibration",
            "内置校准": "Built-in calibration", "实际采用": "In use", "模型": "Model"
        ],
        "zh-Hant": [
            "请求发送中":"傳送中","请求已发送 · 结果未确认":"要求已傳送 · 結果未確認","未发送/失败":"未傳送／失敗",
            "读取的 USB 产品名":"讀取的 USB 產品名稱","自定义校准":"自訂校準",
            "实际采用：自定义校准（controller + PortNumber）":"實際採用：自訂校準（controller + PortNumber）",
            "进入 DFU": "進入 DFU", "重启设备": "重新啟動裝置", "恢复模式": "恢復模式", "Helper 不可用": "Helper 無法使用",
            "不可用 · 调用者签名未获许可": "無法使用 · 呼叫者簽章未獲授權",
            "执行设置中选择的 Apple Configurator 操作": "執行設定中選擇的 Apple Configurator 操作",
            "已连接 Mac · 具体机型未知": "已連接 Mac · 具體機型未知",
            "设备身份暂未读取": "裝置身分尚未讀取",
            "端口控制器已确认连接；USB/Configurator 目标身份暂未读取": "連接埠控制器已確認連接；USB/Configurator 目標身分尚未讀取",
            "本次打开后暂无连接变化": "本次開啟後暫無連接變化",
            "当前没有额外的连接路径信息": "目前沒有額外的連接路徑資訊",
            "当前未识别到设备，没有可展示的连接路径": "目前未識別到裝置，沒有可顯示的連接路徑",
            "无设备": "無裝置", "等待操作": "等待操作",
            "选择物理端口后可执行设备控制。": "選擇實體連接埠後可執行裝置控制。",
            "空闲": "閒置", "停止采集后可导出": "停止擷取後可匯出", "导出后可复制": "匯出後可複製",
            "序列号": "序號", "已连接": "已連接", "未识别设备": "未識別裝置",
            "左侧上方": "左側上方", "左侧下方": "左側下方", "右侧": "右側",
            "控制器": "控制器", "端口": "連接埠", "主机校准": "主機校準",
            "内置校准": "內建校準", "实际采用": "實際採用", "模型": "模型"
        ],
        "ja": [
            "请求发送中":"送信中","请求已发送 · 结果未确认":"送信済み・結果未確認","未发送/失败":"未送信／失敗",
            "读取的 USB 产品名":"読み取った USB 製品名","自定义校准":"カスタム校正",
            "实际采用：自定义校准（controller + PortNumber）":"使用中：カスタム校正（controller + PortNumber）",
            "进入 DFU": "DFU に入る", "重启设备": "デバイスを再起動", "恢复模式": "リカバリ", "Helper 不可用": "Helper を利用できません",
            "不可用 · 调用者签名未获许可": "利用不可 · 呼び出し元の署名が許可されていません",
            "执行设置中选择的 Apple Configurator 操作": "設定で選択した Apple Configurator 操作を実行",
            "已连接 Mac · 具体机型未知": "Mac 接続済み · モデル不明",
            "设备身份暂未读取": "デバイス情報は未取得です",
            "端口控制器已确认连接；USB/Configurator 目标身份暂未读取": "ポートコントローラは接続済み。USB/Configurator のターゲット情報は未取得です",
            "本次打开后暂无连接变化": "起動後の接続変化はありません",
            "当前没有额外的连接路径信息": "追加の接続経路情報はありません",
            "当前未识别到设备，没有可展示的连接路径": "デバイス未認識のため表示できる接続経路はありません",
            "无设备": "デバイスなし", "等待操作": "待機中",
            "选择物理端口后可执行设备控制。": "物理ポートを選択するとデバイス操作を実行できます。",
            "空闲": "アイドル", "停止采集后可导出": "収集停止後に書き出せます", "导出后可复制": "書き出し後にコピーできます",
            "序列号": "シリアル番号", "已连接": "接続済み", "未识别设备": "未認識デバイス",
            "左侧上方": "左上", "左侧下方": "左下", "右侧": "右側",
            "控制器": "コントローラ", "端口": "ポート", "主机校准": "ホスト校正",
            "内置校准": "内蔵校正", "实际采用": "使用中", "模型": "モデル"
        ],
        "ko": [
            "请求发送中":"전송 중","请求已发送 · 结果未确认":"전송됨 · 결과 미확인","未发送/失败":"전송 안 됨/실패",
            "读取的 USB 产品名":"읽은 USB 제품 이름","自定义校准":"사용자 보정",
            "实际采用：自定义校准（controller + PortNumber）":"사용 중: 사용자 보정(controller + PortNumber)",
            "进入 DFU": "DFU 진입", "重启设备": "기기 재시작", "恢复模式": "복구 모드", "Helper 不可用": "Helper 사용 불가",
            "不可用 · 调用者签名未获许可": "사용 불가 · 호출자 서명이 승인되지 않음",
            "执行设置中选择的 Apple Configurator 操作": "설정에서 선택한 Apple Configurator 작업 실행",
            "已连接 Mac · 具体机型未知": "Mac 연결됨 · 모델 알 수 없음",
            "设备身份暂未读取": "기기 정보를 아직 읽지 못했습니다",
            "端口控制器已确认连接；USB/Configurator 目标身份暂未读取": "포트 컨트롤러는 연결됨. USB/Configurator 대상 정보는 아직 없음",
            "本次打开后暂无连接变化": "앱 실행 후 연결 변화 없음",
            "当前没有额外的连接路径信息": "추가 연결 경로 정보가 없습니다",
            "当前未识别到设备，没有可展示的连接路径": "기기를 인식하지 못해 표시할 연결 경로가 없습니다",
            "无设备": "기기 없음", "等待操作": "대기 중",
            "选择物理端口后可执行设备控制。": "물리 포트를 선택하면 기기 제어를 실행할 수 있습니다.",
            "空闲": "유휴", "停止采集后可导出": "수집을 중지한 후 내보낼 수 있습니다", "导出后可复制": "내보낸 후 복사할 수 있습니다",
            "序列号": "일련번호", "已连接": "연결됨", "未识别设备": "인식되지 않은 기기",
            "左侧上方": "왼쪽 위", "左侧下方": "왼쪽 아래", "右侧": "오른쪽",
            "控制器": "컨트롤러", "端口": "포트", "主机校准": "호스트 보정",
            "内置校准": "내장 보정", "实际采用": "사용 중", "模型": "모델"
        ]
    ]

    private static let tokens: [String: [String: String]] = [
        "en": [
            "控制器 ": "Controller ", "主机校准：": "Host calibration: ",
            "内置校准：": "Built-in calibration: ", "实际采用：": "In use: ",
            "操作目标：": "Operation target: ", "模型：": "Model: ",
            "布局核对：": "Layout check: ", "已校准": "Calibrated",
            "未校准": "Not calibrated", "无模型": "No model", "机型未识别": "Model unidentified",
            "后端待更新": "Backend needs update", "已安装": "Installed",
            "最近连接变化": "Recent connection changes", "连接路径": "Connection path",
            "端口控制器": "Port controller", "控制器端口": "Controller port",
            "当前链路": "Current link", "当前协议": "Current protocol",
            "线材与能力": "Cable & capability", "线材标识": "Cable identity",
            "线材/端口能力": "Cable/port capability", "USB 超速活动": "USB SuperSpeed active",
            "主机机型未识别": "Host model unidentified",
            "是":"Yes","否":"No","作废本次日志":"Discard This Log","主机 ":"Host ","内置":"Built-in","英寸":"-inch","秒":"s"
        ],
        "zh-Hant": [
            "控制器 ": "控制器 ", "主机校准：": "主機校準：", "内置校准：": "內建校準：",
            "实际采用：": "實際採用：", "操作目标：": "操作目標：", "模型：": "模型：",
            "已校准": "已校準", "未校准": "未校準", "无模型": "無模型", "机型未识别": "機型未識別",
            "后端待更新": "後端待更新", "已安装": "已安裝"
        ],
        "ja": [
            "控制器 ": "コントローラ ", "主机校准：": "ホスト校正：", "内置校准：": "内蔵校正：",
            "实际采用：": "使用中：", "操作目标：": "操作対象：", "模型：": "モデル：",
            "已校准": "校正済み", "未校准": "未校正", "无模型": "モデルなし", "机型未识别": "機種未認識",
            "后端待更新": "バックエンド更新待ち", "已安装": "インストール済み"
        ],
        "ko": [
            "控制器 ": "컨트롤러 ", "主机校准：": "호스트 보정: ", "内置校准：": "내장 보정: ",
            "实际采用：": "사용 중: ", "操作目标：": "작업 대상: ", "模型：": "모델: ",
            "已校准": "보정됨", "未校准": "미보정", "无模型": "모델 없음", "机型未识别": "기종 미확인",
            "后端待更新": "백엔드 업데이트 필요", "已安装": "설치됨"
        ]
    ]


    private static let helperFix: [String: [String: String]] = [
        "en": ["macOS：版本 27.3（版号 26C5035r）":"macOS Version: 27.3 (Build 26C5035r)","macOS：":"macOS Version: ","架构：":"Architecture: ","App minOS：":"App minOS: ",
               "系统兼容：":"System Compatibility: ","Helper 文件：":"Helper File: ","backend 文件：":"Backend File: ",
               "plist：":"plist: ","服务：":"Service: ","socket：":"Socket: ","已登记/可读取":"Registered / Readable",
               "未监听/不存在":"Not listening / missing","存在":"Present","未运行或未登记":"Not running / not registered",
               "与内嵌 T1306Z 载荷匹配":"Matches embedded T1306Z payload","未安装":"Not installed",
               "内置布局为部分校准；未关联槽位不自动推断。":"Built-in layout is partially calibrated; unmapped slots are not inferred.",
               "签名有效":"Signature Valid",
               
               "检测到旧式 RID-only 自定义行 3 条：Built-in 槽位优先，旧行未删除；如冲突可按 controller/PortNumber 重新校准。":"Detected 3 legacy RID-only custom entries: built-in slots take precedence; old rows are not deleted. Recalibrate by controller/PortNumber if they conflict.",
               "未匹配 Port 只列在详情：RID 5，不默认选中。":"Unmatched ports are listed in details only: RID 5; not selected by default.",
               
               "App 声明 ":"App declares ","检测到旧式 RID-only 自定义行 ":"Detected legacy RID-only custom entries: ",
               " 条；内置槽位优先，旧行未删除；如冲突可按 controller/PortNumber 重新校准。":" built-in slots take precedence; old rows are not deleted. Recalibrate by controller/PortNumber if they conflict.",
               "未匹配端口只列在详情：":"Unmatched ports are listed in details only: ","；不默认选中。":"; not selected by default."],
        "zh-Hant": ["macOS：":"macOS 版本：","架构：":"架構：","App minOS：":"App minOS：","系统兼容：":"系統相容性：",
               "Helper 文件：":"Helper 檔案：","backend 文件：":"backend 檔案：","plist：":"plist：","服务：":"服務：","socket：":"socket：",
               "已登记/可读取":"已登記/可讀取","未监听/不存在":"未監聽/不存在","存在":"存在","未运行或未登记":"未執行或未登記",
               "与内嵌 T1306Z 载荷匹配":"與內嵌 T1306Z 載荷相符","未安装":"未安裝",
               "内置布局为部分校准；未关联槽位不自动推断。":"內建版面為部分校準；未關聯槽位不自動推斷。"],
        "ja": ["macOS：":"macOS バージョン：","架构：":"アーキテクチャ：","App minOS：":"App minOS：","系统兼容：":"システム互換性：",
               "Helper 文件：":"Helper ファイル：","backend 文件：":"backend ファイル：","plist：":"plist：","服务：":"サービス：","socket：":"ソケット：",
               "已登记/可读取":"登録済み/読み取り可能","未监听/不存在":"未待受/存在しません","存在":"存在","未运行或未登记":"未実行/未登録",
               "与内嵌 T1306Z 载荷匹配":"内蔵 T1306Z ペイロードと一致","未安装":"未インストール",
               "内置布局为部分校准；未关联槽位不自动推断。":"内蔵レイアウトは部分校正です。未関連スロットは自動推測しません。"],
        "ko": ["macOS：":"macOS 버전: ","架构：":"아키텍처: ","App minOS：":"App minOS: ","系统兼容：":"시스템 호환성: ",
               "Helper 文件：":"Helper 파일: ","backend 文件：":"backend 파일: ","plist：":"plist: ","服务：":"서비스: ","socket：":"소켓: ",
               "已登记/可读取":"등록됨/읽기 가능","未监听/不存在":"수신 안 함/없음","存在":"있음","未运行或未登记":"실행 안 됨/등록 안 됨","签名有效":"서명 유효",
               "与内嵌 T1306Z 载荷匹配":"내장 T1306Z 페이로드와 일치","未安装":"설치 안 됨",
               "内置布局为部分校准；未关联槽位不自动推断。":"내장 레이아웃은 부분 보정입니다. 연결되지 않은 슬롯은 자동 추론하지 않습니다."]
    ]

    private static let techFix: [String: [String: String]] = [
        "en": ["线材/端口能力":"Cable/port capability","当前链路":"Current link","当前协议":"Current protocol",
               "控制器连接状态":"Controller connection state","连接计数":"Connection count","连接类型（读取值）":"Connection type (read)",
               "线材与能力":"Cable & capability","线材标识":"Cable identity","端口控制器":"Port controller",
               "控制器端口":"Controller port","连接路径":"Connection path","已配置传输，观察":"provisioned (observed)",
               "（已配置传输，观察）":" (provisioned, observed)","目标端口已就绪":"Target port ready",
            "（能力，不代表当前速率）":" (capability, not current speed)","（能力上限，非当前速率）":" (capability limit, not current speed)",
               "当前已选择物理端口，可执行设备控制。":"A physical port is selected and ready for device control."],
        "zh-Hant": ["线材/端口能力":"線材/連接埠能力","当前链路":"目前鏈路","当前协议":"目前協議",
               "控制器连接状态":"控制器連接狀態","连接计数":"連接計數","连接类型（读取值）":"連接類型（讀取值）",
               "线材与能力":"線材與能力","线材标识":"線材標識","端口控制器":"連接埠控制器",
               "控制器端口":"控制器連接埠","连接路径":"連接路徑","已配置传输，观察":"已配置傳輸，觀察",
               "（能力，不代表当前速率）":"（能力，不代表目前速率）","（能力上限，非当前速率）":"（能力上限，非目前速率）",
               "目标端口已就绪":"目標連接埠已就緒","当前已选择物理端口，可执行设备控制。":"目前已選擇實體連接埠，可執行裝置控制。"],
        "ja": ["线材/端口能力":"ケーブル/ポート機能","当前链路":"現在のリンク","当前协议":"現在のプロトコル",
               "控制器连接状态":"コントローラ接続状態","连接计数":"接続回数","连接类型（读取值）":"接続タイプ（読取値）",
               "线材与能力":"ケーブルと機能","线材标识":"ケーブル識別","端口控制器":"ポートコントローラ",
               "控制器端口":"コントローラポート","连接路径":"接続経路","已配置传输，观察":"設定済み（観察）",
               "（能力，不代表当前速率）":"（機能。現在の速度ではありません）","（能力上限，非当前速率）":"（機能上限。現在の速度ではありません）",
               "目标端口已就绪":"対象ポートの準備完了","当前已选择物理端口，可执行设备控制。":"物理ポートが選択され、デバイス操作を実行できます。"],
        "ko": ["线材/端口能力":"케이블/포트 기능","当前链路":"현재 링크","当前协议":"현재 프로토콜",
               "控制器连接状态":"컨트롤러 연결 상태","连接计数":"연결 횟수","连接类型（读取值）":"연결 유형(읽기)",
               "线材与能力":"케이블 및 기능","线材标识":"케이블 식별","端口控制器":"포트 컨트롤러",
               "控制器端口":"컨트롤러 포트","连接路径":"연결 경로","已配置传输，观察":"설정됨(관찰)",
               "（能力，不代表当前速率）":"(기능, 현재 속도 아님)","（能力上限，非当前速率）":"(기능 한계, 현재 속도 아님)",
               "目标端口已就绪":"대상 포트 준비됨","当前已选择物理端口，可执行设备控制。":"물리 포트가 선택되어 기기 제어를 실행할 수 있습니다."]
    ]

    private static let mainFix: [String: [String: String]] = [
        "en": [
            "设备控制与日志采集 · 先看清端口和设备，再采集日志；刷机仍用 Apple Configurator。":"Device control and log capture · Inspect ports and devices first; use Apple Configurator for restore.",
            "模型校准":"Model Calibration","端口校准":"Port Calibration","校准与位置图":"Calibration & Location Map","日志预览过滤":"Log Preview Filter","关于软件":"About Software","语言":"Language",
            "主机 ":"Host ","机型已精确校准":"Model precisely calibrated","内置 ":"Built-in ","英寸":"-inch",
            "部分校准；跳过 ":"partial calibration; skipped ","左侧上方":"Upper Left","左侧下方":"Lower Left","右侧":"Right","左侧":"Left",
            "内置主机校准":"Built-in host calibration", "实际采用：内置主机校准":"In use: Built-in host calibration",
            "本机型直接匹配":"Direct model match", "主机校准：本机型直接匹配":"Host calibration: direct model match",
            "内置校准：":"Built-in calibration: ", "设备详情":"Device details", "端口详情":"Port details",
            "恢复模式：向点击时选定的同一主机端口发送 5 次普通重启（0/3/6/9/12 秒，15 秒窗口）；不调用 reboot serial/DVEn；以目标 Mac 屏幕出现齿轮『选项』为准。":"Recovery: send five ordinary restarts to the same selected host port (0/3/6/9/12 s, 15 s window). No reboot serial/DVEn. The target Mac must show the gear Options screen."
        ],
        "zh-Hant": ["本机型直接匹配":"本機型直接匹配","主机校准：本机型直接匹配":"主機校準：本機型直接匹配","内置主机校准":"內建主機校準","设备详情":"裝置詳情","端口详情":"連接埠詳情",
            "设备控制与日志采集 · 先看清端口和设备，再采集日志；刷机仍用 Apple Configurator。":"裝置控制與日誌擷取 · 先確認連接埠和裝置，再擷取日誌；刷機仍使用 Apple Configurator。",
            "恢复模式：向点击时选定的同一主机端口发送 5 次普通重启（0/3/6/9/12 秒，15 秒窗口）；不调用 reboot serial/DVEn；以目标 Mac 屏幕出现齿轮『选项』为准。":"恢復模式：向點擊時選定的同一主機連接埠發送 5 次一般重新啟動（0/3/6/9/12 秒，15 秒內）；不呼叫 reboot serial/DVEn；以目標 Mac 畫面出現齒輪『選項』為準。"],
        "ja": ["本机型直接匹配":"機種直接一致","主机校准：本机型直接匹配":"ホスト校正：機種直接一致","内置主机校准":"内蔵ホスト校正","设备详情":"デバイス詳細","端口详情":"ポート詳細",
            "设备控制与日志采集 · 先看清端口和设备，再采集日志；刷机仍用 Apple Configurator。":"デバイス制御とログ収集 · 先にポートとデバイスを確認し、復元は Apple Configurator を使用します。",
            "恢复模式：向点击时选定的同一主机端口发送 5 次普通重启（0/3/6/9/12 秒，15 秒窗口）；不调用 reboot serial/DVEn；以目标 Mac 屏幕出现齿轮『选项』为准。":"リカバリ：選択した同じホストポートへ 5 回の通常再起動を送信します（0/3/6/9/12 秒、15 秒間）。reboot serial/DVEn は使用しません。目標 Mac に歯車の「オプション」が表示されることを確認してください。"],
        "ko": ["本机型直接匹配":"기종 직접 일치","主机校准：本机型直接匹配":"호스트 보정: 기종 직접 일치","内置主机校准":"내장 호스트 보정","设备详情":"기기 세부 정보","端口详情":"포트 세부 정보",
            "设备控制与日志采集 · 先看清端口和设备，再采集日志；刷机仍用 Apple Configurator。":"기기 제어 및 로그 수집 · 포트와 기기를 먼저 확인하고 복원은 Apple Configurator를 사용하세요.",
            "恢复模式：向点击时选定的同一主机端口发送 5 次普通重启（0/3/6/9/12 秒，15 秒窗口）；不调用 reboot serial/DVEn；以目标 Mac 屏幕出现齿轮『选项』为准。":"복구 모드: 선택한 동일 호스트 포트로 일반 재시작을 5회 전송합니다(0/3/6/9/12초, 15초 동안). reboot serial/DVEn은 사용하지 않습니다. 대상 Mac 화면에 톱니바퀴 ‘옵션’이 표시되는지 확인하세요."]
    ]

    private static let batch7: [String: [String: String]] = [
        "en": ["生效记录：":"Active record: ", "打开独立校准工具 Hardware Preview B.1（\(CalibrationToolLauncher.expectedVersion)）编辑布局并自行校准。本页不再用简化 RID 表代替该工具。导入模型包来自 v2 整合能力，不是 B.1 成品里已有的导入按钮。":"Open the standalone Hardware Preview B.1 (\(CalibrationToolLauncher.expectedVersion)) tool to edit and calibrate the layout. This page no longer substitutes a simplified RID table for that tool. Model-pack import is a v2 capability, not an existing B.1 button."],
        "zh-Hant": ["生效记录：":"生效記錄：", "打开独立校准工具 Hardware Preview B.1（\(CalibrationToolLauncher.expectedVersion)）编辑布局并自行校准。本页不再用简化 RID 表代替该工具。导入模型包来自 v2 整合能力，不是 B.1 成品里已有的导入按钮。":"開啟獨立校準工具 Hardware Preview B.1（\(CalibrationToolLauncher.expectedVersion)）編輯版面並自行校準。本頁不再以簡化 RID 表取代該工具。匯入模型包來自 v2 整合能力，不是 B.1 成品既有的匯入按鈕。"],
        "ja": ["生效记录：":"有効な記録：", "打开独立校准工具 Hardware Preview B.1（\(CalibrationToolLauncher.expectedVersion)）编辑布局并自行校准。本页不再用简化 RID 表代替该工具。导入模型包来自 v2 整合能力，不是 B.1 成品里已有的导入按钮。":"独立校正ツール Hardware Preview B.1（\(CalibrationToolLauncher.expectedVersion)）でレイアウトを編集し校正します。このページでは簡易 RID 表で代用しません。モデルパックの読み込みは v2 の機能で、B.1 既存のボタンではありません。"],
        "ko": ["生效记录：":"적용 기록: ", "打开独立校准工具 Hardware Preview B.1（\(CalibrationToolLauncher.expectedVersion)）编辑布局并自行校准。本页不再用简化 RID 表代替该工具。导入模型包来自 v2 整合能力，不是 B.1 成品里已有的导入按钮。":"독립 보정 도구 Hardware Preview B.1(\(CalibrationToolLauncher.expectedVersion))에서 레이아웃을 편집하고 보정하세요. 이 페이지는 더 이상 단순화된 RID 표로 해당 도구를 대체하지 않습니다. 모델 팩 가져오기는 v2 기능이며 B.1의 기존 버튼이 아닙니다."]
    ]

    private static let batch6: [String: [String: String]] = [
        "en": ["已保存：":"Saved: ","当前：":"Current: ","隔离保存：":"Isolated save: ","工具路径：":"Tool path: ","个":" items"],
        "zh-Hant": ["已保存：":"已儲存：","当前：":"目前：","隔离保存：":"隔離儲存：","工具路径：":"工具路徑：","个":" 個"],
        "ja": ["已保存：":"保存済み：","当前：":"現在：","隔离保存：":"隔離保存：","工具路径：":"ツールパス：","个":" 個"],
        "ko": ["已保存：":"저장됨: ","当前：":"현재: ","隔离保存：":"격리 저장: ","工具路径：":"도구 경로: ","个":"개"]
    ]

    private static let batch5: [String: [String: String]] = [
        "zh-Hant": [
            "English": "English",
            "© 2026 niubanxian1": "© 2026 niubanxian1",
            "仅添加模型、导入其他机型的包或套用布局，不会自动升级为「本机型已精确校准」或「机型已精确校准」。插拔「检测到唯一变化」仍在 B.1 工具中完成，需实机验收。": "僅新增模型、匯入其他機型的套件或套用版面配置，不會自動變成「本機型已精確校準」或「機型已精確校準」。插拔時的「偵測到唯一變化」仍須在 B.1 工具中完成，並需以實機驗收。",
            "关闭后立即回到完整原始预览，不会留下隐藏的活动过滤条件。保存始终为完整原始日志。主界面默认不显示实时日志行。": "關閉後會立即恢復完整的原始預覽，不會留下隱藏但仍生效的篩選條件。儲存時一律保留完整原始日誌。主畫面預設不顯示即時日誌行。",
            "只编辑槽位名称与朝向；PortNumber / RID 由按槽位校准写入，不从主机校准库猜测。": "僅編輯槽位名稱與方向；PortNumber / RID 由逐槽位校準寫入，不會根據主機校準資料庫推測。",
            "在本 App 内添加主机模型、导入已有模型包、编辑自定义布局，并按槽位完成「采基线 → 检测唯一变化 → 移除探针 → 确认映射」。保存后立即成为主界面与设置页共用的生效记录。": "在本 App 中新增主機模型、匯入現有模型套件、編輯自訂版面配置，並逐槽位完成「擷取基準值 → 偵測唯一變化 → 移除探針 → 確認對應關係」。儲存後，立即成為主畫面與設定頁共用的生效記錄。",
            "安装 Helper 需要 macOS 管理员授权。点击“授权安装”后，在系统授权窗口输入密码即可；只需点击一次。": "安裝 Helper 需要 macOS 管理員授權。按一下「授權安裝」，然後在系統授權視窗中輸入密碼即可；只需按一次。",
            "我希望这个工具不仅仅属于我一个人，而是能够通过大家的使用、研究和改进，逐渐变得更加完善。\n\n你可以自由使用、研究、修改和分发它，也欢迎在此基础上开发更强大的功能。\n\n如果你修复了问题，或者做出了更好的功能，我非常希望你能将这些改进分享回来，让更多人受益。\n\n分享不是义务，进步才是初衷。": "我希望這個工具不只屬於我一個人，而是能透過大家的使用、研究與改進，逐漸變得更加完善。\n\n你可以自由使用、研究、修改及散布它，也歡迎在此基礎上開發更強大的功能。\n\n如果你修復了問題，或開發出更好的功能，我非常希望你能將這些改進分享出來，讓更多人受益。\n\n分享不是義務，進步才是初衷。",
            "我是一名 MacBook 维修工程师。最初开发这个工具，只是想让日常 DFU、Revive 和 Restore 操作变得更方便、更稳定。\n\n现在，我希望把它免费分享给更多同行。": "我是一名 MacBook 維修工程師。最初開發這個工具，只是希望讓日常的 DFU、Revive 和 Restore 操作更方便、更穩定。\n\n現在，我希望把它免費分享給更多同行。",
            "我的开源理念": "我的開源理念",
            "打开模型校准工具…": "開啟模型校準工具…",
            "日本語": "日本語",
            "未找到随 App 打包的微信名片原图。": "找不到隨 App 一同封裝的微信名片原始圖片。",
            "每个槽位都按「采基线 → 插入探针 → 检测唯一变化 → 移除探针 → 确认映射」执行。读取的是主机端口连接状态，不发送 DFU／重启。": "每個槽位均依「擷取基準值 → 插入探針 → 偵測唯一變化 → 移除探針 → 確認對應關係」執行。只會讀取主機連接埠的連線狀態，不會傳送 DFU／重新啟動指令。",
            "测试假设：0/3/6/9/12 秒五次普通重启；15 秒窗口；不调用 serial/DVEn，不自动宣告恢复模式。": "測試假設：在 0/3/6/9/12 秒進行五次一般重新啟動；視窗為 15 秒；不呼叫 serial/DVEn，也不會自動宣告已進入恢復模式。",
            "添加主机模型…": "新增主機模型…",
            "添加模型、导入或套用布局都不会把本机标成「本机型精确校准」。只有完成全部槽位映射并保存，才会标记为精确校准；跳过槽位时为自定义布局。": "新增模型、匯入或套用版面配置，都不會將本機標記為「本機型精確校準」。只有完成所有槽位的對應關係並儲存後，才會標記為精確校準；若跳過槽位，則屬於自訂版面配置。",
            "用手机扫描下方原图即可添加。点击图片可放大查看。": "使用手機掃描下方的原始圖片即可新增聯絡人。點擊圖片可放大檢視。",
            "简体中文": "简体中文",
            "繁體中文": "繁體中文",
            "编辑自定义布局…": "編輯自訂版面配置…",
            "设备控制与日志采集 · 先看清端口和设备，再采集日志；刷机仍用 Apple Configurator。": "裝置控制與日誌擷取 · 先確認連接埠和裝置，再擷取日誌；刷機仍使用 Apple Configurator。",
            "验收模拟模式：以下按钮只改变模拟端口状态，不是真实插拔。": "驗收模擬模式：下列按鈕只會變更模擬連接埠狀態，並非實際插拔。",
            "한국어": "한국어"
        ],
        "en": [
            "English": "English",
            "© 2026 niubanxian1": "© 2026 niubanxian1",
            "仅添加模型、导入其他机型的包或套用布局，不会自动升级为「本机型已精确校准」或「机型已精确校准」。插拔「检测到唯一变化」仍在 B.1 工具中完成，需实机验收。": "Adding a model, importing a package for another model, or applying a layout does not automatically change the status to “This model is precisely calibrated” or “Model is precisely calibrated.” The “detect a unique change” step during connection or disconnection must still be performed in the B.1 tool and verified on real hardware.",
            "关闭后立即回到完整原始预览，不会留下隐藏的活动过滤条件。保存始终为完整原始日志。主界面默认不显示实时日志行。": "Turning this off immediately restores the full raw preview, without leaving any hidden active filters. Saving always preserves the complete raw log. Live log lines are hidden on the main screen by default.",
            "只编辑槽位名称与朝向；PortNumber / RID 由按槽位校准写入，不从主机校准库猜测。": "Only slot names and orientation can be edited here. PortNumber / RID are written by per-slot calibration, not inferred from the host calibration database.",
            "在本 App 内添加主机模型、导入已有模型包、编辑自定义布局，并按槽位完成「采基线 → 检测唯一变化 → 移除探针 → 确认映射」。保存后立即成为主界面与设置页共用的生效记录。": "In this app, add a host model, import an existing model package, edit a custom layout, and complete “Capture baseline → Detect unique change → Remove probe → Confirm mapping” for each slot. Once saved, the record takes effect immediately and is shared by the main screen and Settings.",
            "安装 Helper 需要 macOS 管理员授权。点击“授权安装”后，在系统授权窗口输入密码即可；只需点击一次。": "Installing the Helper requires macOS administrator authorization. Click “Authorize Install” once, then enter your password in the system authorization dialog.",
            "我希望这个工具不仅仅属于我一个人，而是能够通过大家的使用、研究和改进，逐渐变得更加完善。\n\n你可以自由使用、研究、修改和分发它，也欢迎在此基础上开发更强大的功能。\n\n如果你修复了问题，或者做出了更好的功能，我非常希望你能将这些改进分享回来，让更多人受益。\n\n分享不是义务，进步才是初衷。": "I hope this tool will be more than something that belongs to me alone. Through everyone’s use, research, and improvements, I hope it will gradually become better.\n\nYou are free to use, study, modify, and distribute it, and you are welcome to build even more powerful features on top of it.\n\nIf you fix a problem or create a better feature, I would love for you to share those improvements so that more people can benefit.\n\nSharing is not an obligation. Making progress is the original goal.",
            "我是一名 MacBook 维修工程师。最初开发这个工具，只是想让日常 DFU、Revive 和 Restore 操作变得更方便、更稳定。\n\n现在，我希望把它免费分享给更多同行。": "I’m a MacBook repair technician. I originally built this tool simply to make everyday DFU, Revive, and Restore operations easier and more reliable.\n\nNow I want to share it with more fellow technicians for free.",
            "我的开源理念": "My Open-Source Philosophy",
            "打开模型校准工具…": "Open Model Calibration Tool…",
            "日本語": "日本語",
            "未找到随 App 打包的微信名片原图。": "The original WeChat contact-card image bundled with the app could not be found.",
            "每个槽位都按「采基线 → 插入探针 → 检测唯一变化 → 移除探针 → 确认映射」执行。读取的是主机端口连接状态，不发送 DFU／重启。": "For each slot, follow “Capture baseline → Insert probe → Detect unique change → Remove probe → Confirm mapping.” This only reads the host port connection state; it does not send DFU or reboot commands.",
            "测试假设：0/3/6/9/12 秒五次普通重启；15 秒窗口；不调用 serial/DVEn，不自动宣告恢复模式。": "Test hypothesis: five normal reboots at 0/3/6/9/12 seconds; a 15-second window; no calls to serial/DVEn; Recovery mode is not automatically declared.",
            "添加主机模型…": "Add Host Model…",
            "添加模型、导入或套用布局都不会把本机标成「本机型精确校准」。只有完成全部槽位映射并保存，才会标记为精确校准；跳过槽位时为自定义布局。": "Adding a model, importing a package, or applying a layout will not mark this host as “Precisely calibrated for this model.” It is marked as precisely calibrated only after every slot is mapped and saved. If a slot is skipped, the result is a custom layout.",
            "用手机扫描下方原图即可添加。点击图片可放大查看。": "Scan the original image below with your phone to add this contact. Click the image to enlarge it.",
            "简体中文": "简体中文",
            "繁體中文": "繁體中文",
            "编辑自定义布局…": "Edit Custom Layout…",
            "设备控制与日志采集 · 先看清端口和设备，再采集日志；刷机仍用 Apple Configurator。": "Device Control & Log Capture · Check the port and device before capturing logs; continue using Apple Configurator for firmware restores.",
            "验收模拟模式：以下按钮只改变模拟端口状态，不是真实插拔。": "Acceptance-test simulation mode: the buttons below change simulated port states only; they do not physically connect or disconnect a device.",
            "한국어": "한국어"
        ],
        "ja": [
            "English": "English",
            "© 2026 niubanxian1": "© 2026 niubanxian1",
            "仅添加模型、导入其他机型的包或套用布局，不会自动升级为「本机型已精确校准」或「机型已精确校准」。插拔「检测到唯一变化」仍在 B.1 工具中完成，需实机验收。": "モデルの追加、別の機種用パッケージのインポート、またはレイアウトの適用だけでは、「この機種は精密に校正済み」や「機種は精密に校正済み」の状態には自動的に切り替わりません。接続・取り外し時の「一意の変化を検出」は引き続き B.1 ツールで行い、実機で検証する必要があります。",
            "关闭后立即回到完整原始预览，不会留下隐藏的活动过滤条件。保存始终为完整原始日志。主界面默认不显示实时日志行。": "オフにすると、非表示の有効なフィルターを残さず、完全な元ログのプレビューにすぐ戻ります。保存されるのは常に完全な元ログです。メイン画面では、リアルタイムのログ行は既定で表示されません。",
            "只编辑槽位名称与朝向；PortNumber / RID 由按槽位校准写入，不从主机校准库猜测。": "ここではスロット名と向きのみを編集します。PortNumber / RID はスロットごとの校正で書き込まれ、ホストの校正データベースから推測されることはありません。",
            "在本 App 内添加主机模型、导入已有模型包、编辑自定义布局，并按槽位完成「采基线 → 检测唯一变化 → 移除探针 → 确认映射」。保存后立即成为主界面与设置页共用的生效记录。": "このアプリ内でホストのモデルを追加し、既存のモデルパッケージをインポートし、カスタムレイアウトを編集できます。各スロットで「基準値を取得 → 一意の変化を検出 → プローブを取り外す → 対応付けを確定」を行ってください。保存すると、メイン画面と設定画面で共通して使われる有効な記録になります。",
            "安装 Helper 需要 macOS 管理员授权。点击“授权安装”后，在系统授权窗口输入密码即可；只需点击一次。": "Helper のインストールには macOS の管理者認証が必要です。「インストールを承認」を一度だけクリックし、システムの認証ダイアログでパスワードを入力してください。",
            "我希望这个工具不仅仅属于我一个人，而是能够通过大家的使用、研究和改进，逐渐变得更加完善。\n\n你可以自由使用、研究、修改和分发它，也欢迎在此基础上开发更强大的功能。\n\n如果你修复了问题，或者做出了更好的功能，我非常希望你能将这些改进分享回来，让更多人受益。\n\n分享不是义务，进步才是初衷。": "このツールを自分一人だけのものにせず、皆さんに使っていただき、研究や改良を重ねることで、少しずつより良いものにしていきたいと考えています。\n\n自由に利用・研究・改変・再配布していただいて構いません。このツールを基に、さらに優れた機能を開発していただくことも歓迎します。\n\n不具合を修正したり、より良い機能を開発したりした場合は、その改善を共有していただけるとうれしいです。より多くの人に役立つことを願っています。\n\n共有は義務ではありません。進歩こそが、最初からの願いです。",
            "我是一名 MacBook 维修工程师。最初开发这个工具，只是想让日常 DFU、Revive 和 Restore 操作变得更方便、更稳定。\n\n现在，我希望把它免费分享给更多同行。": "私は MacBook の修理技術者です。このツールは、日常の DFU・Revive・Restore 操作をもっと手軽で安定したものにしたいという思いから開発を始めました。\n\n今では、より多くの同業者の皆さんに無料で共有したいと考えています。",
            "我的开源理念": "私のオープンソースに対する考え方",
            "打开模型校准工具…": "モデル校正ツールを開く…",
            "日本語": "日本語",
            "未找到随 App 打包的微信名片原图。": "アプリに同梱されている WeChat 連絡先カードの元画像が見つかりません。",
            "每个槽位都按「采基线 → 插入探针 → 检测唯一变化 → 移除探针 → 确认映射」执行。读取的是主机端口连接状态，不发送 DFU／重启。": "各スロットで「基準値を取得 → プローブを挿入 → 一意の変化を検出 → プローブを取り外す → 対応付けを確定」を実行します。ホストポートの接続状態を読み取るだけで、DFU コマンドや再起動コマンドは送信しません。",
            "测试假设：0/3/6/9/12 秒五次普通重启；15 秒窗口；不调用 serial/DVEn，不自动宣告恢复模式。": "テスト上の仮定：0/3/6/9/12 秒に通常の再起動を計 5 回実行し、ウィンドウは 15 秒とします。serial/DVEn は呼び出さず、リカバリーモードに入ったとは自動判定しません。",
            "添加主机模型…": "ホストモデルを追加…",
            "添加模型、导入或套用布局都不会把本机标成「本机型精确校准」。只有完成全部槽位映射并保存，才会标记为精确校准；跳过槽位时为自定义布局。": "モデルの追加、インポート、またはレイアウトの適用だけでは、このホストは「この機種に対して精密校正済み」とは表示されません。すべてのスロットの対応付けを完了して保存した場合にのみ、精密校正済みと表示されます。スロットをスキップした場合はカスタムレイアウトになります。",
            "用手机扫描下方原图即可添加。点击图片可放大查看。": "スマートフォンで下の元画像をスキャンすると、連絡先を追加できます。画像をクリックすると拡大表示できます。",
            "简体中文": "简体中文",
            "繁體中文": "繁體中文",
            "编辑自定义布局…": "カスタムレイアウトを編集…",
            "设备控制与日志采集 · 先看清端口和设备，再采集日志；刷机仍用 Apple Configurator。": "デバイス制御とログ収集 · ログを収集する前にポートとデバイスを確認してください。ファームウェアの復元には引き続き Apple Configurator を使用します。",
            "验收模拟模式：以下按钮只改变模拟端口状态，不是真实插拔。": "受け入れテスト用シミュレーションモード：以下のボタンは模擬ポートの状態を変更するだけで、実際の接続・取り外しは行いません。",
            "한국어": "한국어"
        ],
        "ko": [
            "English": "English",
            "© 2026 niubanxian1": "© 2026 niubanxian1",
            "仅添加模型、导入其他机型的包或套用布局，不会自动升级为「本机型已精确校准」或「机型已精确校准」。插拔「检测到唯一变化」仍在 B.1 工具中完成，需实机验收。": "모델을 추가하거나 다른 기종의 패키지를 가져오거나 레이아웃을 적용하는 것만으로는 ‘이 기종 정밀 보정 완료’ 또는 ‘기종 정밀 보정 완료’ 상태로 자동 전환되지 않습니다. 연결·분리 시 ‘유일한 변화 감지’ 단계는 여전히 B.1 도구에서 수행하고 실제 기기로 검증해야 합니다.",
            "关闭后立即回到完整原始预览，不会留下隐藏的活动过滤条件。保存始终为完整原始日志。主界面默认不显示实时日志行。": "이 기능을 끄면 숨겨진 활성 필터를 남기지 않고 전체 원본 미리보기로 즉시 돌아갑니다. 저장할 때는 항상 전체 원본 로그가 보존됩니다. 기본적으로 메인 화면에는 실시간 로그 행이 표시되지 않습니다.",
            "只编辑槽位名称与朝向；PortNumber / RID 由按槽位校准写入，不从主机校准库猜测。": "여기서는 슬롯 이름과 방향만 편집합니다. PortNumber / RID는 슬롯별 보정을 통해 기록되며, 호스트 보정 데이터베이스에서 추정하지 않습니다.",
            "在本 App 内添加主机模型、导入已有模型包、编辑自定义布局，并按槽位完成「采基线 → 检测唯一变化 → 移除探针 → 确认映射」。保存后立即成为主界面与设置页共用的生效记录。": "이 앱에서 호스트 모델을 추가하고 기존 모델 패키지를 가져오며 사용자 지정 레이아웃을 편집할 수 있습니다. 각 슬롯에서 ‘기준값 수집 → 유일한 변화 감지 → 프로브 제거 → 매핑 확인’을 완료하세요. 저장하면 메인 화면과 설정 화면에서 함께 사용하는 적용 기록으로 즉시 반영됩니다.",
            "安装 Helper 需要 macOS 管理员授权。点击“授权安装”后，在系统授权窗口输入密码即可；只需点击一次。": "Helper를 설치하려면 macOS 관리자 인증이 필요합니다. ‘설치 승인’을 한 번만 클릭한 다음 시스템 인증 창에 암호를 입력하세요.",
            "我希望这个工具不仅仅属于我一个人，而是能够通过大家的使用、研究和改进，逐渐变得更加完善。\n\n你可以自由使用、研究、修改和分发它，也欢迎在此基础上开发更强大的功能。\n\n如果你修复了问题，或者做出了更好的功能，我非常希望你能将这些改进分享回来，让更多人受益。\n\n分享不是义务，进步才是初衷。": "이 도구가 저만의 것이 아니라, 많은 분이 사용하고 연구하고 개선하면서 점점 더 나아지기를 바랍니다.\n\n누구나 자유롭게 사용하고 연구하고 수정하고 배포할 수 있으며, 이를 바탕으로 더 강력한 기능을 개발하는 것도 환영합니다.\n\n문제를 해결하거나 더 좋은 기능을 만들었다면, 더 많은 사람이 혜택을 받을 수 있도록 그 개선 사항을 공유해 주시면 정말 기쁘겠습니다.\n\n공유는 의무가 아닙니다. 발전이야말로 처음부터 추구한 목표입니다.",
            "我是一名 MacBook 维修工程师。最初开发这个工具，只是想让日常 DFU、Revive 和 Restore 操作变得更方便、更稳定。\n\n现在，我希望把它免费分享给更多同行。": "저는 MacBook 수리 엔지니어입니다. 처음 이 도구를 만든 이유는 일상적인 DFU, Revive, Restore 작업을 더 편리하고 안정적으로 수행하기 위해서였습니다.\n\n이제 더 많은 동료 수리 기사에게 무료로 공유하고 싶습니다.",
            "我的开源理念": "나의 오픈 소스 철학",
            "打开模型校准工具…": "모델 보정 도구 열기…",
            "日本語": "日本語",
            "未找到随 App 打包的微信名片原图。": "앱에 포함된 WeChat 연락처 카드 원본 이미지를 찾을 수 없습니다.",
            "每个槽位都按「采基线 → 插入探针 → 检测唯一变化 → 移除探针 → 确认映射」执行。读取的是主机端口连接状态，不发送 DFU／重启。": "각 슬롯에서 ‘기준값 수집 → 프로브 삽입 → 유일한 변화 감지 → 프로브 제거 → 매핑 확인’ 순서로 진행합니다. 호스트 포트의 연결 상태만 읽으며 DFU 또는 재시동 명령은 보내지 않습니다.",
            "测试假设：0/3/6/9/12 秒五次普通重启；15 秒窗口；不调用 serial/DVEn，不自动宣告恢复模式。": "테스트 가정: 0/3/6/9/12초에 일반 재시동을 총 5회 수행하며, 관찰 구간은 15초입니다. serial/DVEn을 호출하지 않으며 복구 모드 진입을 자동으로 선언하지 않습니다.",
            "添加主机模型…": "호스트 모델 추가…",
            "添加模型、导入或套用布局都不会把本机标成「本机型精确校准」。只有完成全部槽位映射并保存，才会标记为精确校准；跳过槽位时为自定义布局。": "모델을 추가하거나 가져오거나 레이아웃을 적용해도 이 호스트가 ‘이 기종에 대해 정밀 보정 완료’로 표시되지는 않습니다. 모든 슬롯의 매핑을 완료하고 저장해야 정밀 보정 완료로 표시됩니다. 슬롯을 건너뛴 경우 사용자 지정 레이아웃으로 처리됩니다.",
            "用手机扫描下方原图即可添加。点击图片可放大查看。": "휴대전화로 아래 원본 이미지를 스캔하면 연락처를 추가할 수 있습니다. 이미지를 클릭하면 확대해서 볼 수 있습니다.",
            "简体中文": "简体中文",
            "繁體中文": "繁體中文",
            "编辑自定义布局…": "사용자 지정 레이아웃 편집…",
            "设备控制与日志采集 · 先看清端口和设备，再采集日志；刷机仍用 Apple Configurator。": "기기 제어 및 로그 수집 · 로그를 수집하기 전에 포트와 기기를 확인하세요. 펌웨어 복원은 계속 Apple Configurator에서 수행합니다.",
            "验收模拟模式：以下按钮只改变模拟端口状态，不是真实插拔。": "검수용 시뮬레이션 모드: 아래 버튼은 시뮬레이션 포트 상태만 변경하며, 실제로 기기를 연결하거나 분리하지 않습니다.",
            "한국어": "한국어"
        ],
    ]

    private static let batch4: [String: [String: String]] = [
        "en": ["技术详情":"Technical Details","按槽位校准…":"Calibrate by Slot…","授权安装":"Authorize Install",
               "文件名":"File Name","正面":"Front","添加":"Add","界面语言":"Interface Language",
               "端口校准":"Port Calibration","设置":"Settings","跟随系统":"Follow System",
               "跳过此槽位":"Skip This Slot","重新载入":"Reload","背面":"Rear","许可证：":"License:",
               "设备控制":"Device Control","实际采用：内置记录（如有）":"In use: built-in record (if any)",
               "尚未选择主机物理端口":"No host physical port selected","左侧":"Left","已读回的槽位":"Read-back slots","开发者":"Developer"],
        "zh-Hant": ["技术详情":"技術詳情","按槽位校准…":"依槽位校準…","授权安装":"授權安裝",
               "文件名":"檔名","正面":"正面","添加":"新增","界面语言":"介面語言",
               "端口校准":"連接埠校準","设置":"設定","跟随系统":"跟隨系統",
               "跳过此槽位":"跳過此槽位","重新载入":"重新載入","背面":"背面","许可证：":"授權條款：",
               "设备控制":"裝置控制","实际采用：内置记录（如有）":"實際採用：內建記錄（如有）",
               "尚未选择主机物理端口":"尚未選擇主機實體連接埠","左侧":"左側","已读回的槽位":"已讀回的槽位","开发者":"開發者"],
        "ja": ["技术详情":"技術詳細","按槽位校准…":"スロットごとに校正…","授权安装":"インストールを承認",
               "文件名":"ファイル名","正面":"前面","添加":"追加","界面语言":"表示言語",
               "端口校准":"ポート校正","设置":"設定","跟随系统":"システムに合わせる",
               "跳过此槽位":"このスロットをスキップ","重新载入":"再読み込み","背面":"背面","许可证：":"ライセンス：",
               "设备控制":"デバイス制御","实际采用：内置记录（如有）":"使用中：内蔵記録（ある場合）",
               "尚未选择主机物理端口":"ホスト物理ポートが未選択です","左侧":"左","已读回的槽位":"読み戻したスロット","开发者":"開発者"],
        "ko": ["技术详情":"기술 세부 정보","按槽位校准…":"슬롯별 보정…","授权安装":"설치 승인",
               "文件名":"파일 이름","正面":"앞면","添加":"추가","界面语言":"인터페이스 언어",
               "端口校准":"포트 보정","设置":"설정","跟随系统":"시스템 설정 따르기",
               "跳过此槽位":"이 슬롯 건너뛰기","重新载入":"다시 불러오기","背面":"뒷면","许可证：":"라이선스:",
               "设备控制":"기기 제어","实际采用：内置记录（如有）":"사용 중: 내장 기록(있는 경우)",
               "尚未选择主机物理端口":"호스트 물리 포트가 선택되지 않았습니다","左侧":"왼쪽","已读回的槽位":"다시 읽은 슬롯","开发者":"개발자"]
    ]

    private static let batch3: [String: [String: String]] = [
        "en": [
            "Helper / 运行环境":"Helper / Environment","作者":"Author","保存并立即应用":"Save and Apply",
            "停止后续":"Stop Remaining","关于这个项目":"About This Project","关闭":"Close",
            "刷机日志采集":"Restore Log Capture","单机刷机日志预览过滤":"Restore Log Preview Filter",
            "取消":"Cancel","只改变界面显示，不会改变端口选择、设备状态、DFU、重启、恢复序列或采集。":"Display only; it does not change port selection, device state, DFU, restart, recovery sequence, or capture.",
            "只添加机型标识；不会自动套用布局，也不会标记精确校准。":"Adds a model identifier only; it does not apply a layout or mark exact calibration.",
            "在访达中显示":"Show in Finder","复制 ZIP":"Copy ZIP","复制邮箱":"Copy Email","完成":"Done",
            "导入已有模型包…":"Import Existing Model Pack…","尚无槽位。可先导入模型包，或编辑自定义布局添加槽位。":"No slots yet. Import a model pack or edit a custom layout to add slots.",
            "开始采集":"Start Capture","微信":"WeChat","微信名片原图":"WeChat Contact Image"
        ],
        "zh-Hant": [
            "Helper / 运行环境":"Helper / 執行環境","作者":"作者","保存并立即应用":"儲存並立即套用",
            "停止后续":"停止後續","关于这个项目":"關於這個專案","关闭":"關閉",
            "刷机日志采集":"刷機日誌擷取","单机刷机日志预览过滤":"單機刷機日誌預覽篩選",
            "取消":"取消","只改变界面显示，不会改变端口选择、设备状态、DFU、重启、恢复序列或采集。":"只改變介面顯示，不會改變連接埠選擇、裝置狀態、DFU、重新啟動、恢復序列或擷取。",
            "只添加机型标识；不会自动套用布局，也不会标记精确校准。":"只新增機型標識；不會自動套用版面，也不會標記精確校準。",
            "在访达中显示":"在 Finder 中顯示","复制 ZIP":"複製 ZIP","复制邮箱":"複製電子郵件","完成":"完成",
            "导入已有模型包…":"匯入現有機型包…","尚无槽位。可先导入模型包，或编辑自定义布局添加槽位。":"尚無槽位。可先匯入機型包，或編輯自訂版面新增槽位。",
            "开始采集":"開始擷取","微信":"微信","微信名片原图":"微信名片原圖"
        ],
        "ja": [
            "Helper / 运行环境":"Helper / 実行環境","作者":"作者","保存并立即应用":"保存して適用",
            "停止后续":"残りを停止","关于这个项目":"このプロジェクトについて","关闭":"閉じる",
            "刷机日志采集":"復元ログ収集","单机刷机日志预览过滤":"復元ログプレビュー フィルター",
            "取消":"キャンセル","只改变界面显示，不会改变端口选择、设备状态、DFU、重启、恢复序列或采集。":"表示のみを変更し、ポート選択、デバイス状態、DFU、再起動、リカバリ、収集には影響しません。",
            "只添加机型标识；不会自动套用布局，也不会标记精确校准。":"モデル識別子のみ追加し、レイアウト適用や正確な校正の marking は行いません。",
            "在访达中显示":"Finder に表示","复制 ZIP":"ZIP をコピー","复制邮箱":"メールをコピー","完成":"完了",
            "导入已有模型包…":"既存モデルパックを読み込む…","尚无槽位。可先导入模型包，或编辑自定义布局添加槽位。":"スロットがありません。モデルパックを読み込むか、カスタムレイアウトを編集して追加してください。",
            "开始采集":"収集開始","微信":"WeChat","微信名片原图":"WeChat 連絡先画像"
        ],
        "ko": [
            "Helper / 运行环境":"Helper / 실행 환경","作者":"작성자","保存并立即应用":"저장 및 적용",
            "停止后续":"나머지 중지","关于这个项目":"프로젝트 정보","关闭":"닫기",
            "刷机日志采集":"복원 로그 수집","单机刷机日志预览过滤":"복원 로그 미리보기 필터",
            "取消":"취소","只改变界面显示，不会改变端口选择、设备状态、DFU、重启、恢复序列或采集。":"표시만 변경하며 포트 선택, 기기 상태, DFU, 재시작, 복구 시퀀스, 수집에는 영향을 주지 않습니다.",
            "只添加机型标识；不会自动套用布局，也不会标记精确校准。":"모델 식별자만 추가하며 레이아웃 적용이나 정확한 보정 표시는 하지 않습니다.",
            "在访达中显示":"Finder에서 보기","复制 ZIP":"ZIP 복사","复制邮箱":"이메일 복사","完成":"완료",
            "导入已有模型包…":"기존 모델 팩 가져오기…","尚无槽位。可先导入模型包，或编辑自定义布局添加槽位。":"슬롯이 없습니다. 모델 팩을 가져오거나 사용자 레이아웃을 편집해 슬롯을 추가하세요.",
            "开始采集":"수집 시작","微信":"WeChat","微信名片原图":"WeChat 연락처 이미지"
        ]
    ]

    private static let batch2: [String: [String: String]] = [
        "en": [
            "校准物理位置、PortNumber/RID、USB location。与模型校准分开保存；不替代模型校准。":"Calibrate physical position, PortNumber/RID, and USB location. Saved separately from model calibration.",
            "只读展示校准后的主机端口位置；编辑入口在“端口校准”，模型关联在“模型校准”。":"Read-only host port positions. Edit in Port Calibration; model mapping is in Model Calibration.",
            "接口位置图":"Port Location Map", "保存端口校准":"Save Port Calibration",
            "停止采集":"Stop Capture", "导出 ZIP…":"Export ZIP…",
            "作废本次日志":"Discard This Log", "复制摘要":"Copy Summary",
            "采集进行中":"Capture in progress"
        ],
        "zh-Hant": [
            "校准物理位置、PortNumber/RID、USB location。与模型校准分开保存；不替代模型校准。":"校準實體位置、PortNumber/RID、USB location。與機型校準分開儲存；不取代機型校準。",
            "只读展示校准后的主机端口位置；编辑入口在“端口校准”，模型关联在“模型校准”。":"唯讀顯示校準後的主機連接埠位置；編輯入口在「連接埠校準」，機型關聯在「機型校準」。",
            "接口位置图":"連接埠位置圖", "保存端口校准":"儲存連接埠校準",
            "停止采集":"停止擷取", "导出 ZIP…":"匯出 ZIP…",
            "作废本次日志":"作廢本次日誌", "复制摘要":"複製摘要",
            "采集进行中":"擷取進行中"
        ],
        "ja": [
            "校准物理位置、PortNumber/RID、USB location。与模型校准分开保存；不替代模型校准。":"物理位置、PortNumber/RID、USB location を校正します。モデル校正とは別に保存され、モデル校正の代わりにはなりません。",
            "只读展示校准后的主机端口位置；编辑入口在“端口校准”，模型关联在“模型校准”。":"校正済みホストポート位置を表示します。編集は「ポート校正」、モデル関連は「モデル校正」です。",
            "接口位置图":"ポート位置図", "保存端口校准":"ポート校正を保存",
            "停止采集":"収集を停止", "导出 ZIP…":"ZIP を書き出す…",
            "作废本次日志":"このログを破棄", "复制摘要":"概要をコピー",
            "采集进行中":"収集中"
        ],
        "ko": [
            "校准物理位置、PortNumber/RID、USB location。与模型校准分开保存；不替代模型校准。":"물리 위치, PortNumber/RID, USB location을 보정합니다. 모델 보정과 별도로 저장되며 모델 보정을 대체하지 않습니다.",
            "只读展示校准后的主机端口位置；编辑入口在“端口校准”，模型关联在“模型校准”。":"보정된 호스트 포트 위치를 읽기 전용으로 표시합니다. 편집은 포트 보정, 모델 연결은 모델 보정에서 합니다.",
            "接口位置图":"포트 위치 지도", "保存端口校准":"포트 보정 저장",
            "停止采集":"수집 중지", "导出 ZIP…":"ZIP 내보내기…",
            "作废本次日志":"이 로그 폐기", "复制摘要":"요약 복사",
            "采集进行中":"수집 중"
        ]
    ]

    private static let configFix: [String: [String: String]] = [
        "en": ["重置 Apple Configurator":"Reset Apple Configurator",
               "这里操作的是本机上的 Apple Configurator 软件，不是左侧对目标设备的「重启设备」。进程存在并不表示正在刷机，也不表示软件空闲。":"This operates Apple Configurator on this Mac, not Restart Device for the target on the left. A running process does not mean a restore is in progress or that the app is idle.",
               "重新启动 Configurator 可能中断正在进行的刷机":"Restarting Configurator may interrupt a restore in progress.",
               "清理并重启 Configurator":"Clean Up and Restart Configurator","重新打开 Configurator":"Reopen Configurator","仅重新打开 Configurator":"Reopen Configurator Only",
               "保留缓存和用户数据":"Keep caches and user data","清理并重启":"Clean Up and Restart","重新打开":"Reopen",
               "取消":"Cancel","分步结果":"Step Results","成功":"Succeeded","失败":"Failed","可恢复副本：":"Recoverable copy: ",
               "本次将清理以下已核实的 Caches 路径：":"The following verified cache paths will be cleaned:",
               "本次默认清理以下已核实的 Caches 路径（若存在）：":"The following verified cache paths will be cleaned if present:",
               "Application Support 中的用户数据默认保留。":"User data in Application Support is kept by default.",
               "同时重置 Application Support（将先保留可恢复副本）":"Also reset Application Support (a recoverable copy is kept first)"],
        "zh-Hant": ["重置 Apple Configurator":"重設 Apple Configurator",
               "这里操作的是本机上的 Apple Configurator 软件，不是左侧对目标设备的「重启设备」。进程存在并不表示正在刷机，也不表示软件空闲。":"這裡操作的是本機上的 Apple Configurator 軟體，不是左側對目標裝置的「重新啟動裝置」。程序存在並不表示正在刷機，也不表示軟體閒置。",
               "重新启动 Configurator 可能中断正在进行的刷机":"重新啟動 Configurator 可能中斷正在進行的復原作業。",
               "清理并重启 Configurator":"清理並重新啟動 Configurator","仅重新打开 Configurator":"僅重新開啟 Configurator",
               "保留缓存和用户数据":"保留快取與使用者資料","清理并重启":"清理並重新啟動","重新打开":"重新開啟",
               "取消":"取消","分步结果":"分步結果","成功":"成功","失败":"失敗","可恢复副本：":"可還原的副本：",
               "本次将清理以下已核实的 Caches 路径：":"本次將清理下列已確認的快取路徑：",
               "本次默认清理以下已核实的 Caches 路径（若存在）：":"本次預設清理下列已確認的快取路徑（若存在）：",
               "Application Support 中的用户数据默认保留。":"Application Support 中的使用者資料預設會保留。",
               "同时重置 Application Support（将先保留可恢复副本）":"同時重設 Application Support（會先保留可還原的副本）"],
        "ja": ["重置 Apple Configurator":"Apple Configurator をリセット",
               "这里操作的是本机上的 Apple Configurator 软件，不是左侧对目标设备的「重启设备」。进程存在并不表示正在刷机，也不表示软件空闲。":"この操作はこの Mac 上の Apple Configurator に対するもので、左側で選択した対象デバイスの「デバイスを再起動」ではありません。プロセスが起動していても、復元処理中かどうか、またアプリがアイドル状態かどうかは判断できません。",
               "重新启动 Configurator 可能中断正在进行的刷机":"Configurator を再起動すると、進行中の復元が中断される可能性があります。",
               "清理并重启 Configurator":"キャッシュを消去して Configurator を再起動","仅重新打开 Configurator":"Configurator を開き直すだけ",
               "保留缓存和用户数据":"キャッシュとユーザーデータを保持","清理并重启":"消去して再起動","重新打开":"開き直す",
               "取消":"キャンセル","分步结果":"ステップ結果","成功":"成功","失败":"失敗","可恢复副本：":"復元可能なコピー：",
               "本次将清理以下已核实的 Caches 路径：":"以下の確認済みキャッシュパスを削除します：",
               "本次默认清理以下已核实的 Caches 路径（若存在）：":"以下の確認済みキャッシュパスを存在する場合に削除します：",
               "Application Support 中的用户数据默认保留。":"Application Support のユーザーデータは既定で保持されます。",
               "同时重置 Application Support（将先保留可恢复副本）":"Application Support もリセットする（事前に復元可能なコピーを保存）"],
        "ko": ["重置 Apple Configurator":"Apple Configurator 재설정",
               "这里操作的是本机上的 Apple Configurator 软件，不是左侧对目标设备的「重启设备」。进程存在并不表示正在刷机，也不表示软件空闲。":"이 작업은 왼쪽의 대상 기기를 재시동하는 것이 아니라 이 Mac의 Apple Configurator 앱을 대상으로 합니다. 프로세스가 실행 중이라는 사실만으로 복원이 진행 중이거나 앱이 유휴 상태라고 판단할 수는 없습니다.",
               "重新启动 Configurator 可能中断正在进行的刷机":"Configurator를 재시동하면 진행 중인 복원이 중단될 수 있습니다.",
               "清理并重启 Configurator":"캐시 정리 후 Configurator 재시동","仅重新打开 Configurator":"Configurator만 다시 열기",
               "保留缓存和用户数据":"캐시와 사용자 데이터 유지","清理并重启":"정리 후 재시동","重新打开":"다시 열기",
               "取消":"취소","分步结果":"단계 결과","成功":"성공","失败":"실패","可恢复副本：":"복구 가능한 사본: ",
               "本次将清理以下已核实的 Caches 路径：":"이번에 정리할 확인된 캐시 경로:",
               "本次默认清理以下已核实的 Caches 路径（若存在）：":"이번에 기본적으로 정리할 확인된 캐시 경로(있는 경우):",
               "Application Support 中的用户数据默认保留。":"Application Support의 사용자 데이터는 기본적으로 유지됩니다.",
               "同时重置 Application Support（将先保留可恢复副本）":"Application Support도 재설정(먼저 복구 가능한 사본 보관)"]
    ]


    private static let settingsFix: [String: [String: String]] = [
        "en": ["界面语言":"Interface Language","语言":"Language","跟随系统":"Follow System","模型校准":"Model Calibration",
               "端口 ID":"Port ID","显示名":"Display Name","方向":"Side","启用预览过滤":"Enable Preview Filter","预览范围":"Preview Scope",
               "完整原始":"Full Raw","当前设备":"Current Device","公共/未归属":"Public / Unassigned",
               "主界面按钮行为":"Main Button Behavior",
               "仅清理已存在的 Caches；Application Support 默认保留。":"Cleans existing Caches only; Application Support is kept by default.",
               "选择后立即保存；修改设置本身不会执行操作。":"Saves immediately; changing this setting does not execute anything.",
               "正在执行…":"Running…",
               "端口校准":"Port Calibration","校准与位置图":"Calibration & Location Map","日志预览过滤":"Log Preview Filter",
               "关于软件":"About Software","只改变界面显示，不会改变端口选择、设备状态、DFU、重启、恢复序列或采集。":"Display only. Port selection, device state, DFU, restart, recovery sequence, and capture are unchanged.",
               "需要安装 Helper":"Install Helper Required","稍后":"Later"],
        "zh-Hant": ["界面语言":"介面語言","语言":"語言","跟随系统":"跟隨系統","模型校准":"機型校準","端口校准":"連接埠校準",
               "主界面按钮行为":"主介面按鈕行為",
               "仅清理已存在的 Caches；Application Support 默认保留。":"僅清理已存在的 Caches；Application Support 預設保留。",
               "选择后立即保存；修改设置本身不会执行操作。":"選擇後立即儲存；修改設定本身不會執行操作。",
               "正在执行…":"正在執行…",
               "端口 ID":"連接埠 ID","显示名":"顯示名稱","方向":"方向","启用预览过滤":"啟用預覽篩選","预览范围":"預覽範圍",
               "完整原始":"完整原始","当前设备":"目前裝置","公共/未归属":"公共/未歸屬",
               "校准与位置图":"校準與位置圖","日志预览过滤":"日誌預覽篩選","关于软件":"關於軟體",
               "需要安装 Helper":"需要安裝 Helper","稍后":"稍後",
               "只改变界面显示，不会改变端口选择、设备状态、DFU、重启、恢复序列或采集。":"只改變介面顯示，不會改變連接埠選擇、裝置狀態、DFU、重新啟動、恢復序列或擷取。"],
        "ja": ["界面语言":"表示言語","语言":"言語","跟随系统":"システムに合わせる","模型校准":"モデル校正","端口校准":"ポート校正",
               "主界面按钮行为":"メイン画面のボタン動作",
               "仅清理已存在的 Caches；Application Support 默认保留。":"既存の Caches のみを清理します。Application Support は既定で保持されます。",
               "选择后立即保存；修改设置本身不会执行操作。":"選択するとすぐに保存されます。設定変更自体は操作を実行しません。",
               "正在执行…":"実行中…",
               "端口 ID":"ポート ID","显示名":"表示名","方向":"方向","启用预览过滤":"プレビュー フィルターを有効化","预览范围":"プレビュー範囲",
               "完整原始":"完全な生ログ","当前设备":"現在のデバイス","公共/未归属":"共通/未割り当て",
               "校准与位置图":"校正と位置図","日志预览过滤":"ログプレビュー フィルター","关于软件":"ソフトウェアについて",
               "需要安装 Helper":"Helper のインストールが必要","稍后":"後で",
               "只改变界面显示，不会改变端口选择、设备状态、DFU、重启、恢复序列或采集。":"表示のみを変更し、ポート選択、デバイス状態、DFU、再起動、復元、収集には影響しません。"],
        "ko": ["界面语言":"인터페이스 언어","语言":"언어","跟随系统":"시스템 설정 따르기","模型校准":"모델 보정","端口校准":"포트 보정",
               "主界面按钮行为":"메인 버튼 동작",
               "仅清理已存在的 Caches；Application Support 默认保留。":"기존 Caches만 정리합니다. Application Support는 기본적으로 유지됩니다.",
               "选择后立即保存；修改设置本身不会执行操作。":"선택 즉시 저장됩니다. 설정 변경 자체는 작업을 실행하지 않습니다.",
               "正在执行…":"실행 중…",
               "端口 ID":"포트 ID","显示名":"표시 이름","方向":"방향","启用预览过滤":"미리보기 필터 활성화","预览范围":"미리보기 범위",
               "完整原始":"전체 원본","当前设备":"현재 기기","公共/未归属":"공용/미할당",
               "校准与位置图":"보정 및 위치 지도","日志预览过滤":"로그 미리보기 필터","关于软件":"소프트웨어 정보",
               "需要安装 Helper":"Helper 설치 필요","稍后":"나중에",
               "只改变界面显示，不会改变端口选择、设备状态、DFU、重启、恢复序列或采集。":"표시만 변경하며 포트 선택, 기기 상태, DFU, 재시작, 복구, 수집에는 영향을 주지 않습니다."]
    ]

    private static let batch1: [String: [String: String]] = [
        "en": [
            "未识别到主机 AppleHPM 端口": "No host AppleHPM port detected",
            "插入": "Insert", "检测变化": "Detect Change",
            "确认已移除": "Confirm Removed", "重新读回": "Read Back",
            "添加端口": "Add Port", "布局名（可选）": "Layout name (optional)"
        ],
        "zh-Hant": [
            "未识别到主机 AppleHPM 端口": "未識別到主機 AppleHPM 連接埠",
            "插入": "插入", "检测变化": "偵測變化",
            "确认已移除": "確認已移除", "重新读回": "重新讀回",
            "添加端口": "新增連接埠", "布局名（可选）": "版面名稱（選填）"
        ],
        "ja": [
            "未识别到主机 AppleHPM 端口": "ホスト AppleHPM ポートが見つかりません",
            "插入": "挿入", "检测变化": "変化を検出",
            "确认已移除": "取り外しを確認", "重新读回": "再読み込み",
            "添加端口": "ポートを追加", "布局名（可选）": "レイアウト名（任意）"
        ],
        "ko": [
            "未识别到主机 AppleHPM 端口": "호스트 AppleHPM 포트를 찾지 못했습니다",
            "插入": "삽입", "检测变化": "변화 감지",
            "确认已移除": "제거 확인", "重新读回": "다시 읽기",
            "添加端口": "포트 추가", "布局名（可选）": "레이아웃 이름(선택)"
        ]
    ]

    private static let moduleC: [String: [String: String]] = [
        "en": [
            "模型校准":"Model Calibration","布局槽位":"Layout slots","添加主机模型":"Add Host Model",
            "编辑自定义布局":"Edit Custom Layout","按槽位校准":"Calibrate by Slot",
            "全部槽位已完成":"All slots complete","确认映射":"Confirm Mapping","检测变化":"Detect Change",
            "采基线":"Capture Baseline","移除":"Remove","添加槽位":"Add Slot","保存端口校准":"Save Port Calibration",
            "无效输入":"Invalid input","校验失败":"Validation failed","校准完成":"Calibration complete",
            "候选端口：":"Candidate port: ","当前槽位：":"Current slot: ","生效记录：":"Active record: ",
            "实际采用：":"In use: ","只添加机型标识":"Adds a model identifier only"
        ],
        "zh-Hant": [
            "模型校准":"機型校準","布局槽位":"版面槽位","添加主机模型":"新增主機機型",
            "编辑自定义布局":"編輯自訂版面","按槽位校准":"依槽位校準","全部槽位已完成":"所有槽位已完成",
            "确认映射":"確認映射","检测变化":"偵測變化","采基线":"採基準","移除":"移除",
            "添加槽位":"新增槽位","保存端口校准":"儲存連接埠校準","无效输入":"無效輸入",
            "校验失败":"驗證失敗","校准完成":"校準完成"
        ],
        "ja": [
            "模型校准":"モデル校正","布局槽位":"レイアウトスロット","添加主机模型":"ホストモデルを追加",
            "编辑自定义布局":"カスタムレイアウトを編集","按槽位校准":"スロットごとに校正",
            "全部槽位已完成":"すべてのスロット完了","确认映射":"マッピングを確認","检测变化":"変化を検出",
            "采基线":"ベースライン取得","移除":"削除","添加槽位":"スロットを追加",
            "保存端口校准":"ポート校正を保存","无效输入":"無効な入力","校验失败":"検証失敗",
            "校准完成":"校正完了"
        ],
        "ko": [
            "模型校准":"모델 보정","布局槽位":"레이아웃 슬롯","添加主机模型":"호스트 모델 추가",
            "编辑自定义布局":"사용자 레이아웃 편집","按槽位校准":"슬롯별 보정",
            "全部槽位已完成":"모든 슬롯 완료","确认映射":"매핑 확인","检测变化":"변화 감지",
            "采基线":"기준선 캡처","移除":"제거","添加槽位":"슬롯 추가",
            "保存端口校准":"포트 보정 저장","无效输入":"잘못된 입력","校验失败":"검증 실패",
            "校准完成":"보정 완료"
        ]
    ]

    private static let moduleB: [String: [String: String]] = [
        "en": [
            "未检测": "Not checked", "未安装": "Not installed", "未配置": "Not configured",
            "重新检测": "Check Again", "安装 Helper": "Install Helper", "修复 Helper": "Repair Helper",
            "升级 Helper": "Upgrade Helper", "卸载 Helper…": "Uninstall Helper…",
            "其他管理…": "Other Management…", "运行中": "Running", "已停止": "Stopped",
            "管理命令已完成。": "Management command completed.",
            "已有管理操作进行中。": "A management operation is already running.",
            "当前状态不提供该管理动作。": "This action is not available in the current state.",
            "这些检查只用于展示和管理入口，不会作为发送 DFU / 重启的新门槛。基线已有的 Helper 连接方式保持不变。": "These checks are for display and management only; they are not a new gate for DFU or restart."
        ],
        "zh-Hant": [
            "未检测": "未檢測", "未安裝": "未安裝", "未配置": "未設定",
            "重新检测": "重新檢測", "安装 Helper": "安裝 Helper", "修复 Helper": "修復 Helper",
            "升级 Helper": "升級 Helper", "卸载 Helper…": "解除安裝 Helper…",
            "其他管理…": "其他管理…", "运行中": "執行中", "已停止": "已停止",
            "管理命令已完成。": "管理命令已完成。",
            "已有管理操作进行中。": "已有管理操作進行中。",
            "当前状态不提供该管理动作。": "目前狀態不提供該管理動作。",
            "这些检查只用于展示和管理入口，不会作为发送 DFU / 重启的新门槛。基线已有的 Helper 连接方式保持不变。": "這些檢查僅用於顯示與管理入口，不會成為傳送 DFU / 重新啟動的新門檻。"
        ],
        "ja": [
            "未检测": "未確認", "未安装": "未インストール", "未配置": "未設定",
            "重新检测": "再確認", "安装 Helper": "Helper をインストール", "修复 Helper": "Helper を修復",
            "升级 Helper": "Helper をアップグレード", "卸载 Helper…": "Helper をアンインストール…",
            "其他管理…": "その他の管理…", "运行中": "実行中", "已停止": "停止",
            "管理命令已完成。": "管理コマンドが完了しました。",
            "已有管理操作进行中。": "別の管理操作を実行中です。",
            "当前状态不提供该管理动作。": "現在の状態ではこの操作を実行できません。",
            "这些检查只用于展示和管理入口，不会作为发送 DFU / 重启的新门槛。基线已有的 Helper 连接方式保持不变。": "この確認は表示と管理のみに使用され、DFU / 再起動の新しい条件にはなりません。"
        ],
        "ko": [
            "未检测": "확인 안 됨", "未安装": "설치 안 됨", "未配置": "구성 안 됨",
            "重新检测": "다시 확인", "安装 Helper": "Helper 설치", "修复 Helper": "Helper 복구",
            "升级 Helper": "Helper 업그레이드", "卸载 Helper…": "Helper 제거…",
            "其他管理…": "기타 관리…", "运行中": "실행 중", "已停止": "중지됨",
            "管理命令已完成。": "관리 명령이 완료되었습니다.",
            "已有管理操作进行中。": "이미 관리 작업이 진행 중입니다.",
            "当前状态不提供该管理动作。": "현재 상태에서는 이 작업을 사용할 수 없습니다.",
            "这些检查只用于展示和管理入口，不会作为发送 DFU / 重启的新门槛。基线已有的 Helper 连接方式保持不变。": "이 검사는 표시와 관리용이며 DFU/재시작의 새로운 조건이 아닙니다."
        ]
    ]

    private static let moduleA: [String: [String: String]] = [
        "en": [
            "最近连接变化": "Recent connection changes",
            "本次打开后暂无连接变化": "No connection changes since launch",
            "连接路径": "Connection path",
            "端口控制器": "Port controller", "控制器端口": "Controller port",
            "当前链路": "Current link", "当前协议": "Current protocol",
            "线材与能力": "Cable & capability", "线材标识": "Cable identity",
            "线材/端口能力": "Cable/port capability", "USB 超速活动": "USB SuperSpeed active",
            "已连接": "Connected", "无设备": "No device", "未识别设备": "Unidentified device",
            "重连耗时：": "Reconnect time: ", "收起": "Collapse", "展开": "Expand",
            "当前没有额外的连接路径信息": "No additional connection path details",
            "当前未识别到设备，没有可展示的连接路径": "No device identified; no connection path to show",
            "操作目标：": "Operation target: ", "端口详情": "Port details",
            "设备身份暂未读取": "Device identity not read yet",
            "端口控制器已确认连接；USB/Configurator 目标身份暂未读取": "Port controller connected; USB/Configurator target identity not read",
            "已配置传输，观察": "transports provisioned (observed)",
            "（已配置传输，观察）": " (transports provisioned, observed)"
        ],
        "zh-Hant": [
            "最近连接变化": "最近連接變化", "本次打开后暂无连接变化": "本次開啟後暫無連接變化",
            "连接路径": "連接路徑", "端口控制器": "連接埠控制器", "控制器端口": "控制器連接埠",
            "当前链路": "目前鏈路", "当前协议": "目前協議", "线材与能力": "線材與能力",
            "线材标识": "線材標識", "线材/端口能力": "線材/連接埠能力", "USB 超速活动": "USB 超速活動",
            "已连接": "已連接", "无设备": "無裝置", "未识别设备": "未識別裝置",
            "重连耗时：": "重連耗時：", "收起": "收合", "展开": "展開",
            "操作目标：": "操作目標：", "端口详情": "連接埠詳情",
            "设备身份暂未读取": "裝置身分尚未讀取",
            "端口控制器已确认连接；USB/Configurator 目标身份暂未读取": "連接埠控制器已確認連接；USB/Configurator 目標身分尚未讀取"
        ],
        "ja": [
            "最近连接变化": "最近の接続変化", "本次打开后暂无连接变化": "起動後の接続変化はありません",
            "连接路径": "接続経路", "端口控制器": "ポートコントローラ", "控制器端口": "コントローラポート",
            "当前链路": "現在のリンク", "当前协议": "現在のプロトコル", "线材与能力": "ケーブルと機能",
            "线材标识": "ケーブル識別", "线材/端口能力": "ケーブル/ポート機能", "USB 超速活动": "USB SuperSpeed 動作",
            "已连接": "接続済み", "无设备": "デバイスなし", "未识别设备": "未認識デバイス",
            "重连耗时：": "再接続時間：", "收起": "折りたたむ", "展开": "展開",
            "操作目标：": "操作対象：", "端口详情": "ポート詳細",
            "设备身份暂未读取": "デバイス情報は未取得です",
            "端口控制器已确认连接；USB/Configurator 目标身份暂未读取": "ポートコントローラは接続済み。USB/Configurator のターゲット情報は未取得です"
        ],
        "ko": [
            "最近连接变化": "최근 연결 변화", "本次打开后暂无连接变化": "앱 실행 후 연결 변화 없음",
            "连接路径": "연결 경로", "端口控制器": "포트 컨트롤러", "控制器端口": "컨트롤러 포트",
            "当前链路": "현재 링크", "当前协议": "현재 프로토콜", "线材与能力": "케이블 및 기능",
            "线材标识": "케이블 식별", "线材/端口能力": "케이블/포트 기능", "USB 超速活动": "USB SuperSpeed 동작",
            "已连接": "연결됨", "无设备": "기기 없음", "未识别设备": "인식되지 않은 기기",
            "重连耗时：": "재연결 시간: ", "收起": "접기", "展开": "펼치기",
            "操作目标：": "작업 대상: ", "端口详情": "포트 세부 정보",
            "设备身份暂未读取": "기기 정보를 아직 읽지 못했습니다",
            "端口控制器已确认连接；USB/Configurator 目标身份暂未读取": "포트 컨트롤러는 연결됨. USB/Configurator 대상 정보는 아직 없음"
        ]
    ]

    static func yesNo(_ value: Bool) -> String {
        switch code() {
        case "zh-Hant": return value ? "是" : "否"
        case "ja": return value ? "はい" : "いいえ"
        case "ko": return value ? "예" : "아니요"
        case "en": return value ? "Yes" : "No"
        default: return value ? "是" : "否"
        }
    }

    static func readyPortDetail(_ port: String) -> String {
        switch code() {
        case "zh-Hant": return "已選擇 \(port)，可執行裝置控制。"
        case "en": return "Selected \(port); device control is available."
        case "ja": return "\(port) を選択済み。デバイス操作を実行できます。"
        case "ko": return "\(port) 선택됨. 기기 제어를 실행할 수 있습니다."
        default: return "已选择 \(port)，可执行设备控制。"
        }
    }

    static func hostModelSummary(host: String, layout: String) -> String {
        let localLayout: String
        switch code() {
        case "en": localLayout = layout.replacingOccurrences(of: "英寸", with: "-inch")
        case "zh-Hant": localLayout = layout.replacingOccurrences(of: "英寸", with: " 吋")
        case "ja": localLayout = layout.replacingOccurrences(of: "英寸", with: "インチ")
        case "ko": localLayout = layout.replacingOccurrences(of: "英寸", with: "형")
        default: localLayout = layout
        }
        switch code() {
        case "zh-Hant": return "主機 \(host) · 內建 \(localLayout)"
        case "en": return "Host \(host) · Built-in \(localLayout)"
        case "ja": return "ホスト \(host) · 内蔵 \(localLayout)"
        case "ko": return "호스트 \(host) · 내장 \(localLayout)"
        default: return "主机 \(host) · 内置 \(localLayout)"
        }
    }


    static func helperMacOSVersion(_ raw: String) -> String {
        switch code() {
        case "en":
            return raw.replacingOccurrences(of: "版本 ", with: "Version ")
                .replacingOccurrences(of: "（版号 ", with: " (Build ")
                .replacingOccurrences(of: "）", with: ")")
        case "zh-Hant": return raw.replacingOccurrences(of: "版号", with: "版號")
        case "ja": return raw.replacingOccurrences(of: "版本 ", with: "バージョン ")
        case "ko": return raw.replacingOccurrences(of: "版本 ", with: "버전 ")
                .replacingOccurrences(of: "版号", with: "빌드")
        default: return raw
        }
    }

    static func helperCompatibility(minOS: String) -> String {
        switch code() {
        case "en": return "App declares minOS \(minOS). Actual compatibility depends on whether macOS can load the component; this field shows declared compatibility information only."
        case "zh-Hant": return "App 宣告 minOS \(minOS)；實際相容性取決於 macOS 能否載入元件，此欄僅顯示宣告資訊。"
        case "ja": return "App の宣言 minOS \(minOS)。実際の互換性は macOS がコンポーネントを読み込めるかで決まり、この欄は宣言情報のみを表示します。"
        case "ko": return "App 선언 minOS \(minOS). 실제 호환성은 macOS가 구성 요소를 로드할 수 있는지에 따라 결정되며, 이 필드는 선언 정보만 표시합니다."
        default: return "App 声明 minOS \(minOS)；实际兼容性取决于 macOS 能否加载组件，此处仅展示声明信息。"
        }
    }


    static func logPreviewCaption() -> String {
        switch code() {
        case "en": return "Preview only · Used for one-Mac restore logs · Saved logs always remain complete raw logs"
        case "zh-Hant": return "僅影響預覽 · 單機刷機時使用 · 儲存始終為完整原始日誌"
        case "ja": return "プレビューのみ · 単一 Mac の復元ログで使用 · 保存ログは常に完全な生ログです"
        case "ko": return "미리보기 전용 · 단일 Mac 복원 로그에 사용 · 저장 로그는 항상 전체 원본 로그입니다"
        default: return "仅影响预览 · 单机刷机时使用 · 保存始终为完整原始日志"
        }
    }

    static func builtInStatus(host: String, layout rawLayout: String, partial: Bool, skipped: String) -> String {
        let layout: String
        switch code() {
        case "zh-Hant": layout = rawLayout.replacingOccurrences(of: "英寸", with: " 吋")
        case "ja": layout = rawLayout.replacingOccurrences(of: "英寸", with: "インチ")
        case "ko": layout = rawLayout.replacingOccurrences(of: "英寸", with: "인치")
        default: layout = rawLayout
        }
        let suffix: String
        if partial {
            switch code() {
            case "en": suffix = " (partial calibration; skipped \(skipped))"
            case "zh-Hant": suffix = "（部分校準；跳過 \(skipped)）"
            case "ja": suffix = "（部分校正、\(skipped) をスキップ）"
            case "ko": suffix = " (부분 보정, \(skipped) 건너뜀)"
            default: suffix = "（部分校准；跳过 \(skipped)）"
            }
        } else { suffix = "" }
        switch code() {
        case "en": return "Host \(host) · Built-in \(layout)\(suffix)"
        case "zh-Hant": return "主機 \(host) · 內建 \(layout)\(suffix)"
        case "ja": return "ホスト \(host) · 内蔵 \(layout)\(suffix)"
        case "ko": return "호스트 \(host) · 내장 \(layout)\(suffix)"
        default: return "主机 \(host) · 内置 \(layout)\(suffix)"
        }
    }

    static func hostCalibrationStatus(_ kind: String, host: String) -> String {
        switch (code(), kind) {
        case ("en", "exact"): return "Host \(host) · Model precisely calibrated"
        case ("en", "shared"): return "Host \(host) · Shared layout (confirmed)"
        case ("en", "reuse"): return "Host \(host) · Not precisely calibrated (same-mold layout)"
        case ("en", "unidentified"): return "Host model unidentified · Not calibrated"
        case ("en", "uncalibrated"): return "Host \(host) · Not calibrated"
        case ("zh-Hans", "exact"): return "主机 \(host) · 机型已精确校准"
        case ("zh-Hans", "shared"): return "主机 \(host) · 同模具共享布局（已确认）"
        case ("zh-Hans", "reuse"): return "主机 \(host) · 未精确校准（沿用同模具布局）"
        case ("zh-Hans", "unidentified"): return "主机机型未识别 · 未校准"
        case ("zh-Hans", "uncalibrated"): return "主机 \(host) · 未校准"
        case ("zh-Hant", "exact"): return "主機 \(host) · 機型已精確校準"
        case ("zh-Hant", "shared"): return "主機 \(host) · 同模具共享佈局（已確認）"
        case ("zh-Hant", "reuse"): return "主機 \(host) · 未精確校準（沿用同模具佈局）"
        case ("zh-Hant", "unidentified"): return "主機機型未識別 · 未校準"
        case ("zh-Hant", "uncalibrated"): return "主機 \(host) · 未校準"
        case ("ja", "exact"): return "ホスト \(host) · 機種は正確に校正済み"
        case ("ja", "shared"): return "ホスト \(host) · 同一金型の共有レイアウト（確認済み）"
        case ("ja", "reuse"): return "ホスト \(host) · 正確な校正なし（同一金型レイアウトを使用）"
        case ("ja", "unidentified"): return "ホスト機種未識別 · 未校正"
        case ("ja", "uncalibrated"): return "ホスト \(host) · 未校正"
        case ("ko", "exact"): return "호스트 \(host) · 기종 정밀 보정 완료"
        case ("ko", "shared"): return "호스트 \(host) · 동일 금형 공유 레이아웃(확인됨)"
        case ("ko", "reuse"): return "호스트 \(host) · 정밀 보정 안 됨(동일 금형 레이아웃 사용)"
        case ("ko", "unidentified"): return "호스트 기종 미확인 · 보정 안 됨"
        case ("ko", "uncalibrated"): return "호스트 \(host) · 보정 안 됨"
        default: return "主机 \(host) · 未校准"
        }
    }


    static func faceLabel(_ face: String) -> String {
        switch (code(), face) {
        case ("en", "LEFT"): return "Left"
        case ("en", "RIGHT"): return "Right"
        case ("en", "FRONT"): return "Front"
        case ("en", "REAR"): return "Rear"
        case ("zh-Hant", "LEFT"): return "左側"
        case ("zh-Hant", "RIGHT"): return "右側"
        case ("zh-Hant", "FRONT"): return "正面"
        case ("zh-Hant", "REAR"): return "背面"
        case ("ja", "LEFT"): return "左"
        case ("ja", "RIGHT"): return "右"
        case ("ja", "FRONT"): return "前面"
        case ("ja", "REAR"): return "背面"
        case ("ko", "LEFT"): return "왼쪽"
        case ("ko", "RIGHT"): return "오른쪽"
        case ("ko", "FRONT"): return "앞면"
        case ("ko", "REAR"): return "뒷면"
        case (_, "LEFT"): return "左侧"
        case (_, "RIGHT"): return "右侧"
        case (_, "FRONT"): return "正面"
        case (_, "REAR"): return "背面"
        default: return face
        }
    }


    static func legacyRIDNote(_ count: Int) -> String {
        switch code() {
        case "en": return "Detected \(count) legacy RID-only custom entries; built-in slots take precedence and old rows are not deleted. Recalibrate by controller/PortNumber if they conflict."
        case "zh-Hant": return "偵測到 \(count) 筆舊式 RID-only 自訂資料；內建槽位優先，舊資料未刪除；如有衝突可依 controller/PortNumber 重新校準。"
        case "ja": return "\(count) 件の旧式 RID-only カスタム行を検出しました。内蔵スロットを優先し、旧行は削除していません。競合する場合は controller/PortNumber で再校正してください。"
        case "ko": return "레거시 RID-only 사용자 항목 \(count)개를 발견했습니다. 내장 슬롯을 우선하며 이전 행은 삭제하지 않았습니다. 충돌 시 controller/PortNumber로 다시 보정하세요."
        default: return "检测到旧式 RID-only 自定义行 \(count) 条；内置槽位优先，旧行未删除；如冲突可按 controller/PortNumber 重新校准。"
        }
    }

    static func unmatchedPortsNote(_ rids: String) -> String {
        switch code() {
        case "en": return "Unmatched ports are listed in details only: \(rids); not selected by default."
        case "zh-Hant": return "未匹配連接埠只列在詳情：\(rids)；不預設選取。"
        case "ja": return "未一致ポートは詳細にのみ表示されます：\(rids)。既定では選択されません。"
        case "ko": return "일치하지 않는 포트는 세부 정보에만 표시됩니다: \(rids). 기본적으로 선택되지 않습니다."
        default: return "未匹配端口只列在详情：\(rids)；不默认选中。"
        }
    }


    static func installAlertTitle() -> String {
        switch code() {
        case "zh-Hant": return "需要安裝 Helper"
        case "en": return "Install Helper Required"
        case "ja": return "Helper のインストールが必要"
        case "ko": return "Helper 설치 필요"
        default: return "需要安装 Helper"
        }
    }
    static func installAlertMessage() -> String {
        switch code() {
        case "zh-Hant": return "安裝 Helper 需要 macOS 管理員授權。按一下「授權安裝」，然後在系統授權視窗中輸入密碼即可；只需按一次。"
        case "en": return "Installing the Helper requires macOS administrator authorization. Click “Authorize Install” once, then enter your password in the system authorization dialog."
        case "ja": return "Helper のインストールには macOS の管理者認証が必要です。「インストールを承認」を一度だけクリックし、システムの認証ダイアログでパスワードを入力してください。"
        case "ko": return "Helper를 설치하려면 macOS 관리자 인증이 필요합니다. ‘설치 승인’을 한 번만 클릭한 다음 시스템 인증 창에 암호를 입력하세요."
        default: return "安装 Helper 需要 macOS 管理员授权。点击“授权安装”后，在系统授权窗口输入密码即可；只需点击一次。"
        }
    }
    static func installAlertButton() -> String {
        switch code() {
        case "zh-Hant": return "授權安裝"
        case "en": return "Authorize Install"
        case "ja": return "インストールを承認"
        case "ko": return "설치 승인"
        default: return "授权安装"
        }
    }


    static func wizardCurrentSlot(face: String, slotID: String) -> String {
        switch code() {
        case "en": return "Current slot: \(slotID) (\(faceLabel(face)))"
        case "zh-Hant": return "目前槽位：\(slotID)（\(faceLabel(face))）"
        case "ja": return "現在のスロット：\(slotID)（\(faceLabel(face))）"
        case "ko": return "현재 슬롯: \(slotID)(\(faceLabel(face)))"
        default: return "当前槽位：\(slotID)（\(faceLabel(face))）"
        }
    }


    static func portRowTitle(label: String, status: String) -> String {
        let knownLabels: [String: String]
        switch code() {
        case "en": knownLabels = ["左侧上方": "Upper Left", "左侧下方": "Lower Left", "右侧": "Right", "左侧": "Left"]
        case "zh-Hant": knownLabels = ["左侧上方": "左側上方", "左侧下方": "左側下方", "右侧": "右側", "左侧": "左側"]
        case "ja": knownLabels = ["左侧上方": "左上", "左侧下方": "左下", "右侧": "右側", "左侧": "左"]
        case "ko": knownLabels = ["左侧上方": "왼쪽 위", "左侧下方": "왼쪽 아래", "右侧": "오른쪽", "左侧": "왼쪽"]
        default: return "\(label) · \(status)"
        }
        let localizedLabel = knownLabels[label] ?? label
        let localizedStatus: String
        switch (code(), status) {
        case ("en", "已连接"): localizedStatus = "Connected"
        case ("en", "未识别设备"): localizedStatus = "Unidentified device"
        case ("zh-Hant", "已连接"): localizedStatus = "已連接"
        case ("zh-Hant", "未识别设备"): localizedStatus = "未識別裝置"
        case ("ja", "已连接"): localizedStatus = "接続済み"
        case ("ja", "未识别设备"): localizedStatus = "未認識デバイス"
        case ("ko", "已连接"): localizedStatus = "연결됨"
        case ("ko", "未识别设备"): localizedStatus = "인식되지 않은 기기"
        default: localizedStatus = status
        }
        return "\(localizedLabel) · \(localizedStatus)"
    }


    static func localizedPortName(_ name: String) -> String {
        let map: [String: String]
        switch code() {
        case "en": map = ["左侧上方":"Upper Left","左侧下方":"Lower Left","右侧":"Right","左侧":"Left"]
        case "zh-Hant": map = ["左侧上方":"左側上方","左侧下方":"左側下方","右侧":"右側","左侧":"左側"]
        case "ja": map = ["左侧上方":"左上","左侧下方":"左下","右侧":"右側","左侧":"左"]
        case "ko": map = ["左侧上方":"왼쪽 위","左侧下方":"왼쪽 아래","右侧":"오른쪽","左侧":"왼쪽"]
        default: return name
        }
        return map[name] ?? name
    }


    static func duration(seconds total: Int) -> String {
        let t = max(0, total)
        let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        switch code() {
        case "en":
            if h > 0 { return "\(h)h " + String(format: "%02dm %02ds", m, sec) }
            if m > 0 { return "\(m)m " + String(format: "%02ds", sec) }
            return "\(sec)s"
        case "zh-Hant":
            if h > 0 { return "\(h)小時" + String(format: "%02d分%02d秒", m, sec) }
            if m > 0 { return "\(m)分" + String(format: "%02d秒", sec) }
            return "\(sec)秒"
        case "ja":
            if h > 0 { return "\(h)時間" + String(format: "%02d分%02d秒", m, sec) }
            if m > 0 { return "\(m)分" + String(format: "%02d秒", sec) }
            return "\(sec)秒"
        case "ko":
            if h > 0 { return "\(h)시간 " + String(format: "%02d분 %02d초", m, sec) }
            if m > 0 { return "\(m)분 " + String(format: "%02d초", sec) }
            return "\(sec)초"
        default:
            if h > 0 { return "\(h)小时" + String(format: "%02d分%02d秒", m, sec) }
            if m > 0 { return "\(m)分" + String(format: "%02d秒", sec) }
            return "\(sec)秒"
        }
    }


    static func portLocation(side: String, location: String) -> String {
        let knownSide: String?
        switch (code(), side) {
        case ("en", "左侧"): knownSide = "Left"
        case ("en", "右侧"): knownSide = "Right"
        case ("en", "正面"): knownSide = "Front"
        case ("en", "背面"): knownSide = "Rear"
        case ("zh-Hant", "左侧"): knownSide = "左側"
        case ("zh-Hant", "右侧"): knownSide = "右側"
        case ("zh-Hant", "正面"): knownSide = "正面"
        case ("zh-Hant", "背面"): knownSide = "背面"
        case ("ja", "左侧"): knownSide = "左"
        case ("ja", "右侧"): knownSide = "右"
        case ("ja", "正面"): knownSide = "前面"
        case ("ja", "背面"): knownSide = "背面"
        case ("ko", "左侧"): knownSide = "왼쪽"
        case ("ko", "右侧"): knownSide = "오른쪽"
        case ("ko", "正面"): knownSide = "앞면"
        case ("ko", "背面"): knownSide = "뒷면"
        case ("zh-Hans", "左侧"): knownSide = "左侧"
        case ("zh-Hans", "右侧"): knownSide = "右侧"
        case ("zh-Hans", "正面"): knownSide = "正面"
        case ("zh-Hans", "背面"): knownSide = "背面"
        default: knownSide = nil
        }
        let prefix: String
        switch code() {
        case "en": prefix = "Location"
        case "zh-Hant": prefix = "位置"
        case "ja": prefix = "位置"
        case "ko": prefix = "위치"
        default: prefix = "位置"
        }
        guard let knownSide, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let unknown: String
            switch code() {
            case "en": unknown = "Unknown"
            case "zh-Hant": unknown = "未知"
            case "ja": unknown = "不明"
            case "ko": unknown = "알 수 없음"
            default: unknown = "未知"
            }
            return "\(prefix): \(unknown)"
        }
        return "\(prefix): \(knownSide) · \(location)"
    }


    static func connectionSummary(location: String) -> String {
        switch code() {
        case "en": return "Current connection: USB location \(location)"
        case "zh-Hant": return "目前連接：USB location \(location)"
        case "ja": return "現在の接続：USB location \(location)"
        case "ko": return "현재 연결: USB location \(location)"
        default: return "当前连接：USB location \(location)"
        }
    }
    static func customCalibrationSummary(label: String, physicalPort: String) -> String {
        switch code() {
        case "en": return "Custom calibration: \(label) · \(physicalPort)"
        case "zh-Hant": return "自訂校準：\(label) · \(physicalPort)"
        case "ja": return "カスタム校正：\(label) · \(physicalPort)"
        case "ko": return "사용자 보정: \(label) · \(physicalPort)"
        default: return "自定义校准：\(label) · \(physicalPort)"
        }
    }

}

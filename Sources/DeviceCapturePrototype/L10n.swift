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
        // UI-1：左栏遥测与状态药丸新增的少量文案（四语齐备）。
        let ui1Copy: [String: [String: String]] = [
            "未获取": [
                "zh-Hant": "未取得",
                "en": "Not available",
                "ja": "未取得",
                "ko": "가져오지 못함",
            ],
            "正常": [
                "zh-Hant": "狀態正常",
                "en": "Normal",
                "ja": "正常稼働",
                "ko": "정상",
            ],
            "端口遥测": [
                "zh-Hant": "連接埠遙測",
                "en": "Port telemetry",
                "ja": "ポートテレメトリ",
                "ko": "포트 텔레메트리",
            ],
            "只读": [
                "zh-Hant": "唯讀",
                "en": "Read-only",
                "ja": "読み取り専用",
                "ko": "읽기 전용",
            ],
        ]
        if let localized = ui1Copy[source]?[code] { return localized }
        // UI-2：统一 A/B Restore 准备态的少量新增文案（四语齐备）。
        let ui2Copy: [String: [String: String]] = [
            "当前生效固件": [
                "zh-Hant": "目前生效韌體",
                "en": "Effective firmware",
                "ja": "現在有効なファームウェア",
                "ko": "현재 적용 펌웨어",
            ],
            "手动选择 IPSW…": [
                "zh-Hant": "手動選擇 IPSW…",
                "en": "Choose IPSW…",
                "ja": "IPSW を選択…",
                "ko": "IPSW 선택…",
            ],
            "搜索 IPSW…": [
                "zh-Hant": "搜尋 IPSW…",
                "en": "Search IPSW…",
                "ja": "IPSW を検索…",
                "ko": "IPSW 검색…",
            ],
            "IPSW 文件": [
                "zh-Hant": "IPSW 檔案",
                "en": "IPSW file",
                "ja": "IPSW ファイル",
                "ko": "IPSW 파일",
            ],
            "版本 / Build": [
                "zh-Hant": "版本／Build",
                "en": "Version / Build",
                "ja": "バージョン / Build",
                "ko": "버전 / Build",
            ],
            "兼容性": [
                "zh-Hant": "相容性",
                "en": "Compatibility",
                "ja": "互換性",
                "ko": "호환성",
            ],
            "来源": [
                "zh-Hant": "來源",
                "en": "Source",
                "ja": "ソース",
                "ko": "출처",
            ],
            "手动选择": [
                "zh-Hant": "手動選擇",
                "en": "Manual",
                "ja": "手動選択",
                "ko": "수동 선택",
            ],
            "机型默认": [
                "zh-Hant": "機型預設",
                "en": "Model default",
                "ja": "機種の既定",
                "ko": "모델 기본값",
            ],
            "全局默认": [
                "zh-Hant": "全域預設",
                "en": "Global default",
                "ja": "グローバル既定",
                "ko": "전역 기본값",
            ],
            "上次选择": [
                "zh-Hant": "上次選擇",
                "en": "Last selected",
                "ja": "前回の選択",
                "ko": "마지막 선택",
            ],
            "开始 Restore…": [
                "zh-Hant": "開始 Restore…",
                "en": "Start Restore…",
                "ja": "Restore を開始…",
                "ko": "Restore 시작…",
            ],
            "当前无法开始 Restore": [
                "zh-Hant": "目前無法開始 Restore",
                "en": "Cannot start Restore now",
                "ja": "現在 Restore を開始できません",
                "ko": "현재 Restore를 시작할 수 없음",
            ],
            "默认固件不可用": [
                "zh-Hant": "預設韌體無法使用",
                "en": "Default firmware unavailable",
                "ja": "既定のファームウェアを利用できません",
                "ko": "기본 펌웨어를 사용할 수 없음",
            ],
            "请重新选择 IPSW，或恢复自动推荐。": [
                "zh-Hant": "請重新選擇 IPSW，或恢復自動推薦。",
                "en": "Choose another IPSW or restore the automatic recommendation.",
                "ja": "別の IPSW を選択するか、自動推奨に戻してください。",
                "ko": "다른 IPSW를 선택하거나 자동 추천으로 복원하세요.",
            ],
            "已有两个 Restore 任务在执行。": [
                "zh-Hant": "已有兩個 Restore 任務在執行。",
                "en": "Two Restore tasks are already running.",
                "ja": "2 つの Restore タスクが実行中です。",
                "ko": "두 Restore 작업이 이미 실행 중입니다.",
            ],
            "兼容": [
                "zh-Hant": "相容",
                "en": "Compatible",
                "ja": "互換",
                "ko": "호환",
            ],
            "不兼容": [
                "zh-Hant": "不相容",
                "en": "Incompatible",
                "ja": "非互換",
                "ko": "비호환",
            ],
            "未验证": [
                "zh-Hant": "未驗證",
                "en": "Unverified",
                "ja": "未検証",
                "ko": "미검증",
            ],
            "有效": [
                "zh-Hant": "有效狀態",
                "en": "Valid",
                "ja": "有効",
                "ko": "유효",
            ],
            "无效": [
                "zh-Hant": "無效",
                "en": "Invalid",
                "ja": "無効",
                "ko": "무효",
            ],
            "固件库为空。": [
                "zh-Hant": "韌體庫為空。",
                "en": "The firmware library is empty.",
                "ja": "ファームウェアライブラリは空です。",
                "ko": "펌웨어 라이브러리가 비어 있습니다.",
            ],
            "Restore 会抹除目标 Mac 上的数据。本工具不会自动开始，也不会检测到设备后自动刷机。": [
                "zh-Hant": "Restore 會抹除目標 Mac 上的資料。本工具不會自動開始，也不會偵測到裝置後自動刷機。",
                "en": "Restore erases data on the target Mac. This tool never starts automatically and never flashes a device when one is detected.",
                "ja": "Restore は対象 Mac のデータを消去します。本ツールは自動開始せず、デバイス検出時に自動で書き込みません。",
                "ko": "Restore는 대상 Mac의 데이터를 지웁니다. 이 도구는 자동으로 시작하지 않으며 기기를 감지해도 자동으로 플래시하지 않습니다.",
            ],
            "没有匹配的 IPSW。": [
                "zh-Hant": "沒有符合的 IPSW。",
                "en": "No matching IPSW.",
                "ja": "一致する IPSW はありません。",
                "ko": "일치하는 IPSW가 없습니다.",
            ],
        ]
        if let localized = ui2Copy[source]?[code] { return localized }

        let ui3Copy: [String: [String: String]] = [
            "实时日志预览": [
                "zh-Hant": "即時日誌預覽",
                "en": "Live log preview",
                "ja": "リアルタイムログプレビュー",
                "ko": "실시간 로그 미리보기",
            ],
            "cfgutil 内存尾部 · 非完整原始日志": [
                "zh-Hant": "cfgutil 記憶體尾部 · 非完整原始日誌",
                "en": "cfgutil memory tail · not the full raw log",
                "ja": "cfgutil メモリ末尾 · 完全な生ログではありません",
                "ko": "cfgutil 메모리 꼬리 · 전체 원본 로그 아님",
            ],
            "回到底部": [
                "zh-Hant": "捲回底部",
                "en": "Back to bottom",
                "ja": "最下部へ",
                "ko": "맨 아래로",
            ],
            "复制当前预览": [
                "zh-Hant": "複製目前預覽",
                "en": "Copy current preview",
                "ja": "現在のプレビューをコピー",
                "ko": "현재 미리보기 복사",
            ],
            "已复制当前预览": [
                "zh-Hant": "已複製目前預覽",
                "en": "Copied current preview",
                "ja": "現在のプレビューをコピーしました",
                "ko": "현재 미리보기 복사됨",
            ],
            "仅展示有界内存尾部；完整原始日志请使用 Raw 保存/归档导出。": [
                "zh-Hant": "僅顯示有界記憶體尾部；完整原始日誌請使用 Raw 儲存/歸檔匯出。",
                "en": "Only a bounded memory tail is shown; use Raw save/archive export for the full raw log.",
                "ja": "表示するのは有界メモリ末尾のみです。完全な生ログは Raw 保存/アーカイブ書き出しを使用してください。",
                "ko": "제한된 메모리 꼬리만 표시합니다. 전체 원본 로그는 Raw 저장/아카이브 내보내기를 사용하세요.",
            ],
            "任务详情": [
                "zh-Hant": "任務詳情",
                "en": "Task details",
                "ja": "タスクの詳細",
                "ko": "작업 세부정보",
            ],
            "复制完整 attempt UUID": [
                "zh-Hant": "複製完整 attempt UUID",
                "en": "Copy full attempt UUID",
                "ja": "完全な attempt UUID をコピー",
                "ko": "전체 attempt UUID 복사",
            ],
            "主任务": [
                "zh-Hant": "主任務",
                "en": "Primary task",
                "ja": "メインタスク",
                "ko": "기본 작업",
            ],
            "第二任务": [
                "zh-Hant": "第二任務",
                "en": "Second task",
                "ja": "2 番目のタスク",
                "ko": "두 번째 작업",
            ],
            "正在取消": [
                "zh-Hant": "正在取消中",
                "en": "Canceling",
                "ja": "キャンセル中",
                "ko": "취소 중",
            ],
            "进行中": [
                "zh-Hant": "進行中",
                "en": "In progress",
                "ja": "進行中",
                "ko": "진행 중",
            ],
            "已执行": [
                "zh-Hant": "已執行",
                "en": "Elapsed",
                "ja": "経過",
                "ko": "경과",
            ],
            "强制结束…": [
                "zh-Hant": "強制結束…",
                "en": "Force stop…",
                "ja": "強制終了…",
                "ko": "강제 종료…",
            ],
            "打开原始日志目录": [
                "zh-Hant": "開啟原始日誌目錄",
                "en": "Open raw log folder",
                "ja": "生ログフォルダを開く",
                "ko": "원본 로그 폴더 열기",
            ],
            "正在取消：已发送中断信号，等待进程退出…": [
                "zh-Hant": "正在取消：已送出中斷訊號，等待程序結束…",
                "en": "Canceling: interrupt sent, waiting for the process to exit…",
                "ja": "キャンセル中：割り込みを送信し、プロセスの終了を待っています…",
                "ko": "취소 중: 인터럽트를 보냈으며 프로세스 종료를 기다리는 중…",
            ],
            "Restore 启动准备中；cfgutil 尚未确认运行。": [
                "zh-Hant": "Restore 啟動準備中；cfgutil 尚未確認執行。",
                "en": "Restore is preparing; cfgutil has not been confirmed running.",
                "ja": "Restore 起動準備中。cfgutil の実行はまだ確認されていません。",
                "ko": "Restore 시작 준비 중이며 cfgutil 실행은 아직 확인되지 않았습니다.",
            ],
            "Restore 正在执行；取消入口保持可见。": [
                "zh-Hant": "Restore 正在執行；取消入口保持可見。",
                "en": "Restore is running; the cancel control stays visible.",
                "ja": "Restore 実行中。キャンセル入口は常に表示されます。",
                "ko": "Restore 실행 중이며 취소 버튼은 계속 표시됩니다.",
            ],
            "执行耗时": [
                "zh-Hant": "執行耗時",
                "en": "Elapsed",
                "ja": "実行時間",
                "ko": "소요 시간",
            ],
            "失败阶段：": [
                "zh-Hant": "失敗階段：",
                "en": "Failure stage: ",
                "ja": "失敗段階：",
                "ko": "실패 단계: ",
            ],
            "未提供更多失败原因。": [
                "zh-Hant": "未提供更多失敗原因。",
                "en": "No further failure reason provided.",
                "ja": "追加の失敗理由はありません。",
                "ko": "추가 실패 사유가 없습니다.",
            ],
            "取消已确认；任务已结束。": [
                "zh-Hant": "取消已確認；任務已結束。",
                "en": "Cancellation confirmed; the task has ended.",
                "ja": "キャンセルを確認しました。タスクは終了しました。",
                "ko": "취소가 확인되었으며 작업이 종료되었습니다.",
            ],
            "底层未给出可判定的终态；请以原始日志与归档为准。": [
                "zh-Hant": "底層未提供可判定的終態；請以原始日誌與歸檔為準。",
                "en": "The backend gave no determinable terminal state; use the raw log and archive.",
                "ja": "基層から判定可能な終態が得られません。生ログとアーカイブを参照してください。",
                "ko": "백엔드가 판정 가능한 종료 상태를 제공하지 않았습니다. 원본 로그와 아카이브를 기준으로 하세요.",
            ],
            "任务已完成。": [
                "zh-Hant": "任務已完成。",
                "en": "Task completed.",
                "ja": "タスクは完了しました。",
                "ko": "작업이 완료되었습니다.",
            ],
            "本次未保存完整原始日志。": [
                "zh-Hant": "本次未儲存完整原始日誌。",
                "en": "The full raw log was not saved this run.",
                "ja": "今回、完全な生ログは保存されていません。",
                "ko": "이번 실행에서 전체 원본 로그를 저장하지 않았습니다.",
            ],
            "正在写入原始证据与历史记录，导出暂不可用。": [
                "zh-Hant": "正在寫入原始證據與歷史記錄，匯出暫不可用。",
                "en": "Writing raw evidence and history; export is not available yet.",
                "ja": "生エビデンスと履歴を書き込み中です。書き出しはまだ利用できません。",
                "ko": "원본 증거와 기록을 쓰는 중이며 내보내기는 아직 사용할 수 없습니다.",
            ],
            "返回准备": [
                "zh-Hant": "返回準備",
                "en": "Back to preparation",
                "ja": "準備に戻る",
                "ko": "준비로 돌아가기",
            ],
            "当前没有可展示的 Restore 任务。": [
                "zh-Hant": "目前沒有可顯示的 Restore 任務。",
                "en": "No Restore task is available to display.",
                "ja": "表示できる Restore タスクはありません。",
                "ko": "표시할 Restore 작업이 없습니다.",
            ],
            "取消 Restore…": [
                "zh-Hant": "中止 Restore…",
                "en": "Cancel Restore…",
                "ja": "Restore をキャンセル…",
                "ko": "Restore 취소…",
            ],
            "尚未启动": [
                "zh-Hant": "尚未啟動",
                "en": "Not started",
                "ja": "未開始",
                "ko": "시작되지 않음",
            ],
        ]
        if let localized = ui3Copy[source]?[code] { return localized }

        let ui31Copy: [String: [String: String]] = [
            "原始日志说明": [
                "zh-Hant": "原始日誌說明",
                "en": "Raw log help",
                "ja": "生ログの説明",
                "ko": "원본 로그 설명",
            ],
            "正在整理原始日志，稍后可导出。": [
                "zh-Hant": "正在整理原始日誌，稍後可匯出。",
                "en": "Preparing the raw log; export will be available shortly.",
                "ja": "生ログを整理中です。まもなく書き出せます。",
                "ko": "원본 로그를 정리 중이며 곧 내보낼 수 있습니다.",
            ],
            "任务已结束，请返回准备态确认后重新开始。": [
                "zh-Hant": "任務已結束，請返回準備態確認後重新開始。",
                "en": "The task has ended; return to preparation and confirm before restarting.",
                "ja": "タスクは終了しました。準備状態に戻って確認してから再開してください。",
                "ko": "작업이 종료되었습니다. 준비 상태로 돌아가 확인 후 다시 시작하세요.",
            ],
            "兼容性未验证，缺少：": [
                "zh-Hant": "相容性未驗證，缺少：",
                "en": "Compatibility unverified; missing: ",
                "ja": "互換性が未検証です。不足：",
                "ko": "호환성을 확인할 수 없습니다. 누락: ",
            ],
            "；不能开始 Restore。": [
                "zh-Hant": "；無法開始 Restore。",
                "en": "; cannot start Restore.",
                "ja": "。Restore を開始できません。",
                "ko": "; Restore를 시작할 수 없습니다.",
            ],
            "Restore 未能启动，请检查目标设备与固件兼容性。": [
                "zh-Hant": "Restore 無法啟動，請檢查目標裝置與韌體相容性。",
                "en": "Restore did not start. Check the target device and firmware compatibility.",
                "ja": "Restore を開始できませんでした。対象デバイスとファームウェアの互換性を確認してください。",
                "ko": "Restore가 시작되지 않았습니다. 대상 기기와 펌웨어 호환성을 확인하세요.",
            ],
            "目标已变化，未启动 Restore。": [
                "zh-Hant": "目標已變更，未啟動 Restore。",
                "en": "The target changed; Restore did not start.",
                "ja": "対象が変わったため Restore を開始しませんでした。",
                "ko": "대상이 변경되어 Restore를 시작하지 않았습니다.",
            ],
            "正在扫描本地 IPSW…": [
                "zh-Hant": "正在掃描本機 IPSW…",
                "en": "Scanning local IPSWs…",
                "ja": "ローカル IPSW をスキャン中…",
                "ko": "로컬 IPSW 스캔 중…",
            ],
            "清除失效默认": [
                "zh-Hant": "清除失效預設",
                "en": "Clear Invalid Default",
                "ja": "無効な既定を消去",
                "ko": "유효하지 않은 기본값 지우기",
            ],
            "尚未选择固件；请从下方固件库选择。": [
                "zh-Hant": "尚未選擇韌體；請從下方韌體庫選擇。",
                "en": "No firmware selected; choose from the firmware library below.",
                "ja": "ファームウェアが未選択です。下のファームウェアライブラリから選択してください。",
                "ko": "펌웨어가 선택되지 않았습니다. 아래 펌웨어 라이브러리에서 선택하세요.",
            ],
            "参考上次成功": ["zh-Hant": "參考上次成功", "en": "Last success", "ja": "前回の成功", "ko": "이전 성공"],
            "同 ECID 同固件": ["zh-Hant": "同 ECID 同韌體", "en": "Same ECID and firmware", "ja": "同じ ECID と同じファームウェア", "ko": "동일 ECID 및 펌웨어"],
            "同机型同固件": ["zh-Hant": "同機型同韌體", "en": "Same model and firmware", "ja": "同じモデルと同じファームウェア", "ko": "동일 모델 및 펌웨어"],
            "同机型最近成功": ["zh-Hant": "同機型最近成功", "en": "Same model, most recent success", "ja": "同じモデルの直近成功", "ko": "동일 모델 최근 성공"],
            "正在解压/校验固件，首次进度更新可能需要数分钟…": ["zh-Hant": "正在解壓縮/校驗韌體，首次進度更新可能需要數分鐘…", "en": "Extracting/verifying firmware; the first progress update may take several minutes…", "ja": "ファームウェアを展開/検証中です。最初の進捗更新まで数分かかる場合があります…", "ko": "펌웨어 압축 해제/검증 중입니다. 첫 진행 업데이트까지 몇 분 걸릴 수 있습니다…"],
            "全部": ["zh-Hant": "全部", "en": "All", "ja": "すべて", "ko": "전체"],
            "仅看报错": ["zh-Hant": "僅看錯誤", "en": "Errors Only", "ja": "エラーのみ", "ko": "오류만"],
            "查看全部": ["zh-Hant": "顯示全部", "en": "View All", "ja": "すべて表示", "ko": "전체 보기"],
            "命中报错": ["zh-Hant": "命中錯誤", "en": "error hits", "ja": "エラー一致", "ko": "오류 일치"],
            "内存预览 · 非完整原始日志": ["zh-Hant": "記憶體預覽 · 非完整原始日誌", "en": "Memory preview · not the complete raw log", "ja": "メモリプレビュー · 完全な生ログではありません", "ko": "메모리 미리보기 · 전체 원본 로그 아님"],
            "终端预览": ["zh-Hant": "終端預覽", "en": "Terminal Preview", "ja": "ターミナルプレビュー", "ko": "터미널 미리보기"],
            "线索：": ["zh-Hant": "線索：", "en": "Clues: ", "ja": "手がかり：", "ko": "단서: "],
            "仅基于日志原文关键词归类，不替代实测诊断": ["zh-Hant": "僅依日誌原文關鍵字歸類，不替代實測診斷", "en": "Keyword grouping from raw log text only; not a substitute for hardware diagnosis", "ja": "ログ原文のキーワード分類のみ。実機診断の代替ではありません", "ko": "로그 원문 키워드 분류만 수행하며 실제 진단을 대체하지 않습니다"],
            "在 Finder 中打开原始目录": ["zh-Hant": "在 Finder 中開啟原始目錄", "en": "Open Raw Folder in Finder", "ja": "Finder で生ログフォルダを開く", "ko": "Finder에서 원본 폴더 열기"],
            "采集说明": ["zh-Hant": "擷取說明", "en": "Capture help", "ja": "キャプチャの説明", "ko": "캡처 설명"],
            "原始日志目录不存在": ["zh-Hant": "原始日誌目錄不存在", "en": "Raw log folder does not exist", "ja": "生ログフォルダが存在しません", "ko": "원본 로그 폴더가 없습니다"],
            "设为本机型默认": ["zh-Hant": "設為本機型預設", "en": "Set as Model Default", "ja": "このモデルの既定に設定", "ko": "이 모델 기본값으로 설정"],
            "设为全局默认": ["zh-Hant": "設為全域預設", "en": "Set as Global Default", "ja": "グローバル既定に設定", "ko": "전역 기본값으로 설정"],
            "在 Finder 中显示": ["zh-Hant": "在 Finder 中顯示", "en": "Show in Finder", "ja": "Finder に表示", "ko": "Finder에서 보기"],
            "复制": ["zh-Hant": "複製", "en": "Copy", "ja": "コピー", "ko": "복사"],
            "复制十六进制": ["zh-Hant": "複製十六進位", "en": "Copy Hexadecimal", "ja": "16 進数をコピー", "ko": "16진수 복사"],
            "复制十进制": ["zh-Hant": "複製十進位", "en": "Copy Decimal", "ja": "10 進数をコピー", "ko": "10진수 복사"],
            "已复制": ["zh-Hant": "已複製", "en": "Copied", "ja": "コピーしました", "ko": "복사됨"],
            "复制失败摘要": ["zh-Hant": "複製失敗摘要", "en": "Copy Failure Summary", "ja": "失敗概要をコピー", "ko": "실패 요약 복사"],
            "Restore 完成提示音": ["zh-Hant": "Restore 完成音效", "en": "Restore completion sound", "ja": "Restore 完了サウンド", "ko": "Restore 완료 소리"],
            "近 1 分钟变化": ["zh-Hant": "近 1 分鐘變化", "en": "Changes in last minute", "ja": "直近 1 分の変化", "ko": "최근 1분 변화"],
            "近 1 分钟重连/掉线次数；≥3 次提示反复重启/掉盘可能": ["zh-Hant": "近 1 分鐘重新連線/斷線次數；≥3 次提示反覆重啟/掉盤可能", "en": "Reconnect/disconnect events in the last minute; ≥3 suggests repeated reboot/drop risk", "ja": "直近 1 分の再接続/切断回数。3 回以上は再起動/切断の可能性を示します", "ko": "최근 1분 재연결/연결 끊김 횟수. 3회 이상이면 반복 재부팅/드롭 가능성을 나타냅니다"],
            "归属冲突": ["zh-Hant": "歸屬衝突", "en": "Attribution conflict", "ja": "帰属の競合", "ko": "귀속 충돌"],
            "非 USB-C": ["zh-Hant": "非 USB-C", "en": "Not USB-C", "ja": "USB-C 以外", "ko": "USB-C 아님"],
            "异常 · 过流": ["zh-Hant": "異常 · 過流", "en": "Fault · overcurrent", "ja": "異常 · 過電流", "ko": "이상 · 과전류"],
            "扫描完成。": [
                "zh-Hant": "掃描完成。",
                "en": "Scan complete.",
                "ja": "スキャン完了。",
                "ko": "스캔 완료.",
            ],
            "添加目录…": [
                "zh-Hant": "加入目錄…",
                "en": "Add Folder…",
                "ja": "フォルダを追加…",
                "ko": "폴더 추가…",
            ],
            "重新扫描": [
                "zh-Hant": "重新掃描",
                "en": "Rescan",
                "ja": "再スキャン",
                "ko": "다시 스캔",
            ],
            "启动时自动扫描本机 IPSW": [
                "zh-Hant": "啟動時自動掃描本機 IPSW",
                "en": "Scan local IPSWs on launch",
                "ja": "起動時にローカル IPSW をスキャン",
                "ko": "실행 시 로컬 IPSW 스캔",
            ],
            "已添加的固件目录": [
                "zh-Hant": "已加入的韌體目錄",
                "en": "Added firmware folders",
                "ja": "追加済みファームウェアフォルダ",
                "ko": "추가된 펌웨어 폴더",
            ],
            "添加固件文件夹…": [
                "zh-Hant": "加入韌體檔案夾…",
                "en": "Add Firmware Folder…",
                "ja": "ファームウェアフォルダを追加…",
                "ko": "펌웨어 폴더 추가…",
            ],
            "固件扫描已取消。": [
                "zh-Hant": "韌體掃描已取消。",
                "en": "Firmware scan cancelled.",
                "ja": "ファームウェアのスキャンを中止しました。",
                "ko": "펌웨어 스캔을 취소했습니다.",
            ],
            "Restore 进行中，自动固件扫描已延后。": [
                "zh-Hant": "Restore 進行中，自動韌體掃描已延後。",
                "en": "Restore is running; automatic firmware scan is deferred.",
                "ja": "Restore 実行中のため、自動ファームウェアスキャンを延期しました。",
                "ko": "Restore 실행 중이라 자동 펌웨어 스캔을 연기했습니다.",
            ],
            "扫描完成（部分目录受权限或上限限制）。": [
                "zh-Hant": "掃描完成（部分目錄受權限或上限限制）。",
                "en": "Scan complete (some folders were limited by permissions or caps).",
                "ja": "スキャン完了（一部のフォルダは権限または上限で制限されました）。",
                "ko": "스캔 완료(일부 폴더는 권한 또는 상한으로 제한됨).",
            ],
            "已移除固件目录；文件本身未删除。": [
                "zh-Hant": "已移除韌體目錄；檔案本身未刪除。",
                "en": "Firmware folder removed; files were not deleted.",
                "ja": "ファームウェアフォルダを削除しました。ファイルは削除していません。",
                "ko": "펌웨어 폴더를 제거했습니다. 파일은 삭제하지 않았습니다.",
            ],
            "兼容性未验证，不能开始 Restore；请检查固件与设备身份。": [
                "zh-Hant": "相容性未驗證，無法開始 Restore；請檢查韌體與裝置身分。",
                "en": "Compatibility unverified; cannot start Restore. Check the firmware and device identity.",
                "ja": "互換性が未検証のため Restore を開始できません。ファームウェアとデバイス ID を確認してください。",
                "ko": "호환성을 확인할 수 없어 Restore를 시작할 수 없습니다. 펌웨어와 기기 ID를 확인하세요.",
            ],
        ]
        if let localized = ui31Copy[source]?[code] { return localized }

        let uxFixCopy: [String: [String: String]] = [
            "固件准备完成，可启动 B；A 继续运行。": [
                "zh-Hant": "韌體準備完成，可啟動 B；A 繼續執行。",
                "en": "Firmware ready; B can start while A keeps running.",
                "ja": "ファームウェア準備完了。A の実行中に B を開始できます。",
                "ko": "펌웨어 준비 완료. A 실행 중 B를 시작할 수 있습니다.",
            ],
            "固件草稿已保存；可在 A 运行时手动启动 B。": [
                "zh-Hant": "韌體草稿已儲存；可在 A 執行時手動啟動 B。",
                "en": "Firmware draft saved; start B manually while A runs.",
                "ja": "ファームウェア下書きを保存しました。A の実行中に B を手動で開始できます。",
                "ko": "펌웨어 초안 저장됨. A 실행 중 B를 수동으로 시작할 수 있습니다.",
            ],
            "已自动选择": [
                "zh-Hant": "已自動選擇", "en": "Auto-selected",
                "ja": "自動選択", "ko": "자동 선택",
            ],
            "当前机型默认固件": [
                "zh-Hant": "目前機型預設韌體", "en": "current model default",
                "ja": "現在のモデルの既定", "ko": "현재 모델 기본",
            ],
            "全局默认固件": [
                "zh-Hant": "全域預設韌體", "en": "global default",
                "ja": "グローバル既定", "ko": "전역 기본",
            ],
            "最近使用固件": [
                "zh-Hant": "最近使用的韌體", "en": "recently used",
                "ja": "最近使用したファームウェア", "ko": "최근 사용",
            ],
            "上次选择固件": [
                "zh-Hant": "上次選擇的韌體", "en": "last selected",
                "ja": "前回選択したファームウェア", "ko": "마지막 선택",
            ],
            "兼容固件库推荐": [
                "zh-Hant": "相容韌體庫推薦", "en": "compatible library recommendation",
                "ja": "互換ライブラリの推奨", "ko": "호환 라이브러리 추천",
            ],
            "固件库": [
                "zh-Hant": "韌體庫", "en": "Firmware library",
                "ja": "ファームウェアライブラリ", "ko": "펌웨어 라이브러리",
            ],
            "使用此固件": [
                "zh-Hant": "使用此韌體", "en": "Use this firmware",
                "ja": "このファームウェアを使用", "ko": "이 펌웨어 사용",
            ],
            "固件库中没有与 B 兼容且可读的 IPSW；请手动选择。": [
                "zh-Hant": "韌體庫中沒有與 B 相容且可讀的 IPSW；請手動選擇。",
                "en": "No compatible, readable IPSW for B in the library; choose one manually.",
                "ja": "B に互換で読み取り可能な IPSW がライブラリにありません。手動で選択してください。",
                "ko": "B에 호환되고 읽을 수 있는 IPSW가 라이브러리에 없습니다. 직접 선택하세요.",
            ],
            "B 的日志策略": [
                "zh-Hant": "B 的日誌策略", "en": "B log policy",
                "ja": "B のログポリシー", "ko": "B 로그 정책",
            ],
            "原始日志按当前保存设置写入 B 自己的任务目录；B 不启动独立 RLM 采集。": [
                "zh-Hant": "原始日誌按目前儲存設定寫入 B 自己的任務目錄；B 不啟動獨立 RLM 擷取。",
                "en": "Raw logs follow the current save setting into B's own task directory; B does not start its own RLM capture.",
                "ja": "生ログは現在の保存設定に従って B 専用のタスクディレクトリへ書き込まれます。B は独立した RLM キャプチャを開始しません。",
                "ko": "원시 로그는 현재 저장 설정에 따라 B 전용 작업 디렉터리에 기록되며, B는 별도 RLM 캡처를 시작하지 않습니다.",
            ],
            "A 正在使用独立 RLM 日志，B 将被拒绝启动。": [
                "zh-Hant": "A 正在使用獨立 RLM 日誌，B 將被拒絕啟動。",
                "en": "A owns an independent RLM log; B will be refused.",
                "ja": "A が独立した RLM ログを使用中のため、B は拒否されます。",
                "ko": "A가 독립 RLM 로그를 사용 중이므로 B는 거부됩니다.",
            ],
            "该物理端口当前没有已连接的设备。": [
                "zh-Hant": "此實體連接埠目前沒有已連接的裝置。",
                "en": "No device is currently connected to this physical port.",
                "ja": "この物理ポートに接続されているデバイスはありません。",
                "ko": "이 물리 포트에 연결된 기기가 없습니다.",
            ],
            "左侧选中端口与右侧身份严格对应；不会回落到其他接口的设备。": [
                "zh-Hant": "左側選取的連接埠與右側身分嚴格對應；不會回退到其他介面的裝置。",
                "en": "The selected left port and the right-side identity are strictly paired; no fallback to another port's device.",
                "ja": "左側で選択したポートと右側の識別情報は厳密に対応し、他のポートのデバイスへフォールバックしません。",
                "ko": "왼쪽에서 선택한 포트와 오른쪽 신원은 엄격히 대응하며 다른 포트 기기로 대체되지 않습니다.",
            ],
            "当前已有首任务正在运行，请先完成当前任务。": [
                "zh-Hant": "目前已有首任務正在執行，請先完成。", "en": "A primary restore is already running; finish it first.",
                "ja": "先頭タスクが実行中です。完了してください。", "ko": "첫 작업이 실행 중입니다. 먼저 완료하세요.",
            ],
            "当前已有两个 Restore 任务，无法再启动第三个。": [
                "zh-Hant": "目前已有兩個 Restore 任務，無法再啟動第三個。", "en": "Two restores are active; a third cannot start.",
                "ja": "Restore が 2 件実行中です。3 件目は開始できません。", "ko": "Restore 두 개가 실행 중입니다. 세 번째는 시작할 수 없습니다.",
            ],
            "目标已不在可用列表中，无法确认。": [
                "zh-Hant": "目標已不在可用清單中，無法確認。", "en": "The target is no longer available; cannot confirm.",
                "ja": "対象が利用可能一覧にありません。確認できません。", "ko": "대상이 더 이상 목록에 없습니다. 확인할 수 없습니다.",
            ],
            "尚无已校验的 IPSW，无法确认。": [
                "zh-Hant": "尚無已驗證的 IPSW，無法確認。", "en": "No verified IPSW; cannot confirm.",
                "ja": "検証済み IPSW がないため確認できません。", "ko": "검증된 IPSW가 없어 확인할 수 없습니다.",
            ],
            "固件尚未通过本机 BuildIdentity 精确验证，已拒绝启动。": [
                "zh-Hant": "韌體尚未通過本機 BuildIdentity 精確驗證，已拒絕啟動。", "en": "Firmware is not exactly BuildIdentity-verified for this device; start refused.",
                "ja": "この機体の BuildIdentity 精确一致が未確認のため、起動を拒否しました。", "ko": "이 기기의 BuildIdentity가 정확히 검증되지 않아 시작을 거부했습니다.",
            ],
            "确认对象已变化，请重新确认。": [
                "zh-Hant": "確認對象已變更，請重新確認。", "en": "The confirmation object changed; confirm again.",
                "ja": "確認対象が変更されました。再確認してください。", "ko": "확인 대상이 변경되었습니다. 다시 확인하세요.",
            ],
            "IPSW 或文件身份已变化，请重新确认。": [
                "zh-Hant": "IPSW 或檔案身分已變更，請重新確認。", "en": "The IPSW or file identity changed; confirm again.",
                "ja": "IPSW またはファイル識別情報が変更されました。再確認してください。", "ko": "IPSW 또는 파일 신원이 변경되었습니다. 다시 확인하세요.",
            ],
            "IPSW 文件身份在确认期间已变化，请重新确认。": [
                "zh-Hant": "IPSW 檔案身分在確認期間已變更，請重新確認。", "en": "The IPSW file identity changed during confirmation; confirm again.",
                "ja": "確認中に IPSW ファイル識別情報が変更されました。再確認してください。", "ko": "확인 중 IPSW 파일 신원이 변경되었습니다. 다시 확인하세요.",
            ],
            "确认已失效，请重新确认。": [
                "zh-Hant": "確認已失效，請重新確認。", "en": "The confirmation expired; confirm again.",
                "ja": "確認は失効しました。再確認してください。", "ko": "확인이 만료되었습니다. 다시 확인하세요.",
            ],
            "目标身份缺少必需字段：": [
                "zh-Hant": "目標身分缺少必要欄位：", "en": "Target identity is missing required fields: ",
                "ja": "対象の識別情報に必須項目がありません: ", "ko": "대상 신원에 필수 필드가 없습니다: ",
            ],
            "；已保留 IPSW，修正前禁止启动。": [
                "zh-Hant": "；已保留 IPSW，修正前禁止啟動。", "en": "; the IPSW is retained and start is blocked until corrected.",
                "ja": "。IPSW は保持され、修正まで起動できません。", "ko": "; IPSW는 유지되며 수정 전에는 시작할 수 없습니다.",
            ],
            "第二台的 IPSW 文件身份或 BuildManifest 已变化，已拒绝启动。": [
                "zh-Hant": "第二台的 IPSW 檔案身分或 BuildManifest 已變更，已拒絕啟動。",
                "en": "The second device's IPSW identity or BuildManifest changed; start was refused.",
                "ja": "2 台目の IPSW 識別情報または BuildManifest が変更されたため、起動を拒否しました。",
                "ko": "두 번째 기기의 IPSW 신원 또는 BuildManifest가 변경되어 시작을 거부했습니다.",
            ],
            "任务注册失败，已拒绝启动。": [
                "zh-Hant": "任務註冊失敗，已拒絕啟動。", "en": "Task registration failed; start was refused.",
                "ja": "タスク登録に失敗したため、起動を拒否しました。", "ko": "작업 등록에 실패하여 시작을 거부했습니다.",
            ],
            "版本未知": [
                "zh-Hant": "版本未知", "en": "version unknown",
                "ja": "バージョン不明", "ko": "버전 알 수 없음",
            ],
            "Build 未知": [
                "zh-Hant": "Build 未知", "en": "build unknown",
                "ja": "Build 不明", "ko": "Build 알 수 없음",
            ],
            "没有找到当前设备可用且兼容的固件；请手动选择 IPSW。": [
                "zh-Hant": "找不到目前裝置可用且相容的韌體；請手動選擇 IPSW。",
                "en": "No compatible firmware is available for this device; choose an IPSW manually.",
                "ja": "このデバイスで利用可能な互換ファームウェアがありません。IPSW を手動で選択してください。",
                "ko": "이 기기에 사용 가능한 호환 펌웨어가 없습니다. IPSW를 직접 선택하세요.",
            ],
        ]
        let g3g4Copy: [String: [String: String]] = [
            "设备最近结果": ["en": "Recent device result", "zh-Hant": "裝置最近結果", "ja": "デバイスの最新結果", "ko": "기기 최근 결과"],
            "导出原始日志…": ["en": "Export raw logs…", "zh-Hant": "匯出原始日誌…", "ja": "生ログを書き出す…", "ko": "원시 로그 내보내기…"],
            "保存本次 Restore 原始日志": ["en": "Save raw logs for this Restore", "zh-Hant": "儲存本次 Restore 原始日誌", "ja": "今回の Restore の生ログを保存", "ko": "이번 Restore 원시 로그 저장"],
            "只作用于下一次 Restore；关闭时不创建 raw/Staging 副本。": ["en": "Applies to the next Restore only; no raw/Staging copy is created when off.", "zh-Hant": "僅作用於下一次 Restore；關閉時不建立 raw/Staging 副本。", "ja": "次の Restore にのみ適用。オフ時は raw/Staging コピーを作成しません。", "ko": "다음 Restore에만 적용되며 끄면 raw/Staging 복사본을 만들지 않습니다."],
            "固件准备完成，可启动此设备。": ["en": "Firmware is ready; this device can start.", "zh-Hant": "韌體準備完成，可啟動此裝置。", "ja": "ファームウェアの準備が完了し、このデバイスを開始できます。", "ko": "펌웨어 준비 완료, 이 기기를 시작할 수 있습니다."],
            "固件准备完成，可启动此设备；另一台继续运行。": ["en": "Firmware is ready; this device can start while the other keeps running.", "zh-Hant": "韌體準備完成，可啟動此裝置；另一台繼續執行。", "ja": "ファームウェア準備完了。他のデバイスの実行中に開始できます。", "ko": "펌웨어 준비 완료, 다른 기기가 실행 중에도 시작할 수 있습니다."],
            "当前无法启动此设备的 Restore": ["en": "This device cannot start Restore now", "zh-Hant": "目前無法啟動此裝置的 Restore", "ja": "現在このデバイスの Restore を開始できません", "ko": "현재 이 기기의 Restore를 시작할 수 없습니다"],
            "设备 · 固件准备": ["en": "Device · Firmware preparation", "zh-Hant": "裝置 · 韌體準備", "ja": "デバイス · ファームウェア準備", "ko": "기기 · 펌웨어 준비"],
            "设备身份": ["en": "Device identity", "zh-Hant": "裝置身分", "ja": "デバイス識別情報", "ko": "기기 ID"],
            "设备的固件草稿": ["en": "Device firmware draft", "zh-Hant": "裝置的韌體草稿", "ja": "デバイスのファームウェア下書き", "ko": "기기 펌웨어 초안"],
            "为此设备选择 IPSW…": ["en": "Choose IPSW for this device…", "zh-Hant": "為此裝置選擇 IPSW…", "ja": "このデバイスの IPSW を選択…", "ko": "이 기기의 IPSW 선택…"],
            "设备的日志策略": ["en": "Device log policy", "zh-Hant": "裝置的日誌策略", "ja": "デバイスのログ方針", "ko": "기기 로그 정책"],
            "原始日志按当前保存设置写入此任务自己的目录；本任务不启动独立 RLM 采集。": ["en": "Raw logs follow the current policy and stay in this task's directory; no separate RLM capture starts for this task.", "zh-Hant": "原始日誌依目前儲存設定寫入此任務自己的目錄；本任務不啟動獨立 RLM 擷取。", "ja": "生ログは現在の保存設定でこのタスクのディレクトリに書き込まれ、このタスク専用の RLM 取得は開始しません。", "ko": "원시 로그는 현재 저장 설정에 따라 이 작업의 디렉터리에 기록되며 이 작업용 RLM 수집은 시작하지 않습니다."],
            "开始此设备的 Restore…": ["en": "Start Restore for this device…", "zh-Hant": "開始此裝置的 Restore…", "ja": "このデバイスの Restore を開始…", "ko": "이 기기의 Restore 시작…"],
            "此设备拥有独立 ECID、端口、固件、进程、取消与结果；请确认后启动。": ["en": "This device has its own ECID, port, firmware, process, cancel, and result; confirm to start.", "zh-Hant": "此裝置擁有獨立 ECID、連接埠、韌體、程序、取消與結果；請確認後啟動。", "ja": "このデバイスは独自の ECID、ポート、ファームウェア、プロセス、キャンセル、結果を持ちます。確認して開始してください。", "ko": "이 기기는 독립적인 ECID, 포트, 펌웨어, 프로세스, 취소, 결과를 가집니다. 확인 후 시작하세요."],
            "另一台正在使用独立 RLM 日志，此设备将被拒绝启动。": ["en": "The other device is using a separate RLM log; this device will be refused.", "zh-Hant": "另一台正在使用獨立 RLM 日誌，此裝置將被拒絕啟動。", "ja": "他のデバイスが独立した RLM ログを使用中のため、このデバイスの起動は拒否されます。", "ko": "다른 기기가 독립 RLM 로그를 사용 중이라 이 기기의 시작이 거부됩니다."],
            "设备 · Restore 进行中": ["en": "Device · Restore in progress", "zh-Hant": "裝置 · Restore 進行中", "ja": "デバイス · Restore 実行中", "ko": "기기 · Restore 진행 중"],
            "设备与固件": ["en": "Device and firmware", "zh-Hant": "裝置與韌體", "ja": "デバイスとファームウェア", "ko": "기기 및 펌웨어"],
            "执行状态": ["en": "Execution status", "zh-Hant": "執行狀態", "ja": "実行状態", "ko": "실행 상태"],
            "取消此设备的 Restore…": ["en": "Cancel Restore for this device…", "zh-Hant": "取消此裝置的 Restore…", "ja": "このデバイスの Restore をキャンセル…", "ko": "이 기기의 Restore 취소…"],
            "为这台设备选择的固件只保存为独立草稿；另一台运行时也可手动启动，两台独立执行，不自动排队或重试。": ["en": "Firmware chosen for this device is kept as a separate draft; it can be started while the other runs, independently and without automatic queueing or retry.", "zh-Hant": "為這台裝置選擇的韌體只儲存為獨立草稿；另一台執行時也可手動啟動，兩台獨立執行，不自動排隊或重試。", "ja": "このデバイス用のファームウェアは独立した下書きとして保存され、他の実行中でも手動で開始できます。自動キューや再試行は行いません。", "ko": "이 기기의 펌웨어는 별도 초안으로 저장되며 다른 기기가 실행 중에도 수동으로 시작할 수 있습니다. 자동 대기열이나 재시도는 없습니다."],
        ]
        let g3g4CancelCopy: [String: [String: String]] = [
            "取消对象已变化，取消未执行。": ["en": "Cancel target changed; cancel not performed.", "zh-Hant": "取消對象已變更，取消未執行。", "ja": "キャンセル対象が変わったため実行しませんでした。", "ko": "취소 대상이 변경되어 실행하지 않았습니다."],
            "次任务引擎句柄已释放，取消未送达；请等待终态或使用强杀。": ["en": "Second-task engine handle was released; cancel not delivered. Wait for terminal state or force kill.", "zh-Hant": "次任務引擎控制代碼已釋放，取消未送達；請等待終態或使用強制結束。", "ja": "2 番目タスクのエンジン参照は解放済みで、キャンセルを送信できません。終了状態を待つか強制終了してください。", "ko": "두 번째 작업 엔진 핸들이 해제되어 취소를 전달하지 못했습니다. 종료 상태를 기다리거나 강제 종료하십시오."],
            "正在取消次任务：已发送中断信号，等待进程退出…": ["en": "Canceling second task: interrupt sent, waiting for process exit…", "zh-Hant": "正在取消次任務：已送出中斷訊號，等待程序結束…", "ja": "2 番目タスクをキャンセル中: 中断信号を送信し、プロセス終了を待機しています…", "ko": "두 번째 작업 취소 중: 인터럽트를 보냈고 프로세스 종료를 기다리는 중…"],
            "强杀对象已变化或尚未请求取消，强杀未执行。": ["en": "Force-kill target changed or cancel was not requested; not performed.", "zh-Hant": "強制結束對象已變更或尚未請求取消，未執行。", "ja": "強制終了対象が変わったかキャンセル未要求のため実行しませんでした。", "ko": "강제 종료 대상이 변경되었거나 취소 요청이 없어 실행하지 않았습니다."],
            "已对次任务发送强制结束信号。": ["en": "Force-kill signal sent to second task.", "zh-Hant": "已對次任務送出強制結束訊號。", "ja": "2 番目タスクに強制終了信号を送信しました。", "ko": "두 번째 작업에 강제 종료 신호를 보냈습니다."],
            "当前任务已结束或不可取消，取消未执行。": ["en": "Task already ended or cannot be canceled; cancel not performed.", "zh-Hant": "目前任務已結束或不可取消，取消未執行。", "ja": "タスクは終了済みかキャンセルできません。", "ko": "작업이 이미 종료되었거나 취소할 수 없습니다."],
            "取消已请求，正在等待进程退出…": ["en": "Cancel requested; waiting for process exit…", "zh-Hant": "已請求取消，正在等待程序結束…", "ja": "キャンセル要求済み。プロセス終了を待機しています…", "ko": "취소를 요청했으며 프로세스 종료를 기다리는 중…"],
            "强杀不可用：任务已结束、未请求取消或进程已退出。": ["en": "Force kill unavailable: task ended, cancel not requested, or process exited.", "zh-Hant": "無法強制結束：任務已結束、未請求取消或程序已退出。", "ja": "強制終了できません: タスク終了、キャンセル未要求、またはプロセス終了済みです。", "ko": "강제 종료 불가: 작업 종료, 취소 요청 없음 또는 프로세스 종료."],
            "次任务仍未退出，可使用强制结束。": ["en": "Second task still running; force kill is available.", "zh-Hant": "次任務仍未結束，可使用強制結束。", "ja": "2 番目タスクはまだ実行中です。強制終了できます。", "ko": "두 번째 작업이 아직 실행 중입니다. 강제 종료를 사용할 수 있습니다."],
            "正在取消：已发送中断信号，等待进程退出…": ["en": "Canceling: interrupt sent, waiting for process exit…", "zh-Hant": "正在取消：已送出中斷訊號，等待程序結束…", "ja": "キャンセル中: 中断信号を送信し、プロセス終了を待機しています…", "ko": "취소 중: 인터럽트를 보냈고 프로세스 종료를 기다리는 중…"],
            "强制结束次任务…": ["en": "Force kill second task…", "zh-Hant": "強制結束次任務…", "ja": "2 番目タスクを強制終了…", "ko": "두 번째 작업 강제 종료…"],
        ]
        if let localized = g3g4CancelCopy[source]?[code] { return localized }
        let g3g4CopyExtra: [String: [String: String]] = [
            "开始此设备的 Restore": ["en": "Start Restore for this device", "zh-Hant": "開始此裝置的 Restore", "ja": "このデバイスの Restore を開始", "ko": "이 기기의 Restore 시작"],
            "开始此设备的 Restore？若另一台正在运行，两台将同时刷机，并各自拥有独立进程、取消与结果。": ["en": "Start Restore for this device? If the other is running, both restore at once with independent processes, cancel, and results.", "zh-Hant": "開始此裝置的 Restore？若另一台正在執行，兩台將同時刷機，並各自擁有獨立程序、取消與結果。", "ja": "このデバイスの Restore を開始しますか？他のデバイスが実行中の場合は同時に復元し、プロセス、キャンセル、結果は独立します。", "ko": "이 기기의 Restore를 시작할까요? 다른 기기가 실행 중이면 동시에 복원하며 프로세스, 취소, 결과는 독립적입니다."],
        ]
        if let localized = g3g4CopyExtra[source]?[code] { return localized }
        if let localized = g3g4Copy[source]?[code] { return localized }
        if let localized = uxFixCopy[source]?[code] { return localized }
        let feedbackTitles: [String: [String: String]] = [
            "双发序列进行中": ["zh-Hant":"雙發序列進行中", "en":"DFU sequence in progress", "ja":"DFU シーケンス実行中", "ko":"DFU 전송 진행 중"],
            "恢复模式进行中": ["zh-Hant":"恢復模式進行中", "en":"Recovery in progress", "ja":"リカバリ実行中", "ko":"복구 모드 진행 중"],
            "测试组运行中": ["zh-Hant":"測試組執行中", "en":"Request sequence in progress", "ja":"リクエスト実行中", "ko":"요청 진행 중"],
            "已停止：主机侧无法唯一定位原端口": ["zh-Hant":"已停止：主機端無法唯一定位原連接埠", "en":"Stopped: original host port cannot be uniquely identified", "ja":"停止：元のホストポートを一意に特定できません", "ko":"중지됨: 원래 호스트 포트를 식별할 수 없음"],
            "恢复模式请求已完成": ["zh-Hant":"恢復模式要求已完成", "en":"Recovery requests complete.", "ja":"リカバリのリクエストが完了しました。", "ko":"복구 요청이 완료되었습니다."],
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
        for map in [mainFix, techFix, helperFix, settingsFix, configFix, batch1, batch2, batch3, batch4, batch5, batch6, batch7, batch8, batch9, batch10, batch11, batch12, batch13, restoreFix, workbenchFix, firmwarePreferencesFix] {
            if let exact = map[code]?[source] { return exact }
        }
        let currentViewPrefix = "当前查看 · "
        if source.hasPrefix(currentViewPrefix) {
            let target = String(source.dropFirst(currentViewPrefix.count))
            let templates = [
                "zh-Hant": "目前檢視 · %@",
                "en": "Viewing · %@",
                "ja": "表示対象 · %@",
                "ko": "보기 · %@"
            ]
            if let template = templates[code] {
                return String(format: template, t(target))
            }
        }
        let pinnedViewPrefix = "固定查看："
        if source.hasPrefix(pinnedViewPrefix) {
            let target = String(source.dropFirst(pinnedViewPrefix.count))
            let templates = [
                "zh-Hant": "固定檢視：%@",
                "en": "Pin View: %@",
                "ja": "表示を固定：%@",
                "ko": "보기 고정: %@"
            ]
            if let template = templates[code] {
                return String(format: template, t(target))
            }
        }
        let helperPrefix = "Helper："
        if source.hasPrefix(helperPrefix) {
            let state = String(source.dropFirst(helperPrefix.count))
            let templates = [
                "zh-Hant": "Helper：%@",
                "en": "Helper: %@",
                "ja": "Helper: %@",
                "ko": "Helper: %@"
            ]
            if let template = templates[code] {
                return String(format: template, t(state))
            }
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
        for (zh, translated) in restoreFix[code] ?? [:] {
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
        for (zh, translated) in batch8[code] ?? [:] {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        for (zh, translated) in batch9[code] ?? [:] {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        for (zh, translated) in batch10[code] ?? [:] {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        for (zh, translated) in batch11[code] ?? [:] {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        for (zh, translated) in batch12[code] ?? [:] {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        for (zh, translated) in batch13[code] ?? [:] {
            result = result.replacingOccurrences(of: zh, with: translated)
        }
        return result
    }

    private static let batch12: [String: [String: String]] = [
        "en": [
            "日志存储与清理": "Log Storage and Cleanup",
            "Restore 原始日志存储": "Restore Raw Log Storage",
            "默认不长期保存完整原始日志。自动监控 Restore、自动保存原始日志和保存本次日志是三个独立选择。": "Complete raw logs are not retained by default. Auto-monitor, auto-save raw logs, and save-this-run are independent choices.",
            "保存设置": "Saving Settings",
            "自动保存 Restore 原始日志": "Automatically save Restore raw logs",
            "新安装默认关闭。关闭时 Restore 照常执行，但结束后可能无法补导出本次完整原始日志。": "Off by default for a new installation. Restore still runs normally, but the complete raw log may not be recoverable afterward.",
            "此选择只作用于下一次 Restore，不改变全局默认。关闭时不会创建 Restore raw、Staging 或隐藏副本。": "This choice applies only to the next Restore and does not change the global default. When off, no Restore raw, staging, or hidden copy is created.",
            "cfgutil 原始日志保存位置": "cfgutil raw log location",
            "证据包保存位置": "Evidence package location",
            "更改…": "Change…",
            "RLM 系统原始日志（固定本机目录）": "RLM system raw logs (fixed local directory)",
            "空间提醒": "Space warning",
            "字节": "bytes",
            "异常原始日志保留天数": "Failure raw-log retention days",
            "日志总预算": "Total log budget",
            "空间统计与清理预览": "Storage Usage and Cleanup Preview",
            "扫描日志占用": "Scan log usage",
            "预览并确认清理…": "Preview and confirm cleanup…",
            "尚未扫描。清理前必须查看分类预览并再次确认。": "Not scanned yet. Review the categorized preview and confirm before cleanup.",
            "确认清理日志": "Confirm log cleanup",
            "删除已列出的可清理候选": "Delete listed cleanup candidates",
            "只处理当前预览中的可清理候选；锁定项、成功基准、证据包、未知来源、活动或状态已变化的文件会被跳过。不会删除 Configurator、IPSW 或客户数据。": "Only current cleanup candidates are processed. Locked items, trusted baselines, evidence packages, unknown files, active files, and files whose state changed are skipped. Configurator, IPSW, and customer data are not deleted.",
            "扫描完成；未执行任何删除。": "Scan completed; nothing was deleted.",
            "有 Restore 正在准备或运行；结束当前任务前不会清理日志。": "A Restore is being prepared or is running. Logs will not be cleaned until the current task ends.",
            "证据包已导出，关联日志保护已持久登记。": "The evidence package was exported and its linked log protection was persisted.",
            "证据包已生成，但保护登记写入失败；已保存待重试标记，日志清理保持关闭。": "The evidence package was created, but its protection record could not be persisted. A retry marker was saved and log cleanup remains closed.",
            "证据包已生成，但保护登记和待重试标记均写入失败；本次运行已禁用日志清理。": "The evidence package was created, but both its protection record and retry marker failed to persist. Log cleanup is disabled for this run."
        ],
        "zh-Hant": [
            "日志存储与清理": "日誌儲存與清理",
            "Restore 原始日志存储": "Restore 原始日誌儲存",
            "默认不长期保存完整原始日志。自动监控 Restore、自动保存原始日志和保存本次日志是三个独立选择。": "預設不長期保存完整原始日誌。自動監控 Restore、自動保存原始日誌與保存本次日誌是三個獨立選項。",
            "保存设置": "儲存設定",
            "自动保存 Restore 原始日志": "自動保存 Restore 原始日誌",
            "新安装默认关闭。关闭时 Restore 照常执行，但结束后可能无法补导出本次完整原始日志。": "全新安裝預設關閉。關閉時 Restore 仍正常執行，但結束後可能無法補匯出本次完整原始日誌。",
            "此选择只作用于下一次 Restore，不改变全局默认。关闭时不会创建 Restore raw、Staging 或隐藏副本。": "此選擇只作用於下一次 Restore，不變更全域預設。關閉時不會建立 Restore 原始日誌、Staging 或隱藏副本。",
            "cfgutil 原始日志保存位置": "cfgutil 原始日誌儲存位置",
            "证据包保存位置": "證據包儲存位置",
            "更改…": "變更…",
            "RLM 系统原始日志（固定本机目录）": "RLM 系統原始日誌（固定本機目錄）",
            "空间提醒": "空間提醒",
            "字节": "位元組",
            "异常原始日志保留天数": "異常原始日誌保留天數",
            "日志总预算": "日誌總預算",
            "空间统计与清理预览": "空間統計與清理預覽",
            "扫描日志占用": "掃描日誌使用量",
            "预览并确认清理…": "預覽並確認清理…",
            "尚未扫描。清理前必须查看分类预览并再次确认。": "尚未掃描。清理前必須查看分類預覽並再次確認。",
            "确认清理日志": "確認清理日誌",
            "删除已列出的可清理候选": "刪除已列出的可清理候選",
            "只处理当前预览中的可清理候选；锁定项、成功基准、证据包、未知来源、活动或状态已变化的文件会被跳过。不会删除 Configurator、IPSW 或客户数据。": "只處理目前預覽中的可清理候選；鎖定項目、成功基準、證據包、未知來源、使用中或狀態已變更的檔案會跳過。不會刪除 Configurator、IPSW 或客戶資料。",
            "扫描完成；未执行任何删除。": "掃描完成；未執行任何刪除。",
            "有 Restore 正在准备或运行；结束当前任务前不会清理日志。": "有 Restore 正在準備或執行；目前工作結束前不會清理日誌。",
            "证据包已导出，关联日志保护已持久登记。": "證據包已匯出，關聯日誌保護已持久登錄。",
            "证据包已生成，但保护登记写入失败；已保存待重试标记，日志清理保持关闭。": "證據包已建立，但保護登錄寫入失敗。已儲存待重試標記，日誌清理保持關閉。",
            "证据包已生成，但保护登记和待重试标记均写入失败；本次运行已禁用日志清理。": "證據包已建立，但保護登錄與待重試標記均寫入失敗。本次執行已停用日誌清理。"
        ],
        "ja": [
            "日志存储与清理": "ログ保存とクリーンアップ",
            "Restore 原始日志存储": "Restore 生ログの保存",
            "默认不长期保存完整原始日志。自动监控 Restore、自动保存原始日志和保存本次日志是三个独立选择。": "完全な生ログは既定では長期保存されません。Restore の自動監視、生ログの自動保存、今回のみ保存は独立した選択です。",
            "保存设置": "保存設定",
            "自动保存 Restore 原始日志": "Restore 生ログを自動保存",
            "新安装默认关闭。关闭时 Restore 照常执行，但结束后可能无法补导出本次完整原始日志。": "新規インストールでは既定でオフです。オフでも Restore は正常に実行されますが、終了後に完全な生ログを復元できない場合があります。",
            "此选择只作用于下一次 Restore，不改变全局默认。关闭时不会创建 Restore raw、Staging 或隐藏副本。": "この選択は次回の Restore にのみ適用され、グローバル既定値は変わりません。オフの場合、Restore の生ログ、ステージング、隠しコピーは作成されません。",
            "cfgutil 原始日志保存位置": "cfgutil 生ログの保存先",
            "证据包保存位置": "証拠パッケージの保存先",
            "更改…": "変更…",
            "RLM 系统原始日志（固定本机目录）": "RLM システム生ログ（固定ローカルディレクトリ）",
            "空间提醒": "容量警告",
            "字节": "バイト",
            "异常原始日志保留天数": "異常生ログの保存日数",
            "日志总预算": "ログ総容量予算",
            "空间统计与清理预览": "容量集計とクリーンアップのプレビュー",
            "扫描日志占用": "ログ使用量をスキャン",
            "预览并确认清理…": "確認してクリーンアップ…",
            "尚未扫描。清理前必须查看分类预览并再次确认。": "未スキャンです。クリーンアップ前に分類プレビューを確認してください。",
            "确认清理日志": "ログのクリーンアップを確認",
            "删除已列出的可清理候选": "一覧の候補を削除",
            "只处理当前预览中的可清理候选；锁定项、成功基准、证据包、未知来源、活动或状态已变化的文件会被跳过。不会删除 Configurator、IPSW 或客户数据。": "現在の候補だけを処理します。ロック項目、信頼済み基準、証拠パッケージ、出所不明、使用中、状態が変わったファイルはスキップします。Configurator、IPSW、顧客データは削除しません。",
            "扫描完成；未执行任何删除。": "スキャン完了。削除は実行されていません。",
            "有 Restore 正在准备或运行；结束当前任务前不会清理日志。": "Restore の準備または実行中です。現在のタスクが終了するまでログを削除しません。",
            "证据包已导出，关联日志保护已持久登记。": "証拠パッケージを書き出し、関連ログの保護を永続登録しました。",
            "证据包已生成，但保护登记写入失败；已保存待重试标记，日志清理保持关闭。": "証拠パッケージは作成されましたが、保護登録を永続化できませんでした。再試行マーカーを保存し、ログ削除は無効のままです。",
            "证据包已生成，但保护登记和待重试标记均写入失败；本次运行已禁用日志清理。": "証拠パッケージは作成されましたが、保護登録と再試行マーカーの両方を永続化できませんでした。今回の実行ではログ削除を無効にしました。"
        ],
        "ko": [
            "日志存储与清理": "로그 저장 및 정리",
            "Restore 原始日志存储": "Restore 원본 로그 저장",
            "默认不长期保存完整原始日志。自动监控 Restore、自动保存原始日志和保存本次日志是三个独立选择。": "전체 원본 로그는 기본적으로 장기 저장되지 않습니다. Restore 자동 모니터링, 원본 로그 자동 저장, 이번 실행 저장은 서로 독립적인 선택입니다.",
            "保存设置": "저장 설정",
            "自动保存 Restore 原始日志": "Restore 원본 로그 자동 저장",
            "新安装默认关闭。关闭时 Restore 照常执行，但结束后可能无法补导出本次完整原始日志。": "새 설치에서는 기본적으로 꺼져 있습니다. 꺼져 있어도 Restore는 정상 실행되지만 종료 후 전체 원본 로그를 다시 내보내지 못할 수 있습니다.",
            "此选择只作用于下一次 Restore，不改变全局默认。关闭时不会创建 Restore raw、Staging 或隐藏副本。": "이 선택은 다음 Restore에만 적용되며 전역 기본값을 변경하지 않습니다. 꺼져 있으면 Restore 원본 로그, Staging 또는 숨은 복사본을 만들지 않습니다.",
            "cfgutil 原始日志保存位置": "cfgutil 원본 로그 저장 위치",
            "证据包保存位置": "증거 패키지 저장 위치",
            "更改…": "변경…",
            "RLM 系统原始日志（固定本机目录）": "RLM 시스템 원본 로그(고정 로컬 폴더)",
            "空间提醒": "공간 경고",
            "字节": "바이트",
            "异常原始日志保留天数": "오류 원본 로그 보존 일수",
            "日志总预算": "로그 전체 예산",
            "空间统计与清理预览": "공간 사용량 및 정리 미리보기",
            "扫描日志占用": "로그 사용량 스캔",
            "预览并确认清理…": "미리보기 후 정리 확인…",
            "尚未扫描。清理前必须查看分类预览并再次确认。": "아직 스캔하지 않았습니다. 정리 전에 분류 미리보기를 확인하고 다시 승인해야 합니다.",
            "确认清理日志": "로그 정리 확인",
            "删除已列出的可清理候选": "표시된 정리 후보 삭제",
            "只处理当前预览中的可清理候选；锁定项、成功基准、证据包、未知来源、活动或状态已变化的文件会被跳过。不会删除 Configurator、IPSW 或客户数据。": "현재 미리보기의 정리 후보만 처리합니다. 잠긴 항목, 신뢰 기준, 증거 패키지, 출처가 불명확한 파일, 사용 중이거나 상태가 바뀐 파일은 건너뜁니다. Configurator, IPSW 또는 고객 데이터는 삭제하지 않습니다.",
            "扫描完成；未执行任何删除。": "스캔 완료. 삭제는 수행하지 않았습니다.",
            "有 Restore 正在准备或运行；结束当前任务前不会清理日志。": "Restore가 준비 또는 실행 중입니다. 현재 작업이 끝날 때까지 로그를 정리하지 않습니다.",
            "证据包已导出，关联日志保护已持久登记。": "증거 패키지를 내보냈고 연결된 로그 보호를 영구 등록했습니다.",
            "证据包已生成，但保护登记写入失败；已保存待重试标记，日志清理保持关闭。": "증거 패키지는 생성되었지만 보호 등록을 저장하지 못했습니다. 재시도 표시를 저장했으며 로그 정리는 계속 차단됩니다.",
            "证据包已生成，但保护登记和待重试标记均写入失败；本次运行已禁用日志清理。": "증거 패키지는 생성되었지만 보호 등록과 재시도 표시를 모두 저장하지 못했습니다. 이번 실행에서는 로그 정리를 비활성화했습니다."
        ]
    ]

    private static let exact: [String: [String: String]] = [
        "en": [
            "当前版本不会启动第二个任务":"This version will not start a second task.",
            "状态已变化，需重新核验后才能使用。":"State changed; re-verify before use.",
            "兼容性未确认，需人工核验后才能使用。":"Compatibility unverified; manual verification is required before use.",
            "取消 A 的 Restore…":"Cancel A's Restore…",
            "目标设备已变化，未载入草稿。":"The target device changed; the draft was not loaded.",
            "草稿已保存；需重新核验后再启动。":"Draft saved; re-verify before starting.",
            "第二台设备 · 固件准备":"Second device · Firmware preparation",
            "A 正在 Restore":"A is restoring",
            "为 B 选择的固件只保存为草稿；当前版本仅支持一个活动任务，不会启动、排队或自动开始。":"Firmware chosen for B is saved as a draft only; this version supports one active task and will not start, queue, or auto-start.",
            "B 的设备身份":"B's device identity",
            "B 的固件草稿":"B's firmware draft",
            "为 B 选择 IPSW…":"Choose IPSW for B…",
            "清除草稿":"Clear draft",
            "启动状态":"Start status",
            "开始 Restore（当前仅支持一个活动任务）":"Start Restore (one active task only)",
            "A 结束后，请重新核验 B 的设备与固件，再使用原有确认流程手动启动。":"After A finishes, re-verify B's device and firmware, then start manually through the existing confirmation flow.",
            "固件准备完成，等待当前 Restore 结束。":"Firmware ready; waiting for the current Restore to finish.",            "设备连接已变化，需重新核验后才能使用。":"The device connection changed; re-verify before use.",
            "当前未检测到可靠设备身份，不能确认固件归属。":"No reliable device identity detected; firmware ownership cannot be confirmed.",
            "该草稿属于另一台设备，不可用于当前设备。":"This draft belongs to another device and cannot be used here.",
            "设备连接代际已变化，需重新核验。":"The device connection generation changed; re-verify.",
            "固件文件已被替换或移动，需重新选择。":"The firmware file was replaced or moved; choose it again.",
            "固件未通过验证，不能用于启动。":"Firmware did not pass verification and cannot be used to start.",
            "端口归属不唯一，不能自动绑定该草稿。":"Port ownership is ambiguous; the draft cannot be bound automatically.",
            "还没有为这台设备准备固件。":"No firmware prepared for this device yet.",
            "已保存的 B 固件草稿":"Saved B firmware draft",
            "重新核验并载入":"Re-verify and load",
            "固件草稿已保存，等待当前 Restore 结束后再核验启动。":"Firmware draft saved; re-verify and start after the current Restore finishes.",            "无法读取该 IPSW 的固件信息；草稿未保存。":"Cannot read this IPSW's firmware info; draft not saved.",
            "固件未通过验证；草稿已保留，但不能直接用于启动。":"Firmware did not pass verification; the draft is kept but cannot be used to start.",
            "固件与当前设备不兼容；草稿已保留，但不能直接用于启动。":"Firmware is incompatible with this device; the draft is kept but cannot be used to start.",
            "未知端口":"Unknown port",
            "查看端口当前不可用":"Viewed port is unavailable",
            "该端口已不在当前设备列表中；此处不显示该端口的设备详情。":"This port is no longer in the device list; its device details are not shown here.",
            "未记录":"Not recorded",
            "Restore 任务总览":"Task overview",
            "项活动":"task(s)",
            "单任务模式":"Single-task mode",
            "正在查看":"Viewing",
            "查看任务":"View task",
            "当前没有活动 Restore":"No active Restore",
            "本阶段":"Stage",
            "整体未知":"overall unknown",
            "完成":"Done",
            "失败":"Failed",
            "Restore 成功":"Restore succeeded",
            "Restore 失败":"Restore failed",
            "Restore 已取消":"Restore canceled",
            "已取消":"Canceled",
            "结果未知":"Result unknown",
            "取消处理中":"Canceling",
            "准备中":"Preparing",
            "执行中":"Running",
            "结束处理中":"Finalizing",
            "上一项任务":"Previous task",
            "端口历史":"Port history",
            "本口最近任务":"Latest task on this port",
            "查看历史":"View history",
            "收起历史":"Hide history",
            "固件":"Firmware",
            "结果":"Result",
            "退出":"Exit code",
            "原始日志":"Raw log",
            "完成时间":"Completed",
            "尝试":"Attempt",
            "历史任务不可取消、不可擦除；仅用于核对。":"Historical tasks cannot be canceled or erased; for reference only.",
            "端口归属待确认，未显示历史":"Port ownership unconfirmed; history hidden.",
            "物理控制":"Control",
            "返回控制端口":"Back to control port",
            "任务已变化，取消未执行":"Task changed; cancel not executed.",
            "任务已结束，强杀未执行":"Task ended; force kill not executed.",
            "当前没有可取消的任务":"No cancellable task.",
            "关闭":"Close",
            "无法取得 Restore 独占锁，已阻止启动以避免并发冲突。":"Could not take the Restore lease; launch blocked to avoid a concurrent conflict.","当前已有 Restore 任务正在运行，请先完成当前任务。":"Another Restore task is already running. Finish it first.",
            "请求发送中":"Sending request","请求已发送 · 结果未确认":"Request sent · result unconfirmed","未发送/失败":"Not sent / failed",
            "读取的 USB 产品名":"USB product name read","自定义校准":"Custom calibration",
            "实际采用：自定义校准（controller + PortNumber）":"In use: Custom calibration (controller + PortNumber)",
            "进入 DFU": "Enter DFU", "重启设备": "Restart Device", "恢复模式": "Recovery", "Helper 不可用": "Helper unavailable",
            "设备控制调用不可用":"Device control call unavailable",
            "USB location + controller/PortNumber/RID 精确校准一致":"USB location + controller/PortNumber/RID exactly calibrated and matched",
            "未检测到目标 Mac":"No target Mac detected",
            "当前未检测到目标设备":"No target device currently detected",
            "当前没有目标设备":"No target device currently",
            "当前观察未知":"Current observation unknown",
            "USB 设备已连接 · 身份待识别":"USB device connected · identity pending",
            "USB 外设，不冒充目标 Mac":"USB peripheral; not presented as the target Mac",
            "当前 Mac 身份证据不足":"Current Mac identity evidence is insufficient",
            "端口链路有连接；未枚举到目标设备":"Port link is connected; no target device enumerated",
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
            "内置校准": "Built-in calibration", "实际采用": "In use", "模型": "Model",
            "模型库": "Model Library", "导出所选模型包…": "Export Selected Model Pack…",
            "没有可导出的模型布局。": "No model layout is available to export."
        ],
        "zh-Hant": [
            "当前版本不会启动第二个任务":"目前版本不會啟動第二個任務",
            "状态已变化，需重新核验后才能使用。":"狀態已變更，需重新核驗後才能使用。",
            "兼容性未确认，需人工核验后才能使用。":"相容性未確認，需人工核驗後才能使用。",
            "取消 A 的 Restore…":"取消 A 的 Restore…",
            "目标设备已变化，未载入草稿。":"目標裝置已變更，未載入草稿。",
            "草稿已保存；需重新核验后再启动。":"草稿已儲存；需重新核驗後再啟動。",
            "第二台设备 · 固件准备":"第二台裝置 · 韌體準備",
            "A 正在 Restore":"A 正在 Restore",
            "为 B 选择的固件只保存为草稿；当前版本仅支持一个活动任务，不会启动、排队或自动开始。":"為 B 選擇的韌體只儲存為草稿；目前版本僅支援一個活動任務，不會啟動、排隊或自動開始。",
            "B 的设备身份":"B 的裝置身分",
            "B 的固件草稿":"B 的韌體草稿",
            "为 B 选择 IPSW…":"為 B 選擇 IPSW…",
            "清除草稿":"清除草稿",
            "启动状态":"啟動狀態",
            "开始 Restore（当前仅支持一个活动任务）":"開始 Restore（目前僅支援一個活動任務）",
            "A 结束后，请重新核验 B 的设备与固件，再使用原有确认流程手动启动。":"A 結束後，請重新核驗 B 的裝置與韌體，再使用原有確認流程手動啟動。",
            "固件准备完成，等待当前 Restore 结束。":"韌體準備完成，等待目前 Restore 結束。",
            "设备连接已变化，需重新核验后才能使用。":"裝置連線已變更，需重新核驗後才能使用。",
            "当前未检测到可靠设备身份，不能确认固件归属。":"目前未偵測到可靠裝置身分，無法確認韌體歸屬。",
            "该草稿属于另一台设备，不可用于当前设备。":"該草稿屬於另一台裝置，不可用於目前裝置。",
            "设备连接代际已变化，需重新核验。":"裝置連線世代已變更，需重新核驗。",
            "固件文件已被替换或移动，需重新选择。":"韌體檔案已被替換或移動，需重新選擇。",
            "固件未通过验证，不能用于启动。":"韌體未通過驗證，不能用於啟動。",
            "端口归属不唯一，不能自动绑定该草稿。":"埠歸屬不唯一，不能自動綁定該草稿。",
            "还没有为这台设备准备固件。":"還沒有為這台裝置準備韌體。",
            "已保存的 B 固件草稿":"已儲存的 B 韌體草稿",
            "重新核验并载入":"重新核驗並載入",
            "固件草稿已保存，等待当前 Restore 结束后再核验启动。":"韌體草稿已儲存，等待目前 Restore 結束後再核驗啟動。",
            "无法读取该 IPSW 的固件信息；草稿未保存。":"無法讀取該 IPSW 的韌體資訊；草稿未儲存。",
            "固件未通过验证；草稿已保留，但不能直接用于启动。":"韌體未通過驗證；草稿已保留，但不能直接用於啟動。",
            "固件与当前设备不兼容；草稿已保留，但不能直接用于启动。":"韌體與目前裝置不相容；草稿已保留，但不能直接用於啟動。",
            "未知端口":"未知埠",
            "查看端口当前不可用":"檢視埠目前不可用",
            "该端口已不在当前设备列表中；此处不显示该端口的设备详情。":"該埠已不在目前裝置清單中；此處不顯示該埠的裝置資訊。",
            "未记录":"未記錄",
            "Restore 任务总览":"Restore 任務總覽",
            "项活动":"項活動",
            "单任务模式":"單任務模式",
            "正在查看":"正在檢視",
            "查看任务":"檢視任務",
            "当前没有活动 Restore":"目前沒有活動 Restore",
            "本阶段":"本階段",
            "整体未知":"整體未知",
            "完成":"完成",
            "失败":"失敗",
            "Restore 成功":"Restore 成功",
            "Restore 失败":"Restore 失敗",
            "Restore 已取消":"Restore 已取消",
            "已取消":"已取消",
            "结果未知":"結果未知",
            "取消处理中":"取消處理中",
            "准备中":"準備中",
            "执行中":"執行中",
            "结束处理中":"結束處理中",
            "上一项任务":"上一項任務",
            "端口历史":"埠歷史",
            "本口最近任务":"本埠最近任務",
            "查看历史":"檢視歷史",
            "收起历史":"收合歷史",
            "固件":"韌體",
            "结果":"結果",
            "退出":"結束代碼",
            "原始日志":"原始日誌",
            "完成时间":"完成時間",
            "尝试":"嘗試",
            "历史任务不可取消、不可擦除；仅用于核对。":"歷史任務不可取消、不可抹除；僅供核對。",
            "端口归属待确认，未显示历史":"埠歸屬待確認，未顯示歷史",
            "物理控制":"實體控制",
            "返回控制端口":"返回控制埠",
            "任务已变化，取消未执行":"任務已變更，取消未執行",
            "任务已结束，强杀未执行":"任務已結束，強制結束未執行",
            "当前没有可取消的任务":"目前沒有可取消的任務",
            "关闭":"關閉",
            "无法取得 Restore 独占锁，已阻止启动以避免并发冲突。":"無法取得 Restore 獨佔鎖，已阻止啟動以避免並行衝突。","当前已有 Restore 任务正在运行，请先完成当前任务。":"目前已有 Restore 任務正在執行，請先完成目前任務。",
            "请求发送中":"傳送中","请求已发送 · 结果未确认":"要求已傳送 · 結果未確認","未发送/失败":"未傳送／失敗",
            "读取的 USB 产品名":"讀取的 USB 產品名稱","自定义校准":"自訂校準",
            "实际采用：自定义校准（controller + PortNumber）":"實際採用：自訂校準（controller + PortNumber）",
            "进入 DFU": "進入 DFU", "重启设备": "重新啟動裝置", "恢复模式": "恢復模式", "Helper 不可用": "Helper 無法使用",
            "设备控制调用不可用":"裝置控制呼叫不可用",
            "USB location + controller/PortNumber/RID 精确校准一致":"USB location + controller/PortNumber/RID 精確校準一致",
            "未检测到目标 Mac":"未偵測到目標 Mac",
            "当前未检测到目标设备":"目前未偵測到目標裝置",
            "当前没有目标设备":"目前沒有目標裝置",
            "当前观察未知":"目前觀察未知",
            "USB 设备已连接 · 身份待识别":"USB 裝置已連接 · 身分待識別",
            "USB 外设，不冒充目标 Mac":"USB 周邊，不冒充目標 Mac",
            "当前 Mac 身份证据不足":"目前 Mac 身分證據不足",
            "端口链路有连接；未枚举到目标设备":"連接埠鏈路有連線；未列舉到目標裝置",
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
            "内置校准": "內建校準", "实际采用": "實際採用", "模型": "模型",
            "模型库": "機型資料庫", "导出所选模型包…": "匯出所選機型包…",
            "没有可导出的模型布局。": "沒有可匯出的機型版面。"
        ],
        "ja": [
            "当前版本不会启动第二个任务":"このバージョンは 2 つ目のタスクを開始しません。",
            "状态已变化，需重新核验后才能使用。":"状態が変更されました。使用前に再確認してください。",
            "兼容性未确认，需人工核验后才能使用。":"互換性が未確認です。使用前に手動で確認してください。",
            "取消 A 的 Restore…":"A の Restore をキャンセル…",
            "目标设备已变化，未载入草稿。":"対象デバイスが変更されたため、下書きを読み込みませんでした。",
            "草稿已保存；需重新核验后再启动。":"下書きを保存しました。起動前に再確認してください。",
            "第二台设备 · 固件准备":"2 台目デバイス · ファームウェア準備",
            "A 正在 Restore":"A は Restore 実行中",
            "为 B 选择的固件只保存为草稿；当前版本仅支持一个活动任务，不会启动、排队或自动开始。":"B 用に選んだファームウェアは下書きとして保存されるだけです。このバージョンは 1 つの実行中タスクのみ対応し、起動・待機・自動開始は行いません。",
            "B 的设备身份":"B のデバイス情報",
            "B 的固件草稿":"B のファームウェア下書き",
            "为 B 选择 IPSW…":"B 用 IPSW を選択…",
            "清除草稿":"下書きを消去",
            "启动状态":"起動状態",
            "开始 Restore（当前仅支持一个活动任务）":"Restore を開始（実行中タスクは 1 つのみ）",
            "A 结束后，请重新核验 B 的设备与固件，再使用原有确认流程手动启动。":"A の終了後、B のデバイスとファームウェアを再確認し、既存の確認フローで手動起動してください。",
            "固件准备完成，等待当前 Restore 结束。":"ファームウェア準備完了。現在の Restore の終了を待っています。",
            "设备连接已变化，需重新核验后才能使用。":"デバイス接続が変更されました。使用前に再確認してください。",
            "当前未检测到可靠设备身份，不能确认固件归属。":"信頼できるデバイス情報がありません。ファームウェアの帰属を確認できません。",
            "该草稿属于另一台设备，不可用于当前设备。":"この下書きは別のデバイスのものです。現在のデバイスには使えません。",
            "设备连接代际已变化，需重新核验。":"デバイス接続の世代が変更されました。再確認してください。",
            "固件文件已被替换或移动，需重新选择。":"ファームウェアファイルが置換または移動されました。再選択してください。",
            "固件未通过验证，不能用于启动。":"ファームウェアが検証に合格していないため起動できません。",
            "端口归属不唯一，不能自动绑定该草稿。":"ポートの帰属が一意でないため、下書きを自動で紐付けられません。",
            "还没有为这台设备准备固件。":"このデバイス用のファームウェアはまだ準備されていません.",
            "已保存的 B 固件草稿":"保存済みの B ファームウェア下書き",
            "重新核验并载入":"再確認して読み込む",
            "固件草稿已保存，等待当前 Restore 结束后再核验启动。":"ファームウェア下書きを保存しました。現在の Restore 終了後に再確認して起動してください。",
            "无法读取该 IPSW 的固件信息；草稿未保存。":"この IPSW のファームウェア情報を読み取れません。下書きは保存されていません。",
            "固件未通过验证；草稿已保留，但不能直接用于启动。":"ファームウェアが検証に合格していません。下書きは保持されますが起動には使えません。",
            "固件与当前设备不兼容；草稿已保留，但不能直接用于启动。":"ファームウェアが現在のデバイスと互換性がありません。下書きは保持されますが起動には使えません。",
            "未知端口":"不明なポート",
            "查看端口当前不可用":"表示中のポートは利用できません",
            "该端口已不在当前设备列表中；此处不显示该端口的设备详情。":"このポートは現在のデバイス一覧にありません。ここではこのポートの情報を表示しません。",
            "未记录":"記録なし",
            "Restore 任务总览":"Restore タスク概要",
            "项活动":"件",
            "单任务模式":"単一タスクモード",
            "正在查看":"表示中",
            "查看任务":"タスクを表示",
            "当前没有活动 Restore":"実行中の Restore はありません",
            "本阶段":"この段階",
            "整体未知":"全体は不明",
            "完成":"完了",
            "失败":"失敗",
            "Restore 成功":"Restore 成功",
            "Restore 失败":"Restore 失敗",
            "Restore 已取消":"Restore キャンセル済み",
            "已取消":"キャンセル済み",
            "结果未知":"結果不明",
            "取消处理中":"キャンセル処理中",
            "准备中":"準備中",
            "执行中":"実行中",
            "结束处理中":"終了処理中",
            "上一项任务":"前回のタスク",
            "端口历史":"ポート履歴",
            "本口最近任务":"このポートの最新タスク",
            "查看历史":"履歴を表示",
            "收起历史":"履歴を閉じる",
            "固件":"ファームウェア",
            "结果":"結果",
            "退出":"終了コード",
            "原始日志":"生ログ",
            "完成时间":"完了時刻",
            "尝试":"試行",
            "历史任务不可取消、不可擦除；仅用于核对。":"履歴タスクは取消・消去できません。確認用です。",
            "端口归属待确认，未显示历史":"ポート帰属が未確認のため履歴を表示しません。",
            "物理控制":"物理制御",
            "返回控制端口":"制御ポートに戻る",
            "任务已变化，取消未执行":"タスクが変更されたため取消を実行しませんでした。",
            "任务已结束，强杀未执行":"タスクは終了済みのため強制終了しませんでした。",
            "当前没有可取消的任务":"取消できるタスクがありません。",
            "关闭":"閉じる",
            "无法取得 Restore 独占锁，已阻止启动以避免并发冲突。":"Restore の排他ロックを取得できないため、競合を避けるため起動を中止しました。","当前已有 Restore 任务正在运行，请先完成当前任务。":"別の Restore タスクが実行中です。先に完了してください。",
            "请求发送中":"送信中","请求已发送 · 结果未确认":"送信済み・結果未確認","未发送/失败":"未送信／失敗",
            "读取的 USB 产品名":"読み取った USB 製品名","自定义校准":"カスタム校正",
            "实际采用：自定义校准（controller + PortNumber）":"使用中：カスタム校正（controller + PortNumber）",
            "进入 DFU": "DFU に入る", "重启设备": "デバイスを再起動", "恢复模式": "リカバリ", "Helper 不可用": "Helper を利用できません",
            "设备控制调用不可用":"デバイス制御の呼び出しは利用できません",
            "USB location + controller/PortNumber/RID 精确校准一致":"USB location + controller/PortNumber/RID が正確に校正一致",
            "未检测到目标 Mac":"対象 Mac は未検出",
            "当前未检测到目标设备":"現在、対象デバイスは未検出",
            "当前没有目标设备":"現在対象デバイスはありません",
            "当前观察未知":"現在の観測は不明",
            "USB 设备已连接 · 身份待识别":"USB デバイス接続済み · 識別情報待ち",
            "USB 外设，不冒充目标 Mac":"USB 周辺機器であり、対象 Mac として扱いません",
            "当前 Mac 身份证据不足":"現在の Mac 識別証拠が不足しています",
            "端口链路有连接；未枚举到目标设备":"ポートリンクは接続中ですが、対象デバイスは列挙されていません",
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
            "内置校准": "内蔵校正", "实际采用": "使用中", "模型": "モデル",
            "模型库": "モデルライブラリ", "导出所选模型包…": "選択したモデルパックを書き出す…",
            "没有可导出的模型布局。": "書き出せるモデルレイアウトがありません。"
        ],
        "ko": [
            "当前版本不会启动第二个任务":"이 버전은 두 번째 작업을 시작하지 않습니다.",
            "状态已变化，需重新核验后才能使用。":"상태가 변경되었습니다. 사용 전에 다시 확인하세요.",
            "兼容性未确认，需人工核验后才能使用。":"호환성이 확인되지 않았습니다. 사용 전에 수동 확인이 필요합니다.",
            "取消 A 的 Restore…":"A의 Restore 취소…",
            "目标设备已变化，未载入草稿。":"대상 장치가 변경되어 초안을 불러오지 않았습니다.",
            "草稿已保存；需重新核验后再启动。":"초안이 저장되었습니다. 시작 전에 다시 확인하세요.",
            "第二台设备 · 固件准备":"두 번째 장치 · 펌웨어 준비",
            "A 正在 Restore":"A Restore 진행 중",
            "为 B 选择的固件只保存为草稿；当前版本仅支持一个活动任务，不会启动、排队或自动开始。":"B용으로 선택한 펌웨어는 초안으로만 저장됩니다. 이 버전은 하나의 활성 작업만 지원하며 시작·대기·자동 시작하지 않습니다.",
            "B 的设备身份":"B 장치 정보",
            "B 的固件草稿":"B 펌웨어 초안",
            "为 B 选择 IPSW…":"B용 IPSW 선택…",
            "清除草稿":"초안 지우기",
            "启动状态":"시작 상태",
            "开始 Restore（当前仅支持一个活动任务）":"Restore 시작 (활성 작업 하나만)",
            "A 结束后，请重新核验 B 的设备与固件，再使用原有确认流程手动启动。":"A 종료 후 B의 장치와 펌웨어를 다시 확인한 뒤 기존 확인 절차로 수동 시작하세요.",
            "固件准备完成，等待当前 Restore 结束。":"펌웨어 준비 완료. 현재 Restore 종료를 기다리는 중입니다.",
            "设备连接已变化，需重新核验后才能使用。":"장치 연결이 변경되었습니다. 사용 전에 다시 확인하세요.",
            "当前未检测到可靠设备身份，不能确认固件归属。":"신뢰할 수 있는 장치 정보가 없습니다. 펌웨어 귀속을 확인할 수 없습니다.",
            "该草稿属于另一台设备，不可用于当前设备。":"이 초안은 다른 장치의 것입니다. 현재 장치에 사용할 수 없습니다.",
            "设备连接代际已变化，需重新核验。":"장치 연결 세대가 변경되었습니다. 다시 확인하세요.",
            "固件文件已被替换或移动，需重新选择。":"펌웨어 파일이 교체되었거나 이동되었습니다. 다시 선택하세요.",
            "固件未通过验证，不能用于启动。":"펌웨어가 검증을 통과하지 못해 시작할 수 없습니다.",
            "端口归属不唯一，不能自动绑定该草稿。":"포트 귀속이 유일하지 않아 초안을 자동으로 연결할 수 없습니다.",
            "还没有为这台设备准备固件。":"이 장치용 펌웨어가 아직 준비되지 않았습니다.",
            "已保存的 B 固件草稿":"저장된 B 펌웨어 초안",
            "重新核验并载入":"다시 확인 후 불러오기",
            "固件草稿已保存，等待当前 Restore 结束后再核验启动。":"펌웨어 초안을 저장했습니다. 현재 Restore 종료 후 다시 확인하고 시작하세요.",
            "无法读取该 IPSW 的固件信息；草稿未保存。":"이 IPSW의 펌웨어 정보를 읽을 수 없습니다. 초안이 저장되지 않았습니다.",
            "固件未通过验证；草稿已保留，但不能直接用于启动。":"펌웨어가 검증을 통과하지 못했습니다. 초안은 보관되지만 시작에 사용할 수 없습니다.",
            "固件与当前设备不兼容；草稿已保留，但不能直接用于启动。":"펌웨어가 현재 장치와 호환되지 않습니다. 초안은 보관되지만 시작에 사용할 수 없습니다.",
            "未知端口":"알 수 없는 포트",
            "查看端口当前不可用":"보는 포트를 사용할 수 없음",
            "该端口已不在当前设备列表中；此处不显示该端口的设备详情。":"이 포트는 현재 장치 목록에 없습니다. 여기서는 이 포트의 정보를 표시하지 않습니다.",
            "未记录":"기록 없음",
            "Restore 任务总览":"Restore 작업 개요",
            "项活动":"개",
            "单任务模式":"단일 작업 모드",
            "正在查看":"보는 중",
            "查看任务":"작업 보기",
            "当前没有活动 Restore":"진행 중인 Restore 없음",
            "本阶段":"이번 단계",
            "整体未知":"전체 알 수 없음",
            "完成":"완료",
            "失败":"실패",
            "Restore 成功":"Restore 성공",
            "Restore 失败":"Restore 실패",
            "Restore 已取消":"Restore 취소됨",
            "已取消":"취소됨",
            "结果未知":"결과 알 수 없음",
            "取消处理中":"취소 처리 중",
            "准备中":"준비 중",
            "执行中":"실행 중",
            "结束处理中":"종료 처리 중",
            "上一项任务":"이전 작업",
            "端口历史":"포트 기록",
            "本口最近任务":"이 포트 최근 작업",
            "查看历史":"기록 보기",
            "收起历史":"기록 접기",
            "固件":"펌웨어",
            "结果":"결과",
            "退出":"종료 코드",
            "原始日志":"원본 로그",
            "完成时间":"완료 시각",
            "尝试":"시도",
            "历史任务不可取消、不可擦除；仅用于核对。":"기록 작업은 취소·삭제할 수 없습니다. 확인용입니다.",
            "端口归属待确认，未显示历史":"포트 귀속이 확인되지 않아 기록을 표시하지 않습니다.",
            "物理控制":"물리 제어",
            "返回控制端口":"제어 포트로 돌아가기",
            "任务已变化，取消未执行":"작업이 변경되어 취소하지 않았습니다.",
            "任务已结束，强杀未执行":"작업이 종료되어 강제 종료하지 않았습니다.",
            "当前没有可取消的任务":"취소할 작업이 없습니다.",
            "关闭":"닫기",
            "无法取得 Restore 独占锁，已阻止启动以避免并发冲突。":"Restore 전용 잠금을 확보할 수 없어 동시 충돌을 피하기 위해 시작을 차단했습니다.","当前已有 Restore 任务正在运行，请先完成当前任务。":"이미 다른 Restore 작업이 실행 중입니다. 먼저 완료하세요.",
            "请求发送中":"전송 중","请求已发送 · 结果未确认":"전송됨 · 결과 미확인","未发送/失败":"전송 안 됨/실패",
            "读取的 USB 产品名":"읽은 USB 제품 이름","自定义校准":"사용자 보정",
            "实际采用：自定义校准（controller + PortNumber）":"사용 중: 사용자 보정(controller + PortNumber)",
            "进入 DFU": "DFU 진입", "重启设备": "기기 재시작", "恢复模式": "복구 모드", "Helper 不可用": "Helper 사용 불가",
            "设备控制调用不可用":"기기 제어 호출 사용 불가",
            "USB location + controller/PortNumber/RID 精确校准一致":"USB location + controller/PortNumber/RID 정확히 보정 일치",
            "未检测到目标 Mac":"대상 Mac가 감지되지 않음",
            "当前未检测到目标设备":"현재 대상 기기가 감지되지 않음",
            "当前没有目标设备":"현재 대상 기기 없음",
            "当前观察未知":"현재 관찰 상태 알 수 없음",
            "USB 设备已连接 · 身份待识别":"USB 기기 연결됨 · ID 확인 대기",
            "USB 外设，不冒充目标 Mac":"USB 주변기기이며 대상 Mac로 표시하지 않음",
            "当前 Mac 身份证据不足":"현재 Mac ID 증거 부족",
            "端口链路有连接；未枚举到目标设备":"포트 링크는 연결되어 있지만 대상 기기가 열거되지 않음",
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
            "内置校准": "내장 보정", "实际采用": "사용 중", "模型": "모델",
            "模型库": "모델 라이브러리", "导出所选模型包…": "선택한 모델 팩 내보내기…",
            "没有可导出的模型布局。": "내보낼 수 있는 모델 레이아웃이 없습니다."
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
            "恢复模式：向点击时选定的同一主机端口发送 5 次普通重启（0/3/6/9/12 秒，15 秒窗口）；不调用 reboot serial/DVEn。":"Recovery: send five ordinary restarts to the same selected host port (0/3/6/9/12 s, 15 s window). No reboot serial/DVEn."
        ],
        "zh-Hant": ["本机型直接匹配":"本機型直接匹配","主机校准：本机型直接匹配":"主機校準：本機型直接匹配","内置主机校准":"內建主機校準","设备详情":"裝置詳情","端口详情":"連接埠詳情",
            "设备控制与日志采集 · 先看清端口和设备，再采集日志；刷机仍用 Apple Configurator。":"裝置控制與日誌擷取 · 先確認連接埠和裝置，再擷取日誌；刷機仍使用 Apple Configurator。",
            "恢复模式：向点击时选定的同一主机端口发送 5 次普通重启（0/3/6/9/12 秒，15 秒窗口）；不调用 reboot serial/DVEn。":"恢復模式：向點擊時選定的同一主機連接埠發送 5 次一般重新啟動（0/3/6/9/12 秒，15 秒視窗）；不呼叫 reboot serial/DVEn。"],
        "ja": ["本机型直接匹配":"機種直接一致","主机校准：本机型直接匹配":"ホスト校正：機種直接一致","内置主机校准":"内蔵ホスト校正","设备详情":"デバイス詳細","端口详情":"ポート詳細",
            "设备控制与日志采集 · 先看清端口和设备，再采集日志；刷机仍用 Apple Configurator。":"デバイス制御とログ収集 · 先にポートとデバイスを確認し、復元は Apple Configurator を使用します。",
            "恢复模式：向点击时选定的同一主机端口发送 5 次普通重启（0/3/6/9/12 秒，15 秒窗口）；不调用 reboot serial/DVEn。":"リカバリ：選択した同じホストポートへ 5 回の通常再起動を送信します（0/3/6/9/12 秒、15 秒間）。reboot serial/DVEn は使用しません。"],
        "ko": ["本机型直接匹配":"기종 직접 일치","主机校准：本机型直接匹配":"호스트 보정: 기종 직접 일치","内置主机校准":"내장 호스트 보정","设备详情":"기기 세부 정보","端口详情":"포트 세부 정보",
            "设备控制与日志采集 · 先看清端口和设备，再采集日志；刷机仍用 Apple Configurator。":"기기 제어 및 로그 수집 · 포트와 기기를 먼저 확인하고 복원은 Apple Configurator를 사용하세요.",
            "恢复模式：向点击时选定的同一主机端口发送 5 次普通重启（0/3/6/9/12 秒，15 秒窗口）；不调用 reboot serial/DVEn。":"복구 모드: 선택한 동일 호스트 포트로 일반 재시작을 5회 전송합니다(0/3/6/9/12초, 15초 동안). reboot serial/DVEn은 사용하지 않습니다."]
    ]

    private static let batch7: [String: [String: String]] = [
        "en": ["生效记录：":"Active record: ", "打开独立校准工具 Hardware Preview B.1（\(CalibrationToolLauncher.expectedVersion)）编辑布局并自行校准。本页不再用简化 RID 表代替该工具。导入模型包来自 v2 整合能力，不是 B.1 成品里已有的导入按钮。":"Open the standalone Hardware Preview B.1 (\(CalibrationToolLauncher.expectedVersion)) tool to edit and calibrate the layout. This page no longer substitutes a simplified RID table for that tool. Model-pack import is a v2 capability, not an existing B.1 button."],
        "zh-Hant": ["生效记录：":"生效記錄：", "打开独立校准工具 Hardware Preview B.1（\(CalibrationToolLauncher.expectedVersion)）编辑布局并自行校准。本页不再用简化 RID 表代替该工具。导入模型包来自 v2 整合能力，不是 B.1 成品里已有的导入按钮。":"開啟獨立校準工具 Hardware Preview B.1（\(CalibrationToolLauncher.expectedVersion)）編輯版面並自行校準。本頁不再以簡化 RID 表取代該工具。匯入模型包來自 v2 整合能力，不是 B.1 成品既有的匯入按鈕。"],
        "ja": ["生效记录：":"有効な記録：", "打开独立校准工具 Hardware Preview B.1（\(CalibrationToolLauncher.expectedVersion)）编辑布局并自行校准。本页不再用简化 RID 表代替该工具。导入模型包来自 v2 整合能力，不是 B.1 成品里已有的导入按钮。":"独立校正ツール Hardware Preview B.1（\(CalibrationToolLauncher.expectedVersion)）でレイアウトを編集し校正します。このページでは簡易 RID 表で代用しません。モデルパックの読み込みは v2 の機能で、B.1 既存のボタンではありません。"],
        "ko": ["生效记录：":"적용 기록: ", "打开独立校准工具 Hardware Preview B.1（\(CalibrationToolLauncher.expectedVersion)）编辑布局并自行校准。本页不再用简化 RID 表代替该工具。导入模型包来自 v2 整合能力，不是 B.1 成品里已有的导入按钮。":"독립 보정 도구 Hardware Preview B.1(\(CalibrationToolLauncher.expectedVersion))에서 레이아웃을 편집하고 보정하세요. 이 페이지는 더 이상 단순화된 RID 표로 해당 도구를 대체하지 않습니다. 모델 팩 가져오기는 v2 기능이며 B.1의 기존 버튼이 아닙니다."]
    ]

    private static let batch8: [String: [String: String]] = [
        "en": [
            "日志抓取":"Log Capture", "自动监控 Restore 开始":"Monitor restore start automatically",
            "采集中 · 监听已暂停":"Capturing · monitoring paused",
            "监听中 · 等待 Configurator Restore":"Monitoring · waiting for Configurator restore",
            "监听中 · ":"Monitoring · ",
            "自动监控已开启，但当前未监听":"Automatic monitoring is enabled but not currently listening",
            "未监听 · 手动采集仍可用":"Not monitoring · manual capture remains available",
            "日志是 Apple Configurator / DeviceService 的系统采集范围，可能包含多台设备；当前左侧设备选择不决定日志归属。":"Logs cover Apple Configurator / DeviceService system activity and may include multiple devices. The selected device does not determine log ownership.",
            "停止采集":"Stop Capture", "开始采集":"Start Capture",
            "本次采集时长":"Capture duration", "当前日志大小":"Current log size", "已采集行数":"Captured lines",
            "尚无日志内容":"No log content yet", "搜索没有匹配项":"No matching preview lines",
            "预览已截取末尾；采集和保存始终使用完整原始日志。":"Showing the end of the preview only; capture and saving always use the complete raw log.",
            "实时日志预览":"Live Log Preview", "最多":"Up to", "行 · 完整原始日志不受影响":"lines · complete raw log is unaffected",
            "搜索":"Search", "自动滚动":"Auto-scroll", "继续预览":"Resume Preview", "暂停预览":"Pause Preview", "复制预览":"Copy Preview",
            "历史日志分析":"Historical Log Analysis", "导入历史 .log…":"Import Historical .log…", "打开诊断报告":"Open Diagnostic Report",
            "原始":"Raw", "行数":"Lines", "终态":"Terminal state", "保留":"Kept", "丢弃":"Dropped",
            "文件名":"File Name", "默认文件名":"Default File Name", "取消导出":"Cancel Export",
            "原始日志：":"Raw log: ", "证据包：":"Evidence package: ",
            "保存原始日志":"Save Raw Log", "丢弃本次日志":"Discard This Log",
            "导出 .log…":"Export .log…", "打开日志位置":"Open Log Location",
            "导出本次证据包":"Export This Evidence Package", "证据包另存为…":"Save Evidence Package As…",
            "打开证据包位置":"Open Evidence Package Location",
            "日志与导出设置":"Log & Export Settings", "原始日志默认目录":"Default Raw Log Folder",
            "证据包默认目录":"Default Evidence Package Folder", "预览行数":"Preview lines",
            "证据包包含 timeline.json":"Include timeline.json in the evidence package",
            "证据包包含 diagnostic_summary.md":"Include diagnostic_summary.md in the evidence package",
            "证据包包含实际捕获的 updater output":"Include captured updater output in the evidence package",
            "启用预览过滤（仅预览，不改原始日志）":"Enable preview filtering (preview only; raw log unchanged)",
            "范围":"Scope", "选择…":"Choose…", "显示":"Reveal",
            "选择历史原始日志进行只读分析":"Choose a historical raw log for read-only analysis",
            "选择原始日志默认目录":"Choose the default raw log folder",
            "选择证据包默认目录":"Choose the default evidence package folder", "分析":"Analyze", "选择":"Choose", "导出":"Export",
            "原始日志导出":"Raw Log Export", "证据包导出":"Evidence Package Export",
            "取消":"Cancel", "当前阶段工作量无法可靠计算":"Work remaining in this stage cannot be measured reliably",
            "秒":"s", "复制日志路径":"Copy Log Path", "复制证据包路径":"Copy Evidence Package Path",
            "准备导出":"Preparing export", "校验原始日志":"Validating raw log", "复制原始日志":"Copying raw log",
            "生成诊断附件":"Generating diagnostic attachments", "生成哈希与元数据":"Generating hashes and metadata",
            "封装 ZIP":"Packaging ZIP", "验证 ZIP":"Verifying ZIP", "发布文件":"Publishing file",
            "完成":"Complete", "失败":"Failed", "已取消":"Cancelled",
            "离线模拟采集":"Offline simulated capture", "真实日志采集":"Live log capture",
            "正在启动采集":"Starting capture", "正在停止":"Stopping", "已停止，等待保存":"Stopped · waiting to save",
            "已保存并校验":"Saved and verified", "已保存（部分证据）":"Saved (partial evidence)",
            "采集被中断":"Capture interrupted", "采集失败":"Capture failed",
            "采集已停止。请选择保存原始日志或丢弃；证据包必须另行明确导出。":"Capture stopped. Save the raw log or discard it; the evidence package must be exported separately.",
            "导出已取消；原始日志保留。":"Export cancelled; the raw log was preserved.",
            "证据包已生成并校验。":"Evidence package generated and verified.",
            "磁盘空间不足；原始日志保留，可重试。":"Insufficient disk space; the raw log was preserved and the export can be retried.",
            "监听启动失败：":"Monitoring failed to start: ", "监听失败：":"Monitoring failed: ",
            "手动采集仍可用。":"Manual capture remains available.",
            "检测到 Restore，但当前已有采集会话；未重复启动。":"Restore was detected, but a capture session is already active; no duplicate session was started.",
            "采集中（离线模拟）":"Capturing (offline simulation)", "采集中（真实日志）":"Capturing (live log)",
            "未导入":"Not imported", "分析中":"Analyzing", "分析完成":"Analysis complete", "分析失败":"Analysis failed",
            "选择历史日志进行只读分析；不会修改原文件。":"Choose a historical log for read-only analysis; the original file will not be modified.",
            "正在只读分析 ":"Reading for analysis: ", "分析完成。原始日志未被修改。":"Analysis complete. The raw log was not modified.",
            "分析失败：":"Analysis failed: ", "正在导出…":"Exporting…",
            "尚无采集会话":"No capture session yet", "保存失败；采集会话仍保留，可重试。":"Save failed; the capture session is retained and can be retried.",
            "证据包和原始日志均已保存。":"The evidence package and raw log were both saved.",
            "证据包已保存；原始日志保存失败。":"The evidence package was saved; raw log saving failed.",
            "原始日志已保存；证据包保存失败。":"The raw log was saved; evidence package saving failed."
        ],
        "zh-Hant": [
            "日志抓取":"日誌擷取", "自动监控 Restore 开始":"自動監控 Restore 開始",
            "采集中 · 监听已暂停":"擷取中 · 監聽已暫停",
            "监听中 · 等待 Configurator Restore":"監聽中 · 等待 Configurator Restore",
            "监听中 · ":"監聽中 · ",
            "自动监控已开启，但当前未监听":"已開啟自動監控，但目前未監聽",
            "未监听 · 手动采集仍可用":"未監聽 · 仍可手動擷取",
            "日志是 Apple Configurator / DeviceService 的系统采集范围，可能包含多台设备；当前左侧设备选择不决定日志归属。":"日誌涵蓋 Apple Configurator / DeviceService 的系統活動，可能包含多台裝置；左側目前選取的裝置不代表日誌都屬於該裝置。",
            "停止采集":"停止擷取", "开始采集":"開始擷取",
            "本次采集时长":"本次擷取時間", "当前日志大小":"目前日誌大小", "已采集行数":"已擷取行數",
            "尚无日志内容":"尚無日誌內容", "搜索没有匹配项":"搜尋沒有符合項目",
            "预览已截取末尾；采集和保存始终使用完整原始日志。":"預覽僅顯示末尾；擷取與儲存一律使用完整原始日誌。",
            "实时日志预览":"即時日誌預覽", "最多":"最多", "行 · 完整原始日志不受影响":"行 · 完整原始日誌不受影響",
            "搜索":"搜尋", "自动滚动":"自動捲動", "继续预览":"繼續預覽", "暂停预览":"暫停預覽", "复制预览":"複製預覽",
            "历史日志分析":"歷史日誌分析", "导入历史 .log…":"匯入歷史 .log…", "打开诊断报告":"開啟診斷報告",
            "原始":"原始", "行数":"行數", "终态":"終態", "保留":"保留", "丢弃":"捨棄",
            "文件名":"檔名", "默认文件名":"預設檔名", "取消导出":"取消匯出",
            "原始日志：":"原始日誌：", "证据包：":"證據包：",
            "保存原始日志":"儲存原始日誌", "丢弃本次日志":"捨棄本次日誌",
            "导出 .log…":"匯出 .log…", "打开日志位置":"開啟日誌位置",
            "导出本次证据包":"匯出本次證據包", "证据包另存为…":"證據包另存為…",
            "打开证据包位置":"開啟證據包位置",
            "日志与导出设置":"日誌與匯出設定", "原始日志默认目录":"原始日誌預設目錄",
            "证据包默认目录":"證據包預設目錄", "预览行数":"預覽行數",
            "证据包包含 timeline.json":"證據包包含 timeline.json",
            "证据包包含 diagnostic_summary.md":"證據包包含 diagnostic_summary.md",
            "证据包包含实际捕获的 updater output":"證據包包含實際擷取的 updater output",
            "启用预览过滤（仅预览，不改原始日志）":"啟用預覽篩選（僅影響預覽，不修改原始日誌）",
            "范围":"範圍", "选择…":"選擇…", "显示":"顯示",
            "选择历史原始日志进行只读分析":"選擇歷史原始日誌進行唯讀分析",
            "选择原始日志默认目录":"選擇原始日誌預設目錄",
            "选择证据包默认目录":"選擇證據包預設目錄", "分析":"分析", "选择":"選擇", "导出":"匯出",
            "原始日志导出":"原始日誌匯出", "证据包导出":"證據包匯出",
            "取消":"取消", "当前阶段工作量无法可靠计算":"目前階段的工作量無法可靠計算",
            "秒":"秒", "复制日志路径":"複製日誌路徑", "复制证据包路径":"複製證據包路徑",
            "准备导出":"準備匯出", "校验原始日志":"驗證原始日誌", "复制原始日志":"複製原始日誌",
            "生成诊断附件":"產生診斷附件", "生成哈希与元数据":"產生雜湊與中繼資料",
            "封装 ZIP":"封裝 ZIP", "验证 ZIP":"驗證 ZIP", "发布文件":"發佈檔案",
            "完成":"完成", "失败":"失敗", "已取消":"已取消",
            "离线模拟采集":"離線模擬擷取", "真实日志采集":"真實日誌擷取",
            "正在启动采集":"正在啟動擷取", "正在停止":"正在停止", "已停止，等待保存":"已停止，等待儲存",
            "已保存并校验":"已儲存並驗證", "已保存（部分证据）":"已儲存（部分證據）",
            "采集被中断":"擷取被中斷", "采集失败":"擷取失敗",
            "采集已停止。请选择保存原始日志或丢弃；证据包必须另行明确导出。":"擷取已停止。請選擇儲存原始日誌或捨棄；證據包必須另行明確匯出。",
            "导出已取消；原始日志保留。":"匯出已取消；原始日誌已保留。",
            "证据包已生成并校验。":"證據包已產生並驗證。",
            "磁盘空间不足；原始日志保留，可重试。":"磁碟空間不足；原始日誌已保留，可重試。",
            "监听启动失败：":"監聽啟動失敗：", "监听失败：":"監聽失敗：",
            "手动采集仍可用。":"仍可手動擷取。",
            "检测到 Restore，但当前已有采集会话；未重复启动。":"偵測到 Restore，但目前已有擷取工作階段；未重複啟動。",
            "采集中（离线模拟）":"擷取中（離線模擬）", "采集中（真实日志）":"擷取中（真實日誌）",
            "未导入":"未匯入", "分析中":"分析中", "分析完成":"分析完成", "分析失败":"分析失敗",
            "选择历史日志进行只读分析；不会修改原文件。":"選擇歷史日誌進行唯讀分析；不會修改原始檔案。",
            "正在只读分析 ":"正在唯讀分析 ", "分析完成。原始日志未被修改。":"分析完成。原始日誌未被修改。",
            "分析失败：":"分析失敗：", "正在导出…":"正在匯出…",
            "尚无采集会话":"尚無擷取工作階段", "保存失败；采集会话仍保留，可重试。":"儲存失敗；擷取工作階段仍保留，可重試。",
            "证据包和原始日志均已保存。":"證據包和原始日誌均已儲存。",
            "证据包已保存；原始日志保存失败。":"證據包已儲存；原始日誌儲存失敗。",
            "原始日志已保存；证据包保存失败。":"原始日誌已儲存；證據包儲存失敗。"
        ],
        "ja": [
            "日志抓取":"ログ収集", "自动监控 Restore 开始":"Restore 開始を自動監視",
            "采集中 · 监听已暂停":"収集中 · 監視一時停止",
            "监听中 · 等待 Configurator Restore":"監視中 · Configurator Restore を待機",
            "监听中 · ":"監視中 · ",
            "自动监控已开启，但当前未监听":"自動監視は有効ですが、現在は監視していません",
            "未监听 · 手动采集仍可用":"未監視 · 手動収集は利用可能",
            "日志是 Apple Configurator / DeviceService 的系统采集范围，可能包含多台设备；当前左侧设备选择不决定日志归属。":"ログは Apple Configurator / DeviceService のシステム活動を対象とし、複数のデバイスを含む場合があります。左側の選択デバイスがログの所有先を示すものではありません。",
            "停止采集":"収集を停止", "开始采集":"収集を開始",
            "本次采集时长":"今回の収集時間", "当前日志大小":"現在のログサイズ", "已采集行数":"収集済み行数",
            "尚无日志内容":"ログ内容はまだありません", "搜索没有匹配项":"一致するプレビュー行はありません",
            "预览已截取末尾；采集和保存始终使用完整原始日志。":"プレビューは末尾のみ表示します。収集と保存では常に完全な元ログを使用します。",
            "实时日志预览":"リアルタイムログプレビュー", "最多":"最大", "行 · 完整原始日志不受影响":"行 · 完全な元ログには影響しません",
            "搜索":"検索", "自动滚动":"自動スクロール", "继续预览":"プレビュー再開", "暂停预览":"プレビュー一時停止", "复制预览":"プレビューをコピー",
            "历史日志分析":"履歴ログ分析", "导入历史 .log…":"履歴 .log を読み込む…", "打开诊断报告":"診断レポートを開く",
            "原始":"元ログ", "行数":"行数", "终态":"終了状態", "保留":"保持", "丢弃":"除外",
            "文件名":"ファイル名", "默认文件名":"既定のファイル名", "取消导出":"エクスポートをキャンセル",
            "原始日志：":"元ログ：", "证据包：":"証拠パッケージ：",
            "保存原始日志":"元ログを保存", "丢弃本次日志":"今回のログを破棄",
            "导出 .log…":".log をエクスポート…", "打开日志位置":"ログの場所を開く",
            "导出本次证据包":"今回の証拠パッケージをエクスポート", "证据包另存为…":"証拠パッケージを別名保存…",
            "打开证据包位置":"証拠パッケージの場所を開く",
            "日志与导出设置":"ログとエクスポート設定", "原始日志默认目录":"元ログの既定フォルダ",
            "证据包默认目录":"証拠パッケージの既定フォルダ", "预览行数":"プレビュー行数",
            "证据包包含 timeline.json":"証拠パッケージに timeline.json を含める",
            "证据包包含 diagnostic_summary.md":"証拠パッケージに diagnostic_summary.md を含める",
            "证据包包含实际捕获的 updater output":"証拠パッケージに実際に収集した updater output を含める",
            "启用预览过滤（仅预览，不改原始日志）":"プレビューフィルターを有効化（プレビューのみ、元ログは変更しません）",
            "范围":"範囲", "选择…":"選択…", "显示":"表示",
            "选择历史原始日志进行只读分析":"読み取り専用分析に使用する履歴元ログを選択",
            "选择原始日志默认目录":"元ログの既定フォルダを選択",
            "选择证据包默认目录":"証拠パッケージの既定フォルダを選択", "分析":"分析", "选择":"選択", "导出":"エクスポート",
            "原始日志导出":"元ログのエクスポート", "证据包导出":"証拠パッケージのエクスポート",
            "取消":"キャンセル", "当前阶段工作量无法可靠计算":"この段階の残り作業量は正確に算出できません",
            "秒":"秒", "复制日志路径":"ログパスをコピー", "复制证据包路径":"証拠パッケージのパスをコピー",
            "准备导出":"エクスポートを準備中", "校验原始日志":"元ログを検証中", "复制原始日志":"元ログをコピー中",
            "生成诊断附件":"診断添付ファイルを生成中", "生成哈希与元数据":"ハッシュとメタデータを生成中",
            "封装 ZIP":"ZIP をパッケージ中", "验证 ZIP":"ZIP を検証中", "发布文件":"ファイルを公開中",
            "完成":"完了", "失败":"失敗", "已取消":"キャンセル済み",
            "离线模拟采集":"オフライン模擬収集", "真实日志采集":"実ログ収集",
            "正在启动采集":"収集を開始中", "正在停止":"停止中", "已停止，等待保存":"停止済み · 保存待ち",
            "已保存并校验":"保存・検証済み", "已保存（部分证据）":"保存済み（部分証拠）",
            "采集被中断":"収集が中断されました", "采集失败":"収集に失敗しました",
            "采集已停止。请选择保存原始日志或丢弃；证据包必须另行明确导出。":"収集を停止しました。元ログを保存するか破棄してください。証拠パッケージは別途明示的にエクスポートする必要があります。",
            "导出已取消；原始日志保留。":"エクスポートをキャンセルしました。元ログは保持されています。",
            "证据包已生成并校验。":"証拠パッケージを生成し、検証しました。",
            "磁盘空间不足；原始日志保留，可重试。":"ディスク容量が不足しています。元ログは保持されており、再試行できます。",
            "监听启动失败：":"監視の開始に失敗：", "监听失败：":"監視に失敗：",
            "手动采集仍可用。":"手動収集は引き続き利用できます。",
            "检测到 Restore，但当前已有采集会话；未重复启动。":"Restore を検出しましたが、収集セッションが既にあります。重複して開始しませんでした。",
            "采集中（离线模拟）":"収集中（オフライン模擬）", "采集中（真实日志）":"収集中（実ログ）",
            "未导入":"未読み込み", "分析中":"分析中", "分析完成":"分析完了", "分析失败":"分析失敗",
            "选择历史日志进行只读分析；不会修改原文件。":"履歴ログを選択して読み取り専用分析を行います。元ファイルは変更しません。",
            "正在只读分析 ":"読み取り専用で分析中: ", "分析完成。原始日志未被修改。":"分析完了。元ログは変更されていません。",
            "分析失败：":"分析失敗：", "正在导出…":"エクスポート中…",
            "尚无采集会话":"収集セッションはまだありません", "保存失败；采集会话仍保留，可重试。":"保存に失敗しました。収集セッションは保持されており、再試行できます。",
            "证据包和原始日志均已保存。":"証拠パッケージと元ログを保存しました。",
            "证据包已保存；原始日志保存失败。":"証拠パッケージは保存されましたが、元ログの保存に失敗しました。",
            "原始日志已保存；证据包保存失败。":"元ログは保存されましたが、証拠パッケージの保存に失敗しました。"
        ],
        "ko": [
            "日志抓取":"로그 캡처", "自动监控 Restore 开始":"Restore 시작 자동 모니터링",
            "采集中 · 监听已暂停":"캡처 중 · 모니터링 일시 중지",
            "监听中 · 等待 Configurator Restore":"모니터링 중 · Configurator Restore 대기",
            "监听中 · ":"모니터링 중 · ",
            "自动监控已开启，但当前未监听":"자동 모니터링이 켜져 있지만 현재 수신 중이 아닙니다",
            "未监听 · 手动采集仍可用":"모니터링 안 함 · 수동 캡처 사용 가능",
            "日志是 Apple Configurator / DeviceService 的系统采集范围，可能包含多台设备；当前左侧设备选择不决定日志归属。":"로그는 Apple Configurator / DeviceService 시스템 활동을 포함하며 여러 기기의 로그가 섞일 수 있습니다. 왼쪽에서 선택한 기기가 로그 소유자를 의미하지는 않습니다.",
            "停止采集":"캡처 중지", "开始采集":"캡처 시작",
            "本次采集时长":"캡처 시간", "当前日志大小":"현재 로그 크기", "已采集行数":"캡처된 줄",
            "尚无日志内容":"아직 로그 내용이 없습니다", "搜索没有匹配项":"일치하는 미리보기 줄이 없습니다",
            "预览已截取末尾；采集和保存始终使用完整原始日志。":"미리보기는 끝부분만 표시합니다. 캡처와 저장에는 항상 전체 원본 로그를 사용합니다.",
            "实时日志预览":"실시간 로그 미리보기", "最多":"최대", "行 · 完整原始日志不受影响":"줄 · 전체 원본 로그에는 영향 없음",
            "搜索":"검색", "自动滚动":"자동 스크롤", "继续预览":"미리보기 재개", "暂停预览":"미리보기 일시 중지", "复制预览":"미리보기 복사",
            "历史日志分析":"기록 로그 분석", "导入历史 .log…":"기록 .log 가져오기…", "打开诊断报告":"진단 보고서 열기",
            "原始":"원본", "行数":"줄 수", "终态":"종료 상태", "保留":"유지", "丢弃":"제외",
            "文件名":"파일 이름", "默认文件名":"기본 파일 이름", "取消导出":"내보내기 취소",
            "原始日志：":"원본 로그: ", "证据包：":"증거 패키지: ",
            "保存原始日志":"원본 로그 저장", "丢弃本次日志":"이번 로그 폐기",
            "导出 .log…":".log 내보내기…", "打开日志位置":"로그 위치 열기",
            "导出本次证据包":"이번 증거 패키지 내보내기", "证据包另存为…":"증거 패키지 다른 이름으로 저장…",
            "打开证据包位置":"증거 패키지 위치 열기",
            "日志与导出设置":"로그 및 내보내기 설정", "原始日志默认目录":"기본 원본 로그 폴더",
            "证据包默认目录":"기본 증거 패키지 폴더", "预览行数":"미리보기 줄 수",
            "证据包包含 timeline.json":"증거 패키지에 timeline.json 포함",
            "证据包包含 diagnostic_summary.md":"증거 패키지에 diagnostic_summary.md 포함",
            "证据包包含实际捕获的 updater output":"증거 패키지에 실제 캡처한 updater output 포함",
            "启用预览过滤（仅预览，不改原始日志）":"미리보기 필터 사용(미리보기에만 적용, 원본 로그는 변경하지 않음)",
            "范围":"범위", "选择…":"선택…", "显示":"보기",
            "选择历史原始日志进行只读分析":"읽기 전용 분석에 사용할 기록 원본 로그 선택",
            "选择原始日志默认目录":"기본 원본 로그 폴더 선택",
            "选择证据包默认目录":"기본 증거 패키지 폴더 선택", "分析":"분석", "选择":"선택", "导出":"내보내기",
            "原始日志导出":"원본 로그 내보내기", "证据包导出":"증거 패키지 내보내기",
            "取消":"취소", "当前阶段工作量无法可靠计算":"현재 단계의 남은 작업량을 정확히 계산할 수 없습니다",
            "秒":"초", "复制日志路径":"로그 경로 복사", "复制证据包路径":"증거 패키지 경로 복사",
            "准备导出":"내보내기 준비 중", "校验原始日志":"원본 로그 검증 중", "复制原始日志":"원본 로그 복사 중",
            "生成诊断附件":"진단 첨부 파일 생성 중", "生成哈希与元数据":"해시 및 메타데이터 생성 중",
            "封装 ZIP":"ZIP 패키징 중", "验证 ZIP":"ZIP 검증 중", "发布文件":"파일 게시 중",
            "完成":"완료", "失败":"실패", "已取消":"취소됨",
            "离线模拟采集":"오프라인 시뮬레이션 캡처", "真实日志采集":"실제 로그 캡처",
            "正在启动采集":"캡처 시작 중", "正在停止":"중지 중", "已停止，等待保存":"중지됨 · 저장 대기",
            "已保存并校验":"저장 및 검증됨", "已保存（部分证据）":"저장됨(부분 증거)",
            "采集被中断":"캡처 중단됨", "采集失败":"캡처 실패",
            "采集已停止。请选择保存原始日志或丢弃；证据包必须另行明确导出。":"캡처가 중지되었습니다. 원본 로그를 저장하거나 폐기하세요. 증거 패키지는 별도로 명시적으로 내보내야 합니다.",
            "导出已取消；原始日志保留。":"내보내기가 취소되었습니다. 원본 로그는 보존됩니다.",
            "证据包已生成并校验。":"증거 패키지가 생성되고 검증되었습니다.",
            "磁盘空间不足；原始日志保留，可重试。":"디스크 공간이 부족합니다. 원본 로그는 보존되며 다시 시도할 수 있습니다.",
            "监听启动失败：":"모니터링 시작 실패: ", "监听失败：":"모니터링 실패: ",
            "手动采集仍可用。":"수동 캡처는 계속 사용할 수 있습니다.",
            "检测到 Restore，但当前已有采集会话；未重复启动。":"Restore가 감지되었지만 이미 캡처 세션이 있어 중복 시작하지 않았습니다.",
            "采集中（离线模拟）":"캡처 중(오프라인 시뮬레이션)", "采集中（真实日志）":"캡처 중(실제 로그)",
            "未导入":"가져오지 않음", "分析中":"분석 중", "分析完成":"분석 완료", "分析失败":"분석 실패",
            "选择历史日志进行只读分析；不会修改原文件。":"기록 로그를 선택하여 읽기 전용 분석을 실행합니다. 원본 파일은 변경하지 않습니다.",
            "正在只读分析 ":"읽기 전용 분석 중: ", "分析完成。原始日志未被修改。":"분석 완료. 원본 로그는 변경되지 않았습니다.",
            "分析失败：":"분석 실패: ", "正在导出…":"내보내는 중…",
            "尚无采集会话":"캡처 세션이 없습니다", "保存失败；采集会话仍保留，可重试。":"저장 실패. 캡처 세션은 유지되며 다시 시도할 수 있습니다.",
            "证据包和原始日志均已保存。":"증거 패키지와 원본 로그를 모두 저장했습니다.",
            "证据包已保存；原始日志保存失败。":"증거 패키지는 저장되었지만 원본 로그 저장에 실패했습니다.",
            "原始日志已保存；证据包保存失败。":"원본 로그는 저장되었지만 증거 패키지 저장에 실패했습니다."
        ]
    ]

    private static let batch9: [String: [String: String]] = [
        "en": [
            "安全深度重置 Configurator":"Safe Configurator deep reset",
            "清理缓存并重启 Configurator":"Clear caches and restart Configurator",
            "退出后只读盘点当前容器和旧路径，只清理精确 Caches；Application Support 默认保留；不暂停 usbd；重新打开后验证置前。":"After quitting, inspect the current container and legacy paths read-only, then clear exact cache targets. Application Support is preserved by default. usbd is not paused. Reopening and foreground activation are verified.",
            "同时处理 Application Support（先保留可恢复副本）":"Also process Application Support (backup first)",
            "默认关闭；关闭时 Application Support 保持不变。":"Off by default. Application Support remains unchanged while this is off.",
            "安全深度重置":"Safe deep reset",
            "清理缓存并重启":"Clear caches and restart",
            "只读盘点":"Read-only inventory",
            "保留数据":"Preserve data",
            "保留 Application Support":"Preserve Application Support",
            "精确清理":"Exact cleanup",
            "备份 Application Support":"Back up Application Support",
            "置前当前窗口":"Bring current window forward",
            "无匹配":"No match",
            "跳过":"Skipped",
            "默认选择安全深度重置；修改设置本身不会执行操作。":"Safe deep reset is selected by default. Changing the setting does not execute it.",
            "A 型号未知":"A model unknown", "年份未知":"Year unknown",
            "A 型号待确认":"A model pending confirmation", "年份待确认":"Year pending confirmation",
            "身份冲突":"Identity conflict", "A/年份未定":"A/year unresolved",
            "当前无身份证据":"No current identity evidence",
            "识别状态":"Identity state", "机型":"Model", "设备类别":"Device category",
            "系列":"Series", "尺寸":"Size", "芯片/SoC":"Chip/SoC", "A 型号":"A model",
            "年份":"Year", "机型标识符":"Model identifier", "iBridge":"iBridge", "T2":"T2",
            "HardwareCode":"HardwareCode", "身份观察":"Identity observation",
            "观察代际":"Observation generation", "识别来源":"Identity source",
            "识别来源：":"Identity source: ",
            "冲突字段":"Conflict fields", "历史提示":"Historical hint",
            "同 ECID 旧记录":"Prior record with same ECID",
            "不参与当前确认":"does not participate in current confirmation",
            "确定（当前明确字段）":"Confirmed (current explicit field)",
            "仅历史提示":"Historical hint only", "笔记本":"Notebook", "台式机":"Desktop",
            "候选":"Candidate", "候选机型":"Candidate models", "冲突候选":"Conflicting candidates",
            "待确认":"Pending confirmation", "资料未收录":"Not in catalog",
            "未读取":"Not read", "唯一匹配":"Unique match", "确定":"Confirmed",
            "物理接口与设备（按证据优先级）":"Physical ports and devices (evidence priority)",
            "归属未证实的线材、伙伴与供电":"Cables, peers, and power without proven ownership",
            "物理归属未证实":"Physical ownership not proven",
            "未检测到 Mac、USB HUB 或外设":"No Mac, USB hub, or peripheral detected",
            "USB 观察已看到设备，但接口树尚无可靠物理归属。":"USB observation sees a device, but the interface tree has no reliable physical-port attribution.",
            "原始 USB 拓扑":"Raw USB topology",
            "以下仅显示系统父子关系，不代表已确认物理接口。":"This only shows system parent/child relationships; physical ports are not confirmed.",
            "Mac 身份：":"Mac identity: ", "类别：":"Category: ", "系列：":"Series: ",
            "尺寸：":"Size: ", "芯片/SoC：":"Chip/SoC: ", "机型标识符：":"Model identifier: ",
            "物理端口待确认":"Physical port pending confirmation",
            "选中端口":"Selected Port", "端口已连接 · 设备身份未读取":"Port connected · device identity not read",
            "Mac 设备已连接 · 身份未知":"Mac device connected · identity unknown",
            "Helper 可用 · 签名授权通过":"Helper available · signature authorization passed",
            "Helper 调用可用 · 安装检测另有提示":"Helper callable · installation check has a separate warning",
            "Helper 已安装 · 调用未授权":"Helper installed · call not authorized",
            "设备控制调用不可用":"Device control call unavailable",
            "Helper 状态未知 · 调用不可用":"Helper state unknown · call unavailable",
            "Helper 检测失败 · 调用不可用":"Helper detection failed · call unavailable",
            "安装与服务检测：":"Installation and service check: ",
            "可用（签名授权与 socket 调用已通过）":"Available (signature authorization and socket call passed)",
            "主界面只读关联：":"Main-window read-only correlation: ",
            "不适用（该节点没有已证实的 USB location）":"Not applicable (no proven USB location for this node)",
            "未找到相同 USB location 的当前观察":"No current observation with the same USB location",
            "发现相同 location，但端口归属不唯一，保持未知":"The same location was found, but port ownership is not unique; keeping it unknown",
            "一致（不改变设备控制目标）":"Match (device control target unchanged)",
            "同端口只读 USB 全景":"Read-only USB panorama for this port",
            "当前没有可用于关联的明确 USB location；不强行分配外设或线材。":"No explicit USB location is available for correlation; peripherals and cables are not assigned.",
            "全景中暂无相同 USB location 的节点；这不代表端口没有设备。":"No panorama node currently shares this USB location; this does not mean the port has no device.",
            "物理归属来自同一当前 location 证据":"Physical ownership comes from the same current location evidence"
        ],
        "zh-Hant": [
            "安全深度重置 Configurator":"安全深度重設 Configurator",
            "清理缓存并重启 Configurator":"清除快取並重新開啟 Configurator",
            "退出后只读盘点当前容器和旧路径，只清理精确 Caches；Application Support 默认保留；不暂停 usbd；重新打开后验证置前。":"結束後先以唯讀方式盤點目前容器與舊路徑，只清除精確的 Caches；Application Support 預設保留；不暫停 usbd；重新開啟後驗證是否置前。",
            "同时处理 Application Support（先保留可恢复副本）":"同時處理 Application Support（先保留可還原副本）",
            "默认关闭；关闭时 Application Support 保持不变。":"預設關閉；關閉時 Application Support 保持不變。",
            "安全深度重置":"安全深度重設",
            "清理缓存并重启":"清除快取並重新開啟",
            "只读盘点":"唯讀盤點",
            "保留数据":"保留資料",
            "保留 Application Support":"保留 Application Support",
            "精确清理":"精確清理",
            "备份 Application Support":"備份 Application Support",
            "置前当前窗口":"將目前視窗置前",
            "无匹配":"無符合項目",
            "跳过":"略過",
            "默认选择安全深度重置；修改设置本身不会执行操作。":"預設選擇安全深度重設；修改設定本身不會執行操作。",
            "A 型号未知":"A 型號未知", "年份未知":"年份未知",
            "A 型号待确认":"A 型號待確認", "年份待确认":"年份待確認",
            "身份冲突":"身分衝突", "A/年份未定":"A／年份未定",
            "当前无身份证据":"目前沒有身分證據",
            "识别状态":"辨識狀態", "机型":"機型", "设备类别":"裝置類別",
            "系列":"系列", "尺寸":"尺寸", "芯片/SoC":"晶片/SoC", "A 型号":"A 型號",
            "年份":"年份", "机型标识符":"機型識別碼", "iBridge":"iBridge", "T2":"T2",
            "HardwareCode":"HardwareCode", "身份观察":"身分觀察",
            "观察代际":"觀察世代", "识别来源":"辨識來源",
            "识别来源：":"辨識來源：",
            "冲突字段":"衝突欄位", "历史提示":"歷史提示",
            "同 ECID 旧记录":"同 ECID 舊記錄",
            "不参与当前确认":"不參與目前確認",
            "确定（当前明确字段）":"確定（目前明確欄位）",
            "仅历史提示":"僅歷史提示", "笔记本":"筆記型電腦", "台式机":"桌上型電腦",
            "候选":"候選", "候选机型":"候選機型", "冲突候选":"衝突候選",
            "待确认":"待確認", "资料未收录":"資料未收錄",
            "未读取":"未讀取", "唯一匹配":"唯一符合", "确定":"確定",
            "物理接口与设备（按证据优先级）":"實體連接埠與裝置（依證據優先順序）",
            "归属未证实的线材、伙伴与供电":"尚未證實歸屬的線材、對端與供電",
            "物理归属未证实":"尚未證實實體歸屬",
            "未检测到 Mac、USB HUB 或外设":"未偵測到 Mac、USB HUB 或周邊裝置",
            "USB 观察已看到设备，但接口树尚无可靠物理归属。":"USB 觀察已看到裝置，但介面樹尚無可靠實體連接埠歸屬。",
            "原始 USB 拓扑":"原始 USB 拓撲",
            "以下仅显示系统父子关系，不代表已确认物理接口。":"以下僅顯示系統父子關係，不代表已確認實體連接埠。",
            "Mac 身份：":"Mac 身分：", "类别：":"類別：", "系列：":"系列：",
            "尺寸：":"尺寸：", "芯片/SoC：":"晶片/SoC：", "机型标识符：":"機型識別碼：",
            "物理端口待确认":"實體連接埠待確認",
            "选中端口":"選取連接埠", "端口已连接 · 设备身份未读取":"連接埠已連接 · 尚未讀取裝置身分",
            "Mac 设备已连接 · 身份未知":"Mac 裝置已連接 · 身分未知",
            "Helper 可用 · 签名授权通过":"Helper 可用 · 簽章授權通過",
            "Helper 调用可用 · 安装检测另有提示":"Helper 呼叫可用 · 安裝檢查另有提示",
            "Helper 已安装 · 调用未授权":"Helper 已安裝 · 呼叫未授權",
            "设备控制调用不可用":"裝置控制呼叫不可用",
            "Helper 状态未知 · 调用不可用":"Helper 狀態未知 · 呼叫不可用",
            "Helper 检测失败 · 调用不可用":"Helper 偵測失敗 · 呼叫不可用",
            "安装与服务检测：":"安裝與服務檢查：",
            "可用（签名授权与 socket 调用已通过）":"可用（簽章授權與 socket 呼叫已通過）",
            "主界面只读关联：":"主畫面唯讀關聯：",
            "不适用（该节点没有已证实的 USB location）":"不適用（此節點沒有已證實的 USB location）",
            "未找到相同 USB location 的当前观察":"找不到相同 USB location 的目前觀察",
            "发现相同 location，但端口归属不唯一，保持未知":"找到相同 location，但連接埠歸屬不唯一，維持未知",
            "一致（不改变设备控制目标）":"一致（不變更裝置控制目標）",
            "同端口只读 USB 全景":"同一連接埠的唯讀 USB 全景",
            "当前没有可用于关联的明确 USB location；不强行分配外设或线材。":"目前沒有可用於關聯的明確 USB location；不會強行分配周邊或線材。",
            "全景中暂无相同 USB location 的节点；这不代表端口没有设备。":"全景目前沒有相同 USB location 的節點；這不代表連接埠沒有裝置。",
            "物理归属来自同一当前 location 证据":"實體歸屬來自相同的目前 location 證據"
        ],
        "ja": [
            "安全深度重置 Configurator":"Configurator 安全リセット",
            "清理缓存并重启 Configurator":"キャッシュを消去して Configurator を再起動",
            "退出后只读盘点当前容器和旧路径，只清理精确 Caches；Application Support 默认保留；不暂停 usbd；重新打开后验证置前。":"終了後に現在のコンテナと旧パスを読み取り専用で確認し、正確な Caches のみを消去します。Application Support は既定で保持し、usbd は停止しません。再起動後の前面表示も確認します。",
            "同时处理 Application Support（先保留可恢复副本）":"Application Support も処理する（先に復元可能なバックアップを作成）",
            "默认关闭；关闭时 Application Support 保持不变。":"既定ではオフです。オフの間、Application Support は変更されません。",
            "安全深度重置":"安全な詳細リセット",
            "清理缓存并重启":"キャッシュ消去と再起動",
            "只读盘点":"読み取り専用の確認",
            "保留数据":"データを保持",
            "保留 Application Support":"Application Support を保持",
            "精确清理":"正確な対象のみ消去",
            "备份 Application Support":"Application Support をバックアップ",
            "置前当前窗口":"現在のウインドウを前面へ",
            "无匹配":"一致なし",
            "跳过":"スキップ",
            "默认选择安全深度重置；修改设置本身不会执行操作。":"安全な詳細リセットが既定です。設定変更だけでは実行されません。",
            "A 型号未知":"A 型番不明", "年份未知":"年不明",
            "A 型号待确认":"A 型番確認待ち", "年份待确认":"年確認待ち",
            "身份冲突":"識別情報の競合", "A/年份未定":"A／年未確定",
            "当前无身份证据":"現在の識別情報なし",
            "识别状态":"識別状態", "机型":"機種", "设备类别":"デバイス分類",
            "系列":"シリーズ", "尺寸":"サイズ", "芯片/SoC":"チップ/SoC", "A 型号":"A 型番",
            "年份":"年", "机型标识符":"機種識別子", "iBridge":"iBridge", "T2":"T2",
            "HardwareCode":"HardwareCode", "身份观察":"識別観測",
            "观察代际":"観測世代", "识别来源":"識別ソース",
            "识别来源：":"識別ソース：",
            "冲突字段":"競合フィールド", "历史提示":"履歴ヒント",
            "同 ECID 旧记录":"同じ ECID の以前の記録",
            "不参与当前确认":"現在の確定には使用しません",
            "确定（当前明确字段）":"確定（現在の明示フィールド）",
            "仅历史提示":"履歴ヒントのみ", "笔记本":"ノートブック", "台式机":"デスクトップ",
            "候选":"候補", "候选机型":"候補機種", "冲突候选":"競合候補",
            "待确认":"確認待ち", "资料未收录":"資料に未収録",
            "未读取":"未取得", "唯一匹配":"一意に一致", "确定":"確定",
            "物理接口与设备（按证据优先级）":"物理ポートとデバイス（証拠の優先順）",
            "归属未证实的线材、伙伴与供电":"物理的な帰属が未確認のケーブル、接続相手、給電",
            "物理归属未证实":"物理的な帰属は未確認",
            "未检测到 Mac、USB HUB 或外设":"Mac、USB HUB、周辺機器を検出していません",
            "USB 观察已看到设备，但接口树尚无可靠物理归属。":"USB 観察ではデバイスを検出していますが、インターフェイスツリーには信頼できる物理ポート帰属がありません。",
            "原始 USB 拓扑":"元の USB トポロジー",
            "以下仅显示系统父子关系，不代表已确认物理接口。":"以下はシステム上の親子関係のみで、物理ポートを確認したものではありません。",
            "Mac 身份：":"Mac 識別：", "类别：":"分類：", "系列：":"シリーズ：",
            "尺寸：":"サイズ：", "芯片/SoC：":"チップ/SoC：", "机型标识符：":"機種識別子：",
            "物理端口待确认":"物理ポート確認待ち",
            "选中端口":"選択ポート", "端口已连接 · 设备身份未读取":"ポート接続済み · デバイス識別情報は未取得",
            "Mac 设备已连接 · 身份未知":"Mac デバイス接続済み · 識別情報不明",
            "Helper 可用 · 签名授权通过":"Helper 利用可能 · 署名認証済み",
            "Helper 调用可用 · 安装检测另有提示":"Helper 呼び出し可能 · インストール検査に別の警告あり",
            "Helper 已安装 · 调用未授权":"Helper インストール済み · 呼び出し未認証",
            "设备控制调用不可用":"デバイス制御の呼び出しは利用できません",
            "Helper 状态未知 · 调用不可用":"Helper 状態不明 · 呼び出し不可",
            "Helper 检测失败 · 调用不可用":"Helper 検出失敗 · 呼び出し不可",
            "安装与服务检测：":"インストールとサービスの検査：",
            "可用（签名授权与 socket 调用已通过）":"利用可能（署名認証と socket 呼び出しに成功）",
            "主界面只读关联：":"メイン画面との読み取り専用の関連：",
            "不适用（该节点没有已证实的 USB location）":"該当なし（このノードには確認済みの USB location がありません）",
            "未找到相同 USB location 的当前观察":"同じ USB location の現在の観測はありません",
            "发现相同 location，但端口归属不唯一，保持未知":"同じ location を検出しましたが、ポートの所有関係が一意でないため不明のままです",
            "一致（不改变设备控制目标）":"一致（デバイス制御の対象は変更しません）",
            "同端口只读 USB 全景":"同じポートの読み取り専用 USB パノラマ",
            "当前没有可用于关联的明确 USB location；不强行分配外设或线材。":"関連付けに使える明確な USB location がありません。周辺機器やケーブルを強制的に割り当てません。",
            "全景中暂无相同 USB location 的节点；这不代表端口没有设备。":"パノラマに同じ USB location のノードはありません。ポートにデバイスがないという意味ではありません。",
            "物理归属来自同一当前 location 证据":"物理的な帰属は同じ現在の location 証拠に基づきます"
        ],
        "ko": [
            "安全深度重置 Configurator":"Configurator 안전 심층 초기화",
            "清理缓存并重启 Configurator":"캐시 정리 후 Configurator 재시작",
            "退出后只读盘点当前容器和旧路径，只清理精确 Caches；Application Support 默认保留；不暂停 usbd；重新打开后验证置前。":"종료 후 현재 컨테이너와 이전 경로를 읽기 전용으로 확인하고 정확한 Caches만 정리합니다. Application Support는 기본적으로 보존하며 usbd를 중지하지 않습니다. 다시 연 뒤 앞으로 가져오기를 검증합니다.",
            "同时处理 Application Support（先保留可恢复副本）":"Application Support도 처리(먼저 복원 가능한 백업 생성)",
            "默认关闭；关闭时 Application Support 保持不变。":"기본값은 꺼짐입니다. 꺼져 있으면 Application Support는 변경되지 않습니다.",
            "安全深度重置":"안전 심층 초기화",
            "清理缓存并重启":"캐시 정리 및 재시작",
            "只读盘点":"읽기 전용 목록 확인",
            "保留数据":"데이터 보존",
            "保留 Application Support":"Application Support 보존",
            "精确清理":"정확한 대상만 정리",
            "备份 Application Support":"Application Support 백업",
            "置前当前窗口":"현재 창을 앞으로 가져오기",
            "无匹配":"일치 항목 없음",
            "跳过":"건너뜀",
            "默认选择安全深度重置；修改设置本身不会执行操作。":"안전 심층 초기화가 기본 선택입니다. 설정 변경만으로 실행되지는 않습니다.",
            "A 型号未知":"A 모델 알 수 없음", "年份未知":"연도 알 수 없음",
            "A 型号待确认":"A 모델 확인 대기", "年份待确认":"연도 확인 대기",
            "身份冲突":"ID 정보 충돌", "A/年份未定":"A/연도 미정",
            "当前无身份证据":"현재 ID 증거 없음",
            "识别状态":"ID 상태", "机型":"모델", "设备类别":"기기 분류",
            "系列":"시리즈", "尺寸":"크기", "芯片/SoC":"칩/SoC", "A 型号":"A 모델",
            "年份":"연도", "机型标识符":"모델 식별자", "iBridge":"iBridge", "T2":"T2",
            "HardwareCode":"HardwareCode", "身份观察":"ID 관찰",
            "观察代际":"관찰 세대", "识别来源":"ID 출처",
            "识别来源：":"ID 출처: ",
            "冲突字段":"충돌 필드", "历史提示":"기록 힌트",
            "同 ECID 旧记录":"같은 ECID의 이전 기록",
            "不参与当前确认":"현재 확인에는 사용하지 않음",
            "确定（当前明确字段）":"확정(현재 명시 필드)",
            "仅历史提示":"기록 힌트만", "笔记本":"노트북", "台式机":"데스크탑",
            "候选":"후보", "候选机型":"후보 모델", "冲突候选":"충돌 후보",
            "待确认":"확인 대기", "资料未收录":"자료에 없음",
            "未读取":"읽지 않음", "唯一匹配":"고유 일치", "确定":"확정",
            "物理接口与设备（按证据优先级）":"물리 포트 및 기기(증거 우선순위)",
            "归属未证实的线材、伙伴与供电":"물리적 귀속이 확인되지 않은 케이블, 연결 상대, 전원",
            "物理归属未证实":"물리적 귀속 미확인",
            "未检测到 Mac、USB HUB 或外设":"Mac, USB HUB 또는 주변 기기를 감지하지 못함",
            "USB 观察已看到设备，但接口树尚无可靠物理归属。":"USB 관찰에서는 기기를 확인했지만 인터페이스 트리에 신뢰할 수 있는 물리 포트 귀속이 없습니다.",
            "原始 USB 拓扑":"원본 USB 토폴로지",
            "以下仅显示系统父子关系，不代表已确认物理接口。":"시스템 상하위 관계만 표시하며 물리 포트가 확인된 것은 아닙니다.",
            "Mac 身份：":"Mac ID: ", "类别：":"분류: ", "系列：":"시리즈: ",
            "尺寸：":"크기: ", "芯片/SoC：":"칩/SoC: ", "机型标识符：":"모델 식별자: ",
            "物理端口待确认":"물리 포트 확인 대기",
            "选中端口":"선택한 포트", "端口已连接 · 设备身份未读取":"포트 연결됨 · 기기 ID를 아직 읽지 않음",
            "Mac 设备已连接 · 身份未知":"Mac 기기 연결됨 · ID 알 수 없음",
            "Helper 可用 · 签名授权通过":"Helper 사용 가능 · 서명 권한 확인됨",
            "Helper 调用可用 · 安装检测另有提示":"Helper 호출 가능 · 설치 검사에 별도 경고 있음",
            "Helper 已安装 · 调用未授权":"Helper 설치됨 · 호출 권한 없음",
            "设备控制调用不可用":"기기 제어 호출 사용 불가",
            "Helper 状态未知 · 调用不可用":"Helper 상태 알 수 없음 · 호출 불가",
            "Helper 检测失败 · 调用不可用":"Helper 감지 실패 · 호출 불가",
            "安装与服务检测：":"설치 및 서비스 검사: ",
            "可用（签名授权与 socket 调用已通过）":"사용 가능(서명 권한 및 socket 호출 통과)",
            "主界面只读关联：":"메인 창 읽기 전용 연계: ",
            "不适用（该节点没有已证实的 USB location）":"해당 없음(이 노드에 확인된 USB location이 없음)",
            "未找到相同 USB location 的当前观察":"같은 USB location의 현재 관찰을 찾지 못함",
            "发现相同 location，但端口归属不唯一，保持未知":"같은 location을 찾았지만 포트 귀속이 고유하지 않아 알 수 없음으로 유지",
            "一致（不改变设备控制目标）":"일치(기기 제어 대상은 변경하지 않음)",
            "同端口只读 USB 全景":"같은 포트의 읽기 전용 USB 파노라마",
            "当前没有可用于关联的明确 USB location；不强行分配外设或线材。":"연계에 사용할 명확한 USB location이 없습니다. 주변 기기나 케이블을 강제로 할당하지 않습니다.",
            "全景中暂无相同 USB location 的节点；这不代表端口没有设备。":"파노라마에 같은 USB location의 노드가 없습니다. 포트에 기기가 없다는 뜻은 아닙니다.",
            "物理归属来自同一当前 location 证据":"물리적 귀속은 동일한 현재 location 증거에서 확인"
        ]
    ]

    private static let batch10: [String: [String: String]] = [
        "en": [
            "USB 时序观察":"USB timing observation",
            "接口与设备":"Ports and Devices",
            "Mac DFU · 型号待确认":"Mac DFU · model pending confirmation",
            "Mac Recovery · 型号待确认":"Mac Recovery · model pending confirmation",
            "Mac 已连接 · 型号待确认":"Mac connected · model pending confirmation",
            "Mac 未知模式 · 型号待确认":"Mac unknown mode · model pending confirmation",
            "未知模式":"Unknown mode",
            "当前：":"Current: ",
            "次":"times",
            "controller + PortNumber + RID + USB location 精确校准一致":"controller + PortNumber + RID + USB location exactly calibrated and matched",
            "USB location 未获可信端口归属":"USB location has no trusted port ownership",
            "未检测到目标 Mac":"No target Mac detected",
            "端口链路有连接；未枚举到目标设备":"Port link is connected; no target device enumerated",
            "当前没有目标设备":"No target device currently",
            "当前观察未知":"Current observation unknown",
            "当前读取失败或尚未完成；不认定拔出":"Read failed or has not completed; disconnection is not inferred",
            "已确认当前枚举为 Mac；A 型号和年份未确定":"Current USB device is identified as a Mac; A model and year remain unknown",
            "型号待确认":"Model pending confirmation",
            "USB 设备已连接 · 身份待识别":"USB device connected · identity pending",
            "USB 外设，不冒充目标 Mac":"USB peripheral; not presented as the target Mac",
            "当前未检测到目标设备":"No target device currently detected",
            "当前 Mac 身份证据不足":"Current Mac identity evidence is insufficient",
            "观察不完整；缺失区间不计算精确次数":"Observation incomplete; exact counts are withheld for missing intervals",
            "复制当前口时序":"Copy this port's timing",
            "清零当前口统计":"Clear this port's timing",
            "已复制同屏快照":"Copied the same on-screen snapshot",
            "最近 10 条真实出现/消失":"Latest 10 observed appearance/removal events",
            "身份待识别":"Identity pending",
            "当前驻留：":"Current residence: ",
            "开始观察时已存在":"Already present when observation began",
            "清零后建立观察基线":"Observation baseline established after clear",
            "出现时间未知":"Appearance time unknown",
            "已观察至少":"observed for at least ",
            "当前未见可归属于此口的 USB 设备":"No USB device is currently attributable to this port",
            "上次驻留：":"Previous residence: ",
            "上次端口再出现间隔：":"Previous port reappearance gap: ",
            "最近 60 秒端口再出现：":"Port reappearances in the last 60 seconds: ",
            "其中同机重枚举：":"Same-machine re-enumerations: ",
            "同机重枚举：未知":"Same-machine re-enumerations: unknown",
            "事件不完整，至少丢失":"Event history incomplete; at least ",
            "条":" events missing",
            "最近 USB 系统通知：":"Recent USB system notifications:",
            "暂无":"None",
            "出现":"appeared",
            "消失":"removed",
            "实例 ID 未知":"instance ID unknown",
            "终止时使用留存字段":"retained fields used at termination",
            "同模式再枚举":"same-mode re-enumeration",
            "模式改变":"mode changed",
            "模式关系未知":"mode relationship unknown",
            "端口归属未知":"port ownership unknown",
            "时区：":"Time zone: ",
            "观察不完整：":"Observation incomplete: ",
            "未归属 USB 时序（最近 10 条）":"Unowned USB timing (latest 10)",
            "没有可信的当前 USB location 归属；不强行分配外设或线材。":"No trusted current USB location ownership; peripherals and cables are not assigned.",
            "USB 外设":"USB peripheral",
            "当前外设":"Current peripheral",
            "归属证据":"Ownership evidence",
            "端口控制器连接状态存在；当前未检测到目标设备":"Port controller connection exists; no target device is currently detected"
        ],
        "zh-Hant": [
            "USB 时序观察":"USB 時序觀察",
            "接口与设备":"連接埠與裝置",
            "Mac DFU · 型号待确认":"Mac DFU · 型號待確認",
            "Mac Recovery · 型号待确认":"Mac Recovery · 型號待確認",
            "Mac 已连接 · 型号待确认":"Mac 已連接 · 型號待確認",
            "Mac 未知模式 · 型号待确认":"Mac 未知模式 · 型號待確認",
            "未知模式":"未知的模式",
            "当前：":"目前：",
            "次":"次數",
            "controller + PortNumber + RID + USB location 精确校准一致":"controller + PortNumber + RID + USB location 精確校準一致",
            "USB location 未获可信端口归属":"USB location 尚未取得可信連接埠歸屬",
            "未检测到目标 Mac":"未偵測到目標 Mac",
            "端口链路有连接；未枚举到目标设备":"連接埠鏈路有連線；未列舉到目標裝置",
            "当前没有目标设备":"目前沒有目標裝置",
            "当前观察未知":"目前觀察未知",
            "当前读取失败或尚未完成；不认定拔出":"目前讀取失敗或尚未完成；不判定為拔出",
            "已确认当前枚举为 Mac；A 型号和年份未确定":"已確認目前列舉為 Mac；A 型號與年份未確定",
            "型号待确认":"型號待確認",
            "USB 设备已连接 · 身份待识别":"USB 裝置已連接 · 身分待識別",
            "USB 外设，不冒充目标 Mac":"USB 周邊，不冒充目標 Mac",
            "当前未检测到目标设备":"目前未偵測到目標裝置",
            "当前 Mac 身份证据不足":"目前 Mac 身分證據不足",
            "观察不完整；缺失区间不计算精确次数":"觀察不完整；缺失區間不計算精確次數",
            "复制当前口时序":"複製目前連接埠時序",
            "清零当前口统计":"清除目前連接埠統計",
            "已复制同屏快照":"已複製同畫面快照",
            "最近 10 条真实出现/消失":"最近 10 筆真實出現/消失",
            "身份待识别":"身分待識別",
            "当前驻留：":"目前駐留：",
            "开始观察时已存在":"開始觀察時已存在",
            "清零后建立观察基线":"清零後建立觀察基線",
            "出现时间未知":"出現時間未知",
            "已观察至少":"已觀察至少 ",
            "当前未见可归属于此口的 USB 设备":"目前未見可歸屬於此連接埠的 USB 裝置",
            "上次驻留：":"上次駐留：",
            "上次端口再出现间隔：":"上次連接埠再出現間隔：",
            "最近 60 秒端口再出现：":"最近 60 秒連接埠再出現：",
            "其中同机重枚举：":"其中同機重新列舉：",
            "同机重枚举：未知":"同機重新列舉：未知",
            "事件不完整，至少丢失":"事件不完整，至少遺失 ",
            "条":" 筆",
            "最近 USB 系统通知：":"最近 USB 系統通知：",
            "暂无":"暫無",
            "出现":"出現",
            "消失":"消失",
            "实例 ID 未知":"實例 ID 未知",
            "终止时使用留存字段":"終止時使用留存欄位",
            "同模式再枚举":"同模式重新列舉",
            "模式改变":"模式改變",
            "模式关系未知":"模式關係未知",
            "端口归属未知":"連接埠歸屬未知",
            "时区：":"時區：",
            "观察不完整：":"觀察不完整：",
            "未归属 USB 时序（最近 10 条）":"未歸屬 USB 時序（最近 10 筆）",
            "没有可信的当前 USB location 归属；不强行分配外设或线材。":"沒有可信的目前 USB location 歸屬；不強行分配周邊或線材。",
            "USB 外设":"USB 周邊",
            "当前外设":"目前周邊",
            "归属证据":"歸屬證據",
            "端口控制器连接状态存在；当前未检测到目标设备":"連接埠控制器有連線狀態；目前未偵測到目標裝置"
        ],
        "ja": [
            "USB 时序观察":"USB タイミング観測",
            "接口与设备":"ポートとデバイス",
            "Mac DFU · 型号待确认":"Mac DFU · 機種確認待ち",
            "Mac Recovery · 型号待确认":"Mac Recovery · 機種確認待ち",
            "Mac 已连接 · 型号待确认":"Mac 接続済み · 機種確認待ち",
            "Mac 未知模式 · 型号待确认":"Mac 不明モード · 機種確認待ち",
            "未知模式":"不明なモード",
            "当前：":"現在：",
            "次":"回",
            "controller + PortNumber + RID + USB location 精确校准一致":"controller + PortNumber + RID + USB location が正確に校正一致",
            "USB location 未获可信端口归属":"USB location の信頼できるポート帰属なし",
            "未检测到目标 Mac":"対象 Mac は未検出",
            "端口链路有连接；未枚举到目标设备":"ポートリンクは接続中ですが、対象デバイスは列挙されていません",
            "当前没有目标设备":"現在対象デバイスはありません",
            "当前观察未知":"現在の観測は不明",
            "当前读取失败或尚未完成；不认定拔出":"読み取り失敗または未完のため、取り外しとは判定しません",
            "已确认当前枚举为 Mac；A 型号和年份未确定":"現在の列挙は Mac と確認済み。A 型番と年式は未確定です",
            "型号待确认":"型番確認待ち",
            "USB 设备已连接 · 身份待识别":"USB デバイス接続済み · 識別情報待ち",
            "USB 外设，不冒充目标 Mac":"USB 周辺機器であり、対象 Mac として扱いません",
            "当前未检测到目标设备":"現在、対象デバイスは未検出",
            "当前 Mac 身份证据不足":"現在の Mac 識別証拠が不足しています",
            "观察不完整；缺失区间不计算精确次数":"観測が不完全なため、欠落区間の正確な回数は算出しません",
            "复制当前口时序":"選択ポートのタイミングをコピー",
            "清零当前口统计":"選択ポートの統計をクリア",
            "已复制同屏快照":"画面と同じスナップショットをコピーしました",
            "最近 10 条真实出现/消失":"最新 10 件の実際の出現/消失",
            "身份待识别":"識別情報待ち",
            "当前驻留：":"現在の滞在時間：",
            "开始观察时已存在":"観測開始時から存在",
            "清零后建立观察基线":"クリア後の観測基準",
            "出现时间未知":"出現時刻不明",
            "已观察至少":"少なくとも ",
            "当前未见可归属于此口的 USB 设备":"このポートに帰属できる USB デバイスは現在見つかりません",
            "上次驻留：":"前回の滞在時間：",
            "上次端口再出现间隔：":"前回のポート再出現間隔：",
            "最近 60 秒端口再出现：":"直近 60 秒のポート再出現：",
            "其中同机重枚举：":"同一 Mac の再列挙：",
            "同机重枚举：未知":"同一 Mac の再列挙：不明",
            "事件不完整，至少丢失":"イベント履歴が不完全で、少なくとも ",
            "条":" 件欠落",
            "最近 USB 系统通知：":"最近の USB システム通知：",
            "暂无":"なし",
            "出现":"出現",
            "消失":"消失",
            "实例 ID 未知":"インスタンス ID 不明",
            "终止时使用留存字段":"終了時に保持情報を使用",
            "同模式再枚举":"同一モードの再列挙",
            "模式改变":"モード変更",
            "模式关系未知":"モード関係不明",
            "端口归属未知":"ポート帰属不明",
            "时区：":"タイムゾーン：",
            "观察不完整：":"観測不完全：",
            "未归属 USB 时序（最近 10 条）":"帰属不明 USB タイミング（最新 10 件）",
            "没有可信的当前 USB location 归属；不强行分配外设或线材。":"信頼できる現在の USB location 帰属がないため、周辺機器やケーブルを割り当てません。",
            "USB 外设":"USB 周辺機器",
            "当前外设":"現在の周辺機器",
            "归属证据":"帰属証拠",
            "端口控制器连接状态存在；当前未检测到目标设备":"ポートコントローラに接続状態はありますが、対象デバイスは未検出です"
        ],
        "ko": [
            "USB 时序观察":"USB 타이밍 관찰",
            "接口与设备":"포트 및 기기",
            "Mac DFU · 型号待确认":"Mac DFU · 모델 확인 대기",
            "Mac Recovery · 型号待确认":"Mac Recovery · 모델 확인 대기",
            "Mac 已连接 · 型号待确认":"Mac 연결됨 · 모델 확인 대기",
            "Mac 未知模式 · 型号待确认":"Mac 알 수 없는 모드 · 모델 확인 대기",
            "未知模式":"알 수 없는 모드",
            "当前：":"현재: ",
            "次":"회",
            "controller + PortNumber + RID + USB location 精确校准一致":"controller + PortNumber + RID + USB location 정확히 보정 일치",
            "USB location 未获可信端口归属":"USB location의 신뢰할 수 있는 포트 귀속 없음",
            "未检测到目标 Mac":"대상 Mac가 감지되지 않음",
            "端口链路有连接；未枚举到目标设备":"포트 링크는 연결되어 있지만 대상 기기가 열거되지 않음",
            "当前没有目标设备":"현재 대상 기기 없음",
            "当前观察未知":"현재 관찰 상태 알 수 없음",
            "当前读取失败或尚未完成；不认定拔出":"읽기 실패 또는 미완료 상태이며 분리로 판단하지 않음",
            "已确认当前枚举为 Mac；A 型号和年份未确定":"현재 열거된 기기는 Mac로 확인되었지만 A 모델과 연도는 미확정",
            "型号待确认":"모델 확인 대기",
            "USB 设备已连接 · 身份待识别":"USB 기기 연결됨 · ID 확인 대기",
            "USB 外设，不冒充目标 Mac":"USB 주변기기이며 대상 Mac로 표시하지 않음",
            "当前未检测到目标设备":"현재 대상 기기가 감지되지 않음",
            "当前 Mac 身份证据不足":"현재 Mac ID 증거 부족",
            "观察不完整；缺失区间不计算精确次数":"관찰이 불완전하여 누락 구간의 정확한 횟수를 계산하지 않음",
            "复制当前口时序":"현재 포트 타이밍 복사",
            "清零当前口统计":"현재 포트 통계 지우기",
            "已复制同屏快照":"화면과 같은 스냅샷을 복사함",
            "最近 10 条真实出现/消失":"최근 실제 연결/분리 10건",
            "身份待识别":"ID 확인 대기",
            "当前驻留：":"현재 연결 유지 시간: ",
            "开始观察时已存在":"관찰 시작 시 이미 존재",
            "清零后建立观察基线":"지우기 후 관찰 기준 설정",
            "出现时间未知":"연결 시각 알 수 없음",
            "已观察至少":"최소 관찰 시간 ",
            "当前未见可归属于此口的 USB 设备":"현재 이 포트에 귀속할 USB 기기가 없음",
            "上次驻留：":"이전 연결 유지 시간: ",
            "上次端口再出现间隔：":"이전 포트 재등장 간격: ",
            "最近 60 秒端口再出现：":"최근 60초 포트 재등장: ",
            "其中同机重枚举：":"동일 기기 재열거: ",
            "同机重枚举：未知":"동일 기기 재열거: 알 수 없음",
            "事件不完整，至少丢失":"이벤트 이력이 불완전하며 최소 ",
            "条":"건 누락",
            "最近 USB 系统通知：":"최근 USB 시스템 알림:",
            "暂无":"없음",
            "出现":"연결",
            "消失":"분리",
            "实例 ID 未知":"인스턴스 ID 알 수 없음",
            "终止时使用留存字段":"종료 시 보관 필드 사용",
            "同模式再枚举":"동일 모드 재열거",
            "模式改变":"모드 변경",
            "模式关系未知":"모드 관계 알 수 없음",
            "端口归属未知":"포트 귀속 알 수 없음",
            "时区：":"시간대: ",
            "观察不完整：":"관찰 불완전: ",
            "未归属 USB 时序（最近 10 条）":"귀속되지 않은 USB 타이밍(최근 10건)",
            "没有可信的当前 USB location 归属；不强行分配外设或线材。":"신뢰할 수 있는 현재 USB location 귀속이 없어 주변기기나 케이블을 강제로 할당하지 않습니다.",
            "USB 外设":"USB 주변기기",
            "当前外设":"현재 주변기기",
            "归属证据":"귀속 증거",
            "端口控制器连接状态存在；当前未检测到目标设备":"포트 컨트롤러 연결 상태는 있지만 대상 기기는 감지되지 않음"
        ]
    ]

    private static let batch11: [String: [String: String]] = [
        "en": [
            "传输支持":"Supported transports",
            "传输配置":"Provisioned transports",
            "传输活动":"Active transports",
            "HPM 过流计数":"HPM overcurrent count",
            "未授权传输":"Unauthorized transports",
            "授权要求":"Authorization required",
            "用户授权状态":"User authorization status",
            "支持功能":"Supported features",
            "启用功能":"Enabled features",
            "端口与设备":"Ports and Devices",
            "供电与 PD":"Power and PD",
            "PD 合约":"PD contract",
            "link-error-count":"Link error count",
            "系统未提供":"Not provided by the system",
            "无（空列表）":"None (empty list)",
            "仅检测到非 USB-C 供电记录；未挂接":"Only a non-USB-C power record was found; not attached",
            "0xFFFF（饱和/不可用）":"0xFFFF (saturated/unavailable)",
            "请求已发送 · 观察中":"Request submitted · observing",
            "观察到 DFU · 结果未确认":"DFU observed · result unconfirmed",
            "已确认进入 DFU · 同一设备":"DFU confirmed · same device",
            "已确认该端口出现 DFU · 设备身份未确认":"DFU confirmed on this port · device identity unconfirmed",
            "结果未确认 · 观察窗口结束":"Outcome unconfirmed · observation window ended",
            "只读观察进行中；尚未确认设备进入 DFU。":"Read-only observation is in progress; the device has not entered DFU with sufficient evidence.",
            "本次请求后，同一设备已进入 DFU；这不代表 Restore 成功。":"The same device entered DFU after this request; this does not mean Restore succeeded.",
            "本次请求后，该物理端口出现 DFU；具体设备身份未确认。":"DFU appeared on this physical port after the request; the specific device identity is unconfirmed.",
            "本次操作已确认进入 DFU；当前端口未观察到 DFU。":"This operation was confirmed to enter DFU; DFU is not currently observed on the port.",
            "只读确认不会解锁按钮或改变发送链。":"Read-only confirmation does not unlock buttons or change the send chain."
        ],
        "zh-Hant": [
            "传输支持":"傳輸支援",
            "传输配置":"已配置傳輸",
            "传输活动":"活動傳輸",
            "HPM 过流计数":"HPM 過流計數",
            "未授权传输":"未授權傳輸",
            "授权要求":"授權要求",
            "用户授权状态":"使用者授權狀態",
            "支持功能":"支援功能",
            "启用功能":"已啟用功能",
            "端口与设备":"連接埠與裝置",
            "供电与 PD":"供電與 PD",
            "PD 合约":"PD 合約",
            "link-error-count":"鏈路錯誤次數",
            "系统未提供":"系統未提供",
            "无（空列表）":"無（空清單）",
            "仅检测到非 USB-C 供电记录；未挂接":"僅偵測到非 USB-C 供電記錄；未掛接",
            "0xFFFF（饱和/不可用）":"0xFFFF（飽和/不可用）",
            "请求已发送 · 观察中":"要求已傳送 · 觀察中",
            "观察到 DFU · 结果未确认":"觀察到 DFU · 結果未確認",
            "已确认进入 DFU · 同一设备":"已確認進入 DFU · 同一裝置",
            "已确认该端口出现 DFU · 设备身份未确认":"已確認此連接埠出現 DFU · 裝置身分未確認",
            "结果未确认 · 观察窗口结束":"結果未確認 · 觀察視窗結束",
            "只读观察进行中；尚未确认设备进入 DFU。":"唯讀觀察進行中；尚無足夠證據確認裝置進入 DFU。",
            "本次请求后，同一设备已进入 DFU；这不代表 Restore 成功。":"本次要求後，同一裝置已進入 DFU；這不代表 Restore 成功。",
            "本次请求后，该物理端口出现 DFU；具体设备身份未确认。":"本次要求後，此實體連接埠出現 DFU；具體裝置身分未確認。",
            "本次操作已确认进入 DFU；当前端口未观察到 DFU。":"本次操作已確認進入 DFU；目前連接埠未觀察到 DFU。",
            "只读确认不会解锁按钮或改变发送链。":"唯讀確認不會解鎖按鈕或變更傳送鏈。"
        ],
        "ja": [
            "传输支持":"対応トランスポート",
            "传输配置":"設定済みトランスポート",
            "传输活动":"アクティブトランスポート",
            "HPM 过流计数":"HPM 過電流回数",
            "未授权传输":"未承認トランスポート",
            "授权要求":"承認が必要",
            "用户授权状态":"ユーザー承認状態",
            "支持功能":"対応機能",
            "启用功能":"有効な機能",
            "端口与设备":"ポートとデバイス",
            "供电与 PD":"給電と PD",
            "PD 合约":"PD 契約",
            "link-error-count":"リンクエラー数",
            "系统未提供":"システムから提供されていません",
            "无（空列表）":"なし（空のリスト）",
            "仅检测到非 USB-C 供电记录；未挂接":"非 USB-C の給電記録のみを検出しました。関連付けていません",
            "0xFFFF（饱和/不可用）":"0xFFFF（飽和/利用不可）",
            "请求已发送 · 观察中":"要求送信済み · 観察中",
            "观察到 DFU · 结果未确认":"DFU を検出 · 結果未確認",
            "已确认进入 DFU · 同一设备":"DFU 進入を確認 · 同一デバイス",
            "已确认该端口出现 DFU · 设备身份未确认":"このポートで DFU を確認 · デバイス ID は未確認",
            "结果未确认 · 观察窗口结束":"結果未確認 · 観察時間終了",
            "只读观察进行中；尚未确认设备进入 DFU。":"読み取り専用の観察中です。デバイスが DFU に入ったことを確認する十分な証拠はまだありません。",
            "本次请求后，同一设备已进入 DFU；这不代表 Restore 成功。":"この要求後、同じデバイスが DFU に入りました。Restore の成功を示すものではありません。",
            "本次请求后，该物理端口出现 DFU；具体设备身份未确认。":"この要求後、この物理ポートで DFU を検出しました。具体的なデバイス ID は未確認です。",
            "本次操作已确认进入 DFU；当前端口未观察到 DFU。":"この操作で DFU 進入を確認しました。現在このポートでは DFU を検出していません。",
            "只读确认不会解锁按钮或改变发送链。":"読み取り専用の確認はボタンのロック解除や送信経路の変更を行いません。"
        ],
        "ko": [
            "传输支持":"지원 전송",
            "传输配置":"구성된 전송",
            "传输活动":"활성 전송",
            "HPM 过流计数":"HPM 과전류 횟수",
            "未授权传输":"승인되지 않은 전송",
            "授权要求":"승인 필요",
            "用户授权状态":"사용자 승인 상태",
            "支持功能":"지원 기능",
            "启用功能":"활성화된 기능",
            "端口与设备":"포트 및 기기",
            "供电与 PD":"전원 및 PD",
            "PD 合约":"PD 계약",
            "link-error-count":"링크 오류 횟수",
            "系统未提供":"시스템에서 제공하지 않음",
            "无（空列表）":"없음(빈 목록)",
            "仅检测到非 USB-C 供电记录；未挂接":"USB-C가 아닌 전원 기록만 감지되었으며 연결하지 않았습니다",
            "0xFFFF（饱和/不可用）":"0xFFFF(포화/사용 불가)",
            "请求已发送 · 观察中":"요청 전송됨 · 관찰 중",
            "观察到 DFU · 结果未确认":"DFU 감지 · 결과 미확인",
            "已确认进入 DFU · 同一设备":"DFU 진입 확인 · 동일 기기",
            "已确认该端口出现 DFU · 设备身份未确认":"이 포트에서 DFU 확인 · 기기 ID 미확인",
            "结果未确认 · 观察窗口结束":"결과 미확인 · 관찰 시간 종료",
            "只读观察进行中；尚未确认设备进入 DFU。":"읽기 전용 관찰 중이며 기기가 DFU에 진입했다는 충분한 증거가 아직 없습니다.",
            "本次请求后，同一设备已进入 DFU；这不代表 Restore 成功。":"이 요청 후 동일 기기가 DFU에 진입했습니다. Restore 성공을 의미하지 않습니다.",
            "本次请求后，该物理端口出现 DFU；具体设备身份未确认。":"이 요청 후 해당 물리 포트에서 DFU가 나타났으며 구체적인 기기 ID는 확인되지 않았습니다.",
            "本次操作已确认进入 DFU；当前端口未观察到 DFU。":"이 작업의 DFU 진입은 확인되었으며 현재 포트에서는 DFU가 관찰되지 않습니다.",
            "只读确认不会解锁按钮或改变发送链。":"읽기 전용 확인은 버튼 잠금 해제 또는 전송 체인 변경을 수행하지 않습니다."
        ]
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
               "深度清理并重启 Configurator":"Deep Clean and Restart Configurator",
               "重置级别":"Reset level","最高级别 · 默认":"Highest level · Default",
               "完整执行旧版重置：退出、清理 Caches 和 Application Support、重置 USB，然后重新打开并置顶。":"Run the legacy reset exactly: quit, clear Caches and Application Support, reset USB, then reopen and bring to front.",
               "默认选择深度清理并重启；修改设置本身不会执行操作。":"Deep clean and restart is selected by default; changing the setting does not run an action.",
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
               "深度清理并重启 Configurator":"深度清理並重新啟動 Configurator",
               "重置级别":"重設級別","最高级别 · 默认":"最高級別 · 預設",
               "完整执行旧版重置：退出、清理 Caches 和 Application Support、重置 USB，然后重新打开并置顶。":"依舊版流程完整執行：結束、清除 Caches 與 Application Support、重設 USB，然後重新開啟並置前。",
               "默认选择深度清理并重启；修改设置本身不会执行操作。":"預設選擇深度清理並重新啟動；修改設定不會執行操作。",
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
               "深度清理并重启 Configurator":"Configurator を詳細消去して再起動",
               "重置级别":"リセットレベル","最高级别 · 默认":"最上位 · 既定",
               "完整执行旧版重置：退出、清理 Caches 和 Application Support、重置 USB，然后重新打开并置顶。":"旧版の処理をそのまま実行：終了、Caches と Application Support を消去、USB をリセットし、再度開いて前面に表示します。",
               "默认选择深度清理并重启；修改设置本身不会执行操作。":"既定では詳細消去と再起動が選択されています。設定変更だけでは実行されません。",
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
               "深度清理并重启 Configurator":"Configurator 정밀 정리 및 재시작",
               "重置级别":"초기화 수준","最高级别 · 默认":"최고 수준 · 기본",
               "完整执行旧版重置：退出、清理 Caches 和 Application Support、重置 USB，然后重新打开并置顶。":"이전 버전 절차를 그대로 실행합니다: 종료, Caches 및 Application Support 정리, USB 초기화 후 다시 열고 앞으로 가져옵니다.",
               "默认选择深度清理并重启；修改设置本身不会执行操作。":"기본값은 정밀 정리 및 재시작입니다. 설정 변경만으로는 실행되지 않습니다.",
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
        case ("en", "shared"): return "Host \(host) · Not precisely calibrated (confirmed shared layout)"
        case ("en", "reuse"): return "Host \(host) · Not precisely calibrated (same-mold layout)"
        case ("en", "unidentified"): return "Host model unidentified · Not calibrated"
        case ("en", "uncalibrated"): return "Host \(host) · Not calibrated"
        case ("zh-Hans", "exact"): return "主机 \(host) · 机型已精确校准"
        case ("zh-Hans", "shared"): return "主机 \(host) · 未精确校准（沿用已确认共享布局）"
        case ("zh-Hans", "reuse"): return "主机 \(host) · 未精确校准（沿用同模具布局）"
        case ("zh-Hans", "unidentified"): return "主机机型未识别 · 未校准"
        case ("zh-Hans", "uncalibrated"): return "主机 \(host) · 未校准"
        case ("zh-Hant", "exact"): return "主機 \(host) · 機型已精確校準"
        case ("zh-Hant", "shared"): return "主機 \(host) · 未精確校準（沿用已確認共享佈局）"
        case ("zh-Hant", "reuse"): return "主機 \(host) · 未精確校準（沿用同模具佈局）"
        case ("zh-Hant", "unidentified"): return "主機機型未識別 · 未校準"
        case ("zh-Hant", "uncalibrated"): return "主機 \(host) · 未校準"
        case ("ja", "exact"): return "ホスト \(host) · 機種は正確に校正済み"
        case ("ja", "shared"): return "ホスト \(host) · 正確な校正なし（確認済み共有レイアウトを使用）"
        case ("ja", "reuse"): return "ホスト \(host) · 正確な校正なし（同一金型レイアウトを使用）"
        case ("ja", "unidentified"): return "ホスト機種未識別 · 未校正"
        case ("ja", "uncalibrated"): return "ホスト \(host) · 未校正"
        case ("ko", "exact"): return "호스트 \(host) · 기종 정밀 보정 완료"
        case ("ko", "shared"): return "호스트 \(host) · 정밀 보정 안 됨(확인된 공유 레이아웃 사용)"
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

    private static let restoreFix: [String: [String: String]] = [
        "en": [
            "固件与恢复": "Firmware & Restore",
            "Restore 目标": "Restore target",
            "本地 IPSW": "Local IPSW",
            "确认擦除数据并恢复…": "Confirm erase and restore…",
            "当前任务": "Current task",
            "整体进度：未知": "Overall progress: Unknown",
            "暂无恢复任务": "No restore task",
            "请求取消恢复": "Request restore cancellation",
            "强制结束无响应进程…": "Force-stop unresponsive process…",
            "打开本次原始日志目录": "Open raw output folder",
            "确认抹除并恢复？": "Erase and restore?",
            "抹除并恢复": "Erase and restore",
            "固件库": "Firmware Library",
            "刷新固件库": "Refresh Firmware Library",
            "恢复自动推荐": "Restore Automatic Recommendation",
            "校验完整 IPSW SHA-256…": "Verify Complete IPSW SHA-256…",
            "未选择固件来源": "No firmware source selected",
            "系统自动推荐": "Automatic system recommendation",
            "用户手动选择": "User manual selection",
            "已验证恢复记录": "Verified restore record",
            "用户显式默认": "Explicit user default",
            "本地元数据推断": "Local metadata inference",
            "需人工确认": "Manual confirmation required",
            "可用": "Available",
            "文件丢失": "File missing",
            "重定位有歧义": "Ambiguous relocation",
            "无效": "Invalid",
            "无法读取": "Unreadable",
            "iCloud 未下载": "iCloud item not downloaded",
            "已确认 DFU，可继续准备 Restore": "DFU confirmed. Continue preparing Restore",
            "操作端口：": "Port: ",
            "目标已选中；请选择本地 IPSW。": "Target selected; choose a local IPSW.",
            "准备此目标": "Prepare this target",
            "该物理端口已确认出现 DFU；尚无可唯一归属的 Restore 目标，请等待观察刷新。": "DFU was confirmed on this physical port, but no unique Restore target is available yet. Wait for observation refresh.",
            "关闭提示": "Dismiss",
            "端口身份待确认": "Port identity pending confirmation",
            "用户手动选择的 IPSW；后台刷新不得覆盖。": "User-selected IPSW; background refresh must not replace it.",
            "同一机型最近一次通过原生 1.7.0.3 验证链确认成功的 IPSW。": "The most recent IPSW recorded as successful by the native 1.7.0.3 verification chain for the same model family.",
            "同一机型显式设置的机型默认固件。": "The explicitly configured model-default firmware.",
            "用户显式设置的全局默认固件。": "The explicitly configured global-default firmware.",
            "兼容候选优先，其次按分段数值 ProductVersion 与 Build 降序选择；仅基于本地元数据推断。": "Compatible candidates are preferred, then segmented numeric ProductVersion and Build descending. This is inferred from local metadata only.",
            "机型身份未知；仅预选用户显式设置的全局默认固件，需人工确认。": "The model family is unknown. Only an explicit global-default firmware is preselected, with manual confirmation required.",
        ],
        "zh-Hant": [
            "固件与恢复": "韌體與恢復",
            "Restore 目标": "Restore 目標",
            "本地 IPSW": "本機 IPSW",
            "确认擦除数据并恢复…": "確認清除資料並恢復…",
            "当前任务": "目前任務",
            "整体进度：未知": "整體進度：未知",
            "暂无恢复任务": "尚無恢復任務",
            "请求取消恢复": "要求取消恢復",
            "强制结束无响应进程…": "強制結束無回應程序…",
            "打开本次原始日志目录": "開啟本次原始日誌資料夾",
            "确认抹除并恢复？": "確認清除並恢復？",
            "抹除并恢复": "清除並恢復",
            "固件库": "韌體庫",
            "刷新固件库": "重新整理韌體庫",
            "恢复自动推荐": "恢復自動推薦",
            "校验完整 IPSW SHA-256…": "驗證完整 IPSW SHA-256…",
            "未选择固件来源": "尚未選擇韌體來源",
            "系统自动推荐": "系統自動推薦",
            "用户手动选择": "使用者手動選擇",
            "已验证恢复记录": "已驗證恢復記錄",
            "用户显式默认": "使用者明確預設",
            "本地元数据推断": "本機中繼資料推斷",
            "需人工确认": "需要人工確認",
            "可用": "可用",
            "文件丢失": "檔案遺失",
            "重定位有歧义": "重新定位有歧義",
            "无效": "無效",
            "无法读取": "無法讀取",
            "iCloud 未下载": "iCloud 項目尚未下載",
            "已确认 DFU，可继续准备 Restore": "已確認 DFU，可繼續準備 Restore",
            "操作端口：": "操作連接埠：",
            "目标已选中；请选择本地 IPSW。": "目標已選取；請選擇本機 IPSW。",
            "准备此目标": "準備此目標",
            "该物理端口已确认出现 DFU；尚无可唯一归属的 Restore 目标，请等待观察刷新。": "此實體連接埠已確認出現 DFU；目前尚無可唯一歸屬的 Restore 目標，請等待觀察重新整理。",
            "关闭提示": "關閉提示",
            "端口身份待确认": "連接埠身分待確認",
            "用户手动选择的 IPSW；后台刷新不得覆盖。": "使用者手動選擇的 IPSW；背景重新整理不得覆蓋。",
            "同一机型最近一次通过原生 1.7.0.3 验证链确认成功的 IPSW。": "同一機型最近一次由原生 1.7.0.3 驗證鏈確認為成功的 IPSW。",
            "同一机型显式设置的机型默认固件。": "同一機型明確設定的機型預設韌體。",
            "用户显式设置的全局默认固件。": "使用者明確設定的全域預設韌體。",
            "兼容候选优先，其次按分段数值 ProductVersion 与 Build 降序选择；仅基于本地元数据推断。": "優先選擇相容候選，其次依分段數值 ProductVersion 與 Build 遞減排序；僅依本機中繼資料推斷。",
            "机型身份未知；仅预选用户显式设置的全局默认固件，需人工确认。": "機型身分未知；僅預選使用者明確設定的全域預設韌體，仍需人工確認。",
        ],
        "ja": [
            "固件与恢复": "ファームウェアと復元",
            "Restore 目标": "復元対象",
            "本地 IPSW": "ローカル IPSW",
            "确认擦除数据并恢复…": "消去して復元する…",
            "当前任务": "現在のタスク",
            "整体进度：未知": "全体の進捗：不明",
            "暂无恢复任务": "復元タスクはありません",
            "请求取消恢复": "復元のキャンセルを要求",
            "强制结束无响应进程…": "応答しないプロセスを強制終了…",
            "打开本次原始日志目录": "今回の生ログフォルダを開く",
            "确认抹除并恢复？": "消去して復元しますか？",
            "抹除并恢复": "消去して復元",
            "固件库": "ファームウェアライブラリ",
            "刷新固件库": "ファームウェアライブラリを更新",
            "恢复自动推荐": "自動推薦に戻す",
            "校验完整 IPSW SHA-256…": "IPSW 全体の SHA-256 を検証…",
            "未选择固件来源": "ファームウェアの選択元なし",
            "系统自动推荐": "システムの自動推薦",
            "用户手动选择": "ユーザーによる手動選択",
            "已验证恢复记录": "検証済み復元記録",
            "用户显式默认": "ユーザー指定の既定値",
            "本地元数据推断": "ローカルメタデータからの推定",
            "需人工确认": "手動確認が必要",
            "可用": "利用可能",
            "文件丢失": "ファイルなし",
            "重定位有歧义": "再配置候補が複数",
            "无效": "無効",
            "无法读取": "読み取り不可",
            "iCloud 未下载": "iCloud 項目は未ダウンロード",
            "已确认 DFU，可继续准备 Restore": "DFU を確認しました。Restore の準備を続けられます",
            "操作端口：": "操作ポート：",
            "目标已选中；请选择本地 IPSW。": "対象は選択済みです。ローカル IPSW を選択してください。",
            "准备此目标": "この対象を準備",
            "该物理端口已确认出现 DFU；尚无可唯一归属的 Restore 目标，请等待观察刷新。": "この物理ポートで DFU を確認しましたが、一意に紐付けられる Restore 対象はまだありません。観測の更新を待ってください。",
            "关闭提示": "閉じる",
            "端口身份待确认": "ポート ID の確認待ち",
            "用户手动选择的 IPSW；后台刷新不得覆盖。": "ユーザーが手動選択した IPSW です。バックグラウンド更新で置き換えません。",
            "同一机型最近一次通过原生 1.7.0.3 验证链确认成功的 IPSW。": "同じ機種で、ネイティブ 1.7.0.3 検証経路により直近の成功が確認された IPSW です。",
            "同一机型显式设置的机型默认固件。": "同じ機種に明示設定された既定ファームウェアです。",
            "用户显式设置的全局默认固件。": "ユーザーが明示設定したグローバル既定ファームウェアです。",
            "兼容候选优先，其次按分段数值 ProductVersion 与 Build 降序选择；仅基于本地元数据推断。": "互換候補を優先し、その後に ProductVersion と Build を数値セグメントで降順比較します。ローカルメタデータからの推定です。",
            "机型身份未知；仅预选用户显式设置的全局默认固件，需人工确认。": "機種 ID は不明です。明示されたグローバル既定ファームウェアだけを予備選択し、手動確認を要求します。",
        ],
        "ko": [
            "固件与恢复": "펌웨어 및 복원",
            "Restore 目标": "복원 대상",
            "本地 IPSW": "로컬 IPSW",
            "确认擦除数据并恢复…": "데이터를 지우고 복원…",
            "当前任务": "현재 작업",
            "整体进度：未知": "전체 진행률: 알 수 없음",
            "暂无恢复任务": "복원 작업 없음",
            "请求取消恢复": "복원 취소 요청",
            "强制结束无响应进程…": "응답 없는 프로세스 강제 종료…",
            "打开本次原始日志目录": "이번 원본 로그 폴더 열기",
            "确认抹除并恢复？": "지우고 복원하시겠습니까?",
            "抹除并恢复": "지우고 복원",
            "固件库": "펌웨어 라이브러리",
            "刷新固件库": "펌웨어 라이브러리 새로 고침",
            "恢复自动推荐": "자동 추천 복원",
            "校验完整 IPSW SHA-256…": "전체 IPSW SHA-256 검증…",
            "未选择固件来源": "펌웨어 선택 출처 없음",
            "系统自动推荐": "시스템 자동 추천",
            "用户手动选择": "사용자 수동 선택",
            "已验证恢复记录": "검증된 복원 기록",
            "用户显式默认": "사용자 지정 기본값",
            "本地元数据推断": "로컬 메타데이터 추론",
            "需人工确认": "수동 확인 필요",
            "可用": "사용 가능",
            "文件丢失": "파일 없음",
            "重定位有歧义": "재배치 후보 모호",
            "无效": "유효하지 않음",
            "无法读取": "읽을 수 없음",
            "iCloud 未下载": "iCloud 항목이 다운로드되지 않음",
            "已确认 DFU，可继续准备 Restore": "DFU가 확인되었습니다. Restore 준비를 계속할 수 있습니다",
            "操作端口：": "작업 포트: ",
            "目标已选中；请选择本地 IPSW。": "대상이 선택되었습니다. 로컬 IPSW를 선택하십시오.",
            "准备此目标": "이 대상 준비",
            "该物理端口已确认出现 DFU；尚无可唯一归属的 Restore 目标，请等待观察刷新。": "이 물리 포트에서 DFU가 확인되었지만 고유하게 연결된 Restore 대상이 아직 없습니다. 관찰 새로 고침을 기다리십시오.",
            "关闭提示": "닫기",
            "端口身份待确认": "포트 ID 확인 대기",
            "用户手动选择的 IPSW；后台刷新不得覆盖。": "사용자가 수동 선택한 IPSW이며 백그라운드 새로 고침으로 덮어쓰지 않습니다.",
            "同一机型最近一次通过原生 1.7.0.3 验证链确认成功的 IPSW。": "동일 모델에서 네이티브 1.7.0.3 검증 경로로 가장 최근 성공이 확인된 IPSW입니다.",
            "同一机型显式设置的机型默认固件。": "동일 모델에 명시적으로 설정된 모델 기본 펌웨어입니다.",
            "用户显式设置的全局默认固件。": "사용자가 명시적으로 설정한 전역 기본 펌웨어입니다.",
            "兼容候选优先，其次按分段数值 ProductVersion 与 Build 降序选择；仅基于本地元数据推断。": "호환 후보를 우선하고 ProductVersion과 Build를 숫자 구간으로 내림차순 비교합니다. 로컬 메타데이터 기반 추론입니다.",
            "机型身份未知；仅预选用户显式设置的全局默认固件，需人工确认。": "모델 ID를 알 수 없습니다. 명시된 전역 기본 펌웨어만 미리 선택하며 수동 확인이 필요합니다.",
        ],
    ]

    static let batch13: [String: [String: String]] = [
        "en": [
            "Configurator 存储只读盘点": "Read-only Configurator Storage Inventory",
            "仅扫描明确的 Configurator Group Container、App Container、用户缓存和临时目录；不扫描整个 /var/folders、IPSW、Blueprints、客户数据或未知目录。": "Only explicit Configurator group containers, app containers, user caches, and temporary directories are scanned. The entire /var/folders tree, IPSW files, Blueprints, customer data, and unknown directories are excluded.",
            "刷新只读盘点": "Refresh read-only inventory",
            "相关进程": "Related processes",
            "部分系统区域无法枚举；已知值不会显示为 0 B。": "Some system areas cannot be enumerated. Known values are not displayed as 0 B.",
            "等待只读盘点…": "Waiting for read-only inventory…",
            "清理 Configurator 数据": "Clean up Configurator data",
            "待白名单核验授权": "Awaiting whitelist verification authorization",
            "本页只读。不会删除、移动或写入 Configurator 容器、缓存、Blueprints 或其他用户文件。": "This page is read-only. It does not delete, move, or write Configurator containers, caches, Blueprints, or other user files.",
            "已排除": "Excluded",
            "个 Reference Lab、Blueprints、IPSW 或未知类型条目。": "Reference Lab, Blueprints, IPSW, or unknown-type entries.",
            "扫描完成": "Scan complete",
            "部分权限受限": "Partially permission-limited",
            "部分可读": "Partially readable",
            "扫描失败": "Scan failed",
            "内容大小：": "Content size: ",
            "磁盘占用：": "Disk usage: ",
            "目录不存在": "Directory does not exist",
            "权限受限，无法枚举内部占用": "Permission limited; internal usage cannot be enumerated",
            "已成功扫描 · 0 B": "Scanned successfully · 0 B",
            "运行中": "Running",
            "未运行": "Not running",
            "未知": "Unknown",
            "磁盘": "Disk",
            "已知至少": "Known minimum",
        ],
        "zh-Hant": [
            "Configurator 存储只读盘点": "Configurator 儲存唯讀盤點",
            "仅扫描明确的 Configurator Group Container、App Container、用户缓存和临时目录；不扫描整个 /var/folders、IPSW、Blueprints、客户数据或未知目录。": "僅掃描明確的 Configurator Group Container、App Container、使用者快取與暫存目錄；不掃描整個 /var/folders、IPSW、Blueprints、客戶資料或未知目錄。",
            "刷新只读盘点": "重新整理唯讀盤點",
            "相关进程": "相關程序",
            "部分系统区域无法枚举；已知值不会显示为 0 B。": "部分系統區域無法列舉；已知值不會顯示為 0 B。",
            "等待只读盘点…": "等待唯讀盤點…",
            "清理 Configurator 数据": "清理 Configurator 資料",
            "待白名单核验授权": "待白名單核驗授權",
            "本页只读。不会删除、移动或写入 Configurator 容器、缓存、Blueprints 或其他用户文件。": "本頁僅供唯讀。不會刪除、移動或寫入 Configurator 容器、快取、Blueprints 或其他使用者檔案。",
            "已排除": "已排除",
            "个 Reference Lab、Blueprints、IPSW 或未知类型条目。": "個 Reference Lab、Blueprints、IPSW 或未知類型項目。",
            "扫描完成": "掃描完成",
            "部分权限受限": "部分權限受限",
            "部分可读": "部分可讀",
            "扫描失败": "掃描失敗",
            "内容大小：": "內容大小：",
            "磁盘占用：": "磁碟佔用：",
            "目录不存在": "目錄不存在",
            "权限受限，无法枚举内部占用": "權限受限，無法列舉內部佔用",
            "已成功扫描 · 0 B": "已成功掃描 · 0 B",
            "运行中": "執行中",
            "未运行": "未執行",
            "未知": "未知",
            "磁盘": "磁碟",
            "已知至少": "已知至少",
        ],
        "ja": [
            "Configurator 存储只读盘点": "Configurator ストレージの読み取り専用調査",
            "仅扫描明确的 Configurator Group Container、App Container、用户缓存和临时目录；不扫描整个 /var/folders、IPSW、Blueprints、客户数据或未知目录。": "明示された Configurator Group Container、App Container、ユーザーキャッシュ、一時ディレクトリのみを調査します。/var/folders 全体、IPSW、Blueprints、顧客データ、不明なディレクトリは除外します。",
            "刷新只读盘点": "読み取り専用調査を更新",
            "相关进程": "関連プロセス",
            "部分系统区域无法枚举；已知值不会显示为 0 B。": "一部のシステム領域を列挙できません。既知の値を 0 B として表示しません。",
            "等待只读盘点…": "読み取り専用調査を待機中…",
            "清理 Configurator 数据": "Configurator データを整理",
            "待白名单核验授权": "ホワイトリスト検証の承認待ち",
            "本页只读。不会删除、移动或写入 Configurator 容器、缓存、Blueprints 或其他用户文件。": "このページは読み取り専用です。Configurator コンテナ、キャッシュ、Blueprints、その他のユーザーファイルを削除、移動、書き込みしません。",
            "已排除": "除外済み",
            "个 Reference Lab、Blueprints、IPSW 或未知类型条目。": "件の Reference Lab、Blueprints、IPSW、または不明な種類の項目。",
            "扫描完成": "調査完了",
            "部分权限受限": "一部権限制限あり",
            "部分可读": "一部読み取り可能",
            "扫描失败": "調査失敗",
            "内容大小：": "内容サイズ：",
            "磁盘占用：": "ディスク使用量：",
            "目录不存在": "ディレクトリがありません",
            "权限受限，无法枚举内部占用": "権限が制限され、内部使用量を列挙できません",
            "已成功扫描 · 0 B": "正常に調査済み · 0 B",
            "运行中": "実行中",
            "未运行": "停止中",
            "未知": "不明",
            "磁盘": "ディスク",
            "已知至少": "既知の最小値",
        ],
        "ko": [
            "Configurator 存储只读盘点": "Configurator 저장 공간 읽기 전용 목록",
            "仅扫描明确的 Configurator Group Container、App Container、用户缓存和临时目录；不扫描整个 /var/folders、IPSW、Blueprints、客户数据或未知目录。": "명시된 Configurator Group Container, App Container, 사용자 캐시 및 임시 디렉터리만 검사합니다. 전체 /var/folders, IPSW, Blueprints, 고객 데이터 및 알 수 없는 디렉터리는 제외합니다.",
            "刷新只读盘点": "읽기 전용 목록 새로 고침",
            "相关进程": "관련 프로세스",
            "部分系统区域无法枚举；已知值不会显示为 0 B。": "일부 시스템 영역은 열거할 수 없습니다. 알려진 값을 0 B로 표시하지 않습니다.",
            "等待只读盘点…": "읽기 전용 목록 대기 중…",
            "清理 Configurator 数据": "Configurator 데이터 정리",
            "待白名单核验授权": "화이트리스트 검증 승인 대기",
            "本页只读。不会删除、移动或写入 Configurator 容器、缓存、Blueprints 或其他用户文件。": "이 페이지는 읽기 전용입니다. Configurator 컨테이너, 캐시, Blueprints 또는 기타 사용자 파일을 삭제, 이동 또는 기록하지 않습니다.",
            "已排除": "제외됨",
            "个 Reference Lab、Blueprints、IPSW 或未知类型条目。": "개의 Reference Lab, Blueprints, IPSW 또는 알 수 없는 유형 항목.",
            "扫描完成": "검사 완료",
            "部分权限受限": "일부 권한 제한",
            "部分可读": "일부 읽기 가능",
            "扫描失败": "검사 실패",
            "内容大小：": "콘텐츠 크기: ",
            "磁盘占用：": "디스크 사용량: ",
            "目录不存在": "디렉터리가 없습니다",
            "权限受限，无法枚举内部占用": "권한이 제한되어 내부 사용량을 열거할 수 없습니다",
            "已成功扫描 · 0 B": "검사 성공 · 0 B",
            "运行中": "실행 중",
            "未运行": "실행 중 아님",
            "未知": "알 수 없음",
            "磁盘": "디스크",
            "已知至少": "알려진 최소값",
        ],
    ]

    private static let workbenchFix: [String: [String: String]] = [
        "en": [
            "模拟环境": "SIMULATED",
            "专业 Mac 设备控制、USB-C 证据与 Restore 工作台": "Professional Mac control, USB-C evidence, and Restore workspace",
            "Configurator 存储": "Configurator Storage",
            "快捷控制": "Quick Controls",
            "物理端口": "Physical Ports",
            "RLM 日志": "RLM Logs",
            "只读盘点 Configurator 存储；不提供未授权清理": "Read-only Configurator storage inventory; no unauthorized cleanup.",
            "查看目标与控制目标、Restore 锁定目标相互独立": "The viewed port, Control target, and locked Restore target are independent.",
            "Restore 任务保持独立运行；切换查看工作区不会改变锁定目标。": "The Restore task keeps running independently; switching workspaces does not change the locked target.",
            "关闭提示": "Dismiss",
            "减少动态效果": "Reduce Motion",
            "降低透明度": "Reduce Transparency",
            "提高对比度": "Increase Contrast",
            "显示密度": "Display Density",
            "当前查看 · 跟随左侧": "Viewing · Follow Left",
            "当前查看 · ": "Viewing · ",
            "固定查看：": "Pin View: ",
            "已固定端口不可用": "Pinned port unavailable",
            "详情": "Details",
            "仅当前操作接口": "Active control port only",
            "简洁": "Simple",
            "常用": "Standard",
            "全部": "All",
            "当前状态": "Current state",
            "上次识别": "Last seen",
            "当前没有可展示的操作端口": "No active control port to display",
            "展开接口与设备树": "Expand interface and device tree",
            "采集会话不会被清空；执行时使用当前端口/控制器/RID。": "The capture session will not be cleared. Execution uses the current port, controller, and RID.",
            "刷新": "Refresh",
            "导出诊断 JSON": "Export Diagnostic JSON",
            "正在后台读取系统信息…": "Reading system information in the background…",
            "系统只读快照 · 物理接口归属待确认": "Read-only system snapshot · Physical-port attribution pending",
            "原始只读属性": "Raw read-only properties",
            "Thunderbolt / USB4 系统报告": "Thunderbolt / USB4 system report",
            "选择左侧节点查看系统记录。": "Select a node on the left to view its system record.",
            "控制接口": "Control port",
            "端口校准": "Port calibration",
            "设备身份": "Device identity",
            "识别状态": "Identity status",
            "机型": "Model",
            "型号待确认": "Model pending confirmation",
            "上游节点": "Upstream node",
            "物理端口待确认": "Physical port pending confirmation",
            "主界面只读关联": "Main UI read-only association",
            "供电选项": "Power options",
            "系统未提供": "Not provided by system",
            "物理归属未证实": "Physical ownership not proven",
            "完整设备身份、USB-C、PD、HPM、USB4、Thunderbolt 与设备树": "Full device identity, USB-C, PD, HPM, USB4, Thunderbolt, and device tree",
            "锁定目标、固件身份、任务状态与真实执行输出": "Locked target, firmware identity, task state, and real execution output",
            "独立 RLM 会话与原始记录；不与 cfgutil 实时输出混用": "Independent RLM session and raw records, kept separate from cfgutil live output",
            "进入恢复模式": "Enter Recovery",
            "跟随当前操作接口": "Follow Active Port",
            "自动跟随": "Auto-follow",
            "恢复自动跟随": "Resume Auto-follow",
            "自动导航": "Auto Navigation",
            "恢复自动导航": "Resume Auto Navigation",
            "前往固件与恢复": "Open Firmware & Restore",
            "外观与动效": "Appearance & Motion",
            "视觉参数只改变材质、空间和反馈，不参与设备控制、端口解析、Restore 或 RLM 的状态判断。": "Visual settings change only materials, depth, and feedback. They never affect device control, port parsing, Restore, or RLM state.",
            "实时预览": "Live Preview",
            "当前操作接口": "Active Control Port",
            "未选择物理端口": "No physical port selected",
            "预设": "Presets",
            "视觉方向": "Visual Direction",
            "外观": "Appearance",
            "材质、空间与动效": "Material, Depth & Motion",
            "装饰动效": "Decorative Motion",
            "系统辅助功能": "System Accessibility",
            "恢复默认": "Restore Defaults",
            "纯净": "Pure",
            "均衡": "Balanced",
            "沉浸": "Immersive",
            "自定义": "Custom",
            "低装饰、低动效，优先长时间阅读与稳定功耗": "Low decoration and motion for long reading sessions and stable power use.",
            "克制的材质与反馈，日常维修推荐默认": "Restrained materials and feedback for everyday repair work.",
            "更完整的层次与局部环境反馈": "Deeper hierarchy and local ambient feedback.",
            "独立参数，不再跟随预设覆盖": "Independent parameters no longer controlled by a preset.",
            "轻盈材质与克制层次，接近 Apple 原生表达": "Light materials and restrained hierarchy close to Apple’s native expression.",
            "石墨工程表面、清晰字段与低强度状态光": "Graphite engineering surfaces, crisp fields, and low-intensity status light.",
            "更明显的空间层次，仍保持专业数据可读性": "More spatial depth while keeping technical data readable.",
            "跟随系统": "Use System Setting",
            "浅色": "Light",
            "深色": "Dark",
            "玻璃材质强度": "Glass Strength",
            "影响工具栏与浮层；工程数据面保持不透明": "Affects toolbars and floating surfaces; technical data surfaces remain opaque.",
            "边缘光效": "Edge Light",
            "只影响 Hover、选中和焦点边缘": "Affects only hover, selection, and focused edges.",
            "空间悬浮深度": "Floating Depth",
            "影响阴影、层差和轻微抬升": "Affects shadows, layer separation, and subtle lift.",
            "动效强度": "Motion Strength",
            "影响 Hover、按压、工作区切换和相关动画": "Affects hover, press, workspace transitions, and related animation.",
            "环境呼吸": "Ambient Breathing",
            "窗口激活时显示极低频背景亮度变化": "Adds a very slow background luminance change while the window is active.",
            "粒子背景": "Particle Background",
            "少量低速点光；默认关闭，不影响按钮命中区": "A small number of slow points. Off by default and never changes button hit areas.",
            "视差与局部高光": "Parallax & Local Highlight",
            "只改变光影，不移动控件点击区域": "Changes light only and never moves clickable areas.",
            "高级 3D": "Advanced 3D",
            "仅限轻微空间层次；Reduce Motion 时归零": "Limited to subtle depth and disabled by Reduce Motion.",
            "辅助功能优先于视觉预设。降低动效或透明度后，全部设备控制、Restore 与日志功能保持可用。": "Accessibility overrides visual presets. Reduced motion or transparency keeps all device control, Restore, and logging available.",
            "当前参数已偏离预设，自动标记为“自定义”。": "Current values differ from a preset and are marked as Custom.",
            "锁定的 Restore 目标": "Locked Restore Target",
            "查看锁定目标与本次日志策略": "Review Locked Target and This Run's Log Policy",
            "控制目标不会被左侧端口或右侧查看端口切换": "The Control target does not change when the left Control port or right Observe port changes.",
            "Restore 尝试：": "Restore attempt: ",
            "Restore 实时输出": "Restore Live Output",
            "cfgutil 内存尾部": "cfgutil in-memory tail",
            "此面板仅展示当前 cfgutil 子进程的有界内存输出；原始日志保存和 RLM 状态以锁定任务摘要为准。": "This panel shows only bounded in-memory output from the current cfgutil subprocess. Raw-log saving and RLM status are shown in the locked task summary.",
            "等待 cfgutil 输出…": "Waiting for cfgutil output…",
            "cfgutil 尚未实际启动；当前没有子进程输出。": "cfgutil has not actually started; there is no subprocess output yet.",
            "Restore 正在执行；取消入口保持可见。": "Restore is running; Cancel remains visible.",
            "Restore 启动准备中；cfgutil 尚未确认运行。": "Restore startup is being prepared; cfgutil has not been confirmed running.",
            "本次原始日志：已请求保存": "Raw log for this run: requested",
            "本次原始日志：未保存": "Raw log for this run: not saved",
            "USB 观察已看到设备，但接口树尚无可靠物理归属。": "USB observation sees a device, but the interface tree has no reliable physical-port attribution.",
            "Helper：": "Helper: ",
            "已授权": "Authorized",
            "未授权": "Not authorized",
            "检测失败": "Detection failed",
            "已启用": "Enabled",
            "已选择": "Selected",
            "未选择": "Not selected",
        ],
        "zh-Hant": [
            "模拟环境": "模擬環境",
            "专业 Mac 设备控制、USB-C 证据与 Restore 工作台": "專業 Mac 裝置控制、USB-C 證據與 Restore 工作台",
            "Configurator 存储": "Configurator 儲存",
            "快捷控制": "快速控制",
            "物理端口": "實體連接埠",
            "RLM 日志": "RLM 日誌",
            "只读盘点 Configurator 存储；不提供未授权清理": "以唯讀方式盤點 Configurator 儲存空間；不提供未授權清理",
            "查看目标与控制目标、Restore 锁定目标相互独立": "檢視目標、控制目標與已鎖定的 Restore 目標彼此獨立",
            "Restore 任务保持独立运行；切换查看工作区不会改变锁定目标。": "Restore 任務會獨立持續執行；切換檢視工作區不會改變已鎖定目標。",
            "关闭提示": "關閉提示",
            "减少动态效果": "減少動態效果",
            "降低透明度": "降低透明效果",
            "提高对比度": "提高對比度",
            "显示密度": "顯示密度",
            "当前查看 · 跟随左侧": "目前檢視 · 跟隨左側",
            "当前查看 · ": "目前檢視 · ",
            "固定查看：": "固定檢視：",
            "已固定端口不可用": "已固定連接埠無法使用",
            "详情": "詳細資料",
            "仅当前操作接口": "僅限目前操作連接埠",
            "简洁": "簡潔",
            "常用": "常用",
            "全部": "全部",
            "当前状态": "目前狀態",
            "上次识别": "上次識別",
            "当前没有可展示的操作端口": "目前沒有可顯示的操作連接埠",
            "展开接口与设备树": "展開介面與裝置樹",
            "采集会话不会被清空；执行时使用当前端口/控制器/RID。": "擷取工作階段不會被清空；執行時使用目前連接埠、控制器與 RID。",
            "刷新": "重新整理",
            "导出诊断 JSON": "匯出診斷 JSON",
            "正在后台读取系统信息…": "正在背景讀取系統資訊…",
            "系统只读快照 · 物理接口归属待确认": "系統唯讀快照 · 實體連接埠歸屬待確認",
            "原始只读属性": "原始唯讀屬性",
            "Thunderbolt / USB4 系统报告": "Thunderbolt / USB4 系統報告",
            "选择左侧节点查看系统记录。": "選擇左側節點以查看系統記錄。",
            "控制接口": "控制連接埠",
            "端口校准": "連接埠校準",
            "设备身份": "裝置身分",
            "识别状态": "識別狀態",
            "机型": "機型",
            "型号待确认": "機型待確認",
            "上游节点": "上游節點",
            "物理端口待确认": "實體連接埠待確認",
            "主界面只读关联": "主介面唯讀關聯",
            "供电选项": "供電選項",
            "系统未提供": "系統未提供",
            "物理归属未证实": "實體歸屬未證實",
            "完整设备身份、USB-C、PD、HPM、USB4、Thunderbolt 与设备树": "完整裝置身分、USB-C、PD、HPM、USB4、Thunderbolt 與裝置樹",
            "锁定目标、固件身份、任务状态与真实执行输出": "鎖定目標、韌體身分、任務狀態與真實執行輸出",
            "独立 RLM 会话与原始记录；不与 cfgutil 实时输出混用": "獨立 RLM 工作階段與原始記錄；不與 cfgutil 即時輸出混用",
            "进入恢复模式": "進入復原模式",
            "跟随当前操作接口": "跟隨目前操作連接埠",
            "自动跟随": "自動跟隨",
            "恢复自动跟随": "恢復自動跟隨",
            "自动导航": "自動導覽",
            "恢复自动导航": "恢復自動導覽",
            "前往固件与恢复": "前往韌體與恢復",
            "外观与动效": "外觀與動效",
            "视觉参数只改变材质、空间和反馈，不参与设备控制、端口解析、Restore 或 RLM 的状态判断。": "視覺參數只改變材質、空間與回饋，不參與裝置控制、連接埠解析、Restore 或 RLM 狀態判斷。",
            "实时预览": "即時預覽",
            "当前操作接口": "目前操作連接埠",
            "未选择物理端口": "尚未選擇實體連接埠",
            "预设": "預設",
            "视觉方向": "視覺方向",
            "外观": "外觀",
            "材质、空间与动效": "材質、空間與動效",
            "装饰动效": "裝飾動效",
            "系统辅助功能": "系統輔助功能",
            "恢复默认": "恢復預設",
            "纯净": "純淨",
            "均衡": "均衡",
            "沉浸": "沉浸",
            "自定义": "自訂",
            "低装饰、低动效，优先长时间阅读与稳定功耗": "低裝飾、低動效，優先支援長時間閱讀與穩定功耗。",
            "克制的材质与反馈，日常维修推荐默认": "克制的材質與回饋，適合作為日常維修預設。",
            "更完整的层次与局部环境反馈": "更完整的層次與局部環境回饋。",
            "独立参数，不再跟随预设覆盖": "獨立參數，不再由預設覆寫。",
            "轻盈材质与克制层次，接近 Apple 原生表达": "輕盈材質與克制層次，接近 Apple 原生表現。",
            "石墨工程表面、清晰字段与低强度状态光": "石墨工程表面、清晰欄位與低強度狀態光。",
            "更明显的空间层次，仍保持专业数据可读性": "更明顯的空間層次，同時維持專業資料可讀性。",
            "跟随系统": "跟隨系統",
            "浅色": "淺色",
            "深色": "深色",
            "玻璃材质强度": "玻璃材質強度",
            "影响工具栏与浮层；工程数据面保持不透明": "影響工具列與浮層；工程資料面維持不透明。",
            "边缘光效": "邊緣光效",
            "只影响 Hover、选中和焦点边缘": "只影響 Hover、選取與焦點邊緣。",
            "空间悬浮深度": "空間懸浮深度",
            "影响阴影、层差和轻微抬升": "影響陰影、層差與輕微抬升。",
            "动效强度": "動效強度",
            "影响 Hover、按压、工作区切换和相关动画": "影響 Hover、按壓、工作區切換與相關動畫。",
            "环境呼吸": "環境呼吸",
            "窗口激活时显示极低频背景亮度变化": "視窗啟用時顯示極低頻背景亮度變化。",
            "粒子背景": "粒子背景效果",
            "少量低速点光；默认关闭，不影响按钮命中区": "少量低速點光；預設關閉，不影響按鈕點擊區。",
            "视差与局部高光": "視差與局部高光",
            "只改变光影，不移动控件点击区域": "只改變光影，不移動控制項點擊區。",
            "高级 3D": "進階 3D",
            "仅限轻微空间层次；Reduce Motion 时归零": "僅限輕微空間層次；Reduce Motion 時關閉。",
            "辅助功能优先于视觉预设。降低动效或透明度后，全部设备控制、Restore 与日志功能保持可用。": "輔助功能優先於視覺預設。降低動效或透明度後，全部裝置控制、Restore 與日誌功能仍可使用。",
            "当前参数已偏离预设，自动标记为“自定义”。": "目前參數已偏離預設，會自動標記為「自訂」。",
            "锁定的 Restore 目标": "鎖定的 Restore 目標",
            "查看锁定目标与本次日志策略": "查看鎖定目標與本次日誌策略",
            "控制目标不会被左侧端口或右侧查看端口切换": "左側控制連接埠或右側檢視連接埠切換時，不會改寫控制目標。",
            "Restore 尝试：": "Restore 嘗試：",
            "Restore 实时输出": "Restore 即時輸出",
            "cfgutil 内存尾部": "cfgutil 記憶體尾部",
            "此面板仅展示当前 cfgutil 子进程的有界内存输出；原始日志保存和 RLM 状态以锁定任务摘要为准。": "此面板僅顯示目前 cfgutil 子程序的有界記憶體輸出；原始日誌保存與 RLM 狀態以鎖定任務摘要為準。",
            "等待 cfgutil 输出…": "等待 cfgutil 輸出…",
            "cfgutil 尚未实际启动；当前没有子进程输出。": "cfgutil 尚未實際啟動；目前沒有子程序輸出。",
            "Restore 正在执行；取消入口保持可见。": "Restore 正在執行；取消入口保持可見。",
            "Restore 启动准备中；cfgutil 尚未确认运行。": "Restore 正在準備啟動；尚未確認 cfgutil 執行。",
            "本次原始日志：已请求保存": "本次原始日誌：已要求儲存",
            "本次原始日志：未保存": "本次原始日誌：未儲存",
            "USB 观察已看到设备，但接口树尚无可靠物理归属。": "USB 觀察已看到裝置，但介面樹尚無可靠實體連接埠歸屬。",
            "Helper：": "Helper：",
            "已授权": "已授權",
            "未授权": "未授權",
            "检测失败": "偵測失敗",
            "已启用": "已啟用",
            "已选择": "已選取",
            "未选择": "未選取",
        ],
        "ja": [
            "模拟环境": "シミュレーション",
            "专业 Mac 设备控制、USB-C 证据与 Restore 工作台": "プロ向け Mac 制御、USB-C 証拠、Restore ワークスペース",
            "Configurator 存储": "Configurator ストレージ",
            "快捷控制": "クイック操作",
            "物理端口": "物理ポート",
            "RLM 日志": "RLM ログ",
            "只读盘点 Configurator 存储；不提供未授权清理": "Configurator ストレージを読み取り専用で一覧表示します。未承認のクリーンアップは行いません。",
            "查看目标与控制目标、Restore 锁定目标相互独立": "表示ポート、制御対象、ロックされた Restore 対象は互いに独立しています。",
            "Restore 任务保持独立运行；切换查看工作区不会改变锁定目标。": "Restore タスクは独立して継続します。表示ワークスペースを切り替えてもロック対象は変わりません。",
            "关闭提示": "通知を閉じる",
            "减少动态效果": "モーションを減らす",
            "降低透明度": "透明度を下げる",
            "提高对比度": "コントラストを上げる",
            "显示密度": "表示密度",
            "当前查看 · 跟随左侧": "表示対象 · 左側に追従",
            "当前查看 · ": "表示対象 · ",
            "固定查看：": "表示を固定：",
            "已固定端口不可用": "固定ポートは利用できません",
            "详情": "詳細",
            "仅当前操作接口": "現在の操作ポートのみ",
            "简洁": "簡潔",
            "常用": "標準",
            "全部": "すべて",
            "当前状态": "現在の状態",
            "上次识别": "前回の認識",
            "当前没有可展示的操作端口": "表示できる操作ポートがありません",
            "展开接口与设备树": "インターフェイスとデバイスツリーを展開",
            "采集会话不会被清空；执行时使用当前端口/控制器/RID。": "キャプチャセッションは消去されません。実行には現在のポート、コントローラ、RID を使用します。",
            "刷新": "更新",
            "导出诊断 JSON": "診断 JSON を書き出す",
            "正在后台读取系统信息…": "バックグラウンドでシステム情報を読み取り中…",
            "系统只读快照 · 物理接口归属待确认": "システムの読み取り専用スナップショット · 物理ポート帰属は確認待ち",
            "原始只读属性": "元の読み取り専用属性",
            "Thunderbolt / USB4 系统报告": "Thunderbolt / USB4 システムレポート",
            "选择左侧节点查看系统记录。": "左側のノードを選択してシステム記録を表示します。",
            "控制接口": "制御ポート",
            "端口校准": "ポート校正",
            "设备身份": "デバイス ID",
            "识别状态": "認識状態",
            "机型": "機種",
            "型号待确认": "機種確認待ち",
            "上游节点": "上流ノード",
            "物理端口待确认": "物理ポート確認待ち",
            "主界面只读关联": "メイン画面の読み取り専用関連",
            "供电选项": "給電オプション",
            "系统未提供": "システム未提供",
            "物理归属未证实": "物理的な帰属は未確認",
            "完整设备身份、USB-C、PD、HPM、USB4、Thunderbolt 与设备树": "完全なデバイス ID、USB-C、PD、HPM、USB4、Thunderbolt、デバイスツリー",
            "锁定目标、固件身份、任务状态与真实执行输出": "固定ターゲット、ファームウェア ID、タスク状態、実際の実行出力",
            "独立 RLM 会话与原始记录；不与 cfgutil 实时输出混用": "独立した RLM セッションと生ログ。cfgutil のライブ出力とは分離します。",
            "进入恢复模式": "リカバリモードへ",
            "跟随当前操作接口": "操作ポートに追従",
            "自动跟随": "自動追従",
            "恢复自动跟随": "自動追従を再開",
            "自动导航": "自動ナビゲーション",
            "恢复自动导航": "自動ナビゲーションを再開",
            "前往固件与恢复": "ファームウェアと復元を開く",
            "外观与动效": "外観とモーション",
            "视觉参数只改变材质、空间和反馈，不参与设备控制、端口解析、Restore 或 RLM 的状态判断。": "外観設定は素材、奥行き、フィードバックだけを変更し、デバイス制御、ポート解析、Restore、RLM の状態には影響しません。",
            "实时预览": "ライブプレビュー",
            "当前操作接口": "現在の操作ポート",
            "未选择物理端口": "物理ポートが未選択です",
            "预设": "プリセット",
            "视觉方向": "ビジュアル方向",
            "外观": "外観",
            "材质、空间与动效": "素材、奥行き、モーション",
            "装饰动效": "装飾モーション",
            "系统辅助功能": "システム補助機能",
            "恢复默认": "既定値に戻す",
            "纯净": "ピュア",
            "均衡": "バランス",
            "沉浸": "イマーシブ",
            "自定义": "カスタム",
            "低装饰、低动效，优先长时间阅读与稳定功耗": "装飾と動きを抑え、長時間の閲覧と安定した消費電力を優先します。",
            "克制的材质与反馈，日常维修推荐默认": "控えめな素材とフィードバックで、日常修理に推奨される既定値です。",
            "更完整的层次与局部环境反馈": "より豊かな階層と局所的な環境フィードバック。",
            "独立参数，不再跟随预设覆盖": "プリセットに上書きされない独立した設定です。",
            "轻盈材质与克制层次，接近 Apple 原生表达": "軽やかな素材と控えめな階層で、Apple のネイティブ表現に近づけます。",
            "石墨工程表面、清晰字段与低强度状态光": "グラファイト調の表面、明瞭な項目、低強度の状態光。",
            "更明显的空间层次，仍保持专业数据可读性": "専門データの可読性を保ちながら空間的な奥行きを強めます。",
            "跟随系统": "システムに合わせる",
            "浅色": "ライト",
            "深色": "ダーク",
            "玻璃材质强度": "ガラス素材の強さ",
            "影响工具栏与浮层；工程数据面保持不透明": "ツールバーと浮遊面に適用し、技術データ面は不透明のまま維持します。",
            "边缘光效": "エッジ光",
            "只影响 Hover、选中和焦点边缘": "Hover、選択、フォーカス時のエッジだけに適用します。",
            "空间悬浮深度": "浮遊する奥行き",
            "影响阴影、层差和轻微抬升": "影、レイヤー差、わずかな浮き上がりに影響します。",
            "动效强度": "モーション強度",
            "影响 Hover、按压、工作区切换和相关动画": "Hover、押下、ワークスペース切替などの動きに影響します。",
            "环境呼吸": "環境の呼吸",
            "窗口激活时显示极低频背景亮度变化": "ウィンドウがアクティブな間だけ、非常にゆっくりした背景の明暗変化を表示します。",
            "粒子背景": "パーティクル背景",
            "少量低速点光；默认关闭，不影响按钮命中区": "少数の低速な光点を表示します。既定ではオフで、ボタンのクリック領域を変えません。",
            "视差与局部高光": "視差と局所ハイライト",
            "只改变光影，不移动控件点击区域": "光だけを変更し、クリック領域は移動しません。",
            "高级 3D": "高度な 3D",
            "仅限轻微空间层次；Reduce Motion 时归零": "控えめな奥行きに限定し、Reduce Motion では無効になります。",
            "辅助功能优先于视觉预设。降低动效或透明度后，全部设备控制、Restore 与日志功能保持可用。": "補助機能は外観プリセットより優先されます。動きや透明性を減らしても、デバイス制御、Restore、ログ機能はすべて利用できます。",
            "当前参数已偏离预设，自动标记为“自定义”。": "現在の設定はプリセットから変更されており、カスタムとして扱われます。",
            "锁定的 Restore 目标": "固定された Restore ターゲット",
            "查看锁定目标与本次日志策略": "固定ターゲットと今回のログ方針を確認",
            "控制目标不会被左侧端口或右侧查看端口切换": "左側の制御ポートや右側の表示ポートを切り替えても制御ターゲットは変わりません。",
            "Restore 尝试：": "Restore 試行：",
            "Restore 实时输出": "Restore ライブ出力",
            "cfgutil 内存尾部": "cfgutil メモリ内テール",
            "此面板仅展示当前 cfgutil 子进程的有界内存输出；原始日志保存和 RLM 状态以锁定任务摘要为准。": "このパネルは現在の cfgutil 子プロセスの制限付きメモリ内出力のみを表示します。raw ログ保存と RLM 状態は固定タスク概要に表示されます。",
            "等待 cfgutil 输出…": "cfgutil の出力を待機中…",
            "cfgutil 尚未实际启动；当前没有子进程输出。": "cfgutil はまだ実際には起動しておらず、子プロセス出力はありません。",
            "Restore 正在执行；取消入口保持可见。": "Restore 実行中です。キャンセルは常に表示されます。",
            "Restore 启动准备中；cfgutil 尚未确认运行。": "Restore の起動を準備中です。cfgutil の実行はまだ確認されていません。",
            "本次原始日志：已请求保存": "今回の raw ログ：保存を要求済み",
            "本次原始日志：未保存": "今回の raw ログ：未保存",
            "USB 观察已看到设备，但接口树尚无可靠物理归属。": "USB 観察ではデバイスを検出していますが、インターフェイスツリーには信頼できる物理ポート帰属がありません。",
            "Helper：": "Helper: ",
            "已授权": "認証済み",
            "未授权": "未認証",
            "检测失败": "検出失敗",
            "已启用": "有効",
            "已选择": "選択済み",
            "未选择": "未選択",
        ],
        "ko": [
            "模拟环境": "시뮬레이션 환경",
            "专业 Mac 设备控制、USB-C 证据与 Restore 工作台": "전문 Mac 제어, USB-C 증거 및 Restore 작업 공간",
            "Configurator 存储": "Configurator 저장 공간",
            "快捷控制": "빠른 제어",
            "物理端口": "물리 포트",
            "RLM 日志": "RLM 로그",
            "只读盘点 Configurator 存储；不提供未授权清理": "Configurator 저장 공간을 읽기 전용으로 점검하며 승인되지 않은 정리를 제공하지 않습니다.",
            "查看目标与控制目标、Restore 锁定目标相互独立": "보기 포트, 제어 대상, 잠긴 Restore 대상은 서로 독립적입니다.",
            "Restore 任务保持独立运行；切换查看工作区不会改变锁定目标。": "Restore 작업은 독립적으로 계속 실행되며 보기 작업 공간을 전환해도 잠긴 대상은 바뀌지 않습니다.",
            "关闭提示": "알림 닫기",
            "减少动态效果": "동작 줄이기",
            "降低透明度": "투명도 줄이기",
            "提高对比度": "대비 높이기",
            "显示密度": "표시 밀도",
            "当前查看 · 跟随左侧": "보기 · 왼쪽 따르기",
            "当前查看 · ": "보기 · ",
            "固定查看：": "보기 고정: ",
            "已固定端口不可用": "고정 포트를 사용할 수 없음",
            "详情": "세부 정보",
            "仅当前操作接口": "현재 작업 포트만",
            "简洁": "간단",
            "常用": "일반",
            "全部": "전체",
            "当前状态": "현재 상태",
            "上次识别": "마지막 인식",
            "当前没有可展示的操作端口": "표시할 작업 포트가 없습니다",
            "展开接口与设备树": "인터페이스 및 기기 트리 펼치기",
            "采集会话不会被清空；执行时使用当前端口/控制器/RID。": "캡처 세션은 지워지지 않습니다. 실행에는 현재 포트, 컨트롤러, RID를 사용합니다.",
            "刷新": "새로 고침",
            "导出诊断 JSON": "진단 JSON 내보내기",
            "正在后台读取系统信息…": "백그라운드에서 시스템 정보 읽는 중…",
            "系统只读快照 · 物理接口归属待确认": "시스템 읽기 전용 스냅샷 · 물리 포트 귀속 확인 대기",
            "原始只读属性": "원본 읽기 전용 속성",
            "Thunderbolt / USB4 系统报告": "Thunderbolt / USB4 시스템 보고서",
            "选择左侧节点查看系统记录。": "왼쪽 노드를 선택하여 시스템 기록을 확인하십시오.",
            "控制接口": "제어 포트",
            "端口校准": "포트 보정",
            "设备身份": "기기 ID",
            "识别状态": "인식 상태",
            "机型": "모델",
            "型号待确认": "모델 확인 대기",
            "上游节点": "상위 노드",
            "物理端口待确认": "물리 포트 확인 대기",
            "主界面只读关联": "기본 화면 읽기 전용 연결",
            "供电选项": "전원 옵션",
            "系统未提供": "시스템에서 제공하지 않음",
            "物理归属未证实": "물리적 귀속 미확인",
            "完整设备身份、USB-C、PD、HPM、USB4、Thunderbolt 与设备树": "전체 기기 ID, USB-C, PD, HPM, USB4, Thunderbolt 및 기기 트리",
            "锁定目标、固件身份、任务状态与真实执行输出": "고정 대상, 펌웨어 ID, 작업 상태 및 실제 실행 출력",
            "独立 RLM 会话与原始记录；不与 cfgutil 实时输出混用": "독립 RLM 세션과 원본 기록. cfgutil 실시간 출력과 혼용하지 않습니다.",
            "进入恢复模式": "복구 모드 진입",
            "跟随当前操作接口": "현재 작업 포트 따르기",
            "自动跟随": "자동 따르기",
            "恢复自动跟随": "자동 따르기 재개",
            "自动导航": "자동 탐색",
            "恢复自动导航": "자동 탐색 재개",
            "前往固件与恢复": "펌웨어 및 복원 열기",
            "外观与动效": "외관 및 모션",
            "视觉参数只改变材质、空间和反馈，不参与设备控制、端口解析、Restore 或 RLM 的状态判断。": "시각 설정은 재질, 깊이, 피드백만 변경하며 기기 제어, 포트 분석, Restore 또는 RLM 상태에는 영향을 주지 않습니다.",
            "实时预览": "실시간 미리보기",
            "当前操作接口": "현재 작업 포트",
            "未选择物理端口": "물리 포트가 선택되지 않음",
            "预设": "프리셋",
            "视觉方向": "시각 방향",
            "外观": "외관",
            "材质、空间与动效": "재질, 깊이 및 모션",
            "装饰动效": "장식 모션",
            "系统辅助功能": "시스템 접근성",
            "恢复默认": "기본값 복원",
            "纯净": "순수",
            "均衡": "균형",
            "沉浸": "몰입",
            "自定义": "사용자 설정",
            "低装饰、低动效，优先长时间阅读与稳定功耗": "장식과 모션을 줄여 장시간 읽기와 안정적인 전력 사용을 우선합니다.",
            "克制的材质与反馈，日常维修推荐默认": "절제된 재질과 피드백으로 일상 수리에 권장되는 기본값입니다.",
            "更完整的层次与局部环境反馈": "더 풍부한 계층과 국소 환경 피드백을 제공합니다.",
            "独立参数，不再跟随预设覆盖": "프리셋이 덮어쓰지 않는 독립 설정입니다.",
            "轻盈材质与克制层次，接近 Apple 原生表达": "가벼운 재질과 절제된 계층으로 Apple의 네이티브 표현에 가깝습니다.",
            "石墨工程表面、清晰字段与低强度状态光": "그래파이트 엔지니어링 표면, 선명한 필드, 낮은 강도의 상태광을 사용합니다.",
            "更明显的空间层次，仍保持专业数据可读性": "전문 데이터 가독성을 유지하면서 공간 계층을 더 분명하게 표현합니다.",
            "跟随系统": "시스템 설정 따르기",
            "浅色": "라이트",
            "深色": "다크",
            "玻璃材质强度": "유리 재질 강도",
            "影响工具栏与浮层；工程数据面保持不透明": "도구 막대와 부유 표면에 적용하며 기술 데이터 표면은 불투명하게 유지합니다.",
            "边缘光效": "가장자리 광효과",
            "只影响 Hover、选中和焦点边缘": "Hover, 선택 및 포커스 가장자리에만 적용합니다.",
            "空间悬浮深度": "공간 부유 깊이",
            "影响阴影、层差和轻微抬升": "그림자, 계층 간격 및 약한 부양 효과에 영향을 줍니다.",
            "动效强度": "모션 강도",
            "影响 Hover、按压、工作区切换和相关动画": "Hover, 누름, 작업 공간 전환 및 관련 애니메이션에 영향을 줍니다.",
            "环境呼吸": "환경 호흡",
            "窗口激活时显示极低频背景亮度变化": "창이 활성화된 동안 매우 느린 배경 밝기 변화를 표시합니다.",
            "粒子背景": "입자 배경",
            "少量低速点光；默认关闭，不影响按钮命中区": "소수의 느린 광점을 표시합니다. 기본적으로 꺼져 있으며 버튼 클릭 영역을 바꾸지 않습니다.",
            "视差与局部高光": "시차 및 국소 하이라이트",
            "只改变光影，不移动控件点击区域": "빛과 그림자만 바꾸며 클릭 영역은 이동하지 않습니다.",
            "高级 3D": "고급 3D",
            "仅限轻微空间层次；Reduce Motion 时归零": "미세한 공간 깊이에만 사용하며 Reduce Motion에서는 비활성화됩니다.",
            "辅助功能优先于视觉预设。降低动效或透明度后，全部设备控制、Restore 与日志功能保持可用。": "접근성 설정이 시각 프리셋보다 우선합니다. 모션 또는 투명도를 줄여도 모든 기기 제어, Restore 및 로그 기능은 계속 사용할 수 있습니다.",
            "当前参数已偏离预设，自动标记为“自定义”。": "현재 값이 프리셋과 달라 사용자 설정으로 표시됩니다.",
            "锁定的 Restore 目标": "고정된 Restore 대상",
            "查看锁定目标与本次日志策略": "고정 대상 및 이번 로그 정책 보기",
            "控制目标不会被左侧端口或右侧查看端口切换": "왼쪽 제어 포트 또는 오른쪽 보기 포트를 바꿔도 제어 대상은 변경되지 않습니다.",
            "Restore 尝试：": "Restore 시도: ",
            "Restore 实时输出": "Restore 실시간 출력",
            "cfgutil 内存尾部": "cfgutil 메모리 테일",
            "此面板仅展示当前 cfgutil 子进程的有界内存输出；原始日志保存和 RLM 状态以锁定任务摘要为准。": "이 패널은 현재 cfgutil 하위 프로세스의 제한된 메모리 출력만 표시합니다. raw 로그 저장 및 RLM 상태는 잠긴 작업 요약에 표시됩니다.",
            "等待 cfgutil 输出…": "cfgutil 출력 대기 중…",
            "cfgutil 尚未实际启动；当前没有子进程输出。": "cfgutil이 아직 실제로 시작되지 않아 하위 프로세스 출력이 없습니다.",
            "Restore 正在执行；取消入口保持可见。": "Restore 실행 중이며 취소는 항상 표시됩니다.",
            "Restore 启动准备中；cfgutil 尚未确认运行。": "Restore 시작을 준비 중이며 cfgutil 실행은 아직 확인되지 않았습니다.",
            "本次原始日志：已请求保存": "이번 원본 로그: 저장 요청됨",
            "本次原始日志：未保存": "이번 원본 로그: 저장 안 함",
            "USB 观察已看到设备，但接口树尚无可靠物理归属。": "USB 관찰에서는 기기를 확인했지만 인터페이스 트리에 신뢰할 수 있는 물리 포트 귀속이 없습니다.",
            "Helper：": "Helper: ",
            "已授权": "승인됨",
            "未授权": "승인되지 않음",
            "检测失败": "검사 실패",
            "已启用": "활성화됨",
            "已选择": "선택됨",
            "未选择": "선택되지 않음",
        ],
    ]

    private static let firmwarePreferencesFix: [String: [String: String]] = [
        "en": [
            "固件偏好": "Firmware Preferences",
            "偏好只决定 Restore 准备时的候选固件，不会自动开始刷机，也不会绕过文件身份、BuildManifest 与兼容性复验。": "Preferences only choose Restore preparation candidates. They never start a restore or bypass file identity, BuildManifest, and compatibility revalidation.",
            "本地固件库": "Local Firmware Library",
            "添加固件文件夹…": "Add Firmware Folder…",
            "刷新固件库": "Refresh Firmware Library",
            "个可用固件": "usable firmware files",
            "尚未设置全局默认": "No global default configured",
            "选择全局默认固件": "Choose Global Default Firmware",
            "全局默认固件": "Global Default Firmware",
            "全局默认只是跨机型首选。机型专属默认优先于全局默认；兼容性不足时仍需人工确认。": "A global default is only a cross-model preference. A model default takes precedence, and manual confirmation is still required when compatibility is uncertain.",
            "机型默认固件": "Model Default Firmware",
            "尚未配置机型默认固件": "No model default firmware configured",
            "添加机型默认固件": "Add Model Default Firmware",
            "机型标识符，例如 MacBookPro18,2": "Model identifier, e.g. MacBookPro18,2",
            "选择固件": "Choose Firmware",
            "已选择固件": "Firmware Selected",
            "添加": "Add",
            "使用当前设备机型：": "Use current model: ",
            "该机型标识符不在内置可靠机型目录中。": "This model identifier is not in the built-in verified model catalog.",
            "最近使用": "Recently Used",
            "尚无最近使用记录": "No recent use records",
            "尚无实际启动过 Restore 的固件记录": "No firmware has actually launched a Restore yet",
            "机型未知": "Model unknown",
            "使用": "Use",
            "更换": "Change",
            "删除": "Delete",
            "清除": "Clear",
            "设为全局默认": "Set as Global Default",
            "设为当前机型默认": "Set as Model Default",
            "备份并重置固件偏好…": "Back Up and Reset Firmware Preferences…",
            "固件偏好文件无法读取；已保留原文件，等待用户重新设置。": "The firmware preference file cannot be read. The original file was preserved and awaits an explicit reset.",
            "固件文件已移动、删除，或当前固件库尚未扫描到。": "The firmware file was moved, deleted, or has not been found by the current library scan.",
            "固件文件身份已变化，原偏好不会自动替换为另一份文件。": "The firmware file identity changed. The preference is not silently replaced with another file.",
            "该固件是 iCloud 占位文件，请先下载到本机。": "This firmware is an iCloud placeholder. Download it locally first.",
            "该固件当前无法读取。": "This firmware cannot currently be read.",
            "固件已损坏或缺少有效 BuildManifest。": "The firmware is damaged or lacks a valid BuildManifest.",
            "固件文件存在多个重定位候选，需人工确认。": "Multiple relocation candidates exist for this firmware; manual confirmation is required.",
            "固件文件身份与固件库记录一致。": "The firmware file identity matches the library record.",
            "固件文件身份与 BuildManifest 复验通过。": "The firmware identity and BuildManifest revalidation passed.",
            "当前机型默认固件不可用。": "The current model-default firmware is unavailable.",
            "全局默认固件不可用。": "The global default firmware is unavailable.",
            "macOS 系统辅助功能": "macOS System Accessibility",
            "系统状态（只读）": "System Status (Read Only)",
            "不会修改 macOS 全局设置": "Does not change macOS global settings",
            "打开 macOS 辅助功能设置…": "Open macOS Accessibility Settings…",
            "无法打开 macOS 辅助功能设置。": "Unable to open macOS Accessibility Settings.",
            "系统辅助功能优先于视觉预设。应用内动效强度不会改写这些系统状态；降低动效或透明度后，全部设备控制、Restore 与日志功能保持可用。": "System accessibility overrides visual presets. In-app motion strength never changes these system states, and all device control, Restore, and logging remain available with reduced motion or transparency.",
            "Restore 准备中": "Preparing Restore",
            "Restore 已结束": "Restore Finished",
            "等待真实活动": "Waiting for Real Activity",
            "整体进度：未知": "Overall Progress: Unknown",
            "等待 cfgutil 真实阶段输出。": "Waiting for a real cfgutil stage.",
            "cfgutil 尚未报告可识别的阶段。": "cfgutil has not reported a recognizable stage.",
            "该百分比只对应当前 Step，不能推导整体完成情况。": "This percentage applies only to the current Step and cannot be used to infer overall completion.",
            "cfgutil 已报告当前阶段完成，等待下一阶段真实输出。": "cfgutil reported that the current stage is complete. Waiting for the next real stage.",
            "设备操作已结束，结果来自 cfgutil 终态。": "Device activity ended; the result is the cfgutil terminal outcome.",
        ],
        "zh-Hant": [
            "固件偏好": "韌體偏好",
            "偏好只决定 Restore 准备时的候选固件，不会自动开始刷机，也不会绕过文件身份、BuildManifest 与兼容性复验。": "偏好只決定 Restore 準備時的候選韌體，不會自動開始刷機，也不會略過檔案身分、BuildManifest 與相容性複驗。",
            "本地固件库": "本機韌體庫",
            "添加固件文件夹…": "加入韌體資料夾…",
            "刷新固件库": "重新整理韌體庫",
            "个可用固件": "個可用韌體",
            "尚未设置全局默认": "尚未設定全域預設",
            "选择全局默认固件": "選擇全域預設韌體",
            "全局默认固件": "全域預設韌體",
            "全局默认只是跨机型首选。机型专属默认优先于全局默认；兼容性不足时仍需人工确认。": "全域預設只是跨機型的首選。機型專屬預設優先，相容性不足時仍需人工確認。",
            "机型默认固件": "機型預設韌體",
            "尚未配置机型默认固件": "尚未設定機型預設韌體",
            "添加机型默认固件": "加入機型預設韌體",
            "机型标识符，例如 MacBookPro18,2": "機型識別碼，例如 MacBookPro18,2",
            "选择固件": "選擇韌體",
            "已选择固件": "已選擇韌體",
            "添加": "加入",
            "使用当前设备机型：": "使用目前裝置機型：",
            "该机型标识符不在内置可靠机型目录中。": "此機型識別碼不在內建可靠機型目錄中。",
            "最近使用": "最近使用過的",
            "尚无最近使用记录": "尚無最近使用記錄",
            "尚无实际启动过 Restore 的固件记录": "尚無實際啟動過 Restore 的韌體記錄",
            "机型未知": "機型未知",
            "使用": "使用",
            "更换": "更換",
            "删除": "刪除",
            "清除": "清除",
            "设为全局默认": "設為全域預設",
            "设为当前机型默认": "設為目前機型預設",
            "备份并重置固件偏好…": "備份並重設韌體偏好…",
            "固件偏好文件无法读取；已保留原文件，等待用户重新设置。": "韌體偏好檔案無法讀取；已保留原檔案，等待使用者明確重設。",
            "固件文件已移动、删除，或当前固件库尚未扫描到。": "韌體檔案已移動、刪除，或目前韌體庫尚未掃描到。",
            "固件文件身份已变化，原偏好不会自动替换为另一份文件。": "韌體檔案身分已變更，原偏好不會自動替換成另一個檔案。",
            "该固件是 iCloud 占位文件，请先下载到本机。": "此韌體是 iCloud 預留檔，請先下載到本機。",
            "该固件当前无法读取。": "此韌體目前無法讀取。",
            "固件已损坏或缺少有效 BuildManifest。": "韌體已損壞或缺少有效 BuildManifest。",
            "固件文件存在多个重定位候选，需人工确认。": "韌體檔案存在多個重新定位候選，需人工確認。",
            "固件文件身份与固件库记录一致。": "韌體檔案身分與韌體庫記錄一致。",
            "固件文件身份与 BuildManifest 复验通过。": "韌體檔案身分與 BuildManifest 複驗通過。",
            "当前机型默认固件不可用。": "目前機型預設韌體不可用。",
            "全局默认固件不可用。": "全域預設韌體不可用。",
            "macOS 系统辅助功能": "macOS 系統輔助功能",
            "系统状态（只读）": "系統狀態（唯讀）",
            "不会修改 macOS 全局设置": "不會修改 macOS 全域設定",
            "打开 macOS 辅助功能设置…": "開啟 macOS 輔助功能設定…",
            "无法打开 macOS 辅助功能设置。": "無法開啟 macOS 輔助功能設定。",
            "系统辅助功能优先于视觉预设。应用内动效强度不会改写这些系统状态；降低动效或透明度后，全部设备控制、Restore 与日志功能保持可用。": "系統輔助功能優先於視覺預設。應用內動效強度不會改寫這些系統狀態；降低動效或透明度後，所有裝置控制、Restore 與日誌功能仍可使用。",
            "Restore 准备中": "Restore 準備中",
            "Restore 已结束": "Restore 已結束",
            "等待真实活动": "等待真實活動",
            "整体进度：未知": "整體進度：未知",
            "等待 cfgutil 真实阶段输出。": "等待 cfgutil 真實階段輸出。",
            "cfgutil 尚未报告可识别的阶段。": "cfgutil 尚未回報可辨識的階段。",
            "该百分比只对应当前 Step，不能推导整体完成情况。": "此百分比僅對應目前 Step，不能推導整體完成情況。",
            "cfgutil 已报告当前阶段完成，等待下一阶段真实输出。": "cfgutil 已回報目前階段完成，正在等待下一階段的真實輸出。",
            "设备操作已结束，结果来自 cfgutil 终态。": "裝置操作已結束，結果來自 cfgutil 終態。",
        ],
        "ja": [
            "固件偏好": "ファームウェア設定",
            "偏好只决定 Restore 准备时的候选固件，不会自动开始刷机，也不会绕过文件身份、BuildManifest 与兼容性复验。": "設定は Restore 準備時の候補を選ぶだけで、自動開始やファイル ID、BuildManifest、互換性の再検証を省略しません。",
            "本地固件库": "ローカルファームウェアライブラリ",
            "添加固件文件夹…": "ファームウェアフォルダを追加…",
            "刷新固件库": "ファームウェアライブラリを更新",
            "个可用固件": "個の利用可能なファームウェア",
            "尚未设置全局默认": "グローバル既定は未設定",
            "选择全局默认固件": "グローバル既定ファームウェアを選択",
            "全局默认固件": "グローバル既定ファームウェア",
            "全局默认只是跨机型首选。机型专属默认优先于全局默认；兼容性不足时仍需人工确认。": "グローバル既定は機種をまたぐ候補です。機種別既定が優先され、互換性が不明な場合は手動確認が必要です。",
            "机型默认固件": "機種別既定ファームウェア",
            "尚未配置机型默认固件": "機種別既定ファームウェアは未設定",
            "添加机型默认固件": "機種別既定ファームウェアを追加",
            "机型标识符，例如 MacBookPro18,2": "機種 ID（例: MacBookPro18,2）",
            "选择固件": "ファームウェアを選択",
            "已选择固件": "選択済み",
            "添加": "追加",
            "使用当前设备机型：": "現在の機種を使用: ",
            "该机型标识符不在内置可靠机型目录中。": "この機種 ID は内蔵の検証済み機種カタログにありません。",
            "最近使用": "最近使ったもの",
            "尚无最近使用记录": "最近使用の記録はありません",
            "尚无实际启动过 Restore 的固件记录": "Restore を実際に開始したファームウェアはまだありません",
            "机型未知": "機種不明",
            "使用": "使用",
            "更换": "変更",
            "删除": "削除",
            "清除": "消去",
            "设为全局默认": "グローバル既定に設定",
            "设为当前机型默认": "現在の機種の既定に設定",
            "备份并重置固件偏好…": "バックアップして設定をリセット…",
            "固件偏好文件无法读取；已保留原文件，等待用户重新设置。": "ファームウェア設定ファイルを読み取れません。元ファイルを保持し、明示的なリセットを待っています。",
            "固件文件已移动、删除，或当前固件库尚未扫描到。": "ファームウェアファイルが移動・削除されたか、現在のライブラリで未検出です。",
            "固件文件身份已变化，原偏好不会自动替换为另一份文件。": "ファイル ID が変わりました。別ファイルへ自動置換しません。",
            "该固件是 iCloud 占位文件，请先下载到本机。": "iCloud のプレースホルダです。先にローカルへダウンロードしてください。",
            "该固件当前无法读取。": "このファームウェアは現在読み取れません。",
            "固件已损坏或缺少有效 BuildManifest。": "ファームウェアが破損しているか、有効な BuildManifest がありません。",
            "固件文件存在多个重定位候选，需人工确认。": "再配置候補が複数あるため、手動確認が必要です。",
            "固件文件身份与固件库记录一致。": "ファイル ID はライブラリ記録と一致します。",
            "固件文件身份与 BuildManifest 复验通过。": "ファイル ID と BuildManifest の再検証に合格しました。",
            "当前机型默认固件不可用。": "現在の機種別既定ファームウェアは利用できません。",
            "全局默认固件不可用。": "グローバル既定ファームウェアは利用できません。",
            "macOS 系统辅助功能": "macOS システムアクセシビリティ",
            "系统状态（只读）": "システム状態（読み取り専用）",
            "不会修改 macOS 全局设置": "macOS のグローバル設定は変更しません",
            "打开 macOS 辅助功能设置…": "macOS アクセシビリティ設定を開く…",
            "无法打开 macOS 辅助功能设置。": "macOS アクセシビリティ設定を開けません。",
            "系统辅助功能优先于视觉预设。应用内动效强度不会改写这些系统状态；降低动效或透明度后，全部设备控制、Restore 与日志功能保持可用。": "システムのアクセシビリティが視覚プリセットより優先されます。アプリ内の動きの強さはシステム状態を変更せず、低減後もすべての制御、Restore、ログ機能を利用できます。",
            "Restore 准备中": "Restore 準備中",
            "Restore 已结束": "Restore 終了",
            "等待真实活动": "実際のアクティビティを待機",
            "整体进度：未知": "全体進捗：不明",
            "等待 cfgutil 真实阶段输出。": "cfgutil の実際の段階出力を待機しています。",
            "cfgutil 尚未报告可识别的阶段。": "cfgutil は認識可能な段階をまだ報告していません。",
            "该百分比只对应当前 Step，不能推导整体完成情况。": "この割合は現在の Step のみに対応し、全体の完了状況は推定できません。",
            "cfgutil 已报告当前阶段完成，等待下一阶段真实输出。": "cfgutil は現在の段階が完了したと報告しました。次の実際の段階出力を待っています。",
            "设备操作已结束，结果来自 cfgutil 终态。": "デバイス操作は終了し、結果は cfgutil の終端状態です。",
        ],
        "ko": [
            "固件偏好": "펌웨어 환경설정",
            "偏好只决定 Restore 准备时的候选固件，不会自动开始刷机，也不会绕过文件身份、BuildManifest 与兼容性复验。": "환경설정은 Restore 준비 후보만 선택하며 자동 시작이나 파일 ID, BuildManifest, 호환성 재검증을 생략하지 않습니다.",
            "本地固件库": "로컬 펌웨어 라이브러리",
            "添加固件文件夹…": "펌웨어 폴더 추가…",
            "刷新固件库": "펌웨어 라이브러리 새로 고침",
            "个可用固件": "개의 사용 가능한 펌웨어",
            "尚未设置全局默认": "전역 기본값이 설정되지 않음",
            "选择全局默认固件": "전역 기본 펌웨어 선택",
            "全局默认固件": "전역 기본 펌웨어",
            "全局默认只是跨机型首选。机型专属默认优先于全局默认；兼容性不足时仍需人工确认。": "전역 기본값은 여러 모델에 공통된 선호일 뿐입니다. 모델별 기본값이 우선하며 호환성이 불확실하면 수동 확인이 필요합니다.",
            "机型默认固件": "모델별 기본 펌웨어",
            "尚未配置机型默认固件": "모델별 기본 펌웨어가 없습니다",
            "添加机型默认固件": "모델별 기본 펌웨어 추가",
            "机型标识符，例如 MacBookPro18,2": "모델 식별자, 예: MacBookPro18,2",
            "选择固件": "펌웨어 선택",
            "已选择固件": "펌웨어 선택됨",
            "添加": "추가",
            "使用当前设备机型：": "현재 기기 모델 사용: ",
            "该机型标识符不在内置可靠机型目录中。": "이 모델 식별자는 내장 검증 모델 목록에 없습니다.",
            "最近使用": "최근 사용",
            "尚无最近使用记录": "최근 사용 기록 없음",
            "尚无实际启动过 Restore 的固件记录": "실제로 Restore를 시작한 펌웨어 기록이 없습니다",
            "机型未知": "모델 알 수 없음",
            "使用": "사용",
            "更换": "변경",
            "删除": "삭제",
            "清除": "지우기",
            "设为全局默认": "전역 기본값으로 설정",
            "设为当前机型默认": "현재 모델 기본값으로 설정",
            "备份并重置固件偏好…": "백업 후 펌웨어 설정 재설정…",
            "固件偏好文件无法读取；已保留原文件，等待用户重新设置。": "펌웨어 설정 파일을 읽을 수 없습니다. 원본을 보존하고 명시적 재설정을 기다립니다.",
            "固件文件已移动、删除，或当前固件库尚未扫描到。": "펌웨어 파일이 이동 또는 삭제되었거나 현재 라이브러리 검사에서 발견되지 않았습니다.",
            "固件文件身份已变化，原偏好不会自动替换为另一份文件。": "펌웨어 파일 ID가 변경되어 다른 파일로 자동 대체하지 않습니다.",
            "该固件是 iCloud 占位文件，请先下载到本机。": "이 펌웨어는 iCloud 자리 표시자입니다. 먼저 로컬로 다운로드하세요.",
            "该固件当前无法读取。": "이 펌웨어를 현재 읽을 수 없습니다.",
            "固件已损坏或缺少有效 BuildManifest。": "펌웨어가 손상되었거나 유효한 BuildManifest가 없습니다.",
            "固件文件存在多个重定位候选，需人工确认。": "여러 재배치 후보가 있어 수동 확인이 필요합니다.",
            "固件文件身份与固件库记录一致。": "펌웨어 파일 ID가 라이브러리 기록과 일치합니다.",
            "固件文件身份与 BuildManifest 复验通过。": "펌웨어 파일 ID와 BuildManifest 재검증을 통과했습니다.",
            "当前机型默认固件不可用。": "현재 모델 기본 펌웨어를 사용할 수 없습니다.",
            "全局默认固件不可用。": "전역 기본 펌웨어를 사용할 수 없습니다.",
            "macOS 系统辅助功能": "macOS 시스템 손쉬운 사용",
            "系统状态（只读）": "시스템 상태(읽기 전용)",
            "不会修改 macOS 全局设置": "macOS 전역 설정을 변경하지 않음",
            "打开 macOS 辅助功能设置…": "macOS 손쉬운 사용 설정 열기…",
            "无法打开 macOS 辅助功能设置。": "macOS 손쉬운 사용 설정을 열 수 없습니다.",
            "系统辅助功能优先于视觉预设。应用内动效强度不会改写这些系统状态；降低动效或透明度后，全部设备控制、Restore 与日志功能保持可用。": "시스템 손쉬운 사용 설정이 시각 프리셋보다 우선합니다. 앱 내 모션 강도는 시스템 상태를 바꾸지 않으며 모션 또는 투명도를 줄여도 모든 기기 제어, Restore 및 로그 기능을 사용할 수 있습니다.",
            "Restore 准备中": "Restore 준비 중",
            "Restore 已结束": "Restore 종료됨",
            "等待真实活动": "실제 활동 대기 중",
            "整体进度：未知": "전체 진행률: 알 수 없음",
            "等待 cfgutil 真实阶段输出。": "실제 cfgutil 단계 출력을 기다리는 중입니다.",
            "cfgutil 尚未报告可识别的阶段。": "cfgutil이 아직 인식 가능한 단계를 보고하지 않았습니다.",
            "该百分比只对应当前 Step，不能推导整体完成情况。": "이 백분율은 현재 Step에만 적용되며 전체 완료율을 추정하는 데 사용할 수 없습니다.",
            "cfgutil 已报告当前阶段完成，等待下一阶段真实输出。": "cfgutil이 현재 단계 완료를 보고했습니다. 다음 실제 단계 출력을 기다리는 중입니다.",
            "设备操作已结束，结果来自 cfgutil 终态。": "기기 작업이 종료되었으며 결과는 cfgutil 최종 상태입니다.",
        ],
    ]

    static func times(_ count: Int) -> String {
        switch code() {
        case "en": return count == 1 ? "1 time" : "\(count) times"
        case "zh-Hant": return "\(count) 次"
        case "ja": return "\(count) 回"
        case "ko": return "\(count) 회"
        default: return "\(count) 次"
        }
    }

    static func currentRestoreStage(_ stage: String) -> String {
        switch code() {
        case "en": return "Current stage: \(stage)"
        case "zh-Hant": return "目前階段：\(stage)"
        case "ja": return "現在の段階：\(stage)"
        case "ko": return "현재 단계: \(stage)"
        default: return "当前阶段：\(stage)"
        }
    }

    static func ports(_ count: Int) -> String {
        switch code() {
        case "en": return count == 1 ? "1 interface" : "\(count) interfaces"
        case "zh-Hant": return "\(count) 個介面"
        case "ja": return "\(count) ポート"
        case "ko": return "인터페이스 \(count)개"
        default: return "\(count) 个接口"
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

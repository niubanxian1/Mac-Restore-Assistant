# HANDOFF_CURRENT

时间：2026-11-11 12:05 Asia/Shanghai（UTC+8）；测试节点：12:06、12:14、12:35；T545 节点：2026-11-11 12:37 Asia/Shanghai（UTC+8）
本交接只写实际状态。工作区 `Info.plist` 当前构建号为 `20261111.1236`。`MRA-Device-Control-0.2.3-T532.zip`（`20261111.1220`）保留为中间产物，不是 t545 的交付包，也不把它宣布为 Owner 交付。

## 1. 工作区、基线、版本、构建号

- 当前正在修改的工作区（0.2.3 T532 候选，唯一写入树）：`/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI`
- 完整票面（Grok Bot 电脑）：`/workspace/MRA_0.2.3_T532_UI_TICKET.md`（t532u–t544u）。工作区副本若尚未拷入，请先从上述路径复制到 `_t532/`。
- 工程笔记：`/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI/_t532/WORK_NOTES.md`
- 校准工具定位笔记（t539  uniqueness STOP，已被后续票面补充，不要再按「无法唯一确定」停住）：`/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI/_t532/T539_TOOL_IDENTITY.md`
- 短版本：`0.2.3`（工作区 `Info.plist` 的 `CFBundleShortVersionString`）
- 工作区 `Info.plist` 的 `CFBundleVersion` 当前为 `20261111.1236`（t545 打包时刻）。`20261111.1220` 只属于已保留的中间 zip `MRA-Device-Control-0.2.3-T532.zip`。短版本仍为 `0.2.3`，minOS 仍为 `27.2`。
- 最低系统：`27.2`
- 官方 0.2.2 工程基线（只读，禁止写入）：`/Users/Shared/MRA_DEVICE_CONTROL_RELEASE_0.2.2_20261110T1306Z`（T1306Z，`CFBundleVersion` `20261110.2106`，`APP_CDHASH=0e7a15b864a1001af08702f35edb13550368463d`）。源码冻结树：`/Users/Shared/MRA_DEVICE_CAPTURE_PROTOTYPE_0.2.2_20261110T1306Z`。密封前代 T1205Z 与冻结 0.2.1 同样禁止改。
- Helper / backend 意图：继续复用 T1306Z 已签名载荷；本树 `Resources/mra-helper`、`Resources/direct_rid_dfu`、`com.mra.devicecontrol.helper.plist` 自拷树后未作为本轮修改对象。本轮不要重签 `--deep`，不要替换现网 Helper。
- 本工作区不是 git 仓库。

### 三者请严格区分

1. **最新源码**：就是当前工作区 `/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI`（Sources / Tests / Resources / `Info.plist` 等）。本轮 t532–t544 的修改都在这里。12:05 快照之后又写入了 t542 校准接入与 t544 作废控制，以工作区现场和 `SRC_20261111T1214+0800` 为准，不要把 12:05 快照当成当前源码。
2. **最近一次成功构建的 App（本树）**：`/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI/_t532/app-stage/MRA Device Control Prototype.app`（12:21:17 Asia/Shanghai 只签 App，CDHash `c48a19317fb3e68484fa5379f5cca1d8d93b7d5c`）。最终 zip 解出的是同一份。`_t532/test-build` 仍只是测试缓存。
3. **已经交付的 T532 ZIP**（文件名不是 T523 固定名）：
   - `/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI/_t532/delivery/MRA-Device-Control-0.2.3-T532.zip`
   - SHA-256 `73fe1f10b5b1c486a58bf507c80261a18a3270ba07599404112f2d5c0ee60c59`（4,425,397 字节）
   - 短版本 0.2.3 / CFBundleVersion `20261111.1220`；内含已签名 App、试用说明、四张隔离全窗口截图。
   - 报告：`_t532/delivery/REPORT.md`

**仍不要覆盖**的 T523 包（12:25 复核哈希未变）：
   - `/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T523_UI/_t523/delivery/MRA-Device-Control-0.2.3-候选.zip`
   - SHA-256 `ee85cf4afcd1a756b85e8509a1c6976da6d4b5b8cd81a41c75e85a6075c79ecc`
   - App `0.2.3` / `CFBundleVersion` `20261111.1116`；App exe SHA-256 `7fda810e20a3f890e7913daa9a9aabdc4091d9219cba65d71c28d0666c91df86`；CDHash `21844c190da060de3c0e22e1d6b25b4a1cb6492a`
   - 不要覆盖该 ZIP，也不要用这个旧构建号冒充 T532 交付。

更早保留、同样不要覆盖：T522 `/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T520_UI/_t520/delivery/`（`20261111.1035`）；Phase 1 `/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_CANDIDATE/_phase1/delivery/`（`20261111.0940`）；日常 App `/Users/Shared/MRA_DEVICE_CONTROL_RELEASE_0.2.2_T498_PORT_DISPATCH/MRA Device Control Prototype.app`。

### 校准参照（都不是当前候选工作区，只读）

- **Phase B.1 是校准成品参照**，不是当前候选工作区：`/Users/niubanxiandaiuzhichakanqi/Documents/deepseek-harness/default-workspace/MacBook-hardware-preview-phase-b/dist-hardware-preview-phase-b/`，App 为 `Mac Restore Assistant Hardware Preview.app`，版本 `1.7-hardware-preview0.3.2-phase-b.1`。校准界面、布局编辑、「检测到唯一变化」插拔流程优先对照该成品及其同名父工程。
- **model-calibration-v2 是整合源码**，不是当前候选工作区：`/Users/niubanxiandaiuzhichakanqi/Documents/deepseek-harness/default-workspace/MacBook-model-calibration-v2/`。模型包导入、保存或新版整合能力再查这里（`ModelCalibrationDialog` / `CalibrationSessionDialog`）。不要把整合分支独有功能说成 B.1 已有，也不要因为参照 B.1 而丢掉后续成熟功能。

## 2. 已完成、验证到哪、还没做

### 已完成（事实）

- 已从 T523 源码拷出独立 T532 工作区，未改冻结树，未覆盖已交付 T523 ZIP / T522 / Phase 1 / 日常 T498。
- 工作区源码中已出现面向 t532–t538 的编辑和测试文件（见下方关键文件）。这只说明源码里有对应字符串和模块，**不能当成已经实现并通过验收**。
- t539 已写出工具定位笔记 `_t532/T539_TOOL_IDENTITY.md`。Owner 随后在 t540–t542 指定了成品参照与整合源码，定位 STOP 已被取代。
- 桌面原件已拷入本树 `Resources/`（拷入时记录的 SHA-256）：`小牛图标.icns` = `391e9dd6cb144ab14c47ff53464b0c8d1de7d88162435133dee71b26338206e2`；`微信.JPG` = `a5c3c29ceccc7fe1f792fac60fb030c25361d66c5d56a8ca4cfe0bf1f47d323a`。`Info.plist` 已有 `CFBundleIconFile=小牛图标`。
- 日常校准库在 t539 定位时只做了哈希、未写入。当时记录（之后若未再核验，不要假设仍相同）：
  - `~/Library/Application Support/MRA_DeviceCapture_Prototype/calibration.json` sha256 `968d0ef95fd4cb9beed8e8fc029f6f8e1081d5213de0a6ebe6cc8f2c3f904ead`（ino 49609127）
  - `port-history.json` sha256 `c2500c69193c39b7e5615caa987497bd8dad9d9f10b6b4e7ceaae573223fc0da`（ino 49606772）

### 验证到哪一步

11:49 编译失败日志仍保留、未覆盖：

- `/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI/_t532/test-logs/swift-test-device.txt`
- 时间：2026-11-11 11:49:20 Asia/Shanghai
- 原始错误：`ContentView.swift:170:47` `#OpaqueTypeInference`（opaque return 无 return）。同日志还有当时的 `ContentView.swift:195:10` `#NoUsage` 警告，以及 `error: Build failed` / `error: fatalError`。

12:06 已用当前工作区源码重跑测试（本机 Swift 6.4.2 只接受 `--scratch-path`，不是票面写的 `--build-path`；目录仍是指定的 `_t532/test-build`）：

- 新日志：`/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI/_t532/test-logs/swift-test-device-20261111T1206+0800.txt`（12:06:17–12:06:48 Asia/Shanghai，exit 0，56,580 字节）
- 编译通过。新日志中**没有** `ContentView.swift` 错误，也没有 `#OpaqueTypeInference` / `Build failed`。11:49 的 line 170 问题：当前 `portDetailsSection` 在约第 188–190 行已有 `return VStack`，该错误已消除。
- `DeviceCapturePrototypeTests`：Executed 116 tests, 1 skipped, 0 failures。跳过的是 `DeviceObserverTests.testCurrentDFUEnumerationIfPresent`（「当前没有 DFU 目标；仅做离线样本检查」）。含 T532UIWiringTests 13 项全部通过。
- 编译警告（非失败）：`Models.swift:327` `var payload` 从未被修改（建议改 `let`）；既有测试文件 `DFUSequenceRunnerTests.swift:12` 的 async lock 警告。

12:11 曾用当时源码编译测试，失败并另存日志（未覆盖 11:49 / 12:06）：

- `/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI/_t532/test-logs/swift-test-device-20261111T1211+0800.txt`（12:11 Asia/Shanghai，13,598 字节，`error: Build failed`）
- 原因：既有 `T542CalibrationToolTests.testConfirmedB1PathIfPresent` 对 `throw XCTSkip` 未声明 `throws`。已补 `throws`，未改该测试的断言意图。

12:12 再次全量 `swift test`（误设了进程级 `MRA_APPLICATION_SUPPORT_ROOT`，使 `PortHistoryStore.defaultURL()` 不再落到产品路径）日志：

- `/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI/_t532/test-logs/swift-test-device-20261111T1212+0800.txt`（12:12 Asia/Shanghai，88,315 字节）
- `T544DiscardCaptureTests` 4 项已在该次通过。`DeviceCapturePrototypeTests` 合计 Executed 128 tests, 1 skipped, 3 failures：`T522UIWiringTests.testAppSupportOverrideDoesNotUseRealUserDirectory`（环境变量污染，非产品回归）；`T542CalibrationToolTests.testImportingUnrelatedPackIsUncalibratedNotExact` 两项断言（导入无关机型包时，仍用主机自带同模具候选标成「沿用同模具布局」）。同日志里 `MRA022AcceptanceTests` 安装脚本用例也有失败，本轮未改安装脚本，未当作 t544 结论。

12:13–12:14 在**未**设置 `MRA_*` 环境变量的前提下，只跑 `DeviceCapturePrototypeTests`（`--scratch-path …/_t532/test-build`，新日志，未覆盖旧日志）：

- `/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI/_t532/test-logs/swift-test-device-20261111T1213+0800.txt`（12:13:48–12:14:07 Asia/Shanghai，39,746 字节）
- 编译通过。`DeviceCapturePrototypeTests`：Executed 128 tests, 1 skipped, 0 failures。跳过的仍是 `DeviceObserverTests.testCurrentDFUEnumerationIfPresent`（「当前没有 DFU 目标；仅做离线样本检查」）。
- T532UIWiringTests 13 项通过；T542CalibrationToolTests 8 项通过（含 `testImportingUnrelatedPackIsUncalibratedNotExact`、`testIsolatedWalkthroughWithCopiedDesktopSampleIfPresent`）；T544DiscardCaptureTests 4 项通过。

t544 隔离模拟走通（`T544DiscardCaptureTests.testStartThenDiscardStopsBackendRemovesTempAndAllowsNewStart`，以及停止后作废、导出中禁用、空闲禁用）：`CaptureModel` 使用临时目录 + `backendMode: .simulated`。结果：Start 进入 `.recording` 后点作废，先进入 `.stopping`，后端退出且作废后字节数不再增长；本会话 `{uuid}.partial` 临时目录被删除；同目录下预置的 `already-saved.zip` 与 `other-session.partial` 仍在；界面回到空闲，`durationText` 为「0秒」，`byteCount` 为 0，`saveMessage` 为「本次日志已作废，采集已停止」；再次 Start 使用新的会话目录，并可正常 stop。停止但尚未导出时，按钮文案为「作废本次日志」，点击可直接清理。该走通是自动化模拟，不是已签名 App 的界面截图。

伴随修正（非 t544 按钮本身）：`DeviceControlPresentation.hostModelCalibrationKind` 在已采用 overlay 时，只有 overlay 来源机型属于同模具对才标「沿用同模具布局」，不再让主机自带的同模具候选把无关导入包标成同模具。这只通过了上述单元测试，不是 B.1 图形界面实机走通。

本树仍然没有已签名 App，没有交付截图，没有 T532 ZIP。`HARDWARE_VALIDATION` 仍为 PENDING。现场 M4 在 11:30 Asia/Shanghai 的只读扫描中未枚举到 Apple 目标，机型保持 UNCONFIRMED，不要猜。日常校准库在 12:14 Asia/Shanghai 再次只读核验，哈希与 inode 未变：`calibration.json` sha256 `968d0ef95fd4cb9beed8e8fc029f6f8e1081d5213de0a6ebe6cc8f2c3f904ead`（ino 49609127）；`port-history.json` sha256 `c2500c69193c39b7e5615caa987497bd8dad9d9f10b6b4e7ceaae573223fc0da`（ino 49606772）。

### 还没做（需求仍在票面里，不要写成已完成）

- 隔离 UI 截图、App-only 签名、T532 交付 ZIP：已在 12:26 节点完成（见上）。
- B.1：隔离启动已做；「在 B.1 中添加模型 / 导入或编辑布局 / 保存 → T532 主界面不重启即读回」仍 PENDING。
- 自行校准中的插拔「检测到唯一变化」、真机 DFU/重启发送仍待实机验收。HARDWARE_VALIDATION=PENDING。本轮不要对真机发 DFU/重启，不要操作官方左下 Air。

源码中已出现、但**未经验证**的文案/模块线索（供对照，不是验收通过）：`去校准`、`机型已精确校准`、`沿用同模具`、`关于软件`、`卸载 Helper`、`操作目标已切换`、`DFU · 机型未识别`、`清理并重启 Configurator`、`CaptureDisplayFormat`。

### 12:26 交付节点（实际完成）

- 隔离截图（已签名 App，`_t532/isolated/extract-app/`，1960×1280 主窗口含标题栏）：`01-main-switch-right-feedback.png`（左侧端口详情、右侧「DFU · 机型未识别」、技术详情展开、「操作目标已切换：右侧」、「重置 Configurator…」、导出旁「作废本次日志」、左下「主机 MacBookPro18,2 · 机型已精确校准」无「去校准…」）;`02-settings-helper-uninstall.png`（导航名完整，「卸载 Helper…」直接可见，未点击）;`03-about-software.png`（版本 0.2.3 / 20261111.1220，二维码白边未反色）;`04-configurator-reset-panel.png`（默认清理 Caches，隔离路径，未执行）。
- B.1 隔离启动已做：`MRA_HARDWARE_PREVIEW_HOME=_t532/isolated/b1-home`，窗口显示预览库在该隔离路径；默认日常校准库与默认 Yifei `draft.json` / `port_preview.db` 哈希和 inode 未变。证据图 `_t532/delivery/evidence/05-b1-isolated-launch.png`（不在产品 zip 内）。**未**在 B.1 中保存布局，也**未**做保存后 T532 主界面读回，这两步仍 PENDING。不要把 12:14 单测写成该 GUI 走通。
- 未点击或退出 PID 12686 / 13245。HARDWARE_VALIDATION 仍为 PENDING。现场 M4 仍 UNCONFIRMED。

### 12:37 t545 节点（实际完成）

在同一 T532 树恢复旧左栏样式，对照 Owner 裁图 `/workspace/t545-refs/owner-old-left-port-details.png`，不以 12:23 的 T532 主窗截图为终态。

- 源码：`ContentView.swift` 左侧改为默认展开的 `DisclosureGroup("端口详情")`（紧凑行：控制器 · PortNumber · RID、内置/自定义校准、实际采用、模型/主机摘要）、其下固定 `operationTargetText`（「操作目标：…」）、按钮下方 `feedbackCard`。保留「重启设备」。手动切端口时 feedback 标题仍为「操作目标已切换：…」。左下角校准摘要、右栏、采集区、发送路径、Helper 未改。
- 测试：`_t532/test-logs/swift-test-device-20261111T1235+0800.txt`，DeviceCapturePrototypeTests Executed 130，1 skipped，0 failures。未设置进程级 `MRA_*`。
- 包：`/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI/_t532/delivery/MRA-Device-Control-0.2.3-T545.zip` SHA-256 `83444129d37493e3749a518246f5ec631fda0477fefccb3ac2d75594c50f9e86`（4,440,920 字节）。CFBundleVersion `20261111.1236`。CDHash `658334374bb12ffde435553fca2e666a3a70164f`。只签 App，无 `--deep`。报告 `REPORT-T545.md`。
- 隔离主窗截图：`_t532/isolated-t545/screenshots/01-main-switch-right-feedback.png`（1960×1280）。
- `MRA-Device-Control-0.2.3-T532.zip`（1220）未覆盖，哈希仍为 `73fe1f10b5b1c486a58bf507c80261a18a3270ba07599404112f2d5c0ee60c59`。T523 zip 未覆盖。日常 `calibration.json` / `port-history.json` 哈希与 inode 未变。
- HARDWARE_VALIDATION 仍为 PENDING。

### 关键文件

- `Sources/DeviceCapturePrototype/ContentView.swift`（12:05 快照时 SHA-256 `0f598e89b53ea21daef5e7a9d7bbd4a89d28935435bd28f4dbf8499734beae02`；12:14 工作区 SHA-256 `1e9dd0852b1d27314f184c71d73c8a41659f57e521508729ae7f71bff05d43b1`，含导出旁「作废并停止」按钮）
- `Sources/DeviceCapturePrototype/Models.swift`
- `Sources/DeviceCapturePrototype/DeviceControlPresentation.swift`
- `Sources/DeviceCapturePrototype/HelperEnvironment.swift`
- `Sources/DeviceCapturePrototype/AboutSoftware.swift`
- `Sources/DeviceCapturePrototype/ConfiguratorReset.swift`
- `Sources/DeviceCapturePrototype/CaptureDisplayFormat.swift`
- `Sources/DeviceCapturePrototype/HardwarePreviewPack.swift`（12:03:52，SHA-256 `4662fb2fb1ab3120b5caca600bd5d69b99501a7f9361f2f4c90b19858481b65e`）
- `Sources/DeviceCapturePrototype/CalibrationToolLauncher.swift`（12:04:10，SHA-256 `0535ae65e1cfce074f206783478c9589b53f334ea05d8f8af4fab1fa30da37a2`）
- `Tests/DeviceCapturePrototypeTests/T532UIWiringTests.swift`
- `Tests/DeviceCapturePrototypeTests/CaptureDisplayFormatTests.swift`
- `Tests/DeviceCapturePrototypeTests/ConfiguratorResetTests.swift`
- `Tests/DeviceCapturePrototypeTests/T542CalibrationToolTests.swift`
- `Tests/DeviceCapturePrototypeTests/T544DiscardCaptureTests.swift`（12:14 SHA-256 `bb413025ed8c07787f2d78e7025a84c36ebc33639f99714e14ae5bf12a012e9f`）
- `Sources/DeviceCapturePrototype/Models.swift`（12:14 SHA-256 `601d6247b055360c31f303a07abc90fd3b6b6e1720413d1ae22556ac45d679b1`，含 `discardUnsavedSession`）
- `Sources/DeviceCapturePrototype/DeviceControlPresentation.swift`（12:14 SHA-256 `9a80a900aa694ad1c0ee5aa3228d91297ddf278c4c1c2bd10a287eb2fd855d51`）
- `Info.plist`（SHA-256 `6205299627ab5c776c1fa2e78c7d32e05d61663b1783ec4379311c57c9a09b2a`）
- `Resources/小牛图标.icns`、`Resources/微信.JPG`

## 3. 源码快照（不覆盖旧快照）

拍摄时刻：2026-11-11 12:05 Asia/Shanghai。含 Sources、Tests、Resources、根目录打包文件、`_t532` 笔记与当时的测试日志；**不含** `_t532/test-build` 构建缓存。若拍摄后仍有写入，以工作区现场文件为准，并另存新快照，不要改本目录。

- 目录：`/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI/_t532/snapshots/SRC_20261111T1205+0800/`
- 逐文件清单：该目录内 `SHA256SUMS.txt`（109 条）
- 归档：`/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI/_t532/snapshots/SRC_20261111T1205+0800.tar.gz`
- 归档 SHA-256：`1e254e3fafa828785b59651e928aff0f74181ee40c456ec492b9e0d86d1dff99`（1,891,194 字节）
- 该 12:05 归档在 12:14 再次核验，哈希未变，**未覆盖**。

12:14 Asia/Shanghai 另存新快照（源码已相对 12:05 变化；不含 `_t532/test-build`，也不把旧快照套进新快照）：

- 目录：`/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI/_t532/snapshots/SRC_20261111T1214+0800/`
- 归档：`/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI/_t532/snapshots/SRC_20261111T1214+0800.tar.gz`
- 归档 SHA-256 以同级文件 `SRC_20261111T1214+0800.tar.gz.sha256` 及本段拍摄后补记为准（先拍归档，再回写哈希，故包内这份 HANDOFF 可能比工作区根文件少最后一行哈希）。

- 工作区补记（拍完归档后写入，不回头覆盖包内文件）：归档 SHA-256 `d548140fb43077070c890e4defccd3aa67d0320dab45e9c29dacc538a655312b`（1926658 字节）；清单 `116` 条（`SHA256SUMS.txt`）。

12:26 Asia/Shanghai 另存新快照（工作区 `Info.plist` 构建号已改为 `20261111.1220`；不含 `_t532/test-build`、`build-release`、已签名 App 与交付 zip 本体）：

- 目录：`/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI/_t532/snapshots/SRC_20261111T1226+0800/`
- 归档：`/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI/_t532/snapshots/SRC_20261111T1226+0800.tar.gz`
- 归档 SHA-256：`cc2d89ad53fdea142ed3590fe63cd2d81aff0411a96e49edf75189eac68a1e4f`（3529660 字节）；清单 124 条。未覆盖 12:05 / 12:14 快照。

12:38 Asia/Shanghai 另存新快照（含 t545 左栏源码与 `Info.plist` `20261111.1236`；不含 test-build / build-release / 已签名 App / zip 本体）。未覆盖 12:05 / 12:14 / 12:26 快照。

- 目录：`/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI/_t532/snapshots/SRC_20261111T1238+0800/`
- 归档：`/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI/_t532/snapshots/SRC_20261111T1238+0800.tar.gz`
- 归档 SHA-256：`f3192d387419bbde4a0ec048f02e7ab04e7e280daa313613ec89376868b2001a`（3395789 字节）。

Phase B.1 成品与 model-calibration-v2 源码均未打进这些快照（它们不是候选工作区；保持只读，不要改）。

## 4. 边界

不覆盖日常 App，不替换现网 Helper，不操作真机，不覆盖已交付 T523 ZIP / T522 / Phase 1 / 冻结 T1306Z / T1205Z / 0.2.1，不写入用户日常校准库（含 `MRA_DeviceCapture_Prototype`、`Yifei.MacFlashAssistantHardwarePreview`、`Library/Logs/MacFlashAssistant/model-calibration`）。不把旧 Restore、任务系统或额外发送门槛带回来。`canControl` / `disabledReason` / DFU·重启发送路径保持原样。

下一步：不要把 `MRA-Device-Control-0.2.3-T532.zip`（20261111.1220）当作 Owner 交付；t545 包是 `MRA-Device-Control-0.2.3-T545.zip`（20261111.1236）。若仍要补 B.1 保存后主窗读回，使用隔离 HOME，禁止写默认 Yifei 库。不要覆盖 `SRC_20261111T1205+0800`、`SRC_20261111T1214+0800`、`SRC_20261111T1226+0800` 或既有测试日志，不要覆盖 T523 zip / 1220 中间包 / 日常 App / 现网 Helper。HARDWARE_VALIDATION 保持 PENDING。

## 5. 2026-11-11 13:24 Asia/Shanghai · 牛半仙Mac维修辅助工具 1.0 RC1

### 5.1 产品定名与版本

- 正式名称：`牛半仙Mac维修辅助工具`；短版本 `1.0`。
- RC1 构建号：`20261111.1405`（前两包 `20261111.1320`、`20261111.1350` 分别保留为 `-RC1-build1320.zip`、`-RC1-build1350.zip`）。
- 保留不变：Bundle ID `com.mra.devicecontrol.prototype`、Team `6NFD357KL3`、Helper Label `com.mra.devicecontrol.helper`、socket `/var/run/com.mra.devicecontrol.helper.sock`、现有配置目录 `MRA_DeviceCapture_Prototype`。未全局替换内部 `prototype`。
- `.app` 文件名、Finder 显示名、主窗口、关于页、试用说明和 ZIP 名已改为新名称。关于页从 App 内读取版本，显示「版本 1.0（20261111.1405）」。
- 安装脚本已优先查找 `牛半仙Mac维修辅助工具.app`，仍兼容旧 `MRA Device Control Prototype.app`；Helper/backend 载荷与哈希未变，已有匹配 Helper 的机器不需要因改名重装或重新输入密码。
- 小牛图标、微信二维码、作者刘海峰、邮箱 `liuhaifeng2001522@gmail.com` 保留。

### 5.2 RC1 ZIP（当前系统可测试）

- `/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI/_t532/delivery-rc1/牛半仙Mac维修辅助工具-1.0-RC1.zip`
- SHA-256 `3099a817376c13cf0f0b1ce655e85860083876a27d4211f408db01496c2e314a`（5,728,477 字节）
- 前两包保留：`-RC1-build1320.zip` SHA-256 `d8ca1b5e30d9e5e8aa1c7aebc81cb194cf18f2f84db64ff7b85120209a5d42ea`；`-RC1-build1350.zip` SHA-256 `1722aa7425c2fdb16abc0409f004db1236c9bf910546f09089f846a2123b4a9a`
- 解出 App：`牛半仙Mac维修辅助工具.app`，`CFBundleShortVersionString=1.0`，`CFBundleVersion=20261111.1405`，`LSMinimumSystemVersion=27.2`；App CDHash `c89b9f9d3055f7ec0188f5a531684762505a6173`。
- 签名：Apple Development `liuhaifeng2001522@gmail.com (236PF79JKR)`，Team `6NFD357KL3`；未公证、无 Hardened Runtime、无 Developer ID。**内部测试候选，不可公开分发。**
- 包内：App、`install-mra-device-control.sh`、`uninstall-mra-device-control.sh`、`mra-quarantine.sh`、`com.mra.devicecontrol.helper.plist`、`样例模型包-M1Pro-A2442.zip`、`试用说明-RC1.txt`、`安装说明-RC1.txt`、`界面示例/` 8 张隔离截图。
- 解包后 `codesign --verify --strict` 通过；App/Helper/`direct_rid_dfu` minos 均为 27.2，`LSMinimumSystemVersion` 27.2；安装脚本 `--dry-run` 输出 `MINOS_CONSISTENT=YES`、`QUARANTINE_DETECTED=NONE`、`DRY_RUN_OK`。未执行正式安装。
- 最终测试日志 `_t532/test-logs/swift-test-device-20261111T1333+0800.txt`：`DeviceCapturePrototypeTests` 155 tests，1 skipped，0 failures。跳过项仍是当前无 DFU 目标的现场枚举检查。

### 5.3 App 内模型校准（本轮实现）

- 设置 → 模型校准已改为完全在 App 内：添加主机模型、导入已有模型包、编辑自定义布局、按槽位校准、保存并立即应用；不再启动 Hardware Preview B.1，不依赖开发机绝对路径。
- 槽位状态机：采基线 → 插入探针 → 检测唯一变化 → 移除探针 → 确认映射。读取主机端口连接状态；不发送 DFU／重启。一个槽位跳过或未完成时保存为 `.customLayout`，不标精确；全部完成才写 `.inAppCalibration`。
- 主页与设置页共用 `CalibrationStore.adoptedOverlay`。添加模型、导入其他机型包、套用布局只显示「沿用同模具布局」或「未校准」。
- 隔离验收（模拟）：`MRA_CALIBRATION_SIMULATION=1` 下，从内置布局进入向导，P1/P2/P3 模拟插拔，3/3 完成并保存；`adopted-layout.json` 的 `source=inAppCalibration`、`partial=false`；关闭并重开同一隔离 App Support，设置页仍显示「主机 MacBookPro18,2 · 机型已精确校准」和 3 个槽位。截图见 `界面示例/03`–`07`。
- 样例包导入（同一 App 内）：`样例模型包-M1Pro-A2442.zip` 导入后 `source=appliedLayout`、`sourceHostModel=MacBookPro18,3`，显示「未精确校准（沿用同模具布局）」；截图 `界面示例/02`。
- **真实插拔校准仍 PENDING**；模拟通过不等于实机通过。

### 5.3.1 左下角主机校准状态与「去校准…」

- A2485（16 英寸 M1 Pro/Max）主机标识是 `MacBookPro18,2`；内置校准库已有同机型 S3/S4/S5 精确记录。A2442（14 英寸）是 `MacBookPro18,3`，与 16 英寸不是同一物理模具；同尺寸内 Pro/Max 共用同一机型标识。
- 旧日常生效记录中残留的 `previewToolSave`（`sourceHostModel` 为空、三个槽位无 PortNumber/RID）不再覆盖内置精确命中；App 加载时忽略该无效记录，也不再从旧 B.1 `draft.json` 回填。
- 同机型且完整槽位映射与内置精确记录一致的导入包（A2485）仍显示「机型已精确校准」；同机型但映射不一致显示「未校准」，不再误写「沿用同模具布局」。其他机型仍按同模具/未校准区分。


- 左下 Helper 状态旁显示 `hostCalibrationSummaryText`，只取决于主机机型与生效记录，不随选口切换。
- 三种文案：`机型已精确校准`；`未精确校准（沿用同模具布局）`；`主机机型未识别 · 未校准`；其余为 `主机 <model> · 未校准`。
- `去校准…` 只在非精确命中时出现，点击直接打开「设置 → 模型校准」布局页，不再调用外部 Hardware Preview B.1；不弹确认框、不改变端口选择或 `canControl`。
- 单口控制器、RID、实际采用来源仍在「端口详情」。
- 新增 `HostCalibrationStatusTests` 5 项，覆盖不随选口切换、同模具、未识别、未校准和端口详情分离。

### 5.4 端口显示修正（本轮实现）

- USB 读取不再只接受 `Apple Mobile Device`；通用 `Mac` 节点被读入，按 Apple vendor + DFU/Recovery/Mac 证据分类，普通 Mac 为 `connected`，不误判 DFU。
- 控制器确认连接但目标身份未读到时：左「已连接」，右「设备身份暂未读取」；不写「无设备」，不猜 DFU/型号。
- 通用 Mac 显示「已连接 Mac · 具体机型未知」；DFU 保留模式 + ECID，只有显式机型标识/同 ECID 可信缓存才接入标题；不从主机校准库猜目标型号。
- 技术详情只列实际读到的当前协议、协商速率、线材标识/能力、Hub 名称、连接路径；线材能力与协商速率分开；USB2/USB3/CIO 只作观察，不推断线材/速度/雷电。首次打开不记「设备插入」，只有前后状态变化才记。
- 截图 `界面示例/01` 显示左侧下方「已连接」、右侧「设备身份暂未读取」及当前协议/线材标识。
- 未改端口路由、Helper、DFU/重启发送按钮。

### 5.4.1 导出旁「作废并停止／作废本次日志」

- 位置：右侧「导出 ZIP…」同排，次要 `.bordered` 样式，间距 16；说明「停止抓取并删除本次未导出的日志」；一次点击直接执行，无确认框。
- 采集中显示「作废并停止」；停止但未导出显示「作废本次日志」；空闲禁用；导出进行中禁用，避免与导出抢同一份文件。
- 流程：立即进入 `.stopping` → 等待后端退出 → 再观察 200ms 确认字节/文件大小不再增长 → 只删除本次会话临时目录；停止失败保留文件并报「停止失败」，不显示已作废。
- 成功后回到 `.idle`，时长「0秒」、字节 0、显示「本次日志已作废，采集已停止」；下次开始创建新会话。已保存 ZIP、其他会话、设备操作记录不删。
- 模拟验证：`T544DiscardCaptureTests` 4 项通过（含开始→作废→字节不再增长→临时目录消失→可重新开始；导出中禁用；已保存/其他会话保留）。

### 5.5 恢复模式结论：未接通，保持禁用

- 旧 `run_dfu('reboot serial')` 在多个旧快照中被 `_recovery_backend_missing()` / `EXACT_BACKENDS['ENTER_RECOVERY']=''` 在进程前阻断（`MacBook-p2-port-knowledge/main_optimized.py:4062`、`privileged/contract.py:18-22`）。
- 能到达进程的旧版本（commit `7cf749a`）实际执行 `dfu_tool reboot serial`，单次调用；`dfu_tool` 无端口/RID 过滤，`FindDevice` 遍历全部 AppleHPM 并取最后一个，不是操作者所选物理端口。
- `DoRebootSerial` 先发普通重启 VDM `{0x05ac8012,0x105,0x80000000}`，再额外发 `{0x05ac8012,0x01840306}` 并进入串口模式；**不是 macOS Recovery**。`direct_rid_dfu reboot` 只发第一条 VDM，不能等同替代。
- 当前 `direct_rid_dfu` 只有 `probe|dfu|reboot`，没有 recovery 命令/VDM；`HelperAction` 也没有 recovery。缺的证据：可验证的 Recovery VDM/序列、精确端口后端、真实进入 Recovery 的 level-D 证据。
- 因此「进入恢复模式」继续禁用，界面写明原因；不影响 DFU、重启和采集。离线只做证据调查，未发任何恢复命令。

### 5.6 macOS 13/14 兼容（独立副本）

- 源码审计：`Package.swift` 平台 27.2 和 `Info.plist` minos 27.2 只是构建配置；唯一 14.0 API 是 `ContentView.swift` 的双参数 `.onChange(of:scenePhase)`。RLM 清单声明 14.0，但源码可降到 13.0；`direct_rid_dfu`、`mra-helper` 均可重编。
- 已建独立副本 `_t532/compat-ventura13/`（RLM 源码 vendored 到 `ThirdParty/RLM`，未写回封存工程），改平台 13.0、单参数 onChange、Info.plist 13.0，重建 App / Helper / `direct_rid_dfu`，三件套 minos 均 13.0；Helper/backend 哈希与 RC1 不同，脚本常量已同步。
- 兼容 ZIP：`/Users/Shared/MRA_DEVICE_CONTROL_PROTOTYPE_0.2.3_T532_UI/_t532/delivery-ventura13/牛半仙Mac维修辅助工具-1.0-Ventura13-试验.zip`
  - SHA-256 `a1e9ca34b6347edc6f12a95dda0ac3945c04e967044ff597c45efe180ceb7e16`（3,115,379 字节）
  - 构建号 `20261111.1345`；App CDHash `52ecf570bd03f061fcdc46b4d54611e0b277c37e`；Apple Development，未公证。
  - 解包 `codesign --verify --deep --strict` 通过；安装 `--dry-run` 输出 `MINOS_EFFECTIVE=13.0`、`MINOS_CONSISTENT=YES`、`DRY_RUN_OK`。
  - 已在构建机 macOS 27.3 隔离启动并看到关于页「版本 1.0（20261111.1345）」；**没有真实 macOS 13 主机，目标系统未验收**。不得写「已支持 macOS 13」。
- 兼容包基于 13:22 源码快照构建，未包含随后加入的左下主机校准状态/「去校准…」导航改动；其目标系统仍未验收。
- 14 fallback：源码无需改 Swift API，只需平台/manifest 14.0、重编 Helper/backend、更新哈希并重签；本轮未另出 14 包。

### 5.7 保留与待办

- T545 ZIP 未覆盖，SHA-256 仍 `83444129d37493e3749a518246f5ec631fda0477fefccb3ac2d75594c50f9e86`；T523 / T522 / Phase 1 / 日常 App / 现网 Helper 未覆盖。
- 日常 `calibration.json` / `port-history.json` 未写入；隔离验收使用 `_t532/isolated-rc1/`。
- 待 Owner 验证：
  1. 当前 Mac 打开 RC1、关于页、设置 → 模型校准；用同一 ZIP 换第二台 Mac。
  2. 真实插拔完成一次槽位校准；模拟通过不算实机通过。
  3. 真机端口「已连接 / 设备身份暂未读取」与 DFU 标题。
  4. macOS 13 或 14 实机启动兼容试验包；目标系统未验收。
  5. 恢复模式已按旧 `reboot serial` 顺序接回（精确端口/RID）；真实设备进入 Recovery 仍未验证，保持 HARDWARE VALIDATION PENDING。
- 公开分发缺 Developer ID 分发证书与公证；当前只能标「内部测试候选」。HARDWARE_VALIDATION 保持 PENDING。

## 6. 2026-11-11 13:40 Asia/Shanghai · macOS 26 测试包

- Owner 更正最低兼容要求为 **macOS 26**；产品目标系统改为 26.0，不再以 13/14 为当前交付目标。
- 测试包：`_t532/delivery-macos26/牛半仙Mac维修辅助工具-1.0-macOS26-测试.zip`
  - SHA-256 `deeae17c63ae74ca2d921dfb4ddcde6e9da201f58abb8a93458425a653e3784a`（3,148,269 字节）
  - 前一包保留：`-macOS26-测试-build1430.zip` SHA-256 `639c2bbc0aec215fd7a63be6e9834a46bf0d5a790d7a23ab388cd3c6a4c1c732`
  - 构建号 `20261111.1560`；App CDHash `a54d82e470519ef0491052c316f409e98c0abc8a`
  - App / mra-helper / direct_rid_dfu 三件套均按 26.0 重编；`LC_BUILD_VERSION minos` 全部 26.0，`LSMinimumSystemVersion=26.0`（不是只改 plist）
  - App 深度签名验证通过；Apple Development，未公证；内部测试候选
  - 安装 `--dry-run`：`MINOS_EFFECTIVE=26.0`、`MINOS_CONSISTENT=YES`、`EXISTING_INSTALL=KNOWN`、`DRY_RUN_OK`
  - 未执行正式安装、未替换现网 Helper
- Helper 识别：新 26.0 载荷期望哈希 `916b78cb…`/`f5bc28e0…`；旧 27.2 已安装载荷 `44d54a4c…`/`2a009425…` 已列入 known legacy，App 不会把旧文件当未知；DFU/重启发送路径未改。当前 Mac 不要求重装 Helper。
- 本包包含 A2485 同机型精确命中修正、左下主机校准状态/「去校准…」、端口「已连接 / 设备身份暂未读取」、导出旁「作废并停止／作废本次日志」。
- 修复 Helper 管理严重交互缺口：旧版状态现在同时给出「升级 Helper」与「卸载 Helper…」；管理脚本改为通过 `osascript do shell script … with administrator privileges` 弹出 macOS 管理员授权，不再用 GUI 进程直接 `sudo` 静默失败。
- 卸载脚本同时接受新 26.0 哈希和旧 27.2 `44d54a4c…`/`2a009425…`，旧 Helper 可真正清理/重装；安装脚本已把旧 27.2 三元组列为 known predecessor。
- 已用 `uninstall-mra-device-control.sh --dry-run` 验证旧 27.2 Helper 被识别并给出 WOULD_DELETE，不再 STOP_UNKNOWN_VERSION；未执行真实删除。
- 又修复 26 实机“装不上”的 quarantine 传递：App 确认后现在确实传 `MRA_QUARANTINE_CONFIRM=yes`；此前只设置了一个脚本不读取的变量，GUI 无 TTY 时脚本直接 `STOP_QUARANTINED_PACKAGE`。
- 安装/卸载/quarantine 脚本与 Helper plist 已随 App 打包到 `Contents/Resources/helper-management/`；App 通过 `MRA_APP_DIR` 指定自身路径，App 被拖到「应用程序」、旁边没有脚本时仍可管理 Helper。
- 管理失败时设置页显示脚本输出最后 4 行；完整日志在 `~/Library/Logs/MRA Device Control/helper-management.log`。
- 新机未安装 Helper 时，主界面 1.2s 后（或检测到 `.notInstalled`）弹出「需要安装 Helper」提示；点「授权安装」一次即进入 macOS 管理员授权并执行安装。安装/升级/卸载按钮也改为一键直达授权，不再先走额外确认框。
- 「重置 Configurator」按钮原样执行 Owner 桌面「重置刷机软件.app」的 `main.scpt` 命令：`killall 'Apple Configurator'` → 清 `~/Library/Caches/com.apple.AppleConfigurator*` → 清 `~/Library/Application Support/Apple/Apple Configurator*` → `killall -STOP -c usbd` → 重新打开并置前。命令顺序、参数和 1s/2s 延迟均按原脚本，不增删。
- usbd 步骤不再走 `osascript` 密码授权，改由 Helper 新增的固定 root 动作 `resetUsbd`（Helper `0.2.4`）执行；重置结果弹窗已删除，只在按钮下方显示状态。
- 旧 Helper `0.2.2/0.2.3`（916b…）没有 `resetUsbd`；此时重置会明确提示先到设置 → Helper 升级，升级只需一次管理员授权，之后重置不再输密码。新 Helper 哈希 `197d1f33…`，旧 916b 已列入 known legacy。
- 修复“只关不重开”：重置流程无论中间步骤（包括旧 Helper 不支持 resetUsbd）是否失败，都会继续 `open -a "Apple Configurator"` → 等待进程 → `activate` 两次置前；失败原因显示在按钮下方，不再把 Configurator 留在关闭状态。
- 观察到 13:54 有一条用户侧的 `install-success` 记录：当前 `/Library/PrivilegedHelperTools` 已是 26.0 `916b…`/`f5bc…`，launchd running；本轮没有主动执行正式安装，也没有再替换。
- 验证：`DeviceCapturePrototypeTests` 157 tests，1 skipped，0 failures（日志 `_t532/test-logs/swift-test-device-20261111T1423+0800.txt`）；在构建机 macOS 27.3 隔离启动 About 页显示「版本 1.0（20261111.1560）」。
- 未在真实 macOS 26 上运行；测试包状态只写「26 测试包，待实测」。13/14 兼容试验包保留为历史实验，不再是当前最低系统目标。
- 前序包保留：26 测试 1550 `693836b9…`、1540 `fae1a1fd…`、1530 `3a505dc7…`、1520 `953a8256…`、1510 `e82a3668…`、1500 `02b8379a…`、1450 `ef22cf43…`、1430 `639c2bbc…`；RC1 1405 `3099a817…`；T545 未覆盖。




## 7. 2026-11-11 14:26 Asia/Shanghai · macOS 26 单 App 包

- Owner 要求只复制一个 `.app`，不带外部脚本；已把安装/卸载/quarantine 脚本与 Helper plist 全部放入 App 内 `Contents/Resources/helper-management/`。
- 单 App ZIP：`_t532/delivery-single-app/牛半仙Mac维修辅助工具-1.0-macOS26-单App.zip`
  - SHA-256 `e07c063c3ea3769cb7c9ab69312f020c03b8b8323905e942d4e4dead34a68853`（3,120,761 字节）
  - 构建号 `20261111.1570`；App CDHash `1fdc6e421bb6bf3ef1370378275ffd1042d79710`
  - ZIP 内只有 `牛半仙Mac维修辅助工具.app`，无外部脚本、无 `._` AppleDouble 文件
  - App 内包含 `mra-helper`、`direct_rid_dfu`、`helper-management/`（install/uninstall/quarantine/plist）、内置校准、图标、二维码
- 验证：解包后 `codesign --verify --deep --strict` 通过；在只有 App 的干净目录中，用 App 内部脚本 `--dry-run`：`MINOS_EFFECTIVE=26.0`、`MINOS_CONSISTENT=YES`、`DRY_RUN_OK`。
- 用法：解压 ZIP，把唯一一个 `牛半仙Mac维修辅助工具.app` 拖到目标 Mac（应用程序或任意目录），打开后按提示安装/升级 Helper；不需要再复制脚本。
- 前提：重置 Configurator 仍需要目标 Mac 已安装 Apple Configurator；Helper 管理由 App 内部脚本执行。旧 Helper 升级一次后，重置的 usbd 步骤不再输密码。
- 未公证、Apple Development 签名；内部测试候选。未在真实 macOS 26 上执行安装/重置。


## 8. 2026-11-11 14:42 Asia/Shanghai · 恢复模式按钮接回（单 App 1610）

- Owner 的旧版恢复按钮实际执行 `dfu_tool reboot serial`；当前版本按“重启按钮同一条链路、只换后端命令”接回，不再引入旧 `dfu_tool` 广播式二进制。
- UI：`进入恢复模式` 按钮启用，调用 `DeviceControlModel.performRecovery()` → `performSingle(.recovery)`；与重启共用同一选中 controller/PortNumber/RID、Helper 单发、10s 超时、不重试。
- Helper：`HelperAction.recovery`，Helper 版本 `0.2.5`（`c81917fd…`）。
- 后端：`direct_rid_dfu recovery --controller ID --port-number N --rid N`，走同一 `prepare_target` 单候选门禁，再执行 `DoRebootSerial`（先普通 reboot VDM `{0x05ac8012,0x105,0x80000000}`，再 target serial VDM `{0x05ac8012,0x01840306}` + local DVEn），与旧 `dfu_tool reboot serial` 顺序一致；回执 `RECOVERY_REQUESTED`，只表示请求已发送，不是恢复模式成功证明。
- 后端按 macOS 26.0 重编：`MINOS_BACKEND=26.0`；哈希 `b03160fd…`；CDHash `2e75d08a…`。
- 单 App 包：`_t532/delivery-single-app/牛半仙Mac维修辅助工具-1.0-macOS26-单App.zip`
  - SHA-256 `ec9811bbb4588a5c2eace6fb6cf61f35cdb1e1311c8e618d4835ebde4e4b2267`（3,121,924 字节）
  - 构建号 `20261111.1610`；App CDHash `938601119f50ba32257c906313932b1337275676`
  - 安装预检 `MINOS_EFFECTIVE=26.0`、`MINOS_CONSISTENT=YES`、`EXISTING_INSTALL=KNOWN`、`DRY_RUN_OK`
- 测试：157 tests，1 skipped，0 failures（`_t532/test-logs/swift-test-device-20261111T1442+0800.txt`）。
- 未操作真实设备；恢复模式 VDM 属于 `HARDWARE VALIDATION PENDING`，不能用软件测试或回执声称真实进入恢复模式。
- 当前机器已装 Helper 0.2.4（197d…），需升级到 0.2.5 后恢复按钮才可执行；旧 0.2.4 已纳入升级前代与 known legacy。

> 5.5 的“保持禁用”是 14:00 前结论；1410 后已按 Owner 要求接回 targeted recovery，见本节。

## 9. 2026-11-11 15:44 Asia/Shanghai · 1630：About 双语 + 恢复失败回执诊断

- 失败现场保留：`_t532/recovery-failure-20261111T144757/`（窗口截图、AX 原文、Helper 0.2.5/哈希、诊断）。requestID `42E5F711-79CF-4EBE-8871-675A61B8639F`；目标 100000760/Port 2/RID 1；UI 回执 `dispatch=NOT_DISPATCHED reason=BACKEND_FAILED`。exitCode/stdout/stderr/backend JSON 未保存，**本次失败点未取得**；未重装、未重发。
- 旧 `dfu_tool` 反汇编确认 `DoRebootSerial = DoReboot -> WaitConnected(30×100ms, 1s settle) -> DoSerial`；1610 漏了 WaitConnected，1630 backend 已补。serial VDM/reboot VDM/local DVEn 载荷与旧版一致；目标选择改为精确 triplet（旧版为广播/最后 HPM，非原样）。无 macOS Recovery 界面证据；`RECOVERY_REQUESTED` 只是请求回执。
- App 1630 新增 backend stdout JSON 解析：pre-send 显示“发送前被拒绝”，post-send 显示“已发送 · 后续失败”，缺失回执显示“本次原因未取得”；技术详情保留 exit/stage/raw stdout/stderr；DFU/普通重启路径未改。
- About 1630：Swift 1.0「设置 → 关于软件」增加 `牛半仙 Mac 维修辅助工具` / `Mac Restore Assistant`、开发者 `牛半仙（niubanxian1）`、项目介绍/开源理念、GitHub、MIT/copyright；保留小牛图标、二维码入口、邮箱、动态版本和作者行。GitHub 公开产品仓库已核对；MIT 依据仓库 `LICENSE`（本地 Swift 工程根目录无 LICENSE）。
- 单 App ZIP：`_t532/delivery-single-app/牛半仙Mac维修辅助工具-1.0-macOS26-单App.zip`；SHA-256 `6a12c951f0884ad875bdd66f10490105b4c6886e0b760e51f59148f04e0603bb`；构建 `20261111.1630`；CDHash `0d8f74746eebc20d31ada7c302bea6754d875c24`。
- 真实 About 截图：`_t532/delivery-single-app/about-1630-real.png`（版本 1.0（20261111.1630））。
- 测试：161 tests，1 skipped，0 failures（`_t532/test-logs/swift-test-device-20261111T1543+0800.txt`）。
- macOS 26 / 真实恢复界面仍待 Owner 手动验收；旧 Python `default-workspace/MacBook` About 修改仅保留参考，不打包。

## 10. 2026-11-11 16:00 Asia/Shanghai · 最终底栏口径（1650）

- 主窗口默认宽度 1155×671 的底栏固定两盏独立灯，不显示主机型号，不再放重复「设置」；右上角设置保留。左侧上方/左侧下方/右侧以及主机型号、校准来源、具体映射仍在端口详情。
- Helper 灯：`c81917fd…` 本体 + `b03160fd…` 已知旧 backend + 当前 plist，服务/socket 正常 → 橙色 `Helper · 后端待更新`；点击进 Helper 管理页。未知文件仍未知，不自动覆盖，不显示「检测未完成」或「全套最新」。预期 backend `7105ddd2…`。
- 校准灯以「已确认的物理端口布局」为单位，不按 CPU/年份/显示名：
  - 绿色 `已校准`：当前主机直接命中已验证记录，或命中 Owner 已确认的同模具共享 PortNumber/RID 布局；不提示重新校准。
  - 橙色 `未校准`：机型已知但无精确/已确认共享记录；未确认的 same-mold 也保持橙色，悬停说明「正在使用同模具布局，当前机型未经精确校准」。
  - 灰色 `无模型`：机型已知但模型库没有当前主机可用模型；`机型未识别`：主机机型未读到，不等于模型库为空。
  - 橙色 `布局待核对`：当前主机已映射数据口的 PortNumber/RID 集合与库记录真实冲突。仅比较已映射数据口，MagSafe/充电 HPM 节点不算冲突。
- 数据：`Resources/builtin-calibrations.json` 增加 Owner confirmed `MacBookPro18,1` + `MacBookPro18,2` A2485 共享映射；18,2 本身有直接记录（displayName 写 M1 Pro，但判定只看 host id + layout，不看显示名）。这只是共享映射，不宣称 18,1/18,2 都分别做过实机校准。
- 单 App 1650：`_t532/delivery-single-app/牛半仙Mac维修辅助工具-1.0-macOS26-单App.zip`；SHA-256 `e2df46ec205781e458eabfee43ac5ec3b776dcea6baca3a816eab5ad76a47545`；构建 `20261111.1650`；CDHash `3565bb9556810417f94007c273e16b277123b05a`。
- 真实底栏截图：`_t532/delivery-single-app/bottom-status-1650-real.png`（Helper · 后端待更新 / 已校准）；真实 About：`_t532/delivery-single-app/about-1650-real.png`（版本 1.0（20261111.1650））。
- 测试：165 tests，1 skipped，0 failures（`_t532/test-logs/swift-test-device-20261111T1558+0800.txt`）。未安装、卸载或替换现网 Helper；未重发恢复。

## 11. 2026-11-11 16:08 Asia/Shanghai · 1670 最终收口

- **16:01:31.699 恢复现场（PID 3351，实际进程 `verify-status-1640`，构建 20261111.1640）**：requestID `EF7C6C19-6B8A-4C0D-8B87-234F623390EC`；exit 1；Helper 0.2.5；backend `RECOVERY_COMMAND_FAILED`、`send_performed=false`；stdout 有 `Rebooting target into normal mode... OK`、`Putting target into serial mode... OK`、`Putting local end into serial mode... Failed.`。证据在 `_t532/recovery-failure-20261111T160131/`。旧文案“发送前被拒绝；未发送”是错的；1670 改为只有 `PRE_BOUNDARY_FAILURE/TRIPLET_REQUIRED/UNKNOWN_COMMAND` 才说发送前拒绝，否则显示“恢复命令失败，是否已发送未确认”。
- **校准比较（1640 现场）**：expected `1:0(S3)、2:1(S4)、3:2(S5)`；actual raw 为 `1:0、2:1、3:2、1:5`，其中 `1:5` 是 MagSafe/充电 HPM，不是数据布局槽。1640 把全部 livePorts 纳入比较导致误报；1670 只比较 `orderedDisplayPorts` 的已映射数据口，expected/actual/slot/source 已做成 `HostLayoutMappingComparison`；真有冲突时详情显示预期/实测/仅预期/仅实测。当前 18,2 直接记录 → 绿灯“已校准”，详情“本机型直接匹配”。
- **发送条件**：1670 的真实按钮 `performDFU()` 离线用例（单端口、无目标枚举、两发间目标消失/刷新、第一发失败）确认两次都调用同一 controller/PortNumber/RID，第二发不被第一发失败取消。`canControl` 不读校准灯/设备观察；校准灯只展示。未改 DFU 调度。
- **DFU 诊断**：`DFUSequenceEvent.attempted` 区分“定时器已安排”与“实际调用”；日志保留两发 requestID、attempted、backend_called、confirmed_submit、exit、status、send_performed、reason、stdout/stderr。界面按“已尝试/后端确认提交/结果未知/观察到 DFU”显示，不再把 `BACKEND_FAILED` 一律写成未发送。
- **最终单 App 1670**：`_t532/delivery-single-app/牛半仙Mac维修辅助工具-1.0-macOS26-单App.zip`；SHA-256 `9b3b25ad8aa8c57de2e11153e8ae0eb2b2dfb86fa3aaa2c30abbbd3683741a7c`；构建 `20261111.1670`；CDHash `9a64b1b3d50bdc4b32f4322e17d4238a0060a527`。
- 真实底栏：`bottom-status-1670-real.png`（`Helper · 后端待更新` + `已校准`）；真实 About：`about-1670-real.png`（版本 1.0（20261111.1670））。测试：169 tests，1 skipped，0 failures（`_t532/test-logs/swift-test-device-20261111T1604+0800.txt`）。
- 未安装/卸载/替换现网 Helper；未重发恢复。新版等待重连 backend 是 `7105ddd2…`，当前现网仍是 `b03160fd…`；不自动安装。

## 12. 2026-11-11 16:23 Asia/Shanghai · 恢复模式只读核对 + 独立测试包

- 暂停 DFU 时序调查。当前运行窗口：PID 3351 = build 20261111.1640；PID 6522 = build 20261111.1660；1670 未运行。
- 最新可用恢复回执只在 1640 窗口：16:01:31.699，requestID `EF7C6C19-6B8A-4C0D-8B87-234F623390EC`，target 100000760/Port2/RID1，exit 1，stdout 失败点 `Putting local end into serial mode... Failed.`；backend JSON `RECOVERY_COMMAND_FAILED`、`send_performed=false`。1660 窗口没有恢复请求；没有更新的恢复回执，未重发。证据：`_t532/recovery-failure-20261111T160131/`。
- 16:01 stdout 没有 `Waiting for connection...`，对应旧 backend `b03160fd…`；当前磁盘 backend 已是 `7105ddd2…`，二者不可混用。
- `DVEn` 实际语义：`HPMPluginInstance::command` 在 IOKit Command 非零时返回 -1，否则返回寄存器 9 低 4 位（0..15）；`DoSerial` 把任何非零都打印 `Failed.` 并返回 1，未保存具体数值。旧源码/旧 `dfu_tool` 的 `DoSerial` 实现相同，没有可复用的“忽略 DVEn 失败”版本。
- 目标 serial VDM 已成功，失败在 local-end HPM DVEn；serial/reboot/exit 0 均不等于 macOS Recovery。缺的是已验证的 Recovery 入口 VDM/序列及目标屏幕证据；本轮不能安全地靠跳过 DVEn、反转判断、加延时或重试来声称修复。
- 独立测试包（只用于手动观察，不自动安装/不重发）：`_t532/delivery-recovery-1670/牛半仙Mac维修辅助工具-恢复模式-1670.zip`，SHA-256 `4ee8a862b698b5b8ffa91fce8e01ed30bc8ed9294b3ad38626e96785f1d3090b`；构建 20261111.1670；启动路径 `_t532/delivery-recovery-1670/牛半仙Mac维修辅助工具-恢复模式-1670.app`。
- 未安装/卸载/替换现网 Helper；未重发恢复。下一步由 Owner 指定精确端口后手动点击；若仍失败，需要新 stdout 的 `DVEn` 具体返回值，不能以旧 16:01 代替。

## 13. 2026-11-11 16:30 Asia/Shanghai · 旧版恢复基线比对

> **Owner 2026-11-11 复测更正：桌面旧版同样未能让目标进入 macOS 恢复模式；此前把旧版当作“恢复模式已实机验证”的解释已撤回。本节原始比对记录保留，仅用于说明 ZIP/主程序/dfu_tool 相同和旧版实际执行的 serial 链路，不再作为恢复能力证据。**

- 桌面包 `/Users/niubanxiandetuzhichakanqi/Desktop/MAC刷机助手.zip`（保持原样，未启动旧 App） SHA-256 `7ea441148d7a523511e78c64b93431f1757b07d836aaff0db802f35804526fa5`；微信同名包 SHA-256 `44b9ac6f9ae884eb8ff2a8be4b7e1b2b5166dd858baf250402bc6934cf2045d2`。解包后主程序 `aafda67c...`、`dfu_tool` `fb7cdf2d...`、base library `04a6db4a...` 完全一致；ZIP 哈希不同不是行为差异来源。
- 桌面版恢复链路：`action_recovery` → `run_dfu('reboot serial')` → `dfu_tool` → `DoReboot` → `WaitConnected` → `DoSerial`（目标 reboot VDM、目标 serial VDM、local DVEn）。旧版用 `dfu_tool` 扫描 HPM，无精确 Port/RID；当前 1.0 保留精确 selected triplet。
- 具体差异：16:01 回执来自旧 backend `b03160fd…`，stdout 没有 `Waiting for connection...`；当前磁盘 backend `7105ddd2…` 已补 `WaitConnected`。这是“同一 DoSerial 但旧版等待目标重连、旧候选立即发 local DVEn”的具体差异；不能据此断言 7105 一定成功或目标已进入 Recovery。
- `DVEn` 返回：IOKit Command 非零 → -1；否则寄存器 9 低 4 位（0..15）。旧/新 `DoSerial` 都把任何非零当失败且只打 `Failed.`，没有数值。serial/reboot/exit 0/`RECOVERY_REQUESTED` 不能替代目标屏幕出现 macOS 恢复选项；缺失仍是已验证 Recovery 入口步骤。
- DFU 基线：Owner 确认桌面版曾在无限重启 Mac 上最终被系统枚举为 DFU。以后 DFU 对照必须分开“后端已提交 / 系统已枚举 DFU / App 已更新显示”；本轮不改 DFU 时序、不重发。
- 独立测试包保留：`_t532/delivery-recovery-1670/牛半仙Mac维修辅助工具-恢复模式-1670.zip`，SHA-256 `4ee8a862...`，构建 `20261111.1670`；启动路径见该目录 README。未安装/替换现网 Helper，未重发。

## 14. 2026-11-11 16:42 Asia/Shanghai · 62242258 现场与 1680 诊断包

- 1670 新回执已只读保存：`_t532/recovery-1670-62242258/`；requestID `62242258-DD7C-4D65-86F8-3D59367BAAE4`，时间 `16:35:14.633 → 16:35:17.154`，target `100000760/Port2/RID1`，exit 1，Helper 0.2.5。
- 本次证据：`Waiting for connection.... Connected`（WaitConnected 成功）；`Rebooting target into normal mode... OK`；`Putting target into serial mode... OK`；`Putting local end into serial mode... Failed.`；backend JSON `send_performed=false`、`RECOVERY_COMMAND_FAILED`。即目标 reboot/serial 已提交，主机端串口启用失败，恢复界面未确认。
- App 失败提示现在按阶段显示：标题「目标已提交 · 主机端串口启用失败」；正文「目标重启与 serial 步骤已提交；主机端串口启用失败；恢复界面未确认」。不写成发送前拒绝，也不写成已进入恢复模式。
- 新 backend `ea512931a2793de2bc18fcd7b2b2a539d7964336b2696d75662b7d4cf34d2c15`（CDHash `18dbdc9cad4fc02edf36769c569530413dce5458`）保留 DVEn 原始诊断：`DVEn return=x, IOKit=0x..., write=0x..., reg9=...`；`-1` 与 `1..15` 仍按原逻辑失败，不忽略、不增加等待。
- 现网 installed backend 仍是 `7105ddd2…`；1680 包内新 backend **未安装**，没有重装/重发。安装脚本 dry-run：`MINOS_EFFECTIVE=26.0`、`MINOS_CONSISTENT=YES`、`EXISTING_INSTALL=KNOWN`、`DRY_RUN_OK`。
- 独立包：`_t532/delivery-recovery-1680/牛半仙Mac维修辅助工具-恢复模式-1680.zip`，SHA-256 `dd30fca9188c0e70058cea71aeef7a945cb6c51200b792f6872beae175ca94ad`；App CDHash `d79d654d46ff209396e7907a1498bc49d2c50fd1`；启动路径见同目录 README。
- 测试：169 tests，1 skipped，0 failures（`_t532/test-logs/swift-test-device-20261111T1640+0800.txt`）。DFU 未改、未重发。


## 15. 2026-11-11 16:47 Asia/Shanghai · Owner 更正：恢复能力撤回与分发禁用

- **更正**：Owner 刚刚复测，桌面旧版 `MAC刷机助手.zip` 同样未能让目标进入 macOS 恢复模式。此前“旧版恢复模式已实机验证/旧版正常”的表述撤回；原始测试记录、ZIP/AX/截图和 16:01/16:35 回执全部保留，不删除、不改写。旧版实际执行仍只是 `reboot serial`（reboot VDM + target serial VDM + local DVEn），不能证明恢复界面。
- **冻结**：DFU 与普通重启已由 Owner 实机验证可用，冻结，不再改时序/后端/UI 发送条件；本轮不动 DFU 双发。
- **分发 UI**：1.0 保留第三个按钮的位置，但禁用「进入恢复模式」；按钮下注明「当前版本暂无已验证的恢复入口」。`performRecovery()` 不再调用 `.recovery`/后端，点击不会只得到一次重启。
- **1680**：保留为诊断候选，不覆盖、不继续为“修通 DVEn”加延时/重试/新恢复包。1680 内的 backend 原始诊断只用于后续证据收集，不构成恢复入口。
- **调查结论（只读）**：本地旧契约 `privileged/contract.py` 把 `ENTER_RECOVERY` 设为空；当前后端只有 probe/dfu/reboot，`recovery` 命令只是 `DoRebootSerial`。旧版/新版都没有一个已验证的、由主机触发、精确指定目标并让目标屏幕出现启动选项并进入恢复工具的入口。
- 外部只读参照：Apple 官方 Apple Silicon 恢复路径要求目标关机后由人按住电源键，直到出现启动选项（[Apple Support 102518](https://support.apple.com/zh-cn/102518)）；`cfgutil` 手册是 iOS 设备工具，命令表没有 Mac 启动选项入口（[cfgutil man page](http://www.configautomation.omni-automation.com/cfgutil-man-page.html)）。这些只说明现有证据，不证明存在可用 API。
- **起始状态**：若目标是已启动的普通 Mac，当前没有已验证的主机触发恢复入口；若目标已关机，需要人工按住电源键进入启动选项；若目标已在 DFU/Recovery USB，Configurator/cfgutil 的 restore/revive 是另一类操作，且 USB Recovery 枚举不是目标屏幕证据。
- 调查有结果前不实现、不自动操作真机、不新增恢复入口。


## 16. 2026-11-11 16:49 Asia/Shanghai · 1690 分发安全包（恢复按钮禁用）

- 源码：`ContentView` 第三按钮保留位置但 `.disabled(true)`；`Models.performRecovery()` 不再调用 `.recovery`/后端，只给出「当前版本暂无已验证的恢复入口」提示。DFU、重启动作未改。
- 真实窗口截图：`_t532/delivery-distribution-1690/recovery-disabled-1690.png`，第三个按钮为灰色禁用，下方显示「当前版本暂无已验证的恢复入口」。
- 分发包：`_t532/delivery-distribution-1690/牛半仙Mac维修辅助工具-1.0-恢复入口禁用-1690.zip`；SHA-256 `160a3d2436b6735a03ea9f492af4fdcf36717d30e63b311e24b89fc5fdbc54a5`；构建 `20261111.1690`。安装 dry-run：`MINOS_EFFECTIVE=26.0`、`MINOS_CONSISTENT=YES`、`EXISTING_INSTALL=KNOWN`、`DRY_RUN_OK`；未安装。
- 1680 保持不变，作为诊断候选；不覆盖、不重发、不再为 DVEn/恢复假设出新包。全量测试：169 tests，1 skipped，0 failures（`_t532/test-logs/swift-test-device-20261111T1648+0800.txt`）。
- DFU 与普通重启保持冻结；本轮没有发送任何设备命令。

## 17. 2026-11-11 17:08 Asia/Shanghai · 启动选项测试包 1700（仅测试假设）

- 仅在编译条件 `MRA_TEST_BOOT_OPTIONS` 的 1700 测试包中，第三按钮改为「测试启动选项（3 秒 3 次）」；默认 1690 分发版仍是禁用「进入恢复模式」。
- 动作只用现有精确 `.reboot` 后端：点击时冻结 controller/PortNumber/RID，按同一起点 0、1.5、3.0 秒各发一次；每发独立 UUID requestID；不调用 `reboot serial`/`DVEn`；最多三次，不补发；运行中点击不另开组。
- 对端消失/无 ECID/机型未知不取消后续；只有主机侧无法唯一定位原端口才停止并说明，不换口、不广播。界面显示已尝试 1/3、2/3、3/3；可停止尚未发起的子请求；日志写每发 `backend_start`、requestID、目标、结果。
- 三次结束只显示「三次尝试已结束，请查看目标屏幕」，不宣告恢复模式。测试包使用新的 backend 诊断构建，但本轮 Bot 未向真机发送任何命令。
- 假后端测试：`BootOptionsTripleTests` 3 项通过；实测三次调用间隔约 1.5s/1.5s，同一目标、3 个独立 requestID、最多 3 发；运行中重复点击不增加；停止只取消未发起项；主机端口丢失停止且不换口。全量 172 tests，1 skipped，0 failures（`_t532/test-logs/swift-test-device-20261111T1705+0800.txt`）。
- 独立包：`_t532/delivery-boot-options-1700/牛半仙Mac维修辅助工具-启动选项测试-1700.zip`；SHA-256 `cfa706682a62b3774c5e23bbfab15d08bfaed356ad1309cbc4ee52b6f3979804`；构建 `20261111.1700`；真实 UI 截图 `test-ui-1700-active.png`。当前 1700 测试 App 已打开（PID 22112），未安装 Helper、未发送设备命令。

## 18. 2026-11-11 17:17 Asia/Shanghai · 右侧 Mac16,13 机型识别修复

- 现场（只读）：右侧 Mac16,13 当前为 connected；ECID `00061124360B801C`，序列 `KWCXXY29HT`，USB location `02100000`。DFU Blaster Pro PID 20328 为试用版，当前表格被 `Pro Feature` 遮住，未取得其型号/ECID 原文；本 App 修复前为 `已连接 Mac · 具体机型未知`。
- 原始 USB 节点 `Mac@02100000` 只有 `USB Product Name = Mac`、`idVendor=1452`、`idProduct=6405`、序列、ECID、location；**没有 deviceType/ProductType/model/Mac16,13**。断点在 `DeviceObserver.parse` 取不到机型字段，`TargetModelCatalog` 本身已有 Mac16,13，但无桥接。
- 可用只读来源：`/usr/local/bin/cfgutil list` 输出 `Type: Mac16,13  ECID: 0x61124360B801C  Location: 0x2100000`。旧 `port-history.json` 只有 ECID/mode/端口，没有 model，不能作为本次型号来源。
- 最小修复：新增 `TargetModelReadOnlyResolver`，只读 `cfgutil list`，按 ECID 优先、USB location 兜底绑定；只在 USB 记录缺 model 时 enrichment。`ObservedDevice` 增加 `modelSource`；详情显示「机型来源 cfgutil list（只读枚举）」。不使用主机校准库，不改发送/DFU/重启/恢复。
- 现场验证 1710：右侧标题/行显示 `MacBook Air（15 英寸，M4，2025 年） · 已连接`，详情机型来源正确；左侧不同 ECID/location 不继承。截图：`_t532/delivery-model-ident-1710/model-ident-1710.png`；证据：`_t532/model-ident-20261111T1709/README.md`。
- 独立包：`_t532/delivery-model-ident-1710/牛半仙Mac维修辅助工具-机型识别-1710.zip`；SHA-256 `24986609e8cda7eea0a6cdb5f22fcce50134d865ede199b9abc992de5c67f5d1`；构建 `20261111.1710`；未安装 Helper、未发设备命令。
- 测试：175 tests，1 skipped，0 failures（`_t532/test-logs/swift-test-device-20261111T1715+0800.txt`）。

## 19. 2026-11-11 17:24 Asia/Shanghai · 启动选项测试包 5 × 3 秒（1720）

- 测试包按钮：`测试启动选项（15 秒 5 次）`；排程 0/3/6/9/12 秒各一次普通 `.reboot`，整组 15 秒窗口结束后显示「五次尝试已结束，请查看目标屏幕」。仍固定点击时端口，独立 requestID；最多 5 次，不补发；运行中不另开组；可停止未发起项。不调用 `reboot serial`/`DVEn`。
- 默认分发版 1710 的恢复按钮仍禁用；DFU/普通重启未改。
- 假后端测试：5 次、相邻约 3 秒、同一目标、5 个独立 requestID；运行中重复点击不增加；停止只取消未发起项；主机端口丢失停止不换口。全量 175 tests，1 skipped，0 failures（`_t532/test-logs/swift-test-device-20261111T1723+0800.txt`）。
- 独立包：`_t532/delivery-boot-options-1720/牛半仙Mac维修辅助工具-启动选项测试-1720.zip`；SHA-256 `98af9f650b3facbeb045062f2c7e4a42c59af291d3c116907c83be0acb3a14cb`；构建 `20261111.1720`；真实 UI 截图 `test-ui-1720.png`。当前 1720 测试 App 已打开（PID 27514），未发送设备命令。

## 20. 2026-11-11 17:30 Asia/Shanghai · 机型识别边界审计与最终候选 1730

- **换机不串型号**：`TargetModelReadOnlyResolver.enrich` 现在对带 ECID 的新观测只接受 **ECID 完全匹配**的 hint；同一 USB location 上不同 ECID 的旧 hint 不会被用作型号。旧查询晚到也只对当前 `observedDevices` 做 ECID 匹配，不会把旧型号带到新设备。测试：`testDifferentECIDOnSameLocationDoesNotInheritOldModel`、`testAnotherPortDoesNotInheritTheRightHandModel`。
- **查型号不拖慢操作**：`ObservedDeviceReader`/`refreshObservedDevices` 先应用原始端口状态；`cfgutil list` 只在后台 `Task.detached` 中执行，每未知 ECID/location 至多启动一次，`queryInFlight` 防重复；4 秒 watchdog 终止超时进程。缺失/空结果/超时只让型号保持未知，不阻塞端口刷新、DFU 或重启发送。`canControl` 不读取型号或 cfgutil 状态。
- 1710 保留；1710 在 17:16 的右侧 Mac16,13 实测记录仍有效。1730 为带入异步/ECID 严格边界的最终候选，默认分发 UI 仍禁用恢复按钮；独立测试包 1720 的 5×3 时序不变。
- 1730 实测：左侧 Mac14,2 由异步 cfgutil 补全，显示 `MacBook Air（M2，2022 年）`，来源 `cfgutil list（只读枚举）`。复核末尾 `cfgutil list` 当前只列左侧 `Mac14,2`（右侧目标暂时不在枚举中）；右侧 Mac16,13 的既有验证仍是 1710 截图，不将左侧型号归到右侧。
- 全量测试：177 tests，1 skipped，0 failures（`_t532/test-logs/swift-test-device-20261111T1728+0800.txt`）。
- 最终候选包：`_t532/delivery-final-1730/牛半仙Mac维修辅助工具-最终候选-1730.zip`；SHA-256 `39a676e3b7584c6a5096cdacfca2226908cead49c17c5501f4350d13bf0f0367`；构建 `20261111.1730`；未安装 Helper、未发送设备命令。

## 21. 2026-11-11 17:35 Asia/Shanghai · 1730 + 1720 合并最终候选 1740

- 基线：1730（异步 cfgutil、ECID 严格绑定、恢复按钮禁用）合入 1720 的五次重启序列。序列实现未重写：首次发送 0 秒，1/2/3/4/5 发在 0/3/6/9/12 秒，等待起点为点击时 `bootOptionsTestStartedAt`，15 秒窗口结束；五次固定点击时 controller/PortNumber/RID，独立 requestID，最多五次，不补发，运行中不另开组，可停止未发起项。不调用 `reboot serial`/`DVEn`。
- 产品 UI：第三按钮中文「恢复模式」/英文「Recovery」，默认启用；序列结束反馈「恢复模式请求已完成，请查看目标 Mac 是否出现齿轮『选项』」，不宣告已进入恢复。DFU、普通重启、日志、校准、Helper 管理未改。
- 机型识别继续 1730：端口先更新，`cfgutil list` 后台补全，ECID 严格匹配；查询失败/超时不影响操作；M2/M4 映射与来源保留。
- 离线入口测试：`performRecoveryMode()`（UI 按钮调用）五次均为 `.reboot`，同一目标，5 个独立 requestID，间隔约 3s，总计 5 次；无 `.recovery`/普通单发/serial 路径。全量 176 tests，1 skipped，0 failures（`_t532/test-logs/swift-test-device-20261111T1733+0800.txt`）。
- 最终包：`_t532/delivery-final-1740/牛半仙Mac维修辅助工具-1.0-1740.zip`；构建 `20261111.1740`；SHA-256 `23981089b02dbb11b4450342a717676b71cac4886bc22b57e48a54e8644dd2f8`；ZIP 内只有一个 `.app`；App 签名通过，CDHash `70f1e1554e8cc1cd85c4981478b7c0b169c69cf9`；App/Helper/backend minos 26.0；LSMinimumSystemVersion 26.0。
- 内嵌：Helper `c81917fd…`；backend `ea512931…`（诊断构建）。现有用户**不需要强制更新 Helper**：Helper 本体/协议未变，现网 backend 7105 已支持重启；包内 e32 是可选诊断更新，未安装。现有 Helper 0.2.5 + 7105 可执行五次重启。
- 1720 的时序有 Owner 本人实机成功记录；1740 仅完成离线合并/回归，尚未实机操作；最终由 Owner 验收。

## 22. 2026-11-11 17:50 Asia/Shanghai · 六语言切换预览 1750

- 设置新增「语言」页：跟随系统、简体中文、繁體中文、English、日本語、한국어；选择持久化，只改变显示，不参与端口/设备/DFU/重启/恢复/采集。
- 静态外壳、设置页签、主操作、关于页已本地化；动态设备/诊断文案加了 `L10n` 翻译层，但**仍未覆盖全部技术字符串**，英文/日文/韩文截图中仍有中文回退。按 Owner 的完整多语言验收标准，1750 只能算语言预览，不是完成的最终包。
- 多语言布局测试：en / ja / ko / zh-Hant 主窗未裂；但混排问题仍存在（如端口详情、采集状态、部分 Helper/校准页面）。
- 1750 包：`_t532/delivery-language-1750/牛半仙Mac维修辅助工具-语言预览-1750.zip`；SHA-256 `dbb1b5826f91b30f5eccb0682758aeae41899a639bf1effc13ccdeb1405f9141`；构建 20261111.1750；176 tests，1 skipped，0 failures（`_t532/test-logs/swift-test-device-20261111T1749+0800.txt`）。
- 1740 最终候选保持不变；1750 未安装 Helper、未发设备命令。

## 23. 2026-11-11 17:52 Asia/Shanghai · 语言预览 1760（应用名修正）

- 应用名规则：简体/繁體中文显示「牛半仙Mac维修辅助工具」；English/日本語/한국어显示「Mac Restore Assistant」。窗口标题、主标题、About 主名称统一使用该规则。
- 语言预览 1760：6 种语言选择、静态外壳/设置/主操作/关于标签已本地化；动态设备/诊断技术文案仍有中文回退，仍是预览，不是完整多语言最终版。
- 1760 包：`_t532/delivery-language-1760/牛半仙Mac维修辅助工具-语言预览-1760.zip`；SHA-256 `f65e745be83a24eeae67cff7bbbded3a777f0e5b53a38944adc66c63b1c83d13`；构建 20261111.1760；176 tests，1 skipped，0 failures（`_t532/test-logs/swift-test-device-20261111T1751+0800.txt`）。
- 1740 最终候选保持不变；1760 未安装 Helper、未发设备命令。

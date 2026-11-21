# Mac Restore Assistant

**A free and open-source utility for MacBook repair professionals.**

Mac Restore Assistant is a native macOS workbench for DFU mode, physical port
control, device information, firmware preparation, dual-device Restore, and
independent raw-log collection. It is built for repair workflows where a wrong
device or an unverified percentage is worse than a slow answer.

## Three core capabilities

1. **Stable device control** — DFU / Reboot / Recovery / Helper and physical
   port control with explicit per-port binding, not a broadcast to every
   attached device.
2. **Real hardware information** — actual USB-C / USB4 / Thunderbolt / PD
   topology, port identity, ECID, CPID/BDID and connection health as reported
   by the host and device.
3. **Independent raw logs** — RLM capture that keeps raw stdout/stderr separate
   from the UI projection, with rule-based error clues only (no AI diagnosis).

## 1.0.8-rc highlights

- **Apple Native Precision Tool V2** — a dark, professional three-page
  workbench with a real S3/S4/S5 physical-port bar and top three-port status
  pills. Layouts are verified at 920×680 and 1000×720 in light/dark modes.
- **Unified dual-device Restore workbench** — independent firmware, progress,
  logs, symmetric 3-second force-stop, and cancel-then-restart workflow per
  device. The viewed task can be switched without changing the physical control
  target.
- **Real DFU CPID/BDID parsing and strict `BuildManifest` compatibility** —
  compatibility comes from Apple's manifest, not a filename guess. A firmware
  that does not list the target ProductType is shown as incompatible.
- **Lightweight firmware discovery and folder watching** — Spotlight + a
  DispatchSource directory watcher with a 1.5-second debounce, a utility queue,
  complete-scan-only pruning, and automatic deferral while a Restore is active.
- **Last-success duration reference** — read-only projection of real successful
  history by ECID/firmware, model/firmware, or the model's most recent success.
  It is a reference only; it never fabricates progress.
- **RLM independent logging and rule-based error focus** — raw bytes remain the
  evidence; the UI shows a bounded preview and keyword clues, not generated
  diagnosis.

## Safety and validation boundaries

- **No built-in AI fault diagnosis.**
- **No online/ECID gate for entering DFU.**
- Offline automation: **850+ tests pass**, including P1 restore guards,
  acceptance tests, Python checks, and four-language L10n.
- A **single-machine M2 real Restore** has been performed. Cross-model and
  dual-device concurrent hardware matrices are still being validated; software
  tests are not hardware proof.
- Local builds are **not Apple-notarized**. The source is provided so you can
  inspect and build it yourself. A Developer ID signature/notarization is a
  separate release process.
- DFU/Restore is destructive. Use only on hardware you own or are authorized to
  service. Do not run a restore against a device you cannot identify.

## Build from source

Requirements: macOS 26 SDK, Swift 6 / Xcode 26 or newer.

```bash
git clone https://github.com/niubanxian1/Mac-Restore-Assistant.git
cd Mac-Restore-Assistant
swift build -c release
swift test
```

The package builds the app executable (`DeviceCapturePrototype`) and the
`mra-helper` executable. The app bundle metadata is in `Info.plist`; resources
are under `Resources/`. Helper installation is not performed by `swift build`.
If you package the app yourself, sign it with your own identity and verify:

```bash
codesign --verify --deep --strict --verbose=2 /path/to/Your.app
```

The repository intentionally excludes built `.app`, `.zip`, `.ipsw`, `.dmg`,
compiled helper binaries, customer logs, and private engineering records.

## Version

`1.0.8-rc` — see [RELEASE_NOTES_1.0.8-rc.md](RELEASE_NOTES_1.0.8-rc.md).

## License

See [LICENSE](LICENSE). Contributions are welcome via pull requests.

---

## 中文简介

Mac Restore Assistant 是面向 MacBook 维修人员的原生 macOS 工具，核心是三件事：

1. **稳定可控的设备操作**：DFU / 重启 / 恢复模式 / Helper 与物理端口控制，按端口明确绑定，绝不广播。
2. **真实硬件信息**：展示本机真实的 USB-C / USB4 / Thunderbolt / PD 拓扑、端口、ECID、CPID/BDID 与连接状态。
3. **独立可靠的原始日志**：RLM 将原始 stdout/stderr 与界面投影分离；报错线索仅基于规则，无内置 AI 诊断。

`1.0.8-rc` 包含暗黑专业三页工作台、双机独立 Restore、真实 DFU 身份解析与严格 `BuildManifest` 兼容性校验、固件目录自动监听、上次成功用时参考和 RLM 日志聚焦。离线 850+ 测试全过；已完成单机 M2 真机实刷，跨机型/双机并发矩阵仍在验证。本地构建未公证，请从源码自行构建并签名。

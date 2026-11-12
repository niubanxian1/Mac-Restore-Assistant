# MRA Device Control Prototype 0.2.2 — 部署说明（minos 一致 / quarantine 预检）

工作区：`/Users/Shared/MRA_DEVICE_CAPTURE_PROTOTYPE_0.2.2_20261110T1106Z`

本文件只描述 0.2.2 工作区中的 Info.plist、安装/卸载脚本与部署预检。未改 App 业务逻辑，未改冻结 0.2.1 发布目录或源码树，未在开发机重装 Helper，未改 Gatekeeper / AMFI / spctl / SIP，未执行真机 DFU / Reboot。

## 分发状态

本包是工程候选，不是可公开分发版本。当前签名是 Apple Development 本地测试签名，不是 Developer ID。本仓库没有公证凭据，也尚未启用 Hardened Runtime。

```
DISTRIBUTION_READY=NO
NOTARIZATION=PENDING
HARDENED_RUNTIME=PENDING
ENGINEERING_CANDIDATE_ONLY=YES
```

不得把 Apple Development 本地测试包称为可公开分发版本。另一台 Mac 上若出现 Gatekeeper 提示，不要把它当成 Helper、DFU 或 backend 故障。正式分发需要 Developer ID、公证并 staple，且须由构建/签名负责人完成，不在本脚本里关闭或绕过系统安全策略。

## 版本与最低系统

| 项 | 值 |
|---|---|
| `CFBundleShortVersionString` | `0.2.2` |
| `CFBundleVersion` | `20261110.1945`（正式候选构建号，已重签） |
| `LSMinimumSystemVersion` | `27.2` |
| App / Helper `vtool` minos | `27.2` |
| `direct_rid_dfu` `vtool` minos | `27.2` |
| 生效最低系统 | `27.2`（取捆绑二进制最高 minos，并与 Info.plist、安装器预检和本文档对齐） |

Worker C 不能重编后端。实测 `direct_rid_dfu` 的 Mach-O minos 为 27.2，因此本版统一声明最低系统为 macOS 27.2，并在安装器里拒绝更低的主机版本。不再宣传支持 macOS 14。没有对 macOS 14 运行时行为做猜测。`Package.swift` 仍是 `.macOS(.v14)`；把 platforms 改为 27.2 的提案写在证据目录 `PACKAGE_SWIFT_PROPOSAL.md`，由 Orch 合并，本角色未直接改 `Package.swift`。

源模板：工作区根目录 `Info.plist`。Candidate 包内 `Contents/Info.plist` 已同步为 `LSMinimumSystemVersion=27.2`、短版本 `0.2.2`。

**必须重签后再装。** 改 Info.plist 会使 Candidate App 的现有签名失效。本角色不会重签、不会安装 Helper。请由构建/签名负责人重签 App（以及如有需要的 Helper / backend）后再做安装验证。在重签完成前，安装器会在签名预检阶段失败并中止，这是预期现象。

## 安装预检

脚本：`install-mra-device-control.sh`（根目录与 `Candidate/` 内容相同）。本包**不依赖**开发机上的 0.2.1 `BACKUP_DIR`（`/Users/Shared/MRA_HELPER_ROLLBACK_20261110T1650`）。失败回滚只使用本次安装前写入 `install-record/pre-install-backup/` 的包内快照；若是全新安装则在服务已停止后，只删除本包刚写入且哈希匹配的文件。

预检在任何系统复制、bootout、bootstrap 之前执行，顺序如下：

1. 定位 App：优先脚本同目录，其次 `Candidate/`。
2. **哈希：** 校验 helper / backend / plist 的固定 SHA-256。
3. **签名：** `codesign --verify --strict`（App 使用 `--deep`）以及 plist / Info.plist 的 `plutil -lint`。发现 quarantine 时也必须先完成这一步，再询问是否清除。
4. **minos 一致：** 读取 App、Helper、backend 的 `vtool` minos，以及 Info.plist 的 `LSMinimumSystemVersion`。
   - 输出 `MINOS_APP`、`MINOS_HELPER`、`MINOS_BACKEND`、`MINOS_PLIST`、`MINOS_EFFECTIVE`、`HOST_OS`。
   - plist 必须等于捆绑二进制的最高 minos，否则 `MINOS_MISMATCH` 并中止。
   - 本机 `sw_vers` 低于生效最低版本时输出 `STOP_UNSUPPORTED_OS` 并中止。
   - 通过时输出 `MINOS_CONSISTENT=YES`。
5. **已安装版本（只读）：** 目标路径若已有文件，三个文件必须组成已知的 0.2.2 或前任三元组，否则 `STOP_UNKNOWN_VERSION`，不覆盖。
6. **quarantine 预检：** 只扫描当前部署载荷（App 包、plist、安装/卸载/quarantine 脚本）。不把整个源码工作区当作清除根目录。
   - 发现 `com.apple.quarantine` 时输出 `QUARANTINE_DETECTED=<路径>` 和 `QUARANTINE_CLEARED=NO`。
   - `--dry-run` 只报告，不清除属性，并以 `STOP_QUARANTINED_PACKAGE` 结束。
   - 非交互（无 TTY）同样 `STOP_QUARANTINED_PACKAGE`，不复制任何系统文件。
   - 交互安装会询问：「是否只清除当前部署目录的 quarantine？」只有明确输入 `yes` 后，才对上述载荷路径执行 `xattr -dr com.apple.quarantine`。
   - 清除后复扫；仍残留则失败。未确认或清除失败：`STOP_QUARANTINED_PACKAGE`。
   - 不静默删除，不关闭 Gatekeeper，不运行 `spctl --master-disable`，不改 AMFI / SIP。

安装记录写到脚本目录下的 `install-record/`。失败日志也只写这里，不写 0.2.1 `BACKUP_DIR`。

`--dry-run` 不会 bootout、不会复制系统文件、不会 bootstrap。当前开发机不要执行无 `--dry-run` 的安装：本角色禁止重装开发机 Helper。

## 卸载

脚本：`uninstall-mra-device-control.sh`。

- 只处理 `com.mra.devicecontrol.helper` 及其配套 backend / plist。
- 三个已安装文件哈希必须与本包预期完全一致，否则 `STOP_UNKNOWN_VERSION`，不删除。
- 删除前等待：launchd label 不存在、精确路径 Helper 进程已退出、socket 无 listener。超时输出 `DELETE_ABORTED_*` 和 `NO_FILES_DELETED`，不删除文件。
- 不使用 SIGKILL，不改系统安全设置，不对设备发命令。
- `--dry-run` 只报告，不 bootout、不删除。

**开发机警告：** 当前 0.2.2 包的 helper / backend / plist 哈希与已装的冻结 0.2.1 Helper 相同。若在本开发机执行正式卸载，会卸掉正在使用的 Helper。不要在本机跑正式卸载。

## 使用

```bash
# 仅预检，不改系统（可在本工作区执行）
bash install-mra-device-control.sh --dry-run
bash uninstall-mra-device-control.sh --dry-run

# 正式安装仅用于尚未安装该 Helper 的干净机器，且须先重签 App
# 不要在当前开发机执行：
# sudo bash install-mra-device-control.sh
```

## 本次未做

- 未修改冻结 0.2.1 发布目录或 `/Users/Shared/MRA_DEVICE_CAPTURE_PROTOTYPE`。
- 未重签、未重装、未 bootout 开发机 Helper。
- 未改 Gatekeeper / AMFI / `spctl` / SIP。
- 未执行真机 DFU / Reboot / Restore / Revive / Erase。
- 未改 App / Helper / backend 业务代码或 `Package.swift`。


## 正式候选重签（Orch，2026-11-10 19:46 Asia/Shanghai）

官方发布目录：`/Users/Shared/MRA_DEVICE_CONTROL_RELEASE_0.2.2_20261110T1145Z`。已用工作区 `Package.swift` platforms `macOS 27.2` 重编 Release 的 App 与 Helper，并把三元组 backend（Resources 未签名原件 `b2e93d8f…`）签入包内。`vtool` 实测 App / Helper / backend 均为 minos 27.2，与 `LSMinimumSystemVersion=27.2` 一致。签名身份为 Apple Development（Team `6NFD357KL3`），`flags=none`，无 Hardened Runtime，无公证。`DISTRIBUTION_READY=NO`。

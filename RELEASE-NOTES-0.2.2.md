# MRA Device Control Prototype 0.2.2 — 部署发行说明

工程候选，不是可公开分发版本。

```
DISTRIBUTION_READY=NO
NOTARIZATION=PENDING
HARDENED_RUNTIME=PENDING
ENGINEERING_CANDIDATE_ONLY=YES
```

当前二进制为 Apple Development 本地测试签名，没有 Developer ID，未公证，Hardened Runtime 仍为 PENDING。不得把本包称为可公开分发版本。

## 本版部署变更

- 统一声明最低系统为 macOS 27.2。App / Helper 的 Mach-O minos 仍为 14.0，但捆绑的 `direct_rid_dfu` minos 为 27.2；在无法按 macOS 14 构建 backend 的前提下，不再宣传支持 macOS 14。`Info.plist` 的 `LSMinimumSystemVersion`、安装器预检和本文档一致。
- 安装器不再依赖 0.2.1 开发机 `BACKUP_DIR`。回滚只使用本次写入 `install-record/pre-install-backup` 的快照，或在全新安装失败且服务已停止后删除本包哈希匹配的文件。
- 安装前检测 App、Helper、backend 和 plist 的 `com.apple.quarantine`。检测到时先完成哈希和签名校验，再询问是否只清除当前部署目录的 quarantine。未确认输出 `STOP_QUARANTINED_PACKAGE`，不复制系统文件。不修改 Gatekeeper、AMFI、spctl 或 SIP。
- 未知版本不得覆盖（`STOP_UNKNOWN_VERSION`）。卸载和失败回滚在服务未停止时绝不删除文件。
- 改过 Candidate `Info.plist` 后必须重签再安装。本说明不覆盖 0.2.1 发布目录中的原文。

`Package.swift` 的 `platforms` 仍为 macOS 14；改为 27.2 的提案交给 Orch 合并。

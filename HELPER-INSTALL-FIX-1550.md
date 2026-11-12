# Mac Restore Assistant Helper install/uninstall fix — RC 20261112.1550

Status: offline verified, ready for the Owner's macOS 26 install/uninstall test.

## Scope

Device dispatch and behavior were frozen. This build changes only Helper
management, status detection, install/uninstall scripts and their tests:

- App status now probes the Unix socket with a real connection instead of
  treating a leftover socket file as a listener.
- Healthy status requires launchd `state = running` with a live PID.
- Uninstall remains available when the installed payload is unhealthy or its
  backend needs updating.
- App, installer and uninstaller now agree on the real T1205Z and T1306Z
  helper/backend/plist triplets.
- The uninstaller removes a stale socket file and fails verification if any
  socket file remains.
- Source `Resources/mra-helper` and `Resources/direct_rid_dfu` were aligned to
  the current c81917fd/ea512931 payloads.
- The existing minos fallback remains: installation no longer requires `vtool`.

## Offline verification

- Full Swift suite: 200 tests, 1 skipped, 0 failures, exit 0.
- Installer/script acceptance: 13/13 tests passed.
- Current payload dry-run: `MINOS_CONSISTENT=YES`, `DRY_RUN_OK`.
- `VTOOL_BIN=/usr/bin/false` dry-run: `MINOS_CONSISTENT=YES`, `DRY_RUN_OK`.
- T1205Z upgrade and uninstall dry-runs: accepted as a known legacy triplet.
- T1306Z upgrade and uninstall dry-runs: accepted as a known legacy triplet.
- Live service/process/socket uninstall guards still abort without deleting.
- Stale socket uninstall test reports `STALE_SOCKET_REMOVED`, removes the socket,
  helper, backend and plist, and reports `UNINSTALL_OK`.

No live install, uninstall, service replacement or device command was performed
while producing this build.

## Known boundary

The embedded backend remains ad-hoc/linker-signed. Its bytes and behavior were
not changed because the current verified device path depends on that payload.
The Helper is Apple Development signed and remains in Team `6NFD357KL3`.

# Mac Restore Assistant 1.0.8-rc

Release date: 2026-11-21

This is a source-first release candidate. It is not notarized by Apple.

## Highlights

### Apple Native Precision Tool V2

- Unified dark workbench across Device, Firmware & Restore, and RLM pages.
- Real S3/S4/S5 physical-port rail with three top status pills.
- 920×680 and 1000×720 layouts checked in light and dark appearance; no
  horizontal overflow in the checked states.

### Dual-device Restore workbench

- Two devices can prepare and restore independently; firmware, stage, progress,
  and logs are per device.
- Every overview row exposes “View Task” and the whole row switches the viewed
  task without changing the left physical control target.
- Follow-left mode resolves the currently selected physical port even while the
  other port is restoring.
- Symmetric 3-second force-stop and cancel-then-restart behavior remain owned by
  the existing restore control chain.

### Firmware identity and compatibility

- Real DFU `CPID`/`BDID` parsing; ECID and board identity are shown from live
  device data.
- Strict `BuildManifest.plist` compatibility: ProductType, board, and chip
  evidence must agree. A firmware that does not list the target model is
  displayed as incompatible rather than guessed compatible.
- Repair code (for example `A2681`) is shown beside the model line; the five
  identity columns keep a common baseline.

### Firmware discovery

- Spotlight-assisted discovery plus a per-user-directory DispatchSource watcher.
- 1.5-second debounce on a utility queue; no polling loop.
- Missing ordinary entries are pruned only after a complete scan; a partial
  scan preserves the index.
- New `.ipsw` files are indexed incrementally; restore-active discovery is
  deferred so it does not compete with restore I/O.

### Progress and history

- Parses real Chinese and English cfgutil progress lines such as
  `第 2/2 步：正在安装系统 [2/2] 37%` and
  `Step 2 of 2: Installing system [2/2] 37%`.
- Real 0% is retained; a gentle hint explains that firmware extraction and
  verification can take several minutes before the first progress update.
- “Last success” duration reference is read-only and matched by:
  1. same ECID + same firmware version/build;
  2. same ProductType + same firmware version/build;
  3. same model's most recent success, with firmware version shown.
- No historical duration is converted into a synthetic percentage.

### RLM logs and error clues

- Independent RLM raw capture, bounded UI preview, and rule-based error clues.
- No AI diagnosis and no network upload.
- Raw stdout/stderr remains the evidence source; the UI does not claim to be a
  complete raw-log viewer.

## Verification

- Offline Swift suite: **850 executed / 2 skipped / 0 failures**.
- P1 restore guard: **20/20**.
- Acceptance: **36/36**.
- Python checks: **7/7**.
- Four-language L10n: **pass**.
- One M2 real-device restore has been completed. Cross-model and dual-device
  concurrent hardware validation is still in progress.
- The local build is **not notarized**; build and sign from source with your own
  identity.

## Known boundaries

- No built-in AI diagnosis.
- No online/ECID gate for entering DFU.
- Software tests do not prove hardware behavior.
- Network/removable-volume folder events may delay discovery; files are never
  deleted by the watcher.
- A stale P1 lease file can remain after an app process exits; it is recorded as
  an operational residual and was not manually removed in this release.

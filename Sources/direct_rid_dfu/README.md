# direct_rid_dfu

RID-selective Direct Host helper for Mac Restore Assistant 1.6.6 D5.

Derived from public [AsahiLinux/macvdmtool](https://github.com/AsahiLinux/macvdmtool) (Apache-2.0). `LICENSE` is that upstream license. Copyright remains with osy86 (2019) and the Asahi Linux Contributors (2021). Upstream `main` does not select an arbitrary RID. DoDFU / DoVDM sequences in this file are the upstream ones. This tree does not add VDM payloads.

The helper does not know product sendable sets, host models, or physical slot names. Those stay in the app.

## Commands

```
direct_rid_dfu probe --controller ID --port-number N --rid N
direct_rid_dfu dfu --controller ID --port-number N --rid N
direct_rid_dfu reboot --controller ID --port-number N --rid N
```

Missing or invalid `--controller`, `--port-number`, or `--rid` exits non-zero (`TRIPLET_REQUIRED`). There is no silent RID 0 and no first-item fallback.

`probe` enumerates `AppleHPM`, keeps services whose `RID` equals N and that have a BuiltIn `Port-USB-C` child, and stops. It does not open the plugin and does not send VDM. `candidate_service_count` is the count after that filter, not the raw AppleHPM node count.

`READY` requires `rid_selective`, `requested_rid == selected_rid`, `candidate_service_count == 1`, BuiltIn, Port-USB-C, and `send_performed=false`.

`dfu` runs only when that count is 1. It opens that one service, calls the existing DoDFU / DoVDM path, and releases the plugin. `REQUEST_SUBMITTED` is not DFU success. Any other count exits without sending and without trying another RID.

Stdout includes one JSON object:

```
{"rid_selective":true,"requested_rid":N,"candidate_service_count":1,"selected_rid":N,"built_in":true,"port_usb_c":true,"send_performed":false,"status":"READY","reason":"","dfu_success":false}
```

## Build

On a Mac with Xcode command-line tools, from this directory:

```
make
```

The product is `./direct_rid_dfu`. Linux CI does not link this binary. A missing binary is `BACKEND_NOT_RID_SELECTIVE`. Do not rename the helper to `dfu_tool` and do not fall back to `dfu_tool dfu`.

Owner Layer B PASS opens Direct Per-Port for host scope `macbookpro18,2-t147u` only, and only as `direct_rid_dfu probe|dfu --controller ID --port-number N --rid N`. That is not full hardware validation. D11 and D12 stay pending.

## Desktop pack

Versioned kit notes: `scripts/macos/MACBUILDKIT`. Official Mac entry:

```
scripts/macos/BUILD_ON_MAC
```

That runs `scripts/macos/build_dfu_beta.sh` (PyInstaller) after `make` in this directory. `scripts/macos/py2app_setup.py` is the py2app entry and does the same install. The Desktop bundle name is `MAC刷机助手 <APP_VERSION>.app`. Both copy the Mach-O to:

- `Contents/MacOS/direct_rid_dfu`
- `Contents/Resources/direct_rid_dfu`

Those are the paths `preferred_rid_backend` checks beside `sys.executable`. Exact pack notes: `docs/PACK_1.6.8-alpha3.md`. The pack fails if either copy is missing after the versioned rename. It does not rename `dfu_tool` or fall back to `dfu_tool dfu`. `HOT_INJECT_IS_NOT_THE_RELEASE_PATH`. The `.app` is an INTERNAL BUILD until `python3 scripts/release_gate.py --app <that.app>` passes. After the pack, stop for the gate status report. Linux prints `MUST_RUN_ON_MAC` and does not claim PASS.

`reboot --controller ID --port-number N --rid N` uses the same single-candidate triplet gate as `dfu` and reports
`REBOOT_REQUESTED`, which is a receipt, not proof the target rebooted. The
product does not enable it: `EXACT_BACKENDS['REBOOT']` stays empty until a
hardware batch proves it, and the helper refuses a REBOOT payload without a RID
(`TARGET_NOT_PRECISE`).

Enter DFU uses the existing administrator prompt and runs `direct_rid_dfu dfu --controller ID --port-number N --rid N`. The process exits and its destructor releases AppleHPM. `REQUEST_SUBMITTED` is not DFU success. This helper does not write SQLite. Linux does not link the Mach-O.

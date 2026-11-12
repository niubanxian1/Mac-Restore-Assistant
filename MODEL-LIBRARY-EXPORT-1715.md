# Model library and live Helper state — RC 20261112.1715

## Fixed

- Successful Helper refresh clears the stale red “Helper unavailable” feedback
  immediately. No port click or App restart is required.
- Added M4 Pro 14-inch A3401 (`Mac16,8`) with L1/L2/R1 port bindings.
- Added model-library selection and “Export Selected Model Pack…”.
- Export produces the existing import-compatible `report.json` ZIP format.
- The app now distinguishes exact calibration from reusable shared layouts.

## Shared interface families

- MacBook Air M2–M5.
- 16-inch MacBook Pro M1 Pro–M5 Max.
- 14-inch MacBook Pro M1 Pro–M5 Max.
- M4/M5 base and Pro/Max reuse the M4 Pro A3401 three-port layout.
- M6 base `Mac18,1` and the 2026 M5 PROLED XDR identifiers are registered in the
  three-port 14/16-inch families.
- Base M3 `Mac15,3` remains separate as a two-left-port model.

Shared layouts are explicitly “reusable but not precisely calibrated”. They use
the orange lamp and show a calibration action. Green is reserved for a direct
exact record or a completed in-App slot calibration.

## Verification

- Full suite: 208 passed, 1 skipped, 0 failed.
- A3401 record and export/import round-trip passed.
- Air, 16-inch, 14-inch Pro/Max and M4/M5/M6 three-port family tests passed.
- M3-base two-port separation test passed.
- Completed calibration lights green.
- Helper recovery clears stale warning feedback.

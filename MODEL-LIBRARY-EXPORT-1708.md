# Model library, export and calibration lamp — RC 20261112.1708

## Fixed

- Successful Helper refresh clears the stale red “Helper unavailable” feedback
  immediately instead of waiting for an unrelated click.
- Added A3401 as built-in `Mac16,8` with L1/L2/R1 = PortNumber 1/2/3 and
  RID 0/1/2.
- Added a model-library selector and “Export Selected Model Pack…” action.
- Exported ZIP uses the existing import format: `report.json` and `README.txt`.
  Export -> import round-trip preserves host model, slots and bindings.
- Confirmed shared layout families:
  - MacBook Air M2 through M5.
  - 16-inch MacBook Pro M1 Pro through M5 Max.
  - 14-inch M1 Pro through M5 Max three-port family.
  - M4/M5 base and Pro/Max three-port family reusing M4 Pro A3401 data.
  - Base M3 14-inch remains separate as a two-left-port model.
- Reusable shared layouts show “not precisely calibrated” and an orange lamp.
  Only a direct exact record or completed in-App slot calibration turns green.
- A known model with no reusable layout shows “No Model” and offers calibration.

## Verification

- A3401 built-in record test passed.
- Export/import round-trip test passed.
- Air, 16-inch, 14-inch Pro/Max, M4 base/M4 Pro and M3-base family tests passed.
- Completed in-App calibration produces the green calibration lamp.
- Helper recovery clears stale unavailable feedback.
- Full Swift suite: 208 passed, 1 skipped, 0 failed, exit 0.

No real device command was performed while producing this build.

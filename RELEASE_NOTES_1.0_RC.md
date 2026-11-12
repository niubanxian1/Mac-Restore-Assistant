# Mac Restore Assistant 1.0 RC

This is the first public 1.0 release candidate for the Swift macOS application.

## Highlights

- Per-port DFU, normal restart, and Recovery workflows.
- Installation and uninstallation management for the privileged Helper.
- Passive, read-only target observation with ECID-aware identity handling.
- Current desktop and notebook model recognition, including Mac mini,
  Mac Studio, Mac Pro, and iMac families.
- Calibrated port layouts with explicit distinction between exact calibration,
  reusable shared layouts, and uncalibrated hosts.
- Model-library import/export.
- Chinese Simplified, Chinese Traditional, English, Japanese, and Korean UI.
- Read-only port refresh every 3 seconds; disconnect state clears before the
  next USB scan and cannot interfere with an in-flight action.

## Package

- Build: `20261112.1855`
- App ZIP SHA-256:
  `ba503cba361e4eec6ae5f67fbf5ee5af111e93f958052c228b04329716c088a0`

## Signing

The attached application is an Apple Development build. It is not Developer ID
signed and not notarized. macOS requires manual first-launch approval in
System Settings.

## Verification

- 277 automated tests passed.
- Release build completed successfully.
- ZIP extraction and deep code-signing verification passed.

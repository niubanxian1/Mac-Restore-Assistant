# Mac Restore Assistant 1.0 RC — Gatekeeper launch responsiveness fix

Build: `20261112.1830`

## Root cause

Build 1815 kept a quarantined first launch as an accessory process and hid its
windows. The process main thread was healthy, but LaunchServices treated the
first launch as not completed because the regular Dock App never finished a
normal presentation/check-in. A second manual open then produced repeated
"Not Responding" reports while the first hidden instance was still alive.

## Fix

- Removed `LSUIElement` and the accessory-process first-launch state.
- The App always starts as a regular responsive Dock App.
- While SecurityAgent is visible, only the App window is ordered behind the
  system password dialog.
- The App remains alive, responsive and registered with LaunchServices.
- After the authorization UI closes, the existing window is restored and
  activated through Launch Services.
- The first-launch guard is still one-time per build.

## Verification

- Live authorization regression:
  - App activation policy remained `Regular` while authorization was visible.
  - SecurityAgent remained frontmost.
  - App remained responsive and did not use a hidden/accessory process.
  - App automatically returned to the foreground after authorization closed.
- Full Swift suite: 276 tests passed, 1 existing test skipped, 0 failed.
- Release build and deep code-signing verification passed.
- No device, Helper, DFU, Reboot, Recovery, or Restore operation was performed.

## Remaining Gatekeeper limitation

The package still uses Apple Development signing and is not notarized. The
first `Open Anyway` confirmation remains required. Developer ID signing,
notarization, and stapling are required to remove that confirmation entirely.

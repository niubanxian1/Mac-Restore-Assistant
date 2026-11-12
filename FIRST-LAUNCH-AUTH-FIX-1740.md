# Mac Restore Assistant 1.0 RC — first-launch authorization focus fix

Build: `20261112.1740`

## Root cause

On a quarantined first launch, Launch Services starts the App while
SecurityAgent is presenting the "Open Anyway" administrator password dialog.
A regular App launch can add a bouncing Dock tile and put App windows above that
system dialog before the App's own initialization finishes.

## Fix

- The App bundle now declares `LSUIElement` so a quarantined first launch starts
  without a Dock tile or App window.
- On launch, the App checks its own `com.apple.quarantine` attribute.
- A quarantined, not-yet-handled first launch stays as an accessory process and
  keeps its windows hidden.
- It watches the visible windows owned by `SecurityAgent` and the Touch ID UI
  agent. The latter process can remain resident after its window closes, so
  process presence alone is not treated as an active authorization prompt.
- After the authorization UI closes, the App switches back to a regular App and
  uses Launch Services to restore and activate itself.
- Normal and subsequent launches switch to the regular App mode immediately.
- This guard runs once per build version; later launches take the ordinary path.

## Verification

- Full Swift suite: 270 tests passed, 1 existing test skipped, 0 failed.
- Release build completed successfully.
- Live authorization regression:
  - SecurityAgent remained the frontmost process while authorization was active.
  - The App remained hidden with no competing window.
  - After the authorization UI was cancelled, the App automatically returned to
    the foreground.
- Deep code-signing verification passed after packaging.
- No Helper installation, Helper uninstallation, device command, DFU, Reboot,
  Recovery, or Restore operation was performed.

## Signing limitation

The package still uses the available Apple Development identity. macOS will
still require the first manual "Open Anyway" approval because the package is not
notarized. This fix specifically prevents the App's Dock animation and windows
from covering the password dialog after that approval is started. Eliminating
the approval itself still requires Developer ID signing, notarization, and
stapling.

## Unchanged

- DFU sending sequence and timing.
- Reboot / Recovery five-restart policy.
- Restore engine.
- Device identification and port selection.
- Five-language localization.
- Helper installation and uninstallation rules.

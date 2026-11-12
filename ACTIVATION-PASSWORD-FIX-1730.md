# Mac Restore Assistant 1.0 RC — first-launch focus fix

Build: `20261112.1730`

## Fixed

- Removed the App-initiated `activate(ignoringOtherApps: true)` call.
- macOS Launch Services now decides when the App becomes active for a normal
  user launch.
- The App no longer forces itself in front of the Privacy & Security password
  prompt while Gatekeeper is handling an unnotarized build.

## Verified

- Full Swift suite: 265 passed across the test bundles, 1 skipped, 0 failed.
- Release build completed successfully.
- A packaged-App background launch left Codex as the frontmost application.
- Deep code-signing verification passed after ZIP extraction.
- Missing Helper parent directories and existing Helper lifecycle handling remain
  covered by the passing installer acceptance tests.
- No Helper installation, Helper uninstallation, device command, DFU,
  Reboot, Recovery, or Restore operation was performed while producing this
  build.

## Signing limitation

The App uses the available Apple Development identity. Without a Developer ID
Application identity and notarization, macOS Gatekeeper will still require the
first manual approval on another Mac, and its Dock launch animation may still be
visible during that system check. This build prevents the App from taking focus
away from the password dialog. Fully removing the first-launch approval and
Dock animation requires Developer ID signing, notarization, and stapling.

## Artifacts

- App ZIP SHA-256:
  `767c5eea18dbcb070e4b907457456ddeaeba2dacb4a6de4258f67d42331690c5`
- Source ZIP SHA-256:
  `e4b21187702fe5effaadd1076845da0c2cb24efe43ee717a0e09a5b09dd05637`
- App CDHash:
  `de07b01e6321d0f3bf220356a0ad23d66f0be8bb`
- Team ID:
  `6NFD357KL3`

## Unchanged

- DFU sending sequence and timing.
- Reboot / Recovery five-restart policy.
- Restore engine.
- Device identification and port selection.
- Five-language localization.
- Existing Helper installation and uninstallation rules.

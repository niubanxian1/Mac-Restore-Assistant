# AppTranslocation quarantine fix — RC 20261112.1601

Status: offline verified, ready for the Owner's macOS 26 reinstall test.

## Confirmed failure

The macOS 26 App was running from a read-only AppTranslocation path:

```text
/private/var/folders/.../T/AppTranslocation/.../牛半仙Mac维修辅助工具 2.app
```

The installer tried `xattr -dr com.apple.quarantine` on that source App and
all of its sealed files. macOS returned `EPERM` for every path, so no Helper
install began.

## Fix

- The installer no longer modifies the running App bundle.
- Quarantine is checked only on the Helper, backend and launchd plist that will
  actually be installed.
- When quarantine is present, those three files are copied to a private
  `mktemp` staging directory.
- Hashes, code signatures and the plist are revalidated on the staged copies.
- Quarantine is cleared only on that private stage, then checked again.
- The private stage is removed on success and failure.
- The source App, including its quarantine attribute and file bytes, remains
  untouched.

## Verification

- Regression test runs the installer against a read-only protected quarantined
  App and confirms `QUARANTINE_STAGED_PAYLOAD=YES`,
  `QUARANTINE_CLEARED=YES`, `STAGED_PAYLOAD_VERIFIED=YES`.
- The test confirms `SOURCE_APP_UNCHANGED=YES` and that the original helper hash
  and quarantine remain unchanged.
- Full Swift suite exits 0; 200 passed, 1 skipped.
- InstallerScriptAcceptanceTests includes the new translocation case.

No real Helper install or uninstall was performed while producing this build.

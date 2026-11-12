# Mac Restore Assistant 1.0 RC — Mac16,8 target recognition fix

Build: `20261112.1855`

## Root cause

The connected target reported:

```text
Type: Mac16,8
Location: 0x1100000
```

At the same USB location, the booted Mac exposed:

```text
USB Product Name: Debug USB
idVendor: 1452
idProduct: 6281
```

The observer accepted only `Mac`, DFU, and Recovery descriptors, so it discarded
the target before cfgutil's correct `Mac16,8` identity could be attached.

## Fix

- Accept Apple vendor product ID `0x1881` (`Debug USB`) as a connected Mac
  observation.
- A model is still never inferred from `Debug USB` itself.
- The model name comes only from a unique matching cfgutil location, preserving
  fail-closed behavior for missing or ambiguous model evidence.
- A regression uses the exact live `locationID`, product ID, cfgutil ECID, and
  `Mac16,8` response from this connection.

## Verification

- Full Swift suite: 277 tests passed, 1 existing test skipped, 0 failed.
- Release build and deep code-signing verification passed.
- No device, Helper, DFU, Reboot, Recovery, or Restore operation was performed.

# Mac Restore Assistant 1.0 RC — desktop models and disconnect state

Build: `20261112.1815`

## Desktop Mac model recognition

The connected test Mac reported `Type: Mac16,10` from the read-only
`cfgutil list` enumeration. The existing table had the identifier, but the
normal-boot USB observation had no ECID. The resolver previously required an
ECID match, so it discarded the host/location hint and left the model unknown.

Fixed by allowing an ECID-less normal Mac to use a cfgutil hint only when there
is exactly one hint at the same location. Ambiguous locations remain unresolved.

Added friendly names and recognition for recent desktop Mac families:

- Mac mini: 2014, 2018, M1, M2, M2 Pro, M4, M4 Pro, M5 Pro, M6.
- Mac Studio: M1 Max, M1 Ultra, M2 Max, M2 Ultra, M3 Ultra, M4 Max, M5 Max,
  M5 Ultra.
- Mac Pro: 2019 and M2 Ultra 2023.
- iMac Pro and recent Intel, M1, M3, and M4 iMac identifiers, including the
  two-port and four-port variants.

## Unplug state

The host AppleHPM link was initially read only once, so a stale connected state
could remain after a cable was removed.

Fixed:

- AppleHPM link state is refreshed read-only every 3 seconds.
- Parsing runs at utility priority outside the main thread.
- A read failure preserves the previous state instead of pretending that all
  ports disappeared.
- An explicit link disconnect immediately clears the current observed device on
  that port. Historical "last seen" information may remain, but it is no longer
  presented as a current connection.
- Periodic refresh is skipped while a device action is in flight. It does not
  retarget, cancel, resend, or overwrite action progress.

## Verification

- Full Swift suite: 276 tests passed, 1 existing test skipped, 0 failed.
- The connected Mac mini case `Mac16,10` is covered by an offline regression.
- ECID-less unique-location binding and ambiguous-location fail-closed behavior
  are both covered.
- Link disconnect without waiting for the next USB scan is covered.
- Read-only refresh being skipped during an in-flight action is covered.
- No device command, Helper operation, DFU, Reboot, Recovery, or Restore was
  performed.

## Unchanged

- DFU sending sequence and timing.
- Reboot / Recovery five-restart policy.
- Restore engine.
- Existing port calibration and Helper rules.
- Five-language localization.

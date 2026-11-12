# Live Helper state synchronization fix — RC 20261112.1621

## Fixed behavior

After a successful Helper install, the environment status lamp changed to
“Helper 已连接”, but `DeviceControlModel.helperAvailable` still held its initial
false value. The device controls therefore remained disabled until an App
restart produced another Helper status query.

Changes:

- Every Helper redetection now synchronizes the device model by issuing a
  `status` request.
- The synchronization is bound in the real App as well as test/injected models.
- A completed install can immediately enable device controls without restarting
  or clicking a port.
- The stale install prompt is dismissed when the Helper state leaves
  `notInstalled`.
- The explanatory text below the Recovery button has been removed.

The five-reboot Recovery sequence and all device dispatch logic are unchanged.

## Verification

- New model test starts with Helper not installed, performs a mocked successful
  install, and verifies that the device model receives a status refresh and
  becomes available immediately.
- Full Swift suite: 201 passed, 1 skipped, 0 failed, exit 0.

No real Helper install/uninstall or device command was performed while producing
this build.

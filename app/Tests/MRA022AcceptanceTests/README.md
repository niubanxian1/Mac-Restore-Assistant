# MRA022AcceptanceTests

Official 0.2.2 acceptance layer for Owner requirements T01–T13.

- Complements, and does not edit, `Tests/DeviceCapturePrototypeTests` and `Tests/MRAHelperTests`.
- Uses injectable seams already landed by Worker B (`DeviceControlModel` testing init, `CalibrationStore(testingDocument:…)`, `applyDiscoveredPorts`) and Worker A (`MRAHelperCore`).
- Calibration JSON and installer stubs live under `Fixtures/` so these tests do not depend on `workers/D` paths.
- Installer/uninstall cases invoke the product scripts in the package root with destination overrides into an isolated scratch tree only. Destinations under `/Library` or the real `/var/run` are refused.
- These tests never construct the production `DeviceControlModel` initializer that calls `refreshHelper()` against `/var/run/com.mra.devicecontrol.helper.sock`.
- They never install, uninstall, or talk to the Owner Mac Helper, and never launch the App UI.

See `workers/ORCH/acceptance_landing/` for RED/GREEN logs and the full-suite summary.

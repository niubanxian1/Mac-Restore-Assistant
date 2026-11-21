import Combine
import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class ObservationHeartbeatBatch0Tests: XCTestCase {
    private func makeDevice() -> (DeviceControlModel, LiveHostPort) {
        let port = LiveHostPort(
            controller: "ObservationHeartbeatTestController",
            portNumber: 1,
            rid: 0,
            link: HostPortLink(
                connectionActive: true,
                connectionCount: 1,
                connectType: 4,
                connectTypePublished: 4,
                superSpeedActive: false,
                activeCable: false,
                opticalCable: false,
                powerMode: 3,
                transportsProvisioned: ["CC"],
                transportsSupported: ["CC", "USB2"]))
        let calibration = PortCalibrationEntry(
            physicalPort: "left1",
            location: "01200000",
            label: "左侧上方",
            rid: "0",
            side: "左侧",
            controller: port.controller,
            portNumber: port.portNumber)
        let store = CalibrationStore(
            testingDocument: CalibrationDocument(
                models: [],
                ports: [calibration],
                selectedPort: port.id),
            hostModel: "MacTest,1",
            builtInLayout: nil)
        let model = DeviceControlModel(
            calibration: store,
            livePorts: [port],
            helperAvailable: true,
            persistPortSelection: false,
            startLiveWork: false)
        return (model, port)
    }

    private func sampleDevice() -> ObservedDevice {
        var device = ObservedDevice(
            id: "ecid:0011223344556677",
            ecid: "0011223344556677",
            mode: .dfu,
            locationID: "01200000",
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:0011223344556677")
        device.modelIdentifier = "Mac16,8"
        device.explicitMachineIdentifierRaw = "Mac16,8"
        return device
    }

    func testStableSuccessRefreshesIndependentHeartbeatWithoutModelPublication() {
        let (model, _) = makeDevice()
        let sample = sampleDevice()
        model.applyObservationResult(.success([sample]), now: Date())

        var modelPublishes = 0
        let modelCancellable = model.objectWillChange.sink { modelPublishes += 1 }
        var snapshots: [DeviceControlModel.ObservationHeartbeatSnapshot] = []
        let heartbeatCancellable = model.observationHeartbeat.$latest.sink {
            snapshots.append($0)
        }

        model.applyObservationResult(
            .success([sample]),
            now: Date().addingTimeInterval(1))
        model.applyObservationResult(
            .success([sample]),
            now: Date().addingTimeInterval(2))

        withExtendedLifetime((modelCancellable, heartbeatCancellable)) {
            XCTAssertEqual(modelPublishes, 0)
            XCTAssertEqual(snapshots.count, 3)
            XCTAssertEqual(snapshots.map(\.observationSequence), [1, 2, 3])
            XCTAssertEqual(snapshots[1].observationResult, .successUnchanged)
            XCTAssertEqual(snapshots[2].observationResult, .successUnchanged)
            XCTAssertEqual(snapshots[2].devices, model.observedDevices)
            XCTAssertNotNil(snapshots[2].completedUptimeNs)
        }
    }

    func testExplicitObservationFailureCannotPublishSuccess() {
        let (model, _) = makeDevice()
        model.applyObservationResult(.success([sampleDevice()]), now: Date())
        let success = model.observationHeartbeat.latest

        model.applyObservationResult(.failed("read failed"), now: Date())
        let failure = model.observationHeartbeat.latest

        XCTAssertEqual(failure.observationSequence, success.observationSequence + 1)
        XCTAssertEqual(failure.observationResult, .failed(reason: "read failed"))
        XCTAssertTrue(failure.devices.isEmpty)
        XCTAssertFalse(
            failure.isFreshSuccess(
                atUptimeNs: (failure.completedUptimeNs ?? 0) + 1))
    }

    func testHeartbeatDevicesAreFromTheSameSuccessfulObservationRound() {
        let (model, port) = makeDevice()
        let sample = sampleDevice()

        model.applyObservationResult(.success([sample]), now: Date())
        let heartbeat = model.observationHeartbeat.latest

        XCTAssertEqual(heartbeat.observationResult, .successChanged)
        XCTAssertEqual(heartbeat.devices, model.observedDevices)
        XCTAssertEqual(heartbeat.devices.first?.ecid, sample.ecid)
        XCTAssertEqual(
            heartbeat.devices.first?.modelIdentifier,
            "Mac16,8")
        XCTAssertEqual(
            model.observedPortKey(for: heartbeat.devices[0]),
            port.id)
    }

    func testStoppedObservationExpiresWithoutInventingAStopReason() throws {
        let (model, _) = makeDevice()
        model.applyObservationResult(.success([sampleDevice()]), now: Date())
        let heartbeat = model.observationHeartbeat.latest
        let completed = try XCTUnwrap(heartbeat.completedUptimeNs)

        model.stopObservationForTests()

        XCTAssertEqual(model.observationHeartbeat.latest, heartbeat)
        XCTAssertTrue(
            heartbeat.isFreshSuccess(
                atUptimeNs: completed + 3_000_000_000))
        XCTAssertFalse(
            heartbeat.isFreshSuccess(
                atUptimeNs: completed + 3_000_000_001))
    }
}

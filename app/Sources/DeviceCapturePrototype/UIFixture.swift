import Foundation

@MainActor
enum UIFixture {
    static var isActive: Bool {
        let value = ProcessInfo.processInfo.environment["MRA_UI_FIXTURE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false
    }

    static var name: String {
        ProcessInfo.processInfo.environment["MRA_UI_FIXTURE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func layout() -> BuiltInLayout {
        BuiltInLayout(displayName: "M1 Pro", sourceFile: "fixture.json", slots: [
            BuiltInSlot(slot: "S3", face: "LEFT", portNumber: 1, rid: 0, binding: "MacBookPro18,2|AppleHPMDevice|1|0", physicalName: "左侧上方"),
            BuiltInSlot(slot: "S4", face: "LEFT", portNumber: 2, rid: 1, binding: "MacBookPro18,2|AppleHPMDevice|2|1", physicalName: "左侧下方"),
            BuiltInSlot(slot: "S5", face: "RIGHT", portNumber: 3, rid: 2, binding: "MacBookPro18,2|AppleHPMDevice|3|2", physicalName: "右侧"),
        ], partial: true, skippedSlots: ["S2"], generatedAt: "fixture")
    }

    static func ports() -> [LiveHostPort] {
        // Fixture-only link state so the isolated UI can show the read-only
        // "controller connected, target identity not read" case.
        let connected = HostPortLink(
            connectionActive: true,
            connectionCount: 3,
            connectType: 4,
            connectTypePublished: 4,
            superSpeedActive: false,
            activeCable: false,
            opticalCable: false,
            powerMode: 3,
            transportsProvisioned: ["CC", "USB2"],
            transportsSupported: ["CC", "USB2", "USB3", "CIO", "DisplayPort"])
        let disconnected = HostPortLink(
            connectionActive: false,
            connectionCount: 0,
            connectType: 0,
            connectTypePublished: 0,
            superSpeedActive: false,
            activeCable: false,
            opticalCable: false,
            powerMode: 0,
            transportsProvisioned: [],
            transportsSupported: [])
        return [
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 1, rid: 0, link: disconnected),
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 2, rid: 1, link: connected),
            LiveHostPort(controller: "AppleHPMDevice", portNumber: 3, rid: 2, link: disconnected),
        ]
    }

    static func makeCalibrationStore() -> CalibrationStore {
        let custom = [
            PortCalibrationEntry(physicalPort: "left1", location: "01200000", label: "左侧上方",
                                 rid: "0", side: "左侧", controller: "AppleHPMDevice", portNumber: 1),
            PortCalibrationEntry(physicalPort: "left2", location: "01100000", label: "左侧下方",
                                 rid: "1", side: "左侧", controller: "AppleHPMDevice", portNumber: 2),
            PortCalibrationEntry(physicalPort: "right1", location: "02100000", label: "右侧",
                                 rid: "2", side: "右侧", controller: "AppleHPMDevice", portNumber: 3),
        ]
        let url = AppSupportLocations.calibrationURL()
        let doc = CalibrationDocument(models: [], ports: custom, selectedPort: "AppleHPMDevice:2")
        return CalibrationStore(testingDocument: doc, hostModel: "MacBookPro18,2", builtInLayout: layout(),
                               sharedLayoutCandidates: [SharedCandidate(models: ["MacBookPro18,2", "MacBookPro18,3"], basis: "fixture same mold")],
                               fileURL: url)
    }

    static func makeDevice(store: CalibrationStore) -> DeviceControlModel {
        let history = AppSupportLocations.portHistoryURL()
        return DeviceControlModel(
            calibration: store,
            livePorts: ports(),
            helperAvailable: true,
            persistPortSelection: false,
            startLiveWork: false,
            historyURL: history)
    }

    static func lowerDFUDevice() -> ObservedDevice {
        ObservedDevice(
            id: "ecid:0011223344556677",
            ecid: "0011223344556677",
            mode: .dfu,
            locationID: "01100000",
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:0011223344556677")
    }

    static func rightDFUDevice() -> ObservedDevice {
        ObservedDevice(
            id: "ecid:00AABBCCDDEEFF00",
            ecid: "00AABBCCDDEEFF00",
            mode: .dfu,
            locationID: "02100000",
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:00AABBCCDDEEFF00")
    }

    static func seedConfiguratorCaches(home: URL) throws {
        let caches = [
            home.appendingPathComponent("Library/Caches/com.apple.configurator.ui", isDirectory: true),
            home.appendingPathComponent("Library/Containers/com.apple.configurator.ui/Data/Library/Caches", isDirectory: true),
        ]
        let appSupport = home.appendingPathComponent(
            "Library/Containers/com.apple.configurator.ui/Data/Library/Application Support", isDirectory: true)
        for url in caches + [appSupport] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try "cache".write(to: caches[0].appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
        try "prefs".write(to: appSupport.appendingPathComponent("prefs.txt"), atomically: true, encoding: .utf8)
    }

    @MainActor
    static func prepare(device: DeviceControlModel, capture: CaptureModel) async {
        guard isActive else { return }
        let ports = device.orderedDisplayPorts
        let lower = ports.first { device.label(for: $0) == "左侧下方" } ?? ports[safe: 1]
        let right = ports.first { device.label(for: $0) == "右侧" } ?? ports[safe: 2]
        if let lower { device.selectPort(lower) }

        switch name {
        case "t532-main", "switch-right-feedback":
            if let lower { device.selectPort(lower) }
            device.applyObservedDevices([rightDFUDevice()], now: Date())
            if let right { device.selectPort(right) }
        case "t534-home":
            if let lower { device.selectPort(lower) }
        case "capturing-with-device":
            if let lower { device.selectPort(lower) }
            // Baseline first so later changes can be unique; then a unique appear on 左侧下方.
            device.applyObservedDevices([], now: Date().addingTimeInterval(-8))
            device.applyObservedDevices([lowerDFUDevice()], now: Date())
            capture.start()
        case "export-ready-empty-port", "export-ready-reconnect-lower":
            if let lower { device.selectPort(lower) }
            let t0 = Date().addingTimeInterval(-20)
            device.applyObservedDevices([], now: t0)
            device.applyObservedDevices([lowerDFUDevice()], now: t0.addingTimeInterval(2))
            device.applyObservedDevices([], now: t0.addingTimeInterval(8))
            device.applyObservedDevices([
                ObservedDevice(id: "ecid:0011223344556677", ecid: "0011223344556677", mode: .recovery,
                               locationID: "01100000", product: "Apple Mobile Device (Recovery Mode)",
                               serial: "ECID:0011223344556677")
            ], now: t0.addingTimeInterval(12.8))
            device.applyObservedDevices([], now: t0.addingTimeInterval(16))
            capture.start()
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline && capture.state != .recording {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            // Let the simulated session accumulate a visible duration (t530 shot 2).
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            capture.exportBaseName = "Bench-Repair-Log"
            capture.stop()
            let stopDeadline = Date().addingTimeInterval(8)
            while Date() < stopDeadline && !capture.canSave {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            // One more status refresh so the stopped duration is visible immediately.
            try? await Task.sleep(nanoseconds: 300_000_000)
            if name == "export-ready-empty-port", let right {
                device.selectPort(right)
            } else if let lower {
                device.selectPort(lower)
            }
        default:
            break
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

import Foundation
import MRAHelperProtocol

enum UIFixtureHelperSimulation: String, Equatable {

    case notInstalled = "not_installed"
    case currentHealthy = "current_healthy"
}

struct UIFixtureRuntimePolicy: Equatable {
    let isActive: Bool
    let usesSimulatedCapture: Bool
    let helperSimulation: UIFixtureHelperSimulation?
    let applicationSupportRoot: URL?

    init(environment: [String: String]) {
        let fixtureName = environment["MRA_UI_FIXTURE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        isActive = fixtureName?.isEmpty == false
        usesSimulatedCapture =
            isActive
            || environment["MRA_CAPTURE_BACKEND"] == "simulated"

        if isActive {
            let requestedHelper = environment["MRA_HELPER_SIMULATE"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            helperSimulation =
                requestedHelper == UIFixtureHelperSimulation.notInstalled.rawValue
                ? .notInstalled
                : .currentHealthy

            let requestedRoot = environment["MRA_APPLICATION_SUPPORT_ROOT"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let requestedRoot, !requestedRoot.isEmpty {
                applicationSupportRoot = URL(
                    fileURLWithPath: requestedRoot,
                    isDirectory: true)
            } else {
                applicationSupportRoot = FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "MRA_UI_FIXTURE_\(ProcessInfo.processInfo.processIdentifier)",
                        isDirectory: true)
            }
        } else {
            helperSimulation = environment["MRA_HELPER_SIMULATE"]
                .flatMap(UIFixtureHelperSimulation.init(rawValue:))
            applicationSupportRoot = nil
        }
    }
}

@MainActor
enum UIFixture {
    /// 仅夹具诊断：写入 /tmp/mra-b-gui.log，生产路径不执行。
    @MainActor
    static func debugEvent(_ name: String, _ fields: String = "") {
        guard isActive else { return }
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(name) \(fields)\n"
        let url = URL(fileURLWithPath: "/tmp/mra-b-gui.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        }
    }
    static var isolatedRoot: URL? {
        UIFixtureRuntimePolicy(
            environment: ProcessInfo.processInfo.environment
        ).applicationSupportRoot
    }

    static var isolatedRawLogDirectory: URL? {
        isolatedRoot?.appendingPathComponent(
            "G4RawExports", isDirectory: true)
    }

    static func isPathIsolated(_ url: URL) -> Bool {
        guard let root = isolatedRoot else { return false }
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    static var isActive: Bool {
        let value = ProcessInfo.processInfo.environment["MRA_UI_FIXTURE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false
    }

    static var name: String {
        ProcessInfo.processInfo.environment["MRA_UI_FIXTURE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static var isRestoreRunning: Bool {
        name == "restore-running" || name.hasPrefix("restore-running-multi")
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
        let driver = UIFixtureActionDriver()
        let observationSource: UIFixtureObservationSource?
        if name == "dfu-auto-nav" {
            let source = UIFixtureObservationSource()
            observationSource = source
            driver.observationSource = source
        } else {
            observationSource = nil
        }
        let device = DeviceControlModel(
            calibration: store,
            livePorts: ports(),
            helperAvailable: true,
            persistPortSelection: false,
            startLiveWork: false,
            requestHandler: { action, controller, portNumber, rid, requestID in
                await driver.handle(
                    action: action,
                    controller: controller,
                    portNumber: portNumber,
                    rid: rid,
                    requestID: requestID)
            },
            historyURL: history)
        driver.device = device
        if let observationSource {
            device.observationReadHandler = {
                .success(observationSource.devices)
            }
            device.startObservationForTests(
                intervalNanoseconds: 200_000_000)
        }
        return device
    }

    /// P2-B 收尾：夹具 Restore 使用隔离租约，绝不触碰生产
    /// `/Users/Shared/MRA-Restore-Slot.lease` 或其 `.inprogress` 标记。
    /// 仅在 `MRA_UI_FIXTURE` 启用时由 App 组装层注入；生产路径仍用共享默认实例。
    static func fixtureLeaseDirectory() -> URL {
        AppSupportLocations.directory()
            .appendingPathComponent("FixtureLease", isDirectory: true)
    }

    static func makeProcessLease(
        baseDirectory: URL? = nil
    ) -> RestoreProcessLease {
        let base = baseDirectory ?? fixtureLeaseDirectory()
        try? FileManager.default.createDirectory(
            at: base, withIntermediateDirectories: true)
        return RestoreProcessLease(
            lockURL: base.appendingPathComponent("Restore-Slot.lease"))
    }

    static func makeFirmwareLibrary() -> FirmwareLibraryStore {
        FirmwareLibraryStore(metadataLoader: readFirmwareMetadata)
    }

    static func makeRestoreEngine() -> any RestoreEngineRunning {
        UIFixtureRestoreEngine()
    }

    nonisolated static func makeG4IPSW(at url: URL, build: String) throws -> URL {
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("G4IPSW-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "SupportedProductTypes": ["MacBookPro18,2"],
            "ProductVersion": "26.0.1",
            "ProductBuildVersion": build,
            "BuildIdentities": [[
                "Info": ["DeviceClass": "j314s"],
                "ApBoardID": 0x24,
                "ApChipID": 0x6001,
            ]],
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: manifest, format: .xml, options: 0)
        let manifestURL = work.appendingPathComponent("BuildManifest.plist")
        try data.write(to: manifestURL)
        try? FileManager.default.removeItem(at: url)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.arguments = ["-q", "-j", url.path, manifestURL.path]
        try proc.run()
        proc.waitUntilExit()
        try? FileManager.default.removeItem(at: work)
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "UIFixture.G4IPSW", code: Int(proc.terminationStatus))
        }
        return url
    }

    nonisolated static func readFirmwareMetadata(
        url: URL
    ) throws -> IPSWMetadataReadResult {
        let manifestDigest = String(repeating: "c", count: 64)
        let identity = try IPSWMetadataReader.fileIdentity(
            url: url,
            buildManifestSHA256: manifestDigest)
        return IPSWMetadataReadResult(
            validity: .valid,
            metadata: IPSWMetadata(
                productTypes: ["MacBookPro18,2"],
                identities: [
                    IPSWBuildIdentity(
                        deviceClass: "j314s",
                        boardID: 0x24,
                        chipID: 0x6001)
                ],
                productVersion: "26.0.1",
                productBuild: "24A348"),
            error: nil,
            fileIdentity: identity,
            buildManifestSHA256: manifestDigest,
            wholeFileSHA256: nil)
    }

    static func restoreFixtureFirmwareURL() throws -> URL {
        let directory = AppSupportLocations.directory()
            .appendingPathComponent("RestoreFixture", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(
            "MacBookPro18,2_26.0.1_24A348.ipsw")
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data("MRA restore fixture".utf8).write(
                to: url,
                options: .atomic)
        }
        return url
    }

    static func lowerDFUDevice() -> ObservedDevice {
        ObservedDevice(
            id: "ecid:00C0FFEE00000001",
            ecid: "00C0FFEE00000001",
            mode: .dfu,
            locationID: "01100000",
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:00C0FFEE00000001")
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

    static func rightRecoveryDevice() -> ObservedDevice {
        ObservedDevice(
            id: "ecid:00AABBCCDDEEFF00",
            ecid: "00AABBCCDDEEFF00",
            mode: .recovery,
            locationID: "02100000",
            product: "Apple Mobile Device (Recovery Mode)",
            serial: "ECID:00AABBCCDDEEFF00")
    }

    /// P2-B 夹具：第二台不同端口、不同 ECID 的 DFU 设备（左侧上方）。
    static func multiDFUDeviceB(
        generation: UInt64 = 0
    ) -> ObservedDevice {
        ObservedDevice(
            id: "ecid:00C0FFEE00000002",
            ecid: "00C0FFEE00000002",
            mode: .dfu,
            locationID: "01200000",
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:00C0FFEE00000002",
            modelIdentifier: "MacBookPro18,2",
            modelSource: "UI restore fixture",
            chipID: 0x6001,
            boardID: 0x24,
            hardwareCode: "j314s",
            connectionGeneration: generation,
            productType: "MacBookPro18,2")
    }

    static func g4ReplacementDFUDevice() -> ObservedDevice {
        ObservedDevice(
            id: "ecid:00C0FFEE00000003",
            ecid: "00C0FFEE00000003",
            mode: .dfu,
            locationID: "01100000",
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:00C0FFEE00000003",
            modelIdentifier: "MacBookPro18,2",
            modelSource: "G4 replacement fixture",
            chipID: 0x6001,
            boardID: 0x24,
            hardwareCode: "j314s",
            productType: "MacBookPro18,2")
    }

    static func g4RightDFUDevice() -> ObservedDevice {
        ObservedDevice(
            id: "ecid:00C0FFEE00000004",
            ecid: "00C0FFEE00000004",
            mode: .dfu,
            locationID: "02100000",
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:00C0FFEE00000004",
            modelIdentifier: "MacBookPro18,2",
            modelSource: "G4 dual fixture",
            chipID: 0x6001,
            boardID: 0x24,
            hardwareCode: "j314s",
            productType: "MacBookPro18,2")
    }

    /// P2-B 夹具：同一台 B 重新枚举（同 ECID、连接代际变化）。
    static func multiDFUDeviceBReplug() -> ObservedDevice {
        ObservedDevice(
            id: "ecid:00C0FFEE00000002",
            ecid: "00C0FFEE00000002",
            mode: .dfu,
            locationID: "01200000",
            product: "Apple Mobile Device (DFU Mode) · re-enumerated",
            serial: "ECID:00C0FFEE00000002-REPLUG",
            modelIdentifier: "MacBookPro18,2",
            modelSource: "UI restore fixture",
            chipID: 0x6001,
            boardID: 0x24,
            hardwareCode: "j314s",
            productType: "MacBookPro18,2")
    }

    /// P2-B 夹具：B 拔出后接入同一物理端口的另一台设备。
    static func multiDFUDeviceC() -> ObservedDevice {
        ObservedDevice(
            id: "ecid:00C0FFEE00000005",
            ecid: "00C0FFEE00000005",
            mode: .dfu,
            locationID: "01200000",
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:00C0FFEE00000005",
            modelIdentifier: "MacBookPro18,2",
            modelSource: "UI restore fixture",
            chipID: 0x6001,
            boardID: 0x24,
            hardwareCode: "j314s",
            productType: "MacBookPro18,2")
    }

    /// P2-B 夹具：用于验证长固件名的独立草稿文件。
    static func multiDraftFixtureFirmwareURL() throws -> URL {
        let directory = AppSupportLocations.directory()
            .appendingPathComponent("RestoreFixture", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(
            "MacBookPro18,2_26.0.1_24A348_LONG_FIRMWARE_NAME_FOR_LAYOUT_CHECK.ipsw")
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data("MRA restore fixture".utf8).write(
                to: url, options: .atomic)
        }
        return url
    }

    static func restoreFixtureDevice() -> ObservedDevice {
        ObservedDevice(
            id: "ecid:00C0FFEE00000001",
            ecid: "00C0FFEE00000001",
            mode: .dfu,
            locationID: "01100000",
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:00C0FFEE00000001",
            modelIdentifier: "MacBookPro18,2",
            modelSource: "UI restore fixture",
            chipID: 0x6001,
            boardID: 0x24,
            hardwareCode: "j314s",
            productType: "MacBookPro18,2")
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
    static func prepare(
        device: DeviceControlModel,
        capture: CaptureModel,
        restore: RestoreWorkspaceModel
    ) async {
        guard isActive else { return }
        let ports = device.orderedDisplayPorts
        let lower = ports.first { device.label(for: $0) == "左侧下方" } ?? ports[safe: 1]
        let right = ports.first { device.label(for: $0) == "右侧" } ?? ports[safe: 2]
        if let lower { device.selectPort(lower) }

        switch name {
        case "dual-dfu-zero-task":
            if let lower { device.selectPort(lower) }
            device.applyObservationResult(
                .success([restoreFixtureDevice(), g4RightDFUDevice()]),
                now: Date())
            Task { @MainActor in
                var left = restoreFixtureDevice()
                let control = URL(fileURLWithPath: "/tmp/MRA_G4_DEVICE_CONTROL")
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if let mode = try? String(contentsOf: control, encoding: .utf8)
                        .trimmingCharacters(in: .whitespacesAndNewlines) {
                        try? FileManager.default.removeItem(at: control)
                        if mode == "reenum" {
                            device.applyObservationResult(.success([]), now: Date())
                            try? await Task.sleep(nanoseconds: 300_000_000)
                        } else if mode == "replace" {
                            left = g4ReplacementDFUDevice()
                        }
                    }
                    device.applyObservationResult(
                        .success([left, g4RightDFUDevice()]),
                        now: Date())
                }
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
            restore.refreshTargets()
            let g4dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("MRA_G4_DUAL_FIRMWARE", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: g4dir, withIntermediateDirectories: true)
            _ = try? makeG4IPSW(
                at: g4dir.appendingPathComponent("G4_A_82003597_MacBookPro18,2.ipsw"),
                build: "24A348")
            _ = try? makeG4IPSW(
                at: g4dir.appendingPathComponent("G4_B_82003597_MacBookPro18,2.ipsw"),
                build: "24A349")
            await restore.scanFirmwareDirectory(g4dir)

        case "restore-running":
            if let lower { device.selectPort(lower) }
            device.applyObservationResult(
                .success([restoreFixtureDevice()]),
                now: Date())
            try? await Task.sleep(nanoseconds: 80_000_000)
            restore.refreshTargets()
            if let target = restore.availableTargets.first {
                restore.selectTarget(id: target.id)
                if let firmware = try? restoreFixtureFirmwareURL() {
                    await restore.loadFirmware(url: firmware)
                    Task { @MainActor in
                        if let id = restore.selectedTarget?.id,
                           restore.freezeRestoreConfirmation(targetID: id) {
                            _ = await restore.beginUnifiedRestoreAfterConfirmation(targetID: id)
                        }
                    }
                    let deadline = Date().addingTimeInterval(3)
                    while Date() < deadline && !restore.isRestoring {
                        try? await Task.sleep(
                            nanoseconds: 50_000_000)
                    }
                }
            }
        case "restore-running-multi", "restore-running-multi-raw", "restore-running-multi-nodraft", "restore-running-multi-swap", "restore-running-multi-replug":
            if name == "restore-running-multi-raw" {
                restore.setRawSaveRequestedThisRun(true)
            }
            if let lower { device.selectPort(lower) }
            device.applyObservationResult(
                .success([restoreFixtureDevice(), multiDFUDeviceB()]),
                now: Date())
            if name == "restore-running-multi" || name == "restore-running-multi-raw" || name == "restore-running-multi-nodraft" {
                // 夹具：持续刷新观察快照，模拟真实 App 每秒心跳，
                // 否则 A 运行数秒后 B 的启动前新鲜度门禁会正确拒绝。
                Task { @MainActor in
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        device.applyObservationResult(
                            .success([
                                restoreFixtureDevice(),
                                multiDFUDeviceB(),
                            ]),
                            now: Date())
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
            restore.refreshTargets()
            if let a = restore.availableTargets.first(where: {
                $0.canonicalHex.uppercased().hasSuffix("00C0FFEE00000001")
            }) {
                restore.selectTarget(id: a.id)
                if let firmware = try? restoreFixtureFirmwareURL() {
                    await restore.loadFirmware(url: firmware)
                    Task { @MainActor in
                        if let id = restore.selectedTarget?.id,
                           restore.freezeRestoreConfirmation(targetID: id) {
                            _ = await restore.beginUnifiedRestoreAfterConfirmation(targetID: id)
                        }
                    }
                    let deadline = Date().addingTimeInterval(3)
                    while Date() < deadline && !restore.isRestoring {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                    }
                }
            }
            // 为另一台设备准备独立草稿（虚拟 IPSW，不执行 cfgutil）。
            if name != "restore-running-multi-nodraft",
               let b = restore.availableTargets.first(where: {
                $0.canonicalHex.uppercased().hasSuffix("00C0FFEE00000002")
            }),
               let draftFirmware = try? multiDraftFixtureFirmwareURL() {
                _ = await restore.prepareFirmwareDraft(
                    for: b, url: draftFirmware)
            }
            if name == "restore-running-multi-swap" {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 14_000_000_000)
                    device.applyObservationResult(
                        .success([restoreFixtureDevice(), multiDFUDeviceC()]),
                        now: Date())
                    restore.refreshTargets()
                }
            }
            if name == "restore-running-multi-replug" {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 12_000_000_000)
                    device.applyObservationResult(
                        .success([
                            restoreFixtureDevice(),
                            multiDFUDeviceBReplug(),
                        ]),
                        now: Date())
                    restore.refreshTargets()
                }
            }
        case "t532-main", "switch-right-feedback":
            if let lower { device.selectPort(lower) }
            device.applyObservedDevices([rightDFUDevice()], now: Date())
            if let right { device.selectPort(right) }
        case "model-candidate":
            if let lower { device.selectPort(lower) }
            device.applyObservedDevices([
                ObservedDevice(
                    id: "ecid:00C0FFEE00000001",
                    ecid: "00C0FFEE00000001",
                    mode: .dfu,
                    locationID: "01100000",
                    product: "Apple Mobile Device (DFU Mode)",
                    serial: "ECID:00C0FFEE00000001",
                    modelIdentifier: "Mac16,8",
                    modelSource: FixedModelCatalog.sourceLabel,
                    modelIsCandidate: true,
                    chipID: 0x6040,
                    boardID: 0x04,
                    hardwareCode: "j614sap")
            ], now: Date())
        case "logging-active":
            capture.state = .recording
            capture.byteCount = 2_480_512
            capture.lineCount = 12_406
            capture.elapsedSeconds = 18
            capture.durationText = CaptureDisplayFormat.duration(seconds: 18)
            capture.previewTruncated = true
            capture.previewLines = [
                "15:06:10.108 Df DeviceService restore session started",
                "15:06:10.442 I  AMPDevices RestoreDevice identified",
                "15:06:11.003 D  MobileDevice connection established",
                "15:06:12.119 I  DeviceService ACURestoreFirmwareCommand",
                "15:06:13.208 D  AMAuthInstall personalization request",
                "15:06:14.884 D  MobileDevice transfer started",
                "15:06:15.001 D  MobileDevice transfer progress 42%",
                "15:06:16.375 D  MobileDevice transfer progress 78%",
                "15:06:17.010 D  MobileDevice transfer progress 100%",
                "15:06:17.882 I  DeviceService restore complete"
            ]
        case "logging-export":
            if let lower { device.selectPort(lower) }
            capture.state = .savedPartial
            capture.byteCount = 1_073_741_824
            capture.lineCount = 8_124_553
            capture.elapsedSeconds = 431
            capture.durationText = CaptureDisplayFormat.duration(seconds: 431)
            capture.previewTruncated = true
            capture.previewLines = [
                "15:06:10.108 Df DeviceService restore session started",
                "15:06:12.119 I  DeviceService ACURestoreFirmwareCommand",
                "15:06:15.001 D  MobileDevice transfer progress 42%",
                "15:06:17.010 D  MobileDevice transfer progress 100%",
                "15:06:17.882 I  DeviceService restore complete"
            ]
            let exportState = ProcessInfo.processInfo.environment["MRA_UI_EXPORT_STATE"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "zip"
            switch exportState {
            case "raw":
                capture.isExporting = true
                capture.isRawExporting = true
                capture.exportProgress = LogExportProgress(
                    operation: .rawLog,
                    stage: .copyingRaw,
                    processedBytes: 734_003_200,
                    totalBytes: 1_073_741_824,
                    elapsedSeconds: 1.24,
                    bytesPerSecond: 592_000_000,
                    isIndeterminate: false)
                capture.exportProgressText = "复制原始日志"
            case "cancelled":
                capture.exportProgress = LogExportProgress(
                    operation: .evidencePackage,
                    stage: .cancelled,
                    processedBytes: nil,
                    totalBytes: nil,
                    elapsedSeconds: 2.4,
                    bytesPerSecond: nil,
                    isIndeterminate: true,
                    message: "导出已取消；原始日志保留。")
                capture.exportProgressText = "已取消"
                capture.saveMessage = "导出已取消；原始日志保留。"
            case "failed":
                capture.exportProgress = LogExportProgress(
                    operation: .evidencePackage,
                    stage: .failed,
                    processedBytes: nil,
                    totalBytes: nil,
                    elapsedSeconds: 2.4,
                    bytesPerSecond: nil,
                    isIndeterminate: true,
                    message: "磁盘空间不足；原始日志保留，可重试。")
                capture.exportProgressText = "失败"
                capture.saveMessage = "导出失败：磁盘空间不足；原始日志保留，可重试。"
            case "complete":
                capture.exportProgress = LogExportProgress(
                    operation: .evidencePackage,
                    stage: .complete,
                    processedBytes: 1_073_741_824,
                    totalBytes: 1_073_741_824,
                    elapsedSeconds: 1.84,
                    bytesPerSecond: nil,
                    isIndeterminate: false,
                    message: "证据包已生成并校验。")
                capture.exportProgressText = "完成"
                capture.saveMessage = "证据包已生成并校验。"
            default:
                capture.isExporting = true
                capture.isPackageExporting = true
                capture.exportProgress = LogExportProgress(
                    operation: .evidencePackage,
                    stage: .packagingZIP,
                    processedBytes: 734_003_200,
                    totalBytes: 1_073_741_824,
                    elapsedSeconds: 1.24,
                    bytesPerSecond: 592_000_000,
                    isIndeterminate: false)
                capture.exportProgressText = "封装 ZIP"
            }
        case "t534-home":
            if let lower { device.selectPort(lower) }
        case "dfu-auto-nav":
            if let lower { device.selectPort(lower) }
        case "multi-device":
            if let lower { device.selectPort(lower) }
            device.applyObservedDevices(
                [lowerDFUDevice(), rightRecoveryDevice()],
                now: Date())
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
                ObservedDevice(id: "ecid:00C0FFEE00000001", ecid: "00C0FFEE00000001", mode: .recovery,
                               locationID: "01100000", product: "Apple Mobile Device (Recovery Mode)",
                               serial: "ECID:00C0FFEE00000001")
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

@MainActor
private final class UIFixtureRestoreEngine: RestoreEngineRunning {
    private(set) var isRunning = false
    private(set) var cancellationGraceExpired = false
    private var continuation:
        CheckedContinuation<CfgutilRestoreRunResult, Never>?
    private var activeRequest: CfgutilRestoreRequest?

    func run(
        request: CfgutilRestoreRequest,
        launchPermitted: @escaping @MainActor () -> Bool,
        onUpdate: (@MainActor (RestoreOutputSnapshot) -> Void)?
    ) async -> CfgutilRestoreRunResult {
        UIFixture.debugEvent(
            "B_ENGINE_RUN_ENTER",
            "engine=\(ObjectIdentifier(self)) task=\(request.taskID.uuidString.prefix(8))")
        activeRequest = request
        guard launchPermitted() else {
            UIFixture.debugEvent(
                "B_ENGINE_RUN_EXIT", "engine=\(ObjectIdentifier(self)) early=canceled")
            return result(outcome: .canceled)
        }

        let preparationDelayMs =
            ProcessInfo.processInfo.environment[
                "MRA_UI_RESTORE_PREP_DELAY_MS"]
            .flatMap(Int.init)
            ?? 0
        if preparationDelayMs > 0 {
            let boundedDelayMs = min(preparationDelayMs, 15_000)
            try? await Task.sleep(
                nanoseconds: UInt64(boundedDelayMs) * 1_000_000)
        }
        guard launchPermitted() else {
            return result(outcome: .canceled)
        }

        isRunning = true
        if let directory = request.outputDirectory {
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let tag = String(format: "%016llX", request.targetECID)
                .lowercased().hasSuffix("402f") ? "G4_B" : "G4_A"
            let marker = "\(tag)_STDOUT task=\(request.taskID.uuidString)\n"
            try? marker.write(
                to: directory.appendingPathComponent("stdout.raw"),
                atomically: true, encoding: .utf8)
            try? "\(tag)_STDERR task=\(request.taskID.uuidString)\n".write(
                to: directory.appendingPathComponent("stderr.raw"),
                atomically: true, encoding: .utf8)
        }
        let launched = RestoreLifecycleClock.now()
        let activity = RestoreLifecycleClock.now()
        var snapshot = RestoreOutputSnapshot()
        snapshot.stepText = "RestoreOS · 正在准备恢复分区"
        snapshot.stageFraction = 0.42
        snapshot.restoreActivityObserved = true
        snapshot.lastOutputAt = activity.wallTime
        snapshot.processLaunched = launched
        snapshot.firstRestoreActivityTime = activity
        snapshot.outputTail = [
            "cfgutil 2.21 · started owned restore process",
            "Target ECID: \(request.targetECID)",
            "Reading BuildManifest and restoring firmware image…",
            "Step=Progress restoreActivity=RestoreOS",
            "Operation 13 progress 42%",
        ]
        onUpdate?(snapshot)

        let isB = String(format: "%016llX", request.targetECID)
            .lowercased().hasSuffix("402f")
        let tag = isB ? "G4_B" : "G4_A"
        let sequence: [Double] = isB ? [0.63, 0.81] : [0.17, 0.58]
        let controlURL = URL(fileURLWithPath:
            "/tmp/MRA_G4_OUTCOME_\(String(format: "%016llX", request.targetECID).suffix(4))")
        // UI-3.1：仅测试夹具输出行数；正常路径仍为 5 行 sequence。
        let testLineCount = ProcessInfo.processInfo.environment[
            "MRA_UI_RESTORE_LOG_LINES"].flatMap(Int.init) ?? 0
        if testLineCount > 0 {
            var lines = (1...min(testLineCount, 200)).map {
                String(format: "TRIAL_LOG %03d · simulated restore output", $0)
            }
            snapshot.stageFraction = 0.42
            snapshot.outputTail = Array(lines.suffix(160))
            onUpdate?(snapshot)
            var emitted = testLineCount
            while isRunning && emitted < testLineCount + 80 {
                try? await Task.sleep(nanoseconds: 600_000_000)
                if FileManager.default.fileExists(atPath: controlURL.path) {
                    break
                }
                guard isRunning else { break }
                emitted += 1
                lines.append(String(
                    format: "TRIAL_LOG %03d · simulated append", emitted))
                snapshot.outputTail = Array(lines.suffix(160))
                onUpdate?(snapshot)
            }
        } else {
            for fraction in sequence {
                guard isRunning else { break }
                try? await Task.sleep(nanoseconds: 800_000_000)
                snapshot.stageFraction = fraction
                snapshot.outputTail = [
                    "cfgutil 2.21 · started owned restore process",
                    "Target ECID: \(request.targetECID)",
                    "\(tag)_STDOUT \(tag)_STDERR",
                    "Step=Progress restoreActivity=RestoreOS",
                    "Operation 13 progress \(Int(fraction * 100))%",
                ]
                onUpdate?(snapshot)
            }
        }
        UIFixture.debugEvent(
            "B_ENGINE_RUN_WAIT", "engine=\(ObjectIdentifier(self))")
        Task { @MainActor [weak self] in
            while let self, self.continuation != nil {
                if let text = try? String(contentsOf: controlURL, encoding: .utf8) {
                    self.finish(outcome: text.contains("failure") ? .failure : .success)
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        let result: CfgutilRestoreRunResult = await withCheckedContinuation {
            continuation in
            self.continuation = continuation
        }
        UIFixture.debugEvent(
            "B_ENGINE_RUN_EXIT",
            "engine=\(ObjectIdentifier(self)) outcome=\(result.outcome.rawValue)")
        return result
    }

    func cancel() {
        UIFixture.debugEvent(
            "B_ENGINE_CANCEL", "engine=\(ObjectIdentifier(self))")
        if ProcessInfo.processInfo.environment["MRA_UI_RESTORE_CANCEL_IGNORES"] == "1" {
            UIFixture.debugEvent(
                "B_ENGINE_CANCEL_IGNORED", "engine=\(ObjectIdentifier(self))")
            return
        }
        finish(outcome: .canceled)
    }

    func forceKill() {
        UIFixture.debugEvent(
            "B_ENGINE_FORCE_KILL", "engine=\(ObjectIdentifier(self))")
        finish(outcome: .canceled)
    }

    private func finish(outcome: RestoreOutcome) {
        UIFixture.debugEvent(
            "B_ENGINE_FINISH",
            "engine=\(ObjectIdentifier(self)) outcome=\(outcome.rawValue) waiting=\(continuation != nil)")
        guard let continuation else { return }
        isRunning = false
        self.continuation = nil
        continuation.resume(returning: result(outcome: outcome))
    }

    private func result(
        outcome: RestoreOutcome
    ) -> CfgutilRestoreRunResult {
        let directory = activeRequest?.outputDirectory
        let stdoutURL = directory?.appendingPathComponent("stdout.raw")
        let stderrURL = directory?.appendingPathComponent("stderr.raw")
        let stdoutExists = stdoutURL.map {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false
        let stderrExists = stderrURL.map {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false
        let complete = stdoutExists && stderrExists
        let rawEvidence: RestoreRawEvidenceResult = complete
            ? RestoreRawEvidenceResult(
                status: .complete,
                stdoutURL: stdoutURL,
                stderrURL: stderrURL,
                stdoutSHA256: "",
                stderrSHA256: "",
                stdoutBytes: Int64((try? Data(contentsOf: stdoutURL!))?.count ?? 0),
                stderrBytes: Int64((try? Data(contentsOf: stderrURL!))?.count ?? 0),
                writeComplete: true,
                tailPartialReason: nil,
                failures: [])
            : .notSavedByChoice
        return CfgutilRestoreRunResult(
            outcome: outcome,
            exitCode: outcome == .success ? 0 : nil,
            stdoutURL: complete ? stdoutURL : nil,
            stderrURL: complete ? stderrURL : nil,
            stdoutSHA256: "",
            stderrSHA256: "",
            tailComplete: complete,
            cancellationRequested: outcome == .canceled,
            forcedKill: false,
            snapshot: RestoreOutputSnapshot(),
            lifecycle: RestoreLifecycleTimes(
                userConfirmed: RestoreLifecycleClock.now()),
            rawEvidence: rawEvidence)
    }
}

@MainActor
private final class UIFixtureActionDriver {
    weak var device: DeviceControlModel?
    weak var observationSource: UIFixtureObservationSource?
    private var sequence = 0

    func handle(
        action: HelperAction,
        controller: String,
        portNumber: Int,
        rid: Int,
        requestID: String
    ) async -> HelperResponse {
        guard action != .status else {
            return HelperResponse(
                requestID: requestID,
                ok: true,
                dispatchTruth: "NOT_DISPATCHED",
                exitCode: nil,
                reason: "READY",
                helperVersion: "UI-FIXTURE")
        }

        sequence &+= 1
        let fixtureSequence = sequence
        if action == .dfu {
            let live = device?.livePorts.first {
                $0.controller == controller
                    && $0.portNumber == portNumber
                    && $0.rid == rid
            }
            let location = device?.selectedCalibration?.location
                ?? live.map { _ in "01100000" }
                ?? "01100000"
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 420_000_000)
                guard let self, self.sequence >= fixtureSequence else { return }
                let observed = [
                    ObservedDevice(
                        id: "fixture-dfu-\(controller)-\(portNumber)-\(rid)",
                        ecid: "00C0FFEE00000001",
                        mode: .dfu,
                        locationID: location,
                        product: "Apple Mobile Device (DFU Mode)",
                        serial: "ECID:00C0FFEE00000001",
                        modelIdentifier: "MacBookPro18,2",
                        modelSource: "UI fixture",
                        modelIsCandidate: false)
                ]
                if let source = self.observationSource {
                    source.devices = observed
                } else {
                    self.device?.applyObservedDevices(observed, now: Date())
                }
            }
        }

        return HelperResponse(
            requestID: requestID,
            ok: true,
            dispatchTruth: "REQUEST_SENT",
            exitCode: 0,
            reason: "",
            helperVersion: "UI-FIXTURE")
    }
}

@MainActor
private final class UIFixtureObservationSource {
    var devices: [ObservedDevice] = [
        ObservedDevice(
            id: "ecid:00C0FFEE00000001",
            ecid: "00C0FFEE00000001",
            mode: .connected,
            locationID: "01100000",
            product: "MacBook Pro",
            serial: "ECID:00C0FFEE00000001",
            modelIdentifier: "MacBookPro18,2",
            modelSource: "UI fixture",
            modelIsCandidate: false)
    ]
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

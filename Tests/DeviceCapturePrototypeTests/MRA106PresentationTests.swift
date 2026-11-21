import Combine
import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class MRA106PresentationTests: XCTestCase {
    private func makeDevice() -> (DeviceControlModel, LiveHostPort) {
        makeDevice(link: HostPortLink(
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
    }

    private func makeDevice(
        link: HostPortLink
    ) -> (DeviceControlModel, LiveHostPort) {
        let port = LiveHostPort(
            controller: "TestController",
            portNumber: 1,
            rid: 0,
            link: link)
        let custom = PortCalibrationEntry(
            physicalPort: "left1",
            location: "01200000",
            label: "左侧上方",
            rid: "0",
            side: "左侧",
            controller: port.controller,
            portNumber: port.portNumber)
        let document = CalibrationDocument(
            models: [],
            ports: [custom],
            selectedPort: port.id)
        let store = CalibrationStore(
            testingDocument: document,
            hostModel: "MacTest,1",
            builtInLayout: nil)
        let model = DeviceControlModel(
            calibration: store,
            livePorts: [port],
            helperAvailable: true,
            persistPortSelection: false,
            startLiveWork: false)
        model.selectPort(port)
        return (model, port)
    }

    private func row(
        _ detail: SelectedPortDetail,
        _ name: String
    ) -> String? {
        detail.technicalRows.first { $0.name == name }?.value
    }

    func testHealthyEmptyObservationDoesNotInventUnknownMacIdentity() {
        let (model, port) = makeDevice()
        model.applyObservationResult(.success([]), now: Date())

        let row = model.compactPortIdentity(for: port)
        let detail = model.selectedPortDetail

        XCTAssertEqual(row.firstLine, "左侧上方 · 未检测到目标 Mac")
        XCTAssertFalse(row.firstLine.contains("A 型号未知"))
        XCTAssertFalse(row.secondLine.contains("设备身份未读取"))
        XCTAssertEqual(detail.currentHeadline, "当前未检测到目标设备")
        XCTAssertFalse(detail.hasCurrentDevice)
        XCTAssertTrue(detail.technicalRows.contains {
            $0.name == "控制器连接状态" && $0.value == "已连接"
        })
        XCTAssertFalse(model.copySummaryText().contains("A 型号未知"))
        XCTAssertEqual(model.selectedLiveKey, port.id)
    }

    func testObservationFailurePreservesLastStateAndSaysCurrentObservationUnknown() {
        let (model, port) = makeDevice()
        model.applyObservationResult(.failed("read failed"), now: Date())

        let row = model.compactPortIdentity(for: port)
        let detail = model.selectedPortDetail
        XCTAssertEqual(row.firstLine, "左侧上方 · 当前观察未知")
        XCTAssertEqual(detail.currentHeadline, "当前观察未知")
        XCTAssertFalse(detail.hasCurrentDevice)
        XCTAssertTrue(detail.currentHeadline.contains("未知"))
    }

    func testU1U2U3U4TechnicalDetailsExposeReadOnlyEngineeringFacts() {
        let link = HostPortLink(
            portLocation: "left-front",
            parentPortNumber: 1,
            parentPortTypeDescription: "USB-C",
            connectionActive: true,
            transportsProvisioned: ["CC"],
            transportsSupported: [],
            transportsActive: ["USB3"],
            transportsProvisionedState: .provided(["CC"]),
            transportsSupportedState: .notProvided,
            transportsActiveState: .provided(["USB3"]),
            activeTransportDetails: [
                HostPortActiveTransport(
                    name: "USB3",
                    dataRateDescription: "5 Gbps",
                    linkRateDescription: nil,
                    superspeedSignalingDescription: "Gen 1",
                    tunneled: false,
                    dataRoleDescription: "Host",
                    trmStateDescription: "Active"),
            ],
            overcurrentCount: 0,
            transportsUnauthorized: .provided(["Power In"]),
            authorizationRequired: true,
            userAuthorizationStatusDescription: "No Action",
            featuresSupported: .provided(["TRM"]),
            featuresEnabled: .provided([]))
        let (model, _) = makeDevice(link: link)
        let detail = model.selectedPortDetail

        XCTAssertEqual(row(detail, "端口位置"), "left-front")
        XCTAssertEqual(row(detail, "父端口证据"), "Port 1 · USB-C")
        XCTAssertEqual(row(detail, "传输支持"), "系统未提供")
        XCTAssertEqual(row(detail, "传输配置"), "CC")
        XCTAssertEqual(row(detail, "传输活动"), "USB3")
        XCTAssertEqual(
            row(detail, "活动传输 · USB3"),
            "5 Gbps · 信号 Gen 1 · 数据角色 Host · Tunneled 否 · TRM Active")
        XCTAssertEqual(row(detail, "HPM 过流计数"), "0")
        XCTAssertEqual(row(detail, "未授权传输"), "Power In")
        XCTAssertEqual(row(detail, "授权要求"), "是")
        XCTAssertEqual(row(detail, "用户授权状态"), "No Action")
        XCTAssertEqual(row(detail, "支持功能"), "TRM")
        XCTAssertEqual(row(detail, "启用功能"), "无（空列表）")
        XCTAssertTrue(model.canControl, "read-only facts must not change control gating")
    }

    func testU5PowerContractIsLabelledAsLimitAndConflictIsNotAttached() {
        let (model, port) = makeDevice()
        let contract = PanoramaPowerContract(
            portNumber: 1,
            portType: "USB-C",
            sourceName: "USB-PD",
            voltageMillivolts: 28_000,
            maxCurrentMilliamps: 4_990,
            maxPowerMilliwatts: 139_720,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let unique = model.detail(
            for: port,
            sharedUSB: MainPortUSBProjection(
                displayName: nil,
                isMacEvidence: false,
                modeText: "USB",
                evidence: "test",
                powerAttribution: .unique(contract)))
        XCTAssertEqual(
            row(unique, "PD 合约"),
            "USB-PD · 28.000 V · 4.990 A · 139.720 W（合约最大功率上限，非实时功耗）")

        let conflicting = model.detail(
            for: port,
            sharedUSB: MainPortUSBProjection(
                displayName: nil,
                isMacEvidence: false,
                modeText: "USB",
                evidence: "test",
                powerAttribution: .conflicting))
        XCTAssertEqual(row(conflicting, "PD 合约"), "归属未证实：存在多个 USB-C 合约")
    }

    func testU6RootStatisticsPreservePerNodeValuesAndSaturation() {
        let rows = PanoramaUSBStatisticsPresentation.rows(
            for: PanoramaUSBRootStatistics(
                linkErrorCount: 3,
                connectCount: 7,
                overcurrentCount: 0,
                enumerationFailureCount: 2,
                usb3LinkFailureCount: 0xFFFF))

        XCTAssertEqual(
            rows.first { $0.name == "link-error-count" }?.value,
            "3")
        XCTAssertEqual(
            rows.first { $0.name == "连接次数" }?.value,
            "7")
        XCTAssertEqual(
            rows.first { $0.name == "过流次数" }?.value,
            "0")
        XCTAssertEqual(
            rows.first { $0.name == "枚举失败次数" }?.value,
            "2")
        XCTAssertEqual(
            rows.first { $0.name == "USB3 链路失败次数" }?.value,
            "0xFFFF（饱和/不可用）")
    }

    func testU1ToU6CoreLabelsTranslateInAllLanguages() {
        let keys = [
            "端口位置",
            "父端口证据",
            "传输支持",
            "传输配置",
            "传输活动",
            "HPM 过流计数",
            "未授权传输",
            "授权要求",
            "用户授权状态",
            "支持功能",
            "启用功能",
            "供电与 PD",
            "PD 合约",
            "USB 根端口统计",
            "link-error-count",
            "连接次数",
            "过流次数",
            "枚举失败次数",
            "USB3 链路失败次数",
            "系统未提供",
            "无（空列表）",
            "归属未证实：存在多个 USB-C 合约",
            "仅检测到非 USB-C 供电记录；未挂接",
            "0xFFFF（饱和/不可用）",
        ]
        let original = UserDefaults.standard.string(forKey: "ui.languageMode")
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: "ui.languageMode")
            } else {
                UserDefaults.standard.removeObject(forKey: "ui.languageMode")
            }
        }
        for code in ["en", "zh-Hant", "ja", "ko"] {
            UserDefaults.standard.set(code, forKey: "ui.languageMode")
            for key in keys {
                XCTAssertNotEqual(
                    L10n.t(key),
                    key,
                    "\(code) missing U1-U6 presentation translation for \(key)")
            }
        }
    }

    func testDFUConfirmationLabelsTranslateInAllLanguages() {
        let keys = [
            "请求已发送 · 观察中",
            "观察到 DFU · 结果未确认",
            "已确认进入 DFU · 同一设备",
            "已确认该端口出现 DFU · 设备身份未确认",
            "结果未确认 · 观察窗口结束",
            "只读观察进行中；尚未确认设备进入 DFU。",
            "本次请求后，同一设备已进入 DFU；这不代表 Restore 成功。",
            "本次请求后，该物理端口出现 DFU；具体设备身份未确认。",
            "本次操作已确认进入 DFU；当前端口未观察到 DFU。",
            "只读确认不会解锁按钮或改变发送链。",
        ]
        let original = UserDefaults.standard.string(forKey: "ui.languageMode")
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: "ui.languageMode")
            } else {
                UserDefaults.standard.removeObject(forKey: "ui.languageMode")
            }
        }
        for code in ["en", "zh-Hant", "ja", "ko"] {
            UserDefaults.standard.set(code, forKey: "ui.languageMode")
            for key in keys {
                XCTAssertNotEqual(
                    L10n.t(key),
                    key,
                    "\(code) missing DFU confirmation translation for \(key)")
            }
        }
    }

    func testTrustedPeripheralAndMacUnknownUseDistinctDisplayStates() {
        let (model, port) = makeDevice()
        model.applyObservationResult(.success([]), now: Date())

        let peripheral = MainPortUSBProjection(
            displayName: "AX88179A",
            isMacEvidence: false,
            modeText: "USB",
            evidence: "精确校准 + location")
        let peripheralRow = model.compactPortIdentity(
            for: port,
            sharedUSB: peripheral)
        let peripheralDetail = model.detail(for: port, sharedUSB: peripheral)
        XCTAssertEqual(peripheralRow.firstLine, "左侧上方 · USB 设备已连接 · AX88179A")
        XCTAssertEqual(peripheralDetail.currentHeadline, "USB 设备已连接 · AX88179A")
        XCTAssertTrue(peripheralDetail.hasCurrentDevice)

        let macUnknown = MainPortUSBProjection(
            displayName: "Mac",
            isMacEvidence: true,
            modeText: "DFU",
            evidence: "精确校准 + location")
        let macRow = model.compactPortIdentity(
            for: port,
            sharedUSB: macUnknown)
        let macDetail = model.detail(for: port, sharedUSB: macUnknown)
        XCTAssertEqual(macRow.firstLine, "左侧上方 · Mac DFU · 型号待确认")
        XCTAssertEqual(macDetail.currentHeadline, "Mac DFU · 型号待确认")
        XCTAssertTrue(macDetail.hasCurrentDevice)
    }

    func testObservedMacCopiesStayConsistentBetweenRowsDetailAndReadback() {
        let (model, port) = makeDevice()
        let dfu = ObservedDevice(
            id: "ecid:00C0FFEE00000001",
            ecid: "00C0FFEE00000001",
            mode: .dfu,
            locationID: "01200000",
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:00C0FFEE00000001")
        model.applyObservedDevices([dfu], now: Date())

        XCTAssertEqual(model.compactRowStatus(for: port), "Mac DFU · 型号待确认")
        XCTAssertEqual(
            model.compactPortIdentity(for: port).firstLine,
            "左侧上方 · Mac DFU · 型号待确认")
        XCTAssertEqual(
            model.selectedPortDetail.currentHeadline,
            "Mac DFU · 型号待确认")
        XCTAssertTrue(
            model.copySummaryText().contains("当前观察：Mac DFU · 型号待确认"))
    }

    func testEnglishMacUnknownCopyHasNoChineseStatusFragments() {
        let key = "ui.languageMode"
        let original = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set("en", forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        let (model, port) = makeDevice()
        let dfu = ObservedDevice(
            id: "ecid:00C0FFEE00000001",
            ecid: "00C0FFEE00000001",
            mode: .dfu,
            locationID: "01200000",
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:00C0FFEE00000001")
        model.applyObservedDevices([dfu], now: Date())

        XCTAssertEqual(
            model.compactPortIdentity(for: port).firstLine,
            "Upper Left · Mac DFU · Model pending confirmation")
        XCTAssertEqual(
            model.selectedPortDetail.currentHeadline,
            "Mac DFU · Model pending confirmation")
        XCTAssertFalse(
            model.selectedPortDetail.currentHeadline.contains("型号"))
    }

    func testTimelineAssociationRequiresExactTraceableCalibration() {
        let (model, _) = makeDevice()
        let trusted = model.trustedTimelineAssignment(
            forUSBlocation: "0x01200000")
        XCTAssertTrue(trusted.isConfirmed)
        XCTAssertEqual(trusted.portKey, "TestController:1")

        let live = LiveHostPort(controller: "DifferentController", portNumber: 3, rid: 2)
        let defaultDocument = CalibrationDocument.initial
        let defaultStore = CalibrationStore(
            testingDocument: defaultDocument,
            hostModel: "MacBookPro18,2",
            builtInLayout: nil)
        let defaultModel = DeviceControlModel(
            calibration: defaultStore,
            livePorts: [live],
            helperAvailable: true,
            persistPortSelection: false,
            startLiveWork: false)
        let untrusted = defaultModel.trustedTimelineAssignment(
            forUSBlocation: "02100000")
        XCTAssertFalse(untrusted.isConfirmed)
        XCTAssertNil(untrusted.portKey)
    }

    func testEquivalentIdleScansDoNotPublishDeviceModelAgain() {
        let (model, _) = makeDevice()
        model.applyObservationResult(.success([]), now: Date())
        let ports = model.livePorts
        var publishes = 0
        let cancellable = model.objectWillChange.sink { publishes += 1 }

        model.applyObservationResult(.success([]), now: Date().addingTimeInterval(1))
        model.applyObservationResult(.success([]), now: Date().addingTimeInterval(2))
        model.applyDiscoveredPorts(ports, persistCalibration: false)
        model.applyDiscoveredPorts(ports, persistCalibration: false)

        withExtendedLifetime(cancellable) {
            XCTAssertEqual(publishes, 0)
        }
    }

    func testEquivalentConnectedDeviceScansDoNotPublishIdentityOrCardsAgain() {
        let (model, port) = makeDevice()
        var sample = ObservedDevice(
            id: "ecid:0011223344556677",
            ecid: "0011223344556677",
            mode: .dfu,
            locationID: "01200000",
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:0011223344556677")
        sample.modelIdentifier = "Mac16,8"
        sample.explicitMachineIdentifierRaw = "Mac16,8"
        model.applyObservationResult(.success([sample]), now: Date())
        XCTAssertEqual(model.compactPortIdentity(for: port).firstLine.contains("A3401"), true)

        var publishes = 0
        let cancellable = model.objectWillChange.sink { publishes += 1 }
        model.applyObservationResult(
            .success([sample]),
            now: Date().addingTimeInterval(1))
        model.applyObservationResult(
            .success([sample]),
            now: Date().addingTimeInterval(2))

        withExtendedLifetime(cancellable) {
            XCTAssertEqual(publishes, 0)
        }
        XCTAssertEqual(model.compactPortIdentity(for: port).secondLine, "DFU · 确定")
    }

    func testHeaderHasSingleFixedConfiguratorActionAndNoPanoramaShortcut() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/ContentView.swift"),
            encoding: .utf8)

        XCTAssertEqual(
            content.components(separatedBy: "headerConfiguratorAction").count - 1,
            2)
        XCTAssertFalse(content.contains(
            "if workspaceTab == .device {\n                            Button(configuratorReset.mainActionTitle)"))
        XCTAssertFalse(content.contains("Button(L10n.t(\"接口与设备\"))"))
    }
}

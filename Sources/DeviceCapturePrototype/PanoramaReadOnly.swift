import Foundation
import IOKit
import SwiftUI
import AppKit

struct PanoramaPowerContract: Equatable {
    let portNumber: Int
    let portType: String
    let sourceName: String?
    let voltageMillivolts: Int?
    let maxCurrentMilliamps: Int?
    let maxPowerMilliwatts: Int?
    let capturedAt: Date

    var isContractLimitOnly: Bool { true }
}

enum PanoramaPowerAttributionResult: Equatable {
    case unique(PanoramaPowerContract)
    case conflicting
    case notUSBCOwned
    case notProvided

    var contract: PanoramaPowerContract? {
        if case .unique(let contract) = self { return contract }
        return nil
    }
}

enum PanoramaPowerAttribution {
    static func contract(
        forUSBCPortNumber portNumber: Int,
        nodes: [PanoramaNode]
    ) -> PanoramaPowerAttributionResult {
        let matchingContracts = nodes.filter {
            integer($0.properties["ParentBuiltInPortNumber"]) == portNumber
                && string($0.properties["ParentBuiltInPortTypeDescription"]) == "USB-C"
                && $0.properties["WinningPowerSourceOption"] != nil
        }
        if matchingContracts.count > 1 { return .conflicting }
        guard let node = matchingContracts.first else {
            let hasPowerForPort = nodes.contains {
                (integer($0.properties["ParentBuiltInPortNumber"]) == portNumber
                    || integer($0.properties["ParentPortNumber"]) == portNumber)
                    && $0.properties["WinningPowerSourceOption"] != nil
            }
            return hasPowerForPort ? .notUSBCOwned : .notProvided
        }

        let matchingPorts = nodes.filter {
            integer($0.properties["PortNumber"]) == portNumber && isUSBCPort($0)
        }
        if matchingPorts.count > 1 { return .conflicting }
        guard matchingPorts.count == 1 else { return .notProvided }

        let option = dictionary(node.properties["WinningPowerSourceOption"])
        return .unique(PanoramaPowerContract(
            portNumber: portNumber,
            portType: "USB-C",
            sourceName: string(node.properties["PowerSourceName"]) ?? node.name,
            voltageMillivolts: integer(option["Voltage (mV)"]),
            maxCurrentMilliamps: integer(option["Max Current (mA)"]),
            maxPowerMilliwatts: integer(option["Max Power (mW)"]),
            capturedAt: Date()))
    }

    private static func isUSBCPort(_ node: PanoramaNode) -> Bool {
        let description = string(node.properties["PortTypeDescription"])
        return description?.caseInsensitiveCompare("USB-C") == .orderedSame
            || node.name.localizedCaseInsensitiveContains("Port-USB-C")
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let value = value as? Int { return value }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        guard let value else { return nil }
        let text = String(describing: value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func dictionary(_ value: Any?) -> [String: Any] {
        if let dictionary = value as? [String: Any] { return dictionary }
        if let dictionary = value as? NSDictionary {
            return dictionary.reduce(into: [:]) { result, pair in
                if let key = pair.key as? String {
                    result[key] = pair.value
                }
            }
        }
        return [:]
    }
}

struct PanoramaUSBRootStatistics: Equatable {
    let linkErrorCount: Int?
    let connectCount: Int?
    let overcurrentCount: Int?
    let enumerationFailureCount: Int?
    let usb3LinkFailureCount: Int?

    func isSaturated(_ value: Int?) -> Bool { value == 0xFFFF }

    static func read(from node: PanoramaNode) -> PanoramaUSBRootStatistics? {
        let rawStatistics = node.properties["port-statistics"]
        let statistics: [String: Any]
        if let value = rawStatistics as? [String: Any] {
            statistics = value
        } else if let value = rawStatistics as? NSDictionary {
            statistics = value.reduce(into: [:]) { result, pair in
                if let key = pair.key as? String {
                    result[key] = pair.value
                }
            }
        } else {
            statistics = [:]
        }
        let linkErrorCount = integer(node.properties["link-error-count"])
        guard linkErrorCount != nil || !statistics.isEmpty else { return nil }
        return PanoramaUSBRootStatistics(
            linkErrorCount: linkErrorCount,
            connectCount: integer(statistics["kPortStatConnectCount"]),
            overcurrentCount: integer(statistics["kPortStatOverCurrentCount"]),
            enumerationFailureCount:
                integer(statistics["kPortStatEnumerationFailureCount"]),
            usb3LinkFailureCount:
                integer(statistics["kPortStatUSB3LinkFailureCount"]))
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let value = value as? Int { return value }
        if let value = value as? String { return Int(value) }
        return nil
    }
}

enum PanoramaKind: String { case controller, hub, device, interface, port, power, cable, partner, other }
enum PanoramaClassifier {
    static func kind(className: String, properties: [String: Any]) -> PanoramaKind {
        if className.contains("IOUSBHostInterface") { return .interface }
        if className.contains("IOUSBHostDevice") { return (properties["bDeviceClass"] as? NSNumber)?.intValue == 9 ? .hub : .device }
        if className.contains("XHCI") { return .controller }
        if className.contains("PowerSource") { return .power }
        if className.contains("SOPp") { return .cable }
        if className.contains("SOP") { return .partner }
        if className.contains("IOPort") || className.contains("ControllerType") || className.contains("HPMInterface") { return .port }
        return .other
    }
    static func physicalPortEvidence(location: Int) -> String { _ = location; return "物理端口待确认" }
    static func speedLabel(properties: [String: Any]) -> String? {
        guard let n = properties["UsbLinkSpeed"] as? NSNumber else { return nil }
        return "系统链路原始值 \(n)（单位待核实）"
    }
    static func cableSummary(properties: [String: Any]) -> String {
        guard let meta = properties["Metadata"] as? [String:Any], !meta.isEmpty else { return "线材身份：系统未提供" }
        let vendor = meta["Vendor ID"].map { String(describing:$0) } ?? "未知"
        let type = meta["Product Type Description"].map { String(describing:$0) } ?? "未知"
        return "SOP′ 系统记录：厂商 ID \(vendor) · 类型 \(type)（自报，待核实）"
    }
    static func powerSummary(properties: [String: Any]) -> String {
        guard let value = properties["WinningPowerSourceOption"] as? [String:Any] else { return "供电选项：系统未提供" }
        func item(_ key:String,_ unit:String) -> String { value[key].map { "\($0) \(unit)" } ?? "未知" }
        return "系统报告供电选项：\(item("Voltage (mV)","mV")) · 最大电流 \(item("Max Current (mA)","mA")) · 最大功率 \(item("Max Power (mW)","mW"))；非实时功耗"
    }
}

enum PanoramaDisplayPriority: Int, CaseIterable, Comparable {
    case identifiedMac = 0
    case unknownMac = 1
    case usbHubOrPeripheral = 2
    case ownedCable = 3
    case ownedPeerOrPower = 4
    case noDevice = 5

    static func < (lhs: PanoramaDisplayPriority, rhs: PanoramaDisplayPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct PanoramaDisplayEntry: Identifiable, Equatable {
    let nodeID: UInt64
    let title: String
    let subtitle: String
    let priority: PanoramaDisplayPriority
    let icon: String
    let resolution: ResolvedMacIdentity?

    var id: UInt64 { nodeID }
}

struct PanoramaPanelProjection: Equatable {
    let primaryEntries: [PanoramaDisplayEntry]
    let unownedAttachments: [PanoramaDisplayEntry]
}

enum PanoramaEntryBuilder {
    static func project(nodes: [PanoramaNode]) -> PanoramaPanelProjection {
        var primary: [PanoramaDisplayEntry] = []
        var unowned: [PanoramaDisplayEntry] = []
        for node in nodes {
            switch node.kind {
            case .hub:
                primary.append(entry(for: node, priority: .usbHubOrPeripheral,
                                     icon: "point.3.connected.trianglepath.dotted"))
            case .device:
                let resolution = identityResolution(for: node)
                if resolution != nil {
                    let identified = resolution?.state == .confirmedCurrent
                        || resolution?.state == .uniqueCurrentMatch
                    primary.append(entry(
                        for: node,
                        priority: identified ? .identifiedMac : .unknownMac,
                        icon: "laptopcomputer"))
                } else {
                    primary.append(entry(for: node, priority: .usbHubOrPeripheral,
                                         icon: "cable.connector"))
                }
            case .cable:
                unowned.append(entry(
                    for: node,
                    priority: .ownedCable,
                    icon: "cable.connector.slash",
                    subtitleSuffix: "物理归属未证实"))
            case .partner, .power:
                unowned.append(entry(
                    for: node,
                    priority: .ownedPeerOrPower,
                    icon: node.kind == .power ? "bolt.fill" : "point.3.connected.trianglepath.dotted",
                    subtitleSuffix: "物理归属未证实"))
            case .controller, .interface, .port, .other:
                continue
            }
        }
        primary.sort {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.nodeID < $1.nodeID
        }
        unowned.sort {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.title < $1.title
        }
        return PanoramaPanelProjection(
            primaryEntries: primary,
            unownedAttachments: unowned)
    }

    static func identityResolution(for node: PanoramaNode) -> ResolvedMacIdentity? {
        guard node.kind == .device else { return nil }
        let product = propertyString(node, "USB Product Name")
            ?? propertyString(node, "kUSBProductString")
            ?? ""
        let deviceType = propertyString(node, "deviceType")
            ?? propertyString(node, "ProductType")
            ?? propertyString(node, "model")
        let explicit = TargetModelCatalog.identifier(from: deviceType)
            ?? TargetModelCatalog.identifier(from: product)
        let explicitMachine = explicit?.hasPrefix("iBridge") == true ? nil : explicit
        let productType = deviceType
            ?? (explicit?.hasPrefix("iBridge") == true ? explicit : nil)
        let serial = propertyString(node, "USB Serial Number")
            ?? propertyString(node, "kUSBSerialNumberString")
            ?? ""
        let ecid = ECIDIdentity.fromUSB(
            serial: serial,
            numericProperty: propertyString(node, "UsbAppleDeviceECID"))?.canonicalHex
        let mode = product.localizedCaseInsensitiveContains("dfu")
            ? "DFU"
            : (product.localizedCaseInsensitiveContains("recovery") ? "Recovery" : "已连接")
        let resolved = MacIdentityResolver.resolve(
            observation: MacIdentityObservation(
                observationID: "panorama:\(node.id)",
                connectionGeneration: 1,
                capturedAt: Date(),
                mode: mode,
                currentECID: ecid,
                explicitMachineIdentifier: explicitMachine,
                productType: productType,
                hardwareCode: propertyString(node, "HardwareModel")
                    ?? propertyString(node, "hardwareModel")
                    ?? propertyString(node, "HardwareCode"),
                cpid: DFUUSBIdentityParser.field(
                    topLevelRaw: propertyString(node, "CPID")
                        ?? propertyString(node, "ChipID"),
                    serial: serial,
                    label: "CPID"),
                bdid: DFUUSBIdentityParser.field(
                    topLevelRaw: propertyString(node, "BDID")
                        ?? propertyString(node, "BoardID"),
                    serial: serial,
                    label: "BDID")))
        let hasMacIdentityEvidence = !resolved.records.isEmpty
            || !resolved.hardwareRecords.isEmpty
            || explicitMachine != nil
            || product.localizedCaseInsensitiveContains("mac")
        return hasMacIdentityEvidence ? resolved : nil
    }

    private static func entry(
        for node: PanoramaNode,
        priority: PanoramaDisplayPriority,
        icon: String,
        subtitleSuffix: String? = nil
    ) -> PanoramaDisplayEntry {
        let resolution = priority == .identifiedMac || priority == .unknownMac
            ? identityResolution(for: node)
            : nil
        let product = propertyString(node, "USB Product Name")
            ?? propertyString(node, "kUSBProductString")
            ?? node.name
        let title: String
        if let resolution {
            let a = resolution.commonANumbers.prefix(2).joined(separator: "/")
            let year = resolution.commonYears.count == 1
                ? String(resolution.commonYears[0])
                : "年份未知"
            title = a.isEmpty ? "\(product) · A 型号未知 · \(year)" : "\(a) · \(year)"
        } else {
            title = product
        }
        let mode = product.localizedCaseInsensitiveContains("dfu")
            ? "DFU"
            : (product.localizedCaseInsensitiveContains("recovery") ? "Recovery" : node.kind.rawValue)
        var subtitleParts: [String] = [mode]
        if let resolution {
            switch resolution.state {
            case .confirmedCurrent:
                subtitleParts.append("确定")
            case .uniqueCurrentMatch:
                subtitleParts.append("唯一匹配")
            case .candidates:
                subtitleParts.append("候选 \(max(1, resolution.modelIdentifiers.count))")
            case .conflict:
                subtitleParts.append("身份冲突")
            case .unknown, .historicalHintOnly:
                subtitleParts.append("型号未知")
            }
        }
        if let subtitleSuffix { subtitleParts.append(subtitleSuffix) }
        return PanoramaDisplayEntry(
            nodeID: node.id,
            title: title,
            subtitle: subtitleParts.joined(separator: " · "),
            priority: priority,
            icon: icon,
            resolution: resolution)
    }

    private static func propertyString(_ node: PanoramaNode, _ key: String) -> String? {
        guard let value = node.properties[key] else { return nil }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func propertyInt(_ node: PanoramaNode, _ key: String) -> Int? {
        (node.properties[key] as? NSNumber)?.intValue
    }
}

struct PanoramaNode: Identifiable {
    let id: UInt64
    let parentID: UInt64?
    let name: String
    let className: String
    let plane: String
    let properties: [String: Any]
    var kind: PanoramaKind { PanoramaClassifier.kind(className: className, properties: properties) }
}

struct PanoramaSnapshotReadResult {
    let nodes: [PanoramaNode]
    let isComplete: Bool
    let failures: [String]
}

enum PanoramaSnapshotAvailability: Equatable {
    case notLoaded
    case current
    case partial(String)
    case failed(String)
}

enum PanoramaReader {
    static let classes = ["IOUSBHostInterface", "AppleHPMInterfaceType10", "AppleHPMInterfaceType11", "AppleHPMInterfaceType12", "AppleTCControllerType10", "AppleTCControllerType11", "IOPortFeaturePowerSource", "IOPortTransportComponentCCUSBPDSOP", "IOPortTransportComponentCCUSBPDSOPp", "IOPortTransportComponentCCUSBPDSOPpp", "IOPort"]
    static func identifier(_ object: io_object_t) -> UInt64? {
        var value: UInt64 = 0
        return IORegistryEntryGetRegistryEntryID(object, &value) == KERN_SUCCESS ? value : nil
    }
    static func name(_ object: io_object_t, className: Bool = false) -> String {
        var value = [CChar](repeating: 0, count: 128)
        let status = className ? IOObjectGetClass(object, &value) : IORegistryEntryGetName(object, &value)
        return status == KERN_SUCCESS ? String(cString: value) : "未知"
    }
    static func properties(_ object: io_registry_entry_t) -> [String: Any] {
        var result: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(object, &result, kCFAllocatorDefault, 0) == KERN_SUCCESS, let result else { return [:] }
        return result.takeRetainedValue() as? [String: Any] ?? [:]
    }
    static func nearestParent(_ object: io_registry_entry_t, plane: String, known: Set<UInt64>? = nil) -> UInt64? {
        var cursor = object
        var owned = false
        defer { if owned { IOObjectRelease(cursor) } }
        for _ in 0..<32 {
            var next: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(cursor, plane, &next) == KERN_SUCCESS else { return nil }
            if owned { IOObjectRelease(cursor) }
            cursor = next; owned = true
            if let id = identifier(cursor), known == nil || known!.contains(id) { return id }
        }
        return nil
    }
    static func snapshot() -> [PanoramaNode] {
        snapshotResult().nodes
    }

    static func snapshotResult() -> PanoramaSnapshotReadResult {
        var failures: [String] = []
        var nodes: [PanoramaNode] = []
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else {
            return PanoramaSnapshotReadResult(
                nodes: [],
                isComplete: false,
                failures: ["无法打开 IORegistry 根节点"])
        }
        var iterator: io_iterator_t = 0
        if IORegistryEntryCreateIterator(root, "IOUSB", IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS {
            while true {
                let object = IOIteratorNext(iterator); if object == 0 { break }
                if let id = identifier(object) {
                    nodes.append(PanoramaNode(id:id, parentID:nearestParent(object, plane:"IOUSB"), name:name(object), className:name(object,className:true), plane:"IOUSB", properties:properties(object)))
                }
                IOObjectRelease(object)
            }
            IOObjectRelease(iterator)
        } else {
            failures.append("IOUSB 节点枚举失败")
        }
        IOObjectRelease(root)
        let known = Set(nodes.map(\.id))
        var seen = known
        for cls in classes {
            var matches: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &matches) == KERN_SUCCESS else {
                failures.append("\(cls) 枚举失败")
                continue
            }
            while true {
                let object = IOIteratorNext(matches); if object == 0 { break }
                if let id = identifier(object), !seen.contains(id) {
                    seen.insert(id)
                    let parent = cls == "IOUSBHostInterface" ? nearestParent(object, plane:"IOService", known:known) : nearestParent(object, plane:"IOService")
                    nodes.append(PanoramaNode(id:id, parentID:parent, name:name(object), className:name(object,className:true), plane:"IOService", properties:properties(object)))
                }
                IOObjectRelease(object)
            }
            IOObjectRelease(matches)
        }
        return PanoramaSnapshotReadResult(
            nodes: nodes,
            isComplete: failures.isEmpty,
            failures: failures)
    }
    static func serializable(_ v: Any) -> Any {
        if let d = v as? Data { return ["encoding":"base64", "value":d.base64EncodedString()] }
        if let a = v as? [Any] { return a.map(serializable) }
        if let d = v as? [String:Any] { return d.mapValues(serializable) }
        if v is String || v is NSNumber || v is NSNull { return v }
        return String(describing:v)
    }
}

final class PanoramaWatch {
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var sessionID: UUID?
    private var nextSequence: UInt64 = 0
    private var coverage: USBConnectionObservationCoverage = .registering
    private var retained: [UInt64: RetainedDevice] = [:]
    private var retainedOrder: [UInt64] = []
    private let maxRetainedDevices = 256
    private let maxEventsPerBatch = 256
    var changed: (() -> Void)?
    var usbEventHandler: ((PanoramaUSBWatchUpdate) -> Void)?

    private struct RetainedDevice {
        let locationID: String?
        let mode: USBConnectionTimelineMode
        let vendorID: Int?
        let productID: Int?
        let ecid: String?
        let productName: String?
        let deviceClass: Int?
    }

    var isActive: Bool { port != nil }

    func start(sessionID: UUID = UUID()) {
        guard port == nil, let p = IONotificationPortCreate(kIOMainPortDefault) else { return }
        port = p
        IONotificationPortSetDispatchQueue(p, DispatchQueue.main)
        self.sessionID = sessionID
        nextSequence = 0
        coverage = .registering
        retained.removeAll(keepingCapacity: true)
        retainedOrder.removeAll(keepingCapacity: true)

        for cls in ["IOUSBHostInterface", "IOPortTransportComponentCCUSBPDSOP", "IOPortTransportComponentCCUSBPDSOPp", "IOPortFeaturePowerSource"] {
            for kind in [kIOFirstMatchNotification, kIOTerminatedNotification] {
                var iterator: io_iterator_t = 0
                let status = IOServiceAddMatchingNotification(p,kind,IOServiceMatching(cls), { ref, iterator in
                    guard let ref else { return }
                    let watch = Unmanaged<PanoramaWatch>.fromOpaque(ref).takeUnretainedValue()
                    watch.drainGeneric(iterator)
                    watch.changed?()
                }, Unmanaged.passUnretained(self).toOpaque(), &iterator)
                if status == KERN_SUCCESS {
                    iterators.append(iterator)
                    drainGeneric(iterator)
                }
            }
        }

        var arrivedRegistered = false
        var terminatedRegistered = false
        var arrivedIterator: io_iterator_t = 0
        let arrivedStatus = IOServiceAddMatchingNotification(
            p,
            kIOFirstMatchNotification,
            IOServiceMatching("IOUSBHostDevice"),
            { ref, iterator in
                guard let ref else { return }
                let watch = Unmanaged<PanoramaWatch>.fromOpaque(ref).takeUnretainedValue()
                watch.consumeUSBDevice(
                    iterator: iterator,
                    direction: .arrived,
                    initial: false)
                watch.changed?()
            },
            Unmanaged.passUnretained(self).toOpaque(),
            &arrivedIterator)
        if arrivedStatus == KERN_SUCCESS {
            arrivedRegistered = true
            iterators.append(arrivedIterator)
            consumeUSBDevice(
                iterator: arrivedIterator,
                direction: .arrived,
                initial: true)
            changed?()
        }

        var terminatedIterator: io_iterator_t = 0
        let terminatedStatus = IOServiceAddMatchingNotification(
            p,
            kIOTerminatedNotification,
            IOServiceMatching("IOUSBHostDevice"),
            { ref, iterator in
                guard let ref else { return }
                let watch = Unmanaged<PanoramaWatch>.fromOpaque(ref).takeUnretainedValue()
                watch.consumeUSBDevice(
                    iterator: iterator,
                    direction: .removed,
                    initial: false)
                watch.changed?()
            },
            Unmanaged.passUnretained(self).toOpaque(),
            &terminatedIterator)
        if terminatedStatus == KERN_SUCCESS {
            terminatedRegistered = true
            iterators.append(terminatedIterator)
            consumeUSBDevice(
                iterator: terminatedIterator,
                direction: .removed,
                initial: true)
            changed?()
        }

        if !arrivedRegistered {
            coverage = .incomplete(.arrivedRegistrationFailed)
        } else if !terminatedRegistered {
            coverage = .incomplete(.terminatedRegistrationFailed)
        } else {
            coverage = .complete
        }
        usbEventHandler?(PanoramaUSBWatchUpdate(
            observations: [],
            coverage: coverage,
            droppedInBatch: 0))
    }

    private func drainGeneric(_ iterator: io_iterator_t) {
        while true {
            let object = IOIteratorNext(iterator)
            if object == 0 { break }
            IOObjectRelease(object)
        }
    }

    private func consumeUSBDevice(
        iterator: io_iterator_t,
        direction: USBConnectionTimelineDirection,
        initial: Bool
    ) {
        let wallTime = Date()
        let monotonic = ProcessInfo.processInfo.systemUptime
        let batchID = UUID()
        var observations: [PanoramaUSBDeviceObservation] = []
        var dropped = 0
        while true {
            let object = IOIteratorNext(iterator)
            if object == 0 { break }
            defer { IOObjectRelease(object) }

            let registryID = PanoramaReader.identifier(object)
            let direct = registryID.flatMap { readDevice(object, registryID: $0) }
            let cached = registryID.flatMap { retained[$0] }
            let metadata = direct ?? cached

            if direction == .arrived,
               let registryID,
               let direct {
                cache(direct, registryID: registryID)
            }

            guard !initial || direction == .arrived else { continue }
            guard observations.count < maxEventsPerBatch else {
                dropped += 1
                continue
            }
            nextSequence += 1
            let eventDirection: USBConnectionTimelineDirection
            if initial && direction == .arrived {
                eventDirection = .initialPresent
            } else {
                eventDirection = direction
            }
            observations.append(PanoramaUSBDeviceObservation(
                sessionID: sessionID ?? UUID(),
                sequence: nextSequence,
                batchID: batchID,
                observedAtUTC: wallTime,
                monotonicSeconds: monotonic,
                direction: eventDirection,
                registryEntryID: registryID,
                locationID: metadata?.locationID,
                mode: metadata?.mode ?? .unknown,
                vendorID: metadata?.vendorID,
                productID: metadata?.productID,
                ecid: metadata?.ecid,
                productName: metadata?.productName,
                deviceClass: metadata?.deviceClass,
                retainedAttributes: direct == nil && cached != nil))

            if direction == .removed, let registryID {
                retained.removeValue(forKey: registryID)
                retainedOrder.removeAll { $0 == registryID }
            }
        }
        usbEventHandler?(PanoramaUSBWatchUpdate(
            observations: observations,
            coverage: coverage,
            droppedInBatch: dropped))
    }

    private func readDevice(
        _ object: io_registry_entry_t,
        registryID: UInt64
    ) -> RetainedDevice? {
        let vendor = intProperty(object, "idVendor")
        let productID = intProperty(object, "idProduct")
        let productName = stringProperty(object, "USB Product Name")
            ?? stringProperty(object, "kUSBProductString")
        let deviceClass = intProperty(object, "bDeviceClass")
        let serial = stringProperty(object, "USB Serial Number")
            ?? stringProperty(object, "kUSBSerialNumberString")
            ?? ""
        let numericECID = stringProperty(object, "UsbAppleDeviceECID")
        let ecid = ECIDIdentity.fromUSB(
            serial: serial,
            numericProperty: numericECID)?.canonicalHex
        let location = USBTimelineLocationNormalizer.normalize(
            propertyValue(object, "locationID"))
        let mode = mode(
            productName: productName,
            vendorID: vendor,
            productID: productID,
            deviceClass: deviceClass)
        _ = registryID
        return RetainedDevice(
            locationID: location,
            mode: mode,
            vendorID: vendor,
            productID: productID,
            ecid: ecid,
            productName: productName,
            deviceClass: deviceClass)
    }

    private func mode(
        productName: String?,
        vendorID: Int?,
        productID: Int?,
        deviceClass: Int?
    ) -> USBConnectionTimelineMode {
        let product = (productName ?? "").lowercased()
        if product.contains("dfu") { return .dfu }
        if product.contains("recovery") { return .recovery }
        if deviceClass == 9 { return .hub }
        if vendorID == 0x05AC,
           product.contains("mac") || productID == 0x1881 {
            return .connected
        }
        return productName == nil ? .unknown : .usb
    }

    private func cache(_ value: RetainedDevice, registryID: UInt64) {
        if retained[registryID] == nil {
            retainedOrder.append(registryID)
        }
        retained[registryID] = value
        while retainedOrder.count > maxRetainedDevices {
            let removed = retainedOrder.removeFirst()
            retained.removeValue(forKey: removed)
        }
    }

    private func propertyValue(_ object: io_registry_entry_t, _ key: String) -> Any? {
        guard let value = IORegistryEntryCreateCFProperty(
            object,
            key as CFString,
            kCFAllocatorDefault,
            0)?.takeRetainedValue() else {
            return nil
        }
        return value
    }

    private func intProperty(_ object: io_registry_entry_t, _ key: String) -> Int? {
        guard let value = propertyValue(object, key) else { return nil }
        if let number = value as? NSNumber {
            let double = number.doubleValue
            return double == double.rounded() ? number.intValue : nil
        }
        if let text = value as? String {
            if text.lowercased().hasPrefix("0x") {
                return Int(text.dropFirst(2), radix: 16)
            }
            return Int(text)
        }
        return nil
    }

    private func stringProperty(_ object: io_registry_entry_t, _ key: String) -> String? {
        guard let value = propertyValue(object, key) else { return nil }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    func stop() {
        changed = nil
        usbEventHandler = nil
        sessionID = nil
        coverage = .registering
        for iterator in iterators { IOObjectRelease(iterator) }; iterators.removeAll()
        if let p = port { IONotificationPortDestroy(p); port = nil }
        retained.removeAll(keepingCapacity: false)
        retainedOrder.removeAll(keepingCapacity: false)
    }
    deinit { stop() }
}

@MainActor final class PanoramaViewModel: ObservableObject {
    @Published var nodes: [PanoramaNode] = []
    @Published var updated: Date?
    @Published var busy = false
    @Published var thunderbolt = "尚未读取；仅在手动刷新时读取。"
    @Published var error = ""
    @Published private(set) var snapshotAvailability: PanoramaSnapshotAvailability = .notLoaded
    @Published private(set) var timelineRevision = 0
    private var generation = 0
    private let watcher = PanoramaWatch()
    private var eventTask: Task<Void,Never>?
    private var rerun = false
    private weak var deviceModel: DeviceControlModel?
    private var timelineTracker = USBConnectionTimelineTracker()
    private var timelineSessionID: UUID?

    func startWatching(device: DeviceControlModel? = nil) {
        if let device {
            deviceModel = device
        }
        guard !watcher.isActive else { return }
        let sessionID = UUID()
        timelineSessionID = sessionID
        timelineTracker.beginSession(
            id: sessionID,
            wallTime: Date(),
            monotonicSeconds: ProcessInfo.processInfo.systemUptime)
        timelineRevision &+= 1
        if UIFixture.isActive,
           ProcessInfo.processInfo.environment["MRA_QA_TIMELINE_FIXTURE"] == "trace" {
            seedTimelineFixture(sessionID: sessionID)
            return
        }
        watcher.changed = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.eventTask?.cancel()
                self.eventTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds:700_000_000)
                    guard !Task.isCancelled else { return }
                    self?.refreshUSBOnly()
                }
            }
        }
        watcher.usbEventHandler = { [weak self] update in
            DispatchQueue.main.async {
                self?.receiveUSBWatchUpdate(update)
            }
        }
        watcher.start(sessionID: sessionID)
        if !watcher.isActive {
            timelineTracker.setCoverage(.incomplete(.arrivedRegistrationFailed))
            timelineRevision &+= 1
        }
    }

    func stopWatching() {
        eventTask?.cancel()
        watcher.stop()
        timelineTracker.endSession()
        timelineSessionID = nil
        timelineRevision &+= 1
        generation += 1
        busy = false
    }

    func refreshUSBOnly() {
        guard !busy else { rerun = true; return }
        busy = true; generation += 1; let ticket = generation
        Task {
            let fresh = await Task.detached(priority:.utility) { PanoramaReader.snapshotResult() }.value
            guard ticket == generation else { return }
            nodes = fresh.nodes
            snapshotAvailability = PanoramaViewModel.availability(for: fresh)
            updated = Date(); busy = false
            if rerun { rerun = false; refreshUSBOnly() }
        }
    }
    func refresh() {
        guard !busy else { return }
        busy = true; error = ""; generation += 1; let ticket = generation
        Task {
            let data = await Task.detached(priority:.utility) { () -> (PanoramaSnapshotReadResult, String) in
                let snapshot = PanoramaReader.snapshotResult()
                let p = Process(); p.executableURL = URL(fileURLWithPath:"/usr/sbin/system_profiler")
                p.arguments = ["-json", "SPThunderboltDataType"]
                let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
                do { try p.run(); let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }; DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now() + 8, execute:watchdog); defer { watchdog.cancel() }; let bytes = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); return (snapshot, p.terminationStatus == 0 ? (String(data:bytes, encoding:.utf8) ?? "系统未提供") : "Thunderbolt 信息读取失败或超时") }
                catch { return (snapshot,"Thunderbolt 信息读取失败：\(error.localizedDescription)") }
            }.value
            guard ticket == generation else { return }
            let snapshot = data.0
            nodes = snapshot.nodes
            snapshotAvailability = PanoramaViewModel.availability(for: snapshot)
            thunderbolt = data.1
            updated = Date()
            busy = false
            if rerun { rerun = false; refreshUSBOnly() }
        }
    }
    func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "interfaces-diagnostics.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let payload: [String:Any] = ["captured_at":updated.map { ISO8601DateFormatter().string(from:$0) } ?? "unknown", "note":"原始诊断可能含序列号和 ECID；仅由用户手动保存。", "nodes":nodes.map { ["id":String($0.id), "parent_id":$0.parentID.map(String.init) ?? "unknown", "class":$0.className, "name":$0.name, "plane":$0.plane, "physical_port":"unknown", "properties":PanoramaReader.serializable($0.properties)] }, "thunderbolt_raw_json":thunderbolt]
        do { try JSONSerialization.data(withJSONObject:payload,options:[.prettyPrinted,.sortedKeys]).write(to:url,options:.atomic) }
        catch { self.error = error.localizedDescription }
    }

    func mainPortProjection(for live: LiveHostPort) -> MainPortUSBProjection? {
        guard let deviceModel else { return nil }
        let candidates = nodes.compactMap { node -> PanoramaNode? in
            guard [.device, .hub].contains(node.kind),
                  let raw = node.properties["locationID"],
                  let location = USBTimelineLocationNormalizer.normalize(raw) else {
                return nil
            }
            let assignment = deviceModel.trustedTimelineAssignment(
                forUSBlocation: location)
            return assignment.isConfirmed && assignment.portKey == live.id
                ? node
                : nil
        }
        guard !candidates.isEmpty else { return nil }
        let macNode = candidates.first {
            PanoramaEntryBuilder.identityResolution(for: $0) != nil
        }
        let selected = macNode ?? candidates.first { $0.kind == .hub } ?? candidates[0]
        let product = stringProperty(selected, "USB Product Name")
            ?? stringProperty(selected, "kUSBProductString")
            ?? selected.name
        let mode: USBConnectionTimelineMode
        if product.localizedCaseInsensitiveContains("dfu") {
            mode = .dfu
        } else if product.localizedCaseInsensitiveContains("recovery") {
            mode = .recovery
        } else if macNode != nil || product.localizedCaseInsensitiveContains("mac") {
            mode = .connected
        } else if selected.kind == .hub {
            mode = .hub
        } else {
            mode = .usb
        }
        return MainPortUSBProjection(
            displayName: product.isEmpty ? nil : product,
            isMacEvidence: macNode != nil
                || product.localizedCaseInsensitiveContains("mac"),
            modeText: mode.displayText,
            evidence: "USB location + controller/PortNumber/RID 精确校准一致",
            powerAttribution: PanoramaPowerAttribution.contract(
                forUSBCPortNumber: live.portNumber,
                nodes: nodes))
    }

    func timelineSnapshot(
        for live: LiveHostPort,
        wallTime: Date = Date(),
        monotonicSeconds: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> USBConnectionTimelineSnapshot {
        timelineTracker.snapshot(
            for: live.id,
            label: deviceModel?.label(for: live),
            nowMonotonicSeconds: monotonicSeconds,
            nowWallTime: wallTime)
    }

    func clearTimeline(
        for live: LiveHostPort,
        wallTime: Date = Date(),
        monotonicSeconds: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        timelineTracker.clear(
            portKey: live.id,
            monotonicSeconds: monotonicSeconds,
            wallTime: wallTime)
        timelineRevision &+= 1
    }

    func unownedTimelineEvents(limit: Int = 10) -> [USBConnectionTimelineEvent] {
        timelineTracker.unownedEvents(limit: limit)
    }

    private func receiveUSBWatchUpdate(_ update: PanoramaUSBWatchUpdate) {
        guard let timelineSessionID,
              update.observations.allSatisfy({ $0.sessionID == timelineSessionID }) else {
            timelineTracker.recordDropped(
                max(1, update.observations.count),
                reason: .outOfOrderEvent)
            timelineRevision &+= 1
            return
        }
        timelineTracker.setCoverage(update.coverage)
        if update.droppedInBatch > 0 {
            timelineTracker.recordDropped(
                update.droppedInBatch,
                reason: .historyOverflow)
        }
        let observations = update.observations.map { raw in
            USBConnectionTimelineObservation(
                sessionID: raw.sessionID,
                sequence: raw.sequence,
                batchID: raw.batchID,
                observedAtUTC: raw.observedAtUTC,
                monotonicSeconds: raw.monotonicSeconds,
                direction: raw.direction,
                registryEntryID: raw.registryEntryID,
                locationID: raw.locationID,
                mode: raw.mode,
                vendorID: raw.vendorID,
                productID: raw.productID,
                ecid: raw.ecid,
                productName: raw.productName,
                deviceClass: raw.deviceClass,
                assignment: raw.locationID.map {
                    deviceModel?.trustedTimelineAssignment(forUSBlocation: $0)
                        ?? .unowned(location: $0)
                } ?? .unowned(location: nil),
                retainedAttributes: raw.retainedAttributes)
        }
        _ = timelineTracker.ingest(observations)
        timelineRevision &+= 1
    }

    private func seedTimelineFixture(sessionID: UUID) {
        guard let deviceModel,
              let live = deviceModel.livePorts.first(where: {
                  deviceModel.label(for: $0) == "左侧下方"
              }) ?? deviceModel.livePorts.first else {
            return
        }
        let assignment = deviceModel.trustedTimelineAssignment(
            forUSBlocation: "01100000")
        guard assignment.isConfirmed else { return }
        let nowMonotonic = ProcessInfo.processInfo.systemUptime
        let now = Date()
        let batch = UUID()
        timelineTracker.setCoverage(.complete)
        let observations = [
            USBConnectionTimelineObservation(
                sessionID: sessionID,
                sequence: 1,
                batchID: batch,
                observedAtUTC: now.addingTimeInterval(-14),
                monotonicSeconds: nowMonotonic - 14,
                direction: .arrived,
                registryEntryID: 91001,
                locationID: "01100000",
                mode: .dfu,
                vendorID: 0x05AC,
                productID: 0x1281,
                ecid: "00C0FFEE00000001",
                productName: "Apple Mobile Device (DFU Mode)",
                deviceClass: 0,
                assignment: assignment,
                retainedAttributes: false),
            USBConnectionTimelineObservation(
                sessionID: sessionID,
                sequence: 2,
                batchID: batch,
                observedAtUTC: now.addingTimeInterval(-10),
                monotonicSeconds: nowMonotonic - 10,
                direction: .removed,
                registryEntryID: 91001,
                locationID: "01100000",
                mode: .dfu,
                vendorID: 0x05AC,
                productID: 0x1281,
                ecid: "00C0FFEE00000001",
                productName: "Apple Mobile Device (DFU Mode)",
                deviceClass: 0,
                assignment: assignment,
                retainedAttributes: true),
            USBConnectionTimelineObservation(
                sessionID: sessionID,
                sequence: 3,
                batchID: batch,
                observedAtUTC: now.addingTimeInterval(-6),
                monotonicSeconds: nowMonotonic - 6,
                direction: .arrived,
                registryEntryID: 91002,
                locationID: "01100000",
                mode: .recovery,
                vendorID: 0x05AC,
                productID: 0x1280,
                ecid: "00C0FFEE00000001",
                productName: "Apple Mobile Device (Recovery Mode)",
                deviceClass: 0,
                assignment: assignment,
                retainedAttributes: false),
        ]
        _ = timelineTracker.ingest(observations)
        nodes = [
            PanoramaNode(
                id: 91_002,
                parentID: nil,
                name: "Apple Mobile Device (Recovery Mode)",
                className: "IOUSBHostDevice",
                plane: "IOUSB",
                properties: [
                    "USB Product Name": "Apple Mobile Device (Recovery Mode)",
                    "deviceType": "MacBookPro18,2",
                    "locationID": NSNumber(value: 0x01100000),
                    "HardwareModel": "MacBookPro18,2",
                ])
        ]
        snapshotAvailability = .current
        updated = now
        timelineRevision &+= 1
        _ = live
    }

    private static func availability(
        for snapshot: PanoramaSnapshotReadResult
    ) -> PanoramaSnapshotAvailability {
        if snapshot.isComplete {
            return .current
        }
        if snapshot.nodes.isEmpty {
            return .failed(snapshot.failures.joined(separator: "；"))
        }
        return .partial(snapshot.failures.joined(separator: "；"))
    }

    private func stringProperty(_ node: PanoramaNode, _ key: String) -> String? {
        guard let value = node.properties[key] else { return nil }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

struct PanoramaView: View {
    @ObservedObject var model: PanoramaViewModel
    let isEmbedded: Bool
    let emptyPrimaryText: String?
    let onUserSelection: (() -> Void)?
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var device: DeviceControlModel
    @State private var selection: UInt64?

    init(
        model: PanoramaViewModel,
        isEmbedded: Bool,
        emptyPrimaryText: String? = nil,
        onUserSelection: (() -> Void)? = nil
    ) {
        self.model = model
        self.isEmbedded = isEmbedded
        self.emptyPrimaryText = emptyPrimaryText
        self.onUserSelection = onUserSelection
    }

    private var projection: PanoramaPanelProjection {
        PanoramaEntryBuilder.project(nodes: model.nodes)
    }
    private var unownedTimelineEvents: [USBConnectionTimelineEvent] {
        model.unownedTimelineEvents(limit: 10)
    }
    private var usbNodes: [PanoramaNode] {
        let all = model.nodes.filter { [.controller,.hub,.device,.interface].contains($0.kind) }
        let ids = Set(all.map(\.id))
        var output: [PanoramaNode] = []; var visited = Set<UInt64>()
        func add(_ node: PanoramaNode) {
            guard visited.insert(node.id).inserted else { return }
            output.append(node)
            for child in all.filter({ $0.parentID == node.id }).sorted(by: { $0.id < $1.id }) { add(child) }
        }
        for root in all.filter({ $0.parentID == nil || !ids.contains($0.parentID!) }).sorted(by: { $0.id < $1.id }) { add(root) }
        for node in all { add(node) }
        return output
    }
    private func indentation(_ node: PanoramaNode) -> CGFloat {
        var id = node.parentID; var seen = Set<UInt64>(); var depth = 0
        while let current = id, seen.insert(current).inserted, depth < 5, let parent = model.nodes.first(where: { $0.id == current }) { depth += 1; id = parent.parentID }
        return CGFloat(depth * 14)
    }
    var body: some View {
        VStack(alignment:.leading, spacing:12) {
            HStack {
                VStack(alignment:.leading) {
                    Text(L10n.t("接口与设备")).font(.title2.bold())
                    Text(L10n.t("系统只读快照 · 物理接口归属待确认"))
                        .foregroundStyle(.secondary).font(.caption)
                }
                Spacer()
                Button(L10n.t("刷新")) { model.refresh() }.disabled(model.busy)
                Button(L10n.t("导出诊断 JSON")) { model.export() }.disabled(model.updated == nil)
            }
            if model.busy { ProgressView(L10n.t("正在后台读取系统信息…")) }
            if !model.error.isEmpty { Text(model.error).foregroundStyle(.red) }
            HSplitView {
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:2) {
                        Text(L10n.t("物理接口与设备（按证据优先级）"))
                            .font(.caption.bold()).foregroundStyle(.secondary).padding(.vertical,8)
                        if projection.primaryEntries.isEmpty {
                            Text(emptyPrimaryText.map { L10n.t($0) }
                                ?? L10n.t("未检测到 Mac、USB HUB 或外设"))
                                .font(.caption).foregroundStyle(.secondary).padding(6)
                        } else {
                            ForEach(projection.primaryEntries) { selectEntry($0) }
                        }

                        if !projection.unownedAttachments.isEmpty {
                            Text(L10n.t("归属未证实的线材、伙伴与供电"))
                                .font(.caption.bold()).foregroundStyle(.orange).padding(.vertical,8)
                            ForEach(projection.unownedAttachments) { selectEntry($0) }
                        }

                        if !unownedTimelineEvents.isEmpty {
                            DisclosureGroup(L10n.t("未归属 USB 时序（最近 10 条）")) {
                                ForEach(unownedTimelineEvents) { event in
                                    Text(USBConnectionTimelineFormatter.eventLine(event))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .font(.caption)
                            .padding(.vertical, 6)
                        }

                        DisclosureGroup(L10n.t("原始 USB 拓扑")) {
                            Text(L10n.t("以下仅显示系统父子关系，不代表已确认物理接口。"))
                                .font(.caption2).foregroundStyle(.secondary).padding(.vertical,4)
                            ForEach(usbNodes, id:\.id) { node in
                                selectRow(node).padding(.leading,indentation(node))
                            }
                        }
                        .font(.caption)
                        .padding(.vertical,8)
                    }.padding(.horizontal,8)
                }.frame(minWidth:200, idealWidth:250)
                ScrollView {
                    if let node = model.nodes.first(where: { $0.id == selection }) {
                        let identity = PanoramaEntryBuilder.identityResolution(for: node)
                        VStack(alignment:.leading,spacing:8) {
                            Text(node.name).font(.headline)
                            Text("\(node.className) · \(node.plane) · Registry ID \(node.id)").font(.caption).textSelection(.enabled)
                            Text(L10n.t(
                                "上游节点：\(node.parentID.map(String.init) ?? "未知") · 物理端口待确认"))
                                .font(.caption)
                            Text(L10n.t(mainPortCorrelationText(for: node)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            if let identity {
                                let a = identity.commonANumbers.isEmpty
                                    ? "未读取"
                                    : identity.commonANumbers.joined(separator: " / ")
                                let year = identity.commonYears.count == 1
                                    ? String(identity.commonYears[0])
                                    : "未读取"
                                Text(L10n.t(
                                    "Mac 身份：\(a) · \(year) · \(identityStateText(identity.state))"))
                                    .font(.caption).foregroundStyle(.primary)
                                if let category = identity.commonCategory {
                                    Text(L10n.t(
                                        "类别：\(categoryText(category))"))
                                        .font(.caption)
                                }
                                if let series = identity.commonSeries {
                                    Text(L10n.t("系列：\(series)")).font(.caption)
                                }
                                if let size = identity.commonSizeLabel {
                                    Text(L10n.t("尺寸：\(size)")).font(.caption)
                                }
                                if let chip = identity.commonChip {
                                    Text(L10n.t("芯片/SoC：\(chip)")).font(.caption)
                                }
                                if !identity.modelIdentifiers.isEmpty {
                                    Text(L10n.t(
                                        "机型标识符：\(identity.modelIdentifiers.joined(separator: " / "))"))
                                        .font(.caption).textSelection(.enabled)
                                }
                                if !identity.sourceSummary.isEmpty {
                                    Text(L10n.t(
                                        "身份来源：\(identity.sourceSummary.joined(separator: "；"))"))
                                        .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                            ForEach([("厂商", "USB Vendor Name"), ("产品", "USB Product Name"), ("VID", "idVendor"), ("PID", "idProduct"), ("序列号", "USB Serial Number"), ("设备类别", "bDeviceClass"), ("子类", "bDeviceSubClass"), ("协议", "bDeviceProtocol"), ("USB 版本原值", "bcdUSB"), ("设备版本原值", "bcdDevice"), ("USB location", "locationID")], id:\.1) { title, key in
                                if let v = node.properties[key] {
                                    Text(L10n.t(
                                        "\(title)：\(String(describing:v))"))
                                        .font(.caption)
                                        .textSelection(.enabled)
                                }
                            }
                            if let value = PanoramaClassifier.speedLabel(properties:node.properties) { Text(value).font(.caption) }
                            if let statistics = PanoramaUSBRootStatistics.read(from: node) {
                                let rows = PanoramaUSBStatisticsPresentation.rows(for: statistics)
                                if !rows.isEmpty {
                                    DisclosureGroup(
                                        L10n.t("USB 根端口原始统计")) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            ForEach(rows) { row in
                                                Text(L10n.t(
                                                    "\(row.name)：\(row.value)"))
                                                    .font(.system(.caption, design: .monospaced))
                                                    .textSelection(.enabled)
                                            }
                                        }
                                    }
                                    .font(.caption)
                                }
                            }
                            if node.kind == .cable {
                                Text(L10n.t(
                                    PanoramaClassifier.cableSummary(
                                        properties: node.properties)))
                                    .font(.caption)
                            }
                            if node.kind == .cable, let cable = PanoramaPD.decodeCable(properties:node.properties) {
                                Text(L10n.t(
                                    String(format:"线材自报 VID 0x%04X · PID 0x%04X · bcdDevice 0x%04X",cable.vendorID,cable.productID,cable.productVersion)))
                                    .font(.caption)
                                    .textSelection(.enabled)
                                Text(L10n.t(
                                    "线材自报：\(cable.maxCurrentAmps.map { "\($0) A" } ?? "电流未知") · \(cable.maxVoltageVolts.map { "\($0) V" } ?? "电压未知") · \(cable.speedDescription ?? "速率编码 \(cable.speedCode)，待确认")"))
                                    .font(.caption)
                            }
                            if node.kind == .power {
                                Text(L10n.t(
                                    PanoramaClassifier.powerSummary(
                                        properties: node.properties)))
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                            Text(L10n.t(
                                "E-Marker / PD：仅显示系统登记的原始属性；无数据为未知，供电参数不等于实时功耗。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            DisclosureGroup(L10n.t("原始只读属性")) { Text(String(describing:PanoramaReader.serializable(node.properties))).font(.system(.caption,design:.monospaced)).textSelection(.enabled) }
                        }.frame(maxWidth:.infinity,alignment:.leading).padding()
                    } else { Text(L10n.t("选择左侧节点查看系统记录。")).foregroundStyle(.secondary).padding() }
                    DisclosureGroup(L10n.t("Thunderbolt / USB4 系统报告")) { Text(model.thunderbolt).font(.system(.caption,design:.monospaced)).textSelection(.enabled) }.padding()
                }.frame(minWidth:300)
            }
        }.padding(isEmbedded ? 12 : 18)
            .frame(
                minWidth: isEmbedded ? 0 : 550,
                minHeight: isEmbedded ? 0 : 580)
            .onAppear {
                if model.updated == nil { model.refreshUSBOnly() }
            }
            .onChange(of: model.updated) { _, _ in
                if selection == nil {
                    selection = projection.primaryEntries.first?.nodeID
                        ?? projection.unownedAttachments.first?.nodeID
                }
            }
    }
    @ViewBuilder private func nodeRow(_ node: PanoramaNode) -> some View {
        VStack(alignment:.leading) {
            Text(node.name)
            if let n = node.properties["PortNumber"] as? NSNumber, let connected = node.properties["ConnectionActive"] as? Bool {
                Text(L10n.t(
                    "系统端口 \(n)：\(connected ? "系统报告已连接" : "系统报告未连接") · 物理位置待确认"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else { Text("\(node.kind.rawValue) · \(node.id)").font(.caption2).foregroundStyle(.secondary) }
        }
    }
    private func selectRow(_ node:PanoramaNode) -> some View {
        Button {
            onUserSelection?()
            selection = node.id
        } label: {
            nodeRow(node).frame(maxWidth:.infinity,alignment:.leading).padding(6)
                .background(selection == node.id ? Color.accentColor.opacity(0.22) : Color.clear)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(node.name)，\(node.kind.rawValue)")
    }

    private func selectEntry(_ entry: PanoramaDisplayEntry) -> some View {
        Button {
            onUserSelection?()
            selection = entry.nodeID
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: entry.icon)
                    .frame(width: 16)
                    .foregroundStyle(selection == entry.nodeID ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 12, weight: selection == entry.nodeID ? .semibold : .regular))
                        .lineLimit(2)
                    Text(entry.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selection == entry.nodeID ? Color.accentColor.opacity(0.16) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.title)，\(entry.subtitle)")
    }

    private func identityStateText(_ state: MacIdentityState) -> String {
        switch state {
        case .confirmedCurrent: return "确定"
        case .uniqueCurrentMatch: return "唯一匹配"
        case .candidates: return "候选"
        case .conflict: return "冲突"
        case .unknown: return "未知"
        case .historicalHintOnly: return "仅历史提示"
        }
    }

    private func categoryText(_ category: MacDeviceCategory) -> String {
        switch category {
        case .notebook: return "笔记本"
        case .desktop: return "台式机"
        case .unknown: return "未知"
        }
    }

    private func mainPortCorrelationText(for node: PanoramaNode) -> String {
        guard [.device, .hub].contains(node.kind),
              let rawLocation = node.properties["locationID"] else {
            return "主界面只读关联：不适用（该节点没有已证实的 USB location）"
        }
        let raw = String(describing: rawLocation)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let location: String
        if raw.lowercased().hasPrefix("0x"),
           let value = Int(raw.dropFirst(2), radix: 16) {
            location = String(format: "%08X", value)
        } else {
            location = raw.uppercased()
        }
        let matches = device.observedDevices.filter {
            $0.locationID.caseInsensitiveCompare(location) == .orderedSame
        }
        if matches.isEmpty {
            return "主界面只读关联：未找到相同 USB location 的当前观察"
        }
        let keys = Set(matches.compactMap { device.observedPortKey(for: $0) })
        guard keys.count == 1, let key = keys.first,
              let live = device.livePorts.first(where: { $0.id == key }) else {
            return "主界面只读关联：发现相同 location，但端口归属不唯一，保持未知"
        }
        return "主界面只读关联：USB location 与\(device.label(for: live))一致（不改变设备控制目标）"
    }
}

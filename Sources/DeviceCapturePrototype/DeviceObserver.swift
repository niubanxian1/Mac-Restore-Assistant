import Foundation

enum ObservedDeviceMode: String, Hashable {
    case dfu
    case recovery
    /// A normal, booted Apple host enumerated over USB. It is not DFU.
    case connected
    case unknown
    var title: String {
        switch self {
        case .dfu: return "DFU"
        case .recovery: return "Recovery"
        case .connected: return "已连接"
        case .unknown: return "未知模式"
        }
    }
}

struct ObservedDevice: Identifiable, Hashable {
    let id: String            // ECID when trustworthy, else USB location
    let ecid: String?
    let mode: ObservedDeviceMode
    let locationID: String
    let product: String
    let serial: String
    /// Only a real machine identifier from an explicit descriptor field or a
    /// matched read-only identity source. Never the USB product name and never
    /// the host calibration record.
    var modelIdentifier: String? = nil
    /// Where a resolved model came from, for the detail view.
    var modelSource: String? = nil
    var vendorID: Int? = nil
    var productID: Int? = nil
    /// Raw negotiated-link field (`UsbLinkSpeed`, bits per second), if read.
    var linkSpeedBps: Int? = nil
    /// Raw descriptor enums; kept as read, never translated into a speed claim.
    var deviceSpeed: Int? = nil
    var usbSpeed: Int? = nil
    var usbPortType: Int? = nil
    /// Nearest IOUSBHostDevice ancestor whose name contains "Hub".
    var hubName: String? = nil
    /// Read-only USB topology path (hub chain → this node).
    var topologyPath: String? = nil

    var displayIdentity: String {
        if let ecid, !ecid.isEmpty { return "Mac · \(mode.title) · ECID \(ecid)" }
        return "Mac · \(mode.title)"
    }
}

enum ObservedDeviceReader {
    private static let appleVendorID = 1452
    private static let iOSDFUProductID = 0x1227
    private static let macDFUProductID = 0x1281
    private static let macDebugUSBProductID = 0x1881
    private static let macRecoveryProductIDs: Set<Int> = [0x1280, 0x1282, 0x1283]

    /// Read-only USB observation. No device commands, no capture start.
    static func read() -> [ObservedDevice] {
        if case .success(let devices) = readResult() { return devices }
        return []
    }

    /// Distinguishes a failed ioreg spawn/exit from a successful empty observation.
    static func readResult() -> ObservedDeviceReadResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        p.arguments = ["-p", "IOUSB", "-l", "-w0"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return .failed("spawn: \(error.localizedDescription)") }
        // Drain the pipe before waiting: `ioreg -l` can exceed the pipe buffer.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            return .failed("exit \(p.terminationStatus)")
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        return .success(parse(text))
    }

    /// Parse `ioreg -p IOUSB -l -w0` text.
    ///
    /// T545 only started a block at `Apple Mobile Device`, so a normal Mac
    /// node whose product name is `Mac` disappeared before mode/identity were
    /// read. Every IOUSBHostDevice node is now considered, then filtered by
    /// Apple vendor plus DFU/Recovery/Mac evidence. A generic Mac node is
    /// `connected`, never `dfu`.
    static func parse(_ text: String) -> [ObservedDevice] {
        let nodes = parseNodes(text)
        var result: [ObservedDevice] = []
        for (index, node) in nodes.enumerated() {
            let product = node.value("kUSBProductString")
                ?? node.value("USB Product Name") ?? ""
            let vendor = node.intValue("idVendor")
            let productID = node.intValue("idProduct")
            let deviceType = node.value("deviceType")
                ?? node.value("ProductType")
                ?? node.value("model")
            let modelIdentifier = TargetModelCatalog.identifier(from: deviceType)
                ?? TargetModelCatalog.identifier(from: product)
            let looksLikeMac = isMacDescriptor(product: product,
                                               deviceType: deviceType,
                                               modelIdentifier: modelIdentifier)
            guard let mode = classify(vendor: vendor,
                                      productID: productID,
                                      product: product,
                                      looksLikeMac: looksLikeMac) else { continue }

            let serial = node.value("USB Serial Number")
                ?? node.value("kUSBSerialNumberString") ?? ""
            let identity = ECIDIdentity.fromUSB(
                serial: serial,
                numericProperty: node.value("UsbAppleDeviceECID"))
            let ecid = identity?.canonicalHex
            let location = node.value("locationID").flatMap(locationText) ?? ""
            let deviceID = ecid.map { "ecid:\($0)" } ?? "usb:\(location):\(mode.rawValue)"
            let hub = hubName(nodes: nodes, index: index)
            let path = topologyPath(nodes: nodes, index: index)
            result.append(ObservedDevice(
                id: deviceID,
                ecid: ecid,
                mode: mode,
                locationID: location,
                product: product,
                serial: serial,
                modelIdentifier: modelIdentifier,
                vendorID: vendor,
                productID: productID,
                linkSpeedBps: node.intValue("UsbLinkSpeed"),
                deviceSpeed: node.intValue("Device Speed"),
                usbSpeed: node.intValue("USBSpeed"),
                usbPortType: node.intValue("USBPortType"),
                hubName: hub,
                topologyPath: path))
        }
        return result
    }

    // MARK: - IOUSB tree

    private struct USBNode {
        var header: String
        var name: String
        var indent: Int
        var className: String
        var properties: [String: String] = [:]
        var parent: Int?

        func value(_ key: String) -> String? {
            guard var value = properties[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            if value.hasPrefix("\"") {
                value.removeFirst()
                if let end = value.firstIndex(of: "\"") { value = String(value[..<end]) }
            }
            return value.isEmpty ? nil : value
        }

        func intValue(_ key: String) -> Int? {
            guard let value = value(key) else { return nil }
            if value.lowercased().hasPrefix("0x") {
                return Int(value.dropFirst(2), radix: 16)
            }
            return Int(value)
        }
    }

    private static func parseNodes(_ text: String) -> [USBNode] {
        var nodes: [USBNode] = []
        var stack: [Int] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.drop(while: { $0 == " " || $0 == "|" })
            if trimmed.hasPrefix("+-o ") {
                let indent = line.prefix(while: { $0 != "+" }).count
                while let last = stack.last, nodes[last].indent >= indent {
                    stack.removeLast()
                }
                let parent = stack.last
                let header = String(trimmed)
                let node = USBNode(header: header,
                                   name: nodeName(header),
                                   indent: indent,
                                   className: nodeClass(header),
                                   parent: parent)
                nodes.append(node)
                stack.append(nodes.count - 1)
            } else if !nodes.isEmpty, let pair = propertyPair(line) {
                nodes[nodes.count - 1].properties[pair.0] = pair.1
            }
        }
        return nodes
    }

    private static func nodeName(_ header: String) -> String {
        var name = header
        if name.hasPrefix("+-o ") { name.removeFirst(4) }
        if let at = name.firstIndex(of: "@") { name = String(name[..<at]) }
        if let range = name.range(of: "  <class") { name = String(name[..<range.lowerBound]) }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nodeClass(_ header: String) -> String {
        guard let range = header.range(of: "<class "),
              let end = header[range.upperBound...].firstIndex(where: { $0 == "," || $0 == ">" }) else {
            return ""
        }
        return String(header[range.upperBound..<end]).trimmingCharacters(in: .whitespaces)
    }

    private static func propertyPair(_ line: String) -> (String, String)? {
        guard let first = line.firstIndex(of: "\""),
              let second = line[line.index(after: first)...].firstIndex(of: "\"") else {
            return nil
        }
        let key = String(line[line.index(after: first)..<second])
        let after = line[line.index(after: second)...]
        guard let equals = after.range(of: "=") else { return nil }
        let value = after[equals.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (key, value)
    }

    private static func hubName(nodes: [USBNode], index: Int) -> String? {
        var current = nodes[index].parent
        while let i = current {
            if nodes[i].name.localizedCaseInsensitiveContains("hub")
                || nodes[i].className.localizedCaseInsensitiveContains("Hub") {
                return nodes[i].name
            }
            current = nodes[i].parent
        }
        return nil
    }

    private static func topologyPath(nodes: [USBNode], index: Int) -> String? {
        var names: [String] = []
        var current = nodes[index].parent
        while let i = current {
            if nodes[i].className.contains("IOUSBHostDevice") || !nodes[i].name.isEmpty {
                names.append(nodes[i].name)
            }
            current = nodes[i].parent
        }
        names.reverse()
        names.append(nodes[index].name)
        let path = names.filter { !$0.isEmpty }.joined(separator: " → ")
        return path.isEmpty ? nil : path
    }

    /// Old-project `strict_usb_mode` semantics, extended with `connected`
    /// for a normal Mac. Returns nil when the node is not a target-class
    /// Apple device this app should surface.
    private static func classify(vendor: Int?,
                                 productID: Int?,
                                 product: String,
                                 looksLikeMac: Bool) -> ObservedDeviceMode? {
        if let vendor, vendor != appleVendorID { return nil }
        let name = product.lowercased()
        if name.contains("dfu") && name.contains("mode") { return .dfu }
        if name.contains("recovery") && name.contains("mode") { return .recovery }
        if let productID {
            if productID == iOSDFUProductID { return .dfu }
            if productID == macDFUProductID { return looksLikeMac ? .dfu : .unknown }
            // A normal-boot Apple Silicon Mac can enumerate as "Debug USB"
            // instead of "Mac" on some host ports. Its model still comes only
            // from a unique cfgutil location hint, never from this product name.
            if productID == macDebugUSBProductID { return .connected }
            if macRecoveryProductIDs.contains(productID) { return .recovery }
        }
        if vendor == appleVendorID, name.contains("mac") { return .connected }
        if name.contains("apple mobile device") { return .unknown }
        return nil
    }

    private static func isMacDescriptor(product: String,
                                        deviceType: String?,
                                        modelIdentifier: String?) -> Bool {
        if modelIdentifier != nil { return true }
        let text = [product, deviceType ?? ""].joined(separator: " ").lowercased()
        return ["macbook", "imac", "mac mini", "mac studio", "mac pro", "mac"]
            .contains { text.contains($0) }
    }

    private static func locationText(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let number = Int(value) {
            return String(format: "%08X", number)
        }
        if value.lowercased().hasPrefix("0x"),
           let number = Int(value.dropFirst(2), radix: 16) {
            return String(format: "%08X", number)
        }
        return nil
    }
}


struct ObservedDeviceCard: Identifiable, Hashable {
    let id: String
    var device: ObservedDevice
    var portKey: String?
    var portLabel: String?
    var lastSeen: Date
    var isConnected: Bool
    var isSample: Bool = false
}

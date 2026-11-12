import Foundation
import MRAHelperCore

/// Read-only link facts reported by the port controller (`AppleHPM` /
/// `AppleTCControllerType*`). Every field is optional because a missing
/// property is unknown, not false.
struct HostPortLink: Hashable {
    var connectionActive: Bool? = nil
    var connectionCount: Int? = nil
    var connectType: Int? = nil
    var connectTypePublished: Int? = nil
    var superSpeedActive: Bool? = nil
    var activeCable: Bool? = nil
    var opticalCable: Bool? = nil
    var powerMode: Int? = nil
    var transportsProvisioned: [String] = []
    var transportsSupported: [String] = []
    var transportsActive: [String] = []
    var cableSpeed: String? = nil
    var dataRateDescription: String? = nil
    var linkRateDescription: String? = nil
    var superspeedSignaling: String? = nil

    /// Controller-confirmed connection. A published/active USB connect type
    /// or a non-zero connection count is enough; transport flags alone are
    /// not treated as a speed or cable claim.
    var isConnected: Bool {
        if connectionActive == false { return false }
        if let count = connectionCount, count > 0 { return true }
        if let published = connectTypePublished, published != 0 { return true }
        if let type = connectType, type != 0 { return true }
        if !transportsProvisioned.isEmpty,
           transportsProvisioned.contains(where: { $0.caseInsensitiveCompare("CC") != .orderedSame }) {
            return true
        }
        return false
    }

    var cableIdentityText: String? {
        var parts: [String] = []
        if let activeCable { parts.append("Active Cable：\(L10n.yesNo(activeCable))") }
        if let opticalCable { parts.append("Optical Cable：\(L10n.yesNo(opticalCable))") }
        return parts.isEmpty ? nil : parts.joined(separator: "；")
    }
}

struct LiveHostPort: Identifiable, Hashable {
    let controller: String
    let portNumber: Int
    let rid: Int
    /// Controller link facts from the same `ioreg -r -c AppleHPM -l` read.
    var link: HostPortLink?
    var id: String { "\(controller):\(portNumber)" }
    var rawTitle: String { "控制器 \(controller) · 端口 \(portNumber) · RID \(rid)" }

    init(controller: String, portNumber: Int, rid: Int, link: HostPortLink? = nil) {
        self.controller = controller
        self.portNumber = portNumber
        self.rid = rid
        self.link = link
    }

    init(_ parsed: ParsedHostPort, link: HostPortLink? = nil) {
        self.init(controller: parsed.controller, portNumber: parsed.portNumber,
                  rid: parsed.rid, link: link)
    }
}

enum HostPortReader {
    static func read() -> [LiveHostPort] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        p.arguments = ["-r", "-c", "AppleHPM", "-l"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return [] }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return [] }
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return parse(text)
    }

    /// Parse `ioreg -r -c AppleHPM -l` text. The triplet still comes from the
    /// shared parser; link facts are attached from the same text (no extra
    /// process, no extra polling source).
    static func parse(_ text: String) -> [LiveHostPort] {
        let links = HostPortLinkTextParser.parse(text)
        return HostPortTextParser.parse(text).map { parsed in
            let key = HostPortLinkTextParser.key(controller: parsed.controller,
                                                 portNumber: parsed.portNumber)
            return LiveHostPort(parsed, link: links[key])
        }
    }
}

/// Parses the controller-level link properties for each `Port-USB-C@N`.
/// Only reads properties; it never opens a user client or sends a VDM.
enum HostPortLinkTextParser {
    static func key(controller: String, portNumber: Int) -> String {
        "\(controller.lowercased()):\(portNumber)"
    }

    static func parse(_ text: String) -> [String: HostPortLink] {
        var result: [String: HostPortLink] = [:]
        var controller = ""
        var rid: Int?
        var portNumber: Int?
        var properties: [String: String] = [:]
        var inPort = false

        func flush() {
            defer {
                properties = [:]
                portNumber = nil
                inPort = false
            }
            guard inPort, !controller.isEmpty, let portNumber else { return }
            result[key(controller: controller, portNumber: portNumber)] =
                makeLink(properties: properties, rid: rid)
        }

        for line in text.split(separator: "\n").map(String.init) {
            if line.contains("+-o AppleHPM") {
                let isChild = line.contains("AppleHPMDevice") || line.contains("AppleHPMUserClient")
                if isChild { continue }
                flush()
                if let range = line.range(of: "id 0x") {
                    controller = String(line[range.upperBound...].prefix { $0 != "," && $0 != " " })
                }
                rid = nil
                continue
            }
            if line.contains("+-o Port-USB-C@") {
                flush()
                inPort = true
                portNumber = parsePortNumberFromHeader(line)
                continue
            }
            if line.contains("+-o ") {
                // A child node ends the port's own property block.
                flush()
                continue
            }
            guard inPort else {
                if let range = line.range(of: "\"RID\" = ") {
                    rid = Int(line[range.upperBound...].prefix { $0.isNumber })
                }
                continue
            }
            guard let (key, value) = property(line) else { continue }
            properties[key] = value
            if key == "PortNumber", let number = Int(value) {
                portNumber = number
            }
        }
        flush()
        return result
    }

    private static func makeLink(properties: [String: String], rid: Int?) -> HostPortLink {
        _ = rid
        return HostPortLink(
            connectionActive: bool(properties["ConnectionActive"]),
            connectionCount: int(properties["ConnectionCount"]),
            connectType: int(properties["IOAccessoryUSBConnectType"]),
            connectTypePublished: int(properties["IOAccessoryUSBConnectTypePublished"]),
            superSpeedActive: bool(properties["IOAccessoryUSBSuperSpeedActive"]),
            activeCable: bool(properties["ActiveCable"]),
            opticalCable: bool(properties["OpticalCable"]),
            powerMode: int(properties["IOAccessoryPowerMode"]),
            transportsProvisioned: array(properties["TransportsProvisioned"]),
            transportsSupported: array(properties["TransportsSupported"]),
            transportsActive: array(properties["TransportsActive"]),
            cableSpeed: text(properties["CableSpeed"]),
            dataRateDescription: text(properties["DataRateDescription"]),
            linkRateDescription: text(properties["LinkRateDescription"]),
            superspeedSignaling: text(properties["SuperSpeedSignalingDescription"]))
    }

    private static func parsePortNumberFromHeader(_ line: String) -> Int? {
        guard let at = line.range(of: "@") else { return nil }
        return Int(line[at.upperBound...].prefix { $0.isNumber })
    }

    private static func property(_ line: String) -> (String, String)? {
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

    private static func text(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        if value.hasPrefix("\"") {
            value.removeFirst()
            if let end = value.firstIndex(of: "\"") { value = String(value[..<end]) }
        }
        return value.isEmpty ? nil : value
    }

    private static func bool(_ raw: String?) -> Bool? {
        guard let value = text(raw)?.lowercased() else { return nil }
        if value == "yes" || value == "true" { return true }
        if value == "no" || value == "false" { return false }
        return nil
    }

    private static func int(_ raw: String?) -> Int? {
        guard let value = text(raw) else { return nil }
        if value.lowercased().hasPrefix("0x") { return Int(value.dropFirst(2), radix: 16) }
        return Int(value)
    }

    private static func array(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        let range = raw.range(of: "(")?.upperBound
        let content = range.map { String(raw[$0...]) } ?? raw
        return content
            .replacingOccurrences(of: ")", with: "")
            .split(separator: ",")
            .compactMap { token -> String? in
                let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                return value.isEmpty ? nil : value
            }
    }
}

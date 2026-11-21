import Foundation

/// One host USB-C port parsed from `ioreg -r -c AppleHPM -l`.
public struct ParsedHostPort: Equatable, Hashable, Sendable {
    public let controller: String
    public let portNumber: Int
    public let rid: Int

    public init(controller: String, portNumber: Int, rid: Int) {
        self.controller = controller
        self.portNumber = portNumber
        self.rid = rid
    }
}

/// Shared App/Helper parser so both send and validate the same triplet.
/// Controller IDs must be the AppleHPM matching service (for example
/// AppleHPMARMI2C), because `IOServiceMatching("AppleHPM")` in the
/// backend only returns those nodes. Child AppleHPMDevice and
/// AppleHPMUserClient registry IDs must not overwrite the controller.
public enum HostPortTextParser {
    public static func parse(_ text: String) -> [ParsedHostPort] {
        var result: [ParsedHostPort] = []
        var controller = ""
        var rid: Int?
        var port: Int?
        func flush() {
            if let rid, let port, !controller.isEmpty {
                result.append(ParsedHostPort(controller: controller, portNumber: port, rid: rid))
            }
            rid = nil
            port = nil
        }
        for line in text.split(separator: "\n").map(String.init) {
            if line.contains("+-o AppleHPM") {
                let isChildNode = line.contains("AppleHPMDevice") || line.contains("AppleHPMUserClient")
                if isChildNode {
                    continue
                }
                flush()
                if let range = line.range(of: "id 0x") {
                    let rest = line[range.upperBound...]
                    controller = String(rest.prefix { $0 != "," && $0 != " " })
                }
                continue
            }
            if let range = line.range(of: "\"RID\" = ") {
                rid = Int(line[range.upperBound...].prefix { $0.isNumber })
            }
            if let range = line.range(of: "\"PortNumber\" = ") {
                port = Int(line[range.upperBound...].prefix { $0.isNumber })
            }
        }
        flush()
        return result.sorted { ($0.controller, $0.portNumber) < ($1.controller, $1.portNumber) }
    }
}

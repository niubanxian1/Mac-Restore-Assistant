import Foundation

/// Normalized Apple ECID identity. Log text is parsed by labeled ECID tokens,
/// never by substring containment.
struct ECIDIdentity: Hashable {
    let value: UInt64

    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isHexDigit }),
              let value = UInt64(cleaned, radix: 16) else { return nil }
        self.value = value
    }

    init?(decimal: String) {
        let cleaned = decimal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isNumber }),
              let value = UInt64(cleaned, radix: 10) else { return nil }
        self.value = value
    }

    init(canonical: String) {
        if let hex = ECIDIdentity(hex: canonical) {
            self = hex
        } else {
            preconditionFailure("invalid canonical ECID")
        }
    }

    var canonicalHex: String {
        String(format: "%016llX", value)
    }

    var canonicalDecimal: String { String(value) }

    static func fromUSB(serial: String, numericProperty: String?) -> ECIDIdentity? {
        // The USB serial field is the authoritative textual form and is hex.
        if let range = serial.range(of: "ECID:", options: .caseInsensitive) {
            let tail = serial[range.upperBound...]
            let token = String(tail.prefix { $0.isHexDigit })
            if let identity = ECIDIdentity(hex: token) { return identity }
        }
        // UsbAppleDeviceECID is numeric/decimal.
        if let numericProperty { return ECIDIdentity(decimal: numericProperty) }
        return nil
    }

    /// Parses only explicitly labeled ECID tokens. A token with 0x or hex
    /// letters is hex; an all-digit token is decimal (including leading zeros).
    static func values(in line: String) -> Set<UInt64> {
        let pattern = #"(?i)\bECID\s*[:=]\s*(0x)?([0-9A-F]{8,20})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        var result = Set<UInt64>()
        for match in regex.matches(in: line, options: [], range: range) {
            let prefix = match.range(at: 1).location != NSNotFound
            guard let tokenRange = Range(match.range(at: 2), in: line) else { continue }
            let token = String(line[tokenRange])
            let value: UInt64?
            if prefix || token.contains(where: { $0.isHexDigit && !$0.isNumber }) {
                value = UInt64(token, radix: 16)
            } else {
                value = UInt64(token, radix: 10)
            }
            if let value { result.insert(value) }
        }
        return result
    }
}

enum ECIDLogAttribution {
    static func line(_ line: String, belongsTo canonicalECID: String) -> Bool {
        guard let identity = ECIDIdentity(hex: canonicalECID) else { return false }
        let values = ECIDIdentity.values(in: line)
        return values.count == 1 && values.contains(identity.value)
    }

    static func unbound(_ lines: [String], knownCanonicalECIDs: [String]) -> [String] {
        let known = Set(knownCanonicalECIDs.compactMap { ECIDIdentity(hex: $0)?.value })
        guard !known.isEmpty else { return lines }
        return lines.filter { line in
            let values = ECIDIdentity.values(in: line)
            if values.isEmpty { return true }
            if values.count > 1 { return true } // multiple identities -> never pick one
            return values.isDisjoint(with: known)
        }
    }
}

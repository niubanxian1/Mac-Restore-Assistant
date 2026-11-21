import Foundation

/// Resolves a read-only USB location to exactly one live AppleHPM port.
/// Matching uses the calibrated location and RID; it never falls back to list
/// order or the currently selected port.
enum PortAssociationResolver {
    static func resolve(locationID: String,
                        calibratedPorts: [PortCalibrationEntry],
                        livePorts: [LiveHostPort]) -> String? {
        let normalized = normalize(locationID)
        guard !normalized.isEmpty else { return nil }
        let locations = calibratedPorts.filter { normalize($0.location) == normalized }
        guard !locations.isEmpty else { return nil }
        var candidates: [LiveHostPort] = []
        for entry in locations {
            guard let rid = Int(entry.rid) else { continue }
            let matches = livePorts.filter { live in
                live.rid == rid
                    && (entry.controller == nil || entry.controller == live.controller)
                    && (entry.portNumber == nil || entry.portNumber == live.portNumber)
            }
            candidates.append(contentsOf: matches)
        }
        let unique = Dictionary(grouping: candidates, by: \.id).compactMap { $0.value.first }
        return unique.count == 1 ? unique[0].id : nil
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "0X", with: "")
            .uppercased()
    }
}

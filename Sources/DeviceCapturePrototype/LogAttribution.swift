import Foundation

// Compatibility facade retained for the UI; implementation lives in
// ECIDNormalization.swift and uses labeled token parsing, not substring search.
enum LogAttribution {
    static func line(_ line: String, belongsTo ecid: String) -> Bool {
        ECIDLogAttribution.line(line, belongsTo: ecid)
    }

    static func unbound(_ lines: [String], knownECIDs: [String]) -> [String] {
        ECIDLogAttribution.unbound(lines, knownCanonicalECIDs: knownECIDs)
    }
}

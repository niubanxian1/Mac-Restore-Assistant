import Foundation

/// P0-N1 late attribution. Never auto-claims REAL_* . Production policy remains fail-closed.
public enum LateAttributionEngine {
    public enum Decision: String, Codable, Sendable {
        case unbound = "UNBOUND"
        case candidatePathFromWroteLine = "CANDIDATE_PATH_FROM_WROTE_LINE"
        case associatedSingleECIDSession = "ASSOCIATED_SINGLE_ECID_SESSION"
        case conflict = "CONFLICT"
        case boundSynthSessionUUID = "BOUND_SYNTH_SESSION_UUID"
    }

    public struct Result: Codable, Sendable, Equatable {
        public var decision: Decision
        public var ecid: String?
        public var note: String
        public var realConfiguratorBodyCaptured: String
        public var realMcdp29xxBodyCaptured: String
    }

    public static func attribute(
        sourceDirName: String,
        wroteLinePaths: [String] = [],
        sessionLogExcerpt: String? = nil,
        synthSessionUUID: UUID? = nil
    ) -> Result {
        if let sid = synthSessionUUID, sourceDirName.uppercased().contains(sid.uuidString.uppercased()) {
            return Result(decision: .boundSynthSessionUUID, ecid: nil, note: "test-only-synth-uuid", realConfiguratorBodyCaptured: "NO", realMcdp29xxBodyCaptured: "NO")
        }
        let pathHit = wroteLinePaths.contains { sourceDirName.contains(($0 as NSString).lastPathComponent) || $0.contains(sourceDirName) }
        var ecids: Set<String> = []
        if let text = sessionLogExcerpt {
            let re = try? NSRegularExpression(pattern: #"ECID\s*[=:]\s*(0x[0-9A-Fa-f]+)"#)
            let ns = text as NSString
            re?.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m, m.numberOfRanges > 1 else { return }
                ecids.insert(ns.substring(with: m.range(at: 1)).lowercased())
            }
        }
        if ecids.count >= 2 {
            return Result(decision: .conflict, ecid: nil, note: "multi-ecid", realConfiguratorBodyCaptured: "NO", realMcdp29xxBodyCaptured: "NO")
        }
        if ecids.count == 1 && pathHit {
            return Result(decision: .associatedSingleECIDSession, ecid: ecids.first, note: "conditional-offline-only", realConfiguratorBodyCaptured: "NO", realMcdp29xxBodyCaptured: "NO")
        }
        if pathHit {
            return Result(decision: .candidatePathFromWroteLine, ecid: nil, note: "path-only", realConfiguratorBodyCaptured: "NO", realMcdp29xxBodyCaptured: "NO")
        }
        return Result(decision: .unbound, ecid: nil, note: "no-authority", realConfiguratorBodyCaptured: "NO", realMcdp29xxBodyCaptured: "NO")
    }
}

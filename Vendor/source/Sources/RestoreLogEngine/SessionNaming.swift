import Foundation

public enum SessionNamingStyle: String, CaseIterable, Sendable {
    case automaticConcise = "AUTO_CONCISE"
    case automaticProfessional = "AUTO_PROFESSIONAL"
    case custom = "CUSTOM"

    public var displayName: String {
        switch self {
        case .automaticConcise: return "自动简洁"
        case .automaticProfessional: return "自动专业"
        case .custom: return "自定义"
        }
    }
}

public struct SessionNamingEvidence: Sendable, Equatable {
    public var modelIdentifiers: Set<String>
    public var ecids: Set<String>
    public var terminalKind: DiagnosticLogBuilder.RestoreTerminalKind
    public var marketingModel: String?

    public init(
        modelIdentifiers: Set<String> = [],
        ecids: Set<String> = [],
        terminalKind: DiagnosticLogBuilder.RestoreTerminalKind = .unknown,
        marketingModel: String? = nil
    ) {
        self.modelIdentifiers = modelIdentifiers
        self.ecids = ecids
        self.terminalKind = terminalKind
        self.marketingModel = marketingModel
    }

    public var modelIdentifier: String? { modelIdentifiers.count == 1 ? modelIdentifiers.first : nil }
    public var ecid: String? { ecids.count == 1 ? ecids.first : nil }
    public var conflict: Bool { modelIdentifiers.count > 1 || ecids.count > 1 }
}

public enum SessionNamingReader {
    /// Verified mappings only. Unknown identifiers remain Model Identifiers.
    public static let verifiedMarketingModels: [String: String] = [
        "MacBookPro18,2": "A2485"
    ]

    public static func read(rawURL: URL, includeTerminal: Bool = true) -> SessionNamingEvidence {
        guard let handle = try? FileHandle(forReadingFrom: rawURL) else {
            return SessionNamingEvidence()
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        var firstText = ""
        var tailText = ""
        do {
            try handle.seek(toOffset: 0)
            firstText = String(decoding: try handle.read(upToCount: 4 * 1024 * 1024) ?? Data(), as: UTF8.self)
            let tailWindow: UInt64 = 1 * 1024 * 1024
            if size > tailWindow {
                try handle.seek(toOffset: size - tailWindow)
                tailText = String(decoding: try handle.readToEnd() ?? Data(), as: UTF8.self)
            } else {
                tailText = firstText
            }
        } catch {
            return SessionNamingEvidence()
        }
        let text = firstText + "\n" + tailText
        let models = Set(matches(in: text, pattern: #"\b(Mac(?:Book(?:Pro|Air)|mini|iMac)\d{1,2},\d{1,2})\b"#))
        let ecids = Set(matches(in: text, pattern: #"(?i)(?<![A-Za-z0-9_])ECID\s*[:=]\s*((?:0x)?[0-9A-F]{8,20})"#).map(normalizeECID))
        // Terminal markers are streamed over the whole raw in bounded chunks.
        // A tail-only probe misses a success marker earlier in a large log;
        // this scanner keeps only marker offsets, not file contents.
        let terminal = includeTerminal ? scanTerminal(rawURL: rawURL) : .unknown
        let marketing = models.count == 1 ? verifiedMarketingModels[models.first!] : nil
        return SessionNamingEvidence(
            modelIdentifiers: models,
            ecids: ecids,
            terminalKind: terminal,
            marketingModel: marketing
        )
    }

    public static func terminalKind(rawURL: URL) -> DiagnosticLogBuilder.RestoreTerminalKind {
        scanTerminal(rawURL: rawURL)
    }

    /// Lightweight, bounded terminal marker scan for naming only. Full
    /// DiagnosticLogBuilder classification remains authoritative for analysis.
    private static func scanTerminal(rawURL: URL) -> DiagnosticLogBuilder.RestoreTerminalKind {
        let markers: [(Data, DiagnosticLogBuilder.RestoreTerminalKind)] = [
            (Data("restore succeeded".utf8), .success),
            (Data("Restore succeeded".utf8), .success),
            (Data("restore complete".utf8), .success),
            (Data("Restore complete".utf8), .success),
            (Data("restore completed".utf8), .success),
            (Data("Restore completed".utf8), .success),
            (Data("status:success".utf8), .success),
            (Data("restore failed".utf8), .failure),
            (Data("Restore failed".utf8), .failure),
            (Data("failed to restore".utf8), .failure),
            (Data("Failed to restore".utf8), .failure),
            (Data("amrestoreerrordomain".utf8), .failure),
            (Data("AMRestoreErrorDomain".utf8), .failure),
            (Data("ramroderrordomain".utf8), .failure),
            (Data("RamrodErrorDomain".utf8), .failure),
            (Data("status:error".utf8), .failure),
            (Data("retry restore".utf8), .retry),
            (Data("restore retry".utf8), .retry),
            (Data("restore conflict".utf8), .conflict)
        ]
        guard let handle = try? FileHandle(forReadingFrom: rawURL) else { return .unknown }
        defer { try? handle.close() }
        var best: (offset: Int, kind: DiagnosticLogBuilder.RestoreTerminalKind)?
        var consumed = 0
        var overlap = Data()
        while true {
            let chunk = (try? handle.read(upToCount: 4 * 1024 * 1024)) ?? Data()
            if chunk.isEmpty { break }
            var data = overlap
            data.append(chunk)
            for (needle, kind) in markers {
                if let range = data.range(of: needle, options: [.backwards]) {
                    let offset = consumed - overlap.count + range.lowerBound
                    if best == nil || offset >= best!.offset { best = (offset, kind) }
                }
            }
            let keep = min(64, data.count)
            overlap = Data(data.suffix(keep))
            consumed += chunk.count
        }
        return best?.kind ?? .unknown
    }

    public static func makeName(
        style: SessionNamingStyle,
        evidence: SessionNamingEvidence,
        date: Date = Date()
    ) -> String {
        let model = evidence.modelIdentifier ?? "UNKNOWN"
        let ecid = evidence.ecid ?? "UNKNOWN"
        let ecidSuffix = evidence.ecid.map { String($0.suffix(6)).uppercased() }
        let device = evidence.marketingModel
            ?? evidence.modelIdentifier
            ?? ecidSuffix.map { "ECID-\($0)" }
            ?? "Session"
        let status = statusLabel(evidence.terminalKind)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(format: "%04d%02d%02d-%02d%02d%02d",
                           c.year ?? 0, c.month ?? 0, c.day ?? 0,
                           c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        let raw: String
        switch style {
        case .automaticConcise:
            raw = "\(device)-Restore-\(status)-\(stamp)"
        case .automaticProfessional:
            raw = "\(device)_\(model)_\(ecid)-Restore-\(status)_\(stamp)"
        case .custom:
            raw = "\(device)-Restore-\(status)-\(stamp)"
        }
        return ExportNaming.sanitizedBase(raw)
    }

    public static func normalizeECID(_ raw: String) -> String {
        var value = raw.lowercased()
        if value.hasPrefix("0x") { value.removeFirst(2) }
        while value.count > 1 && value.first == "0" { value.removeFirst() }
        return "0x" + value.uppercased()
    }

    public static func statusLabel(_ kind: DiagnosticLogBuilder.RestoreTerminalKind) -> String {
        switch kind {
        case .success: return "Success"
        case .failure: return "Failure"
        case .retry: return "Retry"
        case .conflict: return "Conflict"
        case .unverified: return "Unverified"
        case .unknown, .none: return "Unknown"
        }
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }
}

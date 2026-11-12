import Foundation

/// Naming and source facts for a saved capture session. This type does not
/// classify restore outcomes; the caller supplies the existing
/// DiagnosticLogBuilder terminal kind.
public struct SessionPackageNamingContext: Sendable, Equatable {
    public var date: String
    public var time: String
    public var model: String
    public var ecid: String
    public var restoreStatus: String
    public var sessionID: String
    public var sessionIDShort: String

    public init(
        date: String,
        time: String,
        model: String,
        ecid: String,
        restoreStatus: String,
        sessionID: String,
        sessionIDShort: String = ""
    ) {
        self.date = date
        self.time = time
        self.model = model
        self.ecid = ecid
        self.restoreStatus = restoreStatus
        self.sessionID = sessionID
        self.sessionIDShort = sessionIDShort
    }
}

public enum SessionPackageNaming {
    public static let defaultTemplate = "RLM-Evidence-{date}-{time}-{model}-{status}"
    public static let rawDefaultTemplate = "RLM-Evidence-Session-{session_id_short}"
    public static let fallback = "UNKNOWN"

    /// Supported fields are deliberately small, deterministic, and previewable.
    /// Unknown/empty values use `UNKNOWN`; they are never silently omitted.
    public static func expand(template: String, context: SessionPackageNamingContext) -> String {
        let effective = template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultTemplate
            : template
        let values: [String: String] = [
            "date": nonEmpty(context.date),
            "time": nonEmpty(context.time),
            "model": nonEmpty(context.model),
            "ecid": nonEmpty(context.ecid),
            "status": nonEmpty(context.restoreStatus),
            "session_id": nonEmpty(context.sessionID),
            "session_id_short": nonEmpty(context.sessionIDShort.isEmpty
                ? String(context.sessionID.prefix(8))
                : context.sessionIDShort)
        ]
        var result = effective
        for key in ["date", "time", "model", "ecid", "status", "session_id", "session_id_short"] {
            result = result.replacingOccurrences(of: "{\(key)}", with: values[key] ?? fallback)
        }
        // Any unsupported placeholder is an explicit safe fallback, never a
        // literal filename fragment that might confuse the operator.
        if let unknown = try? NSRegularExpression(pattern: #"\{[^}]+\}"#) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = unknown.stringByReplacingMatches(in: result, range: range, withTemplate: fallback)
        }
        // Do not allow a template to escape the chosen parent directory.
        result = result.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return cleaned.isEmpty ? "RLM-Evidence-\(fallback)" : String(cleaned.prefix(180))
    }

    private static func nonEmpty(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

public struct SessionPackageSource: Sendable, Equatable {
    public let record: SessionRecord
    public let directory: URL
    public let rawURL: URL
    public let diagnosticURL: URL
    public let sessionJSONURL: URL
    public let preCaptureURL: URL

    public init(record: SessionRecord, directory: URL) {
        self.record = record
        self.directory = directory
        self.rawURL = directory.appendingPathComponent("restore.log")
        self.diagnosticURL = directory.appendingPathComponent("diagnostic.log")
        self.sessionJSONURL = directory.appendingPathComponent("session.json")
        self.preCaptureURL = directory.appendingPathComponent("pre-capture-context.log")
    }
}

public enum SessionEvidencePackage {
    /// The frozen display name is the only default package base name. Old
    /// sessions without it fall back to a safe Session-ID-derived name.
    public static func displayName(for record: SessionRecord) -> String {
        if let stored = record.sessionDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty {
            return ExportNaming.sanitizedBase(stored)
        }
        return "Session-" + ExportNaming.shortSessionID(record.sessionID)
    }

    public static func zipName(for record: SessionRecord) -> String {
        displayName(for: record) + ".zip"
    }

    public static func source(record: SessionRecord, directory: URL) -> SessionPackageSource {
        SessionPackageSource(record: record, directory: directory)
    }

    /// Convert a saved record into the package's real session metadata.
    /// No capture-session identity is fabricated. ECID/model come from the
    /// record files only; the UI may show UNKNOWN when absent.
    public static func metadata(for source: SessionPackageSource) -> [String: Any] {
        var files: [[String: Any]] = []
        for f in source.record.files {
            files.append(["role": f.role, "path": f.relativePath, "bytes": f.byteSize, "sha256": f.sha256])
        }
        return [
            "schema": "rlm-session-metadata-v1",
            "status": "AVAILABLE",
            "session_id": source.record.sessionID.uuidString,
            "capture_state": source.record.captureState.rawValue,
            "capture_profile": source.record.captureProfile,
            "capture_backend": source.record.captureBackend,
            "started_at_utc": source.record.startedAtUTC ?? NSNull(),
            "ended_at_utc": source.record.endedAtUTC ?? NSNull(),
            "event_count": source.record.eventCount,
            "coverage_status": source.record.coverageStatus.rawValue,
            "integrity_status": source.record.integrityStatus.rawValue,
            "diagnostic_status": source.record.diagnosticStatus.rawValue,
            "hardware_root_cause": "UNVERIFIED",
            "files": files,
            "missing_evidence": source.record.missingEvidence,
            "fabricated": false
        ]
    }

    /// Lightweight identity scan of the saved raw. It is display/naming-only:
    /// it never changes device identity or claims a restore outcome.
    public static func identity(fromRawURL url: URL) -> (model: String?, ecid: String?) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (nil, nil) }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 2 * 1024 * 1024)) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        let model = firstMatch(in: text, pattern: #"(MacBook(?:Pro|Air)\d{1,2},\d{1,2})"#)
        let ecid = firstMatch(in: text, pattern: #"ECID\s*[:=]\s*(0x[0-9A-Fa-f]+|\d+)"#)
        return (model, ecid)
    }

    public static func namingContext(
        source: SessionPackageSource,
        terminal: String,
        now: Date = Date()
    ) -> SessionPackageNamingContext {
        let date = parseISO(source.record.endedAtUTC ?? source.record.startedAtUTC) ?? now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let dateString = String(format: "%04d%02d%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
        let timeString = String(format: "%02d%02d%02d", comps.hour ?? 0, comps.minute ?? 0, comps.second ?? 0)
        let identity = identity(fromRawURL: source.rawURL)
        return SessionPackageNamingContext(
            date: dateString,
            time: timeString,
            model: identity.model ?? "UNKNOWN",
            ecid: identity.ecid ?? "UNKNOWN",
            restoreStatus: terminal,
            sessionID: source.record.sessionID.uuidString,
            sessionIDShort: String(source.record.sessionID.uuidString.prefix(8))
        )
    }

    public static func packageName(
        template: String,
        source: SessionPackageSource,
        terminal: String,
        now: Date = Date()
    ) -> String {
        SessionPackageNaming.expand(
            template: template,
            context: namingContext(source: source, terminal: terminal, now: now)
        )
    }

    private static func parseISO(_ value: String?) -> Date? {
        guard let value else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: value) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: value)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}

import Foundation

/// Paths owned by one capture session. The work session lives in Application
/// Support and is deliberately *not* a purgeable temporary directory.
public struct SessionPaths: Sendable, Equatable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var rawLogURL: URL { directory.appendingPathComponent("restore.log") }
    public var stderrLogURL: URL { directory.appendingPathComponent("capture-stderr.log") }
    public var diagnosticLogURL: URL { directory.appendingPathComponent("diagnostic.log") }
    public var preCaptureContextURL: URL { directory.appendingPathComponent("pre-capture-context.log") }
    public var sessionJSONURL: URL { directory.appendingPathComponent("session.json") }
    public var sha256SumsURL: URL { directory.appendingPathComponent("SHA256SUMS.txt") }
    /// Preemptive updater_output snapshots (RLM 1.2). Never pollutes restore.log.
    public var updaterOutputRootURL: URL { directory.appendingPathComponent("updater-output", isDirectory: true) }
    public var evidenceCoverageURL: URL { directory.appendingPathComponent("EVIDENCE_COVERAGE.ini") }
    public var updaterOutputCaptureJSONURL: URL { directory.appendingPathComponent("UPDATER_OUTPUT_CAPTURE.json") }
}

/// Creates session directories and writes metadata atomically.
public struct EvidenceStore: Sendable {
    public let root: URL

    /// Test-only seam, invoked between the atomic write and the read-back
    /// comparison in `writeJSON`.
    ///
    /// It exists because a read-back mismatch is otherwise not reachable
    /// deterministically: the write and the comparison are adjacent, so no
    /// caller can interpose. Production initialisers leave this `nil` and the
    /// seam costs one optional call.
    let afterWrite: (@Sendable (URL) throws -> Void)?

    public init(root: URL) {
        self.root = root
        self.afterWrite = nil
    }

    init(root: URL, afterWrite: (@Sendable (URL) throws -> Void)?) {
        self.root = root
        self.afterWrite = afterWrite
    }

    /// Default application-support root for the POC.
    public static func defaultRoot() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("RestoreLogMonitor/Sessions", isDirectory: true)
    }

    /// Creates `<root>/<uuid>.partial` and proves it is writable *before* the
    /// capture process is started. Failing here is cheap; failing at the end
    /// of a restore loses the evidence.
    @discardableResult
    public func createSession(id: UUID) throws -> SessionPaths {
        let directory = root.appendingPathComponent("\(id.uuidString).partial", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let probe = directory.appendingPathComponent(".write-probe")
        do {
            try Data("ok".utf8).write(to: probe, options: .atomic)
            try fm.removeItem(at: probe)
        } catch {
            throw CaptureError.outputDirectoryNotWritable(directory.path)
        }
        return SessionPaths(directory: directory)
    }

    /// Saved sessions only: a session is eligible for current/recent package
    /// export only after session.json exists. Temporary `.partial` directories
    /// without session.json are never treated as saved.
    public func savedSessionRecords() throws -> [(record: SessionRecord, directory: URL)] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        let kids = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        var result: [(SessionRecord, URL)] = []
        for dir in kids where dir.lastPathComponent.hasSuffix(".partial") {
            let json = dir.appendingPathComponent("session.json")
            guard fm.fileExists(atPath: json.path) else { continue }
            do {
                let data = try Data(contentsOf: json)
                let record = try JSONDecoder().decode(SessionRecord.self, from: data)
                result.append((record, dir))
            } catch {
                // A corrupt session is not a saved session; never fabricate one.
                continue
            }
        }
        return result.sorted { lhs, rhs in
            let l = lhs.0.endedAtUTC ?? lhs.0.startedAtUTC ?? ""
            let r = rhs.0.endedAtUTC ?? rhs.0.startedAtUTC ?? ""
            if l == r { return lhs.0.sessionID.uuidString > rhs.0.sessionID.uuidString }
            return l > r
        }
    }

    public func latestSavedSession() throws -> (record: SessionRecord, directory: URL)? {
        try savedSessionRecords().first
    }

    /// Writes JSON atomically and reads it straight back.
    public func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)

        // Test-only seam: lets a test replace the just-written bytes so the
        // read-back comparison below fails. No-op in production.
        try afterWrite?(url)

        let readBack = try Data(contentsOf: url)
        guard readBack == data else {
            throw CaptureError.integrityCheckFailed("session.json read-back mismatch at \(url.path)")
        }
    }
}

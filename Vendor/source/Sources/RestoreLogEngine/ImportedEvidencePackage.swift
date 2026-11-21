import Foundation

/// 014H — write a complete, portable evidence package for an imported raw log.
/// This is packaging only: the semantic report is the exact DiagnosticLogBuilder
/// output; no classifier is duplicated here.
public struct ImportedEvidenceFile: Sendable, Equatable, Codable {
    public let role: String
    public let relativePath: String
    public let byteSize: Int
    public let sha256: String

    public init(role: String, relativePath: String, byteSize: Int, sha256: String) {
        self.role = role
        self.relativePath = relativePath
        self.byteSize = byteSize
        self.sha256 = sha256
    }
}

public struct ImportedEvidencePackage: Sendable, Equatable {
    public let directoryPath: String
    public let files: [ImportedEvidenceFile]

    public init(directoryPath: String, files: [ImportedEvidenceFile]) {
        self.directoryPath = directoryPath
        self.files = files
    }
}

public enum ImportedEvidencePackageError: Error, LocalizedError {
    case destinationExists(URL)
    case rawChangedDuringExport
    case rawUnreadable(URL, Error)
    case writeFailed(URL, Error)
    case diagnosticUnreadable(URL, Error)

    public var errorDescription: String? {
        switch self {
        case .destinationExists(let url):
            return "导出目录已存在：\(url.path)"
        case .rawChangedDuringExport:
            return "原始日志在导出过程中发生变化，已拒绝生成证据包。"
        case .rawUnreadable(let url, let error):
            return "无法读取原始日志 \(url.lastPathComponent)：\(error.localizedDescription)"
        case .writeFailed(let url, let error):
            return "写入证据包失败 \(url.lastPathComponent)：\(error.localizedDescription)"
        case .diagnosticUnreadable(let url, let error):
            return "无法读取诊断报告 \(url.lastPathComponent)：\(error.localizedDescription)"
        }
    }
}

public enum ImportedEvidencePackageBuilder {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Build `<destination>/<package>`; destination must not already exist.
    /// The raw file is copied byte-for-byte and hashed before/after. The
    /// complete diagnostic is copied and also preserved verbatim as the
    /// timeline/key-context file; no truncation or de-duplication occurs.
    public static func build(
        rawURL: URL,
        diagnosticURL: URL,
        analysis: ImportedDiagnosticAnalysis,
        destination: URL,
        sessionMetadata: [String: Any]? = nil,
        sessionJSONURL: URL? = nil,
        preCaptureURL: URL? = nil,
        sessionDirectory: URL? = nil,
        shouldCancel: (@Sendable () -> Bool)? = nil
    ) throws -> ImportedEvidencePackage {
        let fm = FileManager.default
        if shouldCancel?() == true { throw CancellationError() }
        guard !fm.fileExists(atPath: destination.path) else {
            throw ImportedEvidencePackageError.destinationExists(destination)
        }

        let sourceRawSHA = try hash(rawURL, raw: true)
        let sourceDiagnosticSHA = try hash(diagnosticURL, raw: false)
        do {
            try fm.createDirectory(at: destination, withIntermediateDirectories: false)
        } catch {
            throw ImportedEvidencePackageError.writeFailed(destination, error)
        }

        var files: [ImportedEvidenceFile] = []
        let rawName = rawURL.lastPathComponent.isEmpty ? "restore.log" : rawURL.lastPathComponent
        let rawDir = destination.appendingPathComponent("raw", isDirectory: true)
        do {
            try fm.createDirectory(at: rawDir, withIntermediateDirectories: true)
        } catch {
            throw ImportedEvidencePackageError.writeFailed(rawDir, error)
        }
        let rawCopy = rawDir.appendingPathComponent(rawName)
        let diagnosticCopy = destination.appendingPathComponent("diagnostic.log")
        let contextCopy = destination.appendingPathComponent("TIMELINE_AND_KEY_ERROR_CONTEXT.log")
        do {
            if shouldCancel?() == true { throw CancellationError() }
            try fm.copyItem(at: rawURL, to: rawCopy)
            if shouldCancel?() == true { throw CancellationError() }
            try fm.copyItem(at: diagnosticURL, to: diagnosticCopy)
            try fm.copyItem(at: diagnosticURL, to: contextCopy)
        } catch {
            throw ImportedEvidencePackageError.writeFailed(destination, error)
        }
        let sessionJSONCopy = destination.appendingPathComponent("session.json")
        if let sessionJSONURL, fm.fileExists(atPath: sessionJSONURL.path) {
            do { try fm.copyItem(at: sessionJSONURL, to: sessionJSONCopy) }
            catch { throw ImportedEvidencePackageError.writeFailed(destination, error) }
        }
        let preCaptureCopy = destination.appendingPathComponent("pre-capture-context.log")
        if let preCaptureURL, fm.fileExists(atPath: preCaptureURL.path) {
            do { try fm.copyItem(at: preCaptureURL, to: preCaptureCopy) }
            catch { throw ImportedEvidencePackageError.writeFailed(destination, error) }
        }
        // Preserve the other session-owned artifacts too. This is packaging,
        // not re-analysis; the raw/diagnostic remain the primary evidence.
        var auxiliary: [(role: String, relative: String)] = []
        if let sessionDirectory {
            for (name, role) in [
                ("capture-stderr.log", "capture-stderr"),
                ("UPDATER_OUTPUT_CAPTURE.json", "updater-capture-meta")
            ] {
                let src = sessionDirectory.appendingPathComponent(name)
                guard fm.fileExists(atPath: src.path) else { continue }
                let dst = destination.appendingPathComponent(name)
                do { try fm.copyItem(at: src, to: dst) }
                catch { throw ImportedEvidencePackageError.writeFailed(destination, error) }
                auxiliary.append((role, name))
            }
            let updaterDir = sessionDirectory.appendingPathComponent("updater-output", isDirectory: true)
            if fm.fileExists(atPath: updaterDir.path),
               let en = fm.enumerator(at: updaterDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let src as URL in en {
                    guard (try? src.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                    let rel = "updater-output/" + src.path.replacingOccurrences(of: updaterDir.path + "/", with: "")
                    let dst = destination.appendingPathComponent(rel)
                    try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                    do { try fm.copyItem(at: src, to: dst) }
                    catch { throw ImportedEvidencePackageError.writeFailed(destination, error) }
                    auxiliary.append(("updater-output", rel))
                }
            }
        }

        let rawAfter = try hash(rawCopy, raw: true)
        guard rawAfter == sourceRawSHA else {
            throw ImportedEvidencePackageError.rawChangedDuringExport
        }
        let diagnosticAfter = try Integrity.sha256(ofFileAt: diagnosticCopy)
        guard diagnosticAfter == sourceDiagnosticSHA else {
            throw ImportedEvidencePackageError.diagnosticUnreadable(diagnosticCopy, CocoaError(.fileReadCorruptFile))
        }

        files.append(ImportedEvidenceFile(
            role: "raw-log",
            relativePath: "raw/\(rawName)",
            byteSize: try Integrity.byteSize(ofFileAt: rawCopy),
            sha256: rawAfter
        ))
        files.append(ImportedEvidenceFile(
            role: "diagnostic",
            relativePath: "diagnostic.log",
            byteSize: try Integrity.byteSize(ofFileAt: diagnosticCopy),
            sha256: diagnosticAfter
        ))
        files.append(ImportedEvidenceFile(
            role: "timeline-and-key-error-context",
            relativePath: "TIMELINE_AND_KEY_ERROR_CONTEXT.log",
            byteSize: try Integrity.byteSize(ofFileAt: contextCopy),
            sha256: try Integrity.sha256(ofFileAt: contextCopy)
        ))
        if fm.fileExists(atPath: sessionJSONCopy.path) {
            files.append(ImportedEvidenceFile(
                role: "session-json",
                relativePath: "session.json",
                byteSize: try Integrity.byteSize(ofFileAt: sessionJSONCopy),
                sha256: try Integrity.sha256(ofFileAt: sessionJSONCopy)
            ))
        }
        if fm.fileExists(atPath: preCaptureCopy.path) {
            files.append(ImportedEvidenceFile(
                role: "pre-capture-context",
                relativePath: "pre-capture-context.log",
                byteSize: try Integrity.byteSize(ofFileAt: preCaptureCopy),
                sha256: try Integrity.sha256(ofFileAt: preCaptureCopy)
            ))
        }
        for aux in auxiliary {
            let url = destination.appendingPathComponent(aux.relative)
            files.append(ImportedEvidenceFile(
                role: aux.role,
                relativePath: aux.relative,
                byteSize: try Integrity.byteSize(ofFileAt: url),
                sha256: try Integrity.sha256(ofFileAt: url)
            ))
        }

        // Import metadata is real; capture-session metadata is explicitly absent.
        let importedAt = formatter.string(from: Date())
        let isSessionPackage = sessionMetadata != nil
        let importMetadata: [String: Any] = [
            "schema": isSessionPackage ? "rlm-session-evidence-v1" : "rlm-import-evidence-v1",
            "created_at": importedAt,
            "raw_file": rawName,
            "source_path": rawURL.path,
            "raw_bytes": analysis.rawBytes,
            "raw_sha256": sourceRawSHA,
            "diagnostic_sha256": sourceDiagnosticSHA,
            "diagnostic_bytes": analysis.diagnosticBytes,
            "terminal_kind": analysis.terminalKind.rawValue,
            "event_lines": analysis.eventLines,
            "metadata_lines": analysis.metadataLines,
            "malformed_json_lines": analysis.malformedJSONLines,
            "checkpoint_line_count": analysis.checkpointLineCount,
            "analyzer": "DiagnosticLogBuilder",
            "analyzer_semantics": "existing verified engine output; no new classifier"
        ]
        let sessionMetadataJSON: [String: Any] = sessionMetadata ?? [
            "schema": "rlm-session-metadata-v1",
            "status": "NOT_AVAILABLE",
            "reason": "This raw log was imported; no RLM capture session/session.json is associated with it.",
            "fabricated": false
        ]
        let coverage = isSessionPackage ? """
        RAW_LOG=INCLUDED
        FULL_DIAGNOSTIC=INCLUDED
        TIMELINE_AND_KEY_ERROR_CONTEXT=INCLUDED_VERBATIM_COPY_OF_DIAGNOSTIC
        CAPTURE_SESSION_METADATA=INCLUDED
        PRECAPTURE_CONTEXT=SEPARATE_BOUNDED_FILE_IF_PRESENT
        HARDWARE_ROOT_CAUSE=UNVERIFIED
        RAW_LOG_MUTATED=NO
        """ : """
        RAW_LOG=INCLUDED
        FULL_DIAGNOSTIC=INCLUDED
        TIMELINE_AND_KEY_ERROR_CONTEXT=INCLUDED_VERBATIM_COPY_OF_DIAGNOSTIC
        CAPTURE_SESSION_METADATA=NOT_AVAILABLE
        ECID_STRUCTURED_FIELD=NOT_AVAILABLE
        RESTORE_START_STRUCTURED_FIELD=NOT_AVAILABLE
        LAST_SUCCESSFUL_CHECKPOINT_STRUCTURED_FIELD=NOT_AVAILABLE
        FIRST_MEANINGFUL_FAILURE_STRUCTURED_FIELD=NOT_AVAILABLE
        FINAL_RESTORE_ERROR_STRUCTURED_FIELD=NOT_AVAILABLE
        HARDWARE_ROOT_CAUSE=UNVERIFIED
        RAW_LOG_MUTATED=NO
        """
        let readme = isSessionPackage ? """
        # RLM 1.2 Capture Session Evidence Package

        This package preserves the session raw log, the complete
        `DiagnosticLogBuilder` output, session metadata, and SHA-256 manifest.
        It does not claim a hardware root cause.

        - `raw/` — byte-identical source log; never modified.
        - `diagnostic.log` — complete existing-engine diagnostic.
        - `TIMELINE_AND_KEY_ERROR_CONTEXT.log` — verbatim copy of diagnostic.
        - `session.json` / `session-metadata.json` — real RLM session facts when available.
        - `pre-capture-context.log` — bounded context if the auto monitor provided it.
        - `SHA256SUMS.txt` / `PACKAGE_MANIFEST.json` — integrity.

        The raw log remains authoritative. `HARDWARE_ROOT_CAUSE=UNVERIFIED`.
        """ : """
        # RLM 1.2 Imported Evidence Package

        This package preserves the imported raw log and the complete
        `DiagnosticLogBuilder` output generated from it. It is intended for
        analysis by a higher-level agent; it does not claim a hardware root cause.

        - `raw/` — byte-identical source log; never modified.
        - `diagnostic.log` — complete existing-engine diagnostic.
        - `TIMELINE_AND_KEY_ERROR_CONTEXT.log` — verbatim copy of the complete
          diagnostic, so timeline and key-error context are not truncated.
        - `import-metadata.json` — real import/analysis facts.
        - `session-metadata.json` — explicitly NOT_AVAILABLE for an imported file.
        - `EVIDENCE_COVERAGE.ini` — included vs unavailable evidence.
        - `SHA256SUMS.txt` — hashes of all payload files.
        - `PACKAGE_MANIFEST.json` — roles and hashes.

        The raw log remains authoritative. `HARDWARE_ROOT_CAUSE=UNVERIFIED`.
        """
        do {
            try writeJSON(importMetadata, to: destination.appendingPathComponent("import-metadata.json"))
            try writeJSON(sessionMetadataJSON, to: destination.appendingPathComponent("session-metadata.json"))
            try Data(coverage.utf8).write(to: destination.appendingPathComponent("EVIDENCE_COVERAGE.ini"), options: .atomic)
            try Data(readme.utf8).write(to: destination.appendingPathComponent("README.md"), options: .atomic)
        } catch {
            throw ImportedEvidencePackageError.writeFailed(destination, error)
        }
        files.append(contentsOf: try filesForJSON(
            destination: destination,
            roles: [
                "import-metadata.json": "import-metadata",
                "session-metadata.json": "session-metadata",
                "EVIDENCE_COVERAGE.ini": "coverage",
                "README.md": "readme"
            ]
        ))

        // SHA256SUMS covers every payload file except itself and the manifest.
        let sums = files
            .sorted { $0.relativePath < $1.relativePath }
            .map { "\($0.sha256)  \($0.relativePath)" }
            .joined(separator: "\n") + "\n"
        let sumsURL = destination.appendingPathComponent("SHA256SUMS.txt")
        do {
            try Data(sums.utf8).write(to: sumsURL, options: .atomic)
        } catch {
            throw ImportedEvidencePackageError.writeFailed(sumsURL, error)
        }
        files.append(ImportedEvidenceFile(
            role: "sha256-sums",
            relativePath: "SHA256SUMS.txt",
            byteSize: try Integrity.byteSize(ofFileAt: sumsURL),
            sha256: try Integrity.sha256(ofFileAt: sumsURL)
        ))

        let manifest: [String: Any] = [
            "schema": isSessionPackage ? "rlm-session-evidence-package-v1" : "rlm-import-evidence-package-v1",
            "created_at": importedAt,
            "package_directory": destination.lastPathComponent,
            "source_raw_sha256": sourceRawSHA,
            "diagnostic_sha256": sourceDiagnosticSHA,
            "files": files.map { ["role": $0.role, "path": $0.relativePath, "bytes": $0.byteSize, "sha256": $0.sha256] },
            "unknowns": isSessionPackage ? ["structured-ecid", "hardware-root-cause"] : ["capture-session-metadata", "structured-ecid", "hardware-root-cause"],
            "raw_log_mutated": false
        ]
        do {
            try writeJSON(manifest, to: destination.appendingPathComponent("PACKAGE_MANIFEST.json"))
        } catch {
            throw ImportedEvidencePackageError.writeFailed(destination, error)
        }
        return ImportedEvidencePackage(directoryPath: destination.path, files: files)
    }

    private static func hash(_ url: URL, raw: Bool) throws -> String {
        do { return try Integrity.sha256(ofFileAt: url) }
        catch {
            if raw { throw ImportedEvidencePackageError.rawUnreadable(url, error) }
            throw ImportedEvidencePackageError.diagnosticUnreadable(url, error)
        }
    }

    private static func filesForJSON(
        destination: URL,
        roles: [String: String]
    ) throws -> [ImportedEvidenceFile] {
        try roles.sorted { $0.key < $1.key }.map { name, role in
            let url = destination.appendingPathComponent(name)
            return ImportedEvidenceFile(
                role: role,
                relativePath: name,
                byteSize: try Integrity.byteSize(ofFileAt: url),
                sha256: try Integrity.sha256(ofFileAt: url)
            )
        }
    }

    private static func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}

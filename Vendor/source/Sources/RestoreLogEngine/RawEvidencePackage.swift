import Foundation

public struct RawEvidencePackageOptions: Sendable, Equatable {
    public var includeTimeline: Bool
    public var includeSummary: Bool
    public var includeUpdaterOutput: Bool

    public init(
        includeTimeline: Bool = true,
        includeSummary: Bool = true,
        includeUpdaterOutput: Bool = true
    ) {
        self.includeTimeline = includeTimeline
        self.includeSummary = includeSummary
        self.includeUpdaterOutput = includeUpdaterOutput
    }
}

public enum RawEvidencePackageError: Error, LocalizedError {
    case destinationExists(URL)
    case missingRaw(URL)
    case sourceChanged(URL)
    case rawHashMismatch
    case writeFailed(String)
    case verifyFailed(String)

    public var errorDescription: String? {
        switch self {
        case .destinationExists(let url): return "证据包已存在，未覆盖：\(url.path)"
        case .missingRaw(let url): return "找不到已保存的原始日志：\(url.path)"
        case .sourceChanged(let url): return "原始日志在打包期间发生变化，已拒绝发布：\(url.path)"
        case .rawHashMismatch: return "原始日志 SHA-256 与已保存记录不一致，已拒绝打包。"
        case .writeFailed(let detail): return "证据包写入失败：\(detail)"
        case .verifyFailed(let detail): return "证据包 SHA-256 校验失败：\(detail)"
        }
    }
}

public struct RawEvidencePackageResult: Sendable, Equatable {
    public let archiveURL: URL
    public let archiveSHA256: String
    public let archiveBytes: Int
    public let rawSHA256: String
    public let rawBytes: Int
    public let includedAttachments: [String]
    public let skippedAttachments: [String: String]
}

/// Minimum raw evidence package plus optional, source-bound attachments:
/// restore.log, session.json, SHA256SUMS.txt;
/// timeline.json / diagnostic_summary.md (derived from the same staged raw);
/// updater_output.log (only real registered updater-output files).
///
/// It deliberately never calls ImportedEvidencePackageBuilder,
/// ImportedDiagnosticAnalyzer, or a diagnostic cache. The old diagnostic is
/// never read. ZIP, unzip verification and no-overwrite publication reuse
/// EvidencePackageArchive.
public enum RawEvidencePackageBuilder {
    public static func build(
        source: SessionPackageSource,
        destination: URL,
        archiveRootName: String,
        options: RawEvidencePackageOptions = RawEvidencePackageOptions(),
        shouldCancel: (@Sendable () -> Bool)? = nil
    ) throws -> RawEvidencePackageResult {
        if shouldCancel?() == true { throw CancellationError() }
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else {
            throw RawEvidencePackageError.destinationExists(destination)
        }
        guard fm.fileExists(atPath: source.rawURL.path) else {
            throw RawEvidencePackageError.missingRaw(source.rawURL)
        }
        guard let rawFile = source.record.files.first(where: { $0.role == "raw-log" }) else {
            throw RawEvidencePackageError.rawHashMismatch
        }
        let expectedRawSHA = rawFile.sha256
        let beforeSHA = try Integrity.sha256(ofFileAt: source.rawURL)
        let beforeBytes = try Integrity.byteSize(ofFileAt: source.rawURL)
        guard beforeSHA == expectedRawSHA, beforeBytes == rawFile.byteSize else {
            throw RawEvidencePackageError.rawHashMismatch
        }

        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".rlm-raw-evidence-stage-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        } catch {
            throw RawEvidencePackageError.writeFailed(error.localizedDescription)
        }
        defer { try? fm.removeItem(at: staging) }

        let rawCopy = staging.appendingPathComponent("restore.log")
        do {
            try fm.copyItem(at: source.rawURL, to: rawCopy)
        } catch {
            throw RawEvidencePackageError.writeFailed("复制 restore.log：\(error.localizedDescription)")
        }
        let copiedSHA = try Integrity.sha256(ofFileAt: rawCopy)
        let copiedBytes = try Integrity.byteSize(ofFileAt: rawCopy)
        guard copiedSHA == expectedRawSHA else { throw RawEvidencePackageError.rawHashMismatch }
        guard try Integrity.sha256(ofFileAt: source.rawURL) == expectedRawSHA else {
            throw RawEvidencePackageError.sourceChanged(source.rawURL)
        }

        var included: [String] = []
        var skipped: [String: String] = [:]
        var metrics: DiagnosticLogBuilder.Metrics?
        var diagnosticText: String?
        if options.includeTimeline || options.includeSummary {
            let temporaryDiagnostic = staging.appendingPathComponent(".diagnostic-derived.tmp")
            do {
                metrics = try DiagnosticLogBuilder.build(fromRaw: rawCopy, to: temporaryDiagnostic)
                diagnosticText = try String(contentsOf: temporaryDiagnostic, encoding: .utf8)
                try? fm.removeItem(at: temporaryDiagnostic)
            } catch {
                try? fm.removeItem(at: temporaryDiagnostic)
                let reason = "无法从同一 raw 生成派生分析：\(error.localizedDescription)"
                if options.includeTimeline { skipped["timeline.json"] = reason }
                if options.includeSummary { skipped["diagnostic_summary.md"] = reason }
            }
        }
        if options.includeTimeline {
            if let metrics, let diagnosticText {
                do {
                    let timeline = try makeTimeline(
                        diagnosticText: diagnosticText,
                        rawSHA: copiedSHA,
                        rawBytes: copiedBytes,
                        rawLines: metrics.rawLines
                    )
                    let data = try JSONSerialization.data(withJSONObject: timeline, options: [.prettyPrinted, .sortedKeys])
                    try data.write(to: staging.appendingPathComponent("timeline.json"), options: .atomic)
                    included.append("timeline.json")
                } catch {
                    skipped["timeline.json"] = "无法生成 timeline.json：\(error.localizedDescription)"
                }
            } else if skipped["timeline.json"] == nil {
                skipped["timeline.json"] = "派生分析不可用"
            }
        }
        if options.includeSummary {
            if let metrics {
                let summary = makeSummary(metrics: metrics, rawSHA: copiedSHA, rawBytes: copiedBytes)
                do {
                    try Data(summary.utf8).write(to: staging.appendingPathComponent("diagnostic_summary.md"), options: .atomic)
                    included.append("diagnostic_summary.md")
                } catch {
                    skipped["diagnostic_summary.md"] = "无法写入摘要：\(error.localizedDescription)"
                }
            } else if skipped["diagnostic_summary.md"] == nil {
                skipped["diagnostic_summary.md"] = "派生分析不可用"
            }
        }
        if options.includeUpdaterOutput {
            let updater = try makeUpdaterOutput(source: source, staging: staging)
            if let updater {
                included.append("updater_output.log")
                skipped.removeValue(forKey: "updater_output.log")
            } else {
                skipped["updater_output.log"] = "未捕获到真实 updater output 正文"
            }
        }

        var metadata = SessionEvidencePackage.metadata(for: source)
        metadata["package_schema"] = "rlm-raw-evidence-v1"
        metadata["package_mode"] = "RAW_ONLY_WITH_OPTIONAL_SOURCE_BOUND_ATTACHMENTS"
        metadata["raw_sha256"] = copiedSHA
        metadata["raw_bytes"] = copiedBytes
        metadata["capture_completeness"] = source.record.captureState == .savedVerified ? "COMPLETE" : "PARTIAL"
        metadata["restore_terminal"] = metrics.map { $0.terminalKind.rawValue.uppercased() } ?? "UNKNOWN"
        metadata["device_identity"] = "NOT_INCLUDED"
        metadata["diagnostic_attachments"] = "RAW_DERIVED_ONLY"
        metadata["old_diagnostic_cache_used"] = false
        metadata["requested_attachments"] = [
            "timeline.json": options.includeTimeline,
            "diagnostic_summary.md": options.includeSummary,
            "updater_output.log": options.includeUpdaterOutput
        ]
        metadata["attachments"] = Dictionary(uniqueKeysWithValues:
            ["timeline.json", "diagnostic_summary.md", "updater_output.log"].map { name in
                (name, included.contains(name) ? "INCLUDED" : "NOT_INCLUDED: \(skipped[name] ?? "未提供")")
            }
        )
        metadata["unknowns"] = ["device-identity", "hardware-root-cause"]
        do {
            let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: staging.appendingPathComponent("session.json"), options: .atomic)
        } catch {
            throw RawEvidencePackageError.writeFailed("写 session.json：\(error.localizedDescription)")
        }

        let payload = ["restore.log", "session.json"] + included
        var lines: [String] = []
        for name in payload {
            let file = staging.appendingPathComponent(name)
            lines.append("\(try Integrity.sha256(ofFileAt: file))  \(name)")
        }
        let sumsText = lines.joined(separator: "\n") + "\n"
        let sumsURL = staging.appendingPathComponent("SHA256SUMS.txt")
        do {
            try Data(sumsText.utf8).write(to: sumsURL, options: .atomic)
        } catch {
            throw RawEvidencePackageError.writeFailed("写 SHA256SUMS.txt：\(error.localizedDescription)")
        }
        try verifySums(in: staging, names: payload)

        if shouldCancel?() == true { throw CancellationError() }
        do {
            let result = try EvidencePackageArchive.archive(
                packageDirectory: staging,
                destination: destination,
                archiveRootName: archiveRootName,
                shouldCancel: shouldCancel
            )
            guard try Integrity.sha256(ofFileAt: source.rawURL) == expectedRawSHA else {
                throw RawEvidencePackageError.sourceChanged(source.rawURL)
            }
            return RawEvidencePackageResult(
                archiveURL: result.archiveURL,
                archiveSHA256: result.sha256,
                archiveBytes: result.byteSize,
                rawSHA256: copiedSHA,
                rawBytes: copiedBytes,
                includedAttachments: included,
                skippedAttachments: skipped
            )
        } catch let error as RawEvidencePackageError {
            throw error
        } catch {
            throw RawEvidencePackageError.verifyFailed(error.localizedDescription)
        }
    }

    private static func makeTimeline(
        diagnosticText: String,
        rawSHA: String,
        rawBytes: Int,
        rawLines: Int
    ) throws -> [String: Any] {
        var entries: [[String: Any]] = []
        var inTimeline = false
        let regex = try NSRegularExpression(pattern: #"#rawL=(\d+)\s*$"#)
        for line in diagnosticText.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            if text == "===== RESTORE TIMELINE =====" { inTimeline = true; continue }
            if inTimeline && text.hasPrefix("===== ") { break }
            guard inTimeline else { continue }
            let ns = text as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  let rawRange = Range(match.range(at: 1), in: text),
                  let rawLine = Int(text[rawRange]) else { continue }
            let display = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "").trimmingCharacters(in: .whitespaces)
            entries.append(["raw_line": rawLine, "text": display])
        }
        return [
            "schema": "rlm-timeline-v1",
            "source_raw_sha256": rawSHA,
            "source_raw_bytes": rawBytes,
            "source_raw_lines": rawLines,
            "entries": entries,
            "note": "Derived from the package restore.log; #rawL is 1-based raw line. Not authoritative evidence."
        ]
    }

    private static func makeSummary(
        metrics: DiagnosticLogBuilder.Metrics,
        rawSHA: String,
        rawBytes: Int
    ) -> String {
        """
        # RLM Diagnostic Summary

        - source_raw_sha256: \(rawSHA)
        - raw_bytes: \(rawBytes)
        - raw_lines: \(metrics.rawLines)
        - terminal_kind: \(metrics.terminalKind.rawValue.uppercased())
        - kept_lines: \(metrics.keptLines)
        - dropped_lines: \(metrics.droppedLines)
        - noise_reduction_percent: \(String(format: "%.2f", metrics.noiseReductionPercent))
        - device_restore_blocks: \(metrics.deviceRestoreBlocks)
        - semantic_incomplete: \(metrics.semanticIncomplete)

        This summary is derived from the package's restore.log by the existing
        DiagnosticLogBuilder. It is not authoritative evidence and does not
        establish a hardware root cause. The original raw log remains the source
        of truth. HARDWARE_ROOT_CAUSE=UNVERIFIED.
        """
    }

    private static func makeUpdaterOutput(source: SessionPackageSource, staging: URL) throws -> String? {
        let candidates = source.record.files.filter { $0.role == "updater-output" }
        guard !candidates.isEmpty else { return nil }
        var body = Data()
        var count = 0
        for file in candidates {
            let url = source.directory.appendingPathComponent(file.relativePath)
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
            guard (try? Integrity.sha256(ofFileAt: url)) == file.sha256 else { continue }
            let header = "# updater-output source=\(file.relativePath) bytes=\(data.count) sha256=\(file.sha256)\n"
            body.append(Data(header.utf8)); body.append(data); body.append(Data("\n".utf8))
            count += 1
        }
        guard count > 0 else { return nil }
        let dest = staging.appendingPathComponent("updater_output.log")
        try body.write(to: dest, options: .atomic)
        return "updater_output.log"
    }

    private static func verifySums(in directory: URL, names: [String]) throws {
        let sumsURL = directory.appendingPathComponent("SHA256SUMS.txt")
        let text = try String(contentsOf: sumsURL, encoding: .utf8)
        var seen = Set<String>()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty { continue }
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, parts[1].isEmpty else {
                throw RawEvidencePackageError.verifyFailed("SHA256SUMS 格式错误")
            }
            let name = String(parts[2])
            guard names.contains(name) else {
                throw RawEvidencePackageError.verifyFailed("SHA256SUMS 含未知文件：\(name)")
            }
            let actual = try Integrity.sha256(ofFileAt: directory.appendingPathComponent(name))
            guard actual == String(parts[0]) else {
                throw RawEvidencePackageError.verifyFailed("SHA-256 不匹配：\(name)")
            }
            seen.insert(name)
        }
        guard seen == Set(names) else {
            throw RawEvidencePackageError.verifyFailed("SHA256SUMS 未覆盖全部文件")
        }
    }
}

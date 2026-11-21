import Foundation

/// 014H — thin, read-only adapter for analyzing an already-captured raw log.
/// It deliberately delegates every semantic decision to `DiagnosticLogBuilder`;
/// it does not classify errors, checkpoints, or terminals itself.
public struct ImportedDiagnosticAnalysis: Sendable, Equatable {
    public let rawPath: String
    public let rawBytes: Int
    public let rawLines: Int
    public let diagnosticPath: String
    public let diagnosticBytes: Int
    public let diagnosticLines: Int
    public let terminalKind: DiagnosticLogBuilder.RestoreTerminalKind
    public let eventLines: Int
    public let metadataLines: Int
    public let malformedJSONLines: Int
    public let keptLines: Int
    public let droppedLines: Int
    public let checkpointLineCount: Int
    public let preservedNeedles: [String: Int]

    public init(
        rawPath: String,
        rawBytes: Int,
        rawLines: Int,
        diagnosticPath: String,
        diagnosticBytes: Int,
        diagnosticLines: Int,
        terminalKind: DiagnosticLogBuilder.RestoreTerminalKind,
        eventLines: Int,
        metadataLines: Int,
        malformedJSONLines: Int,
        keptLines: Int,
        droppedLines: Int,
        checkpointLineCount: Int,
        preservedNeedles: [String: Int]
    ) {
        self.rawPath = rawPath
        self.rawBytes = rawBytes
        self.rawLines = rawLines
        self.diagnosticPath = diagnosticPath
        self.diagnosticBytes = diagnosticBytes
        self.diagnosticLines = diagnosticLines
        self.terminalKind = terminalKind
        self.eventLines = eventLines
        self.metadataLines = metadataLines
        self.malformedJSONLines = malformedJSONLines
        self.keptLines = keptLines
        self.droppedLines = droppedLines
        self.checkpointLineCount = checkpointLineCount
        self.preservedNeedles = preservedNeedles
    }
}

public enum ImportedDiagnosticAnalysisError: Error, LocalizedError {
    case rawUnreadable(URL, Error)
    case diagnosticUnreadable(URL, Error)

    public var errorDescription: String? {
        switch self {
        case .rawUnreadable(let url, let error):
            return "无法读取原始日志 \(url.lastPathComponent)：\(error.localizedDescription)"
        case .diagnosticUnreadable(let url, let error):
            return "诊断报告已生成但无法读取 \(url.lastPathComponent)：\(error.localizedDescription)"
        }
    }
}

public enum ImportedDiagnosticAnalyzer {
    /// Reuse an already verified diagnostic instead of rebuilding it. The
    /// caller must verify the diagnostic SHA from session.json first. This is
    /// the package fast path for a saved session; it never rewrites raw.
    public static func analyzeExistingDiagnostic(
        rawURL: URL,
        diagnosticURL: URL,
        eventCountHint: Int = 0
    ) throws -> ImportedDiagnosticAnalysis {
        guard FileManager.default.isReadableFile(atPath: rawURL.path) else {
            throw ImportedDiagnosticAnalysisError.rawUnreadable(rawURL, CocoaError(.fileReadNoPermission))
        }
        guard FileManager.default.isReadableFile(atPath: diagnosticURL.path) else {
            throw ImportedDiagnosticAnalysisError.diagnosticUnreadable(diagnosticURL, CocoaError(.fileReadNoSuchFile))
        }
        let rawBytes = try Integrity.byteSize(ofFileAt: rawURL)
        let rawLines = try Integrity.lineCount(ofFileAt: rawURL)
        let diagnosticBytes = try Integrity.byteSize(ofFileAt: diagnosticURL)
        let diagnosticLines = try Integrity.lineCount(ofFileAt: diagnosticURL)
        var checkpointLineCount = 0
        try Integrity.forEachLineDataBounded(
            url: diagnosticURL,
            maxRetainBytes: 4096,
            shouldRetainFull: { _ in true }
        ) { _, lineBytes, _ in
            let needle = Data("checkpoint id:".utf8)
            if Data(lineBytes).range(of: needle) != nil { checkpointLineCount += 1 }
        }
        let terminal = readTerminalKind(rawURL: rawURL)
        return ImportedDiagnosticAnalysis(
            rawPath: rawURL.path,
            rawBytes: rawBytes,
            rawLines: rawLines,
            diagnosticPath: diagnosticURL.path,
            diagnosticBytes: diagnosticBytes,
            diagnosticLines: diagnosticLines,
            terminalKind: terminal,
            eventLines: max(0, eventCountHint),
            metadataLines: 0,
            malformedJSONLines: 0,
            keptLines: diagnosticLines,
            droppedLines: max(0, rawLines - diagnosticLines),
            checkpointLineCount: checkpointLineCount,
            preservedNeedles: [:]
        )
    }

    private static func readTerminalKind(rawURL: URL) -> DiagnosticLogBuilder.RestoreTerminalKind {
        SessionNamingReader.terminalKind(rawURL: rawURL)
    }

    public static func analyze(
        rawURL: URL,
        diagnosticURL: URL,
        shouldCancel: (@Sendable () -> Bool)? = nil
    ) throws -> ImportedDiagnosticAnalysis {
        let fm = FileManager.default
        guard fm.isReadableFile(atPath: rawURL.path) else {
            throw ImportedDiagnosticAnalysisError.rawUnreadable(
                rawURL,
                NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
            )
        }
        do {
            try fm.createDirectory(
                at: diagnosticURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw ImportedDiagnosticAnalysisError.diagnosticUnreadable(
                diagnosticURL,
                error
            )
        }

        let metrics = try DiagnosticLogBuilder.build(fromRaw: rawURL, to: diagnosticURL, shouldCancel: shouldCancel)
        let diagnosticData: Data
        do {
            diagnosticData = try Data(contentsOf: diagnosticURL)
        } catch {
            throw ImportedDiagnosticAnalysisError.diagnosticUnreadable(diagnosticURL, error)
        }

        // Presentation-only count of the builder's own checkpoint lines. This
        // does not classify or redefine checkpoint semantics.
        let text = String(decoding: diagnosticData, as: UTF8.self)
        let checkpointLineCount = text.split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(into: 0) { count, line in
                if line.contains("checkpoint id:") { count += 1 }
            }

        return ImportedDiagnosticAnalysis(
            rawPath: rawURL.path,
            rawBytes: metrics.rawBytes,
            rawLines: metrics.rawLines,
            diagnosticPath: diagnosticURL.path,
            diagnosticBytes: metrics.diagnosticBytes,
            diagnosticLines: metrics.diagnosticLines,
            terminalKind: metrics.terminalKind,
            eventLines: metrics.eventLines,
            metadataLines: metrics.metadataLines,
            malformedJSONLines: metrics.malformedJSONLines,
            keptLines: metrics.keptLines,
            droppedLines: metrics.droppedLines,
            checkpointLineCount: checkpointLineCount,
            preservedNeedles: metrics.preservedNeedles
        )
    }
}

// FullScanOracle.swift — OFFLINE TEST REFERENCE ONLY
// Draft for RLM_1_2_LONG_LINE_RECALL_AND_N1_SOURCE_006 Agent A
// DO NOT copy into Sources/RestoreLogEngine. Writer may place under Tests/.../Support/.
//
// Semantics: scan EVERY byte of each accepted line (≤ maxLineBytes). No 2048 cap.
// Needle tables: prefer referencing DiagnosticLogBuilder public needle arrays to avoid drift.

import Foundation
#if canImport(RestoreLogEngine)
import RestoreLogEngine
#endif

public enum FullScanOracle {
    public struct Result: Equatable {
        public var keptRawLineNumbers: [Int]
        public var keptLines: [String]
        public var droppedLines: Int
        public var rawLines: Int
        public var terminalKindName: String
        public var firstFatalRawLine: Int?
        public var truncatedLineCount: Int
        public var semanticIncomplete: Bool
    }

    public static var maxLineBytes: Int = 1 * 1024 * 1024

    /// ASCII A–Z → a–z (same as product fast path).
    public static func asciiLowercased(_ data: Data) -> Data {
        var out = data
        out.withUnsafeMutableBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            for i in 0..<raw.count {
                let b = base[i]
                if b >= 0x41 && b <= 0x5A { base[i] = b + 0x20 }
            }
        }
        return out
    }

    public static func containsAny(_ hay: Data, _ needles: [Data]) -> Bool {
        for n in needles where hay.range(of: n) != nil { return true }
        return false
    }

    /// Analyze raw log with FULL-LINE scans (Oracle).
    /// This draft uses DiagnosticLogBuilder public needle lists when the module is linked.
    public static func analyze(rawURL: URL) throws -> Result {
        #if canImport(RestoreLogEngine)
        let signal = DiagnosticLogBuilder.signalNeedles.map { Data($0.utf8) }
        let noise = DiagnosticLogBuilder.noiseNeedles.map { Data($0.utf8) }
        let context = DiagnosticLogBuilder.contextNeedles.map { Data($0.utf8) }
        let failureCI = DiagnosticLogBuilder.failureNeedlesCI.map { Data($0.utf8) }
        let successCI = DiagnosticLogBuilder.successNeedlesCI.map { Data($0.utf8) }
        let retryCI = DiagnosticLogBuilder.retryNeedlesCI.map { Data($0.utf8) }
        #else
        // Fallback stubs — Writer must link RestoreLogEngine in tests.
        let signal: [Data] = [Data("AMRestoreErrorDomain".utf8), Data("RamrodErrorDomain".utf8),
                              Data("update_mcdp29xx".utf8), Data("Checkpoint".utf8)]
        let noise: [Data] = [Data("CFPrefs".utf8)]
        let context: [Data] = [Data("progress -1".utf8)]
        let failureCI: [Data] = [Data("ramroderrordomain".utf8), Data("amrestoreerrordomain".utf8),
                                 Data("restore failed".utf8)]
        let successCI: [Data] = [Data("restore succeeded".utf8)]
        let retryCI: [Data] = [Data("retrying restore".utf8)]
        #endif

        let fatalCI: [Data] = [
            Data("amrestoreerrordomain".utf8),
            Data("ramroderrordomain".utf8),
            Data("restore failed".utf8),
            Data("failed restoreos".utf8),
            Data("ramrod firmware update failed".utf8),
            Data("status:error".utf8),
        ]
        let checkpoint = Data("Checkpoint".utf8)
        let failCI = Data("fail".utf8)

        var keptNums: [Int] = []
        var keptLines: [String] = []
        var dropped = 0
        var rawLines = 0
        var firstFatal: Int? = nil
        var truncated = 0
        var terminalParts: [String] = []

        // Full retain: maxRetainBytes == maxLineBytes
        try Integrity.forEachLineDataBounded(
            url: rawURL,
            maxLineBytes: maxLineBytes,
            maxRetainBytes: maxLineBytes,
            shouldRetainFull: { _ in true }
        ) { lineNo, lineBytes, fullByteCount in
            rawLines = lineNo
            if fullByteCount > maxLineBytes {
                truncated += 1
                // Policy mirror: product currently throws before emit; if soft path added, count here.
            }
            let data = Data(lineBytes)
            let low = asciiLowercased(data)

            let isSignal = containsAny(data, signal)
                || containsAny(low, successCI)
                || containsAny(low, failureCI)
            let isNoise = containsAny(data, noise)
            let isContext = containsAny(data, context)
            let keep = isSignal ? true : (isNoise ? false : isContext)

            let terminalHit = containsAny(low, failureCI)
                || containsAny(low, successCI)
                || containsAny(low, retryCI)
                || containsAny(low, [Data("ecid".utf8), Data("session".utf8), Data("device ".utf8)])

            var fatalHit = false
            if firstFatal == nil {
                if containsAny(low, fatalCI) { fatalHit = true }
                else if data.range(of: checkpoint) != nil && low.range(of: failCI) != nil { fatalHit = true }
            }

            let line = String(decoding: lineBytes, as: UTF8.self)
            if keep || terminalHit || fatalHit {
                if terminalHit { terminalParts.append(line) }
                if keep {
                    keptNums.append(lineNo)
                    keptLines.append(line)
                } else {
                    dropped += 1
                }
                if fatalHit { firstFatal = lineNo }
            } else {
                dropped += 1
            }
        }

        #if canImport(RestoreLogEngine)
        let terminal = DiagnosticLogBuilder.classifyTerminal(in: terminalParts.joined(separator: "\n"))
        let terminalName = terminal.rawValue
        #else
        let terminalName = terminalParts.isEmpty ? "none" : "unknown"
        #endif

        return Result(
            keptRawLineNumbers: keptNums,
            keptLines: keptLines,
            droppedLines: dropped,
            rawLines: rawLines,
            terminalKindName: terminalName,
            firstFatalRawLine: firstFatal,
            truncatedLineCount: truncated,
            semanticIncomplete: truncated > 0
        )
    }
}


extension FullScanOracle {
    public static func extractRawLineNumbers(fromDiagnostic text: String) -> [Int] {
        var nums: [Int] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let r = line.range(of: "#rawL=") else { continue }
            let rest = line[r.upperBound...]
            var s = ""
            for ch in rest {
                if ch.isNumber { s.append(ch) } else { break }
            }
            if let v = Int(s) { nums.append(v) }
        }
        return nums
    }
}

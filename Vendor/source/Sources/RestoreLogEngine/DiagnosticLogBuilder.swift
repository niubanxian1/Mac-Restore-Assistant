import Foundation
import Darwin

/// RLM 1.2 — application-side post-filter that builds `diagnostic.log` from the
/// immutable raw `restore.log`. Never rewrites raw. Never changes the capture
/// stream predicate / global log config.
///
/// Classification priority: SIGNAL > NOISE > CONTEXT (BOT-B DENOISE_RULES_V12).
/// `progress -1` is CONTEXT only — never a terminal failure by itself.
/// Section order follows BOT-E DIAGNOSTIC_SUMMARY_DESIGN.
public enum DiagnosticLogBuilder {
    public struct Metrics: Sendable, Equatable {
        public var rawBytes: Int
        public var rawLines: Int
        public var diagnosticBytes: Int
        public var diagnosticLines: Int
        public var keptLines: Int
        public var droppedLines: Int
        public var noiseReductionPercent: Double
        public var terminalKind: RestoreTerminalKind
        public var preservedNeedles: [String: Int]
        /// Lines that hit hard maxLineBytes (build throws today; counted if soft path ever used).
        public var truncatedLineCount: Int
        /// True when any line could not be fully semantically scanned within bounds.
        public var semanticIncomplete: Bool
        /// 012B: number of explicit device-restore blocks preserved.
        public var deviceRestoreBlocks: Int
        /// 012B: total kept block body lines (marker + continuation; header excluded).
        public var deviceRestoreBlockLines: Int
        /// 012B: number of blocks that hit the bounded block limit (RLM_BLOCK_TRUNCATED).
        public var blockTruncatedCount: Int
        /// 014B: input-boundary accounting. These are not hardware failure signals.
        public var eventLines: Int
        public var metadataLines: Int
        public var malformedJSONLines: Int

        public init(
            rawBytes: Int,
            rawLines: Int,
            diagnosticBytes: Int,
            diagnosticLines: Int,
            keptLines: Int,
            droppedLines: Int,
            noiseReductionPercent: Double,
            terminalKind: RestoreTerminalKind,
            preservedNeedles: [String: Int],
            truncatedLineCount: Int = 0,
            semanticIncomplete: Bool = false,
            deviceRestoreBlocks: Int = 0,
            deviceRestoreBlockLines: Int = 0,
            blockTruncatedCount: Int = 0,
            eventLines: Int = 0,
            metadataLines: Int = 0,
            malformedJSONLines: Int = 0
        ) {
            self.rawBytes = rawBytes
            self.rawLines = rawLines
            self.diagnosticBytes = diagnosticBytes
            self.diagnosticLines = diagnosticLines
            self.keptLines = keptLines
            self.droppedLines = droppedLines
            self.noiseReductionPercent = noiseReductionPercent
            self.terminalKind = terminalKind
            self.preservedNeedles = preservedNeedles
            self.truncatedLineCount = truncatedLineCount
            self.semanticIncomplete = semanticIncomplete
            self.deviceRestoreBlocks = deviceRestoreBlocks
            self.deviceRestoreBlockLines = deviceRestoreBlockLines
            self.blockTruncatedCount = blockTruncatedCount
            self.eventLines = eventLines
            self.metadataLines = metadataLines
            self.malformedJSONLines = malformedJSONLines
        }
    }

    /// Terminal kinds (P0-08). `none` = empty; `unknown` = ambiguous;
    /// `conflict` = same-device mixed or distinct-ECID opposite terminals;
    /// `retry` = same-device failure then later success;
    /// `unverified` = mixed success+failure with no bindable device identity.
    public enum RestoreTerminalKind: String, Codable, Sendable, Equatable {
        case success
        case failure
        case retry
        case conflict
        case unverified
        case unknown
        case none
    }

    public enum DiagnosticSection: String, Sendable, CaseIterable {
        case deviceSession = "DEVICE / SESSION"
        case restoreTimeline = "RESTORE TIMELINE"
        case firmwareUpdates = "FIRMWARE UPDATES"
        case firstFatal = "FIRST FATAL"
        case updaterOutput = "UPDATER OUTPUT"
        case hardwareSummary = "HARDWARE DIAGNOSTIC SUMMARY"
        case evidenceMissing = "EVIDENCE / MISSING"
    }

    /// SIGNAL needles (BOT-B S-V1…S-V13 + 1.1 A-set + P0-07 USB/FSM).
    public static let signalNeedles: [String] = [
        "Restore failed",
        "previous restore failed",
        "AMRestoreErrorDomain",
        "RamrodErrorDomain",
        "update_madea",
        "update_mcdp29xx",
        "mcdp29xx",
        "boardConfig",
        "platform=",
        "ECID",
        "deviceType",
        "sending file:",
        "ACURestoreFirmwareOperation",
        "ACURestoreFirmwareCommand",
        "installFirmware",
        "Started checkpoint id:",
        "Completed checkpoint id:",
        "requested restore behavior",
        "State Machine Dump",
        "Finished RestoreOS",
        "Finished DFU",
        "DFU succeeded",
        "Recovery succeeded",
        "ramrod firmware update failed",
        "Failed RestoreOS",
        "status:ERROR",
        "status:SUCCESS",
        "Checkpoint",
        "failed with result",
        "tss_submit_job_with_retry",
        "TSS_ERR_",
        "TSS Connection attempt",
        "TSS reject",
        "server rejected",
        "unable to personalize",
        "personalization failed",
        "AMAuthInstallRequestSendSync",
        "AMAuthInstallUpdaterPersonalize",
        "Failed to create recovery OS variant",
        "Wrote updater output",
        "updater_output",
        "update_orion",
        "update_device_firmware",
        "perform_restore_installing",
        // P0-07 — USB disconnect / FSM / nested fault context
        "Device disconnected",
        "disconnected during transition",
        "during transition",
        "Nested error",
        "nested error",
        "Underlying error",
        "NSUnderlyingError",
    ]

    public static let successNeedlesCI: [String] = [
        "restore succeeded",
        "was successful",
        "restore complete",
    ]

    /// Case-insensitive failure needles (P0-08).
    public static let failureNeedlesCI: [String] = [
        "restore failed",
        "previous restore failed",
        "amrestoreerrordomain",
        "ramroderrordomain",
        "ramrod firmware update failed",
        "failed restoreos",
        "failed with result",
        "status:error",
    ]

    public static let retryNeedlesCI: [String] = [
        "retrying restore",
        "restore retry",
        "attempting restore again",
    ]

    /// NOISE drop (1.1 N1–N8 + 1.2 N-V9…N-V13 + network chatter without SIGNAL).
    public static let noiseNeedles: [String] = [
        "CFPrefs",
        "[com.apple.defaults:User Defaults]",
        "found no value for key",
        "[com.apple.CFBundle:",
        "iconservices",
        "[com.apple.iconservices",
        "AppleMediaServices",
        "AMSURL",
        "[com.apple.xpc.transaction:",
        "fetchOperationProgressForOperationID",
        "launchservices",
        "[com.apple.launchservices",
        "[com.apple.AppKit:",
        "Found minimum MobileDeviceVersion:",
        "CFURLResolveBookmarkData",
        "_AMAuthInstallBundleCreateServerRequestDictionary",
        "CopyOverrideBuildIdentity",
        "PopulateManifestProperties",
        "UpdateHTTPHeaderWithEntry",
        "AMAuthInstallApImg4FindProperty",
        "does not require personalization; skipping",
        "boringssl",
        "nw_endpoint",
        "nw_connection",
        "nw_path",
        "nw_protocol",
        "CFNetwork",
        "TLS",
        "DNSService",
        "dns_query",
        "resolver_host",
        "[com.apple.network:",
    ]

    /// CONTEXT keep — NO bare DeviceService / InternetService / (MobileDevice).
    public static let contextNeedles: [String] = [
        "progress -1",
        "<DFU Device",
        "<Restore Device",
        "<Recovery Mode Device",
        "_AMDFUDeviceConnected",
        "_AMRestoreDeviceConnected",
        "AMAuthInstallBundleCopyBuildIdentityForVariant",
        "Found variant",
    ]

    /// Default hard caps for P0-10. Oversize raw fails closed (no hang).
    public static var maxRawBytesDefault: Int = 512 * 1024 * 1024
    public static var maxLineBytesDefault: Int = 1 * 1024 * 1024
    public static var timeBudgetSecondsDefault: Double = 180.0

    /// Builds diagnostic beside raw. Raw file bytes are never opened for writing.
    /// P0-10: streams lines — does not `Data(contentsOf:)` the whole raw into RSS.
    @discardableResult
    public static func build(
        fromRaw rawURL: URL,
        to diagnosticURL: URL,
        shouldCancel: (@Sendable () -> Bool)? = nil
    ) throws -> Metrics {
        let rawBytes = try Integrity.byteSize(ofFileAt: rawURL)
        if rawBytes > maxRawBytesDefault {
            throw DiagnosticResourceError.rawTooLarge(bytes: rawBytes, limit: maxRawBytesDefault)
        }

        let started = Date()
        var keptIndexed: [(idx: Int, line: String)] = []
        var keptIdx = Set<Int>()
        var dropped = 0
        var rawLines = 0
        var firstFatalLineNo: Int? = nil
        var ring: [(idx: Int, data: Data)] = [] // last ~17 line prefixes for fatal window
        var terminalTextParts: [String] = []
        terminalTextParts.reserveCapacity(256)

        // P0-10 / 006: retainPrefilterBytes (2048) is ONLY a fast retain hint via shouldRetainFull.
        // Final keep/terminal/fatal classification always scans the FULL retained line (≤ maxLineBytes)
        // with a single-pass multi-needle index — never a 2048 semantic boundary.
        var truncatedLineCount = 0
        // 012B: bounded preservation of explicitly-marked multi-line device restore output.
        // raw.log remains the complete mother source; diagnostic keeps the whole marked block
        // (bounded) instead of dropping it because individual lines lack a keyword.
        var inDeviceRestoreBlock = false
        var blockStartRawL: Int? = nil
        var blockKeptLines = 0
        var blockKeptBytes = 0
        var blockTruncated = false
        var blockHasSourceEllipsis = false
        var blockAnnotations: [String] = []
        var deviceRestoreBlocks = 0
        var deviceRestoreBlockLines = 0
        var blockTruncatedCount = 0
        var eventLines = 0
        var metadataLines = 0
        var malformedJSONLines = 0

        func appendKept(_ idx: Int, _ line: String) {
            if keptIdx.insert(idx).inserted {
                keptIndexed.append((idx, line))
            }
        }
        func appendRing(_ idx: Int, _ bytes: UnsafeRawBufferPointer, full: Bool) {
            if full {
                ring.append((idx, Data(bytes)))
            } else {
                let stub = min(bytes.count, 256)
                ring.append((idx, Data(bytes.prefix(stub))))
            }
            if ring.count > 17 { ring.removeFirst() }
        }
        func blockAnnotation() -> String {
            let start = blockStartRawL ?? 0
            return "# DEVICE_RESTORE_OUTPUT blockStartRawL=\(start) lines=\(blockKeptLines) bytes=\(blockKeptBytes) SOURCE_TEXT_CONTAINS_ELLIPSIS=\(blockHasSourceEllipsis ? "YES" : "NO") RLM_BLOCK_TRUNCATED=\(blockTruncated ? "YES" : "NO")"
        }
        func closeBlock() {
            guard inDeviceRestoreBlock else { return }
            blockAnnotations.append(blockAnnotation())
            deviceRestoreBlocks += 1
            deviceRestoreBlockLines += blockKeptLines
            if blockTruncated { blockTruncatedCount += 1 }
            inDeviceRestoreBlock = false
            blockStartRawL = nil
            blockKeptLines = 0
            blockKeptBytes = 0
            blockTruncated = false
            blockHasSourceEllipsis = false
        }

        try Integrity.forEachLineDataBounded(
            url: rawURL,
            maxLineBytes: maxLineBytesDefault,
            maxRetainBytes: maxLineBytesDefault,
            shouldRetainFull: { prefixView in
                // Cheap prefilter: if the first retainPrefilterBytes already show interest, keep retaining
                // (always true path once maxRetainBytes == maxLineBytes; kept for API clarity / future chunking).
                if prefixView.count < retainPrefilterBytes { return true }
                return lineHasInterestPrefilter(prefixView)
            },
            onLine: { lineNo, lineBytes, fullByteCount in
            if lineNo % 4096 == 0 {
                if shouldCancel?() == true { throw CancellationError() }
                let elapsed = Date().timeIntervalSince(started)
                if elapsed > timeBudgetSecondsDefault {
                    throw DiagnosticResourceError.timeBudgetExceeded(seconds: elapsed, limit: timeBudgetSecondsDefault)
                }
            }
            rawLines = lineNo
            // Honesty: hard oversize throws inside Integrity before emit. If soft path ever soft-truncates,
            // count it — never claim complete scan silently.
            if fullByteCount > lineBytes.count {
                truncatedLineCount += 1
            }

            // 014B input boundary: capture Header/Footer metadata is not a log
            // event and must never enter the Restore terminal classifier.
            switch inputLineKind(Data(lineBytes)) {
            case .event:
                eventLines += 1
            case .captureMetadata:
                metadataLines += 1
                dropped += 1
                appendRing(lineNo, lineBytes, full: false)
                return
            case .malformedJSON:
                metadataLines += 1
                malformedJSONLines += 1
                dropped += 1
                appendRing(lineNo, lineBytes, full: false)
                return
            }

            let isStart = bytesEqual(lineBytes, deviceRestoreStartMarkerBytes)
            let isEnd = bytesEqual(lineBytes, deviceRestoreEndMarkerBytes)
            let isHostRecord = looksLikeHostRecord(lineBytes)

            if inDeviceRestoreBlock {
                if isStart {
                    // Two adjacent explicit blocks: close the first, start the second.
                    closeBlock()
                    inDeviceRestoreBlock = true
                    blockStartRawL = lineNo
                    blockKeptLines = 1
                    blockKeptBytes = lineBytes.count
                    blockTruncated = false
                    blockHasSourceEllipsis = bytesContain(lineBytes, ellipsisMarkerBytes)
                    appendKept(lineNo, String(decoding: lineBytes, as: UTF8.self))
                    appendRing(lineNo, lineBytes, full: true)
                    return
                }
                if isEnd {
                    appendKept(lineNo, String(decoding: lineBytes, as: UTF8.self))
                    blockKeptLines += 1
                    blockKeptBytes += 1 + lineBytes.count
                    if bytesContain(lineBytes, ellipsisMarkerBytes) { blockHasSourceEllipsis = true }
                    appendRing(lineNo, lineBytes, full: true)
                    closeBlock()
                    return
                }
                if isHostRecord {
                    // Strict outer compact-record boundary. This line is an independent
                    // record, NOT block body; close and let normal classification handle it.
                    closeBlock()
                } else {
                    if blockTruncated {
                        if bytesContain(lineBytes, ellipsisMarkerBytes) { blockHasSourceEllipsis = true }
                        dropped += 1
                        appendRing(lineNo, lineBytes, full: false)
                        return
                    }
                    if blockKeptLines + 1 > deviceRestoreMaxLines
                        || blockKeptBytes + 1 + lineBytes.count > deviceRestoreMaxBytes {
                        if bytesContain(lineBytes, ellipsisMarkerBytes) { blockHasSourceEllipsis = true }
                        blockTruncated = true
                        dropped += 1
                        appendRing(lineNo, lineBytes, full: false)
                        return
                    }
                    appendKept(lineNo, String(decoding: lineBytes, as: UTF8.self))
                    blockKeptLines += 1
                    blockKeptBytes += 1 + lineBytes.count
                    if bytesContain(lineBytes, ellipsisMarkerBytes) { blockHasSourceEllipsis = true }
                    appendRing(lineNo, lineBytes, full: true)
                    return
                }
            }

            if isStart {
                inDeviceRestoreBlock = true
                blockStartRawL = lineNo
                blockKeptLines = 1
                blockKeptBytes = lineBytes.count
                blockTruncated = false
                blockHasSourceEllipsis = bytesContain(lineBytes, ellipsisMarkerBytes)
                // Keep the immediately preceding source header only when it is a valid
                // outer host record explicitly bound to MobileDevice.
                if let h = ring.last, h.idx == lineNo - 1, looksLikeHostRecord(h.data),
                   String(decoding: h.data, as: UTF8.self).contains("(MobileDevice)") {
                    if !keptIdx.contains(h.idx) {
                        appendKept(h.idx, String(decoding: h.data, as: UTF8.self))
                        if dropped > 0 { dropped -= 1 }
                    }
                }
                appendKept(lineNo, String(decoding: lineBytes, as: UTF8.self))
                appendRing(lineNo, lineBytes, full: true)
                return
            }

            let cls = classifyLineBytes(lineBytes)
            if cls.keep || cls.terminalHit || cls.fatalHit {
                let line = String(decoding: lineBytes, as: UTF8.self)
                if cls.terminalHit {
                    // terminalHit also covers ECID/session/device context lines.
                    // Only actual terminal markers are needed by classifyTerminal;
                    // feeding 20k+ unrelated context lines made a 305 MB log spend
                    // ~60 s re-lowercasing context.
                    let low = line.lowercased()
                    if successNeedlesCI.contains(where: { low.contains($0) })
                        || failureNeedlesCI.contains(where: { low.contains($0) })
                        || retryNeedlesCI.contains(where: { low.contains($0) }) {
                        terminalTextParts.append(line)
                    }
                }
                if cls.keep {
                    keptIdx.insert(lineNo)
                    keptIndexed.append((lineNo, line))
                } else {
                    dropped += 1
                }
                if cls.fatalHit && firstFatalLineNo == nil { firstFatalLineNo = lineNo }
            } else {
                dropped += 1
            }
            // Ring: full bytes only for interesting lines; noise gets ≤256B stub (fatal window
            // second-pass re-reads full file for any missing rawL in ±8).
            if cls.keep || cls.terminalHit || cls.fatalHit {
                ring.append((lineNo, Data(lineBytes)))
            } else {
                let stub = min(lineBytes.count, 256)
                ring.append((lineNo, Data(lineBytes.prefix(stub))))
            }
            if ring.count > 17 { ring.removeFirst() }
        })

        // EOF is a valid block terminator (blocks may omit an explicit end marker).
        closeBlock()


        // Fatal ±8 rescue using ring collected near fatal; if fatal early, ring may be incomplete —
        // second streaming pass for window when needed.
        if let fatalNo = firstFatalLineNo {
            let lo = max(1, fatalNo - 8)
            let hi = fatalNo + 8
            var have = Set(keptIndexed.map(\.idx))
            // Prefer ring hits
            for (lineNo, data) in ring where lineNo >= lo && lineNo <= hi {
                if have.contains(lineNo) { continue }
                let line = String(decoding: data, as: UTF8.self)
                if isNoise(line) && !isSignal(line) { continue }
                if isSignal(line) || isContext(line) || isFaultContext(line) {
                    keptIdx.insert(lineNo)
                    keptIndexed.append((lineNo, line))
                    have.insert(lineNo)
                    if dropped > 0 { dropped -= 1 }
                }
            }
            // If window extends beyond ring (fatal near start of large file after ring rolled),
            // second pass only for missing window lines.
            let missing = (lo...min(hi, rawLines)).filter { !have.contains($0) }
            if !missing.isEmpty {
                var want = Set(missing)
                // P0-10/006: do NOT String-decode every line in debug — only the ≤17 window hits.
                try Integrity.forEachLineData(url: rawURL, maxLineBytes: maxLineBytesDefault) { lineNo, lineBytes in
                    guard want.contains(lineNo) else { return }
                    want.remove(lineNo)
                    if have.contains(lineNo) { return }
                    switch inputLineKind(Data(lineBytes)) {
                    case .event: break
                    case .captureMetadata, .malformedJSON: return
                    }
                    let cls = classifyLineBytes(lineBytes)
                    if cls.isNoise && !cls.isSignal { return }
                    if cls.isSignal || cls.isContext || cls.isFaultContext {
                        let line = String(decoding: lineBytes, as: UTF8.self)
                        keptIdx.insert(lineNo)
                        keptIndexed.append((lineNo, line))
                        have.insert(lineNo)
                        if dropped > 0 { dropped -= 1 }
                    }
                }
            }
            keptIndexed.sort { $0.idx < $1.idx }
        }

        let kept = keptIndexed.map(\.line)
        let terminalBlob = terminalTextParts.joined(separator: "\n")
        let sectioned = emitSectionedDiagnostic(
            keptIndexed: keptIndexed,
            rawText: terminalBlob,
            blockAnnotations: blockAnnotations
        )
        let outData = Data(sectioned.utf8)
        try outData.write(to: diagnosticURL, options: .atomic)

        let terminal = classifyTerminal(in: terminalBlob)
        let needles = [
            "Restore failed",
            "AMRestoreErrorDomain",
            "RamrodErrorDomain",
            "Restore succeeded",
            "progress -1",
            "update_madea",
            "updater_output",
            "tss_submit_job_with_retry",
            "TSS_ERR_",
            "Device disconnected",
        ]
        var preserved: [String: Int] = [:]
        let diagText = String(decoding: outData, as: UTF8.self)
        for n in needles {
            preserved[n] = diagText.components(separatedBy: n).count - 1
        }
        let diagLow = diagText.lowercased()
        preserved["restore succeeded/ci"] = diagLow.components(separatedBy: "restore succeeded").count - 1
        preserved["was successful/ci"] = diagLow.components(separatedBy: "was successful").count - 1
        preserved["restore complete/ci"] = diagLow.components(separatedBy: "restore complete").count - 1
        preserved["restore failed/ci"] = diagLow.components(separatedBy: "restore failed").count - 1

        let diagLines = splitLines(diagText).count
        let reduction: Double = rawLines == 0 ? 0 : (Double(dropped) / Double(rawLines)) * 100.0

        return Metrics(
            rawBytes: rawBytes,
            rawLines: rawLines,
            diagnosticBytes: outData.count,
            diagnosticLines: diagLines,
            keptLines: kept.count,
            droppedLines: dropped,
            noiseReductionPercent: reduction,
            terminalKind: terminal,
            preservedNeedles: preserved,
            truncatedLineCount: truncatedLineCount,
            semanticIncomplete: truncatedLineCount > 0 || blockTruncatedCount > 0,
            deviceRestoreBlocks: deviceRestoreBlocks,
            deviceRestoreBlockLines: deviceRestoreBlockLines,
            blockTruncatedCount: blockTruncatedCount,
            eventLines: eventLines,
            metadataLines: metadataLines,
            malformedJSONLines: malformedJSONLines
        )
    }

    /// BOT-E mandatory section order. Empty sections still emit a missing line.
    public static func emitSectionedDiagnostic(
        keptLines: [String],
        rawText: String,
        blockAnnotations: [String] = []
    ) -> String {
        let indexed = keptLines.enumerated().map { ($0.offset + 1, $0.element) }
        return emitSectionedDiagnostic(keptIndexed: indexed, rawText: rawText, blockAnnotations: blockAnnotations)
    }

    public static func emitSectionedDiagnostic(
        keptIndexed: [(idx: Int, line: String)],
        rawText: String,
        blockAnnotations: [String] = []
    ) -> String {
        // P0-07 / Agent B Option A: primary body is chronological by #rawL.
        // Thematic sections below are secondary; FIRST FATAL is a highlight only.
        let sortedKept = keptIndexed.sorted { lhs, rhs in
            if lhs.idx != rhs.idx { return lhs.idx < rhs.idx }
            return false // stable
        }
        let chrono: [String] = sortedKept.map { "\($0.line)  #rawL=\($0.idx)" }

        var buckets: [DiagnosticSection: [String]] = Dictionary(
            uniqueKeysWithValues: DiagnosticSection.allCases.map { ($0, []) }
        )
        for (lineNo, line) in sortedKept {
            let annotated = "\(line)  #rawL=\(lineNo)"
            let section = classifySection(line)
            // UPDATER OUTPUT: host path lines only — not Started checkpoint / update_madea body.
            if section == .updaterOutput && line.lowercased().contains("checkpoint") {
                buckets[.restoreTimeline, default: []].append(annotated)
            } else {
                buckets[section, default: []].append(annotated)
            }
        }

        var out: [String] = [
            "# RestoreLogMonitor diagnostic.log (RLM-1.2)",
            "# Derived view over immutable restore.log — not authoritative evidence.",
            "# Filter: SIGNAL>NOISE>CONTEXT. progress sentinel(-1) is stage CONTEXT only.",
            "# Forbidden inference: do not invent hardware-fault claims from updater/progress codes.",
            "# taxonomy=\(EventTaxonomy.version) builder=DiagnosticLogBuilder",
            "# HARDWARE_ROOT_CAUSE=UNVERIFIED unless independent board evidence exists.",
            "# Line tags: #rawL=N is the 1-based raw restore.log line number.",
            "# ORDERING=CHRONOLOGICAL_PRIMARY: first body section is full kept stream by #rawL.",
            "# FIRST FATAL is a highlight appendix — not a substitute timeline.",
        ]
        if !blockAnnotations.isEmpty {
            out.append(contentsOf: blockAnnotations)
        }
        out.append("")

        let terminal = classifyTerminal(in: rawText)

        // Primary chronological timeline (all kept lines).
        // Keep canonical section banner "===== RESTORE TIMELINE =====" for consumers/tests;
        // chronology note is a header comment + first line annotation.
        out.append("===== RESTORE TIMELINE =====")
        out.append("# CHRONOLOGICAL_PRIMARY by #rawL (authoritative fault-chain order)")
        if chrono.isEmpty {
            out.append(emptySectionPlaceholder(.restoreTimeline, terminal: terminal))
        } else {
            out.append(contentsOf: chrono)
        }
        out.append("")

        // Secondary thematic sections (skip restoreTimeline — already emitted as primary).
        for section in DiagnosticSection.allCases where section != .restoreTimeline {
            out.append("===== \(section.rawValue) =====")
            if section == .firstFatal {
                out.append("# HIGHLIGHT only — not a substitute timeline; sort consumers by #rawL")
            }
            var lines = buckets[section] ?? []
            lines.sort { rawL(fromAnnotated: $0) < rawL(fromAnnotated: $1) }
            if lines.isEmpty {
                out.append(emptySectionPlaceholder(section, terminal: terminal))
            } else {
                out.append(contentsOf: lines)
            }
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    private static func emptySectionPlaceholder(
        _ section: DiagnosticSection,
        terminal: RestoreTerminalKind
    ) -> String {
        switch section {
        case .firstFatal:
            return (terminal == .failure || terminal == .conflict || terminal == .retry || terminal == .unverified)
                ? "# MISSING: FIRST FATAL not extracted from kept lines (see raw)"
                : "# n/a — no terminal failure"
        case .updaterOutput:
            return "# HOST_OUTPUT_BODY_EVER_EXISTED=UNVERIFIED · REAL_UPDATER_BODY_CAPTURED=NO (unless watcher registered bytes)"
        case .hardwareSummary:
            return "# HARDWARE_ROOT_CAUSE=UNVERIFIED — software/updater text alone is not chip damage proof"
        case .evidenceMissing:
            return "# See session missingEvidence / EVIDENCE_COVERAGE.ini"
        default:
            return "# (none)"
        }
    }

    public static func classifySection(_ line: String) -> DiagnosticSection {
        let low = line.lowercased()
        // P0-07: fatal/error BEFORE device/session so nested Ramrod+ECID lines
        // land in FIRST FATAL, not DEVICE/SESSION.
        if isFatalSignal(line) {
            return .firstFatal
        }
        // P0-07 chronology: non-fatal checkpoint start/complete belong on the
        // main RESTORE TIMELINE (before FIRST FATAL), never after it in UPDATER OUTPUT.
        // "Started checkpoint … (update_madea)" must precede "Checkpoint … failed".
        if low.contains("checkpoint") {
            if low.contains("fail") || low.contains("error") || low.contains("returned") {
                return .firstFatal
            }
            return .restoreTimeline
        }
        if line.contains("updater_output") || line.contains("Wrote updater output")
            || line.contains("update_mcdp29xx") || line.contains("update_madea")
        {
            if line.contains("failed") || line.contains("returned") || line.contains("Ramrod")
                || line.contains("AMRestoreErrorDomain")
            {
                return .firstFatal
            }
            return .updaterOutput
        }
        if line.contains("ECID") || line.contains("boardConfig") || line.contains("platform=")
            || line.contains("deviceType") || low.contains("requested restore behavior")
        {
            return .deviceSession
        }
        if line.contains("sending file:") || line.contains("ACURestoreFirmwareOperation")
            || line.contains("update_orion") || line.contains("update_device_firmware")
            || line.contains("mcdp29xx") || line.contains("Finished DFU")
            || line.contains("Finished RestoreOS")
        {
            return .firmwareUpdates
        }
        if line.contains("tss_") || line.contains("TSS_") || line.contains("AMAuthInstall")
            || line.contains("personaliz")
        {
            return .firmwareUpdates
        }
        if line.contains("Device disconnected") || low.contains("during transition")
            || line.contains("State Machine Dump")
        {
            return .restoreTimeline
        }
        if line.contains("progress -1") || line.contains("<DFU Device")
            || line.contains("<Restore Device") || line.contains("<Recovery Mode Device")
            || line.contains("DFU succeeded")
            || line.contains("Recovery succeeded") || low.contains("restore succeeded")
            || low.contains("restore complete") || low.contains("was successful")
        {
            return .restoreTimeline
        }
        if line.contains("missingEvidence") || line.contains("MISSING") {
            return .evidenceMissing
        }
        return .restoreTimeline
    }

    /// Fast retain prefilter window ONLY — never the final semantic match boundary (006 / audit005 FN class).
    private static let retainPrefilterBytes = 2048
    /// 012B: bounded device-restore block limits (body incl. marker; header excluded).
    public static let deviceRestoreMaxBytes = 64 * 1024
    public static let deviceRestoreMaxLines = 256
    private static let deviceRestoreStartMarkerBytes = Array("==== device restore output ====".utf8)
    private static let deviceRestoreEndMarkerBytes = Array("==== end of device restore output ====".utf8)

    private enum InputLineKind {
        case event
        case captureMetadata
        case malformedJSON
    }

    private static let logStreamHeaderPrefix = Data("Filtering the log data using \"".utf8)

    /// A compact host record's `YYYY-MM-DD HH:...` prefix. This is deliberately
    /// narrow: it preserves fixture-style compact lines that do not match
    /// `looksLikeHostRecord`'s timezone requirement, without treating arbitrary
    /// numeric text as a log record.
    private static func looksLikeCompactTimestamp(_ data: Data) -> Bool {
        guard data.count >= 11 else { return false }
        for i in 0..<10 {
            let b = data[data.startIndex + i]
            switch i {
            case 4, 7: if b != 0x2D { return false }
            default: if b < 0x30 || b > 0x39 { return false }
            }
        }
        return data[data.startIndex + 10] == 0x20
    }

    /// 014B: identify real log events before semantic classification.
    ///
    /// - JSON with both `timestamp` and `eventMessage`: real event.
    /// - valid JSON without those fields: capture metadata/footer, not an event.
    /// - malformed JSON: malformed input, never a normal event.
    /// - exact log-stream `Filtering...` header: capture metadata (unless it is
    ///   itself a host-record line).
    /// - all other non-JSON lines: legacy compact-log event.
    private static func inputLineKind(_ data: Data) -> InputLineKind {
        var i = data.startIndex
        while i < data.endIndex {
            let b = data[i]
            if b == 0x20 || b == 0x09 || b == 0x0D {
                i = data.index(after: i)
            } else {
                break
            }
        }
        if i == data.endIndex { return .captureMetadata }

        // 014F: candidate detection and JSON parsing must use the same
        // whitespace-trimmed slice. Copy only when leading whitespace exists.
        let candidate: Data = i == data.startIndex ? data : Data(data[i...])

        // Compact host records (including fixture timestamps without a timezone)
        // are never NDJSON fragments.
        if looksLikeHostRecord(candidate) || looksLikeCompactTimestamp(candidate) {
            return .event
        }

        let first = candidate[candidate.startIndex]
        let trueToken = Data("true".utf8)
        let falseToken = Data("false".utf8)
        let nullToken = Data("null".utf8)
        let isJSONCandidate: Bool =
            first == 0x7B || first == 0x5B || first == 0x22 || first == 0x2D
            || (first >= 0x30 && first <= 0x39)
            || (candidate.count >= trueToken.count && candidate.prefix(trueToken.count).elementsEqual(trueToken))
            || (candidate.count >= falseToken.count && candidate.prefix(falseToken.count).elementsEqual(falseToken))
            || (candidate.count >= nullToken.count && candidate.prefix(nullToken.count).elementsEqual(nullToken))

        if isJSONCandidate {
            // Fast path for well-formed NDJSON event objects. JSONSerialization
            // and [String: Any] bridging were the dominant CPU cost on 300 MB
            // ndjson. Structural balance plus the required key tokens preserves
            // the event/metadata boundary for normal log records; malformed or
            // ambiguous lines still go through JSONSerialization below.
            if first == 0x7B,
               looksLikeCompleteJSONObject(candidate),
               containsJSONKeyString(candidate, "timestamp"),
               containsJSONKeyString(candidate, "eventMessage") {
                return .event
            }
            do {
                // .fragmentsAllowed is required for top-level string/number/
                // boolean/null JSON values; a valid object still must satisfy
                // the event field/type contract below.
                let object = try JSONSerialization.jsonObject(
                    with: candidate,
                    options: [.fragmentsAllowed]
                )
                guard let dict = object as? [String: Any],
                      dict["timestamp"] as? String != nil,
                      dict["eventMessage"] as? String != nil else {
                    return .captureMetadata
                }
                return .event
            } catch {
                // Invalid object JSON is malformed. Invalid bracket-prefixed
                // lines are historical compact device-restore block text, not
                // JSON; preserve them as compact events. Other malformed
                // JSON-looking values must not become events.
                if first == 0x5B { return .event }
                return .malformedJSON
            }
        }

        if candidate.count >= logStreamHeaderPrefix.count,
           candidate.prefix(logStreamHeaderPrefix.count).elementsEqual(logStreamHeaderPrefix),
           !looksLikeHostRecord(candidate) {
            return .captureMetadata
        }
        return .event
    }

    /// UTF-8 bytes for "<…>" — an upstream/source ellipsis, not a local truncation.
    private static let ellipsisMarkerBytes: [UInt8] = [0x3C, 0xE2, 0x80, 0xA6, 0x3E]
    /// Chunk size for optional overlapping prefilter walks (overlap ≥ longest needle).
    private static let scanOverlapBytes = 64

    /// Precomputed UTF-8 needles (all ASCII). Byte containment ≡ String.contains for these.
    private static let signalNeedleBytes: [Data] = signalNeedles.map { Data($0.utf8) }
    private static let noiseNeedleBytes: [Data] = noiseNeedles.map { Data($0.utf8) }
    private static let contextNeedleBytes: [Data] = contextNeedles.map { Data($0.utf8) }
    private static let failureNeedleBytesCI: [Data] = failureNeedlesCI.map { Data($0.utf8) }
    private static let successNeedleBytesCI: [Data] = successNeedlesCI.map { Data($0.utf8) }
    private static let retryNeedleBytesCI: [Data] = retryNeedlesCI.map { Data($0.utf8) }
    private static let terminalExtraBytesCI: [Data] = [
        Data("ecid".utf8), Data("session".utf8), Data("device ".utf8)
    ]
    private static let fatalNeedleBytesCI: [Data] = [
        Data("amrestoreerrordomain".utf8),
        Data("ramroderrordomain".utf8),
        Data("restore failed".utf8),
        Data("failed restoreos".utf8),
        Data("ramrod firmware update failed".utf8),
        Data("status:error".utf8),
    ]
    private static let faultContextBytesCI: [Data] = [
        Data("nested error".utf8),
        Data("underlying error".utf8),
        Data("device disconnected".utf8),
        Data("during transition".utf8),
    ]
    private static let nsUnderlyingErrorBytes = Data("NSUnderlyingError".utf8)
    private static let checkpointBytes = Data("Checkpoint".utf8)
    private static let failBytesCI = Data("fail".utf8)

    private struct LineClass {
        var keep: Bool
        var terminalHit: Bool
        var fatalHit: Bool
        var isSignal: Bool
        var isNoise: Bool
        var isContext: Bool
        var isFaultContext: Bool
    }

    /// First-byte indexed needle set. Case-insensitive needles must already be lowercase ASCII.
    private struct ByteNeedleIndex: Sendable {
        private let buckets: [[Data]]
        private let caseInsensitive: Bool

        init(needles: [Data], caseInsensitive: Bool) {
            var b = Array(repeating: [Data](), count: 256)
            for n in needles {
                guard let first = n.first, !n.isEmpty else { continue }
                if caseInsensitive {
                    let fl = Self.lower(first)
                    b[Int(fl)].append(n)
                    if fl >= 0x61 && fl <= 0x7A {
                        b[Int(fl &- 0x20)].append(n)
                    }
                } else {
                    b[Int(first)].append(n)
                }
            }
            self.buckets = b
            self.caseInsensitive = caseInsensitive
        }

        @inline(__always)
        private static func lower(_ c: UInt8) -> UInt8 {
            (c >= 0x41 && c <= 0x5A) ? c &+ 0x20 : c
        }

        /// Full scan (any position).
        func contains(in hay: UnsafeRawBufferPointer) -> Bool {
            guard let base = hay.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
            return contains(base: base, count: hay.count)
        }

        func contains(base: UnsafePointer<UInt8>, count n: Int) -> Bool {
            var i = 0
            while i < n {
                if matchesAt(base: base, i: i, n: n) { return true }
                i += 1
            }
            return false
        }

        @inline(__always)
        func matchesAt(base: UnsafePointer<UInt8>, i: Int, n: Int) -> Bool {
            let list = buckets[Int(base[i])]
            if list.isEmpty { return false }
            for needle in list {
                let m = needle.count
                if i + m > n { continue }
                if match(base: base, at: i, needle: needle, count: m) { return true }
            }
            return false
        }

        @inline(__always)
        private func match(base: UnsafePointer<UInt8>, at i: Int, needle: Data, count m: Int) -> Bool {
            needle.withUnsafeBytes { nbRaw in
                guard let nb = nbRaw.bindMemory(to: UInt8.self).baseAddress else { return false }
                if caseInsensitive {
                    for j in 0..<m {
                        if Self.lower(base[i &+ j]) != nb[j] { return false }
                    }
                    return true
                } else {
                    return memcmp(base + i, nb, m) == 0
                }
            }
        }
    }

    private static let signalIndex = ByteNeedleIndex(needles: signalNeedleBytes, caseInsensitive: false)
    private static let noiseIndex = ByteNeedleIndex(needles: noiseNeedleBytes, caseInsensitive: false)
    private static let contextIndex = ByteNeedleIndex(needles: contextNeedleBytes, caseInsensitive: false)
    private static let failureCIIndex = ByteNeedleIndex(needles: failureNeedleBytesCI, caseInsensitive: true)
    private static let successCIIndex = ByteNeedleIndex(needles: successNeedleBytesCI, caseInsensitive: true)
    private static let retryCIIndex = ByteNeedleIndex(needles: retryNeedleBytesCI, caseInsensitive: true)
    private static let terminalExtraCIIndex = ByteNeedleIndex(needles: terminalExtraBytesCI, caseInsensitive: true)
    private static let fatalCIIndex = ByteNeedleIndex(needles: fatalNeedleBytesCI, caseInsensitive: true)
    private static let faultContextCIIndex = ByteNeedleIndex(needles: faultContextBytesCI, caseInsensitive: true)
    private static let checkpointIndex = ByteNeedleIndex(needles: [checkpointBytes], caseInsensitive: false)
    private static let failCIIndex = ByteNeedleIndex(needles: [failBytesCI], caseInsensitive: true)
    private static let nsUnderlyingIndex = ByteNeedleIndex(needles: [nsUnderlyingErrorBytes], caseInsensitive: false)

    /// Full-line (≤ maxLineBytes) UTF-8 view of a String — never truncated to 2048.
    private static func utf8LineData(_ line: String) -> Data {
        let u = line.utf8
        if u.count <= maxLineBytesDefault { return Data(u) }
        return Data(u.prefix(maxLineBytesDefault))
    }

    /// ASCII-only lowercase (A-Z → a-z). Sound for our ASCII needle set.
    private static func asciiLowercased(_ data: Data) -> Data {
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

    private static func dataContainsAny(_ haystack: Data, _ needles: [Data]) -> Bool {
        for n in needles where haystack.range(of: n) != nil { return true }
        return false
    }

    /// Single-pass multi-needle classification over the ENTIRE accepted line body.
    /// Flat contiguous needle bytes + offset table — avoids per-hit Array copy in the hot loop (debug).
    private struct FlatNeedle: Sendable {
        var start: Int
        var count: Int
        var ci: Bool
        var flags: UInt16
    }

    /// Flat needles + first-byte buckets + 2-byte (bigram) busy table.
    /// Bigram reject is critical on CFPrefs/NNNN padding: 'N' alone hits Nested/NSUnderlying
    /// buckets, but bigram 0x4E4E ("NN") matches no needle → O(n) skip without memcmp.
    private static let flatNeedleTables: (
        storage: [UInt8],
        meta: [FlatNeedle],
        bucketStarts: [Int],
        bucketIdxs: [Int],
        bigramBusy: [Bool]
    ) = {
        var bytes: [UInt8] = []
        var meta: [FlatNeedle] = []
        func add(_ needles: [Data], _ ci: Bool, _ flag: UInt16) {
            for n in needles {
                let start = bytes.count
                bytes.append(contentsOf: n)
                meta.append(FlatNeedle(start: start, count: n.count, ci: ci, flags: flag))
            }
        }
        let F_SIGNAL: UInt16 = 1 << 0
        let F_NOISE: UInt16 = 1 << 1
        let F_CONTEXT: UInt16 = 1 << 2
        let F_TERMINAL: UInt16 = 1 << 3
        let F_FATAL: UInt16 = 1 << 4
        let F_FAULT: UInt16 = 1 << 5
        let F_CHECKPOINT: UInt16 = 1 << 6
        let F_FAILTOK: UInt16 = 1 << 7
        add(signalNeedleBytes, false, F_SIGNAL)
        add(successNeedleBytesCI, true, F_SIGNAL | F_TERMINAL)
        add(failureNeedleBytesCI, true, F_SIGNAL | F_TERMINAL)
        add(noiseNeedleBytes, false, F_NOISE)
        add(contextNeedleBytes, false, F_CONTEXT)
        add(retryNeedleBytesCI, true, F_TERMINAL)
        // terminalExtra (ECID/session/device) is not emitted as a standalone
        // output section here. It is used by the terminal classifier when it
        // receives terminal-boundary lines; do not flag every device line.
        _ = terminalExtraBytesCI
        add(fatalNeedleBytesCI, true, F_FATAL)
        add(faultContextBytesCI, true, F_FAULT)
        add([nsUnderlyingErrorBytes], false, F_FAULT)
        add([checkpointBytes], false, F_CHECKPOINT)
        add([failBytesCI], true, F_FAILTOK)

        var lists = Array(repeating: [Int](), count: 256)
        var bigram = Array(repeating: false, count: 65536)
        func fold(_ c: UInt8) -> UInt8 {
            (c >= 0x41 && c <= 0x5A) ? c &+ 0x20 : c
        }
        func markBigram(_ a: UInt8, _ b: UInt8, ci: Bool) {
            if ci {
                let altsA: [UInt8] = {
                    let f = fold(a)
                    if f >= 0x61 && f <= 0x7A { return [f, f &- 0x20] }
                    return [a]
                }()
                let altsB: [UInt8] = {
                    let f = fold(b)
                    if f >= 0x61 && f <= 0x7A { return [f, f &- 0x20] }
                    return [b]
                }()
                for x in altsA {
                    for y in altsB {
                        bigram[(Int(x) << 8) | Int(y)] = true
                    }
                }
            } else {
                bigram[(Int(a) << 8) | Int(b)] = true
            }
        }
        for (idx, row) in meta.enumerated() {
            guard row.count > 0 else { continue }
            let first = bytes[row.start]
            if row.ci {
                let fl = fold(first)
                lists[Int(fl)].append(idx)
                if fl >= 0x61 && fl <= 0x7A { lists[Int(fl &- 0x20)].append(idx) }
            } else {
                lists[Int(first)].append(idx)
            }
            if row.count >= 2 {
                markBigram(bytes[row.start], bytes[row.start + 1], ci: row.ci)
            } else {
                // 1-byte needle: any follower is busy
                for y in 0..<256 { markBigram(first, UInt8(y), ci: row.ci) }
            }
        }
        var bucketStarts = Array(repeating: 0, count: 257)
        var bucketIdxs: [Int] = []
        bucketIdxs.reserveCapacity(meta.count * 2)
        for b in 0..<256 {
            bucketStarts[b] = bucketIdxs.count
            bucketIdxs.append(contentsOf: lists[b])
        }
        bucketStarts[256] = bucketIdxs.count
        return (bytes, meta, bucketStarts, bucketIdxs, bigram)
    }()

    /// Exact byte equality, tolerating a trailing CR from CRLF captures.
    private static func bytesEqual(_ view: UnsafeRawBufferPointer, _ pattern: [UInt8]) -> Bool {
        var count = view.count
        if count > 0 && view[count - 1] == 0x0D { count -= 1 }
        guard count == pattern.count else { return false }
        var i = 0
        while i < pattern.count {
            if view[i] != pattern[i] { return false }
            i += 1
        }
        return true
    }

    /// Byte containment for the source ellipsis only (small fixed pattern).
    private static func bytesContain(_ view: UnsafeRawBufferPointer, _ pattern: [UInt8]) -> Bool {
        guard !pattern.isEmpty, view.count >= pattern.count else { return false }
        let limit = view.count - pattern.count
        var i = 0
        while i <= limit {
            var j = 0
            while j < pattern.count {
                if view[i + j] != pattern[j] { break }
                j += 1
            }
            if j == pattern.count { return true }
            i += 1
        }
        return false
    }

    /// Strict outer compact-log record prefix:
    /// `YYYY-MM-DD HH:MM:SS.mmm <Ty> ...` (Ty is 1–2 ASCII letters).
    /// Used only to terminate a device-restore block; arbitrary date-like body text
    /// that does not match the full prefix is not a boundary.
    private static func looksLikeHostRecord(_ view: UnsafeRawBufferPointer) -> Bool {
        let n = view.count
        guard n >= 24 else { return false }
        func digit(_ i: Int) -> Bool {
            let c = view[i]
            return c >= 0x30 && c <= 0x39
        }
        guard digit(0), digit(1), digit(2), digit(3), view[4] == 0x2D,
              digit(5), digit(6), view[7] == 0x2D,
              digit(8), digit(9), view[10] == 0x20,
              digit(11), digit(12), view[13] == 0x3A,
              digit(14), digit(15), view[16] == 0x3A,
              digit(17), digit(18), view[19] == 0x2E,
              digit(20), digit(21), digit(22), view[23] == 0x20 else { return false }
        var i = 24
        var letters = 0
        while i < n && letters < 3 {
            let c = view[i]
            if (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) {
                letters += 1
                i += 1
            } else {
                break
            }
        }
        return letters >= 1 && letters <= 2 && i < n && view[i] == 0x20
    }

    private static func containsJSONKeyString(_ data: Data, _ key: String) -> Bool {
        data.range(of: Data("\"\(key)\":\"".utf8)) != nil
    }

    /// Fast shape gate for NDJSON event records. Full structural/JSON parsing is
    /// deliberately kept as the fallback; this gate only accepts a complete
    /// brace-terminated object, then the two required keys are verified.
    private static func looksLikeCompleteJSONObject(_ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard let ptr = raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count >= 2 else { return false }
            guard ptr[0] == 0x7B else { return false }
            var i = raw.count - 1
            while i >= 0 {
                let b = ptr[i]
                if b == 0x20 || b == 0x09 || b == 0x0D || b == 0x0A { i -= 1; continue }
                return b == 0x7D
            }
            return false
        }
    }

    /// Bracket/string balance probe only; it deliberately does not attempt to
    /// replace JSONSerialization for ambiguous input. A malformed or unbalanced
    /// candidate falls back to the authoritative parser.
    private static func balancedJSONObject(_ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard let ptr = raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count >= 2 else { return false }
            guard ptr[0] == 0x7B else { return false }
            var stack: [UInt8] = []
            stack.reserveCapacity(32)
            var inString = false
            var escaped = false
            var i = 0
            let n = raw.count
            while i < n {
                let b = ptr[i]
                if inString {
                    if escaped { escaped = false }
                    else if b == 0x5C { escaped = true }
                    else if b == 0x22 { inString = false }
                } else {
                    switch b {
                    case 0x22: inString = true
                    case 0x7B, 0x5B: stack.append(b)
                    case 0x7D:
                        guard stack.popLast() == 0x7B else { return false }
                    case 0x5D:
                        guard stack.popLast() == 0x5B else { return false }
                    case 0x00...0x1F:
                        return false
                    default: break
                    }
                }
                i += 1
            }
            return !inString && stack.isEmpty
        }
    }

    private static func looksLikeHostRecord(_ data: Data) -> Bool {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            looksLikeHostRecord(raw)
        }
    }

    private static func classifyLineBytes(_ hay: UnsafeRawBufferPointer) -> LineClass {
        guard let base = hay.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
            return LineClass(keep: false, terminalHit: false, fatalHit: false,
                             isSignal: false, isNoise: false, isContext: false, isFaultContext: false)
        }
        let n = hay.count
        let storage = flatNeedleTables.storage
        let meta = flatNeedleTables.meta
        let bucketStarts = flatNeedleTables.bucketStarts
        let bucketIdxs = flatNeedleTables.bucketIdxs
        let bigramBusy = flatNeedleTables.bigramBusy
        let F_SIGNAL: UInt16 = 1 << 0
        let F_NOISE: UInt16 = 1 << 1
        let F_CONTEXT: UInt16 = 1 << 2
        let F_TERMINAL: UInt16 = 1 << 3
        let F_FATAL: UInt16 = 1 << 4
        let F_FAULT: UInt16 = 1 << 5
        let F_CHECKPOINT: UInt16 = 1 << 6
        let F_FAILTOK: UInt16 = 1 << 7
        var flags: UInt16 = 0

        flags = storage.withUnsafeBufferPointer { storBuf -> UInt16 in
            guard let stor = storBuf.baseAddress else { return 0 }
            return bucketIdxs.withUnsafeBufferPointer { idxBuf -> UInt16 in
                return bigramBusy.withUnsafeBufferPointer { bgBuf -> UInt16 in
                    guard let idxs = idxBuf.baseAddress, let bg = bgBuf.baseAddress else { return 0 }
                    var f: UInt16 = 0
                    var i = 0
                    while i < n {
                        if i + 1 < n {
                            let bgKey = (Int(base[i]) << 8) | Int(base[i &+ 1])
                            if !bg[bgKey] {
                                i &+= 1
                                continue
                            }
                        }
                        let b = Int(base[i])
                        let lo = bucketStarts[b]
                        let hi = bucketStarts[b &+ 1]
                        if lo < hi {
                            var k = lo
                            while k < hi {
                                let idx = idxs[k]
                                let row = meta[idx]
                                let m = row.count
                                if i + m <= n {
                                    let needle = stor + row.start
                                    var ok = true
                                    if row.ci {
                                        var j = 0
                                        while j < m {
                                            var c = base[i &+ j]
                                            if c >= 0x41 && c <= 0x5A { c &+= 0x20 }
                                            if c != needle[j] { ok = false; break }
                                            j &+= 1
                                        }
                                    } else if memcmp(base + i, needle, m) != 0 {
                                        ok = false
                                    }
                                    if ok { f |= row.flags }
                                }
                                k &+= 1
                            }
                        }
                        i &+= 1
                    }
                    return f
                }
            }
        }

        if (flags & F_CHECKPOINT) != 0 && (flags & F_FAILTOK) != 0 {
            flags |= F_FATAL
        }
        let isSig = (flags & F_SIGNAL) != 0
        let isNoi = (flags & F_NOISE) != 0
        let isCtx = (flags & F_CONTEXT) != 0
        let keep = isSig ? true : (isNoi ? false : isCtx)
        return LineClass(
            keep: keep,
            terminalHit: (flags & F_TERMINAL) != 0,
            fatalHit: (flags & F_FATAL) != 0,
            isSignal: isSig,
            isNoise: isNoi,
            isContext: isCtx,
            isFaultContext: (flags & F_FAULT) != 0
        )
    }

    /// Retain prefilter on the first retainPrefilterBytes — may false-negative; caller must still
    /// full-scan when the full line is retained. Used only as a fast positive hint.
    private static func lineHasInterestPrefilter(_ prefix: UnsafeRawBufferPointer) -> Bool {
        let cls = classifyLineBytes(prefix)
        return cls.keep || cls.terminalHit || cls.fatalHit
    }

    public static func shouldKeep(_ line: String) -> Bool {
        utf8LineData(line).withUnsafeBytes { classifyLineBytes($0).keep }
    }

    public static func isSignal(_ line: String) -> Bool {
        utf8LineData(line).withUnsafeBytes { classifyLineBytes($0).isSignal }
    }

    public static func isFatalSignal(_ line: String) -> Bool {
        utf8LineData(line).withUnsafeBytes { classifyLineBytes($0).fatalHit }
    }

    public static func isFaultContext(_ line: String) -> Bool {
        utf8LineData(line).withUnsafeBytes { classifyLineBytes($0).isFaultContext }
    }

    public static func isNoise(_ line: String) -> Bool {
        utf8LineData(line).withUnsafeBytes { classifyLineBytes($0).isNoise }
    }

    public static func isContext(_ line: String) -> Bool {
        utf8LineData(line).withUnsafeBytes { classifyLineBytes($0).isContext }
    }

    public static func classifyTerminal(in text: String) -> RestoreTerminalKind {
        classifyTerminal(in: text, sessionECID: nil, sessionIDHint: nil)
    }

    public static func classifyTerminal(in text: String, sessionECID: String?) -> RestoreTerminalKind {
        classifyTerminal(in: text, sessionECID: sessionECID, sessionIDHint: nil)
    }

    /// P0-08: DeviceKey ≠ SessionKey. sessionECID is never treated as SessionKey.
    public static func classifyTerminal(
        in text: String,
        sessionECID: String?,
        sessionIDHint: String?
    ) -> RestoreTerminalKind {
        let lines = splitLines(text)
        if lines.isEmpty { return .none }

        enum MarkerKind { case success, failure, retry }
        struct Marker {
            var index: Int
            var kind: MarkerKind
            var deviceKey: String?
            var sessionKey: String?
        }
        var markers: [Marker] = []
        var lastSession: String? = sessionIDHint
        for (i, line) in lines.enumerated() {
            if let s = restoreSessionIdentity(from: line) {
                lastSession = s
            }
            let low = line.lowercased()
            let isFail = failureNeedlesCI.contains(where: { low.contains($0) })
            let isSucc = successNeedlesCI.contains(where: { low.contains($0) })
            let isRetry = retryNeedlesCI.contains(where: { low.contains($0) })
            var device = deviceIdentity(from: line)
            if device == nil {
                let lo = max(0, i - 5)
                if lo < i {
                    for j in stride(from: i - 1, through: lo, by: -1) {
                        if let near = deviceIdentity(from: lines[j]) {
                            device = near
                            break
                        }
                    }
                }
            }
            if device == nil { device = sessionECID.map { "ecid:\($0.lowercased())" } }
            var session = restoreSessionIdentity(from: line) ?? lastSession
            // Do not leap session across a newer "Session K started" already applied via lastSession.
            if isFail { markers.append(Marker(index: i, kind: .failure, deviceKey: device, sessionKey: session)) }
            if isSucc { markers.append(Marker(index: i, kind: .success, deviceKey: device, sessionKey: session)) }
            if isRetry { markers.append(Marker(index: i, kind: .retry, deviceKey: device, sessionKey: session)) }
        }
        if markers.isEmpty { return .none }

        let hasFailure = markers.contains { $0.kind == .failure }
        let hasSuccess = markers.contains { $0.kind == .success }
        let hasRetry = markers.contains { $0.kind == .retry }

        if hasFailure && hasSuccess {
            let fails = markers.filter { $0.kind == .failure }
            let succs = markers.filter { $0.kind == .success }
            let lastFail = fails.last!
            let lastSucc = succs.last!

            let failDev = Set(fails.compactMap(\.deviceKey))
            let succDev = Set(succs.compactMap(\.deviceKey))
            let failSess = Set(fails.compactMap(\.sessionKey))
            let succSess = Set(succs.compactMap(\.sessionKey))
            let anyUnbound = fails.contains(where: { $0.deviceKey == nil })
                || succs.contains(where: { $0.deviceKey == nil })

            // Distinct known device identities on opposite terminals → conflict.
            if !failDev.isEmpty && !succDev.isEmpty && failDev.isDisjoint(with: succDev) {
                return .conflict
            }
            // Same device, distinct known sessions → conflict (never cross-session retry).
            let sharedDev = failDev.intersection(succDev)
            if !sharedDev.isEmpty && !failSess.isEmpty && !succSess.isEmpty && failSess.isDisjoint(with: succSess) {
                return .conflict
            }
            // Mixed unbound on either side → unverified (never causal retry).
            if anyUnbound {
                return .unverified
            }
            // Same device, session unknown on both → unverified (ECID ≠ session).
            if !sharedDev.isEmpty && failSess.isEmpty && succSess.isEmpty {
                return .unverified
            }
            // Same (device, session) both known.
            let sharedSess = failSess.intersection(succSess)
            if !sharedDev.isEmpty && !sharedSess.isEmpty {
                if lastFail.index < lastSucc.index { return .retry }
                if lastSucc.index < lastFail.index { return .conflict }
                return .conflict
            }
            // Ambiguous session boundary
            return .unverified
        }
        if hasRetry && hasSuccess && !hasFailure { return .retry }
        if hasRetry && hasFailure && !hasSuccess { return .failure }
        if hasFailure { return .failure }
        if hasSuccess { return .success }
        return .unknown
    }

    /// Conservative restore session token. Never invent from timestamps alone.
    public static func restoreSessionIdentity(from line: String) -> String? {
        if let r = line.range(of: #"Restore session\s+(\d+|\w+)"#, options: [.regularExpression, .caseInsensitive]) {
            let s = String(line[r])
            if let tok = s.split(whereSeparator: { $0.isWhitespace }).last {
                return "rsession:" + tok.lowercased()
            }
        }
        if let r = line.range(of: #"^Session\s+(\d+)\b"#, options: [.regularExpression, .caseInsensitive]) {
            let s = String(line[r])
            if let tok = s.split(whereSeparator: { $0.isWhitespace }).last {
                return "rsession:" + tok.lowercased()
            }
        }
        if let r = line.range(of: #"Session\s+(\d+)\s+started"#, options: [.regularExpression, .caseInsensitive]) {
            let s = String(line[r])
            let parts = s.split(whereSeparator: { $0.isWhitespace })
            if parts.count >= 2 {
                return "rsession:" + parts[1].lowercased()
            }
        }
        return nil
    }

    /// Extract a device identity. Rejects `device with …` forged phrases.
    public static func deviceIdentity(from line: String) -> String? {
        // ECID = 0x... or ECID:0x...
        if let r = line.range(of: #"ECID\s*[=:]\s*(0x[0-9A-Fa-f]+)"#, options: .regularExpression) {
            let s = String(line[r])
            if let hex = s.split(whereSeparator: { "=:".contains($0) }).last {
                return "ecid:" + hex.trimmingCharacters(in: .whitespaces).lowercased()
            }
        }
        let low = line.lowercased()
        // Reject "device with …" before generic device token match.
        if low.range(of: #"device\s+with\b"#, options: .regularExpression) != nil {
            // Still allow ECID on same line (handled above). No device:with token.
            return nil
        }
        let deny: Set<String> = [
            "with", "error", "retry", "type", "disconnected", "for", "the", "an",
            "during", "transition", "state", "machine", "from", "to", "and", "or"
        ]
        if let r = low.range(of: #"device\s+([a-z0-9_-]+)"#, options: .regularExpression) {
            let token = String(low[r]).split(separator: " ").last.map(String.init) ?? ""
            // Allow single-letter synth probes (device A/B); deny stopwords otherwise.
            if !token.isEmpty && (token.count == 1 || !deny.contains(token)) {
                return "device:" + token
            }
        }
        return nil
    }

    private static func rawL(fromAnnotated line: String) -> Int {
        guard let r = line.range(of: #"#rawL=(\d+)"#, options: .regularExpression) else {
            return Int.max
        }
        let s = String(line[r]).split(separator: "=").last.map(String.init) ?? ""
        return Int(s) ?? Int.max
    }

    public static func progressMinusOneAloneWouldBeFalseFailure(in text: String) -> Bool {
        text.contains("progress -1") && classifyTerminal(in: text) != .failure
    }

    private static func splitLines(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if text.hasSuffix("\n"), let last = lines.last, last.isEmpty {
            lines.removeLast()
        }
        return lines
    }
}

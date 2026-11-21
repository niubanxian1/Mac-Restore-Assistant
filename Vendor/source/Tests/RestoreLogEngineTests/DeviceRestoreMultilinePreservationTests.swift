import XCTest
@testable import RestoreLogEngine

/// 012B — bounded preservation of explicitly-marked multi-line device restore output.
/// The raw is the complete mother source; diagnostic keeps the whole marked block
/// (bounded) instead of dropping lines that lack a single-line keyword.
final class DeviceRestoreMultilinePreservationTests: XCTestCase {
    private let host = "2026-11-06 16:36:03.626 Df com.apple.configurator.xpc.DeviceService[23446:6b8ec] (MobileDevice) "
    private let nextHost = "2026-11-06 16:36:03.700 I  com.apple.configurator.xpc.DeviceService[23446:6a774] (MobileDevice) "
    private let marker = "==== device restore output ===="
    private let endMarker = "==== end of device restore output ===="

    /// Exact 012A block: rawL 25701..25719, 1,019 bytes including the 18 internal LFs.
    private let realBlock: [String] = [
        "==== device restore output ====",
        "Setting crash behaviors: logOnCrash",
        "[00:10:18.0761-GMT]{5>7} CHECKPOINT NOTICE: Image4 device: AP nonce clearable",
        "entering ramrod_clear_ap_nonce",
        "[00:10:18.0773-GMT]{5>7} CHECKPOINT NOTICE: AP nonce consumed",
        "ramrod_NVRAM_has_system_namespace: system namespace IS present",
        "[00:10:18.0773-GMT]{5>7} CHECKPOINT NOTICE: Pre-existing NVRAM variable: auto-boot=false",
        "[00:10:18.0773-GMT]{5>7} CHECKPOINT NOTICE: Pre-existing NVRAM variable: restore-outcome=initial_monitor_no_return",
        "[00:10:18.0773-GMT]{5>7} CHECKPOINT PROGRESS: START (unknown) -> (initial_engine_no_return)",
        "[00:10:18.0774-GMT]{5>7} CHECKPOINT NOTICE: NVRAM access available on initial check",
        "restore-outcome = initial_engine_no_return",
        "vm.shared_region_trace_level: 1 -> 0",
        "net.inet.log_restricted: 0 -> 1",
        "net.inet.tcp.disable_access_to_stats: 1 -> 0",
        "net.inet.tcp.keepinit: 75000 -> 8000",
        "net.inet.tcp.keepidle: 7200000 -> 30000",
        "net.inet.tcp.keepintvl: 75000 -> 5000",
        "net.inet.tcp.keepcnt: 8 -> 6",
        "net.inet.tcp.always_keepalive: <…>",
    ]

    private func makeRaw(_ lines: [String], trailingNewline: Bool = true) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlm-012b-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("raw.log")
        var text = lines.joined(separator: "\n")
        if trailingNewline { text += "\n" }
        try Data(text.utf8).write(to: url)
        return url
    }

    private func build(_ lines: [String], trailingNewline: Bool = true) throws
        -> (diag: String, metrics: DiagnosticLogBuilder.Metrics, raw: URL, out: URL) {
        let raw = try makeRaw(lines, trailingNewline: trailingNewline)
        let out = raw.deletingLastPathComponent().appendingPathComponent("diag.log")
        let metrics = try DiagnosticLogBuilder.build(fromRaw: raw, to: out)
        let diag = try String(contentsOf: out, encoding: .utf8)
        return (diag, metrics, raw, out)
    }

    private func primaryLines(_ diag: String) -> [String] {
        let lines = diag.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(of: "===== RESTORE TIMELINE =====") else { return [] }
        var out: [String] = []
        for line in lines[(start + 1)...] {
            if line.hasPrefix("===== ") { break }
            out.append(line)
        }
        return out
    }

    private func annotated(_ lines: [String]) -> [(rawL: Int, payload: String)] {
        var out: [(Int, String)] = []
        for line in lines {
            guard let r = line.range(of: "  #rawL=", options: .backwards) else { continue }
            let payload = String(line[..<r.lowerBound])
            let rawL = Int(line[r.upperBound...]) ?? -1
            out.append((rawL, payload))
        }
        return out
    }

    private func blockAnnotation(_ diag: String) -> String {
        diag.split(separator: "\n").map(String.init)
            .first { $0.hasPrefix("# DEVICE_RESTORE_OUTPUT ") } ?? ""
    }

    private func assertRealBlock(_ diag: String, metrics: DiagnosticLogBuilder.Metrics,
                                 blockStartRawL: Int, headerRawL: Int?) {
        let primary = annotated(primaryLines(diag))
        let block = primary.filter {
            $0.rawL >= blockStartRawL && $0.rawL < blockStartRawL + realBlock.count
        }.sorted { $0.rawL < $1.rawL }
        XCTAssertEqual(block.count, realBlock.count, "all 19 block lines must be kept")
        XCTAssertEqual(block.map(\.payload), realBlock, "block payload must be byte-for-byte identical")
        XCTAssertEqual(block.map(\.rawL), Array(blockStartRawL..<(blockStartRawL + realBlock.count)),
                       "rawL order must be preserved")
        if let h = headerRawL {
            XCTAssertEqual(primary.filter { $0.rawL == h }.count, 1, "source header once")
        }
        XCTAssertEqual(primary.filter { $0.rawL == blockStartRawL }.count, 1,
                       "marker must not be duplicated")
        XCTAssertEqual(metrics.deviceRestoreBlocks, 1)
        XCTAssertEqual(metrics.deviceRestoreBlockLines, realBlock.count)
        XCTAssertEqual(metrics.blockTruncatedCount, 0)
        let ann = blockAnnotation(diag)
        XCTAssertTrue(ann.contains("lines=19"), ann)
        XCTAssertTrue(ann.contains("bytes=1019"), ann)
        XCTAssertTrue(ann.contains("SOURCE_TEXT_CONTAINS_ELLIPSIS=YES"), ann)
        XCTAssertTrue(ann.contains("RLM_BLOCK_TRUNCATED=NO"), ann)
    }

    func testRealShaped19LineBlockPreservedExactly() throws {
        let next = nextHost + "Restore failed"
        let (diag, metrics, _, _) = try build([host, marker] + realBlock.dropFirst() + [next])
        XCTAssertEqual(realBlock.joined(separator: "\n").utf8.count, 1019)
        assertRealBlock(diag, metrics: metrics, blockStartRawL: 2, headerRawL: 1)
        let primary = annotated(primaryLines(diag))
        XCTAssertEqual(primary.first { $0.rawL == 21 }?.payload, next,
                       "the independent next record must not be swallowed")
        XCTAssertEqual(metrics.rawLines, 21)
        XCTAssertEqual(metrics.keptLines, 21)
        XCTAssertEqual(metrics.droppedLines, 0)
        XCTAssertFalse(metrics.semanticIncomplete)
        XCTAssertTrue(diag.contains("<…>"), "source ellipsis must be preserved verbatim")
    }

    func testMarkerOnlyEmptyBlock() throws {
        let next = nextHost + "Restore failed"
        let (diag, metrics, _, _) = try build([host, marker, next])
        XCTAssertEqual(metrics.deviceRestoreBlocks, 1)
        XCTAssertEqual(metrics.deviceRestoreBlockLines, 1)
        XCTAssertEqual(metrics.blockTruncatedCount, 0)
        let primary = annotated(primaryLines(diag))
        XCTAssertEqual(primary.first { $0.rawL == 2 }?.payload, marker)
        XCTAssertEqual(primary.first { $0.rawL == 3 }?.payload, next)
        let ann = blockAnnotation(diag)
        XCTAssertTrue(ann.contains("lines=1"), ann)
        XCTAssertTrue(ann.contains("bytes=31"), ann)
        XCTAssertTrue(ann.contains("RLM_BLOCK_TRUNCATED=NO"), ann)
    }

    func testEOFWithoutEndMarker() throws {
        let body = ["a", "b", "c"]
        let (diag, metrics, _, _) = try build([host, marker] + body, trailingNewline: false)
        XCTAssertEqual(metrics.deviceRestoreBlocks, 1)
        XCTAssertEqual(metrics.deviceRestoreBlockLines, 4)
        XCTAssertEqual(metrics.blockTruncatedCount, 0)
        let primary = annotated(primaryLines(diag))
        XCTAssertEqual(primary.filter { $0.rawL >= 2 }.map(\.payload), [marker] + body)
        XCTAssertTrue(blockAnnotation(diag).contains("RLM_BLOCK_TRUNCATED=NO"))
    }

    func testExplicitEndMarker() throws {
        let next = nextHost + "Restore failed"
        let (diag, metrics, _, _) = try build([host, marker, "body", endMarker, next])
        XCTAssertEqual(metrics.deviceRestoreBlocks, 1)
        XCTAssertEqual(metrics.deviceRestoreBlockLines, 3)
        let primary = annotated(primaryLines(diag))
        XCTAssertEqual(primary.first { $0.rawL == 4 }?.payload, endMarker)
        XCTAssertEqual(primary.first { $0.rawL == 5 }?.payload, next)
        XCTAssertTrue(blockAnnotation(diag).contains("lines=3"))
    }

    func testTwoAdjacentBlocks() throws {
        let next = nextHost + "Restore failed"
        let lines = [host, marker, "b1", "b2", host, marker, "b3", next]
        let (diag, metrics, _, _) = try build(lines)
        XCTAssertEqual(metrics.deviceRestoreBlocks, 2)
        XCTAssertEqual(metrics.deviceRestoreBlockLines, 5)
        XCTAssertEqual(metrics.blockTruncatedCount, 0)
        let primary = annotated(primaryLines(diag))
        XCTAssertEqual(primary.first { $0.rawL == 2 }?.payload, marker)
        XCTAssertEqual(primary.first { $0.rawL == 6 }?.payload, marker)
        XCTAssertEqual(primary.first { $0.rawL == 8 }?.payload, next)
    }

    func testBlocksSeparatedByIndependentRecord() throws {
        let signal = host + "Restore failed"
        let next = nextHost + "Restore failed"
        let lines = [host, marker, "b1", signal, host, marker, "b2", next]
        let (diag, metrics, _, _) = try build(lines)
        XCTAssertEqual(metrics.deviceRestoreBlocks, 2)
        XCTAssertEqual(metrics.deviceRestoreBlockLines, 4)
        let primary = annotated(primaryLines(diag))
        XCTAssertEqual(primary.first { $0.rawL == 4 }?.payload, signal)
        XCTAssertEqual(primary.first { $0.rawL == 8 }?.payload, next)
    }

    func testTimestampLikeBodyDoesNotTerminate() throws {
        let body = [
            "2026-11-06 16:36:03.626 not-a-host-record",
            "note 2026-11-06 16:36:03.626",
        ]
        let next = nextHost + "Restore failed"
        let (diag, metrics, _, _) = try build([host, marker] + body + [next])
        XCTAssertEqual(metrics.deviceRestoreBlockLines, 3)
        let primary = annotated(primaryLines(diag))
        XCTAssertEqual(primary.filter { $0.rawL >= 2 && $0.rawL <= 4 }.map(\.payload), [marker] + body)
        XCTAssertEqual(primary.first { $0.rawL == 5 }?.payload, next)
    }

    func testUnrelatedCheckpointBodyKept() throws {
        let body = ["CHECKPOINT unrelated", "not a checkpoint"]
        let next = nextHost + "Restore failed"
        let (diag, metrics, _, _) = try build([host, marker] + body + [next])
        XCTAssertEqual(metrics.deviceRestoreBlockLines, 3)
        let primary = annotated(primaryLines(diag))
        XCTAssertEqual(primary.filter { $0.rawL >= 2 && $0.rawL <= 4 }.map(\.payload), [marker] + body)
    }

    func test256LineBoundary() throws {
        let body = (0..<255).map { "L\($0)" }
        let next = nextHost + "Restore failed"
        let (diag, metrics, _, _) = try build([host, marker] + body + [next])
        XCTAssertEqual(metrics.deviceRestoreBlockLines, 256)
        XCTAssertEqual(metrics.blockTruncatedCount, 0)
        XCTAssertFalse(blockAnnotation(diag).contains("RLM_BLOCK_TRUNCATED=YES"))
    }

    func testOver256LinesTruncated() throws {
        let body = (0..<256).map { "L\($0)" }
        let next = nextHost + "Restore failed"
        let (diag, metrics, _, _) = try build([host, marker] + body + [next])
        XCTAssertEqual(metrics.deviceRestoreBlockLines, 256)
        XCTAssertEqual(metrics.blockTruncatedCount, 1)
        XCTAssertTrue(metrics.semanticIncomplete)
        let ann = blockAnnotation(diag)
        XCTAssertTrue(ann.contains("lines=256"), ann)
        XCTAssertTrue(ann.contains("RLM_BLOCK_TRUNCATED=YES"), ann)
        let primary = annotated(primaryLines(diag))
        XCTAssertNil(primary.first { $0.rawL == 258 }, "the 257th block line must be skipped")
        XCTAssertEqual(primary.first { $0.rawL == 259 }?.payload, next)
    }

    func test64KiBExactBoundary() throws {
        // marker 31 + LF 1 + body 65,504 = 65,536
        let body = String(repeating: "A", count: 65_504)
        let next = nextHost + "Restore failed"
        let (diag, metrics, _, _) = try build([host, marker, body, next])
        XCTAssertEqual(metrics.deviceRestoreBlockLines, 2)
        XCTAssertEqual(metrics.blockTruncatedCount, 0)
        let ann = blockAnnotation(diag)
        XCTAssertTrue(ann.contains("bytes=65536"), ann)
        XCTAssertTrue(ann.contains("RLM_BLOCK_TRUNCATED=NO"), ann)
    }

    func testOver64KiBTruncated() throws {
        let body = String(repeating: "A", count: 65_505)
        let next = nextHost + "Restore failed"
        let (diag, metrics, _, _) = try build([host, marker, body, next])
        XCTAssertEqual(metrics.deviceRestoreBlockLines, 1)
        XCTAssertEqual(metrics.blockTruncatedCount, 1)
        XCTAssertTrue(metrics.semanticIncomplete)
        let ann = blockAnnotation(diag)
        XCTAssertTrue(ann.contains("bytes=31"), ann)
        XCTAssertTrue(ann.contains("RLM_BLOCK_TRUNCATED=YES"), ann)
        let primary = annotated(primaryLines(diag))
        XCTAssertEqual(primary.first { $0.rawL == 2 }?.payload, marker)
        XCTAssertNil(primary.first { $0.rawL == 3 })
        XCTAssertEqual(primary.first { $0.rawL == 4 }?.payload, next)
    }

    func testUTF8MultibytePreserved() throws {
        let body = "ramrod 中文 é <…>"
        let next = nextHost + "Restore failed"
        let (diag, metrics, _, _) = try build([host, marker, body, next])
        XCTAssertEqual(metrics.deviceRestoreBlockLines, 2)
        let primary = annotated(primaryLines(diag))
        XCTAssertEqual(primary.first { $0.rawL == 3 }?.payload, body)
        let ann = blockAnnotation(diag)
        XCTAssertTrue(ann.contains("SOURCE_TEXT_CONTAINS_ELLIPSIS=YES"), ann)
        XCTAssertTrue(ann.contains("RLM_BLOCK_TRUNCATED=NO"), ann)
    }

    func testMalformedHeaderNotInvented() throws {
        let next = nextHost + "Restore failed"
        let (diag, metrics, _, _) = try build(["not a host record", marker, "body", next])
        XCTAssertEqual(metrics.deviceRestoreBlocks, 1)
        XCTAssertEqual(metrics.deviceRestoreBlockLines, 2)
        let primary = annotated(primaryLines(diag))
        XCTAssertNil(primary.first { $0.rawL == 1 }, "malformed predecessor must not be kept as header")
        XCTAssertEqual(blockAnnotation(diag).contains("blockStartRawL=2"), true)

        let otherHeader = "2026-11-06 16:36:03.626 Df com.apple.configurator.xpc.DeviceService[23446:6b8ec] (Other)"
        let (diag2, metrics2, _, _) = try build([otherHeader, marker, "body", next])
        XCTAssertEqual(metrics2.deviceRestoreBlockLines, 2)
        XCTAssertNil(annotated(primaryLines(diag2)).first { $0.rawL == 1 },
                     "a host header without (MobileDevice) is not a source header")
    }

    func testNoTrailingNewline() throws {
        let next = nextHost + "Restore failed"
        let (diag, metrics, _, _) = try build([host, marker, "a", "b", next], trailingNewline: false)
        XCTAssertEqual(metrics.deviceRestoreBlockLines, 3)
        XCTAssertEqual(metrics.blockTruncatedCount, 0)
        let primary = annotated(primaryLines(diag))
        XCTAssertEqual(primary.filter { $0.rawL >= 2 && $0.rawL <= 4 }.map(\.payload),
                       [marker, "a", "b"])
        XCTAssertEqual(primary.first { $0.rawL == 5 }?.payload, next)
    }

    func testNoDuplicateMarkerOrHeader() throws {
        let next = nextHost + "Restore failed"
        let (diag, _, _, _) = try build([host, marker] + realBlock.dropFirst() + [next])
        let primary = annotated(primaryLines(diag))
        XCTAssertEqual(primary.filter { $0.rawL == 2 }.count, 1)
        XCTAssertEqual(primary.filter { $0.rawL == 1 }.count, 1)
        XCTAssertEqual(diag.split(separator: "\n").filter { $0.hasSuffix("  #rawL=2") }.count, 1)
        XCTAssertEqual(diag.split(separator: "\n").filter { $0.hasSuffix("  #rawL=1") }.count, 1)
    }

    func testSourceEllipsisIsNotLocalTruncation() throws {
        let next = nextHost + "Restore failed"
        let (diag, metrics, _, _) = try build([host, marker] + realBlock.dropFirst() + [next])
        XCTAssertEqual(metrics.blockTruncatedCount, 0)
        let ann = blockAnnotation(diag)
        XCTAssertTrue(ann.contains("SOURCE_TEXT_CONTAINS_ELLIPSIS=YES"), ann)
        XCTAssertTrue(ann.contains("RLM_BLOCK_TRUNCATED=NO"), ann)
        XCTAssertTrue(diag.contains("net.inet.tcp.always_keepalive: <…>"),
                      "source ellipsis must remain verbatim")
    }
}

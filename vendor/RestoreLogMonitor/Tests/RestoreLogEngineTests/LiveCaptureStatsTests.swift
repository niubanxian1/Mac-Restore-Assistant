import XCTest
@testable import RestoreLogEngine

/// Covers the read-only projector that feeds the live GUI counters.
///
/// These tests do not touch the UI; the GUI itself is verified separately by
/// driving the real app and reading its rendered text.
final class LiveCaptureStatsTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlm-live-stats-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func logURL() -> URL {
        root.appendingPathComponent("restore.log")
    }

    private func write(_ text: String) throws {
        try Data(text.utf8).write(to: logURL())
    }

    private func append(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: logURL())
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    private func classifyCount(_ text: String) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .filter { EventTaxonomy.classify(String($0)) != nil }
            .count
    }

    // C01 — a genuinely empty file is a real zero, and it is available.
    func testC01EmptyFileIsARealZero() async throws {
        try write("")
        let stats = LiveCaptureStats()
        let snap = await stats.snapshot(forPath: logURL().path)
        XCTAssertTrue(snap.isAvailable)
        XCTAssertEqual(snap.byteCount, 0)
        XCTAssertEqual(snap.eventCount, 0)
    }

    // C05 — a missing file must be reported as unknown, never as a confident 0.
    func testC02MissingFileIsUnknownNotZero() async throws {
        let stats = LiveCaptureStats()
        let snap = await stats.snapshot(forPath: root.appendingPathComponent("nope.log").path)
        XCTAssertFalse(snap.isAvailable, "an unobservable file must not masquerade as an empty one")
    }

    // C02/C03 — bytes always grow; events only grow for vocabulary matches.
    func testC03BytesGrowImmediatelyAndEventsOnlyForKnownLines() async throws {
        try write("")
        let stats = LiveCaptureStats()

        try append(String(repeating: "noise without a needle\n", count: 40))
        let afterNoise = await stats.snapshot(forPath: logURL().path)
        XCTAssertEqual(afterNoise.byteCount, 40 * "noise without a needle\n".utf8.count)
        XCTAssertEqual(afterNoise.eventCount, 0, "unclassified lines must not inflate the event count")

        let known = "2026-10-31 10:46:08.666 Df com.apple.configurator.xpc.DeviceService[90421:1] (MobileDevice) Created state machine for device with ECID=0x1\n"
        try append(known)
        let afterKnown = await stats.snapshot(forPath: logURL().path)
        XCTAssertGreaterThan(afterKnown.byteCount, afterNoise.byteCount)
        XCTAssertEqual(afterKnown.eventCount, 1)
    }

    // C04 — a half-written trailing line must not be counted until its newline arrives.
    func testC04PartialTrailingLineIsNotCountedUntilComplete() async throws {
        try write("")
        let stats = LiveCaptureStats()
        let full = "2026-10-31 10:50:00.000 Df DeviceService[1:2] (MobileDevice) ASR progress 42%\n"

        try append(String(full.dropLast()))
        let partial = await stats.snapshot(forPath: logURL().path)
        XCTAssertEqual(partial.eventCount, 0, "an incomplete line is not an event yet")

        try append("\n")
        let complete = await stats.snapshot(forPath: logURL().path)
        XCTAssertEqual(complete.eventCount, 1, "the same line becomes an event once terminated")
    }

    // C07 — repeated reads without growth must not double count.
    func testC05RepeatedReadsAreStable() async throws {
        try write("")
        let stats = LiveCaptureStats()
        let known = "2026-10-31 10:46:08.666 Df x[1:2] Created state machine for device with ECID=0x1\n"
        try append(known)

        let first = await stats.snapshot(forPath: logURL().path)
        let second = await stats.snapshot(forPath: logURL().path)
        let third = await stats.snapshot(forPath: logURL().path)
        XCTAssertEqual(first.eventCount, 1)
        XCTAssertEqual(second.eventCount, 1)
        XCTAssertEqual(third.eventCount, 1)
        XCTAssertEqual(second.byteCount, first.byteCount)
    }

    // C06 — truncation or replacement resets the cursor instead of reporting a negative delta.
    func testC06TruncationResetsCounters() async throws {
        try write("")
        let stats = LiveCaptureStats()
        let known = "2026-10-31 10:46:08.666 Df x[1:2] Created state machine for device with ECID=0x1\n"
        try append(String(repeating: known, count: 5))
        let before = await stats.snapshot(forPath: logURL().path)
        XCTAssertEqual(before.eventCount, 5)

        try write("")   // replaced with a smaller file
        let afterTruncate = await stats.snapshot(forPath: logURL().path)
        XCTAssertEqual(afterTruncate.byteCount, 0)
        XCTAssertEqual(afterTruncate.eventCount, 0, "a replaced file must restart the count")

        try append(known)
        let afterAppend = await stats.snapshot(forPath: logURL().path)
        XCTAssertEqual(afterAppend.eventCount, 1)
    }

    // Incrementality: the projector reads only what was appended, so the live
    // count is identical to a full classification of the same bytes.
    func testC07IncrementalCountMatchesFullClassification() async throws {
        try write("")
        let stats = LiveCaptureStats()
        var accumulated = ""
        for i in 0..<25 {
            let line = i % 3 == 0
                ? "2026-10-31 10:46:0\(i % 10).000 Df x[1:2] Created state machine for device with ECID=0x\(i)\n"
                : "2026-10-31 10:46:0\(i % 10).000 Db x[1:2] unrelated chatter line \(i)\n"
            accumulated += line
            try append(line)
            let snap = await stats.snapshot(forPath: logURL().path)
            XCTAssertEqual(snap.eventCount, classifyCount(accumulated), "live count drifted at step \(i)")
            XCTAssertEqual(snap.byteCount, accumulated.utf8.count)
        }
    }

    // forget() must drop the cursor so a reused path starts clean.
    func testC08ForgetDropsCursor() async throws {
        try write("")
        let stats = LiveCaptureStats()
        let known = "2026-10-31 10:46:08.666 Df x[1:2] Created state machine for device with ECID=0x1\n"
        try append(known)
        _ = await stats.snapshot(forPath: logURL().path)
        await stats.forget(path: logURL().path)
        let afterForget = await stats.snapshot(forPath: logURL().path)
        XCTAssertEqual(afterForget.eventCount, 1, "after forget, the file is re-read from the start once")
    }
    // PERF-01 — the byte prefilter must be EXACT: for every line, the fast path
    // must agree with a full EventTaxonomy.classify. This is the guarantee that the
    // speed-up did not drop an event.
    func testC09PrefilterAgreesWithFullClassificationOnMixedLines() async throws {
        try write("")
        let stats = LiveCaptureStats()
        let lines = [
            "2026-10-31 12:00:00.000 Df x[1:2] Created state machine for device with ECID=0x1",   // needle
            "2026-10-31 12:00:01.000 I  x[1:2] ASR progress 19%",                                  // needle
            "2026-10-31 12:00:02.000 Db x[1:2] unrelated chatter that matches nothing",            // no needle
            "2026-10-31 12:00:03.000 I  x[1:2] asr PROGRESS 19%",                                  // wrong case -> no match
            "2026-10-31 12:00:04.000 Df x[1:2] _AMAuthInstall personalization failed",             // needle
            "2026-10-31 12:00:05.000 Df x[1:2] AMRUSBDevice error (-536854449)",                   // needle
            "2026-10-31 12:00:06.000 Df x[1:2] Issued GETSTATUS request: state = 2",               // needle
            "2026-10-31 12:00:07.000 Db x[1:2] 中文日志行 with no needle",                          // utf8, no needle
        ]
        var expected = 0
        for l in lines {
            if EventTaxonomy.classify(l) != nil { expected += 1 }
            try append(l + "\n")
            let snap = await stats.snapshot(forPath: logURL().path)
            XCTAssertEqual(snap.eventCount, expected, "fast path diverged on: \(l)")
        }
        XCTAssertGreaterThan(expected, 0)
    }

    // PERF-01 — a needle split across two appends must still be classified once the
    // line completes, i.e. the prefilter respects the carry buffer.
    func testC10NeedleSplitAcrossAppendsIsClassified() async throws {
        try write("")
        let stats = LiveCaptureStats()
        let line = "2026-10-31 12:00:00.000 Df x[1:2] Created state machine for device with ECID=0x1\n"
        let cut = line.index(line.startIndex, offsetBy: 40)
        try append(String(line[..<cut]))
        let partial = await stats.snapshot(forPath: logURL().path)
        XCTAssertEqual(partial.eventCount, 0)
        try append(String(line[cut...]))
        let complete = await stats.snapshot(forPath: logURL().path)
        XCTAssertEqual(complete.eventCount, 1)
    }

    // PERF-01 — the prefilter must never count a line that classify rejects, even
    // when a needle's bytes are present in a different case or split by other bytes.
    func testC11PrefilterDoesNotInflateOnNearMisses() async throws {
        try write("")
        let stats = LiveCaptureStats()
        let nearMisses = [
            "2026-10-31 12:00:00.000 Db x[1:2] state machine",              // partial needle
            "2026-10-31 12:00:01.000 Db x[1:2] CREATED STATE MACHINE",      // upper case
            "2026-10-31 12:00:02.000 Db x[1:2] ASR  progress",              // double space
        ]
        for l in nearMisses {
            let matches = EventTaxonomy.classify(l) != nil
            try append(l + "\n")
            let snap = await stats.snapshot(forPath: logURL().path)
            let n = nearMisses.firstIndex(of: l)!
            let expected = nearMisses[0...n].filter { EventTaxonomy.classify($0) != nil }.count
            XCTAssertEqual(snap.eventCount, expected, "prefilter inflated on: \(l) (classify=\(matches))")
        }
    }
}

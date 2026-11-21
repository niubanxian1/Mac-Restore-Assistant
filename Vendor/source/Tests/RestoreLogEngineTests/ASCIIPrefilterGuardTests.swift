import XCTest
import Foundation
@testable import RestoreLogEngine

/// H01-B — permanent guard for the PERF-01 ASCII prefilter.
///
/// `LiveCaptureStats` skips `EventTaxonomy.classify` when a line's **bytes** contain
/// none of the rule needles. That is only sound if the byte test and the
/// grapheme-based `String.contains` agree. This file locks that agreement in.
///
/// Two independent references are used, deliberately neither of them the prefilter:
///
///   1. `classificationTable` — a hand-written literal expectation of which rule each
///      sample must produce. It is NOT computed by calling `EventTaxonomy`, so a
///      change to the vocabulary fails loudly instead of silently re-baselining.
///   2. the prefilter's own contract — for every line the table calls classified, the
///      production pipeline must count an event; for every line it calls
///      unclassified, it must not.
///
/// The prefilter is `private`, so it is exercised the only legitimate way: through
/// the public `snapshot(forPath:)` on a real file. If the fast path ever drops a
/// line the classifier would have matched, `eventCount` comes out short and these
/// tests fail.
final class ASCIIPrefilterGuardTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rlm-prefilter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let dir { try? FileManager.default.removeItem(at: dir) }
    }

    // MARK: - The independent expectation table

    /// `expected` is the rule id the frozen vocabulary must produce, or nil.
    /// Written by hand from the needles in `EventTaxonomy` and the rule order
    /// (error rules before phase rules). It is not derived at runtime.
    private struct Case {
        let id: String
        let line: String
        let expected: String?
        let note: String
    }

    private var classificationTable: [Case] {
        [
            // --- one witness per needle, all nine rules -------------------------
            Case(id: "A01", line: "AMRUSBDevice error: 0xe00002c5", expected: "usb.deviceRequest.error", note: "needle 1 of usb rule"),
            Case(id: "A02", line: "command device request for 5", expected: "usb.deviceRequest.error", note: "needle 2 of usb rule"),
            Case(id: "A03", line: "_AMAuthInstall: TSS ok", expected: "amai.personalization.error", note: "needle 1 of TSS rule"),
            Case(id: "A04", line: "personalization began", expected: "amai.personalization.error", note: "needle 2 of TSS rule"),
            Case(id: "A05", line: "Failed to create recovery OS variant", expected: "amai.personalization.error", note: "needle 3, wins over restore.failure by rule order"),
            Case(id: "A06", line: "failed to open device", expected: "restore.failure", note: "lowercase failure needle"),
            Case(id: "A07", line: "Failure to write image", expected: "restore.failure", note: "capitalised failure needle"),
            Case(id: "A08", line: "unable to open port", expected: "restore.failure", note: "third failure needle"),
            Case(id: "A09", line: "Created state machine for device 1234", expected: "device.stateMachine", note: "state machine needle"),
            Case(id: "A10", line: "State Machine Dump, status: 3", expected: "device.stateMachine", note: "state dump needle"),
            Case(id: "A11", line: "_AMDFUDeviceConnected", expected: "device.connect", note: "DFU enumeration"),
            Case(id: "A12", line: "_AMRestoreDeviceConnected", expected: "device.connect", note: "restore enumeration"),
            Case(id: "A13", line: "<DFU Device 0x1234>", expected: "device.progress", note: "DFU transfer marker"),
            Case(id: "A14", line: "<Restore Device 0x1234>", expected: "device.progress", note: "restore transfer marker"),
            Case(id: "A15", line: "Issued GETSTATUS request", expected: "device.progress", note: "GETSTATUS"),
            Case(id: "A16", line: "Issuing DNLOAD request", expected: "device.progress", note: "DNLOAD"),
            Case(id: "A17", line: "AMAuthInstallBundleCopyBuildIdentity ok", expected: "amai.buildIdentity", note: "build identity"),
            Case(id: "A18", line: "requested restore behavior", expected: "amai.buildIdentity", note: "variant selection"),
            Case(id: "A19", line: "ASR progress 19%", expected: "delivery.payload", note: "payload progress"),
            Case(id: "A20", line: "sending file: /Volumes/x.dmg", expected: "delivery.payload", note: "payload path"),
            Case(id: "A21", line: "Sent image successfully", expected: "delivery.payload", note: "payload done"),
            Case(id: "A22", line: "[com.apple.CFNetwork] connection", expected: "network.context", note: "CFNetwork"),
            Case(id: "A23", line: "com.apple.network:connection went away", expected: "network.context", note: "network connection"),

            // --- negatives: nothing in the vocabulary --------------------------
            Case(id: "B01", line: "2026-10-31 10:00:00.000 Df some ordinary chatter", expected: nil, note: "plain line"),
            Case(id: "B02", line: "AMRUSBDevice erro", expected: nil, note: "one character short of the needle"),
            Case(id: "B03", line: "Personalization began", expected: nil, note: "capital P — needles are case sensitive"),
            Case(id: "B04", line: "CREATED STATE MACHINE FOR DEVICE", expected: nil, note: "upper case"),
            Case(id: "B05", line: "<DFU", expected: nil, note: "prefix only, no ' Device'"),
            Case(id: "B06", line: "asr progress 19%", expected: nil, note: "lower case ASR"),
            Case(id: "B07", line: "failed", expected: nil, note: "verb without ' to'"),
            Case(id: "B08", line: "com.apple.network without the colon", expected: nil, note: "truncated needle"),

            // --- adversarial: the prefilter must not be fooled by byte context --
            Case(id: "C01", line: "前缀中文 AMRUSBDevice error 后缀中文", expected: "usb.deviceRequest.error", note: "multibyte UTF-8 around an ASCII needle"),
            Case(id: "C02", line: "😀<DFU Device🎉", expected: "device.progress", note: "4-byte emoji immediately adjacent"),
            Case(id: "C03", line: "failed to open\u{0D}", expected: "restore.failure", note: "CR retained by the LF split"),
            Case(id: "C04", line: String(repeating: "noise ", count: 900) + "Issued GETSTATUS request", expected: "device.progress", note: "long line, needle at the end"),
            Case(id: "C05", line: String(repeating: "x", count: 8000) + "ASR progress 1%", expected: "delivery.payload", note: "very long line"),
            Case(id: "C06", line: "personalization failed to start", expected: "amai.personalization.error", note: "two rules match, the earlier rule must win"),
            Case(id: "C07", line: "failed to open _AMAuthInstall", expected: "amai.personalization.error", note: "TSS rule outranks failure rule"),
            Case(id: "C08", line: "ｅtiquette full-width letters", expected: nil, note: "full-width characters are not ASCII bytes"),
        ]
    }

    // MARK: - helpers

    /// Write one line followed by a newline and count events the production
    /// pipeline reports for that file.
    private func countEvents(forLines lines: [String], name: String) async throws -> Int {
        let path = dir.appendingPathComponent("\(name).log")
        var blob = ""
        for l in lines { blob += l + "\n" }
        try Data(blob.utf8).write(to: path)
        let stats = LiveCaptureStats()
        let snap = await stats.snapshot(forPath: path.path)
        XCTAssertTrue(snap.isAvailable, "snapshot unavailable for \(name)")
        return snap.eventCount
    }

    private func countByteEvents(_ bytes: Data, name: String) async throws -> Int {
        let path = dir.appendingPathComponent("\(name).log")
        try bytes.write(to: path)
        let stats = LiveCaptureStats()
        let snap = await stats.snapshot(forPath: path.path)
        XCTAssertTrue(snap.isAvailable, "snapshot unavailable for \(name)")
        return snap.eventCount
    }

    // MARK: - the guard

    /// Every row of the independent table, one file per row, so a failure names the
    /// exact line rather than a total.
    func testH01B01PrefilterNeverDropsAClassifiedLine() async throws {
        XCTAssertGreaterThan(classificationTable.count, 0, "an empty table would pass vacuously")
        for c in classificationTable {
            let count = try await countEvents(forLines: [c.line], name: c.id)
            let want = c.expected == nil ? 0 : 1
            XCTAssertEqual(count, want,
                           "[\(c.id)] expected \(want) event(s) (\(c.expected ?? "none")) — \(c.note); line=\(c.line.prefix(120))")
        }
    }

    /// The same table, but with the expectation recomputed through the public
    /// vocabulary. Two independent references must agree; if they disagree, the
    /// hand-written table has drifted from the contract and this fails.
    func testH01B02IndependentTableAgreesWithTheVocabulary() throws {
        for c in classificationTable {
            let byVocabulary = EventTaxonomy.classify(c.line)?.id
            XCTAssertEqual(c.expected, byVocabulary,
                           "[\(c.id)] hand-written expectation disagrees with EventTaxonomy — \(c.note)")
        }
    }

    /// A mixed file: the total must equal the number of classified lines, and the
    /// count must not depend on ordering or on neighbouring lines.
    func testH01B03MixedFileCountsExactlyTheClassifiedLines() async throws {
        let lines = classificationTable.map(\.line)
        let expected = classificationTable.filter { $0.expected != nil }.count
        XCTAssertGreaterThan(expected, 0)
        XCTAssertGreaterThan(classificationTable.count - expected, 0)
        let total = try await countEvents(forLines: lines, name: "mixed")
        XCTAssertEqual(total, expected, "mixed file counted \(total), contract says \(expected)")
    }

    /// The carry buffer: a line split across two appends must still be classified
    /// once, at the moment it becomes complete.
    func testH01B04LineSplitAcrossTwoAppendsIsClassifiedOnce() async throws {
        let path = dir.appendingPathComponent("carry.log")
        let stats = LiveCaptureStats()
        try Data("Issued GETST".utf8).write(to: path)
        var snap = await stats.snapshot(forPath: path.path)
        XCTAssertEqual(snap.eventCount, 0, "an incomplete line must not be counted")

        let h = try FileHandle(forWritingTo: path)
        try h.seekToEnd()
        try h.write(contentsOf: Data("ATUS request\n".utf8))
        try h.close()

        snap = await stats.snapshot(forPath: path.path)
        XCTAssertEqual(snap.eventCount, 1, "the completed line must be counted exactly once")
    }

    /// A line that is not valid UTF-8 passes the byte prefilter but cannot be
    /// decoded, so it must not be counted — and must not crash the loop or swallow
    /// the valid lines around it.
    func testH01B05InvalidUTF8IsSkippedWithoutAffectingNeighbours() async throws {
        var bytes = Data()
        bytes.append(Data("ASR progress 1%\n".utf8))
        bytes.append(contentsOf: [0xFF, 0xFE, 0x41, 0x0A])   // invalid sequence + LF
        bytes.append(Data("ASR progress 2%\n".utf8))
        let count = try await countByteEvents(bytes, name: "invalid-utf8")
        XCTAssertEqual(count, 2, "both valid lines must survive an undecodable neighbour")
    }

    /// The prefilter must not inflate: lines with no needle must stay uncounted even
    /// when they carry the log's usual structure.
    func testH01B06PrefilterDoesNotInflateOnRealisticNoise() async throws {
        let noise = [
            "2026-10-31 10:46:08.625 Df com.apple.configurator.xpc.DeviceService[90421:20f293] (MobileDevice) heartbeat",
            "2026-10-31 10:46:09.001 I  com.apple.configurator.xpc.DeviceService[90421:20f292] (MobileDevice) ui tick",
            "Command line invocation: /usr/bin/x",
        ]
        let count = try await countEvents(forLines: noise, name: "noise")
        XCTAssertEqual(count, 0, "noise lines must not be counted")
    }
}

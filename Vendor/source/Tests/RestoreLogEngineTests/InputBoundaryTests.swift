import Foundation
import XCTest
@testable import RestoreLogEngine

final class InputBoundaryTests: XCTestCase {
    private func jsonEvent(_ message: String, timestamp: String = "2026-11-08 09:47:25.296 +0800") throws -> String {
        let object: [String: Any] = [
            "timestamp": timestamp,
            "eventType": "logEvent",
            "eventMessage": message,
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func build(_ raw: String) throws -> (DiagnosticLogBuilder.Metrics, String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlm-014b-input-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let rawURL = dir.appendingPathComponent("unified.ndjson")
        let diagURL = dir.appendingPathComponent("diagnostic.log")
        try Data(raw.utf8).write(to: rawURL)
        let metrics = try DiagnosticLogBuilder.build(fromRaw: rawURL, to: diagURL)
        XCTAssertEqual(try Data(contentsOf: rawURL), Data(raw.utf8), "raw input must not be modified")
        return (metrics, try String(contentsOf: diagURL, encoding: .utf8))
    }

    func test014B_header_footer_error_words_do_not_create_false_conflict() throws {
        let header = #"Filtering the log data using "process CONTAINS[c] \"DeviceService\" OR eventMessage CONTAINS[c] \"AMRestoreErrorDomain\" OR eventMessage CONTAINS[c] \"RamrodErrorDomain\"""#
        let raw = [
            header,
            "",
            try jsonEvent("Restore succeeded"),
            #"{"count":1,"finished":1}"#,
            #"{"child_argv":["log","stream","AMRestoreErrorDomain","RamrodErrorDomain"],"reason":"CHILD_EXITED"}"#,
        ].joined(separator: "\n") + "\n"
        let (m, diag) = try build(raw)
        XCTAssertEqual(m.rawLines, 5)
        XCTAssertEqual(m.eventLines, 1)
        XCTAssertEqual(m.metadataLines, 4)
        XCTAssertEqual(m.malformedJSONLines, 0)
        XCTAssertEqual(m.terminalKind, .success)
        XCTAssertTrue(diag.lowercased().contains("restore succeeded"))
        XCTAssertFalse(diag.contains("AMRestoreErrorDomain"))
        XCTAssertFalse(diag.contains("RamrodErrorDomain"))
    }

    func test014B_filtering_text_inside_real_event_is_not_dropped() throws {
        let raw = try jsonEvent(#"Filtering the log data using "x"; Restore succeeded"#) + "\n"
        let (m, diag) = try build(raw)
        XCTAssertEqual(m.eventLines, 1)
        XCTAssertEqual(m.metadataLines, 0)
        XCTAssertEqual(m.terminalKind, .success)
        XCTAssertTrue(diag.lowercased().contains("restore succeeded"))
    }

    func test014B_real_failure_in_event_is_preserved() throws {
        let raw = try jsonEvent("Restore failed (result = -1); AMRestoreErrorDomain") + "\n"
        let (m, diag) = try build(raw)
        XCTAssertEqual(m.eventLines, 1)
        XCTAssertEqual(m.metadataLines, 0)
        XCTAssertEqual(m.terminalKind, .failure)
        XCTAssertTrue(diag.contains("Restore failed"))
        XCTAssertTrue(diag.contains("AMRestoreErrorDomain"))
    }

    func test014B_only_success_and_only_failure() throws {
        let (success, _) = try build(try jsonEvent("Restore succeeded") + "\n")
        XCTAssertEqual(success.terminalKind, .success)
        let (failure, _) = try build(try jsonEvent("Restore failed (result = -1)") + "\n")
        XCTAssertEqual(failure.terminalKind, .failure)
    }

    func test014B_success_then_warning_is_still_success() throws {
        let raw = try jsonEvent("Restore succeeded") + "\n" + (try jsonEvent("ordinary warning: transient network retry")) + "\n"
        let (m, _) = try build(raw)
        XCTAssertEqual(m.terminalKind, .success)
        XCTAssertEqual(m.eventLines, 2)
    }

    func test014B_true_terminal_conflict_is_not_success() throws {
        let raw = try jsonEvent("device A: Restore failed") + "\n" + (try jsonEvent("device B: Restore succeeded")) + "\n"
        let (m, _) = try build(raw)
        XCTAssertEqual(m.terminalKind, .conflict)
    }

    func test014B_malformed_json_is_metadata_not_event() throws {
        let raw = #"{"timestamp":"2026-11-08 09:47:25.296 +0800","eventMessage":"# + "\n" + (try jsonEvent("Restore succeeded")) + "\n"
        let (m, diag) = try build(raw)
        XCTAssertEqual(m.eventLines, 1)
        XCTAssertEqual(m.metadataLines, 1)
        XCTAssertEqual(m.malformedJSONLines, 1)
        XCTAssertEqual(m.terminalKind, .success)
        XCTAssertTrue(diag.lowercased().contains("restore succeeded"))
    }

    func test014B_multiple_adjacent_headers_and_footers() throws {
        let h = #"Filtering the log data using "AMRestoreErrorDomain""#
        let f = #"{"count":0,"finished":1}"#
        let c = #"{"child_argv":["log","stream","RamrodErrorDomain"]}"#
        let raw = [h, h, "", try jsonEvent("Restore succeeded"), f, c, f, c].joined(separator: "\n") + "\n"
        let (m, _) = try build(raw)
        XCTAssertEqual(m.eventLines, 1)
        XCTAssertEqual(m.metadataLines, 7)
        XCTAssertEqual(m.terminalKind, .success)
    }

    func test014B_long_line_and_eof() throws {
        let payload = "Restore succeeded " + String(repeating: "x", count: 120_000)
        let raw = try jsonEvent(payload) // no trailing newline: EOF line
        let (m, _) = try build(raw)
        XCTAssertEqual(m.eventLines, 1)
        XCTAssertEqual(m.terminalKind, .success)
        XCTAssertFalse(m.semanticIncomplete)
    }

    func test014B_device_restore_block_is_not_metadata() throws {
        let raw = [
            "2026-11-06 16:36:03.626 Df com.apple.configurator.xpc.DeviceService[1:1] (MobileDevice) ",
            "==== device restore output ====",
            "body one",
            "body two",
            "body three",
            "==== end of device restore output ====",
            try jsonEvent("Restore succeeded"),
        ].joined(separator: "\n") + "\n"
        let (m, diag) = try build(raw)
        XCTAssertEqual(m.deviceRestoreBlocks, 1)
        XCTAssertEqual(m.deviceRestoreBlockLines, 5)
        XCTAssertTrue(diag.contains("body one"))
        XCTAssertTrue(diag.contains("body three"))
    }


    func test014D_valid_non_object_top_level_json_is_metadata() throws {
        let values = [
            "[\"Restore failed\"]",
            "[\"Restore succeeded\"]",
            "\"Restore failed\"",
            "\"Restore succeeded\"",
            "123",
            "-12.5",
            "true",
            "false",
            "null",
        ]
        for value in values {
            let (m, diag) = try build(value + "\n")
            XCTAssertEqual(m.eventLines, 0, "eventLines for \(value)")
            XCTAssertEqual(m.metadataLines, 1, "metadataLines for \(value)")
            XCTAssertEqual(m.terminalKind, .none, "terminal for \(value)")
            XCTAssertFalse(diag.lowercased().contains("restore failed"), value)
            XCTAssertFalse(diag.lowercased().contains("restore succeeded"), value)
        }
    }

    func test014D_event_object_field_types_are_required() throws {
        let fail = #"{"timestamp":123,"eventMessage":"Restore failed"}"#
        let fail2 = #"{"timestamp":"2026-11-08T01:00:00Z","eventMessage":123}"#
        for value in [fail, fail2] {
            let (m, _) = try build(value + "\n")
            XCTAssertEqual(m.eventLines, 0, value)
            XCTAssertEqual(m.metadataLines, 1, value)
            XCTAssertEqual(m.terminalKind, .none, value)
        }
        let (failure, _) = try build(try jsonEvent("Restore failed") + "\n")
        XCTAssertEqual(failure.eventLines, 1)
        XCTAssertEqual(failure.metadataLines, 0)
        XCTAssertEqual(failure.terminalKind, .failure)
        let (success, _) = try build(try jsonEvent("Restore succeeded") + "\n")
        XCTAssertEqual(success.eventLines, 1)
        XCTAssertEqual(success.metadataLines, 0)
        XCTAssertEqual(success.terminalKind, .success)
    }

    func test014D_invalid_bracket_line_remains_compact_event() throws {
        let (m, _) = try build("[invalid compact line]\n")
        XCTAssertEqual(m.eventLines, 1)
        XCTAssertEqual(m.metadataLines, 0)
        XCTAssertEqual(m.terminalKind, .none)
    }

    func test014D_invalid_scalar_does_not_become_event() throws {
        let (m, _) = try build("123 extra\n")
        XCTAssertEqual(m.eventLines, 0)
        XCTAssertEqual(m.metadataLines, 1)
        XCTAssertEqual(m.malformedJSONLines, 1)
        XCTAssertEqual(m.terminalKind, .none)
    }



    func test014F_leading_whitespace_json_boundary() throws {
        let nonObjects = [
            "  [\"Restore failed\"]",
            "\t[\"Restore succeeded\"]",
            "  \"Restore failed\"",
            "\t\"Restore succeeded\"",
            "  123",
            "\t-12.5",
            "  true",
            "\tfalse",
            "  null",
        ]
        for value in nonObjects {
            let (m, _) = try build(value + "\n")
            XCTAssertEqual(m.eventLines, 0, "eventLines for \(value.debugDescription)")
            XCTAssertEqual(m.metadataLines, 1, "metadataLines for \(value.debugDescription)")
            XCTAssertEqual(m.malformedJSONLines, 0, "malformed for \(value.debugDescription)")
            XCTAssertEqual(m.terminalKind, .none, "terminal for \(value.debugDescription)")
        }

        let failure = try build("  " + jsonEvent("Restore failed") + "\n")
        XCTAssertEqual(failure.0.eventLines, 1)
        XCTAssertEqual(failure.0.metadataLines, 0)
        XCTAssertEqual(failure.0.terminalKind, .failure)

        let success = try build("\t" + jsonEvent("Restore succeeded") + "\n")
        XCTAssertEqual(success.0.eventLines, 1)
        XCTAssertEqual(success.0.metadataLines, 0)
        XCTAssertEqual(success.0.terminalKind, .success)

        let wrongTypes = [
            #"  {"timestamp":123,"eventMessage":"Restore failed"}"#,
            "\t" + #"{"timestamp":"2026-11-08T01:00:00Z","eventMessage":123}"#,
        ]
        for value in wrongTypes {
            let (m, _) = try build(value + "\n")
            XCTAssertEqual(m.eventLines, 0, value)
            XCTAssertEqual(m.metadataLines, 1, value)
            XCTAssertEqual(m.terminalKind, .none, value)
        }

        let compact = try build("  [invalid compact line]\n")
        XCTAssertEqual(compact.0.eventLines, 1)
        XCTAssertEqual(compact.0.metadataLines, 0)
        XCTAssertEqual(compact.0.terminalKind, .none)

        let timestamp = try build("  2026-11-06 10:00:01.000 Restore failed\n")
        XCTAssertEqual(timestamp.0.eventLines, 1)
        XCTAssertEqual(timestamp.0.metadataLines, 0)
        XCTAssertEqual(timestamp.0.terminalKind, .failure)
    }

}

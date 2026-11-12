import XCTest
import Foundation
@testable import RestoreLogEngine

final class RLM12OfflineMetricsDump: XCTestCase {
    func testDumpNoiseReductionMetrics() throws {
        // Test isolation (Agent C ISO-1): env → EVROOT fixtures → bundle.
        // Shared /tmp/rlm12_fixtures ONLY if RLM12_ALLOW_TMP_FIXTURES=1 (default off).
        let envRoot = ProcessInfo.processInfo.environment["RLM12_FIXTURES_DIR"]
        let allowTmp = ProcessInfo.processInfo.environment["RLM12_ALLOW_TMP_FIXTURES"] == "1"
        let evrootFixtures = URL(fileURLWithPath:
            "/Users/niubanxiandetuzhichakanqi/Desktop/gongzuoqu/RUN_RLM_1_2_P0_TARGETED_REMEDIATION_003_20261106T192921Z/fixtures",
            isDirectory: true)
        var candidates: [URL] = [
            envRoot.map { URL(fileURLWithPath: $0, isDirectory: true) },
            evrootFixtures,
            Bundle.module.resourceURL?.appendingPathComponent("Fixtures", isDirectory: true),
        ].compactMap { $0 }
        if allowTmp {
            candidates.append(URL(fileURLWithPath: "/tmp/rlm12_fixtures", isDirectory: true))
        }
        var resolvedFail: URL?
        var resolvedOk: URL?
        for root in candidates {
            let f = root.appendingPathComponent("fail_537561A7.log")
            let o = root.appendingPathComponent("ok_9caca5ec.log")
            if FileManager.default.fileExists(atPath: f.path),
               FileManager.default.fileExists(atPath: o.path)
            {
                resolvedFail = f
                resolvedOk = o
                break
            }
        }
        XCTAssertNotNil(resolvedFail, "hermetic fail fixture missing (set RLM12_FIXTURES_DIR or provide Tests Fixtures)")
        XCTAssertNotNil(resolvedOk, "hermetic ok fixture missing")
        let failRaw = resolvedFail!
        let okRaw = resolvedOk!

        let outDir = FileManager.default.temporaryDirectory.appendingPathComponent("rlm12-metrics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let failDiag = outDir.appendingPathComponent("fail_diagnostic.log")
        let okDiag = outDir.appendingPathComponent("ok_diagnostic.log")

        let failM = try DiagnosticLogBuilder.build(fromRaw: failRaw, to: failDiag)
        let okM = try DiagnosticLogBuilder.build(fromRaw: okRaw, to: okDiag)

        func count(_ text: String, _ needle: String) -> Int {
            text.components(separatedBy: needle).count - 1
        }
        let failRawText = try String(contentsOf: failRaw, encoding: .utf8)
        let failDiagText = try String(contentsOf: failDiag, encoding: .utf8)
        let okRawText = try String(contentsOf: okRaw, encoding: .utf8)
        let okDiagText = try String(contentsOf: okDiag, encoding: .utf8)

        let probes = [
            "DeviceService", "InternetService", "boringssl", "nw_endpoint", "nw_connection",
            "CFNetwork", "TLS", "DNS", "AMAuthInstall", "update_madea", "mcdp29xx",
            "RamrodErrorDomain", "AMRestoreErrorDomain", "Restore failed", "Restore succeeded",
            "progress -1", "updater_output", "tss_submit_job_with_retry", "TSS_ERR_", "Wrote updater output"
        ]

        var failProbe: [String: [String: Int]] = [:]
        var okProbe: [String: [String: Int]] = [:]
        for p in probes {
            failProbe[p] = ["raw": count(failRawText, p), "diag": count(failDiagText, p)]
            okProbe[p] = ["raw": count(okRawText, p), "diag": count(okDiagText, p)]
        }

        // Section headers present in BOT-E order
        let sectionOrder = DiagnosticLogBuilder.DiagnosticSection.allCases.map(\.rawValue)
        var failSections: [String: Bool] = [:]
        for s in sectionOrder { failSections[s] = failDiagText.contains("## \(s)") || failDiagText.contains(s) }

        let payload: [String: Any] = [
            "task": "RLM_1_2_DIAGNOSTIC_CAPTURE_ENGINE",
            "measuredAt": ISO8601DateFormatter().string(from: Date()),
            "fixtures": [
                "fail": "fail_537561A7.log",
                "ok": "ok_9caca5ec.log"
            ],
            "fail": [
                "rawLines": failM.rawLines,
                "rawBytes": failM.rawBytes,
                "diagnosticLines": failM.diagnosticLines,
                "diagnosticBytes": failM.diagnosticBytes,
                "keptLines": failM.keptLines,
                "droppedLines": failM.droppedLines,
                "noiseReductionPercent": failM.noiseReductionPercent,
                "terminalKind": failM.terminalKind.rawValue,
                "preservedNeedles": failM.preservedNeedles,
                "substringProbes": failProbe
            ],
            "ok": [
                "rawLines": okM.rawLines,
                "rawBytes": okM.rawBytes,
                "diagnosticLines": okM.diagnosticLines,
                "diagnosticBytes": okM.diagnosticBytes,
                "keptLines": okM.keptLines,
                "droppedLines": okM.droppedLines,
                "noiseReductionPercent": okM.noiseReductionPercent,
                "terminalKind": okM.terminalKind.rawValue,
                "preservedNeedles": okM.preservedNeedles,
                "substringProbes": okProbe
            ],
            "sectionOrder": sectionOrder,
            "failSectionHeadersPresent": failSections,
            "gates": [
                "REAL_UPDATER_BODY_CAPTURED": "NO",
                "progress_minus_1_not_terminal": failM.terminalKind == .failure && (failM.preservedNeedles["progress -1"] ?? 0) >= 0
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let dumpURL = outDir.appendingPathComponent("NOISE_REDUCTION_METRICS.json")
        try data.write(to: dumpURL)
        // Isolation: metrics stay under unique outDir only (no shared /tmp mirrors).

        XCTAssertEqual(failM.terminalKind, .failure)
        XCTAssertEqual(okM.terminalKind, .success)
        XCTAssertGreaterThan(failM.noiseReductionPercent, 90.0, "1.2 denoise should drop >> 1.1 ~76%")
        // SIGNAL preserved
        XCTAssertGreaterThan(failM.preservedNeedles["Restore failed"] ?? 0, 0)
        XCTAssertGreaterThan(failM.preservedNeedles["update_madea"] ?? 0, 0)
        XCTAssertGreaterThan(failM.preservedNeedles["RamrodErrorDomain"] ?? 0, 0)
        // Network NOISE collapsed
        XCTAssertLessThan(failProbe["boringssl"]!["diag"]!, failProbe["boringssl"]!["raw"]!)
        // DeviceService process token still appears on SIGNAL lines; must be << 1.1 diag baseline (~7352).
        XCTAssertLessThan(failProbe["DeviceService"]!["diag"]!, 2000, "DeviceService CONTEXT over-match removed")
        XCTAssertLessThan(failProbe["boringssl"]!["diag"]!, 50)
        XCTAssertLessThan(failProbe["TLS"]!["diag"]!, 80)
    }
}

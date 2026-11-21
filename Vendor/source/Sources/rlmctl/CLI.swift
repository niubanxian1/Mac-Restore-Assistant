import Foundation
import RestoreLogEngine

/// Headless proof that the capture core runs with no window, no SwiftUI, and
/// no Apple Configurator present. This is the command the future Mac Restore
/// Adapter is expected to resemble.
@main
struct CLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let command = args.first ?? "help"

        do {
            switch command {
            case "selftest":
                try await runSelfTest(arguments: Array(args.dropFirst()))
            case "probe":
                try runProbe()
            default:
                printUsage()
                exit(2)
            }
        } catch {
            FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func printUsage() {
        print("""
        rlmctl — Restore Log Engine headless control

          rlmctl selftest [--output <dir>]   run a full session against a simulated backend
          rlmctl probe                       check /usr/bin/log availability (read-only)
        """)
    }

    // MARK: - selftest

    private struct SelfTestReport: Encodable {
        let sessionID: String
        let captureBackend: String
        let captureState: String
        let captureHealth: String
        let coverageStatus: String
        let integrityStatus: String
        let archiveStatus: String
        let eventCount: Int
        let rawLogPath: String
        let rawLogBytes: Int
        let rawLogSHA256: String
        let sessionJSONPath: String
        let sha256SumsPath: String
        let missingEvidence: [String]
    }

    private static func runSelfTest(arguments: [String]) async throws {
        var outputRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlm-selftest-\(UUID().uuidString)", isDirectory: true)

        if let index = arguments.firstIndex(of: "--output"), arguments.count > index + 1 {
            outputRoot = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        }
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        let store = EvidenceStore(root: outputRoot.appendingPathComponent("Sessions", isDirectory: true))
        let engine = CaptureCoordinator(backend: SimulatedLogCaptureBackend(), store: store)

        // P0-N1: self-test leaves ecidHint unset on purpose — production without a
        // real ECID/nonce must not pretend random UUID updater dirs are BOUND.
        let session = try await engine.beginCapture(
            config: CaptureConfig(outputDirectory: outputRoot, ecidHint: nil)
        )
        _ = try await engine.getStatus(sessionID: session.sessionID)
        _ = try await engine.stopCapture(sessionID: session.sessionID)
        let exported = try await engine.finalize(sessionID: session.sessionID)
        let summary = try await engine.getEventSummary(sessionID: session.sessionID)

        let raw = exported.record.files.first { $0.role == "raw-log" }
        let report = SelfTestReport(
            sessionID: session.sessionID.uuidString,
            captureBackend: exported.record.captureBackend,
            captureState: exported.record.captureState.rawValue,
            captureHealth: exported.record.captureHealth.rawValue,
            coverageStatus: exported.record.coverageStatus.rawValue,
            integrityStatus: exported.record.integrityStatus.rawValue,
            archiveStatus: exported.record.archiveStatus.rawValue,
            eventCount: exported.record.eventCount,
            rawLogPath: session.rawLogPath,
            rawLogBytes: raw?.byteSize ?? 0,
            rawLogSHA256: raw?.sha256 ?? "",
            sessionJSONPath: exported.sessionJSONPath,
            sha256SumsPath: exported.sha256SumsPath,
            missingEvidence: exported.record.missingEvidence
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))

        print("SELFTEST_EVENT_COUNT=\(summary.totalEvents)")
        print("SELFTEST_TAXONOMY=\(summary.taxonomyVersion)")
        print("SELFTEST_OK=\(exported.record.integrityStatus == .verified ? "YES" : "NO")")
    }

    // MARK: - probe

    private static func runProbe() throws {
        let logPath = "/usr/bin/log"
        let exists = FileManager.default.isExecutableFile(atPath: logPath)

        var lineCount = 0
        var exitCode: Int32 = -1
        if exists {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: logPath)
            process.arguments = ["show", "--last", "1m", "--style", "compact"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            exitCode = process.terminationStatus
            lineCount = data.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
        }

        let payload: [String: String] = [
            "log_executable": logPath,
            "log_executable_exists": exists ? "YES" : "NO",
            "log_show_exit_code": String(exitCode),
            "log_show_lines_last_1m": String(lineCount),
            "read_only": "YES",
        ]
        let data = try JSONEncoder().encode(payload)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

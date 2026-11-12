import Foundation
import XCTest
@testable import RestoreLogEngine

/// F03 reproduction — red before the repair, green after.
///
/// Claim under test: when finalization fails, the session directory must not be
/// left holding a `session.json` that asserts `integrityStatus: verified`.
///
/// Injection is deterministic and local: inside an isolated temporary session
/// directory, the `SHA256SUMS.txt` path is created as a *directory*, so the
/// manifest's atomic write fails with EISDIR. No system log, no system
/// permission, no device, and no concurrency is involved.
final class F03ReproTests: XCTestCase {
    private var root: URL = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlm-f03-repro-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testFailedFinalizationMustNotLeaveVerifiedMetadata() async throws {
        let engine = CaptureCoordinator(
            backend: SimulatedLogCaptureBackend(),
            store: EvidenceStore(root: root.appendingPathComponent("Sessions", isDirectory: true))
        )
        let session = try await engine.beginCapture(config: CaptureConfig(outputDirectory: root))
        _ = try await engine.stopCapture(sessionID: session.sessionID)

        let sessionDir = URL(fileURLWithPath: session.outputDirectory, isDirectory: true)
        let sumsPath = sessionDir.appendingPathComponent("SHA256SUMS.txt")
        try FileManager.default.createDirectory(at: sumsPath, withIntermediateDirectories: true)

        var finalizeThrew = false
        do {
            _ = try await engine.finalize(sessionID: session.sessionID)
        } catch {
            finalizeThrew = true
        }
        XCTAssertTrue(
            finalizeThrew,
            "finalize must not report success when the checksum manifest cannot be written"
        )

        let jsonPath = sessionDir.appendingPathComponent("session.json")
        let exists = FileManager.default.fileExists(atPath: jsonPath.path)
        let onDisk: String
        if let data = try? Data(contentsOf: jsonPath),
           let text = String(data: data, encoding: .utf8) {
            onDisk = text
        } else {
            onDisk = "<absent>"
        }

        XCTAssertFalse(
            exists,
            "F03: a FAILED finalization left session.json on disk. on-disk content was: \(onDisk)"
        )
        XCTAssertFalse(
            onDisk.contains("\"verified\""),
            "F03: on-disk metadata claims integrityStatus=verified although finalization failed: \(onDisk)"
        )

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: session.rawLogPath),
            "F03: raw evidence must be preserved when finalization fails"
        )
    }
}

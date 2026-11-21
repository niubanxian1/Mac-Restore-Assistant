import XCTest
import Foundation
@testable import RestoreLogEngine

final class ImportedDiagnosticAnalysisTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlm-014h-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    func testImportAnalyzerDelegatesToBuilderAndPreservesRaw() throws {
        let raw = root.appendingPathComponent("import_ok.log")
        let text = """
        Filtering the log data using "process CONTAINS[c] "configurator""

        2026-11-08 01:00:00.000 Restore succeeded
        2026-11-08 01:00:01.000 restore was successful
        """
        try Data(text.utf8).write(to: raw)
        let before = try Data(contentsOf: raw)
        let diagnostic = root.appendingPathComponent("diagnostic.log")
        let analysis = try ImportedDiagnosticAnalyzer.analyze(rawURL: raw, diagnosticURL: diagnostic)

        XCTAssertEqual(analysis.terminalKind, .success)
        XCTAssertEqual(analysis.eventLines, 2)
        XCTAssertEqual(analysis.metadataLines, 2)
        XCTAssertEqual(analysis.rawPath, raw.path)
        XCTAssertEqual(analysis.diagnosticPath, diagnostic.path)
        XCTAssertEqual(try Data(contentsOf: raw), before, "import analysis must not modify raw")
        XCTAssertTrue(FileManager.default.fileExists(atPath: diagnostic.path))
        XCTAssertEqual(analysis.diagnosticBytes, try Integrity.byteSize(ofFileAt: diagnostic))
    }

    func testPackageContainsRawFullDiagnosticTimelineMetadataAndSums() throws {
        let raw = root.appendingPathComponent("import_fail.log")
        let text = """
        Filtering the log data using "process CONTAINS[c] "configurator""

        2026-11-08 01:00:00.000 Restore failed (result = -1)
        2026-11-08 01:00:01.000 CFError domain:AMRestoreErrorDomain code:-1
        2026-11-08 01:00:02.000 RamrodErrorDomain code:7 update_madea
        """
        try Data(text.utf8).write(to: raw)
        let before = try Data(contentsOf: raw)
        let diagnostic = root.appendingPathComponent("diagnostic.log")
        let analysis = try ImportedDiagnosticAnalyzer.analyze(rawURL: raw, diagnosticURL: diagnostic)

        XCTAssertEqual(analysis.terminalKind, .failure)
        XCTAssertEqual(analysis.eventLines, 3)
        XCTAssertEqual(analysis.metadataLines, 2)
        XCTAssertGreaterThan(analysis.preservedNeedles["Restore failed"] ?? 0, 0)

        let packageDir = root.appendingPathComponent("EvidencePackage", isDirectory: true)
        let package = try ImportedEvidencePackageBuilder.build(
            rawURL: raw,
            diagnosticURL: diagnostic,
            analysis: analysis,
            destination: packageDir
        )
        XCTAssertEqual(package.directoryPath, packageDir.path)
        let packagedRaw = packageDir.appendingPathComponent("raw/import_fail.log")
        XCTAssertEqual(try Data(contentsOf: packagedRaw), before, "packaged raw must be byte-identical")
        XCTAssertEqual(try Data(contentsOf: packageDir.appendingPathComponent("diagnostic.log")),
                       try Data(contentsOf: diagnostic))
        XCTAssertEqual(try Data(contentsOf: packageDir.appendingPathComponent("TIMELINE_AND_KEY_ERROR_CONTEXT.log")),
                       try Data(contentsOf: diagnostic))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageDir.appendingPathComponent("import-metadata.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageDir.appendingPathComponent("session-metadata.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageDir.appendingPathComponent("EVIDENCE_COVERAGE.ini").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageDir.appendingPathComponent("SHA256SUMS.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageDir.appendingPathComponent("PACKAGE_MANIFEST.json").path))

        let sessionData = try Data(contentsOf: packageDir.appendingPathComponent("session-metadata.json"))
        let session = try JSONSerialization.jsonObject(with: sessionData) as? [String: Any]
        XCTAssertEqual(session?["status"] as? String, "NOT_AVAILABLE")
        let coverage = try String(contentsOf: packageDir.appendingPathComponent("EVIDENCE_COVERAGE.ini"))
        XCTAssertTrue(coverage.contains("CAPTURE_SESSION_METADATA=NOT_AVAILABLE"))
        XCTAssertTrue(coverage.contains("RAW_LOG_MUTATED=NO"))
        XCTAssertTrue(package.files.contains { $0.role == "raw-log" })
        XCTAssertTrue(package.files.contains { $0.role == "sha256-sums" })
    }

    func testPackageRefusesExistingDestination() throws {
        let raw = root.appendingPathComponent("import.log")
        try Data("2026-11-08 01:00:00.000 Restore succeeded\n".utf8).write(to: raw)
        let diagnostic = root.appendingPathComponent("diag.log")
        let analysis = try ImportedDiagnosticAnalyzer.analyze(rawURL: raw, diagnosticURL: diagnostic)
        let destination = root.appendingPathComponent("existing", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        XCTAssertThrowsError(
            try ImportedEvidencePackageBuilder.build(
                rawURL: raw, diagnosticURL: diagnostic, analysis: analysis, destination: destination
            )
        )
    }
}

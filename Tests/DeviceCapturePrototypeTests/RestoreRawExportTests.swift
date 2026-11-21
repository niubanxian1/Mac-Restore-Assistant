import Foundation
import XCTest
@testable import DeviceCapturePrototype

final class RestoreRawExportTests: XCTestCase {
    private var root: URL!
    private var attemptID: UUID!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        attemptID = UUID()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testExportCreatesZipAndKeepsArchive() throws {
        let archive = try makeArchive()
        let destination = root.appendingPathComponent("export.zip")
        let result = try RestoreRawArchiveExporter.export(
            archive: archive,
            attemptID: attemptID,
            destination: destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertGreaterThan(result.bytes, 0)
        XCTAssertEqual(result.url, destination)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: archive.directoryPath),
            "导出不得移动或删除原归档")
        XCTAssertEqual(result.sha256.count, 64)
    }

    func testAttemptMismatchIsRejected() throws {
        let archive = try makeArchive()
        XCTAssertThrowsError(try RestoreRawArchiveExporter.export(
            archive: archive,
            attemptID: UUID(),
            destination: root.appendingPathComponent("bad.zip"))) { error in
            guard case RestoreRawExportError.attemptMismatch = error else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    func testTamperedFileIsRejectedBeforeExport() throws {
        let archive = try makeArchive()
        let file = URL(fileURLWithPath: archive.directoryPath)
            .appendingPathComponent("stdout.log")
        try Data("tampered".utf8).write(to: file)
        XCTAssertThrowsError(try RestoreRawArchiveExporter.export(
            archive: archive,
            attemptID: attemptID,
            destination: root.appendingPathComponent("bad2.zip")))
    }

    func testMissingManifestIsRejected() throws {
        let archive = try makeArchive()
        try FileManager.default.removeItem(
            atPath: archive.manifestPath)
        XCTAssertThrowsError(try RestoreRawArchiveExporter.export(
            archive: archive,
            attemptID: attemptID,
            destination: root.appendingPathComponent("bad3.zip")))
    }


    func testG4TwoArchiveZIPContentEvidence() throws {
        let evidence = URL(fileURLWithPath: "/tmp/MRA_G4_LOWER_ZIP_EVIDENCE", isDirectory: true)
        try? FileManager.default.removeItem(at: evidence)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        var outputs: [(String, URL)] = []
        for tag in ["A", "B"] {
            let id = UUID()
            let directory = evidence.appendingPathComponent("archive-\(tag)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stdout = Data("G4_\(tag)_STDOUT task=\(id.uuidString)\n".utf8)
            let stderr = Data("G4_\(tag)_STDERR task=\(id.uuidString)\n".utf8)
            try stdout.write(to: directory.appendingPathComponent("stdout.raw"))
            try stderr.write(to: directory.appendingPathComponent("stderr.raw"))
            let manifest = RestoreArchiveManifest(
                schemaVersion: 1,
                archiveID: "archive-\(id.uuidString.prefix(8))",
                taskID: id,
                attemptID: id,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                outcome: .success,
                modelFamilyKey: "MacBookPro18,2",
                rawEvidenceComplete: true,
                baselineEligible: false,
                directorySyncLevel: .standard,
                files: [
                    RestoreArchiveManifestFile(relativePath: "stdout.raw", sizeBytes: Int64(stdout.count), sha256: sha256(stdout)),
                    RestoreArchiveManifestFile(relativePath: "stderr.raw", sizeBytes: Int64(stderr.count), sha256: sha256(stderr)),
                ])
            let manifestURL = directory.appendingPathComponent("manifest.json")
            let data = try JSONEncoder().encode(manifest)
            try data.write(to: manifestURL)
            let archive = RestoreArchiveRecord(
                archiveID: manifest.archiveID,
                taskID: id,
                attemptID: id,
                directoryPath: directory.path,
                manifestPath: manifestURL.path,
                manifestSHA256: sha256(data),
                outcome: .success,
                modelFamilyKey: "MacBookPro18,2",
                publishedAt: Date(),
                directorySyncLevel: .standard,
                localStagingRetained: false,
                baselineEligible: false)
            let dest = evidence.appendingPathComponent("\(tag)_EXPORT.zip")
            let result = try RestoreRawArchiveExporter.export(
                archive: archive, attemptID: id, destination: dest)
            XCTAssertGreaterThan(result.bytes, 0)
            outputs.append((tag, dest))
        }
        XCTAssertNotEqual(outputs[0].1, outputs[1].1)
    }
    private func makeArchive() throws -> RestoreArchiveRecord {
        let directory = root.appendingPathComponent("archive", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stdout = Data("MRA_FIXTURE_RAW task=\(attemptID.uuidString)\n".utf8)
        try stdout.write(to: directory.appendingPathComponent("stdout.log"))
        let manifest = RestoreArchiveManifest(
            schemaVersion: 1,
            archiveID: "archive-\(attemptID.uuidString.prefix(8))",
            taskID: attemptID,
            attemptID: attemptID,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            outcome: .success,
            modelFamilyKey: "Mac14,2",
            rawEvidenceComplete: true,
            baselineEligible: false,
            directorySyncLevel: .standard,
            files: [RestoreArchiveManifestFile(
                relativePath: "stdout.log",
                sizeBytes: Int64(stdout.count),
                sha256: sha256(stdout))])
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL)
        return RestoreArchiveRecord(
            archiveID: manifest.archiveID,
            taskID: attemptID,
            attemptID: attemptID,
            directoryPath: directory.path,
            manifestPath: manifestURL.path,
            manifestSHA256: sha256(data),
            outcome: .success,
            modelFamilyKey: "Mac14,2",
            publishedAt: Date(),
            directorySyncLevel: .standard,
            localStagingRetained: false,
            baselineEligible: false)
    }

    private func sha256(_ data: Data) -> String {
        var hash = SHA256()
        hash.update(data: data)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

import CryptoKit

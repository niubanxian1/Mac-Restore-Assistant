import CryptoKit
import Foundation
import XCTest
@testable import DeviceCapturePrototype

final class Batch2IPSWIdentityTests: XCTestCase {
    func testIPSWIdentityUsesDarwinNanosecondMetadataAndManifestDigest() throws {
        let url = try makeIPSW(
            manifest: manifest(version: "27.9", build: "26C99", board: 0x24, chip: 0x8132))

        let first = try IPSWMetadataReader.read(url: url)
        let second = try IPSWMetadataReader.read(url: url)
        let identity = try XCTUnwrap(first.fileIdentity)

        XCTAssertEqual(identity, second.fileIdentity)
        XCTAssertGreaterThan(identity.sizeBytes, 0)
        XCTAssertGreaterThan(identity.mtimeNs, 0)
        XCTAssertGreaterThan(identity.ctimeNs, 0)
        XCTAssertEqual(identity.buildManifestSHA256.count, 64)
        XCTAssertEqual(
            identity.buildManifestSHA256,
            IPSWMetadataReader.sha256Hex(
                try extractManifestData(from: url)))
        XCTAssertEqual(
            URL(fileURLWithPath: identity.canonicalRealpath).resolvingSymlinksInPath(),
            url.resolvingSymlinksInPath())
    }

    func testManifestHashAndWholeFileHashRemainSeparate() throws {
        let url = try makeIPSW(
            manifest: manifest(version: "14.0", build: "23A344", board: 0x24, chip: 0x8132))
        let result = try IPSWMetadataReader.read(url: url)
        let identity = try XCTUnwrap(result.fileIdentity)
        let wholeDigest = IPSWMetadataReader.sha256Hex(try Data(contentsOf: url))

        XCTAssertEqual(identity.buildManifestSHA256, result.buildManifestSHA256)
        XCTAssertNotEqual(identity.buildManifestSHA256, wholeDigest)
        XCTAssertNil(result.wholeFileSHA256)
    }

    func testReplacingIPSWInvalidatesPreviouslyCapturedIdentity() throws {
        let url = try makeIPSW(
            manifest: manifest(version: "14.0", build: "23A344", board: 0x24, chip: 0x8132))
        let expected = try XCTUnwrap(
            IPSWMetadataReader.read(url: url).fileIdentity)

        let replacement = try makeIPSW(
            manifest: manifest(version: "14.1", build: "23B100", board: 0x25, chip: 0x8132))
        try Data(contentsOf: replacement).write(to: url, options: .atomic)

        let verification = try IPSWMetadataReader.verifyIdentity(
            url: url,
            expected: expected)

        guard case .changed(let actual) = verification else {
            return XCTFail("A replaced IPSW must not retain the old identity")
        }
        XCTAssertNotEqual(actual, expected)
    }

    func testMetadataChangeTimeIsNotTheFileCreationDate() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Batch2Identity-\(UUID().uuidString).bin")
        try Data(repeating: 0x41, count: 64).write(to: url)

        let before = try IPSWMetadataReader.fileIdentity(
            url: url,
            buildManifestSHA256: String(repeating: "a", count: 64))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path)
        let after = try IPSWMetadataReader.fileIdentity(
            url: url,
            buildManifestSHA256: String(repeating: "a", count: 64))

        XCTAssertNotEqual(after.ctimeNs, before.ctimeNs)
        XCTAssertEqual(after.mtimeNs, before.mtimeNs)
        XCTAssertEqual(after.dev, before.dev)
        XCTAssertEqual(after.ino, before.ino)
    }

    func testSizeAndModificationTimeChangesInvalidateIdentity() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Batch2SizeTime-\(UUID().uuidString).bin")
        try Data(repeating: 0x41, count: 64).write(to: url)
        let before = try IPSWMetadataReader.fileIdentity(
            url: url,
            buildManifestSHA256: String(repeating: "a", count: 64))

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0x42]))
        try handle.close()
        let after = try IPSWMetadataReader.fileIdentity(
            url: url,
            buildManifestSHA256: String(repeating: "a", count: 64))

        XCTAssertGreaterThan(after.sizeBytes, before.sizeBytes)
        XCTAssertNotEqual(after.mtimeNs, before.mtimeNs)
        XCTAssertNotEqual(after, before)
    }

    func testValidFilePassesIdentityRevalidation() throws {
        let url = try makeIPSW(
            manifest: manifest(version: "14.0", build: "23A344", board: 0x24, chip: 0x8132))
        let expected = try XCTUnwrap(
            IPSWMetadataReader.read(url: url).fileIdentity)

        let verification = try IPSWMetadataReader.verifyIdentity(
            url: url,
            expected: expected)

        guard case .valid(let actual, let metadata) = verification else {
            return XCTFail("Unchanged IPSW should pass revalidation")
        }
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(metadata.productVersion, "14.0")
    }

    private func manifest(
        version: String,
        build: String,
        board: Int,
        chip: Int
    ) -> [String: Any] {
        [
            "SupportedProductTypes": ["Mac14,2"],
            "ProductVersion": version,
            "ProductBuildVersion": build,
            "BuildIdentities": [[
                "ApBoardID": board,
                "ApChipID": chip,
                "Info": ["DeviceClass": "j413ap"]
            ]]
        ]
    }

    private func makeIPSW(manifest: [String: Any]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Batch2IPSWIdentity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: manifest,
            format: .xml,
            options: 0)
        try data.write(to: root.appendingPathComponent("BuildManifest.plist"))

        let zip = FileManager.default.temporaryDirectory
            .appendingPathComponent("Batch2IPSWIdentity-\(UUID().uuidString).ipsw")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", root.path, zip.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return zip
    }

    private func extractManifestData(from url: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, "BuildManifest.plist"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return data
    }
}

import Foundation
import XCTest
@testable import DeviceCapturePrototype

final class IPSWMetadataReaderTests: XCTestCase {
    func testSystemVersionIsOptionalWhileBuildManifestEstablishesValidity() throws {
        let url = try makeIPSW(
            manifest: manifest(products: ["Mac14,2"], board: 0x24, chip: 0x8132),
            systemVersion: nil)

        let result = try IPSWMetadataReader.read(url: url)
        XCTAssertEqual(result.validity, .valid)
        XCTAssertEqual(result.metadata?.productTypes, ["Mac14,2"])
        XCTAssertEqual(result.metadata?.boardChipPairs.count, 1)
        XCTAssertEqual(result.metadata?.deviceClasses, ["j413ap"])
    }

    func testMissingBuildManifestMakesFirmwareInvalid() throws {
        let url = try makeIPSW(manifest: nil, systemVersion: ["ProductVersion": "14.0"])
        let result = try IPSWMetadataReader.read(url: url)
        XCTAssertEqual(result.validity, .invalid)
        XCTAssertNil(result.metadata)
    }

    func testCompatibilityUsesSameBuildIdentityAndDistinguishesUnknownFromIncompatible() throws {
        let metadata = try XCTUnwrap(
            IPSWMetadataReader.read(url: try makeIPSW(
                manifest: manifest(products: ["Mac14,2"], board: 0x24, chip: 0x8132),
                systemVersion: nil)).metadata)

        XCTAssertEqual(
            IPSWCompatibilityEvaluator.evaluate(
                metadata: metadata,
                target: RestoreTargetIdentity(
                    productType: "Mac14,2",
                    deviceClass: "j413ap",
                    boardID: 0x24,
                    chipID: 0x8132)).status,
            .compatible)

        XCTAssertEqual(
            IPSWCompatibilityEvaluator.evaluate(
                metadata: metadata,
                target: RestoreTargetIdentity(
                    productType: "Mac14,2",
                    deviceClass: nil,
                    boardID: nil,
                    chipID: nil)).status,
            .unverified)

        XCTAssertEqual(
            IPSWCompatibilityEvaluator.evaluate(
                metadata: metadata,
                target: RestoreTargetIdentity(
                    productType: "Mac14,2",
                    deviceClass: "j413ap",
                    boardID: 0x25,
                    chipID: 0x8132)).status,
            .incompatible)

        XCTAssertEqual(
            IPSWCompatibilityEvaluator.evaluate(
                metadata: metadata,
                target: RestoreTargetIdentity(
                    productType: "Mac14,3",
                    deviceClass: nil,
                    boardID: nil,
                    chipID: nil)).status,
            .incompatible)
    }

    func testSharedEvaluatorInfersUniqueClassAndKeepsAmbiguityStrict() {
        let identity = IPSWBuildIdentity(
            deviceClass: "j413ap",
            boardID: 0x28,
            chipID: 0x8112)
        let metadata = IPSWMetadata(
            productTypes: ["Mac14,2"],
            identities: [identity],
            productVersion: "27.0",
            productBuild: "26A428")
        let target = RestoreTargetIdentity(
            productType: "Mac14,2",
            deviceClass: nil,
            boardID: 0x28,
            chipID: 0x8112)

        XCTAssertEqual(
            IPSWCompatibilityEvaluator.evaluate(
                metadata: metadata,
                target: target).status,
            .compatible)
        XCTAssertEqual(
            IPSWCompatibilityEvaluator.evaluate(
                metadata: metadata,
                target: RestoreTargetIdentity(
                    productType: "Mac14,2",
                    deviceClass: nil,
                    boardID: nil,
                    chipID: nil)).status,
            .unverified)

        let ambiguous = IPSWMetadata(
            productTypes: ["Mac14,2"],
            identities: [
                identity,
                IPSWBuildIdentity(
                    deviceClass: "j414ap",
                    boardID: 0x28,
                    chipID: 0x8112)
            ],
            productVersion: "27.0",
            productBuild: "26A428")
        XCTAssertEqual(
            IPSWCompatibilityEvaluator.evaluate(
                metadata: ambiguous,
                target: target).status,
            .unverified)
    }

    private func manifest(
        products: [String],
        board: Int,
        chip: Int
    ) -> [String: Any] {
        [
            "SupportedProductTypes": products,
            "ProductVersion": "14.0",
            "ProductBuildVersion": "23A344",
            "BuildIdentities": [[
                "ApBoardID": board,
                "ApChipID": chip,
                "Info": ["DeviceClass": "j413ap"]
            ]]
        ]
    }

    private func makeIPSW(
        manifest: [String: Any]?,
        systemVersion: [String: Any]?
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IPSWMetadataReaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let manifest {
            let data = try PropertyListSerialization.data(
                fromPropertyList: manifest,
                format: .xml,
                options: 0)
            try data.write(to: root.appendingPathComponent("BuildManifest.plist"))
        }
        if let systemVersion {
            let data = try PropertyListSerialization.data(
                fromPropertyList: systemVersion,
                format: .xml,
                options: 0)
            try data.write(to: root.appendingPathComponent("SystemVersion.plist"))
        }

        let zip = FileManager.default.temporaryDirectory
            .appendingPathComponent("IPSWMetadataReaderTests-\(UUID().uuidString).ipsw")
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
}

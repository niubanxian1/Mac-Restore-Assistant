import Foundation
import XCTest
@testable import DeviceCapturePrototype

final class FirmwareDiscoveryTests: XCTestCase {
    func testPolicyDefersDuringRestoreAndCoalescesDuplicateRequests() {
        XCTAssertEqual(
            FirmwareDiscoveryPolicy.action(
                isRestoreActive: true,
                isScanning: false),
            .deferForRestore)
        XCTAssertEqual(
            FirmwareDiscoveryPolicy.action(
                isRestoreActive: false,
                isScanning: true),
            .coalesce)
        XCTAssertEqual(
            FirmwareDiscoveryPolicy.action(
                isRestoreActive: false,
                isScanning: false),
            .start)
    }

    func testForbiddenRootsAndPaths() {
        for path in ["/", "/System", "/Library", "/private", "/System/Volumes", "/Volumes"] {
            XCTAssertTrue(
                isForbiddenFirmwareDiscoveryRoot(URL(fileURLWithPath: path)),
                path)
        }
        XCTAssertFalse(
            isForbiddenFirmwareDiscoveryRoot(
                FileManager.default.homeDirectoryForCurrentUser))
        XCTAssertTrue(
            isForbiddenFirmwareDiscoveryPath(
                URL(fileURLWithPath: "/Users/x/.Trash/UniversalMac.ipsw")))
        XCTAssertTrue(
            isForbiddenFirmwareDiscoveryPath(
                URL(fileURLWithPath: "/System/Library/UniversalMac.ipsw")))
        XCTAssertTrue(
            isForbiddenFirmwareDiscoveryPath(
                URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("UniversalMac.ipsw")))
    }

    func testICloudPlaceholderNameIsNotAnIPSWToOpen() {
        XCTAssertTrue(isICloudPlaceholderName("UniversalMac.ipsw.icloud"))
        XCTAssertFalse(isICloudPlaceholderName("UniversalMac.ipsw"))
    }
}

final class FirmwareDiscoveryViewContractTests: XCTestCase {
    private func read(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relative),
            encoding: .utf8)
    }

    func testLibraryHeaderHasCompactAddRescanAndScanningIndicator() throws {
        let view = try read("Sources/DeviceCapturePrototype/FirmwareRestoreWorkspaceView.swift")
        XCTAssertTrue(view.contains("ui2-prep-library-add"))
        XCTAssertTrue(view.contains("ui2-prep-library-rescan"))
        XCTAssertTrue(view.contains("ui2-prep-library-scanning"))
        XCTAssertTrue(view.contains("添加目录…"))
        XCTAssertTrue(view.contains("重新扫描"))
    }

    func testSettingsHasAutoScanToggleAndRootRemoval() throws {
        let settings = try read("Sources/DeviceCapturePrototype/FirmwarePreferencesSettingsView.swift")
        XCTAssertTrue(settings.contains("firmware-auto-scan-toggle"))
        XCTAssertTrue(settings.contains("启动时自动扫描本机 IPSW"))
        XCTAssertTrue(settings.contains("firmwareLibraryRoots"))
        XCTAssertTrue(settings.contains("removeFirmwareDirectory"))
    }

    func testModelHasSingleFlightDeferAndCancellation() throws {
        let model = try read("Sources/DeviceCapturePrototype/RestoreWorkspaceModel.swift")
        XCTAssertTrue(model.contains("FirmwareDiscoveryPolicy.action"))
        XCTAssertTrue(model.contains("firmwareDiscoveryPending"))
        XCTAssertTrue(model.contains("cancelFirmwareDiscovery"))
        XCTAssertTrue(model.contains("isFirmwareDiscoveryActive"))
        XCTAssertTrue(model.contains("discoveredURLs"))
    }
}

import Foundation
import XCTest
@testable import DeviceCapturePrototype

/// P2-B 收尾：证明 UI 夹具 Restore 与生产 P1 租约隔离。
@MainActor
final class P2BFixtureLeaseIsolationTests: XCTestCase {
    private let productionLock = URL(
        fileURLWithPath: RestoreProcessLease.authoritativeLockPath)

    func testDefaultFixtureLeaseDirectoryIsIsolated() {
        let dir = UIFixture.fixtureLeaseDirectory()
        XCTAssertNotEqual(
            dir.appendingPathComponent("Restore-Slot.lease").path,
            RestoreProcessLease.authoritativeLockPath)
        XCTAssertNotEqual(
            dir.appendingPathComponent("Restore-Slot.lease").lastPathComponent,
            URL(fileURLWithPath: RestoreProcessLease.authoritativeLockPath)
                .lastPathComponent)
        XCTAssertEqual(dir.lastPathComponent, "FixtureLease")
    }

    func testFixtureLeaseUsesIsolatedTempPath() {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("P2B-Lease-\(UUID().uuidString)", isDirectory: true)
        let lease = UIFixture.makeProcessLease(baseDirectory: base)
        XCTAssertNotEqual(lease.lockURL.path, RestoreProcessLease.authoritativeLockPath)
        XCTAssertTrue(lease.lockURL.path.hasPrefix(base.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: base.path))
    }

    func testProductionDefaultLeaseKeepsAuthoritativePath() {
        let lease = RestoreProcessLease()
        XCTAssertEqual(
            lease.lockURL.path,
            RestoreProcessLease.authoritativeLockPath)
    }

    func testFixtureLeaseLifecycleNeverTouchesProductionPaths() throws {
        let lease = UIFixture.makeProcessLease(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "P2B-Lease-\(UUID().uuidString)", isDirectory: true))
        let marker = URL(fileURLWithPath: lease.lockURL.path + ".inprogress")
        let before = productionFingerprint()

        XCTAssertEqual(lease.acquire(), .acquired)
        XCTAssertTrue(lease.writeInProgress())
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertTrue(lease.clearInProgress())
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        lease.release()

        XCTAssertEqual(productionFingerprint(), before,
                       "夹具租约不得创建/修改/清理生产锁文件或标记")
        try? FileManager.default.removeItem(
            at: lease.lockURL.deletingLastPathComponent())
    }

    func testAppOnlyInjectsFixtureLeaseWhenFixtureIsActive() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/App.swift"),
            encoding: .utf8)
        XCTAssertTrue(app.contains(
            "processLease: UIFixture.isActive\n                ? UIFixture.makeProcessLease()\n                : nil"))
    }

    func testInvalidDraftHidesNormalPreparationMessage() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let view = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/FirmwareRestoreWorkspaceView.swift"),
            encoding: .utf8)
        XCTAssertTrue(view.contains("draftStatusText(status)"))
        XCTAssertTrue(view.contains("firmwareDraftMessage(for: target)"))
        // 切片 3：B 启动按钮由 canStart 控制；不可启动时明确禁用。
        XCTAssertTrue(view.contains("secondary-start-button"))
        XCTAssertTrue(view.contains("disabled(!canStart)"))
        XCTAssertTrue(view.contains("当前无法开始 Restore"))
    }

    private func productionFingerprint() -> String {
        let marker = URL(fileURLWithPath: productionLock.path + ".inprogress")
        return [productionLock, marker].map { url -> String in
            guard
                let attributes = try? FileManager.default
                    .attributesOfItem(atPath: url.path)
            else {
                return "absent"
            }
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            let inode = (attributes[.systemFileNumber] as? NSNumber)?.int64Value ?? -1
            let mtime = (attributes[.modificationDate] as? Date)
                .map { String(Int64($0.timeIntervalSince1970)) } ?? "-1"
            return "size=\(size)|inode=\(inode)|mtime=\(mtime)"
        }.joined(separator: "\n")
    }
}

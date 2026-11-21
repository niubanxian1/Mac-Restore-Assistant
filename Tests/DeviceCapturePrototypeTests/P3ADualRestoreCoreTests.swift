import Foundation
import XCTest
@testable import DeviceCapturePrototype

/// P3-A 离线验收：双任务执行核心、注册表、独立引擎、独立取消与 P1 机器所有权。
@MainActor
final class P3ADualRestoreCoreTests: XCTestCase {
    private var engines: [P3AFakeEngine] = []

    // MARK: - 双进程重叠

    func testTwoFakeProcessesOverlapWithDistinctRequests() async throws {
        let core = makeCore()
        let a = try makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")
        let b = try makeExecution("000000000000000B", port: "left2", ipsw: "b.ipsw")
        try core.start(a)
        try core.start(b)
        await waitUntil { self.engines.count == 2 && self.engines.allSatisfy(\.started) }

        XCTAssertEqual(core.activeCount, 2)
        XCTAssertTrue(engines[0].isRunning)
        XCTAssertTrue(engines[1].isRunning)
        XCTAssertEqual(engines[0].request?.targetECID, 0xA)
        XCTAssertEqual(engines[1].request?.targetECID, 0xB)
        XCTAssertTrue(engines[0].request?.ipswURL.lastPathComponent == "a.ipsw")
        XCTAssertTrue(engines[1].request?.ipswURL.lastPathComponent == "b.ipsw")

        engines[0].release(outcome: .success, exitCode: 0)
        engines[1].release(outcome: .success, exitCode: 0)
        await core.waitUntilIdle()
        XCTAssertEqual(core.terminal.count, 2)
    }

    func testOnlyTwoAttemptsAndIdentityOccupancyAreEnforced() throws {
        let registry = RestoreTaskRegistry()
        let a = try registry.reserve(
            attemptID: UUID(), canonicalECID: "000000000000000A", portKey: "left1")
        XCTAssertEqual(a.canonicalECID, "000000000000000A")

        XCTAssertThrowsError(try registry.reserve(
            attemptID: UUID(), canonicalECID: "000000000000000A", portKey: "left2")) {
            XCTAssertEqual($0 as? RestoreTaskAdmissionError, .duplicateECID)
        }
        XCTAssertThrowsError(try registry.reserve(
            attemptID: UUID(), canonicalECID: "000000000000000B", portKey: "left1")) {
            XCTAssertEqual($0 as? RestoreTaskAdmissionError, .duplicatePort)
        }
        _ = try registry.reserve(
            attemptID: UUID(), canonicalECID: "000000000000000B", portKey: "left2")
        XCTAssertThrowsError(try registry.reserve(
            attemptID: UUID(), canonicalECID: "000000000000000C", portKey: "right1")) {
            XCTAssertEqual($0 as? RestoreTaskAdmissionError, .capacityExceeded(limit: 2))
        }
        XCTAssertEqual(registry.activeCount, 2)
    }

    func testDuplicateAttemptAndUnreliableIdentityAreRefused() {
        let registry = RestoreTaskRegistry()
        let id = UUID()
        XCTAssertNoThrow(try registry.reserve(
            attemptID: id, canonicalECID: "000000000000000A", portKey: "left1"))
        XCTAssertThrowsError(try registry.reserve(
            attemptID: id, canonicalECID: "000000000000000B", portKey: "left2")) {
            XCTAssertEqual($0 as? RestoreTaskAdmissionError, .duplicateAttempt)
        }
        XCTAssertThrowsError(try registry.reserve(
            attemptID: UUID(), canonicalECID: nil, portKey: "left2")) {
            XCTAssertEqual($0 as? RestoreTaskAdmissionError, .unreliableIdentity)
        }
        XCTAssertThrowsError(try registry.reserve(
            attemptID: UUID(), canonicalECID: "000000000000000B", portKey: " ")) {
            XCTAssertEqual($0 as? RestoreTaskAdmissionError, .unreliableIdentity)
        }
    }

    // MARK: - 独立取消

    func testCancelingADoesNotSignalB() async throws {
        let core = makeCore()
        let a = try makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")
        let b = try makeExecution("000000000000000B", port: "left2", ipsw: "b.ipsw")
        try core.start(a)
        try core.start(b)
        await waitUntil { self.engines.count == 2 && self.engines.allSatisfy(\.started) }
        let aEngine = engines[0]
        let bEngine = engines[1]
        XCTAssertTrue((aEngine as AnyObject) !== (bEngine as AnyObject),
                      "每个 attempt 必须使用独立引擎实例")

        // 取消 A：B 的引擎不得收到任何信号。
        core.cancel(a.attemptID)
        XCTAssertEqual(aEngine.cancelCount, 1)
        XCTAssertEqual(bEngine.cancelCount, 0)
        XCTAssertTrue(bEngine.isRunning)
        core.forceKill(a.attemptID)
        XCTAssertEqual(aEngine.forceKillCount, 1)
        XCTAssertEqual(bEngine.forceKillCount, 0)

        aEngine.release(outcome: .canceled, exitCode: nil)
        await waitUntil { core.activeCount == 1 }
        XCTAssertTrue(bEngine.isRunning)
        bEngine.release(outcome: .success, exitCode: 0)
        await core.waitUntilIdle()
    }

    func testALateCallbackCannotMutateFinishedAttempt() async throws {
        let core = makeCore()
        let execution = try makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")
        try core.start(execution)
        await waitUntil { self.engines.count == 1 && self.engines[0].started }
        let engine = engines[0]
        let late = try XCTUnwrap(engine.lastOnUpdate)
        XCTAssertEqual(core.snapshots[execution.attemptID]?.stepText, "RestoreOS")
        engine.release(outcome: .success, exitCode: 0)
        await core.waitUntilIdle()
        let terminalBefore = core.terminalRecord(for: execution.attemptID)

        var lateSnapshot = RestoreOutputSnapshot()
        lateSnapshot.stepText = "LATE"
        lateSnapshot.stageFraction = 0.99
        late(lateSnapshot)

        XCTAssertEqual(core.terminalRecord(for: execution.attemptID), terminalBefore)
        XCTAssertEqual(core.terminal.count, 1)
        XCTAssertEqual(core.snapshots[execution.attemptID]?.stepText, "RestoreOS",
                       "迟到回调不得改写已收尾 attempt 的快照")
    }

    // MARK: - 结果与输出归属

    func testResultsAndStreamsStayPerAttempt() async throws {
        let core = makeCore()
        let a = try makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")
        let b = try makeExecution("000000000000000B", port: "left2", ipsw: "b.ipsw")
        try core.start(a)
        try core.start(b)
        await waitUntil { self.engines.count == 2 && self.engines.allSatisfy(\.started) }

        let outA = URL(fileURLWithPath: "/tmp/a.stdout")
        let errA = URL(fileURLWithPath: "/tmp/a.stderr")
        let outB = URL(fileURLWithPath: "/tmp/b.stdout")
        let errB = URL(fileURLWithPath: "/tmp/b.stderr")
        engines[0].release(outcome: .success, exitCode: 0, stdout: outA, stderr: errA)
        engines[1].release(outcome: .failure, exitCode: 1, stdout: outB, stderr: errB)
        await core.waitUntilIdle()

        XCTAssertEqual(core.terminalRecord(for: a.attemptID)?.status, .succeeded)
        XCTAssertEqual(core.terminalRecord(for: a.attemptID)?.stdoutURL, outA)
        XCTAssertEqual(core.terminalRecord(for: a.attemptID)?.exitCode, 0)
        XCTAssertEqual(core.terminalRecord(for: b.attemptID)?.status, .failed)
        XCTAssertEqual(core.terminalRecord(for: b.attemptID)?.stderrURL, errB)
        XCTAssertEqual(core.terminalRecord(for: b.attemptID)?.exitCode, 1)
    }

    // MARK: - P1 机器所有权

    func testMachineLeaseHeldUntilLastAttemptEnds() async throws {
        let core = makeCore()
        try core.start(makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw"))
        try core.start(makeExecution("000000000000000B", port: "left2", ipsw: "b.ipsw"))
        await waitUntil { self.engines.count == 2 && self.engines.allSatisfy(\.started) }
        XCTAssertEqual(core.leaseAcquireCount, 1)
        XCTAssertTrue(core.isLeaseHeld)

        engines[0].release(outcome: .success, exitCode: 0)
        await waitUntil { core.activeCount == 1 }
        XCTAssertTrue(core.isLeaseHeld)
        XCTAssertEqual(core.leaseReleaseCount, 0)

        engines[1].release(outcome: .success, exitCode: 0)
        await core.waitUntilIdle()
        XCTAssertFalse(core.isLeaseHeld)
        XCTAssertEqual(core.leaseReleaseCount, 1)
    }

    func testSecondAppInstanceIsRefusedWhileLeaseIsHeld() throws {
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("P3A-\(UUID().uuidString).lease")
        let other = RestoreProcessLease(lockURL: lockURL)
        XCTAssertEqual(other.acquire(), .acquired)
        defer { other.release() }

        let core = RestoreDualRestoreCore(
            lease: RestoreProcessLease(lockURL: lockURL),
            engineFactory: { [weak self] in self?.makeEngine() ?? P3AFakeEngine() })
        let taskID = UUID()
        XCTAssertThrowsError(try core.start(
            RestoreTaskExecutionRequest(
                attemptID: UUID(), taskID: taskID,
                canonicalECID: "000000000000000A", portKey: "left1",
                ipswURL: URL(fileURLWithPath: "/tmp/a.ipsw"),
                request: P3AFakeEngine.request(
                    ecid: 0xA, ipsw: "/tmp/a.ipsw", taskID: taskID)))) {
            XCTAssertEqual($0 as? RestoreTaskAdmissionError, .machineLeaseBusy)
        }
        XCTAssertTrue(core.registry.isEmpty)
        XCTAssertEqual(core.leaseAcquireCount, 0)
    }

    func testLaunchFailureRollsBackAdmissionAndLease() async throws {
        let core = makeCore()
        core.launchGuard = { _ in false }
        let execution = try makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")
        try core.start(execution)
        await waitUntil { self.engines.count == 1 && self.engines[0].started }
        await core.waitUntilIdle()

        XCTAssertTrue(core.registry.isEmpty)
        XCTAssertFalse(core.isLeaseHeld)
        XCTAssertEqual(core.leaseReleaseCount, 1)
        XCTAssertEqual(core.terminalRecord(for: execution.attemptID)?.status, .canceled)

        // 回滚后同一 ECID / 端口可以重新准入（新 attempt UUID）。
        core.launchGuard = { _ in true }
        XCTAssertNoThrow(try core.start(
            makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")))
        await waitUntil { self.engines.count == 2 && self.engines[1].started }
        engines[1].release(outcome: .success, exitCode: 0)
        await core.waitUntilIdle()
    }

    func testStartEnforcesOccupancyAndUnknownIsPreserved() async throws {
        let core = makeCore()
        let a = try makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")
        try core.start(a)
        XCTAssertThrowsError(try core.start(
            makeExecution("000000000000000A", port: "left2", ipsw: "b.ipsw"))) {
            XCTAssertEqual($0 as? RestoreTaskAdmissionError, .duplicateECID)
        }
        XCTAssertThrowsError(try core.start(
            makeExecution("000000000000000C", port: "left1", ipsw: "c.ipsw"))) {
            XCTAssertEqual($0 as? RestoreTaskAdmissionError, .duplicatePort)
        }
        await waitUntil { self.engines.count == 1 && self.engines[0].started }
        engines[0].release(outcome: .unknown, exitCode: nil)
        await core.waitUntilIdle()
        XCTAssertEqual(core.terminalRecord(for: a.attemptID)?.status, .unknown)
    }

    func testIdentityMismatchIsRefused() throws {
        let core = makeCore()
        let request = CfgutilRestoreRequest(
            taskID: UUID(),
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            ipswURL: URL(fileURLWithPath: "/tmp/a.ipsw"),
            targetECID: 0xB,
            outputDirectory: nil)
        let execution = RestoreTaskExecutionRequest(
            attemptID: UUID(), taskID: UUID(),
            canonicalECID: "000000000000000A", portKey: "left1",
            ipswURL: URL(fileURLWithPath: "/tmp/a.ipsw"),
            request: request)
        XCTAssertThrowsError(try core.start(execution)) {
            XCTAssertEqual($0 as? RestoreTaskAdmissionError, .identityMismatch)
        }
        XCTAssertTrue(core.registry.isEmpty)
        XCTAssertFalse(core.isLeaseHeld)
    }

    func testDuplicateOutputDirectoryIsRefused() async throws {
        let core = makeCore()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("P3A-out-\(UUID().uuidString)", isDirectory: true)
        let a = try makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")
        let b = try makeExecution("000000000000000B", port: "left2", ipsw: "b.ipsw")
        try core.start(RestoreTaskExecutionRequest(
            attemptID: a.attemptID, taskID: a.taskID,
            canonicalECID: a.canonicalECID, portKey: a.portKey,
            ipswURL: a.ipswURL,
            request: CfgutilRestoreRequest(
                taskID: a.taskID,
                executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                ipswURL: a.ipswURL,
                targetECID: 0xA,
                outputDirectory: directory)))
        XCTAssertThrowsError(try core.start(RestoreTaskExecutionRequest(
            attemptID: b.attemptID, taskID: b.taskID,
            canonicalECID: b.canonicalECID, portKey: b.portKey,
            ipswURL: b.ipswURL,
            request: CfgutilRestoreRequest(
                taskID: b.taskID,
                executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                ipswURL: b.ipswURL,
                targetECID: 0xB,
                outputDirectory: directory)))) {
            XCTAssertEqual($0 as? RestoreTaskAdmissionError, .duplicateOutputDirectory)
        }
        await waitUntil { self.engines.count == 1 && self.engines[0].started }
        engines[0].release(outcome: .success, exitCode: 0)
        await core.waitUntilIdle()
    }

    func testFinishedAttemptUUIDCannotBeReused() async throws {
        let core = makeCore()
        let execution = try makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")
        try core.start(execution)
        await waitUntil { self.engines.count == 1 && self.engines[0].started }
        engines[0].release(outcome: .success, exitCode: 0)
        await core.waitUntilIdle()
        XCTAssertThrowsError(try core.start(execution)) {
            XCTAssertEqual($0 as? RestoreTaskAdmissionError, .duplicateAttempt)
        }
    }

    func testLeaseIsReacquiredForNextRound() async throws {
        let core = makeCore()
        try core.start(makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw"))
        await waitUntil { self.engines.count == 1 && self.engines[0].started }
        engines[0].release(outcome: .success, exitCode: 0)
        await core.waitUntilIdle()
        XCTAssertEqual(core.leaseAcquireCount, 1)
        XCTAssertEqual(core.leaseReleaseCount, 1)

        try core.start(makeExecution("000000000000000B", port: "left2", ipsw: "b.ipsw"))
        await waitUntil { self.engines.count == 2 && self.engines[1].started }
        XCTAssertEqual(core.leaseAcquireCount, 2)
        engines[1].release(outcome: .success, exitCode: 0)
        await core.waitUntilIdle()
    }

    // MARK: - 准备期取消（审计 P1）

    func testCancelInSameTurnPreventsLauncherCall() async throws {
        let core = makeCore()
        let execution = try makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")
        try core.start(execution)
        // 同一 MainActor 回合内立即取消：此时执行 Task 尚未获得运行机会。
        core.cancel(execution.attemptID)

        for _ in 0..<20 { await Task.yield() }
        let launched = engines.first?.runCount ?? 0
        if launched > 0 { engines[0].release(outcome: .success, exitCode: 0) }
        await core.waitUntilIdle()

        XCTAssertEqual(launched, 0, "准备期取消后不得调用 launcher")
        XCTAssertEqual(engines.first?.spawnCount ?? 0, 0)
        XCTAssertEqual(core.terminalRecord(for: execution.attemptID)?.status, .canceled)
        XCTAssertEqual(core.leaseReleaseCount, 1)
        XCTAssertFalse(core.isLeaseHeld)
    }

    func testCancelWhileWaitingForPermissionBlocksSpawn() async throws {
        let engine = P3AFakeEngine()
        var gate: CheckedContinuation<Void, Never>?
        engine.permissionGate = {
            await withCheckedContinuation { gate = $0 }
        }
        let core = makeCore(engine: engine)
        let execution = try makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")
        try core.start(execution)
        await waitUntil { engine.runCount == 1 && gate != nil }
        XCTAssertEqual(engine.runCount, 1, "必须先进入引擎，才能验证许可闭包")
        XCTAssertNotNil(gate, "许可门未建立，测试窗口不成立")

        core.cancel(execution.attemptID)
        gate?.resume()
        await core.waitUntilIdle()

        XCTAssertEqual(engine.spawnCount, 0, "许可等待期间取消后不得 spawn")
        XCTAssertEqual(engine.cancelCount, 1)
        XCTAssertEqual(core.terminalRecord(for: execution.attemptID)?.status, .canceled)
        XCTAssertFalse(core.isLeaseHeld)
    }

    func testPrelaunchCancelOfADoesNotAffectB() async throws {
        let core = makeCore()
        let a = try makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")
        let b = try makeExecution("000000000000000B", port: "left2", ipsw: "b.ipsw")
        try core.start(a)
        core.cancel(a.attemptID)
        try core.start(b)
        await waitUntil { self.engines.count == 2 && self.engines.contains(where: { $0.spawnCount == 1 }) }

        XCTAssertNil(core.engines[a.attemptID], "取消后不得保留活动引擎引用")
        let aEngine = try XCTUnwrap(engines.first)
        let bEngine = try XCTUnwrap(engines.last)
        XCTAssertEqual(aEngine.runCount, 0)
        XCTAssertEqual(aEngine.spawnCount, 0)
        XCTAssertEqual(bEngine.runCount, 1)
        XCTAssertEqual(bEngine.spawnCount, 1)
        XCTAssertEqual(bEngine.cancelCount, 0)
        XCTAssertTrue(core.isLeaseHeld, "A 取消后 B 仍在运行，机器租约必须保持")
        XCTAssertEqual(core.leaseReleaseCount, 0)
        bEngine.release(outcome: .success, exitCode: 0)
        await core.waitUntilIdle()
        XCTAssertEqual(core.terminalRecord(for: a.attemptID)?.status, .canceled)
        XCTAssertEqual(core.terminalRecord(for: b.attemptID)?.status, .succeeded)
        XCTAssertEqual(core.leaseReleaseCount, 1)
        XCTAssertFalse(core.isLeaseHeld)
    }

    func testPrelaunchCancelReleasesOutputDirectory() async throws {
        let core = makeCore()
        let execution = try makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("P3A-cancel-out-\(UUID().uuidString)", isDirectory: true)
        let withDirectory = RestoreTaskExecutionRequest(
            attemptID: execution.attemptID, taskID: execution.taskID,
            canonicalECID: execution.canonicalECID, portKey: execution.portKey,
            ipswURL: execution.ipswURL,
            request: CfgutilRestoreRequest(
                taskID: execution.taskID,
                executableURL: execution.request.executableURL,
                ipswURL: execution.ipswURL,
                targetECID: execution.request.targetECID,
                outputDirectory: directory))
        try core.start(withDirectory)
        core.cancel(execution.attemptID)
        for _ in 0..<20 { await Task.yield() }
        await core.waitUntilIdle()

        // 目录占用必须已释放：同一目录可被下一任务重新准入。
        let next = try makeExecution("000000000000000B", port: "left2", ipsw: "b.ipsw")
        XCTAssertNoThrow(try core.start(RestoreTaskExecutionRequest(
            attemptID: next.attemptID, taskID: next.taskID,
            canonicalECID: next.canonicalECID, portKey: next.portKey,
            ipswURL: next.ipswURL,
            request: CfgutilRestoreRequest(
                taskID: next.taskID,
                executableURL: next.request.executableURL,
                ipswURL: next.ipswURL,
                targetECID: next.request.targetECID,
                outputDirectory: directory))))
        await waitUntil { !self.engines.isEmpty && self.engines.last?.started == true }
        engines.last?.release(outcome: .success, exitCode: 0)
        await core.waitUntilIdle()
    }

    func testDuplicateCancelProducesSingleTerminalAndSingleRelease() async throws {
        let core = makeCore()
        let execution = try makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")
        try core.start(execution)
        core.cancel(execution.attemptID)
        core.cancel(execution.attemptID)
        for _ in 0..<20 { await Task.yield() }
        await core.waitUntilIdle()

        XCTAssertEqual(core.terminal.count, 1)
        XCTAssertEqual(core.leaseReleaseCount, 1)
        XCTAssertFalse(core.isLeaseHeld)
        let engine = try XCTUnwrap(engines.first)
        XCTAssertEqual(engine.cancelCount, 1)
        XCTAssertEqual(core.terminalRecord(for: execution.attemptID)?.status, .canceled)
    }

    func testCancelRacingLaunchFailureKeepsSingleCanceledTerminal() async throws {
        let core = makeCore()
        core.launchGuard = { _ in false }
        let execution = try makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")
        try core.start(execution)
        core.cancel(execution.attemptID)
        for _ in 0..<20 { await Task.yield() }
        await core.waitUntilIdle()

        XCTAssertEqual(core.terminal.count, 1)
        XCTAssertEqual(core.terminalRecord(for: execution.attemptID)?.status, .canceled)
        XCTAssertEqual(core.leaseReleaseCount, 1)
        XCTAssertFalse(core.isLeaseHeld)
        XCTAssertTrue(core.registry.isEmpty)
    }

    // MARK: - 最终许可回调重入（复审 P1）

    private func makeRealEngineCore(launcher: P3ASpyLauncher) -> RestoreDualRestoreCore {
        let lease = RestoreProcessLease(
            lockURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("P3A-re-\(UUID().uuidString).lease"))
        return RestoreDualRestoreCore(
            lease: lease,
            engineFactory: { CfgutilRestoreEngine(launcher: launcher) })
    }

    func testCancelInsideFinalLaunchGuardPreventsRealEngineLaunch() async throws {
        let launcher = P3ASpyLauncher()
        let core = makeRealEngineCore(launcher: launcher)
        let execution = try makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")
        var hookCalls = 0
        core.launchGuard = { attemptID in
            hookCalls += 1
            if hookCalls == 2 {
                core.cancel(attemptID)
            }
            return true
        }
        try core.start(execution)
        await core.waitUntilIdle(timeout: 5)

        XCTAssertEqual(launcher.launchCount, 0,
                       "最终许可回调内取消后不得调用真实启动器")
        XCTAssertEqual(core.terminalRecord(for: execution.attemptID)?.status, .canceled)
        XCTAssertEqual(core.leaseReleaseCount, 1)
        XCTAssertFalse(core.isLeaseHeld)
    }

    func testCancelInsideFinalLaunchGuardWithThrowingLauncherStillNoLaunch() async throws {
        let launcher = P3ASpyLauncher()
        launcher.shouldThrow = true
        let core = makeRealEngineCore(launcher: launcher)
        let execution = try makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")
        var hookCalls = 0
        core.launchGuard = { attemptID in
            hookCalls += 1
            if hookCalls == 2 { core.cancel(attemptID) }
            return true
        }
        try core.start(execution)
        await core.waitUntilIdle(timeout: 5)

        XCTAssertEqual(launcher.launchCount, 0)
        XCTAssertEqual(core.terminalRecord(for: execution.attemptID)?.status, .canceled)
    }

    func testAlreadyCanceledAttemptDoesNotInvokeExternalHook() async throws {
        let launcher = P3ASpyLauncher()
        let core = makeRealEngineCore(launcher: launcher)
        let execution = try makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")
        var hookCalls = 0
        core.launchGuard = { _ in
            hookCalls += 1
            return true
        }
        try core.start(execution)
        core.cancel(execution.attemptID)
        for _ in 0..<20 { await Task.yield() }
        await core.waitUntilIdle()

        XCTAssertEqual(hookCalls, 0, "已取消的 UUID 不应再调用外部许可钩子")
        XCTAssertEqual(launcher.launchCount, 0)
        XCTAssertEqual(core.terminalRecord(for: execution.attemptID)?.status, .canceled)
    }

    func testHookReturningFalsePreventsLaunch() async throws {
        let launcher = P3ASpyLauncher()
        let core = makeRealEngineCore(launcher: launcher)
        let execution = try makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")
        core.launchGuard = { _ in false }
        try core.start(execution)
        await core.waitUntilIdle(timeout: 5)

        XCTAssertEqual(launcher.launchCount, 0)
        XCTAssertEqual(core.terminalRecord(for: execution.attemptID)?.status, .canceled)
    }

    func testFinalHookCancelOfADoesNotAffectBRealEngine() async throws {
        let launcher = P3ASpyLauncher()
        let core = makeRealEngineCore(launcher: launcher)
        let a = try makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")
        let b = try makeExecution("000000000000000B", port: "left2", ipsw: "b.ipsw")
        var canceledA = false
        core.launchGuard = { attemptID in
            if attemptID == a.attemptID, !canceledA {
                canceledA = true
                core.cancel(attemptID)
            }
            return true
        }
        try core.start(a)
        try core.start(b)
        await core.waitUntilIdle(timeout: 5)

        // 取消发生在 A 的第一次许可询问；A 不启动，B 仍正常启动一次。
        XCTAssertEqual(launcher.launchCount, 1)
        XCTAssertEqual(core.terminalRecord(for: a.attemptID)?.status, .canceled)
        XCTAssertNotNil(core.terminalRecord(for: b.attemptID))
        XCTAssertEqual(core.leaseReleaseCount, 1)
    }

    func testRealEngineRunningCancelKeepsNormalPath() async throws {
        let launcher = P3ASpyLauncher()
        launcher.processBlocksUntilInterrupted = true
        let core = makeRealEngineCore(launcher: launcher)
        let execution = try makeExecution("000000000000000A", port: "left1", ipsw: "a.ipsw")
        try core.start(execution)
        await waitUntil {
            launcher.launchCount == 1
                && core.engines[execution.attemptID]?.isRunning == true
        }
        XCTAssertEqual(launcher.launchCount, 1)

        core.cancel(execution.attemptID)
        await core.waitUntilIdle(timeout: 5)

        XCTAssertEqual(launcher.lastProcess?.interruptCount, 1)
        XCTAssertEqual(core.terminalRecord(for: execution.attemptID)?.status, .canceled)
        XCTAssertEqual(core.leaseReleaseCount, 1)
    }

    // MARK: - 生产仍为串行

    func testProductionModelRemainsSerialAndDoesNotUseDualCore() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let model = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/DeviceCapturePrototype/RestoreWorkspaceModel.swift"),
            encoding: .utf8)
        let regionStart = try XCTUnwrap(
            model.range(of: "func beginRestoreAfterConfirmation() async"))
        let region = model[regionStart.lowerBound...].prefix(1200)
        XCTAssertTrue(region.contains("guard activeAttempt == nil,"))
        XCTAssertTrue(region.contains("runTask == nil,"))
        XCTAssertTrue(region.contains("!engine.isRunning"))
        for file in ["MinimalWorkbenchView.swift", "FirmwareRestoreWorkspaceView.swift", "App.swift"] {
            let text = try String(
                contentsOf: root.appendingPathComponent(
                    "Sources/DeviceCapturePrototype/\(file)"),
                encoding: .utf8)
            XCTAssertFalse(text.contains("RestoreDualRestoreCore"))
        }
    }

    // MARK: - 工具

    private func makeCore(engine: P3AFakeEngine? = nil) -> RestoreDualRestoreCore {
        engines = engine.map { [$0] } ?? []
        let lease = RestoreProcessLease(
            lockURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("P3A-\(UUID().uuidString).lease"))
        return RestoreDualRestoreCore(
            lease: lease,
            engineFactory: { [weak self] in
                if let engine { return engine }
                return self?.makeEngine() ?? P3AFakeEngine()
            })
    }

    private func makeEngine() -> P3AFakeEngine {
        let engine = P3AFakeEngine()
        engines.append(engine)
        return engine
    }

    private func makeExecution(
        _ ecid: String,
        port: String,
        ipsw: String
    ) throws -> RestoreTaskExecutionRequest {
        let url = URL(fileURLWithPath: "/tmp/\(ipsw)")
        let value = UInt64(ecid, radix: 16) ?? 0
        let taskID = UUID()
        return RestoreTaskExecutionRequest(
            attemptID: UUID(),
            taskID: taskID,
            canonicalECID: ecid,
            portKey: port,
            ipswURL: url,
            request: P3AFakeEngine.request(ecid: value, ipsw: url.path, taskID: taskID))
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            await Task.yield()
        }
    }
}

@MainActor
final class P3ASpyLauncher: CfgutilProcessLaunching {
    private(set) var launchCount = 0
    private(set) var lastProcess: P3ASpyProcess?
    var shouldThrow = false
    var processBlocksUntilInterrupted = false

    func launch(
        request: CfgutilRestoreRequest,
        onChunk: @escaping @Sendable (RestoreOutputChannel, Data) -> Void
    ) throws -> any CfgutilProcessRunning {
        launchCount += 1
        if shouldThrow {
            throw CfgutilRestoreEngineError.launchFailed("spy launcher failure")
        }
        let process = P3ASpyProcess()
        process.blocksUntilInterrupted = processBlocksUntilInterrupted
        lastProcess = process
        return process
    }
}

@MainActor
final class P3ASpyProcess: CfgutilProcessRunning {
    var processLaunched: RestoreLifecycleTimePoint? = RestoreLifecycleClock.now()
    var blocksUntilInterrupted = false
    private(set) var interruptCount = 0
    private var continuation: CheckedContinuation<CfgutilProcessCompletion, Never>?

    func waitForCompletion(tailTimeout: TimeInterval) async -> CfgutilProcessCompletion {
        guard blocksUntilInterrupted else { return Self.completed(exitCode: 0) }
        return await withCheckedContinuation { continuation = $0 }
    }

    func interrupt() {
        interruptCount += 1
        continuation?.resume(returning: Self.completed(exitCode: 130))
        continuation = nil
    }

    func terminate() {
        continuation?.resume(returning: Self.completed(exitCode: 143))
        continuation = nil
    }

    func forceKill() {
        continuation?.resume(returning: Self.completed(exitCode: 137))
        continuation = nil
    }

    static func completed(exitCode: Int32) -> CfgutilProcessCompletion {
        CfgutilProcessCompletion(
            exitCode: exitCode,
            stdoutEOF: true,
            stderrEOF: true,
            forcedKill: false,
            processExited: nil,
            bothStreamsEOF: nil,
            terminationReason: .exit)
    }
}

@MainActor
final class P3AFakeEngine: RestoreEngineRunning {
    var isRunning = false
    var cancellationGraceExpired = false
    private(set) var started = false
    private(set) var runCount = 0
    private(set) var spawnCount = 0
    var permissionGate: (@MainActor () async -> Void)?
    private(set) var request: CfgutilRestoreRequest?
    private(set) var cancelCount = 0
    private(set) var forceKillCount = 0
    private(set) var lastOnUpdate: (@MainActor (RestoreOutputSnapshot) -> Void)?
    private var continuation: CheckedContinuation<Void, Never>?
    private var pending: (RestoreOutcome, Int32?, URL?, URL?) = (.canceled, nil, nil, nil)

    static func request(ecid: UInt64, ipsw: String, taskID: UUID = UUID()) -> CfgutilRestoreRequest {
        CfgutilRestoreRequest(
            taskID: taskID,
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            ipswURL: URL(fileURLWithPath: ipsw),
            targetECID: ecid,
            outputDirectory: nil)
    }

    func run(
        request: CfgutilRestoreRequest,
        launchPermitted: @escaping @MainActor () -> Bool,
        onUpdate: (@MainActor (RestoreOutputSnapshot) -> Void)?
    ) async -> CfgutilRestoreRunResult {
        started = true
        runCount += 1
        self.request = request
        lastOnUpdate = onUpdate
        if let permissionGate {
            await permissionGate()
        }
        guard launchPermitted() else {
            return result(outcome: .canceled)
        }
        spawnCount += 1
        isRunning = true
        var snapshot = RestoreOutputSnapshot()
        snapshot.processLaunched = RestoreLifecycleClock.now()
        snapshot.restoreActivityObserved = true
        snapshot.stepText = "RestoreOS"
        onUpdate?(snapshot)
        await withCheckedContinuation { continuation = $0 }
        isRunning = false
        return result(
            outcome: pending.0,
            exitCode: pending.1,
            stdout: pending.2,
            stderr: pending.3)
    }

    func cancel() { cancelCount += 1 }
    func forceKill() { forceKillCount += 1 }

    func release(
        outcome: RestoreOutcome,
        exitCode: Int32?,
        stdout: URL? = nil,
        stderr: URL? = nil
    ) {
        pending = (outcome, exitCode, stdout, stderr)
        continuation?.resume()
        continuation = nil
    }

    private func result(
        outcome: RestoreOutcome,
        exitCode: Int32? = nil,
        stdout: URL? = nil,
        stderr: URL? = nil
    ) -> CfgutilRestoreRunResult {
        var snapshot = RestoreOutputSnapshot()
        snapshot.stepText = "RestoreOS"
        return CfgutilRestoreRunResult(
            outcome: outcome,
            exitCode: exitCode,
            stdoutURL: stdout,
            stderrURL: stderr,
            stdoutSHA256: "",
            stderrSHA256: "",
            tailComplete: outcome != .unknown,
            cancellationRequested: outcome == .canceled,
            forcedKill: false,
            snapshot: snapshot)
    }
}

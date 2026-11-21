import Combine
import Foundation
import XCTest
@testable import DeviceCapturePrototype
import RestoreLogEngine

/// P1 跨进程保护的离线专项夹具（独立开发工作区，不进入产品工作树）。
///
/// 环境变量：
/// - `P1_LEASE_HOLDER`：跨进程夹具二进制路径（`mra-lease-holder`）。
///   未设置时，依赖真实第二进程的用例会 SKIP，其余用例照常运行。
@MainActor
final class AuditP1RestoreGuardTests: XCTestCase {
    private let ecidA: UInt64 = 0x12345670

    // MARK: - 单任务与反馈

    // G01：运行中第二次请求 → 明确提示 + 不产生第二任务。
    func testG01SecondRequestShowsExplicitMessage() async throws {
        let context = try makeContext()
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        context.publish([device(ecid: ecidA, location: "01100000")])

        let run = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        try await waitUntil { context.engine.isRunning }
        context.workspace.message = ""

        await context.workspace.testStartPrimaryThroughConfirmation()

        XCTAssertEqual(context.engine.runCount, 1)
        XCTAssertEqual(
            context.workspace.errorMessage,
            "第二台与第一台是同一设备，已拒绝。")
        XCTAssertTrue(context.workspace.message.isEmpty)
        XCTAssertFalse(context.workspace.canStartRestore)

        context.engine.complete(outcome: .success)
        await run.value
    }

    // MARK: - 锁语义（同进程）

    // G02：取得 → 重复取得 busy → 释放后可再取得。
    func testG02LeaseAcquireBusyReleaseRoundTrip() throws {
        let url = temporaryLockURL()
        let first = RestoreProcessLease(lockURL: url)
        XCTAssertEqual(first.acquire(), .acquired)
        XCTAssertTrue(first.isHeld)

        // 同进程内第二个实例：另一个描述符，flock 仍然互斥。
        let second = RestoreProcessLease(lockURL: url)
        XCTAssertEqual(second.acquire(), .busy)

        first.release()
        XCTAssertFalse(first.isHeld)
        XCTAssertEqual(second.acquire(), .acquired)
        second.release()
    }

    // G03：模型在"准备→运行→收尾"全程持有租约，结束后才释放。
    func testG03ModelHoldsLeaseAcrossRun() async throws {
        let url = temporaryLockURL()
        let context = try makeContext(lease: RestoreProcessLease(lockURL: url))
        let probe = RestoreProcessLease(lockURL: url)

        try await startAndReachRunning(context)

        XCTAssertEqual(probe.acquire(), .busy)

        context.engine.complete(outcome: .success)
        await context.run.value

        XCTAssertEqual(probe.acquire(), .acquired)
        probe.release()
    }

    // G08：FINALIZING 与日志归档窗口内租约仍然有效。
    func testG08LeaseHeldThroughFinalizingAndArchive() async throws {
        let url = temporaryLockURL()
        let gate = HookGate()
        let context = try makeContext(
            lease: RestoreProcessLease(lockURL: url),
            rawArchiveObservationHook: { await gate.wait() })
        let probe = RestoreProcessLease(lockURL: url)

        try await startAndReachRunning(context)

        context.engine.complete(outcome: .success)
        try await waitUntil { context.workspace.currentTask?.outcome != nil }

        XCTAssertTrue(context.workspace.isFinalizingRestoreEvidence)
        XCTAssertEqual(probe.acquire(), .busy)

        gate.release()
        await context.run.value

        XCTAssertEqual(probe.acquire(), .acquired)
        probe.release()
    }

    // G04：权限失败（文件 0000）必须 fail-closed，且不得回退到其它锁域。
    func testG04PermissionFailureIsFailClosed() throws {
        let url = temporaryLockURL()
        FileManager.default.createFile(atPath: url.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: url.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: url)
        }

        let lease = RestoreProcessLease(lockURL: url)
        switch lease.acquire() {
        case .unavailable:
            break
        case .acquired, .busy:
            XCTFail("permission failure must be unavailable, not acquired/busy")
            lease.release()
        }
    }

    // G09：父目录不存在时必须 unavailable（不存在任何回退锁域）。
    func testG09MissingParentIsUnavailable() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("P1Missing-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("lease.lock")
        let lease = RestoreProcessLease(lockURL: url)
        if case .unavailable = lease.acquire() {
            // expected
        } else {
            XCTFail("missing parent must be unavailable")
            lease.release()
        }
    }

    // G10：模型遇到不可用锁时 fail-closed（无 attempt、无引擎启动）。
    func testG10ModelFailsClosedWhenLeaseUnavailable() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("P1NoDir-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("lease.lock")
        let context = try makeContext(lease: RestoreProcessLease(lockURL: url))
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        context.publish([device(ecid: ecidA, location: "01100000")])

        await context.workspace.testStartPrimaryThroughConfirmation()

        XCTAssertNil(context.workspace.activeAttempt)
        XCTAssertEqual(context.engine.runCount, 0)
        XCTAssertFalse(context.workspace.errorMessage.isEmpty)
    }

    // G11a：崩溃后仍有 cfgutil 存活 → fail-closed。
    func testG11aOrphanMarkerWithLiveCfgutilIsUnavailable() throws {
        let url = temporaryLockURL()
        let cfgutil = try spawnFakeCfgutil()
        defer { stopFakeCfgutil(cfgutil) }
        try writeMarker(
            at: url,
            appPID: try deadPID(),
            ageSeconds: 60)

        let lease = RestoreProcessLease(lockURL: url)
        if case .unavailable = lease.acquire() {
            // expected: 上一次 Restore 可能仍在运行
        } else {
            XCTFail("orphan cfgutil must block acquisition")
            lease.release()
        }
    }

    // G11b：标记存在但 App 与 cfgutil 都不在 → 视为陈旧，清除后继续。
    func testG11bStaleMarkerIsCleared() throws {
        let url = temporaryLockURL()
        try writeMarker(
            at: url,
            appPID: try deadPID(),
            ageSeconds: 60)

        let lease = RestoreProcessLease(lockURL: url)
        XCTAssertEqual(lease.acquire(), .acquired)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path + ".inprogress"))
        lease.release()
    }

    // G11c：陈旧标记（无 cfgutil）→ 清除后取得。
    // 不再按 appPid 存活判定（PID 复用会造成永久误锁）；
    // 孤儿判定只依赖 cfgutil 进程与标记年龄。
    func testG11cStaleMarkerIsClearedEvenIfPidIsAlive() throws {
        let url = temporaryLockURL()
        try writeMarker(
            at: url,
            appPID: getpid(),
            ageSeconds: 60)

        let lease = RestoreProcessLease(lockURL: url)
        XCTAssertEqual(lease.acquire(), .acquired)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path + ".inprogress"))
        lease.release()
    }

    // G14：无在制标记，但存在孤儿 cfgutil（例如从无标记的旧版本升级）→ 拒绝。
    func testG14OrphanCfgutilWithoutMarkerIsRejected() throws {
        let cfgutil = try spawnFakeCfgutil()
        defer { stopFakeCfgutil(cfgutil) }
        let url = temporaryLockURL()

        let lease = RestoreProcessLease(lockURL: url)
        if case .unavailable = lease.acquire() {
            // expected
        } else {
            XCTFail("orphan cfgutil without marker must block acquisition")
            lease.release()
        }
    }

    // G11f：0 字节标记且 mtime 陈旧 → 清除后取得（避免永久锁死）。
    func testG11fZeroByteStaleMarkerIsRecovered() throws {
        let url = temporaryLockURL()
        let marker = URL(fileURLWithPath: url.path + ".inprogress")
        FileManager.default.createFile(atPath: marker.path, contents: Data())
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-60)],
            ofItemAtPath: marker.path)

        let lease = RestoreProcessLease(lockURL: url, launchGrace: 10)
        XCTAssertEqual(lease.acquire(), .acquired)
        lease.release()
    }

    // G11g：0 字节标记但 mtime 很新（可能正在写入）→ 拒绝。
    func testG11gZeroByteFreshMarkerIsRejected() throws {
        let url = temporaryLockURL()
        let marker = URL(fileURLWithPath: url.path + ".inprogress")
        FileManager.default.createFile(atPath: marker.path, contents: Data())

        let lease = RestoreProcessLease(lockURL: url, launchGrace: 30)
        if case .unavailable = lease.acquire() {
            // expected
        } else {
            XCTFail("fresh unreadable marker must block acquisition")
            lease.release()
        }
    }

    // G11d：新鲜标记（App 已死、尚无 cfgutil、仍在启动宽限期）→ 不得判为陈旧。
    func testG11dFreshMarkerIsNotStale() throws {
        let url = temporaryLockURL()
        try writeMarker(at: url, appPID: try deadPID(), ageSeconds: 0)

        let lease = RestoreProcessLease(lockURL: url, launchGrace: 30)
        if case .unavailable = lease.acquire() {
            // expected
        } else {
            XCTFail("fresh marker must be treated as still starting")
            lease.release()
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.path + ".inprogress"))
    }

    // G11e：在制标记是符号链接 → fail-closed。
    func testG11eSymlinkMarkerIsRejected() throws {
        let url = temporaryLockURL()
        let target = URL(fileURLWithPath: url.path + ".target")
        FileManager.default.createFile(atPath: target.path, contents: Data("{}".utf8))
        try FileManager.default.createSymbolicLink(
            at: URL(fileURLWithPath: url.path + ".inprogress"),
            withDestinationURL: target)

        let lease = RestoreProcessLease(lockURL: url)
        if case .unavailable = lease.acquire() {
            // expected
        } else {
            XCTFail("symlink marker must be rejected")
            lease.release()
        }
    }

    // G12：跨进程锁被占用时，模型给出可见错误且不启动引擎。
    func testG12ModelBusyBranchIsVisible() async throws {
        let url = temporaryLockURL()
        let holder = RestoreProcessLease(lockURL: url)
        XCTAssertEqual(holder.acquire(), .acquired)
        defer { holder.release() }

        let context = try makeContext(lease: RestoreProcessLease(lockURL: url))
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        context.publish([device(ecid: ecidA, location: "01100000")])

        await context.workspace.testStartPrimaryThroughConfirmation()

        XCTAssertNil(context.workspace.activeAttempt)
        XCTAssertEqual(context.engine.runCount, 0)
        XCTAssertEqual(
            context.workspace.errorMessage,
            "当前已有 Restore 任务正在运行，请先完成当前任务。")
    }

    // G13：锁路径是符号链接 → fail-closed。
    func testG13SymlinkLockPathIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("P1Symlink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("real.lease")
        FileManager.default.createFile(atPath: target.path, contents: Data())
        let link = directory.appendingPathComponent("lease.lock")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: target)

        let lease = RestoreProcessLease(lockURL: link)
        if case .unavailable = lease.acquire() {
            // expected: O_NOFOLLOW 拒绝符号链接
        } else {
            XCTFail("symlink lock path must be rejected")
            lease.release()
        }
    }

    // MARK: - 真实第二进程

    // G05：外部进程持锁时本进程得到 busy。
    func testG05ExternalHolderCausesBusy() throws {
        let holder = try holderBinary()
        let url = temporaryLockURL()
        let process = try spawnHolder(holder, lock: url, seconds: 30)
        defer { process.terminate() }

        let acquired = try waitForHolderLine(from: process)
        XCTAssertTrue(acquired, "holder should report ACQUIRED")

        let lease = RestoreProcessLease(lockURL: url)
        XCTAssertEqual(lease.acquire(), .busy)
    }

    // G06：外部进程被 SIGKILL 后内核释放锁，本进程可取得。
    func testG06AbnormalExitReleasesLock() throws {
        let holder = try holderBinary()
        let url = temporaryLockURL()
        let process = try spawnHolder(holder, lock: url, seconds: 60)
        XCTAssertTrue(try waitForHolderLine(from: process))

        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()

        let lease = RestoreProcessLease(lockURL: url)
        XCTAssertEqual(lease.acquire(), .acquired)
        lease.release()
    }

    // G07：外部进程正常释放后本进程可取得。
    func testG07NormalReleaseByOtherProcess() throws {
        let holder = try holderBinary()
        let url = temporaryLockURL()
        let process = try spawnHolder(holder, lock: url, seconds: 0.2)
        XCTAssertTrue(try waitForHolderLine(from: process))
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let lease = RestoreProcessLease(lockURL: url)
        XCTAssertEqual(lease.acquire(), .acquired)
        lease.release()
    }

    // MARK: - 夹具

    private func canonicalHex(_ value: UInt64) -> String {
        String(format: "%016llX", value)
    }

    private func device(ecid: UInt64, location: String) -> ObservedDevice {
        ObservedDevice(
            id: "ecid:\(canonicalHex(ecid))",
            ecid: canonicalHex(ecid),
            mode: .dfu,
            locationID: location,
            product: "Apple Mobile Device (DFU Mode)",
            serial: "ECID:\(canonicalHex(ecid))",
            modelIdentifier: "Mac14,2",
            chipID: 0x8132,
            boardID: 0x24,
            hardwareCode: "j413ap",
            productType: "Mac14,2")
    }

    private func firmwareURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("p1-\(UUID().uuidString).ipsw")
        XCTAssertTrue(FileManager.default.createFile(
            atPath: url.path,
            contents: Data("fixture".utf8)))
        return url
    }

    /// 一个必然不存在的 PID（macOS pid 上限远小于此值）。
    private func deadPID() throws -> Int32 { 999_999 }

    private func writeMarker(
        at lockURL: URL,
        appPID: Int32,
        ageSeconds: TimeInterval = 0
    ) throws {
        let payload: [String: Any] = [
            "v": 1,
            "appPid": Int(appPID),
            "createdAt": ISO8601DateFormatter().string(
                from: Date().addingTimeInterval(-ageSeconds))
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys])
        try data.write(to: URL(fileURLWithPath: lockURL.path + ".inprogress"))
    }

    /// 复制 /bin/sleep 为名为 cfgutil 的可执行文件并运行，供进程名探测使用。
    private func spawnFakeCfgutil() throws -> Process {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("P1FakeCfgutil-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        let binary = directory.appendingPathComponent("cfgutil")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: binary)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: binary.path)
        let process = Process()
        process.executableURL = binary
        process.arguments = ["10"]
        try process.run()
        // 等待进程真正出现在进程表中。
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if (RestoreProcessLease.runningCfgutilProcessCount() ?? 0) > 0 {
                return process
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return process
    }

    /// 终止假 cfgutil 并确认内核进程表中已无同名进程，
    /// 避免后续用例被"孤儿刷机"误判。
    private func stopFakeCfgutil(_ process: Process) {
        process.terminate()
        process.waitUntilExit()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if (RestoreProcessLease.runningCfgutilProcessCount() ?? 0) == 0 {
                return
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTFail("fake cfgutil did not exit")
    }

    private func temporaryLockURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("P1Lease-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        return directory.appendingPathComponent("lease.lock")
    }

    private func holderBinary() throws -> URL {
        guard let path = ProcessInfo.processInfo
            .environment["P1_LEASE_HOLDER"], !path.isEmpty else {
            throw XCTSkip("P1_LEASE_HOLDER not set")
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw XCTSkip("P1_LEASE_HOLDER is not executable")
        }
        return url
    }

    private func spawnHolder(
        _ binary: URL,
        lock: URL,
        seconds: Double
    ) throws -> Process {
        try FileManager.default.createDirectory(
            at: lock.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = binary
        process.arguments = ["hold", lock.path, String(seconds)]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        holderPipes[process] = pipe
        return process
    }

    private func waitForHolderLine(from process: Process) throws -> Bool {
        guard let pipe = holderPipes[process] else { return false }
        let handle = pipe.fileHandleForReading
        let deadline = Date().addingTimeInterval(10)
        var buffer = Data()
        while Date() < deadline {
            let chunk = handle.availableData
            if chunk.isEmpty {
                if !process.isRunning { break }
                Thread.sleep(forTimeInterval: 0.02)
                continue
            }
            buffer.append(chunk)
            if let text = String(data: buffer, encoding: .utf8),
               text.contains("ACQUIRED") {
                return true
            }
        }
        return false
    }

    private func makeContext(
        lease: RestoreProcessLease? = nil,
        rawArchiveObservationHook: (@MainActor () async -> Void)? = nil
    ) throws -> P1Context {
        let resolvedLease = lease ?? RestoreProcessLease(lockURL: temporaryLockURL())
        let store = CalibrationStore(
            testingDocument: CalibrationDocument(
                models: [],
                ports: [],
                selectedPort: ""),
            hostModel: "MacTest,1",
            builtInLayout: nil)
        let deviceControl = DeviceControlModel(
            calibration: store,
            livePorts: [],
            helperAvailable: false,
            persistPortSelection: false,
            startLiveWork: false)
        let coordinator = P1RLMCoordinator()
        let engine = P1FakeEngine()
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("P1RestoreGuard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: output,
            withIntermediateDirectories: true)
        let metadataReader: (URL) throws -> IPSWMetadataReadResult = { _ in
            IPSWMetadataReadResult(
                validity: .valid,
                metadata: IPSWMetadata(
                    productTypes: ["Mac14,2"],
                    identities: [
                        IPSWBuildIdentity(
                            deviceClass: "j413ap",
                            boardID: 0x24,
                            chipID: 0x8132)
                    ],
                    productVersion: "14.0",
                    productBuild: "23A344"),
                error: nil)
        }
        let firmwareLibrary = FirmwareLibraryStore(
            indexURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "P1FirmwareLibrary-\(UUID().uuidString).json"),
            metadataLoader: metadataReader)
        let workspace = RestoreWorkspaceModel(
            capture: P1FakeCapture(),
            engine: engine,
            outputRoot: output,
            maximumSnapshotAge: 1,
            heartbeatPollInterval: 0.005,
            cancellationGraceDelay: 0.01,
            observationHeartbeat: deviceControl.observationHeartbeat,
            portKeyResolver: { device in
                device.locationID == "01100000" ? "port-A" : nil
            },
            portDisplayNameResolver: { _ in "左侧上方" },
            metadataReader: metadataReader,
            cfgutilURL: URL(fileURLWithPath: "/usr/bin/true"),
            rlmCoordinator: coordinator,
            firmwareLibrary: firmwareLibrary,
            rawArchiveObservationHook: rawArchiveObservationHook,
            stablePortKeyProvider: { target in
                "synthetic-host|\(target.portKey ?? "unattributed")"
            },
            processLease: resolvedLease)
        return P1Context(
            deviceControl: deviceControl,
            workspace: workspace,
            engine: engine,
            coordinator: coordinator)
    }

    private func startAndReachRunning(_ context: P1Context) async throws {
        context.publish([device(ecid: ecidA, location: "01100000")])
        context.workspace.refreshTargets()
        context.workspace.selectTarget(id: canonicalHex(ecidA))
        await context.workspace.loadFirmware(url: try firmwareURL())
        context.publish([device(ecid: ecidA, location: "01100000")])

        let run = Task { @MainActor in
            await context.workspace.testStartPrimaryThroughConfirmation()
        }
        context.runTask = run
        try await waitUntil { context.engine.isRunning }
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<400 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for condition", file: file, line: line)
    }

    private var holderPipes: [Process: Pipe] {
        get { ProcessPipeRegistry.shared.pipes }
        set { ProcessPipeRegistry.shared.pipes = newValue }
    }
}

/// 进程→管道登记（仅测试用，避免把 Pipe 存在 Process 关联对象里）。
private final class ProcessPipeRegistry {
    static let shared = ProcessPipeRegistry()
    var pipes: [Process: Pipe] = [:]
}

@MainActor
private final class HookGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class P1Context {
    let deviceControl: DeviceControlModel
    let workspace: RestoreWorkspaceModel
    let engine: P1FakeEngine
    let coordinator: P1RLMCoordinator
    var runTask: Task<Void, Never>?

    init(
        deviceControl: DeviceControlModel,
        workspace: RestoreWorkspaceModel,
        engine: P1FakeEngine,
        coordinator: P1RLMCoordinator
    ) {
        self.deviceControl = deviceControl
        self.workspace = workspace
        self.engine = engine
        self.coordinator = coordinator
    }

    /// `startAndReachRunning` 创建的启动任务。
    var run: Task<Void, Never> {
        get { runTask ?? Task {} }
        set { runTask = newValue }
    }

    func publish(_ devices: [ObservedDevice]) {
        deviceControl.applyObservationResult(.success(devices), now: Date())
    }
}

@MainActor
private final class P1FakeEngine: RestoreEngineRunning {
    private(set) var runCount = 0
    private(set) var cancelCount = 0
    private(set) var forceKillCount = 0
    private(set) var request: CfgutilRestoreRequest?
    private var continuation: CheckedContinuation<Void, Never>?
    var cancellationGraceExpired = false
    var isRunning = false
    private var completionOutcome: RestoreOutcome = .success

    func run(
        request: CfgutilRestoreRequest,
        launchPermitted: @escaping @MainActor () -> Bool,
        onUpdate: (@MainActor (RestoreOutputSnapshot) -> Void)?
    ) async -> CfgutilRestoreRunResult {
        runCount += 1
        self.request = request
        guard launchPermitted() else {
            return result(request: request, outcome: .canceled)
        }
        isRunning = true
        var snapshot = RestoreOutputSnapshot()
        snapshot.restoreActivityObserved = true
        snapshot.stepText = "RestoreOS"
        onUpdate?(snapshot)
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        isRunning = false
        return result(request: request, outcome: completionOutcome)
    }

    func cancel() { cancelCount += 1 }
    func forceKill() { forceKillCount += 1 }

    func complete(outcome: RestoreOutcome) {
        guard let continuation else { return }
        completionOutcome = outcome
        self.continuation = nil
        continuation.resume()
        isRunning = false
    }

    private func result(
        request: CfgutilRestoreRequest,
        outcome: RestoreOutcome
    ) -> CfgutilRestoreRunResult {
        CfgutilRestoreRunResult(
            outcome: outcome,
            exitCode: outcome == .success ? 0 : nil,
            stdoutURL: request.outputDirectory?.appendingPathComponent("stdout.raw"),
            stderrURL: request.outputDirectory?.appendingPathComponent("stderr.raw"),
            stdoutSHA256: outcome == .success ? String(repeating: "a", count: 64) : "",
            stderrSHA256: outcome == .success ? String(repeating: "b", count: 64) : "",
            tailComplete: outcome == .success,
            cancellationRequested: outcome == .canceled,
            forcedKill: false,
            snapshot: RestoreOutputSnapshot())
    }
}

@MainActor
private final class P1RLMCoordinator: RestoreRLMPreparing {
    func prepare(
        taskID: UUID,
        canonicalECID: String
    ) async -> RestoreRLMBinding {
        RestoreRLMBinding(
            taskID: taskID,
            canonicalECID: canonicalECID,
            status: .unavailable,
            rawLogURL: nil,
            startAt: Date(),
            endAt: Date(),
            reason: "P1 fixture coordinator")
    }

    func finish(taskID: UUID, outcome: RestoreOutcome) async {}
}

@MainActor
private final class P1FakeCapture: RestoreCaptureLifecycle {
    var state: CaptureState = .idle
    var currentRawLogURL: URL?

    func start(preCaptureContext: String?, automatic: Bool) {
        state = .recording
    }

    func stop() {
        state = .finalizing
    }
}

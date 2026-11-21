import Foundation

/// P3-A：双任务 Restore 执行核心（离线）。
///
/// 设计约束：
/// - 单 App 所有者；最多两个活动 attempt；每个 attempt 独立引擎实例与 cfgutil 子进程。
/// - 注册表以 attempt UUID 为主键，并对规范化 ECID 与物理端口做占用校验。
/// - 检查与占用是 `@MainActor` 上的同步原子操作，中间没有 await。
/// - 机器级 P1 租约由本核心持有：第一个任务启动前获取，最后一个任务收尾后释放。
/// - 生产 App 未接入本核心；正常路径仍是 `SERIAL_RESTORE_ONLY`。

enum RestoreTaskAdmissionError: Error, Equatable, Sendable {
    case duplicateAttempt
    case duplicateECID
    case duplicatePort
    case capacityExceeded(limit: Int)
    case unreliableIdentity
    case machineLeaseBusy
    case machineLeaseUnavailable(String)
    case inProgressMarkerFailed
    case identityMismatch
    case duplicateOutputDirectory
}

struct RestoreTaskRegistration: Equatable, Sendable {
    let attemptID: UUID
    let canonicalECID: String
    let portKey: String
}

@MainActor
final class RestoreTaskRegistry {
    static let maximumCapacity = 2

    let capacity: Int
    private(set) var registrations: [UUID: RestoreTaskRegistration] = [:]

    init(capacity: Int = RestoreTaskRegistry.maximumCapacity) {
        self.capacity = max(1, min(capacity, RestoreTaskRegistry.maximumCapacity))
    }

    var activeCount: Int { registrations.count }
    var isEmpty: Bool { registrations.isEmpty }

    func registration(for attemptID: UUID) -> RestoreTaskRegistration? {
        registrations[attemptID]
    }

    /// 原子预留：校验 all-or-nothing，失败不留任何占用。
    @discardableResult
    func reserve(
        attemptID: UUID,
        canonicalECID: String?,
        portKey: String?
    ) throws -> RestoreTaskRegistration {
        guard registrations[attemptID] == nil else {
            throw RestoreTaskAdmissionError.duplicateAttempt
        }
        guard let ecid = ECIDIdentity(
                hex: canonicalECID?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "")?
                .canonicalHex,
            let port = portKey?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !port.isEmpty else {
            throw RestoreTaskAdmissionError.unreliableIdentity
        }
        guard !registrations.values.contains(where: { $0.canonicalECID == ecid }) else {
            throw RestoreTaskAdmissionError.duplicateECID
        }
        guard !registrations.values.contains(where: { $0.portKey == port }) else {
            throw RestoreTaskAdmissionError.duplicatePort
        }
        guard registrations.count < capacity else {
            throw RestoreTaskAdmissionError.capacityExceeded(limit: capacity)
        }
        let registration = RestoreTaskRegistration(
            attemptID: attemptID,
            canonicalECID: ecid,
            portKey: port)
        registrations[attemptID] = registration
        return registration
    }

    func release(_ attemptID: UUID) {
        registrations[attemptID] = nil
    }
}

/// 单个 attempt 的离线执行请求。
struct RestoreTaskExecutionRequest: Equatable, Sendable {
    let attemptID: UUID
    let taskID: UUID
    let canonicalECID: String
    let portKey: String
    let ipswURL: URL
    let request: CfgutilRestoreRequest
}

enum RestoreLeaseOwnership: Equatable, Sendable {
    /// 核心自己获取/释放机器租约（P3-A 独立用法）。
    case ownedByCore
    /// 租约已由产品模型持有；核心只刷新在制标记，不 acquire/clear/release。
    case ownedExternally
}

enum RestoreTaskTerminalStatus: String, Equatable, Sendable {
    case succeeded
    case failed
    case canceled
    case unknown
}

struct RestoreTaskTerminalRecord: Equatable, Sendable {
    let attemptID: UUID
    let status: RestoreTaskTerminalStatus
    let exitCode: Int32?
    let stdoutURL: URL?
    let stderrURL: URL?
    let snapshot: RestoreOutputSnapshot
    let lifecycle: RestoreLifecycleTimes?
    let terminationReason: RestoreTerminationReason
    let sentSignals: [RestoreSentSignal]
    let rawEvidenceStatus: RestoreRawEvidenceStatus
}

/// 双任务执行核心：每个 attempt 一个引擎实例，独立取消、独立终态、独立输出归属。
@MainActor
final class RestoreDualRestoreCore {
    let registry: RestoreTaskRegistry
    private let releaseRegistryOnComplete: Bool
    private let lease: RestoreProcessLease
    private let engineFactory: @MainActor () -> any RestoreEngineRunning

    private(set) var engines: [UUID: any RestoreEngineRunning] = [:]
    private(set) var snapshots: [UUID: RestoreOutputSnapshot] = [:]
    private(set) var terminal: [UUID: RestoreTaskTerminalRecord] = [:]
    private(set) var cancellationRequested: Set<UUID> = []
    private(set) var leaseAcquireCount = 0
    private(set) var leaseReleaseCount = 0
    private(set) var isLeaseHeld = false
    private(set) var activeAttemptIDs: Set<UUID> = []

    /// 仅测试可覆盖：模拟启动期失败（launchPermitted 返回 false）。
    var launchGuard: @MainActor (UUID) -> Bool = { _ in true }

    private var runs: [UUID: Task<Void, Never>] = [:]
    private var activeOutputDirectories: Set<String> = []
    private var outputDirectoryByAttempt: [UUID: String] = [:]
    private var leaseOwnershipByAttempt: [UUID: RestoreLeaseOwnership] = [:]
    private var updateCallbacks: [UUID: @MainActor (UUID, RestoreOutputSnapshot) -> Void] = [:]
    private var finishCallbacks: [UUID: @MainActor (RestoreTaskTerminalRecord) -> Void] = [:]

    init(
        registry: RestoreTaskRegistry? = nil,
        releaseRegistryOnComplete: Bool = true,
        lease: RestoreProcessLease,
        engineFactory: @escaping @MainActor () -> any RestoreEngineRunning
    ) {
        self.registry = registry ?? RestoreTaskRegistry()
        self.releaseRegistryOnComplete = releaseRegistryOnComplete
        self.lease = lease
        self.engineFactory = engineFactory
    }

    var activeCount: Int { activeAttemptIDs.count }

    /// 原子准入 + 租约获取 + 启动。任一步失败都会回滚已取得的资源。
    @discardableResult
    func start(
        _ execution: RestoreTaskExecutionRequest,
        leaseOwnership: RestoreLeaseOwnership = .ownedByCore,
        onUpdate: (@MainActor (UUID, RestoreOutputSnapshot) -> Void)? = nil,
        onFinish: (@MainActor (RestoreTaskTerminalRecord) -> Void)? = nil
    ) throws -> RestoreTaskRegistration {
        // 声明身份必须与真正传给 cfgutil 的目标一致，避免“登记 A、执行 B”。
        guard let declaredECID = ECIDIdentity(hex: execution.canonicalECID),
              declaredECID.value == execution.request.targetECID,
              execution.request.taskID == execution.taskID,
              execution.request.ipswURL == execution.ipswURL else {
            throw RestoreTaskAdmissionError.identityMismatch
        }
        guard terminal[execution.attemptID] == nil else {
            throw RestoreTaskAdmissionError.duplicateAttempt
        }
        if let directory = execution.request.outputDirectory,
           activeOutputDirectories.contains(directory.standardizedFileURL.path) {
            throw RestoreTaskAdmissionError.duplicateOutputDirectory
        }
        let registration = try registry.reserve(
            attemptID: execution.attemptID,
            canonicalECID: execution.canonicalECID,
            portKey: execution.portKey)
        var acquiredLeaseHere = false
        do {
            switch leaseOwnership {
            case .ownedByCore:
                if !isLeaseHeld {
                    switch lease.acquire() {
                    case .acquired:
                        isLeaseHeld = true
                        acquiredLeaseHere = true
                        leaseAcquireCount += 1
                    case .busy:
                        throw RestoreTaskAdmissionError.machineLeaseBusy
                    case .unavailable(let reason):
                        throw RestoreTaskAdmissionError.machineLeaseUnavailable(reason)
                    }
                }
            case .ownedExternally:
                // 外部所有者已持有机器锁；这里只刷新在制标记。
                break
            }
            // 每次准入都刷新在制标记，保证第二个任务 spawn 窗口也受宽限期保护。
            guard lease.writeInProgress() else {
                throw RestoreTaskAdmissionError.inProgressMarkerFailed
            }
            let engine = engineFactory()
            engines[execution.attemptID] = engine
            snapshots[execution.attemptID] = RestoreOutputSnapshot()
            leaseOwnershipByAttempt[execution.attemptID] = leaseOwnership
            if let onUpdate {
                updateCallbacks[execution.attemptID] = onUpdate
            }
            if let onFinish {
                finishCallbacks[execution.attemptID] = onFinish
            }
            activeAttemptIDs.insert(execution.attemptID)
            if let directory = execution.request.outputDirectory {
                let path = directory.standardizedFileURL.path
                activeOutputDirectories.insert(path)
                outputDirectoryByAttempt[execution.attemptID] = path
            }
            startRun(execution, engine: engine)
            return registration
        } catch {
            registry.release(execution.attemptID)
            if acquiredLeaseHere {
                lease.clearInProgress()
                lease.release()
                isLeaseHeld = false
                leaseReleaseCount += 1
            }
            throw error
        }
    }

    /// 仅取消指定 attempt；其它任务的引擎不会被触碰。
    func cancel(_ attemptID: UUID) {
        guard activeAttemptIDs.contains(attemptID),
              !cancellationRequested.contains(attemptID) else { return }
        // 许可撤销必须先于任何引擎引用判断：准备期可能尚无进程。
        cancellationRequested.insert(attemptID)
        engines[attemptID]?.cancel()
    }

    func forceKill(_ attemptID: UUID) {
        guard activeAttemptIDs.contains(attemptID),
              cancellationRequested.contains(attemptID),
              let engine = engines[attemptID] else { return }
        engine.forceKill()
    }

    func terminalRecord(for attemptID: UUID) -> RestoreTaskTerminalRecord? {
        terminal[attemptID]
    }

    func waitUntilStarted(_ attemptID: UUID, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if activeAttemptIDs.contains(attemptID) { return }
            await Task.yield()
        }
    }

    func waitUntilIdle(timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !activeAttemptIDs.isEmpty && Date() < deadline {
            await Task.yield()
        }
    }

    /// 某 attempt 当前是否仍被允许启动 cfgutil。
    /// 取消、终态、或已不活动时立即为 false；每次异步恢复后都必须重新询问。
    private func isLaunchPermitted(_ attemptID: UUID) -> Bool {
        activeAttemptIDs.contains(attemptID)
            && !cancellationRequested.contains(attemptID)
            && terminal[attemptID] == nil
    }

    /// 契约（P3-A 审计）：
    /// - 已取消/已终态的 UUID 绝不再调用任何外部钩子；
    /// - 外部 `launchGuard` 可以同步取消本任务，所以它返回后必须重新读取
    ///   `isLaunchPermitted`，不得缓存调用前的布尔值；
    /// - 真实引擎在最终许可检查与 `process.run()` 之间没有回调或 await；
    ///   若未来在该区间引入可重入点，必须在此层再次复核。
    private func startRun(
        _ execution: RestoreTaskExecutionRequest,
        engine: any RestoreEngineRunning
    ) {
        let attemptID = execution.attemptID
        runs[attemptID] = Task { @MainActor [weak self] in
            guard let self else { return }
            // 同一回合内被取消、或已收尾：不得调用 launcher，直接按取消收尾。
            guard self.isLaunchPermitted(attemptID) else {
                self.completeCanceledBeforeLaunch(attemptID)
                return
            }
            let result = await engine.run(
                request: execution.request,
                launchPermitted: { [weak self] in
                    guard let self else { return false }
                    // 契约：外部钩子可以执行任意同步代码（包括取消本任务），
                    // 因此绝不缓存钩子之前的许可结果；钩子返回后再读取一次权威状态。
                    guard self.isLaunchPermitted(attemptID) else { return false }
                    guard self.launchGuard(attemptID) else { return false }
                    return self.isLaunchPermitted(attemptID)
                },
                onUpdate: { [weak self] snapshot in
                    // 迟到回调：attempt 已收尾时不更新任何状态。
                    guard let self,
                          self.activeAttemptIDs.contains(attemptID) else { return }
                    self.snapshots[attemptID] = snapshot
                    self.updateCallbacks[attemptID]?(attemptID, snapshot)
                })
            self.finish(attemptID, result: result)
        }
    }

    private func finish(
        _ attemptID: UUID,
        result: CfgutilRestoreRunResult
    ) {
        UIFixture.debugEvent(
            "B_CORE_FINISH_MAP",
            "attempt=\(attemptID.uuidString.prefix(8)) outcome=\(result.outcome.rawValue)")
        let status: RestoreTaskTerminalStatus
        switch result.outcome {
        case .success: status = .succeeded
        case .failure: status = .failed
        case .canceled: status = .canceled
        case .unknown: status = .unknown
        }
        complete(
            attemptID,
            record: RestoreTaskTerminalRecord(
                attemptID: attemptID,
                status: status,
                exitCode: result.exitCode,
                stdoutURL: result.stdoutURL,
                stderrURL: result.stderrURL,
                snapshot: result.snapshot,
            lifecycle: result.lifecycle,
            terminationReason: result.terminationReason,
            sentSignals: result.sentSignals,
            rawEvidenceStatus: result.rawEvidence.status))
    }

    /// 尚未启动 cfgutil 就被取消：不调用 launcher，直接写取消终态。
    private func completeCanceledBeforeLaunch(_ attemptID: UUID) {
        let snapshot = snapshots[attemptID] ?? RestoreOutputSnapshot()
        complete(
            attemptID,
            record: RestoreTaskTerminalRecord(
                attemptID: attemptID,
                status: .canceled,
                exitCode: nil,
                stdoutURL: nil,
                stderrURL: nil,
                snapshot: snapshot,
                lifecycle: nil,
                terminationReason: .unknown,
                sentSignals: [],
                rawEvidenceStatus: .notSavedByChoice))
    }

    private func complete(
        _ attemptID: UUID,
        record: RestoreTaskTerminalRecord
    ) {
        // 终态只写一次。
        guard activeAttemptIDs.contains(attemptID) else { return }
        terminal[attemptID] = record
        let ownership = leaseOwnershipByAttempt.removeValue(forKey: attemptID)
            ?? .ownedExternally
        let finishCallback = finishCallbacks.removeValue(forKey: attemptID)
        updateCallbacks[attemptID] = nil
        activeAttemptIDs.remove(attemptID)
        if let path = outputDirectoryByAttempt.removeValue(forKey: attemptID) {
            activeOutputDirectories.remove(path)
        }
        engines[attemptID] = nil
        runs[attemptID] = nil
        // 产品外持模式由模型在归档/历史结算后释放；核心自持保持旧语义。
        if releaseRegistryOnComplete {
            registry.release(attemptID)
        }
        if ownership == .ownedByCore, registry.isEmpty {
            lease.clearInProgress()
            lease.release()
            isLeaseHeld = false
            leaseReleaseCount += 1
        }
        finishCallback?(record)
    }
}

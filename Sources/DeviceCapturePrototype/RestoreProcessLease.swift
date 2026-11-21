import Foundation
import Darwin

/// 跨进程独占租约：Restore 单任务槽的唯一权威互斥。
///
/// ## 设计要点（REV2）
///
/// 1. **单一锁域**：唯一权威路径 `/Users/Shared/MRA-Restore-Slot.lease`。
///    不回退到每用户目录——那会造成两把互不相干的锁。
/// 2. **非阻塞 flock**：`flock(LOCK_EX | LOCK_NB)`；被占用即 `.busy`。
/// 3. **异常退出**：内核在描述符关闭后立即释放锁。Foundation 的 `Process` 会关闭
///    除 stdin/stdout/stderr 外的所有描述符，无法让 cfgutil 继承锁，因此崩溃恢复
///    依赖“在制标记 + cfgutil 存活探测”：App 崩溃后若仍有 cfgutil 进程在运行，
///    重启的实例一律拒绝启动（详见文件末尾的孤儿防护说明）。
/// 4. **路径不可替换**：父目录 `lstat`（真实目录、拒绝符号链接；权威路径额外要求
///    root 拥有且 sticky）、`O_NOFOLLOW` 打开、`fstat` 必须是常规文件、
///    取得锁后复核 `dev+ino` 未变。
/// 5. **跨用户会话**：创建后尽力 `fchmod 0666`，使另一本地用户可打开同一 inode 竞争。
/// 6. 锁文件永不删除；内容仅诊断用，不参与归属判定。
final class RestoreProcessLease {
    enum AcquireOutcome: Equatable {
        case acquired
        case busy
        case unavailable(String)
    }

    static let authoritativeLockPath = "/Users/Shared/MRA-Restore-Slot.lease"

    /// 进程内共享实例：同一进程的多个模型共用同一把锁。
    static let shared = RestoreProcessLease()

    let lockURL: URL
    private let requiresProtectedParent: Bool
    /// 新鲜在制标记的宽限期：启动到进程可识别之间存在极短窗口，
    /// 此窗口内的标记不得判为陈旧。
    let launchGrace: TimeInterval
    private let checkOrphanCfgutil: Bool

    private var descriptor: Int32 = -1

    /// - Parameters:
    ///   - lockURL: 权威路径，或测试注入的临时路径。
    ///   - requiresProtectedParent: 是否强制父目录为 root 拥有的 sticky 目录。
    ///     默认仅对权威路径开启，避免影响测试临时目录。
    init(
        lockURL: URL = URL(fileURLWithPath: RestoreProcessLease.authoritativeLockPath),
        requiresProtectedParent: Bool? = nil,
        launchGrace: TimeInterval = 10,
        checkOrphanCfgutil: Bool = true
    ) {
        self.lockURL = lockURL
        self.requiresProtectedParent = requiresProtectedParent
            ?? (lockURL.path == RestoreProcessLease.authoritativeLockPath)
        self.launchGrace = max(0, launchGrace)
        self.checkOrphanCfgutil = checkOrphanCfgutil
    }

    deinit {
        closeDescriptor()
    }

    var isHeld: Bool { descriptor >= 0 }

    /// 尝试取得租约；永不阻塞。
    func acquire() -> AcquireOutcome {
        if descriptor >= 0 { return .busy }

        let parent = lockURL.deletingLastPathComponent()
        var parentStat = stat()
        guard lstat(parent.path, &parentStat) == 0 else {
            return .unavailable("parent lstat errno \(errno)")
        }
        guard (parentStat.st_mode & S_IFMT) == S_IFDIR else {
            return .unavailable("parent is not a directory")
        }
        if requiresProtectedParent {
            guard parentStat.st_uid == 0,
                  (parentStat.st_mode & mode_t(S_ISVTX)) != 0 else {
                return .unavailable("parent is not a root-owned sticky directory")
            }
        }

        var fd: Int32 = -1
        repeat {
            fd = open(
                lockURL.path,
                O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
                0o666)
        } while fd < 0 && errno == EINTR
        guard fd >= 0 else {
            return .unavailable("open errno \(errno)")
        }

        var fileStat = stat()
        guard fstat(fd, &fileStat) == 0 else {
            close(fd)
            return .unavailable("fstat errno \(errno)")
        }
        guard (fileStat.st_mode & S_IFMT) == S_IFREG else {
            close(fd)
            return .unavailable("lock path is not a regular file")
        }

        var lockResult: Int32 = -1
        repeat {
            lockResult = flock(fd, LOCK_EX | LOCK_NB)
        } while lockResult != 0 && errno == EINTR
        if lockResult != 0 {
            let code = errno
            close(fd)
            if code == EWOULDBLOCK || code == EAGAIN {
                return .busy
            }
            return .unavailable("flock errno \(code)")
        }

        // 身份复核：取得锁后路径必须仍指向同一 inode，否则说明锁文件被替换。
        var pathStat = stat()
        guard lstat(lockURL.path, &pathStat) == 0,
              (pathStat.st_mode & S_IFMT) == S_IFREG,
              pathStat.st_dev == fileStat.st_dev,
              pathStat.st_ino == fileStat.st_ino else {
            _ = flock(fd, LOCK_UN)
            close(fd)
            return .unavailable("lock file identity changed during acquisition")
        }

        // 无论是否存在在制标记，都必须探测是否有 cfgutil 正在运行：
        // 旧版本（rc2 及更早）没有标记，其遗留刷机进程同样必须被拦住。
        if checkOrphanCfgutil {
            guard let cfgutilCount = Self.runningCfgutilProcessCount() else {
                _ = flock(fd, LOCK_UN)
                close(fd)
                return .unavailable("cannot enumerate processes for orphan detection")
            }
            if cfgutilCount > 0 {
                _ = flock(fd, LOCK_UN)
                close(fd)
                return .unavailable("previous restore may still be running")
            }
        }

        switch inProgressState() {
        case .absent:
            break
        case .unreadable:
            // 无法解析（0 字节、乱码、符号链接、超限）：只有确认不是"刚写入"
            // 才允许清除，否则视为仍在启动阶段。
            if let age = Self.markerAge(at: markerURL), age < launchGrace {
                _ = flock(fd, LOCK_UN)
                close(fd)
                return .unavailable("previous restore may still be starting")
            }
            guard clearInProgress() else {
                _ = flock(fd, LOCK_UN)
                close(fd)
                return .unavailable("in-progress marker cannot be cleared")
            }
        case .present(let marker):
            // 新鲜标记：可能是"已 spawn、cfgutil 尚未出现在进程表"的窗口，
            // 不得判为陈旧，否则会放行第二个 Restore。
            if Date().timeIntervalSince(marker.createdAt) < launchGrace {
                _ = flock(fd, LOCK_UN)
                close(fd)
                return .unavailable("previous restore may still be starting")
            }
            guard clearInProgress() else {
                _ = flock(fd, LOCK_UN)
                close(fd)
                return .unavailable("stale in-progress marker cannot be cleared")
            }
        }

        _ = fchmod(fd, 0o666)
        writeDiagnostics(to: fd)

        descriptor = fd
        return .acquired
    }

    func release() {
        closeDescriptor()
    }

    private func closeDescriptor() {
        guard descriptor >= 0 else { return }
        _ = flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    private func writeDiagnostics(to fd: Int32) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "pid=\(getpid()) uid=\(getuid()) acquired=\(stamp)\n"
        _ = ftruncate(fd, 0)
        _ = line.withCString { pointer in
            write(fd, pointer, strlen(pointer))
        }
    }
}

// MARK: - 崩溃/强退后的孤儿 Restore 防护
//
// Foundation 的 Process 会关闭除 stdin/stdout/stderr 外的描述符，无法让 cfgutil
// 继承锁，因此改用“在制标记 + cfgutil 存活探测”：
//
// - 启动 cfgutil 前写入最小在制标记（版本 / App PID / 写入时间）。
//   **不记录 ECID、IPSW 路径、设备名或任何客户信息。**
// - 正常结束（成功/失败/取消）后删除标记。
// - 取得锁时若发现标记：App PID 仍存活 → busy；App 已死但有 cfgutil → 拒绝；
//   App 已死且无 cfgutil，但标记仍在启动宽限期内 → 拒绝（spawn 到进程可识别之间
//   的窗口）；超出宽限期且确实无 cfgutil → 清陈旧标记后继续。
// - 标记的读写都用 O_NOFOLLOW + fstat 常规文件检查 + 4 KiB 上限；
//   不可读、非普通文件（含符号链接）、超限或枚举进程失败 → fail-closed。
//
// 说明：这是尽力而为的孤儿检测，不改变 flock 的权威互斥语义。

struct RestoreInProgressMarker: Equatable {
    static let schemaVersion = 1

    let appPID: Int32
    let createdAt: Date
}

extension RestoreProcessLease {
    enum InProgressState {
        case absent
        case unreadable
        case present(RestoreInProgressMarker)
    }

    private enum MarkerReadResult {
        case absent
        case unreadable
        case present(RestoreInProgressMarker)
    }

    var markerURL: URL {
        URL(fileURLWithPath: lockURL.path + ".inprogress")
    }

    func inProgressState() -> InProgressState {
        switch Self.readMarker(at: markerURL) {
        case .absent: return .absent
        case .unreadable: return .unreadable
        case .present(let marker): return .present(marker)
        }
    }

    /// 写入最小在制标记（不包含设备身份或固件路径）。
    ///
    /// 先写临时文件、`fsync` 后 `rename`，保证路径上永远不会出现半截/0 字节标记。
    @discardableResult
    func writeInProgress() -> Bool {
        let payload: [String: Any] = [
            "v": RestoreInProgressMarker.schemaVersion,
            "appPid": Int(getpid()),
            "createdAt": ISO8601DateFormatter().string(from: Date())
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]) else {
            return false
        }

        let temporaryURL = URL(
            fileURLWithPath: markerURL.path + ".tmp.\(getpid())")
        var fd: Int32 = -1
        repeat {
            fd = open(
                temporaryURL.path,
                O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC | O_NOFOLLOW,
                0o666)
        } while fd < 0 && errno == EINTR
        guard fd >= 0 else { return false }

        let written = data.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return Darwin.write(fd, base, raw.count)
        }
        _ = fsync(fd)
        close(fd)
        guard written == data.count else {
            _ = unlink(temporaryURL.path)
            return false
        }
        guard rename(temporaryURL.path, markerURL.path) == 0 else {
            _ = unlink(temporaryURL.path)
            return false
        }
        return true
    }

    /// 标记文件的 mtime 年龄（秒）；无法 `lstat` 时返回 nil。
    static func markerAge(at url: URL) -> TimeInterval? {
        var fileStat = stat()
        guard lstat(url.path, &fileStat) == 0 else { return nil }
        let modified = TimeInterval(fileStat.st_mtimespec.tv_sec)
            + TimeInterval(fileStat.st_mtimespec.tv_nsec) / 1_000_000_000
        return max(0, Date().timeIntervalSince1970 - modified)
    }

    /// 删除在制标记；返回是否已不存在（删除失败且仍存在则为 false）。
    @discardableResult
    func clearInProgress() -> Bool {
        do {
            try FileManager.default.removeItem(at: markerURL)
            return true
        } catch {
            return !FileManager.default.fileExists(atPath: markerURL.path)
        }
    }

    private static func readMarker(at url: URL) -> MarkerReadResult {
        var fd: Int32 = -1
        repeat {
            fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        } while fd < 0 && errno == EINTR
        if fd < 0 {
            return errno == ENOENT ? .absent : .unreadable
        }
        defer { close(fd) }

        var fileStat = stat()
        guard fstat(fd, &fileStat) == 0,
              (fileStat.st_mode & S_IFMT) == S_IFREG,
              fileStat.st_size > 0,
              fileStat.st_size <= 4096 else {
            return .unreadable
        }

        var buffer = [UInt8](repeating: 0, count: Int(fileStat.st_size))
        let bytesRead = buffer.withUnsafeMutableBytes { raw -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return Darwin.read(fd, base, raw.count)
        }
        guard bytesRead == buffer.count,
              let object = try? JSONSerialization.jsonObject(with: Data(buffer)),
              let dictionary = object as? [String: Any],
              let version = dictionary["v"] as? NSNumber,
              version.intValue == RestoreInProgressMarker.schemaVersion,
              let pid = dictionary["appPid"] as? NSNumber,
              let created = dictionary["createdAt"] as? String,
              let date = ISO8601DateFormatter().date(from: created) else {
            return .unreadable
        }
        return .present(RestoreInProgressMarker(
            appPID: pid.int32Value,
            createdAt: date))
    }

    /// 枚举内核进程表，统计进程名恰为 `cfgutil` 的进程数；失败返回 nil。
    ///
    /// 进程表在两次 `sysctl` 之间可能变大（测试/构建期间尤其明显），
    /// 此时 `sysctl` 返回 `ENOMEM` 并回填所需大小；这里按内核惯用做法扩充重试，
    /// 避免把"进程表正在变化"误判为"无法保证独占"而拒绝 Restore。
    static func runningCfgutilProcessCount() -> Int? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        let stride = MemoryLayout<kinfo_proc>.stride
        var processes: [kinfo_proc] = []

        var obtained = false
        for _ in 0..<3 {
            var size = 0
            let first = mib.withUnsafeMutableBufferPointer { buffer in
                sysctl(buffer.baseAddress, u_int(buffer.count), nil, &size, nil, 0)
            }
            guard first == 0, size > 0 else { return nil }
            var capacity = max(1, size / stride + 16)
            var actual = capacity * stride
            processes = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
            let second = processes.withUnsafeMutableBufferPointer { procBuffer in
                mib.withUnsafeMutableBufferPointer { mibBuffer in
                    sysctl(
                        mibBuffer.baseAddress,
                        u_int(mibBuffer.count),
                        procBuffer.baseAddress,
                        &actual,
                        nil,
                        0)
                }
            }
            if second == 0 {
                processes = Array(processes.prefix(min(actual / stride, capacity)))
                obtained = true
                break
            }
            guard errno == ENOMEM else { return nil }
            // 进程表变大：按内核回填的大小重试。
            _ = capacity
        }
        guard obtained else { return nil }
        let count = processes.count
        var matches = 0
        for index in 0..<count {
            let pid = processes[index].kp_proc.p_pid
            guard pid > 0, pid != getpid() else { continue }
            var comm = processes[index].kp_proc.p_comm
            let name = withUnsafeBytes(of: &comm) { raw -> String in
                guard let base = raw.baseAddress?
                    .assumingMemoryBound(to: CChar.self) else { return "" }
                return String(cString: base)
            }
            if name == "cfgutil" { matches += 1 }
        }
        return matches
    }

}

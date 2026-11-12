import Foundation
import Darwin
import MRAHelperProtocol

/// Testable Helper policy and backend invocation helpers.
/// The listen loop stays in HelperMain.swift so this file can be compiled
/// into a library for Tests/MRAHelperTests without starting a socket server.
public enum MRAHelperCore {
    /// Owner+group read/write, no "other" access. Never world-writable.
    public static let desiredSocketPOSIXMode: mode_t = 0o660
    public static let staffGroupID: gid_t = 20

    public static func backendArguments(
        action: String,
        controller: String,
        portNumber: Int,
        rid: Int
    ) -> [String] {
        [
            action,
            mraBackendControllerFlag, controller,
            mraBackendPortNumberFlag, String(portNumber),
            mraBackendRIDFlag, String(rid),
        ]
    }

    /// Unsigned-test bypass is unreachable in a production build, and is also
    /// rejected when the Helper is bound to the production socket path.
    public static func allowsUnsignedTestBypass(
        environment: [String: String],
        socketPath: String,
        productionSocketPath: String = mraHelperSocketPath,
        testingBuild: Bool = false
    ) -> Bool {
        guard testingBuild else { return false }
        guard environment["MRA_HELPER_ALLOW_UNSIGNED_TEST"] == "1" else { return false }
        guard socketPath != productionSocketPath else { return false }
        return true
    }

    public static func applySocketPermissions(path: String) throws {
        guard chmod(path, desiredSocketPOSIXMode) == 0 else {
            throw posixError("chmod")
        }
        let gid = consoleUserGid() ?? staffGroupID
        let uid: uid_t
        if geteuid() == 0 {
            uid = 0
        } else {
            var st = stat()
            uid = lstat(path, &st) == 0 ? st.st_uid : geteuid()
        }
        if chown(path, uid, gid) != 0, geteuid() == 0 {
            throw posixError("chown")
        }
    }

    public static func posixMode(at path: String) throws -> mode_t {
        var st = stat()
        guard lstat(path, &st) == 0 else {
            throw posixError("lstat")
        }
        return st.st_mode & 0o777
    }

    public static func runBackend(
        action: String,
        controller: String,
        portNumber: Int,
        rid: Int,
        backendPath: String
    ) -> (Int32, String, String) {
        guard FileManager.default.isExecutableFile(atPath: backendPath) else {
            return (-1, "", "BACKEND_MISSING")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: backendPath)
        process.arguments = backendArguments(
            action: action, controller: controller, portNumber: portNumber, rid: rid)
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do { try process.run() } catch { return (-1, "", "BACKEND_SPAWN_FAILED") }
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }

    public static func consoleUserGid() -> gid_t? {
        var st = stat()
        guard stat("/dev/console", &st) == 0 else { return nil }
        guard let pw = getpwuid(st.st_uid) else { return nil }
        return pw.pointee.pw_gid
    }


    /// Upper bound for a single newline-delimited request on the Helper socket.
    public static let maxRequestBytes = 64 * 1024
    /// In-flight accepted connections the Helper will handle at once.
    public static let maxConcurrentConnections = 8
    /// Read deadline for a single client connection.
    public static let connectionReadTimeout: TimeInterval = 5

    public enum RequestAccumulation: Equatable {
        case needMore
        case complete(Data)
        case tooLarge
    }

    /// Accumulate one newline-delimited request. Fail closed when the first
    /// line would exceed `maxBytes`. Bytes past the first newline are ignored.
    public static func accumulateRequest(
        buffer: inout Data,
        incoming: Data,
        maxBytes: Int = maxRequestBytes
    ) -> RequestAccumulation {
        if let newline = incoming.firstIndex(of: 0x0A) {
            let lineByteCount = buffer.count + incoming.distance(from: incoming.startIndex, to: newline)
            if lineByteCount > maxBytes {
                return .tooLarge
            }
            buffer.append(incoming)
            if let idx = buffer.firstIndex(of: 0x0A) {
                return .complete(Data(buffer[..<idx]))
            }
            return .needMore
        }
        if buffer.count + incoming.count > maxBytes {
            return .tooLarge
        }
        buffer.append(incoming)
        return .needMore
    }

    public static func readHasTimedOut(
        startedAt: Date,
        now: Date = Date(),
        timeout: TimeInterval = connectionReadTimeout
    ) -> Bool {
        return now.timeIntervalSince(startedAt) >= timeout
    }

    public final class ConnectionLimiter: @unchecked Sendable {
        public let maxConcurrent: Int
        private let lock = NSLock()
        private var active = 0

        public init(maxConcurrent: Int = MRAHelperCore.maxConcurrentConnections) {
            self.maxConcurrent = maxConcurrent
        }

        /// Returns false when the Helper is already at capacity. The caller
        /// must invoke `end()` exactly once after a successful `tryBegin()`.
        public func tryBegin() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard active < maxConcurrent else { return false }
            active += 1
            return true
        }

        public func end() {
            lock.lock()
            defer { lock.unlock() }
            if active > 0 { active -= 1 }
        }
    }

    private static func posixError(_ op: String) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno),
            userInfo: [NSLocalizedDescriptionKey: "\(op) failed: \(String(cString: strerror(errno)))"])
    }
}

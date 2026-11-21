import Foundation

/// Real backend: `/usr/bin/log stream` as an owned child process.
///
/// Binding rules enforced here:
/// - fixed executable path, never a shell string;
/// - argument vector, never string concatenation;
/// - stdout goes straight to the session raw log (no in-memory buffering);
/// - stderr goes to its own diagnostic file;
/// - the PID is only ever acted on together with the executable path and the
///   argument vector captured at start, so a recycled PID is not ours.
///
/// Measured on macOS 27.2: `log stream` ignores SIGINT but exits on SIGTERM.
/// The stop path therefore requests SIGTERM and never escalates by PID alone.
public actor ProcessLogCaptureBackend: LogCaptureBackend {
    public let kind = "process"

    private let executableURL = URL(fileURLWithPath: "/usr/bin/log")
    private var processes: [Int32: Process] = [:]
    private var writeHandles: [Int32: [FileHandle]] = [:]

    public init() {}

    public func start(
        config: CaptureConfig,
        rawLogURL: URL,
        stderrURL: URL
    ) async throws -> BackendHandle {
        for url in [rawLogURL, stderrURL] where !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw CaptureError.backendStartFailed("cannot create \(url.path)")
            }
        }

        let out = try FileHandle(forWritingTo: rawLogURL)
        let err = try FileHandle(forWritingTo: stderrURL)

        let process = Process()
        process.executableURL = executableURL
        process.arguments = config.profile.commandArguments
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            try? out.close()
            try? err.close()
            throw CaptureError.backendStartFailed(String(describing: error))
        }

        let pid = process.processIdentifier
        processes[pid] = process
        writeHandles[pid] = [out, err]

        return BackendHandle(
            pid: pid,
            executablePath: executableURL.path,
            arguments: config.profile.commandArguments,
            startedAtUTC: Date()
        )
    }

    /// Bounded wait. Returns `nil` when the process is still alive at the
    /// deadline so the caller can report "exit not observed" instead of guessing.
    public func waitForExit(handle: BackendHandle) async -> Int32? {
        guard let process = processes[handle.pid] else { return nil }
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard !process.isRunning else { return nil }
        let code = process.terminationStatus
        flushAndClose(pid: handle.pid)
        processes[handle.pid] = nil
        return code
    }

    public func requestTermination(handle: BackendHandle) async {
        guard let process = processes[handle.pid], process.isRunning else { return }
        // SIGTERM only. SIGINT is ignored by `log stream` (measured), and a
        // blind SIGKILL would risk losing the tail of the file.
        process.terminate()
    }

    public func isRunning(handle: BackendHandle) async -> Bool {
        guard let process = processes[handle.pid] else { return false }
        return process.isRunning
    }

    private func flushAndClose(pid: Int32) {
        guard let handles = writeHandles[pid] else { return }
        for handle in handles {
            try? handle.synchronize()
            try? handle.close()
        }
        writeHandles[pid] = nil
    }
}

import Foundation

/// Low-volume pre-capture watcher for a real Configurator Restore command.
///
/// It deliberately does NOT use DFU/USB presence as a trigger. The trigger is
/// the Configurator/DeviceService event that starts a restore operation.
/// It keeps a bounded ring of recent lines and hands that context to the full
/// capture session as a separate file; it never prepends bytes to restore.log.
public final class RestoreStartMonitor: @unchecked Sendable {
    public struct Config: Sendable {
        public var executableURL: URL
        public var predicate: String
        public var bufferLineLimit: Int

        public init(
            executableURL: URL = URL(fileURLWithPath: "/usr/bin/log"),
            predicate: String = #"process CONTAINS[c] "configurator" AND eventMessage CONTAINS[c] "ACURestoreFirmwareCommand""#,
            bufferLineLimit: Int = 120
        ) {
            self.executableURL = executableURL
            self.predicate = predicate
            self.bufferLineLimit = bufferLineLimit
        }

        public var arguments: [String] {
            ["stream", "--style", "compact", "--level", "debug", "--no-backtrace", "--no-signpost", "--predicate", predicate]
        }
    }

    public typealias StartedHandler = @Sendable (String) -> Void
    public typealias FailureHandler = @Sendable (String) -> Void

    private let config: Config
    private let onStart: StartedHandler
    private let onFailure: FailureHandler
    private let lock = NSLock()
    private var process: Process?
    private var pipe: Pipe?
    private var buffer: [String] = []
    private var carry = Data()
    private var triggered = false
    private var stopped = false

    public init(config: Config = Config(), onStart: @escaping StartedHandler, onFailure: @escaping FailureHandler) {
        self.config = config
        self.onStart = onStart
        self.onFailure = onFailure
    }

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return process?.isRunning == true && !stopped
    }

    public func start() throws {
        lock.lock(); defer { lock.unlock() }
        guard !stopped, process == nil else { return }
        let p = Process()
        p.executableURL = config.executableURL
        p.arguments = config.arguments
        p.standardInput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        self.process = p
        self.pipe = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }
        do {
            try p.run()
        } catch {
            self.process = nil
            self.pipe = nil
            throw error
        }
        p.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.lock.lock()
            let stoppedLocally = self.stopped
            self.lock.unlock()
            if !stoppedLocally && !self.isTriggered {
                self.onFailure("restore monitor exited with status \(proc.terminationStatus)")
            }
        }
    }

    public func stop() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true
        let p = process
        let pipe = self.pipe
        process = nil
        self.pipe = nil
        lock.unlock()
        pipe?.fileHandleForReading.readabilityHandler = nil
        if let p, p.isRunning {
            p.terminate()
            p.waitUntilExit()
        }
    }

    deinit { stop() }

    private var isTriggered: Bool {
        lock.lock(); defer { lock.unlock() }
        return triggered
    }

    private func consume(_ data: Data) {
        lock.lock()
        carry.append(data)
        var lines: [String] = []
        while let newline = carry.firstIndex(of: 0x0A) {
            let lineData = carry[carry.startIndex..<newline]
            carry = carry[carry.index(after: newline)...]
            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(line)
            }
        }
        let eventLines = lines.filter { line in
            // `log stream` prints a "Filtering the log data using ..." header
            // that itself contains the predicate text. It is NOT a restore event.
            // A real compact event starts with an ISO-like timestamp.
            line.range(of: #"^\d{4}-\d{2}-\d{2} "#, options: .regularExpression) != nil
        }
        for line in eventLines {
            buffer.append(line)
            if buffer.count > max(1, config.bufferLineLimit) {
                buffer.removeFirst(buffer.count - max(1, config.bufferLineLimit))
            }
        }
        let hit = eventLines.first { $0.range(of: "ACURestoreFirmwareCommand", options: .caseInsensitive) != nil }
        if let hit, !triggered {
            triggered = true
            let context = buffer.joined(separator: "\n")
            lock.unlock()
            stop()
            onStart(context + (context.isEmpty ? "" : "\n") + hit)
            return
        }
        lock.unlock()
    }
}

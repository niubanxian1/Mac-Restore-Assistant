import CryptoKit
import Darwin
import Foundation

enum RestoreOutputChannel: String, Sendable {
    case stdout
    case stderr
}

struct CfgutilRestoreRequest: Equatable, Sendable {
    let taskID: UUID
    let executableURL: URL
    let ipswURL: URL
    let targetECID: UInt64
    let outputDirectory: URL?

    var arguments: [String] {
        [
            "--progress",
            "-v",
            "-e",
            String(targetECID),
            "restore",
            "-I",
            ipswURL.path
        ]
    }
}

enum RestoreRawWriteStage: String, Codable, Equatable, Sendable {
    case directoryCreate = "DIRECTORY_CREATE"
    case fileCreate = "FILE_CREATE"
    case stdoutWrite = "STDOUT_WRITE"
    case stderrWrite = "STDERR_WRITE"
    case stdoutFlush = "STDOUT_FLUSH"
    case stderrFlush = "STDERR_FLUSH"
    case stdoutSynchronize = "STDOUT_SYNCHRONIZE"
    case stderrSynchronize = "STDERR_SYNCHRONIZE"
    case stdoutClose = "STDOUT_CLOSE"
    case stderrClose = "STDERR_CLOSE"
    case streamTail = "STREAM_TAIL"
    case fileVerification = "FILE_VERIFICATION"
}

struct RestoreRawWriteFailure: Codable, Equatable, Sendable {
    let stage: RestoreRawWriteStage
    let errno: Int32?
    let message: String
}

struct RestoreRawSinkCompletion: Equatable, Sendable {
    let writeComplete: Bool
    let stdoutBytes: Int64
    let stderrBytes: Int64
    let failures: [RestoreRawWriteFailure]
}

struct RestoreRawEvidenceResult: Codable, Equatable, Sendable {
    let status: RestoreRawEvidenceStatus
    let stdoutURL: URL?
    let stderrURL: URL?
    let stdoutSHA256: String
    let stderrSHA256: String
    let stdoutBytes: Int64
    let stderrBytes: Int64
    let writeComplete: Bool
    let tailPartialReason: String?
    let failures: [RestoreRawWriteFailure]

    static let notSavedByChoice = RestoreRawEvidenceResult(
        status: .notSavedByChoice,
        stdoutURL: nil,
        stderrURL: nil,
        stdoutSHA256: "",
        stderrSHA256: "",
        stdoutBytes: 0,
        stderrBytes: 0,
        writeComplete: false,
        tailPartialReason: nil,
        failures: [])
}

struct CfgutilProcessCompletion: Equatable, Sendable {
    let exitCode: Int32
    let stdoutEOF: Bool
    let stderrEOF: Bool
    let forcedKill: Bool
    let processExited: RestoreLifecycleTimePoint?
    let bothStreamsEOF: RestoreLifecycleTimePoint?
    let terminationReason: RestoreTerminationReason

    init(
        exitCode: Int32,
        stdoutEOF: Bool,
        stderrEOF: Bool,
        forcedKill: Bool,
        processExited: RestoreLifecycleTimePoint? = nil,
        bothStreamsEOF: RestoreLifecycleTimePoint? = nil,
        terminationReason: RestoreTerminationReason = .unknown
    ) {
        self.exitCode = exitCode
        self.stdoutEOF = stdoutEOF
        self.stderrEOF = stderrEOF
        self.forcedKill = forcedKill
        self.processExited = processExited
        self.bothStreamsEOF = bothStreamsEOF
        self.terminationReason = terminationReason
    }
}

struct CfgutilRestoreRunResult: Equatable, Sendable {
    let outcome: RestoreOutcome
    let exitCode: Int32?
    let stdoutURL: URL?
    let stderrURL: URL?
    let stdoutSHA256: String
    let stderrSHA256: String
    let tailComplete: Bool
    let cancellationRequested: Bool
    let forcedKill: Bool
    let snapshot: RestoreOutputSnapshot
    let lifecycle: RestoreLifecycleTimes
    let terminationReason: RestoreTerminationReason
    let sentSignals: [RestoreSentSignal]
    let rawEvidence: RestoreRawEvidenceResult

    init(
        outcome: RestoreOutcome,
        exitCode: Int32?,
        stdoutURL: URL?,
        stderrURL: URL?,
        stdoutSHA256: String,
        stderrSHA256: String,
        tailComplete: Bool,
        cancellationRequested: Bool,
        forcedKill: Bool,
        snapshot: RestoreOutputSnapshot,
        lifecycle: RestoreLifecycleTimes,
        terminationReason: RestoreTerminationReason = .unknown,
        sentSignals: [RestoreSentSignal] = [],
        rawEvidence: RestoreRawEvidenceResult? = nil
    ) {
        self.outcome = outcome
        self.exitCode = exitCode
        self.stdoutURL = stdoutURL
        self.stderrURL = stderrURL
        self.stdoutSHA256 = stdoutSHA256
        self.stderrSHA256 = stderrSHA256
        self.tailComplete = tailComplete
        self.cancellationRequested = cancellationRequested
        self.forcedKill = forcedKill
        self.snapshot = snapshot
        self.lifecycle = lifecycle
        self.terminationReason = terminationReason
        self.sentSignals = sentSignals
        self.rawEvidence = rawEvidence
            ?? RestoreRawEvidenceResult(
                status: .complete,
                stdoutURL: stdoutURL,
                stderrURL: stderrURL,
                stdoutSHA256: stdoutSHA256,
                stderrSHA256: stderrSHA256,
                stdoutBytes: 0,
                stderrBytes: 0,
                writeComplete: tailComplete,
                tailPartialReason: tailComplete ? nil : "STREAM_TAIL_INCOMPLETE",
                failures: [])
    }

    init(
        outcome: RestoreOutcome,
        exitCode: Int32?,
        stdoutURL: URL?,
        stderrURL: URL?,
        stdoutSHA256: String,
        stderrSHA256: String,
        tailComplete: Bool,
        cancellationRequested: Bool,
        forcedKill: Bool,
        snapshot: RestoreOutputSnapshot
    ) {
        let now = RestoreLifecycleClock.now()
        self.init(
            outcome: outcome,
            exitCode: exitCode,
            stdoutURL: stdoutURL,
            stderrURL: stderrURL,
            stdoutSHA256: stdoutSHA256,
            stderrSHA256: stderrSHA256,
            tailComplete: tailComplete,
            cancellationRequested: cancellationRequested,
            forcedKill: forcedKill,
            snapshot: snapshot,
            lifecycle: RestoreLifecycleTimes(
                userConfirmed: now,
                outcomeConfirmed: now),
            terminationReason: .unknown,
            sentSignals: [],
            rawEvidence: nil)
    }
}

enum CfgutilRestoreEngineError: Error, LocalizedError {
    case cfgutilUnavailable
    case launchFailed(String)
    case outputDirectoryUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .cfgutilUnavailable:
            return "未找到可执行的 Apple Configurator cfgutil。"
        case .launchFailed(let message):
            return "cfgutil 启动失败：\(message)"
        case .outputDirectoryUnavailable(let message):
            return "无法建立 Restore 原始输出目录：\(message)"
        }
    }
}

@MainActor
protocol CfgutilProcessRunning: AnyObject {
    var processLaunched: RestoreLifecycleTimePoint? { get }
    func waitForCompletion(tailTimeout: TimeInterval) async -> CfgutilProcessCompletion
    func interrupt()
    func terminate()
    func forceKill()
}

extension CfgutilProcessRunning {
    var processLaunched: RestoreLifecycleTimePoint? { nil }
}

@MainActor
protocol CfgutilProcessLaunching: AnyObject {
    func launch(
        request: CfgutilRestoreRequest,
        onChunk: @escaping @Sendable (RestoreOutputChannel, Data) -> Void
    ) throws -> any CfgutilProcessRunning
}

@MainActor
protocol RestoreEngineRunning: AnyObject {
    var isRunning: Bool { get }
    var cancellationGraceExpired: Bool { get }
    func run(
        request: CfgutilRestoreRequest,
        launchPermitted: @escaping @MainActor () -> Bool,
        onUpdate: (@MainActor (RestoreOutputSnapshot) -> Void)?
    ) async -> CfgutilRestoreRunResult
    func cancel()
    func forceKill()
}

extension RestoreEngineRunning {
    func run(
        request: CfgutilRestoreRequest,
        onUpdate: (@MainActor (RestoreOutputSnapshot) -> Void)? = nil
    ) async -> CfgutilRestoreRunResult {
        await run(
            request: request,
            launchPermitted: { true },
            onUpdate: onUpdate)
    }
}

@MainActor
final class CfgutilRestoreEngine: RestoreEngineRunning {
    nonisolated static let applicationCfgutilPath =
        "/Applications/Apple Configurator.app/Contents/MacOS/cfgutil"
    nonisolated static let fallbackCfgutilPath = "/usr/local/bin/cfgutil"

    private let launcher: any CfgutilProcessLaunching
    private let timeProvider: @Sendable () -> RestoreLifecycleTimePoint
    private let rawSinkFactory:
        (URL, URL) throws -> RestoreRawOutputSink
    private var activeProcess: (any CfgutilProcessRunning)?
    private(set) var isRunning = false
    private(set) var cancellationRequested = false
    private(set) var cancellationGraceExpired = false
    private(set) var cancelRequestedAt: RestoreLifecycleTimePoint?
    private var sentSignals: [RestoreSentSignal] = []
    private var cancellationTask: Task<Void, Never>?

    init(
        launcher: (any CfgutilProcessLaunching)? = nil,
        timeProvider: @escaping @Sendable () -> RestoreLifecycleTimePoint = {
            RestoreLifecycleClock.now()
        },
        rawSinkFactory:
            @escaping (URL, URL) throws -> RestoreRawOutputSink = {
                try RestoreRawOutputSink(
                    stdoutURL: $0,
                    stderrURL: $1)
        }
    ) {
        self.launcher = launcher
            ?? LiveCfgutilProcessLauncher(timeProvider: timeProvider)
        self.timeProvider = timeProvider
        self.rawSinkFactory = rawSinkFactory
    }

    nonisolated static func locateCfgutil(
        fileManager: FileManager = .default
    ) -> URL? {
        for path in [applicationCfgutilPath, fallbackCfgutilPath] {
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    func run(
        request: CfgutilRestoreRequest,
        launchPermitted: @escaping @MainActor () -> Bool,
        onUpdate: (@MainActor (RestoreOutputSnapshot) -> Void)? = nil
    ) async -> CfgutilRestoreRunResult {
        cancellationTask?.cancel()
        cancellationTask = nil
        let runEnteredAt = timeProvider()
        let outputDirectory = request.outputDirectory?
            .standardizedFileURL
        let stdoutURL = outputDirectory?.appendingPathComponent(
            "stdout.raw")
        let stderrURL = outputDirectory?.appendingPathComponent(
            "stderr.raw")
        guard launchPermitted() else {
            cancellationRequested = true
            cancelRequestedAt = timeProvider()
            sentSignals = []
            let confirmedAt = timeProvider()
            return CfgutilRestoreRunResult(
                outcome: .canceled,
                exitCode: nil,
                stdoutURL: stdoutURL,
                stderrURL: stderrURL,
                stdoutSHA256: "",
                stderrSHA256: "",
                tailComplete: false,
                cancellationRequested: true,
                forcedKill: false,
                snapshot: RestoreOutputSnapshot(),
                lifecycle: RestoreLifecycleTimes(
                    userConfirmed: runEnteredAt,
                    outcomeConfirmed: confirmedAt),
                terminationReason: .unknown,
                sentSignals: [],
                rawEvidence: request.outputDirectory == nil
                    ? .notSavedByChoice
                    : RestoreRawEvidenceResult(
                        status: .incompleteProtected,
                        stdoutURL: nil,
                        stderrURL: nil,
                        stdoutSHA256: "",
                        stderrSHA256: "",
                        stdoutBytes: 0,
                        stderrBytes: 0,
                        writeComplete: false,
                        tailPartialReason: "CANCELED_BEFORE_RAW_SINK",
                        failures: []))
        }

        cancellationRequested = false
        cancellationGraceExpired = false
        cancelRequestedAt = nil
        sentSignals = []
        isRunning = true
        defer {
            isRunning = false
            activeProcess = nil
            cancellationTask?.cancel()
            cancellationTask = nil
        }

        var setupFailures: [RestoreRawWriteFailure] = []
        var usableURLs = (stdout: stdoutURL, stderr: stderrURL)
        var sink: RestoreRawOutputSink?
        if let outputDirectory, let stdoutURL, let stderrURL {
            do {
                try Self.prepareRawDirectory(outputDirectory)
                try Self.requireSafeRawDestination(stdoutURL)
                try Self.requireSafeRawDestination(stderrURL)
                try Data().write(to: stdoutURL, options: .atomic)
                try Data().write(to: stderrURL, options: .atomic)
                sink = try rawSinkFactory(stdoutURL, stderrURL)
            } catch {
                setupFailures.append(Self.rawFailure(
                    stage: FileManager.default.fileExists(
                        atPath: outputDirectory.path)
                        ? .fileCreate
                        : .directoryCreate,
                    error: error))
                usableURLs = (nil, nil)
            }
        }
        let parser = RestoreOutputParser(
            targetECID: request.targetECID,
            timeProvider: timeProvider)
        guard launchPermitted() else {
            let sinkCompletion = sink?.finish()
            cancellationRequested = true
            cancelRequestedAt = timeProvider()
            sentSignals = []
            let confirmedAt = timeProvider()
            return CfgutilRestoreRunResult(
                outcome: .canceled,
                exitCode: nil,
                stdoutURL: usableURLs.stdout,
                stderrURL: usableURLs.stderr,
                stdoutSHA256: usableURLs.stdout.map(Self.sha256) ?? "",
                stderrSHA256: usableURLs.stderr.map(Self.sha256) ?? "",
                tailComplete: false,
                cancellationRequested: true,
                forcedKill: false,
                snapshot: parser.snapshot,
                lifecycle: RestoreLifecycleTimes(
                    userConfirmed: runEnteredAt,
                    outcomeConfirmed: confirmedAt),
                terminationReason: .unknown,
                sentSignals: [],
                rawEvidence: Self.makeRawEvidence(
                    requested: outputDirectory != nil,
                    stdoutURL: usableURLs.stdout,
                    stderrURL: usableURLs.stderr,
                    stdoutSHA256: usableURLs.stdout.map(Self.sha256) ?? "",
                    stderrSHA256: usableURLs.stderr.map(Self.sha256) ?? "",
                    sinkCompletion: sinkCompletion,
                    tailComplete: false,
                    setupFailures: setupFailures))
        }

        let rawSink = sink
        let process: any CfgutilProcessRunning
        do {
            process = try launcher.launch(request: request) { [weak self] channel, data in
                rawSink?.write(channel, data)
                let snapshot = parser.feed(data)
                Task { @MainActor [weak self] in
                    self?.onUpdate(snapshot, onUpdate)
                }
            }
        } catch {
            let sinkCompletion = sink?.finish()
            let confirmedAt = timeProvider()
            let stdoutSHA = usableURLs.stdout.map(Self.sha256) ?? ""
            let stderrSHA = usableURLs.stderr.map(Self.sha256) ?? ""
            return CfgutilRestoreRunResult(
                outcome: .failure,
                exitCode: nil,
                stdoutURL: usableURLs.stdout,
                stderrURL: usableURLs.stderr,
                stdoutSHA256: stdoutSHA,
                stderrSHA256: stderrSHA,
                tailComplete: false,
                cancellationRequested: cancellationRequested,
                forcedKill: false,
                snapshot: parser.flush(),
                lifecycle: RestoreLifecycleTimes(
                    userConfirmed: runEnteredAt,
                    outcomeConfirmed: confirmedAt),
                terminationReason: .unknown,
                sentSignals: sentSignals,
                rawEvidence: Self.makeRawEvidence(
                    requested: request.outputDirectory != nil,
                    stdoutURL: usableURLs.stdout,
                    stderrURL: usableURLs.stderr,
                    stdoutSHA256: stdoutSHA,
                    stderrSHA256: stderrSHA,
                    sinkCompletion: sinkCompletion,
                    tailComplete: false,
                    setupFailures: setupFailures))
        }
        activeProcess = process
        let processLaunched =
            process.processLaunched
            ?? timeProvider()
        var launchSnapshot = parser.snapshot
        launchSnapshot.processLaunched = processLaunched
        onUpdate?(launchSnapshot)

        let completion = await process.waitForCompletion(tailTimeout: 5)
        var snapshot = parser.flush()
        let sinkCompletion = rawSink?.finish()

        let tailComplete = completion.stdoutEOF && completion.stderrEOF
        let bothStreamsEOF = tailComplete
            ? (completion.bothStreamsEOF ?? timeProvider())
            : nil
        let outcome = parser.outcome(context: RestoreOutcomeContext(
            exitCode: completion.exitCode,
            userCancelled: cancellationRequested,
            processLaunched: true,
            cancelRequestedAt: cancelRequestedAt,
            tailComplete: tailComplete,
            terminationReason: completion.terminationReason,
            sentSignals: sentSignals))
        let outcomeConfirmed = timeProvider()
        snapshot.processLaunched = processLaunched
        snapshot.firstRestoreActivityTime =
            snapshot.firstRestoreActivityTime
            ?? parser.snapshot.firstRestoreActivityTime
        onUpdate?(snapshot)
        let lifecycle = RestoreLifecycleTimes(
            userConfirmed: runEnteredAt,
            processLaunched: processLaunched,
            firstRestoreActivity: snapshot.firstRestoreActivityTime,
            processExited: completion.processExited,
            bothStreamsEOF: bothStreamsEOF,
            outcomeConfirmed: outcomeConfirmed)
        let stdoutSHA = usableURLs.stdout.map(Self.sha256) ?? ""
        let stderrSHA = usableURLs.stderr.map(Self.sha256) ?? ""
        return CfgutilRestoreRunResult(
            outcome: outcome,
            exitCode: completion.exitCode,
            stdoutURL: usableURLs.stdout,
            stderrURL: usableURLs.stderr,
            stdoutSHA256: stdoutSHA,
            stderrSHA256: stderrSHA,
            tailComplete: tailComplete,
            cancellationRequested: cancellationRequested,
            forcedKill: completion.forcedKill,
            snapshot: snapshot,
            lifecycle: lifecycle,
            terminationReason: completion.terminationReason,
            sentSignals: sentSignals,
            rawEvidence: Self.makeRawEvidence(
                requested: request.outputDirectory != nil,
                stdoutURL: usableURLs.stdout,
                stderrURL: usableURLs.stderr,
                stdoutSHA256: stdoutSHA,
                stderrSHA256: stderrSHA,
                sinkCompletion: sinkCompletion,
                tailComplete: tailComplete,
                setupFailures: setupFailures))
    }

    func cancel() {
        guard let process = activeProcess, isRunning else { return }
        if cancelRequestedAt == nil {
            cancelRequestedAt = timeProvider()
        }
        cancellationRequested = true
        recordSignal(.interrupt)
        process.interrupt()
        cancellationTask = Task { @MainActor [weak self, weak process] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self, self.isRunning else { return }
            process?.terminate()
            self.recordSignal(.terminate)
            try? await Task.sleep(nanoseconds: 13_000_000_000)
            guard !Task.isCancelled, self.isRunning else { return }
            self.cancellationGraceExpired = true
        }
    }

    func forceKill() {
        guard cancellationRequested, let process = activeProcess, isRunning else { return }
        recordSignal(.kill)
        process.forceKill()
    }

    private func onUpdate(
        _ snapshot: RestoreOutputSnapshot,
        _ callback: (@MainActor (RestoreOutputSnapshot) -> Void)?
    ) {
        callback?(snapshot)
    }

    private func recordSignal(_ kind: RestoreSentSignalKind) {
        guard !sentSignals.contains(where: { $0.kind == kind }) else { return }
        sentSignals.append(RestoreSentSignal(
            kind: kind,
            time: timeProvider()))
    }

    private static func sha256(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
                hasher.update(data: data)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch {
            return ""
        }
    }

    private static func rawFailure(
        stage: RestoreRawWriteStage,
        error: Error
    ) -> RestoreRawWriteFailure {
        let nsError = error as NSError
        let code = nsError.userInfo[NSUnderlyingErrorKey]
            .flatMap { ($0 as? NSError)?.code }
            ?? nsError.code
        return RestoreRawWriteFailure(
            stage: stage,
            errno: Int32(code),
            message: error.localizedDescription)
    }

    private static func prepareRawDirectory(
        _ url: URL
    ) throws {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFDIR else {
                throw CfgutilRestoreEngineError
                    .outputDirectoryUnavailable(
                        "Restore Staging is not a directory")
            }
            return
        }
        guard errno == ENOENT else {
            throw POSIXError(
                POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true)
    }

    private static func requireSafeRawDestination(
        _ url: URL
    ) throws {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard (info.st_mode & S_IFMT) != S_IFLNK else {
                throw CfgutilRestoreEngineError
                    .outputDirectoryUnavailable(
                        "Raw destination is a symbolic link")
            }
        } else if errno != ENOENT {
            throw POSIXError(
                POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func makeRawEvidence(
        requested: Bool,
        stdoutURL: URL?,
        stderrURL: URL?,
        stdoutSHA256: String,
        stderrSHA256: String,
        sinkCompletion: RestoreRawSinkCompletion?,
        tailComplete: Bool,
        setupFailures: [RestoreRawWriteFailure]
    ) -> RestoreRawEvidenceResult {
        guard requested else { return .notSavedByChoice }
        var failures = setupFailures
        failures.append(contentsOf: sinkCompletion?.failures ?? [])
        if !tailComplete {
            failures.append(RestoreRawWriteFailure(
                stage: .streamTail,
                errno: nil,
                message: "stdout or stderr EOF was not observed"))
        }
        let expectedStdoutBytes =
            sinkCompletion?.stdoutBytes ?? 0
        let expectedStderrBytes =
            sinkCompletion?.stderrBytes ?? 0
        let stdoutVerified = rawFile(
            url: stdoutURL,
            expectedBytes: expectedStdoutBytes)
        let stderrVerified = rawFile(
            url: stderrURL,
            expectedBytes: expectedStderrBytes)
        if stdoutURL != nil, !stdoutVerified {
            failures.append(RestoreRawWriteFailure(
                stage: .fileVerification,
                errno: nil,
                message:
                    "stdout.raw size or file identity does not match the completed sink"))
        }
        if stderrURL != nil, !stderrVerified {
            failures.append(RestoreRawWriteFailure(
                stage: .fileVerification,
                errno: nil,
                message:
                    "stderr.raw size or file identity does not match the completed sink"))
        }
        if stdoutURL != nil,
           !Self.isSHA256(stdoutSHA256) {
            failures.append(RestoreRawWriteFailure(
                stage: .fileVerification,
                errno: nil,
                message: "stdout.raw SHA-256 is unavailable"))
        }
        if stderrURL != nil,
           !Self.isSHA256(stderrSHA256) {
            failures.append(RestoreRawWriteFailure(
                stage: .fileVerification,
                errno: nil,
                message: "stderr.raw SHA-256 is unavailable"))
        }
        let complete =
            setupFailures.isEmpty
            && (sinkCompletion?.writeComplete == true)
            && tailComplete
            && stdoutURL != nil
            && stderrURL != nil
            && stdoutVerified
            && stderrVerified
            && Self.isSHA256(stdoutSHA256)
            && Self.isSHA256(stderrSHA256)
        return RestoreRawEvidenceResult(
            status: complete ? .complete : .incompleteProtected,
            stdoutURL: stdoutURL,
            stderrURL: stderrURL,
            stdoutSHA256: stdoutSHA256,
            stderrSHA256: stderrSHA256,
            stdoutBytes: sinkCompletion?.stdoutBytes ?? 0,
            stderrBytes: sinkCompletion?.stderrBytes ?? 0,
            writeComplete: complete,
            tailPartialReason: complete
                ? nil
                : failures.first?.message ?? "RAW_EVIDENCE_INCOMPLETE",
            failures: failures)
    }

    private static func rawFile(
        url: URL?,
        expectedBytes: Int64
    ) -> Bool {
        guard let url,
              let identity = try? RestoreFileSystemInspector.identity(
                at: url,
                requireRegularFile: true) else {
            return false
        }
        return identity.sizeBytes == expectedBytes
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64
            && value.utf8.allSatisfy {
                ($0 >= 48 && $0 <= 57)
                    || ($0 >= 97 && $0 <= 102)
            }
    }
}

protocol RestoreRawFileWriting: AnyObject {
    func write(_ data: Data) throws
    func flush() throws
    func synchronize() throws
    func close() throws
}

final class RestoreRawFileHandleWriter: RestoreRawFileWriting {
    private let handle: FileHandle

    init(url: URL) throws {
        handle = try FileHandle(forWritingTo: url)
    }

    func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
    }

    func flush() throws {
        try handle.synchronize()
    }

    func synchronize() throws {
        try handle.synchronize()
    }

    func close() throws {
        try handle.close()
    }
}

final class RestoreRawOutputSink: @unchecked Sendable {
    private let lock = NSLock()
    private let stdoutWriter: any RestoreRawFileWriting
    private let stderrWriter: any RestoreRawFileWriting
    private var closed = false
    private var stdoutBytes: Int64 = 0
    private var stderrBytes: Int64 = 0
    private var failures: [RestoreRawWriteFailure] = []
    private var completed: RestoreRawSinkCompletion?

    init(stdoutURL: URL, stderrURL: URL) throws {
        stdoutWriter = try RestoreRawFileHandleWriter(url: stdoutURL)
        stderrWriter = try RestoreRawFileHandleWriter(url: stderrURL)
    }

    init(
        stdoutWriter: any RestoreRawFileWriting,
        stderrWriter: any RestoreRawFileWriting
    ) {
        self.stdoutWriter = stdoutWriter
        self.stderrWriter = stderrWriter
    }

    func write(_ channel: RestoreOutputChannel, _ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        switch channel {
        case .stdout:
            do {
                try stdoutWriter.write(data)
                stdoutBytes += Int64(data.count)
            } catch {
                recordFailure(.stdoutWrite, error: error)
            }
        case .stderr:
            do {
                try stderrWriter.write(data)
                stderrBytes += Int64(data.count)
            } catch {
                recordFailure(.stderrWrite, error: error)
            }
        }
    }

    func finish() -> RestoreRawSinkCompletion {
        lock.lock()
        defer { lock.unlock() }
        if let completed { return completed }
        guard !closed else {
            let completion = RestoreRawSinkCompletion(
                writeComplete: failures.isEmpty,
                stdoutBytes: stdoutBytes,
                stderrBytes: stderrBytes,
                failures: failures)
            completed = completion
            return completion
        }
        closed = true
        flush(.stdout)
        flush(.stderr)
        synchronize(.stdout)
        synchronize(.stderr)
        close(.stdout)
        close(.stderr)
        let completion = RestoreRawSinkCompletion(
            writeComplete: failures.isEmpty,
            stdoutBytes: stdoutBytes,
            stderrBytes: stderrBytes,
            failures: failures)
        completed = completion
        return completion
    }

    private func flush(_ channel: RestoreOutputChannel) {
        do {
            switch channel {
            case .stdout:
                try stdoutWriter.flush()
            case .stderr:
                try stderrWriter.flush()
            }
        } catch {
            recordFailure(
                channel == .stdout
                    ? .stdoutFlush
                    : .stderrFlush,
                error: error)
        }
    }

    func close() {
        _ = finish()
    }

    private func synchronize(_ channel: RestoreOutputChannel) {
        do {
            switch channel {
            case .stdout:
                try stdoutWriter.synchronize()
            case .stderr:
                try stderrWriter.synchronize()
            }
        } catch {
            recordFailure(
                channel == .stdout
                    ? .stdoutSynchronize
                    : .stderrSynchronize,
                error: error)
        }
    }

    private func close(_ channel: RestoreOutputChannel) {
        do {
            switch channel {
            case .stdout:
                try stdoutWriter.close()
            case .stderr:
                try stderrWriter.close()
            }
        } catch {
            recordFailure(
                channel == .stdout
                    ? .stdoutClose
                    : .stderrClose,
                error: error)
        }
    }

    private func recordFailure(
        _ stage: RestoreRawWriteStage,
        error: Error
    ) {
        let nsError = error as NSError
        let code = nsError.userInfo[NSUnderlyingErrorKey]
            .flatMap { ($0 as? NSError)?.code }
            ?? nsError.code
        failures.append(RestoreRawWriteFailure(
            stage: stage,
            errno: Int32(code),
            message: error.localizedDescription))
    }
}

@MainActor
final class LiveCfgutilProcessLauncher: CfgutilProcessLaunching {
    private let timeProvider: @Sendable () -> RestoreLifecycleTimePoint

    init(
        timeProvider: @escaping @Sendable () -> RestoreLifecycleTimePoint = {
            RestoreLifecycleClock.now()
        }
    ) {
        self.timeProvider = timeProvider
    }

    func launch(
        request: CfgutilRestoreRequest,
        onChunk: @escaping @Sendable (RestoreOutputChannel, Data) -> Void
    ) throws -> any CfgutilProcessRunning {
        try LiveCfgutilProcess(
            request: request,
            timeProvider: timeProvider,
            onChunk: onChunk)
    }
}

@MainActor
private final class LiveCfgutilProcess: CfgutilProcessRunning {
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let timeProvider: @Sendable () -> RestoreLifecycleTimePoint
    private let onChunk: @Sendable (RestoreOutputChannel, Data) -> Void
    private var stdoutEOF = false
    private var stderrEOF = false
    private var terminated = false
    private var exitCode: Int32 = -1
    private var forcedKill = false
    private var processExited: RestoreLifecycleTimePoint?
    private var bothStreamsEOF: RestoreLifecycleTimePoint?
    private var terminationReason: RestoreTerminationReason = .unknown
    private(set) var processLaunched: RestoreLifecycleTimePoint?
    private var tailTimeoutTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<CfgutilProcessCompletion, Never>?

    init(
        request: CfgutilRestoreRequest,
        timeProvider: @escaping @Sendable () -> RestoreLifecycleTimePoint,
        onChunk: @escaping @Sendable (RestoreOutputChannel, Data) -> Void
    ) throws {
        self.timeProvider = timeProvider
        self.onChunk = onChunk
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                Task { @MainActor [weak self] in self?.markEOF(.stdout) }
            } else {
                onChunk(.stdout, data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                Task { @MainActor [weak self] in self?.markEOF(.stderr) }
            } else {
                onChunk(.stderr, data)
            }
        }
        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                self?.markTerminated(process)
            }
        }

        do {
            try process.run()
            processLaunched = timeProvider()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw CfgutilRestoreEngineError.launchFailed(error.localizedDescription)
        }
    }

    func waitForCompletion(tailTimeout: TimeInterval) async -> CfgutilProcessCompletion {
        if terminated {
            startTailTimeoutIfNeeded(tailTimeout)
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            maybeFinish()
        }
    }

    func interrupt() {
        guard process.isRunning else { return }
        process.interrupt()
    }

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }

    func forceKill() {
        guard process.isRunning else { return }
        forcedKill = true
        kill(process.processIdentifier, SIGKILL)
    }

    private func markEOF(_ channel: RestoreOutputChannel) {
        if channel == .stdout {
            stdoutEOF = true
        } else {
            stderrEOF = true
        }
        if stdoutEOF, stderrEOF, bothStreamsEOF == nil {
            bothStreamsEOF = timeProvider()
        }
        maybeFinish()
    }

    private func markTerminated(_ process: Process) {
        exitCode = process.terminationStatus
        terminationReason = process.terminationReason == .uncaughtSignal
            ? .uncaughtSignal
            : .exit
        processExited = timeProvider()
        terminated = true
        startTailTimeoutIfNeeded(5)
        maybeFinish()
    }

    private func startTailTimeoutIfNeeded(_ seconds: TimeInterval) {
        guard tailTimeoutTask == nil else { return }
        tailTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.stdoutPipe.fileHandleForReading.readabilityHandler = nil
            self.stderrPipe.fileHandleForReading.readabilityHandler = nil
            try? self.stdoutPipe.fileHandleForReading.close()
            try? self.stderrPipe.fileHandleForReading.close()
            self.finish()
        }
    }

    private func maybeFinish() {
        guard terminated, stdoutEOF, stderrEOF else { return }
        finish()
    }

    private func finish() {
        guard let continuation else { return }
        self.continuation = nil
        tailTimeoutTask?.cancel()
        tailTimeoutTask = nil
        continuation.resume(returning: CfgutilProcessCompletion(
            exitCode: exitCode,
            stdoutEOF: stdoutEOF,
            stderrEOF: stderrEOF,
            forcedKill: forcedKill,
            processExited: processExited,
            bothStreamsEOF: bothStreamsEOF,
            terminationReason: terminationReason))
    }
}

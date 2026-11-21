import Foundation
import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class Batch4RawPersistenceTests: XCTestCase {
    private let ecid: UInt64 = 0x12345670

    func testDisabledRawSinkCreatesNothingAndPreservesSuccessfulOutcome() async throws {
        let root = try temporaryDirectory()
        let process = Batch4MockProcess(
            chunks: successChunks(),
            completion: CfgutilProcessCompletion(
                exitCode: 0,
                stdoutEOF: true,
                stderrEOF: true,
                forcedKill: false))
        let engine = CfgutilRestoreEngine(
            launcher: Batch4MockLauncher(process: process))

        let result = await engine.run(request: CfgutilRestoreRequest(
            taskID: UUID(),
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            ipswURL: URL(fileURLWithPath: "/tmp/Batch4.ipsw"),
            targetECID: ecid,
            outputDirectory: nil))

        XCTAssertEqual(result.outcome, .success)
        XCTAssertTrue(result.tailComplete)
        XCTAssertEqual(result.rawEvidence.status, .notSavedByChoice)
        XCTAssertTrue(result.rawEvidence.writeComplete == false)
        XCTAssertNil(result.rawEvidence.stdoutURL)
        XCTAssertNil(result.rawEvidence.stderrURL)
        XCTAssertEqual(try visibleInventory(root), [])
    }

    func testDisabledRawSinkPreservesFailureUnknownAndCanceledOutcomes() async throws {
        let failureRoot = try temporaryDirectory()
        let failure = Batch4MockProcess(
            chunks: [(.stderr, Data("cfgutil: error: fixture\n".utf8))],
            completion: CfgutilProcessCompletion(
                exitCode: 1,
                stdoutEOF: true,
                stderrEOF: true,
                forcedKill: false))
        let failureResult = await CfgutilRestoreEngine(
            launcher: Batch4MockLauncher(process: failure))
            .run(request: CfgutilRestoreRequest(
                taskID: UUID(),
                executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                ipswURL: URL(fileURLWithPath: "/tmp/Batch4.ipsw"),
                targetECID: ecid,
                outputDirectory: nil))
        XCTAssertEqual(failureResult.outcome, .failure)
        XCTAssertEqual(
            failureResult.rawEvidence.status,
            .notSavedByChoice)
        XCTAssertEqual(try visibleInventory(failureRoot), [])

        let unknownRoot = try temporaryDirectory()
        let unknown = Batch4MockProcess(
            chunks: [],
            completion: CfgutilProcessCompletion(
                exitCode: 0,
                stdoutEOF: true,
                stderrEOF: true,
                forcedKill: false))
        let unknownResult = await CfgutilRestoreEngine(
            launcher: Batch4MockLauncher(process: unknown))
            .run(request: CfgutilRestoreRequest(
                taskID: UUID(),
                executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                ipswURL: URL(fileURLWithPath: "/tmp/Batch4.ipsw"),
                targetECID: ecid,
                outputDirectory: nil))
        XCTAssertEqual(unknownResult.outcome, .unknown)
        XCTAssertEqual(
            unknownResult.rawEvidence.status,
            .notSavedByChoice)
        XCTAssertEqual(try visibleInventory(unknownRoot), [])

        let canceledRoot = try temporaryDirectory()
        let canceled = Batch4MockProcess(
            chunks: [],
            completion: CfgutilProcessCompletion(
                exitCode: 130,
                stdoutEOF: true,
                stderrEOF: true,
                forcedKill: false),
            exitOnInterrupt: true)
        let engine = CfgutilRestoreEngine(
            launcher: Batch4MockLauncher(process: canceled))
        let task = Task { @MainActor in
            await engine.run(request: CfgutilRestoreRequest(
                taskID: UUID(),
                executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                ipswURL: URL(fileURLWithPath: "/tmp/Batch4.ipsw"),
                targetECID: ecid,
                outputDirectory: nil))
        }
        for _ in 0..<100 where !engine.isRunning {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        engine.cancel()
        let canceledResult = await task.value
        XCTAssertEqual(canceledResult.outcome, .canceled)
        XCTAssertEqual(
            canceledResult.rawEvidence.status,
            .notSavedByChoice)
        XCTAssertEqual(try visibleInventory(canceledRoot), [])
    }

    func testRawDirectoryFailureDoesNotRewriteSuccessfulRestore() async throws {
        let root = try temporaryDirectory()
        let blocker = root.appendingPathComponent("not-a-directory")
        try Data("fixture".utf8).write(to: blocker)
        let process = Batch4MockProcess(
            chunks: successChunks(),
            completion: CfgutilProcessCompletion(
                exitCode: 0,
                stdoutEOF: true,
                stderrEOF: true,
                forcedKill: false))
        let engine = CfgutilRestoreEngine(
            launcher: Batch4MockLauncher(process: process))

        let result = await engine.run(request: CfgutilRestoreRequest(
            taskID: UUID(),
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            ipswURL: URL(fileURLWithPath: "/tmp/Batch4.ipsw"),
            targetECID: ecid,
            outputDirectory: blocker))

        XCTAssertEqual(result.outcome, .success)
        XCTAssertTrue(result.tailComplete)
        XCTAssertEqual(result.rawEvidence.status, .incompleteProtected)
        XCTAssertFalse(result.rawEvidence.writeComplete)
        XCTAssertFalse(result.rawEvidence.tailPartialReason?.isEmpty ?? true)
    }

    func testSymbolicRawDestinationIsRejectedWithoutRewritingRestore() async throws {
        let root = try temporaryDirectory()
        let outside = root.appendingPathComponent("outside.txt")
        try Data("untouched".utf8).write(to: outside)
        let stdoutLink =
            root.appendingPathComponent("stdout.raw")
        try FileManager.default.createSymbolicLink(
            at: stdoutLink,
            withDestinationURL: outside)
        let process = Batch4MockProcess(
            chunks: successChunks(),
            completion: CfgutilProcessCompletion(
                exitCode: 0,
                stdoutEOF: true,
                stderrEOF: true,
                forcedKill: false))
        let result = await CfgutilRestoreEngine(
            launcher: Batch4MockLauncher(process: process))
            .run(request: CfgutilRestoreRequest(
                taskID: UUID(),
                executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                ipswURL: URL(fileURLWithPath: "/tmp/Batch4.ipsw"),
                targetECID: ecid,
                outputDirectory: root))

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(
            result.rawEvidence.status,
            .incompleteProtected)
        XCTAssertEqual(
            try String(contentsOf: outside, encoding: .utf8),
            "untouched")
    }

    func testStdoutWriteFailureLeavesRestoreSuccessButEvidenceIncomplete() async throws {
        let output = try temporaryDirectory()
        let process = Batch4MockProcess(
            chunks: successChunks(),
            completion: CfgutilProcessCompletion(
                exitCode: 0,
                stdoutEOF: true,
                stderrEOF: true,
                forcedKill: false))
        let engine = CfgutilRestoreEngine(
            launcher: Batch4MockLauncher(process: process),
            rawSinkFactory: { _, _ in
                RestoreRawOutputSink(
                    stdoutWriter: Batch4FailingWriter(
                        failure: .write(errno: ENOSPC)),
                    stderrWriter: Batch4MemoryWriter())
            })

        let result = await engine.run(request: CfgutilRestoreRequest(
            taskID: UUID(),
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            ipswURL: URL(fileURLWithPath: "/tmp/Batch4.ipsw"),
            targetECID: ecid,
            outputDirectory: output))

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.rawEvidence.status, .incompleteProtected)
        XCTAssertFalse(result.rawEvidence.writeComplete)
        XCTAssertTrue(
            result.rawEvidence.failures.contains {
                $0.stage == .stdoutWrite && $0.errno == ENOSPC
            })
    }

    func testSyncAndCloseFailuresAreReportedIndependently() {
        let stdout = Batch4FailingWriter(
            failure: .synchronize(errno: EIO))
        let stderr = Batch4FailingWriter(
            failure: .close(errno: EIO))
        let sink = RestoreRawOutputSink(
            stdoutWriter: stdout,
            stderrWriter: stderr)

        sink.write(.stdout, Data("out\n".utf8))
        sink.write(.stderr, Data("err\n".utf8))
        let completion = sink.finish()

        XCTAssertFalse(completion.writeComplete)
        XCTAssertTrue(
            completion.failures.contains {
                $0.stage == .stdoutSynchronize
            })
        XCTAssertTrue(
            completion.failures.contains {
                $0.stage == .stderrClose
            })
    }

    func testFlushAndStderrWriteFailuresAreReportedIndependently() {
        let stdout = Batch4FailingWriter(
            failure: .flush(errno: EIO))
        let stderr = Batch4FailingWriter(
            failure: .write(errno: ENOSPC))
        let sink = RestoreRawOutputSink(
            stdoutWriter: stdout,
            stderrWriter: stderr)

        sink.write(.stdout, Data("out\n".utf8))
        sink.write(.stderr, Data("err\n".utf8))
        let completion = sink.finish()

        XCTAssertFalse(completion.writeComplete)
        XCTAssertTrue(
            completion.failures.contains {
                $0.stage == .stdoutFlush
            })
        XCTAssertTrue(
            completion.failures.contains {
                $0.stage == .stderrWrite
                    && $0.errno == ENOSPC
            })
    }

    func testReportedWriteCountsMustMatchFilesOnDisk() async throws {
        let output = try temporaryDirectory()
        let process = Batch4MockProcess(
            chunks: successChunks(),
            completion: CfgutilProcessCompletion(
                exitCode: 0,
                stdoutEOF: true,
                stderrEOF: true,
                forcedKill: false))
        let engine = CfgutilRestoreEngine(
            launcher: Batch4MockLauncher(process: process),
            rawSinkFactory: { _, _ in
                RestoreRawOutputSink(
                    stdoutWriter: Batch4MemoryWriter(),
                    stderrWriter: Batch4MemoryWriter())
            })

        let result = await engine.run(request: CfgutilRestoreRequest(
            taskID: UUID(),
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            ipswURL: URL(fileURLWithPath: "/tmp/Batch4.ipsw"),
            targetECID: ecid,
            outputDirectory: output))

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(
            result.rawEvidence.status,
            .incompleteProtected)
        XCTAssertFalse(result.rawEvidence.writeComplete)
        XCTAssertTrue(
            result.rawEvidence.failures.contains {
                $0.stage == .fileVerification
            })
    }

    private func successChunks() -> [(RestoreOutputChannel, Data)] {
        [
            (.stdout, Data("Restored System on Unknown device (ECID: \(ecid)).\n".utf8)),
            (.stdout, Data(#"Operation "restore" succeeded on 1 devices."#.utf8)),
            (.stderr, Data("diagnostic stderr\n".utf8))
        ]
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Batch4Raw-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func visibleInventory(_ root: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [])
            .map(\.lastPathComponent)
            .sorted()
    }
}

@MainActor
private final class Batch4MockLauncher: CfgutilProcessLaunching {
    private let process: Batch4MockProcess

    init(process: Batch4MockProcess) {
        self.process = process
    }

    func launch(
        request: CfgutilRestoreRequest,
        onChunk: @escaping @Sendable (RestoreOutputChannel, Data) -> Void
    ) throws -> any CfgutilProcessRunning {
        process.onChunk = onChunk
        return process
    }
}

@MainActor
private final class Batch4MockProcess: CfgutilProcessRunning {
    private let chunks: [(RestoreOutputChannel, Data)]
    private let completion: CfgutilProcessCompletion
    private let exitOnInterrupt: Bool
    var onChunk: (@Sendable (RestoreOutputChannel, Data) -> Void)?
    private var continuation:
        CheckedContinuation<CfgutilProcessCompletion, Never>?

    init(
        chunks: [(RestoreOutputChannel, Data)],
        completion: CfgutilProcessCompletion,
        exitOnInterrupt: Bool = false
    ) {
        self.chunks = chunks
        self.completion = completion
        self.exitOnInterrupt = exitOnInterrupt
    }

    func waitForCompletion(
        tailTimeout: TimeInterval
    ) async -> CfgutilProcessCompletion {
        for chunk in chunks {
            onChunk?(chunk.0, chunk.1)
        }
        if exitOnInterrupt {
            return await withCheckedContinuation {
                continuation = $0
            }
        }
        return completion
    }

    func interrupt() {
        if exitOnInterrupt {
            continuation?.resume(returning: completion)
            continuation = nil
        }
    }
    func terminate() {}
    func forceKill() {}
}

private enum Batch4Fault: Error, Equatable {
    case write(errno: Int32)
    case flush(errno: Int32)
    case synchronize(errno: Int32)
    case close(errno: Int32)
}

private final class Batch4FailingWriter: RestoreRawFileWriting {
    private let failure: Batch4Fault

    init(failure: Batch4Fault) {
        self.failure = failure
    }

    func write(_ data: Data) throws {
        if case .write(let code) = failure {
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    func flush() throws {
        if case .flush(let code) = failure {
            throw POSIXError(
                POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    func synchronize() throws {
        if case .synchronize(let code) = failure {
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    func close() throws {
        if case .close(let code) = failure {
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }
}

private final class Batch4MemoryWriter: RestoreRawFileWriting {
    func write(_ data: Data) throws {}
    func flush() throws {}
    func synchronize() throws {}
    func close() throws {}
}

import Foundation
import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class CfgutilRestoreEngineTests: XCTestCase {
    private let ecid: UInt64 = 0x12345670

    func testCommandUsesOneDecimalECIDTargetAndExactRestoreArguments() {
        let request = CfgutilRestoreRequest(
            taskID: UUID(),
            executableURL: URL(fileURLWithPath: "/usr/local/bin/cfgutil"),
            ipswURL: URL(fileURLWithPath: "/tmp/Test.ipsw"),
            targetECID: ecid,
            outputDirectory: FileManager.default.temporaryDirectory)

        XCTAssertEqual(
            request.arguments,
            ["--progress", "-v", "-e", "305419888",
             "restore", "-I", "/tmp/Test.ipsw"])
        XCTAssertFalse(request.arguments.contains("--foreach"))
    }

    func testRunWritesIndependentRawStreamsAndRequiresThreePartTailFence() async throws {
        let output = try makeOutputDirectory()
        let process = MockCfgutilProcess(
            chunks: [
                (.stdout, Data("Step = \"RestoreOS\"; Type = Step;\n".utf8)),
                (.stdout, Data("Restored System on Unknown device (ECID: \(ecid)).\n".utf8)),
                (.stdout, Data(#"Operation "restore" succeeded on 1 devices."#.utf8)),
                (.stderr, Data("diagnostic stderr\n".utf8))
            ],
            completion: CfgutilProcessCompletion(
                exitCode: 0,
                stdoutEOF: true,
                stderrEOF: true,
                forcedKill: false))
        let launcher = MockCfgutilProcessLauncher(process: process)
        let engine = CfgutilRestoreEngine(launcher: launcher)
        let request = CfgutilRestoreRequest(
            taskID: UUID(),
            executableURL: URL(fileURLWithPath: "/usr/local/bin/cfgutil"),
            ipswURL: URL(fileURLWithPath: "/tmp/Test.ipsw"),
            targetECID: ecid,
            outputDirectory: output)

        let result = await engine.run(request: request)

        XCTAssertEqual(result.outcome, .success)
        XCTAssertTrue(result.tailComplete)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertNotEqual(result.stdoutURL, result.stderrURL)
        XCTAssertTrue(try String(
            contentsOf: XCTUnwrap(result.stdoutURL),
            encoding: .utf8)
            .contains("Restored System on"))
        XCTAssertEqual(
            try String(
                contentsOf: XCTUnwrap(result.stderrURL),
                encoding: .utf8),
            "diagnostic stderr\n")
        XCTAssertEqual(result.stdoutSHA256.count, 64)
        XCTAssertEqual(result.stderrSHA256.count, 64)
    }

    func testExitZeroWithoutTerminalSummaryRemainsUnknown() async throws {
        let process = MockCfgutilProcess(
            chunks: [
                (.stdout, Data("Restored System on Unknown device (ECID: \(ecid)).\n".utf8))
            ],
            completion: CfgutilProcessCompletion(
                exitCode: 0,
                stdoutEOF: true,
                stderrEOF: true,
                forcedKill: false))
        let engine = CfgutilRestoreEngine(
            launcher: MockCfgutilProcessLauncher(process: process))
        let result = await engine.run(
            request: CfgutilRestoreRequest(
                taskID: UUID(),
                executableURL: URL(fileURLWithPath: "/usr/local/bin/cfgutil"),
                ipswURL: URL(fileURLWithPath: "/tmp/Test.ipsw"),
                targetECID: ecid,
                outputDirectory: try makeOutputDirectory()))

        XCTAssertEqual(result.outcome, .unknown)
        XCTAssertTrue(result.tailComplete)
    }

    func testNonzeroExitIsFailureAndIncompleteTailCannotBecomeSuccess() async throws {
        let failure = MockCfgutilProcess(
            chunks: [(.stderr, Data("cfgutil: error: test failure\n".utf8))],
            completion: CfgutilProcessCompletion(
                exitCode: 1,
                stdoutEOF: true,
                stderrEOF: true,
                forcedKill: false))
        let failureResult = await CfgutilRestoreEngine(
            launcher: MockCfgutilProcessLauncher(process: failure))
            .run(request: CfgutilRestoreRequest(
                taskID: UUID(),
                executableURL: URL(fileURLWithPath: "/usr/local/bin/cfgutil"),
                ipswURL: URL(fileURLWithPath: "/tmp/Test.ipsw"),
                targetECID: ecid,
                outputDirectory: try makeOutputDirectory()))
        XCTAssertEqual(failureResult.outcome, .failure)

        let incomplete = MockCfgutilProcess(
            chunks: [
                (.stdout, Data("Restored System on Unknown device (ECID: \(ecid)).\n".utf8)),
                (.stdout, Data(#"Operation "restore" succeeded on 1 devices."#.utf8))
            ],
            completion: CfgutilProcessCompletion(
                exitCode: 0,
                stdoutEOF: true,
                stderrEOF: false,
                forcedKill: false))
        let incompleteResult = await CfgutilRestoreEngine(
            launcher: MockCfgutilProcessLauncher(process: incomplete))
            .run(request: CfgutilRestoreRequest(
                taskID: UUID(),
                executableURL: URL(fileURLWithPath: "/usr/local/bin/cfgutil"),
                ipswURL: URL(fileURLWithPath: "/tmp/Test.ipsw"),
                targetECID: ecid,
                outputDirectory: try makeOutputDirectory()))
        XCTAssertFalse(incompleteResult.tailComplete)
        XCTAssertEqual(incompleteResult.outcome, .unknown)
    }

    func testConfirmedCancellationUsesInterruptAndClassifiesCanceled() async throws {
        let output = try makeOutputDirectory()
        let process = MockCfgutilProcess(
            chunks: [(.stdout, Data("Waiting for device\n".utf8))],
            completion: CfgutilProcessCompletion(
                exitCode: 130,
                stdoutEOF: true,
                stderrEOF: true,
                forcedKill: false),
            exitOnInterrupt: true)
        let engine = CfgutilRestoreEngine(
            launcher: MockCfgutilProcessLauncher(process: process))
        let runTask = Task { @MainActor in
            await engine.run(
                request: CfgutilRestoreRequest(
                    taskID: UUID(),
                    executableURL: URL(fileURLWithPath: "/usr/local/bin/cfgutil"),
                    ipswURL: URL(fileURLWithPath: "/tmp/Test.ipsw"),
                    targetECID: ecid,
                    outputDirectory: output))
        }

        for _ in 0..<50 where !engine.isRunning {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(engine.isRunning)
        engine.cancel()
        let result = await runTask.value

        XCTAssertGreaterThanOrEqual(process.interruptCount, 1)
        XCTAssertEqual(result.outcome, .canceled)
        XCTAssertTrue(result.cancellationRequested)
    }


    func testIgnoringSIGINTAndSIGTERMIsForceKilledAndClassifiedCanceled() async throws {
        let dir = try makeOutputDirectory()
        let script = dir.appendingPathComponent("ignore-signals.sh")
        try """
        #!/bin/sh
        trap '' INT TERM
        while :; do :; done
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)
        let engine = CfgutilRestoreEngine()
        let run = Task { @MainActor in
            await engine.run(request: CfgutilRestoreRequest(
                taskID: UUID(),
                executableURL: script,
                ipswURL: URL(fileURLWithPath: "/tmp/Test.ipsw"),
                targetECID: self.ecid,
                outputDirectory: dir))
        }
        for _ in 0..<100 where !engine.isRunning {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(engine.isRunning)
        try await Task.sleep(nanoseconds: 500_000_000)
        engine.cancel()
        try await Task.sleep(nanoseconds: 3_200_000_000)
        XCTAssertTrue(engine.isRunning, "ignored signals must keep process alive")
        engine.forceKill()
        let result = await run.value
        XCTAssertEqual(result.outcome, .canceled)
        XCTAssertTrue(result.forcedKill)
        XCTAssertTrue(result.sentSignals.contains { $0.kind == .kill })
        XCTAssertFalse(engine.isRunning)
    }

    private func makeOutputDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CfgutilRestoreEngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
private final class MockCfgutilProcessLauncher: CfgutilProcessLaunching {
    private let process: MockCfgutilProcess

    init(process: MockCfgutilProcess) {
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
private final class MockCfgutilProcess: CfgutilProcessRunning {
    let chunks: [(RestoreOutputChannel, Data)]
    let completion: CfgutilProcessCompletion
    let exitOnInterrupt: Bool
    var onChunk: (@Sendable (RestoreOutputChannel, Data) -> Void)?
    private var continuation: CheckedContinuation<CfgutilProcessCompletion, Never>?
    private(set) var interruptCount = 0
    private(set) var terminateCount = 0
    private(set) var forceKillCount = 0

    init(
        chunks: [(RestoreOutputChannel, Data)],
        completion: CfgutilProcessCompletion,
        exitOnInterrupt: Bool = false
    ) {
        self.chunks = chunks
        self.completion = completion
        self.exitOnInterrupt = exitOnInterrupt
    }

    func waitForCompletion(tailTimeout: TimeInterval) async -> CfgutilProcessCompletion {
        for chunk in chunks {
            onChunk?(chunk.0, chunk.1)
        }
        if Task.isCancelled {
            return completion
        }
        if exitOnInterrupt {
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        return completion
    }

    func interrupt() {
        interruptCount += 1
        if exitOnInterrupt {
            continuation?.resume(returning: completion)
            continuation = nil
        }
    }

    func terminate() {
        terminateCount += 1
    }

    func forceKill() {
        forceKillCount += 1
    }
}

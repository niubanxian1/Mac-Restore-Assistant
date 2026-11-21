import Foundation
import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class Batch3TimingOutcomeTests: XCTestCase {
    private let ecid: UInt64 = 0x0011223344556677
    private let wallOrigin = Date(timeIntervalSince1970: 1_800_000_000)

    func testLifecycleDurationUsesMonotonicTimeAcrossWallClockJumps() {
        let times = RestoreLifecycleTimes(
            userConfirmed: point(ns: 1_000_000_000, wallDelta: 3_600),
            processLaunched: point(ns: 2_000_000_000, wallDelta: -3_600),
            firstRestoreActivity: point(ns: 3_000_000_000, wallDelta: 7_200),
            processExited: point(ns: 12_000_000_000, wallDelta: -7_200),
            bothStreamsEOF: point(ns: 13_000_000_000, wallDelta: -9_000),
            outcomeConfirmed: point(ns: 14_000_000_000, wallDelta: 9_000),
            rlmFinalized: nil)

        XCTAssertEqual(times.processWallDurationSeconds ?? -1, 10, accuracy: 0.000_001)
        XCTAssertNil(RestoreLifecycleTimes(userConfirmed: point(ns: 10)).processWallDurationSeconds)
    }

    func testFirstRestoreActivityRecordsOnlyFirstParserEvent() {
        let clock = Batch3SequenceClock([
            point(ns: 2_000),
            point(ns: 3_000),
            point(ns: 4_000)
        ])
        let parser = RestoreOutputParser(
            targetECID: ecid,
            timeProvider: { clock.now() })

        _ = parser.feed(Data(#"Step = "RestoreOS"; Type = Step;"#.utf8))
        _ = parser.feed(Data(#"Step = "RestoreOS"; Progress = "0.4"; Type = Progress;"#.utf8))

        XCTAssertEqual(
            parser.snapshot.firstRestoreActivityTime?.monotonicNanoseconds,
            2_000)
    }

    func testCancelBeforeInterruptionIsCanceledWhileKeepingDiagnosticText() {
        let clock = Batch3SequenceClock([point(ns: 1_000)])
        let parser = RestoreOutputParser(
            targetECID: ecid,
            timeProvider: { clock.now() })
        _ = parser.feed(Data(
            "cfgutil: error: RestoreOS device removed before restored completed (Domain: com.apple.MobileDevice.MobileRestore Code: 9)\n"
                .utf8))

        let outcome = parser.outcome(context: RestoreOutcomeContext(
            exitCode: 130,
            userCancelled: true,
            processLaunched: true,
            cancelRequestedAt: point(ns: 900),
            tailComplete: true,
            terminationReason: .uncaughtSignal,
            sentSignals: [
                RestoreSentSignal(kind: .interrupt, time: point(ns: 900))
            ]))

        XCTAssertEqual(outcome, .canceled)
        XCTAssertTrue(parser.snapshot.failureText.contains("Code: 9"))
        XCTAssertTrue(parser.snapshot.sawCancellationInterruptionFailure)
        XCTAssertFalse(parser.snapshot.sawIndependentFailure)
    }

    func testFailureBeforeCancelRemainsFailure() {
        let clock = Batch3SequenceClock([point(ns: 1_000)])
        let parser = RestoreOutputParser(
            targetECID: ecid,
            timeProvider: { clock.now() })
        _ = parser.feed(Data(
            #""restore" failed on Unknown device (ECID: \#(ecid))."#.utf8))

        let outcome = parser.outcome(context: RestoreOutcomeContext(
            exitCode: 1,
            userCancelled: true,
            processLaunched: true,
            cancelRequestedAt: point(ns: 2_000),
            tailComplete: true,
            terminationReason: .exit,
            sentSignals: []))

        XCTAssertEqual(outcome, .failure)
        XCTAssertTrue(parser.snapshot.sawIndependentFailure)
    }

    func testIndependentFailureAfterCancelRemainsFailure() {
        let clock = Batch3SequenceClock([point(ns: 2_000)])
        let parser = RestoreOutputParser(
            targetECID: ecid,
            timeProvider: { clock.now() })
        _ = parser.feed(Data(
            "AMRestoreErrorDomain: failed to restore firmware\n".utf8))

        let outcome = parser.outcome(context: RestoreOutcomeContext(
            exitCode: 1,
            userCancelled: true,
            processLaunched: true,
            cancelRequestedAt: point(ns: 1_000),
            tailComplete: true,
            terminationReason: .exit,
            sentSignals: []))

        XCTAssertEqual(outcome, .failure)
    }

    func testExplicitSuccessWinsEvenWhenCancelWasRequestedEarlier() {
        let parser = RestoreOutputParser(targetECID: ecid)
        _ = parser.feed(Data(
            "Restored System on Unknown device (ECID: \(ecid)).\n".utf8))
        _ = parser.feed(Data(
            #"Operation "restore" succeeded on 1 devices."#.utf8))

        let outcome = parser.outcome(context: RestoreOutcomeContext(
            exitCode: 0,
            userCancelled: true,
            processLaunched: true,
            cancelRequestedAt: point(ns: 1_000),
            tailComplete: true,
            terminationReason: .exit,
            sentSignals: []))

        XCTAssertEqual(outcome, .success)
    }

    func testMissingEOFOrContradictoryEvidenceRemainsUnknown() {
        let parser = RestoreOutputParser(targetECID: ecid)
        _ = parser.feed(Data("Waiting for device\n".utf8))

        XCTAssertEqual(parser.outcome(context: RestoreOutcomeContext(
            exitCode: 1,
            userCancelled: false,
            processLaunched: true,
            cancelRequestedAt: nil,
            tailComplete: false,
            terminationReason: .unknown,
            sentSignals: [])), .unknown)
    }

    func testPrelaunchCancelCannotProduceProcessLaunchedTimestamp() async throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("Batch3Prelaunch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let launcher = Batch3CountingLauncher()
        let outcomeTime = point(ns: 5_000_000_000)
        let engine = CfgutilRestoreEngine(
            launcher: launcher,
            timeProvider: { outcomeTime })

        let result = await engine.run(
            request: CfgutilRestoreRequest(
                taskID: UUID(),
                executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                ipswURL: URL(fileURLWithPath: "/tmp/Test.ipsw"),
                targetECID: ecid,
                outputDirectory: output),
            launchPermitted: { false },
            onUpdate: nil)

        XCTAssertEqual(result.outcome, .canceled)
        XCTAssertNil(result.lifecycle.processLaunched)
        XCTAssertEqual(launcher.launchCount, 0)
    }

    func testFinalPermissionIsCheckedImmediatelyBeforeLaunch() async throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Batch3FinalPermission-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: output,
            withIntermediateDirectories: true)
        let launcher = Batch3CountingLauncher()
        let outcomeTime = point(ns: 6_000_000_000)
        let engine = CfgutilRestoreEngine(
            launcher: launcher,
            timeProvider: { outcomeTime })
        var permissionChecks = 0

        let result = await engine.run(
            request: CfgutilRestoreRequest(
                taskID: UUID(),
                executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                ipswURL: URL(fileURLWithPath: "/tmp/Test.ipsw"),
                targetECID: ecid,
                outputDirectory: output),
            launchPermitted: {
                permissionChecks += 1
                return permissionChecks == 1
            },
            onUpdate: nil)

        XCTAssertEqual(permissionChecks, 2)
        XCTAssertEqual(result.outcome, .canceled)
        XCTAssertNil(result.lifecycle.processLaunched)
        XCTAssertEqual(launcher.launchCount, 0)
    }

    func testEngineRecordsLaunchExitEOFAndOutcomeFromStableEvents() async throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("Batch3Timing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let process = Batch3TimedProcess(
            launch: point(ns: 10_000_000_000, wallDelta: -3_600),
            completion: CfgutilProcessCompletion(
                exitCode: 0,
                stdoutEOF: true,
                stderrEOF: true,
                forcedKill: false,
                processExited: point(ns: 20_000_000_000, wallDelta: 3_600),
                bothStreamsEOF: point(ns: 21_000_000_000, wallDelta: -3_600),
                terminationReason: .exit),
            chunks: [
                (.stdout, Data("Restored System on Unknown device (ECID: \(ecid)).\n".utf8)),
                (.stdout, Data(#"Operation "restore" succeeded on 1 devices."#.utf8))
            ])
        let outcomeTime = point(ns: 25_000_000_000, wallDelta: 9_000)
        let engine = CfgutilRestoreEngine(
            launcher: Batch3TimedLauncher(process: process),
            timeProvider: { outcomeTime })

        let result = await engine.run(
            request: CfgutilRestoreRequest(
                taskID: UUID(),
                executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                ipswURL: URL(fileURLWithPath: "/tmp/Test.ipsw"),
                targetECID: ecid,
                outputDirectory: output))

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(
            result.lifecycle.processLaunched?.monotonicNanoseconds,
            10_000_000_000)
        XCTAssertEqual(
            result.lifecycle.processExited?.monotonicNanoseconds,
            20_000_000_000)
        XCTAssertEqual(
            result.lifecycle.bothStreamsEOF?.monotonicNanoseconds,
            21_000_000_000)
        XCTAssertEqual(
            result.lifecycle.outcomeConfirmed?.monotonicNanoseconds,
            25_000_000_000)
        XCTAssertEqual(result.lifecycle.processWallDurationSeconds ?? -1, 10, accuracy: 0.000_001)
    }

    private func point(
        ns: UInt64,
        wallDelta: TimeInterval = 0
    ) -> RestoreLifecycleTimePoint {
        RestoreLifecycleTimePoint(
            wallTime: wallOrigin.addingTimeInterval(wallDelta),
            monotonicNanoseconds: ns)
    }
}

private final class Batch3SequenceClock: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [RestoreLifecycleTimePoint]

    init(_ values: [RestoreLifecycleTimePoint]) {
        self.values = values
    }

    func now() -> RestoreLifecycleTimePoint {
        lock.lock()
        defer { lock.unlock() }
        guard !values.isEmpty else {
            return RestoreLifecycleTimePoint(wallTime: Date(), monotonicNanoseconds: 0)
        }
        return values.removeFirst()
    }
}

@MainActor
private final class Batch3CountingLauncher: CfgutilProcessLaunching {
    private(set) var launchCount = 0

    func launch(
        request: CfgutilRestoreRequest,
        onChunk: @escaping @Sendable (RestoreOutputChannel, Data) -> Void
    ) throws -> any CfgutilProcessRunning {
        launchCount += 1
        return Batch3TimedProcess(
            launch: nil,
            completion: CfgutilProcessCompletion(
                exitCode: 0,
                stdoutEOF: true,
                stderrEOF: true,
                forcedKill: false),
            chunks: [])
    }
}

@MainActor
private final class Batch3TimedLauncher: CfgutilProcessLaunching {
    let process: Batch3TimedProcess

    init(process: Batch3TimedProcess) {
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
private final class Batch3TimedProcess: CfgutilProcessRunning {
    let processLaunched: RestoreLifecycleTimePoint?
    let completion: CfgutilProcessCompletion
    let chunks: [(RestoreOutputChannel, Data)]
    var onChunk: (@Sendable (RestoreOutputChannel, Data) -> Void)?

    init(
        launch: RestoreLifecycleTimePoint?,
        completion: CfgutilProcessCompletion,
        chunks: [(RestoreOutputChannel, Data)]
    ) {
        processLaunched = launch
        self.completion = completion
        self.chunks = chunks
    }

    func waitForCompletion(tailTimeout: TimeInterval) async -> CfgutilProcessCompletion {
        for chunk in chunks {
            onChunk?(chunk.0, chunk.1)
        }
        return completion
    }

    func interrupt() {}
    func terminate() {}
    func forceKill() {}
}

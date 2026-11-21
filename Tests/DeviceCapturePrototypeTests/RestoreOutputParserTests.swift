import Foundation
import XCTest
@testable import DeviceCapturePrototype

final class RestoreOutputParserTests: XCTestCase {
    private let target: UInt64 = 0x12345670

    func testStepProgressAndCompletionStayStageLocal() {
        let parser = RestoreOutputParser(targetECID: target)
        var snapshot = parser.feed(
            Data(#"""
            Step = "\U6B63\U5728\U5B89\U88C5\U7CFB\U7EDF";
            Type = Step;
            Progress = "0.42";
            Step = "\U6B63\U5728\U5B89\U88C5\U7CFB\U7EDF";
            Type = Progress;

            """#.utf8))

        XCTAssertTrue(snapshot.restoreActivityObserved)
        XCTAssertEqual(snapshot.stepText, "正在安装系统")
        XCTAssertEqual(snapshot.stageFraction ?? -1, 0.42, accuracy: 0.0001)
        XCTAssertNil(snapshot.overallFraction)

        snapshot = parser.feed(
            Data("Step = \"正在安装系统\"; Type = StepComplete;".utf8))
        XCTAssertTrue(snapshot.stepCompleted)
        XCTAssertFalse(snapshot.terminalSummarySeen)
    }

    func testNewStepResetsPreviousFractionAndInvalidFractionsAreIgnored() {
        let parser = RestoreOutputParser(targetECID: target)
        var snapshot = parser.feed(
            Data("Step = \"第一步\"; Type = Step;\nStep = \"第一步\"; Progress = \"0.73\"; Type = Progress;\n".utf8))
        XCTAssertEqual(snapshot.stageFraction ?? -1, 0.73, accuracy: 0.0001)

        snapshot = parser.feed(
            Data("Step = \"第二步\"; Type = Step;\n".utf8))
        XCTAssertEqual(snapshot.stepText, "第二步")
        XCTAssertNil(snapshot.stageFraction)

        snapshot = parser.feed(
            Data("Step = \"第二步\"; Progress = \"1.5\"; Type = Progress;\n".utf8))
        XCTAssertNil(snapshot.stageFraction)
    }

    func testStepTypeAlwaysResetsFractionEvenWhenLabelRepeatsOrIsMissing() {
        let parser = RestoreOutputParser(targetECID: target)
        _ = parser.feed(
            Data("Step = \"安装系统\"; Type = Step;\nStep = \"安装系统\"; Progress = \"1.0\"; Type = Progress;\n".utf8))
        XCTAssertEqual(parser.snapshot.stageFraction, 1)

        var snapshot = parser.feed(
            Data("Step = \"安装系统\"; Type = Step;\n".utf8))
        XCTAssertNil(snapshot.stageFraction)
        XCTAssertEqual(snapshot.stepText, "安装系统")

        _ = parser.feed(
            Data("Step = \"安装系统\"; Progress = \"0.25\"; Type = Progress;\n".utf8))
        XCTAssertEqual(parser.snapshot.stageFraction ?? -1, 0.25, accuracy: 0.0001)

        snapshot = parser.feed(Data("Type = Step;\n".utf8))
        XCTAssertNil(snapshot.stageFraction)
        XCTAssertEqual(snapshot.stepText, "")
    }

    func testStepCompleteClearsTheCompletedStepFraction() {
        let parser = RestoreOutputParser(targetECID: target)
        _ = parser.feed(
            Data("Step = \"安装系统\"; Progress = \"0.42\"; Type = Progress;\n".utf8))
        XCTAssertEqual(
            parser.snapshot.stageFraction ?? -1,
            0.42,
            accuracy: 0.0001)

        let snapshot = parser.feed(
            Data("Step = \"安装系统\"; Type = StepComplete;\n".utf8))

        XCTAssertTrue(snapshot.stepCompleted)
        XCTAssertNil(snapshot.stageFraction)
        XCTAssertEqual(snapshot.stepText, "安装系统")
    }

    func testOneHundredPercentWithoutSummaryRemainsUnknown() {
        let parser = RestoreOutputParser(targetECID: target)
        let snapshot = parser.feed(
            Data("Step = \"最后一步\"; Type = Step;\nStep = \"最后一步\"; Progress = \"1.0\"; Type = Progress;\n".utf8))

        XCTAssertEqual(snapshot.stageFraction, 1)
        XCTAssertEqual(
            parser.outcome(
                exitCode: 0,
                userCancelled: false,
                tailComplete: true),
            .unknown)
    }

    func testAdjacentDictionariesAndSentinelAreParsedWithoutNegativeProgress() {
        let parser = RestoreOutputParser(targetECID: target)
        let snapshot = parser.feed(
            Data(#"Step = "第二"; Type = Step;}{Progress = "-1"; Step = "第二"; Type = Progress;"#.utf8))

        XCTAssertEqual(snapshot.stepText, "第二")
        XCTAssertTrue(snapshot.sentinelComplete)
        XCTAssertNil(snapshot.stageFraction)
    }

    func testSuccessRequiresExitZeroMatchingDeviceAndFinalSummary() {
        let parser = RestoreOutputParser(targetECID: target)
        _ = parser.feed(
            Data("Restored System on Unknown device (ECID: \(target)).\n".utf8))
        _ = parser.feed(
            Data(#"--- Summary ---\nOperation "restore" succeeded on 1 devices.\n"#.utf8))

        XCTAssertEqual(
            parser.outcome(exitCode: 0, userCancelled: false, tailComplete: true),
            .success)
        XCTAssertEqual(
            parser.outcome(exitCode: 0, userCancelled: false, tailComplete: false),
            .unknown)
    }

    func testExitZeroWithoutSummaryIsUnknown() {
        let parser = RestoreOutputParser(targetECID: target)
        _ = parser.feed(Data("Restored System on Unknown device (ECID: \(target)).\n".utf8))
        XCTAssertEqual(
            parser.outcome(exitCode: 0, userCancelled: false, tailComplete: true),
            .unknown)
    }

    func testPartialUTF8ChunkIsNotConsumedUntilItsLineIsComplete() {
        let parser = RestoreOutputParser(targetECID: target)
        let line = "Step = \"正在安装系统\"; Type = Step;\r\n"
        let bytes = Data(line.utf8)
        let split = bytes.count / 2

        let first = parser.feed(bytes.prefix(split))
        XCTAssertEqual(first.stepText, "")
        XCTAssertTrue(first.outputTail.isEmpty)

        let second = parser.feed(bytes.suffix(from: split))
        XCTAssertEqual(second.stepText, "正在安装系统")
        XCTAssertEqual(second.outputTail.count, 1)
    }

    func testCfgutilOutputTailIsBoundedAndLineLimited() {
        let parser = RestoreOutputParser(targetECID: target)
        let lines = (0..<300).map { "line-\($0)" }
        _ = parser.feed(Data((lines.joined(separator: "\n") + "\n").utf8))

        let snapshot = parser.snapshot
        XCTAssertEqual(snapshot.outputTail.count, 240)
        XCTAssertEqual(snapshot.outputSequence, 300)
        XCTAssertEqual(snapshot.outputTail.first, "line-60")
        XCTAssertEqual(snapshot.outputTail.last, "line-299")

        _ = parser.feed(Data(
            (String(repeating: "x", count: 10_000) + "\n").utf8))
        XCTAssertEqual(
            parser.snapshot.outputTail.last?.count,
            8_192)
    }

    func testNonZeroExitWithoutExplicitErrorIsFailureUnlessUserCancelled() {
        let parser = RestoreOutputParser(targetECID: target)
        _ = parser.feed(Data("Waiting for device\n".utf8))
        XCTAssertEqual(
            parser.outcome(exitCode: 1, userCancelled: false, tailComplete: true),
            .failure)
        XCTAssertEqual(
            parser.outcome(exitCode: 1, userCancelled: true, tailComplete: true),
            .canceled)
    }

    func testExplicitFailureWinsAndUserCancellationIsReported() {
        let failure = RestoreOutputParser(targetECID: target)
        _ = failure.feed(Data(#"""
        cfgutil: error: RestoreOS device removed before restored completed
        (Domain: com.apple.MobileDevice.MobileRestore Code: 9)
        "restore" failed on Unknown device (ECID: \(target)).
        """#.utf8))
        XCTAssertEqual(
            failure.outcome(exitCode: 1, userCancelled: false, tailComplete: true),
            .failure)

        let cancelled = RestoreOutputParser(targetECID: target)
        _ = cancelled.feed(Data("Waiting for device\n".utf8))
        XCTAssertEqual(
            cancelled.outcome(exitCode: 130, userCancelled: true, tailComplete: true),
            .canceled)
    }
}

extension RestoreOutputParserTests {
    func testChineseHumanStepAndRealPercent() {
        let parser = RestoreOutputParser(targetECID: target)
        var snapshot = parser.feed(Data("第 2/2 步：正在安装系统 [2/2] 0%\n".utf8))
        XCTAssertEqual(snapshot.stepText, "正在安装系统")
        XCTAssertEqual(snapshot.stageFraction, 0)
        snapshot = parser.feed(Data("第 2/2 步：正在安装系统 [2/2] 37%\n".utf8))
        XCTAssertEqual(snapshot.stageFraction ?? -1, 0.37, accuracy: 0.0001)
        XCTAssertEqual(snapshot.stepText, "正在安装系统")
    }

    func testEnglishHumanStepAndWaitingLine() {
        let parser = RestoreOutputParser(targetECID: target)
        var snapshot = parser.feed(Data("Step 2 of 2: Installing system [2/2] 42%\n".utf8))
        XCTAssertEqual(snapshot.stepText, "Installing system")
        XCTAssertEqual(snapshot.stageFraction ?? -1, 0.42, accuracy: 0.0001)
        snapshot = parser.feed(Data("正在等待设备 [1/2] 100%\n".utf8))
        XCTAssertEqual(snapshot.stepText, "正在等待设备")
        XCTAssertEqual(snapshot.stageFraction, 1)
    }

    func testInvalidHumanPercentIsIgnoredAndNoSuccessIsInferred() {
        let parser = RestoreOutputParser(targetECID: target)
        let snapshot = parser.feed(Data("第 2/2 步：正在安装系统 [2/2] 101%\n".utf8))
        XCTAssertEqual(snapshot.stageFraction, nil)
        XCTAssertFalse(snapshot.sawSuccessSummary)
        XCTAssertEqual(
            parser.outcome(exitCode: 0, userCancelled: false, tailComplete: true),
            .unknown)
    }

    func testTwentySevenLineChineseSampleReachesInstallPercent() {
        let parser = RestoreOutputParser(targetECID: target)
        let lines = (0..<27).map { index -> String in
            if index < 20 { return "第 1/2 步：准备恢复 [1/2] \(min(index, 100))%" }
            if index == 20 { return "第 2/2 步：正在安装系统 [2/2] 0%" }
            return "第 2/2 步：正在安装系统 [2/2] 37%"
        }
        var snapshot = parser.snapshot
        for line in lines { snapshot = parser.feed(Data((line + "\n").utf8)) }
        XCTAssertEqual(snapshot.stepText, "正在安装系统")
        XCTAssertEqual(snapshot.stageFraction ?? -1, 0.37, accuracy: 0.0001)
    }
}

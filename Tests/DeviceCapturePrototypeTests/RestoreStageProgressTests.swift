import Foundation
import XCTest
@testable import DeviceCapturePrototype

final class RestoreStageProgressTests: XCTestCase {
    func testNoTrustedValueShowsIndeterminateStageAndOverallUnknown() {
        let presentation = RestoreStageProgressPresentation(
            stageFraction: nil,
            stepText: "",
            outcome: nil,
            processStarted: true)

        XCTAssertTrue(presentation.isIndeterminate)
        XCTAssertNil(presentation.stageFraction)
        XCTAssertEqual(presentation.overallText, "整体进度：未知")
    }

    func testZeroFractionIsARealStageValue() {
        let presentation = RestoreStageProgressPresentation(
            stageFraction: 0,
            stepText: "正在准备",
            outcome: nil,
            processStarted: true)

        XCTAssertEqual(presentation.stageFraction, 0)
        XCTAssertEqual(presentation.percentageText, "0%")
        XCTAssertFalse(presentation.isIndeterminate)
    }

    func testFractionalStageValueKeepsUsefulPrecision() {
        let presentation = RestoreStageProgressPresentation(
            stageFraction: 0.495,
            stepText: "正在安装系统",
            outcome: nil,
            processStarted: true)

        XCTAssertEqual(presentation.percentageText, "49.5%")
        XCTAssertEqual(presentation.overallText, "整体进度：未知")
    }

    func testOneHundredPercentWithoutTerminalDoesNotClaimSuccess() {
        let presentation = RestoreStageProgressPresentation(
            stageFraction: 1,
            stepText: "正在等待设备重新启动",
            outcome: nil,
            processStarted: true)

        XCTAssertEqual(presentation.percentageText, "100%")
        XCTAssertEqual(presentation.overallText, "整体进度：未知")
    }

    func testInvalidFractionsAreNeverDisplayed() {
        for value in [-0.01, 1.01, .nan, .infinity] {
            let presentation = RestoreStageProgressPresentation(
                stageFraction: value,
                stepText: "阶段",
                outcome: nil,
                processStarted: true)
            XCTAssertNil(presentation.stageFraction)
            XCTAssertNil(presentation.percentageText)
            XCTAssertTrue(presentation.isIndeterminate)
        }
    }

    func testTerminalOutcomeStopsDeviceProgressPresentation() {
        let presentation = RestoreStageProgressPresentation(
            stageFraction: 1,
            stepText: "正在安装系统",
            outcome: .success,
            processStarted: true)

        XCTAssertNil(presentation.stageFraction)
        XCTAssertFalse(presentation.isIndeterminate)
        XCTAssertEqual(presentation.overallText, "Restore 终态：SUCCESS")
    }

    func testPreparationDoesNotUseAStaleFraction() {
        let presentation = RestoreStageProgressPresentation(
            stageFraction: 0.75,
            stepText: "",
            outcome: nil,
            processStarted: false)

        XCTAssertNil(presentation.stageFraction)
        XCTAssertTrue(presentation.isIndeterminate)
        XCTAssertEqual(presentation.phaseText, "Restore 准备中")
    }

    func testCompletedStepDoesNotKeepShowingItsPreviousFraction() {
        let presentation = RestoreStageProgressPresentation(
            stageFraction: 0.42,
            stepText: "正在安装系统",
            stepCompleted: true,
            outcome: nil,
            processStarted: true)

        XCTAssertNil(presentation.stageFraction)
        XCTAssertNil(presentation.percentageText)
        XCTAssertFalse(presentation.isIndeterminate)
        XCTAssertEqual(presentation.phaseText, "正在安装系统")
        XCTAssertEqual(
            presentation.detailText,
            "cfgutil 已报告当前阶段完成，等待下一阶段真实输出。")
        XCTAssertEqual(presentation.overallText, "整体进度：未知")
    }

    func testFractionWithoutStageContextRemainsUnknown() {
        let presentation = RestoreStageProgressPresentation(
            stageFraction: 0.5,
            stepText: "",
            outcome: nil,
            processStarted: true)

        XCTAssertNil(presentation.stageFraction)
        XCTAssertNil(presentation.percentageText)
        XCTAssertTrue(presentation.isIndeterminate)
    }
}

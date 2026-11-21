import XCTest
@testable import DeviceCapturePrototype

final class HelperRuntimePresentationTests: XCTestCase {
    private func snapshot(
        _ kind: HelperEnvironmentKind,
        statusLine: String = "已安装 · 已连接"
    ) -> HelperEnvironmentSnapshot {
        HelperEnvironmentSnapshot(
            kind: kind,
            statusLine: statusLine,
            statusColor: kind == .currentHealthy ? "green" : "orange",
            detailLines: [],
            allowedActions: [],
            macosVersion: "27.3",
            architecture: "arm64",
            appMinOS: "26.0",
            osCompatibility: "兼容",
            helperVersion: "0.2.5",
            socketState: "存在",
            serviceState: "已登记/可读取",
            detectionError: nil)
    }

    func testInstalledButUnauthorizedCallIsNotShownAsConnected() {
        let installed = snapshot(.currentHealthy)
        XCTAssertEqual(
            HelperRuntimePresentation.homeText(
                snapshot: installed,
                authenticatedCallAvailable: false),
            "Helper 已安装 · 调用未授权")
        XCTAssertEqual(
            HelperRuntimePresentation.homeColor(
                snapshot: installed,
                authenticatedCallAvailable: false),
            "red")
    }

    func testAuthenticatedCallHasSeparateExecutableStatus() {
        let installed = snapshot(.currentHealthy)
        XCTAssertEqual(
            HelperRuntimePresentation.homeText(
                snapshot: installed,
                authenticatedCallAvailable: true),
            "Helper 可用 · 签名授权通过")
        XCTAssertEqual(
            HelperRuntimePresentation.callStatusText(
                authenticatedCallAvailable: true,
                callReason: "READY"),
            "可用（签名授权与 socket 调用已通过）")
    }

    func testNotInstalledIsDistinctFromUnauthorizedInstalledHelper() {
        let missing = snapshot(.notInstalled, statusLine: "未安装 Helper")
        XCTAssertEqual(
            HelperRuntimePresentation.homeText(
                snapshot: missing,
                authenticatedCallAvailable: false),
            "Helper 未安装")
        XCTAssertEqual(
            HelperRuntimePresentation.homeColor(
                snapshot: missing,
                authenticatedCallAvailable: false),
            "gray")
    }
}

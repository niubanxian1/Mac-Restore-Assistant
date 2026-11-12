import XCTest
import CoreGraphics
@testable import DeviceCapturePrototype

final class FirstLaunchAuthorizationWindowGuardTests: XCTestCase {
    func testQuarantinedFirstLaunchDefersWindow() {
        XCTAssertTrue(FirstLaunchAuthorizationWindowGuardPolicy.shouldDefer(
            hasQuarantine: true,
            alreadyHandled: false))
    }

    func testNormalLaunchDoesNotDeferWindow() {
        XCTAssertFalse(FirstLaunchAuthorizationWindowGuardPolicy.shouldDefer(
            hasQuarantine: false,
            alreadyHandled: false))
    }

    func testPreviouslyHandledQuarantineDoesNotDeferAgain() {
        XCTAssertFalse(FirstLaunchAuthorizationWindowGuardPolicy.shouldDefer(
            hasQuarantine: true,
            alreadyHandled: true))
    }

    func testPasswordAndTouchIDAuthorizationPromptsAreBothRecognized() {
        XCTAssertTrue(FirstLaunchAuthorizationWindowGuardPolicy.isAuthorizationPromptBundleIdentifier(
            "com.apple.SecurityAgent"))
        XCTAssertTrue(FirstLaunchAuthorizationWindowGuardPolicy.isAuthorizationPromptBundleIdentifier(
            "com.apple.LocalAuthentication.UIAgent"))
        XCTAssertFalse(FirstLaunchAuthorizationWindowGuardPolicy.isAuthorizationPromptBundleIdentifier(
            "com.openai.codex"))
    }

    func testOnlyVisibleWindowsFromAuthorizationProcessesDeferLaunch() {
        let authorizationPID: pid_t = 123
        let unrelatedPID: pid_t = 456
        XCTAssertTrue(FirstLaunchAuthorizationWindowGuardPolicy.hasVisibleAuthorizationWindow(
            ownerPIDs: [authorizationPID],
            windows: [[
                kCGWindowOwnerPID as String: NSNumber(value: authorizationPID),
                kCGWindowAlpha as String: NSNumber(value: 1.0),
            ]]))
        XCTAssertFalse(FirstLaunchAuthorizationWindowGuardPolicy.hasVisibleAuthorizationWindow(
            ownerPIDs: [authorizationPID],
            windows: [[
                kCGWindowOwnerPID as String: NSNumber(value: unrelatedPID),
                kCGWindowAlpha as String: NSNumber(value: 1.0),
            ]]))
        XCTAssertFalse(FirstLaunchAuthorizationWindowGuardPolicy.hasVisibleAuthorizationWindow(
            ownerPIDs: [authorizationPID],
            windows: []))
    }
}

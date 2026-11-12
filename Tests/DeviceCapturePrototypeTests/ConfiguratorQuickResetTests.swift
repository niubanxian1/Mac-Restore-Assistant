import XCTest
@testable import DeviceCapturePrototype

@MainActor
final class ConfiguratorQuickResetTests: XCTestCase {
    func testCommandsMatchOwnerResetAppExactly() {
        let commands = ConfiguratorQuickReset.commands
        XCTAssertEqual(commands.map(\.name), [
            "退出 Apple Configurator",
            "清理 Caches",
            "清理 Application Support",
            "USB 重置",
        ])
        XCTAssertEqual(commands.map(\.shell), [
            "killall 'Apple Configurator' 2>/dev/null || true",
            "rm -rf ~/Library/Caches/com.apple.AppleConfigurator* 2>/dev/null || true",
            "rm -rf ~/Library/Application\\ Support/Apple/Apple\\ Configurator* 2>/dev/null || true",
            "sudo killall -STOP -c usbd 2>/dev/null || true",
        ])
        XCTAssertEqual(commands.map(\.requiresAdministrator), [false, false, false, true])
    }

    func testOnlyUSBResetRequestsAdministratorAuthorization() {
        let admins = ConfiguratorQuickReset.commands.filter(\.requiresAdministrator)
        XCTAssertEqual(admins.count, 1)
        XCTAssertEqual(admins.first?.name, "USB 重置")
        XCTAssertTrue(admins.first?.shell.contains("killall -STOP -c usbd") == true)
    }
}

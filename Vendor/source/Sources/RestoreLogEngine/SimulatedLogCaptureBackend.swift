import Foundation

/// Deterministic stand-in for `/usr/bin/log` used by tests and by the headless
/// self-test. It writes real bytes to a real file on a real disk so the
/// evidence path is exercised end to end; only the producer is synthetic and
/// `captureBackend` records that fact.
public actor SimulatedLogCaptureBackend: LogCaptureBackend {
    public enum Fixture: Sendable {
        case restoreSequence
        case empty
    }

    public let kind = "simulated"

    private let fixture: Fixture
    private let immediateExit: Int32?
    private var running = false
    private var finishedCode: Int32?

    public init(fixture: Fixture = .restoreSequence, immediateExit: Int32? = nil) {
        self.fixture = fixture
        self.immediateExit = immediateExit
        self.finishedCode = immediateExit
    }

    public func start(
        config: CaptureConfig,
        rawLogURL: URL,
        stderrURL: URL
    ) async throws -> BackendHandle {
        let fm = FileManager.default
        try? fm.removeItem(at: rawLogURL)
        try? fm.removeItem(at: stderrURL)
        try Data().write(to: stderrURL, options: .atomic)

        let lines = render(fixture: fixture)
        try Data(lines.utf8).write(to: rawLogURL, options: .atomic)
        running = immediateExit == nil

        return BackendHandle(
            pid: 0,
            executablePath: "simulated://log-stream",
            arguments: config.profile.commandArguments,
            startedAtUTC: Date()
        )
    }

    public func waitForExit(handle: BackendHandle) async -> Int32? {
        running ? nil : finishedCode
    }

    public func requestTermination(handle: BackendHandle) async {
        running = false
        if finishedCode == nil { finishedCode = 0 }
    }

    public func isRunning(handle: BackendHandle) async -> Bool {
        running
    }

    private func render(fixture: Fixture) -> String {
        guard case .restoreSequence = fixture else { return "" }
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.timeZone = TimeZone.current
        stamp.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let now = Date()
        let proc = "com.apple.configurator.xpc.DeviceService[90001:1a2b]"

        let templates: [(TimeInterval, String, String)] = [
            (-42, "Df", "Created state machine for device with ECID=0x469023A9A801E"),
            (-41, "Df", "State Machine Dump, status:RUNNING - [state:DFU remaining-cycles:2 (current state)]"),
            (-38, "I", "amai: AMAuthInstallBundleCopyBuildIdentityForVariant: Found variant: Customer Erase Install (IPSW)"),
            (-30, "Df", "Issued GETSTATUS request: state = 2 status = 0"),
            (-20, "I", "sending file: /Users/operator/Library/Containers/com.apple.configurator.xpc.DeviceService/Data/tmp/Firmware/all_flash/iBootData.j316c.RELEASE.img4"),
            (-12, "I", "Sent image successfully from: /Users/operator/tmp/iBootData.j316c.RELEASE.img4"),
            (-8, "I", "<Restore Device 0x795b918c80>: operation 13 progress 19"),
            (-3, "Df", "_AMRUSBDeviceSendDeviceRequestTO_block_invoke: AMRUSBDevice error (-536854449): { \"Error message\" = \"DeviceRequest failed: 0xe000404f (IOKit return code)\"; }"),
        ]

        return templates.map { item -> String in
            let offset = item.0
            let level = item.1
            let message = item.2
            return "\(stamp.string(from: now.addingTimeInterval(offset))) \(level) \(proc) (MobileDevice) \(message)"
        }.joined(separator: "\n") + "\n"
    }
}

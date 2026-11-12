import Foundation

// MARK: - Configuration

/// A capture profile is versioned so a saved session can explain *why* it
/// contains or lacks a class of information.
public struct CaptureProfile: Sendable, Equatable {
    public let id: String
    public let level: String
    public let style: String
    public let predicate: String
    /// Additional `/usr/bin/log` arguments (for example --no-backtrace).
    public let additionalArguments: [String]

    public init(
        id: String,
        level: String,
        style: String,
        predicate: String,
        additionalArguments: [String] = []
    ) {
        self.id = id
        self.level = level
        self.style = style
        self.predicate = predicate
        self.additionalArguments = additionalArguments
    }

    /// Exact 014H/014A compatibility profile: only the Configurator XPC family.
    /// Kept for replay/regression; it is not the RC default after 014I.
    public static let restoreDefaultV1 = CaptureProfile(
        id: "restore-default-v1",
        level: "debug",
        style: "compact",
        predicate: #"process CONTAINS[c] "configurator""#
    )

    /// 014I RC target coverage. This deliberately keeps DeviceService,
    /// MobileDeviceUpdater and AMPDevices, but does NOT add a global
    /// `eventMessage CHECKPOINT` clause: that clause captured foreign
    /// iCloud/analytics CHECKPOINT noise in the 014A A2681 raw.
    public static let restore014APrimaryV2 = CaptureProfile(
        id: "restore-014a-primary-v2",
        level: "debug",
        style: "ndjson",
        predicate: #"process CONTAINS[c] "DeviceService" OR process CONTAINS[c] "configurator" OR process CONTAINS[c] "MobileDevice" OR process CONTAINS[c] "AMPDevices" OR processImagePath CONTAINS[c] "DeviceService" OR senderImagePath CONTAINS[c] "MobileDevice" OR subsystem CONTAINS[c] "MobileDevice" OR eventMessage CONTAINS[c] "device restore output" OR eventMessage CONTAINS[c] "update_mcdp29xx" OR eventMessage CONTAINS[c] "RamrodErrorDomain" OR eventMessage CONTAINS[c] "AMRestoreErrorDomain""#,
        additionalArguments: ["--no-backtrace", "--no-signpost", "--timeout", "43200s"]
    )

    /// Exact argument vector handed to `/usr/bin/log`. Never a shell string.
    public var commandArguments: [String] {
        ["stream", "--style", style, "--level", level]
            + additionalArguments
            + ["--predicate", predicate]
    }
}

/// Bounded runtime/resource guard for an owned capture child.
/// CPU is intentionally not a stop input: a short CPU spike is not a failure.
public struct CaptureLimits: Sendable, Equatable {
    public var maxDurationSeconds: TimeInterval
    public var minFreeDiskBytes: Int64
    public var maxResidentBytes: Int64
    public var sampleIntervalSeconds: TimeInterval

    public init(
        maxDurationSeconds: TimeInterval = 12 * 60 * 60,
        minFreeDiskBytes: Int64 = 20 * 1024 * 1024 * 1024,
        maxResidentBytes: Int64 = 2 * 1024 * 1024 * 1024,
        sampleIntervalSeconds: TimeInterval = 5
    ) {
        self.maxDurationSeconds = maxDurationSeconds
        self.minFreeDiskBytes = minFreeDiskBytes
        self.maxResidentBytes = maxResidentBytes
        self.sampleIntervalSeconds = sampleIntervalSeconds
    }

    public static let standard = CaptureLimits()
}

public struct CaptureConfig: Sendable {
    public var outputDirectory: URL
    public var profile: CaptureProfile
    /// Host directory scanned for `updater_output-*` (tests inject a temp root).
    public var updaterWatchRoot: URL
    public var ecidHint: String?
    /// Bounded pre-capture lines captured by the Restore-start monitor. This is
    /// stored beside the raw log, never prepended to it.
    public var preCaptureContext: String?
    public var limits: CaptureLimits

    public init(
        outputDirectory: URL,
        profile: CaptureProfile = .restore014APrimaryV2,
        updaterWatchRoot: URL = URL(fileURLWithPath: "/tmp", isDirectory: true),
        ecidHint: String? = nil,
        preCaptureContext: String? = nil,
        limits: CaptureLimits = .standard
    ) {
        self.outputDirectory = outputDirectory
        self.profile = profile
        self.updaterWatchRoot = updaterWatchRoot
        self.ecidHint = ecidHint
        self.preCaptureContext = preCaptureContext
        self.limits = limits
    }
}

// MARK: - Backend boundary

/// Identifies one capture process this engine owns.
///
/// Ownership is proven by executable path + argument vector + PID + start time,
/// so a recycled PID can never be mistaken for our child process.
public struct BackendHandle: Sendable, Equatable {
    public let pid: Int32
    public let executablePath: String
    public let arguments: [String]
    public let startedAtUTC: Date

    public init(pid: Int32, executablePath: String, arguments: [String], startedAtUTC: Date) {
        self.pid = pid
        self.executablePath = executablePath
        self.arguments = arguments
        self.startedAtUTC = startedAtUTC
    }
}

/// The one seam that separates the engine from the real system.
/// Tests inject `SimulatedLogCaptureBackend`; production uses
/// `ProcessLogCaptureBackend`. No SwiftUI type may appear here.
public protocol LogCaptureBackend: Sendable {
    /// "process" for the real `/usr/bin/log` backend, "simulated" for fixtures.
    /// Recorded in `session.json` so simulated evidence can never be mistaken
    /// for a real capture.
    var kind: String { get }

    func start(config: CaptureConfig, rawLogURL: URL, stderrURL: URL) async throws -> BackendHandle
    func waitForExit(handle: BackendHandle) async -> Int32?
    func requestTermination(handle: BackendHandle) async
    func isRunning(handle: BackendHandle) async -> Bool
}

// MARK: - Engine contract (contract §3.2)

/// The reusable asset. Consumed by `rlmctl` today, by the Mac Restore Adapter
/// later. Implementations must not touch SwiftUI, windows, or buttons.
public protocol CaptureEngine: Sendable {
    func beginCapture(config: CaptureConfig) async throws -> SessionHandle
    func getStatus(sessionID: UUID) async throws -> CaptureStatus
    func stopCapture(sessionID: UUID) async throws -> StopResult
    func finalize(sessionID: UUID) async throws -> ExportResult
    func getEventSummary(sessionID: UUID) async throws -> EventSummary
}

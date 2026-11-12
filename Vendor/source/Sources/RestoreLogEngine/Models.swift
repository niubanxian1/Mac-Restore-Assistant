import Foundation

// MARK: - Session state machine (contract: spec §5)

/// The nine honest states. There is no `SUCCESS`: saving evidence and a device
/// restore succeeding are different claims and must never share a state.
public enum CaptureState: String, Codable, Sendable, CaseIterable {
    case idle = "IDLE"
    case starting = "STARTING"
    case recording = "RECORDING"
    case stopping = "STOPPING"
    case finalizing = "FINALIZING"
    case savedVerified = "SAVED_VERIFIED"
    case savedPartial = "SAVED_PARTIAL"
    case interrupted = "INTERRUPTED"
    case failed = "ERROR"

    public var isTerminal: Bool {
        switch self {
        case .savedVerified, .savedPartial, .interrupted, .failed: return true
        case .idle, .starting, .recording, .stopping, .finalizing: return false
        }
    }

    /// Whether a new session may be started from this state.
    public var acceptsNewSession: Bool {
        switch self {
        case .idle, .savedVerified, .savedPartial, .interrupted, .failed: return true
        case .starting, .recording, .stopping, .finalizing: return false
        }
    }
}

/// Capture health describes the *acquisition*, never the restore outcome.
public enum CaptureHealth: String, Codable, Sendable {
    case healthy        // process alive and bytes are landing
    case unconfirmed    // process alive, no verified restore event yet
    case degraded       // process gone, read error, write error
}

public enum CoverageStatus: String, Codable, Sendable {
    case unverified
    case partial
    case verified
}

public enum IntegrityStatus: String, Codable, Sendable {
    case unchecked
    case verified
    case failed
}

/// Outcome of building the sibling `diagnostic.log` (FIX residual: status separation).
/// Independent of `IntegrityStatus` (raw checksum). Old session.json without this
/// field decodes as `.unchecked` — never invent `.ok`.
public enum DiagnosticStatus: String, Codable, Sendable {
    case unchecked
    case ok
    case failed
    case skipped
}

/// Host updater_output capture outcome (additive; legacy JSON → unverified).
public enum UpdaterOutputStatus: String, Codable, Sendable {
    case unchecked
    case notAttempted
    case emptyDirectory
    case capturedPartial
    case capturedComplete
    case miss
    case quarantined
    case failed
}

public enum UpdaterStdoutPresence: String, Codable, Sendable {
    case unverified = "UNVERIFIED"
    case yes = "YES"
    case no = "NO"
    case emptyDir = "EMPTY_DIR"
}

// MARK: - P0-STATUS layered updater reduce (order-independent)

public struct SourceObservation: Codable, Sendable, Equatable {
    public var dirsObserved: [String]
    public var filesObservedCount: Int
    public var emptyDirs: [String]
    public var unreadableDirs: [String]
    public init(dirsObserved: [String] = [], filesObservedCount: Int = 0, emptyDirs: [String] = [], unreadableDirs: [String] = []) {
        self.dirsObserved = dirsObserved
        self.filesObservedCount = filesObservedCount
        self.emptyDirs = emptyDirs
        self.unreadableDirs = unreadableDirs
    }
}

public struct CaptureIntegrityLayer: Codable, Sendable, Equatable {
    public var capturedBytesTotal: Int
    public var anyCompleteBody: Bool
    public var anyPartialBody: Bool
    public var anyProvenBody: Bool
    public init(capturedBytesTotal: Int = 0, anyCompleteBody: Bool = false, anyPartialBody: Bool = false, anyProvenBody: Bool = false) {
        self.capturedBytesTotal = capturedBytesTotal
        self.anyCompleteBody = anyCompleteBody
        self.anyPartialBody = anyPartialBody
        self.anyProvenBody = anyProvenBody
    }
}

public enum AttributionRollup: String, Codable, Sendable, Equatable {
    case bound = "BOUND"
    case unbound = "UNBOUND"
    case conflict = "CONFLICT"
    case mixed = "MIXED"
    case none = "NONE"
}

public struct AttributionLayer: Codable, Sendable, Equatable {
    public var boundDirs: [String]
    public var unboundDirs: [String]
    public var quarantinedDirs: [String]
    public var conflictDirs: [String]
    public var rollup: AttributionRollup
    public init(
        boundDirs: [String] = [],
        unboundDirs: [String] = [],
        quarantinedDirs: [String] = [],
        conflictDirs: [String] = [],
        rollup: AttributionRollup = .none
    ) {
        self.boundDirs = boundDirs
        self.unboundDirs = unboundDirs
        self.quarantinedDirs = quarantinedDirs
        self.conflictDirs = conflictDirs
        self.rollup = rollup
    }
}

public struct UpdaterSessionSummary: Codable, Sendable, Equatable {
    public var updaterOutputStatus: UpdaterOutputStatus
    public var stdoutPresent: UpdaterStdoutPresence
    public var summaryDerivationVersion: String
    public var observation: SourceObservation
    public var integrity: CaptureIntegrityLayer
    public var attribution: AttributionLayer
    public var missingEvidence: [String]
    public init(
        updaterOutputStatus: UpdaterOutputStatus = .notAttempted,
        stdoutPresent: UpdaterStdoutPresence = .unverified,
        summaryDerivationVersion: String = "status-reduce-v1",
        observation: SourceObservation = .init(),
        integrity: CaptureIntegrityLayer = .init(),
        attribution: AttributionLayer = .init(),
        missingEvidence: [String] = []
    ) {
        self.updaterOutputStatus = updaterOutputStatus
        self.stdoutPresent = stdoutPresent
        self.summaryDerivationVersion = summaryDerivationVersion
        self.observation = observation
        self.integrity = integrity
        self.attribution = attribution
        self.missingEvidence = missingEvidence
    }
}

public enum ArchiveStatus: String, Codable, Sendable {
    case notRequested = "NOT_REQUESTED"
    case unavailable = "UNAVAILABLE"
    case collected = "COLLECTED"
    case failed = "FAILED"
}

/// Finalization work is explicit. Saving raw evidence must not implicitly run
/// the full diagnostic analysis.
public enum FinalizeMode: String, Sendable, Equatable {
    case saveOnly = "SAVE_ONLY"
    case withDiagnostic = "WITH_DIAGNOSTIC"
}

/// Real, monotonic finalization progress. Bytes are bytes of the current stage,
/// not a synthetic percentage.
public struct FinalizeProgress: Sendable, Equatable {
    public let stage: String
    public let processedBytes: Int64
    public let totalBytes: Int64
    public let elapsedSeconds: Double

    public init(stage: String, processedBytes: Int64, totalBytes: Int64, elapsedSeconds: Double) {
        self.stage = stage
        self.processedBytes = processedBytes
        self.totalBytes = totalBytes
        self.elapsedSeconds = elapsedSeconds
    }
}

/// Why the capture process stopped. Normal user stop is not abnormal exit.
public enum StopReason: String, Codable, Sendable {
    case userRequested = "USER_REQUESTED"
    case processExited = "PROCESS_EXITED"
    case processSignalled = "PROCESS_SIGNALLED"
    case backendFailure = "BACKEND_FAILURE"
    case resourceLimit = "RESOURCE_LIMIT"
    case unknown = "UNKNOWN"
}

// MARK: - Events

public enum EventTier: String, Codable, Sendable, CaseIterable {
    case t1Device = "T1_DEVICE"            // enumeration, identity, state machine
    case t2Transfer = "T2_TRANSFER"        // USB request/progress traffic
    case t3Personalization = "T3_PERSONALIZATION" // AMAuthInstall / variant selection
    case t4Delivery = "T4_DELIVERY"        // payload / ASR progress
    case t5Error = "T5_ERROR"              // explicit error lines
    case t6Network = "T6_NETWORK"          // CFNetwork noise (context only)
}

public struct CaptureEvent: Codable, Sendable, Equatable {
    public let timestampUTC: Date
    public let process: String
    public let rawLine: String
    public let taxonomyID: String?
    public let tier: EventTier?

    public init(
        timestampUTC: Date,
        process: String,
        rawLine: String,
        taxonomyID: String?,
        tier: EventTier?
    ) {
        self.timestampUTC = timestampUTC
        self.process = process
        self.rawLine = rawLine
        self.taxonomyID = taxonomyID
        self.tier = tier
    }
}

// MARK: - Evidence

public struct EvidenceFile: Codable, Sendable, Equatable {
    public let role: String
    public let relativePath: String
    public let byteSize: Int
    public let sha256: String

    public init(role: String, relativePath: String, byteSize: Int, sha256: String) {
        self.role = role
        self.relativePath = relativePath
        self.byteSize = byteSize
        self.sha256 = sha256
    }
}

public struct SessionHandle: Codable, Sendable, Equatable {
    public let sessionID: UUID
    public let outputDirectory: String
    public let rawLogPath: String
    public let stderrLogPath: String
    public let backendPID: Int32
    public let startedAtUTC: Date

    public init(
        sessionID: UUID,
        outputDirectory: String,
        rawLogPath: String,
        stderrLogPath: String,
        backendPID: Int32,
        startedAtUTC: Date
    ) {
        self.sessionID = sessionID
        self.outputDirectory = outputDirectory
        self.rawLogPath = rawLogPath
        self.stderrLogPath = stderrLogPath
        self.backendPID = backendPID
        self.startedAtUTC = startedAtUTC
    }
}

public struct CaptureStatus: Codable, Sendable, Equatable {
    public let sessionID: UUID
    public let state: CaptureState
    public let health: CaptureHealth
    public let coverage: CoverageStatus
    public let startedAtUTC: Date?
    public let endedAtUTC: Date?
    public let rawByteCount: Int
    public let rawLineCount: Int
    public let capturedEventCount: Int
    public let backendPID: Int32?

    public init(
        sessionID: UUID,
        state: CaptureState,
        health: CaptureHealth,
        coverage: CoverageStatus,
        startedAtUTC: Date?,
        endedAtUTC: Date?,
        rawByteCount: Int,
        rawLineCount: Int,
        capturedEventCount: Int,
        backendPID: Int32?
    ) {
        self.sessionID = sessionID
        self.state = state
        self.health = health
        self.coverage = coverage
        self.startedAtUTC = startedAtUTC
        self.endedAtUTC = endedAtUTC
        self.rawByteCount = rawByteCount
        self.rawLineCount = rawLineCount
        self.capturedEventCount = capturedEventCount
        self.backendPID = backendPID
    }
}

public struct StopResult: Codable, Sendable, Equatable {
    public let sessionID: UUID
    public let reason: StopReason
    public let exitCode: Int32?
    public let durationSeconds: Double

    public init(sessionID: UUID, reason: StopReason, exitCode: Int32?, durationSeconds: Double) {
        self.sessionID = sessionID
        self.reason = reason
        self.exitCode = exitCode
        self.durationSeconds = durationSeconds
    }
}

/// Result of an explicit discard. The session directory has been removed;
/// no SessionRecord is written and no raw/package may reference the session.
public struct DiscardResult: Codable, Sendable, Equatable {
    public let sessionID: UUID
    public let removedDirectory: String

    public init(sessionID: UUID, removedDirectory: String) {
        self.sessionID = sessionID
        self.removedDirectory = removedDirectory
    }
}

public struct EventSummary: Codable, Sendable, Equatable {
    public let sessionID: UUID
    public let totalEvents: Int
    public let countsByTier: [String: Int]
    public let taxonomyVersion: String
    /// FIX-002: true when raw log matches restore terminal success/failure needles.
    /// `progress -1` alone never sets this.
    public let terminalEventDetected: Bool

    public init(
        sessionID: UUID,
        totalEvents: Int,
        countsByTier: [String: Int],
        taxonomyVersion: String,
        terminalEventDetected: Bool
    ) {
        self.sessionID = sessionID
        self.totalEvents = totalEvents
        self.countsByTier = countsByTier
        self.taxonomyVersion = taxonomyVersion
        self.terminalEventDetected = terminalEventDetected
    }
}

/// The persisted `session.json` shape (contract §3.2 exchange schema).
public struct SessionRecord: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let sessionID: UUID
    /// Frozen at first successful save. Never regenerated from later device data.
    public let sessionDisplayName: String?
    public let captureState: CaptureState
    public let captureHealth: CaptureHealth
    public let startedAtUTC: String?
    public let endedAtUTC: String?
    public let captureProfile: String
    public let captureCommand: [String]
    public let captureBackend: String
    public let eventCount: Int
    public let coverageStatus: CoverageStatus
    public let archiveStatus: ArchiveStatus
    public let integrityStatus: IntegrityStatus
    /// Sibling diagnostic.log build outcome. Absent in pre-separation JSON → `.unchecked`.
    public let diagnosticStatus: DiagnosticStatus
    /// True when raw was saved without running DiagnosticLogBuilder. Nil for
    /// legacy session.json, which must be treated as not deferred.
    public let analysisDeferred: Bool?
    public let updaterOutputStatus: UpdaterOutputStatus
    public let updaterStdoutPresent: UpdaterStdoutPresence
    public let earlyWatcherStarted: Bool
    public let firstFatalCheckpoint: String?
    public let updaterReturnCode: String?
    public let hardwareRootCause: String
    public let updaterStatusLayers: UpdaterSessionSummary?
    public let files: [EvidenceFile]
    public let missingEvidence: [String]
    public let errorReason: String?

    public init(
        schemaVersion: Int = 1,
        sessionID: UUID,
        sessionDisplayName: String? = nil,
        captureState: CaptureState,
        captureHealth: CaptureHealth,
        startedAtUTC: String?,
        endedAtUTC: String?,
        captureProfile: String,
        captureCommand: [String],
        captureBackend: String,
        eventCount: Int,
        coverageStatus: CoverageStatus,
        archiveStatus: ArchiveStatus,
        integrityStatus: IntegrityStatus,
        diagnosticStatus: DiagnosticStatus = .unchecked,
        analysisDeferred: Bool? = nil,
        updaterOutputStatus: UpdaterOutputStatus = .unchecked,
        updaterStdoutPresent: UpdaterStdoutPresence = .unverified,
        earlyWatcherStarted: Bool = false,
        firstFatalCheckpoint: String? = nil,
        updaterReturnCode: String? = nil,
        hardwareRootCause: String = "UNVERIFIED",
        updaterStatusLayers: UpdaterSessionSummary? = nil,
        files: [EvidenceFile],
        missingEvidence: [String],
        errorReason: String?
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.sessionDisplayName = sessionDisplayName
        self.captureState = captureState
        self.captureHealth = captureHealth
        self.startedAtUTC = startedAtUTC
        self.endedAtUTC = endedAtUTC
        self.captureProfile = captureProfile
        self.captureCommand = captureCommand
        self.captureBackend = captureBackend
        self.eventCount = eventCount
        self.coverageStatus = coverageStatus
        self.archiveStatus = archiveStatus
        self.integrityStatus = integrityStatus
        self.diagnosticStatus = diagnosticStatus
        self.analysisDeferred = analysisDeferred
        self.updaterOutputStatus = updaterOutputStatus
        self.updaterStdoutPresent = updaterStdoutPresent
        self.earlyWatcherStarted = earlyWatcherStarted
        self.firstFatalCheckpoint = firstFatalCheckpoint
        self.updaterReturnCode = updaterReturnCode
        self.hardwareRootCause = hardwareRootCause
        self.updaterStatusLayers = updaterStatusLayers
        self.files = files
        self.missingEvidence = missingEvidence
        self.errorReason = errorReason
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, sessionID, sessionDisplayName, captureState, captureHealth
        case startedAtUTC, endedAtUTC, captureProfile, captureCommand, captureBackend
        case eventCount, coverageStatus, archiveStatus, integrityStatus
        case diagnosticStatus, analysisDeferred, updaterOutputStatus, updaterStdoutPresent, earlyWatcherStarted
        case firstFatalCheckpoint, updaterReturnCode, hardwareRootCause, updaterStatusLayers
        case files, missingEvidence, errorReason
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        sessionID = try c.decode(UUID.self, forKey: .sessionID)
        sessionDisplayName = try c.decodeIfPresent(String.self, forKey: .sessionDisplayName)
        captureState = try c.decode(CaptureState.self, forKey: .captureState)
        captureHealth = try c.decode(CaptureHealth.self, forKey: .captureHealth)
        startedAtUTC = try c.decodeIfPresent(String.self, forKey: .startedAtUTC)
        endedAtUTC = try c.decodeIfPresent(String.self, forKey: .endedAtUTC)
        captureProfile = try c.decode(String.self, forKey: .captureProfile)
        captureCommand = try c.decode([String].self, forKey: .captureCommand)
        captureBackend = try c.decode(String.self, forKey: .captureBackend)
        eventCount = try c.decode(Int.self, forKey: .eventCount)
        coverageStatus = try c.decode(CoverageStatus.self, forKey: .coverageStatus)
        archiveStatus = try c.decode(ArchiveStatus.self, forKey: .archiveStatus)
        integrityStatus = try c.decode(IntegrityStatus.self, forKey: .integrityStatus)
        // Honest default: missing field is unchecked, never ok/failed invented.
        diagnosticStatus = try c.decodeIfPresent(DiagnosticStatus.self, forKey: .diagnosticStatus) ?? .unchecked
        analysisDeferred = try c.decodeIfPresent(Bool.self, forKey: .analysisDeferred)
        updaterOutputStatus = try c.decodeIfPresent(UpdaterOutputStatus.self, forKey: .updaterOutputStatus) ?? .unchecked
        updaterStdoutPresent = try c.decodeIfPresent(UpdaterStdoutPresence.self, forKey: .updaterStdoutPresent) ?? .unverified
        earlyWatcherStarted = try c.decodeIfPresent(Bool.self, forKey: .earlyWatcherStarted) ?? false
        firstFatalCheckpoint = try c.decodeIfPresent(String.self, forKey: .firstFatalCheckpoint)
        updaterReturnCode = try c.decodeIfPresent(String.self, forKey: .updaterReturnCode)
        hardwareRootCause = try c.decodeIfPresent(String.self, forKey: .hardwareRootCause) ?? "UNVERIFIED"
        updaterStatusLayers = try c.decodeIfPresent(UpdaterSessionSummary.self, forKey: .updaterStatusLayers)
        files = try c.decode([EvidenceFile].self, forKey: .files)
        missingEvidence = try c.decode([String].self, forKey: .missingEvidence)
        errorReason = try c.decodeIfPresent(String.self, forKey: .errorReason)
    }
}

public struct ExportResult: Codable, Sendable, Equatable {
    public let sessionID: UUID
    public let record: SessionRecord
    public let sessionJSONPath: String
    public let sha256SumsPath: String

    public init(
        sessionID: UUID,
        record: SessionRecord,
        sessionJSONPath: String,
        sha256SumsPath: String
    ) {
        self.sessionID = sessionID
        self.record = record
        self.sessionJSONPath = sessionJSONPath
        self.sha256SumsPath = sha256SumsPath
    }
}

// MARK: - Errors

public enum CaptureError: Error, CustomStringConvertible, Sendable {
    case invalidTransition(from: CaptureState, to: CaptureState)
    case noActiveSession
    case sessionNotFound(UUID)
    case backendStartFailed(String)
    case watcherNotReady(String)
    case outputDirectoryNotWritable(String)
    case integrityCheckFailed(String)

    public var description: String {
        switch self {
        case let .invalidTransition(from, to):
            return "invalid transition \(from.rawValue) -> \(to.rawValue)"
        case .noActiveSession:
            return "no active capture session"
        case let .sessionNotFound(id):
            return "session not found: \(id.uuidString)"
        case let .backendStartFailed(detail):
            return "capture backend failed to start: \(detail)"
        case let .watcherNotReady(detail):
            return "updater watcher not ready: \(detail)"
        case let .outputDirectoryNotWritable(path):
            return "output directory not writable: \(path)"
        case let .integrityCheckFailed(detail):
            return "integrity check failed: \(detail)"
        }
    }
}

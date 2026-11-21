import Foundation
import Combine

struct RestoreLifecycleTimePoint: Codable, Equatable, Sendable {
    let wallTime: Date
    let monotonicNanoseconds: UInt64
}

enum RestoreLifecycleClock {
    static func now(
        wallTime: Date = Date(),
        systemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> RestoreLifecycleTimePoint {
        RestoreLifecycleTimePoint(
            wallTime: wallTime,
            monotonicNanoseconds:
                UInt64(max(0, systemUptime) * 1_000_000_000))
    }

    static func seconds(
        from start: RestoreLifecycleTimePoint?,
        to end: RestoreLifecycleTimePoint?
    ) -> TimeInterval? {
        guard let start, let end,
              end.monotonicNanoseconds >= start.monotonicNanoseconds else {
            return nil
        }
        return TimeInterval(
            end.monotonicNanoseconds - start.monotonicNanoseconds)
            / 1_000_000_000
    }
}

struct RestoreLifecycleTimes: Codable, Equatable, Sendable {
    let userConfirmed: RestoreLifecycleTimePoint
    var processLaunched: RestoreLifecycleTimePoint? = nil
    var firstRestoreActivity: RestoreLifecycleTimePoint? = nil
    var processExited: RestoreLifecycleTimePoint? = nil
    var bothStreamsEOF: RestoreLifecycleTimePoint? = nil
    var outcomeConfirmed: RestoreLifecycleTimePoint? = nil
    var rlmFinalized: RestoreLifecycleTimePoint? = nil

    var processWallDurationSeconds: TimeInterval? {
        RestoreLifecycleClock.seconds(
            from: processLaunched,
            to: processExited)
    }

    var userConfirmedToOutcomeSeconds: TimeInterval? {
        RestoreLifecycleClock.seconds(
            from: userConfirmed,
            to: outcomeConfirmed)
    }
}

enum RestoreTerminationReason: String, Codable, Equatable, Sendable {
    case exit
    case uncaughtSignal
    case unknown
}

enum RestoreSentSignalKind: String, Codable, Equatable, Sendable {
    case interrupt
    case terminate
    case kill
}

struct RestoreSentSignal: Codable, Equatable, Sendable {
    let kind: RestoreSentSignalKind
    let time: RestoreLifecycleTimePoint
}

struct RestoreOutcomeContext: Equatable, Sendable {
    let exitCode: Int32?
    let userCancelled: Bool
    let processLaunched: Bool
    let cancelRequestedAt: RestoreLifecycleTimePoint?
    let tailComplete: Bool
    let terminationReason: RestoreTerminationReason
    let sentSignals: [RestoreSentSignal]
}

enum RestoreOperationType: String, Codable, Equatable, Sendable {
    case restore
}

enum RestoreRawEvidenceStatus: String, Codable, Equatable, Sendable {
    case notRequested = "NOT_REQUESTED"
    case notSavedByChoice = "NOT_SAVED_BY_CHOICE"
    case pendingBatch4 = "RAW_SINK_POLICY_PENDING_BATCH_4"
    case complete = "COMPLETE"
    case incompleteProtected = "INCOMPLETE_PROTECTED"
    case unavailable = "UNAVAILABLE"
}

struct RestoreRawPersistencePolicy: Codable, Equatable, Sendable {
    let autoSaveDefault: Bool
    let saveThisRun: Bool
    let destinationDirectory: String
    let autoMonitorEnabled: Bool
    let spaceWarningThresholdBytes: Int64?
    let retentionPolicy: String
}

struct RestoreRawPersistenceDefaults: Equatable, Sendable {
    let autoSaveDefault: Bool
    let destinationDirectory: String
    let autoMonitorEnabled: Bool
    let spaceWarningThresholdBytes: Int64?
    let retentionPolicy: String

    static let standard = RestoreRawPersistenceDefaults(
        autoSaveDefault: false,
        destinationDirectory: "",
        autoMonitorEnabled: false,
        spaceWarningThresholdBytes: nil,
        retentionPolicy: "manual")

    func policy(saveThisRun: Bool) -> RestoreRawPersistencePolicy {
        RestoreRawPersistencePolicy(
            autoSaveDefault: autoSaveDefault,
            saveThisRun: saveThisRun,
            destinationDirectory: destinationDirectory,
            autoMonitorEnabled: autoMonitorEnabled,
            spaceWarningThresholdBytes: spaceWarningThresholdBytes,
            retentionPolicy: retentionPolicy)
    }
}

@MainActor
final class RestoreRawPersistenceSettings: ObservableObject {
    private static let autoSaveKey =
        "MRA.log.autoSaveRestoreRawLogs"
    private static let spaceWarningKey =
        "MRA.log.restoreRawSpaceWarningBytes"
    private static let retentionDaysKey =
        "MRA.log.restoreRawRetentionDays"
    private static let retentionBytesKey =
        "MRA.log.restoreRawRetentionBytes"

    private let defaults: UserDefaults

    @Published var autoSaveRestoreRawLogs: Bool {
        didSet {
            defaults.set(
                autoSaveRestoreRawLogs,
                forKey: Self.autoSaveKey)
        }
    }
    @Published var spaceWarningThresholdBytes: Int64 {
        didSet {
            defaults.set(
                max(0, spaceWarningThresholdBytes),
                forKey: Self.spaceWarningKey)
        }
    }
    @Published var retentionDays: Int {
        didSet {
            defaults.set(
                max(1, retentionDays),
                forKey: Self.retentionDaysKey)
        }
    }
    @Published var retentionBytes: Int64 {
        didSet {
            defaults.set(
                max(1, retentionBytes),
                forKey: Self.retentionBytesKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoSaveRestoreRawLogs =
            defaults.object(forKey: Self.autoSaveKey) as? Bool
            ?? false
        spaceWarningThresholdBytes =
            (defaults.object(forKey: Self.spaceWarningKey) as? NSNumber)?
                .int64Value
            ?? 1_073_741_824
        retentionDays =
            defaults.object(forKey: Self.retentionDaysKey) as? Int
            ?? 30
        retentionBytes =
            (defaults.object(forKey: Self.retentionBytesKey) as? NSNumber)?
                .int64Value
            ?? 1_073_741_824
    }
}

enum RestoreRLMOwnership: String, Codable, Equatable, Sendable {
    case notRequested = "NOT_REQUESTED"
    case manualUserOwned = "MANUAL_USER_OWNED"
    case restoreOwned = "RESTORE_OWNED"
    case unavailable = "UNAVAILABLE"
}

enum RestoreRLMFinalizationDisposition: String, Codable, Equatable, Sendable {
    case finalizedOwnedSession = "FINALIZED_OWNED_SESSION"
    case continuedInManualSession = "CONTINUED_IN_MANUAL_SESSION"
    case continuedInSharedRestoreSession = "CONTINUED_IN_SHARED_RESTORE_SESSION"
    case notRequested = "NOT_REQUESTED"
    case unavailable = "UNAVAILABLE"
    case timedOut = "TIMED_OUT"
}

struct RestoreRLMFinalization: Equatable, Sendable {
    let ownership: RestoreRLMOwnership
    let disposition: RestoreRLMFinalizationDisposition
    let finalizedAt: RestoreLifecycleTimePoint?
    let drainDurationSeconds: TimeInterval?
    let rawLogURL: URL?
    let reason: String?
}

enum RestoreErrorClassification: String, Codable, Equatable, Sendable {
    case none = "NONE"
    case preflight = "PREFLIGHT"
    case launchFailure = "LAUNCH_FAILURE"
    case explicitFailure = "EXPLICIT_FAILURE"
    case cancellationBeforeLaunch = "CANCELLATION_BEFORE_LAUNCH"
    case cancellationInterruption = "CANCELLATION_INTERRUPTION"
    case terminationSignal = "TERMINATION_SIGNAL"
    case missingOutcome = "MISSING_OUTCOME"
    case incompleteEvidence = "INCOMPLETE_EVIDENCE"
    case unknown = "UNKNOWN"
}

enum RestoreHistorySource: String, Codable, Equatable, Sendable {
    case nativeV1703Verified = "NATIVE_V1703_VERIFIED"
    case bootstrapCandidate1702 = "BOOTSTRAP_CANDIDATE_1702"
    case imported = "IMPORTED"
    case unverified = "UNVERIFIED"
}

struct RestoreHistoryRecord: Codable, Equatable, Identifiable, Sendable {
    let taskID: UUID
    let attemptID: UUID
    let operationType: RestoreOperationType
    let deviceDisplayName: String
    let modelFamilyKey: ModelFamilyKey?
    let hardwareBindingKey: HardwareBindingKey
    let stablePortKey: String?
    let firmwareLibraryEntryID: UUID?
    let firmwareFileName: String
    let ipswIdentity: IPSWFileIdentity?
    let productVersion: String?
    let productBuild: String?
    var deviceECID: String? = nil
    var lifecycle: RestoreLifecycleTimes
    var outcome: RestoreOutcome
    var errorClassification: RestoreErrorClassification
    var exitCode: Int32?
    var terminationReason: RestoreTerminationReason
    var cancellationRequested: Bool
    var sentSignals: [RestoreSentSignal]
    var failureSummary: String
    let rawPersistencePolicy: RestoreRawPersistencePolicy
    var rawEvidenceStatus: RestoreRawEvidenceStatus
    var rawArchive: RestoreArchiveRecord?
    var successBaselineID: String?
    var rlmSessionID: String?
    let rlmStatus: RestoreRLMLogStatus
    let rlmOwnership: RestoreRLMOwnership
    var rlmFinalizedAt: RestoreLifecycleTimePoint?
    var rlmDrainDurationSeconds: TimeInterval?
    var rlmFinalizationDisposition: RestoreRLMFinalizationDisposition?
    var rlmFinalizationReason: String?
    var recordSource: RestoreHistorySource
    var verificationComplete: Bool

    var id: UUID { attemptID }

    init(
        taskID: UUID,
        attemptID: UUID,
        operationType: RestoreOperationType,
        deviceDisplayName: String,
        modelFamilyKey: ModelFamilyKey?,
        hardwareBindingKey: HardwareBindingKey,
        stablePortKey: String?,
        firmwareLibraryEntryID: UUID?,
        firmwareFileName: String,
        ipswIdentity: IPSWFileIdentity?,
        productVersion: String?,
        productBuild: String?,
        deviceECID: String? = nil,
        lifecycle: RestoreLifecycleTimes,
        outcome: RestoreOutcome,
        errorClassification: RestoreErrorClassification,
        exitCode: Int32?,
        terminationReason: RestoreTerminationReason,
        cancellationRequested: Bool,
        sentSignals: [RestoreSentSignal],
        failureSummary: String = "",
        rawPersistencePolicy: RestoreRawPersistencePolicy,
        rawEvidenceStatus: RestoreRawEvidenceStatus,
        rawArchive: RestoreArchiveRecord? = nil,
        successBaselineID: String? = nil,
        rlmSessionID: String? = nil,
        rlmStatus: RestoreRLMLogStatus,
        rlmOwnership: RestoreRLMOwnership,
        rlmFinalizedAt: RestoreLifecycleTimePoint?,
        rlmDrainDurationSeconds: TimeInterval?,
        rlmFinalizationDisposition: RestoreRLMFinalizationDisposition? = nil,
        rlmFinalizationReason: String? = nil,
        recordSource: RestoreHistorySource,
        verificationComplete: Bool
    ) {
        self.taskID = taskID
        self.attemptID = attemptID
        self.operationType = operationType
        self.deviceDisplayName = deviceDisplayName
        self.modelFamilyKey = modelFamilyKey
        self.hardwareBindingKey = hardwareBindingKey
        self.stablePortKey = stablePortKey
        self.firmwareLibraryEntryID = firmwareLibraryEntryID
        self.firmwareFileName = firmwareFileName
        self.ipswIdentity = ipswIdentity
        self.productVersion = productVersion
        self.productBuild = productBuild
        self.deviceECID = deviceECID
        self.lifecycle = lifecycle
        self.outcome = outcome
        self.errorClassification = errorClassification
        self.exitCode = exitCode
        self.terminationReason = terminationReason
        self.cancellationRequested = cancellationRequested
        self.sentSignals = sentSignals
        self.failureSummary = failureSummary
        self.rawPersistencePolicy = rawPersistencePolicy
        self.rawEvidenceStatus = rawEvidenceStatus
        self.rawArchive = rawArchive
        self.successBaselineID = successBaselineID
        self.rlmSessionID = rlmSessionID
        self.rlmStatus = rlmStatus
        self.rlmOwnership = rlmOwnership
        self.rlmFinalizedAt = rlmFinalizedAt
        self.rlmDrainDurationSeconds = rlmDrainDurationSeconds
        self.rlmFinalizationDisposition = rlmFinalizationDisposition
        self.rlmFinalizationReason = rlmFinalizationReason
        self.recordSource = recordSource
        self.verificationComplete = verificationComplete
    }
}

struct RestoreHistoryStatistics: Equatable, Sendable {
    let totalRestoreCount: Int
    let successCount: Int
    let failureCount: Int
    let canceledCount: Int
    let unknownCount: Int
    let trustedRuntimeSampleCount: Int
    let averageDurationSeconds: TimeInterval?
    let medianDurationSeconds: TimeInterval?

    static let empty = RestoreHistoryStatistics(
        totalRestoreCount: 0,
        successCount: 0,
        failureCount: 0,
        canceledCount: 0,
        unknownCount: 0,
        trustedRuntimeSampleCount: 0,
        averageDurationSeconds: nil,
        medianDurationSeconds: nil)

    var hasTrustedDuration: Bool {
        trustedRuntimeSampleCount > 0
            && averageDurationSeconds != nil
            && medianDurationSeconds != nil
    }
}

enum RestoreHistoryStoreError: Error, Equatable {
    case unsupportedSchema(Int)
    case corrupt
    case unavailable
    case cannotEncode
}

protocol RestoreHistoryStoring: Sendable {
    func records() async throws -> [RestoreHistoryRecord]
    func upsert(_ record: RestoreHistoryRecord) async throws
    func updateRLMFinalization(
        attemptID: UUID,
        finalizedAt: RestoreLifecycleTimePoint?,
        drainDurationSeconds: TimeInterval?,
        disposition: RestoreRLMFinalizationDisposition?,
        reason: String?
    ) async throws
    func statistics(
        modelFamilyKey: ModelFamilyKey?,
        productBuild: String?
    ) async throws -> RestoreHistoryStatistics
    func firmwareUsageRecords() async throws -> [FirmwareUsageRecord]
}

actor RestoreHistoryStore: RestoreHistoryStoring {
    private struct Document: Codable {
        var schemaVersion: Int
        var records: [RestoreHistoryRecord]
    }

    static let schemaVersion = 2
    private let fileURL: URL
    private var loaded = false
    private var loadFailure: RestoreHistoryStoreError?
    private var storedRecords: [RestoreHistoryRecord] = []

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
            ?? AppSupportLocations.directory()
                .appendingPathComponent("RestoreHistory", isDirectory: true)
                .appendingPathComponent("history-v1.json")
    }

    func records() async throws -> [RestoreHistoryRecord] {
        try ensureLoaded()
        return sortedRecords()
    }

    func upsert(_ record: RestoreHistoryRecord) async throws {
        do {
            try ensureLoaded()
        } catch RestoreHistoryStoreError.corrupt {
            throw RestoreHistoryStoreError.unavailable
        }
        var normalized = record
        normalized.failureSummary = Self.bounded(
            record.failureSummary,
            utf8Limit: 2_048)
        if let index = storedRecords.firstIndex(where: {
            $0.taskID == normalized.taskID
                && $0.operationType == normalized.operationType
        }) {
            storedRecords[index] = normalized
        } else {
            storedRecords.append(normalized)
        }
        try persist()
    }

    func updateRLMFinalization(
        attemptID: UUID,
        finalizedAt: RestoreLifecycleTimePoint?,
        drainDurationSeconds: TimeInterval?,
        disposition: RestoreRLMFinalizationDisposition? = nil,
        reason: String? = nil
    ) async throws {
        do {
            try ensureLoaded()
        } catch RestoreHistoryStoreError.corrupt {
            throw RestoreHistoryStoreError.unavailable
        }
        guard let index = storedRecords.firstIndex(where: {
            $0.attemptID == attemptID
        }) else {
            return
        }
        storedRecords[index].rlmFinalizedAt = finalizedAt
        storedRecords[index].lifecycle.rlmFinalized = finalizedAt
        storedRecords[index].rlmDrainDurationSeconds = drainDurationSeconds
        storedRecords[index].rlmFinalizationDisposition = disposition
        storedRecords[index].rlmFinalizationReason = reason
        try persist()
    }

    func statistics(
        modelFamilyKey: ModelFamilyKey?,
        productBuild: String?
    ) async throws -> RestoreHistoryStatistics {
        try ensureLoaded()
        let matching = storedRecords.filter {
            $0.operationType == .restore
                && (modelFamilyKey == nil || $0.modelFamilyKey == modelFamilyKey)
                && (productBuild == nil || $0.productBuild == productBuild)
        }
        let durations = matching.compactMap { record
            -> TimeInterval? in
            guard record.outcome == .success,
                  record.recordSource == .nativeV1703Verified,
                  record.verificationComplete,
                  let duration = record.lifecycle.processWallDurationSeconds,
                  duration.isFinite,
                  duration >= 0 else {
                return nil
            }
            return duration
        }.sorted()
        let average = durations.isEmpty
            ? nil
            : durations.reduce(0, +) / Double(durations.count)
        let median: TimeInterval? = {
            guard !durations.isEmpty else { return nil }
            let middle = durations.count / 2
            if durations.count.isMultiple(of: 2) {
                return (durations[middle - 1] + durations[middle]) / 2
            }
            return durations[middle]
        }()
        return RestoreHistoryStatistics(
            totalRestoreCount: matching.count,
            successCount: matching.filter { $0.outcome == .success }.count,
            failureCount: matching.filter { $0.outcome == .failure }.count,
            canceledCount: matching.filter { $0.outcome == .canceled }.count,
            unknownCount: matching.filter { $0.outcome == .unknown }.count,
            trustedRuntimeSampleCount: durations.count,
            averageDurationSeconds: average,
            medianDurationSeconds: median)
    }

    func firmwareUsageRecords() async throws -> [FirmwareUsageRecord] {
        try ensureLoaded()
        return storedRecords.compactMap { record in
            guard record.operationType == .restore,
                  record.outcome == .success,
                  record.recordSource == .nativeV1703Verified,
                  record.verificationComplete,
                  let candidateID = record.firmwareLibraryEntryID,
                  let modelFamilyKey = record.modelFamilyKey else {
                return nil
            }
            return FirmwareUsageRecord(
                candidateID: candidateID,
                modelFamilyKey: modelFamilyKey,
                outcome: .success,
                source: .nativeV1703Verified,
                verificationComplete: true,
                occurredAt: record.lifecycle.outcomeConfirmed?.wallTime
                    ?? record.lifecycle.userConfirmed.wallTime)
        }
    }

    private func ensureLoaded() throws {
        if let loadFailure {
            throw loadFailure
        }
        guard !loaded else { return }
        loaded = true
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let document = try decoder.decode(Document.self, from: data)
            guard (1...Self.schemaVersion).contains(
                document.schemaVersion) else {
                let error = RestoreHistoryStoreError.unsupportedSchema(
                    document.schemaVersion)
                loadFailure = error
                throw error
            }
            storedRecords = document.records
        } catch let error as RestoreHistoryStoreError {
            throw error
        } catch {
            loadFailure = .corrupt
            throw RestoreHistoryStoreError.corrupt
        }
    }

    private func persist() throws {
        if let loadFailure {
            throw loadFailure
        }
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(Document(
                schemaVersion: Self.schemaVersion,
                records: sortedRecords()))
            try data.write(to: fileURL, options: .atomic)
        } catch let error as RestoreHistoryStoreError {
            throw error
        } catch {
            throw RestoreHistoryStoreError.unavailable
        }
    }

    private func sortedRecords() -> [RestoreHistoryRecord] {
        storedRecords.sorted {
            if $0.lifecycle.userConfirmed.wallTime
                != $1.lifecycle.userConfirmed.wallTime {
                return $0.lifecycle.userConfirmed.wallTime
                    < $1.lifecycle.userConfirmed.wallTime
            }
            return $0.taskID.uuidString < $1.taskID.uuidString
        }
    }

    private static func bounded(_ value: String, utf8Limit: Int) -> String {
        guard value.utf8.count > utf8Limit else { return value }
        var bytes = Data(value.utf8).prefix(utf8Limit)
        while !bytes.isEmpty,
              String(data: bytes, encoding: .utf8) == nil {
            bytes = bytes.dropLast()
        }
        return String(data: bytes, encoding: .utf8) ?? ""
    }
}

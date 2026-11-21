import CryptoKit
import Darwin
import Foundation

enum DirectorySyncLevel: Codable, Equatable, Sendable {
    case full
    case standard
    case unsupported(errno: Int32)
    case failed(errno: Int32)

    private enum CodingKeys: String, CodingKey {
        case kind
        case errno
    }

    private enum Kind: String, Codable {
        case full = "FULL"
        case standard = "STANDARD"
        case unsupported = "UNSUPPORTED"
        case failed = "FAILED"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .full:
            self = .full
        case .standard:
            self = .standard
        case .unsupported:
            self = .unsupported(
                errno: try container.decode(
                    Int32.self,
                    forKey: .errno))
        case .failed:
            self = .failed(
                errno: try container.decode(
                    Int32.self,
                    forKey: .errno))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self)
        switch self {
        case .full:
            try container.encode(Kind.full, forKey: .kind)
        case .standard:
            try container.encode(Kind.standard, forKey: .kind)
        case .unsupported(let code):
            try container.encode(Kind.unsupported, forKey: .kind)
            try container.encode(code, forKey: .errno)
        case .failed(let code):
            try container.encode(Kind.failed, forKey: .kind)
            try container.encode(code, forKey: .errno)
        }
    }

    var isDurable: Bool {
        switch self {
        case .full, .standard:
            return true
        case .unsupported, .failed:
            return false
        }
    }
}

struct RestoreDirectorySynchronizer: Sendable {
    let synchronize: @Sendable (URL) -> DirectorySyncLevel

    static func simulated(
        _ level: DirectorySyncLevel
    ) -> RestoreDirectorySynchronizer {
        RestoreDirectorySynchronizer { _ in level }
    }

    static let live = RestoreDirectorySynchronizer {
        Self.synchronizeDirectory($0)
    }

    private static func synchronizeDirectory(
        _ url: URL
    ) -> DirectorySyncLevel {
        let descriptor = open(
            url.path,
            O_RDONLY | O_DIRECTORY)
        guard descriptor >= 0 else {
            return .failed(errno: errno)
        }
        defer { close(descriptor) }

        if fcntl(descriptor, F_FULLFSYNC) == 0 {
            return .full
        }
        let fullSyncErrno = errno
        if ![EINVAL, ENOTSUP, ENOSYS].contains(fullSyncErrno) {
            return .failed(errno: fullSyncErrno)
        }
        if fsync(descriptor) == 0 {
            return .standard
        }
        let standardErrno = errno
        if [EINVAL, ENOTSUP, ENOSYS].contains(standardErrno) {
            return .unsupported(errno: standardErrno)
        }
        return .failed(errno: standardErrno)
    }
}

enum RestoreLogRetentionError: Error, Equatable {
    case destinationExists
    case unsafePath(String)
    case missingRequiredFile(String)
    case verificationFailed(String)
    case publicationFailed(Int32)
    case unsupportedSchema(Int)
    case corruptManifest
    case unavailable
    case cannotEncode
    case pendingExportProtectionPersisted
    case pendingExportProtectionNotPersisted
}

struct RestoreArchiveCandidate: Equatable, Sendable {
    let taskID: UUID
    let attemptID: UUID
    let targetDisplayName: String
    let modelFamilyKey: ModelFamilyKey?
    let modelYear: String?
    let productVersion: String?
    let productBuild: String?
    let outcome: RestoreOutcome
    let liveConfirmed: Bool
    let tailComplete: Bool
    let rawWriteComplete: Bool
    let summaryComplete: Bool
    let manuallyLocked: Bool
    let linkedTaskIDs: [UUID]
    let linkedRLMSessionID: String?
    let generatedAt: Date

    var baselineEligible: Bool {
        outcome == .success
            && liveConfirmed
            && modelFamilyKey != nil
            && tailComplete
            && rawWriteComplete
            && summaryComplete
    }
}

struct RestoreArchiveManifestFile: Codable, Equatable, Sendable {
    let relativePath: String
    let sizeBytes: Int64
    let sha256: String
}

struct RestoreArchiveManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let archiveID: String
    let taskID: UUID
    let attemptID: UUID
    let createdAt: String
    let outcome: RestoreOutcome
    let modelFamilyKey: String?
    let rawEvidenceComplete: Bool
    let baselineEligible: Bool?
    let directorySyncLevel: DirectorySyncLevel
    let files: [RestoreArchiveManifestFile]
}

struct RestoreArchiveRecord: Codable, Equatable, Sendable {
    let archiveID: String
    let taskID: UUID
    let attemptID: UUID
    let directoryPath: String
    let manifestPath: String
    let manifestSHA256: String
    let outcome: RestoreOutcome
    let modelFamilyKey: String?
    let publishedAt: Date
    let directorySyncLevel: DirectorySyncLevel
    let localStagingRetained: Bool
    let baselineEligible: Bool
}

struct RestoreArchivePublication: Equatable, Sendable {
    let archiveID: String
    let finalDirectory: URL
    let incompleteDirectory: URL
    let manifestURL: URL
    let manifestSHA256: String
    let directorySyncLevel: DirectorySyncLevel
    let localStagingRetained: Bool
    let record: RestoreArchiveRecord
}

protocol RestoreArchivePublishing: Sendable {
    func publish(
        stagingDirectory: URL,
        destinationRoot: URL,
        candidate: RestoreArchiveCandidate
    ) async throws -> RestoreArchivePublication
}

enum RestoreLogArchiveNaming {
    static func directoryName(
        candidate: RestoreArchiveCandidate
    ) -> String {
        let model = safe(
            candidate.modelFamilyKey?.rawValue ?? "未知",
            fallback: "未知")
        let year = safe(
            candidate.modelYear ?? "未知",
            fallback: "未知")
        let flashYear = String(
            Calendar(identifier: .gregorian).component(
                .year,
                from: candidate.generatedAt))
        let os = safe(
            candidate.productVersion ?? "未知",
            fallback: "未知")
        let build = safe(
            candidate.productBuild ?? "未知",
            fallback: "未知")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let time = formatter.string(from: candidate.generatedAt)
        let shortID = candidate.taskID.uuidString
            .replacingOccurrences(
                of: "-",
                with: "")
            .prefix(8)
        let suffix = "_\(time)_\(candidate.outcome.rawValue)_\(shortID)"
        let prefix = [
            model,
            year,
            flashYear,
            "macOS\(os)",
            "Build\(build)"
        ].joined(separator: "_")
        return boundedUTF8(
            prefix: prefix,
            suffix: suffix,
            limit: 175)
    }

    private static func safe(
        _ raw: String,
        fallback: String
    ) -> String {
        let normalized = raw.precomposedStringWithCanonicalMapping
        let scalars = normalized.unicodeScalars.map { scalar in
            let allowed =
                (scalar.value >= 0x30 && scalar.value <= 0x39)
                || (scalar.value >= 0x41 && scalar.value <= 0x5A)
                || (scalar.value >= 0x61 && scalar.value <= 0x7A)
                || scalar == "."
                || scalar == "_"
                || scalar == "-"
                || (scalar.value >= 0x4E00
                    && scalar.value <= 0x9FFF)
            return allowed ? Character(String(scalar)) : "_"
        }
        let collapsed = String(scalars)
            .replacingOccurrences(
                of: "_+",
                with: "_",
                options: .regularExpression)
            .trimmingCharacters(
                in: CharacterSet(charactersIn: "._-"))
        return collapsed.isEmpty ? fallback : collapsed
    }

    private static func boundedUTF8(
        prefix: String,
        suffix: String,
        limit: Int
    ) -> String {
        var prefix = prefix
        while (prefix + suffix).utf8.count > limit,
              !prefix.isEmpty {
            prefix.removeLast()
        }
        let value = prefix.isEmpty ? suffix : prefix + suffix
        return String(value.prefix(limit))
            .precomposedStringWithCanonicalMapping
    }
}

struct RestoreSuccessBaseline: Codable, Equatable, Sendable {
    let id: String
    let archiveID: String
    let modelFamilyKey: ModelFamilyKey
    let createdAt: Date
    let manuallyLocked: Bool
}

struct RestoreSuccessBaselineDecision: Equatable, Sendable {
    let retainIDs: [String]
    let removeIDs: [String]
}

enum RestoreSuccessBaselinePolicy {
    static func decide(
        candidateID: String,
        modelFamilyKey: ModelFamilyKey,
        existing: [RestoreSuccessBaseline],
        candidateEligible: Bool
    ) -> RestoreSuccessBaselineDecision {
        let matching = existing
            .filter { $0.modelFamilyKey == modelFamilyKey }
            .sorted { $0.createdAt < $1.createdAt }
        guard candidateEligible else {
            return RestoreSuccessBaselineDecision(
                retainIDs: matching.map(\.id),
                removeIDs: [])
        }
        if matching.count < 2 {
            return RestoreSuccessBaselineDecision(
                retainIDs: matching.map(\.id) + [candidateID],
                removeIDs: [])
        }
        guard let removable = matching.first(where: {
            !$0.manuallyLocked
        }) else {
            return RestoreSuccessBaselineDecision(
                retainIDs: matching.map(\.id),
                removeIDs: [])
        }
        let retained = matching
            .filter { $0.id != removable.id }
            .map(\.id) + [candidateID]
        return RestoreSuccessBaselineDecision(
            retainIDs: retained,
            removeIDs: [removable.id])
    }
}

struct RestoreEvidenceExportRecord: Codable, Equatable, Sendable {
    let exportID: String
    let exportPath: String
    let device: UInt64
    let inode: UInt64
    let sizeBytes: Int64
    let exportedAt: Date
    let zipSHA256: String
    let linkedSessionID: String
    let linkedTaskIDs: [UUID]
    let protected: Bool
}

struct RestorePendingExportProtection: Codable, Equatable, Sendable {
    let markerID: String
    let exportPath: String
    let linkedSessionID: String
    let linkedTaskIDs: [UUID]
    let createdAt: Date
}

enum RestoreRLMSessionProtectionStatus: String, Codable, Equatable, Sendable {
    case eligible = "ELIGIBLE"
    case protected = "PROTECTED"
    case protectedUnknown = "PROTECTED_UNKNOWN"
}

struct RestoreRLMSessionProtection: Codable, Equatable, Sendable {
    let sessionID: String
    let ownership: RestoreRLMOwnership
    let linkedTaskIDs: [UUID]
    let linkedTaskOutcomes: [RestoreOutcome]
    let manuallyLocked: Bool
    let hasExportedBundle: Bool
    let recording: Bool
    let finalizing: Bool
    let historyComplete: Bool
    let lifecycleOwnerTaskID: UUID?

    init(
        sessionID: String,
        ownership: RestoreRLMOwnership,
        linkedTaskIDs: [UUID],
        linkedTaskOutcomes: [RestoreOutcome],
        manuallyLocked: Bool,
        hasExportedBundle: Bool,
        recording: Bool,
        finalizing: Bool,
        historyComplete: Bool,
        lifecycleOwnerTaskID: UUID? = nil
    ) {
        self.sessionID = sessionID
        self.ownership = ownership
        self.linkedTaskIDs = linkedTaskIDs
        self.linkedTaskOutcomes = linkedTaskOutcomes
        self.manuallyLocked = manuallyLocked
        self.hasExportedBundle = hasExportedBundle
        self.recording = recording
        self.finalizing = finalizing
        self.historyComplete = historyComplete
        self.lifecycleOwnerTaskID = lifecycleOwnerTaskID
    }
}

struct RestoreRLMSessionProtectionResult: Equatable, Sendable {
    let status: RestoreRLMSessionProtectionStatus
    let reason: String
}

enum RestoreRLMSessionProtectionPolicy {
    static func evaluate(
        _ session: RestoreRLMSessionProtection
    ) -> RestoreRLMSessionProtectionResult {
        if session.recording {
            return protected("RECORDING")
        }
        if session.finalizing {
            return protected("FINALIZING")
        }
        if !session.historyComplete
            || session.ownership == .unavailable {
            return RestoreRLMSessionProtectionResult(
                status: .protectedUnknown,
                reason: "PROTECTED_UNKNOWN")
        }
        if session.ownership == .manualUserOwned {
            return protected("MANUAL_USER_OWNED")
        }
        if session.manuallyLocked {
            return protected("MANUAL_LOCK")
        }
        if session.hasExportedBundle {
            return protected("EVIDENCE_EXPORTED")
        }
        if session.linkedTaskOutcomes.contains(where: {
            $0 != .success
        }) {
            return protected("LINKED_TASK_NOT_SUCCESS")
        }
        return RestoreRLMSessionProtectionResult(
            status: .eligible,
            reason: "")
    }

    private static func protected(
        _ reason: String
    ) -> RestoreRLMSessionProtectionResult {
        RestoreRLMSessionProtectionResult(
            status: .protected,
            reason: reason)
    }
}

private struct RestoreRetentionDocument: Codable {
    var schemaVersion = 1
    var archives: [RestoreArchiveRecord] = []
    var baselines: [RestoreSuccessBaseline] = []
    var exports: [RestoreEvidenceExportRecord] = []
    var sessions: [RestoreRLMSessionProtection] = []
}

actor RestoreLogRetentionStore {
    static let shared = RestoreLogRetentionStore()

    private let fileURL: URL
    private var loaded = false
    private var loadFailure: RestoreLogRetentionError?
    private var document = RestoreRetentionDocument()
    private var exportProtectionFailClosed = false

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
            ?? AppSupportLocations.directory()
                .appendingPathComponent(
                    "RestoreHistory",
                    isDirectory: true)
                .appendingPathComponent(
                    "retention-manifest-v1.json")
    }

    func archives() async throws -> [RestoreArchiveRecord] {
        try ensureLoaded()
        return document.archives.sorted {
            $0.publishedAt < $1.publishedAt
        }
    }

    func exports() async throws -> [RestoreEvidenceExportRecord] {
        try ensureLoaded()
        return document.exports
    }

    func baselines() async throws -> [RestoreSuccessBaseline] {
        try ensureLoaded()
        return document.baselines
    }

    func manuallyLockedArchiveIDs() async throws -> Set<String> {
        try ensureLoaded()
        return Set(
            document.baselines
                .filter(\.manuallyLocked)
                .map(\.archiveID))
    }

    func sessions() async throws -> [RestoreRLMSessionProtection] {
        try ensureLoaded()
        return document.sessions
    }

    func registerSessionProtection(
        _ session: RestoreRLMSessionProtection
    ) throws {
        try ensureLoaded()
        try transaction {
            if let index = document.sessions.firstIndex(where: {
                $0.sessionID == session.sessionID
            }) {
                let existing = document.sessions[index]
                var taskPairs:
                    [(UUID, RestoreOutcome)] = []
                for pair in zip(
                    existing.linkedTaskIDs,
                    existing.linkedTaskOutcomes) {
                    taskPairs.append(pair)
                }
                for pair in zip(
                    session.linkedTaskIDs,
                    session.linkedTaskOutcomes) {
                    if !taskPairs.contains(where: {
                        $0.0 == pair.0 && $0.1 == pair.1
                    }) {
                        taskPairs.append(pair)
                    }
                }
                document.sessions[index] =
                    RestoreRLMSessionProtection(
                        sessionID: session.sessionID,
                        ownership:
                            existing.ownership == .manualUserOwned
                            || session.ownership == .manualUserOwned
                            ? .manualUserOwned
                            : (existing.ownership == .restoreOwned
                                || session.ownership == .restoreOwned
                                ? .restoreOwned
                                : .unavailable),
                        linkedTaskIDs: taskPairs.map(\.0),
                        linkedTaskOutcomes: taskPairs.map(\.1),
                        manuallyLocked:
                            existing.manuallyLocked
                            || session.manuallyLocked,
                        hasExportedBundle:
                            existing.hasExportedBundle
                            || session.hasExportedBundle,
                        recording:
                            existing.recording || session.recording,
                        finalizing:
                            existing.finalizing || session.finalizing,
                        historyComplete:
                            existing.historyComplete
                            && session.historyComplete,
                        lifecycleOwnerTaskID:
                            existing.lifecycleOwnerTaskID
                            ?? session.lifecycleOwnerTaskID)
            } else {
                document.sessions.append(session)
            }
        }
    }

    func setArchiveLocked(
        archiveID: String,
        locked: Bool
    ) throws {
        try ensureLoaded()
        guard let archive = document.archives.first(where: {
            $0.archiveID == archiveID
        }),
        archive.baselineEligible,
        let rawModelKey = archive.modelFamilyKey,
        let modelFamilyKey =
            ModelFamilyKey(rawValue: rawModelKey) else {
            return
        }
        let candidateID = "baseline-\(archiveID)"
        try transaction {
            if locked {
                if let index = document.baselines.firstIndex(where: {
                    $0.id == candidateID
                }) {
                    let existing = document.baselines[index]
                    document.baselines[index] =
                        RestoreSuccessBaseline(
                            id: existing.id,
                            archiveID: existing.archiveID,
                            modelFamilyKey:
                                existing.modelFamilyKey,
                            createdAt: existing.createdAt,
                            manuallyLocked: true)
                } else {
                    let decision =
                        RestoreSuccessBaselinePolicy.decide(
                            candidateID: candidateID,
                            modelFamilyKey: modelFamilyKey,
                            existing: document.baselines,
                            candidateEligible: true)
                    document.baselines.removeAll {
                        decision.removeIDs.contains($0.id)
                    }
                    if decision.retainIDs.contains(candidateID) {
                        document.baselines.append(
                            RestoreSuccessBaseline(
                                id: candidateID,
                                archiveID: archiveID,
                                modelFamilyKey: modelFamilyKey,
                                createdAt: archive.publishedAt,
                                manuallyLocked: true))
                    }
                }
            } else {
                if let index = document.baselines.firstIndex(where: {
                    $0.id == candidateID
                }) {
                    let existing = document.baselines[index]
                    document.baselines[index] =
                        RestoreSuccessBaseline(
                            id: existing.id,
                            archiveID: existing.archiveID,
                            modelFamilyKey:
                                existing.modelFamilyKey,
                            createdAt: existing.createdAt,
                            manuallyLocked: false)
                }
                let matching = document.baselines
                    .filter { $0.modelFamilyKey == modelFamilyKey }
                    .sorted { $0.createdAt > $1.createdAt }
                let retainedIDs = Set(
                    matching.prefix(2).map(\.id))
                document.baselines.removeAll {
                    $0.modelFamilyKey == modelFamilyKey
                        && !retainedIDs.contains($0.id)
                }
            }
        }
    }

    @discardableResult
    func setLocalStagingRetained(
        archiveID: String,
        retained: Bool
    ) throws -> RestoreArchiveRecord? {
        try ensureLoaded()
        guard let index = document.archives.firstIndex(where: {
            $0.archiveID == archiveID
        }) else {
            return nil
        }
        return try transaction {
            let existing = document.archives[index]
            let updated = RestoreArchiveRecord(
                archiveID: existing.archiveID,
                taskID: existing.taskID,
                attemptID: existing.attemptID,
                directoryPath: existing.directoryPath,
                manifestPath: existing.manifestPath,
                manifestSHA256: existing.manifestSHA256,
                outcome: existing.outcome,
                modelFamilyKey: existing.modelFamilyKey,
                publishedAt: existing.publishedAt,
                directorySyncLevel:
                    existing.directorySyncLevel,
                localStagingRetained: retained,
                baselineEligible: existing.baselineEligible)
            document.archives[index] = updated
            return updated
        }
    }

    @discardableResult
    func registerArchive(
        _ record: RestoreArchiveRecord,
        candidate: RestoreArchiveCandidate
    ) throws -> RestoreArchiveRecord {
        try ensureLoaded()
        if let existing = document.archives.first(where: {
            $0.archiveID == record.archiveID
        }) {
            return existing
        }
        return try transaction {
            document.archives.append(record)
            reconcileBaseline(
                for: record,
                manuallyLocked: candidate.manuallyLocked)
            return record
        }
    }

    @discardableResult
    func registerExport(
        exportURL: URL,
        linkedSessionID: String,
        linkedTaskIDs: [UUID]
    ) throws -> RestoreEvidenceExportRecord {
        try ensureLoaded()
        let identity = try RestoreFileSystemInspector.identity(
            at: exportURL,
            requireRegularFile: true)
        let record = RestoreEvidenceExportRecord(
            exportID: UUID().uuidString,
            exportPath: exportURL.standardizedFileURL.path,
            device: identity.device,
            inode: identity.inode,
            sizeBytes: identity.sizeBytes,
            exportedAt: Date(),
            zipSHA256: try RestoreFileSystemInspector.sha256(
                of: exportURL),
            linkedSessionID: linkedSessionID,
            linkedTaskIDs: linkedTaskIDs,
            protected: true)
        return try transaction {
            document.exports.removeAll {
                $0.exportPath == record.exportPath
                    && $0.inode == record.inode
                    && $0.device == record.device
            }
            document.exports.append(record)
            return record
        }
    }

    func registerRecovered(
        _ manifest: RestoreArchiveManifest,
        manifestURL: URL
    ) throws {
        try ensureLoaded()
        guard !document.archives.contains(where: {
            $0.archiveID == manifest.archiveID
        }) else {
            return
        }
        let manifestSHA = try RestoreFileSystemInspector.sha256(
            of: manifestURL)
        let record = RestoreArchiveRecord(
            archiveID: manifest.archiveID,
            taskID: manifest.taskID,
            attemptID: manifest.attemptID,
            directoryPath: manifestURL
                .deletingLastPathComponent()
                .standardizedFileURL.path,
            manifestPath: manifestURL.standardizedFileURL.path,
            manifestSHA256: manifestSHA,
            outcome: manifest.outcome,
            modelFamilyKey: manifest.modelFamilyKey,
            publishedAt: ISO8601DateFormatter().date(
                from: manifest.createdAt)
                ?? Date.distantPast,
            directorySyncLevel: manifest.directorySyncLevel,
            localStagingRetained: !manifest.directorySyncLevel.isDurable,
            baselineEligible:
                manifest.baselineEligible == true)
        try transaction {
            document.archives.append(record)
            reconcileBaseline(
                for: record,
                manuallyLocked: false)
        }
    }

    func resolveOwnedSessionFinalization(
        sessionID: String,
        taskID: UUID,
        finalized: Bool
    ) throws {
        try ensureLoaded()
        guard let index = document.sessions.firstIndex(where: {
            $0.sessionID == sessionID
        }) else {
            return
        }
        let existing = document.sessions[index]
        guard existing.lifecycleOwnerTaskID == taskID else {
            return
        }
        try transaction {
            document.sessions[index] =
                RestoreRLMSessionProtection(
                    sessionID: existing.sessionID,
                    ownership: existing.ownership,
                    linkedTaskIDs: existing.linkedTaskIDs,
                    linkedTaskOutcomes:
                        existing.linkedTaskOutcomes,
                    manuallyLocked:
                        existing.manuallyLocked,
                    hasExportedBundle:
                        existing.hasExportedBundle,
                    recording: !finalized,
                    finalizing: !finalized,
                    historyComplete: finalized,
                    lifecycleOwnerTaskID:
                        existing.lifecycleOwnerTaskID)
        }
    }

    func registerExportWithFallback(
        exportURL: URL,
        linkedSessionID: String,
        linkedTaskIDs: [UUID]
    ) throws -> RestoreEvidenceExportRecord {
        exportProtectionFailClosed = true
        do {
            let record = try registerExport(
                exportURL: exportURL,
                linkedSessionID: linkedSessionID,
                linkedTaskIDs: linkedTaskIDs)
            if try pendingExportCount() == 0 {
                exportProtectionFailClosed = false
            }
            return record
        } catch {
            do {
                try enqueuePendingExport(
                    exportURL: exportURL,
                    linkedSessionID: linkedSessionID,
                    linkedTaskIDs: linkedTaskIDs)
                exportProtectionFailClosed = true
                throw RestoreLogRetentionError
                    .pendingExportProtectionPersisted
            } catch let fallbackError
                as RestoreLogRetentionError
                where fallbackError
                    == .pendingExportProtectionPersisted {
                throw fallbackError
            } catch {
                exportProtectionFailClosed = true
                throw RestoreLogRetentionError
                    .pendingExportProtectionNotPersisted
            }
        }
    }

    func exportProtectionIsFailClosed() -> Bool {
        exportProtectionFailClosed
    }

    func pendingExportCount() throws -> Int {
        let directory = pendingExportDirectory
        guard FileManager.default.fileExists(
            atPath: directory.path) else {
            return 0
        }
        var info = stat()
        guard lstat(directory.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
            throw RestoreLogRetentionError.unsafePath(
                directory.path)
        }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [])
            .filter { $0.pathExtension == "json" }
            .count
    }

    @discardableResult
    func recoverPendingExports() throws
        -> [RestoreEvidenceExportRecord] {
        let directory = pendingExportDirectory
        guard FileManager.default.fileExists(
            atPath: directory.path) else {
            return []
        }
        var directoryInfo = stat()
        guard lstat(directory.path, &directoryInfo) == 0,
              (directoryInfo.st_mode & S_IFMT) == S_IFDIR else {
            throw RestoreLogRetentionError.unsafePath(
                directory.path)
        }
        try ensureLoaded()
        var recovered: [RestoreEvidenceExportRecord] = []
        let markers = try FileManager.default
            .contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.path < $1.path }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for marker in markers {
            let identity = try RestoreFileSystemInspector.identity(
                at: marker,
                requireRegularFile: true)
            guard identity.sizeBytes > 0 else {
                throw RestoreLogRetentionError.corruptManifest
            }
            let pending = try decoder.decode(
                RestorePendingExportProtection.self,
                from: Data(contentsOf: marker))
            let record = try registerExport(
                exportURL: URL(
                    fileURLWithPath: pending.exportPath),
                linkedSessionID: pending.linkedSessionID,
                linkedTaskIDs: pending.linkedTaskIDs)
            try FileManager.default.removeItem(at: marker)
            recovered.append(record)
        }
        if try pendingExportCount() == 0 {
            exportProtectionFailClosed = false
        }
        return recovered
    }

    private var pendingExportDirectory: URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent(
                "export-protection-pending",
                isDirectory: true)
    }

    private func enqueuePendingExport(
        exportURL: URL,
        linkedSessionID: String,
        linkedTaskIDs: [UUID]
    ) throws {
        let directory = pendingExportDirectory
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        let marker = RestorePendingExportProtection(
            markerID: UUID().uuidString,
            exportPath: exportURL.standardizedFileURL.path,
            linkedSessionID: linkedSessionID,
            linkedTaskIDs: linkedTaskIDs,
            createdAt: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(marker)
        let markerURL = directory.appendingPathComponent(
            "pending-\(marker.markerID).json")
        try writeSynchronizedData(data, to: markerURL)
    }

    private func transaction<T>(
        _ mutation: () throws -> T
    ) throws -> T {
        let previous = document
        do {
            let value = try mutation()
            try persist()
            return value
        } catch {
            document = previous
            throw error
        }
    }

    private func reconcileBaseline(
        for record: RestoreArchiveRecord,
        manuallyLocked: Bool
    ) {
        guard record.baselineEligible,
              let rawModelKey = record.modelFamilyKey,
              let modelFamilyKey =
                ModelFamilyKey(rawValue: rawModelKey) else {
            return
        }
        let candidateID = "baseline-\(record.archiveID)"
        let decision = RestoreSuccessBaselinePolicy.decide(
            candidateID: candidateID,
            modelFamilyKey: modelFamilyKey,
            existing: document.baselines,
            candidateEligible: true)
        document.baselines.removeAll {
            decision.removeIDs.contains($0.id)
        }
        guard decision.retainIDs.contains(candidateID),
              !document.baselines.contains(where: {
                  $0.id == candidateID
              }) else {
            return
        }
        document.baselines.append(
            RestoreSuccessBaseline(
                id: candidateID,
                archiveID: record.archiveID,
                modelFamilyKey: modelFamilyKey,
                createdAt: record.publishedAt,
                manuallyLocked: manuallyLocked))
    }

    private func ensureLoaded() throws {
        if let loadFailure { throw loadFailure }
        guard !loaded else { return }
        loaded = true
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        do {
            var info = stat()
            guard lstat(fileURL.path, &info) == 0,
                  (info.st_mode & S_IFMT) == S_IFREG else {
                throw RestoreLogRetentionError.unsafePath(
                    fileURL.path)
            }
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(
                RestoreRetentionDocument.self,
                from: data)
            guard decoded.schemaVersion == 1 else {
                let error = RestoreLogRetentionError.unsupportedSchema(
                    decoded.schemaVersion)
                loadFailure = error
                throw error
            }
            document = decoded
        } catch let error as RestoreLogRetentionError {
            loadFailure = error
            throw error
        } catch {
            loadFailure = .corruptManifest
            throw RestoreLogRetentionError.corruptManifest
        }
    }

    private func persist() throws {
        if let loadFailure { throw loadFailure }
        do {
            if FileManager.default.fileExists(
                atPath: fileURL.path) {
                var info = stat()
                guard lstat(fileURL.path, &info) == 0,
                      (info.st_mode & S_IFMT) == S_IFREG else {
                    throw RestoreLogRetentionError.unsafePath(
                        fileURL.path)
                }
            }
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(document)
            try writeSynchronizedReplacement(
                data,
                to: fileURL)
        } catch let error as RestoreLogRetentionError {
            throw error
        } catch {
            throw RestoreLogRetentionError.unavailable
        }
    }

    private func writeSynchronizedData(
        _ data: Data,
        to url: URL
    ) throws {
        try data.write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }

    private func writeSynchronizedReplacement(
        _ data: Data,
        to url: URL
    ) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(
                to: temporary,
                options: .withoutOverwriting)
            let handle = try FileHandle(
                forWritingTo: temporary)
            do {
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            guard rename(
                temporary.path,
                url.path) == 0 else {
                throw POSIXError(
                    POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? FileManager.default.removeItem(
                at: temporary)
            throw error
        }
    }
}

actor RestoreLogRetentionManager {
    private let localStagingRoot: URL
    private let retentionStore: RestoreLogRetentionStore
    private let directorySynchronizer: RestoreDirectorySynchronizer

    init(
        localStagingRoot: URL,
        retentionManifestURL: URL? = nil,
        directorySynchronizer:
            RestoreDirectorySynchronizer = .live
    ) {
        self.localStagingRoot = localStagingRoot.standardizedFileURL
        retentionStore = RestoreLogRetentionStore(
            fileURL: retentionManifestURL)
        self.directorySynchronizer = directorySynchronizer
    }

    func publish(
        stagingDirectory: URL,
        destinationRoot: URL,
        candidate: RestoreArchiveCandidate
    ) async throws -> RestoreArchivePublication {
        let staging = stagingDirectory.standardizedFileURL
        let destination = destinationRoot.standardizedFileURL
        try RestoreFileSystemInspector.requireManagedDirectory(
            staging,
            root: localStagingRoot)
        try RestoreFileSystemInspector.createManagedDirectory(
            destination)

        let required = ["stdout.raw", "stderr.raw"]
        for name in required
        where !FileManager.default.fileExists(
            atPath: staging.appendingPathComponent(name).path) {
            throw RestoreLogRetentionError.missingRequiredFile(name)
        }
        let summaryURL = staging.appendingPathComponent(
            "task-summary.json")
        try writeSummary(
            candidate,
            to: summaryURL)

        let archiveID = UUID().uuidString
        let finalName = RestoreLogArchiveNaming.directoryName(
            candidate: candidate)
        var final = destination.appendingPathComponent(
            finalName,
            isDirectory: true)
        var uniqueIndex = 2
        while FileManager.default.fileExists(atPath: final.path) {
            final = destination.appendingPathComponent(
                "\(finalName)_\(uniqueIndex)",
                isDirectory: true)
            uniqueIndex += 1
            if uniqueIndex > 100 {
                throw RestoreLogRetentionError.destinationExists
            }
        }
        let incomplete = destination.appendingPathComponent(
            ".incomplete-\(candidate.taskID.uuidString)",
            isDirectory: true)
        guard !FileManager.default.fileExists(
            atPath: incomplete.path),
              !FileManager.default.fileExists(
                atPath: final.path) else {
            throw RestoreLogRetentionError.destinationExists
        }
        try FileManager.default.createDirectory(
            at: incomplete,
            withIntermediateDirectories: false)

        do {
            let names = required + ["task-summary.json"]
            for name in names {
                let source = staging.appendingPathComponent(name)
                let copy = incomplete.appendingPathComponent(name)
                try FileManager.default.copyItem(
                    at: source,
                    to: copy)
                let sourceDigest =
                    try RestoreFileSystemInspector.sha256(
                        of: source)
                let copyDigest =
                    try RestoreFileSystemInspector.sha256(
                        of: copy)
                let sourceSize =
                    try RestoreFileSystemInspector.identity(
                        at: source,
                        requireRegularFile: true).sizeBytes
                let copySize =
                    try RestoreFileSystemInspector.identity(
                        at: copy,
                        requireRegularFile: true).sizeBytes
                guard sourceDigest == copyDigest,
                      sourceSize == copySize else {
                    throw RestoreLogRetentionError.verificationFailed(
                        name)
                }
            }

            let files = try names.sorted().map { name -> RestoreArchiveManifestFile in
                let url = incomplete.appendingPathComponent(name)
                return RestoreArchiveManifestFile(
                    relativePath: name,
                    sizeBytes:
                        try RestoreFileSystemInspector.identity(
                            at: url,
                            requireRegularFile: true).sizeBytes,
                    sha256:
                        try RestoreFileSystemInspector.sha256(
                            of: url))
            }
            let provisionalSyncLevel =
                directorySynchronizer.synchronize(incomplete)
            var manifest = RestoreArchiveManifest(
                schemaVersion: 1,
                archiveID: archiveID,
                taskID: candidate.taskID,
                attemptID: candidate.attemptID,
                createdAt: ISO8601DateFormatter().string(
                    from: candidate.generatedAt),
                outcome: candidate.outcome,
                modelFamilyKey:
                    candidate.modelFamilyKey?.rawValue,
                rawEvidenceComplete:
                    candidate.rawWriteComplete
                    && candidate.tailComplete
                    && candidate.summaryComplete,
                baselineEligible:
                    candidate.baselineEligible,
                directorySyncLevel: provisionalSyncLevel,
                files: files)
            let manifestURL = incomplete.appendingPathComponent(
                "manifest.json")
            try writeAndVerifyManifest(
                manifest,
                to: manifestURL)
            let directorySyncLevel =
                directorySynchronizer.synchronize(incomplete)
            if directorySyncLevel != provisionalSyncLevel {
                manifest = RestoreArchiveManifest(
                    schemaVersion: manifest.schemaVersion,
                    archiveID: manifest.archiveID,
                    taskID: manifest.taskID,
                    attemptID: manifest.attemptID,
                    createdAt: manifest.createdAt,
                    outcome: manifest.outcome,
                    modelFamilyKey: manifest.modelFamilyKey,
                    rawEvidenceComplete:
                        manifest.rawEvidenceComplete,
                    baselineEligible:
                        manifest.baselineEligible,
                    directorySyncLevel: directorySyncLevel,
                    files: manifest.files)
                try writeAndVerifyManifest(
                    manifest,
                    to: manifestURL)
            }
            let manifestSHA =
                try RestoreFileSystemInspector.sha256(
                    of: manifestURL)

            guard renamex_np(
                incomplete.path,
                final.path,
                UInt32(RENAME_EXCL)) == 0 else {
                throw RestoreLogRetentionError.publicationFailed(
                    errno)
            }
            let parentSync = directorySynchronizer.synchronize(
                destination)
            let effectiveSync: DirectorySyncLevel = {
                if !directorySyncLevel.isDurable {
                    return directorySyncLevel
                }
                return parentSync
            }()
            let publishedManifestURL = final
                .appendingPathComponent("manifest.json")
            var record = RestoreArchiveRecord(
                archiveID: archiveID,
                taskID: candidate.taskID,
                attemptID: candidate.attemptID,
                directoryPath: final.path,
                manifestPath: publishedManifestURL.path,
                manifestSHA256: manifestSHA,
                outcome: candidate.outcome,
                modelFamilyKey:
                    candidate.modelFamilyKey?.rawValue,
                publishedAt: Date(),
                directorySyncLevel: effectiveSync,
                localStagingRetained: true,
                baselineEligible: candidate.baselineEligible)
            _ = try await retentionStore.registerArchive(
                record,
                candidate: candidate)
            var retained = true
            if effectiveSync.isDurable {
                do {
                    try FileManager.default.removeItem(at: staging)
                    retained = !FileManager.default.fileExists(
                        atPath: staging.path)
                } catch {
                    retained = true
                }
            }
            if !retained {
                record = RestoreArchiveRecord(
                    archiveID: record.archiveID,
                    taskID: record.taskID,
                    attemptID: record.attemptID,
                    directoryPath: record.directoryPath,
                    manifestPath: record.manifestPath,
                    manifestSHA256: record.manifestSHA256,
                    outcome: record.outcome,
                    modelFamilyKey: record.modelFamilyKey,
                    publishedAt: record.publishedAt,
                    directorySyncLevel:
                        record.directorySyncLevel,
                    localStagingRetained: false,
                    baselineEligible:
                        record.baselineEligible)
                if let updated =
                    try? await retentionStore
                        .setLocalStagingRetained(
                            archiveID: archiveID,
                            retained: false) {
                    record = updated
                }
            }
            return RestoreArchivePublication(
                archiveID: archiveID,
                finalDirectory: final,
                incompleteDirectory: incomplete,
                manifestURL: publishedManifestURL,
                manifestSHA256: manifestSHA,
                directorySyncLevel: effectiveSync,
                localStagingRetained: retained,
                record: record)
        } catch {
            throw error
        }
    }

    func recoverPublishedArchives(
        destinationRoot: URL
    ) async throws -> [RestoreArchiveRecord] {
        let root = destinationRoot.standardizedFileURL
        let children = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [])
        for child in children.sorted(by: {
            $0.lastPathComponent < $1.lastPathComponent
        }) {
            guard !child.lastPathComponent.hasPrefix(
                ".incomplete-") else {
                continue
            }
            guard (try? RestoreFileSystemInspector
                .requireManagedDirectory(
                    child,
                    root: root)) != nil else {
                continue
            }
            let manifestURL = child.appendingPathComponent(
                "manifest.json")
            guard FileManager.default.fileExists(
                atPath: manifestURL.path) else {
                continue
            }
            guard (try? RestoreFileSystemInspector.identity(
                at: manifestURL,
                requireRegularFile: true)) != nil else {
                continue
            }
            let decoder = JSONDecoder()
            guard let manifest = try? decoder.decode(
                RestoreArchiveManifest.self,
                from: Data(contentsOf: manifestURL)),
                  manifest.schemaVersion == 1 else {
                continue
            }
            let requiredPaths: Set<String> = [
                "stdout.raw",
                "stderr.raw",
                "task-summary.json"
            ]
            guard manifest.files.count == requiredPaths.count,
                  Set(manifest.files.map(\.relativePath))
                    == requiredPaths else {
                continue
            }
            var filesValid = true
            for file in manifest.files {
                let url = child.appendingPathComponent(
                    file.relativePath)
                guard !file.relativePath.hasPrefix("/"),
                      !URL(fileURLWithPath: file.relativePath)
                        .pathComponents
                        .contains(".."),
                      url.deletingLastPathComponent()
                        .standardizedFileURL.path
                        == child.standardizedFileURL.path else {
                    filesValid = false
                    break
                }
                guard (try? RestoreFileSystemInspector.identity(
                        at: url,
                        requireRegularFile: true).sizeBytes)
                        == file.sizeBytes,
                      (try? RestoreFileSystemInspector.sha256(of: url))
                        == file.sha256 else {
                    filesValid = false
                    break
                }
            }
            guard filesValid else { continue }
            try await retentionStore.registerRecovered(
                manifest,
                manifestURL: manifestURL)
        }
        return try await retentionStore.archives()
    }

    private func writeSummary(
        _ candidate: RestoreArchiveCandidate,
        to url: URL
    ) throws {
        let payload: [String: Any] = [
            "schemaVersion": 1,
            "taskID": candidate.taskID.uuidString,
            "attemptID": candidate.attemptID.uuidString,
            "modelFamilyKey":
                candidate.modelFamilyKey?.rawValue ?? "未知",
            "modelYear": candidate.modelYear ?? "未知",
            "productVersion":
                candidate.productVersion ?? "未知",
            "productBuild":
                candidate.productBuild ?? "未知",
            "outcome": candidate.outcome.rawValue,
            "liveConfirmed": candidate.liveConfirmed,
            "tailComplete": candidate.tailComplete,
            "rawWriteComplete": candidate.rawWriteComplete
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys])
        try writeSynchronizedData(data, to: url)
        let decoded = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)) as? [String: Any]
        guard decoded?["taskID"] as? String
                == candidate.taskID.uuidString,
              decoded?["attemptID"] as? String
                == candidate.attemptID.uuidString,
              decoded?["rawWriteComplete"] as? Bool
                == candidate.rawWriteComplete else {
            throw RestoreLogRetentionError.verificationFailed(
                "task-summary.json")
        }
    }

    private func writeAndVerifyManifest(
        _ manifest: RestoreArchiveManifest,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try writeSynchronizedData(data, to: url)
        let decoded = try JSONDecoder().decode(
            RestoreArchiveManifest.self,
            from: Data(contentsOf: url))
        guard decoded == manifest else {
            throw RestoreLogRetentionError.verificationFailed(
                "manifest.json")
        }
    }

    private func writeSynchronizedData(
        _ data: Data,
        to url: URL
    ) throws {
        try data.write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }
}

extension RestoreLogRetentionManager: RestoreArchivePublishing {}

enum RestoreLogCategory: String, Codable, CaseIterable, Sendable {
    case activeFinalizing = "ACTIVE_FINALIZING"
    case manualLockedOrExported = "MANUAL_LOCKED_OR_EXPORTED"
    case trustedSuccessBaseline = "TRUSTED_SUCCESS_BASELINE"
    case taskSummaryHistory = "TASK_SUMMARY_HISTORY"
    case unownedFailureOrUnknown = "UNOWNED_FAILURE_OR_UNKNOWN"
    case ordinaryRaw = "ORDINARY_RAW"
    case cleanupEligibleRLMOrTemporary =
        "CLEANUP_ELIGIBLE_RLM_OR_TEMPORARY"

    var protectionPriority: Int {
        switch self {
        case .activeFinalizing: return 700
        case .manualLockedOrExported: return 600
        case .trustedSuccessBaseline: return 500
        case .taskSummaryHistory: return 400
        case .unownedFailureOrUnknown: return 300
        case .ordinaryRaw: return 200
        case .cleanupEligibleRLMOrTemporary: return 100
        }
    }
}

struct RestoreManagedLogFile: Sendable {
    let url: URL
    let category: RestoreLogCategory
    let protected: Bool
    let reason: String
}

struct RestoreLogFileIdentity: Codable, Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let sizeBytes: Int64
    let allocatedBytes: Int64
    let modifiedNanoseconds: Int64
    let changedNanoseconds: Int64
}

struct RestoreStorageItem: Equatable, Sendable {
    let url: URL
    let identity: RestoreLogFileIdentity
    let category: RestoreLogCategory
    let protected: Bool
    let reason: String
}

struct RestoreStoragePreview: Equatable, Sendable {
    let items: [RestoreStorageItem]
    let managedRoots: [URL]
    let scanComplete: Bool
    let issues: [String]

    init(
        items: [RestoreStorageItem],
        managedRoots: [URL] = [],
        scanComplete: Bool = true,
        issues: [String] = []
    ) {
        self.items = items
        self.managedRoots = managedRoots
        self.scanComplete = scanComplete
        self.issues = issues
    }

    var candidateCount: Int {
        items.filter { !$0.protected }.count
    }

    var logicalBytes: Int64 {
        items.reduce(0) { $0 + $1.identity.sizeBytes }
    }

    var allocatedBytes: Int64 {
        items.reduce(0) { $0 + $1.identity.allocatedBytes }
    }
}

struct RestoreManagedStorageRoots: Sendable {
    let rawArchives: URL
    let localStaging: URL
    let rlmSessions: URL
    let evidencePackages: URL
    let history: URL

    var all: [URL] {
        [
            rawArchives,
            localStaging,
            rlmSessions,
            evidencePackages,
            history
        ]
    }
}

struct RestoreLogStorageCatalog: Sendable {
    let retentionStore: RestoreLogRetentionStore

    init(
        retentionStore: RestoreLogRetentionStore = .shared
    ) {
        self.retentionStore = retentionStore
    }

    func preview(
        roots: RestoreManagedStorageRoots,
        retentionDays: Int,
        activeAttemptIDs: Set<UUID> = [],
        now: Date = Date()
    ) async throws -> RestoreStoragePreview {
        let archives = try await retentionStore.archives()
        let baselines = try await retentionStore.baselines()
        let exports = try await retentionStore.exports()
        let sessions = try await retentionStore.sessions()
        let pendingExportProtections =
            try await retentionStore.pendingExportCount()
        let exportProtectionFailClosed =
            await retentionStore.exportProtectionIsFailClosed()
        let exportedSessionIDs = Set(
            exports.map(\.linkedSessionID))
        var descriptors: [RestoreManagedLogFile] = []
        var issues: [String] = []
        if pendingExportProtections > 0 {
            issues.append(
                "\(pendingExportProtections) evidence export protection record(s) pending retry")
        }
        if exportProtectionFailClosed {
            issues.append(
                "evidence export protection failed closed in this process")
        }

        for root in roots.all {
            guard FileManager.default.fileExists(
                atPath: root.path) else {
                let parent = root.deletingLastPathComponent()
                if !FileManager.default.fileExists(
                    atPath: parent.path) {
                    issues.append(
                        "\(root.path): configured volume or parent is unavailable")
                }
                continue
            }
            var rootInfo = stat()
            guard lstat(root.path, &rootInfo) == 0,
                  (rootInfo.st_mode & S_IFMT) == S_IFDIR else {
                issues.append(
                    "\(root.path): managed root is not a safe directory")
                continue
            }
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                ],
                options: [],
                errorHandler: { url, error in
                    issues.append(
                        "\(url.path): \(error.localizedDescription)")
                    return true
                })
            guard let enumerator else {
                issues.append(
                    "\(root.path): managed root could not be enumerated")
                continue
            }
            while let url = enumerator.nextObject() as? URL {
                let values: URLResourceValues
                do {
                    values = try url.resourceValues(
                        forKeys: [
                            .isRegularFileKey,
                            .isSymbolicLinkKey
                        ])
                } catch {
                    issues.append(
                        "\(url.path): \(error.localizedDescription)")
                    continue
                }
                guard values.isRegularFile == true,
                      values.isSymbolicLink != true else {
                    continue
                }
                descriptors.append(
                    describe(
                        url: url,
                        roots: roots,
                        archives: archives,
                        baselines: baselines,
                        exportedSessionIDs: exportedSessionIDs,
                        sessions: sessions,
                        retentionDays: retentionDays,
                        activeAttemptIDs: activeAttemptIDs,
                        now: now))
            }
        }
        let scanned = try RestoreLogStorageScanner().preview(
            managedRoots: roots.all,
            files: descriptors)
        return RestoreStoragePreview(
            items: scanned.items,
            managedRoots: scanned.managedRoots,
            scanComplete: issues.isEmpty,
            issues: issues.sorted())
    }

    private func describe(
        url: URL,
        roots: RestoreManagedStorageRoots,
        archives: [RestoreArchiveRecord],
        baselines: [RestoreSuccessBaseline],
        exportedSessionIDs: Set<String>,
        sessions: [RestoreRLMSessionProtection],
        retentionDays: Int,
        activeAttemptIDs: Set<UUID>,
        now: Date
    ) -> RestoreManagedLogFile {
        let path = url.standardizedFileURL.path
        if isInside(url, root: roots.evidencePackages) {
            return RestoreManagedLogFile(
                url: url,
                category: .manualLockedOrExported,
                protected: true,
                reason: "USER_EVIDENCE_PACKAGE")
        }
        if isInside(url, root: roots.history) {
            return RestoreManagedLogFile(
                url: url,
                category: .taskSummaryHistory,
                protected: true,
                reason: "LIGHTWEIGHT_HISTORY")
        }
        if isInside(url, root: roots.localStaging) {
            let relative = relativeComponents(
                from: roots.localStaging,
                to: url)
            guard let rawAttemptID = relative.first,
                  let attemptID = UUID(
                    uuidString: rawAttemptID) else {
                return RestoreManagedLogFile(
                    url: url,
                    category: .unownedFailureOrUnknown,
                    protected: true,
                    reason: "UNKNOWN_LOCAL_STAGING")
            }
            if activeAttemptIDs.contains(attemptID) {
                return RestoreManagedLogFile(
                    url: url,
                    category: .activeFinalizing,
                    protected: true,
                    reason: "ACTIVE_RESTORE_STAGING")
            }
            let referenceDate =
                archives.first(where: {
                    $0.attemptID == attemptID
                        && $0.localStagingRetained
                })?.publishedAt
                ?? (try? url.resourceValues(
                    forKeys: [.contentModificationDateKey]))
                    .flatMap(\.contentModificationDate)
                ?? Date()
            let cutoff = Calendar(identifier: .gregorian)
                .date(
                    byAdding: .day,
                    value: -max(1, retentionDays),
                    to: now)
                ?? now
            let withinRetention =
                referenceDate > cutoff
            return RestoreManagedLogFile(
                url: url,
                category: withinRetention
                    ? .unownedFailureOrUnknown
                    : .cleanupEligibleRLMOrTemporary,
                protected: withinRetention,
                reason: withinRetention
                    ? "STAGING_RETENTION_WINDOW"
                    : "STAGING_RETENTION_EXPIRED")
        }
        if isInside(url, root: roots.rlmSessions) {
            let relative = relativeComponents(
                from: roots.rlmSessions,
                to: url)
            let sessionID = relative.first ?? ""
            if exportedSessionIDs.contains(sessionID) {
                return RestoreManagedLogFile(
                    url: url,
                    category: .manualLockedOrExported,
                    protected: true,
                    reason: "EVIDENCE_EXPORTED")
            }
            if let protection = sessions.first(where: {
                $0.sessionID == sessionID
            }) {
                let evaluation =
                    RestoreRLMSessionProtectionPolicy.evaluate(
                        protection)
                let active =
                    evaluation.reason == "RECORDING"
                    || evaluation.reason == "FINALIZING"
                return RestoreManagedLogFile(
                    url: url,
                    category:
                        active
                        ? .activeFinalizing
                        : (evaluation.status == .eligible
                        ? .cleanupEligibleRLMOrTemporary
                        : .manualLockedOrExported),
                    protected:
                        evaluation.status != .eligible,
                    reason: evaluation.reason)
            }
            return RestoreManagedLogFile(
                url: url,
                category: .manualLockedOrExported,
                protected: true,
                reason: "PROTECTED_UNKNOWN")
        }
        if path.contains("/.incomplete-") {
            return RestoreManagedLogFile(
                url: url,
                category: .cleanupEligibleRLMOrTemporary,
                protected: true,
                reason: "INCOMPLETE_ARCHIVE_REQUIRES_REVIEW")
        }
        if let archive = archives.first(where: {
            path.hasPrefix(
                URL(fileURLWithPath: $0.directoryPath)
                    .standardizedFileURL.path + "/")
        }) {
            let isBaseline = baselines.contains {
                $0.archiveID == archive.archiveID
            }
            if isBaseline {
                return RestoreManagedLogFile(
                    url: url,
                    category: .trustedSuccessBaseline,
                    protected: true,
                    reason: "TRUSTED_SUCCESS_BASELINE")
            }
            if archive.outcome == .unknown
                || archive.outcome == .canceled {
                return RestoreManagedLogFile(
                    url: url,
                    category: .unownedFailureOrUnknown,
                    protected: true,
                    reason: "UNKNOWN_OR_CANCELED")
            }
            if archive.outcome == .failure {
                let cutoff = Calendar(identifier: .gregorian)
                    .date(
                        byAdding: .day,
                        value: -max(1, retentionDays),
                        to: now)
                    ?? now
                return RestoreManagedLogFile(
                    url: url,
                    category: .unownedFailureOrUnknown,
                    protected: archive.publishedAt > cutoff,
                    reason: archive.publishedAt > cutoff
                        ? "FAILURE_RETENTION_WINDOW"
                        : "FAILURE_RETENTION_EXPIRED")
            }
            return RestoreManagedLogFile(
                url: url,
                category: .ordinaryRaw,
                protected: false,
                reason: "NON_BASELINE_SUCCESS")
        }
        return RestoreManagedLogFile(
            url: url,
            category: .unownedFailureOrUnknown,
            protected: true,
            reason: "PROTECTED_UNKNOWN")
    }

    private func isInside(_ url: URL, root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return path == rootPath
            || path.hasPrefix(
                rootPath.hasSuffix("/")
                    ? rootPath
                    : rootPath + "/")
    }

    private func relativeComponents(
        from root: URL,
        to url: URL
    ) -> [String] {
        let rootComponents = root.standardizedFileURL
            .pathComponents
        let pathComponents = url.standardizedFileURL.pathComponents
        guard pathComponents.count > rootComponents.count else {
            return []
        }
        return Array(pathComponents.dropFirst(rootComponents.count))
    }
}

struct RestoreLogStorageScanner: Sendable {
    func preview(
        managedRoots: [URL],
        files: [RestoreManagedLogFile]
    ) throws -> RestoreStoragePreview {
        let roots = managedRoots.map { $0.standardizedFileURL }
        var selected: [String: RestoreStorageItem] = [:]
        for file in files {
            let url = file.url.standardizedFileURL
            try RestoreFileSystemInspector.requirePathInsideManagedRoot(
                url,
                roots: roots)
            let identity = try RestoreFileSystemInspector.identity(
                at: url,
                requireRegularFile: true)
            let key = "\(identity.device):\(identity.inode)"
            let item = RestoreStorageItem(
                url: url,
                identity: identity,
                category: file.category,
                protected: file.protected,
                reason: file.reason)
            if let existing = selected[key] {
                let category =
                    existing.category.protectionPriority
                    >= file.category.protectionPriority
                    ? existing.category
                    : file.category
                selected[key] = RestoreStorageItem(
                    url: url,
                    identity: identity,
                    category: category,
                    protected:
                        existing.protected || file.protected,
                    reason:
                        existing.protected
                        ? existing.reason
                        : file.reason)
            } else {
                selected[key] = item
            }
        }
        return RestoreStoragePreview(
            items: selected.values.sorted {
                $0.url.path < $1.url.path
            },
            managedRoots: roots,
            scanComplete: true,
            issues: [])
    }
}

struct RestoreLogCleanupReport: Equatable, Sendable {
    let deletedURLs: [URL]
    let skippedURLs: [URL]
    let allocatedBytesReleased: Int64

    var deletedCount: Int { deletedURLs.count }
    var skippedCount: Int { skippedURLs.count }
}

actor RestoreLogCleanupService {
    func execute(
        preview: RestoreStoragePreview,
        confirmed: Bool,
        protectionAtDeleteTime:
            @escaping @Sendable (URL) async -> Bool
    ) async throws -> RestoreLogCleanupReport {
        guard confirmed else {
            return RestoreLogCleanupReport(
                deletedURLs: [],
                skippedURLs: preview.items.map(\.url),
                allocatedBytesReleased: 0)
        }
        var deleted: [URL] = []
        var skipped: [URL] = []
        var released: Int64 = 0
        for item in preview.items where !item.protected {
            do {
                guard !preview.managedRoots.isEmpty else {
                    throw RestoreLogRetentionError.unsafePath(
                        item.url.path)
                }
                try RestoreFileSystemInspector
                    .requirePathInsideManagedRoot(
                        item.url,
                        roots: preview.managedRoots)
                let current =
                    try RestoreFileSystemInspector.identity(
                        at: item.url,
                        requireRegularFile: true)
                guard current.device == item.identity.device,
                      current.inode == item.identity.inode,
                      current.modifiedNanoseconds
                        == item.identity.modifiedNanoseconds,
                      current.changedNanoseconds
                        == item.identity.changedNanoseconds,
                      !(await protectionAtDeleteTime(item.url)) else {
                    skipped.append(item.url)
                    continue
                }
                try RestoreFileSystemInspector
                    .requirePathInsideManagedRoot(
                        item.url,
                        roots: preview.managedRoots)
                let afterProtectionCheck =
                    try RestoreFileSystemInspector.identity(
                        at: item.url,
                        requireRegularFile: true)
                guard afterProtectionCheck.device
                        == item.identity.device,
                      afterProtectionCheck.inode
                        == item.identity.inode,
                      afterProtectionCheck.sizeBytes
                        == item.identity.sizeBytes,
                      afterProtectionCheck.modifiedNanoseconds
                        == item.identity.modifiedNanoseconds,
                      afterProtectionCheck.changedNanoseconds
                        == item.identity.changedNanoseconds else {
                    skipped.append(item.url)
                    continue
                }
                try FileManager.default.removeItem(at: item.url)
                deleted.append(item.url)
                released += afterProtectionCheck.allocatedBytes
            } catch {
                skipped.append(item.url)
            }
        }
        skipped.append(contentsOf:
            preview.items.filter(\.protected).map(\.url))
        return RestoreLogCleanupReport(
            deletedURLs: deleted,
            skippedURLs: skipped.sorted {
                $0.path < $1.path
            },
            allocatedBytesReleased: released)
    }
}

enum RestoreFileSystemInspector {
    static func identity(
        at url: URL,
        requireRegularFile: Bool
    ) throws -> RestoreLogFileIdentity {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw RestoreLogRetentionError.unsafePath(url.path)
        }
        if requireRegularFile,
           (info.st_mode & S_IFMT) != S_IFREG {
            throw RestoreLogRetentionError.unsafePath(url.path)
        }
        return RestoreLogFileIdentity(
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            sizeBytes: Int64(info.st_size),
            allocatedBytes: Int64(info.st_blocks) * 512,
            modifiedNanoseconds:
                nanoseconds(info.st_mtimespec),
            changedNanoseconds:
                nanoseconds(info.st_ctimespec))
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(
            forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(
            upToCount: 1_048_576),
              !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func createManagedDirectory(
        _ url: URL
    ) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            var info = stat()
            guard lstat(url.path, &info) == 0,
                  (info.st_mode & S_IFMT) == S_IFDIR,
                  (try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [])) != nil else {
                throw RestoreLogRetentionError.unsafePath(url.path)
            }
            return
        }
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true)
    }

    static func requireManagedDirectory(
        _ url: URL,
        root: URL
    ) throws {
        try requirePathInsideManagedRoot(
            url,
            roots: [root])
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR,
              (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [])) != nil else {
            throw RestoreLogRetentionError.unsafePath(url.path)
        }
    }

    static func requirePathInsideManagedRoot(
        _ url: URL,
        roots: [URL]
    ) throws {
        let standardized = url.standardizedFileURL
        guard let matchedRoot = roots.first(where: {
            let root = $0.standardizedFileURL
            return standardized.path == root.path
                || standardized.path.hasPrefix(
                    root.path.hasSuffix("/")
                        ? root.path
                        : root.path + "/")
        }) else {
            throw RestoreLogRetentionError.unsafePath(
                standardized.path)
        }
        let canonicalURL = standardized
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let canonicalRoot = matchedRoot
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard canonicalURL.path == canonicalRoot.path
                || canonicalURL.path.hasPrefix(
                    canonicalRoot.path.hasSuffix("/")
                        ? canonicalRoot.path
                        : canonicalRoot.path + "/") else {
            throw RestoreLogRetentionError.unsafePath(
                standardized.path)
        }
        for root in roots {
            let rootPath = root.standardizedFileURL.path
            guard standardized.path.hasPrefix(rootPath) else {
                continue
            }
            var cursor = standardized.deletingLastPathComponent()
            while cursor.path.count >= rootPath.count {
                var info = stat()
                guard lstat(cursor.path, &info) == 0,
                      (info.st_mode & S_IFMT) == S_IFDIR else {
                    throw RestoreLogRetentionError.unsafePath(
                        cursor.path)
                }
                if cursor.path == rootPath { return }
                let parent = cursor.deletingLastPathComponent()
                if parent.path == cursor.path { break }
                cursor = parent
            }
        }
        throw RestoreLogRetentionError.unsafePath(
            standardized.path)
    }

    private static func nanoseconds(
        _ time: timespec
    ) -> Int64 {
        Int64(time.tv_sec) * 1_000_000_000
            + Int64(time.tv_nsec)
    }
}

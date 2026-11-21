import Foundation
import Darwin

enum FirmwareLibraryEntryState: String, Codable, Equatable, Hashable, Sendable {
    case available
    case missing
    case ambiguous
    case invalid
}

enum FirmwareLibraryAccessState: String, Codable, Equatable, Hashable, Sendable {
    case unreadable
    case cloudNotDownloaded
}

enum FirmwareLibraryFileAccessStatus: Equatable, Sendable {
    case readable
    case unreadable(String)
    case cloudNotDownloaded(String)
}

struct FirmwareLibraryDirectoryEntryProperties: Equatable, Sendable {
    let isDirectory: Bool?
    let isPackage: Bool?
    let isRegularFile: Bool?
    let isSymbolicLink: Bool?
}

struct FirmwareLibraryDiscoveryLimits: Equatable, Sendable {
    let maximumDepth: Int
    let maximumVisitedEntries: Int
    let maximumIPSWs: Int

    init(
        maximumDepth: Int = 8,
        maximumVisitedEntries: Int = 20_000,
        maximumIPSWs: Int = 1_024
    ) {
        self.maximumDepth = max(0, maximumDepth)
        self.maximumVisitedEntries = max(1, maximumVisitedEntries)
        self.maximumIPSWs = max(1, maximumIPSWs)
    }

    static let standard = FirmwareLibraryDiscoveryLimits()
}

func isICloudPlaceholderName(_ name: String) -> Bool {
    name.lowercased().hasSuffix(".ipsw.icloud")
}

func isIPSWCandidateName(_ name: String) -> Bool {
    name.lowercased().hasSuffix(".ipsw")
        || isICloudPlaceholderName(name)
}

func inspectFirmwareDirectoryEntryProperties(
    _ url: URL
) throws -> FirmwareLibraryDirectoryEntryProperties {
    let values = try url.resourceValues(forKeys: [
        .isDirectoryKey,
        .isPackageKey,
        .isRegularFileKey,
        .isSymbolicLinkKey
    ])
    return FirmwareLibraryDirectoryEntryProperties(
        isDirectory: values.isDirectory,
        isPackage: values.isPackage,
        isRegularFile: values.isRegularFile,
        isSymbolicLink: values.isSymbolicLink)
}

func inspectFirmwareFileAccess(
    _ url: URL
) -> FirmwareLibraryFileAccessStatus {
    if isICloudPlaceholderName(url.lastPathComponent) {
        return .cloudNotDownloaded(
            "The IPSW is an iCloud placeholder and is not downloaded.")
    }
    do {
        let values = try url.resourceValues(forKeys: [
            .isReadableKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey
        ])
        if values.isUbiquitousItem == true,
           values.ubiquitousItemIsDownloading == true
            || values.ubiquitousItemDownloadingStatus == .notDownloaded {
            return .cloudNotDownloaded(
                "The iCloud IPSW is not locally available. Download it before indexing.")
        }
        if values.isReadable == false
            || !FileManager.default.isReadableFile(atPath: url.path) {
            return .unreadable(
                "The IPSW cannot be read with the current file permissions.")
        }
        return .readable
    } catch {
        return .unreadable(
            "The IPSW access state could not be read: \(error.localizedDescription)")
    }
}

func isUnreadableFileError(_ error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain {
        return nsError.code == CocoaError.Code.fileReadNoPermission.rawValue
            || nsError.code == CocoaError.Code.fileReadUnknown.rawValue
    }
    if nsError.domain == NSPOSIXErrorDomain {
        return nsError.code == Int(EACCES)
            || nsError.code == Int(EPERM)
    }
    return false
}

func isInsideSystemTemporaryRoot(_ url: URL) -> Bool {
    let path = url.resolvingSymlinksInPath().standardizedFileURL.path
    let roots = [
        FileManager.default.temporaryDirectory,
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    ]
    return roots.contains { root in
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        return path == rootPath
            || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }
}

struct FirmwareLibraryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var url: URL
    var state: FirmwareLibraryEntryState
    let addedAt: Date
    var lastSeenAt: Date
    var fileIdentity: IPSWFileIdentity?
    var metadata: IPSWMetadata?
    var validity: IPSWFileValidity
    var errorMessage: String?
    var wholeFileSHA256: String?
    var duplicateEntryIDs: [UUID]
    var accessState: FirmwareLibraryAccessState?

    init(
        id: UUID,
        url: URL,
        state: FirmwareLibraryEntryState,
        addedAt: Date,
        lastSeenAt: Date,
        fileIdentity: IPSWFileIdentity?,
        metadata: IPSWMetadata?,
        validity: IPSWFileValidity,
        errorMessage: String?,
        wholeFileSHA256: String?,
        duplicateEntryIDs: [UUID],
        accessState: FirmwareLibraryAccessState? = nil
    ) {
        self.id = id
        self.url = url
        self.state = state
        self.addedAt = addedAt
        self.lastSeenAt = lastSeenAt
        self.fileIdentity = fileIdentity
        self.metadata = metadata
        self.validity = validity
        self.errorMessage = errorMessage
        self.wholeFileSHA256 = wholeFileSHA256
        self.duplicateEntryIDs = duplicateEntryIDs
        self.accessState = accessState
    }
}

extension FirmwareLibraryEntry {
    var isRestoreEligible: Bool {
        state == .available
            && accessState == nil
            && validity == .valid
            && fileIdentity != nil
    }
}

struct FirmwareLibraryQuery: Equatable, Sendable {
    let modelFamilyKey: ModelFamilyKey?
    let productVersion: String?
    let productBuild: String?
    let productType: String?
    let states: Set<FirmwareLibraryEntryState>

    init(
        modelFamilyKey: ModelFamilyKey? = nil,
        productVersion: String? = nil,
        productBuild: String? = nil,
        productType: String? = nil,
        states: Set<FirmwareLibraryEntryState> = []
    ) {
        self.modelFamilyKey = modelFamilyKey
        self.productVersion = productVersion
        self.productBuild = productBuild
        self.productType = productType
        self.states = states
    }
}

struct FirmwareLibraryScanResult: Equatable, Sendable {
    let entries: [FirmwareLibraryEntry]
    let discoveredCount: Int
    let indexedCount: Int
    let invalidCount: Int
    let unreadableCount: Int
    let cloudNotDownloadedCount: Int
    let visitedEntryCount: Int
    let unreadableDirectoryCount: Int
    let attributeReadFailureCount: Int
    let scanLimitReached: Bool
    let scanIncomplete: Bool
    let relocatedEntryIDs: [UUID]
    let ambiguousEntryIDs: [UUID]
}

enum FirmwareLibraryError: Error, LocalizedError {
    case unsupportedSchema(Int)
    case cannotEncode
    case cannotDecode

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "Unsupported firmware library schema \(version)."
        case .cannotEncode:
            return "The firmware library index could not be encoded."
        case .cannotDecode:
            return "The firmware library index could not be decoded."
        }
    }
}

actor FirmwareLibraryStore {
    private struct Document: Codable {
        var schemaVersion: Int
        var searchRoots: [URL]
        var entries: [FirmwareLibraryEntry]
    }

    private struct Candidate {
        let url: URL
        let identity: IPSWFileIdentity?
        let metadata: IPSWMetadata?
        let state: FirmwareLibraryEntryState
        let accessState: FirmwareLibraryAccessState?
        let validity: IPSWFileValidity
        let error: String?
    }

    private struct DirectoryDiscovery {
        var candidates: [Candidate]
        var visitedEntryCount: Int
        var unreadableDirectoryCount: Int
        var attributeReadFailureCount: Int
        var scanLimitReached: Bool
        var scanIncomplete: Bool
    }

    private static let schemaVersion = 1
    private let indexURL: URL
    private let metadataLoader: (URL) throws -> IPSWMetadataReadResult
    private let discoveryLimits: FirmwareLibraryDiscoveryLimits
    private let directoryEntryPropertyReader:
        (URL) throws -> FirmwareLibraryDirectoryEntryProperties
    private let fileAccessInspector: (URL) -> FirmwareLibraryFileAccessStatus
    private let ignoreSystemTemporaryRoot: Bool
    private var entries: [FirmwareLibraryEntry] = []
    private var searchRoots: [URL] = []
    private var loaded = false
    private var ignoredTemporaryEntries = 0

    init(
        indexURL: URL? = nil,
        metadataLoader: @escaping (URL) throws -> IPSWMetadataReadResult = {
            try IPSWMetadataReader.read(url: $0)
        },
        discoveryLimits: FirmwareLibraryDiscoveryLimits = .standard,
        directoryEntryPropertyReader:
            @escaping (URL) throws -> FirmwareLibraryDirectoryEntryProperties =
                inspectFirmwareDirectoryEntryProperties,
        fileAccessInspector: @escaping (URL) -> FirmwareLibraryFileAccessStatus =
            inspectFirmwareFileAccess,
        ignoreSystemTemporaryRoot: Bool? = nil
    ) {
        let usesDefaultIndex = indexURL == nil
        self.indexURL = indexURL
            ?? AppSupportLocations.directory()
                .appendingPathComponent("FirmwareLibrary", isDirectory: true)
                .appendingPathComponent("library-v1.json")
        self.metadataLoader = metadataLoader
        self.discoveryLimits = discoveryLimits
        self.directoryEntryPropertyReader = directoryEntryPropertyReader
        self.fileAccessInspector = fileAccessInspector
        self.ignoreSystemTemporaryRoot =
            ignoreSystemTemporaryRoot ?? usesDefaultIndex
    }

    func loadEntries() throws -> [FirmwareLibraryEntry] {
        try ensureLoaded()
        return entries
    }

    func revalidateReference(
        _ reference: FirmwareReference
    ) -> FirmwareReferenceResolution {
        do {
            try ensureLoaded()
        } catch {
            return FirmwareReferenceResolution(
                reference: reference,
                entry: nil,
                state: .missing,
                message: "固件库索引无法读取：\(error.localizedDescription)")
        }

        let initial = FirmwareReferenceResolver.resolve(
            reference,
            in: entries)
        guard initial.state == .available,
              let entry = initial.entry else {
            return initial
        }
        switch fileAccessInspector(entry.url) {
        case .cloudNotDownloaded(let message):
            return FirmwareReferenceResolution(
                reference: reference,
                entry: entry,
                state: .cloudNotDownloaded,
                message: message)
        case .unreadable(let message):
            return FirmwareReferenceResolution(
                reference: reference,
                entry: entry,
                state: .unreadable,
                message: message)
        case .readable:
            break
        }
        guard FileManager.default.fileExists(atPath: entry.url.path) else {
            return FirmwareReferenceResolution(
                reference: reference,
                entry: entry,
                state: .missing,
                message: "固件文件已移动或删除。")
        }

        do {
            let result = try metadataLoader(entry.url)
            guard result.validity == .valid,
                  let currentIdentity = result.fileIdentity else {
                return FirmwareReferenceResolution(
                    reference: reference,
                    entry: entry,
                    state: .invalid,
                    message: result.error
                        ?? "固件已损坏或缺少有效 BuildManifest。")
            }
            if let expected = reference.fileIdentity,
               currentIdentity != expected {
                return FirmwareReferenceResolution(
                    reference: reference,
                    entry: entry,
                    state: .modified,
                    message: "固件文件身份已变化，原偏好不会自动替换为另一份文件。")
            }
            var revalidated = entry
            revalidated.state = .available
            revalidated.accessState = nil
            revalidated.validity = .valid
            revalidated.fileIdentity = currentIdentity
            revalidated.metadata = result.metadata
            revalidated.errorMessage = result.error
            return FirmwareReferenceResolution(
                reference: reference,
                entry: revalidated,
                state: .available,
                message: "固件文件身份与 BuildManifest 复验通过。")
        } catch {
            return FirmwareReferenceResolution(
                reference: reference,
                entry: entry,
                state: isUnreadableFileError(error) ? .unreadable : .invalid,
                message: error.localizedDescription)
        }
    }

    func allEntries() -> [FirmwareLibraryEntry] {
        entries
    }

    func ignoredTemporaryEntryCount() -> Int {
        ignoredTemporaryEntries
    }

    func addFile(_ url: URL) throws -> FirmwareLibraryEntry {
        try ensureLoaded()
        let parent = url.deletingLastPathComponent().standardizedFileURL
        addRoot(parent)
        var observedURLs = [url.standardizedFileURL]
        observedURLs.append(contentsOf: entries.compactMap { entry in
            guard entry.url.deletingLastPathComponent().standardizedFileURL == parent,
                  entry.url.standardizedFileURL != url.standardizedFileURL,
                  FileManager.default.fileExists(atPath: entry.url.path) else {
                return nil
            }
            return entry.url.standardizedFileURL
        })
        let discovery = DirectoryDiscovery(
            candidates: uniqueCandidates(observedURLs.map(indexCandidate)),
            visitedEntryCount: observedURLs.count,
            unreadableDirectoryCount: 0,
            attributeReadFailureCount: 0,
            scanLimitReached: false,
            scanIncomplete: false)
        let result = try reconcile(
            discovery: discovery,
            scanRoots: [parent],
            markMissing: false)
        guard let entry = result.entries.first(where: {
            $0.url.standardizedFileURL == url.standardizedFileURL
        }) else {
            throw IPSWMetadataError.cannotRead(
                "The selected IPSW could not be added to the library.")
        }
        return entry
    }

    func addDirectory(_ directory: URL) throws -> FirmwareLibraryScanResult {
        try ensureLoaded()
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        addRoot(root)
        let discovery = indexDirectory(root)
        return try reconcile(
            discovery: discovery,
            scanRoots: [root],
            markMissing: !discovery.scanIncomplete)
    }

    func refresh(
        additionalDirectories: [URL] = [],
        discoveredURLs: [URL] = [],
        pruneMissing: Bool = false
    ) throws -> FirmwareLibraryScanResult {
        try ensureLoaded()
        for directory in additionalDirectories {
            addRoot(directory.resolvingSymlinksInPath().standardizedFileURL)
        }
        let roots = searchRoots.filter {
            !isForbiddenFirmwareDiscoveryRoot($0)
        }
        let discoveries = roots.map(indexDirectory)
        let discoveredCandidates = discoveredURLs
            .map { $0.resolvingSymlinksInPath().standardizedFileURL }
            .filter {
                !isForbiddenFirmwareDiscoveryRoot($0)
                    && !isForbiddenFirmwareDiscoveryPath($0)
                    && isIPSWCandidateName($0.lastPathComponent)
            }
            .prefix(FirmwareDiscoveryService.maximumResults)
            .map(indexCandidate)
        let discovery = DirectoryDiscovery(
            candidates: uniqueCandidates(
                discoveries.flatMap(\.candidates) + discoveredCandidates),
            visitedEntryCount: discoveries.reduce(0) {
                $0 + $1.visitedEntryCount
            },
            unreadableDirectoryCount: discoveries.reduce(0) {
                $0 + $1.unreadableDirectoryCount
            },
            attributeReadFailureCount: discoveries.reduce(0) {
                $0 + $1.attributeReadFailureCount
            },
            scanLimitReached: discoveries.contains {
                $0.scanLimitReached
            },
            scanIncomplete: discoveries.contains {
                $0.scanIncomplete
            })
        return try reconcile(
            discovery: discovery,
            scanRoots: roots,
            markMissing: !discovery.scanIncomplete,
            pruneMissing: pruneMissing)
    }

    func libraryRoots() -> [URL] {
        searchRoots.filter { !isForbiddenFirmwareDiscoveryRoot($0) }
    }

    func removeRoot(_ directory: URL) throws -> [FirmwareLibraryEntry] {
        try ensureLoaded()
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        searchRoots.removeAll { $0.standardizedFileURL == root }
        entries.removeAll { isInside(url: $0.url, roots: [root]) }
        recomputeDuplicateRelationships()
        try persist()
        return entries
    }

    func query(
        _ query: FirmwareLibraryQuery
    ) -> [FirmwareLibraryEntry] {
        entries.filter { entry in
            if let modelFamilyKey = query.modelFamilyKey,
               !(entry.metadata?.productTypes.contains {
                   ModelFamilyKey(rawValue: $0) == modelFamilyKey
               } ?? false) {
                return false
            }
            if let productVersion = query.productVersion,
               entry.metadata?.productVersion != productVersion {
                return false
            }
            if let productBuild = query.productBuild,
               entry.metadata?.productBuild != productBuild {
                return false
            }
            if let productType = query.productType,
               !(entry.metadata?.productTypes.contains {
                   $0.caseInsensitiveCompare(productType) == .orderedSame
               } ?? false) {
                return false
            }
            if !query.states.isEmpty, !query.states.contains(entry.state) {
                return false
            }
            return true
        }
    }

    private func ensureLoaded() throws {
        guard !loaded else { return }
        var persistedStateChanged = false
        var temporaryRootsWereRemoved = false
        if FileManager.default.fileExists(atPath: indexURL.path) {
            let data = try Data(contentsOf: indexURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let document = try? decoder.decode(Document.self, from: data) else {
                throw FirmwareLibraryError.cannotDecode
            }
            guard document.schemaVersion == Self.schemaVersion else {
                throw FirmwareLibraryError.unsupportedSchema(document.schemaVersion)
            }
            if ignoreSystemTemporaryRoot {
                ignoredTemporaryEntries = document.entries.filter {
                    isInsideSystemTemporaryRoot($0.url)
                }.count
                entries = document.entries.filter {
                    !isInsideSystemTemporaryRoot($0.url)
                }
                let retainedRoots = document.searchRoots.filter {
                    !isInsideSystemTemporaryRoot($0)
                }
                temporaryRootsWereRemoved =
                    retainedRoots.count != document.searchRoots.count
                searchRoots = uniqueURLs(retainedRoots)
            } else {
                entries = document.entries
                searchRoots = uniqueURLs(document.searchRoots)
            }
            let refreshedEntries = entries.map(refreshPersistedEntryState)
            persistedStateChanged = refreshedEntries != entries
            entries = refreshedEntries
        }
        loaded = true
        recomputeDuplicateRelationships()
        if ignoredTemporaryEntries > 0
            || temporaryRootsWereRemoved
            || persistedStateChanged {
            try persist()
        }
    }

    private func refreshPersistedEntryState(
        _ entry: FirmwareLibraryEntry
    ) -> FirmwareLibraryEntry {
        guard FileManager.default.fileExists(atPath: entry.url.path) else {
            let parent = entry.url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parent.path),
               !FileManager.default.isReadableFile(atPath: parent.path) {
                var unreadable = entry
                unreadable.state = .invalid
                unreadable.accessState = .unreadable
                unreadable.validity = .unverified
                unreadable.errorMessage =
                    "The containing directory cannot be read with the current permissions."
                return unreadable
            }
            var missing = entry
            missing.state = .missing
            missing.accessState = nil
            missing.errorMessage =
                "The indexed IPSW is not present under the current scanned directories."
            return missing
        }
        switch fileAccessInspector(entry.url) {
        case .readable:
            return entry
        case .unreadable(let message):
            var unreadable = entry
            unreadable.state = .invalid
            unreadable.accessState = .unreadable
            unreadable.validity = .unverified
            unreadable.errorMessage = message
            return unreadable
        case .cloudNotDownloaded(let message):
            var cloud = entry
            cloud.state = .invalid
            cloud.accessState = .cloudNotDownloaded
            cloud.validity = .unverified
            cloud.errorMessage = message
            return cloud
        }
    }

    private func addRoot(_ url: URL) {
        let standardized = url.resolvingSymlinksInPath().standardizedFileURL
        guard !isForbiddenFirmwareDiscoveryRoot(standardized) else { return }
        if !searchRoots.contains(standardized) {
            searchRoots.append(standardized)
            searchRoots.sort { $0.path < $1.path }
        }
    }

    private func indexDirectory(_ directory: URL) -> DirectoryDiscovery {
        guard !isForbiddenFirmwareDiscoveryRoot(directory) else {
            return DirectoryDiscovery(
                candidates: [],
                visitedEntryCount: 0,
                unreadableDirectoryCount: 0,
                attributeReadFailureCount: 0,
                scanLimitReached: false,
                scanIncomplete: false)
        }
        var unreadableDirectories = 0
        var attributeReadFailures = 0
        var urls: [URL] = []
        var visitedEntryCount = 0
        var scanLimitReached = false
        var pendingDirectories = [(url: directory, depth: 0)]
        var pendingIndex = 0

        discoveryLoop: while pendingIndex < pendingDirectories.count {
            let current = pendingDirectories[pendingIndex]
            pendingIndex += 1
            let children: [URL]
            do {
                children = try FileManager.default.contentsOfDirectory(
                    at: current.url,
                    includingPropertiesForKeys: [
                        .isDirectoryKey,
                        .isPackageKey,
                        .isRegularFileKey,
                        .isSymbolicLinkKey
                    ],
                    options: [])
            } catch {
                unreadableDirectories += 1
                continue
            }

            for url in children.sorted(by: {
                $0.lastPathComponent.localizedStandardCompare(
                    $1.lastPathComponent) == .orderedAscending
            }) {
                guard visitedEntryCount
                        < discoveryLimits.maximumVisitedEntries else {
                    scanLimitReached = true
                    break discoveryLoop
                }
                visitedEntryCount += 1
                let values: FirmwareLibraryDirectoryEntryProperties?
                do {
                    values = try directoryEntryPropertyReader(url)
                } catch {
                    attributeReadFailures += 1
                    values = nil
                }
                let name = url.lastPathComponent
                if values?.isSymbolicLink == true {
                    continue
                }
                if values?.isDirectory == true {
                    let isHidden = name.hasPrefix(".")
                    let isPackage = values?.isPackage == true
                    if !isHidden, !isPackage {
                        if current.depth < discoveryLimits.maximumDepth {
                            pendingDirectories.append((
                                url: url,
                                depth: current.depth + 1))
                        } else {
                            scanLimitReached = true
                        }
                    }
                    continue
                }
                if name.hasPrefix("."), !isICloudPlaceholderName(name) {
                    continue
                }
                guard isIPSWCandidateName(name) else {
                    continue
                }
                if let values, values.isRegularFile != true {
                    continue
                }
                guard urls.count < discoveryLimits.maximumIPSWs else {
                    scanLimitReached = true
                    break discoveryLoop
                }
                urls.append(url)
            }
        }
        let candidates = urls
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .map(indexCandidate)
        return DirectoryDiscovery(
            candidates: candidates,
            visitedEntryCount: visitedEntryCount,
            unreadableDirectoryCount: unreadableDirectories,
            attributeReadFailureCount: attributeReadFailures,
            scanLimitReached: scanLimitReached,
            scanIncomplete:
                scanLimitReached
                    || unreadableDirectories > 0
                    || attributeReadFailures > 0)
    }

    private func cachedCandidate(for url: URL) -> Candidate? {
        let standardized = url.resolvingSymlinksInPath().standardizedFileURL
        guard let entry = entries.first(where: {
            candidatePath($0.url) == candidatePath(standardized)
        }),
        let identity = entry.fileIdentity,
        let metadata = entry.metadata,
        !metadata.identities.isEmpty,
        entry.validity == .valid,
        entry.state == .available,
        entry.accessState == nil else {
            return nil
        }
        var fileStat = stat()
        guard lstat(standardized.path, &fileStat) == 0,
              (fileStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              UInt64(fileStat.st_dev) == identity.dev,
              UInt64(fileStat.st_ino) == identity.ino,
              UInt64(fileStat.st_size) == identity.sizeBytes,
              Int64(fileStat.st_mtimespec.tv_sec) * 1_000_000_000
                + Int64(fileStat.st_mtimespec.tv_nsec) == identity.mtimeNs else {
            return nil
        }
        return Candidate(
            url: standardized,
            identity: identity,
            metadata: metadata,
            state: entry.state,
            accessState: nil,
            validity: entry.validity,
            error: entry.errorMessage)
    }

    private func indexCandidate(_ url: URL) -> Candidate {
        switch fileAccessInspector(url) {
        case .unreadable(let message):
            return Candidate(
                url: url.standardizedFileURL,
                identity: nil,
                metadata: nil,
                state: .invalid,
                accessState: .unreadable,
                validity: .unverified,
                error: message)
        case .cloudNotDownloaded(let message):
            return Candidate(
                url: url.standardizedFileURL,
                identity: nil,
                metadata: nil,
                state: .invalid,
                accessState: .cloudNotDownloaded,
                validity: .unverified,
                error: message)
        case .readable:
            break
        }
        if let cached = cachedCandidate(for: url) {
            return cached
        }
        do {
            let result = try metadataLoader(url)
            let identity = result.fileIdentity
                ?? (try? IPSWMetadataReader.fileIdentity(
                    url: url,
                    buildManifestSHA256: result.buildManifestSHA256))
            return Candidate(
                url: url.standardizedFileURL,
                identity: identity,
                metadata: result.metadata,
                state: result.validity == .valid ? .available : .invalid,
                accessState: nil,
                validity: result.validity,
                error: result.error)
        } catch {
            let isUnreadable = isUnreadableFileError(error)
            return Candidate(
                url: url.standardizedFileURL,
                identity: nil,
                metadata: nil,
                state: .invalid,
                accessState: isUnreadable ? .unreadable : nil,
                validity: isUnreadable ? .unverified : .invalid,
                error: error.localizedDescription)
        }
    }

    private func reconcile(
        discovery: DirectoryDiscovery,
        scanRoots: [URL],
        markMissing: Bool = true,
        pruneMissing: Bool = false
    ) throws -> FirmwareLibraryScanResult {
        let candidates = discovery.candidates
        let now = Date()
        var working = entries
        var consumedEntryIDs = Set<UUID>()
        var consumedCandidatePaths = Set<String>()
        var relocatedEntryIDs: [UUID] = []
        var ambiguousEntryIDs: [UUID] = []

        for candidate in candidates {
            let path = candidatePath(candidate.url)
            if let index = working.firstIndex(where: {
                candidatePath($0.url) == path
            }) {
                working[index] = updated(working[index], from: candidate, at: now)
                consumedEntryIDs.insert(working[index].id)
                consumedCandidatePaths.insert(path)
            }
        }

        let unmatchedCandidates = candidates.filter {
            !consumedCandidatePaths.contains(candidatePath($0.url))
        }
        let candidatesByRelocationKey = Dictionary(
            grouping: unmatchedCandidates.filter {
                relocationKey($0) != nil
            },
            by: { relocationKey($0)! })
        let observedPaths = Set(candidates.map { candidatePath($0.url) })
        let scannedRoots = uniqueURLs(scanRoots)
        let missingByRelocationKey = Dictionary(
            grouping: working.filter {
                !observedPaths.contains(candidatePath($0.url))
                    && isInside(url: $0.url, roots: scannedRoots)
                    && relocationKey($0) != nil
            },
            by: { relocationKey($0)! })

        for (key, groupedCandidates) in candidatesByRelocationKey {
            let missingEntries = missingByRelocationKey[key] ?? []
            guard !missingEntries.isEmpty else { continue }
            if groupedCandidates.count == 1, missingEntries.count == 1,
               let candidate = groupedCandidates.first,
               let index = working.firstIndex(where: { $0.id == missingEntries[0].id }) {
                let entryID = working[index].id
                working[index] = updated(working[index], from: candidate, at: now)
                consumedEntryIDs.insert(entryID)
                consumedCandidatePaths.insert(candidatePath(candidate.url))
                relocatedEntryIDs.append(entryID)
            } else {
                for entry in missingEntries {
                    guard let index = working.firstIndex(where: { $0.id == entry.id }) else {
                        continue
                    }
                    working[index].state = .ambiguous
                    working[index].accessState = nil
                    working[index].errorMessage =
                        "Multiple indexed IPSWs match this entry's size and BuildManifest; manual path confirmation is required."
                    ambiguousEntryIDs.append(entry.id)
                }
            }
        }

        for candidate in candidates
        where !consumedCandidatePaths.contains(candidatePath(candidate.url)) {
            let entry = FirmwareLibraryEntry(
                id: UUID(),
                url: candidate.url,
                state: candidate.state,
                addedAt: now,
                lastSeenAt: now,
                fileIdentity: candidate.identity,
                metadata: candidate.metadata,
                validity: candidate.validity,
                errorMessage: candidate.error,
                wholeFileSHA256: nil,
                duplicateEntryIDs: [],
                accessState: candidate.accessState)
            working.append(entry)
            consumedCandidatePaths.insert(candidatePath(candidate.url))
        }

        for index in working.indices
        where markMissing
            && !consumedEntryIDs.contains(working[index].id)
            && !consumedCandidatePaths.contains(candidatePath(working[index].url))
            && isInside(url: working[index].url, roots: scannedRoots)
            && working[index].state != .ambiguous {
            working[index].state = .missing
            working[index].accessState = nil
            working[index].errorMessage =
                "The indexed IPSW is not present under the current scanned directories."
        }

        entries = working
        if pruneMissing && !discovery.scanIncomplete {
            entries.removeAll { $0.state == .missing }
        }
        for root in uniqueURLs(scanRoots) {
            addRoot(root)
        }
        recomputeDuplicateRelationships()
        try persist()

        return FirmwareLibraryScanResult(
            entries: entries,
            discoveredCount: candidates.count,
            indexedCount: candidates.filter { $0.validity == .valid }.count,
            invalidCount: candidates.filter {
                $0.state == .invalid && $0.accessState == nil
            }.count,
            unreadableCount: candidates.filter {
                $0.accessState == .unreadable
            }.count,
            cloudNotDownloadedCount: candidates.filter {
                $0.accessState == .cloudNotDownloaded
            }.count,
            visitedEntryCount: discovery.visitedEntryCount,
            unreadableDirectoryCount: discovery.unreadableDirectoryCount,
            attributeReadFailureCount: discovery.attributeReadFailureCount,
            scanLimitReached: discovery.scanLimitReached,
            scanIncomplete: discovery.scanIncomplete,
            relocatedEntryIDs: Array(Set(relocatedEntryIDs)).sorted {
                $0.uuidString < $1.uuidString
            },
            ambiguousEntryIDs: Array(Set(ambiguousEntryIDs)).sorted {
                $0.uuidString < $1.uuidString
            })
    }

    private func updated(
        _ entry: FirmwareLibraryEntry,
        from candidate: Candidate,
        at date: Date
    ) -> FirmwareLibraryEntry {
        var result = entry
        result.url = candidate.url
        result.state = candidate.state
        result.accessState = candidate.accessState
        result.lastSeenAt = date
        result.fileIdentity = candidate.identity
        result.metadata = candidate.metadata
        result.validity = candidate.validity
        result.errorMessage = candidate.error
        result.wholeFileSHA256 = nil
        return result
    }

    private func recomputeDuplicateRelationships() {
        var byFileIdentity: [String: [UUID]] = [:]
        for entry in entries {
            guard let identity = entry.fileIdentity else { continue }
            let key = "\(identity.dev):\(identity.ino)"
            byFileIdentity[key, default: []].append(entry.id)
        }
        for index in entries.indices {
            guard let identity = entries[index].fileIdentity else {
                entries[index].duplicateEntryIDs = []
                continue
            }
            let key = "\(identity.dev):\(identity.ino)"
            entries[index].duplicateEntryIDs = (byFileIdentity[key] ?? [])
                .filter { $0 != entries[index].id }
                .sorted { $0.uuidString < $1.uuidString }
        }
    }

    private func persist() throws {
        let directory = indexURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        let document = Document(
            schemaVersion: Self.schemaVersion,
            searchRoots: searchRoots,
            entries: entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(document) else {
            throw FirmwareLibraryError.cannotEncode
        }
        try data.write(to: indexURL, options: .atomic)
    }

    private func relocationKey(_ candidate: Candidate) -> String? {
        guard let identity = candidate.identity,
              let metadata = candidate.metadata,
              !identity.buildManifestSHA256.isEmpty,
              let version = metadata.productVersion,
              let build = metadata.productBuild else {
            return nil
        }
        return [
            String(identity.sizeBytes),
            identity.buildManifestSHA256,
            version,
            build
        ].joined(separator: "|")
    }

    private func relocationKey(_ entry: FirmwareLibraryEntry) -> String? {
        guard let identity = entry.fileIdentity,
              let metadata = entry.metadata,
              !identity.buildManifestSHA256.isEmpty,
              let version = metadata.productVersion,
              let build = metadata.productBuild else {
            return nil
        }
        return [
            String(identity.sizeBytes),
            identity.buildManifestSHA256,
            version,
            build
        ].joined(separator: "|")
    }

    private func candidatePath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func uniqueCandidates(_ candidates: [Candidate]) -> [Candidate] {
        var seen = Set<String>()
        return candidates.filter {
            seen.insert(candidatePath($0.url)).inserted
        }
    }

    private func isInside(url: URL, roots: [URL]) -> Bool {
        let path = url.standardizedFileURL.path
        return roots.contains { root in
            let rootPath = root.standardizedFileURL.path
            return path == rootPath
                || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
        }
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls
            .map(\.standardizedFileURL)
            .filter { seen.insert($0.path).inserted }
            .sorted { $0.path < $1.path }
    }
}

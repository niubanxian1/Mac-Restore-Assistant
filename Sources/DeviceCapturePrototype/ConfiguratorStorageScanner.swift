import Darwin
import Foundation
import SwiftUI

enum ConfiguratorStorageRootKind: String, Equatable, Sendable {
    case groupContainer
    case appContainer
    case userCache
    case userTemp
}

struct ConfiguratorStorageRoot: Equatable, Sendable {
    let url: URL
    let kind: ConfiguratorStorageRootKind
    let displayName: String
}

enum ConfiguratorStorageEntryKind: Equatable, Sendable {
    case regularFile
    case directory
    case symbolicLink
    case other
}

struct ConfiguratorStorageFileMetadata: Equatable, Sendable {
    let kind: ConfiguratorStorageEntryKind
    let logicalBytes: Int64
    let allocatedBytes: Int64
    let device: UInt64
    let inode: UInt64
}

enum ConfiguratorStorageReadFailure: Error, Equatable, Sendable {
    case notFound
    case permissionDenied
    case accessDenied
    case notFoundAfterListing
    case changedDuringScan
    case failed
    case unexpected
}

protocol ConfiguratorStorageDirectoryReading: AnyObject {
    var url: URL { get }

    func readChildren(
        visit: (String, ConfiguratorStorageFileMetadata) throws -> Bool
    ) throws

    func withChildDirectory(
        named name: String,
        metadata: ConfiguratorStorageFileMetadata,
        body: (any ConfiguratorStorageDirectoryReading) throws -> Void
    ) throws
}

protocol ConfiguratorStorageFileReading: Sendable {
    func metadata(at url: URL) throws -> ConfiguratorStorageFileMetadata
    func openDirectory(
        at url: URL,
        expectedDevice: UInt64,
        expectedInode: UInt64
    ) throws -> any ConfiguratorStorageDirectoryReading
}

enum ConfiguratorStorageAccessIssueKind: String, Equatable, Sendable {
    case permissionDenied
    case changedDuringScan
    case scanFailed
    case limitReached
    case discoveryFailed
}

struct ConfiguratorStorageAccessIssue: Equatable, Sendable {
    let kind: ConfiguratorStorageAccessIssueKind
    let path: String
    let detail: String
}

struct ConfiguratorStorageRootDiscovery: Equatable, Sendable {
    let roots: [ConfiguratorStorageRoot]
    let issues: [ConfiguratorStorageAccessIssue]
}

protocol ConfiguratorStorageRootDiscovering: Sendable {
    func discover() -> ConfiguratorStorageRootDiscovery
}

enum ConfiguratorStorageRootStatus: String, Equatable, Sendable {
    case complete
    case empty
    case missing
    case permissionDenied
    case partialReadable
    case failed
}

struct ConfiguratorStorageRootResult: Equatable, Sendable {
    let root: ConfiguratorStorageRoot
    let status: ConfiguratorStorageRootStatus
    let logicalBytes: Int64?
    let allocatedBytes: Int64?
    let fileCount: Int?
    let excludedEntryCount: Int
    let issues: [ConfiguratorStorageAccessIssue]
}

enum ConfiguratorProcessKey: String, CaseIterable, Equatable, Sendable {
    case appleConfigurator
    case deviceService
    case internetService
    case migrationService
    case smartHubService

    var approvedExecutablePaths: Set<String> {
        let app = "/Applications/Apple Configurator.app"
        let xpc =
            "\(app)/Contents/Frameworks/ConfigurationUtilityKit.framework/Versions/A/XPCServices"
        switch self {
        case .appleConfigurator:
            return ["\(app)/Contents/MacOS/Apple Configurator"]
        case .deviceService:
            return [
                "\(xpc)/com.apple.configurator.xpc.DeviceService.xpc/Contents/MacOS/com.apple.configurator.xpc.DeviceService",
                "\(app)/Contents/MacOS/DeviceService",
            ]
        case .internetService:
            return [
                "\(xpc)/com.apple.configurator.xpc.InternetService.xpc/Contents/MacOS/com.apple.configurator.xpc.InternetService",
                "\(app)/Contents/MacOS/InternetService",
            ]
        case .migrationService:
            return [
                "\(xpc)/com.apple.configurator.xpc.MigrationService.xpc/Contents/MacOS/com.apple.configurator.xpc.MigrationService",
                "\(app)/Contents/MacOS/MigrationService",
            ]
        case .smartHubService:
            return [
                "\(xpc)/com.apple.configurator.xpc.SmartHubService.xpc/Contents/MacOS/com.apple.configurator.xpc.SmartHubService",
                "\(app)/Contents/MacOS/SmartHubService",
            ]
        }
    }

    var displayName: String {
        switch self {
        case .appleConfigurator: return "Apple Configurator"
        case .deviceService: return "DeviceService"
        case .internetService: return "InternetService"
        case .migrationService: return "MigrationService"
        case .smartHubService: return "SmartHubService"
        }
    }
}

enum ConfiguratorProcessStatus: String, Equatable, Sendable {
    case running
    case notRunning
    case unknown
}

struct ConfiguratorProcessObservation: Equatable, Sendable {
    let key: ConfiguratorProcessKey
    let status: ConfiguratorProcessStatus
}

protocol ConfiguratorProcessDiscovering: Sendable {
    func processNames() -> [String]?
}

enum ConfiguratorStorageScanCompleteness: String, Equatable, Sendable {
    case complete
    case permissionLimited
    case partial
    case failed
}

struct ConfiguratorStorageScanSnapshot: Equatable, Sendable {
    let scannedAt: Date
    let completeness: ConfiguratorStorageScanCompleteness
    let roots: [ConfiguratorStorageRootResult]
    let processes: [ConfiguratorProcessObservation]
    let discoveryIssues: [ConfiguratorStorageAccessIssue]
    let totalLogicalBytes: Int64?
    let totalAllocatedBytes: Int64?
}

struct ConfiguratorStorageLiveFileReader:
    ConfiguratorStorageFileReading
{
    func metadata(at url: URL) throws -> ConfiguratorStorageFileMetadata {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw Self.failure(errno: errno)
        }
        return Self.metadata(from: info)
    }

    func openDirectory(
        at url: URL,
        expectedDevice: UInt64,
        expectedInode: UInt64
    ) throws -> any ConfiguratorStorageDirectoryReading {
        let descriptor = open(
            url.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw Self.failure(errno: errno)
        }

        var opened = stat()
        guard fstat(descriptor, &opened) == 0 else {
            let code = errno
            close(descriptor)
            throw Self.failure(errno: code)
        }
        guard UInt64(opened.st_dev) == expectedDevice,
              UInt64(opened.st_ino) == expectedInode else {
            close(descriptor)
            throw ConfiguratorStorageReadFailure.changedDuringScan
        }
        return ConfiguratorStorageLiveDirectoryReader(
            descriptor: descriptor,
            url: url,
            device: expectedDevice,
            inode: expectedInode)
    }

    fileprivate static func failure(
        errno code: Int32
    ) -> ConfiguratorStorageReadFailure {
        switch code {
        case ENOENT:
            return .notFound
        case EPERM:
            return .permissionDenied
        case EACCES:
            return .accessDenied
        case ELOOP, ENOTDIR:
            return .changedDuringScan
        default:
            return .failed
        }
    }

    fileprivate static func metadata(
        from info: stat
    ) -> ConfiguratorStorageFileMetadata {
        let type = info.st_mode & mode_t(0o170000)
        let kind: ConfiguratorStorageEntryKind
        switch type {
        case mode_t(0o040000):
            kind = .directory
        case mode_t(0o100000):
            kind = .regularFile
        case mode_t(0o120000):
            kind = .symbolicLink
        default:
            kind = .other
        }
        return ConfiguratorStorageFileMetadata(
            kind: kind,
            logicalBytes: Int64(info.st_size),
            allocatedBytes: Int64(info.st_blocks) * 512,
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino))
    }

    private static func failure(error: Error) -> ConfiguratorStorageReadFailure {
        if let failure = error as? ConfiguratorStorageReadFailure {
            return failure
        }
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            return failure(errno: Int32(nsError.code))
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain {
            return failure(errno: Int32(underlying.code))
        }
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                return .notFound
            case NSFileReadNoPermissionError:
                return .accessDenied
            default:
                break
            }
        }
        return .failed
    }
}

private final class ConfiguratorStorageLiveDirectoryReader:
    ConfiguratorStorageDirectoryReading
{
    let url: URL
    private var descriptor: Int32
    private let device: UInt64
    private let inode: UInt64

    init(
        descriptor: Int32,
        url: URL,
        device: UInt64,
        inode: UInt64
    ) {
        self.descriptor = descriptor
        self.url = url
        self.device = device
        self.inode = inode
    }

    deinit {
        close()
    }

    func readChildren(
        visit: (String, ConfiguratorStorageFileMetadata) throws -> Bool
    ) throws {
        guard descriptor >= 0 else {
            throw ConfiguratorStorageReadFailure.changedDuringScan
        }
        let scanDescriptor = dup(descriptor)
        guard scanDescriptor >= 0 else {
            throw ConfiguratorStorageLiveFileReader.failure(
                errno: errno)
        }
        guard let directory = fdopendir(scanDescriptor) else {
            let code = errno
            Darwin.close(scanDescriptor)
            throw ConfiguratorStorageLiveFileReader.failure(
                errno: code)
        }
        defer { closedir(directory) }

        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                if errno != 0 {
                    throw ConfiguratorStorageLiveFileReader.failure(
                        errno: errno)
                }
                return
            }
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                String(
                    cString: UnsafeRawPointer($0)
                        .assumingMemoryBound(to: CChar.self))
            }
            guard name != ".", name != ".." else { continue }
            var info = stat()
            guard fstatat(
                descriptor,
                name,
                &info,
                AT_SYMLINK_NOFOLLOW) == 0 else {
                throw ConfiguratorStorageLiveFileReader.failure(
                    errno: errno)
            }
            let metadata = ConfiguratorStorageLiveFileReader.metadata(
                from: info)
            guard try visit(name, metadata) else { return }
        }
    }

    func withChildDirectory(
        named name: String,
        metadata: ConfiguratorStorageFileMetadata,
        body: (any ConfiguratorStorageDirectoryReading) throws -> Void
    ) throws {
        guard descriptor >= 0,
              metadata.kind == .directory else {
            throw ConfiguratorStorageReadFailure.changedDuringScan
        }
        let childDescriptor = openat(
            descriptor,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard childDescriptor >= 0 else {
            throw ConfiguratorStorageLiveFileReader.failure(
                errno: errno)
        }
        var opened = stat()
        guard fstat(childDescriptor, &opened) == 0 else {
            let code = errno
            Darwin.close(childDescriptor)
            throw ConfiguratorStorageLiveFileReader.failure(
                errno: code)
        }
        guard UInt64(opened.st_dev) == metadata.device,
              UInt64(opened.st_ino) == metadata.inode else {
            Darwin.close(childDescriptor)
            throw ConfiguratorStorageReadFailure.changedDuringScan
        }
        let child = ConfiguratorStorageLiveDirectoryReader(
            descriptor: childDescriptor,
            url: url.appendingPathComponent(name),
            device: metadata.device,
            inode: metadata.inode)
        try body(child)
    }

    private func close() {
        guard descriptor >= 0 else { return }
        Darwin.close(descriptor)
        descriptor = -1
    }
}

struct ConfiguratorStorageLiveRootDiscoverer:
    ConfiguratorStorageRootDiscovering
{
    private let homeDirectory: URL
    private let includeDarwinUserDirectories: Bool
    private let maximumEntriesPerParent: Int
    private let maximumMatchingRoots: Int

    init(
        homeDirectory: URL? = nil,
        includeDarwinUserDirectories: Bool? = nil,
        maximumEntriesPerParent: Int = 100_000,
        maximumMatchingRoots: Int = 128
    ) {
        let env = ProcessInfo.processInfo.environment
        let configuredHome = env["MRA_CONFIGURATOR_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let override = homeDirectory
            ?? configuredHome.flatMap {
                $0.isEmpty
                    ? nil
                    : URL(
                        fileURLWithPath: $0,
                        isDirectory: true)
            }
        self.homeDirectory = override
            ?? FileManager.default.homeDirectoryForCurrentUser
        self.includeDarwinUserDirectories =
            includeDarwinUserDirectories ?? (override == nil)
        self.maximumEntriesPerParent =
            max(1, maximumEntriesPerParent)
        self.maximumMatchingRoots = max(1, maximumMatchingRoots)
    }

    func discover() -> ConfiguratorStorageRootDiscovery {
        let fileManager = FileManager.default
        let home = homeDirectory
        var roots: [ConfiguratorStorageRoot] = [
            ConfiguratorStorageRoot(
                url: home.appendingPathComponent(
                    "Library/Group Containers/K36BKF7T3D.group.com.apple.configurator",
                    isDirectory: true),
                kind: .groupContainer,
                displayName: "Configurator Group Container"),
        ]
        var issues: [ConfiguratorStorageAccessIssue] = []

        let containers = home.appendingPathComponent(
            "Library/Containers",
            isDirectory: true)
        appendMatchingChildren(
            of: containers,
            kind: .appContainer,
            fileManager: fileManager,
            roots: &roots,
            issues: &issues)

        if includeDarwinUserDirectories {
            if let cache = darwinUserDirectory(
                _CS_DARWIN_USER_CACHE_DIR)
            {
                appendMatchingChildren(
                    of: cache,
                    kind: .userCache,
                    fileManager: fileManager,
                    roots: &roots,
                    issues: &issues)
            } else {
                issues.append(
                    ConfiguratorStorageAccessIssue(
                        kind: .discoveryFailed,
                        path: "DARWIN_USER_CACHE_DIR",
                        detail: "User cache directory unavailable"))
            }
            if let temp = darwinUserDirectory(
                _CS_DARWIN_USER_TEMP_DIR)
            {
                appendMatchingChildren(
                    of: temp,
                    kind: .userTemp,
                    fileManager: fileManager,
                    roots: &roots,
                    issues: &issues)
            } else {
                issues.append(
                    ConfiguratorStorageAccessIssue(
                        kind: .discoveryFailed,
                        path: "DARWIN_USER_TEMP_DIR",
                        detail: "User temporary directory unavailable"))
            }
        }

        var seen: Set<String> = []
        let uniqueRoots = roots.filter {
            seen.insert($0.url.standardizedFileURL.path).inserted
        }
        return ConfiguratorStorageRootDiscovery(
            roots: uniqueRoots,
            issues: issues)
    }

    private func appendMatchingChildren(
        of parent: URL,
        kind: ConfiguratorStorageRootKind,
        fileManager: FileManager,
        roots: inout [ConfiguratorStorageRoot],
        issues: inout [ConfiguratorStorageAccessIssue]
    ) {
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: parent,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ],
            options: [.skipsSubdirectoryDescendants],
            errorHandler: { _, error in
                enumerationError = error
                return false
            })
        else {
            let error = enumerationError
            if let error, isMissingError(error) {
                return
            }
            let nsError = error.map { $0 as NSError }
                ?? NSError(
                    domain: "ConfiguratorStorageDiscovery",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Directory could not be enumerated",
                    ])
            issues.append(
                ConfiguratorStorageAccessIssue(
                    kind: error.map(isPermissionError) == true
                        ? .permissionDenied
                        : .discoveryFailed,
                    path: parent.path,
                    detail: nsError.localizedDescription))
            return
        }

        var examined = 0
        var matched = 0
        for case let url as URL in enumerator {
            if examined >= maximumEntriesPerParent {
                issues.append(
                    ConfiguratorStorageAccessIssue(
                        kind: .limitReached,
                        path: parent.path,
                        detail: "DISCOVERY_ENTRY_LIMIT"))
                break
            }
            examined += 1
            guard isConfiguratorName(url.lastPathComponent) else {
                continue
            }
            do {
                let values = try url.resourceValues(
                    forKeys: [
                        .isDirectoryKey,
                        .isSymbolicLinkKey,
                    ])
                guard values.isDirectory == true,
                      values.isSymbolicLink != true else {
                    continue
                }
            } catch {
                issues.append(
                    ConfiguratorStorageAccessIssue(
                        kind: isPermissionError(error)
                            ? .permissionDenied
                            : .discoveryFailed,
                        path: url.path,
                        detail: error.localizedDescription))
                continue
            }
            guard matched < maximumMatchingRoots else {
                issues.append(
                    ConfiguratorStorageAccessIssue(
                        kind: .limitReached,
                        path: parent.path,
                        detail: "DISCOVERY_ROOT_LIMIT"))
                break
            }
            roots.append(
                ConfiguratorStorageRoot(
                    url: url,
                    kind: kind,
                    displayName: url.lastPathComponent))
            matched += 1
        }
        if let enumerationError {
            issues.append(
                ConfiguratorStorageAccessIssue(
                    kind: isPermissionError(enumerationError)
                        ? .permissionDenied
                        : .discoveryFailed,
                    path: parent.path,
                    detail: enumerationError.localizedDescription))
        }
    }

    private func isConfiguratorName(_ name: String) -> Bool {
        name == "com.apple.configurator"
            || name.hasPrefix("com.apple.configurator.")
    }

    private func darwinUserDirectory(_ name: Int32) -> URL? {
        let required = confstr(name, nil, 0)
        guard required > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: required)
        guard confstr(name, &buffer, buffer.count) > 0 else {
            return nil
        }
        return URL(
            fileURLWithPath: String(cString: buffer),
            isDirectory: true)
    }

    private func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileReadNoPermissionError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain,
           [EPERM, EACCES].contains(Int32(nsError.code)) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain,
           [EPERM, EACCES].contains(Int32(underlying.code)) {
            return true
        }
        return false
    }

    private func isMissingError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           [
               NSFileNoSuchFileError,
               NSFileReadNoSuchFileError,
           ].contains(nsError.code) {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain,
           nsError.code == ENOENT {
            return true
        }
        if let underlying =
            nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain,
           underlying.code == ENOENT {
            return true
        }
        return false
    }
}

struct ConfiguratorStorageLiveProcessDiscoverer:
    ConfiguratorProcessDiscovering
{
    func processNames() -> [String]? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "comm="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .map(String.init)
        } catch {
            return nil
        }
    }
}

final class ConfiguratorStorageScanner: @unchecked Sendable {
    private let rootDiscoverer:
        any ConfiguratorStorageRootDiscovering
    private let fileReader:
        any ConfiguratorStorageFileReading
    private let processDiscoverer:
        any ConfiguratorProcessDiscovering
    private let maximumDepth: Int
    private let maximumEntriesPerRoot: Int

    init(
        rootDiscoverer:
            any ConfiguratorStorageRootDiscovering =
                ConfiguratorStorageLiveRootDiscoverer(),
        fileReader:
            any ConfiguratorStorageFileReading =
                ConfiguratorStorageLiveFileReader(),
        processDiscoverer:
            any ConfiguratorProcessDiscovering =
                ConfiguratorStorageLiveProcessDiscoverer(),
        maximumDepth: Int = 24,
        maximumEntriesPerRoot: Int = 100_000
    ) {
        self.rootDiscoverer = rootDiscoverer
        self.fileReader = fileReader
        self.processDiscoverer = processDiscoverer
        self.maximumDepth = max(1, maximumDepth)
        self.maximumEntriesPerRoot = max(1, maximumEntriesPerRoot)
    }

    func scan() -> ConfiguratorStorageScanSnapshot {
        let discovery = rootDiscoverer.discover()
        let roots = discovery.roots.map(scan(root:))
        let processes = processObservations()
        let completeness = overallCompleteness(
            roots: roots,
            discoveryIssues: discovery.issues)
        let aggregateUsageKnown =
            completeness == .complete
            && !roots.isEmpty
            && roots.allSatisfy {
                $0.status == .missing
                    || $0.status == .empty
                    || $0.status == .complete
            }
        return ConfiguratorStorageScanSnapshot(
            scannedAt: Date(),
            completeness: completeness,
            roots: roots,
            processes: processes,
            discoveryIssues: discovery.issues,
            totalLogicalBytes: aggregateUsageKnown
                ? roots.compactMap(\.logicalBytes).reduce(0, +)
                : nil,
            totalAllocatedBytes: aggregateUsageKnown
                ? roots.compactMap(\.allocatedBytes).reduce(0, +)
                : nil)
    }

    private final class Traversal {
        var logicalBytes: Int64 = 0
        var allocatedBytes: Int64 = 0
        var fileCount = 0
        var excludedEntryCount = 0
        var issues: [ConfiguratorStorageAccessIssue] = []
        var visitedDirectories: Set<String> = []
        var allocatedInodes: Set<String> = []
        var entryCount = 0
        var permissionLimited = false
        var failed = false
        var limitReached = false

        var hasPartialState: Bool {
            permissionLimited
                || failed
                || limitReached
                || issues.contains {
                    $0.kind == .changedDuringScan
                }
        }
    }

    private func scan(
        root: ConfiguratorStorageRoot
    ) -> ConfiguratorStorageRootResult {
        let rootPath = root.url.standardizedFileURL.path
        let rootMetadata: ConfiguratorStorageFileMetadata
        do {
            rootMetadata = try fileReader.metadata(at: root.url)
            guard rootMetadata.kind == .directory else {
                throw ConfiguratorStorageReadFailure.failed
            }
        } catch {
            let failure = normalizedFailure(error)
            switch failure {
            case .notFound, .notFoundAfterListing:
                return ConfiguratorStorageRootResult(
                    root: root,
                    status: .missing,
                    logicalBytes: nil,
                    allocatedBytes: nil,
                    fileCount: nil,
                    excludedEntryCount: 0,
                    issues: [])
            case .permissionDenied, .accessDenied:
                return ConfiguratorStorageRootResult(
                    root: root,
                    status: .permissionDenied,
                    logicalBytes: nil,
                    allocatedBytes: nil,
                    fileCount: nil,
                    excludedEntryCount: 0,
                    issues: [
                        issue(
                            kind: .permissionDenied,
                            path: rootPath,
                            detail: "EPERM/EACCES"),
                    ])
            case .changedDuringScan, .failed, .unexpected:
                return ConfiguratorStorageRootResult(
                    root: root,
                    status: .failed,
                    logicalBytes: nil,
                    allocatedBytes: nil,
                    fileCount: nil,
                    excludedEntryCount: 0,
                    issues: [
                        issue(
                            kind: .scanFailed,
                            path: rootPath,
                            detail: "Directory metadata unavailable"),
                    ])
            }
        }

        let state = Traversal()
        state.visitedDirectories.insert(
            "\(rootMetadata.device):\(rootMetadata.inode)")
        do {
            let directory = try fileReader.openDirectory(
                at: root.url,
                expectedDevice: rootMetadata.device,
                expectedInode: rootMetadata.inode)
            traverse(
                directory,
                depth: 0,
                state: state)
        } catch {
            record(
                error,
                at: root.url,
                state: state)
        }

        let status: ConfiguratorStorageRootStatus
        if state.permissionLimited {
            status = state.fileCount > 0
                ? .partialReadable
                : .permissionDenied
        } else if state.issues.contains(where: {
            $0.kind == .changedDuringScan
        }) {
            status = .partialReadable
        } else if state.hasPartialState {
            status = state.fileCount > 0
                ? .partialReadable
                : .failed
        } else if state.fileCount == 0 {
            status = .empty
        } else {
            status = .complete
        }
        let hasKnownUsage = state.fileCount > 0 || status == .empty
        return ConfiguratorStorageRootResult(
            root: root,
            status: status,
            logicalBytes: hasKnownUsage ? state.logicalBytes : nil,
            allocatedBytes: hasKnownUsage ? state.allocatedBytes : nil,
            fileCount: state.fileCount,
            excludedEntryCount: state.excludedEntryCount,
            issues: state.issues)
    }

    private func traverse(
        _ directory: any ConfiguratorStorageDirectoryReading,
        depth: Int,
        state: Traversal
    ) {
        if state.entryCount >= maximumEntriesPerRoot {
            state.limitReached = true
            state.issues.append(
                issue(
                    kind: .limitReached,
                    path: directory.url.path,
                    detail: "ENTRY_LIMIT"))
            return
        }
        do {
            try directory.readChildren { name, metadata in
                guard state.entryCount < maximumEntriesPerRoot else {
                    state.limitReached = true
                    state.issues.append(
                        issue(
                            kind: .limitReached,
                            path: directory.url.path,
                            detail: "ENTRY_LIMIT"))
                    return false
                }
                state.entryCount += 1
                let child =
                    directory.url.appendingPathComponent(name)
                if shouldExclude(child) {
                    state.excludedEntryCount += 1
                } else {
                    switch metadata.kind {
                    case .regularFile:
                        state.fileCount += 1
                        state.logicalBytes += metadata.logicalBytes
                        let inodeKey =
                            "\(metadata.device):\(metadata.inode)"
                        if state.allocatedInodes
                            .insert(inodeKey).inserted {
                            state.allocatedBytes +=
                                metadata.allocatedBytes
                        }
                    case .directory:
                        if depth < maximumDepth {
                            let inodeKey =
                                "\(metadata.device):\(metadata.inode)"
                            if state.visitedDirectories
                                .insert(inodeKey).inserted {
                                do {
                                    try directory.withChildDirectory(
                                        named: name,
                                        metadata: metadata
                                    ) { childDirectory in
                                        traverse(
                                            childDirectory,
                                            depth: depth + 1,
                                            state: state)
                                    }
                                } catch {
                                    record(
                                        error,
                                        at: child,
                                        state: state)
                                }
                            }
                        } else {
                            state.limitReached = true
                            state.issues.append(
                                issue(
                                    kind: .limitReached,
                                    path: child.path,
                                    detail: "DEPTH_LIMIT"))
                        }
                    case .symbolicLink, .other:
                        state.excludedEntryCount += 1
                    }
                }
                if state.entryCount >= maximumEntriesPerRoot {
                    state.limitReached = true
                    state.issues.append(
                        issue(
                            kind: .limitReached,
                            path: directory.url.path,
                            detail: "ENTRY_LIMIT"))
                    return false
                }
                return true
            }
        } catch {
            record(
                error,
                at: directory.url,
                state: state)
        }
    }

    private func record(
        _ error: Error,
        at url: URL,
        state: Traversal
    ) {
        switch normalizedFailure(error) {
        case .permissionDenied, .accessDenied:
            state.permissionLimited = true
            state.issues.append(
                issue(
                    kind: .permissionDenied,
                    path: url.path,
                    detail: "EPERM/EACCES"))
        case .notFound, .notFoundAfterListing:
            state.failed = true
            state.issues.append(
                issue(
                    kind: .changedDuringScan,
                    path: url.path,
                    detail: "ENTRY_CHANGED_DURING_SCAN"))
        case .changedDuringScan:
            state.failed = true
            state.issues.append(
                issue(
                    kind: .changedDuringScan,
                    path: url.path,
                    detail: "DIRECTORY_IDENTITY_CHANGED"))
        case .failed, .unexpected:
            state.failed = true
            state.issues.append(
                issue(
                    kind: .scanFailed,
                    path: url.path,
                    detail: "UNREADABLE_ENTRY"))
        }
    }

    private func processObservations()
        -> [ConfiguratorProcessObservation]
    {
        guard let names = processDiscoverer.processNames() else {
            return ConfiguratorProcessKey.allCases.map {
                ConfiguratorProcessObservation(
                    key: $0,
                    status: .unknown)
            }
        }
        let executablePaths = Set(names.map {
            URL(fileURLWithPath: $0)
                .standardizedFileURL
                .path
        })
        return ConfiguratorProcessKey.allCases.map { key in
            ConfiguratorProcessObservation(
                key: key,
                status: key.approvedExecutablePaths.contains {
                    executablePaths.contains($0)
                }
                    ? .running
                    : .notRunning)
        }
    }

    private func overallCompleteness(
        roots: [ConfiguratorStorageRootResult],
        discoveryIssues: [ConfiguratorStorageAccessIssue]
    ) -> ConfiguratorStorageScanCompleteness {
        if discoveryIssues.contains(where: {
            $0.kind == .permissionDenied
        }) || roots.contains(where: {
            $0.status == .permissionDenied
                || $0.issues.contains {
                    $0.kind == .permissionDenied
                }
        }) {
            return .permissionLimited
        }
        if roots.contains(where: {
            $0.status == .partialReadable
        }) || !discoveryIssues.isEmpty
        {
            return .partial
        }
        let readable = roots.contains {
            $0.status == .complete || $0.status == .empty
        }
        if roots.isEmpty {
            return .failed
        }
        if roots.allSatisfy({ $0.status == .failed }) {
            return .failed
        }
        if roots.contains(where: { $0.status == .failed })
            || readable {
            return roots.contains(where: {
                $0.status == .failed
            }) ? .partial : .complete
        }
        return .complete
    }

    private func normalizedFailure(
        _ error: Error
    ) -> ConfiguratorStorageReadFailure {
        if let failure = error as? ConfiguratorStorageReadFailure {
            return failure
        }
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            switch Int32(nsError.code) {
            case ENOENT: return .notFound
            case EPERM: return .permissionDenied
            case EACCES: return .accessDenied
            case ELOOP, ENOTDIR: return .changedDuringScan
            default: return .failed
            }
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            if underlying.domain == NSPOSIXErrorDomain {
                switch Int32(underlying.code) {
                case ENOENT: return .notFound
                case EPERM: return .permissionDenied
                case EACCES: return .accessDenied
                case ELOOP, ENOTDIR: return .changedDuringScan
                default: return .failed
                }
            }
        }
        return .failed
    }

    private func shouldExclude(_ url: URL) -> Bool {
        let value = url.lastPathComponent.lowercased()
        if value.hasSuffix(".ipsw") {
            return true
        }
        return [
            "appleconfiguratorreferencelab",
            "blueprints",
            "ipsw",
            "ipsws",
        ].contains(value)
    }

    private func issue(
        kind: ConfiguratorStorageAccessIssueKind,
        path: String,
        detail: String
    ) -> ConfiguratorStorageAccessIssue {
        ConfiguratorStorageAccessIssue(
            kind: kind,
            path: path,
            detail: detail)
    }
}

struct ConfiguratorStorageReadOnlyView: View {
    @ObservedObject var model: ConfiguratorResetModel
    @State private var snapshot: ConfiguratorStorageScanSnapshot?
    @State private var isScanning = false
    @State private var errorMessage = ""
    private let scanner = ConfiguratorStorageScanner()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox(L10n.t("Configurator 存储只读盘点")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.t(
                            "仅扫描明确的 Configurator Group Container、App Container、用户缓存和临时目录；不扫描整个 /var/folders、IPSW、Blueprints、客户数据或未知目录。"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button(L10n.t("刷新只读盘点")) {
                                refresh()
                            }
                            .disabled(isScanning)
                            .accessibilityIdentifier(
                                "configurator-storage-refresh")
                            if isScanning {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Spacer()
                        }
                        if let snapshot {
                            Text(completenessText(snapshot))
                                .font(.system(size: 11, weight: .medium))
                            ForEach(
                                Array(snapshot.roots.enumerated()),
                                id: \.offset
                            ) { _, result in
                                rootRow(result)
                            }
                            Divider()
                            Text(L10n.t("相关进程"))
                                .font(.system(size: 11, weight: .medium))
                            ForEach(
                                snapshot.processes,
                                id: \.key.rawValue
                            ) { process in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(
                                            processColor(
                                                process.status))
                                        .frame(width: 7, height: 7)
                                    Text(process.key.displayName)
                                    Spacer()
                                    Text(
                                        processStatusText(
                                            process.status))
                                        .foregroundStyle(.secondary)
                                }
                                .font(.system(size: 11))
                            }
                            if !snapshot.discoveryIssues.isEmpty {
                                Text(L10n.t(
                                    "部分系统区域无法枚举；已知值不会显示为 0 B。"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                            }
                        } else if errorMessage.isEmpty {
                            Text(L10n.t("等待只读盘点…"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        }
                        HStack {
                            Button(L10n.t("清理 Configurator 数据")) {}
                                .disabled(true)
                            Text(L10n.t("待白名单核验授权"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Text(L10n.t(
                            "本页只读。不会删除、移动或写入 Configurator 容器、缓存、Blueprints 或其他用户文件。"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                }

                Divider()
                ConfiguratorSettingsView(model: model)
            }
            .padding(16)
        }
        .task {
            if snapshot == nil {
                refresh()
            }
        }
    }

    private func refresh() {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = ""
        Task {
            let value = await Task.detached(priority: .userInitiated) {
                scanner.scan()
            }.value
            await MainActor.run {
                snapshot = value
                isScanning = false
            }
        }
    }

    @ViewBuilder
    private func rootRow(
        _ result: ConfiguratorStorageRootResult
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.t(result.root.displayName))
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(rootStatusText(result))
                    .font(.system(size: 10))
                    .foregroundStyle(
                        rootStatusColor(result.status))
            }
            Text(displayPath(result.root.url))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
            if result.excludedEntryCount > 0 {
                Text(
                    L10n.t("已排除")
                    + " \(result.excludedEntryCount) "
                    + L10n.t(
                        "个 Reference Lab、Blueprints、IPSW 或未知类型条目。"))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.05)))
    }

    private func completenessText(
        _ snapshot: ConfiguratorStorageScanSnapshot
    ) -> String {
        let logical = snapshot.totalLogicalBytes.map(sizeText) ?? L10n.t("未知")
        let allocated =
            snapshot.totalAllocatedBytes.map(sizeText) ?? L10n.t("未知")
        let state: String
        switch snapshot.completeness {
        case .complete:
            state = L10n.t("扫描完成")
        case .permissionLimited:
            state = L10n.t("部分权限受限")
        case .partial:
            state = L10n.t("部分可读")
        case .failed:
            state = L10n.t("扫描失败")
        }
        return state
            + " · "
            + L10n.t("内容大小：")
            + logical
            + " · "
            + L10n.t("磁盘占用：")
            + allocated
    }

    private func rootStatusText(
        _ result: ConfiguratorStorageRootResult
    ) -> String {
        switch result.status {
        case .complete:
            let logical = result.logicalBytes.map(sizeText) ?? L10n.t("未知")
            let allocated =
                result.allocatedBytes.map(sizeText) ?? L10n.t("未知")
            return L10n.t("扫描完成")
                + " · \(logical) · "
                + L10n.t("磁盘")
                + " \(allocated)"
        case .empty:
            return L10n.t("已成功扫描 · 0 B")
        case .missing:
            return L10n.t("目录不存在")
        case .permissionDenied:
            return L10n.t("权限受限，无法枚举内部占用")
        case .partialReadable:
            let logical = result.logicalBytes.map(sizeText) ?? L10n.t("未知")
            return L10n.t("部分可读")
                + " · "
                + L10n.t("已知至少")
                + " \(logical)"
        case .failed:
            return L10n.t("扫描失败")
        }
    }

    private func rootStatusColor(
        _ status: ConfiguratorStorageRootStatus
    ) -> Color {
        switch status {
        case .complete, .empty: return .secondary
        case .missing: return .secondary
        case .permissionDenied, .partialReadable: return .orange
        case .failed: return .red
        }
    }

    private func processStatusText(
        _ status: ConfiguratorProcessStatus
    ) -> String {
        switch status {
        case .running: return L10n.t("运行中")
        case .notRunning: return L10n.t("未运行")
        case .unknown: return L10n.t("未知")
        }
    }

    private func processColor(
        _ status: ConfiguratorProcessStatus
    ) -> Color {
        switch status {
        case .running: return .green
        case .notRunning: return .secondary
        case .unknown: return .orange
        }
    }

    private func displayPath(_ url: URL) -> String {
        let configuredHome = ProcessInfo.processInfo.environment[
            "MRA_CONFIGURATOR_HOME"
        ]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let home = (
            configuredHome?.isEmpty == false
                ? URL(
                    fileURLWithPath: configuredHome!,
                    isDirectory: true)
                : FileManager.default.homeDirectoryForCurrentUser
        ).standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == home || path.hasPrefix(home + "/") else {
            return path
        }
        return "~" + path.dropFirst(home.count)
    }

    private func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: .file)
    }
}

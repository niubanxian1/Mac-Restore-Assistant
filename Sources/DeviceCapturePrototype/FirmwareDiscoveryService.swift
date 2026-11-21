import Foundation

/// Lightweight discovery policy shared by the model and tests. The actual
/// scan is serialized by `FirmwareDiscoveryService`; this only decides whether
/// a request may start, must be coalesced, or must be deferred during restore.
enum FirmwareDiscoveryAction: Equatable {
    case start
    case coalesce
    case deferForRestore
}

enum FirmwareDiscoveryPolicy {
    static func action(
        isRestoreActive: Bool,
        isScanning: Bool
    ) -> FirmwareDiscoveryAction {
        if isRestoreActive { return .deferForRestore }
        if isScanning { return .coalesce }
        return .start
    }
}

/// Read-only Spotlight discovery. It never traverses `/`: each query is scoped
/// with `mdfind -onlyin <allowed root>`, and roots are capped.
actor FirmwareDiscoveryService {
    static let maximumRoots = 16
    static let maximumResults = 1_024

    private var activeProcess: Process?
    private var cancelled = false

    /// Cancels the current mdfind process; safe to call from the main actor.
    func cancel() {
        cancelled = true
        activeProcess?.terminate()
        activeProcess = nil
    }

    func discoverIPSWURLs(
        roots: [URL],
        home: URL
    ) async -> [URL] {
        var allowed: [URL] = []
        var seenRoots = Set<String>()
        for candidate in [home] + roots {
            let root = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard !isForbiddenFirmwareDiscoveryRoot(root),
                  seenRoots.insert(root.path).inserted,
                  allowed.count < Self.maximumRoots else { continue }
            allowed.append(root)
        }
        cancelled = false
        var result: [URL] = []
        var seen = Set<String>()
        for root in allowed {
            if Task.isCancelled || cancelled { break }
            for url in await mdfind(root: root) {
                if Task.isCancelled || cancelled { break }
                let standardized = url.standardizedFileURL
                guard !isForbiddenFirmwareDiscoveryPath(standardized),
                      isIPSWCandidateName(standardized.lastPathComponent),
                      !isICloudPlaceholderName(standardized.lastPathComponent),
                      seen.insert(standardized.path).inserted else { continue }
                result.append(standardized)
                if result.count >= Self.maximumResults { return result }
            }
        }
        return result
    }

    private func mdfind(root: URL) async -> [URL] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [
            "-onlyin", root.path,
            "kMDItemFSName == '*.ipsw'"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return []
        }
        activeProcess = process
        let data = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: data)
            }
        }
        activeProcess = nil
        guard !cancelled, process.terminationStatus == 0 else { return [] }
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let path = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path, isDirectory: false)
        }
    }
}

/// Reject roots that would turn a "library scan" into a system/whole-volume
/// traversal. User home and explicitly added user folders remain allowed.
func isForbiddenFirmwareDiscoveryRoot(_ url: URL) -> Bool {
    let path = url.resolvingSymlinksInPath().standardizedFileURL.path
    if path == "/" { return true }
    let forbidden = [
        "/System",
        "/Library",
        "/private",
        "/System/Volumes",
        "/Volumes"
    ]
    return forbidden.contains { path == $0 || path.hasPrefix($0 + "/") }
}

func isForbiddenFirmwareDiscoveryPath(_ url: URL) -> Bool {
    if isInsideSystemTemporaryRoot(url) { return true }
    let path = url.standardizedFileURL.path
    let forbidden = [
        "/.Trash/",
        "/.DocumentRevisions-V100/",
        "/System/",
        "/Library/",
        "/private/",
        "/System/Volumes/",
        "/Volumes/"
    ]
    return forbidden.contains { path.contains($0) }
}

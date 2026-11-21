import Foundation

/// Event-driven, debounced watcher for user-added firmware folders. It uses
/// DispatchSource only (no polling) and never reads IPSW contents.
@MainActor
final class FirmwareDirectoryWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var descriptors: [Int32] = []
    private var debounceWork: DispatchWorkItem?
    private(set) var watchedDirectories: [URL] = []
    var onChange: (() -> Void)?

    func update(roots: [URL]) {
        stop()
        let directories = directorySet(roots: roots)
        watchedDirectories = directories
        for directory in directories {
            let fd = open(directory.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .attrib],
                queue: DispatchQueue.global(qos: .utility))
            source.setEventHandler { [weak self] in
                Task { @MainActor in self?.schedule() }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
            descriptors.append(fd)
        }
    }

    func stop() {
        debounceWork?.cancel()
        debounceWork = nil
        sources.forEach { $0.cancel() }
        sources.removeAll()
        descriptors.removeAll()
        watchedDirectories.removeAll()
    }

    private func schedule() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.onChange?() }
        }
        debounceWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + 1.5,
            execute: work)
    }

    private func directorySet(roots: [URL]) -> [URL] {
        var result: [URL] = []
        var seen = Set<String>()
        var pending = roots.filter { !isForbiddenFirmwareDiscoveryRoot($0) }
        var visited = 0
        while let directory = pending.popLast(), visited < 256 {
            visited += 1
            let standardized = directory.resolvingSymlinksInPath().standardizedFileURL
            guard !isForbiddenFirmwareDiscoveryRoot(standardized),
                  seen.insert(standardized.path).inserted else { continue }
            result.append(standardized)
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: standardized,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]) else { continue }
            for child in children {
                guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey]),
                      values.isDirectory == true else { continue }
                pending.append(child)
            }
        }
        return result
    }
}

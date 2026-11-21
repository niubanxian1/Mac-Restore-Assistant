import Foundation

/// P0-N1 offline snapshotter. DEFAULT OFF. Isolated watchRoot only — never vacuums host /tmp.
public actor UpdaterOutputSnapshotter {
    public struct Config: Sendable {
        public var watchRoot: URL
        public var vaultRoot: URL
        public var namePrefix: String
        public var pollIntervalNanoseconds: UInt64
        public var maxActiveDirs: Int
        public init(watchRoot: URL, vaultRoot: URL, namePrefix: String = "updater_output-", pollIntervalNanoseconds: UInt64 = 50_000_000, maxActiveDirs: Int = 128) {
            self.watchRoot = watchRoot
            self.vaultRoot = vaultRoot
            self.namePrefix = namePrefix
            self.pollIntervalNanoseconds = pollIntervalNanoseconds
            self.maxActiveDirs = maxActiveDirs
        }
    }

    private let config: Config
    private let vault: UnboundEvidenceVault
    private var running = false
    private var writeAllowed = true
    private var task: Task<Void, Never>?
    private var seen: Set<String> = []

    public init(config: Config, vault: UnboundEvidenceVault) {
        self.config = config
        self.vault = vault
    }

    public func startWatch() async {
        guard !running else { return }
        running = true
        writeAllowed = true
        await vault.arm()
        task = Task { [weak self] in
            while let self {
                let cont = await self.shouldContinue()
                if !cont { break }
                await self.poll()
                try? await Task.sleep(nanoseconds: await self.config.pollIntervalNanoseconds)
            }
        }
    }

    public func stop() async {
        writeAllowed = false
        running = false
        task?.cancel()
        _ = await task?.value
        task = nil
        await vault.seal()
    }

    private func shouldContinue() -> Bool { running && writeAllowed }

    private func poll() async {
        guard writeAllowed else { return }
        let kids = (try? FileManager.default.contentsOfDirectory(at: config.watchRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for url in kids {
            guard url.lastPathComponent.hasPrefix(config.namePrefix) else { continue }
            let key = url.standardizedFileURL.path
            if seen.contains(key) { continue }
            if seen.count >= config.maxActiveDirs { break }
            seen.insert(key)
            _ = await vault.ingestDirectory(url.standardizedFileURL)
        }
    }

    public func entries() async -> [UnboundEvidenceVault.Entry] {
        await vault.currentEntries()
    }
}

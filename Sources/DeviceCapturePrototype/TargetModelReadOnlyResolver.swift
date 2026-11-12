import Foundation

/// Read-only identity enrichment for normal USB Macs.
///
/// The USB node for a booted Mac exposes only `USB Product Name = Mac`; it
/// does not expose `Mac16,13`. Apple Configurator's `cfgutil list` does expose
/// `Type` plus ECID/Location. The query is optional display enrichment: it runs
/// off the main actor, at most once per 30 seconds per unknown ECID/location, and never blocks
/// port observation or a send path.
enum TargetModelReadOnlyResolver {
    static let source = "cfgutil list（只读枚举）"

    struct Hint: Equatable {
        let modelIdentifier: String
        let ecid: String?
        let locationID: String?
    }

    private static let lock = NSLock()
    private static var cachedHints: [Hint] = []
    private static var queriedIdentities: [String: Date] = [:]
    private static let retryInterval: TimeInterval = 30
    private static var queryInFlight = false

    /// Synchronous display-only merge with hints already in hand. This is what
    /// observation uses; it never spawns `cfgutil`.
    static func enrich(_ devices: [ObservedDevice], hints providedHints: [Hint]? = nil) -> [ObservedDevice] {
        guard devices.contains(where: { $0.modelIdentifier == nil }) else { return devices }
        let hints = providedHints ?? currentHints()
        guard !hints.isEmpty else { return devices }
        return devices.map { device in
            guard device.modelIdentifier == nil else { return device }
            // If the observation has an ECID, only an ECID match may supply a
            // model. A stale location hint must never follow a different ECID.
            let hint: Hint?
            if let deviceECID = device.ecid, !deviceECID.isEmpty {
                hint = hints.first { hint in
                    guard let hintECID = hint.ecid, !hintECID.isEmpty else { return false }
                    return hintECID.caseInsensitiveCompare(deviceECID) == .orderedSame
                }
            } else {
                // Normal-boot Mac USB nodes often omit ECID while cfgutil
                // reports it. Accept a location match only when it is unique;
                // ambiguous or stale-looking locations remain unresolved.
                let locationMatches = hints.filter { hint in
                    hint.locationID?.caseInsensitiveCompare(device.locationID) == .orderedSame
                }
                hint = locationMatches.count == 1 ? locationMatches[0] : nil
            }
            guard let hint else { return device }
            var copy = device
            copy.modelIdentifier = hint.modelIdentifier
            copy.modelSource = source
            return copy
        }
    }

    /// Mark an unknown device for one background cfgutil query. Returns false
    /// when a query is already in flight, when this identity was already
    /// queried, or when no unknown device exists. No polling is introduced.
    static func shouldStartQuery(for devices: [ObservedDevice], now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !queryInFlight else { return false }
        let unknown = devices.filter { $0.modelIdentifier == nil }
        let new = unknown.filter { device in
            guard let last = queriedIdentities[identityKey(device)] else { return true }
            return now.timeIntervalSince(last) >= retryInterval
        }
        guard let first = new.first else { return false }
        for device in new { queriedIdentities[identityKey(device)] = now }
        _ = first
        queryInFlight = true
        return true
    }

    /// Run one read-only enumeration off the main actor. A missing binary,
    /// a timeout, or an empty result simply leaves models unresolved.
    static func refreshHints() async -> [Hint] {
        let fresh = await Task.detached(priority: .utility) {
            readCfgutil()
        }.value
        lock.lock()
        cachedHints = fresh
        queryInFlight = false
        lock.unlock()
        return fresh
    }

    static func finishQueryForTesting(hints: [Hint]) {
        lock.lock()
        cachedHints = hints
        queryInFlight = false
        lock.unlock()
    }

    static func resetForTesting() {
        lock.lock()
        cachedHints = []
        queriedIdentities = [:]
        queryInFlight = false
        lock.unlock()
    }

    static func currentHints() -> [Hint] {
        lock.lock()
        defer { lock.unlock() }
        return cachedHints
    }

    static func parse(_ text: String) -> [Hint] {
        let pattern = #"Type:\s*([^\t\r\n]+).*?ECID:\s*(0x[0-9A-Fa-f]+|[0-9A-Fa-f]+).*?Location:\s*(0x[0-9A-Fa-f]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        var hints: [Hint] = []
        for line in text.split(separator: "\n") {
            let string = String(line)
            let range = NSRange(string.startIndex..<string.endIndex, in: string)
            guard let match = regex.firstMatch(in: string, options: [], range: range),
                  let typeRange = Range(match.range(at: 1), in: string),
                  let ecidRange = Range(match.range(at: 2), in: string),
                  let locationRange = Range(match.range(at: 3), in: string) else { continue }
            let type = String(string[typeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let model = TargetModelCatalog.identifier(from: type) else { continue }
            let ecid = ECIDIdentity(hex: String(string[ecidRange]))?.canonicalHex
            let locationRaw = String(string[locationRange])
            let hex = locationRaw.lowercased().hasPrefix("0x") ? String(locationRaw.dropFirst(2)) : locationRaw
            let location = Int(hex, radix: 16).map { String(format: "%08X", $0) }
            hints.append(Hint(modelIdentifier: model, ecid: ecid, locationID: location))
        }
        return hints
    }

    private static func identityKey(_ device: ObservedDevice) -> String {
        if let ecid = device.ecid, !ecid.isEmpty { return "ecid:\(ecid.uppercased())" }
        return "loc:\(device.locationID)"
    }

    private static func readCfgutil() -> [Hint] {
        let candidates = [
            "/usr/local/bin/cfgutil",
            "/Applications/Apple Configurator.app/Contents/MacOS/cfgutil",
        ]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return []
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["list"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 4, execute: watchdog)
        defer { watchdog.cancel() }
        do {
            try process.run()
        } catch {
            return []
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return [] }
        return parse(text)
    }
}

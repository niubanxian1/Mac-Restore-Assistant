import Foundation

struct PortHistoryRecord: Codable, Equatable {
    var lastECID: String?
    var lastMode: String
    var lastSeenAt: Date
    var controller: String?
    var portNumber: Int?
    var rid: Int?
}

struct PortHistoryDocument: Codable, Equatable {
    var schemaVersion: Int
    var hostModel: String
    var slotMapFingerprint: String
    var slots: [String: PortHistoryRecord]

    static let currentSchemaVersion = 1
}

struct PendingDFUAssociation: Equatable {
    var slotID: String
    var operationID: String
    var sentAt: Date
    var windowEnd: Date
}

enum PortHistoryError: Error, Equatable {
    case unreadable
    case unwritable
}

/// Display-only persistence keyed by the host's built-in slot IDs.
/// Never consulted as a send precondition or auto-selection source.
final class PortHistoryStore {
    private let url: URL
    private let fileManager: FileManager
    private let currentHostModel: String
    private let currentFingerprint: String
    private(set) var document: PortHistoryDocument
    private(set) var availabilityMessage: String = ""
    private(set) var isUnavailable: Bool = false
    private(set) var pendingAssociations: [PendingDFUAssociation] = []
    var associationWindow: TimeInterval

    init(fileURL: URL,
         hostModel: String,
         slotMapFingerprint: String,
         associationWindow: TimeInterval = 30,
         fileManager: FileManager = .default) {
        self.url = fileURL
        self.fileManager = fileManager
        self.currentHostModel = hostModel
        self.currentFingerprint = slotMapFingerprint
        self.associationWindow = associationWindow
        self.document = PortHistoryDocument(
            schemaVersion: PortHistoryDocument.currentSchemaVersion,
            hostModel: hostModel,
            slotMapFingerprint: slotMapFingerprint,
            slots: [:])
        loadFromDisk()
    }

    static func defaultURL() -> URL {
        AppSupportLocations.portHistoryURL()
    }

    static func fingerprint(hostModel: String, layout: BuiltInLayout?) -> String {
        guard let layout else { return "\(hostModel)|no-builtin-layout" }
        let slots = layout.slots
            .map { "\($0.slot):\($0.portNumber ?? -1):\($0.rid ?? -1):\($0.binding)" }
            .sorted()
            .joined(separator: ";")
        return "\(hostModel)|\(slots)"
    }

    func record(forSlot slotID: String) -> PortHistoryRecord? {
        guard matchesCurrentMapping() else { return nil }
        return document.slots[slotID]
    }

    func matchesCurrentMapping(hostModel: String? = nil, fingerprint: String? = nil) -> Bool {
        let host = hostModel ?? currentHostModel
        let fp = fingerprint ?? currentFingerprint
        return !isUnavailable
            && document.hostModel == host
            && document.slotMapFingerprint == fp
    }

    /// Update history only for a clearly attributed Apple Mobile Device DFU / Recovery observation.
    @discardableResult
    func updateIfEligible(slotID: String,
                          product: String,
                          mode: ObservedDeviceMode,
                          ecid: String?,
                          seenAt: Date,
                          controller: String?,
                          portNumber: Int?,
                          rid: Int?,
                          hostModel: String,
                          fingerprint: String) -> Bool {
        guard isEligibleHistoryObservation(product: product, mode: mode) else { return false }
        guard ensureWritableMapping(hostModel: hostModel, fingerprint: fingerprint) else { return false }
        let modeTitle = mode.title
        document.slots[slotID] = PortHistoryRecord(
            lastECID: ecid,
            lastMode: modeTitle,
            lastSeenAt: seenAt,
            controller: controller,
            portNumber: portNumber,
            rid: rid)
        return persist()
    }

    func isEligibleHistoryObservation(product: String, mode: ObservedDeviceMode) -> Bool {
        guard product.contains("Apple Mobile Device") else { return false }
        switch mode {
        case .dfu, .recovery: return true
        case .connected, .unknown: return false
        }
    }

    /// Disconnect must keep the last record and must not rewrite lastSeenAt or invent a mode.
    func preserveOnDisconnect(slotID: String) {
        _ = slotID
    }

    func recordDFUSend(slotID: String, operationID: String, sentAt: Date) {
        pendingAssociations.removeAll { $0.slotID == slotID }
        pendingAssociations.append(PendingDFUAssociation(
            slotID: slotID,
            operationID: operationID,
            sentAt: sentAt,
            windowEnd: sentAt.addingTimeInterval(associationWindow)))
    }

    func invalidateAssociation(slotID: String) {
        pendingAssociations.removeAll { $0.slotID == slotID }
    }

    func invalidateAllAssociations() {
        pendingAssociations.removeAll()
    }

    func pruneAssociations(at now: Date) {
        pendingAssociations.removeAll { $0.windowEnd <= now }
    }

    /// A single still-valid pending DFU send may assist display attribution.
    /// Multiple live targets, expiry, or an already-bound conflicting observation must not write history.
    func singleValidAssociation(at now: Date) -> PendingDFUAssociation? {
        pruneAssociations(at: now)
        guard pendingAssociations.count == 1 else { return nil }
        return pendingAssociations[0]
    }

    func displayStatus(slotID: String,
                       hostModel: String,
                       fingerprint: String,
                       isPresent: Bool,
                       presentModeTitle: String? = nil) -> String {
        if isPresent, let presentModeTitle, !presentModeTitle.isEmpty {
            return presentModeTitle
        }
        guard matchesCurrentMapping(hostModel: hostModel, fingerprint: fingerprint),
              let record = document.slots[slotID], !record.lastMode.isEmpty else {
            return "无设备"
        }
        if isPresent {
            return record.lastMode
        }
        return "当前未识别设备 · 上次 \(record.lastMode)"
    }

    private func ensureWritableMapping(hostModel: String, fingerprint: String) -> Bool {
        if isUnavailable { return false }
        if document.hostModel != hostModel || document.slotMapFingerprint != fingerprint {
            // Host or slot map changed: do not apply the previous machine's history.
            document = PortHistoryDocument(
                schemaVersion: PortHistoryDocument.currentSchemaVersion,
                hostModel: hostModel,
                slotMapFingerprint: fingerprint,
                slots: [:])
        }
        return true
    }

    private func loadFromDisk() {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder.portHistory.decode(PortHistoryDocument.self, from: data)
            document = decoded
            isUnavailable = false
            availabilityMessage = ""
        } catch {
            isUnavailable = true
            availabilityMessage = "端口历史暂不可用（文件无法读取）；不影响发送与采集。"
        }
    }

    @discardableResult
    func persist() -> Bool {
        if isUnavailable { return false }
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(document)
            let temp = url.deletingLastPathComponent()
                .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
            try data.write(to: temp, options: .withoutOverwriting)
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temp)
            } else {
                try fileManager.moveItem(at: temp, to: url)
            }
            isUnavailable = false
            availabilityMessage = ""
            return true
        } catch {
            isUnavailable = true
            availabilityMessage = "端口历史暂不可用（无法写入）；不影响发送与采集。"
            return false
        }
    }

    func reload() {
        isUnavailable = false
        availabilityMessage = ""
        loadFromDisk()
    }
}

extension JSONDecoder {
    static var portHistory: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

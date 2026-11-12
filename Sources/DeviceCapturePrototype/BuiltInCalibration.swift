import Foundation

struct BuiltInSlot: Codable, Hashable {
    let slot: String
    let face: String
    let portNumber: Int?
    let rid: Int?
    let binding: String
    let physicalName: String?

    var faceText: String {
        switch face {
        case "LEFT": return "左侧"
        case "RIGHT": return "右侧"
        case "FRONT": return "正面"
        case "REAR": return "背面"
        default: return face
        }
    }
    var displayLabel: String { physicalName ?? "\(faceText)接口 \(slot)" }
}

struct BuiltInLayout: Codable, Hashable {
    let displayName: String
    let sourceFile: String
    let slots: [BuiltInSlot]
    let partial: Bool
    let skippedSlots: [String]
    let generatedAt: String
}

private struct BuiltInDatabase: Codable {
    let hosts: [String: BuiltInLayout]
    let sharedCandidates: [SharedCandidate]?
    let notes: [String]?
}

struct SharedCandidate: Codable, Hashable {
    let models: [String]
    let basis: String
    /// Only an Owner-confirmed shared physical layout is green in the bottom
    /// lamp. Existing same-mold candidates remain unconfirmed (orange).
    let confirmed: Bool?

    init(models: [String], basis: String, confirmed: Bool? = nil) {
        self.models = models
        self.basis = basis
        self.confirmed = confirmed
    }

    var isConfirmed: Bool { confirmed == true }
}

enum BuiltInCalibration {
    static func currentHostModel() -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/sysctl")
        p.arguments = ["-n", "hw.model"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return "unknown" }
        p.waitUntilExit()
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "unknown" : text
    }

    static func load() -> (database: [String: BuiltInLayout], shared: [SharedCandidate], notes: [String], host: String) {
        var url: URL?
        if let bundled = Bundle.main.url(forResource: "builtin-calibrations", withExtension: "json") {
            url = bundled
        } else if let source = Bundle.module.url(forResource: "builtin-calibrations", withExtension: "json") {
            url = source
        } else {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let candidate = cwd.appendingPathComponent("Resources/builtin-calibrations.json")
            if FileManager.default.fileExists(atPath: candidate.path) { url = candidate }
        }
        guard let url, let data = try? Data(contentsOf: url),
              let db = try? JSONDecoder().decode(BuiltInDatabase.self, from: data) else {
            return ([:], [], ["未能读取内置校准数据"], currentHostModel())
        }
        return (db.hosts, db.sharedCandidates ?? [], db.notes ?? [], currentHostModel())
    }
}

import Foundation

/// Pure, display-only keyword classifier for the RLM preview. It never reads
/// files, never touches capture state, and never gates start/stop/export.
struct LogErrorClueGroup: Equatable {
    let title: String
    let count: Int
}

struct LogErrorClueSummary: Equatable {
    let hitCount: Int
    let groups: [LogErrorClueGroup]
    var isEmpty: Bool { hitCount == 0 }
}

enum LogErrorClueClassifier {
    static let maximumLines = 20_000

    private static let subsystems: [(String, [String])] = [
        ("HDMI/DCP/Retimer", ["hdmi", "dcp", "retimer"]),
        ("NAND/NVMe", ["nand", "nvme"]),
        ("SEP", ["sep"]),
        ("SMC", ["smc"]),
        ("I2C/NACK/timeout", ["i2c", "nack", "timeout"]),
    ]

    private static let errorMarkers = [
        "error", "failed", "failure", "fault", "panic", "nack",
        "timeout", "timed out", "0xe", "0x8", "errno"
    ]

    static func isErrorLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        guard errorMarkers.contains(where: { lower.contains($0) }) else {
            return false
        }
        return true
    }

    static func summarize(_ lines: [String]) -> LogErrorClueSummary {
        var counts: [String: Int] = [:]
        var hits = 0
        for line in lines.prefix(maximumLines) where isErrorLine(line) {
            hits += 1
            let lower = line.lowercased()
            if let group = subsystems.first(where: { _, keys in
                keys.contains(where: lower.contains)
            }) {
                counts[group.0, default: 0] += 1
            } else {
                counts["其他错误", default: 0] += 1
            }
        }
        let groups = counts.keys.sorted().compactMap { key in
            counts[key].map { LogErrorClueGroup(title: key, count: $0) }
        }
        return LogErrorClueSummary(hitCount: hits, groups: groups)
    }
}

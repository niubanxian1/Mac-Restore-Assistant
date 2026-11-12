import Foundation

/// Minimal parser for `log stream --style compact` lines.
///
/// Shape: `2026-10-30 19:06:30.963 Df process[pid:tid] (Category) message`.
/// The parser is deliberately forgiving: an unparsed timestamp degrades to the
/// observation time and is recorded as such, never silently dropped.
public enum LogLineParser {
    public struct Parsed: Sendable, Equatable {
        public let timestampUTC: Date?
        public let process: String
        public let message: String
        public let rawLine: String
    }

    public static func parse(_ line: String) -> Parsed {
        let body = line.hasPrefix("\t") ? line.trimmingCharacters(in: .whitespaces) : line
        let tokens = body.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
        guard tokens.count >= 3 else {
            return Parsed(timestampUTC: nil, process: "unknown", message: body, rawLine: line)
        }

        let stamp = "\(tokens[0]) \(tokens[1])"
        let processToken = String(tokens[2])
        let process = processToken.split(separator: "[").first.map(String.init) ?? processToken
        let message = tokens.count > 4 ? String(tokens[4]) : ""
        return Parsed(
            timestampUTC: parseTimestamp(stamp),
            process: process,
            message: message,
            rawLine: line
        )
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    static func parseTimestamp(_ text: String) -> Date? {
        formatter.date(from: text)
    }
}

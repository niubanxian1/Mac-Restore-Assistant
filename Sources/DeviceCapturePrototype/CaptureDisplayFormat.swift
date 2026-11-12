import Foundation

/// Display-only formatting for the capture pane meter.
/// Does not change stored byte counts or elapsed seconds.
enum CaptureDisplayFormat {
    static func duration(seconds: Int) -> String { L10n.duration(seconds: seconds) }

    /// Decimal SI units (1000), never 1024 / KiB. 1000 GB and above stay in GB.
    static func dataSize(bytes: Int) -> String {
        dataSize(bytes: Int64(max(0, bytes)))
    }

    static func dataSize(bytes: Int64) -> String {
        let value = max(Int64(0), bytes)
        if value < 1000 {
            return "\(value) B"
        }
        if value < 1_000_000 {
            return scaled(value, scale: 1_000, unit: "KB")
        }
        if value < 1_000_000_000 {
            return scaled(value, scale: 1_000_000, unit: "MB")
        }
        return scaled(value, scale: 1_000_000_000, unit: "GB")
    }

    /// Round half-up to two decimal places of `value / scale`, then strip
    /// trailing zeros and a dangling decimal point.
    private static func scaled(_ value: Int64, scale: Int64, unit: String) -> String {
        let hundredths = (value * 100 + scale / 2) / scale
        let text: String
        if hundredths % 100 == 0 {
            text = "\(hundredths / 100)"
        } else if hundredths % 10 == 0 {
            text = "\(hundredths / 100).\( (hundredths / 10) % 10 )"
        } else {
            text = "\(hundredths / 100)." + String(format: "%02d", hundredths % 100)
        }
        return "\(text) \(unit)"
    }
}

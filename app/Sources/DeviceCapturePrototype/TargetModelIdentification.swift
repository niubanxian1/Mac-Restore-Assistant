import Foundation

/// Target-model identity accepted only from explicit evidence.
///
/// Reuses the old Mac Restore Assistant `MODEL_MAP` / `friendly_model`
/// behaviour: a model is shown only when a descriptor supplies a real
/// machine identifier such as `MacBookPro18,2`. A generic USB product
/// string (`Mac`, `Apple Mobile Device (DFU Mode)`) is never a model, and
/// the host calibration record is never used to guess the target model.
enum TargetModelCatalog {
    /// Old-project identifier → Owner-facing Chinese marketing name.
    static let marketingNames: [String: String] = [
        "MacBookPro18,1": "MacBook Pro（16 英寸，2021 年）",
        "MacBookPro18,2": "MacBook Pro（16 英寸，2021 年）",
        "MacBookPro18,3": "MacBook Pro（14 英寸，2021 年）",
        "MacBookPro18,4": "MacBook Pro（14 英寸，2021 年）",
        "MacBookPro17,1": "MacBook Pro（13 英寸，M1，2020 年）",
        "MacBookPro16,1": "MacBook Pro（16 英寸，2019 年）",
        "MacBookPro16,4": "MacBook Pro（16 英寸，2019 年）",
        "MacBookPro16,2": "MacBook Pro（13 英寸，2020 年）",
        "MacBookPro16,3": "MacBook Pro（13 英寸，2020 年）",
        "Mac14,5": "MacBook Pro（14 英寸，2023 年）",
        "Mac14,9": "MacBook Pro（14 英寸，2023 年）",
        "Mac14,6": "MacBook Pro（16 英寸，2023 年）",
        "Mac14,10": "MacBook Pro（16 英寸，2023 年）",
        "Mac14,7": "MacBook Pro（13 英寸，M2，2022 年）",
        "Mac15,3": "MacBook Pro（14 英寸，M3，2023 年）",
        "Mac15,6": "MacBook Pro（14 英寸，M3 Pro/Max，2023 年）",
        "Mac15,7": "MacBook Pro（16 英寸，M3 Pro/Max，2023 年）",
        "Mac15,8": "MacBook Pro（14 英寸，M3 Pro/Max，2023 年）",
        "Mac15,9": "MacBook Pro（16 英寸，M3 Pro/Max，2023 年）",
        "Mac15,10": "MacBook Pro（14 英寸，M3 Pro/Max，2023 年）",
        "Mac15,11": "MacBook Pro（16 英寸，M3 Pro/Max，2023 年）",
        "Mac16,1": "MacBook Pro（14 英寸，M4，2024 年）",
        "Mac16,5": "MacBook Pro（16 英寸，M4 Pro/Max，2024 年）",
        "Mac16,6": "MacBook Pro（14 英寸，M4 Pro/Max，2024 年）",
        "Mac16,7": "MacBook Pro（16 英寸，M4 Pro/Max，2024 年）",
        "Mac16,8": "MacBook Pro（14 英寸，M4 Pro/Max，2024 年）",
        "Mac17,2": "MacBook Pro（14 英寸，M5，2025 年）",
        "Mac17,6": "MacBook Pro（16 英寸，M5 Pro/Max，2026 年）",
        "Mac17,7": "MacBook Pro（14 英寸，M5 Pro/Max，2026 年）",
        "Mac17,8": "MacBook Pro（16 英寸，M5 Pro/Max，2026 年）",
        "Mac17,9": "MacBook Pro（14 英寸，M5 Pro/Max，2026 年）",
        "MacBookAir10,1": "MacBook Air（M1，2020 年）",
        "Mac14,2": "MacBook Air（M2，2022 年）",
        "Mac14,15": "MacBook Air（15 英寸，M2，2023 年）",
        "Mac15,12": "MacBook Air（13 英寸，M3，2024 年）",
        "Mac15,13": "MacBook Air（15 英寸，M3，2024 年）",
        "Mac16,12": "MacBook Air（13 英寸，M4，2025 年）",
        "Mac16,13": "MacBook Air（15 英寸，M4，2025 年）",
        "Mac17,3": "MacBook Air（13 英寸，M5）",
        "Mac17,4": "MacBook Air（15 英寸，M5）",
        "Macmini9,1": "Mac mini（M1，2020 年）",
        "Mac14,3": "Mac mini（2023 年）",
        "Mac14,12": "Mac mini（2023 年）",
        "Mac16,10": "Mac mini（2024 年）",
        "Mac16,11": "Mac mini（2024 年）",
        "Mac17,16": "Mac mini（M5 Pro）",
        "Mac18,5": "Mac mini（M6）",
        "Mac13,1": "Mac Studio（2022 年）",
        "Mac13,2": "Mac Studio（2022 年）",
        "Mac14,13": "Mac Studio（2023 年）",
        "Mac14,14": "Mac Studio（2023 年）",
        "Mac15,14": "Mac Studio（2025 年）",
        "Mac16,9": "Mac Studio（2025 年）",
        "Mac17,14": "Mac Studio（M5 Max）",
        "Mac17,15": "Mac Studio（M5 Ultra）",
    ]

    private static let identifierPattern =
        #"^(?:MacBookPro|MacBookAir|MacBook|iMac|Macmini|MacPro|MacStudio|Mac)\d+,\d+$"#

    /// Accepts only a real machine identifier. USB product text, mode names
    /// and ECID strings are rejected on purpose.
    static func identifier(from raw: String?) -> String? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lowered = text.lowercased()
        if lowered.contains("apple mobile device") { return nil }
        if lowered.contains("dfu") || lowered.contains("recovery") { return nil }
        if lowered.contains("ecid") { return nil }
        guard text.range(of: identifierPattern, options: .regularExpression) != nil else {
            return nil
        }
        return text
    }

    static func displayName(for identifier: String) -> String {
        marketingNames[identifier] ?? identifier
    }
}

import Foundation

struct HelperPayloadTriplet: Equatable {
    let helperSHA256: String
    let backendSHA256: String
    let plistSHA256: String
}

/// Identification only for the Helper / environment page.
/// Not part of control-command Admission.
enum KnownHelperManifest {
    static let expectedCurrentHelperSHA256 =
        "c81917fd26bbcd20b023569a0e6e5abddd510c0a0994d18ed482132b82ac0d58"
    static let expectedCurrentHelperCDHash =
        "20cb6422c80993176a92eda51feba45f59f1802a"
    static let expectedCurrentBackendSHA256 =
        "ea512931a2793de2bc18fcd7b2b2a539d7964336b2696d75662b7d4cf34d2c15"
    static let expectedCurrentBackendCDHash =
        "18dbdc9cad4fc02edf36769c569530413dce5458"
    static let expectedCurrentPlistSHA256 =
        "d30e8029aacd1c80e093380a94fe52edb5d378eb90aeed9dc9e2ec6a03805e3e"

    static let currentTriplet = HelperPayloadTriplet(
        helperSHA256: expectedCurrentHelperSHA256,
        backendSHA256: expectedCurrentBackendSHA256,
        plistSHA256: expectedCurrentPlistSHA256)

    /// Only real payload triplets verified in local historical packages are
    /// accepted for migration. An arbitrary mixture of known hashes is not a
    /// known installation.
    static let knownLegacyTriplets: [HelperPayloadTriplet] = [
        // T1205Z
        HelperPayloadTriplet(
            helperSHA256: "5ed74e1fe877a63ccacf683772c1f735d8b88d14fa0786e2c2f997db255b3aec",
            backendSHA256: "2a00942530b8c28916e55dfc9984c1284f651fddd00d99a4398208b930530a7d",
            plistSHA256: expectedCurrentPlistSHA256),
        // T1306Z
        HelperPayloadTriplet(
            helperSHA256: "44d54a4cfdd0a31b7c65c87db6dfa9599e67e1fa4aeb55a4a811b178f24b5da8",
            backendSHA256: "2a00942530b8c28916e55dfc9984c1284f651fddd00d99a4398208b930530a7d",
            plistSHA256: expectedCurrentPlistSHA256),
        // macOS 26 test payloads before the current diagnostic backend.
        HelperPayloadTriplet(
            helperSHA256: "916b78cb6b95ca8a152f625d4f73c46f3142255fd85f6c12be6f19e3f62f5ac9",
            backendSHA256: "f5bc28e04299f77b8d99e425772c89b2ca54dabd25df2218b491f0363ec32aeb",
            plistSHA256: expectedCurrentPlistSHA256),
        HelperPayloadTriplet(
            helperSHA256: "197d1f334536d9719598db4ccff46cf4b79f04bf3b05629c077c6f1536252ebe",
            backendSHA256: "f5bc28e04299f77b8d99e425772c89b2ca54dabd25df2218b491f0363ec32aeb",
            plistSHA256: expectedCurrentPlistSHA256),
        // Current Helper with a measured older backend.
        HelperPayloadTriplet(
            helperSHA256: expectedCurrentHelperSHA256,
            backendSHA256: "b03160fd14e0424a180c460f4fdd142767fdf8d26bdef0e7a1f1f7b01ad4d418",
            plistSHA256: expectedCurrentPlistSHA256),
        HelperPayloadTriplet(
            helperSHA256: expectedCurrentHelperSHA256,
            backendSHA256: "7105ddd2ce10f735d86747068c68749bce728f5a50502b6d093b2957a69dba25",
            plistSHA256: expectedCurrentPlistSHA256)
    ]

    /// Measured T1205Z helper, confirmed against the T1306Z ticket and release evidence.
    static let knownLegacyHelperSHA256 = [
        "5ed74e1fe877a63ccacf683772c1f735d8b88d14fa0786e2c2f997db255b3aec",
        // The 27.2 T1306Z helper currently installed on the build Mac. A macOS
        // 26 test package must still recognize it for display, while offering
        // the rebuilt 26.0 payload as the upgrade.
        "44d54a4cfdd0a31b7c65c87db6dfa9599e67e1fa4aeb55a4a811b178f24b5da8",
        // The 26.0 helper built before the fixed resetUsbd action.
        "916b78cb6b95ca8a152f625d4f73c46f3142255fd85f6c12be6f19e3f62f5ac9",
        // Helper 0.2.4 with resetUsbd but without recovery.
        "197d1f334536d9719598db4ccff46cf4b79f04bf3b05629c077c6f1536252ebe"
    ]

    static let knownLegacyBackendSHA256 = [
        "2a00942530b8c28916e55dfc9984c1284f651fddd00d99a4398208b930530a7d",
        "f5bc28e04299f77b8d99e425772c89b2ca54dabd25df2218b491f0363ec32aeb",
        "b03160fd14e0424a180c460f4fdd142767fdf8d26bdef0e7a1f1f7b01ad4d418",
        // 26.0 backend with WaitConnected, before raw DVEn diagnostics.
        "7105ddd2ce10f735d86747068c68749bce728f5a50502b6d093b2957a69dba25"
    ]

    static func classifyHelper(sha256: String?) -> HelperPayloadClass {
        guard let sha256, !sha256.isEmpty else { return .missing }
        if sha256 == expectedCurrentHelperSHA256 { return .current }
        if knownLegacyHelperSHA256.contains(sha256) { return .knownLegacy }
        return .unknown
    }

    static func isCurrentTriplet(helper: String?, backend: String?, plist: String?) -> Bool {
        guard let helper, let backend, let plist else { return false }
        return currentTriplet == HelperPayloadTriplet(
            helperSHA256: helper, backendSHA256: backend, plistSHA256: plist)
    }

    static func isKnownLegacyTriplet(helper: String?, backend: String?, plist: String?) -> Bool {
        guard let helper, let backend, let plist else { return false }
        return knownLegacyTriplets.contains(
            HelperPayloadTriplet(helperSHA256: helper, backendSHA256: backend, plistSHA256: plist))
    }
}

enum HelperPayloadClass: String, Equatable {
    case missing
    case current
    case knownLegacy
    case unknown
}

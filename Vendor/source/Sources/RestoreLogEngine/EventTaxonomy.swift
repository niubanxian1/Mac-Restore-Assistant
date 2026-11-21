import Foundation

/// Versioned, read-only event vocabulary.
///
/// Every rule below was observed on a real macOS 27.2 host with Apple
/// Configurator performing a restore (evidence: `rlm-baseline-20261030T1908`).
/// Nothing here is inferred from a tutorial.
///
/// Rule order matters: error rules are evaluated before phase rules so a line
/// carrying both an error and a phase marker is classified as an error.
/// FIX-002 prepends explicit restore terminal needles (success/fail domains)
/// without removing prior rules.
public struct EventRule: Sendable, Equatable {
    public let id: String
    public let tier: EventTier
    public let needles: [String]
    public let note: String
    public let caseInsensitive: Bool

    public init(
        id: String,
        tier: EventTier,
        needles: [String],
        note: String,
        caseInsensitive: Bool = false
    ) {
        self.id = id
        self.tier = tier
        self.needles = needles
        self.note = note
        self.caseInsensitive = caseInsensitive
    }

    func matches(_ line: String) -> Bool {
        if caseInsensitive {
            let low = line.lowercased()
            return needles.contains { low.contains($0.lowercased()) }
        }
        return needles.contains { line.contains($0) }
    }
}

public enum EventTaxonomy {
    public static let version = "restore-events-v1"

    public static let rules: [EventRule] = [
        // FIX-002 terminals (BOT_B A1/A2/A3/A4/A17) — before generic "failed to"
        EventRule(
            id: "restore.terminal.failure",
            tier: .t5Error,
            needles: [
                "Restore failed",
                "AMRestoreErrorDomain",
                "RamrodErrorDomain",
            ],
            note: "Observed restore terminal failure chain. progress -1 is NOT this rule."
        ),
        EventRule(
            id: "restore.terminal.success",
            tier: .t1Device,
            needles: [
                "Restore succeeded",
                "was successful",
                "Restore complete",
            ],
            note: "Positive restore terminals; matched case-insensitively.",
            caseInsensitive: true
        ),
        EventRule(
            id: "restore.updater.mcdp29xx",
            tier: .t5Error,
            needles: ["update_mcdp29xx", "mcdp29xx"],
            note: "Named ramrod updater step. Does not alone prove chip damage."
        ),
        EventRule(
            id: "restore.updater.madea",
            tier: .t5Error,
            needles: ["update_madea", "Wrote updater output", "updater_output"],
            note: "Madea/updater provenance breadcrumb; not chip-damage proof."
        ),
        EventRule(
            id: "usb.deviceRequest.error",
            tier: .t5Error,
            needles: ["AMRUSBDevice error", "command device request for"],
            note: "USB control-transfer failures; carries IOKit return codes."
        ),
        EventRule(
            id: "amai.personalization.error",
            tier: .t5Error,
            needles: ["_AMAuthInstall", "personalization", "Failed to create recovery OS variant"],
            note: "TSS / build-identity failures."
        ),
        EventRule(
            id: "restore.failure",
            tier: .t5Error,
            needles: ["failed to", "Failure to", "unable to open"],
            note: "Generic failure lines; kept because they precede the exit code."
        ),
        EventRule(
            id: "device.stateMachine",
            tier: .t1Device,
            needles: ["Created state machine for device", "State Machine Dump, status:"],
            note: "DFU -> Recovery -> RestoreOS progression."
        ),
        EventRule(
            id: "device.connect",
            tier: .t1Device,
            needles: ["_AMDFUDeviceConnected", "_AMRestoreDeviceConnected"],
            note: "Device enumeration in DFU / restore mode."
        ),
        EventRule(
            id: "device.progress",
            tier: .t2Transfer,
            needles: ["<DFU Device", "<Restore Device", "Issued GETSTATUS request", "Issuing DNLOAD request"],
            note: "USB transfer progress counters. Includes progress -1 stage markers."
        ),
        EventRule(
            id: "amai.buildIdentity",
            tier: .t3Personalization,
            needles: ["AMAuthInstallBundleCopyBuildIdentity", "requested restore behavior"],
            note: "Variant selection, e.g. Customer Erase Install."
        ),
        EventRule(
            id: "delivery.payload",
            tier: .t4Delivery,
            needles: ["ASR progress", "sending file:", "Sent image successfully"],
            note: "Payload delivery. Paths carry the operator's home directory."
        ),
        EventRule(
            id: "network.context",
            tier: .t6Network,
            needles: ["[com.apple.CFNetwork", "com.apple.network:connection"],
            note: "Network chatter. Context only, never evidence of restore state."
        ),
    ]

    /// Returns the first matching rule. `nil` means "not in the vocabulary" and
    /// must never be read as "not relevant to a restore".
    public static func classify(_ line: String) -> EventRule? {
        rules.first { $0.matches(line) }
    }

    /// Session-level terminal detection for EventSummary (FIX-002).
    public static func terminalEventDetected(inLogText text: String) -> Bool {
        DiagnosticLogBuilder.classifyTerminal(in: text) != .none
    }
}

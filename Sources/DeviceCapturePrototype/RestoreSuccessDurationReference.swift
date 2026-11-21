import Foundation

struct RestoreSuccessDurationReference: Equatable {
    enum Priority: Int { case sameECIDAndFirmware = 1, sameModelAndFirmware = 2, sameModelRecent = 3 }
    let seconds: TimeInterval
    let priority: Priority
    let firmwareVersion: String?
    let firmwareBuild: String?
}

/// Read-only matcher over existing RestoreHistoryStore records. It never
/// creates progress; it only supplies a duration reference label.
enum RestoreSuccessDurationMatcher {
    static func match(
        records: [RestoreHistoryRecord],
        target: RestoreTarget,
        productVersion: String?,
        productBuild: String?
    ) -> RestoreSuccessDurationReference? {
        let valid = records.filter { record in
            record.operationType == .restore
                && record.outcome == .success
                && (record.lifecycle.processWallDurationSeconds ?? -1) >= 0
                && record.lifecycle.processWallDurationSeconds?.isFinite == true
        }
        let ecid = target.canonicalHex.uppercased()
        let productType = (target.productType ?? target.machineIdentifier)?.uppercased()
        let matchingFirmware: (RestoreHistoryRecord) -> Bool = { record in
            (productVersion == nil || record.productVersion == productVersion)
                && (productBuild == nil || record.productBuild == productBuild)
        }
        let sameECID = valid.filter {
            $0.deviceECID?.uppercased() == ecid && matchingFirmware($0)
        }
        let sameModel = valid.filter {
            $0.hardwareBindingKey.productType?.uppercased() == productType
                && matchingFirmware($0)
        }
        let sameModelRecent = valid.filter {
            $0.hardwareBindingKey.productType?.uppercased() == productType
        }
        let ordered = [
            (RestoreSuccessDurationReference.Priority.sameECIDAndFirmware, sameECID),
            (.sameModelAndFirmware, sameModel),
            (.sameModelRecent, sameModelRecent)
        ]
        for (priority, records) in ordered {
            guard let record = records.max(by: {
                ($0.lifecycle.outcomeConfirmed?.wallTime
                    ?? $0.lifecycle.userConfirmed.wallTime)
                    < ($1.lifecycle.outcomeConfirmed?.wallTime
                        ?? $1.lifecycle.userConfirmed.wallTime)
            }),
            let seconds = record.lifecycle.processWallDurationSeconds else { continue }
            return RestoreSuccessDurationReference(
                seconds: seconds,
                priority: priority,
                firmwareVersion: record.productVersion,
                firmwareBuild: record.productBuild)
        }
        return nil
    }
}

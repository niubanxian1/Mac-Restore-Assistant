import Foundation

/// Display-only A-number annotation for an exact CPID/BDID pair. The catalog
/// is fixed data; a missing or ambiguous match returns nil and no UI text.
enum RepairCodeCatalog {
    static func aNumber(cpid: Int?, bdid: Int?) -> String? {
        guard let cpid, let bdid,
              let hardware = MacIdentityCatalog.builtIn.hardware(
                cpid: cpid, bdid: bdid) else {
            return nil
        }
        let records = MacIdentityCatalog.builtIn.records(
            forModelIdentifier: hardware.modelIdentifier)
        let numbers = Set(records.flatMap(\.aNumbers))
        return numbers.count == 1 ? numbers.first : nil
    }
}

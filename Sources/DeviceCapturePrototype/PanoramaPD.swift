import Foundation

/// Offline decoding of already registered SOP-prime identity; no PD requests.
/// Field layout: USB PD 3.x passive cable VDO, cross-checked against
/// https://github.com/torvalds/linux/blob/master/include/dt-bindings/usb/pd.h
/// Reports cable self-description; never claims physical model or measured power.
enum PanoramaPD {
    struct Cable {
        let vendorID: UInt16
        let productID: UInt16
        let productVersion: UInt16
        let maxCurrentAmps: Int?
        let maxVoltageVolts: Int?
        let speedDescription: String?
        let speedCode: UInt32
        let rawVDOs: [UInt32]
    }
    static func decodeCable(properties: [String:Any]) -> Cable? {
        guard (properties["Specification Revision"] as? NSNumber)?.intValue == 3,
              let metadata = properties["Metadata"] as? [String:Any],
              (metadata["Product Type"] as? NSNumber)?.intValue == 3,
              let data = metadata["VDOs"] as? [Data], data.count >= 4,
              data.allSatisfy({ $0.count == 4 }) else { return nil }
        let words: [UInt32] = data.map { bytes in
            bytes.enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << (8 * $1.offset)) }
        }
        let header = words[0], product = words[2], cable = words[3]
        guard ((header >> 27) & 7) == 3, let reportedVendor = metadata["Vendor ID"] as? NSNumber,
              reportedVendor.uint32Value == (header & 0xffff),
              let reportedProduct = metadata["Product ID"] as? NSNumber,
              reportedProduct.uint32Value == (product >> 16),
              ((cable >> 21) & 7) == 0 else { return nil }
        let currentCode = (cable >> 5) & 3
        let current: Int? = currentCode == 1 ? 3 : (currentCode == 2 ? 5 : nil)
        let voltageCode = Int((cable >> 9) & 3)
        let voltage = [20,30,40,50][voltageCode]
        let speedCode = cable & 7
        // Later specifications extend the speed codes; preserve unrecognised
        // values rather than infer Thunderbolt version from a cable bit field.
        let speeds: [UInt32:String] = [0:"USB 2.0",1:"USB 3.2 Gen 1",2:"USB 3.2 / USB4 Gen 2",3:"USB4 Gen 3"]
        return Cable(vendorID:UInt16(header & 0xffff), productID:UInt16(product >> 16), productVersion:UInt16(product & 0xffff), maxCurrentAmps:current, maxVoltageVolts:voltage, speedDescription:speeds[speedCode], speedCode:speedCode, rawVDOs:words)
    }
}

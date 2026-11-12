import Foundation
import IOKit

/// A read-only observation of one USB registry object.
///
/// Nothing here authenticates a device. `vendorID == 0x05AC` only means the device
/// *reports* an Apple vendor id; it is not a cryptographic identity claim.
public struct USBDeviceSnapshot: Sendable, Equatable {
    public enum Mode: String, Sendable {
        case dfuCandidate
        case recoveryCandidate
        case otherAppleUSB
        case unknownUSBMode
    }

    public let registryEntryID: UInt64
    public let vendorID: Int?
    public let productID: Int?
    public let locationID: Int?
    public let serialNumber: String?
    public let mode: Mode
    public let observedAtUTC: Date

    public init(registryEntryID: UInt64, vendorID: Int?, productID: Int?,
                locationID: Int?, serialNumber: String?, mode: Mode, observedAtUTC: Date) {
        self.registryEntryID = registryEntryID
        self.vendorID = vendorID
        self.productID = productID
        self.locationID = locationID
        self.serialNumber = serialNumber
        self.mode = mode
        self.observedAtUTC = observedAtUTC
    }

    /// Registry Entry ID is the only identity used here. It is NOT stable across a
    /// re-enumeration, and it is never promoted to a device identity.
    public var identityKey: UInt64 { registryEntryID }
}

public enum USBEvent: Sendable, Equatable {
    case initialPresent(USBDeviceSnapshot)
    case arrived(USBDeviceSnapshot)
    case removed(registryEntryID: UInt64, observedAtUTC: Date)
}

/// Pure classification, separated from IOKit so it can be tested without hardware.
public enum USBClassifier {
    public static let appleVendorID = 0x05AC
    /// Known DFU product ids observed on Apple silicon. Deliberately a set: no single
    /// value is assumed to cover every mode or model.
    public static let knownDFUProductIDs: Set<Int> = [0x1227, 0x1281]
    public static let knownRecoveryProductIDs: Set<Int> = [0x1280, 0x1283]

    public static func classify(vendorID: Int?, productID: Int?) -> USBDeviceSnapshot.Mode {
        guard let v = vendorID, let p = productID, v == appleVendorID else {
            return .unknownUSBMode
        }
        if knownDFUProductIDs.contains(p) { return .dfuCandidate }
        if knownRecoveryProductIDs.contains(p) { return .recoveryCandidate }
        return .otherAppleUSB
    }

    /// Builds a snapshot from registry-style property values. Missing or wrongly typed
    /// values become nil rather than guessed.
    public static func snapshot(registryEntryID: UInt64,
                                properties: [String: Any],
                                now: Date) -> USBDeviceSnapshot {
        let vendor = intValue(properties["idVendor"])
        let product = intValue(properties["idProduct"])
        let location = intValue(properties["locationID"])
        let serial = properties["USB Serial Number"] as? String
        return USBDeviceSnapshot(
            registryEntryID: registryEntryID,
            vendorID: vendor,
            productID: product,
            locationID: location,
            serialNumber: serial,
            mode: classify(vendorID: vendor, productID: product),
            observedAtUTC: now
        )
    }

    static func intValue(_ any: Any?) -> Int? {
        if let n = any as? Int { return n }
        if let n = any as? NSNumber {
            // A fractional value is not a valid USB id; reject it rather than letting
            // NSNumber truncate 3.5 into 3.
            let d = n.doubleValue
            if d != d.rounded() { return nil }
            return n.intValue
        }
        if let s = any as? String { return Int(s) }
        return nil
    }
}

/// Passive IOKit USB observer. It never sends a device request.
public final class USBDeviceObserver {
    public typealias Handler = @Sendable (USBEvent) -> Void

    private let handler: Handler
    private let queue = DispatchQueue(label: "rlm.usb.observer")
    private var notifyPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var runLoopSource: CFRunLoopSource?
    private var seen: Set<UInt64> = []
    private var started = false
    private var retainedSelf: UnsafeMutableRawPointer?

    public init(handler: @escaping Handler) { self.handler = handler }

    public var isRunning: Bool { queue.sync { started } }

    public enum StartError: Error { case notificationPortUnavailable, matchingFailed, iteratorUnavailable }

    public func start() throws {
        try queue.sync {
            guard !started else { return }
            guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
                throw StartError.notificationPortUnavailable
            }
            notifyPort = port
            if let src = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() {
                runLoopSource = src
                CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            }
            let context = Unmanaged.passUnretained(self).toOpaque()
            if let matchAdd = IOServiceMatching("IOUSBHostDevice") {
                let rc = IOServiceAddMatchingNotification(
                    port, kIOFirstMatchNotification, matchAdd,
                    { refcon, iterator in
                        guard let refcon else { return }
                        let me = Unmanaged<USBDeviceObserver>.fromOpaque(refcon).takeUnretainedValue()
                        me.consume(iterator: iterator, arrived: true)
                    }, context, &addedIterator)
                guard rc == KERN_SUCCESS else { throw StartError.matchingFailed }
                consume(iterator: addedIterator, arrived: true, initial: true)
            } else {
                throw StartError.matchingFailed
            }
            if let matchRemove = IOServiceMatching("IOUSBHostDevice") {
                let rc = IOServiceAddMatchingNotification(
                    port, kIOTerminatedNotification, matchRemove,
                    { refcon, iterator in
                        guard let refcon else { return }
                        let me = Unmanaged<USBDeviceObserver>.fromOpaque(refcon).takeUnretainedValue()
                        me.consume(iterator: iterator, arrived: false)
                    }, context, &removedIterator)
                guard rc == KERN_SUCCESS else { throw StartError.matchingFailed }
                consume(iterator: removedIterator, arrived: false, initial: true)
            } else {
                throw StartError.matchingFailed
            }
            started = true
        }
    }

    public func stop() {
        queue.sync {
            guard started else { return }
            if addedIterator != 0 { IOObjectRelease(addedIterator); addedIterator = 0 }
            if removedIterator != 0 { IOObjectRelease(removedIterator); removedIterator = 0 }
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
                runLoopSource = nil
            }
            if let port = notifyPort {
                IONotificationPortDestroy(port)
                notifyPort = nil
            }
            seen.removeAll()
            started = false
        }
    }

    /// Drains the iterator. IOKit requires this or later notifications never fire.
    private func consume(iterator: io_iterator_t, arrived: Bool, initial: Bool = false) {
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(entry, &entryID)
            let now = Date()
            if arrived {
                guard !seen.contains(entryID) else { continue }
                seen.insert(entryID)
                let snap = USBDeviceSnapshot(
                    registryEntryID: entryID,
                    vendorID: property(entry, "idVendor"),
                    productID: property(entry, "idProduct"),
                    locationID: property(entry, "locationID"),
                    serialNumber: stringProperty(entry, "USB Serial Number"),
                    mode: USBClassifier.classify(vendorID: property(entry, "idVendor"),
                                                 productID: property(entry, "idProduct")),
                    observedAtUTC: now)
                handler(initial ? .initialPresent(snap) : .arrived(snap))
            } else {
                seen.remove(entryID)
                handler(.removed(registryEntryID: entryID, observedAtUTC: now))
            }
        }
    }

    private func property(_ entry: io_registry_entry_t, _ key: String) -> Int? {
        guard let cf = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return nil }
        return USBClassifier.intValue(cf)
    }

    private func stringProperty(_ entry: io_registry_entry_t, _ key: String) -> String? {
        guard let cf = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return nil }
        return cf as? String
    }

    deinit { }
}

import Foundation
import Combine

enum PortDisplayDensity: String, CaseIterable, Identifiable {
    case simple
    case common
    case all

    static let defaultValue: PortDisplayDensity = .common

    var id: String { rawValue }
    var title: String {
        switch self {
        case .simple: return "简洁"
        case .common: return "常用"
        case .all: return "全部"
        }
    }
}

enum PortDeviceDensityPolicy {
    static func visible(group: String, density: PortDisplayDensity) -> Bool {
        switch density {
        case .simple:
            return ["设备身份", "当前链路"].contains(group)
        case .common:
            return !["传输子节点", "USB 根端口统计"].contains(group)
        case .all:
            return true
        }
    }
}

/// O-domain state. This object never owns or mutates the left control target.
@MainActor
final class PortDeviceWorkspaceModel: ObservableObject {
    static let densityKey = "mra.portDeviceDisplayDensity"

    @Published private(set) var followsLeftControl = true
    @Published private(set) var fixedPortID: String?
    @Published var density: PortDisplayDensity {
        didSet { defaults.set(density.rawValue, forKey: Self.densityKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        density = PortDisplayDensity(
            rawValue: defaults.string(forKey: Self.densityKey) ?? "")
            ?? .defaultValue
    }

    func observationPortID(
        controlPortID: String,
        availablePortIDs: [String]
    ) -> String? {
        let available = Set(availablePortIDs)
        if followsLeftControl {
            return available.contains(controlPortID) ? controlPortID : nil
        }
        guard let fixedPortID, available.contains(fixedPortID) else {
            return nil
        }
        return fixedPortID
    }

    func setFixedObservationPort(_ portID: String) {
        fixedPortID = portID
        followsLeftControl = false
    }

    func followLeftControl() {
        fixedPortID = nil
        followsLeftControl = true
    }
}

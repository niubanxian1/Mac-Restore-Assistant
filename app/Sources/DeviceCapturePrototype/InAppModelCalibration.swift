import Foundation
import Combine

/// One host-port observation used only by the in-app calibration wizard.
/// `connected` is the controller's read state; no identity is inferred.
struct CalibrationPortObservation: Identifiable, Hashable {
    let id: String
    let controller: String
    let portNumber: Int
    let rid: Int
    let connected: Bool
    let transports: [String]

    var label: String {
        "控制器 \(controller) · PortNumber \(portNumber) · RID \(rid)"
    }
}

@MainActor
protocol CalibrationObservationSource {
    var isSimulated: Bool { get }
    func snapshot() -> [CalibrationPortObservation]
}

struct LiveCalibrationObservationSource: CalibrationObservationSource {
    var isSimulated: Bool { false }

    func snapshot() -> [CalibrationPortObservation] {
        HostPortReader.read().map { port in
            CalibrationPortObservation(
                id: port.id,
                controller: port.controller,
                portNumber: port.portNumber,
                rid: port.rid,
                connected: port.link?.isConnected ?? false,
                transports: port.link?.transportsProvisioned ?? [])
        }
    }
}

/// Acceptance-only source. A button in the wizard toggles a port's
/// connection state; this is never used by the live send path.
@MainActor
final class SimulatedCalibrationObservationSource: ObservableObject, CalibrationObservationSource {
    @Published private(set) var connected: Set<String>
    let ports: [CalibrationPortObservation]

    init(ports: [CalibrationPortObservation], connected: Set<String> = []) {
        self.ports = ports
        self.connected = connected
    }

    var isSimulated: Bool { true }

    func snapshot() -> [CalibrationPortObservation] {
        ports.map { port in
            CalibrationPortObservation(
                id: port.id,
                controller: port.controller,
                portNumber: port.portNumber,
                rid: port.rid,
                connected: connected.contains(port.id),
                transports: port.transports)
        }
    }

    func setConnected(_ id: String, _ value: Bool) {
        if value { connected.insert(id) } else { connected.remove(id) }
    }
}

/// Editable layout row. `portNumber` / `rid` / `controller` are filled by the
/// per-slot calibration, not guessed from the host calibration library.
struct CalibrationSlotDraft: Identifiable, Hashable {
    var id: String
    var face: String
    var label: String
    var portNumber: Int?
    var rid: Int?
    var controller: String?
    var binding: String?

    init(id: String = "custom_\(UUID().uuidString.prefix(8))",
         face: String = "LEFT",
         label: String = "",
         portNumber: Int? = nil,
         rid: Int? = nil,
         controller: String? = nil,
         binding: String? = nil) {
        self.id = id
        self.face = face
        self.label = label
        self.portNumber = portNumber
        self.rid = rid
        self.controller = controller
        self.binding = binding
    }

    static func from(_ layout: BuiltInLayout?) -> [CalibrationSlotDraft] {
        guard let layout else { return [] }
        return layout.slots.map { slot in
            CalibrationSlotDraft(
                id: slot.slot,
                face: slot.face,
                label: slot.physicalName ?? slot.displayLabel,
                portNumber: slot.portNumber,
                rid: slot.rid,
                controller: slot.binding.split(separator: "|").dropFirst().first.map(String.init),
                binding: slot.binding)
        }
    }

    var faceText: String {
        switch face {
        case "LEFT": return "左侧"
        case "RIGHT": return "右侧"
        case "FRONT": return "正面"
        case "REAR": return "背面"
        default: return face
        }
    }

    var displayName: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(faceText)槽位" : label
    }

    func toBuiltInSlot(hostModel: String) -> BuiltInSlot {
        let bindingText: String
        if let controller, let portNumber, let rid {
            bindingText = "\(hostModel)|\(controller)|\(portNumber)|\(rid)"
        } else {
            bindingText = self.binding ?? ""
        }
        return BuiltInSlot(slot: id,
                           face: face,
                           portNumber: portNumber,
                           rid: rid,
                           binding: bindingText,
                           physicalName: label.isEmpty ? nil : label)
    }
}

/// Slot-by-slot in-App calibration. The state machine is UI-independent;
/// it only compares read-only connection snapshots and records a user
/// association. A unique change is not physical proof and is never a send
/// authorization.
@MainActor
final class InAppCalibrationSession: ObservableObject {
    enum Step: Equatable {
        case idle
        case waitingForInsert
        case waitingForRemoval
        case readyToConfirm
        case complete
    }

    @Published private(set) var step: Step = .idle
    @Published private(set) var currentIndex = 0
    @Published private(set) var associations: [String: CalibrationPortObservation] = [:]
    @Published private(set) var skipped: Set<String> = []
    @Published private(set) var baseline: Set<String> = []
    @Published private(set) var candidate: CalibrationPortObservation?
    @Published var statusMessage = ""

    let slots: [CalibrationSlotDraft]
    let source: CalibrationObservationSource

    init(slots: [CalibrationSlotDraft], source: CalibrationObservationSource) {
        self.slots = slots
        self.source = source
    }

    var currentSlot: CalibrationSlotDraft? {
        guard currentIndex < slots.count else { return nil }
        return slots[currentIndex]
    }

    var isComplete: Bool { currentIndex >= slots.count }

    var progressText: String {
        "\(min(currentIndex, slots.count)) / \(slots.count)"
    }

    var canSaveExact: Bool {
        !slots.isEmpty && isComplete && skipped.isEmpty && associations.count == slots.count
    }

    func startSlot() {
        guard currentSlot != nil else {
            step = .complete
            return
        }
        baseline = Set(source.snapshot().filter(\.connected).map(\.id))
        candidate = nil
        step = .waitingForInsert
        statusMessage = "已采基线：\(baseline.count) 个端口当前有连接。请将探针插入「\(currentSlot?.displayName ?? "当前槽位")」。"
    }

    func detectChange() {
        guard step == .waitingForInsert, let slot = currentSlot else { return }
        let snapshot = source.snapshot()
        let connected = Set(snapshot.filter(\.connected).map(\.id))
        let added = connected.subtracting(baseline)
        if added.isEmpty {
            statusMessage = "未检测到唯一变化（0 个）。请确认探针已插入目标槽位，再重试。"
            return
        }
        if added.count > 1 {
            statusMessage = "检测到多个端口变化，无法唯一确定；请只插入一个探针后重试。"
            return
        }
        guard let id = added.first,
              let observation = snapshot.first(where: { $0.id == id }) else {
            statusMessage = "检测到变化，但读不到对应端口；请重试。"
            return
        }
        candidate = observation
        step = .waitingForRemoval
        statusMessage = "检测到唯一变化：\(observation.label)。请移除探针。"
        _ = slot
    }

    func confirmRemoved() {
        guard step == .waitingForRemoval, let candidate else { return }
        let snapshot = source.snapshot()
        if snapshot.contains(where: { $0.id == candidate.id && $0.connected }) {
            statusMessage = "仍检测到「\(candidate.label)」有连接；请先移除探针，再确认。"
            return
        }
        step = .readyToConfirm
        statusMessage = "已确认探针移除。确认后将把「\(currentSlot?.displayName ?? "当前槽位")」映射到 \(candidate.label)。"
    }

    func confirmMapping() {
        guard step == .readyToConfirm, let slot = currentSlot, let candidate else { return }
        associations[slot.id] = candidate
        advance()
    }

    func skipSlot() {
        guard let slot = currentSlot else { return }
        skipped.insert(slot.id)
        advance()
    }

    private func advance() {
        currentIndex += 1
        candidate = nil
        if currentIndex >= slots.count {
            step = .complete
            statusMessage = skipped.isEmpty
                ? "全部槽位已完成。可以保存并立即应用。"
                : "已跳过 \(skipped.count) 个槽位；保存后不会标记本机型精确校准。"
            return
        }
        startSlot()
    }

    func makeLayout(hostModel: String, displayName: String) -> BuiltInLayout {
        let builtSlots = slots.map { slot -> BuiltInSlot in
            var copy = slot
            if let observation = associations[slot.id] {
                copy.controller = observation.controller
                copy.portNumber = observation.portNumber
                copy.rid = observation.rid
                copy.binding = "\(hostModel)|\(observation.controller)|\(observation.portNumber)|\(observation.rid)"
            }
            return copy.toBuiltInSlot(hostModel: hostModel)
        }
        return BuiltInLayout(
            displayName: displayName,
            sourceFile: "",
            slots: builtSlots,
            partial: !skipped.isEmpty || associations.count != slots.count,
            skippedSlots: slots.filter { skipped.contains($0.id) }.map(\.displayName),
            generatedAt: ISO8601DateFormatter().string(from: Date()))
    }
}

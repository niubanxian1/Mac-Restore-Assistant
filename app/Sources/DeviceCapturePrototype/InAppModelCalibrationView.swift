import SwiftUI
import AppKit

/// Settings → 模型校准, fully inside this App.
/// Add a host model, import a pack, edit a custom layout, calibrate each slot
/// against the read-only host-port connection state, then save and apply the
/// same effective record used by the main window.
struct InAppModelCalibrationView: View {
    @EnvironmentObject private var store: CalibrationStore
    @EnvironmentObject private var device: DeviceControlModel
    @State private var message = ""
    @State private var showAddModel = false
    @State private var showLayoutEditor = false
    @State private var showWizard = false
    @State private var draftSlots: [CalibrationSlotDraft] = []
    @State private var newModel = ""
    @State private var newLayoutName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("模型校准")).font(.system(size: 15, weight: .semibold))
                Text(L10n.t("在本 App 内添加主机模型、导入已有模型包、编辑自定义布局，并按槽位完成「采基线 → 检测唯一变化 → 移除探针 → 确认映射」。保存后立即成为主界面与设置页共用的生效记录。"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                statusCard

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                    Button(L10n.t("添加主机模型…")) { showAddModel = true }
                    Button(L10n.t("导入已有模型包…")) { importPack() }
                    Button(L10n.t("编辑自定义布局…")) { showLayoutEditor = true }
                    Button(L10n.t("按槽位校准…")) { showWizard = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftSlots.isEmpty)
                    Button(L10n.t("保存并立即应用")) { applyDraft() }
                        .disabled(draftSlots.isEmpty)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L10n.t("布局槽位")).font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(L10n.t("\(draftSlots.count) 个")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if draftSlots.isEmpty {
                        Text(L10n.t("尚无槽位。可先导入模型包，或编辑自定义布局添加槽位。"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(draftSlots) { slot in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(L10n.t(slot.displayName))
                                    .font(.system(size: 11, weight: .medium))
                                    .frame(width: 130, alignment: .leading)
                                Text(L10n.faceLabel(slot.face))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .leading)
                                Text(slot.portNumber.map { "PortNumber \($0)" } ?? "PortNumber 未校准")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(slot.portNumber == nil ? .secondary : .primary)
                                Text(slot.rid.map { "RID \($0)" } ?? "RID 未校准")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(slot.rid == nil ? .secondary : .primary)
                                if let controller = slot.controller {
                                    Text(controller)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))

                Text(L10n.t("添加模型、导入或套用布局都不会把本机标成「本机型精确校准」。只有完成全部槽位映射并保存，才会标记为精确校准；跳过槽位时为自定义布局。"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message.isEmpty ? (store.saveMessage.isEmpty ? " " : store.saveMessage) : message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(16)
        }
        .onAppear {
            reloadDraft()
            if ProcessInfo.processInfo.environment["MRA_UI_OPEN_MODEL_WIZARD"] == "1",
               !draftSlots.isEmpty {
                showWizard = true
            }
        }
        .sheet(isPresented: $showAddModel) { addModelSheet }
        .sheet(isPresented: $showLayoutEditor) {
            LayoutEditorSheet(slots: $draftSlots) { showLayoutEditor = false }
        }
        .sheet(isPresented: $showWizard) {
            CalibrationWizardSheet(slots: draftSlots) { layout, complete in
                store.applyInAppCalibration(
                    layout: layout,
                    displayName: complete ? "本机校准 \(store.hostModel)" : "自定义布局 \(store.hostModel)",
                    complete: complete)
                message = store.saveMessage
                reloadDraft()
                showWizard = false
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t(device.hostCalibrationSummaryText)).font(.system(size: 12, weight: .medium))
            Text(L10n.t(store.builtInStatusText)).font(.system(size: 11)).foregroundStyle(.secondary)
            if let overlay = store.adoptedOverlay {
                Text(L10n.t("实际采用：\(overlay.sourceSummary)")).font(.system(size: 11))
                Text(overlay.displayName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.t("实际采用：内置记录（如有）")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(L10n.t("生效记录：\(store.adoptedLayoutFileURL.path)"))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
    }

    private var addModelSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("添加主机模型")).font(.system(size: 15, weight: .semibold))
            Text(L10n.t("只添加机型标识；不会自动套用布局，也不会标记精确校准。"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("机型标识，例如 MacBookPro18,2", text: $newModel)
                .textFieldStyle(.roundedBorder)
            TextField("布局名（可选）", text: $newLayoutName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button(L10n.t("取消")) { showAddModel = false }
                Button(L10n.t("添加")) {
                    store.addHostModel(newModel, layoutName: newLayoutName)
                    message = store.saveMessage
                    newModel = ""
                    newLayoutName = ""
                    showAddModel = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    private func importPack() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip, .json]
        panel.message = "选择 Hardware Preview 模型包（report.json / ZIP）。只写入本 App 的生效记录。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try store.importModelPack(from: url)
            store.applyImportedLayout()
            message = store.saveMessage
            reloadDraft()
        } catch {
            message = "导入失败：\(error.localizedDescription)"
        }
    }

    private func reloadDraft() {
        store.reloadAdoptedOverlayFromDisk()
        draftSlots = CalibrationSlotDraft.from(store.adoptedLayout ?? store.builtInLayout)
    }

    private func applyDraft() {
        let mapped = draftSlots.filter { $0.portNumber != nil && $0.rid != nil }
        let layout = BuiltInLayout(
            displayName: "自定义布局 \(store.hostModel)",
            sourceFile: "",
            slots: draftSlots.map { $0.toBuiltInSlot(hostModel: store.hostModel) },
            partial: mapped.count != draftSlots.count,
            skippedSlots: draftSlots.filter { $0.portNumber == nil || $0.rid == nil }.map(\.displayName),
            generatedAt: ISO8601DateFormatter().string(from: Date()))
        store.applyInAppCalibration(
            layout: layout,
            displayName: "自定义布局 \(store.hostModel)",
            complete: false)
        message = store.saveMessage
    }
}

private struct LayoutEditorSheet: View {
    @Binding var slots: [CalibrationSlotDraft]
    let close: () -> Void
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.t("编辑自定义布局")).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(L10n.t("完成")) { close() }
            }
            Text(L10n.t("只编辑槽位名称与朝向；PortNumber / RID 由按槽位校准写入，不从主机校准库猜测。"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach($slots) { $slot in
                        HStack(spacing: 8) {
                            TextField("槽位名称", text: $slot.label)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                            Picker("", selection: $slot.face) {
                                Text(L10n.t("左侧")).tag("LEFT")
                                Text(L10n.t("右侧")).tag("RIGHT")
                                Text(L10n.t("正面")).tag("FRONT")
                                Text(L10n.t("背面")).tag("REAR")
                            }
                            .labelsHidden()
                            .frame(width: 90)
                            Text(slot.portNumber.map { "PortNumber \($0)" } ?? "未校准")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) {
                                slots.removeAll { $0.id == slot.id }
                            } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            HStack {
                Button(L10n.t("添加槽位")) {
                    slots.append(CalibrationSlotDraft(face: "LEFT", label: "槽位 \(slots.count + 1)"))
                }
                Spacer()
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: 620, height: 420)
    }
}

private struct CalibrationWizardSheet: View {
    let slots: [CalibrationSlotDraft]
    let onSave: (BuiltInLayout, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CalibrationStore
    @StateObject private var session: InAppCalibrationSession

    init(slots: [CalibrationSlotDraft],
         onSave: @escaping (BuiltInLayout, Bool) -> Void) {
        self.slots = slots
        self.onSave = onSave
        let simulated = ProcessInfo.processInfo.environment["MRA_CALIBRATION_SIMULATION"] == "1"
        let source: CalibrationObservationSource
        if simulated {
            source = SimulatedCalibrationObservationSource(ports: Self.demoPorts)
        } else {
            source = LiveCalibrationObservationSource()
        }
        _session = StateObject(wrappedValue: InAppCalibrationSession(slots: slots, source: source))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.t("按槽位校准")).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(session.progressText).font(.system(size: 11, design: .monospaced))
                Button(L10n.t("关闭")) { dismiss() }
            }
            Text(L10n.t("每个槽位都按「采基线 → 插入探针 → 检测唯一变化 → 移除探针 → 确认映射」执行。读取的是主机端口连接状态，不发送 DFU／重启。"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if session.source.isSimulated {
                Text(L10n.t("验收模拟模式：以下按钮只改变模拟端口状态，不是真实插拔。"))
                    .font(.system(size: 11)).foregroundStyle(.orange)
                if let sim = session.source as? SimulatedCalibrationObservationSource {
                    HStack(spacing: 6) {
                        ForEach(sim.ports) { port in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t("P\(port.portNumber)")).font(.system(size: 10, design: .monospaced))
                                HStack(spacing: 4) {
                                    Button(L10n.t("插入")) { sim.setConnected(port.id, true) }
                                    Button(L10n.t("移除")) { sim.setConnected(port.id, false) }
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }

            if let slot = session.currentSlot {
                Text(L10n.wizardCurrentSlot(face: slot.face, slotID: slot.id))
                    .font(.system(size: 12, weight: .medium))
            } else {
                Text(L10n.t("全部槽位已完成")).font(.system(size: 12, weight: .medium))
            }
            Text(session.statusMessage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                switch session.step {
                case .idle:
                    Button(L10n.t("采基线")) { session.startSlot() }
                        .buttonStyle(.borderedProminent)
                case .waitingForInsert:
                    Button(L10n.t("检测变化")) { session.detectChange() }
                        .buttonStyle(.borderedProminent)
                case .waitingForRemoval:
                    Button(L10n.t("确认已移除")) { session.confirmRemoved() }
                        .buttonStyle(.borderedProminent)
                case .readyToConfirm:
                    Button(L10n.t("确认映射")) { session.confirmMapping() }
                        .buttonStyle(.borderedProminent)
                case .complete:
                    Button(L10n.t("保存并立即应用")) {
                        let layout = session.makeLayout(
                            hostModel: store.hostModel,
                            displayName: session.canSaveExact
                                ? "本机校准 \(store.hostModel)"
                                : "自定义布局 \(store.hostModel)")
                        guard !session.slots.isEmpty else { return }
                        onSave(layout, session.canSaveExact)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if session.currentSlot != nil, session.step != .complete {
                    Button(L10n.t("跳过此槽位")) { session.skipSlot() }
                }
                Spacer()
            }
            if let candidate = session.candidate {
                Text(L10n.t("候选端口：\(candidate.label)"))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .padding(18)
        .frame(width: 720, height: 430)
    }

    private static let demoPorts: [CalibrationPortObservation] = [
        CalibrationPortObservation(id: "demo:1", controller: "demo", portNumber: 1, rid: 0, connected: false, transports: ["CC", "USB2"]),
        CalibrationPortObservation(id: "demo:2", controller: "demo", portNumber: 2, rid: 1, connected: false, transports: ["CC", "USB2"]),
        CalibrationPortObservation(id: "demo:3", controller: "demo", portNumber: 3, rid: 2, connected: false, transports: ["CC", "USB2"]),
    ]
}

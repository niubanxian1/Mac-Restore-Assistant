import Foundation

/// Source of the layout the main window is actually using.
/// Importing a pack, adding a model, or applying a layout must not be
/// recorded as an exact verified hit for the current host.
enum AdoptedLayoutSource: String, Codable, Equatable {
    case builtinExact
    case importedPack
    case appliedLayout
    case previewToolSave
    case addedModelOnly
    /// Completed slot-by-slot calibration performed inside this App.
    case inAppCalibration
    /// A custom layout saved before every slot was confirmed.
    case customLayout
}

struct AdoptedCalibrationOverlay: Codable, Equatable {
    var source: AdoptedLayoutSource
    var sourceHostModel: String
    var sourceFile: String?
    var displayName: String
    var layout: BuiltInLayout
    var savedAt: String

    var isExactVerifiedHit: Bool { source == .builtinExact || source == .inAppCalibration }

    /// A legacy standalone-tool draft with no host id and no port mapping
    /// cannot be an effective record. It must not hide a builtin exact hit.
    var isUsableEffectiveRecord: Bool {
        if source == .previewToolSave {
            let hasHost = !sourceHostModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasMapping = layout.slots.contains {
                $0.portNumber != nil && $0.rid != nil
            }
            return hasHost && hasMapping
        }
        return true
    }

    /// Same host + the same complete slot/PortNumber/RID mapping as the
    /// verified builtin record is still an exact hit, even when it arrived
    /// through an imported pack. Other layouts stay non-exact.
    func matchesExactBuiltIn(_ builtin: BuiltInLayout?) -> Bool {
        guard let builtin, !layout.partial, !builtin.partial,
              !layout.slots.isEmpty,
              layout.slots.count == builtin.slots.count else { return false }
        let mine = layout.slots.map { "\($0.slot)|\($0.portNumber ?? -1)|\($0.rid ?? -1)" }.sorted()
        let reference = builtin.slots.map { "\($0.slot)|\($0.portNumber ?? -1)|\($0.rid ?? -1)" }.sorted()
        return mine == reference
    }

    var sourceSummary: String {
        switch source {
        case .builtinExact:
            return "内置已验证记录"
        case .importedPack:
            let file = sourceFile.map { " · \($0)" } ?? ""
            return "导入模型包（\(sourceHostModel)\(file)）"
        case .appliedLayout:
            return "已套用布局（\(sourceHostModel)）"
        case .previewToolSave:
            return "校准工具保存的布局（\(sourceHostModel)）"
        case .addedModelOnly:
            return "已添加模型 \(sourceHostModel)，尚未采用布局"
        case .inAppCalibration:
            return "本机按槽位校准（\(sourceHostModel)）"
        case .customLayout:
            return "自定义布局（\(sourceHostModel)，未完成精确校准）"
        }
    }
}

struct HardwarePreviewReport: Equatable {
    var version: String
    var app: String
    var hostModel: String
    var displayHint: String
    var associations: [String: String]
    var slots: [ReportSlot]
    var skippedSlots: [String]
    var partial: Bool
    var generatedAt: String
    var sourceFile: String?

    struct ReportSlot: Equatable {
        var slotID: String
        var face: String
        var label: String
    }

    struct BindingParts {
        var hostModel: String
        var controller: String
        var portNumber: Int?
        var rid: Int?
        var raw: String
    }

    static func parseBinding(_ raw: String) -> BindingParts {
        let parts = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        var port: Int?
        var rid: Int?
        if parts.count >= 3 { port = Int(parts[2]) }
        if parts.count >= 4 { rid = Int(parts[3]) }
        return BindingParts(
            hostModel: parts.first ?? "",
            controller: parts.count >= 2 ? parts[1] : "",
            portNumber: port,
            rid: rid,
            raw: raw)
    }

    func layout(displayName: String? = nil, sourceFile: String? = nil) -> BuiltInLayout {
        let name = displayName ?? (self.displayHint.isEmpty ? "导入自 \(hostModel)" : self.displayHint)
        let file = sourceFile ?? self.sourceFile ?? ""
        let slots: [BuiltInSlot] = self.slots.map { slot in
            let binding = associations[slot.slotID] ?? ""
            let parts = Self.parseBinding(binding)
            return BuiltInSlot(
                slot: slot.slotID,
                face: slot.face,
                portNumber: parts.portNumber,
                rid: parts.rid,
                binding: binding.isEmpty ? parts.controller : binding,
                physicalName: slot.label.isEmpty ? nil : slot.label)
        }
        return BuiltInLayout(
            displayName: name,
            sourceFile: file,
            slots: slots,
            partial: partial || !skippedSlots.isEmpty,
            skippedSlots: skippedSlots,
            generatedAt: generatedAt)
    }

    func makeOverlay(source: AdoptedLayoutSource, savedAt: String = ISO8601DateFormatter().string(from: Date())) -> AdoptedCalibrationOverlay {
        let layout = layout(displayName: displayHint, sourceFile: sourceFile)
        return AdoptedCalibrationOverlay(
            source: source,
            sourceHostModel: hostModel,
            sourceFile: sourceFile,
            displayName: layout.displayName,
            layout: layout,
            savedAt: savedAt)
    }
}

enum HardwarePreviewPackError: Error, Equatable, LocalizedError {
    case unreadable
    case missingReport
    case invalidReport
    case unsupportedModelPack

    var errorDescription: String? {
        switch self {
        case .unreadable: return "无法读取模型包。"
        case .missingReport: return "模型包中没有 report.json。"
        case .invalidReport: return "report.json 格式无法解析。"
        case .unsupportedModelPack: return "这是已签名的 .mramodelpack；本轮按 Hardware Preview 的 report.json / ZIP 导入。来源说明见报告（v2 能力，不是 B.1 成品已有导入按钮）。"
        }
    }
}

enum HardwarePreviewPackWriteError: Error, LocalizedError {
    case noSlots
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSlots: return "当前模型没有可导出的端口槽位。"
        case .writeFailed(let message): return "模型包导出失败：\(message)"
        }
    }
}

enum HardwarePreviewPack {
    static let exportVersion = "1.7-hardware-preview0.3.2-phase-b.1"

    static func load(from url: URL) throws -> HardwarePreviewReport {
        let ext = url.pathExtension.lowercased()
        if ext == "mramodelpack" {
            throw HardwarePreviewPackError.unsupportedModelPack
        }
        let data: Data
        var sourceFile = url.lastPathComponent
        if ext == "zip" {
            data = try dataFromZip(url, fileName: "report.json")
        } else if ext == "json" || url.lastPathComponent == "draft.json" || url.lastPathComponent == "report.json" {
            data = try Data(contentsOf: url)
            sourceFile = url.lastPathComponent
        } else if let zipData = try? dataFromZip(url, fileName: "report.json") {
            data = zipData
        } else {
            data = try Data(contentsOf: url)
        }
        return try decode(data, sourceFile: sourceFile)
    }

    static func decode(_ data: Data, sourceFile: String?) throws -> HardwarePreviewReport {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HardwarePreviewPackError.invalidReport
        }
        let host: [String: Any] = object["host"] as? [String: Any] ?? [:]
        let hostModel = string(host["model"]) ?? string(object["host_model"]) ?? ""
        if hostModel.isEmpty && object["associations"] == nil && object["slots"] == nil {
            throw HardwarePreviewPackError.invalidReport
        }
        var associations: [String: String] = [:]
        if let raw = object["associations"] as? [String: Any] {
            for (key, value) in raw {
                associations[key] = String(describing: value)
            }
        }
        var slots: [HardwarePreviewReport.ReportSlot] = []
        if let rawSlots = object["slots"] as? [[String: Any]] {
            for item in rawSlots {
                let id = string(item["slot_id"]) ?? string(item["slot"]) ?? ""
                guard !id.isEmpty else { continue }
                slots.append(.init(
                    slotID: id,
                    face: string(item["face"]) ?? "",
                    label: string(item["label"]) ?? string(item["display_label"]) ?? ""))
            }
        }
        if slots.isEmpty, let summary = object["summary"] as? [[String: Any]] {
            for item in summary {
                let id = string(item["slot"]) ?? ""
                guard !id.isEmpty else { continue }
                slots.append(.init(
                    slotID: id,
                    face: string(item["face"]) ?? "",
                    label: string(item["binding"]) ?? id))
            }
        }
        if slots.isEmpty {
            slots = associations.keys.sorted().map { .init(slotID: $0, face: "", label: $0) }
        }
        let skipped = (object["skipped_slots"] as? [Any] ?? object["skipped"] as? [Any] ?? []).map { String(describing: $0) }
        let hint: String
        if let app = string(object["app"]), !app.isEmpty {
            hint = "\(app) · \(hostModel)"
        } else {
            hint = hostModel
        }
        return HardwarePreviewReport(
            version: string(object["version"]) ?? "",
            app: string(object["app"]) ?? "",
            hostModel: hostModel,
            displayHint: hint,
            associations: associations,
            slots: slots,
            skippedSlots: skipped,
            partial: bool(object["partial"]) || !skipped.isEmpty,
            generatedAt: string(object["generated_at"]) ?? string(object["updated_at"]) ?? "",
            sourceFile: sourceFile)
    }

    static func export(
        layout: BuiltInLayout,
        hostModel: String,
        sourceFile: String?,
        to destination: URL,
        generatedAt: Date = Date()
    ) throws -> HardwarePreviewReport {
        guard !layout.slots.isEmpty else { throw HardwarePreviewPackWriteError.noSlots }
        let model = hostModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw HardwarePreviewPackError.invalidReport }

        var associations: [String: String] = [:]
        var slots: [[String: Any]] = []
        for slot in layout.slots {
            let parsed = HardwarePreviewReport.parseBinding(slot.binding)
            let binding: String
            if let portNumber = slot.portNumber, let rid = slot.rid, !parsed.controller.isEmpty {
                binding = "\(model)|\(parsed.controller)|\(portNumber)|\(rid)"
            } else {
                binding = slot.binding
            }
            associations[slot.slot] = binding
            slots.append([
                "slot_id": slot.slot,
                "face": slot.face,
                "label": slot.physicalName ?? slot.slot,
                "binding": binding,
            ])
        }
        let timestamp = layout.generatedAt.isEmpty
            ? ISO8601DateFormatter().string(from: generatedAt)
            : layout.generatedAt
        let payload: [String: Any] = [
            "app": "Mac Restore Assistant",
            "version": exportVersion,
            "host": ["model": model],
            "host_model": model,
            "associations": associations,
            "slots": slots.sorted {
                ($0["slot_id"] as? String ?? "") < ($1["slot_id"] as? String ?? "")
            },
            "skipped_slots": layout.skippedSlots,
            "partial": layout.partial,
            "generated_at": timestamp,
            "passive_only": true,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let readme = """
        Mac Restore Assistant model calibration

        Model: \(model)
        Layout: \(layout.displayName)
        Slots: \(layout.slots.count)

        This ZIP uses report.json and can be imported by Mac Restore Assistant.
        No ECID, serial, username, or home-directory path is included.
        """
        let writer = ZipStoreWriter()
        do {
            _ = try writer.write(entries: [
                ZipEntrySpec(pathInZip: "report.json", fileURL: nil, data: data, storedSHA256: nil),
                ZipEntrySpec(pathInZip: "README.txt", fileURL: nil,
                             data: Data(readme.utf8), storedSHA256: nil),
            ], to: destination)
        } catch {
            throw HardwarePreviewPackWriteError.writeFailed(error.localizedDescription)
        }
        return try load(from: destination)
    }

    private static func dataFromZip(_ url: URL, fileName: String) throws -> Data {
        guard let archive = try? FileWrapper(url: url, options: .immediate),
              archive.isDirectory || url.pathExtension.lowercased() == "zip" else {
            throw HardwarePreviewPackError.unreadable
        }
        // Use Foundation ZIP via /usr/bin/unzip -p in a helper to avoid adding a zip lib.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, fileName]
        let pipe = Pipe()
        let err = Pipe()
        process.standardOutput = pipe
        process.standardError = err
        do { try process.run() } catch { throw HardwarePreviewPackError.unreadable }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 || data.isEmpty {
            throw HardwarePreviewPackError.missingReport
        }
        return data
    }

    private static func string(_ value: Any?) -> String? {
        guard let value else { return nil }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text == "<null>" ? nil : text
    }

    private static func bool(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        if let text = string(value)?.lowercased() { return text == "true" || text == "1" }
        return false
    }
}

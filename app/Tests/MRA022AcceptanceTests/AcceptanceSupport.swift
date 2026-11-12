import XCTest
@testable import DeviceCapturePrototype
import MRAHelperProtocol
import Foundation

enum AcceptanceFixtures {
    static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static var testsRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    }

    static func fixture(_ parts: String...) -> URL {
        let underSource = parts.reduce(testsRoot.appendingPathComponent("Fixtures")) {
            $0.appendingPathComponent($1)
        }
        if FileManager.default.fileExists(atPath: underSource.path) {
            return underSource
        }
        if let resourceRoot = Bundle.module.resourceURL {
            let bundled = parts.reduce(resourceRoot.appendingPathComponent("Fixtures")) {
                $0.appendingPathComponent($1)
            }
            if FileManager.default.fileExists(atPath: bundled.path) {
                return bundled
            }
        }
        return underSource
    }

    static func script(_ name: String) -> URL {
        let underSource = testsRoot.appendingPathComponent("Scripts").appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: underSource.path) {
            return underSource
        }
        if let resourceRoot = Bundle.module.resourceURL {
            let bundled = resourceRoot.appendingPathComponent("Scripts").appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: bundled.path) {
                return bundled
            }
        }
        return underSource
    }

    static func loadDocument(_ name: String) throws -> CalibrationDocument {
        let url = fixture("calibration", name)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CalibrationDocument.self, from: data)
    }

    @MainActor
    static func isolatedStore(document: CalibrationDocument,
                              hostModel: String = "MacBookPro18,2",
                              layout: BuiltInLayout? = macBookProLayout(),
                              fileURL: URL? = nil) -> CalibrationStore {
        CalibrationStore(testingDocument: document,
                         hostModel: hostModel,
                         builtInLayout: layout,
                         fileURL: fileURL)
    }

    static func macBookProLayout() -> BuiltInLayout {
        BuiltInLayout(
            displayName: "M1 Pro MacBook Pro A2485 16英寸",
            sourceFile: "canonical-live-ports.json",
            slots: [
                BuiltInSlot(slot: "S3", face: "LEFT", portNumber: 1, rid: 0,
                            binding: "MacBookPro18,2|AppleHPMDevice|1|0", physicalName: "左侧上方"),
                BuiltInSlot(slot: "S4", face: "LEFT", portNumber: 2, rid: 1,
                            binding: "MacBookPro18,2|AppleHPMDevice|2|1", physicalName: "左侧下方"),
                BuiltInSlot(slot: "S5", face: "RIGHT", portNumber: 3, rid: 2,
                            binding: "MacBookPro18,2|AppleHPMDevice|3|2", physicalName: "右侧"),
            ],
            partial: false, skippedSlots: [], generatedAt: "acceptance")
    }

    static let slotS3 = LiveHostPort(controller: "100000834", portNumber: 1, rid: 0)
    static let slotS4 = LiveHostPort(controller: "100000813", portNumber: 2, rid: 1)
    static let slotS5 = LiveHostPort(controller: "10000081e", portNumber: 3, rid: 2)

    static var canonicalLivePorts: [LiveHostPort] { [slotS3, slotS4, slotS5] }

    static var sameRIDTwoControllers: [LiveHostPort] {
        [
            LiveHostPort(controller: "100000aaa", portNumber: 1, rid: 0),
            LiveHostPort(controller: "100000bbb", portNumber: 3, rid: 0),
        ]
    }
}

@MainActor
enum AcceptanceModels {
    static func makeModel(ports: [LiveHostPort],
                          document: CalibrationDocument? = nil,
                          selected: String? = nil,
                          layout: BuiltInLayout? = AcceptanceFixtures.macBookProLayout(),
                          timeout: TimeInterval = 10,
                          delay: TimeInterval = 0.05,
                          persistPortSelection: Bool = false,
                          fileURL: URL? = nil,
                          handler: DeviceControlModel.HelperRequestHandler? = nil) -> DeviceControlModel {
        var doc = document ?? CalibrationDocument(
            models: [],
            ports: [
                PortCalibrationEntry(physicalPort: "left1", location: "01200000", label: "左侧上方",
                                     rid: "0", side: "左侧",
                                     controller: AcceptanceFixtures.slotS3.controller,
                                     portNumber: AcceptanceFixtures.slotS3.portNumber),
                PortCalibrationEntry(physicalPort: "left2", location: "01100000", label: "左侧下方",
                                     rid: "1", side: "左侧",
                                     controller: AcceptanceFixtures.slotS4.controller,
                                     portNumber: AcceptanceFixtures.slotS4.portNumber),
                PortCalibrationEntry(physicalPort: "right1", location: "02100000", label: "右侧",
                                     rid: "2", side: "右侧",
                                     controller: AcceptanceFixtures.slotS5.controller,
                                     portNumber: AcceptanceFixtures.slotS5.portNumber),
            ],
            selectedPort: selected ?? AcceptanceFixtures.slotS5.id)
        if let selected {
            doc.selectedPort = selected
        }
        let store = AcceptanceFixtures.isolatedStore(document: doc, layout: layout, fileURL: fileURL)
        return DeviceControlModel(
            calibration: store,
            livePorts: ports,
            helperAvailable: true,
            sendTimeout: timeout,
            sequenceDelaySeconds: delay,
            persistPortSelection: persistPortSelection,
            startLiveWork: false,
            requestHandler: handler)
    }
}

@MainActor
final class AcceptancePendingResponses {
    private var waiting: [(String, CheckedContinuation<HelperResponse, Never>)] = []
    var count: Int { waiting.count }

    func hang(_ requestID: String) async -> HelperResponse {
        await withCheckedContinuation { waiting.append((requestID, $0)) }
    }

    func completeAll(ok: Bool = true, truth: String = "REQUEST_SENT") {
        let pending = waiting
        waiting.removeAll()
        for (id, continuation) in pending {
            continuation.resume(returning: HelperResponse(
                requestID: id, ok: ok, dispatchTruth: truth, exitCode: 0, reason: ""))
        }
    }
}

struct RecordedSend {
    let action: HelperAction
    let controller: String
    let portNumber: Int
    let rid: Int
    let requestID: String
    let at: Date
}

struct ScriptRun {
    let exitCode: Int32
    let output: String
}

enum ScriptHarness {
    static func run(script: URL, arguments: [String], environment: [String: String] = [:]) throws -> ScriptRun {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment { env[key] = value }
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return ScriptRun(exitCode: process.terminationStatus, output: output)
    }
}

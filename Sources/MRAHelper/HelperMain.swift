import Foundation
import Darwin
import Security
import MRAHelperProtocol
import MRAHelperCore

enum HelperRuntime {
    static let socketPath = ProcessInfo.processInfo.environment["MRA_HELPER_SOCKET"] ?? mraHelperSocketPath
    #if MRA_HELPER_TESTING
    static let testingBuild = true
    #else
    static let testingBuild = false
    #endif
    static let allowUnsignedTest = MRAHelperCore.allowsUnsignedTestBypass(
        environment: ProcessInfo.processInfo.environment,
        socketPath: socketPath,
        productionSocketPath: mraHelperSocketPath,
        testingBuild: testingBuild)
    static let backendPath = ProcessInfo.processInfo.environment["MRA_DIRECT_RID_BIN"] ?? "/Library/PrivilegedHelperTools/com.mra.direct_rid_dfu"
    static let expectedBundle = "com.mra.devicecontrol.prototype"
    static let expectedTeam = "6NFD357KL3"
    static let seenStore = SeenStore()
    static let connectionLimiter = MRAHelperCore.ConnectionLimiter()
}

func jsonLine(_ value: some Encodable) -> Data {
    (try? JSONEncoder().encode(value)) ?? Data()
}

func signingInfo(fd: Int32) -> (String, String)? {
    var token = audit_token_t()
    var len = socklen_t(MemoryLayout<audit_token_t>.size)
    guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else { return nil }
    let data = withUnsafeBytes(of: &token) { Data($0) }
    let attrs = [kSecGuestAttributeAudit as String: data] as CFDictionary
    var code: SecCode?
    guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess,
          let code else { return nil }
    guard SecCodeCheckValidity(code, [], nil) == errSecSuccess else { return nil }
    var info: CFDictionary?
    let staticCode = unsafeBitCast(code, to: SecStaticCode.self)
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let dict = info as? [String: Any] else { return nil }
    return (dict[kSecCodeInfoIdentifier as String] as? String ?? "",
            dict[kSecCodeInfoTeamIdentifier as String] as? String ?? "")
}

func readPorts() -> [(controller: String, port: Int, rid: Int)] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
    p.arguments = ["-r", "-c", "AppleHPM", "-l"]
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
    try? p.run(); p.waitUntilExit()
    let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return HostPortTextParser.parse(text).map { ($0.controller, $0.portNumber, $0.rid) }
}

func validatePort(_ req: HelperRequest) -> String {
    guard req.rid >= 0, !req.controller.isEmpty, req.portNumber >= 0 else { return "INVALID_TARGET" }
    let found = readPorts().contains { $0.controller == req.controller && $0.port == req.portNumber && $0.rid == req.rid }
    return found ? "" : "PORT_RID_MISMATCH"
}

func runBackend(_ action: String, controller: String, portNumber: Int, rid: Int) -> (Int32, String, String) {
    MRAHelperCore.runBackend(
        action: action,
        controller: controller,
        portNumber: portNumber,
        rid: rid,
        backendPath: HelperRuntime.backendPath)
}

final class SeenStore: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: HelperResponse] = [:]
    private var inFlight: Set<String> = []

    func existing(_ id: String) -> HelperResponse? {
        lock.lock(); defer { lock.unlock() }
        return responses[id]
    }

    /// Returns false when another request with the same id is already running.
    func reserve(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if responses[id] != nil { return false }
        if inFlight.contains(id) { return false }
        inFlight.insert(id)
        return true
    }

    func finish(_ id: String, _ response: HelperResponse) {
        lock.lock(); defer { lock.unlock() }
        responses[id] = response
        inFlight.remove(id)
    }
}

func runUsbdStop() -> (Int32, String, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    p.arguments = ["-STOP", "-c", "usbd"]
    let out = Pipe(); let err = Pipe()
    p.standardOutput = out
    p.standardError = err
    do { try p.run() } catch { return (1, "", error.localizedDescription) }
    p.waitUntilExit()
    return (p.terminationStatus,
            String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
}

func handle(_ request: HelperRequest, fd: Int32) -> HelperResponse {
    if !HelperRuntime.allowUnsignedTest {
        guard let (identifier, team) = signingInfo(fd: fd),
              identifier == HelperRuntime.expectedBundle, team == HelperRuntime.expectedTeam else {
            return HelperResponse(requestID: request.requestID, ok: false, dispatchTruth: "NOT_DISPATCHED",
                                  exitCode: nil, reason: "CALLER_NOT_AUTHORIZED")
        }
    }
    if let previous = HelperRuntime.seenStore.existing(request.requestID) { return previous }
    guard HelperRuntime.seenStore.reserve(request.requestID) else {
        return HelperResponse(requestID: request.requestID, ok: false, dispatchTruth: "NOT_DISPATCHED",
                              exitCode: nil, reason: "DUPLICATE_IN_FLIGHT")
    }
    if request.action == .status {
        let response = HelperResponse(requestID: request.requestID, ok: true, dispatchTruth: "NOT_DISPATCHED",
                                      exitCode: nil, reason: "READY", helperVersion: mraHelperVersion)
        HelperRuntime.seenStore.finish(request.requestID, response)
        return response
    }
    if request.action == .resetUsbd {
        let (code, stdout, stderr) = runUsbdStop()
        let response = HelperResponse(
            requestID: request.requestID,
            ok: code == 0,
            dispatchTruth: "REQUEST_SENT",
            exitCode: code,
            reason: code == 0 ? "" : (stderr.isEmpty ? "USBD_RESET_FAILED" : String(stderr.prefix(500))),
            stdout: String(stdout.prefix(2000)),
            stderr: String(stderr.prefix(2000)))
        HelperRuntime.seenStore.finish(request.requestID, response)
        return response
    }
    let mismatch = validatePort(request)
    if !mismatch.isEmpty {
        let response = HelperResponse(requestID: request.requestID, ok: false, dispatchTruth: "NOT_DISPATCHED",
                                      exitCode: nil, reason: mismatch)
        HelperRuntime.seenStore.finish(request.requestID, response)
        return response
    }
    let action = request.action.rawValue
    let (code, stdout, stderr) = runBackend(action, controller: request.controller, portNumber: request.portNumber, rid: request.rid)
    let response = HelperResponse(
        requestID: request.requestID,
        ok: code == 0,
        dispatchTruth: code == 0 ? "REQUEST_SENT" : "NOT_DISPATCHED",
        exitCode: code,
        reason: code == 0 ? "" : (stderr.isEmpty ? "BACKEND_FAILED" : String(stderr.prefix(500))),
        stdout: String(stdout.prefix(8000)),
        stderr: String(stderr.prefix(4000)),
        helperVersion: mraHelperVersion)
    HelperRuntime.seenStore.finish(request.requestID, response)
    return response
}

@main
enum HelperEntry {
    static func main() {
        let socketPath = HelperRuntime.socketPath
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { exit(1) }
        unlink(socketPath)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            for i in 0..<min(dst.count, pathBytes.count) { dst[i] = pathBytes[i] }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bindResult == 0, listen(fd, 8) == 0 else { exit(1) }
        do { try MRAHelperCore.applySocketPermissions(path: socketPath) } catch { exit(1) }
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 { continue }
            guard HelperRuntime.connectionLimiter.tryBegin() else {
                close(client)
                continue
            }
            DispatchQueue.global(qos: .userInitiated).async {
                defer {
                    close(client)
                    HelperRuntime.connectionLimiter.end()
                }
                var timeout = timeval(tv_sec: time_t(MRAHelperCore.connectionReadTimeout), tv_usec: 0)
                _ = setsockopt(
                    client, SOL_SOCKET, SO_RCVTIMEO, &timeout,
                    socklen_t(MemoryLayout<timeval>.size))
                var buffer = Data()
                var tmp = [UInt8](repeating: 0, count: 4096)
                let started = Date()
                var lineData: Data?
                while true {
                    if MRAHelperCore.readHasTimedOut(startedAt: started) { return }
                    let n = read(client, &tmp, tmp.count)
                    if n <= 0 { return }
                    let incoming = Data(tmp[0..<n])
                    switch MRAHelperCore.accumulateRequest(buffer: &buffer, incoming: incoming) {
                    case .needMore:
                        continue
                    case .tooLarge:
                        let response = HelperResponse(
                            requestID: "", ok: false, dispatchTruth: "NOT_DISPATCHED",
                            exitCode: nil, reason: "REQUEST_TOO_LARGE")
                        var out = jsonLine(response); out.append(0x0A)
                        _ = out.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
                        return
                    case .complete(let line):
                        lineData = line
                    }
                    break
                }
                guard let lineData,
                      let request = try? JSONDecoder().decode(HelperRequest.self, from: lineData) else { return }
                let response = handle(request, fd: client)
                var out = jsonLine(response); out.append(0x0A)
                _ = out.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
            }
        }
    }
}

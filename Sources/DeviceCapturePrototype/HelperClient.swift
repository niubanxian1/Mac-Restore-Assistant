import Foundation
import Darwin
import MRAHelperProtocol

struct HelperClient {
    var socketPath: String = mraHelperSocketPath

    func request(action: HelperAction, controller: String = "", portNumber: Int = -1,
                 rid: Int = -1, requestID: String = UUID().uuidString) async -> HelperResponse {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: send(action: action, controller: controller,
                                                   portNumber: portNumber, rid: rid,
                                                   requestID: requestID))
            }
        }
    }

    private func send(action: HelperAction, controller: String, portNumber: Int,
                      rid: Int, requestID: String) -> HelperResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return unavailable(requestID) }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = Array(socketPath.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            for i in 0..<min(dst.count, path.count) { dst[i] = path[i] }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
        }
        guard connected == 0 else { return unavailable(requestID) }
        let request = HelperRequest(action: action, requestID: requestID,
                                    controller: controller, portNumber: portNumber, rid: rid)
        var data = (try? JSONEncoder().encode(request)) ?? Data()
        data.append(0x0A)
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while !buffer.contains(0x0A) {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(chunk, count: n)
        }
        guard let line = String(data: buffer, encoding: .utf8)?.split(separator: "\n").first,
              let response = try? JSONDecoder().decode(HelperResponse.self, from: Data(line.utf8)) else {
            return unavailable(requestID)
        }
        return response
    }

    private func unavailable(_ requestID: String) -> HelperResponse {
        HelperResponse(requestID: requestID, ok: false, dispatchTruth: "NOT_DISPATCHED",
                       exitCode: nil, reason: "HELPER_UNAVAILABLE")
    }
}

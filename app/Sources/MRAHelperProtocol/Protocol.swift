import Foundation

public enum HelperAction: String, Codable, Sendable {
    case status
    case probe
    case dfu
    case reboot
    case recovery
    /// Fixed root action: pause the USB daemon for the Owner's Configurator reset.
    case resetUsbd
}

public struct HelperRequest: Codable, Sendable {
    public let action: HelperAction
    public let requestID: String
    public let controller: String
    public let portNumber: Int
    public let rid: Int
    public init(action: HelperAction, requestID: String, controller: String = "",
                portNumber: Int = -1, rid: Int = -1) {
        self.action = action
        self.requestID = requestID
        self.controller = controller
        self.portNumber = portNumber
        self.rid = rid
    }
}

public struct HelperResponse: Codable, Sendable {
    public let requestID: String
    public let ok: Bool
    public let dispatchTruth: String
    public let exitCode: Int32?
    public let reason: String
    public let stdout: String
    public let stderr: String
    public let helperVersion: String
    public init(requestID: String, ok: Bool, dispatchTruth: String,
                exitCode: Int32?, reason: String, stdout: String = "",
                stderr: String = "", helperVersion: String = mraHelperVersion) {
        self.requestID = requestID
        self.ok = ok
        self.dispatchTruth = dispatchTruth
        self.exitCode = exitCode
        self.reason = reason
        self.stdout = stdout
        self.stderr = stderr
        self.helperVersion = helperVersion
    }
}

public let mraHelperServiceID = "com.mra.devicecontrol.helper"
public let mraHelperSocketPath = "/var/run/com.mra.devicecontrol.helper.sock"
public let mraHelperVersion = "0.2.5"

/// Helper → backend CLI flags. Not JSON protocol fields. The backend must
/// require all three and fail closed unless exactly one service matches.
public let mraBackendControllerFlag = "--controller"
public let mraBackendPortNumberFlag = "--port-number"
public let mraBackendRIDFlag = "--rid"

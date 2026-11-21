import Foundation

struct DFUConfirmationProjection: Equatable {
    let operationID: UUID
    let targetPortKey: String
    let scope: DFUConfirmationScope
    let reason: String
    let evidenceTime: TimeInterval?
    let publishedAt: Date
}

extension Notification.Name {
    static let mraDFUConfirmationProjected =
        Notification.Name("MRA.DFUConfirmationProjected")
}

enum DFUAutoNavigationDecision: Equatable {
    case none
    case cue(portID: String, operationID: UUID)
    case navigate(portID: String, operationID: UUID)
}

struct WorkbenchNavigationContext: Equatable {
    let isDeviceWorkspace: Bool
    let restoreTaskActive: Bool
    let settingsPresented: Bool
    let configuratorPresented: Bool
    let followsControlPort: Bool
    let restorePreparationActive: Bool

    init(
        isDeviceWorkspace: Bool,
        restoreTaskActive: Bool,
        settingsPresented: Bool,
        configuratorPresented: Bool,
        followsControlPort: Bool = true,
        restorePreparationActive: Bool = false
    ) {
        self.isDeviceWorkspace = isDeviceWorkspace
        self.restoreTaskActive = restoreTaskActive
        self.settingsPresented = settingsPresented
        self.configuratorPresented = configuratorPresented
        self.followsControlPort = followsControlPort
        self.restorePreparationActive = restorePreparationActive
    }

    var isImportant: Bool {
        !isDeviceWorkspace
            || restoreTaskActive
            || settingsPresented
            || configuratorPresented
            || !followsControlPort
            || restorePreparationActive
    }
}

enum RestoreNavigationTargetResolver {
    static func uniqueTargetID(
        in targets: [RestoreTarget],
        matchingPortID: String
    ) -> String? {
        let matches = targets.filter { $0.portKey == matchingPortID }
        return matches.count == 1 ? matches[0].id : nil
    }
}

struct DFUAutoNavigationCoordinator: Equatable {
    private(set) var expectedPortID: String?
    private(set) var armedAt: Date?
    private(set) var handledOperationID: UUID?

    mutating func arm(portID: String, now: Date = Date()) {
        guard !portID.isEmpty else {
            cancel()
            return
        }
        expectedPortID = portID
        armedAt = now
        handledOperationID = nil
    }

    mutating func evaluate(
        _ event: DFUConfirmationProjection,
        currentControlPortID: String,
        autoNavigationPaused: Bool,
        importantContextActive: Bool
    ) -> DFUAutoNavigationDecision {
        guard
            let expectedPortID,
            let armedAt,
            event.publishedAt >= armedAt,
            event.targetPortKey == expectedPortID,
            handledOperationID != event.operationID
        else {
            return .none
        }
        guard event.targetPortKey == currentControlPortID else {
            cancel()
            return .none
        }

        handledOperationID = event.operationID
        self.expectedPortID = nil
        self.armedAt = nil
        if autoNavigationPaused || importantContextActive {
            return .cue(
                portID: expectedPortID,
                operationID: event.operationID)
        }
        return .navigate(
            portID: expectedPortID,
            operationID: event.operationID)
    }

    mutating func cancel() {
        expectedPortID = nil
        armedAt = nil
        handledOperationID = nil
    }
}

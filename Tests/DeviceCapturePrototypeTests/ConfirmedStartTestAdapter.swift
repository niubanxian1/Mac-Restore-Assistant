import Foundation
@testable import DeviceCapturePrototype

@MainActor
extension RestoreWorkspaceModel {
    /// Test-only adapter: no shortcut around freeze/validate/consume.
    func testStartPrimaryThroughConfirmation() async {
        guard let targetID = selectedTarget?.id,
              freezeRestoreConfirmation(targetID: targetID) else { return }
        _ = await beginUnifiedRestoreAfterConfirmation(targetID: targetID)
    }

    func testStartSecondaryThroughConfirmation(targetID: String) async -> Bool {
        guard freezeRestoreConfirmation(targetID: targetID) else { return false }
        return await beginUnifiedRestoreAfterConfirmation(targetID: targetID)
    }
}

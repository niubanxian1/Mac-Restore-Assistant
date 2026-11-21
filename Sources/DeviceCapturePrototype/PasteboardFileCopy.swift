import Foundation
import AppKit

protocol FilePasteboard {
    func copyFileURL(_ url: URL) throws
}

enum FilePasteboardError: Error, LocalizedError {
    case failed
    var errorDescription: String? { "复制失败" }
}

struct AppKitFilePasteboard: FilePasteboard {
    func copyFileURL(_ url: URL) throws {
        let board = NSPasteboard.general
        board.clearContents()
        let ok = board.writeObjects([url as NSURL])
        if !ok { throw FilePasteboardError.failed }
    }
}

final class MockFilePasteboard: FilePasteboard {
    var copied: [URL] = []
    var shouldFail = false
    func copyFileURL(_ url: URL) throws {
        if shouldFail { throw FilePasteboardError.failed }
        copied.append(url)
    }
}

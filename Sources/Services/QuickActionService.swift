import Foundation
import AppKit
import QuickLookUI

@MainActor
public final class QuickActionService {
    public static let shared = QuickActionService()

    private init() {}

    public func open(item: SearchItem) {
        guard let url = item.fileURL else { return }
        NSWorkspace.shared.open(url)
    }

    public func revealInFinder(item: SearchItem) {
        guard let url = item.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func copyPath(item: SearchItem) {
        guard let path = item.fileURL?.path else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    public func copyFile(item: SearchItem) {
        guard let url = item.fileURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    public func toggleQuickLook(for item: SearchItem) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }
}

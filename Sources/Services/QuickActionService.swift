import Foundation
import AppKit
import QuickLookUI

@MainActor
public final class QuickActionService {
    public static let shared = QuickActionService()

    private let previewController = QuickLookPreviewController()

    private init() {}

    public func open(item: SearchItem) {
        SearchHistoryStore.shared.recordItemOpened(id: item.id)

        if item.kind == .application, let url = item.fileURL {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }

        if item.isOutlookItem {
            // If it is an email attachment file, open it directly in default app
            if let url = item.fileURL, url.path.contains("Attachments") {
                NSWorkspace.shared.open(url)
                return
            }
            // If it is an Outlook message, launch or switch to Microsoft Outlook
            if let outlookURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.Outlook") {
                NSWorkspace.shared.openApplication(at: outlookURL, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }

        if item.kind == .contact {
            if let name = item.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "addressbook://\(name)") {
                NSWorkspace.shared.open(url)
            }
            return
        }

        if item.kind == .calendarEvent {
            if let url = URL(string: "ical://") {
                NSWorkspace.shared.open(url)
            }
            return
        }

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
        guard let url = item.fileURL else { return }

        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible && previewController.currentPreviewItem?.previewItemURL == url {
            panel.orderOut(nil)
            previewController.currentPreviewItem = nil
        } else {
            previewController.currentPreviewItem = url as NSURL
            panel.dataSource = previewController
            panel.delegate = previewController
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        }
    }
}

private final class QuickLookPreviewController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate, @unchecked Sendable {
    var currentPreviewItem: QLPreviewItem?

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return currentPreviewItem == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        return currentPreviewItem
    }
}

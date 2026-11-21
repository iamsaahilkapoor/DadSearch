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
        learnFromLastQuery(item: item)

        if item.kind == .application, let url = item.fileURL {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }

        // Legacy Outlook message: open the exact message via AppleScript, fall back to the message file, then to Outlook itself.
        if item.source == "outlook" {
            if !item.ref.isEmpty, OutlookLegacyConnector.openMessage(recordID: item.ref) { return }
            if let url = item.fileURL, let outlook = OutlookLegacyConnector.outlookAppURL {
                NSWorkspace.shared.open([url], withApplicationAt: outlook, configuration: NSWorkspace.OpenConfiguration())
                return
            }
            if let outlook = OutlookLegacyConnector.outlookAppURL {
                NSWorkspace.shared.openApplication(at: outlook, configuration: NSWorkspace.OpenConfiguration())
            }
            return
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

    /// "You typed X, then opened this" -> X finds this next time (hidden aliases stored in the index).
    private func learnFromLastQuery(item: SearchItem) {
        guard let q = SearchHistoryStore.shared.getRecentQueries(limit: 1).first, q.count >= 3 else { return }
        let parsed = QueryParser.shared.parse(query: q)
        let name = item.title.lowercased()
        let novel = parsed.cleanedTerms.filter { !name.contains($0) }
        guard !novel.isEmpty else { return }
        let key = item.id
        DispatchQueue.global(qos: .utility).async { IndexStore.shared.learn(key: key, terms: novel) }
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

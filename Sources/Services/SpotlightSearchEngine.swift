import Foundation
import AppKit

/// Spotlight is now a SUPPLEMENT to our own index. Its unique value: full-text bodies of Outlook / Apple Mail
/// messages (via their Spotlight importers) and documents our extractor has not reached yet.
public final class SpotlightSearchEngine: @unchecked Sendable {
    public static let shared = SpotlightSearchEngine()
    private var active = Set<SpotlightRun>()
    private let activeLock = NSLock()

    private init() {}

    /// Each call owns its own query object, so a slow old search can never overwrite a newer one.
    public func search(parsed: ParsedQuery, completion: @escaping @Sendable ([SearchItem]) -> Void) {
        let terms = parsed.allTerms
        guard !terms.isEmpty else { completion([]); return }
        guard let predicate = SpotlightSearchEngine.predicate(for: parsed) else { completion([]); return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { completion([]); return }
            let run = SpotlightRun()
            self.activeLock.lock(); self.active.insert(run); self.activeLock.unlock()
            run.start(predicate: predicate) { [weak self] items in
                self?.activeLock.lock(); self?.active.remove(run); self?.activeLock.unlock()
                completion(items)
            }
        }
    }

    static func predicate(for parsed: ParsedQuery) -> NSPredicate? {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        // Every word must match somewhere (name, title, author, or word-prefix inside the text).
        let clauses = parsed.allTerms.map { t -> String in
            let e = esc(t)
            return "(kMDItemTextContent == \"\(e)*\"cd || kMDItemDisplayName == \"*\(e)*\"cd || kMDItemTitle == \"*\(e)*\"cd || kMDItemAuthors == \"*\(e)*\"cd)"
        }
        var query = clauses.joined(separator: " && ")
        if !parsed.detectedFileExtensions.isEmpty {
            let exts = parsed.detectedFileExtensions.map { "kMDItemFSName == \"*.\(esc($0))\"c" }.joined(separator: " || ")
            query += " && (\(exts))"
        }
        if let range = parsed.dateFilterRange {
            let f = ISO8601DateFormatter()
            let a = f.string(from: range.start), b = f.string(from: range.end)
            query += " && ((kMDItemContentModificationDate >= $time.iso(\(a)) && kMDItemContentModificationDate <= $time.iso(\(b))) || (kMDItemDateAdded >= $time.iso(\(a)) && kMDItemDateAdded <= $time.iso(\(b))))"
        }
        return NSPredicate(fromMetadataQueryString: query)
    }
}

private final class SpotlightRun: NSObject {
    private let query = NSMetadataQuery()
    private var finished = false
    private var completion: (([SearchItem]) -> Void)?

    func start(predicate: NSPredicate, completion: @escaping ([SearchItem]) -> Void) {
        self.completion = completion
        query.predicate = predicate
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        NotificationCenter.default.addObserver(self, selector: #selector(done), name: .NSMetadataQueryDidFinishGathering, object: query)
        query.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in self?.done() }
    }

    @objc private func done() {
        guard !finished else { return }
        finished = true
        query.disableUpdates()
        query.stop()
        NotificationCenter.default.removeObserver(self)
        var items: [SearchItem] = []
        let count = min(query.resultCount, 300)
        for i in 0..<count {
            guard let mdItem = query.result(at: i) as? NSMetadataItem,
                  let path = mdItem.value(forAttribute: kMDItemPath as String) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            let type = (mdItem.value(forAttribute: kMDItemContentType as String) as? String) ?? ""
            let isMail = type.contains("outlook") || type.contains("emlx") || type.contains("email")
            let display = (mdItem.value(forAttribute: kMDItemTitle as String) as? String)
                ?? (mdItem.value(forAttribute: kMDItemDisplayName as String) as? String) ?? url.lastPathComponent
            let mod = (mdItem.value(forAttribute: kMDItemContentModificationDate as String) as? Date) ?? Date()
            let added = mdItem.value(forAttribute: kMDItemDateAdded as String) as? Date
            let authors = (mdItem.value(forAttribute: kMDItemAuthors as String) as? [String])?.joined(separator: ", ")
            let ext = url.pathExtension.lowercased()
            let kind: SearchItemKind = isMail ? .email
                : KindClassifier.kind(ext: ext, name: url.lastPathComponent, isDirectory: false, isPackage: false, path: path)
            items.append(SearchItem(
                id: path, title: display,
                subtitle: path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                fileURL: url, kind: kind, modificationDate: mod, addedDate: added,
                fileSize: nil, authorOrSender: authors,
                isOutlookItem: type.contains("outlook"), matchSnippet: nil, score: 0,
                source: "spotlight", ref: "", isHidden: false
            ))
        }
        let c = completion
        completion = nil
        c?(items)
    }
}

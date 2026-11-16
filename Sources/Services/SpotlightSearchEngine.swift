import Foundation
import CoreServices

public final class SpotlightSearchEngine: @unchecked Sendable {
    public static let shared = SpotlightSearchEngine()

    private var metadataQuery: NSMetadataQuery?
    private var completionHandler: (([SearchItem]) -> Void)?

    public init() {}

    public func search(
        parsedQuery: ParsedQuery,
        category: SearchCategoryFilter,
        completion: @escaping @Sendable ([SearchItem]) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stopCurrentQuery()

            let query = NSMetadataQuery()
            self.metadataQuery = query
            self.completionHandler = completion

            var subpredicates: [NSPredicate] = []

            // 1. Text Search terms
            let term = parsedQuery.searchTerm
            if !term.isEmpty {
                let escapedTerm = term.replacingOccurrences(of: "\"", with: "\\\"")
                let namePredicate = NSPredicate(format: "%K LIKE[cd] %@", kMDItemDisplayName as String, "*\(escapedTerm)*")
                let contentPredicate = NSPredicate(format: "%K LIKE[cd] %@", kMDItemTextContent as String, "*\(escapedTerm)*")
                let emailSubjectPredicate = NSPredicate(format: "%K LIKE[cd] %@", "kMDItemTitle", "*\(escapedTerm)*")
                let authorPredicate = NSPredicate(format: "%K LIKE[cd] %@", kMDItemAuthors as String, "*\(escapedTerm)*")

                let combinedOr = NSCompoundPredicate(orPredicateWithSubpredicates: [
                    namePredicate, contentPredicate, emailSubjectPredicate, authorPredicate
                ])
                subpredicates.append(combinedOr)
            }

            // 2. Specific extensions
            if !parsedQuery.detectedFileExtensions.isEmpty {
                let extPredicates = parsedQuery.detectedFileExtensions.map { ext in
                    NSPredicate(format: "%K LIKE[cd] %@", kMDItemFSName as String, "*.\(ext)")
                }
                subpredicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: extPredicates))
            }

            // 3. Date constraints
            if let dateRange = parsedQuery.dateFilterRange {
                let datePred = NSPredicate(
                    format: "%K >= %@ AND %K <= %@",
                    kMDItemContentModificationDate as String,
                    dateRange.start as NSDate,
                    kMDItemContentModificationDate as String,
                    dateRange.end as NSDate
                )
                subpredicates.append(datePred)
            } else if category == .recent {
                let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                let datePred = NSPredicate(
                    format: "%K >= %@",
                    kMDItemContentModificationDate as String,
                    sevenDaysAgo as NSDate
                )
                subpredicates.append(datePred)
            }

            // 4. Category filtering
            switch category {
            case .emails:
                let emailPred = NSPredicate(
                    format: "%K ==[cd] %@ OR %K LIKE[cd] %@ OR %K LIKE[cd] %@",
                    kMDItemContentType as String, "com.microsoft.outlook16.email-message",
                    kMDItemFSName as String, "*.eml",
                    kMDItemFSName as String, "*.olk15Message"
                )
                subpredicates.append(emailPred)
            case .documents:
                let docPred = NSPredicate(
                    format: "%K LIKE[cd] %@ OR %K LIKE[cd] %@ OR %K LIKE[cd] %@ OR %K LIKE[cd] %@",
                    kMDItemFSName as String, "*.pdf",
                    kMDItemFSName as String, "*.docx",
                    kMDItemFSName as String, "*.doc",
                    kMDItemFSName as String, "*.xlsx"
                )
                subpredicates.append(docPred)
            case .downloads:
                // Scoped search in Downloads
                if let dlURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                    query.searchScopes = [dlURL]
                }
            case .all, .recent, .screenshots, .chatAttachments:
                break
            }

            if subpredicates.isEmpty {
                // Return default non-empty fallback query (everything recent in user home)
                query.searchScopes = [NSMetadataQueryUserHomeScope]
                let recentDays = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                query.predicate = NSPredicate(format: "%K >= %@", kMDItemContentModificationDate as String, recentDays as NSDate)
            } else if subpredicates.count == 1 {
                query.predicate = subpredicates[0]
                if query.searchScopes.isEmpty {
                    query.searchScopes = [NSMetadataQueryUserHomeScope]
                }
            } else {
                query.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
                if query.searchScopes.isEmpty {
                    query.searchScopes = [NSMetadataQueryUserHomeScope]
                }
            }

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.queryDidFinishGathering(_:)),
                name: .NSMetadataQueryDidFinishGathering,
                object: query
            )

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.queryDidUpdate(_:)),
                name: .NSMetadataQueryDidUpdate,
                object: query
            )

            query.start()
        }
    }

    public func stopCurrentQuery() {
        if let query = metadataQuery {
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: query)
            query.stop()
            metadataQuery = nil
        }
    }

    @objc private func queryDidFinishGathering(_ notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery else { return }
        query.disableUpdates()
        processQueryResults(query)
        query.enableUpdates()
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery else { return }
        query.disableUpdates()
        processQueryResults(query)
        query.enableUpdates()
    }

    private func processQueryResults(_ query: NSMetadataQuery) {
        var items: [SearchItem] = []
        let count = min(query.resultCount, 80)

        for i in 0..<count {
            guard let result = query.result(at: i) as? NSMetadataItem else { continue }

            let path = result.value(forAttribute: kMDItemPath as String) as? String
            let displayName = result.value(forAttribute: kMDItemDisplayName as String) as? String
                ?? result.value(forAttribute: "kMDItemTitle") as? String
                ?? (path != nil ? (path! as NSString).lastPathComponent : "Untitled")

            let modDate = result.value(forAttribute: kMDItemContentModificationDate as String) as? Date ?? Date()
            let contentType = result.value(forAttribute: kMDItemContentType as String) as? String ?? ""
            let fsSize = (result.value(forAttribute: kMDItemFSSize as String) as? NSNumber)?.int64Value
            let authors = result.value(forAttribute: kMDItemAuthors as String) as? [String]
            let author = authors?.first

            var fileURL: URL? = nil
            if let path = path {
                fileURL = URL(fileURLWithPath: path)
            }

            let isOutlook = contentType.contains("outlook") || (path?.contains("Outlook") == true) || (path?.hasSuffix(".eml") == true)
            let kind: SearchItemKind
            if isOutlook {
                kind = .email
            } else if let path = path, path.contains("/Downloads/") {
                kind = .download
            } else if contentType.contains("image") {
                kind = .image
            } else if contentType.contains("pdf") || contentType.contains("document") || contentType.contains("presentation") || contentType.contains("spreadsheet") {
                kind = .document
            } else {
                kind = .other
            }

            let subtitle: String
            if isOutlook {
                subtitle = "Outlook Message" + (author != nil ? " • From: \(author!)" : "")
            } else if let path = path {
                subtitle = (path as NSString).abbreviatingWithTildeInPath
            } else {
                subtitle = "Document"
            }

            let item = SearchItem(
                id: path ?? UUID().uuidString,
                title: displayName,
                subtitle: subtitle,
                fileURL: fileURL,
                kind: kind,
                modificationDate: modDate,
                addedDate: nil,
                fileSize: fsSize,
                authorOrSender: author,
                isOutlookItem: isOutlook,
                matchSnippet: nil
            )
            items.append(item)
        }

        // Sort: newest first
        items.sort { $0.modificationDate > $1.modificationDate }

        let handler = completionHandler
        DispatchQueue.main.async {
            handler?(items)
        }
    }
}

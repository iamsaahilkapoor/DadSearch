import Foundation

public final class RelevanceRankingEngine: Sendable {
    public static let shared = RelevanceRankingEngine()

    public init() {}

    public func rank(
        items: [SearchItem],
        parsedQuery: ParsedQuery,
        targetCategory: SearchCategoryFilter
    ) -> [SearchItem] {
        let searchTerm = parsedQuery.searchTerm.lowercased().trimmingCharacters(in: .whitespaces)
        guard !searchTerm.isEmpty else {
            // When query is empty, sort purely by recent modification/added date
            return items.sorted {
                ($0.addedDate ?? $0.modificationDate) > ($1.addedDate ?? $1.modificationDate)
            }
        }

        var scoredItems = items.map { item -> SearchItem in
            var copy = item
            copy.score = calculateScore(for: item, term: searchTerm, query: parsedQuery, category: targetCategory)
            return copy
        }

        scoredItems.sort { a, b in
            if abs(a.score - b.score) > 0.001 {
                return a.score > b.score
            }
            return (a.addedDate ?? a.modificationDate) > (b.addedDate ?? b.modificationDate)
        }

        return scoredItems
    }

    private func calculateScore(
        for item: SearchItem,
        term: String,
        query: ParsedQuery,
        category: SearchCategoryFilter
    ) -> Double {
        var score: Double = 0.0
        let titleLower = item.title.lowercased()
        let subtitleLower = item.subtitle.lowercased()

        // 1. Title Exact Match
        if titleLower == term {
            score += 200.0
        } else if titleLower.hasPrefix(term) {
            score += 120.0
        } else if titleLower.contains(term) {
            score += 80.0
        } else {
            // Subtitle / path match
            if subtitleLower.contains(term) {
                score += 30.0
            }
        }

        // 2. Token overlap
        for token in query.cleanedTerms {
            let lowerToken = token.lowercased()
            if titleLower.contains(lowerToken) {
                score += 25.0
            }
        }

        // 3. Category alignment boost
        if let inferred = query.inferredCategory {
            if matchesCategory(kind: item.kind, category: inferred) {
                score += 40.0
            }
        }

        // 4. Recency boost (exponential decay up to 40 pts)
        let date = item.addedDate ?? item.modificationDate
        let daysAgo = max(0, Date().timeIntervalSince(date) / (86400.0))
        if daysAgo < 1.0 {
            score += 40.0
        } else if daysAgo < 7.0 {
            score += 25.0
        } else if daysAgo < 30.0 {
            score += 10.0
        }

        // 5. Historical frecency boost
        score += SearchHistoryStore.shared.getFrecencyScore(id: item.id)

        // 6. Application priority bonus (when searching an app name)
        if item.kind == .application && (titleLower.hasPrefix(term) || titleLower == term) {
            score += 50.0
        }

        return score
    }

    private func matchesCategory(kind: SearchItemKind, category: SearchCategoryFilter) -> Bool {
        switch (kind, category) {
        case (.document, .documents): return true
        case (.download, .downloads): return true
        case (.email, .emails): return true
        case (.screenshot, .screenshots): return true
        case (.chatAttachment, .chatAttachments): return true
        case (.application, .apps): return true
        case (.contact, .contacts): return true
        case (.calendarEvent, .contacts): return true
        default: return false
        }
    }
}

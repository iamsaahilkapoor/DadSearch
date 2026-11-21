import Foundation

/// One scoring function for every provider, so index, Spotlight, apps and contacts compete fairly.
public final class RelevanceRankingEngine: @unchecked Sendable {
    public static let shared = RelevanceRankingEngine()
    public init() {}

    /// tier: 0 exact, 1 fuzzy/synonym, 2 relaxed. bm25: SQLite's rank (more negative = better).
    func score(item: SearchItem, bm25: Double, parsed: ParsedQuery, tier: Int, frecency: [String: Int], now: Date = Date()) -> Double {
        var s = 0.0
        let name = item.title.lowercased()
        let nameNoExt = (name as NSString).deletingPathExtension
        let terms = parsed.allTerms
        let joined = terms.joined(separator: " ")
        let meta = ((item.authorOrSender ?? "") + " " + item.subtitle).lowercased()

        if !terms.isEmpty {
            if name == joined || nameNoExt == joined { s += 200 }
            else if name.hasPrefix(joined) { s += 120 }
            else if name.contains(joined) { s += 90 }
            var matched = 0
            for t in terms {
                if name.contains(t) { s += 30; matched += 1 }
                else if meta.contains(t) { s += 12 }
            }
            if matched == terms.count { s += 40 }
            if item.kind == .application && name.hasPrefix(terms[0]) { s += 60 }
        }
        s += min(40, max(0, -bm25) * 4)

        let date = max(item.addedDate ?? .distantPast, item.modificationDate)
        let days = max(0, now.timeIntervalSince(date) / 86_400)
        s += 40 * exp(-days / 30)

        if let soft = parsed.softDateRange, soft.contains(date) { s += 30 }
        if parsed.kindHints.contains(item.kind) { s += 25 }
        s += min(Double(frecency[item.id] ?? 0) * 15, 60)

        if item.isHidden && !parsed.rawQuery.contains(".") { s -= 35 }
        if item.kind == .folder && terms.count > 0 && !name.contains(joined) { s -= 20 }
        s -= Double(tier) * 30
        return s
    }

    /// Backwards-compatible entry point.
    public func rank(items: [SearchItem], parsedQuery: ParsedQuery, targetCategory: SearchCategoryFilter) -> [SearchItem] {
        let frec = SearchHistoryStore.shared.frecencySnapshot()
        return items.map { var i = $0; i.score = score(item: $0, bm25: 0, parsed: parsedQuery, tier: 0, frecency: frec); return i }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.modificationDate > $1.modificationDate }
    }
}

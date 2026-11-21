import Foundation

struct SearchOutcome {
    var items: [SearchItem] = []
    var note: String? = nil
    var tier = 0
}

/// Index search in three tiers so a typo or an over-eager filter never produces an empty screen:
///   0  exact: every word must appear (name, sender, origin, body, learned aliases), filters applied
///   1  widened: typo fixes from the user's own vocabulary + synonyms (bill ~ invoice ~ statement)
///   2  relaxed: filters dropped, any word may match
final class UniversalSearch: @unchecked Sendable {
    static let shared = UniversalSearch()
    private let store = IndexStore.shared
    private let ranker = RelevanceRankingEngine.shared

    func browse(includeHidden: Bool, limit: Int = 30) -> [SearchItem] {
        let hits = store.recent(limit: limit * 3, includeHidden: includeHidden)
            .filter { !($0.path ?? "").contains("/Library/") || $0.source != "file" }
        return Array(hits.prefix(limit)).map { item(from: $0, parsed: nil) }
    }

    func search(parsed: ParsedQuery, category: SearchCategoryFilter, includeHidden: Bool, now: Date = Date()) -> SearchOutcome {
        var base = StoreQuery()
        base.includeHidden = includeHidden
        applyFilters(&base, parsed: parsed, category: category, now: now)
        let terms = parsed.allTerms
        base.termGroups = terms.map { [$0] }

        // Tier 0
        var hits = store.search(base)
        var tier = 0
        var note: String? = nil
        var tierOf: [String: Int] = [:]
        hits.forEach { tierOf[$0.key] = 0 }

        // Tier 1: typos + synonyms
        if hits.count < 6 && !terms.isEmpty {
            var widened = base
            var changed = false
            var fixes: [String] = []
            widened.termGroups = terms.map { t in
                var alts = [t]
                if !store.vocabulary.contains(t) {
                    let s = store.vocabulary.suggestions(for: t)
                    if !s.isEmpty { alts.append(contentsOf: s); fixes.append(s[0]); changed = true }
                }
                if let syn = Lexicon.synonymIndex[t] { alts.append(contentsOf: syn); changed = true }
                return alts
            }
            if changed {
                for h in store.search(widened) where tierOf[h.key] == nil { hits.append(h); tierOf[h.key] = 1 }
                tier = 1
                if !fixes.isEmpty { note = "Also showing results for “\(fixes.joined(separator: "”, “"))”" }
            }
        }

        // Tier 2: drop filters, match any word
        if hits.count < 3 {
            var relaxed = StoreQuery()
            relaxed.includeHidden = includeHidden
            relaxed.termGroups = terms.map { t in
                var alts = [t]
                alts.append(contentsOf: store.vocabulary.suggestions(for: t))
                alts.append(contentsOf: Lexicon.synonymIndex[t] ?? [])
                return alts
            }
            relaxed.matchAny = true
            if !terms.isEmpty {
                for h in store.search(relaxed) where tierOf[h.key] == nil { hits.append(h); tierOf[h.key] = 2 }
                if hits.count > 0 { tier = 2; note = "No exact match — showing the closest results" }
            }
        }

        let frec = SearchHistoryStore.shared.frecencySnapshot()
        var items: [SearchItem] = hits.map { h in
            var it = item(from: h, parsed: parsed)
            it.score = ranker.score(item: it, bm25: h.bm25, parsed: parsed, tier: tierOf[h.key] ?? 0, frecency: frec, now: now)
            return it
        }
        items.sort { $0.score != $1.score ? $0.score > $1.score : $0.modificationDate > $1.modificationDate }
        items = Array(items.prefix(80))

        // Snippets only for what will actually be shown (reads the stored text for ~25 rows)
        if !terms.isEmpty {
            let byKey = Dictionary(uniqueKeysWithValues: hits.map { ($0.key, $0.id) })
            items = items.enumerated().map { idx, it in
                guard idx < 25, it.matchSnippet == nil, let id = byKey[it.id] else { return it }
                let body = store.bodyText(id: id)
                guard let snip = UniversalSearch.snippet(in: body, terms: terms) else { return it }
                return SearchItem(id: it.id, title: it.title, subtitle: it.subtitle, fileURL: it.fileURL, kind: it.kind,
                                  modificationDate: it.modificationDate, addedDate: it.addedDate, fileSize: it.fileSize,
                                  authorOrSender: it.authorOrSender, isOutlookItem: it.isOutlookItem, matchSnippet: snip,
                                  score: it.score, source: it.source, ref: it.ref, isHidden: it.isHidden)
            }
        }
        return SearchOutcome(items: items, note: note, tier: tier)
    }

    // MARK: - Helpers

    private func applyFilters(_ q: inout StoreQuery, parsed: ParsedQuery, category: SearchCategoryFilter, now: Date) {
        q.dateRange = parsed.dateFilterRange
        switch category {
        case .all:
            q.extensions = parsed.detectedFileExtensions
            q.kinds = parsed.kindHints
            q.sources = parsed.sourceHints
            if parsed.downloadsOnly { q.pathContains = "/Downloads/" }
        case .downloads:
            q.pathContains = "/Downloads/"
            q.extensions = parsed.detectedFileExtensions
        case .screenshots: q.kinds = [.screenshot]
        case .chatAttachments: q.sources = ["messages", "whatsapp", "telegram", "mail-attachment", "outlook-attachment"]
        case .emails: q.kinds = [.email]
        case .documents:
            q.kinds = [.document]
            q.extensions = parsed.detectedFileExtensions
        case .folders: q.kinds = [.folder]
        case .recent: q.dateRange = DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now)
        case .apps, .contacts: break
        }
    }

    private func item(from h: StoreHit, parsed: ParsedQuery?) -> SearchItem {
        let isEmail = h.kind == .email
        let home = NSHomeDirectory()
        var subtitle: String
        if isEmail {
            let who = h.sender.isEmpty ? "" : " • From: \(h.sender)"
            subtitle = (h.source == "outlook" ? "Outlook" : "Mail") + who
        } else {
            let shown = (h.path ?? "").replacingOccurrences(of: home, with: "~")
            subtitle = shown
            if let host = h.origin.split(separator: " ").compactMap({ URL(string: String($0))?.host }).first {
                subtitle += " • from \(host)"
            }
        }
        return SearchItem(
            id: h.key, title: h.name, subtitle: subtitle,
            fileURL: h.path.map { URL(fileURLWithPath: $0) },
            kind: h.kind, modificationDate: h.mtime, addedDate: h.added,
            fileSize: h.size > 0 ? h.size : nil,
            authorOrSender: h.sender.isEmpty ? nil : h.sender,
            isOutlookItem: h.source.hasPrefix("outlook"),
            matchSnippet: isEmail && !h.snippet.isEmpty ? h.snippet : nil,
            score: 0, source: h.source, ref: h.ref, isHidden: h.hidden
        )
    }

    static func snippet(in body: String, terms: [String]) -> String? {
        guard !body.isEmpty else { return nil }
        let lower = body.lowercased()
        for t in terms {
            if let r = lower.range(of: t) {
                let start = lower.distance(from: lower.startIndex, to: r.lowerBound)
                let a = max(0, start - 50)
                let chars = Array(body)
                let b = min(chars.count, start + t.count + 90)
                let piece = String(chars[a..<b]).replacingOccurrences(of: "\n", with: " ")
                return (a > 0 ? "…" : "") + piece + (b < chars.count ? "…" : "")
            }
        }
        return nil
    }
}

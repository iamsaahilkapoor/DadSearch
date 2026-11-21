import Foundation

public final class SearchHistoryStore: @unchecked Sendable {
    public static let shared = SearchHistoryStore()

    private let defaults = UserDefaults.standard
    private let historyKey = "com.saahil.DadSearch.searchHistory"
    private let frecencyKey = "com.saahil.DadSearch.openCounts"

    private init() {}

    public func getRecentQueries(limit: Int = 10) -> [String] {
        return (defaults.stringArray(forKey: historyKey) ?? []).prefix(limit).map { $0 }
    }

    public func recordQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }

        var list = defaults.stringArray(forKey: historyKey) ?? []
        list.removeAll(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        list.insert(trimmed, at: 0)

        if list.count > 30 {
            list = Array(list.prefix(30))
        }
        defaults.set(list, forKey: historyKey)
    }

    public func recordItemOpened(id: String) {
        var counts = defaults.dictionary(forKey: frecencyKey) as? [String: Int] ?? [:]
        counts[id] = (counts[id] ?? 0) + 1
        defaults.set(counts, forKey: frecencyKey)
    }

    public func getFrecencyScore(id: String) -> Double {
        let counts = defaults.dictionary(forKey: frecencyKey) as? [String: Int] ?? [:]
        let count = counts[id] ?? 0
        return min(Double(count) * 15.0, 60.0) // Up to +60 boost
    }

    public func frecencySnapshot() -> [String: Int] {
        defaults.dictionary(forKey: frecencyKey) as? [String: Int] ?? [:]
    }

    public func clearHistory() {
        defaults.removeObject(forKey: historyKey)
        defaults.removeObject(forKey: frecencyKey)
    }
}

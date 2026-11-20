import Foundation
import Combine
import SwiftUI

@MainActor
public final class SearchViewModel: ObservableObject {
    @Published public var rawQuery: String = ""
    @Published public var selectedCategory: SearchCategoryFilter = .all
    @Published public var results: [SearchItem] = []
    @Published public var todayArrivals: [SearchItem] = []
    @Published public var selectedItem: SearchItem?
    @Published public var isSearching: Bool = false
    @Published public var parsedQuery: ParsedQuery = ParsedQuery(rawQuery: "", cleanedTerms: [])
    @Published public var recentQueries: [String] = []

    private var cancellables = Set<AnyCancellable>()
    private let queryParser = QueryParser.shared
    private let indexDB = SearchIndexDatabase.shared
    private let synonymRings = BusinessSynonymRings.shared
    private let appLauncher = AppLauncherEngine.shared
    private let contactsEngine = ContactsSearchEngine.shared
    private let calendarEngine = CalendarSearchEngine.shared
    private let historyStore = SearchHistoryStore.shared

    public init() {
        setupBindings()
        refreshHistory()
        bootstrapIndex()
        loadInitialRecents()
    }

    public func refreshHistory() {
        self.recentQueries = historyStore.getRecentQueries(limit: 6)
    }

    private func bootstrapIndex() {
        // Start real-time file system watchers (FSEvents)
        FSEventsService.shared.start()

        // Bootstrap existing local files and Apple Mail into FTS5 index in background
        Task.detached(priority: .utility) {
            // 1. Initial crawl of Downloads
            let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            if let files = try? FileManager.default.contentsOfDirectory(at: downloadsURL, includingPropertiesForKeys: nil) {
                for file in files.prefix(150) {
                    await DocumentContentExtractor.shared.indexFile(at: file)
                }
            }

            // 2. Initial crawl of Desktop screenshots & docs
            let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            if let files = try? FileManager.default.contentsOfDirectory(at: desktopURL, includingPropertiesForKeys: nil) {
                for file in files.prefix(60) {
                    await DocumentContentExtractor.shared.indexFile(at: file)
                }
            }

            // 3. Sync Apple Mail Envelope Index
            AppleMailDatabaseReader.shared.syncAppleMailMessages(limit: 300)

            // Update Coverage Health
            Task { @MainActor in
                CoverageHealthService.shared.checkHealth()
            }
        }
    }

    private func setupBindings() {
        $rawQuery
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] newQuery in
                self?.performSearch(query: newQuery)
            }
            .store(in: &cancellables)

        $selectedCategory
            .dropFirst()
            .sink { [weak self] newCategory in
                guard let self = self else { return }
                self.performSearch(query: self.rawQuery, forcedCategory: newCategory)
            }
            .store(in: &cancellables)
    }

    public func loadInitialRecents() {
        isSearching = true

        // 1. Fetch Arrival Radar (today's newly landed items)
        let arrivals = indexDB.fetchTodayArrivals(limit: 30)
        self.todayArrivals = arrivals

        // 2. Fetch recent documents across categories
        let recents = indexDB.fetchRecentDocuments(category: selectedCategory, limit: 30)
        let apps = appLauncher.fetchApplications(limit: 6)

        let merged = (arrivals + recents + apps).sorted {
            ($0.addedDate ?? $0.modificationDate) > ($1.addedDate ?? $1.modificationDate)
        }

        // Deduplicate by path / id
        var seen = Set<String>()
        var unique: [SearchItem] = []
        for item in merged {
            let key = item.fileURL?.path ?? item.id
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(item)
            }
        }

        self.results = unique
        self.selectedItem = unique.first
        self.isSearching = false
    }

    public func performSearch(query: String, forcedCategory: SearchCategoryFilter? = nil) {
        let parsed = queryParser.parse(query: query)
        self.parsedQuery = parsed
        let category = forcedCategory ?? parsed.inferredCategory ?? self.selectedCategory

        // If query is empty and category is all, load initial recents & radar
        if parsed.rawQuery.isEmpty && category == .all {
            loadInitialRecents()
            return
        }

        self.isSearching = true

        // Record history for substantive queries
        if !parsed.searchTerm.isEmpty {
            historyStore.recordQuery(query)
            refreshHistory()
        }

        // Fast path: Apps only
        if category == .apps {
            let apps = appLauncher.fetchApplications(keyword: parsed.searchTerm, limit: 40)
            self.results = apps
            self.selectedItem = apps.first
            self.isSearching = false
            return
        }

        // Fast path: Contacts & Calendar
        if category == .contacts {
            let contacts = contactsEngine.searchContacts(keyword: parsed.searchTerm, limit: 15)
            let events = calendarEngine.searchEvents(keyword: parsed.searchTerm, limit: 15)
            let merged = contacts + events
            self.results = merged
            self.selectedItem = merged.first
            self.isSearching = false
            return
        }

        // 1. Expand search term with Business Synonym Rings (e.g. "invoice" -> "bill", "statement", "po")
        let synonyms = synonymRings.expandQuery(parsed.searchTerm)
        let effectiveQuery = (synonyms.isEmpty ? parsed.searchTerm : synonyms.joined(separator: " ")).trimmingCharacters(in: .whitespaces)

        // 2. Execute Sub-millisecond SQLite FTS5 Trigram query (zero caps, true multi-word matching!)
        var ftsResults = indexDB.search(query: effectiveQuery.isEmpty ? parsed.searchTerm : effectiveQuery, category: category, limit: 100)

        // 3. Date filtering if natural date detected (NSDataDetector)
        if let dateInterval = parsed.dateFilterRange {
            ftsResults = ftsResults.filter { item in
                let targetDate = item.addedDate ?? item.modificationDate
                return dateInterval.contains(targetDate)
            }
        }

        // 4. Augment with active Apps / Contacts if in "All" mode
        var supplementary: [SearchItem] = []
        if category == .all && !parsed.searchTerm.isEmpty {
            let matchedApps = appLauncher.fetchApplications(keyword: parsed.searchTerm, limit: 4)
            supplementary.append(contentsOf: matchedApps)

            let contacts = contactsEngine.searchContacts(keyword: parsed.searchTerm, limit: 3)
            supplementary.append(contentsOf: contacts)

            let events = calendarEngine.searchEvents(keyword: parsed.searchTerm, limit: 3)
            supplementary.append(contentsOf: events)
        }

        // Deduplicate and rank
        var seen = Set<String>()
        var finalItems: [SearchItem] = []

        for item in (supplementary + ftsResults) {
            let key = item.fileURL?.path ?? item.id
            if !seen.contains(key) {
                seen.insert(key)
                finalItems.append(item)
            }
        }

        self.results = finalItems
        if self.selectedItem == nil || !finalItems.contains(where: { $0.id == self.selectedItem?.id }) {
            self.selectedItem = finalItems.first
        }
        self.isSearching = false
    }

    public func selectNext() {
        guard !results.isEmpty else { return }
        guard let current = selectedItem, let idx = results.firstIndex(of: current) else {
            selectedItem = results.first
            return
        }
        let nextIdx = min(idx + 1, results.count - 1)
        selectedItem = results[nextIdx]
    }

    public func selectPrevious() {
        guard !results.isEmpty else { return }
        guard let current = selectedItem, let idx = results.firstIndex(of: current) else {
            selectedItem = results.first
            return
        }
        let prevIdx = max(idx - 1, 0)
        selectedItem = results[prevIdx]
    }

    public func handleItemOpened(_ item: SearchItem) {
        QuickActionService.shared.open(item: item)
        // Record learned alias for this query and item
        if !rawQuery.isEmpty {
            indexDB.recordAlias(query: rawQuery, forId: item.id)
        }
    }
}

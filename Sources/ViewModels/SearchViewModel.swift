import Foundation
import Combine
import SwiftUI

@MainActor
public final class SearchViewModel: ObservableObject {
    @Published public var rawQuery: String = ""
    @Published public var selectedCategory: SearchCategoryFilter = .all
    @Published public var results: [SearchItem] = []
    @Published public var selectedItem: SearchItem?
    @Published public var isSearching: Bool = false
    @Published public var parsedQuery: ParsedQuery = ParsedQuery(rawQuery: "", cleanedTerms: [])
    @Published public var recentQueries: [String] = []

    private var cancellables = Set<AnyCancellable>()
    private let queryParser = QueryParser.shared
    private let downloadsTracker = DownloadsTracker.shared
    private let screenshotsTracker = ScreenshotsTracker.shared
    private let chatAttachmentsIndexer = ChatAttachmentsIndexer.shared
    private let spotlightEngine = SpotlightSearchEngine.shared
    private let outlookEngine = OutlookSearchEngine.shared
    private let appLauncher = AppLauncherEngine.shared
    private let contactsEngine = ContactsSearchEngine.shared
    private let calendarEngine = CalendarSearchEngine.shared
    private let rankingEngine = RelevanceRankingEngine.shared
    private let historyStore = SearchHistoryStore.shared

    public init() {
        setupBindings()
        refreshHistory()
        loadInitialRecents()
    }

    public func refreshHistory() {
        self.recentQueries = historyStore.getRecentQueries(limit: 6)
    }

    private func setupBindings() {
        $rawQuery
            .debounce(for: .milliseconds(180), scheduler: RunLoop.main)
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
        let recentDownloads = downloadsTracker.fetchRecentDownloads(limit: 20)
        let recentScreenshots = screenshotsTracker.fetchRecentScreenshots(limit: 15)
        let recentApps = appLauncher.fetchApplications(limit: 10)

        let merged = (recentDownloads + recentScreenshots + recentApps).sorted {
            ($0.addedDate ?? $0.modificationDate) > ($1.addedDate ?? $1.modificationDate)
        }
        self.results = merged
        self.selectedItem = merged.first
        self.isSearching = false
    }

    public func performSearch(query: String, forcedCategory: SearchCategoryFilter? = nil) {
        let parsed = queryParser.parse(query: query)
        self.parsedQuery = parsed
        let category = forcedCategory ?? parsed.inferredCategory ?? self.selectedCategory

        // If query is empty and category is all, load initial recents
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

        // Fast path 1: Apps only
        if category == .apps {
            let apps = appLauncher.fetchApplications(keyword: parsed.searchTerm, limit: 40)
            let ranked = rankingEngine.rank(items: apps, parsedQuery: parsed, targetCategory: category)
            self.results = ranked
            self.selectedItem = ranked.first
            self.isSearching = false
            return
        }

        // Fast path 2: Screenshots chip
        if category == .screenshots {
            let shots = screenshotsTracker.fetchRecentScreenshots(limit: 50, keyword: parsed.searchTerm)
            let ranked = rankingEngine.rank(items: shots, parsedQuery: parsed, targetCategory: category)
            self.results = ranked
            self.selectedItem = ranked.first
            self.isSearching = false
            return
        }

        // Fast path 3: Chat & Attachments chip
        if category == .chatAttachments {
            let chatFiles = chatAttachmentsIndexer.fetchRecentChatAttachments(limit: 50, keyword: parsed.searchTerm)
            let ranked = rankingEngine.rank(items: chatFiles, parsedQuery: parsed, targetCategory: category)
            self.results = ranked
            self.selectedItem = ranked.first
            self.isSearching = false
            return
        }

        // Fast path 4: Contacts & Calendar
        if category == .contacts {
            let contacts = contactsEngine.searchContacts(keyword: parsed.searchTerm, limit: 15)
            let events = calendarEngine.searchEvents(keyword: parsed.searchTerm, limit: 15)
            let merged = contacts + events
            let ranked = rankingEngine.rank(items: merged, parsedQuery: parsed, targetCategory: category)
            self.results = ranked
            self.selectedItem = ranked.first
            self.isSearching = false
            return
        }

        // Synchronous immediate results gather
        var immediateResults: [SearchItem] = []

        if category == .all || category == .downloads {
            let downloads = downloadsTracker.fetchRecentDownloads(limit: 40)
            if !parsed.searchTerm.isEmpty {
                let lower = parsed.searchTerm.lowercased()
                immediateResults = downloads.filter {
                    $0.title.localizedCaseInsensitiveContains(lower) ||
                    $0.subtitle.localizedCaseInsensitiveContains(lower)
                }
            } else {
                immediateResults = downloads
            }
        }

        if category == .all {
            let shots = screenshotsTracker.fetchRecentScreenshots(limit: 15, keyword: parsed.searchTerm)
            immediateResults.append(contentsOf: shots)

            if !parsed.searchTerm.isEmpty {
                let matchedApps = appLauncher.fetchApplications(keyword: parsed.searchTerm, limit: 5)
                immediateResults.append(contentsOf: matchedApps)

                let contacts = contactsEngine.searchContacts(keyword: parsed.searchTerm, limit: 3)
                immediateResults.append(contentsOf: contacts)

                let events = calendarEngine.searchEvents(keyword: parsed.searchTerm, limit: 3)
                immediateResults.append(contentsOf: events)
            }
        }

        // Query Spotlight for deeper system search & Outlook messages
        let baseImmediate = immediateResults
        spotlightEngine.search(parsedQuery: parsed, category: category) { [weak self] spotlightResults in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                var outlookCacheResults: [SearchItem] = []
                if category == .emails || parsed.inferredCategory == .emails || category == .all {
                    outlookCacheResults = self.outlookEngine.searchOutlookMessages(keyword: parsed.searchTerm, limit: 15)
                }

                var chatMatches: [SearchItem] = []
                if category == .all && !parsed.searchTerm.isEmpty {
                    chatMatches = self.chatAttachmentsIndexer.fetchRecentChatAttachments(limit: 10, keyword: parsed.searchTerm)
                }

                // Merge & deduplicate by file path / id
                var seen = Set<String>()
                var merged: [SearchItem] = []

                for item in (baseImmediate + spotlightResults + outlookCacheResults + chatMatches) {
                    let key = item.fileURL?.path ?? item.id
                    if !seen.contains(key) {
                        seen.insert(key)
                        merged.append(item)
                    }
                }

                // Apply Relevance Ranking Engine (title match + token overlap + recency + frecency)
                let ranked = self.rankingEngine.rank(items: merged, parsedQuery: parsed, targetCategory: category)

                self.results = ranked
                if self.selectedItem == nil || !ranked.contains(where: { $0.id == self.selectedItem?.id }) {
                    self.selectedItem = ranked.first
                }
                self.isSearching = false
            }
        }
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
}

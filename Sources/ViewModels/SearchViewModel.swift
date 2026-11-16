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

    private var cancellables = Set<AnyCancellable>()
    private let queryParser = QueryParser.shared
    private let downloadsTracker = DownloadsTracker.shared
    private let screenshotsTracker = ScreenshotsTracker.shared
    private let chatAttachmentsIndexer = ChatAttachmentsIndexer.shared
    private let spotlightEngine = SpotlightSearchEngine.shared
    private let outlookEngine = OutlookSearchEngine.shared

    public init() {
        setupBindings()
        loadInitialRecents()
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
        let recentDownloads = downloadsTracker.fetchRecentDownloads(limit: 25)
        let recentScreenshots = screenshotsTracker.fetchRecentScreenshots(limit: 15)
        let merged = (recentDownloads + recentScreenshots).sorted {
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

        // 1. If query is empty and category is all, load initial recents
        if parsed.rawQuery.isEmpty && category == .all {
            loadInitialRecents()
            return
        }

        self.isSearching = true

        // Fast path for Screenshots chip or token
        if category == .screenshots {
            let shots = screenshotsTracker.fetchRecentScreenshots(limit: 50, keyword: parsed.searchTerm)
            self.results = shots
            self.selectedItem = shots.first
            self.isSearching = false
            return
        }

        // Fast path for Chat & Attachments chip or token
        if category == .chatAttachments {
            let chatFiles = chatAttachmentsIndexer.fetchRecentChatAttachments(limit: 50, keyword: parsed.searchTerm)
            self.results = chatFiles
            self.selectedItem = chatFiles.first
            self.isSearching = false
            return
        }

        // Fast path for Downloads
        var immediateResults: [SearchItem] = []
        if category == .all || category == .downloads {
            let downloads = downloadsTracker.fetchRecentDownloads(limit: 50)
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
        }

        // Query Spotlight for deeper system search & Outlook messages
        let baseImmediate = immediateResults
        spotlightEngine.search(parsedQuery: parsed, category: category) { [weak self] spotlightResults in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                var outlookCacheResults: [SearchItem] = []
                if category == .emails || parsed.inferredCategory == .emails {
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

                self.results = merged
                if self.selectedItem == nil || !merged.contains(where: { $0.id == self.selectedItem?.id }) {
                    self.selectedItem = merged.first
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

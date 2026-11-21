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
    /// "Also showing results for …", "Indexing 12,400 files…" and similar one-line status.
    @Published public var statusNote: String? = nil
    /// Something that stops DadSearch from seeing part of the Mac (e.g. Full Disk Access missing).
    @Published public var healthIssue: String? = nil
    @AppStorage("com.saahil.DadSearch.includeHidden") public var includeHidden: Bool = true

    private var cancellables = Set<AnyCancellable>()
    private var generation = 0            // every new search invalidates older in-flight ones
    private let queryParser = QueryParser.shared
    private let universal = UniversalSearch.shared
    private let appLauncher = AppLauncherEngine.shared
    private let contactsEngine = ContactsSearchEngine.shared
    private let calendarEngine = CalendarSearchEngine.shared
    private let ranker = RelevanceRankingEngine.shared
    private let historyStore = SearchHistoryStore.shared

    public init() {
        setupBindings()
        refreshHistory()
        startEngines()
        loadInitialRecents()
    }

    public func refreshHistory() {
        self.recentQueries = historyStore.getRecentQueries(limit: 6)
    }

    private func setupBindings() {
        $rawQuery
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] q in self?.performSearch(query: q) }
            .store(in: &cancellables)

        $selectedCategory
            .dropFirst()
            .sink { [weak self] c in
                guard let self = self else { return }
                self.performSearch(query: self.rawQuery, forcedCategory: c)
            }
            .store(in: &cancellables)
    }

    // MARK: - Engines (index, watchers, connectors)

    private func startEngines() {
        _ = IndexStore.shared
        IndexCrawler.shared.onStatusChange = { [weak self] status in
            Task { @MainActor in self?.crawlStatusChanged(status) }
        }
        IndexCrawler.shared.startFullCrawl()

        let home = NSHomeDirectory()
        // Watcher 1: everything in the home folder except ~/Library (too noisy)
        let files = FSEventsWatcher(paths: [home], exclusions: [home + "/Library"]) { paths in
            IndexCrawler.shared.refresh(paths: paths)
        }
        files.start()
        // Watcher 2: the specific Library folders that matter
        var libPaths = CrawlRules.libraryAllowlist().map { $0.path }
        let outlookDir = OutlookLegacyConnector.watchedDirectory
        if FileManager.default.fileExists(atPath: outlookDir) { libPaths.append(outlookDir) }
        let mailRoots = AppleMailIndexer.mailRoots.map { $0.path }
        libPaths.append(contentsOf: mailRoots)
        let library = FSEventsWatcher(paths: libPaths) { paths in
            if paths.contains(where: { $0.hasPrefix(OutlookLegacyConnector.watchedDirectory) }) {
                OutlookLegacyConnector.shared.scheduleSync()
            }
            if paths.contains(where: { p in mailRoots.contains { p.hasPrefix($0) } }) {
                AppleMailIndexer.shared.scheduleSync()
            }
            IndexCrawler.shared.refresh(paths: paths)
        }
        library.start()
        self.watchers = [files, library]

        DispatchQueue.global(qos: .utility).async {
            OutlookLegacyConnector.shared.sync()
            AppleMailIndexer.shared.sync()
            Task { @MainActor in self.refreshHealth() }
        }
        refreshHealth()
    }

    private var watchers: [FSEventsWatcher] = []

    private func crawlStatusChanged(_ status: CrawlStatus) {
        if status.running {
            statusNote = "Building your search index… \(status.itemsSeen.formatted()) items so far (search already works)"
        } else if statusNote?.hasPrefix("Building") == true {
            statusNote = nil
            performSearch(query: rawQuery, forcedCategory: selectedCategory)
        }
        refreshHealth()
    }

    public func refreshHealth() {
        var issue: String? = nil
        if !Permissions.hasFullDiskAccess() {
            issue = "DadSearch can't see your email, messages and some folders yet. Tap to fix (Full Disk Access)."
        } else {
            let r = OutlookLegacyConnector.shared.lastReport
            if r.installed && r.profileFound && !r.databaseReadable {
                issue = "Outlook mail couldn't be read: \(r.note)"
            }
        }
        healthIssue = issue
    }

    public func fixHealthIssue() { Permissions.openFullDiskAccessSettings() }

    public func rescanEverything() {
        IndexCrawler.shared.startFullCrawl(force: true)
        DispatchQueue.global(qos: .utility).async {
            OutlookLegacyConnector.shared.sync()
            AppleMailIndexer.shared.sync()
        }
    }

    // MARK: - Actions

    public func handleItemOpened(_ item: SearchItem) {
        QuickActionService.shared.open(item: item)
    }

    // MARK: - Home screen

    public func loadInitialRecents() {
        performSearch(query: "")
    }

    // MARK: - Searching

    public func performSearch(query: String, forcedCategory: SearchCategoryFilter? = nil) {
        generation += 1
        let gen = generation
        let category = forcedCategory ?? selectedCategory
        let parsed = queryParser.parse(query: query)
        self.parsedQuery = parsed
        let hidden = includeHidden
        isSearching = true

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let universalRef = universal
            let launcherRef = appLauncher
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var items = universalRef.browse(includeHidden: hidden, limit: 30)
                if category == .apps { items = launcherRef.fetchApplications(limit: 30) }
                Task { @MainActor [weak self] in
                    guard let self = self, gen == self.generation else { return }
                    self.todayArrivals = items
                    self.apply(items: items, note: nil, select: true)
                    self.isSearching = false
                }
            }
            return
        }
        if trimmed.count >= 2 { historyStore.recordQuery(trimmed) }

        let wantsIndex = ![.apps, .contacts].contains(category)
        let engine = SpotlightSearchEngine.shared
        let universalRef = universal
        let launcherRef = appLauncher
        let contactsRef = contactsEngine
        let calendarRef = calendarEngine
        let rankerRef = ranker

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var extras: [SearchItem] = []
            let frec = SearchHistoryStore.shared.frecencySnapshot()
            let term = parsed.searchTerm

            if category == .apps || category == .all || parsed.wantsApps {
                extras += launcherRef.fetchApplications(keyword: term, limit: 8)
            }
            if category == .contacts || parsed.wantsContacts || parsed.wantsCalendar || (category == .all && !term.isEmpty) {
                extras += contactsRef.searchContacts(keyword: term, limit: category == .contacts ? 15 : 3)
                extras += calendarRef.searchEvents(keyword: term, limit: category == .contacts ? 15 : 3)
            }
            extras = extras.map { var i = $0; i.score = rankerRef.score(item: $0, bm25: 0, parsed: parsed, tier: 0, frecency: frec); return i }

            var outcome = SearchOutcome()
            if wantsIndex {
                outcome = universalRef.search(parsed: parsed, category: category, includeHidden: hidden)
            }
            let first = Self.merge(outcome.items, extras)
            let note = outcome.note
            Task { @MainActor [weak self] in
                guard let self = self, gen == self.generation else { return }
                self.apply(items: first, note: note, select: true)
                self.isSearching = wantsIndex   // Spotlight supplement may still add results
            }
            guard wantsIndex, category != .folders else {
                Task { @MainActor [weak self] in
                    guard let self = self, gen == self.generation else { return }
                    self.isSearching = false
                }
                return
            }

            // Supplement: Spotlight (email bodies, documents not yet extracted). Merged when it returns.
            engine.search(parsed: parsed) { [weak self] spot in
                let have = Set(first.compactMap { $0.fileURL?.path })
                let fresh = spot.filter { !have.contains($0.fileURL?.path ?? "") }.map { item -> SearchItem in
                    var i = item
                    i.score = rankerRef.score(item: item, bm25: 0, parsed: parsed, tier: 1, frecency: frec)
                    return i
                }
                Task { @MainActor [weak self] in
                    guard let self = self, gen == self.generation else { return }
                    if !fresh.isEmpty { self.apply(items: Self.merge(first, fresh), note: note, select: false) }
                    self.isSearching = false
                }
            }
        }
    }

    nonisolated private static func merge(_ a: [SearchItem], _ b: [SearchItem]) -> [SearchItem] {
        var seen = Set<String>()
        var out: [SearchItem] = []
        for i in (a + b).sorted(by: { $0.score != $1.score ? $0.score > $1.score : $0.modificationDate > $1.modificationDate }) {
            if seen.insert(i.id).inserted { out.append(i) }
        }
        return Array(out.prefix(100))
    }

    private func apply(items: [SearchItem], note: String?, select: Bool) {
        let previous = selectedItem?.id
        results = items
        if statusNote == nil || statusNote?.hasPrefix("Building") == false { statusNote = note }
        if !select, let p = previous, let keep = items.first(where: { $0.id == p }) {
            selectedItem = keep
        } else {
            selectedItem = items.first
        }
    }
}

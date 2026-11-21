import Foundation

public enum SearchCategoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "Everything"
    case downloads = "Downloads"
    case screenshots = "📸 Screenshots"
    case chatAttachments = "💬 Chat & Attachments"
    case emails = "Emails (Outlook & Mail)"
    case documents = "PDF & Docs"
    case folders = "📁 Folders"
    case apps = "📱 Apps"
    case contacts = "👤 Contacts & Events"
    case recent = "Recent (7 Days)"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .all: return "sparkle.magnifyingglass"
        case .downloads: return "arrow.down.circle"
        case .screenshots: return "camera.viewfinder"
        case .chatAttachments: return "bubble.left.and.bubble.right"
        case .emails: return "envelope"
        case .documents: return "doc.text"
        case .folders: return "folder"
        case .apps: return "app.fill"
        case .contacts: return "person.crop.circle"
        case .recent: return "clock.arrow.circlepath"
        }
    }
}

public struct ParsedQuery: Equatable, Sendable {
    public let rawQuery: String
    /// Individual search words (typo-corrected, stop words removed).
    public let cleanedTerms: [String]
    /// "Exact phrase" segments the user typed in quotes.
    public let phrases: [String]
    public let detectedFileExtensions: [String]
    /// Hard date filter from words like "today", "last week", "3 days ago".
    public let dateFilterRange: DateInterval?
    /// Soft hint from month names ("march 2025"): boosts ranking, never excludes.
    public let softDateRange: DateInterval?
    public let inferredCategory: SearchCategoryFilter?
    public let kindHints: [SearchItemKind]
    public let sourceHints: [String]
    public let downloadsOnly: Bool
    public let wantsApps: Bool
    public let wantsContacts: Bool
    public let wantsCalendar: Bool
    /// Pairs of (what the user typed, what we searched instead) for the "Showing results for…" note.
    public let corrections: [String]

    public init(
        rawQuery: String,
        cleanedTerms: [String],
        detectedFileExtensions: [String] = [],
        dateFilterRange: DateInterval? = nil,
        inferredCategory: SearchCategoryFilter? = nil,
        phrases: [String] = [],
        softDateRange: DateInterval? = nil,
        kindHints: [SearchItemKind] = [],
        sourceHints: [String] = [],
        downloadsOnly: Bool = false,
        wantsApps: Bool = false,
        wantsContacts: Bool = false,
        wantsCalendar: Bool = false,
        corrections: [String] = []
    ) {
        self.rawQuery = rawQuery
        self.cleanedTerms = cleanedTerms
        self.phrases = phrases
        self.detectedFileExtensions = detectedFileExtensions
        self.dateFilterRange = dateFilterRange
        self.softDateRange = softDateRange
        self.inferredCategory = inferredCategory
        self.kindHints = kindHints
        self.sourceHints = sourceHints
        self.downloadsOnly = downloadsOnly
        self.wantsApps = wantsApps
        self.wantsContacts = wantsContacts
        self.wantsCalendar = wantsCalendar
        self.corrections = corrections
    }

    /// Words + phrases: everything that must be matched as text.
    public var allTerms: [String] { cleanedTerms + phrases }

    public var searchTerm: String { allTerms.joined(separator: " ") }

    /// True when the user typed only type/date words ("pdf", "screenshots today") — we browse instead of match.
    public var isBrowseOnly: Bool { allTerms.isEmpty && !rawQuery.isEmpty }
}

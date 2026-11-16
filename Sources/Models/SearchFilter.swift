import Foundation

public enum SearchCategoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "Everything"
    case downloads = "Downloads"
    case screenshots = "📸 Screenshots"
    case chatAttachments = "💬 Chat & Attachments"
    case emails = "Outlook Emails"
    case documents = "PDF & Docs"
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
        case .recent: return "clock.arrow.circlepath"
        }
    }
}

public struct ParsedQuery: Equatable, Sendable {
    public let rawQuery: String
    public let cleanedTerms: [String]
    public let detectedFileExtensions: [String]
    public let dateFilterRange: DateInterval?
    public let inferredCategory: SearchCategoryFilter?

    public init(
        rawQuery: String,
        cleanedTerms: [String],
        detectedFileExtensions: [String] = [],
        dateFilterRange: DateInterval? = nil,
        inferredCategory: SearchCategoryFilter? = nil
    ) {
        self.rawQuery = rawQuery
        self.cleanedTerms = cleanedTerms
        self.detectedFileExtensions = detectedFileExtensions
        self.dateFilterRange = dateFilterRange
        self.inferredCategory = inferredCategory
    }

    public var searchTerm: String {
        cleanedTerms.joined(separator: " ")
    }
}

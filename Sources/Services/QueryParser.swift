import Foundation

public final class QueryParser: Sendable {
    public static let shared = QueryParser()

    public init() {}

    public func parse(query: String) -> ParsedQuery {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParsedQuery(rawQuery: "", cleanedTerms: [])
        }

        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var cleanedTerms: [String] = []
        var detectedExtensions: [String] = []
        var dateInterval: DateInterval? = nil
        var inferredCategory: SearchCategoryFilter? = nil

        let now = Date()
        let calendar = Calendar.current
        let lowercasedFull = trimmed.lowercased()

        // 1. Natural language date parsing
        if lowercasedFull.contains("today") {
            let start = calendar.startOfDay(for: now)
            dateInterval = DateInterval(start: start, end: now)
        } else if lowercasedFull.contains("yesterday") {
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: now) {
                let start = calendar.startOfDay(for: yesterday)
                let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: yesterday) ?? now
                dateInterval = DateInterval(start: start, end: end)
            }
        } else if lowercasedFull.contains("this week") {
            if let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) {
                dateInterval = DateInterval(start: startOfWeek, end: now)
            }
        } else if lowercasedFull.contains("last week") {
            if let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) {
                dateInterval = DateInterval(start: sevenDaysAgo, end: now)
            }
        } else if lowercasedFull.contains("this month") || lowercasedFull.contains("last month") {
            if let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) {
                dateInterval = DateInterval(start: thirtyDaysAgo, end: now)
            }
        }

        // 2. Token extraction & stop words removal
        let dateTokens: Set<String> = [
            "today", "yesterday", "this", "last", "week", "month", "from", "since", "in", "the", "dated"
        ]

        for word in words {
            let lower = word.lowercased()

            // Extension / type token
            if lower == "pdf" || lower == ".pdf" {
                detectedExtensions.append("pdf")
                inferredCategory = .documents
                continue
            }
            if lower == "doc" || lower == "docx" || lower == ".docx" || lower == "word" {
                detectedExtensions.append("docx")
                detectedExtensions.append("doc")
                inferredCategory = .documents
                continue
            }
            if lower == "excel" || lower == "sheet" || lower == "xlsx" || lower == "csv" {
                detectedExtensions.append("xlsx")
                detectedExtensions.append("csv")
                detectedExtensions.append("xls")
                inferredCategory = .documents
                continue
            }
            if lower == "mail" || lower == "email" || lower == "outlook" {
                inferredCategory = .emails
                continue
            }
            if lower == "download" || lower == "downloads" || lower == "downloaded" {
                inferredCategory = .downloads
                continue
            }
            if lower == "screenshot" || lower == "screenshots" || lower == "screengrab" || lower == "capture" || lower == "snapshot" {
                inferredCategory = .screenshots
                continue
            }
            if lower == "whatsapp" || lower == "telegram" || lower == "chat" || lower == "chats" || lower == "attachment" || lower == "attachments" || lower == "imessage" || lower == "message" || lower == "messages" {
                inferredCategory = .chatAttachments
                continue
            }

            if dateTokens.contains(lower) {
                continue
            }

            cleanedTerms.append(word)
        }

        return ParsedQuery(
            rawQuery: trimmed,
            cleanedTerms: cleanedTerms,
            detectedFileExtensions: detectedExtensions,
            dateFilterRange: dateInterval,
            inferredCategory: inferredCategory
        )
    }
}

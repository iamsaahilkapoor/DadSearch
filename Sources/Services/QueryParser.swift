import Foundation

public final class QueryParser: Sendable {
    public static let shared = QueryParser()

    public init() {}

    // Dictionary of common typos or vernacular words used by non-tech / older users
    private let commonMisspellings: [String: String] = [
        "recipt": "receipt",
        "reciept": "receipt",
        "receit": "receipt",
        "invoce": "invoice",
        "invioce": "invoice",
        "statment": "statement",
        "statmnt": "statement",
        "perscription": "prescription",
        "perscrip": "prescription",
        "apointment": "appointment",
        "apointmnt": "appointment",
        "apppointment": "appointment",
        "docter": "doctor",
        "docotr": "doctor",
        "screenhot": "screenshot",
        "screnshot": "screenshot",
        "whatspp": "whatsapp",
        "whatsap": "whatsapp",
        "telgram": "telegram",
        "telegrm": "telegram",
        "downlod": "download",
        "downlaod": "download",
        "calender": "calendar",
        "calander": "calendar"
    ]

    public func parse(query: String) -> ParsedQuery {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParsedQuery(rawQuery: "", cleanedTerms: [])
        }

        let rawWords = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
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

        for word in rawWords {
            var lower = word.lowercased()

            // Apply fuzzy / typo correction
            if let corrected = commonMisspellings[lower] {
                lower = corrected
            }

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
            if lower == "app" || lower == "apps" || lower == "application" || lower == "launch" || lower == "open" {
                inferredCategory = .apps
                continue
            }
            if lower == "contact" || lower == "contacts" || lower == "phone" || lower == "call" || lower == "appointment" || lower == "calendar" || lower == "event" || lower == "meeting" {
                inferredCategory = .contacts
                continue
            }

            if dateTokens.contains(lower) {
                continue
            }

            // If word was corrected from a typo, keep the corrected version
            cleanedTerms.append(lower)
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

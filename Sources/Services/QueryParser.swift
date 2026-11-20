import Foundation

public final class QueryParser: Sendable {
    public static let shared = QueryParser()

    private let dateDetector: NSDataDetector?

    public init() {
        self.dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    }

    // Common misspellings mapped to correct roots
    private let commonMisspellings: [String: String] = [
        "recipt": "receipt",
        "reciept": "receipt",
        "receit": "receipt",
        "invoce": "invoice",
        "invioce": "invoice",
        "statment": "statement",
        "statmnt": "statement",
        "perscription": "prescription",
        "apointment": "appointment",
        "apointmnt": "appointment",
        "docter": "doctor",
        "screenhot": "screenshot",
        "whatspp": "whatsapp",
        "telgram": "telegram",
        "downlod": "download",
        "calender": "calendar"
    ]

    public func parse(query: String) -> ParsedQuery {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParsedQuery(rawQuery: "", cleanedTerms: [])
        }

        var detectedDateInterval: DateInterval? = nil
        var textWithoutDates = trimmed

        // 1. Natural language date parsing using NSDataDetector ("yesterday", "last week", "in March", "last Tuesday")
        if let detector = dateDetector {
            let matches = detector.matches(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count))
            for match in matches {
                if let detectedDate = match.date {
                    let now = Date()
                    let calendar = Calendar.current
                    if match.duration > 0 {
                        detectedDateInterval = DateInterval(start: detectedDate, duration: match.duration)
                    } else if detectedDate <= now {
                        let start = calendar.startOfDay(for: detectedDate)
                        let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: detectedDate) ?? now
                        detectedDateInterval = DateInterval(start: start, end: end)
                    } else {
                        detectedDateInterval = DateInterval(start: now, end: detectedDate)
                    }

                    // Remove the detected date text from the search term
                    if let range = Range(match.range, in: textWithoutDates) {
                        textWithoutDates.removeSubrange(range)
                    }
                }
            }
        }

        // 2. Token extraction & typo correction
        let rawWords = textWithoutDates.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var cleanedTerms: [String] = []
        var detectedExtensions: [String] = []
        var inferredCategory: SearchCategoryFilter? = nil

        let lowercasedWords = rawWords.map { $0.lowercased() }
        let hasBillOrFinanceContext = lowercasedWords.contains { ["bill", "invoice", "statement", "receipt", "recharge", "tax"].contains($0) }

        for word in rawWords {
            var lower = word.lowercased()

            // Apply typo correction
            if let corrected = commonMisspellings[lower] {
                lower = corrected
            }

            // Extension / explicit format tokens
            if lower == "pdf" || lower == ".pdf" {
                detectedExtensions.append("pdf")
                inferredCategory = .documents
                continue
            }
            if lower == "docx" || lower == ".docx" || lower == "xlsx" || lower == ".xlsx" {
                detectedExtensions.append(lower.replacingOccurrences(of: ".", with: ""))
                inferredCategory = .documents
                continue
            }

            // Category hints (WITHOUT swallowing search terms!)
            if lower == "screenshot" || lower == "screenshots" {
                inferredCategory = .screenshots
                cleanedTerms.append(lower)
                continue
            }
            if lower == "download" || lower == "downloads" {
                inferredCategory = .downloads
                cleanedTerms.append(lower)
                continue
            }
            if lower == "mail" || lower == "email" || lower == "emails" || lower == "outlook" {
                inferredCategory = .emails
                cleanedTerms.append(lower)
                continue
            }
            if lower == "whatsapp" || lower == "telegram" || lower == "chat" {
                inferredCategory = .chatAttachments
                cleanedTerms.append(lower)
                continue
            }
            if lower == "launch" || lower == "app" || lower == "apps" {
                inferredCategory = .apps
                cleanedTerms.append(lower)
                continue
            }
            if lower == "call" || lower == "contact" || (lower == "phone" && !hasBillOrFinanceContext) {
                inferredCategory = .contacts
                cleanedTerms.append(lower)
                continue
            }

            // Normal search term
            cleanedTerms.append(lower)
        }

        return ParsedQuery(
            rawQuery: trimmed,
            cleanedTerms: cleanedTerms,
            detectedFileExtensions: detectedExtensions,
            dateFilterRange: detectedDateInterval,
            inferredCategory: inferredCategory
        )
    }
}

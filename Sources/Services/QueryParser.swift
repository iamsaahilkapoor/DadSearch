import Foundation

/// Turns what a person types into a structured query.
///
/// Design rules (each one fixes a bug in v1):
///  * Words are NEVER silently removed unless they are pure type/date/filler words.
///  * "phone bill", "meeting notes", "word list" keep all their words.
///  * Type words ("pdf", "email") become filters that the search can relax if they return nothing.
///  * Relative dates ("today", "last week") are hard filters; month names are only a ranking hint.
public final class QueryParser: Sendable {
    public static let shared = QueryParser()

    public init() {}

    public func parse(query: String, now: Date = Date(), calendar: Calendar = .current) -> ParsedQuery {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParsedQuery(rawQuery: "", cleanedTerms: [])
        }

        // 1. Quoted phrases: "tax invoice" stays together
        var working = trimmed
        var phrases: [String] = []
        if let regex = try? NSRegularExpression(pattern: "\"([^\"]+)\"|“([^”]+)”") {
            let ns = working as NSString
            let matches = regex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            for m in matches.reversed() {
                for g in 1...2 where m.range(at: g).location != NSNotFound {
                    let phrase = ns.substring(with: m.range(at: g)).trimmingCharacters(in: .whitespaces)
                    if !phrase.isEmpty { phrases.insert(Lexicon.normalize(phrase), at: 0) }
                }
                working = (working as NSString).replacingCharacters(in: m.range, with: " ")
            }
        }

        // 2. Dates
        let (afterDates, hardRange, softRange) = DateParser.extract(from: working, now: now, calendar: calendar)

        // 3. Tokens
        var terms: [String] = []
        var extensions: [String] = []
        var kindHints: [SearchItemKind] = []
        var sourceHints: [String] = []
        var downloadsOnly = false
        var wantsApps = false
        var wantsContacts = false
        var wantsCalendar = false
        var inferred: SearchCategoryFilter? = nil
        var corrections: [String] = []

        let rawWords = afterDates.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        for word in rawWords {
            var lower = Lexicon.normalize(word)
            if lower.isEmpty { continue }

            if let corrected = Lexicon.misspellings[lower] {
                corrections.append("\(lower)→\(corrected)")
                lower = corrected
            }
            if lower.hasPrefix("."), lower.count <= 6, Lexicon.extensionWords[String(lower.dropFirst())] != nil {
                lower = String(lower.dropFirst())
            }

            if Lexicon.stopwords.contains(lower) { continue }

            if let exts = Lexicon.extensionWords[lower] {
                for e in exts where !extensions.contains(e) { extensions.append(e) }
                inferred = inferred ?? .documents
                continue
            }
            if let kind = Lexicon.kindWords[lower] {
                if !kindHints.contains(kind) { kindHints.append(kind) }
                switch kind {
                case .email: inferred = inferred ?? .emails
                case .screenshot: inferred = inferred ?? .screenshots
                case .folder: inferred = inferred ?? .folders
                default: break
                }
                continue
            }
            if let sources = Lexicon.sourceWords[lower] {
                for s in sources where !sourceHints.contains(s) { sourceHints.append(s) }
                inferred = inferred ?? .chatAttachments
                continue
            }
            if Lexicon.downloadWords.contains(lower) {
                downloadsOnly = true
                inferred = inferred ?? .downloads
                continue
            }
            if Lexicon.appWords.contains(lower) {
                wantsApps = true
                inferred = inferred ?? .apps
                continue
            }
            if Lexicon.contactWords.contains(lower) {
                wantsContacts = true
                inferred = inferred ?? .contacts
                continue
            }
            if Lexicon.calendarWords.contains(lower) {
                wantsCalendar = true
                inferred = inferred ?? .contacts
                continue
            }
            // "phone", "call", "meeting", "message" are ordinary words: keep them as search terms.
            terms.append(lower)
        }

        return ParsedQuery(
            rawQuery: trimmed,
            cleanedTerms: terms,
            detectedFileExtensions: extensions,
            dateFilterRange: hardRange,
            inferredCategory: inferred,
            phrases: phrases,
            softDateRange: softRange,
            kindHints: kindHints,
            sourceHints: sourceHints,
            downloadsOnly: downloadsOnly,
            wantsApps: wantsApps,
            wantsContacts: wantsContacts,
            wantsCalendar: wantsCalendar,
            corrections: corrections
        )
    }
}

// MARK: - Dates

enum DateParser {
    private static let months = ["january", "february", "march", "april", "may", "june", "july",
                                 "august", "september", "october", "november", "december"]
    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    /// Returns (text with the hard-date words removed, hard range, soft range).
    static func extract(from text: String, now: Date, calendar: Calendar) -> (String, DateInterval?, DateInterval?) {
        var remaining = text
        var hard: DateInterval? = nil
        var soft: DateInterval? = nil
        let startToday = calendar.startOfDay(for: now)
        let endToday = calendar.date(byAdding: .day, value: 1, to: startToday)?.addingTimeInterval(-1) ?? now

        func strip(_ pattern: String) -> NSTextCheckingResult? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            let ns = remaining as NSString
            guard let m = regex.firstMatch(in: remaining, range: NSRange(location: 0, length: ns.length)) else { return nil }
            let result = m
            remaining = ns.replacingCharacters(in: m.range, with: " ")
            return result
        }
        func group(_ m: NSTextCheckingResult, _ i: Int, in original: String) -> String {
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : (original as NSString).substring(with: r).lowercased()
        }
        func unitStart(_ unit: String, count: Int) -> Date? {
            switch unit {
            case "day": return calendar.date(byAdding: .day, value: -count, to: startToday)
            case "week": return calendar.date(byAdding: .day, value: -7 * count, to: startToday)
            case "month": return calendar.date(byAdding: .month, value: -count, to: startToday)
            case "year": return calendar.date(byAdding: .year, value: -count, to: startToday)
            default: return nil
            }
        }

        // today / yesterday
        if strip("\\btoday\\b") != nil {
            hard = DateInterval(start: startToday, end: endToday)
        } else if strip("\\byesterday\\b") != nil, let y = calendar.date(byAdding: .day, value: -1, to: startToday) {
            hard = DateInterval(start: y, end: startToday.addingTimeInterval(-1))
        }
        // last 10 days / past 2 weeks
        else if let snapshot = Optional(remaining), let m = strip("\\b(?:last|past)\\s+(\\d+)\\s+(day|week|month|year)s?\\b"),
                let n = Int(group(m, 1, in: snapshot)), let start = unitStart(group(m, 2, in: snapshot), count: n) {
            hard = DateInterval(start: start, end: endToday)
        }
        // 3 days ago
        else if let snapshot = Optional(remaining), let m = strip("\\b(\\d+)\\s+(day|week|month|year)s?\\s+ago\\b"),
                let n = Int(group(m, 1, in: snapshot)) {
            let unit = group(m, 2, in: snapshot)
            if let from = unitStart(unit, count: n + 1), let to = unitStart(unit, count: max(0, n - 1)) {
                hard = DateInterval(start: from, end: min(endToday, to.addingTimeInterval(86_399)))
            }
        }
        // this week / this month / this year  (strict)  |  last week / last month / last year (lenient: through today)
        else if let snapshot = Optional(remaining), let m = strip("\\b(this|last|past)\\s+(week|month|year)\\b") {
            let which = group(m, 1, in: snapshot)
            let unit = group(m, 2, in: snapshot)
            let comp: Calendar.Component = unit == "week" ? .weekOfYear : (unit == "month" ? .month : .year)
            if let thisStart = calendar.dateInterval(of: comp, for: now)?.start {
                if which == "this" {
                    hard = DateInterval(start: thisStart, end: endToday)
                } else if let prev = calendar.date(byAdding: comp, value: -1, to: thisStart) {
                    hard = DateInterval(start: prev, end: endToday)
                }
            }
        }
        // last monday / on friday
        else if let snapshot = Optional(remaining), let m = strip("\\b(?:last\\s+|on\\s+)?(" + weekdays.joined(separator: "|") + ")\\b") {
            let name = group(m, 1, in: snapshot)
            if let idx = weekdays.firstIndex(of: name) {
                var comps = DateComponents()
                comps.weekday = idx + 1
                if let day = calendar.nextDate(after: now, matching: comps, matchingPolicy: .nextTime, direction: .backward) {
                    let start = calendar.startOfDay(for: day)
                    hard = DateInterval(start: start, end: start.addingTimeInterval(86_399))
                }
            }
        }

        // Month names: ranking hint only. Words stay in the query because they often appear in file names.
        let lower = remaining.lowercased()
        for (idx, month) in months.enumerated() where lower.range(of: "\\b\(month)\\b", options: .regularExpression) != nil {
            var year = calendar.component(.year, from: now)
            if let r = lower.range(of: "\\b(19|20)\\d{2}\\b", options: .regularExpression), let y = Int(lower[r]) { year = y }
            else if idx + 1 > calendar.component(.month, from: now) { year -= 1 }
            if let start = calendar.date(from: DateComponents(year: year, month: idx + 1, day: 1)),
               let end = calendar.date(byAdding: .month, value: 1, to: start) {
                soft = DateInterval(start: start, end: end)
            }
            break
        }

        return (remaining, hard, soft)
    }
}

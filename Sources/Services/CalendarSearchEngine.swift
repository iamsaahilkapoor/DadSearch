import Foundation
import EventKit

public final class CalendarSearchEngine: @unchecked Sendable {
    public static let shared = CalendarSearchEngine()

    private let eventStore = EKEventStore()

    private init() {}

    public func searchEvents(keyword: String, limit: Int = 10) -> [SearchItem] {
        guard !keyword.isEmpty else { return [] }

        if #available(macOS 14.0, *) {
            let status = EKEventStore.authorizationStatus(for: .event)
            guard status == .fullAccess else { return [] }
        } else {
            let status = EKEventStore.authorizationStatus(for: .event)
            guard status == .authorized else { return [] }
        }

        let now = Date()
        let past = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        let future = Calendar.current.date(byAdding: .day, value: 60, to: now) ?? now

        let predicate = eventStore.predicateForEvents(withStart: past, end: future, calendars: nil)
        let events = eventStore.events(matching: predicate)

        let lower = keyword.lowercased()
        let matches = events.filter { event in
            let titleMatch = event.title?.lowercased().contains(lower) == true
            let locMatch = event.location?.lowercased().contains(lower) == true
            let notesMatch = event.notes?.lowercased().contains(lower) == true
            return titleMatch || locMatch || notesMatch
        }

        var results: [SearchItem] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        for event in matches.prefix(limit) {
            let title = event.title ?? "Calendar Event"
            var details: [String] = []

            if let start = event.startDate {
                details.append(dateFormatter.string(from: start))
            }
            if let location = event.location, !location.isEmpty {
                details.append(location)
            }

            let subtitle = details.joined(separator: " • ")

            let item = SearchItem(
                id: "event:" + (event.eventIdentifier ?? UUID().uuidString),
                title: title,
                subtitle: subtitle.isEmpty ? "Calendar" : subtitle,
                fileURL: nil,
                kind: .calendarEvent,
                modificationDate: event.startDate ?? Date(),
                addedDate: event.creationDate,
                fileSize: nil,
                authorOrSender: event.calendar?.title,
                isOutlookItem: false,
                matchSnippet: event.location
            )
            results.append(item)
        }

        return results
    }
}

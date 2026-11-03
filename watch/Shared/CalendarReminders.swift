import Foundation
import UserNotifications

// Watch-side reminders for calendar events (docs/PROTOCOL.md).
// Selection logic is separated (pure, testable) from scheduling.
enum CalendarReminders {
    static let maxReminders = 50
    static let prefix = "cal."
    static let threadId = "opi.calendar"

    struct Fire: Equatable {
        let id: String      // "cal.<k>.<rm>"
        let event: CalEvent
        let rm: Int
        let date: Date
    }

    // Reminder time for one event/reminder pair. All-day events are stored at UTC
    // midnight; reminders fire at local midnight of that UTC calendar date minus rm.
    static func fireDate(for event: CalEvent, rm: Int, timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        if event.ad {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            let day = utc.startOfDay(for: event.startDate)
            // Interpret that UTC calendar date in the local timezone.
            let comps = utc.dateComponents([.year, .month, .day], from: day)
            calendar.timeZone = timeZone
            guard let localMidnight = calendar.date(from: comps) else { return nil }
            return localMidnight.addingTimeInterval(-TimeInterval(rm) * 60)
        }
        calendar.timeZone = timeZone
        return event.startDate.addingTimeInterval(-TimeInterval(rm) * 60)
    }

    // Up to `limit` earliest future fires across all events, sorted by date.
    static func select(from events: [CalEvent], now: Date, limit: Int = maxReminders,
                       timeZone: TimeZone = .current) -> [Fire] {
        var fires: [Fire] = []
        for event in events {
            for rm in event.rm.sorted() {
                guard let date = fireDate(for: event, rm: rm, timeZone: timeZone), date > now else { continue }
                fires.append(Fire(id: "\(prefix)\(event.k).\(rm)", event: event, rm: rm, date: date))
            }
        }
        return Array(fires.sorted { $0.date < $1.date }.prefix(limit))
    }

    // Replace all pending "cal." requests with reminders for the new calendar.
    static func reschedule(events: [CalEvent], now: Date = Date(), timeZone: TimeZone = .current) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let stale = pending.filter { $0.identifier.hasPrefix(prefix) }.map { $0.identifier }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        for fire in select(from: events, now: now, timeZone: timeZone) {
            let content = UNMutableNotificationContent()
            content.title = fire.event.t.isEmpty ? "Event" : fire.event.t
            var body = fire.event.ad
                ? "All day"
                : Self.timeRange(event: fire.event, timeZone: timeZone)
            if !fire.event.loc.isEmpty { body += " · \(fire.event.loc)" }
            content.body = body
            content.threadIdentifier = threadId
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, fire.date.timeIntervalSince(now)), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: fire.id, content: content, trigger: trigger))
        }
    }

    static func clear() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.filter { $0.identifier.hasPrefix(prefix) }.map { $0.identifier }
        if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
    }

    private static func timeRange(event: CalEvent, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate("jmm")
        return "\(f.string(from: event.startDate))–\(f.string(from: event.endDate))"
    }
}

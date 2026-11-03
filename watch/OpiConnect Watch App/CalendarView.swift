import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var model: AppModel

    // Groups events by (local) day; all-day events group under their UTC calendar date.
    private var groups: [(String, [CalEvent])] {
        let events = model.calendar?.events ?? []
        let cal = Calendar.current
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var order: [Date] = []
        var map: [Date: [CalEvent]] = [:]
        for e in events {
            let day = (e.ad ? utc : cal).startOfDay(for: e.startDate)
            if map[day] == nil { order.append(day) }
            map[day, default: []].append(e)
        }
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("EEEE d MMM")
        return order.sorted().map { day in
            let title: String
            if cal.isDateInToday(day) { title = "Today" }
            else if cal.isDateInTomorrow(day) { title = "Tomorrow" }
            else { title = fmt.string(from: day) }
            return (title, map[day] ?? [])
        }
    }

    var body: some View {
        Group {
            if let cache = model.calendar, !cache.events.isEmpty {
                List {
                    ForEach(groups, id: \.0) { title, events in
                        Section(header: Text(title)) {
                            ForEach(events) { event in
                                NavigationLink(value: event.k) {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(color(for: event))
                                            .frame(width: 8, height: 8)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(event.t.isEmpty ? "(No title)" : event.t)
                                                .font(.callout).lineLimit(1)
                                            Text(event.ad ? "All day" : timeRange(event))
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if let updated = model.calendar?.updatedAt, updated > .distantPast {
                        Text("Updated \(updated, style: .relative) ago")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Text("No upcoming events")
                        .foregroundStyle(.secondary)
                    Text("Grant OpiConnect calendar access on your phone")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .navigationTitle("Calendar")
        .navigationDestination(for: String.self) { key in
            if let event = model.calendar?.events.first(where: { $0.k == key }) {
                EventDetailView(event: event)
            }
        }
    }

    private func color(for event: CalEvent) -> Color {
        let argb = UInt64(bitPattern: event.col)
        let r = Double((argb >> 16) & 0xff) / 255
        let g = Double((argb >> 8) & 0xff) / 255
        let b = Double(argb & 0xff) / 255
        return Color(red: r, green: g, blue: b)
    }

    private func timeRange(_ event: CalEvent) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jmm")
        return "\(f.string(from: event.startDate))–\(f.string(from: event.endDate))"
    }
}

struct EventDetailView: View {
    let event: CalEvent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(event.t.isEmpty ? "(No title)" : event.t).font(.headline)
                Text(event.ad ? "All day" : "\(dateStr(event.startDate)) \(timeStr(event.startDate))–\(timeStr(event.endDate))")
                    .font(.caption).foregroundStyle(.secondary)
                if !event.loc.isEmpty {
                    Label(event.loc, systemImage: "mappin").font(.caption)
                }
                if !event.n.isEmpty {
                    Text(event.n).font(.caption)
                }
                if !event.cal.isEmpty {
                    Text(event.cal).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Event")
    }

    private func dateStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f.string(from: d)
    }

    private func timeStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: d)
    }
}

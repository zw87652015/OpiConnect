import WidgetKit
import SwiftUI

// Complications for OpiConnect (docs/PROTOCOL.md widget kinds). All data comes from
// SharedStore files in the app group — no BLE or keychain access needed.

@main
struct OpiConnectWidgets: WidgetBundle {
    var body: some Widget {
        BatteryWidget()
        NextEventWidget()
        FindPhoneWidget()
        MusicWidget()
    }
}

private let store = SharedStore()

// MARK: - Battery

struct BatteryEntry: TimelineEntry {
    let date: Date
    let status: PhoneStatus?
}

struct BatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: Date(), status: PhoneStatus(bt: 76, bc: false, at: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        completion(BatteryEntry(date: Date(), status: store.status()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        let now = Date()
        let entry = BatteryEntry(date: now, status: store.status())
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(3600))))
    }
}

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "opi.battery", provider: BatteryProvider()) { entry in
            BatteryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "opiconnect://home"))
        }
        .configurationDisplayName("Phone battery")
        .description("Battery level of the paired phone.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

private struct BatteryView: View {
    @Environment(\.widgetFamily) var family
    let entry: BatteryEntry

    private var stale: Bool {
        guard let at = entry.status?.at else { return false }
        return Date().timeIntervalSince(at) > 6 * 3600
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(max(0, entry.status?.bt ?? 0)) / 100) {
                    Image(systemName: "iphone")
                } currentValueLabel: {
                    if let s = entry.status {
                        HStack(spacing: 1) {
                            Text("\(s.bt)").font(.system(.body, design: .rounded))
                            if s.bc { Image(systemName: "bolt.fill").font(.system(size: 8)) }
                        }
                    } else {
                        Text("—")
                    }
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryInline:
                if let s = entry.status {
                    Text("Phone \(s.bt)%\(s.bc ? " ⚡" : "")")
                } else {
                    Text("Phone —")
                }
            case .accessoryCorner:
                if let s = entry.status {
                    Text("\(s.bt)%").widgetLabel { Image(systemName: s.bc ? "bolt.fill" : "iphone") }
                } else {
                    Image(systemName: "iphone").widgetLabel { Text("Phone") }
                }
            default: // rectangular
                if let s = entry.status {
                    VStack(alignment: .leading) {
                        Text("Phone \(s.bt)%\(s.bc ? " · charging" : "")").font(.headline)
                        Text("Updated \(s.at, style: .relative) ago").font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Phone battery —")
                }
            }
        }
        .opacity(stale ? 0.5 : 1)
    }
}

// MARK: - Next event

struct EventEntry: TimelineEntry {
    let date: Date
    let event: CalEvent?
}

struct NextEventProvider: TimelineProvider {
    private func nextEvent(after now: Date) -> CalEvent? {
        store.calendar()?.events.first { $0.ad ? $0.startDate > now : $0.endDate > now }
    }

    func placeholder(in context: Context) -> EventEntry {
        EventEntry(date: Date(), event: CalEvent(k: "x", t: "Meeting", s: 0, e: 0, ad: false))
    }

    func getSnapshot(in context: Context, completion: @escaping (EventEntry) -> Void) {
        completion(EventEntry(date: Date(), event: nextEvent(after: Date())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EventEntry>) -> Void) {
        let now = Date()
        var entries = [EventEntry(date: now, event: nextEvent(after: now))]
        // Refresh as each of the next 10 events ends.
        for event in (store.calendar()?.events ?? []).filter({ $0.endDate > now }).prefix(10) {
            entries.append(EventEntry(date: event.endDate, event: nextEvent(after: event.endDate)))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct NextEventWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "opi.nextevent", provider: NextEventProvider()) { entry in
            NextEventView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "opiconnect://calendar"))
        }
        .configurationDisplayName("Next event")
        .description("Next event from the phone calendar.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

private struct NextEventView: View {
    @Environment(\.widgetFamily) var family
    let entry: EventEntry

    private var timeString: String {
        guard let e = entry.event else { return "" }
        let f = DateFormatter()
        if e.ad {
            f.setLocalizedDateFormatFromTemplate("d MMM")
        } else {
            f.setLocalizedDateFormatFromTemplate("jmm")
        }
        return f.string(from: e.startDate)
    }

    var body: some View {
        if let e = entry.event {
            switch family {
            case .accessoryInline:
                Text("\(timeString) \(e.t)")
            default:
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.t.isEmpty ? "(No title)" : e.t).font(.headline).lineLimit(1)
                    Text(e.ad ? "\(timeString) · All day" : timeString)
                        .font(.caption2).foregroundStyle(.secondary)
                    if !e.loc.isEmpty {
                        Text(e.loc).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        } else {
            Text("No upcoming events")
        }
    }
}

// MARK: - Find phone / Music

struct StaticProvider: TimelineProvider {
    let makeEntry: (Date) -> SimpleEntry
    func placeholder(in context: Context) -> SimpleEntry { makeEntry(Date()) }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(makeEntry(Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [makeEntry(Date())], policy: .never))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let media: MediaSnapshot?
}

struct FindPhoneWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "opi.findphone", provider: StaticProvider { SimpleEntry(date: $0, media: nil) }) { _ in
            Image(systemName: "iphone.radiowaves.left.and.right")
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "opiconnect://findphone"))
        }
        .configurationDisplayName("Find Phone")
        .description("Ring your phone from the watch.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct MusicWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "opi.music", provider: StaticProvider { SimpleEntry(date: $0, media: store.media()) }) { entry in
            Group {
                if let m = entry.media, m.on, !m.t.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        Image(systemName: "music.note")
                        Text(m.t).font(.caption).lineLimit(1)
                        if !m.ar.isEmpty { Text(m.ar).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    }
                } else {
                    Image(systemName: "music.note")
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(URL(string: "opiconnect://music"))
        }
        .configurationDisplayName("Music")
        .description("Control music on your phone.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

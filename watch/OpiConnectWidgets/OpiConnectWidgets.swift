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

// The app ships English-only resources, so Bundle/Locale.current would stay English;
// follow the watch's preferred language directly for widget text and date formats.
private let preferredLanguage = Locale.preferredLanguages.first ?? "en"
private let widgetLocale = Locale(identifier: preferredLanguage)
private enum UILang { case en, zhHans, zhHant }
private let uiLang: UILang = {
    guard preferredLanguage.hasPrefix("zh") else { return .en }
    let traditional = ["Hant", "TW", "HK", "MO"].contains { preferredLanguage.contains($0) }
    return traditional ? .zhHant : .zhHans
}()

// English, Simplified Chinese, Traditional Chinese (defaults to Simplified).
private func L(_ en: String, _ hans: String, _ hant: String? = nil) -> String {
    switch uiLang {
    case .en: return en
    case .zhHans: return hans
    case .zhHant: return hant ?? hans
    }
}

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
        .configurationDisplayName(Text(L("Phone battery", "手机电量", "手機電量")))
        .description(Text(L("Battery level of the paired phone.", "已配对手机的电量。", "已配對手機的電量。")))
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
                    Text(verbatim: "\(L("Phone", "手机", "手機")) \(s.bt)%\(s.bc ? " ⚡" : "")")
                } else {
                    Text(verbatim: "\(L("Phone", "手机", "手機")) —")
                }
            case .accessoryCorner:
                if let s = entry.status {
                    Text("\(s.bt)%").widgetLabel { Image(systemName: s.bc ? "bolt.fill" : "iphone") }
                } else {
                    Image(systemName: "iphone").widgetLabel { Text(L("Phone", "手机", "手機")) }
                }
            default: // rectangular
                if let s = entry.status {
                    VStack(alignment: .leading) {
                        Text(verbatim: "\(L("Phone", "手机", "手機")) \(s.bt)%\(s.bc ? L(" · charging", " · 充电中", " · 充電中") : "")")
                            .font(.headline)
                        Group {
                            if uiLang == .en { Text("Updated \(s.at, style: .relative) ago") }
                            else { Text("\(s.at, style: .relative)前更新") }
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text(L("Phone battery —", "手机电量 —", "手機電量 —"))
                }
            }
        }
        .opacity(stale ? 0.5 : 1)
        .environment(\.locale, widgetLocale)
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
        var dates: [Date] = []
        for event in (store.calendar()?.events ?? []).filter({ $0.endDate > now }).prefix(10) {
            dates.append(event.endDate)
            if !event.ad, event.startDate > now { dates.append(event.startDate) } // "Now" label
        }
        // Also at the next two midnights, so "Tomorrow" becomes today's time.
        var midnight = Calendar.current.startOfDay(for: now)
        for _ in 0..<2 {
            midnight = Calendar.current.date(byAdding: .day, value: 1, to: midnight)!
            dates.append(midnight)
        }
        for date in Set(dates).sorted() {
            entries.append(EventEntry(date: date, event: nextEvent(after: date)))
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
        .configurationDisplayName(Text(L("Next event", "下一个日程", "下一個行程")))
        .description(Text(L("Next event from the phone calendar.", "手机日历中的下一个日程。", "手機日曆中的下一個行程。")))
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

private struct NextEventView: View {
    @Environment(\.widgetFamily) var family
    let entry: EventEntry

    // "14:00" today, "Tomorrow 14:00", "Fri 14:00" within a week, else "8 Nov 14:00".
    // Relative to the entry date so each timeline entry renders its own day label.
    private var timeString: String {
        guard let e = entry.event else { return "" }
        var cal = Calendar.current
        let f = DateFormatter()
        f.locale = widgetLocale
        if e.ad {
            // All-day events are stored at UTC midnight of their date.
            cal.timeZone = TimeZone(identifier: "UTC")!
            f.timeZone = cal.timeZone
        }
        let today = Calendar.current.dateComponents([.year, .month, .day], from: entry.date)
        let eventDay = cal.dateComponents([.year, .month, .day], from: e.startDate)
        let days = Calendar.current.dateComponents([.day],
            from: Calendar.current.date(from: today)!, to: Calendar.current.date(from: eventDay)!).day ?? 0
        let started = !e.ad && e.startDate <= entry.date
        let day: String
        switch days {
        case ...0: day = started ? "" : (e.ad ? L("Today", "今天") : "")
        case 1: day = L("Tomorrow", "明天")
        case 2...6: f.setLocalizedDateFormatFromTemplate("EEE"); day = f.string(from: e.startDate)
        default: f.setLocalizedDateFormatFromTemplate("d MMM"); day = f.string(from: e.startDate)
        }
        if e.ad { return day }
        f.setLocalizedDateFormatFromTemplate("jmm")
        let time = f.string(from: e.startDate)
        if started { return L("Now · until \(f.string(from: e.endDate))", "进行中 · 至\(f.string(from: e.endDate))", "進行中 · 至\(f.string(from: e.endDate))") }
        return day.isEmpty ? time : "\(day) \(time)"
    }

    var body: some View {
        if let e = entry.event {
            switch family {
            case .accessoryInline:
                Text(verbatim: "\(timeString) \(e.t)")
            default:
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.t.isEmpty ? L("(No title)", "（无标题）", "（無標題）") : e.t).font(.headline).lineLimit(1)
                    Text(e.ad ? "\(timeString) · \(L("All day", "全天"))" : timeString)
                        .lineLimit(1)
                        .font(.caption2).foregroundStyle(.secondary)
                    if !e.loc.isEmpty {
                        Text(e.loc).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        } else {
            Text(L("No upcoming events", "暂无日程", "暫無行程"))
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
        .configurationDisplayName(Text(L("Find Phone", "查找手机", "尋找手機")))
        .description(Text(L("Ring your phone from the watch.", "从手表让手机响铃。", "從手錶讓手機響鈴。")))
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
        .configurationDisplayName(Text(L("Music", "音乐", "音樂")))
        .description(Text(L("Control music on your phone.", "控制手机上的音乐。", "控制手機上的音樂。")))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

// JSON files in the app-group container, read by app, NSE and widgets.
// The base directory is injectable so tests can use a temp directory.
struct SharedStore {
    enum Kind: String, CaseIterable {
        case status = "phone_status.json"
        case calendar = "calendar.json"
        case media = "media.json"

        var widgetKinds: [String] {
            switch self {
            case .status: return ["opi.battery"]
            case .calendar: return ["opi.nextevent"]
            case .media: return ["opi.music"]
            }
        }
    }

    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            self.directory = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: PairingKeys.appGroup)
                ?? FileManager.default.temporaryDirectory
        }
    }

    private func url(_ kind: Kind) -> URL { directory.appendingPathComponent(kind.rawValue) }

    func read<T: Decodable>(_ kind: Kind, as type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: url(kind)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    func write<T: Encodable>(_ kind: Kind, _ value: T) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (try? data.write(to: url(kind), options: .atomic)) != nil
    }

    // Convenience accessors used across the codebase.
    func status() -> PhoneStatus? { read(.status, as: PhoneStatus.self) }
    func saveStatus(_ s: PhoneStatus) { writeAndReload(.status, s) }
    func calendar() -> CalendarCache? { read(.calendar, as: CalendarCache.self) }
    func saveCalendar(_ c: CalendarCache) { writeAndReload(.calendar, c) }
    func media() -> MediaSnapshot? { read(.media, as: MediaSnapshot.self) }
    func saveMedia(_ m: MediaSnapshot) { writeAndReload(.media, m) }

    func remove(_ kind: Kind) {
        try? FileManager.default.removeItem(at: url(kind))
        #if canImport(WidgetKit)
        for name in kind.widgetKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: name)
        }
        #endif
    }

    private func writeAndReload<T: Encodable>(_ kind: Kind, _ value: T) {
        guard write(kind, value) else { return }
        #if canImport(WidgetKit)
        for name in kind.widgetKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: name)
        }
        #endif
    }
}

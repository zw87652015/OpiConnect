import Foundation
import UserNotifications
import WatchKit

struct NotifItem: Identifiable, Equatable {
    var id: String { payload.i }
    let payload: NotifPayload
    var date: Date { Date(timeIntervalSince1970: TimeInterval(payload.w) / 1000) }
}

enum SendState {
    case idle, sending, sent, queued
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var items: [NotifItem] = []
    @Published var paired = UserDefaults.appGroup.bool(forKey: "opi.paired")
    @Published var relayRegistered = false
    @Published var sendState: SendState = .idle
    @Published var phoneStatus: PhoneStatus?
    @Published var media: MediaSnapshot?
    @Published var ringing = false
    @Published var calendar: CalendarCache?
    @Published var path: [Route] = []

    let store = SharedStore()

    // Typed navigation path for HomeView (deep links + notification detail).
    enum Route: Hashable {
        case detail(id: String)
        case findphone
        case music
        case calendar
    }

    private init() {
        phoneStatus = store.status()
        media = store.media()
        calendar = store.calendar()
    }

    // Deep links: opiconnect://findphone | music | calendar | home
    func open(url: URL) {
        guard url.scheme == "opiconnect" else { return }
        switch url.host {
        case "findphone": path = [.findphone]
        case "music": path = [.music]
        case "calendar": path = [.calendar]
        case "home": path = []
        default: break
        }
    }

    func openNotification(id: String) {
        path = [.detail(id: id)]
    }

    func insert(_ payload: NotifPayload) {
        items.removeAll { $0.id == payload.i }
        items.insert(NotifItem(payload: payload), at: 0)
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
    }

    func sync(ids: Set<String>) {
        items.removeAll { !ids.contains($0.id) }
    }

    // Rebuild the list from delivered notifications (parses userInfo["opi"]).
    func reload() {
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            let items = notifications.compactMap { n -> NotifItem? in
                guard let dict = n.request.content.userInfo["opi"] as? [String: Any],
                      let payload = NotifPayload(jsonObject: dict) else { return nil }
                return NotifItem(payload: payload)
            }
            .sorted { $0.payload.w > $1.payload.w }
            Task { @MainActor in
                self.items = items
            }
        }
    }

    func updateStatus(bt: Int, bc: Bool) {
        let s = PhoneStatus(bt: bt, bc: bc, at: Date())
        phoneStatus = s
        store.saveStatus(s)
    }

    func unpair() {
        // Unregister with the OLD credentials before the key is reset.
        let oldPairId = PairingKeys.shared.pairId
        let oldSecret = PairingKeys.shared.secret
        Task { try? await RelayClient.unregister(pairId: oldPairId, secret: oldSecret) }
        UserDefaults.appGroup.set(false, forKey: "opi.paired")
        UserDefaults.appGroup.removeObject(forKey: "opi.registered")
        PendingQueue.shared.clear()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        PhoneLink.shared.disconnect()
        PairingKeys.shared.reset()
        paired = false
        relayRegistered = false
        items = []
        phoneStatus = nil
        media = nil
        ringing = false
        calendar = nil
        for kind in SharedStore.Kind.allCases { store.remove(kind) }
        Task { await CalendarReminders.clear() }
        // The new pairId needs a fresh relay registration, and the pairing
        // screen should resume scanning for the phone.
        WKApplication.shared().registerForRemoteNotifications()
        PhoneLink.shared.start(state: "active")
    }
}

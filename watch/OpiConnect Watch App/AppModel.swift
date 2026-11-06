import Foundation
import StoreKit
import UserNotifications
import WidgetKit

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
    @Published var subscribed = Subscription.isActive()
    @Published var path: [Route] = []

    let store = SharedStore()

    // Typed navigation path for HomeView (deep links + notification detail).
    enum Route: Hashable {
        case detail(id: String)
        case findphone
        case music
        case calendar
        case settings
    }

    private init() {
        phoneStatus = store.status()
        media = store.media()
        calendar = store.calendar()
        if DemoMode.isActive { DemoMode.apply(to: self) }
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

    // Refresh the cached entitlement and update the UI. On change, widgets are
    // reloaded; losing the subscription also drops scheduled calendar reminders.
    func refreshSubscription() async {
        guard !DemoMode.isActive else { return }
        let expiry = await Subscription.refresh()
        let active = Subscription.isActive(expiry: expiry)
        guard active != subscribed else { return }
        subscribed = active
        WidgetCenter.shared.reloadAllTimelines()
        if !active { await CalendarReminders.clear() }
    }

    // Called once at launch: refreshes the cache and finishes transaction updates.
    func startSubscriptionUpdates() {
        guard !DemoMode.isActive, subscriptionTask == nil else { return }
        subscriptionTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refreshSubscription()
            }
        }
        Task { await refreshSubscription() }
    }

    private var subscriptionTask: Task<Void, Never>?

    func markPaired() {
        guard !paired else { return }
        UserDefaults.appGroup.set(true, forKey: "opi.paired")
        paired = true
        RelayRegistration.shared.retryNow()
    }

    func insert(_ payload: NotifPayload) {
        items.removeAll { $0.id == payload.i }
        items.insert(NotifItem(payload: payload), at: 0)
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
    }

    func dismiss(ids: [String]) {
        for id in ids { PendingQueue.shared.enqueue(.dismiss(id: id)) }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        items.removeAll { ids.contains($0.id) }
        PhoneLink.shared.flush()
    }

    func dismissAll() {
        dismiss(ids: items.map(\.id))
    }

    func sync(ids: Set<String>) {
        items.removeAll { !ids.contains($0.id) }
    }

    // Rebuild the list from delivered notifications (parses userInfo["opi"]).
    func reload() {
        guard !DemoMode.isActive else { return }
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            let items = notifications.compactMap { n -> NotifItem? in
                guard let dict = n.request.content.userInfo["opi"] as? [String: Any],
                      let payload = NotifPayload(jsonObject: dict) else { return nil }
                return NotifItem(payload: payload)
            }
            Task { @MainActor in
                var items = items
                if case .detail(let id) = self.path.last,
                   !items.contains(where: { $0.id == id }),
                   let current = self.items.first(where: { $0.id == id }) {
                    items.append(current)
                }
                self.items = items.sorted { $0.payload.w > $1.payload.w }
            }
        }
    }

    func updateStatus(bt: Int, bc: Bool) {
        let s = PhoneStatus(bt: bt, bc: bc, at: Date())
        phoneStatus = s
        store.saveStatus(s)
    }

    func unpair() {
        let oldPairId = PairingKeys.shared.pairId
        let oldSecret = PairingKeys.shared.secret
        UserDefaults.appGroup.set(false, forKey: "opi.paired")
        PendingQueue.shared.clear()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        PhoneLink.shared.disconnect()
        PairingKeys.shared.reset()
        paired = false
        items = []
        phoneStatus = nil
        media = nil
        ringing = false
        calendar = nil
        for kind in SharedStore.Kind.allCases { store.remove(kind) }
        Task { await CalendarReminders.clear() }
        // The new pairId needs a fresh relay registration, and the pairing
        // screen should resume scanning for the phone.
        RelayRegistration.shared.pairingDidReset {
            try? await RelayClient.unregister(pairId: oldPairId, secret: oldSecret)
        }
        PhoneLink.shared.start(state: "active")
    }
}

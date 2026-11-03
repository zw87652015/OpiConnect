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
    @Published var selectedId: String?
    @Published var paired = UserDefaults.appGroup.bool(forKey: "opi.paired")
    @Published var relayRegistered = false
    @Published var sendState: SendState = .idle

    private init() {}

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
        // The new pairId needs a fresh relay registration, and the pairing
        // screen should resume scanning for the phone.
        WKApplication.shared().registerForRemoteNotifications()
        PhoneLink.shared.start(state: "active")
    }
}

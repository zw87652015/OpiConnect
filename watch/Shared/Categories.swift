import Foundation
import UserNotifications

// Notification categories built from a payload's actions (first 3 only).
// The category id is deterministic so BLE and APNs copies of the same notification
// share it.
enum Categories {
    static let none = "opi.none"

    static func categoryId(for payload: NotifPayload) -> String {
        let actions = payload.x ?? []
        guard !actions.isEmpty else { return none }
        let key = actions.prefix(3).map { "\($0.r ? 1 : 0)\($0.l)" }.joined(separator: "\u{1f}")
        let hex = OpiCrypto.sha256(Data(key.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "opi.a." + hex
    }

    static func actions(for payload: NotifPayload) -> [UNNotificationAction] {
        (payload.x ?? []).prefix(3).enumerated().map { idx, action in
            let identifier = "act.\(idx)"
            return action.r
                ? UNTextInputNotificationAction(identifier: identifier, title: action.l,
                                                options: [.foreground], textInputButtonTitle: String(localized: "Send", table: "Shared"),
                                                textInputPlaceholder: "")
                : UNNotificationAction(identifier: identifier, title: action.l, options: [.foreground])
        }
    }

    // Register the category if missing, then force the set to be applied.
    static func ensureRegistered(for payload: NotifPayload) async {
        let center = UNUserNotificationCenter.current()
        let id = categoryId(for: payload)
        var cats = await center.notificationCategories()
        if !cats.contains(where: { $0.identifier == id }) {
            cats.insert(UNNotificationCategory(identifier: id,
                                               actions: actions(for: payload),
                                               intentIdentifiers: [],
                                               options: [.customDismissAction]))
            center.setNotificationCategories(cats)
            _ = await center.notificationCategories()
        }
    }
}

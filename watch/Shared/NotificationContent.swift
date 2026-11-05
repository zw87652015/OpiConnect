import Foundation
import UserNotifications

// Shared by the NSE (APNs path) and the app (BLE path) so both build identical content.
enum NotificationContent {
    static func make(for payload: NotifPayload, quiet: Bool = false) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        if let code = OTPDetector.detect(in: payload) {
            content.title = String(localized: "Code \(OTPDetector.display(code))", table: "Shared")
            content.subtitle = payload.t.isEmpty ? payload.a : "\(payload.a) · \(payload.t)"
        } else {
            content.title = payload.a
            content.subtitle = payload.t
        }
        content.body = payload.b
        content.threadIdentifier = payload.p
        content.sound = quiet ? nil : .default
        content.categoryIdentifier = Categories.categoryId(for: payload)
        content.userInfo = quiet ? ["opi": payload.jsonObject, "q": true] : ["opi": payload.jsonObject]
        return content
    }

    // Placeholder shown while the subscription is inactive: carries no "opi" payload,
    // so AppModel.reload ignores it and a tap can't open a detail view.
    static func locked() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "OpiLink", table: "Shared")
        content.body = String(localized: "Subscribe to OpiLink to see your notifications.", table: "Shared")
        content.interruptionLevel = .passive
        content.threadIdentifier = "opi.locked"
        return content
    }
}

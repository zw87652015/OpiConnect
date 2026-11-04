import Foundation
import UserNotifications

// Shared by the NSE (APNs path) and the app (BLE path) so both build identical content.
enum NotificationContent {
    static func make(for payload: NotifPayload) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        if let code = OTPDetector.detect(in: payload) {
            content.title = "Code " + OTPDetector.display(code)
            content.subtitle = payload.t.isEmpty ? payload.a : "\(payload.a) · \(payload.t)"
        } else {
            content.title = payload.a
            content.subtitle = payload.t
        }
        content.body = payload.b
        content.threadIdentifier = payload.p
        content.sound = .default
        content.categoryIdentifier = Categories.categoryId(for: payload)
        content.userInfo = ["opi": payload.jsonObject]
        return content
    }
}

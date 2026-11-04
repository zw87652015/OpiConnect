import Foundation
import WatchKit
import UserNotifications

final class AppDelegate: NSObject, WKApplicationDelegate {
    static let refreshTaskId = "opi.refresh"
    private var lastRegisteredKey: String? {
        get { UserDefaults.appGroup.string(forKey: "opi.registered") }
        set { UserDefaults.appGroup.set(newValue, forKey: "opi.registered") }
    }

    func applicationDidFinishLaunching() {
        // Demo mode: no permission prompts and no APNs registration.
        guard !DemoMode.isActive else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        WKApplication.shared().registerForRemoteNotifications()
    }

    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        let pairId = PairingKeys.shared.pairId
        let key = "\(pairId)|\(token)"
        guard key != lastRegisteredKey else {
            AppModel.shared.relayRegistered = true
            return
        }
        #if DEBUG
        let env = "sandbox"
        #else
        let env = "production"
        #endif
        Task {
            do {
                try await RelayClient.register(token: token, env: env)
                lastRegisteredKey = key
                AppModel.shared.relayRegistered = true
            } catch {
                AppModel.shared.relayRegistered = false
            }
        }
    }

    func didFailToRegisterForRemoteNotificationsWithError(_ error: Error) {
        AppModel.shared.relayRegistered = false
        NSLog("[opi] remote notification registration failed: \(error.localizedDescription)")
    }

    // Background push (remote dismiss). The payload carries sealed {"i": id}.
    func didReceiveRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> WKBackgroundFetchResult {
        guard let c = userInfo["c"] as? String,
              let sealed = OpiCrypto.base64urlDecode(c),
              let data = try? OpiCrypto.open(sealed, using: PairingKeys.shared.encKey),
              let remove = try? JSONDecoder().decode(RemovePayload.self, from: data) else {
            return .noData
        }
        if let bt = remove.bt {
            SharedStore().saveStatus(PhoneStatus(bt: bt, bc: remove.bc ?? false, at: Date()))
        }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [remove.i])
        AppModel.shared.remove(id: remove.i)
        return .newData
    }

    static func scheduleNextRefresh() {
        let date = Date(timeIntervalSinceNow: 30 * 60)
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: date,
                                                         userInfo: Self.refreshTaskId as NSString) { _ in }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        let actionId = response.actionIdentifier
        if actionId == UNNotificationDismissActionIdentifier {
            PendingQueue.shared.enqueue(.dismiss(id: id))
            AppModel.shared.remove(id: id)
            PhoneLink.shared.flush()
            return
        }
        if actionId.hasPrefix("act.") {
            guard let idx = Int(actionId.dropFirst(4)),
                  let dict = response.notification.request.content.userInfo["opi"] as? [String: Any],
                  let payload = NotifPayload(jsonObject: dict),
                  let action = payload.x?[safe: idx] else { return }
            let text = (response as? UNTextInputNotificationResponse)?.userText
            PendingQueue.shared.enqueue(.action(id: payload.i, idx: idx, label: action.l, text: text))
            // Actions are .foreground, so the app is about to become active: connect and send.
            AppModel.shared.sendState = .sending
            PhoneLink.shared.start(state: "active")
            PhoneLink.shared.flush()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                if AppModel.shared.sendState == .sending { AppModel.shared.sendState = .queued }
            }
            return
        }
        // Default tap: open the detail view.
        AppModel.shared.openNotification(id: id)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension UserDefaults {
    static var appGroup: UserDefaults {
        UserDefaults(suiteName: PairingKeys.appGroup) ?? .standard
    }
}

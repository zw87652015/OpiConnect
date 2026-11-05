import UserNotifications

// Decrypts the sealed payload in userInfo["c"] (base64url) and replaces the
// generic "New notification" alert with the real content.
final class NotificationService: UNNotificationServiceExtension {
    private var handler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        handler = contentHandler
        bestAttempt = request.content.mutableCopy() as? UNMutableNotificationContent

        Task {
            defer { finish() }
            guard let c = request.content.userInfo["c"] as? String,
                  let sealed = OpiCrypto.base64urlDecode(c),
                  let data = try? OpiCrypto.open(sealed, using: PairingKeys.shared.encKey),
                  let payload = try? JSONDecoder().decode(NotifPayload.self, from: data) else { return }
            // Opening the sealed payload proves the phone holds K: count as paired even
            // when BLE advertising never reaches us.
            UserDefaults(suiteName: PairingKeys.appGroup)?.set(true, forKey: "opi.paired")
            if let bt = payload.bt {
                SharedStore().saveStatus(PhoneStatus(bt: bt, bc: payload.bc ?? false, at: Date()))
            }
            await Categories.ensureRegistered(for: payload)
            bestAttempt = NotificationContent.make(for: payload)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        finish()
    }

    private func finish() {
        guard let handler, let bestAttempt else { return }
        self.handler = nil
        handler(bestAttempt)
    }
}

import Foundation

// Watch -> phone messages (dismiss/action) persisted in app-group defaults so they
// survive app termination and can be flushed over BLE or during background refresh.
final class PendingQueue {
    static let shared = PendingQueue()
    private let key = "opi.pending"

    private(set) var items: [Data] = []

    private init() {
        items = UserDefaults.appGroup.array(forKey: key) as? [Data] ?? []
    }

    var count: Int { items.count }

    func enqueue(_ message: BLEMessage) {
        guard let data = try? message.encode() else { return }
        items.append(data)
        save()
    }

    // Called after the final chunk of the first message is acknowledged (didWriteValueFor, no error).
    func removeFirst() {
        guard !items.isEmpty else { return }
        items.removeFirst()
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        UserDefaults.appGroup.set(items, forKey: key)
    }
}

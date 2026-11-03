import Foundation

// Notification payload and removal payload (docs/PROTOCOL.md).
struct OpiAction: Codable, Equatable {
    var l: String // label
    var r: Bool   // has RemoteInput
}

struct NotifPayload: Codable, Equatable {
    var i: String        // notification id
    var p: String        // package
    var a: String        // app label
    var t: String        // title
    var b: String        // body
    var w: Int64         // postTime millis
    var x: [OpiAction]?  // actions
}

struct RemovePayload: Codable, Equatable {
    var i: String
}

// BLE messages, discriminated by "type" (docs/PROTOCOL.md). Plaintext is UTF-8 JSON
// sealed with encKey before chunking.
enum BLEMessage {
    // watch -> phone
    case hello(state: String)   // "active" | "background"
    case state(String)
    case ack(id: String)
    case dismiss(id: String)
    case action(id: String, idx: Int, label: String, text: String?)
    // phone -> watch
    case welcome
    case notif(NotifPayload)
    case remove(id: String)
    case sync(ids: [String])

    var jsonObject: [String: Any] {
        switch self {
        case .hello(let state): return ["type": "hello", "state": state]
        case .state(let state): return ["type": "state", "state": state]
        case .ack(let id): return ["type": "ack", "id": id]
        case .dismiss(let id): return ["type": "dismiss", "id": id]
        case .action(let id, let idx, let label, let text):
            var o: [String: Any] = ["type": "action", "id": id, "idx": idx, "label": label]
            if let text { o["text"] = text }
            return o
        case .welcome: return ["type": "welcome"]
        case .notif(let p):
            var o = p.jsonObject
            o["type"] = "notif"
            return o
        case .remove(let id): return ["type": "remove", "id": id]
        case .sync(let ids): return ["type": "sync", "ids": ids]
        }
    }

    func encode() throws -> Data {
        try JSONSerialization.data(withJSONObject: jsonObject, options: [.withoutEscapingSlashes])
    }

    static func decode(_ data: Data) -> BLEMessage? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = o["type"] as? String else { return nil }
        switch type {
        case "hello": return (o["state"] as? String).map { .hello(state: $0) }
        case "state": return (o["state"] as? String).map { .state($0) }
        case "ack": return (o["id"] as? String).map { .ack(id: $0) }
        case "dismiss": return (o["id"] as? String).map { .dismiss(id: $0) }
        case "action":
            guard let id = o["id"] as? String,
                  let idx = (o["idx"] as? NSNumber)?.intValue,
                  let label = o["label"] as? String else { return nil }
            return .action(id: id, idx: idx, label: label, text: o["text"] as? String)
        case "welcome": return .welcome
        case "notif": return NotifPayload(jsonObject: o).map { .notif($0) }
        case "remove": return (o["id"] as? String).map { .remove(id: $0) }
        case "sync": return (o["ids"] as? [String]).map { .sync(ids: $0) }
        default: return nil
        }
    }
}

extension NotifPayload {
    init?(jsonObject o: [String: Any]) {
        guard let i = o["i"] as? String,
              let p = o["p"] as? String,
              let a = o["a"] as? String,
              let t = o["t"] as? String,
              let b = o["b"] as? String,
              let w = (o["w"] as? NSNumber)?.int64Value else { return nil }
        self.i = i; self.p = p; self.a = a; self.t = t; self.b = b; self.w = w
        self.x = (o["x"] as? [[String: Any]])?.compactMap { e in
            guard let l = e["l"] as? String, let r = e["r"] as? Bool else { return nil }
            return OpiAction(l: l, r: r)
        }
    }

    var jsonObject: [String: Any] {
        var o: [String: Any] = ["i": i, "p": p, "a": a, "t": t, "b": b, "w": w]
        if let x { o["x"] = x.map { ["l": $0.l, "r": $0.r] } }
        return o
    }
}

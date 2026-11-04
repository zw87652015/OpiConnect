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
    var bt: Int?         // phone battery 0-100
    var bc: Bool?        // phone charging
}

struct RemovePayload: Codable, Equatable {
    var i: String
    var bt: Int?
    var bc: Bool?
}

// BLE messages, discriminated by "type" (docs/PROTOCOL.md). Plaintext is UTF-8 JSON
// sealed with encKey before chunking.
enum BLEMessage {
    // watch -> phone
    case hello(state: String, cal: String? = nil)   // "active" | "background"; cal = cached calendar hash
    case state(String)
    case ack(id: String)
    case dismiss(id: String)
    case action(id: String, idx: Int, label: String, text: String?)
    case findphone(on: Bool)
    case media(cmd: String, v: Double? = nil)
    case calSync                                    // manual calendar resend request
    // phone -> watch
    case welcome
    case notif(NotifPayload)
    case remove(id: String)
    case sync(ids: [String])
    case status(bt: Int, bc: Bool)
    case mediaState(MediaSnapshot)
    case findphoneState(on: Bool)
    case cal(CalendarCache)

    var jsonObject: [String: Any] {
        switch self {
        case .hello(let state, let cal):
            var o: [String: Any] = ["type": "hello", "state": state]
            if let cal { o["cal"] = cal }
            return o
        case .state(let state): return ["type": "state", "state": state]
        case .ack(let id): return ["type": "ack", "id": id]
        case .dismiss(let id): return ["type": "dismiss", "id": id]
        case .action(let id, let idx, let label, let text):
            var o: [String: Any] = ["type": "action", "id": id, "idx": idx, "label": label]
            if let text { o["text"] = text }
            return o
        case .findphone(let on): return ["type": "findphone", "on": on]
        case .media(let cmd, let v):
            var o: [String: Any] = ["type": "media", "cmd": cmd]
            if let v { o["v"] = v }
            return o
        case .calSync: return ["type": "cal_sync"]
        case .welcome: return ["type": "welcome"]
        case .notif(let p):
            var o = p.jsonObject
            o["type"] = "notif"
            return o
        case .remove(let id): return ["type": "remove", "id": id]
        case .sync(let ids): return ["type": "sync", "ids": ids]
        case .status(let bt, let bc): return ["type": "status", "bt": bt, "bc": bc]
        case .mediaState(let m): return m.jsonObject.merging(["type": "media_state"]) { _, new in new }
        case .findphoneState(let on): return ["type": "findphone_state", "on": on]
        case .cal(let cache): return cache.jsonObject.merging(["type": "cal"]) { _, new in new }
        }
    }

    func encode() throws -> Data {
        try JSONSerialization.data(withJSONObject: jsonObject, options: [.withoutEscapingSlashes])
    }

    static func decode(_ data: Data) -> BLEMessage? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = o["type"] as? String else { return nil }
        switch type {
        case "hello": return (o["state"] as? String).map { .hello(state: $0, cal: o["cal"] as? String) }
        case "findphone": return (o["on"] as? Bool).map { .findphone(on: $0) }
        case "media":
            return (o["cmd"] as? String).map { .media(cmd: $0, v: (o["v"] as? NSNumber)?.doubleValue) }
        case "status":
            guard let bt = (o["bt"] as? NSNumber)?.intValue,
                  let bc = o["bc"] as? Bool else { return nil }
            return .status(bt: bt, bc: bc)
        case "media_state": return MediaSnapshot(jsonObject: o).map { .mediaState($0) }
        case "findphone_state": return (o["on"] as? Bool).map { .findphoneState(on: $0) }
        case "cal": return CalendarCache(jsonObject: o).map { .cal($0) }
        case "state": return (o["state"] as? String).map { .state($0) }
        case "ack": return (o["id"] as? String).map { .ack(id: $0) }
        case "dismiss": return (o["id"] as? String).map { .dismiss(id: $0) }
        case "action":
            guard let id = o["id"] as? String,
                  let idx = (o["idx"] as? NSNumber)?.intValue,
                  let label = o["label"] as? String else { return nil }
            return .action(id: id, idx: idx, label: label, text: o["text"] as? String)
        case "welcome": return .welcome
        case "cal_sync": return .calSync
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
        self.bt = (o["bt"] as? NSNumber)?.intValue
        self.bc = o["bc"] as? Bool
    }

    var jsonObject: [String: Any] {
        var o: [String: Any] = ["i": i, "p": p, "a": a, "t": t, "b": b, "w": w]
        if let x { o["x"] = x.map { ["l": $0.l, "r": $0.r] } }
        if let bt { o["bt"] = bt }
        if let bc { o["bc"] = bc }
        return o
    }
}

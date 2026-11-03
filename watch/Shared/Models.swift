import Foundation

// Phone status / media / calendar models shared between app, NSE and widgets.
// Foundation-only: this file must compile in the widget extension too.

struct PhoneStatus: Codable, Equatable {
    var bt: Int   // 0-100
    var bc: Bool  // charging
    var at: Date  // when received
}

struct MediaSnapshot: Codable, Equatable {
    var on: Bool
    var app: String
    var t: String    // title
    var ar: String   // artist
    var pl: Bool     // playing
    var v: Double    // music stream volume 0-1
    var at: Date = .distantPast

    init(on: Bool, app: String, t: String, ar: String, pl: Bool, v: Double, at: Date = .distantPast) {
        self.on = on; self.app = app; self.t = t; self.ar = ar; self.pl = pl; self.v = v; self.at = at
    }

    init?(jsonObject o: [String: Any]) {
        guard let on = o["on"] as? Bool else { return nil }
        self.on = on
        self.app = o["app"] as? String ?? ""
        self.t = o["t"] as? String ?? ""
        self.ar = o["ar"] as? String ?? ""
        self.pl = o["pl"] as? Bool ?? false
        self.v = (o["v"] as? NSNumber)?.doubleValue ?? 0
        self.at = Date()
    }

    var jsonObject: [String: Any] {
        ["on": on, "app": app, "t": t, "ar": ar, "pl": pl, "v": v]
    }
}

struct CalEvent: Codable, Equatable, Identifiable {
    var id: String { k }
    var k: String    // event key
    var t: String    // title
    var s: Int64     // start ms
    var e: Int64     // end ms
    var ad: Bool     // all day
    var loc: String  // location
    var n: String    // notes
    var cal: String  // calendar name
    var col: Int64   // ARGB color
    var rm: [Int]    // reminder minutes before

    init?(jsonObject o: [String: Any]) {
        guard let k = o["k"] as? String,
              let t = o["t"] as? String,
              let s = (o["s"] as? NSNumber)?.int64Value,
              let e = (o["e"] as? NSNumber)?.int64Value,
              let ad = o["ad"] as? Bool else { return nil }
        self.k = k; self.t = t; self.s = s; self.e = e; self.ad = ad
        self.loc = o["loc"] as? String ?? ""
        self.n = o["n"] as? String ?? ""
        self.cal = o["cal"] as? String ?? ""
        self.col = (o["col"] as? NSNumber)?.int64Value ?? 0
        self.rm = (o["rm"] as? [NSNumber])?.map { $0.intValue } ?? []
    }

    init(k: String, t: String, s: Int64, e: Int64, ad: Bool, loc: String = "", n: String = "",
         cal: String = "", col: Int64 = 0, rm: [Int] = []) {
        self.k = k; self.t = t; self.s = s; self.e = e; self.ad = ad
        self.loc = loc; self.n = n; self.cal = cal; self.col = col; self.rm = rm
    }

    var jsonObject: [String: Any] {
        ["k": k, "t": t, "s": s, "e": e, "ad": ad, "loc": loc, "n": n,
         "cal": cal, "col": col, "rm": rm]
    }

    var startDate: Date { Date(timeIntervalSince1970: TimeInterval(s) / 1000) }
    var endDate: Date { Date(timeIntervalSince1970: TimeInterval(e) / 1000) }
}

struct CalendarCache: Codable, Equatable {
    var h: String
    var from: Int64
    var to: Int64
    var events: [CalEvent]
    var updatedAt: Date = .distantPast

    init(h: String, from: Int64, to: Int64, events: [CalEvent], updatedAt: Date = .distantPast) {
        self.h = h; self.from = from; self.to = to; self.events = events; self.updatedAt = updatedAt
    }

    init?(jsonObject o: [String: Any]) {
        guard let h = o["h"] as? String,
              let from = (o["from"] as? NSNumber)?.int64Value,
              let to = (o["to"] as? NSNumber)?.int64Value,
              let arr = o["ev"] as? [[String: Any]] else { return nil }
        self.h = h; self.from = from; self.to = to
        self.events = arr.compactMap { CalEvent(jsonObject: $0) }
        self.updatedAt = Date()
    }

    var jsonObject: [String: Any] {
        ["h": h, "from": from, "to": to, "ev": events.map { $0.jsonObject }]
    }
}

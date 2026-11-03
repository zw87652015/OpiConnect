import XCTest
@testable import OpiConnect_Watch_App

final class FeatureTests: XCTestCase {

    // MARK: BLEMessage decode (phone -> watch)

    func testDecodeStatus() {
        let m = BLEMessage.decode(Data(#"{"type":"status","bt":76,"bc":true}"#.utf8))
        guard case .status(let bt, let bc) = m else { return XCTFail() }
        XCTAssertEqual(bt, 76)
        XCTAssertTrue(bc)
    }

    func testDecodeMediaState() {
        let m = BLEMessage.decode(Data(#"{"type":"media_state","on":true,"app":"Spotify","t":"Song","ar":"Artist","pl":true,"v":0.5}"#.utf8))
        guard case .mediaState(let s) = m else { return XCTFail() }
        XCTAssertEqual(s.app, "Spotify")
        XCTAssertEqual(s.t, "Song")
        XCTAssertEqual(s.v, 0.5, accuracy: 0.001)
        let off = BLEMessage.decode(Data(#"{"type":"media_state","on":false,"app":"","t":"","ar":"","pl":false,"v":0}"#.utf8))
        guard case .mediaState(let s2) = off else { return XCTFail() }
        XCTAssertFalse(s2.on)
    }

    func testDecodeFindphoneState() {
        let m = BLEMessage.decode(Data(#"{"type":"findphone_state","on":true}"#.utf8))
        guard case .findphoneState(let on) = m else { return XCTFail() }
        XCTAssertTrue(on)
    }

    func testDecodeCal() {
        let json = """
        {"type":"cal","h":"abc123","from":5,"to":5000,"ev":[
          {"k":"k1","t":"Meeting","s":1000,"e":2000,"ad":false,"loc":"Room","n":"notes","cal":"Work","col":-16776961,"rm":[10,30]}
        ]}
        """
        let m = BLEMessage.decode(Data(json.utf8))
        guard case .cal(let cache) = m else { return XCTFail() }
        XCTAssertEqual(cache.h, "abc123")
        XCTAssertEqual(cache.events.count, 1)
        XCTAssertEqual(cache.events[0].k, "k1")
        XCTAssertEqual(cache.events[0].rm, [10, 30])
        XCTAssertEqual(cache.events[0].col, -16776961)
    }

    // MARK: BLEMessage encode (watch -> phone)

    private func jsonOf(_ m: BLEMessage) throws -> [String: Any] {
        let data = try m.encode()
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testEncodeFindphone() throws {
        let o = try jsonOf(.findphone(on: true))
        XCTAssertEqual(o["type"] as? String, "findphone")
        XCTAssertEqual(o["on"] as? Bool, true)
    }

    func testEncodeMedia() throws {
        let vol = try jsonOf(.media(cmd: "vol", v: 0.65))
        XCTAssertEqual(vol["type"] as? String, "media")
        XCTAssertEqual(vol["cmd"] as? String, "vol")
        XCTAssertEqual((vol["v"] as? NSNumber)?.doubleValue ?? -1, 0.65, accuracy: 0.001)
        let next = try jsonOf(.media(cmd: "next"))
        XCTAssertNil(next["v"])
    }

    func testEncodeHelloWithCal() throws {
        let o = try jsonOf(.hello(state: "active", cal: "abc"))
        XCTAssertEqual(o["cal"] as? String, "abc")
        let plain = try jsonOf(.hello(state: "active"))
        XCTAssertNil(plain["cal"])
    }

    // MARK: Reminder selection

    private func event(k: String, s: Int64, ad: Bool = false, rm: [Int] = [10]) -> CalEvent {
        CalEvent(k: k, t: "Event \(k)", s: s, e: s + 3_600_000, ad: ad, rm: rm)
    }

    func testSelectSkipsPastAndCaps50() {
        let tz = TimeZone(identifier: "Europe/Berlin")!
        let nowMs: Int64 = 1_750_000_000_000
        let now = Date(timeIntervalSince1970: TimeInterval(nowMs) / 1000)
        var events = (0..<60).map { i in
            event(k: "e\(i)", s: nowMs + Int64(i + 1) * 3_600_000, rm: [10])
        }
        events.append(event(k: "past", s: nowMs - 3_600_000, rm: [10])) // fire time in the past
        let fires = CalendarReminders.select(from: events, now: now, timeZone: tz)
        XCTAssertEqual(fires.count, 50)
        XCTAssertFalse(fires.contains { $0.event.k == "past" })
        // sorted ascending by date
        XCTAssertEqual(fires.map { $0.date }, fires.map { $0.date }.sorted())
        XCTAssertEqual(fires[0].id, "cal.e0.10")
    }

    func testAllDayUtcToLocalMidnight() {
        let tz = TimeZone(identifier: "Asia/Shanghai")! // UTC+8
        // All-day event stored at UTC midnight for 2025-07-01.
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let utcMidnight = utcCal.date(from: DateComponents(year: 2025, month: 7, day: 1))!
        let ev = event(k: "ad", s: Int64(utcMidnight.timeIntervalSince1970 * 1000), ad: true, rm: [0])
        let fire = CalendarReminders.fireDate(for: ev, rm: 0, timeZone: tz)
        // Expect local (Shanghai) midnight of the UTC calendar date 2025-07-01 = 2025-06-30T16:00Z
        XCTAssertEqual(fire, utcMidnight.addingTimeInterval(-8 * 3600))
    }

    // MARK: SharedStore round-trip

    func testSharedStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opi-test-\(UUID().uuidString)")
        let store = SharedStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let status = PhoneStatus(bt: 66, bc: true, at: Date(timeIntervalSince1970: 1000))
        store.saveStatus(status)
        XCTAssertEqual(store.status(), status)

        let ev = CalEvent(k: "k", t: "T", s: 1, e: 2, ad: false, loc: "L", n: "N", cal: "C", col: -16776961, rm: [10])
        let cache = CalendarCache(h: "h1", from: 0, to: 10, events: [ev],
                                  updatedAt: Date(timeIntervalSince1970: 2000))
        store.saveCalendar(cache)
        XCTAssertEqual(store.calendar(), cache)

        let media = MediaSnapshot(on: true, app: "Spotify", t: "Song", ar: "Artist", pl: true, v: 0.5,
                                  at: Date(timeIntervalSince1970: 3000))
        store.saveMedia(media)
        XCTAssertEqual(store.media(), media)
    }
}

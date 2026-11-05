import Foundation

#if DEBUG
// Screenshot/demo mode: `xcrun simctl launch ... -OpiDemo en|zh -OpiDemoRoute <route>`.
// All state is in memory only — never written to SharedStore, the app-group
// defaults, or the Keychain.
enum DemoMode {
    static let language: String = UserDefaults.standard.string(forKey: "OpiDemo") ?? ""
    static var isActive: Bool { !language.isEmpty }
    private static var zh: Bool { language.hasPrefix("zh") }
    static let route: String = UserDefaults.standard.string(forKey: "OpiDemoRoute") ?? "home"

    private static let otpId = "demo2"

    private static var notifications: [NotifItem] {
        let now = Date().timeIntervalSince1970 * 1000
        func at(_ minutesAgo: Double) -> Int64 { Int64(now - minutesAgo * 60_000) }
        let n: [(id: String, a: String, t: String, b: String, x: [OpiAction]?)] = zh ? [
            ("demo1", "信息", "陈晓", "我晚到十分钟，先帮我们占个座？",
             [OpiAction(l: "回复", r: true), OpiAction(l: "标为已读", r: false)]),
            (otpId, "银行", "登录验证", "您的验证码为482913，10分钟内有效，请勿泄露。", nil),
            ("demo3", "邮件", "航班值机已开放", "飞往北京 · 14:10 开始登机，B32 登机口", nil),
            ("demo4", "快递", "您的包裹今天送达", "预计 13:00–15:00 送达", nil),
        ] : [
            ("demo1", "Messages", "Alex Chen", "Running 10 min late — grab us a table?",
             [OpiAction(l: "Reply", r: true), OpiAction(l: "Mark as read", r: false)]),
            (otpId, "Bank", "Sign-in verification",
             "Your verification code is 482913. It expires in 10 minutes. Do not share it.", nil),
            ("demo3", "Mail", "Check-in is open",
             "Flight to Amsterdam · boarding 14:10, gate B32", nil),
            ("demo4", "Delivery", "Your parcel arrives today",
             "Expected between 13:00 and 15:00.", nil),
        ]
        return n.enumerated().map { idx, e in
            NotifItem(payload: NotifPayload(i: e.id, p: "com.opiconnect.demo", a: e.a,
                                            t: e.t, b: e.b, w: at(Double(idx) * 3 + 2),
                                            x: e.x, bt: nil, bc: nil))
        }
    }

    private static var calendar: CalendarCache {
        var cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        func on(_ dayOffset: Int, _ hour: Int, _ minute: Int) -> Int64 {
            let d = cal.date(byAdding: .day, value: dayOffset, to: startOfToday)!
            let d2 = cal.date(bySettingHour: hour, minute: minute, second: 0, of: d)!
            return Int64(d2.timeIntervalSince1970 * 1000)
        }
        func allDay(_ dayOffset: Int) -> (Int64, Int64) {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            let d = utc.date(byAdding: .day, value: dayOffset, to: utc.startOfDay(for: now))!
            return (Int64(d.timeIntervalSince1970 * 1000),
                    Int64(d.timeIntervalSince1970 * 1000) + 86_400_000)
        }
        let (bStart, bEnd) = allDay(2)
        let blue = Int64(bitPattern: 0xff4285f4)   // Work
        let green = Int64(bitPattern: 0xff34a853)  // Personal
        let orange = Int64(bitPattern: 0xffff9800)
        let events: [CalEvent] = zh ? [
            CalEvent(k: "d1", t: "团队站会", s: on(0, 9, 30), e: on(0, 9, 45), ad: false,
                     cal: "工作", col: blue),
            CalEvent(k: "d2", t: "和小林吃午饭", s: on(0, 12, 30), e: on(0, 13, 30), ad: false,
                     loc: "街角咖啡", cal: "个人", col: green),
            CalEvent(k: "d3", t: "看牙医", s: on(1, 10, 0), e: on(1, 10, 30), ad: false,
                     loc: "中山路诊所", cal: "个人", col: green),
            CalEvent(k: "d4", t: "妈妈生日", s: bStart, e: bEnd, ad: true, col: orange),
        ] : [
            CalEvent(k: "d1", t: "Team stand-up", s: on(0, 9, 30), e: on(0, 9, 45), ad: false,
                     cal: "Work", col: blue),
            CalEvent(k: "d2", t: "Lunch with Sam", s: on(0, 12, 30), e: on(0, 13, 30), ad: false,
                     loc: "Corner Café", cal: "Personal", col: green),
            CalEvent(k: "d3", t: "Dentist", s: on(1, 10, 0), e: on(1, 10, 30), ad: false,
                     loc: "High St Clinic", cal: "Personal", col: green),
            CalEvent(k: "d4", t: "Mum's birthday", s: bStart, e: bEnd, ad: true, col: orange),
        ]
        return CalendarCache(h: "demo", from: Int64(now.timeIntervalSince1970 * 1000),
                             to: bEnd, events: events, updatedAt: now)
    }

    private static var media: MediaSnapshot {
        zh ? MediaSnapshot(on: true, app: "音乐", t: "晚风", ar: "林间", pl: true, v: 0.6, at: Date())
           : MediaSnapshot(on: true, app: "Music", t: "Northern Lights", ar: "Aurora Lane",
                           pl: true, v: 0.6, at: Date())
    }

    @MainActor
    static func apply(to model: AppModel) {
        model.relayRegistered = true
        model.items = notifications
        model.phoneStatus = PhoneStatus(bt: 82, bc: false, at: Date())
        model.media = media
        model.calendar = calendar
        if route == "pairing" || route == "guide" {
            model.paired = false
            return
        }
        model.paired = true
        switch route {
        case "detail":
            model.path = [.detail(id: model.items.first?.id ?? "")]
        case "otp":
            model.path = [.detail(id: otpId)]
        case "calendar":
            model.path = [.calendar]
        case "music":
            model.path = [.music]
        case "findphone":
            model.path = [.findphone]
        case "settings":
            model.path = [.settings]
        default:
            model.path = []
        }
    }
}
#else
enum DemoMode {
    static var isActive: Bool { false }
    static var route: String { "" }
    @MainActor
    static func apply(to model: AppModel) {}
}
#endif

import Foundation

// Conservative one-time-code detector for forwarded notifications.
// Matches only when OTP vocabulary anchors the text, so phone numbers,
// amounts, dates, order ids, and URLs never produce a code.
enum OTPDetector {

    private static let strongKeywords = [
        "验证码", "校验码", "动态码", "动态密码", "确认码", "激活码", "安全码",
        "登录码", "短信码", "一次性密码", "验证代码",
        "verification code", "security code", "confirmation code", "login code",
        "log-in code", "sign-in code", "signin code", "one-time code", "one time code",
        "one-time password", "one time password", "one-time passcode", "passcode",
        "auth code", "authentication code", "access code",
        "verify", "verification", "apple account code", "apple id code",
    ]
    private static let strongWholeWords = ["otp", "2fa"]
    private static let weakKeywords = ["code", "码", "密码"]
    private static let weakWholeWords = ["pin"]
    private static let validityPhrases = [
        "有效", "请勿", "切勿", "勿告知", "不要告诉", "泄露",
        "expires", "expire", "valid for", "do not share", "don't share",
        "never share", "will never ask", "not share",
    ]
    // Context words that mark a digit run as a card tail, order id, amount, or phone number.
    private static let beforeBlocklist = [
        "尾号", "末四位", "末4位", "后四位", "后4位", "ending in", "ending",
        "card", "卡号", "账号", "账户", "订单", "单号", "order", "no.",
        "tel", "phone", "电话", "热线", "致电", "拨打", "call", "hotline", "客服",
        "¥", "$", "€", "£", "rmb", "usd", "金额", "余额", "balance", "amount",
    ]
    private static let afterBlocklist = [
        "元", "块", "%", "分", "秒", "min", "年", "月", "日", "号",
        "人", "次", "个", "条", "km", "kg", "万",
    ]

    static func detect(in payload: NotifPayload) -> String? {
        detect(title: payload.t, body: payload.b)
    }

    static func detect(title: String, body: String) -> String? {
        let text = (title + "\n" + body).precomposedStringWithCompatibilityMapping
        let ns = mask(text) as NSString
        let full = NSRange(location: 0, length: ns.length)

        // a. Prefixed tokens like "G-123456" (case-sensitive).
        let prefixed = matches(#"(?<![0-9A-Za-z])[A-Z]{1,3}-\d{4,8}(?![0-9A-Za-z])"#, in: ns)
        // b. Grouped digits like "123-456".
        let grouped = matches(#"(?<![0-9A-Za-z+\-])\d{3,4}[ -]\d{3,4}(?![0-9A-Za-z])(?![ -]\d)"#, in: ns)

        var anchors = keywordRanges(in: ns, range: full, substrings: strongKeywords, wholeWords: strongWholeWords)
        if anchors.isEmpty {
            // Weak keywords only qualify with corroboration: a validity phrase,
            // or a code-shaped token (prefixed/grouped) in the text.
            let hasValidity = !keywordRanges(in: ns, range: full, substrings: validityPhrases, wholeWords: []).isEmpty
            if hasValidity || !prefixed.isEmpty || !grouped.isEmpty {
                anchors = keywordRanges(in: ns, range: full, substrings: weakKeywords, wholeWords: weakWholeWords)
            }
        }
        guard !anchors.isEmpty else { return nil }

        struct Candidate { var range: NSRange; var code: String; var anchored: Bool }
        var candidates: [Candidate] = []

        for r in prefixed {
            candidates.append(Candidate(range: r, code: ns.substring(with: r), anchored: false))
        }
        for r in grouped {
            let digits = ns.substring(with: r).filter(\.isNumber)
            candidates.append(Candidate(range: r, code: digits, anchored: false))
        }

        // c. Plain digit runs; skip any fully inside a prefixed match.
        for r in matches(#"(?<![0-9A-Za-z])\d{4,8}(?![0-9A-Za-z])"#, in: ns) {
            if prefixed.contains(where: { NSIntersectionRange($0, r).length == r.length }) { continue }
            candidates.append(Candidate(range: r, code: ns.substring(with: r), anchored: false))
        }

        // d. Alphanumeric codes right after an anchor ("code is a3k9x2").
        let gap = try! NSRegularExpression(pattern: #"^[\s:：是为is]{0,6}[A-Za-z0-9]{4,8}(?![0-9A-Za-z])"#)
        for a in anchors {
            let start = NSMaxRange(a)
            guard start < ns.length else { continue }
            let rest = NSRange(location: start, length: ns.length - start)
            guard let m = gap.firstMatch(in: ns as String, range: rest) else { continue }
            let token = m.range
            // Trim the gap: code is the trailing alnum run of the match.
            var loc = NSMaxRange(token)
            while loc > token.location, isAlnum(ns.character(at: loc - 1)) { loc -= 1 }
            let codeRange = NSRange(location: loc, length: NSMaxRange(token) - loc)
            let code = ns.substring(with: codeRange)
            if code.contains(where: \.isNumber), code.contains(where: { $0.isLetter }) {
                candidates.append(Candidate(range: codeRange, code: code, anchored: true))
            }
        }

        // Score: distance to the nearest anchor, then pick the best.
        var best: (code: String, distance: Int, length: Int, location: Int)?
        for c in candidates {
            if !c.anchored, rejected(c.range, in: ns) { continue }
            let distance = anchors.map { anchorGap(c.range, $0) }.min() ?? .max
            let limit = c.code.count == 4 ? 20 : 60
            guard distance <= limit else { continue }
            if let b = best {
                if distance > b.distance { continue }
                if distance == b.distance {
                    let preferSix = (c.code.count == 6) != (b.length == 6)
                    if preferSix, b.length == 6 { continue }
                    if !preferSix, c.code.count != b.length, c.code.count < b.length { continue }
                    if c.code.count == b.length, c.range.location >= b.location { continue }
                }
            }
            best = (c.code, distance, c.code.count, c.range.location)
        }
        return best?.code
    }

    static func display(_ code: String) -> String {
        guard code.allSatisfy(\.isNumber) else { return code }
        if code.count == 6 { return code.prefix(3) + " " + code.suffix(3) }
        if code.count == 8 { return code.prefix(4) + " " + code.suffix(4) }
        return code
    }

    // MARK: internals

    private static func mask(_ text: String) -> String {
        let re = try! NSRegularExpression(
            pattern: #"https?://\S+|www\.\S+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
            options: [.caseInsensitive])
        let out = NSMutableString(string: text)
        for m in re.matches(in: text, range: NSRange(location: 0, length: out.length)) {
            out.replaceCharacters(in: m.range, with: String(repeating: " ", count: m.range.length))
        }
        return out as String
    }

    private static func matches(_ pattern: String, in ns: NSString,
                                options: NSRegularExpression.Options = []) -> [NSRange] {
        let re = try! NSRegularExpression(pattern: pattern, options: options)
        return re.matches(in: ns as String, range: NSRange(location: 0, length: ns.length)).map(\.range)
    }

    private static func keywordRanges(in ns: NSString, range: NSRange,
                                      substrings: [String], wholeWords: [String]) -> [NSRange] {
        var ranges: [NSRange] = []
        if !substrings.isEmpty {
            let pattern = substrings.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
            let re = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            ranges += re.matches(in: ns as String, range: range).map(\.range)
        }
        for w in wholeWords {
            let pattern = "(?<![A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: w) + "(?![A-Za-z0-9])"
            let re = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            ranges += re.matches(in: ns as String, range: range).map(\.range)
        }
        return ranges
    }

    private static func isAlnum(_ c: unichar) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
    }

    private static func isDigit(_ c: unichar) -> Bool { c >= 48 && c <= 57 }

    private static func anchorGap(_ r: NSRange, _ a: NSRange) -> Int {
        max(0, r.location - NSMaxRange(a), a.location - NSMaxRange(r))
    }

    // Rejects digit runs that look like times, dates, decimals, card tails, or amounts.
    private static func rejected(_ r: NSRange, in ns: NSString) -> Bool {
        let len = ns.length
        if r.location > 0 {
            let before = ns.character(at: r.location - 1)
            if before == 43 { return true } // '+'
            if ".:/,-".utf16.contains(before), r.location > 1, isDigit(ns.character(at: r.location - 2)) {
                return true
            }
        }
        let end = NSMaxRange(r)
        if end < len {
            let after = ns.character(at: end)
            if ".:/-".utf16.contains(after), end + 1 < len, isDigit(ns.character(at: end + 1)) {
                return true
            }
            // ",000" thousands grouping (but not "482913,5分钟").
            if after == 44 {
                var i = end + 1, n = 0
                while i < len, isDigit(ns.character(at: i)) { i += 1; n += 1 }
                if n == 3 { return true }
            }
        }
        let ctxStart = max(0, r.location - 8)
        let ctx = ns.substring(with: NSRange(location: ctxStart, length: r.location - ctxStart)).lowercased()
        if beforeBlocklist.contains(where: { ctx.contains($0) }) { return true }
        let tailLen = min(3, len - end)
        if tailLen > 0 {
            let tail = ns.substring(with: NSRange(location: end, length: tailLen)).lowercased()
            if afterBlocklist.contains(where: { tail.hasPrefix($0) }) { return true }
        }
        return false
    }
}

import XCTest
@testable import OpiConnect_Watch_App

final class OTPDetectorTests: XCTestCase {

    private func assertDetect(_ body: String, title: String = "", _ expected: String?,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(OTPDetector.detect(title: title, body: body), expected, file: file, line: line)
    }

    // MARK: positive

    func testPositives() {
        assertDetect("【招商银行】您的验证码为 482913，5分钟内有效，请勿泄露。", "482913")
        assertDetect("您尾号6688的储蓄卡正在进行网上支付，验证码：739204，金额128.00元。", "739204")
        assertDetect("G-123456 is your Google verification code.", "G-123456")
        assertDetect("Your Apple Account code is: 845201. Don't share it with anyone.\n\n@apple.com #845201 %apple.com", "845201")
        assertDetect("Your Uber code: 9021. Never share this code.", "9021")
        assertDetect("Your WhatsApp code: 123-456", "123456")
        assertDetect("Your code is 5729", title: "Verification code", "5729")
        assertDetect("Microsoft account security code: 4518293", "4518293")
        assertDetect("[淘宝] 校验码 3821 ，您正在登录，切勿告知他人。", "3821")
        assertDetect("您的动态密码是 a3k9x2，10分钟内有效", "a3k9x2")
        assertDetect("验证码：８２３４５６", "823456")
        assertDetect("Enter 304918 to verify your account. This code expires in 10 minutes.", "304918")
    }

    // MARK: negative

    func testNegatives() {
        assertDetect("我电话 13812345678，明天下午3点见", nil)
        assertDetect("Meeting moved to room 4021 at 14:30", nil)
        assertDetect("您的订单 202405120031 已发货，快递单号 SF1234567890", nil)
        assertDetect("Your order #482913 has shipped", nil)
        assertDetect("余额 2350.00 元，尾号 8812 账户 05月12日 支出 300元", nil)
        assertDetect("The code review is at 1500 tomorrow", nil)
        assertDetect("Call our hotline 400-820-8820 for your verification questions", nil)
        assertDetect("验证码已发送至尾号 5521 的手机", nil)
        assertDetect("Happy 2024! See you in 2025", nil)
        assertDetect("Your verification code was used on 2024-05-12 at 10:32", nil)
        assertDetect("Verify your email: https://example.com/v?t=839201", nil)
        assertDetect("+86 130 3223 3871 天津 联通", title: "境外号码", nil)
        assertDetect("来电号码 138 1234 5678", nil)
        assertDetect("Incoming call +1 415 555 0132", title: "Phone", nil)
    }

    // MARK: display

    func testDisplay() {
        XCTAssertEqual(OTPDetector.display("482913"), "482 913")
        XCTAssertEqual(OTPDetector.display("48291305"), "4829 1305")
        XCTAssertEqual(OTPDetector.display("G-123456"), "G-123456")
    }
}

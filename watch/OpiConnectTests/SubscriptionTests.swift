import XCTest
@testable import OpiConnect_Watch_App

final class SubscriptionTests: XCTestCase {

    func testIsActiveNil() {
        XCTAssertFalse(Subscription.isActive(expiry: nil))
    }

    func testIsActivePast() {
        let now = Date()
        XCTAssertFalse(Subscription.isActive(expiry: now.addingTimeInterval(-60), now: now))
    }

    func testIsActiveFuture() {
        let now = Date()
        XCTAssertTrue(Subscription.isActive(expiry: now.addingTimeInterval(60), now: now))
        XCTAssertTrue(Subscription.isActive(expiry: .distantFuture, now: now))
    }

    func testCacheRoundTrip() {
        let name = "test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        defer {
            d.removePersistentDomain(forName: name)
        }
        XCTAssertNil(Subscription.cachedExpiry(in: d))
        XCTAssertFalse(Subscription.isActive(in: d))

        let expiry = Date().addingTimeInterval(3600)
        d.set(expiry.timeIntervalSince1970, forKey: Subscription.expiryKey)
        XCTAssertEqual(Subscription.cachedExpiry(in: d)!.timeIntervalSince1970,
                       expiry.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertTrue(Subscription.isActive(in: d))

        d.removeObject(forKey: Subscription.expiryKey)
        XCTAssertNil(Subscription.cachedExpiry(in: d))
        XCTAssertFalse(Subscription.isActive(in: d))
    }
}

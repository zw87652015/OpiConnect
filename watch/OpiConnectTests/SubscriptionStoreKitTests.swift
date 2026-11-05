import StoreKit
import StoreKitTest
import XCTest
@testable import OpiConnect_Watch_App

// End-to-end check that the unlock path (Subscription.refresh) only activates with a
// real StoreKit entitlement — Restore Purchases alone can't unlock the app.
@MainActor
final class SubscriptionStoreKitTests: XCTestCase {

    private var session: SKTestSession!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // OpiConnectTests
            .deletingLastPathComponent()   // watch
            .appendingPathComponent("Products.storekit")
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        suiteName = "test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // Restore with no purchases must not unlock.
    func testRestoreWithoutPurchase() async throws {
        do {
            try await AppStore.sync()
        } catch {
            // Recorded but not fatal: the assert below is what decides the outcome.
            print("AppStore.sync() threw in test environment: \(error)")
        }
        let expiry = await Subscription.refresh(in: defaults)
        XCTAssertNil(expiry)
        XCTAssertFalse(Subscription.isActive(in: defaults))
        XCTAssertNil(defaults.object(forKey: Subscription.expiryKey))
    }

    // A stale/tampered cached expiry must be cleared when no entitlement exists.
    func testStaleCacheCleared() async throws {
        defaults.set(Date().addingTimeInterval(3600).timeIntervalSince1970,
                     forKey: Subscription.expiryKey)
        XCTAssertTrue(Subscription.isActive(in: defaults)) // precondition

        let expiry = await Subscription.refresh(in: defaults)
        XCTAssertNil(expiry)
        XCTAssertFalse(Subscription.isActive(in: defaults))
        XCTAssertNil(defaults.object(forKey: Subscription.expiryKey))
    }

    // A real purchase unlocks; expiry locks again.
    func testPurchaseUnlocksThenExpiryLocks() async throws {
        // SKTestSession can't complete purchases on watchOS: buyProduct delegates to
        // an "off-device purchase" through the App Store service, which fails with
        // SKInternalErrorDomain Code=2 in this environment.
        do {
            try await session.buyProduct(identifier: "uk.luojiajiang.OpiConnect.Linker.Monthly")
        } catch {
            throw XCTSkip("buyProduct unsupported in watchOS test session: \(error)")
        }

        var expiry = await Subscription.refresh(in: defaults)
        XCTAssertNotNil(expiry)
        XCTAssertGreaterThan(expiry ?? .distantPast, Date())
        XCTAssertTrue(Subscription.isActive(in: defaults))

        try session.expireSubscription(productIdentifier: "uk.luojiajiang.OpiConnect.Linker.Monthly")
        expiry = await Subscription.refresh(in: defaults)
        XCTAssertNil(expiry)
        XCTAssertFalse(Subscription.isActive(in: defaults))
    }

    // A refunded purchase must not unlock.
    func testRefundedPurchaseStaysLocked() async throws {
        do {
            try await session.buyProduct(identifier: "uk.luojiajiang.OpiConnect.Linker.Monthly")
        } catch {
            throw XCTSkip("buyProduct unsupported in watchOS test session: \(error)")
        }
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: transaction.identifier)

        let expiry = await Subscription.refresh(in: defaults)
        XCTAssertNil(expiry)
        XCTAssertFalse(Subscription.isActive(in: defaults))
    }
}

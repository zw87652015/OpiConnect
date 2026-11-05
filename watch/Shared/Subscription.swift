import Foundation
import StoreKit

// Auto-renewable subscription gating: pairing stays free, everything else needs an
// active entitlement. The last known expiry is cached in the app-group defaults so
// the NSE and widgets can check it without StoreKit.
enum Subscription {
    static let productIDs = [
        "uk.luojiajiang.OpiConnect.Linker.Weekly",
        "uk.luojiajiang.OpiConnect.Linker.Monthly",
        "uk.luojiajiang.OpiConnect.Linker.Yearly",
    ]

    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyURL = URL(string: "https://github.com/zw87652015/OpiConnect/blob/main/appstore/privacy-policy.md")!

    // Cached expiry (timeIntervalSince1970) in the app-group defaults.
    static let expiryKey = "opi.proUntil"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: PairingKeys.appGroup) ?? .standard
    }

    static func isActive(expiry: Date?, now: Date = Date()) -> Bool {
        guard let expiry else { return false }
        return now < expiry
    }

    static func cachedExpiry(in d: UserDefaults = defaults) -> Date? {
        let t = d.double(forKey: expiryKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    // Cache-only check for widgets and other synchronous paths.
    static func isActive(in d: UserDefaults = defaults, now: Date = Date()) -> Bool {
        isActive(expiry: cachedExpiry(in: d), now: now)
    }

    // Recompute the entitlement from Transaction.currentEntitlements and update the cache.
    @discardableResult
    static func refresh(in d: UserDefaults = defaults) async -> Date? {
        var expiry: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productType == .autoRenewable,
                  productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            let e = transaction.expirationDate ?? .distantFuture
            if expiry == nil || e > expiry! { expiry = e }
        }
        if let expiry {
            d.set(expiry.timeIntervalSince1970, forKey: expiryKey)
        } else {
            d.removeObject(forKey: expiryKey)
        }
        return expiry
    }

    // Fast path when the cache is still valid; otherwise consult StoreKit.
    static func isActiveRefreshing() async -> Bool {
        if isActive() { return true }
        guard let expiry = await refresh() else { return false }
        return isActive(expiry: expiry)
    }
}

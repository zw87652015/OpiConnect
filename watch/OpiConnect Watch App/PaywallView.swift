import SwiftUI
import StoreKit

// Fully-locked paywall: shown after pairing while no subscription is active.
// Settings stays reachable so the user can still unpair.
struct PaywallView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            SubscriptionStoreView(productIDs: Subscription.productIDs) {
                #if DEBUG
                if DemoMode.isActive && DemoMode.route == "plans" { EmptyView() } else { header }
                #else
                header
                #endif
            }
            .subscriptionStorePolicyDestination(url: Subscription.termsURL, for: .termsOfService)
            .subscriptionStorePolicyDestination(url: Subscription.privacyURL, for: .privacyPolicy)
            .storeButton(.visible, for: .restorePurchases)
            .onInAppPurchaseCompletion { _, _ in
                Task { await model.refreshSubscription() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("OpiLink")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Android notifications on your wrist")
            Text("Find Phone, music and calendar")
            Text("End-to-end encrypted")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding()
    }
}

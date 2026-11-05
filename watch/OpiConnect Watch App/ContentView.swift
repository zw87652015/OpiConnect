import SwiftUI
import StoreKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.paired {
                if model.subscribed {
                    HomeView()
                } else {
                    PaywallView()
                }
            } else {
                PairingView()
            }
        }
        // Re-runs refresh on subscription status changes (e.g. expiry elsewhere);
        // the app-group cache stays the single source of truth for the NSE/widgets.
        .subscriptionStatusTask(for: Subscription.groupID) { _ in
            await model.refreshSubscription()
        }
    }
}

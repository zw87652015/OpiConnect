import SwiftUI
import StoreKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmUnpair = false
    @State private var restoring = false
    @State private var noSubscriptionFound = false
    @StateObject private var link = PhoneLink.shared

    private var calendarText: String {
        guard let cal = model.calendar else { return String(localized: "Never received") }
        let ago = RelativeDateTimeFormatter().localizedString(for: cal.updatedAt, relativeTo: Date())
        return String(localized: "\(cal.events.count) events · \(ago)")
    }

    private var relayURL: String {
        Bundle.main.object(forInfoDictionaryKey: "OpiRelayURL") as? String ?? "-"
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private var subscriptionText: String {
        guard model.subscribed, let expiry = Subscription.cachedExpiry() else {
            return String(localized: "Not subscribed")
        }
        if expiry == .distantFuture { return String(localized: "Active") }
        return String(localized: "Active until \(expiry.formatted(date: .abbreviated, time: .omitted))")
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Pair ID", value: String(PairingKeys.shared.pairId.prefix(8)))
                LabeledContent("Relay", value: relayURL)
                LabeledContent("Version", value: version)
            }
            Section("Subscription") {
                LabeledContent("Status", value: subscriptionText)
                Button("Restore Purchases") {
                    Task {
                        restoring = true
                        defer { restoring = false }
                        try? await AppStore.sync()
                        await model.refreshSubscription()
                        if !model.subscribed { noSubscriptionFound = true }
                    }
                }
                .disabled(restoring)
            }
            Section("Diagnostics") {
                LabeledContent("Link", value: link.status.rawValue)
                LabeledContent("Calendar", value: calendarText)
                LabeledContent("BLE received", value: "\(link.receivedMessages)")
                LabeledContent("BLE dropped", value: "\(link.droppedMessages)")
                LabeledContent("Queued", value: "\(PendingQueue.shared.count)")
            }
            Section {
                Button("Unpair", role: .destructive) { confirmUnpair = true }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Unpair this phone?", isPresented: $confirmUnpair) {
            Button("Unpair", role: .destructive) { model.unpair() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("No active subscription found", isPresented: $noSubscriptionFound) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This Apple Account doesn't have an active OpiLink subscription.")
        }
    }
}

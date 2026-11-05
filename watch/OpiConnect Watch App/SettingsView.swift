import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmUnpair = false
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

    var body: some View {
        List {
            Section {
                LabeledContent("Pair ID", value: String(PairingKeys.shared.pairId.prefix(8)))
                LabeledContent("Relay", value: relayURL)
                LabeledContent("Version", value: version)
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
    }
}

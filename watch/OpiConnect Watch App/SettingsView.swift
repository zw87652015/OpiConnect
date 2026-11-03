import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmUnpair = false

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

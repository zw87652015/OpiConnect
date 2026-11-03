import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var link = PhoneLink.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label(link.status.rawValue, systemImage: "iphone")
                            .font(.caption)
                        Spacer()
                        Image(systemName: model.relayRegistered ? "checkmark.icloud" : "exclamationmark.icloud")
                            .foregroundStyle(model.relayRegistered ? .green : .orange)
                    }
                }
                Section {
                    ForEach(model.items) { item in
                        NavigationLink(value: item.id) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.payload.a).font(.caption2).foregroundStyle(.secondary)
                                Text(item.payload.t).font(.headline).lineLimit(1)
                                Text(item.payload.b).font(.caption).lineLimit(2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("OpiConnect")
            .navigationDestination(for: String.self) { id in
                if let item = model.items.first(where: { $0.id == id }) {
                    DetailView(item: item)
                }
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
            .onChange(of: model.selectedId) { _, id in
                // Tapping a notification opens the detail view.
                if id != nil { /* navigation handled by binding below */ }
            }
            .navigationDestination(isPresented: Binding(
                get: { model.selectedId != nil },
                set: { if !$0 { model.selectedId = nil } })) {
                if let id = model.selectedId,
                   let item = model.items.first(where: { $0.id == id }) {
                    DetailView(item: item)
                }
            }
        }
    }
}

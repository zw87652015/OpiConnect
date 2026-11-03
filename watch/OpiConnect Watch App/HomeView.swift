import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var link = PhoneLink.shared

    var body: some View {
        NavigationStack(path: $model.path) {
            List {
                Section {
                    HStack {
                        Label(link.status.rawValue, systemImage: "iphone")
                            .font(.caption)
                        Spacer()
                        if let s = model.phoneStatus {
                            Label("\(s.bt)%", systemImage: s.bc ? "battery.100.bolt" : "battery.50")
                                .font(.caption)
                                .foregroundStyle(s.bc ? .green : .secondary)
                        }
                        Image(systemName: model.relayRegistered ? "checkmark.icloud" : "exclamationmark.icloud")
                            .foregroundStyle(model.relayRegistered ? .green : .orange)
                    }
                }
                Section {
                    NavigationLink(value: AppModel.Route.findphone) {
                        Label("Find Phone", systemImage: "iphone.radiowaves.left.and.right")
                    }
                    NavigationLink(value: AppModel.Route.music) {
                        Label("Now Playing", systemImage: "music.note")
                    }
                    NavigationLink(value: AppModel.Route.calendar) {
                        Label("Calendar", systemImage: "calendar")
                    }
                }
                Section {
                    ForEach(model.items) { item in
                        NavigationLink(value: AppModel.Route.detail(id: item.id)) {
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
            .navigationDestination(for: AppModel.Route.self) { route in
                switch route {
                case .detail(let id):
                    if let item = model.items.first(where: { $0.id == id }) {
                        DetailView(item: item)
                    } else {
                        Text("Notification gone")
                            .foregroundStyle(.secondary)
                    }
                case .findphone: FindPhoneView()
                case .music: NowPlayingView()
                case .calendar: CalendarView()
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
        }
    }
}

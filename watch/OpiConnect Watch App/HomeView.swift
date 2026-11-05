import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var link = PhoneLink.shared
    @State private var confirmDismissAll = false

    var body: some View {
        NavigationStack(path: $model.path) {
            ScrollViewReader { proxy in
            List {
                Section {
                    HStack {
                        Label(link.status.label, systemImage: "iphone")
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 4)
                        if let s = model.phoneStatus {
                            BatteryRing(level: s.bt, charging: s.bc)
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
                                if let code = OTPDetector.detect(in: item.payload) {
                                    Label(OTPDetector.display(code), systemImage: "key.fill")
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(.green)
                                }
                                Text(item.payload.b).font(.caption).lineLimit(2)
                            }
                        }
                        .id(item.id)
                    }
                    if !model.items.isEmpty {
                        Button(role: .destructive) { confirmDismissAll = true } label: {
                            Label("Dismiss All", systemImage: "xmark.circle")
                        }
                        .id("opi.dismissAll")
                    }
                }
            }
            .onAppear {
                if DemoMode.isActive && DemoMode.route == "notifications",
                   model.items.count > 2 {
                    proxy.scrollTo(model.items[1].id, anchor: .center)
                }
                if DemoMode.isActive && DemoMode.route == "bottom" {
                    proxy.scrollTo("opi.dismissAll", anchor: .bottom)
                }
            }
            }
            .navigationTitle("OpiLink")
            .confirmationDialog("Dismiss all notifications?", isPresented: $confirmDismissAll) {
                Button("Dismiss All", role: .destructive) { model.dismissAll() }
                Button("Cancel", role: .cancel) {}
            }
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
                case .settings: SettingsView()
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

// Phone battery: ring filled to the level, percentage inside; green while charging.
private struct BatteryRing: View {
    let level: Int
    let charging: Bool

    private var color: Color {
        charging ? .green : level <= 20 ? .red : .white
    }

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 2)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(level, 0), 100)) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: "\(level)%")
                .font(.system(size: 7, weight: .semibold).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, 2)
        }
        .frame(width: 24, height: 24)
    }
}

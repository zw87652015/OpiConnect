import SwiftUI
import UserNotifications

struct DetailView: View {
    @EnvironmentObject private var model: AppModel
    let item: NotifItem

    private var payload: NotifPayload { item.payload }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(payload.a).font(.caption2).foregroundStyle(.secondary)
                Text(payload.t).font(.headline)
                Text(payload.b).font(.body)

                if let actions = payload.x, !actions.isEmpty {
                    ForEach(Array(actions.enumerated()), id: \.offset) { idx, action in
                        if action.r {
                            TextFieldLink(prompt: Text("Reply")) {
                                Label(action.l, systemImage: "text.bubble")
                            } onSubmit: { text in
                                sendAction(idx: idx, label: action.l, text: text.isEmpty ? nil : text)
                            }
                        } else {
                            Button(action.l) { sendAction(idx: idx, label: action.l, text: nil) }
                        }
                    }
                }

                Button("Dismiss", role: .destructive) { dismiss() }

                switch model.sendState {
                case .sending: Text("Sending…").font(.caption2).foregroundStyle(.secondary)
                case .sent: Text("Sent").font(.caption2).foregroundStyle(.green)
                case .queued: Text("Will send when phone connects").font(.caption2).foregroundStyle(.orange)
                case .idle: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear {
            model.sendState = .idle
        }
    }

    private func sendAction(idx: Int, label: String, text: String?) {
        PendingQueue.shared.enqueue(.action(id: payload.i, idx: idx, label: label, text: text))
        model.sendState = .sending
        PhoneLink.shared.start(state: "active")
        PhoneLink.shared.flush()
        Task {
            try? await Task.sleep(for: .seconds(20))
            if model.sendState == .sending { model.sendState = .queued }
        }
    }

    private func dismiss() {
        PendingQueue.shared.enqueue(.dismiss(id: payload.i))
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [payload.i])
        model.remove(id: payload.i)
        PhoneLink.shared.flush()
    }
}

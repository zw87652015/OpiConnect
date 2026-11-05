import SwiftUI

struct FindPhoneView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var link = PhoneLink.shared

    private var connected: Bool { link.status == .authenticated }

    var body: some View {
        VStack(spacing: 16) {
            if !connected {
                Text("Connecting to phone…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .onAppear { link.start(state: "active") }
            }
            Button {
                model.ringing.toggle()
                link.send(.findphone(on: model.ringing))
                if !connected { link.start(state: "active") }
            } label: {
                Image(systemName: model.ringing ? "stop.circle.fill" : "iphone.radiowaves.left.and.right")
                    .font(.system(size: 44))
            }
            .buttonStyle(.borderless)
            .disabled(!connected)
            Text(model.ringing ? String(localized: "Phone is ringing") : String(localized: "Ring your phone"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Find Phone")
    }
}

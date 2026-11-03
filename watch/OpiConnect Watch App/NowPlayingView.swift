import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var link = PhoneLink.shared
    @State private var volume: Double = 0
    @State private var crownIdle: DispatchWorkItem?

    private var media: MediaSnapshot? { model.media }

    var body: some View {
        VStack(spacing: 10) {
            if let m = media, m.on {
                if !m.app.isEmpty {
                    Text(m.app).font(.caption2).foregroundStyle(.secondary)
                }
                Text(m.t.isEmpty ? "Unknown track" : m.t)
                    .font(.headline)
                    .lineLimit(2)
                if !m.ar.isEmpty {
                    Text(m.ar).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 24) {
                    Button { send("prev") } label: { Image(systemName: "backward.fill") }
                    Button { send(m.pl ? "pause" : "play") } label: {
                        Image(systemName: m.pl ? "pause.fill" : "play.fill")
                            .font(.title2)
                    }
                    Button { send("next") } label: { Image(systemName: "forward.fill") }
                }
                .buttonStyle(.borderless)
            } else {
                Text("Nothing playing on your phone")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Now Playing")
        .focusable()
        .digitalCrownRotation(
            $volume,
            from: 0, through: 1, by: 0.05,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true,
        )
        .onChange(of: volume) { _, v in
            // Send volume changes debounced at 200 ms.
            crownIdle?.cancel()
            let item = DispatchWorkItem { link.send(.media(cmd: "vol", v: v)) }
            crownIdle = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
        }
        .onAppear {
            link.start(state: "active")
            if let m = media { volume = m.v }
        }
    }

    private func send(_ cmd: String) {
        link.send(.media(cmd: cmd))
        if link.status != .authenticated { link.start(state: "active") }
    }
}

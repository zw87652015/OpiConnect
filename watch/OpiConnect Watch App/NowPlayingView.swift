import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var link = PhoneLink.shared
    @State private var crownOffset = 0.0
    @State private var targetVolume: Double?
    @FocusState private var crownFocused: Bool

    private var media: MediaSnapshot? { model.media }

    var body: some View {
        VStack(spacing: 10) {
            if let m = media, m.on {
                if !m.app.isEmpty {
                    Text(m.app).font(.caption2).foregroundStyle(.secondary)
                }
                Text(m.t.isEmpty ? String(localized: "Unknown track") : m.t)
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
            if link.canAdjustMediaVolume, let media {
                volumeIndicator(media.v)
            }
        }
        .navigationTitle("Now Playing")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($crownFocused)
        .focusEffectDisabled()
        // Keep the system's crown position separate from the phone's volume.
        .digitalCrownRotation($crownOffset, onIdle: { targetVolume = nil })
        .onChange(of: crownOffset) { old, new in
            guard scenePhase == .active, link.canAdjustMediaVolume, let media else { return }
            let baseline = targetVolume ?? media.v
            let volume = min(1, max(0, baseline + (new - old) * 0.05))
            guard volume != baseline else { return }
            targetVolume = volume
            link.sendMediaVolume(volume)
        }
        .onChange(of: link.status) { _, status in
            if status != .authenticated { stopAdjustingVolume() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { stopAdjustingVolume() }
        }
        .onAppear {
            link.start(state: "active")
            crownFocused = true
        }
        .onDisappear { stopAdjustingVolume() }
    }

    private func volumeIndicator(_ volume: Double) -> some View {
        let percent = volume.formatted(.percent.precision(.fractionLength(0)))
        return HStack(spacing: 6) {
            Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
            ProgressView(value: volume)
                .progressViewStyle(.linear)
            Text(verbatim: percent)
                .monospacedDigit()
        }
        .font(.caption2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue(Text(verbatim: percent))
    }

    private func stopAdjustingVolume() {
        targetVolume = nil
        link.cancelPendingMediaVolume()
    }

    private func send(_ cmd: String) {
        link.send(.media(cmd: cmd))
        crownFocused = true // tapping a button can steal crown focus
        if link.status != .authenticated { link.start(state: "active") }
    }
}

import SwiftUI
import QRCodeGenerator

private struct QRCodeView: View {
    let text: String

    private var qr: QRCode? {
        try? QRCode.encode(text: text, ecl: .medium)
    }

    var body: some View {
        if let qr {
            Canvas { context, size in
                let quiet = 2
                let total = qr.size + quiet * 2
                let module = min(size.width, size.height) / CGFloat(total)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                for y in 0..<qr.size {
                    for x in 0..<qr.size where qr.getModule(x: x, y: y) {
                        let rect = CGRect(x: CGFloat(x + quiet) * module,
                                          y: CGFloat(y + quiet) * module,
                                          width: module, height: module)
                        context.fill(Path(rect), with: .color(.black))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .layoutPriority(1)
        }
    }
}

struct PairingView: View {
    static let androidReleasesURL = "https://github.com/zw87652015/OpiConnect/releases"

    @StateObject private var link = PhoneLink.shared
    @State private var path: [Bool] = []

    private var guide: some View {
        VStack(spacing: 2) {
            QRCodeView(text: Self.androidReleasesURL)
            Text("Scan to download OpiLink for your Android phone")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("Get the App")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Next") { path.append(true) }
            }
        }
        .navigationDestination(for: Bool.self) { _ in pairing }
        .onAppear { link.start(state: "active") }
    }

    private var pairing: some View {
        VStack(spacing: 2) {
            QRCodeView(text: PairingKeys.shared.qrString)
            Text("Scan with OpiLink on your Android phone")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(link.status.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("Pair")
        .onAppear { link.start(state: "active") }
    }

    var body: some View {
        NavigationStack(path: $path) { guide }
            .onAppear {
                if DemoMode.isActive && DemoMode.route == "pairing" { path = [true] }
            }
    }
}

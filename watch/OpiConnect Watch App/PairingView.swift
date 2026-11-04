import SwiftUI
import QRCodeGenerator

struct PairingView: View {
    @StateObject private var link = PhoneLink.shared

    private var qr: QRCode? {
        try? QRCode.encode(text: PairingKeys.shared.qrString, ecl: .medium)
    }

    var body: some View {
        VStack(spacing: 8) {
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
                .aspectRatio(1, contentMode: .fit)
            }
            Text("Scan with OpiLink on your Android phone")
                .font(.footnote)
                .multilineTextAlignment(.center)
            Text(link.status.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear { link.start(state: "active") }
    }
}

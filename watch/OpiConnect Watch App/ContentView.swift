import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.paired {
            if model.subscribed {
                HomeView()
            } else {
                PaywallView()
            }
        } else {
            PairingView()
        }
    }
}

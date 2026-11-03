import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.paired {
            HomeView()
        } else {
            PairingView()
        }
    }
}

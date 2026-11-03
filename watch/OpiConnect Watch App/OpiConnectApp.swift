import SwiftUI
import WatchKit

@main
struct OpiConnectApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                PhoneLink.shared.start(state: "active")
                model.reload()
            case .background:
                PhoneLink.shared.goBackground()
                AppDelegate.scheduleNextRefresh()
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(AppDelegate.refreshTaskId)) {
            // Reconnect briefly to flush queued dismiss/action messages.
            if PendingQueue.shared.count > 0 {
                await PhoneLink.shared.start(state: "background")
                try? await Task.sleep(for: .seconds(20))
                await PhoneLink.shared.disconnect()
            }
            await AppDelegate.scheduleNextRefresh()
        }
    }
}

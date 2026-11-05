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
                .onOpenURL { model.open(url: $0) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                PhoneLink.shared.start(state: "active")
                Task { await model.refreshSubscription() }
                // The NSE/AppDelegate may have set the flag while we were suspended.
                if !model.paired && UserDefaults.appGroup.bool(forKey: "opi.paired") { model.paired = true }
                model.reload()
            case .background:
                PhoneLink.shared.goBackground()
                AppDelegate.scheduleNextRefresh()
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(AppDelegate.refreshTaskId)) {
            await model.refreshSubscription()
            // Reconnect when paired: flush queued messages and pick up fresh
            // battery/calendar/media state (welcome + inbound burst, ~3 s quiet).
            if model.paired {
                await PhoneLink.shared.start(state: "background")
                let deadline = Date().addingTimeInterval(20)
                // Wait for the welcome + inbound burst (status/media/cal), then ~3 s of
                // silence with an empty outbound queue, capped at 20 s total.
                while Date() < deadline {
                    if await PhoneLink.shared.status == .authenticated,
                       await PhoneLink.shared.inboundIdle(3),
                       PendingQueue.shared.count == 0 { break }
                    try? await Task.sleep(for: .seconds(0.5))
                }
                await PhoneLink.shared.disconnect()
            }
            await AppDelegate.scheduleNextRefresh()
        }
    }
}

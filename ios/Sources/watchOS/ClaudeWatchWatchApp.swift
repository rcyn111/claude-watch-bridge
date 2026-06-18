import SwiftUI
import WatchConnectivity

@main
struct ClaudeWatchWatchApp: App {
    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .onAppear {
                    _ = WatchWCSessionManager.shared
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        if !WCSession.default.isReachable {
                            WCSession.default.activate()
                        }
                    }
                }
        }
    }
}

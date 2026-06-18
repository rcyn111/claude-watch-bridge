import SwiftUI
import WatchConnectivity

@main
struct ClaudeWatchWatchApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}

class AppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        // Initialize WCSession on app launch
        _ = WatchWCSessionManager.shared
    }

    func applicationDidBecomeActive() {
        // Refresh WCSession state
        let session = WatchWCSessionManager.shared
        if !WCSession.default.isReachable {
            // Try to re-establish
            WCSession.default.activate()
        }
    }
}

import SwiftUI

struct ContentView: View {
    @StateObject private var bridgeClient = BridgeClient()
    @StateObject private var wcSessionManager = WCSessionManager.shared
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(bridgeClient: bridgeClient, wcSessionManager: wcSessionManager)
                .tabItem {
                    Label("Dashboard", systemImage: "rectangle.3.group")
                }
                .tag(0)

            PairingView(bridgeClient: bridgeClient)
                .tabItem {
                    Label("Pairing", systemImage: "link")
                }
                .tag(1)
        }
        .onAppear {
            // Route incoming SSE events to the handler.
            bridgeClient.onEvent = { event in
                Task { @MainActor in
                    await handleEvent(event)
                }
            }

            // Auto-reconnect if we have a saved token and a configured bridge.
            if let token = try? KeychainManager.loadToken() {
                bridgeClient.sessionToken = token
                if bridgeClient.bridgeURL != nil {
                    bridgeClient.startListening()
                }
            }
        }
    }

    @MainActor
    private func handleEvent(_ event: BridgeEvent) async {
        switch event.type {
        case .permissionRequest:
            guard let requestId = event.requestId,
                  let toolName = event.toolName else { break }

            wcSessionManager.lastActivity = "SSE: \(toolName) | WCS: reachable=\(wcSessionManager.isReachable) watch=\(wcSessionManager.isWatchAppInstalled)"
            print("[iOS] SSE event: permission_request | tool=\(toolName) id=\(requestId)")
            print("[iOS] WCSession: activated=\(wcSessionManager.isActivated) reachable=\(wcSessionManager.isReachable) watchInstalled=\(wcSessionManager.isWatchAppInstalled)")

            let request = PermissionRequest(
                id: requestId,
                requestId: requestId,
                toolName: toolName,
                toolInput: event.toolInput ?? [:],
                permissionSuggestions: event.suggestions ?? [],
                timeoutSeconds: 300,
                receivedAt: event.createdAt ?? Date()
            )

            wcSessionManager.pendingRequests.append(request)

            // Forward to Apple Watch if reachable
            if wcSessionManager.isReachable {
                print("[iOS] Sending to watch via WCSession...")
                do {
                    let decision = try await wcSessionManager.sendPermissionRequest(request)
                    print("[iOS] Watch replied: \(decision.behavior.rawValue)")
                    // Submit decision back to bridge
                    try await bridgeClient.submitDecision(decision)
                    // Remove from pending
                    wcSessionManager.pendingRequests.removeAll { $0.requestId == requestId }
                    wcSessionManager.requestHistory.insert(request, at: 0)
                } catch {
                    print("[iOS] sendPermissionRequest error: \(error)")
                }
            }

        case .sessionEnded:
            wcSessionManager.notifySessionEnded()
            wcSessionManager.pendingRequests.removeAll()

        case .heartbeat:
            break

        case .toolUse, .error:
            break
        }
    }
}

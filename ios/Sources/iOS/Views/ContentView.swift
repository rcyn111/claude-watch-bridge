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

            wcSessionManager.lastActivity = "rx: \(toolName) reach=\(wcSessionManager.isReachable)"

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

            if wcSessionManager.isReachable {
                wcSessionManager.lastActivity = "sending to watch..."
                do {
                    let decision = try await wcSessionManager.sendPermissionRequest(request)
                    wcSessionManager.lastActivity = "watch replied: \(decision.behavior.rawValue)"
                    try await bridgeClient.submitDecision(decision)
                    wcSessionManager.pendingRequests.removeAll { $0.requestId == requestId }
                    wcSessionManager.requestHistory.insert(request, at: 0)
                } catch {
                    wcSessionManager.lastActivity = "send err: \(error.localizedDescription.prefix(30))"
                }
            } else {
                wcSessionManager.lastActivity = "NOT reachable, queued"
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

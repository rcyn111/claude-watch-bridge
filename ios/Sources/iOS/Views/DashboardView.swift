import SwiftUI

struct DashboardView: View {
    @ObservedObject var bridgeClient: BridgeClient
    @ObservedObject var wcSessionManager: WCSessionManager

    var body: some View {
        NavigationStack {
            List {
                // Connection status
                Section {
                    StatusRow(
                        title: "Bridge Server",
                        isConnected: bridgeClient.isConnected,
                        detail: bridgeClient.isConnected ? "Connected" : "Disconnected"
                    )
                    StatusRow(
                        title: "Apple Watch",
                        isConnected: wcSessionManager.isReachable,
                        detail: wcSessionManager.isReachable
                            ? "Reachable"
                            : (wcSessionManager.isWatchAppInstalled ? "Not Reachable" : "App Not Installed")
                    )
                } header: {
                    Text("Connection")
                }

                // Last activity
                if wcSessionManager.lastActivity != "—" {
                    Section {
                        HStack {
                            Image(systemName: "arrow.right.circle")
                                .foregroundColor(.blue)
                            Text(wcSessionManager.lastActivity)
                                .font(.subheadline)
                        }
                    } header: {
                        Text("Last Event")
                    }
                }

                // Pending requests
                Section {
                    if wcSessionManager.pendingRequests.isEmpty {
                        HStack {
                            Image(systemName: "bell.slash")
                                .foregroundColor(.secondary)
                            Text("No pending requests")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ForEach(wcSessionManager.pendingRequests) { request in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(request.toolName, systemImage: iconForTool(request.toolName))
                                    .font(.headline)
                                Text(request.toolInputCommand)
                                    .font(.subheadline.monospaced())
                                    .lineLimit(2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Pending Requests")
                }

                // Request history
                if !wcSessionManager.requestHistory.isEmpty {
                    Section {
                        ForEach(wcSessionManager.requestHistory.prefix(20)) { request in
                            HStack {
                                Image(systemName: iconForTool(request.toolName))
                                Text(request.toolName)
                                Spacer()
                                Text(request.toolInputCommand)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    } header: {
                        Text("Recent History")
                    }
                }

                // Actions
                Section {
                    Button(role: .destructive) {
                        bridgeClient.stopListening()
                        KeychainManager.deleteToken()
                        bridgeClient.isConnected = false
                        bridgeClient.sessionToken = nil
                    } label: {
                        Label("Disconnect & Clear Pairing", systemImage: "xmark.circle")
                    }
                }
            }
            .navigationTitle("Claude Watch")
            .refreshable {
                if let healthy = try? await bridgeClient.checkHealth() {
                    bridgeClient.isConnected = healthy
                }
            }
        }
    }

    private func iconForTool(_ toolName: String) -> String {
        switch toolName {
        case "Bash": return "terminal"
        case "Read": return "doc.text"
        case "Write", "Edit": return "pencil"
        case "Agent": return "brain"
        default: return "gearshape"
        }
    }
}

struct StatusRow: View {
    let title: String
    let isConnected: Bool
    let detail: String

    var body: some View {
        HStack {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            Text(title)
                .font(.body)
            Spacer()
            Text(detail)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

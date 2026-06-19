import SwiftUI

struct DashboardView: View {
    @ObservedObject var bridgeClient: BridgeClient
    @ObservedObject var wcSessionManager: WCSessionManager

    var body: some View {
        NavigationStack {
            List {
                // Status section
                Section("Connection Status") {
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
                }

                // Live SSE log (last 20 entries)
                Section("Live Log (SSE)") {
                    ForEach(Array(bridgeClient.sseLog.suffix(20).enumerated()), id: \.offset) { _, msg in
                        Text(msg)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                // Pending requests section
                Section("Pending Requests") {
                    if wcSessionManager.pendingRequests.isEmpty {
                        Text("No pending requests")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(wcSessionManager.pendingRequests) { request in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(request.toolName, systemImage: iconForTool(request.toolName))
                                    .font(.headline)
                                Text(request.toolInputCommand)
                                    .font(.caption.monospaced())
                                    .lineLimit(2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Request history section
                Section("Recent History") {
                    if wcSessionManager.requestHistory.isEmpty {
                        Text("No recent requests")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
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
                    }
                }

                // Actions section
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
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

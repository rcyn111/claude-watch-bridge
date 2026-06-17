import SwiftUI

struct RequestHistoryView: View {
    @ObservedObject var sessionManager = WatchWCSessionManager.shared

    var body: some View {
        List {
            if sessionManager.requestHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No History")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .listRowBackground(Color.clear)
            } else {
                ForEach(sessionManager.requestHistory) { request in
                    HStack {
                        Image(systemName: toolIcon(for: request.toolName))
                            .font(.caption)
                            .foregroundColor(toolColor(for: request.toolName))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(request.toolName)
                                .font(.caption.weight(.medium))
                            Text(request.toolInputCommand)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
    }

    private func toolIcon(for toolName: String) -> String {
        switch toolName {
        case "Bash": return "terminal"
        case "Read": return "doc.text"
        case "Write", "Edit": return "pencil"
        default: return "gearshape"
        }
    }

    private func toolColor(for toolName: String) -> Color {
        switch toolName {
        case "Bash": return .orange
        case "Read": return .blue
        case "Write", "Edit": return .purple
        default: return .gray
        }
    }
}

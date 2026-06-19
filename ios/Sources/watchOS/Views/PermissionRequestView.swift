import SwiftUI

struct PermissionRequestView: View {
    @StateObject private var viewModel = PermissionViewModel()
    @ObservedObject private var sessionManager = WatchWCSessionManager.shared
    @State private var showingDetails = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if viewModel.autoDismissed {
                    autoDismissedView
                } else if let request = sessionManager.pendingRequest {
                    requestContentView(request)
                } else if let lastDecision = viewModel.lastDecision {
                    decisionConfirmationView(lastDecision)
                } else {
                    emptyStateView
                }
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)

            Text("No Pending Requests")
                .font(.headline)

            Text("Waiting for Claude Code permission requests...")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 30)
    }

    // MARK: - Auto Dismissed

    @ViewBuilder
    private var autoDismissedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 36))
                .foregroundColor(.orange)

            Text("Request Expired")
                .font(.headline)

            Text("The permission request timed out while waiting for your response.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 30)
    }

    // MARK: - Decision Confirmation

    @ViewBuilder
    private func decisionConfirmationView(_ decision: DecisionBehavior) -> some View {
        VStack(spacing: 12) {
            Image(systemName: decision == .allow ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(decision == .allow ? .green : .red)

            Text(decision == .allow ? "Approved" : "Denied")
                .font(.headline)

            Text("Tap a new request to respond")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.top, 30)
    }

    // MARK: - Active Request

    @ViewBuilder
    private func requestContentView(_ request: PermissionRequest) -> some View {
        // Tool icon
        toolIconView(for: request.toolName)

        Text("Permission Request")
            .font(.headline)

        // Tool name badge
        Text(request.toolName)
            .font(.caption2)
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(toolColor(for: request.toolName)))

        // Queue count (only visible when more requests are waiting)
        if sessionManager.queueCount > 0 {
            HStack(spacing: 3) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 9))
                Text("+\(sessionManager.queueCount) more")
                    .font(.caption2)
            }
            .foregroundColor(.blue)
            .padding(.vertical, 2)
            .padding(.horizontal, 8)
            .background(
                Capsule().fill(Color.blue.opacity(0.15))
            )
        }

        // Countdown timer
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.system(size: 10))
            Text(viewModel.timeString())
                .font(.caption2.monospacedDigit())
        }
        .foregroundColor(viewModel.isTimeUrgent ? .red : .secondary)
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(
            Capsule()
                .fill(viewModel.isTimeUrgent ? Color.red.opacity(0.15) : Color.gray.opacity(0.15))
        )

        // Command preview
        VStack(alignment: .leading, spacing: 3) {
            Text("Command")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(request.toolInputCommand)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(showingDetails ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.1))
                )
        }

        // Show more / less toggle
        if request.toolInputCommand.count > 80 {
            Button(action: { showingDetails.toggle() }) {
                HStack(spacing: 2) {
                    Text(showingDetails ? "Show Less" : "Show More")
                    Image(systemName: showingDetails ? "chevron.up" : "chevron.down")
                }
                .font(.caption2)
            }
        }

        // Decision buttons
        VStack(spacing: 6) {
            // Approve button
            Button(action: viewModel.approve) {
                HStack(spacing: 4) {
                    if viewModel.isProcessing {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text("Approve")
                        .font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.green.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.green, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isProcessing)

            // Deny button
            Button(action: viewModel.deny) {
                HStack(spacing: 4) {
                    if viewModel.isProcessing {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                    }
                    Text("Deny")
                        .font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.red.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.red, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isProcessing)

            // Approve All button
            Button(action: viewModel.approveAll) {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark.circle")
                        .font(.caption2)
                    Text("Approve All \(request.toolName)")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isProcessing)
        }
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    // MARK: - Helpers

    private func toolIconView(for toolName: String) -> some View {
        let icon = toolIcon(for: toolName)
        return Image(systemName: icon)
            .font(.system(size: 36))
            .foregroundColor(toolColor(for: toolName))
            .padding(.top, 6)
    }

    private func toolIcon(for toolName: String) -> String {
        switch toolName {
        case "Bash": return "terminal"
        case "Read": return "doc.text"
        case "Write": return "square.and.pencil"
        case "Edit": return "pencil"
        case "Agent": return "brain.head.profile"
        case "WebFetch": return "globe"
        case "WebSearch": return "magnifyingglass"
        default: return "gearshape"
        }
    }

    private func toolColor(for toolName: String) -> Color {
        switch toolName {
        case "Bash": return .orange
        case "Read": return .blue
        case "Write", "Edit": return .purple
        case "Agent": return .pink
        case "WebFetch", "WebSearch": return .cyan
        default: return .gray
        }
    }
}

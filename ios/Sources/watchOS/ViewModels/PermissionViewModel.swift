import Foundation
import Combine

@MainActor
class PermissionViewModel: ObservableObject {
    @Published var currentRequest: PermissionRequest?
    @Published var isProcessing = false
    @Published var timeRemaining: TimeInterval = 300
    @Published var autoDismissed = false
    @Published var lastDecision: DecisionBehavior?

    private let sessionManager = WatchWCSessionManager.shared
    private var timer: Timer?
    private var pendingReply: ((PermissionDecision) -> Void)?
    private let hapticManager = HapticManager()

    init() {
        sessionManager.onPermissionRequest = { [weak self] request, reply in
            self?.currentRequest = request
            self?.pendingReply = reply
            self?.isProcessing = false
            self?.autoDismissed = false
            self?.lastDecision = nil
            self?.startCountdown(from: request.timeoutSeconds)
            self?.hapticManager.notifyNewRequest()
        }
    }

    func approve() {
        guard let request = currentRequest, let reply = pendingReply else { return }
        isProcessing = true

        let decision = PermissionDecision(
            requestId: request.requestId,
            behavior: .allow
        )

        hapticManager.feedbackDecision(.allow)
        lastDecision = .allow
        reply(decision)
        clearPending()
    }

    func deny() {
        guard let request = currentRequest, let reply = pendingReply else { return }
        isProcessing = true

        let decision = PermissionDecision(
            requestId: request.requestId,
            behavior: .deny,
            message: "Denied by user on Apple Watch"
        )

        hapticManager.feedbackDecision(.deny)
        lastDecision = .deny
        reply(decision)
        clearPending()
    }

    func approveAll() {
        guard let request = currentRequest, let reply = pendingReply else { return }
        isProcessing = true

        let decision = PermissionDecision(
            requestId: request.requestId,
            behavior: .allow,
            updatedPermissions: [
                PermissionUpdate(
                    type: .addRules,
                    rules: [request.toolName],
                    behavior: "allow",
                    destination: "session"
                )
            ]
        )

        hapticManager.feedbackDecision(.allow)
        lastDecision = .allow
        reply(decision)
        clearPending()
    }

    private func clearPending() {
        currentRequest = nil
        pendingReply = nil
        timer?.invalidate()
        timer = nil
        isProcessing = false
    }

    private func startCountdown(from seconds: Int) {
        timeRemaining = TimeInterval(seconds)
        timer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.timeRemaining -= 1

            // Haptic warning at 30 seconds
            if self.timeRemaining == 30 {
                WKInterfaceDevice.current().play(.directionUp)
            }

            // Auto-dismiss on timeout
            if self.timeRemaining <= 0 {
                self.timer?.invalidate()
                self.autoDismissed = true
                self.clearPending()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func timeString() -> String {
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var isTimeUrgent: Bool {
        timeRemaining < 30
    }
}

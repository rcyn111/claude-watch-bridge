import Foundation
import Combine
import WatchKit

@MainActor
class PermissionViewModel: ObservableObject {
    @Published var currentRequest: PermissionRequest?
    @Published var isProcessing = false
    @Published var timeRemaining: TimeInterval = 300
    @Published var autoDismissed = false
    @Published var lastDecision: DecisionBehavior?

    private let sessionManager = WatchWCSessionManager.shared
    private var timer: Timer?
    private let hapticManager = HapticManager()
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Observe the session-manager's published request. When it changes to
        // a new request (or the next queued request), reset the UI. When it
        // clears, stop the countdown and let the "approved/denied" state show.
        sessionManager.$pendingRequest
            .receive(on: RunLoop.main)
            .sink { [weak self] request in
                guard let self else { return }
                if let request = request {
                    self.currentRequest = request
                    self.isProcessing = false
                    self.autoDismissed = false
                    self.lastDecision = nil
                    self.startCountdown(from: request.timeoutSeconds)
                    self.hapticManager.notifyNewRequest()
                } else {
                    // No request being shown — the queue is drained.
                    self.currentRequest = nil
                    self.timer?.invalidate()
                    self.timer = nil
                    self.isProcessing = false
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Decisions (called from the UI)

    func approve() {
        guard let request = currentRequest, !isProcessing else { return }
        isProcessing = true

        let decision = PermissionDecision(
            requestId: request.requestId,
            behavior: .allow
        )

        hapticManager.feedbackDecision(.allow)
        lastDecision = .allow
        sessionManager.submitDecision(decision)
    }

    func deny() {
        guard let request = currentRequest, !isProcessing else { return }
        isProcessing = true

        let decision = PermissionDecision(
            requestId: request.requestId,
            behavior: .deny,
            message: "Denied by user on Apple Watch"
        )

        hapticManager.feedbackDecision(.deny)
        lastDecision = .deny
        sessionManager.submitDecision(decision)
    }

    func approveAll() {
        guard let request = currentRequest, !isProcessing else { return }
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
        sessionManager.submitDecision(decision)
    }

    // MARK: - Countdown

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

            // Auto-dismiss on timeout — advance the queue so the next request
            // (if any) is shown immediately.
            if self.timeRemaining <= 0 {
                self.timer?.invalidate()
                self.timer = nil
                self.autoDismissed = true
                self.isProcessing = false
                self.sessionManager.timeoutCurrent()
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

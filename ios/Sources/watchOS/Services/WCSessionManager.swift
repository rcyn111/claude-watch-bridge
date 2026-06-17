import Foundation
import WatchConnectivity
import Combine

@MainActor
class WatchWCSessionManager: NSObject, ObservableObject {
    static let shared = WatchWCSessionManager()

    @Published var pendingRequest: PermissionRequest?
    @Published var requestHistory: [PermissionRequest] = []
    @Published var isReachable = false
    @Published var isActivated = false

    /// Callback triggered when a new permission request arrives from the iOS app.
    /// The callback receives the request and a reply handler that must be called with the decision.
    var onPermissionRequest: ((PermissionRequest, @escaping (PermissionDecision) -> Void) -> Void)?

    /// Current pending reply handler (only one request at a time)
    private var pendingReply: (([String: Any]) -> Void)?

    override private init() {
        super.init()
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Submit a decision and invoke the pending reply handler
    func submitDecision(_ decision: PermissionDecision) {
        guard let reply = pendingReply else { return }

        // Convert to WCSession message format
        let message = decision.toWCMessage()
        reply(message)
        pendingReply = nil

        // Move to history
        if let request = pendingRequest {
            requestHistory.insert(request, at: 0)
            if requestHistory.count > 50 {
                requestHistory = Array(requestHistory.prefix(50))
            }
        }
        pendingRequest = nil
    }
}

// MARK: - WCSessionDelegate

extension WatchWCSessionManager: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        Task { @MainActor in
            isActivated = activationState == .activated
            isReachable = session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
        }
    }

    /// Receive message from iPhone — this is where permission requests arrive
    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {

        guard let messageType = message["type"] as? String else {
            replyHandler(["status": "error", "message": "Missing type"])
            return
        }

        switch messageType {
        case "permission_request":
            guard let requestData = try? JSONSerialization.data(withJSONObject: message),
                  let request = try? JSONDecoder().decode(PermissionRequest.self, from: requestData)
            else {
                replyHandler(["status": "error", "message": "Invalid request format"])
                return
            }

            Task { @MainActor in
                self.pendingReply = replyHandler
                self.pendingRequest = request

                // Play haptic feedback to alert the user
                WKInterfaceDevice.current().play(.notification)

                // Notify the view model via callback
                self.onPermissionRequest?(request) { decision in
                    self.submitDecision(decision)
                }
            }

        case "session_ended":
            Task { @MainActor in
                if let reply = self.pendingReply {
                    reply(["status": "error", "message": "Session ended"])
                    self.pendingReply = nil
                }
                self.pendingRequest = nil
            }

        default:
            replyHandler(["status": "ok"])
        }
    }

    /// Receive message without reply (fire and forget)
    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any]) {
        // Handle background messages
        if let messageType = message["type"] as? String {
            switch messageType {
            case "session_ended":
                Task { @MainActor in
                    self.pendingRequest = nil
                }
            default:
                break
            }
        }
    }
}

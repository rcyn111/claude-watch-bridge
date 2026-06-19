import Foundation
import WatchConnectivity
import WatchKit
import Combine

@MainActor
class WatchWCSessionManager: NSObject, ObservableObject {
    static let shared = WatchWCSessionManager()

    @Published var pendingRequest: PermissionRequest?
    @Published var requestHistory: [PermissionRequest] = []
    @Published var isReachable = false
    @Published var isActivated = false
    /// Number of additional requests waiting in the queue (shown as a badge).
    @Published var queueCount: Int = 0

    /// Callback triggered when a new permission request needs to be shown.
    /// Receives the request and a reply handler that the caller MUST call with
    /// the decision.  The reply handler internally manages the queue — after
    /// replying, the next queued request (if any) is automatically shown via
    /// this same callback.
    var onPermissionRequest: ((PermissionRequest, @escaping (PermissionDecision) -> Void) -> Void)?

    /// --- Queue internals -------------------------------------------------
    private var requestQueue: [(PermissionRequest, ([String: Any]) -> Void)] = []
    private var currentReply: (([String: Any]) -> Void)?

    override private init() {
        super.init()
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Call this from the ViewModel when the user approves or denies.
    func submitDecision(_ decision: PermissionDecision) {
        guard let reply = currentReply else { return }
        let message = decision.toWCMessage()
        reply(message)
        currentReply = nil

        // Move to history
        if let request = pendingRequest {
            requestHistory.insert(request, at: 0)
            if requestHistory.count > 50 {
                requestHistory = Array(requestHistory.prefix(50))
            }
        }
        pendingRequest = nil

        // Show next queued request, if any.
        showNext()
    }

    /// Call this when the current request times out on the watch (auto-dismiss).
    /// The iOS side will eventually time out on its own; we abandon the reply
    /// handler and move on to the next queued request.
    func timeoutCurrent() {
        currentReply = nil
        pendingRequest = nil
        showNext()
    }

    /// Dequeue the next pending request and present it.
    private func showNext() {
        guard !requestQueue.isEmpty else {
            queueCount = 0
            return
        }
        let (request, replyHandler) = requestQueue.removeFirst()
        queueCount = requestQueue.count
        pendingRequest = request
        currentReply = replyHandler
        WKInterfaceDevice.current().play(.notification)
        onPermissionRequest?(request) { [weak self] decision in
            self?.submitDecision(decision)
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchWCSessionManager: @preconcurrency WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        print("[Watch] WCSession activation: state=\(activationState.rawValue) reachable=\(session.isReachable) error=\(error?.localizedDescription ?? "nil")")
        Task { @MainActor in
            isActivated = activationState == .activated
            isReachable = session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("[Watch] WCSession reachability changed: \(session.isReachable)")
        Task { @MainActor in
            isReachable = session.isReachable
        }
    }

    /// Receive message from iPhone — this is where permission requests arrive.
    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {

        print("[Watch] didReceiveMessage type=\(message["type"] ?? "nil") keys=\(message.keys.sorted().joined(separator: ","))")

        guard let messageType = message["type"] as? String else {
            print("[Watch] ERROR: missing type in message")
            replyHandler(["status": "error", "message": "Missing type"])
            return
        }

        switch messageType {
        case "permission_request":
            guard let requestData = try? JSONSerialization.data(withJSONObject: message),
                  let request = try? JSONDecoder().decode(PermissionRequest.self, from: requestData)
            else {
                print("[Watch] ERROR: failed to decode PermissionRequest from message")
                replyHandler(["status": "error", "message": "Invalid request format"])
                return
            }

            print("[Watch] decoded request: tool=\(request.toolName) id=\(request.requestId)")

            Task { @MainActor in
                let cbState = self.onPermissionRequest != nil ? "set" : "nil"
                print("[Watch] setting pendingRequest, onPermissionRequest=\(cbState)")
                if self.pendingRequest != nil {
                    // Another request is already being decided — enqueue.
                    self.requestQueue.append((request, replyHandler))
                    self.queueCount = self.requestQueue.count
                    print("[Watch] queued (queueCount=\(self.queueCount))")
                } else {
                    // Show immediately.
                    self.currentReply = replyHandler
                    self.pendingRequest = request
                    self.queueCount = 0
                    print("[Watch] showing immediately, playing haptic")
                    WKInterfaceDevice.current().play(.notification)
                    self.onPermissionRequest?(request) { decision in
                        self.submitDecision(decision)
                    }
                }
            }

        case "session_ended":
            Task { @MainActor in
                // Cancel the current request and drain the queue.
                if let reply = self.currentReply {
                    reply(["status": "error", "message": "Session ended"])
                    self.currentReply = nil
                }
                self.requestQueue.removeAll()
                self.queueCount = 0
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
                    self.currentReply = nil
                    self.requestQueue.removeAll()
                    self.queueCount = 0
                    self.pendingRequest = nil
                }
            default:
                break
            }
        }
    }
}

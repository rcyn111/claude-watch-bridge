import Foundation
import WatchConnectivity
import Combine

enum WCSessionError: LocalizedError {
    case notReachable
    case notInstalled
    case activationFailed

    var errorDescription: String? {
        switch self {
        case .notReachable: return "Apple Watch is not reachable"
        case .notInstalled: return "Apple Watch app is not installed"
        case .activationFailed: return "WCSession activation failed"
        }
    }
}

@MainActor
class WCSessionManager: NSObject, ObservableObject {
    static let shared = WCSessionManager()

    @Published var isReachable = false
    @Published var isWatchAppInstalled = false
    @Published var isActivated = false
    @Published var pendingRequests: [PermissionRequest] = []
    @Published var requestHistory: [PermissionRequest] = []

    var onPermissionRequest: ((PermissionRequest, @escaping (PermissionDecision) -> Void) -> Void)?

    override private init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Send a permission request to the Apple Watch and await a decision
    func sendPermissionRequest(_ request: PermissionRequest) async throws -> PermissionDecision {
        guard WCSession.default.isWatchAppInstalled else {
            throw WCSessionError.notInstalled
        }
        guard WCSession.default.isReachable else {
            throw WCSessionError.notReachable
        }
        guard isActivated else {
            throw WCSessionError.activationFailed
        }

        let message = request.toWCMessage()

        return try await withCheckedThrowingContinuation { continuation in
            WCSession.default.sendMessage(message, replyHandler: { response in
                do {
                    let decision = try PermissionDecision.fromWCMessage(response)
                    continuation.resume(returning: decision)
                } catch {
                    continuation.resume(throwing: error)
                }
            }, errorHandler: { error in
                continuation.resume(throwing: error)
            })
        }
    }

    /// Send a message to the Watch (fire and forget)
    func sendBackgroundMessage(_ message: [String: Any]) {
        guard WCSession.default.isWatchAppInstalled else { return }

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil)
        } else {
            // Use transferUserInfo for background delivery
            WCSession.default.transferUserInfo(message)
        }
    }

    /// Notify Watch that Claude session ended
    func notifySessionEnded() {
        sendBackgroundMessage(["type": "session_ended"])
    }
}

// MARK: - WCSessionDelegate

extension WCSessionManager: @preconcurrency WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        print("[iOS] WCSession activation: state=\(activationState.rawValue) reachable=\(session.isReachable) watchInstalled=\(session.isWatchAppInstalled) error=\(error?.localizedDescription ?? "nil")")
        Task { @MainActor in
            isActivated = activationState == .activated
            isWatchAppInstalled = session.isWatchAppInstalled
            isReachable = session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("[iOS] WCSession reachability changed: \(session.isReachable)")
        Task { @MainActor in
            isReachable = session.isReachable
        }
    }

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        // Handle messages from Watch (e.g., decision responses)
        guard let messageType = message["type"] as? String else { return }

        switch messageType {
        case "permission_decision":
            if let decisionData = try? JSONSerialization.data(withJSONObject: message),
               let decision = try? JSONDecoder().decode(PermissionDecision.self, from: decisionData) {
                replyHandler(["status": "received"])
            }
        default:
            break
        }
    }

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any]) {
        // Handle incoming messages without reply (e.g., ping)
    }

    // iOS delegate methods (not used on watchOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}

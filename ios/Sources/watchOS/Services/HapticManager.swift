import WatchKit

struct HapticManager {
    func notifyNewRequest() {
        WKInterfaceDevice.current().play(.notification)
    }

    func feedbackDecision(_ behavior: DecisionBehavior) {
        switch behavior {
        case .allow:
            WKInterfaceDevice.current().play(.success)
        case .deny:
            WKInterfaceDevice.current().play(.failure)
        }
    }

    func buttonTap() {
        WKInterfaceDevice.current().play(.click)
    }
}

import Foundation

enum DecisionBehavior: String, Codable {
    case allow
    case deny
}

struct PermissionDecision: Codable {
    let requestId: String
    let behavior: DecisionBehavior
    let updatedInput: [String: String]?
    let updatedPermissions: [PermissionUpdate]?
    let message: String?
    let interrupt: Bool?
    let timestamp: Date

    init(
        requestId: String,
        behavior: DecisionBehavior,
        updatedInput: [String: String]? = nil,
        updatedPermissions: [PermissionUpdate]? = nil,
        message: String? = nil,
        interrupt: Bool? = nil,
        timestamp: Date = Date()
    ) {
        self.requestId = requestId
        self.behavior = behavior
        self.updatedInput = updatedInput
        self.updatedPermissions = updatedPermissions
        self.message = message
        self.interrupt = interrupt
        self.timestamp = timestamp
    }

    func toWCMessage() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict
    }

    static func fromWCMessage(_ dict: [String: Any]) throws -> PermissionDecision {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(PermissionDecision.self, from: data)
    }
}

struct PermissionUpdate: Codable {
    let type: PermissionUpdateType
    let rules: [String]
    let behavior: String
    let destination: String
}

enum PermissionUpdateType: String, Codable {
    case addRules
    case replaceRules
    case removeRules
}

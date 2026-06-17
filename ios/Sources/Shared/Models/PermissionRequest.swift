import Foundation

struct PermissionRequest: Codable, Identifiable, Equatable {
    let id: String
    let requestId: String
    let toolName: String
    let toolInput: [String: String]
    let permissionSuggestions: [PermissionSuggestion]
    let timeoutSeconds: Int
    let receivedAt: Date

    var toolInputCommand: String {
        if let cmd = toolInput["command"] { return cmd }
        if let path = toolInput["file_path"] { return path }
        return toolInput.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
    }
}

struct PermissionSuggestion: Codable, Equatable {
    let type: String
    let rules: [String]
    let behavior: String
    let destination: String
}

// MARK: - WCSession Message Serialization

extension PermissionRequest {
    func toWCMessage() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }

        var message = dict
        message["type"] = "permission_request"
        return message
    }

    static func fromWCMessage(_ dict: [String: Any]) throws -> PermissionRequest {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(PermissionRequest.self, from: data)
    }
}

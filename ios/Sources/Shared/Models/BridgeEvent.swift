import Foundation

struct BridgeEvent: Codable, Identifiable {
    var id: String { requestId ?? UUID().uuidString }

    let type: BridgeEventType
    let requestId: String?
    let toolName: String?
    let toolInput: [String: String]?
    let suggestions: [PermissionSuggestion]?
    let deadline: Date?
    let status: String?
    let message: String?
    let createdAt: Date?

    enum BridgeEventType: String, Codable {
        case permissionRequest = "permission_request"
        case toolUse = "tool_use"
        case sessionEnded = "session_ended"
        case heartbeat
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(BridgeEventType.self, forKey: .type)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        toolInput = try container.decodeIfPresent([String: String].self, forKey: .toolInput)
        suggestions = try container.decodeIfPresent([PermissionSuggestion].self, forKey: .suggestions)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        message = try container.decodeIfPresent(String.self, forKey: .message)

        if let deadlineStr = try container.decodeIfPresent(String.self, forKey: .deadline) {
            deadline = ISO8601DateFormatter().date(from: deadlineStr)
        } else {
            deadline = nil
        }

        if let createdAtStr = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = ISO8601DateFormatter().date(from: createdAtStr)
        } else {
            createdAt = nil
        }
    }
}

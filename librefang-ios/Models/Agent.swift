import Foundation

nonisolated struct Agent: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let state: String
    let mode: String
    let createdAt: String?
    let lastActive: String?
    let modelProvider: String?
    let modelName: String?
    let modelTier: String?
    let authStatus: String?
    let ready: Bool
    let profile: String?
    let identity: AgentIdentity?

    enum CodingKeys: String, CodingKey {
        case id, name, state, mode, ready, profile, identity
        case createdAt = "created_at"
        case lastActive = "last_active"
        case modelProvider = "model_provider"
        case modelName = "model_name"
        case modelTier = "model_tier"
        case authStatus = "auth_status"
    }

    var isRunning: Bool { state == "Running" }
    var stateColor: String {
        switch state {
        case "Running": return "green"
        case "Suspended": return "yellow"
        case "Terminated": return "red"
        default: return "gray"
        }
    }
}

nonisolated struct AgentIdentity: Codable, Sendable {
    let emoji: String?
    let avatarUrl: String?
    let color: String?

    enum CodingKeys: String, CodingKey {
        case emoji, color
        case avatarUrl = "avatar_url"
    }
}

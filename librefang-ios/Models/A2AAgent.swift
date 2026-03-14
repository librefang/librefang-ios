import Foundation

nonisolated struct A2AAgentList: Codable, Sendable {
    let agents: [A2AAgent]
    let total: Int
}

nonisolated struct A2AAgent: Codable, Identifiable, Sendable {
    let name: String
    let description: String?
    let url: String
    let version: String?
    let capabilities: A2ACapabilities?
    let skills: [A2ASkill]?

    var id: String { url }
}

nonisolated struct A2ACapabilities: Codable, Sendable {
    let streaming: Bool?
    let pushNotifications: Bool?
    let stateTransitionHistory: Bool?

    enum CodingKeys: String, CodingKey {
        case streaming
        case pushNotifications = "push_notifications"
        case stateTransitionHistory = "state_transition_history"
    }
}

nonisolated struct A2ASkill: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String?
    let tags: [String]?
}

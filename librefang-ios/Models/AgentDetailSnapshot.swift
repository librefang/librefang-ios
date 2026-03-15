import Foundation

nonisolated struct AgentDetailSnapshot: Codable, Sendable {
    let id: String
    let name: String
    let description: String
    let tags: [String]
    let model: AgentSnapshotModel
    let capabilities: AgentManifestCapabilitySnapshot
    let fallbackModels: [AgentFallbackModel]

    enum CodingKeys: String, CodingKey {
        case id, name, description, tags, model, capabilities
        case fallbackModels = "fallback_models"
    }
}

nonisolated struct AgentSnapshotModel: Codable, Sendable {
    let provider: String
    let model: String
}

nonisolated struct AgentManifestCapabilitySnapshot: Codable, Sendable {
    let tools: [String]
    let network: [String]
}

nonisolated struct AgentFallbackModel: Codable, Sendable, Hashable {
    let provider: String
    let model: String
    let apiKeyEnv: String?
    let baseURL: String?

    enum CodingKeys: String, CodingKey {
        case provider, model
        case apiKeyEnv = "api_key_env"
        case baseURL = "base_url"
    }

    var id: String {
        "\(provider)/\(model)"
    }
}

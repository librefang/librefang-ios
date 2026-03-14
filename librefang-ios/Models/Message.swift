import Foundation

nonisolated struct MessageRequest: Codable, Sendable {
    let message: String
}

nonisolated struct MessageResponse: Codable, Sendable {
    let response: String
    let inputTokens: Int?
    let outputTokens: Int?
    let iterations: Int?
    let costUsd: Double?

    enum CodingKeys: String, CodingKey {
        case response, iterations
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case costUsd = "cost_usd"
    }
}

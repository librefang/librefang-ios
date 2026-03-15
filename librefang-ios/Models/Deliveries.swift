import Foundation

nonisolated struct AgentDeliveryReceiptResponse: Codable, Sendable {
    let agentId: String
    let count: Int
    let receipts: [DeliveryReceipt]

    enum CodingKeys: String, CodingKey {
        case count, receipts
        case agentId = "agent_id"
    }
}

nonisolated struct DeliveryReceipt: Codable, Identifiable, Sendable, Hashable {
    let messageId: String
    let channel: String
    let recipient: String
    let status: DeliveryStatus
    let timestamp: String
    let error: String?

    var id: String { "\(messageId)-\(timestamp)" }

    enum CodingKeys: String, CodingKey {
        case channel, recipient, status, timestamp, error
        case messageId = "message_id"
    }
}

nonisolated enum DeliveryStatus: String, Codable, Sendable, Hashable {
    case sent
    case delivered
    case failed
    case bestEffort = "best_effort"

    var label: String {
        switch self {
        case .sent:
            return "Sent"
        case .delivered:
            return "Delivered"
        case .failed:
            return "Failed"
        case .bestEffort:
            return "Best Effort"
        }
    }
}

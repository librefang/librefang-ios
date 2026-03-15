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

extension DeliveryReceipt {
    var localizedChannelLabel: String {
        switch channel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "email":
            return String(localized: "Email")
        case "sms":
            return String(localized: "SMS")
        case "push":
            return String(localized: "Push")
        case "webhook":
            return String(localized: "Webhook")
        default:
            return channel.replacingOccurrences(of: "_", with: " ").capitalized
        }
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
            return String(localized: "Sent")
        case .delivered:
            return String(localized: "Delivered")
        case .failed:
            return String(localized: "Failed")
        case .bestEffort:
            return String(localized: "Best Effort")
        }
    }

    var tone: PresentationTone {
        switch self {
        case .delivered:
            return .positive
        case .failed:
            return .critical
        case .bestEffort:
            return .warning
        case .sent:
            return .caution
        }
    }
}

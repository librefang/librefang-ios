import Foundation

nonisolated struct CommsTopology: Codable, Sendable {
    let nodes: [CommsNode]
    let edges: [CommsEdge]
}

nonisolated struct CommsNode: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let state: String
    let model: String
}

nonisolated struct CommsEdge: Codable, Identifiable, Sendable {
    let from: String
    let to: String
    let kind: CommsEdgeKind

    var id: String { "\(from)->\(to):\(kind.rawValue)" }
}

nonisolated enum CommsEdgeKind: String, Codable, Sendable {
    case parentChild = "parent_child"
    case peer
}

nonisolated struct CommsEvent: Codable, Identifiable, Sendable {
    let id: String
    let timestamp: String
    let kind: CommsEventKind
    let sourceID: String
    let sourceName: String
    let targetID: String
    let targetName: String
    let detail: String

    enum CodingKeys: String, CodingKey {
        case id, timestamp, kind, detail
        case sourceID = "source_id"
        case sourceName = "source_name"
        case targetID = "target_id"
        case targetName = "target_name"
    }
}

nonisolated enum CommsEventKind: String, Codable, Sendable, CaseIterable {
    case agentMessage = "agent_message"
    case agentSpawned = "agent_spawned"
    case agentTerminated = "agent_terminated"
    case taskPosted = "task_posted"
    case taskClaimed = "task_claimed"
    case taskCompleted = "task_completed"

    var label: String {
        switch self {
        case .agentMessage:
            "Message"
        case .agentSpawned:
            "Spawned"
        case .agentTerminated:
            "Terminated"
        case .taskPosted:
            "Task Posted"
        case .taskClaimed:
            "Task Claimed"
        case .taskCompleted:
            "Task Completed"
        }
    }

    var symbolName: String {
        switch self {
        case .agentMessage:
            "arrow.left.arrow.right.circle"
        case .agentSpawned:
            "plus.circle"
        case .agentTerminated:
            "minus.circle"
        case .taskPosted:
            "tray.and.arrow.up"
        case .taskClaimed:
            "hand.raised.circle"
        case .taskCompleted:
            "checkmark.circle"
        }
    }
}

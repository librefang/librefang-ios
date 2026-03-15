import Foundation

nonisolated enum JSONValue: Codable, Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
}

nonisolated struct WorkflowSummary: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let steps: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case steps
        case createdAt = "created_at"
    }
}

nonisolated enum WorkflowRunState: String, Codable, Sendable, CaseIterable {
    case pending
    case running
    case completed
    case failed

    var label: String {
        switch self {
        case .pending:
            String(localized: "Pending")
        case .running:
            String(localized: "Running")
        case .completed:
            String(localized: "Completed")
        case .failed:
            String(localized: "Failed")
        }
    }
}

nonisolated struct WorkflowRun: Codable, Identifiable, Sendable {
    let id: String
    let workflowName: String
    let state: WorkflowRunState
    let stepsCompleted: Int
    let startedAt: String
    let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case workflowName = "workflow_name"
        case state
        case stepsCompleted = "steps_completed"
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }
}

nonisolated struct TriggerDefinition: Codable, Identifiable, Sendable {
    let id: String
    let agentId: String
    let pattern: JSONValue
    let promptTemplate: String
    let enabled: Bool
    let fireCount: Int
    let maxFires: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case agentId = "agent_id"
        case pattern
        case promptTemplate = "prompt_template"
        case enabled
        case fireCount = "fire_count"
        case maxFires = "max_fires"
        case createdAt = "created_at"
    }

    var isExhausted: Bool {
        maxFires > 0 && fireCount >= maxFires
    }

    var patternSummary: String {
        if let raw = pattern.stringValue {
            return friendlyTriggerLabel(kind: raw, payload: nil)
        }

        if let object = pattern.objectValue, let entry = object.first {
            return friendlyTriggerLabel(kind: entry.key, payload: entry.value)
        }

        return String(localized: "Custom trigger")
    }

    private func friendlyTriggerLabel(kind: String, payload: JSONValue?) -> String {
        switch kind {
        case "lifecycle":
            return String(localized: "Lifecycle events")
        case "agent_spawned":
            if let namePattern = payload?.objectValue?["name_pattern"]?.stringValue, !namePattern.isEmpty {
                return String(localized: "Agent spawned · \(namePattern)")
            }
            return String(localized: "Agent spawned")
        case "agent_terminated":
            return String(localized: "Agent terminated")
        case "system":
            return String(localized: "System events")
        case "system_keyword":
            if let keyword = payload?.objectValue?["keyword"]?.stringValue, !keyword.isEmpty {
                return String(localized: "System keyword · \(keyword)")
            }
            return String(localized: "System keyword")
        case "memory_update":
            return String(localized: "Memory updates")
        case "memory_key_pattern":
            if let keyPattern = payload?.objectValue?["key_pattern"]?.stringValue, !keyPattern.isEmpty {
                return String(localized: "Memory key · \(keyPattern)")
            }
            return String(localized: "Memory key pattern")
        case "all":
            return String(localized: "All events")
        case "content_match":
            if let substring = payload?.objectValue?["substring"]?.stringValue, !substring.isEmpty {
                return String(localized: "Content match · \(substring)")
            }
            return String(localized: "Content match")
        default:
            return kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

nonisolated struct ScheduleListResponse: Codable, Sendable {
    let schedules: [ScheduleEntry]
    let total: Int
}

nonisolated struct ScheduleEntry: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let cron: String
    let agentId: String
    let message: String
    let enabled: Bool
    let createdAt: String
    let lastRun: String?
    let runCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case cron
        case agentId = "agent_id"
        case message
        case enabled
        case createdAt = "created_at"
        case lastRun = "last_run"
        case runCount = "run_count"
    }
}

nonisolated struct CronJobListResponse: Codable, Sendable {
    let jobs: [CronJob]
    let total: Int
}

nonisolated enum CronScheduleKind: String, Codable, Sendable {
    case at
    case every
    case cron
}

nonisolated struct CronScheduleDescriptor: Codable, Sendable {
    let kind: CronScheduleKind
    let at: String?
    let everySecs: Int?
    let expr: String?
    let tz: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case at
        case everySecs = "every_secs"
        case expr
        case tz
    }
}

nonisolated enum CronActionKind: String, Codable, Sendable {
    case systemEvent = "system_event"
    case agentTurn = "agent_turn"
}

nonisolated struct CronActionDescriptor: Codable, Sendable {
    let kind: CronActionKind
    let text: String?
    let message: String?
    let modelOverride: String?
    let timeoutSecs: Int?

    enum CodingKeys: String, CodingKey {
        case kind
        case text
        case message
        case modelOverride = "model_override"
        case timeoutSecs = "timeout_secs"
    }
}

nonisolated enum CronDeliveryKind: String, Codable, Sendable {
    case none
    case channel
    case lastChannel = "last_channel"
    case webhook
}

nonisolated struct CronDeliveryDescriptor: Codable, Sendable {
    let kind: CronDeliveryKind
    let channel: String?
    let to: String?
    let url: String?
}

nonisolated struct CronJob: Codable, Identifiable, Sendable {
    let id: String
    let agentId: String
    let name: String
    let enabled: Bool
    let schedule: CronScheduleDescriptor
    let action: CronActionDescriptor
    let delivery: CronDeliveryDescriptor
    let createdAt: String
    let lastRun: String?
    let nextRun: String?

    enum CodingKeys: String, CodingKey {
        case id
        case agentId = "agent_id"
        case name
        case enabled
        case schedule
        case action
        case delivery
        case createdAt = "created_at"
        case lastRun = "last_run"
        case nextRun = "next_run"
    }
}

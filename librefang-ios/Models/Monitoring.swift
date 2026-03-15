import Foundation

nonisolated struct SystemStatus: Codable, Sendable {
    let status: String
    let version: String
    let agentCount: Int
    let defaultProvider: String
    let defaultModel: String
    let uptimeSeconds: Int
    let apiListen: String
    let homeDir: String
    let logLevel: String
    let networkEnabled: Bool
    let agents: [SystemStatusAgent]

    enum CodingKeys: String, CodingKey {
        case status, version, agents
        case agentCount = "agent_count"
        case defaultProvider = "default_provider"
        case defaultModel = "default_model"
        case uptimeSeconds = "uptime_seconds"
        case apiListen = "api_listen"
        case homeDir = "home_dir"
        case logLevel = "log_level"
        case networkEnabled = "network_enabled"
    }
}

nonisolated struct SystemStatusAgent: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let state: String
    let mode: String
    let createdAt: String?
    let modelProvider: String?
    let modelName: String?
    let profile: String?

    enum CodingKeys: String, CodingKey {
        case id, name, state, mode, profile
        case createdAt = "created_at"
        case modelProvider = "model_provider"
        case modelName = "model_name"
    }
}

nonisolated struct UsageSummary: Codable, Sendable {
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let totalCostUsd: Double
    let callCount: Int
    let totalToolCalls: Int

    enum CodingKeys: String, CodingKey {
        case totalInputTokens = "total_input_tokens"
        case totalOutputTokens = "total_output_tokens"
        case totalCostUsd = "total_cost_usd"
        case callCount = "call_count"
        case totalToolCalls = "total_tool_calls"
    }
}

nonisolated struct UsageByModelResponse: Codable, Sendable {
    let models: [ModelUsage]
}

nonisolated struct ModelUsage: Codable, Identifiable, Sendable {
    let model: String
    let totalCostUsd: Double
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let callCount: Int

    var id: String { model }

    enum CodingKeys: String, CodingKey {
        case model
        case totalCostUsd = "total_cost_usd"
        case totalInputTokens = "total_input_tokens"
        case totalOutputTokens = "total_output_tokens"
        case callCount = "call_count"
    }

    var totalTokens: Int { totalInputTokens + totalOutputTokens }
}

nonisolated struct UsageDailyResponse: Codable, Sendable {
    let days: [DailyUsage]
    let todayCostUsd: Double
    let firstEventDate: String?

    enum CodingKeys: String, CodingKey {
        case days
        case todayCostUsd = "today_cost_usd"
        case firstEventDate = "first_event_date"
    }
}

nonisolated struct DailyUsage: Codable, Identifiable, Sendable {
    let date: String
    let costUsd: Double
    let tokens: Int
    let calls: Int

    var id: String { date }

    enum CodingKeys: String, CodingKey {
        case date, tokens, calls
        case costUsd = "cost_usd"
    }
}

nonisolated struct ProviderList: Codable, Sendable {
    let providers: [ProviderStatus]
    let total: Int
}

nonisolated struct ProviderStatus: Codable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let authStatus: String
    let modelCount: Int
    let keyRequired: Bool
    let apiKeyEnv: String?
    let baseURL: String?
    let isLocal: Bool?
    let reachable: Bool?
    let latencyMs: Int?
    let discoveredModels: [String]?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case authStatus = "auth_status"
        case modelCount = "model_count"
        case keyRequired = "key_required"
        case apiKeyEnv = "api_key_env"
        case baseURL = "base_url"
        case isLocal = "is_local"
        case reachable
        case latencyMs = "latency_ms"
        case discoveredModels = "discovered_models"
        case error
    }

    var isConfigured: Bool {
        authStatus == "configured"
    }
}

nonisolated struct ChannelList: Codable, Sendable {
    let channels: [ChannelStatus]
    let total: Int
    let configuredCount: Int

    enum CodingKeys: String, CodingKey {
        case channels, total
        case configuredCount = "configured_count"
    }
}

nonisolated struct ChannelStatus: Codable, Identifiable, Sendable {
    let name: String
    let displayName: String
    let icon: String
    let description: String
    let category: String
    let difficulty: String
    let setupTime: String
    let quickSetup: Bool
    let setupType: String
    let configured: Bool
    let hasToken: Bool
    let fields: [ChannelConfigField]?
    let setupSteps: [String]?
    let configTemplate: String?

    enum CodingKeys: String, CodingKey {
        case name, icon, description, category, difficulty, configured
        case displayName = "display_name"
        case setupTime = "setup_time"
        case quickSetup = "quick_setup"
        case setupType = "setup_type"
        case hasToken = "has_token"
        case fields
        case setupSteps = "setup_steps"
        case configTemplate = "config_template"
    }

    var id: String { name }
}

nonisolated struct ChannelConfigField: Codable, Identifiable, Sendable {
    let key: String
    let label: String
    let type: String
    let envVar: String?
    let required: Bool
    let hasValue: Bool
    let placeholder: String?
    let advanced: Bool

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label, type, required, advanced
        case envVar = "env_var"
        case hasValue = "has_value"
        case placeholder
    }
}

nonisolated struct CatalogModelListResponse: Codable, Sendable {
    let models: [CatalogModel]
    let total: Int
    let available: Int
}

nonisolated struct CatalogModel: Codable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let provider: String
    let tier: String
    let contextWindow: Int?
    let maxOutputTokens: Int?
    let inputCostPerM: Double?
    let outputCostPerM: Double?
    let supportsTools: Bool
    let supportsVision: Bool
    let supportsStreaming: Bool
    let available: Bool

    enum CodingKeys: String, CodingKey {
        case id, provider, tier, available
        case displayName = "display_name"
        case contextWindow = "context_window"
        case maxOutputTokens = "max_output_tokens"
        case inputCostPerM = "input_cost_per_m"
        case outputCostPerM = "output_cost_per_m"
        case supportsTools = "supports_tools"
        case supportsVision = "supports_vision"
        case supportsStreaming = "supports_streaming"
    }
}

nonisolated struct ModelAliasListResponse: Codable, Sendable {
    let aliases: [ModelAliasEntry]
    let total: Int
}

nonisolated struct ModelAliasEntry: Codable, Identifiable, Sendable {
    let alias: String
    let modelId: String

    var id: String { alias }

    enum CodingKeys: String, CodingKey {
        case alias
        case modelId = "model_id"
    }
}

nonisolated struct CatalogStatusResponse: Codable, Sendable {
    let lastSync: String?

    enum CodingKeys: String, CodingKey {
        case lastSync = "last_sync"
    }
}

nonisolated struct IntegrationProbeResult: Codable, Sendable {
    let status: String
    let provider: String?
    let message: String?
    let error: String?
    let note: String?
    let latencyMs: Int?
    let discoveredModels: [String]?

    enum CodingKeys: String, CodingKey {
        case status, provider, message, error, note
        case latencyMs = "latency_ms"
        case discoveredModels = "discovered_models"
    }

    var isHealthy: Bool {
        status.lowercased() == "ok"
    }
}

nonisolated struct HandCatalog: Codable, Sendable {
    let hands: [HandDefinition]
    let total: Int
}

nonisolated struct HandDefinition: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let category: String
    let icon: String
    let tools: [String]
    let requirementsMet: Bool
    let active: Bool
    let degraded: Bool
    let requirements: [HandRequirement]
    let dashboardMetrics: Int
    let hasSettings: Bool
    let settingsCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, description, category, icon, tools, active, degraded, requirements
        case requirementsMet = "requirements_met"
        case dashboardMetrics = "dashboard_metrics"
        case hasSettings = "has_settings"
        case settingsCount = "settings_count"
    }
}

nonisolated struct HandRequirement: Codable, Identifiable, Sendable {
    let key: String
    let label: String
    let satisfied: Bool
    let optional: Bool

    var id: String { key }
}

nonisolated struct ActiveHandList: Codable, Sendable {
    let instances: [HandInstance]
    let total: Int
}

nonisolated struct HandInstance: Codable, Identifiable, Sendable {
    let instanceId: String
    let handId: String
    let status: String
    let agentId: String?
    let agentName: String?
    let activatedAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case status
        case instanceId = "instance_id"
        case handId = "hand_id"
        case agentId = "agent_id"
        case agentName = "agent_name"
        case activatedAt = "activated_at"
        case updatedAt = "updated_at"
    }

    var id: String { instanceId }
}

nonisolated struct ApprovalQueue: Codable, Sendable {
    let approvals: [ApprovalItem]
    let total: Int
}

nonisolated struct SessionListResponse: Codable, Sendable {
    let sessions: [SessionInfo]
}

nonisolated struct SessionInfo: Codable, Identifiable, Sendable {
    let sessionId: String
    let agentId: String
    let messageCount: Int
    let createdAt: String
    let label: String?

    var id: String { sessionId }

    enum CodingKeys: String, CodingKey {
        case label
        case sessionId = "session_id"
        case agentId = "agent_id"
        case messageCount = "message_count"
        case createdAt = "created_at"
    }
}

nonisolated struct AuditRecentResponse: Codable, Sendable {
    let entries: [AuditEntry]
    let total: Int
    let tipHash: String?

    enum CodingKeys: String, CodingKey {
        case entries, total
        case tipHash = "tip_hash"
    }
}

nonisolated struct AuditEntry: Codable, Identifiable, Sendable {
    let seq: Int
    let timestamp: String
    let agentId: String
    let action: String
    let detail: String
    let outcome: String
    let hash: String

    var id: Int { seq }

    enum CodingKeys: String, CodingKey {
        case seq, timestamp, action, detail, outcome, hash
        case agentId = "agent_id"
    }
}

nonisolated struct AuditVerifyStatus: Codable, Sendable {
    let valid: Bool
    let entries: Int
    let warning: String?
    let error: String?
    let tipHash: String?

    enum CodingKeys: String, CodingKey {
        case valid, entries, warning, error
        case tipHash = "tip_hash"
    }
}

nonisolated struct MCPServerList: Codable, Sendable {
    let configured: [MCPConfiguredServer]
    let connected: [MCPConnectedServer]
    let totalConfigured: Int
    let totalConnected: Int

    enum CodingKeys: String, CodingKey {
        case configured, connected
        case totalConfigured = "total_configured"
        case totalConnected = "total_connected"
    }
}

nonisolated struct MCPConfiguredServer: Codable, Identifiable, Sendable {
    let name: String
    let transport: MCPTransportSummary
    let timeoutSecs: Int

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, transport
        case timeoutSecs = "timeout_secs"
    }
}

nonisolated struct MCPTransportSummary: Codable, Sendable {
    let type: String
    let command: String?
    let url: String?
    let baseURL: String?
    let toolsCount: Int?

    enum CodingKeys: String, CodingKey {
        case type, command, url
        case baseURL = "base_url"
        case toolsCount = "tools_count"
    }
}

nonisolated struct MCPConnectedServer: Codable, Identifiable, Sendable {
    let name: String
    let toolsCount: Int
    let tools: [ToolInfo]
    let connected: Bool

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, tools, connected
        case toolsCount = "tools_count"
    }
}

nonisolated struct ToolListResponse: Codable, Sendable {
    let tools: [ToolInfo]
    let total: Int
}

nonisolated struct ToolInfo: Codable, Identifiable, Sendable {
    let name: String
    let description: String?
    let source: String?

    var id: String { name }
}

nonisolated struct ApprovalItem: Codable, Identifiable, Sendable {
    let id: String
    let agentId: String
    let agentName: String
    let toolName: String
    let description: String
    let actionSummary: String
    let riskLevel: String
    let requestedAt: String
    let timeoutSecs: Int
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, description, status
        case agentId = "agent_id"
        case agentName = "agent_name"
        case toolName = "tool_name"
        case actionSummary = "action_summary"
        case riskLevel = "risk_level"
        case requestedAt = "requested_at"
        case timeoutSecs = "timeout_secs"
    }
}

nonisolated struct SecurityStatus: Codable, Sendable {
    let configurable: SecurityConfigurable
    let monitoring: SecurityMonitoring
    let secretZeroization: Bool
    let totalFeatures: Int

    enum CodingKeys: String, CodingKey {
        case configurable, monitoring
        case secretZeroization = "secret_zeroization"
        case totalFeatures = "total_features"
    }
}

nonisolated struct NetworkStatus: Codable, Sendable {
    let enabled: Bool
    let nodeId: String
    let listenAddress: String
    let connectedPeers: Int
    let totalPeers: Int

    enum CodingKeys: String, CodingKey {
        case enabled
        case nodeId = "node_id"
        case listenAddress = "listen_address"
        case connectedPeers = "connected_peers"
        case totalPeers = "total_peers"
    }
}

nonisolated struct PeerList: Codable, Sendable {
    let peers: [PeerStatus]
    let total: Int
}

nonisolated struct PeerStatus: Codable, Identifiable, Sendable {
    let nodeId: String
    let nodeName: String
    let address: String
    let state: String
    let agents: [PeerAgent]
    let connectedAt: String
    let protocolVersion: String

    var id: String { nodeId }

    enum CodingKeys: String, CodingKey {
        case address, state, agents
        case nodeId = "node_id"
        case nodeName = "node_name"
        case connectedAt = "connected_at"
        case protocolVersion = "protocol_version"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeId = try container.decode(String.self, forKey: .nodeId)
        nodeName = try container.decode(String.self, forKey: .nodeName)
        address = try container.decode(String.self, forKey: .address)
        state = try container.decode(String.self, forKey: .state)
        agents = try container.decode([PeerAgent].self, forKey: .agents)
        connectedAt = try container.decode(String.self, forKey: .connectedAt)

        if let version = try? container.decode(String.self, forKey: .protocolVersion) {
            protocolVersion = version
        } else if let version = try? container.decode(Int.self, forKey: .protocolVersion) {
            protocolVersion = String(version)
        } else {
            protocolVersion = "unknown"
        }
    }
}

nonisolated struct PeerAgent: Codable, Identifiable, Sendable {
    let id: String
    let name: String
}

nonisolated struct SecurityConfigurable: Codable, Sendable {
    let auth: SecurityAuthConfig
}

nonisolated struct SecurityAuthConfig: Codable, Sendable {
    let mode: String
    let apiKeySet: Bool

    enum CodingKeys: String, CodingKey {
        case mode
        case apiKeySet = "api_key_set"
    }
}

nonisolated struct SecurityMonitoring: Codable, Sendable {
    let auditTrail: AuditTrailStatus

    enum CodingKeys: String, CodingKey {
        case auditTrail = "audit_trail"
    }
}

nonisolated struct AuditTrailStatus: Codable, Sendable {
    let enabled: Bool
    let algorithm: String
    let entryCount: Int

    enum CodingKeys: String, CodingKey {
        case enabled, algorithm
        case entryCount = "entry_count"
    }
}

nonisolated struct AgentSessionSnapshot: Codable, Sendable {
    let sessionId: String
    let agentId: String
    let messageCount: Int
    let contextWindowTokens: Int
    let label: String?
    let messages: [AgentSessionMessage]

    enum CodingKeys: String, CodingKey {
        case label, messages
        case sessionId = "session_id"
        case agentId = "agent_id"
        case messageCount = "message_count"
        case contextWindowTokens = "context_window_tokens"
    }
}

nonisolated struct AgentSessionMessage: Codable, Sendable {
    let role: String
    let content: String
    let tools: [AgentSessionTool]?
    let images: [AgentSessionImage]?
}

nonisolated struct AgentSessionTool: Codable, Sendable {
    let name: String
    let input: String?
    let result: String?
    let isError: Bool?

    enum CodingKeys: String, CodingKey {
        case name, input, result
        case isError = "is_error"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        input = try? container.decode(String.self, forKey: .input)
        result = try? container.decode(String.self, forKey: .result)
        isError = try? container.decode(Bool.self, forKey: .isError)
    }
}

nonisolated struct AgentSessionImage: Codable, Sendable {
    let fileId: String
    let filename: String

    enum CodingKeys: String, CodingKey {
        case filename
        case fileId = "file_id"
    }
}

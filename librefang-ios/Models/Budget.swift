import Foundation

struct BudgetOverview: Codable, Sendable {
    let hourlySpend: Double
    let hourlyLimit: Double
    let hourlyPct: Double
    let dailySpend: Double
    let dailyLimit: Double
    let dailyPct: Double
    let monthlySpend: Double
    let monthlyLimit: Double
    let monthlyPct: Double
    let alertThreshold: Double
    let defaultMaxLlmTokensPerHour: Int?

    enum CodingKeys: String, CodingKey {
        case hourlySpend = "hourly_spend"
        case hourlyLimit = "hourly_limit"
        case hourlyPct = "hourly_pct"
        case dailySpend = "daily_spend"
        case dailyLimit = "daily_limit"
        case dailyPct = "daily_pct"
        case monthlySpend = "monthly_spend"
        case monthlyLimit = "monthly_limit"
        case monthlyPct = "monthly_pct"
        case alertThreshold = "alert_threshold"
        case defaultMaxLlmTokensPerHour = "default_max_llm_tokens_per_hour"
    }
}

struct AgentBudgetRanking: Codable, Sendable {
    let agents: [AgentBudgetItem]
    let total: Int
}

struct AgentBudgetItem: Codable, Identifiable, Sendable {
    let agentId: String
    let name: String
    let dailyCostUsd: Double
    let hourlyLimit: Double?
    let dailyLimit: Double?
    let monthlyLimit: Double?
    let maxLlmTokensPerHour: Int?

    var id: String { agentId }

    enum CodingKeys: String, CodingKey {
        case name
        case agentId = "agent_id"
        case dailyCostUsd = "daily_cost_usd"
        case hourlyLimit = "hourly_limit"
        case dailyLimit = "daily_limit"
        case monthlyLimit = "monthly_limit"
        case maxLlmTokensPerHour = "max_llm_tokens_per_hour"
    }
}

struct AgentBudgetDetail: Codable, Sendable {
    let agentId: String
    let agentName: String
    let hourly: BudgetPeriod
    let daily: BudgetPeriod
    let monthly: BudgetPeriod
    let tokens: TokenUsage

    enum CodingKeys: String, CodingKey {
        case hourly, daily, monthly, tokens
        case agentId = "agent_id"
        case agentName = "agent_name"
    }
}

struct BudgetPeriod: Codable, Sendable {
    let spend: Double
    let limit: Double
    let pct: Double
}

struct TokenUsage: Codable, Sendable {
    let used: Int
    let limit: Int
    let pct: Double
}

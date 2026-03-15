import Foundation

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidURL
    case httpError(Int, String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

nonisolated struct APIConnectionInfo: Sendable {
    let baseURL: URL
    let apiKey: String
}

// MARK: - Protocol

protocol APIClientProtocol: Sendable {
    func health() async throws -> HealthStatus
    func status() async throws -> SystemStatus
    func agents() async throws -> [Agent]
    func budget() async throws -> BudgetOverview
    func budgetAgents() async throws -> AgentBudgetRanking
    func budgetAgent(id: String) async throws -> AgentBudgetDetail
    func usageSummary() async throws -> UsageSummary
    func usageByModel() async throws -> UsageByModelResponse
    func usageDaily() async throws -> UsageDailyResponse
    func providers() async throws -> ProviderList
    func channels() async throws -> ChannelList
    func models() async throws -> CatalogModelListResponse
    func modelAliases() async throws -> ModelAliasListResponse
    func hands() async throws -> HandCatalog
    func activeHands() async throws -> ActiveHandList
    func approvals() async throws -> ApprovalQueue
    func sessions() async throws -> SessionListResponse
    func recentAudit(limit: Int) async throws -> AuditRecentResponse
    func auditVerify() async throws -> AuditVerifyStatus
    func security() async throws -> SecurityStatus
    func mcpServers() async throws -> MCPServerList
    func tools() async throws -> ToolListResponse
    func networkStatus() async throws -> NetworkStatus
    func peers() async throws -> PeerList
    func commsTopology() async throws -> CommsTopology
    func commsEvents(limit: Int) async throws -> [CommsEvent]
    func workflows() async throws -> [WorkflowSummary]
    func workflowRuns(workflowID: String) async throws -> [WorkflowRun]
    func triggers() async throws -> [TriggerDefinition]
    func schedules() async throws -> ScheduleListResponse
    func cronJobs() async throws -> CronJobListResponse
    func healthDetail() async throws -> HealthDetail
    func versionInfo() async throws -> BuildVersionInfo
    func configSummary() async throws -> RuntimeConfigSummary
    func metricsText() async throws -> String
    func approveApproval(id: String) async throws -> OperatorActionResponse
    func rejectApproval(id: String) async throws -> OperatorActionResponse
    func testProvider(name: String) async throws -> IntegrationProbeResult
    func testChannel(name: String) async throws -> IntegrationProbeResult
    func createSession(agentId: String, label: String?) async throws -> SessionInfo
    func setSessionLabel(id: String, label: String?) async throws -> OperatorActionResponse
    func deleteSession(id: String) async throws -> OperatorActionResponse
    func switchSession(agentId: String, sessionId: String) async throws -> OperatorActionResponse
    func resetSession(agentId: String) async throws -> OperatorActionResponse
    func compactSession(agentId: String) async throws -> OperatorActionResponse
    func stopAgentRun(agentId: String) async throws -> OperatorActionResponse
    func agentSessions(agentId: String) async throws -> SessionListResponse
    func session(agentId: String) async throws -> AgentSessionSnapshot
    func sendMessage(agentId: String, message: String) async throws -> MessageResponse
    func a2aAgents() async throws -> A2AAgentList
    func connectionInfo() async throws -> APIConnectionInfo
    func updateConfig(_ config: ServerConfig) async
}

// MARK: - Implementation

actor APIClient: APIClientProtocol {
    private let session: URLSession
    private var config: ServerConfig

    init(config: ServerConfig) {
        self.config = config
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: sessionConfig)
    }

    func updateConfig(_ config: ServerConfig) {
        self.config = config
    }

    // MARK: - Public API

    func health() async throws -> HealthStatus {
        try await get("/api/health")
    }

    func status() async throws -> SystemStatus {
        try await get("/api/status")
    }

    func agents() async throws -> [Agent] {
        try await get("/api/agents")
    }

    func budget() async throws -> BudgetOverview {
        try await get("/api/budget")
    }

    func budgetAgents() async throws -> AgentBudgetRanking {
        try await get("/api/budget/agents")
    }

    func budgetAgent(id: String) async throws -> AgentBudgetDetail {
        try await get("/api/budget/agents/\(id)")
    }

    func usageSummary() async throws -> UsageSummary {
        try await get("/api/usage/summary")
    }

    func usageByModel() async throws -> UsageByModelResponse {
        try await get("/api/usage/by-model")
    }

    func usageDaily() async throws -> UsageDailyResponse {
        try await get("/api/usage/daily")
    }

    func providers() async throws -> ProviderList {
        try await get("/api/providers")
    }

    func channels() async throws -> ChannelList {
        try await get("/api/channels")
    }

    func models() async throws -> CatalogModelListResponse {
        try await get("/api/models")
    }

    func modelAliases() async throws -> ModelAliasListResponse {
        try await get("/api/models/aliases")
    }

    func hands() async throws -> HandCatalog {
        try await get("/api/hands")
    }

    func activeHands() async throws -> ActiveHandList {
        try await get("/api/hands/active")
    }

    func approvals() async throws -> ApprovalQueue {
        try await get("/api/approvals")
    }

    func sessions() async throws -> SessionListResponse {
        try await get("/api/sessions")
    }

    func recentAudit(limit: Int) async throws -> AuditRecentResponse {
        try await get("/api/audit/recent?n=\(limit)")
    }

    func auditVerify() async throws -> AuditVerifyStatus {
        try await get("/api/audit/verify")
    }

    func security() async throws -> SecurityStatus {
        try await get("/api/security")
    }

    func mcpServers() async throws -> MCPServerList {
        try await get("/api/mcp/servers")
    }

    func tools() async throws -> ToolListResponse {
        try await get("/api/tools")
    }

    func networkStatus() async throws -> NetworkStatus {
        try await get("/api/network/status")
    }

    func peers() async throws -> PeerList {
        try await get("/api/peers")
    }

    func commsTopology() async throws -> CommsTopology {
        try await get("/api/comms/topology")
    }

    func commsEvents(limit: Int) async throws -> [CommsEvent] {
        try await get("/api/comms/events?limit=\(limit)")
    }

    func workflows() async throws -> [WorkflowSummary] {
        try await get("/api/workflows")
    }

    func workflowRuns(workflowID: String) async throws -> [WorkflowRun] {
        try await get("/api/workflows/\(workflowID)/runs")
    }

    func triggers() async throws -> [TriggerDefinition] {
        try await get("/api/triggers")
    }

    func schedules() async throws -> ScheduleListResponse {
        try await get("/api/schedules")
    }

    func cronJobs() async throws -> CronJobListResponse {
        try await get("/api/cron/jobs")
    }

    func healthDetail() async throws -> HealthDetail {
        try await get("/api/health/detail")
    }

    func versionInfo() async throws -> BuildVersionInfo {
        try await get("/api/version")
    }

    func configSummary() async throws -> RuntimeConfigSummary {
        try await get("/api/config")
    }

    func metricsText() async throws -> String {
        try await getText("/api/metrics")
    }

    func approveApproval(id: String) async throws -> OperatorActionResponse {
        try await post("/api/approvals/\(id)/approve")
    }

    func rejectApproval(id: String) async throws -> OperatorActionResponse {
        try await post("/api/approvals/\(id)/reject")
    }

    func testProvider(name: String) async throws -> IntegrationProbeResult {
        try await post("/api/providers/\(name)/test")
    }

    func testChannel(name: String) async throws -> IntegrationProbeResult {
        try await post("/api/channels/\(name)/test")
    }

    func createSession(agentId: String, label: String?) async throws -> SessionInfo {
        try await post("/api/agents/\(agentId)/sessions", body: CreateSessionRequest(label: label))
    }

    func setSessionLabel(id: String, label: String?) async throws -> OperatorActionResponse {
        try await put("/api/sessions/\(id)/label", body: SessionLabelRequest(label: label))
    }

    func deleteSession(id: String) async throws -> OperatorActionResponse {
        try await delete("/api/sessions/\(id)")
    }

    func switchSession(agentId: String, sessionId: String) async throws -> OperatorActionResponse {
        try await post("/api/agents/\(agentId)/sessions/\(sessionId)/switch")
    }

    func resetSession(agentId: String) async throws -> OperatorActionResponse {
        try await post("/api/agents/\(agentId)/session/reset")
    }

    func compactSession(agentId: String) async throws -> OperatorActionResponse {
        try await post("/api/agents/\(agentId)/session/compact")
    }

    func stopAgentRun(agentId: String) async throws -> OperatorActionResponse {
        try await post("/api/agents/\(agentId)/stop")
    }

    func agentSessions(agentId: String) async throws -> SessionListResponse {
        try await get("/api/agents/\(agentId)/sessions")
    }

    func session(agentId: String) async throws -> AgentSessionSnapshot {
        try await get("/api/agents/\(agentId)/session")
    }

    func sendMessage(agentId: String, message: String) async throws -> MessageResponse {
        let body = MessageRequest(message: message)
        return try await post("/api/agents/\(agentId)/message", body: body)
    }

    func a2aAgents() async throws -> A2AAgentList {
        try await get("/api/a2a/agents")
    }

    func connectionInfo() throws -> APIConnectionInfo {
        let base = config.baseURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let url = URL(string: base) else {
            throw APIError.invalidURL
        }
        return APIConnectionInfo(baseURL: url, apiKey: config.apiKey)
    }

    // MARK: - Private Networking

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let request = try buildRequest(path: path, method: "GET")
        return try await perform(request)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        var request = try buildRequest(path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func post<T: Decodable>(_ path: String) async throws -> T {
        let request = try buildRequest(path: path, method: "POST")
        return try await perform(request)
    }

    private func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        var request = try buildRequest(path: path, method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        let request = try buildRequest(path: path, method: "DELETE")
        return try await perform(request)
    }

    private func buildRequest(path: String, method: String) throws -> URLRequest {
        let base = config.baseURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let url = URL(string: base + path) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func getText(_ path: String) async throws -> String {
        let request = try buildRequest(path: path, method: "GET")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(http.statusCode, message)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw APIError.decodingError(DecodingFailure.invalidTextEncoding)
        }
        return text
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                ?? String(data: data, encoding: .utf8)
                ?? "Unknown error"
            throw APIError.httpError(http.statusCode, message)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}

private enum DecodingFailure: LocalizedError {
    case invalidTextEncoding

    var errorDescription: String? {
        switch self {
        case .invalidTextEncoding:
            return "Response text encoding is invalid"
        }
    }
}

private nonisolated struct CreateSessionRequest: Encodable, Sendable {
    let label: String?
}

private nonisolated struct SessionLabelRequest: Encodable, Sendable {
    let label: String?
}

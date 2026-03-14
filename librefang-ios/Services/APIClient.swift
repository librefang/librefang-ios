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

// MARK: - Protocol

protocol APIClientProtocol: Sendable {
    func health() async throws -> HealthStatus
    func agents() async throws -> [Agent]
    func budget() async throws -> BudgetOverview
    func budgetAgents() async throws -> AgentBudgetRanking
    func budgetAgent(id: String) async throws -> AgentBudgetDetail
    func sendMessage(agentId: String, message: String) async throws -> MessageResponse
    func a2aAgents() async throws -> A2AAgentList
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

    func sendMessage(agentId: String, message: String) async throws -> MessageResponse {
        let body = MessageRequest(message: message)
        return try await post("/api/agents/\(agentId)/message", body: body)
    }

    func a2aAgents() async throws -> A2AAgentList {
        try await get("/api/a2a/agents")
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

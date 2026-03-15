import Foundation

extension APIConnectionInfo {
    nonisolated fileprivate func request(path: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }

        let basePath = baseURL.path == "/" ? "" : baseURL.path
        let suffix = path.hasPrefix("/") ? path : "/\(path)"
        components.path = basePath + suffix

        if !queryItems.isEmpty {
            var mergedItems = components.queryItems ?? []
            mergedItems.append(contentsOf: queryItems)
            components.queryItems = mergedItems
        }

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    nonisolated fileprivate func webSocketRequest(path: String) throws -> URLRequest {
        var request = try request(path: path)
        if let url = request.url {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = switch baseURL.scheme?.lowercased() {
            case "https": "wss"
            default: "ws"
            }
            guard let wsURL = components?.url else {
                throw APIError.invalidURL
            }
            request.url = wsURL
        }
        return request
    }
}

actor AuditEventStreamClient {
    private let session: URLSession

    init() {
        self.session = makeStreamingSession()
    }

    func stream(connectionInfo: APIConnectionInfo) -> AsyncThrowingStream<AuditEntry, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try connectionInfo.request(path: "/api/logs/stream")
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        throw APIError.httpError(
                            (response as? HTTPURLResponse)?.statusCode ?? -1,
                            String(localized: "Audit stream unavailable")
                        )
                    }

                    var eventLines: [String] = []

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        if line.isEmpty {
                            if let entry = Self.decodeAuditEntry(from: eventLines) {
                                continuation.yield(entry)
                            }
                            eventLines.removeAll(keepingCapacity: true)
                            continue
                        }

                        if line.hasPrefix(":") {
                            continue
                        }

                        eventLines.append(line)
                    }

                    if let entry = Self.decodeAuditEntry(from: eventLines) {
                        continuation.yield(entry)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func decodeAuditEntry(from lines: [String]) -> AuditEntry? {
        guard !lines.isEmpty else { return nil }
        let payload = decodeSSEPayload(from: lines)
        guard !payload.isEmpty, let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AuditEntry.self, from: data)
    }
}

actor CommsEventStreamClient {
    private let session: URLSession

    init() {
        self.session = makeStreamingSession()
    }

    func stream(connectionInfo: APIConnectionInfo) -> AsyncThrowingStream<CommsEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try connectionInfo.request(path: "/api/comms/events/stream")
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        throw APIError.httpError(
                            (response as? HTTPURLResponse)?.statusCode ?? -1,
                            String(localized: "Comms stream unavailable")
                        )
                    }

                    var eventLines: [String] = []

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        if line.isEmpty {
                            if let event = Self.decodeCommsEvent(from: eventLines) {
                                continuation.yield(event)
                            }
                            eventLines.removeAll(keepingCapacity: true)
                            continue
                        }

                        if line.hasPrefix(":") {
                            continue
                        }

                        eventLines.append(line)
                    }

                    if let event = Self.decodeCommsEvent(from: eventLines) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func decodeCommsEvent(from lines: [String]) -> CommsEvent? {
        let payload = decodeSSEPayload(from: lines)
        guard !payload.isEmpty, let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CommsEvent.self, from: data)
    }
}

nonisolated enum AgentRealtimeEvent: Sendable {
    case connected
    case typing(state: String, tool: String?)
    case textDelta(String)
    case response(content: String, inputTokens: Int?, outputTokens: Int?, iterations: Int?, costUsd: Double?)
    case commandResult(message: String, command: String?)
    case silentComplete(inputTokens: Int?, outputTokens: Int?)
    case error(String)
    case disconnected(String?)
}

nonisolated private func makeStreamingSession() -> URLSession {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 3_600
    configuration.timeoutIntervalForResource = 3_600
    return URLSession(configuration: configuration)
}

nonisolated private func decodeSSEPayload(from lines: [String]) -> String {
    lines
        .compactMap { line -> String? in
            guard line.hasPrefix("data:") else { return nil }
            return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }
        .joined(separator: "\n")
}

actor AgentWebSocketClient {
    private let session: URLSession
    private let connectionInfo: APIConnectionInfo
    private let agentID: String
    private var socketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var connectionID: UUID?

    init(connectionInfo: APIConnectionInfo, agentID: String) {
        self.session = makeStreamingSession()
        self.connectionInfo = connectionInfo
        self.agentID = agentID
    }

    func connect(onEvent: @escaping @Sendable (AgentRealtimeEvent) async -> Void) throws {
        guard socketTask == nil else { return }

        let request = try connectionInfo.webSocketRequest(path: "/api/agents/\(agentID)/ws")
        let task = session.webSocketTask(with: request)
        let token = UUID()

        socketTask = task
        connectionID = token

        task.resume()

        receiveTask = Task { [weak task] in
            guard let task else { return }

            do {
                while !Task.isCancelled {
                    let message = try await task.receive()
                    guard let event = Self.parse(message: message) else {
                        continue
                    }
                    await onEvent(event)
                }
                await onEvent(.disconnected(nil))
            } catch is CancellationError {
                await onEvent(.disconnected(nil))
            } catch {
                await onEvent(.disconnected(error.localizedDescription))
            }

            self.finishReceiveLoop(for: token)
        }
    }

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil

        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
        connectionID = nil
    }

    func sendMessage(_ content: String) async throws {
        guard let socketTask else {
            throw APIError.networkError(RealtimeTransportError.notConnected)
        }

        let payload = AgentRealtimeOutboundMessage(type: "message", content: content)
        let data = try JSONEncoder().encode(payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw APIError.networkError(RealtimeTransportError.encodingFailed)
        }
        try await socketTask.send(.string(text))
    }

    private func finishReceiveLoop(for token: UUID) {
        guard connectionID == token else { return }
        socketTask = nil
        receiveTask = nil
        connectionID = nil
    }

    private static func parse(message: URLSessionWebSocketTask.Message) -> AgentRealtimeEvent? {
        let rawText: String

        switch message {
        case .string(let text):
            rawText = text
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            rawText = text
        @unknown default:
            return nil
        }

        guard let data = rawText.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(AgentRealtimeEnvelope.self, from: data) else {
            return nil
        }

        switch envelope.type {
        case "connected":
            return .connected
        case "typing":
            return .typing(state: envelope.state ?? "start", tool: envelope.tool)
        case "text_delta":
            return .textDelta(envelope.content ?? "")
        case "response":
            return .response(
                content: envelope.content ?? "",
                inputTokens: envelope.inputTokens,
                outputTokens: envelope.outputTokens,
                iterations: envelope.iterations,
                costUsd: envelope.costUsd
            )
        case "command_result":
            return .commandResult(message: envelope.message ?? "", command: envelope.command)
        case "silent_complete":
            return .silentComplete(inputTokens: envelope.inputTokens, outputTokens: envelope.outputTokens)
        case "error":
            return .error(envelope.content ?? envelope.message ?? String(localized: "Unknown realtime error"))
        default:
            return nil
        }
    }
}

private enum RealtimeTransportError: LocalizedError {
    case notConnected
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return String(localized: "Realtime channel is not connected")
        case .encodingFailed:
            return String(localized: "Could not encode realtime payload")
        }
    }
}

nonisolated private struct AgentRealtimeOutboundMessage: Codable, Sendable {
    let type: String
    let content: String
}

nonisolated private struct AgentRealtimeEnvelope: Codable, Sendable {
    let type: String
    let state: String?
    let tool: String?
    let content: String?
    let message: String?
    let command: String?
    let inputTokens: Int?
    let outputTokens: Int?
    let iterations: Int?
    let costUsd: Double?

    enum CodingKeys: String, CodingKey {
        case type, state, tool, content, message, command, iterations
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case costUsd = "cost_usd"
    }
}

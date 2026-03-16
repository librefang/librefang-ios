import Foundation

struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    let content: String
    let images: [AgentSessionImage]
    let tokens: Int?
    let cost: Double?
    let timestamp: Date
    let isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        images: [AgentSessionImage] = [],
        tokens: Int? = nil,
        cost: Double? = nil,
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.images = images
        self.tokens = tokens
        self.cost = cost
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }

    enum Role {
        case user
        case agent
        case system
    }
}

@MainActor
@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var inputText = ""
    var isSending = false
    var isLoadingHistory = false
    var isRealtimeConnected = false
    var error: String?
    var sessionLabel: String?
    var messageCount = 0
    var contextWindowTokens = 0

    let agent: Agent
    private let api: APIClientProtocol
    private var hasLoadedHistory = false
    private var socket: AgentWebSocketClient?
    private var liveAgentMessageID: UUID?
    private var hasActivated = false

    init(agent: Agent, api: APIClientProtocol) {
        self.agent = agent
        self.api = api
    }

    var connectionState: ChatConnectionState {
        ChatConnectionState(isRealtimeConnected: isRealtimeConnected)
    }

    var loadedMessageCount: Int {
        messages.count
    }

    var historyLagCount: Int {
        max(messageCount - loadedMessageCount, 0)
    }

    var hasNamedSession: Bool {
        !(sessionLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var isHighVolumeSession: Bool {
        messageCount >= 40
    }

    func activate() async {
        guard !hasActivated else { return }
        hasActivated = true
        await loadHistoryIfNeeded()
        await connectRealtimeIfNeeded()
    }

    func deactivate() {
        hasActivated = false
        isRealtimeConnected = false
        liveAgentMessageID = nil

        let currentSocket = socket
        socket = nil

        Task {
            await currentSocket?.disconnect()
        }
    }

    func loadHistoryIfNeeded() async {
        guard !hasLoadedHistory else { return }
        hasLoadedHistory = true
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        do {
            let session = try await api.session(agentId: agent.id)
            sessionLabel = session.label
            messageCount = session.messageCount
            contextWindowTokens = session.contextWindowTokens
            messages = session.messages.map(mapMessage)
        } catch {
            self.error = self.error ?? error.localizedDescription
        }
    }

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        messages.append(ChatMessage(role: .user, content: text, tokens: nil, cost: nil))
        inputText = ""
        isSending = true
        error = nil

        do {
            await connectRealtimeIfNeeded()
            if let socket {
                try await socket.sendMessage(text)
                return
            }
        } catch {
            isRealtimeConnected = false
            socket = nil
        }

        await sendViaREST(text)
    }

    private func mapMessage(_ message: AgentSessionMessage) -> ChatMessage {
        ChatMessage(
            role: mapRole(message.role),
            content: displayText(for: message),
            images: message.images ?? [],
            tokens: nil,
            cost: nil
        )
    }

    private func mapRole(_ role: String) -> ChatMessage.Role {
        switch role {
        case "User":
            .user
        case "System":
            .system
        default:
            .agent
        }
    }

    private func displayText(for message: AgentSessionMessage) -> String {
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let tools = message.tools, !tools.isEmpty {
            return tools.map(\.name).joined(separator: ", ")
        }
        if let images = message.images, !images.isEmpty {
            return images.count == 1
                ? String(localized: "1 image attachment")
                : String(localized: "\(images.count) image attachments")
        }
        return String(localized: "No message content")
    }

    private func connectRealtimeIfNeeded() async {
        guard socket == nil else { return }

        do {
            let connectionInfo = try await api.connectionInfo()
            let socket = AgentWebSocketClient(connectionInfo: connectionInfo, agentID: agent.id)
            try await socket.connect { [weak self] event in
                await self?.handleRealtimeEvent(event)
            }
            self.socket = socket
        } catch {
            isRealtimeConnected = false
        }
    }

    private func sendViaREST(_ text: String) async {
        do {
            let response = try await api.sendMessage(agentId: agent.id, message: text)
            finalizeAgentMessage(
                id: liveAgentMessageID ?? UUID(),
                timestamp: Date(),
                content: response.response,
                inputTokens: response.inputTokens,
                outputTokens: response.outputTokens,
                costUsd: response.costUsd
            )
            isSending = false
        } catch {
            self.error = error.localizedDescription
            finishLiveMessage()
            isSending = false
        }
    }

    private func handleRealtimeEvent(_ event: AgentRealtimeEvent) async {
        switch event {
        case .connected:
            isRealtimeConnected = true

        case .typing(let state, _):
            switch state {
            case "stop":
                isSending = false
            default:
                isSending = true
            }

        case .textDelta(let text):
            appendAgentDelta(text)

        case .response(let content, let inputTokens, let outputTokens, _, let costUsd):
            finalizeAgentMessage(
                id: liveAgentMessageID ?? UUID(),
                timestamp: currentLiveTimestamp ?? Date(),
                content: content,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                costUsd: costUsd
            )
            isSending = false

        case .commandResult(let message, _):
            finishLiveMessage()
            isSending = false
            if !message.isEmpty {
                messages.append(ChatMessage(role: .system, content: message))
            }

        case .silentComplete(let inputTokens, let outputTokens):
            finishLiveMessage()
            isSending = false
            let tokensSummary = [inputTokens, outputTokens]
                .compactMap { $0 }
                .map(String.init)
                .joined(separator: " / ")
            let content = tokensSummary.isEmpty
                ? String(localized: "Agent completed without a text reply.")
                : String(localized: "Agent completed without a text reply (\(tokensSummary) tokens).")
            messages.append(ChatMessage(role: .system, content: content))

        case .error(let message):
            finishLiveMessage()
            isSending = false
            error = message

        case .disconnected(let message):
            isRealtimeConnected = false
            socket = nil
            if isSending, let message, !message.isEmpty {
                error = message
            }
        }
    }

    private var currentLiveTimestamp: Date? {
        guard let liveAgentMessageID,
              let existing = messages.first(where: { $0.id == liveAgentMessageID }) else {
            return nil
        }
        return existing.timestamp
    }

    private func appendAgentDelta(_ text: String) {
        guard !text.isEmpty else { return }

        if let liveAgentMessageID,
           let index = messages.firstIndex(where: { $0.id == liveAgentMessageID }) {
            let existing = messages[index]
            messages[index] = ChatMessage(
                id: existing.id,
                role: existing.role,
                content: existing.content + text,
                tokens: existing.tokens,
                cost: existing.cost,
                timestamp: existing.timestamp,
                isStreaming: true
            )
            return
        }

        let message = ChatMessage(role: .agent, content: text, isStreaming: true)
        liveAgentMessageID = message.id
        messages.append(message)
    }

    private func finalizeAgentMessage(
        id: UUID,
        timestamp: Date,
        content: String,
        inputTokens: Int?,
        outputTokens: Int?,
        costUsd: Double?
    ) {
        let totalTokens = (inputTokens ?? 0) + (outputTokens ?? 0)

        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index] = ChatMessage(
                id: id,
                role: .agent,
                content: content,
                tokens: totalTokens > 0 ? totalTokens : nil,
                cost: costUsd,
                timestamp: timestamp,
                isStreaming: false
            )
        } else {
            messages.append(ChatMessage(
                id: id,
                role: .agent,
                content: content,
                tokens: totalTokens > 0 ? totalTokens : nil,
                cost: costUsd,
                timestamp: timestamp,
                isStreaming: false
            ))
        }

        liveAgentMessageID = nil
        messageCount = max(messageCount, messages.count)
    }

    private func finishLiveMessage() {
        guard let liveAgentMessageID,
              let index = messages.firstIndex(where: { $0.id == liveAgentMessageID }) else {
            liveAgentMessageID = nil
            return
        }

        let existing = messages[index]
        messages[index] = ChatMessage(
            id: existing.id,
            role: existing.role,
            content: existing.content,
            tokens: existing.tokens,
            cost: existing.cost,
            timestamp: existing.timestamp,
            isStreaming: false
        )
        self.liveAgentMessageID = nil
    }
}

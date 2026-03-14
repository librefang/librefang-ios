import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let tokens: Int?
    let cost: Double?
    let timestamp = Date()

    enum Role {
        case user
        case agent
        case system
    }
}

@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var inputText = ""
    var isSending = false
    var isLoadingHistory = false
    var error: String?
    var sessionLabel: String?
    var messageCount = 0
    var contextWindowTokens = 0

    let agent: Agent
    private let api: APIClientProtocol
    private var hasLoadedHistory = false

    init(agent: Agent, api: APIClientProtocol) {
        self.agent = agent
        self.api = api
    }

    @MainActor
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

    @MainActor
    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        messages.append(ChatMessage(role: .user, content: text, tokens: nil, cost: nil))
        inputText = ""
        isSending = true
        error = nil

        do {
            let response = try await api.sendMessage(agentId: agent.id, message: text)
            let totalTokens = (response.inputTokens ?? 0) + (response.outputTokens ?? 0)
            messages.append(ChatMessage(
                role: .agent,
                content: response.response,
                tokens: totalTokens,
                cost: response.costUsd
            ))
            messageCount = max(messageCount, messages.count)
        } catch {
            self.error = error.localizedDescription
        }

        isSending = false
    }

    private func mapMessage(_ message: AgentSessionMessage) -> ChatMessage {
        ChatMessage(
            role: mapRole(message.role),
            content: displayText(for: message),
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
            return "\(images.count) image attachment\(images.count == 1 ? "" : "s")"
        }
        return "No message content"
    }
}

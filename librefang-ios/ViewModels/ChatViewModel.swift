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
    }
}

@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var inputText = ""
    var isSending = false
    var error: String?

    let agent: Agent
    private let api: APIClientProtocol

    init(agent: Agent, api: APIClientProtocol) {
        self.agent = agent
        self.api = api
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
        } catch {
            self.error = error.localizedDescription
        }

        isSending = false
    }
}

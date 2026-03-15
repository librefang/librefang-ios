import Foundation

nonisolated struct OperatorActionResponse: Codable, Sendable {
    let id: String?
    let status: String
    let message: String?
    let decidedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case message
        case decidedAt = "decided_at"
    }
}

struct OperatorActionNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum ApprovalDecisionAction: Identifiable {
    case approve(ApprovalItem)
    case reject(ApprovalItem)

    var id: String {
        switch self {
        case .approve(let approval):
            return "approve:\(approval.id)"
        case .reject(let approval):
            return "reject:\(approval.id)"
        }
    }

    var title: String {
        switch self {
        case .approve:
            return String(localized: "Approve Request")
        case .reject:
            return String(localized: "Reject Request")
        }
    }

    var message: String {
        switch self {
        case .approve(let approval):
            return String(localized: "Allow \(approval.agentName) to proceed with \(approval.toolName)?")
        case .reject(let approval):
            return String(localized: "Reject \(approval.actionSummary) for \(approval.agentName)?")
        }
    }

    var confirmLabel: String {
        switch self {
        case .approve:
            return String(localized: "Approve")
        case .reject:
            return String(localized: "Reject")
        }
    }

    var isDestructive: Bool {
        switch self {
        case .approve:
            return false
        case .reject:
            return true
        }
    }

    var approvalID: String {
        switch self {
        case .approve(let approval), .reject(let approval):
            return approval.id
        }
    }

    func perform(using api: APIClientProtocol) async throws -> OperatorActionResponse {
        switch self {
        case .approve(let approval):
            return try await api.approveApproval(id: approval.id)
        case .reject(let approval):
            return try await api.rejectApproval(id: approval.id)
        }
    }

    func successNotice(from response: OperatorActionResponse) -> OperatorActionNotice {
        OperatorActionNotice(
            title: title,
            message: response.message ?? defaultSuccessMessage
        )
    }

    private var defaultSuccessMessage: String {
        switch self {
        case .approve:
            return String(localized: "Approval marked as approved.")
        case .reject:
            return String(localized: "Approval marked as rejected.")
        }
    }
}

enum AgentSessionControlAction: Identifiable {
    case stopRun(agentID: String, agentName: String)
    case compact(agentID: String, agentName: String)
    case reset(agentID: String, agentName: String)
    case switchSession(agentID: String, agentName: String, session: SessionInfo)

    var id: String {
        switch self {
        case .stopRun(let agentID, _):
            return "stop:\(agentID)"
        case .compact(let agentID, _):
            return "compact:\(agentID)"
        case .reset(let agentID, _):
            return "reset:\(agentID)"
        case .switchSession(let agentID, _, let session):
            return "switch:\(agentID):\(session.id)"
        }
    }

    var title: String {
        switch self {
        case .stopRun:
            return String(localized: "Stop Active Run")
        case .compact:
            return String(localized: "Compact Session")
        case .reset:
            return String(localized: "Reset Session")
        case .switchSession:
            return String(localized: "Switch Session")
        }
    }

    var confirmLabel: String {
        switch self {
        case .stopRun:
            return String(localized: "Stop Run")
        case .compact:
            return String(localized: "Compact")
        case .reset:
            return String(localized: "Reset")
        case .switchSession:
            return String(localized: "Switch")
        }
    }

    var isDestructive: Bool {
        switch self {
        case .reset, .stopRun:
            return true
        case .compact, .switchSession:
            return false
        }
    }

    var message: String {
        switch self {
        case .stopRun(_, let agentName):
            return String(localized: "Cancel the active LLM run for \(agentName)?")
        case .compact(_, let agentName):
            return String(localized: "Ask LibreFang to compact the current session context for \(agentName)?")
        case .reset(_, let agentName):
            return String(localized: "Reset the current session for \(agentName)? This clears the active conversational context.")
        case .switchSession(_, let agentName, let session):
            return String(localized: "Make \(session.displayTitle) the active session for \(agentName)?")
        }
    }

    func perform(using api: APIClientProtocol) async throws -> OperatorActionResponse {
        switch self {
        case .stopRun(let agentID, _):
            return try await api.stopAgentRun(agentId: agentID)
        case .compact(let agentID, _):
            return try await api.compactSession(agentId: agentID)
        case .reset(let agentID, _):
            return try await api.resetSession(agentId: agentID)
        case .switchSession(let agentID, _, let session):
            return try await api.switchSession(agentId: agentID, sessionId: session.sessionId)
        }
    }

    func successNotice(from response: OperatorActionResponse) -> OperatorActionNotice {
        OperatorActionNotice(
            title: title,
            message: response.message ?? defaultSuccessMessage
        )
    }

    private var defaultSuccessMessage: String {
        switch self {
        case .stopRun:
            return String(localized: "Run cancelled.")
        case .compact:
            return String(localized: "Session compaction requested.")
        case .reset:
            return String(localized: "Session reset.")
        case .switchSession:
            return String(localized: "Session switched.")
        }
    }
}

private extension SessionInfo {
    var displayTitle: String {
        let trimmedLabel = (label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLabel.isEmpty {
            return trimmedLabel
        }
        return String(sessionId.prefix(8))
    }
}

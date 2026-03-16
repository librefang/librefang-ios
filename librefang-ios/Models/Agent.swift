import Foundation

nonisolated struct Agent: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let state: String
    let mode: String
    let createdAt: String?
    let lastActive: String?
    let modelProvider: String?
    let modelName: String?
    let modelTier: String?
    let authStatus: String?
    let ready: Bool
    let profile: String?
    let identity: AgentIdentity?

    enum CodingKeys: String, CodingKey {
        case id, name, state, mode, ready, profile, identity
        case createdAt = "created_at"
        case lastActive = "last_active"
        case modelProvider = "model_provider"
        case modelName = "model_name"
        case modelTier = "model_tier"
        case authStatus = "auth_status"
    }

    var isRunning: Bool { state == "Running" }
    var stateLabel: String {
        Agent.localizedStateLabel(for: state)
    }
    var stateTone: PresentationTone {
        Agent.stateTone(for: state)
    }
    var modeLabel: String {
        Agent.localizedModeLabel(for: mode)
    }
    var readyLabel: String {
        ready ? String(localized: "Yes") : String(localized: "No")
    }
    var readyTone: PresentationTone {
        ready ? .positive : .warning
    }
    var modelTierLabel: String? {
        guard let modelTier else { return nil }
        return Agent.localizedModelTierLabel(for: modelTier)
    }

    var authStatusLabel: String? {
        guard let authStatus else { return nil }
        switch authStatus.lowercased() {
        case "configured":
            return String(localized: "Configured")
        case "missing":
            return String(localized: "Missing")
        case "invalid":
            return String(localized: "Invalid")
        case "unconfigured", "not_configured":
            return String(localized: "Not configured")
        default:
            return authStatus
        }
    }

    var authStatusTone: PresentationTone? {
        guard let authStatus else { return nil }
        switch authStatus.lowercased() {
        case "configured":
            return .positive
        case "missing", "invalid":
            return .critical
        case "unconfigured", "not_configured":
            return .warning
        default:
            return .neutral
        }
    }

    static func localizedStateLabel(for state: String) -> String {
        switch state {
        case "Running":
            return String(localized: "Running")
        case "Suspended":
            return String(localized: "Suspended")
        case "Terminated":
            return String(localized: "Terminated")
        default:
            return state
        }
    }

    static func stateTone(for state: String) -> PresentationTone {
        switch state {
        case "Running":
            return .positive
        case "Suspended":
            return .caution
        case "Terminated":
            return .critical
        default:
            return .neutral
        }
    }

    static func localizedModeLabel(for mode: String) -> String {
        switch mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "auto", "autonomous":
            return String(localized: "Autonomous")
        case "manual":
            return String(localized: "Manual")
        case "interactive":
            return String(localized: "Interactive")
        case "scheduled":
            return String(localized: "Scheduled")
        case "on_demand", "on-demand":
            return String(localized: "On Demand")
        case "daemon":
            return String(localized: "Daemon")
        case "supervised":
            return String(localized: "Supervised")
        default:
            return StatusPresentation.localizedFallbackLabel(for: mode)
        }
    }

    static func localizedModelTierLabel(for tier: String) -> String {
        switch tier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "mini":
            return String(localized: "Mini")
        case "fast":
            return String(localized: "Fast")
        case "balanced":
            return String(localized: "Balanced")
        case "standard":
            return String(localized: "Standard")
        case "reasoning":
            return String(localized: "Reasoning")
        case "premium":
            return String(localized: "Premium")
        case "flagship":
            return String(localized: "Flagship")
        case "economy":
            return String(localized: "Economy")
        case "local":
            return String(localized: "Local")
        case "custom":
            return String(localized: "Custom")
        default:
            return StatusPresentation.localizedFallbackLabel(for: tier)
        }
    }
}

nonisolated struct AgentIdentity: Codable, Sendable {
    let emoji: String?
    let avatarUrl: String?
    let color: String?

    enum CodingKeys: String, CodingKey {
        case emoji, color
        case avatarUrl = "avatar_url"
    }
}

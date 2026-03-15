import Foundation

enum AuditEventSeverity: Int, CaseIterable {
    case info
    case warning
    case critical

    var shortLabel: String {
        switch self {
        case .info:
            String(localized: "Info")
        case .warning:
            String(localized: "Warn")
        case .critical:
            String(localized: "Critical")
        }
    }

    var symbolName: String {
        switch self {
        case .info:
            "info.circle"
        case .warning:
            "exclamationmark.triangle"
        case .critical:
            "xmark.octagon"
        }
    }

    var tone: PresentationTone {
        switch self {
        case .critical:
            return .critical
        case .warning:
            return .warning
        case .info:
            return .positive
        }
    }
}

enum AuditSeverityScope: String, CaseIterable, Identifiable {
    case all
    case critical
    case warning
    case info

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            String(localized: "All")
        case .critical:
            String(localized: "Critical")
        case .warning:
            String(localized: "Warn")
        case .info:
            String(localized: "Info")
        }
    }

    func contains(_ severity: AuditEventSeverity) -> Bool {
        switch self {
        case .all:
            true
        case .critical:
            severity == .critical
        case .warning:
            severity == .warning
        case .info:
            severity == .info
        }
    }
}

extension AuditEntry {
    var severity: AuditEventSeverity {
        let actionLower = action.lowercased()
        let outcomeLower = outcome.lowercased()
        let detailLower = detail.lowercased()

        if Self.criticalActions.contains(action)
            || actionLower.contains("fail")
            || actionLower.contains("deny")
            || actionLower.contains("error")
            || detailLower.contains("panic")
            || detailLower.contains("fatal")
            || (outcomeLower != "ok" && outcomeLower != "success" && !outcomeLower.isEmpty) {
            return .critical
        }

        if Self.warningActions.contains(action)
            || actionLower.contains("warn")
            || actionLower.contains("rate")
            || actionLower.contains("network")
            || actionLower.contains("shell")
            || actionLower.contains("file") {
            return .warning
        }

        return .info
    }

    var friendlyAction: String {
        switch action {
        case "AgentSpawn":
            String(localized: "Agent Created")
        case "AgentKill", "AgentTerminated":
            String(localized: "Agent Stopped")
        case "ToolInvoke":
            String(localized: "Tool Used")
        case "ToolResult":
            String(localized: "Tool Completed")
        case "AgentMessage":
            String(localized: "Message Received")
        case "NetworkAccess":
            String(localized: "Network Access")
        case "ShellExec":
            String(localized: "Shell Command")
        case "FileAccess":
            String(localized: "File Access")
        case "MemoryAccess":
            String(localized: "Memory Access")
        case "AuthAttempt":
            String(localized: "Login Attempt")
        case "AuthSuccess":
            String(localized: "Login Success")
        case "AuthFailure":
            String(localized: "Login Failure")
        case "CapabilityDenied":
            String(localized: "Capability Denied")
        case "RateLimited":
            String(localized: "Rate Limited")
        default:
            action.splitCamelCase
        }
    }

    func matchesSearch(_ query: String, agentName: String?) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }

        let haystack = [
            action,
            friendlyAction,
            detail,
            outcome,
            agentId,
            agentName ?? ""
        ]
        .joined(separator: " ")
        .lowercased()

        return haystack.contains(needle)
    }

    private static let criticalActions: Set<String> = [
        "AuthFailure",
        "CapabilityDenied",
        "AgentKill",
        "AgentTerminated"
    ]

    private static let warningActions: Set<String> = [
        "RateLimited",
        "NetworkAccess",
        "ShellExec",
        "FileAccess",
        "MemoryAccess",
        "ToolInvoke"
    ]
}

private extension String {
    var splitCamelCase: String {
        replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import Foundation

enum MonitoringAlertSeverity: Int {
    case info
    case warning
    case critical
}

struct MonitoringAlertItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let severity: MonitoringAlertSeverity
    let symbolName: String
}

struct AgentAttentionItem: Identifiable {
    let agent: Agent
    let pendingApprovals: Int
    let hasAuthIssue: Bool
    let isStale: Bool
    let sessionPressure: Bool
    let severity: Int
    let reasons: [String]

    var id: String { agent.id }
}

struct SessionAttentionItem: Identifiable {
    let session: SessionInfo
    let agent: Agent?
    let severity: Int
    let reasons: [String]
    let hasLabel: Bool
    let duplicateCount: Int

    var id: String { session.id }
}

extension DashboardViewModel {
    var isDataStale: Bool {
        guard let lastRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) > MonitoringThresholds.refreshStaleInterval
    }

    var hasBudgetAlert: Bool {
        guard let budget else { return false }
        let maxPct = max(budget.hourlyPct, budget.dailyPct, budget.monthlyPct)
        return budget.alertThreshold > 0 && maxPct >= budget.alertThreshold
    }

    var hasPeerNetworkIssue: Bool {
        networkStatus?.enabled == true && connectedPeerCount == 0
    }

    var hasAuditIntegrityIssue: Bool {
        auditVerify.map { !$0.valid } ?? false
    }

    var hasMCPConnectivityIssue: Bool {
        configuredMCPServerCount > 0 && connectedMCPServerCount == 0
    }

    var staleRunningAgentCount: Int {
        agents.filter { isAgentStale($0) }.count
    }

    var recentCriticalAuditCount: Int {
        recentAudit.filter { $0.severity == .critical }.count
    }

    var unlabeledSessionCount: Int {
        sessions.filter { ($0.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var highVolumeSessionCount: Int {
        sessions.filter { $0.messageCount >= MonitoringThresholds.highVolumeSessionMessages }.count
    }

    var multiSessionAgentCount: Int {
        sessionCountsByAgent.values.filter { $0 > 1 }.count
    }

    var sessionAttentionCount: Int {
        sessionAttentionItems.count
    }

    var criticalAlertCount: Int {
        monitoringAlerts.filter { $0.severity == .critical }.count
    }

    var warningAlertCount: Int {
        monitoringAlerts.filter { $0.severity == .warning }.count
    }

    var criticalAuditEntries: [AuditEntry] {
        recentAudit.filter { $0.severity == .critical }
    }

    var issueAgentCount: Int {
        attentionAgents.count
    }

    var runtimeAlertCount: Int {
        pendingApprovalCount
            + (degradedHandCount > 0 ? 1 : 0)
            + (hasPeerNetworkIssue ? 1 : 0)
            + (hasAuditIntegrityIssue ? 1 : 0)
            + (hasMCPConnectivityIssue ? 1 : 0)
            + (staleRunningAgentCount > 0 ? 1 : 0)
            + (recentCriticalAuditCount > 0 ? 1 : 0)
            + ((highVolumeSessionCount > 0 || multiSessionAgentCount > 0) ? 1 : 0)
    }

    var monitoringAlerts: [MonitoringAlertItem] {
        var items: [MonitoringAlertItem] = []

        if health?.isHealthy != true {
            items.append(MonitoringAlertItem(
                id: "server-disconnected",
                title: "Server disconnected",
                detail: "The app cannot confirm the current LibreFang status.",
                severity: .critical,
                symbolName: "bolt.horizontal.circle"
            ))
        }

        if isDataStale {
            items.append(MonitoringAlertItem(
                id: "monitoring-stale",
                title: "Monitoring data is stale",
                detail: "The dashboard has not refreshed for more than two minutes.",
                severity: .warning,
                symbolName: "clock.badge.exclamationmark"
            ))
        }

        if let budget {
            let maxPct = max(budget.hourlyPct, budget.dailyPct, budget.monthlyPct)
            if budget.alertThreshold > 0, maxPct >= budget.alertThreshold {
                items.append(MonitoringAlertItem(
                    id: "budget-threshold",
                    title: "Budget threshold reached",
                    detail: "Current spend is at \(Int(maxPct * 100))% of the configured limit.",
                    severity: .warning,
                    symbolName: "chart.line.uptrend.xyaxis"
                ))
            }
        }

        if pendingApprovalCount > 0 {
            items.append(MonitoringAlertItem(
                id: "pending-approvals",
                title: pendingApprovalCount == 1 ? "1 approval waiting" : "\(pendingApprovalCount) approvals waiting",
                detail: "Sensitive agent actions are blocked pending operator review.",
                severity: .critical,
                symbolName: "exclamationmark.shield"
            ))
        }

        if degradedHandCount > 0 {
            items.append(MonitoringAlertItem(
                id: "degraded-hands",
                title: degradedHandCount == 1 ? "1 hand degraded" : "\(degradedHandCount) hands degraded",
                detail: "At least one autonomous hand is active but not fully healthy.",
                severity: .warning,
                symbolName: "hand.raised.slash"
            ))
        }

        if hasPeerNetworkIssue {
            items.append(MonitoringAlertItem(
                id: "peer-network-idle",
                title: "Peer network idle",
                detail: "OFP networking is enabled but no peers are currently connected.",
                severity: .warning,
                symbolName: "point.3.connected.trianglepath.dotted"
            ))
        }

        if hasAuditIntegrityIssue {
            items.append(MonitoringAlertItem(
                id: "audit-integrity",
                title: "Audit chain verification failed",
                detail: auditVerify?.error ?? "The forensic chain could not be verified.",
                severity: .critical,
                symbolName: "checkmark.shield.fill"
            ))
        }

        if recentCriticalAuditCount > 0 {
            items.append(MonitoringAlertItem(
                id: "recent-critical-audit",
                title: recentCriticalAuditCount == 1 ? "1 critical audit event" : "\(recentCriticalAuditCount) critical audit events",
                detail: "Recent activity includes failures, denials, or terminated agents that should be reviewed.",
                severity: .critical,
                symbolName: "xmark.octagon"
            ))
        }

        if sessionAttentionCount > 0 {
            items.append(MonitoringAlertItem(
                id: "session-watchlist",
                title: sessionAttentionCount == 1 ? "1 session needs review" : "\(sessionAttentionCount) sessions need review",
                detail: "High-volume, unlabeled, or duplicated sessions are building up in the workspace.",
                severity: highVolumeSessionCount > 0 || multiSessionAgentCount > 0 ? .warning : .info,
                symbolName: "rectangle.stack.badge.person.crop"
            ))
        }

        if hasMCPConnectivityIssue {
            items.append(MonitoringAlertItem(
                id: "mcp-disconnected",
                title: "MCP disconnected",
                detail: "Extension servers are configured but none are currently connected.",
                severity: .warning,
                symbolName: "shippingbox"
            ))
        }

        if staleRunningAgentCount > 0 {
            items.append(MonitoringAlertItem(
                id: "stale-agents",
                title: staleRunningAgentCount == 1 ? "1 running agent looks stale" : "\(staleRunningAgentCount) running agents look stale",
                detail: "These agents are running but have not reported activity for at least 30 minutes.",
                severity: .warning,
                symbolName: "bolt.heart"
            ))
        }

        if configuredProviderCount == 0 {
            items.append(MonitoringAlertItem(
                id: "no-provider",
                title: "No provider configured",
                detail: "Agents may exist, but the model layer is not ready.",
                severity: .warning,
                symbolName: "key.slash"
            ))
        }

        if runningCount > 0 && readyChannelCount == 0 {
            items.append(MonitoringAlertItem(
                id: "no-ready-channel",
                title: "No ready delivery channel",
                detail: "Agents are running, but no configured channel currently has a valid token.",
                severity: .info,
                symbolName: "bubble.left.and.exclamationmark.bubble.right"
            ))
        }

        return items.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity.rawValue > rhs.severity.rawValue
            }
            return lhs.title.localizedCompare(rhs.title) == .orderedAscending
        }
    }

    var attentionAgents: [AgentAttentionItem] {
        agents
            .map { attentionItem(for: $0) }
            .filter { $0.severity > 0 }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return lhs.severity > rhs.severity
                }
                if lhs.agent.isRunning != rhs.agent.isRunning {
                    return lhs.agent.isRunning && !rhs.agent.isRunning
                }
                return lhs.agent.name.localizedCompare(rhs.agent.name) == .orderedAscending
            }
    }

    var sessionAttentionItems: [SessionAttentionItem] {
        sessions
            .map { sessionAttentionItem(for: $0) }
            .filter { $0.severity > 0 }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return lhs.severity > rhs.severity
                }
                return lhs.session.messageCount > rhs.session.messageCount
            }
    }

    func attentionItem(for agent: Agent) -> AgentAttentionItem {
        let approvals = pendingApprovalCount(for: agent)
        let authIssue = hasAuthIssue(for: agent)
        let stale = isAgentStale(agent)
        let sessionPressure = (sessionCountsByAgent[agent.id] ?? 0) > 1
            || sessions.contains { $0.agentId == agent.id && $0.messageCount >= MonitoringThresholds.highVolumeSessionMessages }

        var reasons: [String] = []
        if approvals > 0 {
            reasons.append(approvals == 1 ? "Approval blocked" : "\(approvals) approvals blocked")
        }
        if !agent.ready {
            reasons.append("Not ready")
        }
        if authIssue {
            reasons.append("Auth issue")
        }
        if stale {
            reasons.append("Inactive for 30m+")
        }
        if sessionPressure {
            reasons.append("Session pressure")
        }

        let severity = approvals * 10
            + (stale ? 5 : 0)
            + (!agent.ready ? 4 : 0)
            + (authIssue ? 3 : 0)
            + (sessionPressure ? 2 : 0)
            + (agent.isRunning ? 1 : 0)

        return AgentAttentionItem(
            agent: agent,
            pendingApprovals: approvals,
            hasAuthIssue: authIssue,
            isStale: stale,
            sessionPressure: sessionPressure,
            severity: severity,
            reasons: reasons
        )
    }

    func sessionAttentionItem(for session: SessionInfo) -> SessionAttentionItem {
        let agent = agents.first(where: { $0.id == session.agentId })
        let hasLabel = !((session.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let duplicateCount = sessionCountsByAgent[session.agentId] ?? 1

        var reasons: [String] = []
        var severity = 0

        if session.messageCount >= MonitoringThresholds.veryHighVolumeSessionMessages {
            reasons.append("Very high volume")
            severity += 6
        } else if session.messageCount >= MonitoringThresholds.highVolumeSessionMessages {
            reasons.append("High volume")
            severity += 4
        }

        if !hasLabel {
            reasons.append("Unlabeled")
            severity += 2
        }

        if duplicateCount > 1 {
            reasons.append("\(duplicateCount) sessions on one agent")
            severity += 4
        }

        return SessionAttentionItem(
            session: session,
            agent: agent,
            severity: severity,
            reasons: reasons,
            hasLabel: hasLabel,
            duplicateCount: duplicateCount
        )
    }

    func pendingApprovalCount(for agent: Agent) -> Int {
        approvals.filter { $0.agentId == agent.id || $0.agentName == agent.name }.count
    }

    func hasAuthIssue(for agent: Agent) -> Bool {
        guard let authStatus = agent.authStatus?.lowercased(), !authStatus.isEmpty else { return false }
        return authStatus != "configured"
    }

    private func isAgentStale(_ agent: Agent) -> Bool {
        guard agent.isRunning, let lastActive = agent.lastActive?.monitoringISO8601Date else { return false }
        return Date().timeIntervalSince(lastActive) > MonitoringThresholds.agentStaleInterval
    }

    private var sessionCountsByAgent: [String: Int] {
        Dictionary(grouping: sessions, by: \.agentId).mapValues(\.count)
    }
}

private enum MonitoringThresholds {
    static let refreshStaleInterval: TimeInterval = 120
    static let agentStaleInterval: TimeInterval = 30 * 60
    static let highVolumeSessionMessages = 40
    static let veryHighVolumeSessionMessages = 120
}

private extension String {
    var monitoringISO8601Date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: self) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: self)
    }
}

import Foundation

enum MonitoringAlertSeverity: Int {
    case info
    case warning
    case critical
}

extension MonitoringAlertSeverity {
    var localizedLabel: String {
        switch self {
        case .critical:
            return String(localized: "Critical")
        case .warning:
            return String(localized: "Warn")
        case .info:
            return String(localized: "Info")
        }
    }

    var tone: PresentationTone {
        switch self {
        case .critical:
            return .critical
        case .warning:
            return .warning
        case .info:
            return .caution
        }
    }
}

struct MonitoringAlertItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let severity: MonitoringAlertSeverity
    let symbolName: String
}

struct MonitoringSummaryStatus {
    let summary: String
    let tone: PresentationTone
}

struct AgentAttentionItem: Identifiable {
    let agent: Agent
    let pendingApprovals: Int
    let hasAuthIssue: Bool
    let isStale: Bool
    let sessionPressure: Bool
    let modelDiagnostic: AgentModelDiagnostic?
    let severity: Int
    let reasons: [String]

    var id: String { agent.id }

    var tone: PresentationTone {
        if pendingApprovals > 0 || hasAuthIssue {
            return .critical
        }
        return severity > 0 ? .warning : .neutral
    }
}

struct SessionAttentionItem: Identifiable {
    let session: SessionInfo
    let agent: Agent?
    let severity: Int
    let reasons: [String]
    let hasLabel: Bool
    let duplicateCount: Int

    var id: String { session.id }

    var tone: PresentationTone {
        if severity >= 6 {
            return .critical
        }
        return severity > 0 ? .warning : .neutral
    }

    var messageCountTone: PresentationTone {
        if session.messageCount >= MonitoringThresholds.veryHighVolumeSessionMessages {
            return .critical
        }
        return session.messageCount >= MonitoringThresholds.highVolumeSessionMessages ? .warning : .neutral
    }
}

extension DashboardViewModel {
    var runningAgentStatus: MonitoringSummaryStatus {
        if runningCount > 0 {
            return MonitoringSummaryStatus(
                summary: runningCount == 1
                    ? String(localized: "1 running")
                    : String(localized: "\(runningCount) running"),
                tone: .positive
            )
        }
        return MonitoringSummaryStatus(
            summary: String(localized: "Idle"),
            tone: .neutral
        )
    }

    var agentAttentionStatus: MonitoringSummaryStatus {
        if issueAgentCount == 0 {
            return MonitoringSummaryStatus(
                summary: String(localized: "Stable"),
                tone: .neutral
            )
        }
        return MonitoringSummaryStatus(
            summary: issueAgentCount == 1
                ? String(localized: "1 needs attention")
                : String(localized: "\(issueAgentCount) need attention"),
            tone: .warning
        )
    }

    var providerReadinessStatus: MonitoringSummaryStatus {
        if configuredProviderCount > 0 {
            return MonitoringSummaryStatus(
                summary: configuredProviderCount == 1
                    ? String(localized: "1 provider ready")
                    : String(localized: "\(configuredProviderCount) providers ready"),
                tone: .positive
            )
        }
        return MonitoringSummaryStatus(
            summary: String(localized: "No provider configured"),
            tone: .warning
        )
    }

    var channelReadinessStatus: MonitoringSummaryStatus {
        if readyChannelCount > 0 {
            return MonitoringSummaryStatus(
                summary: readyChannelCount == 1
                    ? String(localized: "1 channel delivering")
                    : String(localized: "\(readyChannelCount) channels delivering"),
                tone: .positive
            )
        }
        return MonitoringSummaryStatus(
            summary: String(localized: "No channel configured"),
            tone: .neutral
        )
    }

    var handReadinessStatus: MonitoringSummaryStatus {
        if activeHandCount > 0 {
            return MonitoringSummaryStatus(
                summary: String(localized: "\(activeHandCount) active, \(degradedHandCount) degraded"),
                tone: degradedHandCount > 0 ? .warning : .positive
            )
        }
        return MonitoringSummaryStatus(
            summary: String(localized: "No active hands"),
            tone: .neutral
        )
    }

    var approvalBacklogStatus: MonitoringSummaryStatus {
        if pendingApprovalCount > 0 {
            return MonitoringSummaryStatus(
                summary: pendingApprovalCount == 1
                    ? String(localized: "1 action waiting")
                    : String(localized: "\(pendingApprovalCount) actions waiting"),
                tone: .critical
            )
        }
        return MonitoringSummaryStatus(
            summary: String(localized: "No approval backlog"),
            tone: .positive
        )
    }

    var peerConnectivityStatus: MonitoringSummaryStatus {
        if totalPeerCount > 0 {
            return MonitoringSummaryStatus(
                summary: String(localized: "\(connectedPeerCount)/\(totalPeerCount) peer links active"),
                tone: connectedPeerCount > 0 ? .positive : .neutral
            )
        }
        return MonitoringSummaryStatus(
            summary: String(localized: "No peer links discovered"),
            tone: .neutral
        )
    }

    var mcpConnectivityStatus: MonitoringSummaryStatus {
        if configuredMCPServerCount > 0 {
            return MonitoringSummaryStatus(
                summary: String(localized: "\(connectedMCPServerCount)/\(configuredMCPServerCount) MCP servers online"),
                tone: connectedMCPServerCount > 0 ? .positive : .warning
            )
        }
        return MonitoringSummaryStatus(
            summary: String(localized: "No MCP extension servers configured"),
            tone: .neutral
        )
    }

    var auditIntegrityStatus: MonitoringSummaryStatus {
        guard let auditVerify else {
            return MonitoringSummaryStatus(
                summary: String(localized: "Unavailable"),
                tone: .neutral
            )
        }
        return MonitoringSummaryStatus(
            summary: auditVerify.valid ? String(localized: "Verified") : String(localized: "Broken"),
            tone: auditVerify.valid ? .positive : .critical
        )
    }

    var catalogFreshnessIssueTone: PresentationTone {
        catalogModels.isEmpty ? .critical : .warning
    }

    var modelDriftIssueTone: PresentationTone {
        unavailableModelAgentCount > 0 ? .critical : .warning
    }

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

    var hasDiagnosticsIssue: Bool {
        hasHealthDatabaseIssue || diagnosticsConfigWarningCount > 0 || (supervisorPanicCount + supervisorRestartCount) > 0
    }

    var diagnosticsSummaryLabel: String {
        if hasHealthDatabaseIssue {
            return String(localized: "Degraded")
        }
        if hasDiagnosticsIssue {
            return String(localized: "Warn")
        }
        return String(localized: "Healthy")
    }

    var diagnosticsSummaryTone: PresentationTone {
        if hasHealthDatabaseIssue {
            return .critical
        }
        return hasDiagnosticsIssue ? .warning : .positive
    }

    var hasIntegrationIssue: Bool {
        unreachableLocalProviderCount > 0
            || channelRequiredFieldGapCount > 0
            || hasEmptyModelCatalog
            || hasCatalogFreshnessIssue
            || !agentsWithModelDiagnostics.isEmpty
    }

    var automationOverviewIssueCount: Int {
        failedWorkflowRunCount + exhaustedTriggerCount + stalledCronJobCount
    }

    var automationOverviewSummaryLabel: String {
        if automationOverviewIssueCount == 0 {
            return String(localized: "Stable")
        }
        return automationOverviewIssueCount == 1
            ? String(localized: "1 issue")
            : String(localized: "\(automationOverviewIssueCount) issues")
    }

    var automationPressureIssueCategoryCount: Int {
        (failedWorkflowRunCount > 0 ? 1 : 0)
            + (exhaustedTriggerCount > 0 ? 1 : 0)
            + (stalledCronJobCount > 0 ? 1 : 0)
    }

    var automationPressureSummaryLabel: String {
        if automationPressureIssueCategoryCount == 0 {
            return String(localized: "Stable")
        }
        return automationPressureIssueCategoryCount == 1
            ? String(localized: "1 issue")
            : String(localized: "\(automationPressureIssueCategoryCount) issues")
    }

    var automationPressureTone: PresentationTone {
        if failedWorkflowRunCount > 0 {
            return .critical
        }
        return automationPressureIssueCategoryCount > 0 ? .warning : .positive
    }

    var hasCatalogFreshnessIssue: Bool {
        isCatalogSyncStale || (catalogLastSyncDate == nil && catalogModels.isEmpty)
    }

    var integrationsOverviewIssueCount: Int {
        unreachableLocalProviderCount
            + channelRequiredFieldGapCount
            + (hasEmptyModelCatalog ? 1 : 0)
            + (hasCatalogFreshnessIssue ? 1 : 0)
            + agentsWithModelDiagnostics.count
    }

    var integrationsOverviewSummaryLabel: String {
        if hasEmptyModelCatalog || unavailableModelAgentCount > 0 {
            return String(localized: "Degraded")
        }
        if integrationsOverviewIssueCount == 0 {
            return String(localized: "Stable")
        }
        return integrationsOverviewIssueCount == 1
            ? String(localized: "1 issue")
            : String(localized: "\(integrationsOverviewIssueCount) issues")
    }

    var integrationPressureIssueCategoryCount: Int {
        (unreachableLocalProviderCount > 0 ? 1 : 0)
            + (channelRequiredFieldGapCount > 0 ? 1 : 0)
            + (hasEmptyModelCatalog ? 1 : 0)
            + (hasCatalogFreshnessIssue ? 1 : 0)
            + (agentsWithModelDiagnostics.isEmpty ? 0 : 1)
    }

    var integrationPressureSummaryLabel: String {
        if integrationPressureIssueCategoryCount == 0 {
            return String(localized: "Stable")
        }
        return integrationPressureIssueCategoryCount == 1
            ? String(localized: "1 issue")
            : String(localized: "\(integrationPressureIssueCategoryCount) issues")
    }

    var integrationPressureTone: PresentationTone {
        if hasEmptyModelCatalog || unavailableModelAgentCount > 0 || (catalogLastSyncDate == nil && catalogModels.isEmpty) {
            return .critical
        }
        return integrationPressureIssueCategoryCount > 0 ? .warning : .positive
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

    var disabledTriggerCount: Int {
        triggers.filter { !$0.enabled }.count
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

    var hasAutomationIdleCoverage: Bool {
        (triggers.count + schedules.count + cronJobs.count) > 0 && enabledAutomationCount == 0
    }

    var runtimeAlertCount: Int {
        pendingApprovalCount
            + (degradedHandCount > 0 ? 1 : 0)
            + (hasPeerNetworkIssue ? 1 : 0)
            + (hasAuditIntegrityIssue ? 1 : 0)
            + (hasMCPConnectivityIssue ? 1 : 0)
            + (hasDiagnosticsIssue ? 1 : 0)
            + (hasIntegrationIssue ? 1 : 0)
            + (staleRunningAgentCount > 0 ? 1 : 0)
            + (recentCriticalAuditCount > 0 ? 1 : 0)
            + (failedWorkflowRunCount > 0 ? 1 : 0)
            + (exhaustedTriggerCount > 0 ? 1 : 0)
            + (stalledCronJobCount > 0 ? 1 : 0)
            + ((highVolumeSessionCount > 0 || multiSessionAgentCount > 0) ? 1 : 0)
    }

    var monitoringAlerts: [MonitoringAlertItem] {
        var items: [MonitoringAlertItem] = []

        if health?.isHealthy != true {
            items.append(MonitoringAlertItem(
                id: "server-disconnected",
                title: String(localized: "Server disconnected"),
                detail: String(localized: "The app cannot confirm the current LibreFang status."),
                severity: .critical,
                symbolName: "bolt.horizontal.circle"
            ))
        }

        if isDataStale {
            items.append(MonitoringAlertItem(
                id: "monitoring-stale",
                title: String(localized: "Monitoring data is stale"),
                detail: String(localized: "The dashboard has not refreshed for more than two minutes."),
                severity: .warning,
                symbolName: "clock.badge.exclamationmark"
            ))
        }

        if let budget {
            let maxPct = max(budget.hourlyPct, budget.dailyPct, budget.monthlyPct)
            if budget.alertThreshold > 0, maxPct >= budget.alertThreshold {
                items.append(MonitoringAlertItem(
                    id: "budget-threshold",
                    title: String(localized: "Budget threshold reached"),
                    detail: String(localized: "Current spend is at \(Int(maxPct * 100))% of the configured limit."),
                    severity: .warning,
                    symbolName: "chart.line.uptrend.xyaxis"
                ))
            }
        }

        if pendingApprovalCount > 0 {
            items.append(MonitoringAlertItem(
                id: "pending-approvals",
                title: pendingApprovalCount == 1
                    ? String(localized: "1 approval waiting")
                    : String(localized: "\(pendingApprovalCount) approvals waiting"),
                detail: String(localized: "Sensitive agent actions are blocked pending operator review."),
                severity: .critical,
                symbolName: "exclamationmark.shield"
            ))
        }

        if degradedHandCount > 0 {
            items.append(MonitoringAlertItem(
                id: "degraded-hands",
                title: degradedHandCount == 1
                    ? String(localized: "1 hand degraded")
                    : String(localized: "\(degradedHandCount) hands degraded"),
                detail: String(localized: "At least one autonomous hand is active but not fully healthy."),
                severity: .warning,
                symbolName: "hand.raised.slash"
            ))
        }

        if hasPeerNetworkIssue {
            items.append(MonitoringAlertItem(
                id: "peer-network-idle",
                title: String(localized: "Peer network idle"),
                detail: String(localized: "OFP networking is enabled but no peers are currently connected."),
                severity: .warning,
                symbolName: "point.3.connected.trianglepath.dotted"
            ))
        }

        if hasAuditIntegrityIssue {
            items.append(MonitoringAlertItem(
                id: "audit-integrity",
                title: String(localized: "Audit chain verification failed"),
                detail: auditVerify?.error ?? String(localized: "The forensic chain could not be verified."),
                severity: .critical,
                symbolName: "checkmark.shield.fill"
            ))
        }

        if recentCriticalAuditCount > 0 {
            items.append(MonitoringAlertItem(
                id: "recent-critical-audit",
                title: recentCriticalAuditCount == 1
                    ? String(localized: "1 critical audit event")
                    : String(localized: "\(recentCriticalAuditCount) critical audit events"),
                detail: String(localized: "Recent activity includes failures, denials, or terminated agents that should be reviewed."),
                severity: .critical,
                symbolName: "xmark.octagon"
            ))
        }

        if sessionAttentionCount > 0 {
            items.append(MonitoringAlertItem(
                id: "session-watchlist",
                title: sessionAttentionCount == 1
                    ? String(localized: "1 session needs review")
                    : String(localized: "\(sessionAttentionCount) sessions need review"),
                detail: String(localized: "High-volume, unlabeled, or duplicated sessions are building up in the workspace."),
                severity: highVolumeSessionCount > 0 || multiSessionAgentCount > 0 ? .warning : .info,
                symbolName: "rectangle.stack.badge.person.crop"
            ))
        }

        if hasMCPConnectivityIssue {
            items.append(MonitoringAlertItem(
                id: "mcp-disconnected",
                title: String(localized: "MCP disconnected"),
                detail: String(localized: "Extension servers are configured but none are currently connected."),
                severity: .warning,
                symbolName: "shippingbox"
            ))
        }

        if hasHealthDatabaseIssue {
            items.append(MonitoringAlertItem(
                id: "health-database",
                title: String(localized: "Kernel database degraded"),
                detail: String(localized: "Deep health diagnostics report the runtime database as unavailable or unhealthy."),
                severity: .critical,
                symbolName: "externaldrive.badge.xmark"
            ))
        }

        if diagnosticsConfigWarningCount > 0 {
            items.append(MonitoringAlertItem(
                id: "config-warnings",
                title: diagnosticsConfigWarningCount == 1
                    ? String(localized: "1 config warning")
                    : String(localized: "\(diagnosticsConfigWarningCount) config warnings"),
                detail: String(localized: "Runtime validation found configuration warnings that should be reviewed in diagnostics."),
                severity: .warning,
                symbolName: "gear.badge.questionmark"
            ))
        }

        let supervisorEvents = supervisorPanicCount + supervisorRestartCount
        if supervisorEvents > 0 {
            items.append(MonitoringAlertItem(
                id: "supervisor-events",
                title: supervisorEvents == 1
                    ? String(localized: "1 supervisor event")
                    : String(localized: "\(supervisorEvents) supervisor events"),
                detail: String(localized: "\(supervisorPanicCount) panics and \(supervisorRestartCount) restarts have been observed since startup."),
                severity: supervisorPanicCount > 0 ? .critical : .warning,
                symbolName: "bolt.trianglebadge.exclamationmark"
            ))
        }

        if staleRunningAgentCount > 0 {
            items.append(MonitoringAlertItem(
                id: "stale-agents",
                title: staleRunningAgentCount == 1
                    ? String(localized: "1 running agent looks stale")
                    : String(localized: "\(staleRunningAgentCount) running agents look stale"),
                detail: String(localized: "These agents are running but have not reported activity for at least 30 minutes."),
                severity: .warning,
                symbolName: "bolt.heart"
            ))
        }

        if failedWorkflowRunCount > 0 {
            items.append(MonitoringAlertItem(
                id: "workflow-runs-failed",
                title: failedWorkflowRunCount == 1
                    ? String(localized: "1 workflow run failed")
                    : String(localized: "\(failedWorkflowRunCount) workflow runs failed"),
                detail: String(localized: "Automation pipelines recently stopped in a failed state and should be reviewed."),
                severity: .warning,
                symbolName: "point.3.filled.connected.trianglepath.dotted"
            ))
        }

        if exhaustedTriggerCount > 0 {
            items.append(MonitoringAlertItem(
                id: "trigger-budget-exhausted",
                title: exhaustedTriggerCount == 1
                    ? String(localized: "1 trigger exhausted")
                    : String(localized: "\(exhaustedTriggerCount) triggers exhausted"),
                detail: String(localized: "Event-driven automations hit their max fire count and will no longer wake agents."),
                severity: .warning,
                symbolName: "bolt.badge.clock"
            ))
        }

        if stalledCronJobCount > 0 {
            items.append(MonitoringAlertItem(
                id: "cron-next-run-missing",
                title: stalledCronJobCount == 1
                    ? String(localized: "1 cron job missing next run")
                    : String(localized: "\(stalledCronJobCount) cron jobs missing next run"),
                detail: String(localized: "Enabled cron jobs exist without a next execution time in the scheduler."),
                severity: .warning,
                symbolName: "calendar.badge.exclamationmark"
            ))
        }

        if hasAutomationIdleCoverage {
            items.append(MonitoringAlertItem(
                id: "automation-idle",
                title: String(localized: "Automation inventory is idle"),
                detail: String(localized: "Triggers, schedules, or cron jobs exist, but all of them are currently disabled."),
                severity: .info,
                symbolName: "pause.circle"
            ))
        }

        if configuredProviderCount == 0 {
            items.append(MonitoringAlertItem(
                id: "no-provider",
                title: String(localized: "No provider configured"),
                detail: String(localized: "Agents may exist, but the model layer is not ready."),
                severity: .warning,
                symbolName: "key.slash"
            ))
        }

        if unreachableLocalProviderCount > 0 {
            items.append(MonitoringAlertItem(
                id: "local-provider-unreachable",
                title: unreachableLocalProviderCount == 1
                    ? String(localized: "1 local provider unreachable")
                    : String(localized: "\(unreachableLocalProviderCount) local providers unreachable"),
                detail: String(localized: "At least one local model endpoint probe failed. Review provider diagnostics for reachability and latency."),
                severity: .warning,
                symbolName: "network.slash"
            ))
        }

        if hasEmptyModelCatalog {
            items.append(MonitoringAlertItem(
                id: "no-available-models",
                title: String(localized: "No available models in catalog"),
                detail: String(localized: "Providers are configured, but the model catalog currently shows no available models for agent execution."),
                severity: .warning,
                symbolName: "square.stack.3d.up.slash"
            ))
        }

        if channelRequiredFieldGapCount > 0 {
            items.append(MonitoringAlertItem(
                id: "channel-credential-gap",
                title: channelRequiredFieldGapCount == 1
                    ? String(localized: "1 configured channel missing required fields")
                    : String(localized: "\(channelRequiredFieldGapCount) configured channels missing required fields"),
                detail: String(localized: "Some configured delivery channels are missing required secrets or config fields."),
                severity: .info,
                symbolName: "bubble.left.and.exclamationmark.bubble.right"
            ))
        }

        if !agentsWithModelDiagnostics.isEmpty {
            items.append(MonitoringAlertItem(
                id: "agent-model-drift",
                title: agentsWithModelDiagnostics.count == 1
                    ? String(localized: "1 agent has model drift")
                    : String(localized: "\(agentsWithModelDiagnostics.count) agents have model drift"),
                detail: String(localized: "Some agents point at unavailable, unknown, or provider-mismatched catalog models."),
                severity: unavailableModelAgentCount > 0 ? .warning : .info,
                symbolName: "square.stack.3d.up.slash"
            ))
        }

        if runningCount > 0 && readyChannelCount == 0 {
            items.append(MonitoringAlertItem(
                id: "no-ready-channel",
                title: String(localized: "No ready delivery channel"),
                detail: String(localized: "Agents are running, but no configured channel currently has a valid token."),
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
        let modelDiagnostic = modelDiagnostic(for: agent)

        var reasons: [String] = []
        if approvals > 0 {
            reasons.append(approvals == 1
                ? String(localized: "Approval blocked")
                : String(localized: "\(approvals) approvals blocked"))
        }
        if !agent.ready {
            reasons.append(String(localized: "Not ready"))
        }
        if authIssue {
            reasons.append(String(localized: "Auth issue"))
        }
        if stale {
            reasons.append(String(localized: "Inactive for 30m+"))
        }
        if sessionPressure {
            reasons.append(String(localized: "Session pressure"))
        }
        if let modelDiagnostic {
            reasons.append(modelDiagnostic.issueSummary)
        }

        let severity = approvals * 10
            + (stale ? 5 : 0)
            + (!agent.ready ? 4 : 0)
            + (authIssue ? 3 : 0)
            + (sessionPressure ? 2 : 0)
            + (modelDiagnostic?.severity ?? 0)
            + (agent.isRunning ? 1 : 0)

        return AgentAttentionItem(
            agent: agent,
            pendingApprovals: approvals,
            hasAuthIssue: authIssue,
            isStale: stale,
            sessionPressure: sessionPressure,
            modelDiagnostic: modelDiagnostic,
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
            reasons.append(String(localized: "Very high volume"))
            severity += 6
        } else if session.messageCount >= MonitoringThresholds.highVolumeSessionMessages {
            reasons.append(String(localized: "High volume"))
            severity += 4
        }

        if !hasLabel {
            reasons.append(String(localized: "Unlabeled"))
            severity += 2
        }

        if duplicateCount > 1 {
            reasons.append(String(localized: "\(duplicateCount) sessions on one agent"))
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

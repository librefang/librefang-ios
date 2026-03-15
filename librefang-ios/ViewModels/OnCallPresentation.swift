import Foundation

enum OnCallPrioritySeverity: Int {
    case advisory
    case warning
    case critical

    var label: String {
        switch self {
        case .advisory:
            String(localized: "Advisory")
        case .warning:
            String(localized: "Warning")
        case .critical:
            String(localized: "Critical")
        }
    }

    var tone: PresentationTone {
        switch self {
        case .advisory:
            return .caution
        case .warning:
            return .warning
        case .critical:
            return .critical
        }
    }
}

enum OnCallRoute: Hashable {
    case incidents
    case approvals
    case agent(String)
    case sessionsAttention
    case sessionsSearch(String)
    case eventsCritical
    case eventsSearch(String)
    case automation
    case integrations
    case integrationsAttention
    case integrationsSearch(String)
    case handoffCenter
}

struct OnCallPriorityItem: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let footnote: String
    let symbolName: String
    let severity: OnCallPrioritySeverity
    let rank: Int
    let route: OnCallRoute
}

extension OnCallRoute {
    var launchTarget: AppShortcutLaunchTarget {
        switch self {
        case .incidents:
            return .surface(.incidents)
        case .approvals:
            return .surface(.approvals)
        case .agent(let id):
            return .agent(id)
        case .sessionsAttention:
            return .sessionsAttention
        case .sessionsSearch(let query):
            return .sessionsSearch(query)
        case .eventsCritical:
            return .eventsCritical
        case .eventsSearch(let query):
            return .eventsSearch(query)
        case .automation:
            return .surface(.automation)
        case .integrations:
            return .surface(.integrations)
        case .integrationsAttention:
            return .integrationsAttention
        case .integrationsSearch(let query):
            return .integrationsSearch(query)
        case .handoffCenter:
            return .surface(.handoffCenter)
        }
    }
}

extension DashboardViewModel {
    func onCallPriorityItems(
        visibleAlerts: [MonitoringAlertItem],
        watchedAttentionItems: [AgentAttentionItem],
        handoffCheckInStatus: HandoffCheckInStatus? = nil,
        handoffFollowUpStatuses: [HandoffFollowUpStatus] = []
    ) -> [OnCallPriorityItem] {
        var items: [OnCallPriorityItem] = []

        items.append(contentsOf: visibleAlerts.map { alert in
            OnCallPriorityItem(
                id: "alert:\(alert.id)",
                title: alert.title,
                detail: alert.detail,
                footnote: String(localized: "Monitoring alert"),
                symbolName: alert.symbolName,
                severity: onCallSeverity(for: alert.severity),
                rank: onCallRank(for: alert.severity),
                route: .incidents
            )
        })

        items.append(contentsOf: approvals.prefix(5).map { approval in
            let risk = approval.riskLevel.lowercased()
            let severity: OnCallPrioritySeverity = (risk.contains("critical") || risk.contains("high")) ? .critical : .warning
            let rank = severity == .critical ? 95 : 84
            let requested = approval.requestedAt.onCallRelativeTimestamp ?? String(localized: "Awaiting review")

            return OnCallPriorityItem(
                id: "approval:\(approval.id)",
                title: approval.actionSummary,
                detail: "\(approval.agentName) · \(approval.toolName)",
                footnote: String(localized: "Approval requested \(requested)"),
                symbolName: "exclamationmark.shield",
                severity: severity,
                rank: rank,
                route: .approvals
            )
        })

        items.append(contentsOf: watchedAttentionItems
            .filter { $0.severity > 0 }
            .map { item in
                let severity: OnCallPrioritySeverity
                if item.pendingApprovals > 0 || item.hasAuthIssue {
                    severity = .critical
                } else if item.isStale || item.sessionPressure || !item.agent.ready {
                    severity = .warning
                } else {
                    severity = .advisory
                }

                let lead = item.reasons.first ?? String(localized: "Needs review")
                return OnCallPriorityItem(
                    id: "watched-agent:\(item.agent.id)",
                    title: item.agent.name,
                    detail: item.reasons.prefix(2).joined(separator: " • "),
                    footnote: String(localized: "Watched agent · \(lead)"),
                    symbolName: "star.fill",
                    severity: severity,
                    rank: 70 + min(item.severity, 20),
                    route: .agent(item.agent.id)
                )
            })

        items.append(contentsOf: criticalAuditEntries.prefix(4).map { entry in
            let target = agents.first(where: { $0.id == entry.agentId })?.name ?? String(entry.agentId.prefix(8))
            return OnCallPriorityItem(
                id: "audit:\(entry.id)",
                title: entry.friendlyAction,
                detail: entry.detail.isEmpty ? target : "\(target) · \(entry.detail)",
                footnote: String(localized: "Critical event \(entry.timestamp.onCallRelativeTimestamp ?? "")")
                    .trimmingCharacters(in: .whitespaces),
                symbolName: entry.severity.symbolName,
                severity: .critical,
                rank: 78,
                route: entry.agentId.isEmpty ? .eventsCritical : .eventsSearch(entry.agentId)
            )
        })

        items.append(contentsOf: sessionAttentionItems
            .filter { item in
                item.severity >= 6 || watchedAttentionItems.contains(where: { $0.agent.id == item.session.agentId })
            }
            .prefix(4)
            .map { item in
                let watched = watchedAttentionItems.contains(where: { $0.agent.id == item.session.agentId })
                let severity: OnCallPrioritySeverity = item.severity >= 6 ? .warning : .advisory
                let title = (item.session.label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? item.session.label!
                    : String(item.session.sessionId.prefix(8))
                let owner = item.agent?.name ?? item.session.agentId
                let sessionQuery = item.agent?.id ?? item.session.agentId

                return OnCallPriorityItem(
                    id: "session:\(item.id)",
                    title: title,
                    detail: String(localized: "\(owner) · \(item.session.messageCount) msgs"),
                    footnote: watched
                        ? String(localized: "Watched agent session pressure")
                        : item.reasons.prefix(2).joined(separator: " • "),
                    symbolName: "rectangle.stack",
                    severity: severity,
                    rank: watched ? 72 : 62,
                    route: sessionQuery.isEmpty ? .sessionsAttention : .sessionsSearch(sessionQuery)
                )
            })

        items.append(contentsOf: onCallAutomationItems())

        items.append(contentsOf: onCallIntegrationItems())

        if let checkInItem = onCallCheckInItem(for: handoffCheckInStatus) {
            items.append(checkInItem)
        }

        if let followUpItem = onCallFollowUpItem(
            for: handoffFollowUpStatuses,
            handoffCheckInStatus: handoffCheckInStatus
        ) {
            items.append(followUpItem)
        }

        return items
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank > rhs.rank
                }
                return lhs.title.localizedCompare(rhs.title) == .orderedAscending
            }
    }

    func onCallDigestLine(
        visibleAlerts: [MonitoringAlertItem],
        watchedAttentionItems: [AgentAttentionItem],
        mutedAlertCount: Int,
        isAcknowledged: Bool,
        handoffCheckInStatus: HandoffCheckInStatus? = nil,
        handoffFollowUpStatuses: [HandoffFollowUpStatus] = []
    ) -> String {
        let liveCritical = visibleAlerts.filter { $0.severity == .critical }.count
        let watchIssues = watchedAttentionItems.filter { $0.severity > 0 }.count
        let automationSummary = automationDigestSummary()
        let integrationsSummary = integrationsDigestSummary()
        let checkInSummary = checkInDigestSummary(for: handoffCheckInStatus)
        let followUpSummary = followUpDigestSummary(
            for: handoffFollowUpStatuses,
            handoffCheckInStatus: handoffCheckInStatus
        )

        if !visibleAlerts.isEmpty {
            if isAcknowledged {
                let base = liveCritical > 0
                    ? String(localized: "\(liveCritical) critical items acknowledged on this iPhone")
                    : String(localized: "\(visibleAlerts.count) live alerts acknowledged on this iPhone")
                return [base, automationSummary, integrationsSummary, checkInSummary, followUpSummary].compactMap { $0 }.joined(separator: " · ")
            }

            return [
                String(localized: "\(visibleAlerts.count) live alerts"),
                String(localized: "\(pendingApprovalCount) approvals"),
                String(localized: "\(watchIssues) watched agents need review"),
                automationSummary,
                integrationsSummary,
                checkInSummary,
                followUpSummary
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
        }

        if mutedAlertCount > 0 {
            let base = mutedAlertCount == 1
                ? String(localized: "1 alert is muted locally; watchlist and sessions remain active")
                : String(localized: "\(mutedAlertCount) alerts are muted locally; watchlist and sessions remain active")
            return [base, automationSummary, integrationsSummary, checkInSummary, followUpSummary].compactMap { $0 }.joined(separator: " · ")
        }

        if watchIssues > 0 {
            return [
                String(localized: "\(watchIssues) watched agents still need review even though no live alert card is visible"),
                automationSummary,
                integrationsSummary,
                checkInSummary,
                followUpSummary
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
        }

        if let automationSummary, let integrationsSummary, let checkInSummary, let followUpSummary {
            return [automationSummary, integrationsSummary, checkInSummary, followUpSummary].joined(separator: " · ")
        }

        let remainingSummaries = [automationSummary, integrationsSummary, checkInSummary, followUpSummary].compactMap { $0 }
        if !remainingSummaries.isEmpty {
            return remainingSummaries.joined(separator: " · ")
        }

        return String(localized: "No live alerts. Monitoring is currently in a calm state on this iPhone.")
    }

    private func onCallIntegrationItems() -> [OnCallPriorityItem] {
        var items: [OnCallPriorityItem] = []

        if !unreachableLocalProviders.isEmpty {
            let preview = unreachableLocalProviders.prefix(2).map(\.displayName).joined(separator: " • ")
            let allLocalProvidersDown = localProviderCount > 0 && unreachableLocalProviderCount >= localProviderCount
            let route: OnCallRoute = unreachableLocalProviders.count == 1
                ? .integrationsSearch(unreachableLocalProviders[0].displayName)
                : .integrationsAttention
            items.append(OnCallPriorityItem(
                id: "integrations:providers",
                title: unreachableLocalProviderCount == 1
                    ? String(localized: "1 local provider unreachable")
                    : String(localized: "\(unreachableLocalProviderCount) local providers unreachable"),
                detail: preview.isEmpty ? String(localized: "Review local model endpoints and provider probes.") : preview,
                footnote: allLocalProvidersDown
                    ? String(localized: "All local providers in the latest snapshot are down")
                    : String(localized: "Local provider probes are failing"),
                symbolName: "network.slash",
                severity: allLocalProvidersDown ? .critical : .warning,
                rank: allLocalProvidersDown ? 88 : 78,
                route: route
            ))
        }

        if channelRequiredFieldGapCount > 0 {
            let preview = channelsMissingRequiredFields.prefix(2).map(\.displayName).joined(separator: " • ")
            let route: OnCallRoute = channelsMissingRequiredFields.count == 1
                ? .integrationsSearch(channelsMissingRequiredFields[0].displayName)
                : .integrationsAttention
            items.append(OnCallPriorityItem(
                id: "integrations:channels",
                title: channelRequiredFieldGapCount == 1
                    ? String(localized: "1 channel missing required fields")
                    : String(localized: "\(channelRequiredFieldGapCount) channels missing required fields"),
                detail: preview.isEmpty ? String(localized: "Configured delivery channels are missing required secrets or config fields.") : preview,
                footnote: missingRequiredChannelFieldCount == 1
                    ? String(localized: "1 required channel field missing")
                    : String(localized: "\(missingRequiredChannelFieldCount) required channel fields missing"),
                symbolName: "bubble.left.and.exclamationmark.bubble.right",
                severity: .warning,
                rank: 70,
                route: route
            ))
        }

        if hasEmptyModelCatalog {
            items.append(OnCallPriorityItem(
                id: "integrations:catalog-empty",
                title: String(localized: "Model catalog has no available models"),
                detail: String(localized: "Providers are configured, but LibreFang currently exposes zero executable catalog models."),
                footnote: String(localized: "Catalog / provider hub"),
                symbolName: "square.stack.3d.up.slash",
                severity: .critical,
                rank: 87,
                route: .integrationsAttention
            ))
        }

        if !agentsWithModelDiagnostics.isEmpty {
            let unavailableCount = unavailableModelAgentCount
            let title: String
            if unavailableCount > 0 {
                title = unavailableCount == 1
                    ? String(localized: "1 agent on unavailable model")
                    : String(localized: "\(unavailableCount) agents on unavailable models")
            } else {
                title = agentsWithModelDiagnostics.count == 1
                    ? String(localized: "1 agent has model drift")
                    : String(localized: "\(agentsWithModelDiagnostics.count) agents have model drift")
            }
            let preview = agentsWithModelDiagnostics.prefix(2).map(\.agent.name).joined(separator: " • ")
            let route: OnCallRoute = agentsWithModelDiagnostics.count == 1
                ? .integrationsSearch(agentsWithModelDiagnostics[0].agent.name)
                : .integrationsAttention
            items.append(
                OnCallPriorityItem(
                    id: "integrations:model-drift",
                    title: title,
                    detail: preview.isEmpty ? String(localized: "Review provider and model catalog drift in integrations diagnostics.") : preview,
                    footnote: String(localized: "Model catalog / provider mismatch"),
                    symbolName: "square.stack.3d.up.slash",
                    severity: unavailableCount > 0 ? .warning : .advisory,
                    rank: unavailableCount > 0 ? 76 : 66,
                    route: route
                )
            )
        }

        return items
    }

    private func onCallAutomationItems() -> [OnCallPriorityItem] {
        var items: [OnCallPriorityItem] = []

        if failedWorkflowRunCount > 0 {
            items.append(OnCallPriorityItem(
                id: "automation:workflow-failures",
                title: failedWorkflowRunCount == 1
                    ? String(localized: "1 workflow run failed")
                    : String(localized: "\(failedWorkflowRunCount) workflow runs failed"),
                detail: workflowRuns
                    .filter { $0.state == .failed }
                    .prefix(2)
                    .map(\.workflowName)
                    .joined(separator: " • "),
                footnote: String(localized: "Automation monitor"),
                symbolName: "flowchart",
                severity: failedWorkflowRunCount >= 2 ? .critical : .warning,
                rank: failedWorkflowRunCount >= 2 ? 86 : 74,
                route: .automation
            ))
        }

        if exhaustedTriggerCount > 0 {
            items.append(OnCallPriorityItem(
                id: "automation:trigger-exhausted",
                title: exhaustedTriggerCount == 1
                    ? String(localized: "1 trigger exhausted")
                    : String(localized: "\(exhaustedTriggerCount) triggers exhausted"),
                detail: String(localized: "Event-driven wakeups reached max fire count and stopped dispatching."),
                footnote: String(localized: "Automation monitor"),
                symbolName: "bolt.badge.clock",
                severity: .warning,
                rank: 72,
                route: .automation
            ))
        }

        if stalledCronJobCount > 0 {
            items.append(OnCallPriorityItem(
                id: "automation:cron-stalled",
                title: stalledCronJobCount == 1
                    ? String(localized: "1 cron job missing next run")
                    : String(localized: "\(stalledCronJobCount) cron jobs missing next run"),
                detail: String(localized: "Enabled scheduler entries exist without a next execution timestamp."),
                footnote: String(localized: "Automation monitor"),
                symbolName: "calendar.badge.exclamationmark",
                severity: .warning,
                rank: 75,
                route: .automation
            ))
        }

        return items
    }

    private func automationDigestSummary() -> String? {
        if failedWorkflowRunCount > 0 && stalledCronJobCount > 0 {
            return String(localized: "\(failedWorkflowRunCount) workflow failures and \(stalledCronJobCount) stalled cron jobs")
        }
        if failedWorkflowRunCount > 0 {
            return failedWorkflowRunCount == 1
                ? String(localized: "1 workflow failure needs review")
                : String(localized: "\(failedWorkflowRunCount) workflow failures need review")
        }
        if exhaustedTriggerCount > 0 && stalledCronJobCount > 0 {
            return String(localized: "\(exhaustedTriggerCount) exhausted triggers and \(stalledCronJobCount) stalled cron jobs")
        }
        if exhaustedTriggerCount > 0 {
            return exhaustedTriggerCount == 1
                ? String(localized: "1 trigger is exhausted")
                : String(localized: "\(exhaustedTriggerCount) triggers are exhausted")
        }
        if stalledCronJobCount > 0 {
            return stalledCronJobCount == 1
                ? String(localized: "1 cron job is missing a next run")
                : String(localized: "\(stalledCronJobCount) cron jobs are missing a next run")
        }
        return nil
    }

    private func integrationsDigestSummary() -> String? {
        if hasEmptyModelCatalog {
            return String(localized: "model catalog has no available models")
        }
        if !unreachableLocalProviders.isEmpty && channelRequiredFieldGapCount > 0 {
            return String(localized: "\(unreachableLocalProviderCount) local providers unreachable and \(channelRequiredFieldGapCount) channels missing required fields")
        }
        if !unreachableLocalProviders.isEmpty {
            return unreachableLocalProviderCount == 1
                ? String(localized: "1 local provider is unreachable")
                : String(localized: "\(unreachableLocalProviderCount) local providers are unreachable")
        }
        if channelRequiredFieldGapCount > 0 {
            return channelRequiredFieldGapCount == 1
                ? String(localized: "1 configured channel is missing required fields")
                : String(localized: "\(channelRequiredFieldGapCount) configured channels are missing required fields")
        }
        if !agentsWithModelDiagnostics.isEmpty {
            return agentsWithModelDiagnostics.count == 1
                ? String(localized: "1 agent still has model drift")
                : String(localized: "\(agentsWithModelDiagnostics.count) agents still have model drift")
        }
        return nil
    }

    private func onCallSeverity(for severity: MonitoringAlertSeverity) -> OnCallPrioritySeverity {
        switch severity {
        case .critical:
            .critical
        case .warning:
            .warning
        case .info:
            .advisory
        }
    }

    private func onCallRank(for severity: MonitoringAlertSeverity) -> Int {
        switch severity {
        case .critical:
            100
        case .warning:
            68
        case .info:
            52
        }
    }

    private func onCallCheckInItem(for status: HandoffCheckInStatus?) -> OnCallPriorityItem? {
        guard let status else { return nil }

        switch status.state {
        case .scheduled:
            return nil
        case .dueSoon:
            return OnCallPriorityItem(
                id: "handoff-checkin:due-soon",
                title: String(localized: "Handoff check-in due soon"),
                detail: status.dueLabel,
                footnote: String(localized: "Local handoff checkpoint \(RelativeDateTimeFormatter().localizedString(for: status.baseline.createdAt, relativeTo: Date()))"),
                symbolName: "timer",
                severity: .warning,
                rank: 76,
                route: .handoffCenter
            )
        case .overdue:
            return OnCallPriorityItem(
                id: "handoff-checkin:overdue",
                title: String(localized: "Handoff check-in overdue"),
                detail: status.dueLabel,
                footnote: String(localized: "Local handoff checkpoint \(RelativeDateTimeFormatter().localizedString(for: status.baseline.createdAt, relativeTo: Date()))"),
                symbolName: "timer",
                severity: .critical,
                rank: 92,
                route: .handoffCenter
            )
        }
    }

    private func checkInDigestSummary(for status: HandoffCheckInStatus?) -> String? {
        guard let status else { return nil }

        switch status.state {
        case .scheduled:
            return nil
        case .dueSoon:
            return String(localized: "handoff check-in due soon")
        case .overdue:
            return String(localized: "handoff check-in overdue")
        }
    }

    private func onCallFollowUpItem(
        for statuses: [HandoffFollowUpStatus],
        handoffCheckInStatus: HandoffCheckInStatus?
    ) -> OnCallPriorityItem? {
        let pending = statuses.filter { !$0.isCompleted }
        guard !pending.isEmpty else { return nil }

        let pendingPreview = pending.prefix(2).map(\.item).joined(separator: " • ")
        let detail: String
        if let handoffCheckInStatus, handoffCheckInStatus.state != .scheduled {
            detail = pendingPreview.isEmpty
                ? handoffCheckInStatus.dueLabel
                : "\(handoffCheckInStatus.dueLabel) · \(pendingPreview)"
        } else {
            detail = pendingPreview
        }

        let title: String
        let footnote: String
        let severity: OnCallPrioritySeverity
        let rank: Int

        switch handoffCheckInStatus?.state {
        case .overdue:
            title = pending.count == 1
                ? String(localized: "1 handoff follow-up overdue")
                : String(localized: "\(pending.count) handoff follow-ups overdue")
            footnote = String(localized: "Local handoff check-in is overdue with open follow-ups")
            severity = .critical
            rank = 90
        case .dueSoon:
            title = pending.count == 1
                ? String(localized: "1 handoff follow-up open before check-in")
                : String(localized: "\(pending.count) handoff follow-ups open before check-in")
            footnote = String(localized: "Local handoff checkpoint is due soon")
            severity = pending.count >= 3 ? .critical : .warning
            rank = pending.count >= 3 ? 82 : 76
        case .scheduled, .none:
            title = pending.count == 1
                ? String(localized: "1 handoff follow-up still open")
                : String(localized: "\(pending.count) handoff follow-ups still open")
            footnote = String(localized: "Latest local handoff follow-through")
            severity = pending.count >= 3 ? .warning : .advisory
            rank = pending.count >= 3 ? 74 : 64
        }

        return OnCallPriorityItem(
            id: "handoff-followups",
            title: title,
            detail: detail,
            footnote: footnote,
            symbolName: "checklist",
            severity: severity,
            rank: rank,
            route: .handoffCenter
        )
    }

    private func followUpDigestSummary(
        for statuses: [HandoffFollowUpStatus],
        handoffCheckInStatus: HandoffCheckInStatus?
    ) -> String? {
        let pendingCount = statuses.filter { !$0.isCompleted }.count
        guard pendingCount > 0 else { return nil }

        switch handoffCheckInStatus?.state {
        case .overdue:
            return pendingCount == 1
                ? String(localized: "1 handoff follow-up is still open after the local check-in deadline")
                : String(localized: "\(pendingCount) handoff follow-ups are still open after the local check-in deadline")
        case .dueSoon:
            return pendingCount == 1
                ? String(localized: "1 handoff follow-up is still open before the next local check-in")
                : String(localized: "\(pendingCount) handoff follow-ups are still open before the next local check-in")
        case .scheduled, .none:
            return pendingCount == 1
                ? String(localized: "1 handoff follow-up still open")
                : String(localized: "\(pendingCount) handoff follow-ups still open")
        }
    }
}

private extension String {
    var onCallRelativeTimestamp: String? {
        guard let date = onCallISO8601Date else { return nil }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    var onCallISO8601Date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: self) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: self)
    }
}

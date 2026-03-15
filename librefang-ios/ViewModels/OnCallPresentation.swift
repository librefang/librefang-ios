import Foundation

enum OnCallPrioritySeverity: Int {
    case advisory
    case warning
    case critical

    var label: String {
        switch self {
        case .advisory:
            "Advisory"
        case .warning:
            "Warning"
        case .critical:
            "Critical"
        }
    }
}

enum OnCallRoute: Hashable {
    case incidents
    case agent(String)
    case sessionsAttention
    case eventsCritical
    case eventsSearch(String)
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
        case .agent(let id):
            return .agent(id)
        case .sessionsAttention:
            return .sessionsAttention
        case .eventsCritical:
            return .eventsCritical
        case .eventsSearch(let query):
            return .eventsSearch(query)
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
                footnote: "Monitoring alert",
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
            let requested = approval.requestedAt.onCallRelativeTimestamp ?? "Awaiting review"

            return OnCallPriorityItem(
                id: "approval:\(approval.id)",
                title: approval.actionSummary,
                detail: "\(approval.agentName) · \(approval.toolName)",
                footnote: "Approval requested \(requested)",
                symbolName: "exclamationmark.shield",
                severity: severity,
                rank: rank,
                route: .incidents
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

                let lead = item.reasons.first ?? "Needs review"
                return OnCallPriorityItem(
                    id: "watched-agent:\(item.agent.id)",
                    title: item.agent.name,
                    detail: item.reasons.prefix(2).joined(separator: " • "),
                    footnote: "Watched agent · \(lead)",
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
                footnote: "Critical event \(entry.timestamp.onCallRelativeTimestamp ?? "")".trimmingCharacters(in: .whitespaces),
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

                return OnCallPriorityItem(
                    id: "session:\(item.id)",
                    title: title,
                    detail: "\(owner) · \(item.session.messageCount) msgs",
                    footnote: watched ? "Watched agent session pressure" : item.reasons.prefix(2).joined(separator: " • "),
                    symbolName: "rectangle.stack",
                    severity: severity,
                    rank: watched ? 72 : 62,
                    route: item.agent.map { .agent($0.id) } ?? .sessionsAttention
                )
            })

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
        let checkInSummary = checkInDigestSummary(for: handoffCheckInStatus)
        let followUpSummary = followUpDigestSummary(
            for: handoffFollowUpStatuses,
            handoffCheckInStatus: handoffCheckInStatus
        )

        if !visibleAlerts.isEmpty {
            if isAcknowledged {
                let base = liveCritical > 0
                    ? "\(liveCritical) critical items acknowledged on this iPhone"
                    : "\(visibleAlerts.count) live alerts acknowledged on this iPhone"
                return [base, checkInSummary, followUpSummary].compactMap { $0 }.joined(separator: " · ")
            }

            return [
                "\(visibleAlerts.count) live alerts",
                "\(pendingApprovalCount) approvals",
                "\(watchIssues) watched agents need review",
                checkInSummary,
                followUpSummary
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
        }

        if mutedAlertCount > 0 {
            let base = mutedAlertCount == 1
                ? "1 alert is muted locally; watchlist and sessions remain active"
                : "\(mutedAlertCount) alerts are muted locally; watchlist and sessions remain active"
            return [base, checkInSummary, followUpSummary].compactMap { $0 }.joined(separator: " · ")
        }

        if watchIssues > 0 {
            return [
                "\(watchIssues) watched agents still need review even though no live alert card is visible",
                checkInSummary,
                followUpSummary
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
        }

        if let checkInSummary, let followUpSummary {
            return [checkInSummary, followUpSummary].joined(separator: " · ")
        }

        if let checkInSummary {
            return checkInSummary
        }

        if let followUpSummary {
            return followUpSummary
        }

        return "No live alerts. Monitoring is currently in a calm state on this iPhone."
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
                title: "Handoff check-in due soon",
                detail: status.dueLabel,
                footnote: "Local handoff checkpoint \(RelativeDateTimeFormatter().localizedString(for: status.baseline.createdAt, relativeTo: Date()))",
                symbolName: "timer",
                severity: .warning,
                rank: 76,
                route: .handoffCenter
            )
        case .overdue:
            return OnCallPriorityItem(
                id: "handoff-checkin:overdue",
                title: "Handoff check-in overdue",
                detail: status.dueLabel,
                footnote: "Local handoff checkpoint \(RelativeDateTimeFormatter().localizedString(for: status.baseline.createdAt, relativeTo: Date()))",
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
            return "handoff check-in due soon"
        case .overdue:
            return "handoff check-in overdue"
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
                ? "1 handoff follow-up overdue"
                : "\(pending.count) handoff follow-ups overdue"
            footnote = "Local handoff check-in is overdue with open follow-ups"
            severity = .critical
            rank = 90
        case .dueSoon:
            title = pending.count == 1
                ? "1 handoff follow-up open before check-in"
                : "\(pending.count) handoff follow-ups open before check-in"
            footnote = "Local handoff checkpoint is due soon"
            severity = pending.count >= 3 ? .critical : .warning
            rank = pending.count >= 3 ? 82 : 76
        case .scheduled, .none:
            title = pending.count == 1
                ? "1 handoff follow-up still open"
                : "\(pending.count) handoff follow-ups still open"
            footnote = "Latest local handoff follow-through"
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
                ? "1 handoff follow-up is still open after the local check-in deadline"
                : "\(pendingCount) handoff follow-ups are still open after the local check-in deadline"
        case .dueSoon:
            return pendingCount == 1
                ? "1 handoff follow-up is still open before the next local check-in"
                : "\(pendingCount) handoff follow-ups are still open before the next local check-in"
        case .scheduled, .none:
            return pendingCount == 1
                ? "1 handoff follow-up still open"
                : "\(pendingCount) handoff follow-ups still open"
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

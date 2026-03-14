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

extension DashboardViewModel {
    func onCallPriorityItems(
        visibleAlerts: [MonitoringAlertItem],
        watchedAttentionItems: [AgentAttentionItem]
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
        isAcknowledged: Bool
    ) -> String {
        let liveCritical = visibleAlerts.filter { $0.severity == .critical }.count
        let watchIssues = watchedAttentionItems.filter { $0.severity > 0 }.count

        if !visibleAlerts.isEmpty {
            if isAcknowledged {
                return liveCritical > 0
                    ? "\(liveCritical) critical items acknowledged on this iPhone"
                    : "\(visibleAlerts.count) live alerts acknowledged on this iPhone"
            }

            return "\(visibleAlerts.count) live alerts · \(pendingApprovalCount) approvals · \(watchIssues) watched agents need review"
        }

        if mutedAlertCount > 0 {
            return mutedAlertCount == 1
                ? "1 alert is muted locally; watchlist and sessions remain active"
                : "\(mutedAlertCount) alerts are muted locally; watchlist and sessions remain active"
        }

        if watchIssues > 0 {
            return "\(watchIssues) watched agents still need review even though no live alert card is visible"
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

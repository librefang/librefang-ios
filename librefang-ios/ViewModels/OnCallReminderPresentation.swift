import Foundation

enum OnCallReminderScope: String, CaseIterable, Identifiable {
    case criticalOnly
    case liveAlerts
    case fullQueue

    var id: String { rawValue }

    var label: String {
        switch self {
        case .criticalOnly:
            "Critical Only"
        case .liveAlerts:
            "Live Alerts"
        case .fullQueue:
            "Full Queue"
        }
    }

    var summary: String {
        switch self {
        case .criticalOnly:
            "Only remind when critical items remain in the on-call queue."
        case .liveAlerts:
            "Remind for active monitoring alerts and approval backlog, but skip watchlist-only noise."
        case .fullQueue:
            "Include watchlist agents, session pressure, and critical event follow-up in reminders."
        }
    }
}

struct OnCallReminderSnapshot: Equatable {
    let signature: String
    let title: String
    let body: String
    let itemCount: Int
    let criticalCount: Int
}

extension DashboardViewModel {
    func onCallReminderSnapshot(
        visibleAlerts: [MonitoringAlertItem],
        watchedAttentionItems: [AgentAttentionItem],
        scope: OnCallReminderScope,
        isAcknowledged: Bool
    ) -> OnCallReminderSnapshot? {
        let priorityItems = reminderPriorityItems(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            scope: scope,
            isAcknowledged: isAcknowledged
        )

        guard !priorityItems.isEmpty else { return nil }

        let criticalCount = priorityItems.filter { $0.severity == .critical }.count
        let title: String
        if criticalCount > 0 {
            title = criticalCount == 1
                ? "1 critical item still needs review"
                : "\(criticalCount) critical items still need review"
        } else if priorityItems.count == 1 {
            title = priorityItems[0].title
        } else {
            title = "\(priorityItems.count) on-call items still queued"
        }

        let watchIssueCount = watchedAttentionItems.filter { $0.severity > 0 }.count
        var detailParts: [String] = []

        switch scope {
        case .criticalOnly:
            if criticalCount > 0 {
                detailParts.append(criticalCount == 1 ? "Critical on-call pressure remains active" : "\(criticalCount) critical pressures remain active")
            }
        case .liveAlerts:
            let liveAlertCount = visibleAlerts.count
            if liveAlertCount > 0 {
                detailParts.append(liveAlertCount == 1 ? "1 live alert still active" : "\(liveAlertCount) live alerts still active")
            }
        case .fullQueue:
            if watchIssueCount > 0 {
                detailParts.append(watchIssueCount == 1 ? "1 watched agent needs review" : "\(watchIssueCount) watched agents need review")
            }
            if sessionAttentionCount > 0 {
                detailParts.append(sessionAttentionCount == 1 ? "1 session hotspot remains" : "\(sessionAttentionCount) session hotspots remain")
            }
            if recentCriticalAuditCount > 0 {
                detailParts.append(recentCriticalAuditCount == 1 ? "1 critical event follow-up remains" : "\(recentCriticalAuditCount) critical event follow-ups remain")
            }
        }

        if pendingApprovalCount > 0 {
            detailParts.append(pendingApprovalCount == 1 ? "1 approval is still waiting" : "\(pendingApprovalCount) approvals are still waiting")
        }

        for item in priorityItems.prefix(2) where detailParts.count < 3 {
            if !detailParts.contains(item.title) {
                detailParts.append(item.title)
            }
        }

        let body = detailParts
            .prefix(3)
            .joined(separator: " · ")

        let signature = ([scope.rawValue] + priorityItems.map(\.id)).joined(separator: "|")

        return OnCallReminderSnapshot(
            signature: signature,
            title: title,
            body: body.isEmpty ? "Open LibreFang to review the on-call queue." : body,
            itemCount: priorityItems.count,
            criticalCount: criticalCount
        )
    }

    private func reminderPriorityItems(
        visibleAlerts: [MonitoringAlertItem],
        watchedAttentionItems: [AgentAttentionItem],
        scope: OnCallReminderScope,
        isAcknowledged: Bool
    ) -> [OnCallPriorityItem] {
        let allItems = onCallPriorityItems(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems
        )

        let acknowledgedLiveSnapshot = !visibleAlerts.isEmpty && isAcknowledged
        let watchlistOnlyItems = allItems.filter { $0.id.hasPrefix("watched-agent:") }

        switch scope {
        case .criticalOnly:
            if acknowledgedLiveSnapshot {
                return watchlistOnlyItems.filter { $0.severity == .critical }
            }

            return allItems.filter { $0.severity == .critical }
        case .liveAlerts:
            guard !acknowledgedLiveSnapshot else { return [] }
            return allItems.filter { item in
                item.id.hasPrefix("alert:") || item.id.hasPrefix("approval:")
            }
        case .fullQueue:
            return acknowledgedLiveSnapshot ? watchlistOnlyItems : allItems
        }
    }
}

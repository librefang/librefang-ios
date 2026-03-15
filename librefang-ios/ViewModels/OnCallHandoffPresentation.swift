import Foundation

extension DashboardViewModel {
    func onCallHandoffText(
        visibleAlerts: [MonitoringAlertItem],
        watchedAttentionItems: [AgentAttentionItem],
        mutedAlertCount: Int,
        isAcknowledged: Bool,
        handoffCheckInStatus: HandoffCheckInStatus? = nil,
        handoffFollowUpStatuses: [HandoffFollowUpStatus] = []
    ) -> String {
        let queue = onCallPriorityItems(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            handoffCheckInStatus: handoffCheckInStatus,
            handoffFollowUpStatuses: handoffFollowUpStatuses
        )

        let watchIssueCount = watchedAttentionItems.filter { $0.severity > 0 }.count
        let criticalCount = visibleAlerts.filter { $0.severity == .critical }.count
        let timestamp = Date().formatted(date: .abbreviated, time: .shortened)

        var lines: [String] = []
        lines.append("LibreFang on-call handoff · \(timestamp)")
        lines.append(onCallDigestLine(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            mutedAlertCount: mutedAlertCount,
            isAcknowledged: isAcknowledged,
            handoffCheckInStatus: handoffCheckInStatus,
            handoffFollowUpStatuses: handoffFollowUpStatuses
        ))
        lines.append("Live alerts: \(visibleAlerts.count) (\(criticalCount) critical)")
        lines.append("Approvals: \(pendingApprovalCount)")
        lines.append("Watchlist issues: \(watchIssueCount)")
        lines.append("Session hotspots: \(sessionAttentionCount)")
        lines.append("Critical audit events: \(recentCriticalAuditCount)")

        if let handoffCheckInStatus {
            lines.append("Handoff check-in: \(handoffCheckInStatus.state.label) · \(handoffCheckInStatus.dueLabel)")
        }

        if !handoffFollowUpStatuses.isEmpty {
            let pendingCount = handoffFollowUpStatuses.filter { !$0.isCompleted }.count
            let completedCount = handoffFollowUpStatuses.count - pendingCount
            lines.append("Handoff follow-ups: \(pendingCount) pending · \(completedCount) done")
        }

        if mutedAlertCount > 0 {
            lines.append("Muted locally: \(mutedAlertCount)")
        }

        if isAcknowledged {
            lines.append("Snapshot acknowledged on this iPhone")
        }

        if let lastRefresh {
            lines.append("Last refresh: \(RelativeDateTimeFormatter().localizedString(for: lastRefresh, relativeTo: Date()))")
        }

        if !queue.isEmpty {
            lines.append("")
            lines.append("Priority queue:")
            for item in queue.prefix(5) {
                lines.append("- \(item.title): \(item.detail)")
            }
        }

        let baseTargets: [AppShortcutLaunchTarget] = [
            .surface(.onCall),
            .surface(.incidents),
            .surface(.handoffCenter),
            .sessionsAttention,
            .eventsCritical,
        ]

        lines.append("")
        lines.append("Mobile links:")
        for target in baseTargets {
            lines.append("- \(target.label): \(target.deepLinkURL.absoluteString)")
        }

        if let leadItem = queue.first {
            let leadTarget = leadItem.route.launchTarget
            if !baseTargets.contains(leadTarget) {
                lines.append("- Lead focus (\(leadItem.title)): \(leadTarget.deepLinkURL.absoluteString)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

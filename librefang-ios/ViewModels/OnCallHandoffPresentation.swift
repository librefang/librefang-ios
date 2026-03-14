import Foundation

extension DashboardViewModel {
    func onCallHandoffText(
        visibleAlerts: [MonitoringAlertItem],
        watchedAttentionItems: [AgentAttentionItem],
        mutedAlertCount: Int,
        isAcknowledged: Bool
    ) -> String {
        let queue = onCallPriorityItems(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems
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
            isAcknowledged: isAcknowledged
        ))
        lines.append("Live alerts: \(visibleAlerts.count) (\(criticalCount) critical)")
        lines.append("Approvals: \(pendingApprovalCount)")
        lines.append("Watchlist issues: \(watchIssueCount)")
        lines.append("Session hotspots: \(sessionAttentionCount)")
        lines.append("Critical audit events: \(recentCriticalAuditCount)")

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

        return lines.joined(separator: "\n")
    }
}

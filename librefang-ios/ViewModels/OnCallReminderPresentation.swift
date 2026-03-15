import Foundation

enum OnCallReminderScope: String, CaseIterable, Identifiable {
    case criticalOnly
    case liveAlerts
    case fullQueue

    var id: String { rawValue }

    var label: String {
        switch self {
        case .criticalOnly:
            String(localized: "Critical Only")
        case .liveAlerts:
            String(localized: "Live Alerts")
        case .fullQueue:
            String(localized: "Full Queue")
        }
    }

    var summary: String {
        switch self {
        case .criticalOnly:
            String(localized: "Only remind when critical items remain in the on-call queue.")
        case .liveAlerts:
            String(localized: "Remind for active monitoring alerts and approval backlog, but skip watchlist-only noise.")
        case .fullQueue:
            String(localized: "Include watchlist agents, session pressure, and critical event follow-up in reminders.")
        }
    }
}

struct OnCallReminderSnapshot: Equatable {
    let signature: String
    let title: String
    let body: String
    let itemCount: Int
    let criticalCount: Int
    let destinationTarget: AppShortcutLaunchTarget
    let suggestedDeliveryDate: Date?
    let schedulingHint: String?
}

extension DashboardViewModel {
    func onCallReminderSnapshot(
        visibleAlerts: [MonitoringAlertItem],
        watchedAttentionItems: [AgentAttentionItem],
        scope: OnCallReminderScope,
        isAcknowledged: Bool,
        handoffCheckInStatus: HandoffCheckInStatus? = nil,
        handoffFollowUpStatuses: [HandoffFollowUpStatus] = []
    ) -> OnCallReminderSnapshot? {
        let priorityItems = reminderPriorityItems(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            scope: scope,
            isAcknowledged: isAcknowledged,
            handoffCheckInStatus: handoffCheckInStatus,
            handoffFollowUpStatuses: handoffFollowUpStatuses
        )

        guard !priorityItems.isEmpty else { return nil }

        let criticalCount = priorityItems.filter { $0.severity == .critical }.count
        let title: String
        if criticalCount > 0 {
            title = criticalCount == 1
                ? String(localized: "1 critical item still needs review")
                : String(localized: "\(criticalCount) critical items still need review")
        } else if priorityItems.count == 1 {
            title = priorityItems[0].title
        } else {
            title = String(localized: "\(priorityItems.count) on-call items still queued")
        }

        let watchIssueCount = watchedAttentionItems.filter { $0.severity > 0 }.count
        let pendingFollowUpCount = handoffFollowUpStatuses.filter { !$0.isCompleted }.count
        var detailParts: [String] = []

        switch scope {
        case .criticalOnly:
            if criticalCount > 0 {
                detailParts.append(
                    criticalCount == 1
                        ? String(localized: "Critical on-call pressure remains active")
                        : String(localized: "\(criticalCount) critical pressures remain active")
                )
            }
        case .liveAlerts:
            let liveAlertCount = visibleAlerts.count
            if liveAlertCount > 0 {
                detailParts.append(
                    liveAlertCount == 1
                        ? String(localized: "1 live alert still active")
                        : String(localized: "\(liveAlertCount) live alerts still active")
                )
            }
        case .fullQueue:
            if let handoffCheckInStatus {
                switch handoffCheckInStatus.state {
                case .scheduled:
                    break
                case .dueSoon:
                    detailParts.append(String(localized: "Handoff check-in is due soon"))
                case .overdue:
                    detailParts.append(String(localized: "Handoff check-in is overdue"))
                }
            }
            if pendingFollowUpCount > 0 {
                detailParts.append(
                    pendingFollowUpCount == 1
                        ? String(localized: "1 handoff follow-up is still open")
                        : String(localized: "\(pendingFollowUpCount) handoff follow-ups are still open")
                )
            }
            if watchIssueCount > 0 {
                detailParts.append(
                    watchIssueCount == 1
                        ? String(localized: "1 watched agent needs review")
                        : String(localized: "\(watchIssueCount) watched agents need review")
                )
            }
            if sessionAttentionCount > 0 {
                detailParts.append(
                    sessionAttentionCount == 1
                        ? String(localized: "1 session hotspot remains")
                        : String(localized: "\(sessionAttentionCount) session hotspots remain")
                )
            }
            if recentCriticalAuditCount > 0 {
                detailParts.append(
                    recentCriticalAuditCount == 1
                        ? String(localized: "1 critical event follow-up remains")
                        : String(localized: "\(recentCriticalAuditCount) critical event follow-ups remain")
                )
            }
        }

        if pendingApprovalCount > 0 {
            detailParts.append(
                pendingApprovalCount == 1
                    ? String(localized: "1 approval is still waiting")
                    : String(localized: "\(pendingApprovalCount) approvals are still waiting")
            )
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
        let includesCheckIn = priorityItems.contains { $0.id.hasPrefix("handoff-checkin:") }
        let handoffFollowUpItem = priorityItems.first { $0.id == "handoff-followups" }
        let suggestedDeliveryDate: Date?
        let schedulingHint: String?
        let destinationTarget: AppShortcutLaunchTarget

        if includesCheckIn, let handoffCheckInStatus {
            switch handoffCheckInStatus.state {
            case .scheduled:
                suggestedDeliveryDate = nil
                schedulingHint = nil
            case .dueSoon:
                suggestedDeliveryDate = handoffCheckInStatus.dueDate
                schedulingHint = String(localized: "Handoff check-in")
            case .overdue:
                suggestedDeliveryDate = Date().addingTimeInterval(30)
                schedulingHint = String(localized: "Handoff check-in overdue")
            }
            destinationTarget = .surface(.handoffCenter)
        } else if let followUpReminderDriver = followUpReminderDriver(
            for: handoffFollowUpItem,
            handoffCheckInStatus: handoffCheckInStatus
        ) {
            suggestedDeliveryDate = followUpReminderDriver.date
            schedulingHint = followUpReminderDriver.hint
            destinationTarget = handoffFollowUpItem?.route.launchTarget ?? .surface(.handoffCenter)
        } else {
            suggestedDeliveryDate = nil
            schedulingHint = nil
            destinationTarget = priorityItems.first?.route.launchTarget ?? .surface(.onCall)
        }

        return OnCallReminderSnapshot(
            signature: signature,
            title: title,
            body: body.isEmpty ? String(localized: "Open LibreFang to review the on-call queue.") : body,
            itemCount: priorityItems.count,
            criticalCount: criticalCount,
            destinationTarget: destinationTarget,
            suggestedDeliveryDate: suggestedDeliveryDate,
            schedulingHint: schedulingHint
        )
    }

    private func reminderPriorityItems(
        visibleAlerts: [MonitoringAlertItem],
        watchedAttentionItems: [AgentAttentionItem],
        scope: OnCallReminderScope,
        isAcknowledged: Bool,
        handoffCheckInStatus: HandoffCheckInStatus?,
        handoffFollowUpStatuses: [HandoffFollowUpStatus]
    ) -> [OnCallPriorityItem] {
        let allItems = onCallPriorityItems(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            handoffCheckInStatus: handoffCheckInStatus,
            handoffFollowUpStatuses: handoffFollowUpStatuses
        )

        let acknowledgedLiveSnapshot = !visibleAlerts.isEmpty && isAcknowledged
        let watchlistOnlyItems = allItems.filter { $0.id.hasPrefix("watched-agent:") }
        let handoffCheckInItems = allItems.filter { $0.id.hasPrefix("handoff-checkin:") }
        let handoffFollowUpItems = allItems.filter { $0.id == "handoff-followups" }

        switch scope {
        case .criticalOnly:
            if acknowledgedLiveSnapshot {
                return watchlistOnlyItems.filter { $0.severity == .critical } + handoffCheckInItems.filter { $0.severity == .critical }
            }

            return allItems.filter { $0.severity == .critical }
        case .liveAlerts:
            guard !acknowledgedLiveSnapshot else { return [] }
            return allItems.filter { item in
                item.id.hasPrefix("alert:") || item.id.hasPrefix("approval:")
            }
        case .fullQueue:
            return acknowledgedLiveSnapshot ? watchlistOnlyItems + handoffCheckInItems + handoffFollowUpItems : allItems
        }
    }

    private func followUpReminderDriver(
        for followUpItem: OnCallPriorityItem?,
        handoffCheckInStatus: HandoffCheckInStatus?
    ) -> (date: Date, hint: String)? {
        guard let followUpItem, let handoffCheckInStatus else { return nil }

        switch handoffCheckInStatus.state {
        case .scheduled:
            return nil
        case .dueSoon:
            guard followUpItem.severity == .critical else { return nil }
            return (handoffCheckInStatus.dueDate, String(localized: "Handoff follow-ups due soon"))
        case .overdue:
            return (Date().addingTimeInterval(30), String(localized: "Handoff follow-ups overdue"))
        }
    }
}

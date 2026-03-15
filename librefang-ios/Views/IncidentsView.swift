import SwiftUI

struct IncidentsView: View {
    @Environment(\.dependencies) private var deps

    private var vm: DashboardViewModel { deps.dashboardViewModel }
    private var incidentStateStore: IncidentStateStore { deps.incidentStateStore }
    private var watchlistStore: AgentWatchlistStore { deps.agentWatchlistStore }
    private var handoffStore: OnCallHandoffStore { deps.onCallHandoffStore }
    private var visibleAlerts: [MonitoringAlertItem] {
        incidentStateStore.visibleAlerts(from: vm.monitoringAlerts)
    }
    private var mutedAlerts: [MonitoringAlertItem] {
        incidentStateStore.activeMutedAlerts(from: vm.monitoringAlerts)
    }
    private var isCurrentSnapshotAcknowledged: Bool {
        incidentStateStore.isCurrentSnapshotAcknowledged(alerts: vm.monitoringAlerts)
    }
    private var currentAcknowledgedAt: Date? {
        incidentStateStore.currentAcknowledgementDate(for: vm.monitoringAlerts)
    }
    private var watchedAttentionItems: [AgentAttentionItem] {
        watchlistStore.watchedAgents(from: vm.agents)
            .map { vm.attentionItem(for: $0) }
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
    private var handoffCheckInStatus: HandoffCheckInStatus? {
        guard let status = handoffStore.latestCheckInStatus, status.state != .scheduled else { return nil }
        return status
    }
    private var handoffReadiness: HandoffReadinessStatus {
        handoffStore.evaluateDraftReadiness(
            note: handoffStore.draftNote,
            checklist: handoffStore.draftChecklist,
            focusAreas: handoffStore.draftFocusAreas,
            followUpItems: handoffStore.draftFollowUpItems,
            checkInWindow: handoffStore.draftCheckInWindow,
            liveAlertCount: visibleAlerts.count,
            pendingApprovalCount: vm.pendingApprovalCount,
            watchlistIssueCount: watchedAttentionItems.count,
            sessionAttentionCount: vm.sessionAttentionCount,
            criticalAuditCount: vm.recentCriticalAuditCount,
            carryover: handoffStore.carryoverFromLatest(
                liveAlertCount: visibleAlerts.count,
                pendingApprovalCount: vm.pendingApprovalCount,
                watchlistIssueCount: watchedAttentionItems.count,
                sessionAttentionCount: vm.sessionAttentionCount,
                criticalAuditCount: vm.recentCriticalAuditCount
            )
        )
    }
    private var handoffIssueCount: Int {
        (handoffCheckInStatus == nil ? 0 : 1) + (handoffReadiness.state == .ready ? 0 : 1)
    }
    private var onCallPriorityItems: [OnCallPriorityItem] {
        vm.onCallPriorityItems(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            handoffCheckInStatus: handoffCheckInStatus
        )
    }
    private var handoffText: String {
        vm.onCallHandoffText(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            mutedAlertCount: mutedAlerts.count,
            isAcknowledged: isCurrentSnapshotAcknowledged,
            handoffCheckInStatus: handoffCheckInStatus
        )
    }
    private var hasVisibleIncidents: Bool {
        !visibleAlerts.isEmpty
            || !mutedAlerts.isEmpty
            || !vm.approvals.isEmpty
            || !vm.attentionAgents.isEmpty
            || !vm.sessionAttentionItems.isEmpty
            || !vm.criticalAuditEntries.isEmpty
            || handoffIssueCount > 0
    }

    var body: some View {
        List {
            Section {
                IncidentScoreboard(
                    criticalCount: visibleAlerts.filter { $0.severity == .critical }.count,
                    warningCount: visibleAlerts.filter { $0.severity == .warning }.count,
                    mutedCount: mutedAlerts.count,
                    approvalCount: vm.pendingApprovalCount,
                    agentCount: vm.issueAgentCount,
                    sessionCount: vm.sessionAttentionCount,
                    handoffCount: handoffIssueCount
                )
                    .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
            }

            if !visibleAlerts.isEmpty || !mutedAlerts.isEmpty {
                Section("Operator State") {
                    IncidentOperatorCard(
                        activeAlertCount: visibleAlerts.count,
                        mutedAlertCount: mutedAlerts.count,
                        isAcknowledged: isCurrentSnapshotAcknowledged,
                        acknowledgedAt: currentAcknowledgedAt,
                        onAcknowledge: { incidentStateStore.acknowledgeCurrentSnapshot(alerts: vm.monitoringAlerts) },
                        onClearAcknowledgement: { incidentStateStore.clearAcknowledgement() },
                        onUnmuteAll: { incidentStateStore.unmuteAll() }
                    )
                }
            }

            if handoffIssueCount > 0 {
                Section {
                    NavigationLink {
                        HandoffCenterView(
                            summary: handoffText,
                            queueCount: onCallPriorityItems.count,
                            criticalCount: visibleAlerts.filter { $0.severity == .critical }.count,
                            liveAlertCount: visibleAlerts.count
                        )
                    } label: {
                        IncidentShiftCoverageCard(
                            checkInStatus: handoffCheckInStatus,
                            readiness: handoffReadiness,
                            latestEntry: handoffStore.latestEntry
                        )
                    }
                } header: {
                    Text("Shift Coverage")
                } footer: {
                    Text("These handoff signals are local to this iPhone and help keep operator follow-through visible inside the incident flow.")
                }
            }

            if !visibleAlerts.isEmpty {
                Section {
                    ForEach(visibleAlerts) { alert in
                        IncidentAlertRow(alert: alert, isMuted: false) {
                            incidentStateStore.toggleMute(for: alert)
                        }
                    }
                } header: {
                    Text("Active Alerts")
                } footer: {
                    Text("Muted alerts stay out of the overview attention card and the global critical banner on this iPhone.")
                }
            }

            if !mutedAlerts.isEmpty {
                Section("Muted Alerts") {
                    ForEach(mutedAlerts) { alert in
                        IncidentAlertRow(alert: alert, isMuted: true) {
                            incidentStateStore.toggleMute(for: alert)
                        }
                    }
                }
            }

            if !vm.approvals.isEmpty {
                Section {
                    ForEach(vm.approvals.prefix(4)) { approval in
                        IncidentApprovalRow(approval: approval)
                    }
                } header: {
                    Text("Pending Approvals")
                } footer: {
                    Text("Approvals block sensitive actions until an operator responds in the main dashboard.")
                }
            }

            if !vm.attentionAgents.isEmpty {
                Section {
                    ForEach(vm.attentionAgents.prefix(5)) { item in
                        NavigationLink {
                            AgentDetailView(agent: item.agent)
                        } label: {
                            IncidentAgentRow(item: item)
                        }
                    }
                } header: {
                    Text("Agents")
                } footer: {
                    Text("\(vm.issueAgentCount) agents currently need attention")
                }
            }

            if !vm.sessionAttentionItems.isEmpty {
                Section {
                    ForEach(vm.sessionAttentionItems.prefix(5)) { item in
                        if let agent = item.agent {
                            NavigationLink {
                                AgentDetailView(agent: agent)
                            } label: {
                                IncidentSessionRow(item: item)
                            }
                        } else {
                            IncidentSessionRow(item: item)
                        }
                    }

                    NavigationLink {
                        SessionsView(initialFilter: .attention)
                    } label: {
                        Label("Open Session Monitor", systemImage: "rectangle.stack")
                    }
                } header: {
                    Text("Sessions")
                } footer: {
                    Text("\(vm.sessionAttentionCount) sessions need review")
                }
            }

            if !vm.criticalAuditEntries.isEmpty {
                Section {
                    ForEach(vm.criticalAuditEntries.prefix(5)) { entry in
                        IncidentEventRow(entry: entry, agentName: agentName(for: entry.agentId))
                    }

                    NavigationLink {
                        EventsView(api: deps.apiClient, initialScope: .critical)
                    } label: {
                        Label("Open Critical Event Feed", systemImage: "list.bullet.rectangle.portrait")
                    }
                } header: {
                    Text("Critical Events")
                } footer: {
                    Text("\(vm.recentCriticalAuditCount) recent critical audit events already surfaced on mobile")
                }
            }

            if !hasVisibleIncidents {
                Section("Incidents") {
                    ContentUnavailableView(
                        "No Active Incidents",
                        systemImage: "checkmark.shield",
                        description: Text("The current mobile monitoring snapshot does not show blocked actions, critical events, unhealthy agents, or overdue local handoff checkpoints.")
                    )
                }
            }
        }
        .navigationTitle("Incidents")
        .refreshable {
            await vm.refresh()
        }
        .overlay {
            if vm.isLoading && vm.lastRefresh == nil {
                ProgressView("Loading incidents...")
            }
        }
        .task {
            if vm.lastRefresh == nil {
                await vm.refresh()
            }
        }
    }

    private func agentName(for id: String) -> String? {
        vm.agents.first(where: { $0.id == id })?.name
    }
}

private struct IncidentScoreboard: View {
    let criticalCount: Int
    let warningCount: Int
    let mutedCount: Int
    let approvalCount: Int
    let agentCount: Int
    let sessionCount: Int
    let handoffCount: Int

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            StatBadge(
                value: "\(criticalCount)",
                label: "Critical",
                icon: "xmark.octagon",
                color: criticalCount > 0 ? .red : .secondary
            )
            StatBadge(
                value: "\(warningCount)",
                label: "Warnings",
                icon: "exclamationmark.triangle",
                color: warningCount > 0 ? .orange : .secondary
            )
            StatBadge(
                value: "\(mutedCount)",
                label: "Muted",
                icon: "bell.slash",
                color: mutedCount > 0 ? .secondary : .secondary
            )
            StatBadge(
                value: "\(approvalCount)",
                label: "Approvals",
                icon: "exclamationmark.shield",
                color: approvalCount > 0 ? .red : .secondary
            )
            StatBadge(
                value: "\(agentCount)",
                label: "Agents",
                icon: "cpu",
                color: agentCount > 0 ? .orange : .secondary
            )
            StatBadge(
                value: "\(sessionCount)",
                label: "Sessions",
                icon: "rectangle.stack",
                color: sessionCount > 0 ? .orange : .secondary
            )
            StatBadge(
                value: "\(handoffCount)",
                label: "Handoff",
                icon: "timer",
                color: handoffCount > 0 ? .orange : .secondary
            )
        }
        .padding(.horizontal)
    }
}

private struct IncidentAlertRow: View {
    let alert: MonitoringAlertItem
    let isMuted: Bool
    let onToggleMute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(alert.title, systemImage: alert.symbolName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(color)
                Spacer()
                Button(action: onToggleMute) {
                    Image(systemName: isMuted ? "bell" : "bell.slash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.secondary.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Text(severityLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.12))
                    .foregroundStyle(color)
                    .clipShape(Capsule())
            }

            Text(alert.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var color: Color {
        switch alert.severity {
        case .critical:
            .red
        case .warning:
            .orange
        case .info:
            .yellow
        }
    }

    private var severityLabel: String {
        switch alert.severity {
        case .critical:
            "Critical"
        case .warning:
            "Warn"
        case .info:
            "Info"
        }
    }
}

private struct IncidentOperatorCard: View {
    let activeAlertCount: Int
    let mutedAlertCount: Int
    let isAcknowledged: Bool
    let acknowledgedAt: Date?
    let onAcknowledge: () -> Void
    let onClearAcknowledgement: () -> Void
    let onUnmuteAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Mobile Operator State", systemImage: "person.crop.rectangle.badge.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(statusText)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.12))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }

            Text(statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let acknowledgedAt {
                Text("Acknowledged \(acknowledgedAt, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if activeAlertCount > 0 {
                    Button(isAcknowledged ? "Reset Ack" : "Acknowledge Snapshot") {
                        if isAcknowledged {
                            onClearAcknowledgement()
                        } else {
                            onAcknowledge()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isAcknowledged ? .orange : .red)
                }

                if mutedAlertCount > 0 {
                    Button("Unmute All") {
                        onUnmuteAll()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        if activeAlertCount == 0 {
            return mutedAlertCount > 0 ? .secondary : .green
        }
        return isAcknowledged ? .orange : .red
    }

    private var statusText: String {
        if activeAlertCount == 0 {
            return mutedAlertCount > 0 ? "Muted" : "Clear"
        }
        return isAcknowledged ? "Acked" : "Needs review"
    }

    private var statusDetail: String {
        if activeAlertCount == 0, mutedAlertCount > 0 {
            return mutedAlertCount == 1
                ? "1 active alert is muted locally. It will stay out of summary surfaces until you unmute it."
                : "\(mutedAlertCount) active alerts are muted locally. They will stay out of summary surfaces until you unmute them."
        }

        if activeAlertCount == 0 {
            return "No live alert cards are currently visible on this device."
        }

        if isAcknowledged {
            return "The current alert snapshot is acknowledged on this iPhone. If counts or details change, it will surface as live again."
        }

        return "Acknowledge the current alert snapshot after review, or mute noisy alert classes locally if they are already understood."
    }
}

private struct IncidentShiftCoverageCard: View {
    let checkInStatus: HandoffCheckInStatus?
    let readiness: HandoffReadinessStatus
    let latestEntry: OnCallHandoffEntry?

    private var readinessColor: Color {
        switch readiness.state {
        case .ready:
            .green
        case .caution:
            .orange
        case .blocked:
            .red
        }
    }

    private var checkInColor: Color {
        guard let checkInStatus else { return Color.secondary }
        switch checkInStatus.state {
        case .scheduled:
            return Color.secondary
        case .dueSoon:
            return Color.orange
        case .overdue:
            return Color.red
        }
    }

    private var topIssue: HandoffReadinessIssue? {
        readiness.blockingIssues.first ?? readiness.advisoryIssues.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Local Handoff Pressure", systemImage: "person.crop.rectangle.badge.clock")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let checkInStatus {
                    Text(checkInStatus.state.label)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(checkInColor.opacity(0.12))
                        .foregroundStyle(checkInColor)
                        .clipShape(Capsule())
                }
                if readiness.state != .ready {
                    Text(readiness.state.label)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(readinessColor.opacity(0.12))
                        .foregroundStyle(readinessColor)
                        .clipShape(Capsule())
                }
            }

            if let checkInStatus {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "timer")
                        .foregroundStyle(checkInColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(checkInStatus.state == .overdue ? "Handoff check-in missed" : "Handoff check-in approaching")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(checkInStatus.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if readiness.state != .ready {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: readiness.state == .blocked ? "exclamationmark.octagon" : "checkmark.seal")
                        .foregroundStyle(readinessColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Next handoff draft needs work")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(topIssue?.message ?? readiness.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let latestEntry {
                Text("Last local handoff saved \(latestEntry.createdAt, style: .relative) ago.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("Open Handoff Center", systemImage: "text.badge.plus")
                    .font(.caption.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct IncidentApprovalRow: View {
    let approval: ApprovalItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(approval.actionSummary)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(approval.riskLevel.capitalized)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red.opacity(0.12))
                    .foregroundStyle(.red)
                    .clipShape(Capsule())
            }

            Text(approval.agentName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(approval.toolName)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

private struct IncidentAgentRow: View {
    let item: AgentAttentionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.agent.name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(item.agent.state)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.agent.isRunning ? .green : .secondary)
            }

            Text(item.reasons.prefix(3).joined(separator: " • "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

private struct IncidentSessionRow: View {
    let item: SessionAttentionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(displayTitle)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(item.session.messageCount) msgs")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(item.severity >= 6 ? .red : .orange)
            }

            Text(item.agent?.name ?? item.session.agentId)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(item.reasons.prefix(3).joined(separator: " • "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private var displayTitle: String {
        let label = (item.session.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? String(item.session.sessionId.prefix(8)) : label
    }
}

private struct IncidentEventRow: View {
    let entry: AuditEntry
    let agentName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.friendlyAction)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(agentName ?? shortAgentId)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(entry.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Text(entry.outcome.capitalized)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.red)
        }
        .padding(.vertical, 2)
    }

    private var shortAgentId: String {
        entry.agentId.isEmpty ? "-" : String(entry.agentId.prefix(8))
    }
}

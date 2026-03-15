import SwiftUI

struct IncidentsView: View {
    @Environment(\.dependencies) private var deps
    @State private var pendingApprovalAction: ApprovalDecisionAction?
    @State private var approvalActionInFlightID: String?
    @State private var operatorNotice: OperatorActionNotice?

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
    private var watchedDiagnosticRows: [(agent: Agent, summary: WatchedAgentDiagnosticsSummary)] {
        watchlistStore.watchedAgents(from: vm.agents)
            .compactMap { agent in
                guard let summary = deps.watchedAgentDiagnosticsStore.summary(for: agent.id), summary.hasIssues else {
                    return nil
                }
                return (agent, summary)
            }
            .sorted { lhs, rhs in
                if lhs.summary.failedDeliveries != rhs.summary.failedDeliveries {
                    return lhs.summary.failedDeliveries > rhs.summary.failedDeliveries
                }
                if lhs.summary.unavailableFallbackModels.count != rhs.summary.unavailableFallbackModels.count {
                    return lhs.summary.unavailableFallbackModels.count > rhs.summary.unavailableFallbackModels.count
                }
                if lhs.summary.missingIdentityFiles.count != rhs.summary.missingIdentityFiles.count {
                    return lhs.summary.missingIdentityFiles.count > rhs.summary.missingIdentityFiles.count
                }
                if lhs.summary.unsettledDeliveries != rhs.summary.unsettledDeliveries {
                    return lhs.summary.unsettledDeliveries > rhs.summary.unsettledDeliveries
                }
                return lhs.agent.name.localizedCompare(rhs.agent.name) == .orderedAscending
            }
    }
    private var combinedAgentIssueCount: Int {
        Set(vm.attentionAgents.map(\.agent.id) + watchedDiagnosticRows.map(\.agent.id)).count
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
        (handoffCheckInStatus == nil ? 0 : 1)
            + (handoffReadiness.state == .ready ? 0 : 1)
            + (handoffStore.pendingLatestFollowUpCount > 0 ? 1 : 0)
    }
    private var automationIssueCount: Int {
        (vm.failedWorkflowRunCount > 0 ? 1 : 0)
            + (vm.exhaustedTriggerCount > 0 ? 1 : 0)
            + (vm.stalledCronJobCount > 0 ? 1 : 0)
    }
    private var integrationIssueCount: Int {
        (vm.unreachableLocalProviderCount > 0 ? 1 : 0)
            + (vm.channelRequiredFieldGapCount > 0 ? 1 : 0)
            + (vm.hasEmptyModelCatalog ? 1 : 0)
            + (vm.agentsWithModelDiagnostics.isEmpty ? 0 : 1)
    }
    private var onCallPriorityItems: [OnCallPriorityItem] {
        vm.onCallPriorityItems(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            handoffCheckInStatus: handoffCheckInStatus,
            handoffFollowUpStatuses: handoffStore.latestFollowUpStatuses
        )
    }
    private var handoffText: String {
        vm.onCallHandoffText(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            mutedAlertCount: mutedAlerts.count,
            isAcknowledged: isCurrentSnapshotAcknowledged,
            handoffCheckInStatus: handoffCheckInStatus,
            handoffFollowUpStatuses: handoffStore.latestFollowUpStatuses
        )
    }
    private var hasVisibleIncidents: Bool {
        !visibleAlerts.isEmpty
            || !mutedAlerts.isEmpty
            || !vm.approvals.isEmpty
            || !vm.attentionAgents.isEmpty
            || !watchedDiagnosticRows.isEmpty
            || !vm.sessionAttentionItems.isEmpty
            || !vm.criticalAuditEntries.isEmpty
            || automationIssueCount > 0
            || integrationIssueCount > 0
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
                    agentCount: combinedAgentIssueCount,
                    sessionCount: vm.sessionAttentionCount,
                    automationCount: automationIssueCount,
                    integrationCount: integrationIssueCount,
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
                            latestEntry: handoffStore.latestEntry,
                            pendingFollowUpCount: handoffStore.pendingLatestFollowUpCount,
                            completedFollowUpCount: handoffStore.completedLatestFollowUpCount
                        )
                    }
                } header: {
                    Text("Shift Coverage")
                } footer: {
                    Text("These handoff signals are local to this iPhone and help keep operator follow-through visible inside the incident flow.")
                }
            }

            if automationIssueCount > 0 {
                Section {
                    NavigationLink {
                        AutomationView()
                    } label: {
                        IncidentAutomationCard(vm: vm)
                    }
                } header: {
                    Text("Automation")
                } footer: {
                    Text("Workflow failures, exhausted triggers, and stalled cron jobs now flow into the mobile incident queue.")
                }
            }

            if integrationIssueCount > 0 {
                Section {
                    NavigationLink {
                        IntegrationsView(initialScope: .attention)
                    } label: {
                        IncidentIntegrationsCard(vm: vm)
                    }

                    if vm.unreachableLocalProviderCount > 0 {
                        NavigationLink {
                            IntegrationsView(
                                initialSearchText: vm.unreachableLocalProviders.count == 1 ? vm.unreachableLocalProviders[0].displayName : "",
                                initialScope: .attention
                            )
                        } label: {
                            Label("Review Provider Failures", systemImage: "network.slash")
                        }
                    }

                    if vm.channelRequiredFieldGapCount > 0 {
                        NavigationLink {
                            IntegrationsView(
                                initialSearchText: vm.channelsMissingRequiredFields.count == 1 ? vm.channelsMissingRequiredFields[0].displayName : "",
                                initialScope: .attention
                            )
                        } label: {
                            Label("Review Channel Field Gaps", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                        }
                    }

                    if vm.hasEmptyModelCatalog {
                        NavigationLink {
                            IntegrationsView(initialScope: .attention)
                        } label: {
                            Label("Review Catalog Availability", systemImage: "square.stack.3d.up.slash")
                        }
                    }

                    ForEach(vm.agentsWithModelDiagnostics.prefix(3)) { diagnostic in
                        NavigationLink {
                            AgentDetailView(agent: diagnostic.agent)
                        } label: {
                            IncidentIntegrationAgentRow(diagnostic: diagnostic)
                        }
                    }
                } header: {
                    Text("Integrations")
                } footer: {
                    Text("Local provider reachability, delivery channel secrets, and model catalog drift now surface as first-class mobile incidents.")
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
                        IncidentApprovalRow(
                            approval: approval,
                            isBusy: approvalActionInFlightID == approval.id,
                            onApprove: {
                                pendingApprovalAction = .approve(approval)
                            },
                            onReject: {
                                pendingApprovalAction = .reject(approval)
                            }
                        )
                    }

                    NavigationLink {
                        ApprovalsView()
                    } label: {
                        Label("Open Full Approval Queue", systemImage: "checkmark.shield")
                    }
                } header: {
                    Text("Pending Approvals")
                } footer: {
                    Text("Approvals block sensitive actions until an operator responds. Mobile can now resolve them directly after confirmation.")
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

            if !watchedDiagnosticRows.isEmpty {
                Section {
                    ForEach(watchedDiagnosticRows.prefix(5), id: \.agent.id) { row in
                        NavigationLink {
                            watchedDiagnosticsDestination(agent: row.agent, summary: row.summary)
                        } label: {
                            IncidentWatchedDiagnosticRow(agent: row.agent, summary: row.summary)
                        }
                    }
                } header: {
                    Text("Watched Diagnostics")
                } footer: {
                    Text("Pinned agents can surface operator issues here even when they are otherwise healthy enough to stay out of the general attention list.")
                }
            }

            if !vm.sessionAttentionItems.isEmpty {
                Section {
                    ForEach(vm.sessionAttentionItems.prefix(5)) { item in
                        if let sessionQuery = sessionQuery(for: item) {
                            NavigationLink {
                                SessionsView(initialSearchText: sessionQuery, initialFilter: .attention)
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
                        if let eventQuery = eventQuery(for: entry) {
                            NavigationLink {
                                EventsView(api: deps.apiClient, initialSearchText: eventQuery, initialScope: .critical)
                            } label: {
                                IncidentEventRow(entry: entry, agentName: agentName(for: entry.agentId))
                            }
                        } else {
                            NavigationLink {
                                EventsView(api: deps.apiClient, initialScope: .critical)
                            } label: {
                                IncidentEventRow(entry: entry, agentName: agentName(for: entry.agentId))
                            }
                        }
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
        .confirmationDialog(
            pendingApprovalAction?.title ?? "",
            isPresented: approvalActionConfirmationPresented,
            titleVisibility: .visible,
            presenting: pendingApprovalAction
        ) { action in
            Button(action.confirmLabel, role: action.isDestructive ? .destructive : nil) {
                Task { await performApprovalAction(action) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(action.message)
        }
        .alert(item: $operatorNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func agentName(for id: String) -> String? {
        vm.agents.first(where: { $0.id == id })?.name
    }

    private func sessionQuery(for item: SessionAttentionItem) -> String? {
        let agentID = item.agent?.id ?? item.session.agentId
        return agentID.isEmpty ? nil : agentID
    }

    private func eventQuery(for entry: AuditEntry) -> String? {
        entry.agentId.isEmpty ? nil : entry.agentId
    }

    @ViewBuilder
    private func watchedDiagnosticsDestination(agent: Agent, summary: WatchedAgentDiagnosticsSummary) -> some View {
        if summary.failedDeliveries > 0 {
            AgentDeliveriesView(agent: agent, initialScope: .failed)
        } else if !summary.missingIdentityFiles.isEmpty {
            AgentFilesView(agent: agent, initialScope: .missing)
        } else {
            AgentDetailView(agent: agent)
        }
    }

    private var approvalActionConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingApprovalAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingApprovalAction = nil
                }
            }
        )
    }

    @MainActor
    private func performApprovalAction(_ action: ApprovalDecisionAction) async {
        pendingApprovalAction = nil
        approvalActionInFlightID = action.approvalID
        defer { approvalActionInFlightID = nil }

        do {
            let response = try await action.perform(using: deps.apiClient)
            await vm.refresh()
            operatorNotice = action.successNotice(from: response)
        } catch {
            operatorNotice = OperatorActionNotice(
                title: action.title,
                message: error.localizedDescription
            )
        }
    }
}

private struct IncidentScoreboard: View {
    let criticalCount: Int
    let warningCount: Int
    let mutedCount: Int
    let approvalCount: Int
    let agentCount: Int
    let sessionCount: Int
    let automationCount: Int
    let integrationCount: Int
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
                value: "\(automationCount)",
                label: "Automation",
                icon: "flowchart",
                color: automationCount > 0 ? .orange : .secondary
            )
            StatBadge(
                value: "\(integrationCount)",
                label: "Integrations",
                icon: "square.3.layers.3d.down.forward",
                color: integrationCount > 0 ? .orange : .secondary
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
            String(localized: "Critical")
        case .warning:
            String(localized: "Warn")
        case .info:
            String(localized: "Info")
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
                    Button(isAcknowledged ? String(localized: "Reset Ack") : String(localized: "Acknowledge Snapshot")) {
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
            return mutedAlertCount > 0 ? String(localized: "Muted") : String(localized: "Clear")
        }
        return isAcknowledged ? String(localized: "Acked") : String(localized: "Needs review")
    }

    private var statusDetail: String {
        if activeAlertCount == 0, mutedAlertCount > 0 {
            return mutedAlertCount == 1
                ? String(localized: "1 active alert is muted locally. It will stay out of summary surfaces until you unmute it.")
                : String(localized: "\(mutedAlertCount) active alerts are muted locally. They will stay out of summary surfaces until you unmute them.")
        }

        if activeAlertCount == 0 {
            return String(localized: "No live alert cards are currently visible on this device.")
        }

        if isAcknowledged {
            return String(localized: "The current alert snapshot is acknowledged on this iPhone. If counts or details change, it will surface as live again.")
        }

        return String(localized: "Acknowledge the current alert snapshot after review, or mute noisy alert classes locally if they are already understood.")
    }
}

private struct IncidentShiftCoverageCard: View {
    let checkInStatus: HandoffCheckInStatus?
    let readiness: HandoffReadinessStatus
    let latestEntry: OnCallHandoffEntry?
    let pendingFollowUpCount: Int
    let completedFollowUpCount: Int

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
                        Text(
                            checkInStatus.state == .overdue
                                ? String(localized: "Handoff check-in missed")
                                : String(localized: "Handoff check-in approaching")
                        )
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
                        Text(String(localized: "Next handoff draft needs work"))
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

            if (pendingFollowUpCount + completedFollowUpCount) > 0 {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: pendingFollowUpCount == 0 ? "checkmark.circle" : "checklist")
                        .foregroundStyle(pendingFollowUpCount == 0 ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            pendingFollowUpCount == 0
                                ? String(localized: "Handoff follow-ups are clear")
                                : String(localized: "Handoff follow-ups still open")
                        )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(
                            pendingFollowUpCount == 0
                                ? String(localized: "\(completedFollowUpCount) follow-up items from the latest local handoff are complete on this iPhone.")
                                : String(localized: "\(pendingFollowUpCount) of \(pendingFollowUpCount + completedFollowUpCount) latest local follow-up items are still pending.")
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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

private struct IncidentAutomationCard: View {
    let vm: DashboardViewModel

    private var statusColor: Color {
        vm.failedWorkflowRunCount > 0 ? .red : .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Automation Pressure", systemImage: "flowchart")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(statusLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.12))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }

            if vm.failedWorkflowRunCount > 0 {
                automationIssueRow(
                    icon: "exclamationmark.triangle.fill",
                    color: .red,
                    title: vm.failedWorkflowRunCount == 1
                        ? String(localized: "Workflow run failed")
                        : String(localized: "\(vm.failedWorkflowRunCount) workflow runs failed"),
                    detail: vm.workflowRuns
                        .filter { $0.state == .failed }
                        .prefix(2)
                        .map(\.workflowName)
                        .joined(separator: " • ")
                )
            }

            if vm.exhaustedTriggerCount > 0 {
                automationIssueRow(
                    icon: "bolt.badge.clock",
                    color: .orange,
                    title: vm.exhaustedTriggerCount == 1
                        ? String(localized: "Trigger exhausted")
                        : String(localized: "\(vm.exhaustedTriggerCount) triggers exhausted"),
                    detail: String(localized: "Event triggers reached their fire budget and stopped waking agents.")
                )
            }

            if vm.stalledCronJobCount > 0 {
                automationIssueRow(
                    icon: "calendar.badge.exclamationmark",
                    color: .orange,
                    title: vm.stalledCronJobCount == 1
                        ? String(localized: "Cron missing next run")
                        : String(localized: "\(vm.stalledCronJobCount) cron jobs missing next run"),
                    detail: String(localized: "Enabled scheduler jobs exist without a next execution timestamp.")
                )
            }

            HStack {
                Label("Open Automation Monitor", systemImage: "flowchart")
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

    private var statusLabel: String {
        let count = (vm.failedWorkflowRunCount > 0 ? 1 : 0)
            + (vm.exhaustedTriggerCount > 0 ? 1 : 0)
            + (vm.stalledCronJobCount > 0 ? 1 : 0)
        return count == 1 ? String(localized: "1 issue") : String(localized: "\(count) issues")
    }

    @ViewBuilder
    private func automationIssueRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct IncidentIntegrationsCard: View {
    let vm: DashboardViewModel

    private var noAvailableModels: Bool {
        vm.hasEmptyModelCatalog
    }

    private var statusColor: Color {
        if noAvailableModels || vm.unavailableModelAgentCount > 0 {
            return .red
        }
        return .orange
    }

    private var statusLabel: String {
        let issueCount = (vm.unreachableLocalProviderCount > 0 ? 1 : 0)
            + (vm.channelRequiredFieldGapCount > 0 ? 1 : 0)
            + (noAvailableModels ? 1 : 0)
            + (vm.agentsWithModelDiagnostics.isEmpty ? 0 : 1)
        return issueCount == 1 ? String(localized: "1 issue") : String(localized: "\(issueCount) issues")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Integration Pressure", systemImage: "square.3.layers.3d.down.forward")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(statusLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.12))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }

            if vm.unreachableLocalProviderCount > 0 {
                integrationIssueRow(
                    icon: "network.slash",
                    color: .orange,
                    title: vm.unreachableLocalProviderCount == 1
                        ? String(localized: "Local provider unreachable")
                        : String(localized: "\(vm.unreachableLocalProviderCount) local providers unreachable"),
                    detail: vm.providers
                        .filter { $0.isLocal == true && $0.reachable == false }
                        .prefix(2)
                        .map(\.displayName)
                        .joined(separator: " • ")
                )
            }

            if vm.channelRequiredFieldGapCount > 0 {
                integrationIssueRow(
                    icon: "bubble.left.and.exclamationmark.bubble.right",
                    color: .orange,
                    title: vm.channelRequiredFieldGapCount == 1
                        ? String(localized: "Channel missing required fields")
                        : String(localized: "\(vm.channelRequiredFieldGapCount) channels missing required fields"),
                    detail: vm.channelsMissingRequiredFields
                        .prefix(2)
                        .map(\.displayName)
                        .joined(separator: " • ")
                )
            }

            if noAvailableModels {
                integrationIssueRow(
                    icon: "square.stack.3d.up.slash",
                    color: .red,
                    title: String(localized: "No catalog models available"),
                    detail: String(localized: "Providers are configured, but the current LibreFang catalog exposes zero executable models.")
                )
            }

            if !vm.agentsWithModelDiagnostics.isEmpty {
                integrationIssueRow(
                    icon: "cpu",
                    color: vm.unavailableModelAgentCount > 0 ? .red : .orange,
                    title: vm.agentsWithModelDiagnostics.count == 1
                        ? String(localized: "1 agent has model drift")
                        : String(localized: "\(vm.agentsWithModelDiagnostics.count) agents have model drift"),
                    detail: vm.agentsWithModelDiagnostics
                        .prefix(2)
                        .map { "\($0.agent.name) (\($0.issueSummary))" }
                        .joined(separator: " • ")
                )
            }

            HStack {
                Label("Open Integrations Diagnostics", systemImage: "square.3.layers.3d.down.forward")
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

    @ViewBuilder
    private func integrationIssueRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct IncidentApprovalRow: View {
    let approval: ApprovalItem
    let isBusy: Bool
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        ApprovalOperatorRow(
            approval: approval,
            isBusy: isBusy,
            onApprove: onApprove,
            onReject: onReject
        )
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

private struct IncidentIntegrationAgentRow: View {
    let diagnostic: AgentModelDiagnostic

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(diagnostic.agent.name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            Text(diagnostic.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 12) {
                Label(diagnostic.requestedModel, systemImage: "cpu")
                if let resolvedAlias = diagnostic.resolvedAlias {
                    Label(resolvedAlias.alias, systemImage: "arrow.left.arrow.right")
                }
                if let resolvedModel = diagnostic.resolvedModel {
                    Label(resolvedModel.provider, systemImage: "cloud")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var statusText: String {
        switch diagnostic.kind {
        case .unknownModel:
            "Unknown"
        case .unavailableModel:
            "Unavailable"
        case .providerMismatch:
            "Mismatch"
        }
    }

    private var statusColor: Color {
        switch diagnostic.kind {
        case .unknownModel:
            .red
        case .unavailableModel:
            .orange
        case .providerMismatch:
            .indigo
        }
    }
}

private struct IncidentWatchedDiagnosticRow: View {
    let agent: Agent
    let summary: WatchedAgentDiagnosticsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(agent.identity?.emoji ?? "🤖")
                    .font(.body)
                Text(agent.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                Spacer()
                if summary.failedDeliveries > 0 {
                    statusChip(
                        label: summary.failedDeliveries == 1
                            ? String(localized: "1 failed")
                            : String(localized: "\(summary.failedDeliveries) failed"),
                        color: .red
                    )
                } else if !summary.unavailableFallbackModels.isEmpty {
                    statusChip(
                        label: summary.unavailableFallbackModels.count == 1
                            ? String(localized: "1 fallback drift")
                            : String(localized: "\(summary.unavailableFallbackModels.count) fallback drift"),
                        color: .orange
                    )
                } else {
                    statusChip(
                        label: summary.issueCount == 1
                            ? String(localized: "1 issue")
                            : String(localized: "\(summary.issueCount) issues"),
                        color: .orange
                    )
                }
            }

            Text(summary.summaryLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(destinationHint)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack(spacing: 8) {
                if summary.unsettledDeliveries > 0 {
                    issuePill(
                        text: summary.unsettledDeliveries == 1
                            ? String(localized: "1 unsettled")
                            : String(localized: "\(summary.unsettledDeliveries) unsettled"),
                        color: .orange
                    )
                }
                if !summary.missingIdentityFiles.isEmpty {
                    issuePill(
                        text: summary.missingIdentityFiles.count == 1
                            ? String(localized: "1 file missing")
                            : String(localized: "\(summary.missingIdentityFiles.count) files missing"),
                        color: .orange
                    )
                }
                if !summary.unavailableFallbackModels.isEmpty {
                    issuePill(
                        text: summary.unavailableFallbackModels.count == 1
                            ? String(localized: "1 fallback")
                            : String(localized: "\(summary.unavailableFallbackModels.count) fallbacks"),
                        color: .orange
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func statusChip(label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func issuePill(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var destinationHint: String {
        if summary.failedDeliveries > 0 {
            return String(localized: "Tap to inspect failed delivery receipts.")
        }
        if !summary.missingIdentityFiles.isEmpty {
            return String(localized: "Tap to inspect missing workspace identity files.")
        }
        if !summary.unavailableFallbackModels.isEmpty {
            return String(localized: "Tap to inspect fallback model drift in the agent config snapshot.")
        }
        return String(localized: "Tap to inspect operator diagnostics for this pinned agent.")
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

import SwiftUI

private enum IncidentSectionAnchor: Hashable {
    case operatorState
    case shiftCoverage
    case automation
    case integrations
    case activeAlerts
    case approvals
    case agents
    case watchedDiagnostics
    case sessions
    case criticalEvents
}

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
    private var criticalAlertCount: Int {
        visibleAlerts.filter { $0.severity == .critical }.count
    }
    private var warningAlertCount: Int {
        visibleAlerts.filter { $0.severity == .warning }.count
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
        vm.automationPressureIssueCategoryCount
    }
    private var integrationIssueCount: Int {
        vm.integrationPressureIssueCategoryCount
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
    private var incidentSectionCount: Int {
        [
            !visibleAlerts.isEmpty || !mutedAlerts.isEmpty,
            handoffIssueCount > 0,
            automationIssueCount > 0,
            integrationIssueCount > 0,
            !visibleAlerts.isEmpty,
            !mutedAlerts.isEmpty,
            !vm.approvals.isEmpty,
            !vm.attentionAgents.isEmpty,
            !watchedDiagnosticRows.isEmpty,
            !vm.sessionAttentionItems.isEmpty,
            !vm.criticalAuditEntries.isEmpty
        ]
        .filter { $0 }
        .count
    }
    private var operatorPrimaryRouteCount: Int { 4 }
    private var operatorSupportRouteCount: Int {
        2 + (automationIssueCount > 0 ? 1 : 0) + (integrationIssueCount > 0 ? 1 : 0)
    }
    private var primaryQueueSectionCount: Int {
        [
            !visibleAlerts.isEmpty || !mutedAlerts.isEmpty,
            handoffIssueCount > 0,
            !visibleAlerts.isEmpty,
            !vm.approvals.isEmpty,
            !vm.sessionAttentionItems.isEmpty
        ]
        .filter { $0 }
        .count
    }
    private var supportQueueSectionCount: Int {
        [
            automationIssueCount > 0,
            integrationIssueCount > 0,
            !vm.attentionAgents.isEmpty,
            !watchedDiagnosticRows.isEmpty,
            !vm.criticalAuditEntries.isEmpty
        ]
        .filter { $0 }
        .count
    }
    private var approvalsHighRiskCount: Int {
        vm.approvals.filter(\.isHighRiskOrAbove).count
    }
    private var approvalAgentCount: Int {
        Set(vm.approvals.map(\.agentId)).count
    }
    private var attentionAgentAuthIssueCount: Int {
        vm.attentionAgents.filter(\.hasAuthIssue).count
    }
    private var attentionAgentApprovalCount: Int {
        vm.attentionAgents.filter { $0.pendingApprovals > 0 }.count
    }
    private var attentionAgentStaleCount: Int {
        vm.attentionAgents.filter(\.isStale).count
    }
    private var watchedFailedAgentCount: Int {
        watchedDiagnosticRows.filter { $0.summary.failedDeliveries > 0 }.count
    }
    private var watchedMissingIdentityAgentCount: Int {
        watchedDiagnosticRows.filter { !$0.summary.missingIdentityFiles.isEmpty }.count
    }
    private var watchedFallbackAgentCount: Int {
        watchedDiagnosticRows.filter { !$0.summary.unavailableFallbackModels.isEmpty }.count
    }
    private var watchedUnsettledAgentCount: Int {
        watchedDiagnosticRows.filter { $0.summary.unsettledDeliveries > 0 }.count
    }
    private var unlabeledSessionCount: Int {
        vm.sessionAttentionItems.filter { !$0.hasLabel }.count
    }
    private var duplicateSessionCount: Int {
        vm.sessionAttentionItems.filter { $0.duplicateCount > 1 }.count
    }
    private var visibleSessionMessageCount: Int {
        vm.sessionAttentionItems.prefix(5).reduce(0) { $0 + $1.session.messageCount }
    }
    private var criticalEventAgentCount: Int {
        Set(vm.criticalAuditEntries.map(\.agentId)).count
    }
    private var criticalEventActionCount: Int {
        Set(vm.criticalAuditEntries.map(\.action)).count
    }

    var body: some View {
        List {
            incidentSections
        }
        .navigationTitle(String(localized: "Incidents"))
        .monitoringRefreshInteractionGate(isRefreshing: vm.isLoading)
        .refreshable {
            await vm.refresh()
        }
        .overlay {
            if vm.isLoading && vm.lastRefresh == nil {
                ProgressView(String(localized: "Loading incidents..."))
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
            Button(String(localized: "Cancel"), role: .cancel) {}
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

    @ViewBuilder
    private var incidentSections: some View {
        scoreboardSection

        if !visibleAlerts.isEmpty || !mutedAlerts.isEmpty {
            operatorStateSection
        }

        if !visibleAlerts.isEmpty {
            activeAlertsSection
        }

        if !vm.approvals.isEmpty {
            approvalsSection
        }

        if !vm.attentionAgents.isEmpty {
            agentsSection
        }

        if !watchedDiagnosticRows.isEmpty {
            watchedDiagnosticsSection
        }

        if !vm.sessionAttentionItems.isEmpty {
            sessionsSection
        }

        if !vm.criticalAuditEntries.isEmpty {
            criticalEventsSection
        }

        if handoffIssueCount > 0 {
            shiftCoverageSection
        }

        if automationIssueCount > 0 {
            automationSection
        }

        if integrationIssueCount > 0 {
            integrationsSection
        }

        if !mutedAlerts.isEmpty {
            mutedAlertsSection
        }

        if !hasVisibleIncidents {
            emptyStateSection
        }
    }

    private var scoreboardSection: some View {
        Section {
            IncidentScoreboard(
                criticalCount: criticalAlertCount,
                warningCount: warningAlertCount,
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
    }

    private var operatorStateSection: some View {
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
        .id(IncidentSectionAnchor.operatorState)
    }

    private var shiftCoverageSection: some View {
        Section {
            NavigationLink {
                HandoffCenterView(
                    summary: handoffText,
                    queueCount: onCallPriorityItems.count,
                    criticalCount: criticalAlertCount,
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
        }
        .id(IncidentSectionAnchor.shiftCoverage)
    }

    private var automationSection: some View {
        Section {
            NavigationLink {
                AutomationView()
            } label: {
                IncidentAutomationCard(vm: vm)
            }
        } header: {
            Text("Automation")
        }
        .id(IncidentSectionAnchor.automation)
    }

    private var integrationsSection: some View {
        Section {
            NavigationLink {
                IntegrationsView(initialScope: .attention)
            } label: {
                IncidentIntegrationsCard(vm: vm)
            }
        } header: {
            Text("Integrations")
        }
        .id(IncidentSectionAnchor.integrations)
    }

    private var activeAlertsSection: some View {
        Section {
            ForEach(visibleAlerts) { alert in
                IncidentAlertRow(alert: alert, isMuted: false) {
                    incidentStateStore.toggleMute(for: alert)
                }
            }
        } header: {
            Text("Active Alerts")
        }
        .id(IncidentSectionAnchor.activeAlerts)
    }

    private var mutedAlertsSection: some View {
        Section("Muted Alerts") {
            ForEach(mutedAlerts) { alert in
                IncidentAlertRow(alert: alert, isMuted: true) {
                    incidentStateStore.toggleMute(for: alert)
                }
            }
        }
    }

    private var approvalsSection: some View {
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

        } header: {
            Text("Pending Approvals")
        }
        .id(IncidentSectionAnchor.approvals)
    }

    private var agentsSection: some View {
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
        }
        .id(IncidentSectionAnchor.agents)
    }

    private var watchedDiagnosticsSection: some View {
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
        }
        .id(IncidentSectionAnchor.watchedDiagnostics)
    }

    private var sessionsSection: some View {
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

        } header: {
            Text("Sessions")
        }
        .id(IncidentSectionAnchor.sessions)
    }

    private var criticalEventsSection: some View {
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

        } header: {
            Text("Critical Events")
        }
        .id(IncidentSectionAnchor.criticalEvents)
    }

    private var approvalCountTone: PresentationTone {
        vm.pendingApprovalCount > 0 ? .critical : .neutral
    }

    private var sessionCountTone: PresentationTone {
        vm.sessionAttentionCount > 0 ? .warning : .neutral
    }

    private var criticalEventTone: PresentationTone {
        vm.recentCriticalAuditCount > 0 ? .critical : .neutral
    }

    private var runtimeSurfaceTone: PresentationTone {
        vm.runtimeAlertCount > 0 ? .warning : .neutral
    }

    private var emptyStateSection: some View {
        Section("Incidents") {
            ContentUnavailableView(
                "No Active Incidents",
                systemImage: "checkmark.shield",
                description: Text("The current mobile monitoring snapshot does not show blocked actions, critical events, unhealthy agents, or overdue local handoff checkpoints.")
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let criticalCount: Int
    let warningCount: Int
    let mutedCount: Int
    let approvalCount: Int
    let agentCount: Int
    let sessionCount: Int
    let automationCount: Int
    let integrationCount: Int
    let handoffCount: Int

    private var criticalStatus: MonitoringSummaryStatus {
        .countStatus(criticalCount, activeTone: .critical)
    }

    private var warningStatus: MonitoringSummaryStatus {
        .countStatus(warningCount, activeTone: .warning)
    }

    private var approvalStatus: MonitoringSummaryStatus {
        .countStatus(approvalCount, activeTone: .critical)
    }

    private var agentStatus: MonitoringSummaryStatus {
        .countStatus(agentCount, activeTone: .warning)
    }

    private var sessionStatus: MonitoringSummaryStatus {
        .countStatus(sessionCount, activeTone: .warning)
    }

    private var automationStatus: MonitoringSummaryStatus {
        .countStatus(automationCount, activeTone: .warning)
    }

    private var integrationStatus: MonitoringSummaryStatus {
        .countStatus(integrationCount, activeTone: .warning)
    }

    private var handoffStatus: MonitoringSummaryStatus {
        .countStatus(handoffCount, activeTone: .warning)
    }

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            StatBadge(
                value: "\(criticalCount)",
                label: "Critical",
                icon: "xmark.octagon",
                color: criticalStatus.tone.color
            )
            StatBadge(
                value: "\(warningCount)",
                label: "Warnings",
                icon: "exclamationmark.triangle",
                color: warningStatus.tone.color
            )
            StatBadge(
                value: "\(mutedCount)",
                label: "Muted",
                icon: "bell.slash",
                color: PresentationTone.neutral.color
            )
            StatBadge(
                value: "\(approvalCount)",
                label: "Approvals",
                icon: "exclamationmark.shield",
                color: approvalStatus.tone.color
            )
            StatBadge(
                value: "\(agentCount)",
                label: "Agents",
                icon: "cpu",
                color: agentStatus.tone.color
            )
            StatBadge(
                value: "\(sessionCount)",
                label: "Sessions",
                icon: "rectangle.stack",
                color: sessionStatus.tone.color
            )
            StatBadge(
                value: "\(automationCount)",
                label: "Automation",
                icon: "flowchart",
                color: automationStatus.tone.color
            )
            StatBadge(
                value: "\(integrationCount)",
                label: "Integrations",
                icon: "square.3.layers.3d.down.forward",
                color: integrationStatus.tone.color
            )
            StatBadge(
                value: "\(handoffCount)",
                label: "Handoff",
                icon: "timer",
                color: handoffStatus.tone.color
            )
        }
        .padding(.horizontal, 6)
    }
}


private struct IncidentAlertRow: View {
    let alert: MonitoringAlertItem
    let isMuted: Bool
    let onToggleMute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ResponsiveAccessoryRow(horizontalAlignment: .top) {
                titleLabel
            } accessory: {
                controlsRow
            }

            Text(alert.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var color: Color {
        alert.severity.tone.color
    }

    private var severityLabel: String {
        alert.severity.localizedLabel
    }

    private var titleLabel: some View {
        Label(alert.title, systemImage: alert.symbolName)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
    }

    private var controlsRow: some View {
        ResponsiveInlineGroup(horizontalSpacing: 8, verticalSpacing: 4) {
            muteButton
            severityBadge
        }
    }

    private var muteButton: some View {
        TintedCircleIconButton(
            systemImage: isMuted ? "bell" : "bell.slash",
            foregroundStyle: .secondary,
            backgroundStyle: .secondary.opacity(0.12),
            action: onToggleMute
        )
    }

    private var severityBadge: some View {
        PresentationToneBadge(
            text: severityLabel,
            tone: alert.severity.tone,
            horizontalPadding: 6,
            verticalPadding: 2
        )
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

    private var snapshotState: AlertSnapshotState {
        AlertSnapshotState(
            liveAlertCount: activeAlertCount,
            mutedAlertCount: mutedAlertCount,
            isAcknowledged: isAcknowledged
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow {
                operatorTitle
            } accessory: {
                operatorBadge
            }

            Text(statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let acknowledgedAt {
                Text("Acknowledged \(acknowledgedAt, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ResponsiveInlineGroup(horizontalSpacing: 8, verticalSpacing: 8) {
                if activeAlertCount > 0 {
                    acknowledgeButton
                }

                if mutedAlertCount > 0 {
                    unmuteButton
                }
            }
        }
        .padding(.vertical, 4)
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

    private var operatorTitle: some View {
        Label("Mobile Operator State", systemImage: "person.crop.rectangle.badge.exclamationmark")
            .font(.subheadline.weight(.semibold))
    }

    private var operatorBadge: some View {
        PresentationToneBadge(
            text: snapshotState.operatorLabel,
            tone: snapshotState.tone
        )
    }

    private var acknowledgeButton: some View {
        Button(isAcknowledged ? String(localized: "Reset Ack") : String(localized: "Acknowledge Snapshot")) {
            if isAcknowledged {
                onClearAcknowledgement()
            } else {
                onAcknowledge()
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(snapshotState.tone.color)
    }

    private var unmuteButton: some View {
        Button("Unmute All") {
            onUnmuteAll()
        }
        .buttonStyle(.bordered)
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
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow {
                headerTitle
            } accessory: {
                headerBadges
            }

            if let checkInStatus {
                issueRow(
                    icon: "timer",
                    color: checkInColor,
                    title: checkInStatus.state == .overdue
                        ? String(localized: "Handoff check-in missed")
                        : String(localized: "Handoff check-in approaching"),
                    detail: checkInStatus.summary
                )
            }

            if readiness.state != .ready {
                issueRow(
                    icon: readiness.state == .blocked ? "exclamationmark.octagon" : "checkmark.seal",
                    color: readinessColor,
                    title: String(localized: "Next handoff draft needs work"),
                    detail: topIssue?.message ?? readiness.summary
                )
            } else if let latestEntry {
                Text("Last local handoff saved \(latestEntry.createdAt, style: .relative) ago.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if (pendingFollowUpCount + completedFollowUpCount) > 0 {
                let followUpSummary = HandoffFollowUpSummary.summarize(
                    pendingCount: pendingFollowUpCount,
                    completedCount: completedFollowUpCount
                )

                issueRow(
                    icon: followUpSummary.symbolName,
                    color: followUpSummary.tone.color,
                    title: followUpSummary.headlineLabel,
                    detail: followUpSummary.detailLabel
                )
            }

            ResponsiveAccessoryRow(verticalSpacing: 6) {
                openLabel
            } accessory: {
                chevronLabel
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var headerTitle: some View {
        Label("Local Handoff Pressure", systemImage: "person.crop.rectangle.badge.clock")
            .font(.subheadline.weight(.semibold))
    }

    private var headerBadges: some View {
        FlowLayout(spacing: 8) {
            if let checkInStatus {
                badge(text: checkInStatus.state.label, tone: checkInStatus.state.tone)
            }
            if readiness.state != .ready {
                badge(text: readiness.state.label, tone: readiness.state.tone)
            }
        }
    }

    private func badge(text: String, tone: PresentationTone) -> some View {
        PresentationToneBadge(text: text, tone: tone)
    }

    private var openLabel: some View {
        Label("Handoff", systemImage: "text.badge.plus")
            .font(.caption.weight(.semibold))
    }

    private var chevronLabel: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
    }

    private func issueRow(icon: String, color: Color, title: String, detail: String) -> some View {
        ResponsiveIconDetailRow(horizontalSpacing: 10, verticalSpacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
        } detail: {
            issueTextBlock(title: title, detail: detail)
        }
    }

    private func issueTextBlock(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct IncidentAutomationCard: View {
    let vm: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow {
                headerTitle
            } accessory: {
                headerBadge
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

            ResponsiveAccessoryRow(verticalSpacing: 6) {
                openLabel
            } accessory: {
                chevronLabel
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var headerTitle: some View {
        Label("Automation Pressure", systemImage: "flowchart")
            .font(.subheadline.weight(.semibold))
    }

    private var headerBadge: some View {
        PresentationToneBadge(
            text: vm.automationPressureSummaryLabel,
            tone: vm.automationPressureTone
        )
    }

    @ViewBuilder
    private func automationIssueRow(icon: String, color: Color, title: String, detail: String) -> some View {
        ResponsiveIconDetailRow(horizontalSpacing: 10, verticalSpacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
        } detail: {
            issueText(title: title, detail: detail)
        }
    }

    private var openLabel: some View {
        Label("Automation", systemImage: "flowchart")
            .font(.caption.weight(.semibold))
    }

    private var chevronLabel: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
    }

    private func issueText(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
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

private struct IncidentIntegrationsCard: View {
    let vm: DashboardViewModel

    private var noAvailableModels: Bool {
        vm.hasEmptyModelCatalog
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow {
                headerTitle
            } accessory: {
                headerBadge
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

            if vm.hasCatalogFreshnessIssue {
                integrationIssueRow(
                    icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    color: vm.catalogFreshnessIssueTone.color,
                    title: vm.catalogLastSyncDate == nil
                        ? String(localized: "Catalog sync timestamp missing")
                        : String(localized: "Catalog sync is stale"),
                    detail: catalogFreshnessDetail
                )
            }

            if !vm.agentsWithModelDiagnostics.isEmpty {
                integrationIssueRow(
                    icon: "cpu",
                    color: vm.modelDriftIssueTone.color,
                    title: vm.agentsWithModelDiagnostics.count == 1
                        ? String(localized: "1 agent has model drift")
                        : String(localized: "\(vm.agentsWithModelDiagnostics.count) agents have model drift"),
                    detail: vm.agentsWithModelDiagnostics
                        .prefix(2)
                        .map { "\($0.agent.name) (\($0.issueSummary))" }
                        .joined(separator: " • ")
                )
            }

            ResponsiveAccessoryRow(verticalSpacing: 6) {
                openLabel
            } accessory: {
                chevronLabel
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var catalogFreshnessDetail: String {
        guard let catalogLastSyncDate = vm.catalogLastSyncDate else {
            return vm.catalogModels.isEmpty
                ? String(localized: "The server has not reported a sync timestamp and the catalog is empty.")
                : String(localized: "The server did not report a catalog sync timestamp.")
        }
        return String(localized: "Last synced \(RelativeDateTimeFormatter().localizedString(for: catalogLastSyncDate, relativeTo: Date()))")
    }

    private var headerTitle: some View {
        Label("Integration Pressure", systemImage: "square.3.layers.3d.down.forward")
            .font(.subheadline.weight(.semibold))
    }

    private var headerBadge: some View {
        PresentationToneBadge(
            text: vm.integrationPressureSummaryLabel,
            tone: vm.integrationPressureTone
        )
    }

    @ViewBuilder
    private func integrationIssueRow(icon: String, color: Color, title: String, detail: String) -> some View {
        ResponsiveIconDetailRow(horizontalSpacing: 10, verticalSpacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
        } detail: {
            issueText(title: title, detail: detail)
        }
    }

    private var openLabel: some View {
        Label("Integrations", systemImage: "square.3.layers.3d.down.forward")
            .font(.caption.weight(.semibold))
    }

    private var chevronLabel: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
    }

    private func issueText(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
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
        VStack(alignment: .leading, spacing: 5) {
            ResponsiveAccessoryRow(verticalSpacing: 6) {
                titleLabel
            } accessory: {
                stateLabel
            }

            Text(item.reasons.prefix(3).joined(separator: " • "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private var titleLabel: some View {
        Text(item.agent.name)
            .font(.subheadline.weight(.medium))
    }

    private var stateLabel: some View {
        Text(item.agent.stateLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(item.agent.stateTone.color)
    }
}

private struct IncidentIntegrationAgentRow: View {
    let diagnostic: AgentModelDiagnostic

    var body: some View {
        MonitoringFactsRow(
            verticalSpacing: 6,
            headerVerticalSpacing: 6,
            factsFont: .caption2
        ) {
            summaryBlock
        } accessory: {
            statusLabel
        } facts: {
            metadataLabels
        }
        .padding(.vertical, 2)
    }

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(diagnostic.agent.name)
                .font(.subheadline.weight(.medium))
            Text(diagnostic.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var statusLabel: some View {
        Text(diagnostic.localizedStatusLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(diagnostic.statusTone.color)
    }

    @ViewBuilder
    private var metadataLabels: some View {
        Label(diagnostic.requestedModel, systemImage: "cpu")
        if let resolvedAlias = diagnostic.resolvedAlias {
            Label(resolvedAlias.alias, systemImage: "arrow.left.arrow.right")
        }
        if let resolvedModel = diagnostic.resolvedModel {
            Label(resolvedModel.provider, systemImage: "cloud")
        }
    }
}

private struct IncidentWatchedDiagnosticRow: View {
    let agent: Agent
    let summary: WatchedAgentDiagnosticsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ResponsiveAccessoryRow(horizontalAlignment: .center, verticalSpacing: 6) {
                agentHeader
            } accessory: {
                statusBadge
            }

            Text(summary.summaryLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(destinationHint)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            FlowLayout(spacing: 8) {
                issuePills
            }
        }
        .padding(.vertical, 2)
    }

    private func statusChip(label: String, tone: PresentationTone) -> some View {
        PresentationToneBadge(
            text: label,
            tone: tone,
            horizontalPadding: 6,
            verticalPadding: 2
        )
    }

    private func issuePill(text: String, color: Color) -> some View {
        TintedCapsuleBadge(
            text: text,
            foregroundStyle: color,
            backgroundStyle: color.opacity(0.1),
            horizontalPadding: 6,
            verticalPadding: 2
        )
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

    private var agentHeader: some View {
        ResponsiveInlineGroup(horizontalSpacing: 8, verticalSpacing: 4) {
            headerContent
        }
    }

    private var headerContent: some View {
        Group {
            Text(agent.identity?.emoji ?? "🤖")
                .font(.body)
            Text(agent.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Image(systemName: "star.fill")
                .font(.caption2)
                .foregroundStyle(PresentationTone.caution.color)
        }
    }

    private var statusBadge: some View {
        let badge = watchedAgentDiagnosticStatusBadge(summary: summary)
        return statusChip(label: badge.text, tone: badge.tone)
    }

    @ViewBuilder
    private var issuePills: some View {
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

private struct IncidentSessionRow: View {
    let item: SessionAttentionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ResponsiveAccessoryRow(verticalSpacing: 6) {
                titleLabel
            } accessory: {
                messageCountLabel
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

    private var titleLabel: some View {
        Text(displayTitle)
            .font(.subheadline.weight(.medium))
            .lineLimit(2)
    }

    private var messageCountLabel: some View {
        Text(String(localized: "\(item.session.messageCount) msgs"))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(item.messageCountTone.color)
    }
}

private struct IncidentEventRow: View {
    let entry: AuditEntry
    let agentName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ResponsiveAccessoryRow(verticalSpacing: 6) {
                titleLabel
            } accessory: {
                agentLabel
            }

            Text(entry.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Text(entry.localizedOutcomeLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(entry.severity.tone.color)
        }
        .padding(.vertical, 2)
    }

    private var shortAgentId: String {
        entry.agentId.isEmpty ? "-" : String(entry.agentId.prefix(8))
    }

    private var titleLabel: some View {
        Text(entry.friendlyAction)
            .font(.subheadline.weight(.medium))
            .lineLimit(2)
    }

    private var agentLabel: some View {
        Text(agentName ?? shortAgentId)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

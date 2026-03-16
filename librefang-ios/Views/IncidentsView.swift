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
        ScrollViewReader { proxy in
            List {
                incidentSections(proxy)
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

    @ViewBuilder
    private func incidentSections(_ proxy: ScrollViewProxy) -> some View {
        scoreboardSection
        operatorDeckSection(proxy)

        if !visibleAlerts.isEmpty || !mutedAlerts.isEmpty {
            operatorStateSection
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

        if !visibleAlerts.isEmpty {
            activeAlertsSection
        }

        if !mutedAlerts.isEmpty {
            mutedAlertsSection
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

    private func operatorDeckSection(_ proxy: ScrollViewProxy) -> some View {
        Section {
            IncidentStatusDeckCard(
                activeAlertCount: visibleAlerts.count,
                mutedAlertCount: mutedAlerts.count,
                criticalCount: criticalAlertCount,
                warningCount: warningAlertCount,
                approvalCount: vm.pendingApprovalCount,
                agentCount: combinedAgentIssueCount,
                sessionCount: vm.sessionAttentionCount,
                eventCount: vm.recentCriticalAuditCount,
                automationCount: automationIssueCount,
                integrationCount: integrationIssueCount,
                handoffCount: handoffIssueCount,
                isAcknowledged: isCurrentSnapshotAcknowledged
            )

            IncidentSectionInventoryDeck(
                sectionCount: incidentSectionCount,
                activeAlertCount: visibleAlerts.count,
                mutedAlertCount: mutedAlerts.count,
                approvalCount: vm.pendingApprovalCount,
                agentCount: combinedAgentIssueCount,
                sessionCount: vm.sessionAttentionCount,
                eventCount: vm.recentCriticalAuditCount,
                automationCount: automationIssueCount,
                integrationCount: integrationIssueCount,
                handoffCount: handoffIssueCount
            )

            IncidentPressureCoverageDeck(
                criticalCount: criticalAlertCount,
                warningCount: warningAlertCount,
                approvalCount: vm.pendingApprovalCount,
                agentCount: combinedAgentIssueCount,
                sessionCount: vm.sessionAttentionCount,
                handoffCount: handoffIssueCount,
                automationCount: automationIssueCount,
                integrationCount: integrationIssueCount
            )

            IncidentSupportCoverageDeck(
                mutedAlertCount: mutedAlerts.count,
                handoffCount: handoffIssueCount,
                watchedDiagnosticCount: watchedDiagnosticRows.count,
                criticalAuditCount: vm.recentCriticalAuditCount,
                automationCount: automationIssueCount,
                integrationCount: integrationIssueCount,
                isAcknowledged: isCurrentSnapshotAcknowledged
            )

            IncidentRouteInventoryDeck(
                primaryRouteCount: operatorPrimaryRouteCount,
                supportRouteCount: operatorSupportRouteCount,
                criticalCount: criticalAlertCount,
                approvalCount: vm.pendingApprovalCount,
                sessionCount: vm.sessionAttentionCount,
                automationCount: automationIssueCount,
                integrationCount: integrationIssueCount,
                handoffCount: handoffIssueCount
            )

            MonitoringSurfaceGroupCard(
                title: String(localized: "Routes"),
                detail: String(localized: "Keep the most likely next drilldowns visible before the incident queue.")
            ) {
                MonitoringShortcutRail(
                    title: String(localized: "Primary"),
                    detail: String(localized: "Use the direct monitors first when approvals, sessions, events, or handoff need a dedicated screen.")
                ) {
                    NavigationLink {
                        ApprovalsView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Approvals"),
                            systemImage: "checkmark.shield",
                            tone: approvalCountTone,
                            badgeText: vm.pendingApprovalCount > 0 ? "\(vm.pendingApprovalCount)" : nil
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SessionsView(initialFilter: .attention)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Sessions"),
                            systemImage: "rectangle.stack",
                            tone: sessionCountTone,
                            badgeText: vm.sessionAttentionCount > 0 ? "\(vm.sessionAttentionCount)" : nil
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        EventsView(api: deps.apiClient, initialScope: .critical)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Critical Events"),
                            systemImage: "list.bullet.rectangle.portrait",
                            tone: criticalEventTone,
                            badgeText: vm.recentCriticalAuditCount > 0 ? "\(vm.recentCriticalAuditCount)" : nil
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        HandoffCenterView(
                            summary: handoffText,
                            queueCount: onCallPriorityItems.count,
                            criticalCount: criticalAlertCount,
                            liveAlertCount: visibleAlerts.count
                        )
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Handoff"),
                            systemImage: "text.badge.plus",
                            tone: handoffReadiness.state.tone,
                            badgeText: handoffIssueCount > 0 ? "\(handoffIssueCount)" : nil
                        )
                    }
                    .buttonStyle(.plain)
                }

                MonitoringShortcutRail(
                    title: String(localized: "Support"),
                    detail: String(localized: "Use the broader runtime path when the incident needs deeper infrastructure context.")
                ) {
                    NavigationLink {
                        RuntimeView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Runtime"),
                            systemImage: "server.rack",
                            tone: runtimeSurfaceTone,
                            badgeText: vm.runtimeAlertCount > 0 ? "\(vm.runtimeAlertCount)" : nil
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Diagnostics"),
                            systemImage: "stethoscope",
                            tone: .neutral
                        )
                    }
                    .buttonStyle(.plain)

                    if automationIssueCount > 0 {
                        NavigationLink {
                            AutomationView()
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Automation"),
                                systemImage: "flowchart",
                                tone: .warning,
                                badgeText: "\(automationIssueCount)"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if integrationIssueCount > 0 {
                        NavigationLink {
                            IntegrationsView(initialScope: .attention)
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Integrations"),
                                systemImage: "square.3.layers.3d.down.forward",
                                tone: .critical,
                                badgeText: "\(integrationIssueCount)"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            IncidentQueueInventoryDeck(
                primarySectionCount: primaryQueueSectionCount,
                supportSectionCount: supportQueueSectionCount,
                activeAlertCount: visibleAlerts.count,
                mutedAlertCount: mutedAlerts.count,
                approvalCount: vm.pendingApprovalCount,
                watchedDiagnosticsCount: watchedDiagnosticRows.count,
                criticalEventCount: vm.recentCriticalAuditCount
            )

            MonitoringSurfaceGroupCard(
                title: String(localized: "Queue"),
                detail: String(localized: "Jump around the incident buckets themselves without dragging through the entire list.")
            ) {
                MonitoringShortcutRail(
                    title: String(localized: "Primary Queue Sections"),
                    detail: String(localized: "Keep the live operator controls and highest-priority buckets closest to the top.")
                ) {
                    if !visibleAlerts.isEmpty || !mutedAlerts.isEmpty {
                        Button {
                            jump(proxy, to: .operatorState)
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Operator State"),
                                systemImage: "person.crop.circle.badge.checkmark",
                                tone: isCurrentSnapshotAcknowledged ? .neutral : .warning
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if handoffIssueCount > 0 {
                        Button {
                            jump(proxy, to: .shiftCoverage)
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Shift Coverage"),
                                systemImage: "text.badge.plus",
                                tone: handoffReadiness.state.tone,
                                badgeText: "\(handoffIssueCount)"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if !visibleAlerts.isEmpty {
                        Button {
                            jump(proxy, to: .activeAlerts)
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Active Alerts"),
                                systemImage: "bell.badge",
                                tone: criticalAlertCount > 0 ? .critical : .warning,
                                badgeText: "\(visibleAlerts.count)"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if !vm.approvals.isEmpty {
                        Button {
                            jump(proxy, to: .approvals)
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Approvals"),
                                systemImage: "checkmark.shield",
                                tone: .critical,
                                badgeText: "\(vm.pendingApprovalCount)"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if !vm.sessionAttentionItems.isEmpty {
                        Button {
                            jump(proxy, to: .sessions)
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Session Hotspots"),
                                systemImage: "rectangle.stack",
                                tone: .warning,
                                badgeText: "\(vm.sessionAttentionCount)"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                MonitoringShortcutRail(
                    title: String(localized: "Supporting Queue Sections"),
                    detail: String(localized: "Keep slower infrastructure and secondary drilldowns behind the primary buckets.")
                ) {
                    if automationIssueCount > 0 {
                        Button {
                            jump(proxy, to: .automation)
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Automation Pressure"),
                                systemImage: "flowchart",
                                tone: .warning,
                                badgeText: "\(automationIssueCount)"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if integrationIssueCount > 0 {
                        Button {
                            jump(proxy, to: .integrations)
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Integration Pressure"),
                                systemImage: "square.3.layers.3d.down.forward",
                                tone: .critical,
                                badgeText: "\(integrationIssueCount)"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if !vm.attentionAgents.isEmpty {
                        Button {
                            jump(proxy, to: .agents)
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Agent Attention"),
                                systemImage: "cpu",
                                tone: .warning,
                                badgeText: "\(vm.attentionAgents.count)"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if !watchedDiagnosticRows.isEmpty {
                        Button {
                            jump(proxy, to: .watchedDiagnostics)
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Watched Diagnostics"),
                                systemImage: "star.fill",
                                tone: .caution,
                                badgeText: "\(watchedDiagnosticRows.count)"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if !vm.criticalAuditEntries.isEmpty {
                        Button {
                            jump(proxy, to: .criticalEvents)
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Critical Events"),
                                systemImage: "list.bullet.rectangle.portrait",
                                tone: .critical,
                                badgeText: "\(vm.criticalAuditEntries.count)"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } header: {
            Text("Controls")
        } footer: {
            Text("Keep incident buckets, primary drilldowns, and queue jumps together before the grouped incident list.")
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
        } footer: {
            Text("These handoff signals are local to this iPhone and help keep operator follow-through visible inside the incident flow.")
        }
        .id(IncidentSectionAnchor.shiftCoverage)
    }

    private var automationSection: some View {
        Section {
            IncidentAutomationInventoryDeck(
                issueCategoryCount: automationIssueCount,
                failedWorkflowRunCount: vm.failedWorkflowRunCount,
                exhaustedTriggerCount: vm.exhaustedTriggerCount,
                stalledCronJobCount: vm.stalledCronJobCount
            )

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
        .id(IncidentSectionAnchor.automation)
    }

    private var integrationsSection: some View {
        Section {
            IncidentIntegrationsInventoryDeck(
                issueCategoryCount: integrationIssueCount,
                providerFailureCount: vm.unreachableLocalProviderCount,
                channelGapCount: vm.channelRequiredFieldGapCount,
                hasEmptyCatalog: vm.hasEmptyModelCatalog,
                modelDriftCount: vm.agentsWithModelDiagnostics.count,
                visibleDiagnosticCount: min(vm.agentsWithModelDiagnostics.count, 3)
            )

            NavigationLink {
                IntegrationsView(initialScope: .attention)
            } label: {
                IncidentIntegrationsCard(vm: vm)
            }

            if vm.unreachableLocalProviderCount > 0 || vm.channelRequiredFieldGapCount > 0 || vm.hasEmptyModelCatalog {
                MonitoringSurfaceGroupCard(
                    title: String(localized: "Routes"),
                    detail: String(localized: "Jump directly into the most likely provider, channel, or catalog failure path.")
                ) {
                    MonitoringShortcutRail(title: String(localized: "Targets")) {
                        if vm.unreachableLocalProviderCount > 0 {
                            NavigationLink {
                                IntegrationsView(
                                    initialSearchText: vm.unreachableLocalProviders.count == 1 ? vm.unreachableLocalProviders[0].displayName : "",
                                    initialScope: .attention
                                )
                            } label: {
                                MonitoringSurfaceShortcutChip(
                                    title: String(localized: "Provider Failures"),
                                    systemImage: "network.slash",
                                    tone: .critical,
                                    badgeText: "\(vm.unreachableLocalProviderCount)"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if vm.channelRequiredFieldGapCount > 0 {
                            NavigationLink {
                                IntegrationsView(
                                    initialSearchText: vm.channelsMissingRequiredFields.count == 1 ? vm.channelsMissingRequiredFields[0].displayName : "",
                                    initialScope: .attention
                                )
                            } label: {
                                MonitoringSurfaceShortcutChip(
                                    title: String(localized: "Channel Gaps"),
                                    systemImage: "bubble.left.and.exclamationmark.bubble.right",
                                    tone: .warning,
                                    badgeText: "\(vm.channelRequiredFieldGapCount)"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if vm.hasEmptyModelCatalog {
                            NavigationLink {
                                IntegrationsView(initialScope: .attention)
                            } label: {
                                MonitoringSurfaceShortcutChip(
                                    title: String(localized: "Catalog Availability"),
                                    systemImage: "square.stack.3d.up.slash",
                                    tone: .critical
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
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
        .id(IncidentSectionAnchor.integrations)
    }

    private var activeAlertsSection: some View {
        Section {
            ActiveAlertsInventoryDeck(
                alerts: visibleAlerts,
                mutedCount: mutedAlerts.count
            )

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
            IncidentApprovalsInventoryDeck(
                visibleCount: min(vm.approvals.count, 4),
                totalCount: vm.approvals.count,
                highRiskCount: approvalsHighRiskCount,
                agentCount: approvalAgentCount
            )

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

            MonitoringSurfaceGroupCard(
                title: String(localized: "Routes"),
                detail: String(localized: "Open the dedicated approval monitor when the compact incident list is not enough.")
            ) {
                MonitoringShortcutRail(title: String(localized: "Approvals")) {
                    NavigationLink {
                        ApprovalsView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Queue"),
                            systemImage: "checkmark.shield",
                            tone: .warning,
                            badgeText: "\(vm.pendingApprovalCount)"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        OnCallView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "On Call"),
                            systemImage: "waveform.path.ecg",
                            tone: .warning
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Pending Approvals")
        } footer: {
            Text("Approvals block sensitive actions until an operator responds. Mobile can now resolve them directly after confirmation.")
        }
        .id(IncidentSectionAnchor.approvals)
    }

    private var agentsSection: some View {
        Section {
            IncidentAgentsInventoryDeck(
                visibleCount: min(vm.attentionAgents.count, 5),
                totalCount: vm.issueAgentCount,
                authIssueCount: attentionAgentAuthIssueCount,
                approvalCount: attentionAgentApprovalCount,
                staleCount: attentionAgentStaleCount,
                watchedDiagnosticsCount: watchedDiagnosticRows.count
            )

            ForEach(vm.attentionAgents.prefix(5)) { item in
                NavigationLink {
                    AgentDetailView(agent: item.agent)
                } label: {
                    IncidentAgentRow(item: item)
                }
            }

            MonitoringSurfaceGroupCard(
                title: String(localized: "Routes"),
                detail: String(localized: "Open the full fleet monitor when agent pressure spreads beyond the top incident rows.")
            ) {
                MonitoringShortcutRail(title: String(localized: "Fleet")) {
                    NavigationLink {
                        AgentsView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Agents"),
                            systemImage: "person.3",
                            tone: .warning,
                            badgeText: "\(vm.issueAgentCount)"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Agents")
        } footer: {
            Text("\(vm.issueAgentCount) agents currently need attention")
        }
        .id(IncidentSectionAnchor.agents)
    }

    private var watchedDiagnosticsSection: some View {
        Section {
            IncidentWatchedDiagnosticsInventoryDeck(
                visibleCount: min(watchedDiagnosticRows.count, 5),
                totalCount: watchedDiagnosticRows.count,
                failedAgentCount: watchedFailedAgentCount,
                missingIdentityAgentCount: watchedMissingIdentityAgentCount,
                fallbackAgentCount: watchedFallbackAgentCount,
                unsettledAgentCount: watchedUnsettledAgentCount
            )

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
        .id(IncidentSectionAnchor.watchedDiagnostics)
    }

    private var sessionsSection: some View {
        Section {
            IncidentSessionsInventoryDeck(
                visibleCount: min(vm.sessionAttentionItems.count, 5),
                totalCount: vm.sessionAttentionCount,
                unlabeledCount: unlabeledSessionCount,
                duplicateCount: duplicateSessionCount,
                visibleMessageCount: visibleSessionMessageCount
            )

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

            MonitoringSurfaceGroupCard(
                title: String(localized: "Routes"),
                detail: String(localized: "Open the dedicated session monitor when hotspots spread beyond the compact incident list.")
            ) {
                MonitoringShortcutRail(title: String(localized: "Sessions")) {
                    NavigationLink {
                        SessionsView(initialFilter: .attention)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Monitor"),
                            systemImage: "rectangle.stack",
                            tone: .warning,
                            badgeText: "\(vm.sessionAttentionCount)"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        RuntimeView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Runtime"),
                            systemImage: "server.rack",
                            tone: .neutral
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Sessions")
        } footer: {
            Text("\(vm.sessionAttentionCount) sessions need review")
        }
        .id(IncidentSectionAnchor.sessions)
    }

    private var criticalEventsSection: some View {
        Section {
            IncidentEventsInventoryDeck(
                visibleCount: min(vm.criticalAuditEntries.count, 5),
                totalCount: vm.recentCriticalAuditCount,
                agentCount: criticalEventAgentCount,
                actionCount: criticalEventActionCount
            )

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

            MonitoringSurfaceGroupCard(
                title: String(localized: "Routes"),
                detail: String(localized: "Open the full event feed when the compact critical trail needs deeper inspection.")
            ) {
                MonitoringShortcutRail(title: String(localized: "Events")) {
                    NavigationLink {
                        EventsView(api: deps.apiClient, initialScope: .critical)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Feed"),
                            systemImage: "list.bullet.rectangle.portrait",
                            tone: .critical,
                            badgeText: "\(vm.recentCriticalAuditCount)"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Diagnostics"),
                            systemImage: "stethoscope",
                            tone: .neutral
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Critical Events")
        } footer: {
            Text("\(vm.recentCriticalAuditCount) recent critical audit events already surfaced on mobile")
        }
        .id(IncidentSectionAnchor.criticalEvents)
    }

    private func jump(_ proxy: ScrollViewProxy, to anchor: IncidentSectionAnchor) {
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
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

private struct IncidentStatusDeckCard: View {
    let activeAlertCount: Int
    let mutedAlertCount: Int
    let criticalCount: Int
    let warningCount: Int
    let approvalCount: Int
    let agentCount: Int
    let sessionCount: Int
    let eventCount: Int
    let automationCount: Int
    let integrationCount: Int
    let handoffCount: Int
    let isAcknowledged: Bool

    private var summaryLine: String {
        if activeAlertCount > 0 {
            if isAcknowledged {
                return activeAlertCount == 1
                    ? String(localized: "1 active alert is acknowledged in the incident queue.")
                    : String(localized: "\(activeAlertCount) active alerts are acknowledged in the incident queue.")
            }

            return activeAlertCount == 1
                ? String(localized: "1 active alert needs review in the incident queue.")
                : String(localized: "\(activeAlertCount) active alerts need review in the incident queue.")
        }

        if mutedAlertCount > 0 {
            return mutedAlertCount == 1
                ? String(localized: "1 muted alert remains visible in the incident queue.")
                : String(localized: "\(mutedAlertCount) muted alerts remain visible in the incident queue.")
        }

        return String(localized: "Incident queue is clear.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(summary: summaryLine, verticalPadding: 4) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: activeAlertCount == 1 ? String(localized: "1 active alert") : String(localized: "\(activeAlertCount) active alerts"),
                        tone: activeAlertCount > 0 ? .critical : .neutral
                    )
                    if mutedAlertCount > 0 {
                        PresentationToneBadge(
                            text: mutedAlertCount == 1 ? String(localized: "1 muted") : String(localized: "\(mutedAlertCount) muted"),
                            tone: .positive
                        )
                    }
                    if approvalCount > 0 {
                        PresentationToneBadge(
                            text: approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                            tone: .warning
                        )
                    }
                    if agentCount > 0 {
                        PresentationToneBadge(
                            text: agentCount == 1 ? String(localized: "1 agent") : String(localized: "\(agentCount) agents"),
                            tone: .warning
                        )
                    }
                    if sessionCount > 0 {
                        PresentationToneBadge(
                            text: sessionCount == 1 ? String(localized: "1 session") : String(localized: "\(sessionCount) sessions"),
                            tone: .warning
                        )
                    }
                    if eventCount > 0 {
                        PresentationToneBadge(
                            text: eventCount == 1 ? String(localized: "1 event") : String(localized: "\(eventCount) events"),
                            tone: .critical
                        )
                    }
                    if automationCount > 0 {
                        PresentationToneBadge(
                            text: automationCount == 1 ? String(localized: "1 automation") : String(localized: "\(automationCount) automation"),
                            tone: .warning
                        )
                    }
                    if integrationCount > 0 {
                        PresentationToneBadge(
                            text: integrationCount == 1 ? String(localized: "1 integration") : String(localized: "\(integrationCount) integration"),
                            tone: .warning
                        )
                    }
                    if handoffCount > 0 {
                        PresentationToneBadge(
                            text: handoffCount == 1 ? String(localized: "1 handoff item") : String(localized: "\(handoffCount) handoff items"),
                            tone: .warning
                        )
                    }
                    PresentationToneBadge(
                        text: isAcknowledged ? String(localized: "Acked") : String(localized: "Live"),
                        tone: isAcknowledged ? .positive : .critical
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Incident queue facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Use this digest to judge whether alerts, approvals, handoff coverage, or deeper monitors deserve the next tap."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: isAcknowledged ? String(localized: "Acked") : String(localized: "Live"),
                    tone: isAcknowledged ? .positive : .critical
                )
            } facts: {
                Label(
                    criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                    systemImage: "xmark.octagon"
                )
                if warningCount > 0 {
                    Label(
                        warningCount == 1 ? String(localized: "1 warning") : String(localized: "\(warningCount) warnings"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if mutedAlertCount > 0 {
                    Label(
                        mutedAlertCount == 1 ? String(localized: "1 muted") : String(localized: "\(mutedAlertCount) muted"),
                        systemImage: "bell.slash"
                    )
                }
                if approvalCount > 0 {
                    Label(
                        approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                        systemImage: "checkmark.shield"
                    )
                }
                if agentCount > 0 {
                    Label(
                        agentCount == 1 ? String(localized: "1 agent issue") : String(localized: "\(agentCount) agent issues"),
                        systemImage: "cpu"
                    )
                }
                if sessionCount > 0 {
                    Label(
                        sessionCount == 1 ? String(localized: "1 session hotspot") : String(localized: "\(sessionCount) session hotspots"),
                        systemImage: "rectangle.stack"
                    )
                }
                if eventCount > 0 {
                    Label(
                        eventCount == 1 ? String(localized: "1 critical event") : String(localized: "\(eventCount) critical events"),
                        systemImage: "list.bullet.rectangle.portrait"
                    )
                }
                if automationCount > 0 {
                    Label(
                        automationCount == 1 ? String(localized: "1 automation issue") : String(localized: "\(automationCount) automation issues"),
                        systemImage: "flowchart"
                    )
                }
                if integrationCount > 0 {
                    Label(
                        integrationCount == 1 ? String(localized: "1 integration issue") : String(localized: "\(integrationCount) integration issues"),
                        systemImage: "square.3.layers.3d.down.forward"
                    )
                }
                if handoffCount > 0 {
                    Label(
                        handoffCount == 1 ? String(localized: "1 handoff issue") : String(localized: "\(handoffCount) handoff issues"),
                        systemImage: "text.badge.plus"
                    )
                }
            }
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

private struct ActiveAlertsInventoryDeck: View {
    let alerts: [MonitoringAlertItem]
    let mutedCount: Int

    private var criticalCount: Int {
        alerts.filter { $0.severity == .critical }.count
    }

    private var warningCount: Int {
        alerts.filter { $0.severity == .warning }.count
    }

    private var infoCount: Int {
        alerts.filter { $0.severity == .info }.count
    }

    private var symbolCount: Int {
        Set(alerts.map(\.symbolName)).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: detailLine,
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if criticalCount > 0 {
                        PresentationToneBadge(
                            text: criticalCount == 1 ? String(localized: "1 critical visible") : String(localized: "\(criticalCount) critical visible"),
                            tone: .critical
                        )
                    }
                    if warningCount > 0 {
                        PresentationToneBadge(
                            text: warningCount == 1 ? String(localized: "1 warning visible") : String(localized: "\(warningCount) warnings visible"),
                            tone: .warning
                        )
                    }
                    if infoCount > 0 {
                        PresentationToneBadge(
                            text: infoCount == 1 ? String(localized: "1 info visible") : String(localized: "\(infoCount) info visible"),
                            tone: .caution
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Alert inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Use the compact alert slice to gauge severity mix and muted spillover before opening each alert row."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: alerts.count == 1 ? String(localized: "1 active") : String(localized: "\(alerts.count) active"),
                    tone: alerts.isEmpty ? .neutral : .critical
                )
            } facts: {
                Label(
                    symbolCount == 1 ? String(localized: "1 alert type") : String(localized: "\(symbolCount) alert types"),
                    systemImage: "bell.badge"
                )
                if mutedCount > 0 {
                    Label(
                        mutedCount == 1 ? String(localized: "1 muted") : String(localized: "\(mutedCount) muted"),
                        systemImage: "bell.slash"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if alerts.count == 1 {
            return String(localized: "The incidents list is showing the only active alert.")
        }
        return String(localized: "The incidents list is showing all \(alerts.count) active alerts.")
    }

    private var detailLine: String {
        if mutedCount > 0 {
            return String(localized: "\(mutedCount) additional alerts are muted locally, so the active slice is not the full phone-level incident picture.")
        }
        return String(localized: "Active severity and alert type spread stay summarized here before the per-alert controls.")
    }
}

private struct IncidentSectionInventoryDeck: View {
    let sectionCount: Int
    let activeAlertCount: Int
    let mutedAlertCount: Int
    let approvalCount: Int
    let agentCount: Int
    let sessionCount: Int
    let eventCount: Int
    let automationCount: Int
    let integrationCount: Int
    let handoffCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: activeAlertCount == 1 ? String(localized: "1 active alert") : String(localized: "\(activeAlertCount) active alerts"),
                        tone: activeAlertCount > 0 ? .critical : .neutral
                    )
                    if mutedAlertCount > 0 {
                        PresentationToneBadge(
                            text: mutedAlertCount == 1 ? String(localized: "1 muted alert") : String(localized: "\(mutedAlertCount) muted alerts"),
                            tone: .neutral
                        )
                    }
                    if handoffCount > 0 {
                        PresentationToneBadge(
                            text: handoffCount == 1 ? String(localized: "1 handoff issue") : String(localized: "\(handoffCount) handoff issues"),
                            tone: .warning
                        )
                    }
                    if automationCount > 0 {
                        PresentationToneBadge(
                            text: automationCount == 1 ? String(localized: "1 automation issue") : String(localized: "\(automationCount) automation issues"),
                            tone: .warning
                        )
                    }
                    if integrationCount > 0 {
                        PresentationToneBadge(
                            text: integrationCount == 1 ? String(localized: "1 integration issue") : String(localized: "\(integrationCount) integration issues"),
                            tone: .critical
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Incident inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep queue coverage and cross-surface pressure visible before the incident routes and bucket lists begin."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: sectionCount == 1 ? String(localized: "1 section") : String(localized: "\(sectionCount) sections"),
                    tone: sectionCount > 0 ? .positive : .neutral
                )
            } facts: {
                Label(
                    approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                    systemImage: "checkmark.shield"
                )
                Label(
                    agentCount == 1 ? String(localized: "1 agent issue") : String(localized: "\(agentCount) agent issues"),
                    systemImage: "person.3"
                )
                Label(
                    sessionCount == 1 ? String(localized: "1 session hotspot") : String(localized: "\(sessionCount) session hotspots"),
                    systemImage: "rectangle.stack"
                )
                Label(
                    eventCount == 1 ? String(localized: "1 critical event") : String(localized: "\(eventCount) critical events"),
                    systemImage: "list.bullet.rectangle.portrait"
                )
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        sectionCount == 1
            ? String(localized: "1 incident section is active in the current queue.")
            : String(localized: "\(sectionCount) incident sections are active in the current queue.")
    }

    private var detailLine: String {
        String(localized: "Alerts, approvals, sessions, events, automation, integrations, and handoff pressure stay grouped before the routes fan out.")
    }
}

private struct IncidentPressureCoverageDeck: View {
    let criticalCount: Int
    let warningCount: Int
    let approvalCount: Int
    let agentCount: Int
    let sessionCount: Int
    let handoffCount: Int
    let automationCount: Int
    let integrationCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: String(localized: "Incident pressure coverage keeps the active severity mix readable before routes and queue buckets."),
                detail: String(localized: "Use this deck to see whether current incident drag comes from alerts, approvals, fleet issues, sessions, or slower infra follow-up."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if criticalCount > 0 {
                        PresentationToneBadge(
                            text: criticalCount == 1 ? String(localized: "1 critical alert") : String(localized: "\(criticalCount) critical alerts"),
                            tone: .critical
                        )
                    }
                    if warningCount > 0 {
                        PresentationToneBadge(
                            text: warningCount == 1 ? String(localized: "1 warning alert") : String(localized: "\(warningCount) warning alerts"),
                            tone: .warning
                        )
                    }
                    if handoffCount > 0 {
                        PresentationToneBadge(
                            text: handoffCount == 1 ? String(localized: "1 handoff issue") : String(localized: "\(handoffCount) handoff issues"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Pressure coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the operator burden readable before diving into the incident buckets themselves."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                    tone: approvalCount > 0 ? .warning : .neutral
                )
            } facts: {
                Label(
                    agentCount == 1 ? String(localized: "1 agent issue") : String(localized: "\(agentCount) agent issues"),
                    systemImage: "person.3"
                )
                Label(
                    sessionCount == 1 ? String(localized: "1 session hotspot") : String(localized: "\(sessionCount) session hotspots"),
                    systemImage: "rectangle.stack"
                )
                if automationCount > 0 {
                    Label(
                        automationCount == 1 ? String(localized: "1 automation issue") : String(localized: "\(automationCount) automation issues"),
                        systemImage: "flowchart"
                    )
                }
                if integrationCount > 0 {
                    Label(
                        integrationCount == 1 ? String(localized: "1 integration issue") : String(localized: "\(integrationCount) integration issues"),
                        systemImage: "square.3.layers.3d.down.forward"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct IncidentSupportCoverageDeck: View {
    let mutedAlertCount: Int
    let handoffCount: Int
    let watchedDiagnosticCount: Int
    let criticalAuditCount: Int
    let automationCount: Int
    let integrationCount: Int
    let isAcknowledged: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep muted drag, watched diagnostics, audit pressure, and slower platform follow-up readable before the incident routes and queue buckets begin."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: isAcknowledged ? String(localized: "Snapshot acknowledged") : String(localized: "Snapshot live"),
                        tone: isAcknowledged ? .positive : .warning
                    )
                    if mutedAlertCount > 0 {
                        PresentationToneBadge(
                            text: mutedAlertCount == 1 ? String(localized: "1 muted alert") : String(localized: "\(mutedAlertCount) muted alerts"),
                            tone: .neutral
                        )
                    }
                    if handoffCount > 0 {
                        PresentationToneBadge(
                            text: handoffCount == 1 ? String(localized: "1 handoff issue") : String(localized: "\(handoffCount) handoff issues"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Support coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep handoff drag, watched diagnostics, audit pressure, and slower automation or integration load visible before the incident buckets take over."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: criticalAuditCount == 1 ? String(localized: "1 critical audit") : String(localized: "\(criticalAuditCount) critical audits"),
                    tone: criticalAuditCount > 0 ? .critical : .neutral
                )
            } facts: {
                if watchedDiagnosticCount > 0 {
                    Label(
                        watchedDiagnosticCount == 1 ? String(localized: "1 watched diagnostic issue") : String(localized: "\(watchedDiagnosticCount) watched diagnostic issues"),
                        systemImage: "star.circle"
                    )
                }
                if automationCount > 0 {
                    Label(
                        automationCount == 1 ? String(localized: "1 automation issue") : String(localized: "\(automationCount) automation issues"),
                        systemImage: "flowchart"
                    )
                }
                if integrationCount > 0 {
                    Label(
                        integrationCount == 1 ? String(localized: "1 integration issue") : String(localized: "\(integrationCount) integration issues"),
                        systemImage: "square.3.layers.3d.down.forward"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if criticalAuditCount > 0 || integrationCount > 0 {
            return String(localized: "Incident support coverage is currently anchored by critical audit or integration drag beyond the live alert buckets.")
        }
        if mutedAlertCount > 0 || handoffCount > 0 || watchedDiagnosticCount > 0 {
            return String(localized: "Incident support coverage is currently anchored by muted alert drag, handoff load, and watched diagnostics.")
        }
        if isAcknowledged {
            return String(localized: "Incident support coverage is currently light, and the active snapshot is acknowledged.")
        }
        return String(localized: "Incident support coverage is currently light and mostly reflects slower automation and audit context.")
    }
}

private struct IncidentRouteInventoryDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let criticalCount: Int
    let approvalCount: Int
    let sessionCount: Int
    let automationCount: Int
    let integrationCount: Int
    let handoffCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: primaryRouteCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryRouteCount) primary routes"),
                        tone: .critical
                    )
                    PresentationToneBadge(
                        text: supportRouteCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportRouteCount) support routes"),
                        tone: .neutral
                    )
                    if criticalCount > 0 {
                        PresentationToneBadge(
                            text: criticalCount == 1 ? String(localized: "1 critical route") : String(localized: "\(criticalCount) critical routes"),
                            tone: .critical
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Route inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the fastest incident drilldowns separate from deeper runtime and infrastructure exits before the queue begins."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: String(localized: "\(primaryRouteCount + supportRouteCount) exits"),
                    tone: .neutral
                )
            } facts: {
                if approvalCount > 0 {
                    Label(
                        approvalCount == 1 ? String(localized: "1 approval route") : String(localized: "\(approvalCount) approval routes"),
                        systemImage: "checkmark.shield"
                    )
                }
                if sessionCount > 0 {
                    Label(
                        sessionCount == 1 ? String(localized: "1 session route") : String(localized: "\(sessionCount) session routes"),
                        systemImage: "rectangle.stack"
                    )
                }
                if automationCount > 0 {
                    Label(
                        automationCount == 1 ? String(localized: "1 automation route") : String(localized: "\(automationCount) automation routes"),
                        systemImage: "flowchart"
                    )
                }
                if integrationCount > 0 {
                    Label(
                        integrationCount == 1 ? String(localized: "1 integration route") : String(localized: "\(integrationCount) integration routes"),
                        systemImage: "square.3.layers.3d.down.forward"
                    )
                }
                if handoffCount > 0 {
                    Label(
                        handoffCount == 1 ? String(localized: "1 handoff route") : String(localized: "\(handoffCount) handoff routes"),
                        systemImage: "text.badge.plus"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        String(localized: "Incident controls are grouping \(primaryRouteCount) primary routes and \(supportRouteCount) support routes before the queue.")
    }

    private var detailLine: String {
        String(localized: "Primary exits stay biased toward the next likely triage surfaces, while support exits keep deeper runtime context nearby.")
    }
}

private struct IncidentQueueInventoryDeck: View {
    let primarySectionCount: Int
    let supportSectionCount: Int
    let activeAlertCount: Int
    let mutedAlertCount: Int
    let approvalCount: Int
    let watchedDiagnosticsCount: Int
    let criticalEventCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: primarySectionCount == 1 ? String(localized: "1 primary bucket") : String(localized: "\(primarySectionCount) primary buckets"),
                        tone: .warning
                    )
                    if supportSectionCount > 0 {
                        PresentationToneBadge(
                            text: supportSectionCount == 1 ? String(localized: "1 support bucket") : String(localized: "\(supportSectionCount) support buckets"),
                            tone: .neutral
                        )
                    }
                    if activeAlertCount > 0 {
                        PresentationToneBadge(
                            text: activeAlertCount == 1 ? String(localized: "1 active alert bucket") : String(localized: "\(activeAlertCount) active alert buckets"),
                            tone: .critical
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Queue inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Use the queue split to tell whether the next tap belongs in live operator buckets or slower infrastructure follow-up."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: supportSectionCount == 0
                        ? String(localized: "Primary only")
                        : String(localized: "\(primarySectionCount + supportSectionCount) buckets"),
                    tone: supportSectionCount == 0 ? .warning : .neutral
                )
            } facts: {
                if mutedAlertCount > 0 {
                    Label(
                        mutedAlertCount == 1 ? String(localized: "1 muted bucket") : String(localized: "\(mutedAlertCount) muted buckets"),
                        systemImage: "bell.slash"
                    )
                }
                if approvalCount > 0 {
                    Label(
                        approvalCount == 1 ? String(localized: "1 approval bucket") : String(localized: "\(approvalCount) approval buckets"),
                        systemImage: "checkmark.shield"
                    )
                }
                if watchedDiagnosticsCount > 0 {
                    Label(
                        watchedDiagnosticsCount == 1 ? String(localized: "1 watched bucket") : String(localized: "\(watchedDiagnosticsCount) watched buckets"),
                        systemImage: "star.fill"
                    )
                }
                if criticalEventCount > 0 {
                    Label(
                        criticalEventCount == 1 ? String(localized: "1 event bucket") : String(localized: "\(criticalEventCount) event buckets"),
                        systemImage: "list.bullet.rectangle.portrait"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        supportSectionCount == 0
            ? String(localized: "Incident queue is currently concentrated in the primary buckets.")
            : String(localized: "Incident queue is split across \(primarySectionCount) primary and \(supportSectionCount) support buckets.")
    }

    private var detailLine: String {
        String(localized: "Primary buckets keep the operator loop near the top, while support buckets hold slower diagnostics and fleet follow-up.")
    }
}

private struct IncidentAutomationInventoryDeck: View {
    let issueCategoryCount: Int
    let failedWorkflowRunCount: Int
    let exhaustedTriggerCount: Int
    let stalledCronJobCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: issueCategoryCount == 1 ? String(localized: "1 issue class") : String(localized: "\(issueCategoryCount) issue classes"),
                        tone: issueCategoryCount > 0 ? .warning : .neutral
                    )
                    if failedWorkflowRunCount > 0 {
                        PresentationToneBadge(
                            text: failedWorkflowRunCount == 1 ? String(localized: "1 failed run") : String(localized: "\(failedWorkflowRunCount) failed runs"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Automation inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep workflow, trigger, and cron pressure readable before opening the dedicated automation monitor."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: issueCategoryCount == 0 ? String(localized: "Stable") : String(localized: "\(issueCategoryCount) issues"), tone: issueCategoryCount > 0 ? .warning : .positive)
            } facts: {
                if exhaustedTriggerCount > 0 {
                    Label(
                        exhaustedTriggerCount == 1 ? String(localized: "1 exhausted trigger") : String(localized: "\(exhaustedTriggerCount) exhausted triggers"),
                        systemImage: "bolt.horizontal.circle"
                    )
                }
                if stalledCronJobCount > 0 {
                    Label(
                        stalledCronJobCount == 1 ? String(localized: "1 stalled cron") : String(localized: "\(stalledCronJobCount) stalled cron jobs"),
                        systemImage: "clock.badge.exclamationmark"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        issueCategoryCount == 0
            ? String(localized: "Automation pressure is currently quiet in the incident queue.")
            : String(localized: "Automation pressure spans \(issueCategoryCount) issue classes in the incident queue.")
    }

    private var detailLine: String {
        String(localized: "Workflow failures, exhausted triggers, and stalled cron jobs stay summarized here before the larger automation monitor opens.")
    }
}

private struct IncidentIntegrationsInventoryDeck: View {
    let issueCategoryCount: Int
    let providerFailureCount: Int
    let channelGapCount: Int
    let hasEmptyCatalog: Bool
    let modelDriftCount: Int
    let visibleDiagnosticCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: issueCategoryCount == 1 ? String(localized: "1 issue class") : String(localized: "\(issueCategoryCount) issue classes"),
                        tone: issueCategoryCount > 0 ? .critical : .neutral
                    )
                    if visibleDiagnosticCount > 0 {
                        PresentationToneBadge(
                            text: visibleDiagnosticCount == 1 ? String(localized: "1 drift agent visible") : String(localized: "\(visibleDiagnosticCount) drift agents visible"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Integration inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep provider, channel, catalog, and drift pressure visible before the integration monitor or per-agent drilldowns."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: issueCategoryCount == 0 ? String(localized: "Stable") : String(localized: "\(issueCategoryCount) issues"), tone: issueCategoryCount > 0 ? .critical : .positive)
            } facts: {
                if providerFailureCount > 0 {
                    Label(
                        providerFailureCount == 1 ? String(localized: "1 provider failure") : String(localized: "\(providerFailureCount) provider failures"),
                        systemImage: "network.slash"
                    )
                }
                if channelGapCount > 0 {
                    Label(
                        channelGapCount == 1 ? String(localized: "1 channel gap") : String(localized: "\(channelGapCount) channel gaps"),
                        systemImage: "bubble.left.and.exclamationmark.bubble.right"
                    )
                }
                if hasEmptyCatalog {
                    Label(String(localized: "Catalog empty"), systemImage: "square.stack.3d.up.slash")
                }
                if modelDriftCount > 0 {
                    Label(
                        modelDriftCount == 1 ? String(localized: "1 drift agent") : String(localized: "\(modelDriftCount) drift agents"),
                        systemImage: "triangle.2.circlepath"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        issueCategoryCount == 0
            ? String(localized: "Integration pressure is currently quiet in the incident queue.")
            : String(localized: "Integration pressure spans \(issueCategoryCount) issue classes in the incident queue.")
    }

    private var detailLine: String {
        String(localized: "Provider reachability, channel config gaps, catalog freshness, and drift stay compact before the larger integration drilldown.")
    }
}

private struct IncidentApprovalsInventoryDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let highRiskCount: Int
    let agentCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: visibleCount == 1 ? String(localized: "1 approval visible") : String(localized: "\(visibleCount) approvals visible"),
                        tone: totalCount > 0 ? .warning : .neutral
                    )
                    if highRiskCount > 0 {
                        PresentationToneBadge(
                            text: highRiskCount == 1 ? String(localized: "1 high risk") : String(localized: "\(highRiskCount) high risk"),
                            tone: .critical
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Approval inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep risk spread and agent breadth visible before the compact approval rows or the full queue view."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: totalCount == 1 ? String(localized: "1 pending") : String(localized: "\(totalCount) pending"), tone: totalCount > 0 ? .warning : .neutral)
            } facts: {
                Label(
                    agentCount == 1 ? String(localized: "1 agent involved") : String(localized: "\(agentCount) agents involved"),
                    systemImage: "cpu"
                )
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if visibleCount == totalCount {
            return totalCount == 1
                ? String(localized: "The incident queue is showing the only pending approval.")
                : String(localized: "The incident queue is showing all \(totalCount) pending approvals.")
        }
        return String(localized: "The incident queue is showing \(visibleCount) of \(totalCount) pending approvals.")
    }

    private var detailLine: String {
        highRiskCount == 0
            ? String(localized: "The compact approval slice is currently dominated by standard-risk actions.")
            : String(localized: "\(highRiskCount) approvals are high risk or higher, so the compact slice stays biased toward faster response.")
    }
}

private struct IncidentAgentsInventoryDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let authIssueCount: Int
    let approvalCount: Int
    let staleCount: Int
    let watchedDiagnosticsCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: visibleCount == 1 ? String(localized: "1 agent visible") : String(localized: "\(visibleCount) agents visible"),
                        tone: totalCount > 0 ? .warning : .neutral
                    )
                    if authIssueCount > 0 {
                        PresentationToneBadge(
                            text: authIssueCount == 1 ? String(localized: "1 auth issue") : String(localized: "\(authIssueCount) auth issues"),
                            tone: .critical
                        )
                    }
                    if staleCount > 0 {
                        PresentationToneBadge(
                            text: staleCount == 1 ? String(localized: "1 stale agent") : String(localized: "\(staleCount) stale agents"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Agent inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep auth, approval, and stale-agent pressure visible before the fleet list grows beyond the compact incident slice."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: totalCount == 1 ? String(localized: "1 fleet issue") : String(localized: "\(totalCount) fleet issues"), tone: totalCount > 0 ? .warning : .neutral)
            } facts: {
                if approvalCount > 0 {
                    Label(
                        approvalCount == 1 ? String(localized: "1 agent with approvals") : String(localized: "\(approvalCount) agents with approvals"),
                        systemImage: "checkmark.shield"
                    )
                }
                if watchedDiagnosticsCount > 0 {
                    Label(
                        watchedDiagnosticsCount == 1 ? String(localized: "1 watched diagnostic") : String(localized: "\(watchedDiagnosticsCount) watched diagnostics"),
                        systemImage: "star.fill"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if visibleCount == totalCount {
            return totalCount == 1
                ? String(localized: "The incidents list is showing the only agent that needs attention.")
                : String(localized: "The incidents list is showing all \(totalCount) agents that need attention.")
        }
        return String(localized: "The incidents list is showing \(visibleCount) of \(totalCount) agents that need attention.")
    }

    private var detailLine: String {
        String(localized: "Watched diagnostics stay in their own bucket, so this slice focuses on the fleet-level attention list.")
    }
}

private struct IncidentWatchedDiagnosticsInventoryDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let failedAgentCount: Int
    let missingIdentityAgentCount: Int
    let fallbackAgentCount: Int
    let unsettledAgentCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: visibleCount == 1 ? String(localized: "1 watched agent visible") : String(localized: "\(visibleCount) watched agents visible"),
                        tone: totalCount > 0 ? .warning : .neutral
                    )
                    if failedAgentCount > 0 {
                        PresentationToneBadge(
                            text: failedAgentCount == 1 ? String(localized: "1 delivery failure") : String(localized: "\(failedAgentCount) delivery failures"),
                            tone: .critical
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Watched diagnostics inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Pinned agents can stay visible here even when they would otherwise drop out of the normal fleet attention list."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: totalCount == 1 ? String(localized: "1 watched issue") : String(localized: "\(totalCount) watched issues"), tone: totalCount > 0 ? .warning : .neutral)
            } facts: {
                if missingIdentityAgentCount > 0 {
                    Label(
                        missingIdentityAgentCount == 1 ? String(localized: "1 identity gap") : String(localized: "\(missingIdentityAgentCount) identity gaps"),
                        systemImage: "doc.badge.gearshape"
                    )
                }
                if fallbackAgentCount > 0 {
                    Label(
                        fallbackAgentCount == 1 ? String(localized: "1 fallback drift") : String(localized: "\(fallbackAgentCount) fallback drifts"),
                        systemImage: "square.stack.3d.up.slash"
                    )
                }
                if unsettledAgentCount > 0 {
                    Label(
                        unsettledAgentCount == 1 ? String(localized: "1 unsettled delivery") : String(localized: "\(unsettledAgentCount) unsettled deliveries"),
                        systemImage: "paperplane"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if visibleCount == totalCount {
            return totalCount == 1
                ? String(localized: "The incident queue is showing the only watched diagnostic issue.")
                : String(localized: "The incident queue is showing all \(totalCount) watched diagnostic issues.")
        }
        return String(localized: "The incident queue is showing \(visibleCount) of \(totalCount) watched diagnostic issues.")
    }

    private var detailLine: String {
        String(localized: "Delivery failures, identity gaps, and fallback drift stay grouped here before the watched-agent drilldowns.")
    }
}

private struct IncidentSessionsInventoryDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let unlabeledCount: Int
    let duplicateCount: Int
    let visibleMessageCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: visibleCount == 1 ? String(localized: "1 session visible") : String(localized: "\(visibleCount) sessions visible"),
                        tone: totalCount > 0 ? .warning : .neutral
                    )
                    if visibleMessageCount > 0 {
                        PresentationToneBadge(
                            text: String(localized: "\(visibleMessageCount) visible msgs"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Session inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep message load, unlabeled sessions, and duplicate-agent pressure readable before the dedicated session monitor opens."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: totalCount == 1 ? String(localized: "1 hotspot") : String(localized: "\(totalCount) hotspots"), tone: totalCount > 0 ? .warning : .neutral)
            } facts: {
                if unlabeledCount > 0 {
                    Label(
                        unlabeledCount == 1 ? String(localized: "1 unlabeled") : String(localized: "\(unlabeledCount) unlabeled"),
                        systemImage: "tag.slash"
                    )
                }
                if duplicateCount > 0 {
                    Label(
                        duplicateCount == 1 ? String(localized: "1 duplicate agent") : String(localized: "\(duplicateCount) duplicate agents"),
                        systemImage: "person.2"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if visibleCount == totalCount {
            return totalCount == 1
                ? String(localized: "The incidents list is showing the only session hotspot.")
                : String(localized: "The incidents list is showing all \(totalCount) session hotspots.")
        }
        return String(localized: "The incidents list is showing \(visibleCount) of \(totalCount) session hotspots.")
    }

    private var detailLine: String {
        String(localized: "The compact session slice stays focused on the hottest rows before you jump into the broader session monitor.")
    }
}

private struct IncidentEventsInventoryDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let agentCount: Int
    let actionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: visibleCount == 1 ? String(localized: "1 event visible") : String(localized: "\(visibleCount) events visible"),
                        tone: totalCount > 0 ? .critical : .neutral
                    )
                    if actionCount > 0 {
                        PresentationToneBadge(
                            text: actionCount == 1 ? String(localized: "1 action") : String(localized: "\(actionCount) actions"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Critical-event inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep action spread and agent breadth visible before opening the deeper event feed."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: totalCount == 1 ? String(localized: "1 critical event") : String(localized: "\(totalCount) critical events"), tone: totalCount > 0 ? .critical : .neutral)
            } facts: {
                if agentCount > 0 {
                    Label(
                        agentCount == 1 ? String(localized: "1 agent involved") : String(localized: "\(agentCount) agents involved"),
                        systemImage: "person.3"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if visibleCount == totalCount {
            return totalCount == 1
                ? String(localized: "The incidents list is showing the only critical event in view.")
                : String(localized: "The incidents list is showing all \(totalCount) critical events in view.")
        }
        return String(localized: "The incidents list is showing \(visibleCount) of \(totalCount) critical events in view.")
    }

    private var detailLine: String {
        String(localized: "The compact event slice stays focused on the newest critical trail before you open the full feed or diagnostics monitor.")
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

import SwiftUI

struct OnCallDigestCard: View {
    let queueCount: Int
    let criticalCount: Int
    let watchCount: Int
    let summary: String

    private var criticalStatus: MonitoringSummaryStatus {
        .countStatus(criticalCount, activeTone: .critical)
    }

    private var watchStatus: MonitoringSummaryStatus {
        .countStatus(watchCount, activeTone: .caution)
    }

    private var watchAccentColor: Color {
        PresentationTone.caution.color
    }

    var body: some View {
        MonitoringFactsRow(
            verticalSpacing: 12,
            headerVerticalSpacing: 6,
            factsFont: .caption2
        ) {
            summaryContent
        } accessory: {
            queueBadge
        } facts: {
            criticalLabel
            watchLabel
            openBadge
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("On Call", systemImage: "waveform.path.ecg")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    private var queueBadge: some View {
        PresentationToneBadge(
            text: queueCount == 1 ? String(localized: "1 queued") : String(localized: "\(queueCount) queued"),
            tone: criticalStatus.tone
        )
    }

    private var criticalLabel: some View {
        Label("\(criticalCount)", systemImage: "xmark.octagon")
            .foregroundStyle(criticalStatus.tone.color)
    }

    private var watchLabel: some View {
        Label("\(watchCount)", systemImage: "star.fill")
            .foregroundStyle(watchAccentColor)
    }

    private var openBadge: some View {
        GlassCapsuleBadge(
            text: String(localized: "Open"),
            foregroundStyle: .secondary,
            backgroundOpacity: 0.08
        )
    }
}

struct OnCallView: View {
    @Environment(\.dependencies) private var deps

    private var vm: DashboardViewModel { deps.dashboardViewModel }
    private var incidentStateStore: IncidentStateStore { deps.incidentStateStore }
    private var watchlistStore: AgentWatchlistStore { deps.agentWatchlistStore }

    private var visibleAlerts: [MonitoringAlertItem] {
        incidentStateStore.visibleAlerts(from: vm.monitoringAlerts)
    }

    private var mutedAlertCount: Int {
        incidentStateStore.activeMutedAlerts(from: vm.monitoringAlerts).count
    }

    private var watchedAgents: [Agent] {
        watchlistStore.watchedAgents(from: vm.agents)
    }
    private var watchedDiagnostics: [String: WatchedAgentDiagnosticsSummary] {
        deps.watchedAgentDiagnosticsStore.summaries
    }

    private var watchedAttentionItems: [AgentAttentionItem] {
        watchedAgentAttentionItemsSorted(
            watchedAgents.map { vm.attentionItem(for: $0) },
            summaries: watchedDiagnostics
        )
    }
    private var watchedDiagnosticPriorityItems: [OnCallPriorityItem] {
        watchedAgentDiagnosticPriorityItems(
            agents: watchedAgents,
            summaries: watchedDiagnostics
        )
    }
    private var watchedDiagnosticIssueAgentCount: Int {
        watchedAttentionItems.filter {
            watchedDiagnostics[$0.agent.id]?.hasIssues == true || $0.severity > 0
        }.count
    }
    private var watchedFailedDeliveryAgentCount: Int {
        watchedAttentionItems.filter { watchedDiagnostics[$0.agent.id]?.failedDeliveries ?? 0 > 0 }.count
    }
    private var watchedMissingIdentityAgentCount: Int {
        watchedAttentionItems.filter { !(watchedDiagnostics[$0.agent.id]?.missingIdentityFiles.isEmpty ?? true) }.count
    }
    private var watchedFallbackDriftAgentCount: Int {
        watchedAttentionItems.filter { !(watchedDiagnostics[$0.agent.id]?.unavailableFallbackModels.isEmpty ?? true) }.count
    }
    private var watchedPausedAgentCount: Int {
        watchedAttentionItems.filter { !$0.agent.isRunning }.count
    }
    private var criticalCount: Int {
        visibleAlerts.filter { $0.severity == .critical }.count
    }
    private var warningCount: Int {
        priorityItems.filter { $0.severity == .warning }.count
    }
    private var advisoryCount: Int {
        priorityItems.filter { $0.severity == .advisory }.count
    }
    private var watchIssueCount: Int {
        watchedAttentionItems.filter { $0.severity > 0 }.count
    }
    private var pendingFollowUpCount: Int {
        latestFollowUpStatuses.filter { !$0.isCompleted }.count
    }
    private var automationIssueCount: Int {
        vm.automationPressureIssueCategoryCount
    }
    private var integrationIssueCount: Int {
        vm.integrationPressureIssueCategoryCount
    }

    private var priorityItems: [OnCallPriorityItem] {
        mergeOnCallPriorityItems(
            vm.onCallPriorityItems(
                visibleAlerts: visibleAlerts,
                watchedAttentionItems: watchedAttentionItems,
                handoffCheckInStatus: handoffStore.latestCheckInStatus,
                handoffFollowUpStatuses: latestFollowUpStatuses
            ),
            with: watchedDiagnosticPriorityItems
        )
    }

    private var digestLine: String {
        let base = vm.onCallDigestLine(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            mutedAlertCount: mutedAlertCount,
            isAcknowledged: incidentStateStore.isCurrentSnapshotAcknowledged(alerts: vm.monitoringAlerts),
            handoffCheckInStatus: handoffStore.latestCheckInStatus,
            handoffFollowUpStatuses: latestFollowUpStatuses
        )
        if let diagnosticsSummary = watchedAgentDiagnosticDigestSummary(summaries: watchedDiagnostics) {
            return [base, diagnosticsSummary].joined(separator: " · ")
        }
        return base
    }
    private var handoffText: String {
        vm.onCallHandoffText(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            mutedAlertCount: mutedAlertCount,
            isAcknowledged: incidentStateStore.isCurrentSnapshotAcknowledged(alerts: vm.monitoringAlerts),
            handoffCheckInStatus: handoffStore.latestCheckInStatus,
            handoffFollowUpStatuses: latestFollowUpStatuses
        )
    }
    private var handoffStore: OnCallHandoffStore { deps.onCallHandoffStore }
    private var currentHandoffDrift: HandoffSnapshotDrift? {
        handoffStore.driftFromLatest(
            queueCount: priorityItems.count,
            criticalCount: visibleAlerts.filter { $0.severity == .critical }.count,
            liveAlertCount: visibleAlerts.count
        )
    }
    private var currentHandoffCarryover: HandoffCarryoverStatus? {
        handoffStore.carryoverFromLatest(
            liveAlertCount: visibleAlerts.count,
            pendingApprovalCount: vm.pendingApprovalCount,
            watchlistIssueCount: watchedAttentionItems.filter { $0.severity > 0 }.count,
            sessionAttentionCount: vm.sessionAttentionCount,
            criticalAuditCount: vm.recentCriticalAuditCount
        )
    }
    private var draftHandoffReadiness: HandoffReadinessStatus {
        handoffStore.evaluateDraftReadiness(
            note: handoffStore.draftNote,
            checklist: handoffStore.draftChecklist,
            focusAreas: handoffStore.draftFocusAreas,
            followUpItems: handoffStore.draftFollowUpItems,
            checkInWindow: handoffStore.draftCheckInWindow,
            liveAlertCount: visibleAlerts.count,
            pendingApprovalCount: vm.pendingApprovalCount,
            watchlistIssueCount: watchedAttentionItems.filter { $0.severity > 0 }.count,
            sessionAttentionCount: vm.sessionAttentionCount,
            criticalAuditCount: vm.recentCriticalAuditCount,
            carryover: currentHandoffCarryover
        )
    }
    private var latestFollowUpStatuses: [HandoffFollowUpStatus] {
        handoffStore.latestFollowUpStatuses
    }
    private var onCallSectionCount: Int {
        [
            true,
            !priorityItems.isEmpty,
            !watchedAttentionItems.isEmpty
        ]
        .filter { $0 }
        .count
    }

    var body: some View {
        List {
            Section {
                OnCallScoreboard(
                    criticalCount: criticalCount,
                    liveAlertCount: visibleAlerts.count,
                    approvalCount: vm.pendingApprovalCount,
                    watchIssueCount: watchIssueCount,
                    sessionCount: vm.sessionAttentionCount,
                    eventCount: vm.recentCriticalAuditCount
                )
                .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
            }

            Section {
                OnCallStatusDeckCard(
                    queueCount: priorityItems.count,
                    criticalCount: criticalCount,
                    approvalCount: vm.pendingApprovalCount,
                    watchIssueCount: watchIssueCount,
                    sessionCount: vm.sessionAttentionCount,
                    eventCount: vm.recentCriticalAuditCount,
                    mutedAlertCount: mutedAlertCount,
                    pendingFollowUpCount: pendingFollowUpCount,
                    automationIssueCount: automationIssueCount,
                    integrationIssueCount: integrationIssueCount,
                    checkInStatus: handoffStore.latestCheckInStatus,
                    readiness: draftHandoffReadiness,
                    isAcknowledged: incidentStateStore.isCurrentSnapshotAcknowledged(alerts: vm.monitoringAlerts)
                )

                OnCallShiftInventoryCard(
                    digestLine: digestLine,
                    liveAlertCount: visibleAlerts.count,
                    acknowledgedAt: incidentStateStore.currentAcknowledgementDate(for: vm.monitoringAlerts),
                    isAcknowledged: incidentStateStore.isCurrentSnapshotAcknowledged(alerts: vm.monitoringAlerts),
                    mutedAlertCount: mutedAlertCount,
                    watchCount: watchedAgents.count,
                    lastRefresh: vm.lastRefresh,
                    freshnessState: handoffStore.freshnessState,
                    freshnessSummary: handoffStore.freshnessSummary,
                    cadenceState: handoffStore.cadenceState,
                    cadenceSummary: handoffStore.cadenceSummary,
                    latestEntry: handoffStore.latestEntry,
                    checkInStatus: handoffStore.latestCheckInStatus,
                    drift: currentHandoffDrift,
                    carryover: currentHandoffCarryover,
                    readiness: draftHandoffReadiness,
                    followUpStatuses: latestFollowUpStatuses
                )

                OnCallSectionInventoryDeck(
                    sectionCount: onCallSectionCount,
                    queueCount: priorityItems.count,
                    watchItemCount: watchedAttentionItems.count,
                    mutedAlertCount: mutedAlertCount,
                    pendingFollowUpCount: pendingFollowUpCount,
                    approvalCount: vm.pendingApprovalCount,
                    eventCount: vm.recentCriticalAuditCount,
                    automationIssueCount: automationIssueCount,
                    integrationIssueCount: integrationIssueCount
                )

                OnCallQueueCoverageDeck(
                    criticalCount: criticalCount,
                    warningCount: warningCount,
                    advisoryCount: advisoryCount,
                    approvalCount: vm.pendingApprovalCount,
                    watchIssueCount: watchIssueCount,
                    pendingFollowUpCount: pendingFollowUpCount
                )
        } header: {
            Text("Controls")
        } footer: {
            Text("Queue shape, ack state, and handoff readiness stay together before queue work.")
        }

            if !priorityItems.isEmpty {
                Section {
                    OnCallPriorityInventoryDeck(
                        items: priorityItems,
                        visibleCount: min(priorityItems.count, 8)
                    )

                    ForEach(priorityItems.prefix(8)) { item in
                        NavigationLink(value: item.route) {
                            OnCallPriorityRow(item: item)
                        }
                    }
                } header: {
                    Text("Priority Queue")
                } footer: {
                    Text("Sorted for quick triage using live alerts, approvals, watched agents, critical events, and session hotspots.")
                }
            }

            Section {
                OnCallRouteInventoryDeck(
                    queueCount: priorityItems.count,
                    liveAlertCount: visibleAlerts.count,
                    criticalCount: criticalCount,
                    approvalCount: vm.pendingApprovalCount,
                    sessionCount: vm.sessionAttentionCount,
                    eventCount: vm.recentCriticalAuditCount,
                    automationIssueCount: automationIssueCount,
                    integrationIssueCount: integrationIssueCount
                )

                OnCallSurfaceDeckCard(
                    approvalCount: vm.pendingApprovalCount,
                    sessionCount: vm.sessionAttentionCount,
                    eventCount: vm.recentCriticalAuditCount,
                    criticalCount: criticalCount,
                    queueCount: priorityItems.count,
                    liveAlertCount: visibleAlerts.count,
                    automationIssueCount: automationIssueCount,
                    integrationIssueCount: integrationIssueCount,
                    handoffText: handoffText
                )
            } header: {
                Text("Routes")
            } footer: {
                Text("Primary exits and slower systemic drilldowns stay below the live queue.")
            }

            if !watchedAttentionItems.isEmpty {
                Section {
                    OnCallWatchlistInventoryDeck(
                        watchedCount: watchedAttentionItems.count,
                        visibleCount: min(watchedAttentionItems.count, 6),
                        issueCount: watchedDiagnosticIssueAgentCount,
                        failedDeliveryCount: watchedFailedDeliveryAgentCount,
                        missingIdentityCount: watchedMissingIdentityAgentCount,
                        fallbackDriftCount: watchedFallbackDriftAgentCount,
                        pausedCount: watchedPausedAgentCount
                    )

                    ForEach(watchedAttentionItems.prefix(6)) { item in
                        NavigationLink {
                            watchedDiagnosticsDestination(for: item)
                        } label: {
                            WatchedAgentRow(
                                agent: item.agent,
                                reasons: item.reasons,
                                severity: item.severity,
                                isHealthy: item.severity == 0,
                                diagnostics: watchedDiagnostics[item.agent.id]
                            )
                        }
                    }
                } header: {
                    Text("Watchlist")
                } footer: {
                    Text("Pinned locally on this iPhone. Edit from the agent list or agent detail page.")
                }
            }

            if priorityItems.isEmpty
                && watchedAgents.isEmpty
                && vm.pendingApprovalCount == 0
                && vm.recentCriticalAuditCount == 0 {
                Section("On Call") {
                    ContentUnavailableView(
                        "Calm State",
                        systemImage: "checkmark.shield",
                        description: Text("No live priorities are currently surfacing on this device.")
                    )
                }
            }
        }
        .navigationTitle("On Call")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: handoffText) {
                    Image(systemName: "square.and.arrow.up")
                }

                Menu {
                    NavigationLink(value: OnCallRoute.incidents) {
                        Label("Incidents", systemImage: "bell.badge")
                    }

                    NavigationLink {
                        NightWatchView()
                    } label: {
                        Label("Night Watch", systemImage: "moon.stars")
                    }

                    NavigationLink {
                        StandbyDigestView()
                    } label: {
                        Label("Standby", systemImage: "rectangle.inset.filled")
                    }

                    NavigationLink {
                        HandoffCenterView(
                            summary: handoffText,
                            queueCount: priorityItems.count,
                            criticalCount: criticalCount,
                            liveAlertCount: visibleAlerts.count
                        )
                    } label: {
                        Label("Handoff", systemImage: "text.badge.plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .navigationDestination(for: OnCallRoute.self) { route in
            destination(for: route)
        }
        .refreshable {
            await refreshAndSync()
        }
        .overlay {
            if vm.isLoading && vm.lastRefresh == nil {
                ProgressView("Loading on-call view...")
            }
        }
        .task {
            if vm.lastRefresh == nil {
                await refreshAndSync()
            } else {
                syncWatchlist()
            }
        }
    }

    @ViewBuilder
    private func destination(for route: OnCallRoute) -> some View {
        switch route {
        case .incidents:
            IncidentsView()
        case .approvals:
            ApprovalsView()
        case .agent(let id):
            if let agent = vm.agents.first(where: { $0.id == id }) {
                AgentDetailView(agent: agent)
            } else {
                ContentUnavailableView(
                    "Agent Unavailable",
                    systemImage: "cpu",
                    description: Text("The watched agent is no longer available in the current snapshot.")
                )
            }
        case .sessionsAttention:
            SessionsView(initialFilter: .attention)
        case .sessionsSearch(let query):
            SessionsView(initialSearchText: query, initialFilter: .attention)
        case .eventsCritical:
            EventsView(api: deps.apiClient, initialScope: .critical)
        case .eventsSearch(let query):
            EventsView(api: deps.apiClient, initialSearchText: query, initialScope: .critical)
        case .automation:
            AutomationView()
        case .integrations:
            IntegrationsView()
        case .integrationsAttention:
            IntegrationsView(initialScope: .attention)
        case .integrationsSearch(let query):
            IntegrationsView(initialSearchText: query, initialScope: .attention)
        case .handoffCenter:
            HandoffCenterView(
                summary: handoffText,
                queueCount: priorityItems.count,
                criticalCount: criticalCount,
                liveAlertCount: visibleAlerts.count
            )
        }
    }

    @ViewBuilder
    private func watchedDiagnosticsDestination(for item: AgentAttentionItem) -> some View {
        if let summary = watchedDiagnostics[item.agent.id], summary.failedDeliveries > 0 {
            AgentDeliveriesView(agent: item.agent, initialScope: .failed)
        } else if let summary = watchedDiagnostics[item.agent.id], !summary.missingIdentityFiles.isEmpty {
            AgentFilesView(agent: item.agent, initialScope: .missing)
        } else {
            AgentDetailView(agent: item.agent)
        }
    }

    @MainActor
    private func refreshAndSync() async {
        await vm.refresh()
        syncWatchlist()
    }

    private func syncWatchlist() {
        watchlistStore.removeMissingAgents(validIDs: Set(vm.agents.map(\.id)))
    }
}

private struct OnCallShiftInventoryCard: View {
    let digestLine: String
    let liveAlertCount: Int
    let acknowledgedAt: Date?
    let isAcknowledged: Bool
    let mutedAlertCount: Int
    let watchCount: Int
    let lastRefresh: Date?
    let freshnessState: HandoffFreshnessState
    let freshnessSummary: String
    let cadenceState: HandoffCadenceState
    let cadenceSummary: String
    let latestEntry: OnCallHandoffEntry?
    let checkInStatus: HandoffCheckInStatus?
    let drift: HandoffSnapshotDrift?
    let carryover: HandoffCarryoverStatus?
    let readiness: HandoffReadinessStatus
    let followUpStatuses: [HandoffFollowUpStatus]

    private var snapshotTone: PresentationTone {
        if isAcknowledged {
            return .positive
        }
        return liveAlertCount > 0 ? .critical : .neutral
    }

    private var pendingFollowUpCount: Int {
        followUpStatuses.filter { !$0.isCompleted }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Operator snapshot and latest handoff context now stay in one compact deck."),
                detail: String(localized: "Live queue state, acknowledgement, freshness, cadence, and follow-up pressure stay together before the route deck."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: isAcknowledged ? String(localized: "Acked") : String(localized: "Live"),
                        tone: snapshotTone
                    )
                    PresentationToneBadge(text: freshnessState.label, tone: freshnessState.tone)
                    PresentationToneBadge(text: cadenceState.label, tone: cadenceState.tone)
                    PresentationToneBadge(text: readiness.state.label, tone: readiness.state.tone)
                    if let checkInStatus {
                        PresentationToneBadge(text: checkInStatus.state.label, tone: checkInStatus.state.tone)
                    }
                }
            }

            OnCallStatusCard(
                digestLine: digestLine,
                liveAlertCount: liveAlertCount,
                acknowledgedAt: acknowledgedAt,
                isAcknowledged: isAcknowledged,
                mutedAlertCount: mutedAlertCount,
                watchCount: watchCount,
                lastRefresh: lastRefresh
            )

            OnCallHandoffStatusRow(
                freshnessState: freshnessState,
                freshnessSummary: freshnessSummary,
                cadenceState: cadenceState,
                cadenceSummary: cadenceSummary,
                latestEntry: latestEntry,
                checkInStatus: checkInStatus,
                drift: drift,
                carryover: carryover,
                readiness: readiness,
                followUpStatuses: followUpStatuses
            )

            if pendingFollowUpCount > 0 {
                Text(
                    pendingFollowUpCount == 1
                        ? String(localized: "1 handoff follow-up is still open in the current deck.")
                        : String(localized: "\(pendingFollowUpCount) handoff follow-ups are still open in the current deck.")
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct OnCallStatusDeckCard: View {
    let queueCount: Int
    let criticalCount: Int
    let approvalCount: Int
    let watchIssueCount: Int
    let sessionCount: Int
    let eventCount: Int
    let mutedAlertCount: Int
    let pendingFollowUpCount: Int
    let automationIssueCount: Int
    let integrationIssueCount: Int
    let checkInStatus: HandoffCheckInStatus?
    let readiness: HandoffReadinessStatus
    let isAcknowledged: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnCallQueueSnapshotCard(
                queueCount: queueCount,
                criticalCount: criticalCount,
                approvalCount: approvalCount,
                watchIssueCount: watchIssueCount,
                sessionCount: sessionCount,
                eventCount: eventCount,
                mutedAlertCount: mutedAlertCount,
                pendingFollowUpCount: pendingFollowUpCount,
                automationIssueCount: automationIssueCount,
                integrationIssueCount: integrationIssueCount,
                checkInStatus: checkInStatus,
                readiness: readiness
            )

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "On-call signal facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep queue shape, acknowledgement state, and cross-surface pressure visible before working deeper on-call sections."))
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
                    queueCount == 1 ? String(localized: "1 queued item") : String(localized: "\(queueCount) queued items"),
                    systemImage: "waveform.path.ecg"
                )
                Label(
                    criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                    systemImage: "xmark.octagon"
                )
                if approvalCount > 0 {
                    Label(
                        approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                        systemImage: "checkmark.shield"
                    )
                }
                if watchIssueCount > 0 {
                    Label(
                        watchIssueCount == 1 ? String(localized: "1 watch issue") : String(localized: "\(watchIssueCount) watch issues"),
                        systemImage: "star.fill"
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
                if pendingFollowUpCount > 0 {
                    Label(
                        pendingFollowUpCount == 1 ? String(localized: "1 follow-up open") : String(localized: "\(pendingFollowUpCount) follow-ups open"),
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                if automationIssueCount > 0 {
                    Label(
                        automationIssueCount == 1 ? String(localized: "1 automation issue") : String(localized: "\(automationIssueCount) automation issues"),
                        systemImage: "flowchart"
                    )
                }
                if integrationIssueCount > 0 {
                    Label(
                        integrationIssueCount == 1 ? String(localized: "1 integration issue") : String(localized: "\(integrationIssueCount) integration issues"),
                        systemImage: "square.3.layers.3d.down.forward"
                    )
                }
            }
        }
    }
}

private struct OnCallRouteInventoryDeck: View {
    let queueCount: Int
    let liveAlertCount: Int
    let criticalCount: Int
    let approvalCount: Int
    let sessionCount: Int
    let eventCount: Int
    let automationIssueCount: Int
    let integrationIssueCount: Int

    private let primaryRouteCount = 6
    private let supportRouteCount = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: String(localized: "The route deck keeps \(primaryRouteCount) primary exits and \(supportRouteCount) support drills grouped above the fold."),
                detail: String(localized: "Queue-first routes stay ahead of slower systemic drilldowns and export actions."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: queueCount == 1 ? String(localized: "1 queued route context") : String(localized: "\(queueCount) queued route context"),
                        tone: queueCount > 0 ? .warning : .neutral
                    )
                    if criticalCount > 0 {
                        PresentationToneBadge(
                            text: criticalCount == 1 ? String(localized: "1 critical route") : String(localized: "\(criticalCount) critical routes"),
                            tone: .critical
                        )
                    }
                    if liveAlertCount > 0 {
                        PresentationToneBadge(
                            text: liveAlertCount == 1 ? String(localized: "1 live alert route") : String(localized: "\(liveAlertCount) live alert routes"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Route inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Use the compact surface inventory to judge whether the next move should stay queue-first or jump into slower runtime and platform drills."))
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
                Label(
                    primaryRouteCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryRouteCount) primary routes"),
                    systemImage: "arrowshape.turn.up.right"
                )
                Label(
                    supportRouteCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportRouteCount) support routes"),
                    systemImage: "square.grid.2x2"
                )
                if approvalCount > 0 {
                    Label(
                        approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                        systemImage: "checkmark.shield"
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
                if automationIssueCount > 0 {
                    Label(
                        automationIssueCount == 1 ? String(localized: "1 automation issue") : String(localized: "\(automationIssueCount) automation issues"),
                        systemImage: "flowchart"
                    )
                }
                if integrationIssueCount > 0 {
                    Label(
                        integrationIssueCount == 1 ? String(localized: "1 integration issue") : String(localized: "\(integrationIssueCount) integration issues"),
                        systemImage: "square.3.layers.3d.down.forward"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct OnCallSectionInventoryDeck: View {
    let sectionCount: Int
    let queueCount: Int
    let watchItemCount: Int
    let mutedAlertCount: Int
    let pendingFollowUpCount: Int
    let approvalCount: Int
    let eventCount: Int
    let automationIssueCount: Int
    let integrationIssueCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: sectionCount == 1 ? String(localized: "1 live section") : String(localized: "\(sectionCount) live sections"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: queueCount == 1 ? String(localized: "1 queued item") : String(localized: "\(queueCount) queued items"),
                        tone: queueCount > 0 ? .warning : .neutral
                    )
                    if watchItemCount > 0 {
                        PresentationToneBadge(
                            text: watchItemCount == 1 ? String(localized: "1 watch item") : String(localized: "\(watchItemCount) watch items"),
                            tone: .caution
                        )
                    }
                    if pendingFollowUpCount > 0 {
                        PresentationToneBadge(
                            text: pendingFollowUpCount == 1 ? String(localized: "1 follow-up") : String(localized: "\(pendingFollowUpCount) follow-ups"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Section inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep queue coverage, watch pressure, and supporting issue buckets visible before the route deck and live rows begin."))
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
                    mutedAlertCount == 1 ? String(localized: "1 muted alert") : String(localized: "\(mutedAlertCount) muted alerts"),
                    systemImage: "bell.slash"
                )
                Label(
                    eventCount == 1 ? String(localized: "1 critical event") : String(localized: "\(eventCount) critical events"),
                    systemImage: "list.bullet.rectangle.portrait"
                )
                if automationIssueCount > 0 {
                    Label(
                        automationIssueCount == 1 ? String(localized: "1 automation issue") : String(localized: "\(automationIssueCount) automation issues"),
                        systemImage: "flowchart"
                    )
                }
                if integrationIssueCount > 0 {
                    Label(
                        integrationIssueCount == 1 ? String(localized: "1 integration issue") : String(localized: "\(integrationIssueCount) integration issues"),
                        systemImage: "square.3.layers.3d.down.forward"
                    )
                }
            }
        }
    }

    private var summaryLine: String {
        sectionCount == 1
            ? String(localized: "1 on-call section is active below the controls deck.")
            : String(localized: "\(sectionCount) on-call sections are active below the controls deck.")
    }

    private var detailLine: String {
        String(localized: "Queue work, watchlist pressure, and supporting issue buckets stay summarized before the route deck and live rows take over.")
    }
}

private struct OnCallQueueCoverageDeck: View {
    let criticalCount: Int
    let warningCount: Int
    let advisoryCount: Int
    let approvalCount: Int
    let watchIssueCount: Int
    let pendingFollowUpCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: String(localized: "Queue coverage keeps severity mix readable before the live on-call rows begin."),
                detail: String(localized: "Use this deck to gauge whether the queue is dominated by criticals, warnings, watch pressure, or handoff follow-ups."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if criticalCount > 0 {
                        PresentationToneBadge(
                            text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                            tone: .critical
                        )
                    }
                    if warningCount > 0 {
                        PresentationToneBadge(
                            text: warningCount == 1 ? String(localized: "1 warning") : String(localized: "\(warningCount) warnings"),
                            tone: .warning
                        )
                    }
                    if advisoryCount > 0 {
                        PresentationToneBadge(
                            text: advisoryCount == 1 ? String(localized: "1 advisory") : String(localized: "\(advisoryCount) advisories"),
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Queue coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep approvals, watch pressure, and follow-up drag visible before opening the full priority queue."))
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
                    watchIssueCount == 1 ? String(localized: "1 watch issue") : String(localized: "\(watchIssueCount) watch issues"),
                    systemImage: "star.fill"
                )
                Label(
                    pendingFollowUpCount == 1 ? String(localized: "1 follow-up") : String(localized: "\(pendingFollowUpCount) follow-ups"),
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
        }
    }
}

private struct OnCallQueueSnapshotCard: View {
    let queueCount: Int
    let criticalCount: Int
    let approvalCount: Int
    let watchIssueCount: Int
    let sessionCount: Int
    let eventCount: Int
    let mutedAlertCount: Int
    let pendingFollowUpCount: Int
    let automationIssueCount: Int
    let integrationIssueCount: Int
    let checkInStatus: HandoffCheckInStatus?
    let readiness: HandoffReadinessStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResponsiveAccessoryRow(verticalSpacing: 8) {
                headerLabel
            } accessory: {
                PresentationToneBadge(text: readiness.state.label, tone: readiness.state.tone)
            }

            Text(readiness.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 8) {
                PresentationToneBadge(
                    text: queueCount == 1 ? String(localized: "1 queued item") : String(localized: "\(queueCount) queued items"),
                    tone: queueCount > 0 ? .warning : .neutral
                )
                PresentationToneBadge(
                    text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                    tone: criticalCount > 0 ? .critical : .neutral
                )
                if approvalCount > 0 {
                    PresentationToneBadge(
                        text: approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                        tone: .critical
                    )
                }
                if watchIssueCount > 0 {
                    PresentationToneBadge(
                        text: watchIssueCount == 1 ? String(localized: "1 watch issue") : String(localized: "\(watchIssueCount) watch issues"),
                        tone: .caution
                    )
                }
                if sessionCount > 0 {
                    PresentationToneBadge(
                        text: sessionCount == 1 ? String(localized: "1 session hotspot") : String(localized: "\(sessionCount) session hotspots"),
                        tone: .warning
                    )
                }
                if eventCount > 0 {
                    PresentationToneBadge(
                        text: eventCount == 1 ? String(localized: "1 critical event") : String(localized: "\(eventCount) critical events"),
                        tone: .critical
                    )
                }
                if mutedAlertCount > 0 {
                    PresentationToneBadge(
                        text: mutedAlertCount == 1 ? String(localized: "1 muted alert") : String(localized: "\(mutedAlertCount) muted alerts"),
                        tone: .neutral
                    )
                }
                if pendingFollowUpCount > 0 {
                    PresentationToneBadge(
                        text: pendingFollowUpCount == 1 ? String(localized: "1 follow-up open") : String(localized: "\(pendingFollowUpCount) follow-ups open"),
                        tone: .warning
                    )
                }
                if automationIssueCount > 0 {
                    PresentationToneBadge(
                        text: automationIssueCount == 1 ? String(localized: "1 automation issue") : String(localized: "\(automationIssueCount) automation issues"),
                        tone: .warning
                    )
                }
                if integrationIssueCount > 0 {
                    PresentationToneBadge(
                        text: integrationIssueCount == 1 ? String(localized: "1 integration issue") : String(localized: "\(integrationIssueCount) integration issues"),
                        tone: .critical
                    )
                }
                if let checkInStatus {
                    PresentationToneBadge(text: checkInStatus.state.label, tone: checkInStatus.state.tone)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var headerLabel: some View {
        Label("Queue Snapshot", systemImage: "square.stack.3d.up")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct OnCallSurfaceDeckCard: View {
    let approvalCount: Int
    let sessionCount: Int
    let eventCount: Int
    let criticalCount: Int
    let queueCount: Int
    let liveAlertCount: Int
    let automationIssueCount: Int
    let integrationIssueCount: Int
    let handoffText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringFactsRow(
                verticalSpacing: 10,
                headerVerticalSpacing: 6,
                factsFont: .caption2
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Keep queue-first routes, slower systemic drilldowns, and export actions in one compact surface deck above the fold."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } accessory: {
                PresentationToneBadge(
                    text: queueCount == 1 ? String(localized: "1 queued") : String(localized: "\(queueCount) queued"),
                    tone: queueCount > 0 ? .warning : .neutral
                )
            } facts: {
                if criticalCount > 0 {
                    Label(
                        criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                        systemImage: "xmark.octagon"
                    )
                }
                if liveAlertCount > 0 {
                    Label(
                        liveAlertCount == 1 ? String(localized: "1 live alert") : String(localized: "\(liveAlertCount) live alerts"),
                        systemImage: "bell.badge"
                    )
                }
                if approvalCount > 0 {
                    Label(
                        approvalCount == 1 ? String(localized: "1 approval waiting") : String(localized: "\(approvalCount) approvals waiting"),
                        systemImage: "checkmark.shield"
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
                if automationIssueCount > 0 {
                    Label(
                        automationIssueCount == 1 ? String(localized: "1 automation issue") : String(localized: "\(automationIssueCount) automation issues"),
                        systemImage: "flowchart"
                    )
                }
                if integrationIssueCount > 0 {
                    Label(
                        integrationIssueCount == 1 ? String(localized: "1 integration issue") : String(localized: "\(integrationIssueCount) integration issues"),
                        systemImage: "square.3.layers.3d.down.forward"
                    )
                }
            }

            Label("Primary", systemImage: "arrowshape.turn.up.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                NavigationLink(value: OnCallRoute.incidents) {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Incidents"),
                        systemImage: "bell.badge",
                        tone: criticalCount > 0 ? .critical : .neutral,
                        badgeText: criticalCount > 0
                            ? (criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"))
                            : (liveAlertCount > 0 ? String(localized: "\(liveAlertCount) alerts") : nil)
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    RuntimeView()
                } label: {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Runtime"),
                        systemImage: "server.rack",
                        tone: approvalCount > 0 || sessionCount > 0 ? .warning : .neutral
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ApprovalsView()
                } label: {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Approvals"),
                        systemImage: "checkmark.shield",
                        tone: approvalCount > 0 ? .critical : .neutral,
                        badgeText: approvalCount > 0
                            ? (approvalCount == 1 ? String(localized: "1 waiting") : String(localized: "\(approvalCount) waiting"))
                            : nil
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: OnCallRoute.sessionsAttention) {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Sessions"),
                        systemImage: "rectangle.stack",
                        tone: sessionCount > 0 ? .warning : .neutral,
                        badgeText: sessionCount > 0
                            ? (sessionCount == 1 ? String(localized: "1 hotspot") : String(localized: "\(sessionCount) hotspots"))
                            : nil
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: OnCallRoute.eventsCritical) {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Critical Events"),
                        systemImage: "list.bullet.rectangle.portrait",
                        tone: eventCount > 0 ? .critical : .neutral,
                        badgeText: eventCount > 0
                            ? (eventCount == 1 ? String(localized: "1 event") : String(localized: "\(eventCount) events"))
                            : nil
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    HandoffCenterView(
                        summary: handoffText,
                        queueCount: queueCount,
                        criticalCount: criticalCount,
                        liveAlertCount: liveAlertCount
                    )
                } label: {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Handoff"),
                        systemImage: "text.badge.plus",
                        tone: queueCount > 0 ? .warning : .neutral,
                        badgeText: queueCount > 0
                            ? (queueCount == 1 ? String(localized: "1 queued") : String(localized: "\(queueCount) queued"))
                            : nil
                    )
                }
                .buttonStyle(.plain)
            }

            Label("Support", systemImage: "square.grid.2x2")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Diagnostics"),
                        systemImage: "stethoscope"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    IntegrationsView(initialScope: .attention)
                } label: {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Integrations"),
                        systemImage: "square.3.layers.3d.down.forward",
                        tone: integrationIssueCount > 0 ? .critical : .neutral,
                        badgeText: integrationIssueCount > 0
                            ? (integrationIssueCount == 1 ? String(localized: "1 issue") : String(localized: "\(integrationIssueCount) issues"))
                            : nil
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    AutomationView(initialScope: .attention)
                } label: {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Automation"),
                        systemImage: "flowchart",
                        tone: automationIssueCount > 0 ? .warning : .neutral,
                        badgeText: automationIssueCount > 0
                            ? (automationIssueCount == 1 ? String(localized: "1 issue") : String(localized: "\(automationIssueCount) issues"))
                            : nil
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    NightWatchView()
                } label: {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Night Watch"),
                        systemImage: "moon.stars"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    StandbyDigestView()
                } label: {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Standby"),
                        systemImage: "rectangle.inset.filled"
                    )
                }
                .buttonStyle(.plain)

                ShareLink(item: handoffText) {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Share Handoff"),
                        systemImage: "square.and.arrow.up"
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct OnCallJumpRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        ResponsiveIconDetailRow(horizontalAlignment: .top, verticalSpacing: 10) {
            iconBadge
        } detail: {
            contentBlock
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private var iconBadge: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 34, height: 34)
            .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var contentBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnCallHandoffStatusRow: View {
    let freshnessState: HandoffFreshnessState
    let freshnessSummary: String
    let cadenceState: HandoffCadenceState
    let cadenceSummary: String
    let latestEntry: OnCallHandoffEntry?
    let checkInStatus: HandoffCheckInStatus?
    let drift: HandoffSnapshotDrift?
    let carryover: HandoffCarryoverStatus?
    let readiness: HandoffReadinessStatus
    let followUpStatuses: [HandoffFollowUpStatus]

    private var pendingFollowUpCount: Int {
        followUpStatuses.filter { !$0.isCompleted }.count
    }

    private var completedFollowUpCount: Int {
        followUpStatuses.filter(\.isCompleted).count
    }

    private var followUpSummary: HandoffFollowUpSummary? {
        guard !followUpStatuses.isEmpty else { return nil }
        return HandoffFollowUpSummary.summarize(statuses: followUpStatuses)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringFactsRow(
                verticalSpacing: 10,
                headerVerticalSpacing: 6,
                factsFont: .caption2
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Latest Handoff"))
                        .font(.subheadline.weight(.semibold))
                    Text(freshnessSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } accessory: {
                PresentationToneBadge(text: freshnessState.label, tone: freshnessState.tone)
            } facts: {
                Label(cadenceState.label, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                Label(readiness.state.label, systemImage: "checkmark.seal")
                if let drift {
                    Label(drift.state.label, systemImage: "arrow.left.arrow.right")
                }
                if let carryover {
                    Label(carryover.state.label, systemImage: "arrow.triangle.branch")
                }
                if let checkInStatus {
                    Label(checkInStatus.state.label, systemImage: "timer")
                }
                if let followUpSummary {
                    Label(followUpSummary.badgeLabel, systemImage: "checklist")
                }
            }

            Text(readiness.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let drift {
                Text(drift.compactSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let carryover {
                Text(carryover.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let checkInStatus {
                Text([checkInStatus.dueLabel, checkInStatus.summary].joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let latestEntry {
                VStack(alignment: .leading, spacing: 8) {
                    ResponsiveAccessoryRow(horizontalAlignment: .top, verticalSpacing: 6) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Latest Snapshot"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(String(localized: "Checklist \(latestEntry.checklist.progressLabel) · \(latestEntry.createdAt.formatted(date: .omitted, time: .shortened))"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } accessory: {
                        HandoffKindBadge(kind: latestEntry.kind)
                    }

                    if !latestEntry.focusAreas.items.isEmpty {
                        HandoffFocusSummaryRow(focusAreas: latestEntry.focusAreas)
                    }

                    if latestEntry.checkInWindow != .none {
                        HandoffCheckInSummaryRow(window: latestEntry.checkInWindow, createdAt: latestEntry.createdAt)
                    }

                    if !latestEntry.followUpItems.isEmpty {
                        HandoffFollowUpSummaryRow(items: latestEntry.followUpItems)
                    }

                    if followUpSummary != nil {
                        Text(String(localized: "\(completedFollowUpCount) complete · \(pendingFollowUpCount) pending"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

private struct OnCallScoreboard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let criticalCount: Int
    let liveAlertCount: Int
    let approvalCount: Int
    let watchIssueCount: Int
    let sessionCount: Int
    let eventCount: Int

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    private var criticalStatus: MonitoringSummaryStatus {
        .countStatus(criticalCount, activeTone: .critical)
    }

    private var liveAlertStatus: MonitoringSummaryStatus {
        .countStatus(liveAlertCount, activeTone: .warning)
    }

    private var approvalStatus: MonitoringSummaryStatus {
        .countStatus(approvalCount, activeTone: .critical)
    }

    private var watchIssueStatus: MonitoringSummaryStatus {
        .countStatus(watchIssueCount, activeTone: .caution)
    }

    private var sessionStatus: MonitoringSummaryStatus {
        .countStatus(sessionCount, activeTone: .warning)
    }

    private var eventStatus: MonitoringSummaryStatus {
        .countStatus(eventCount, activeTone: .critical)
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
                value: "\(liveAlertCount)",
                label: "Live Alerts",
                icon: "bell.badge",
                color: liveAlertStatus.tone.color
            )
            StatBadge(
                value: "\(approvalCount)",
                label: "Approvals",
                icon: "exclamationmark.shield",
                color: approvalStatus.tone.color
            )
            StatBadge(
                value: "\(watchIssueCount)",
                label: "Watchlist",
                icon: "star.fill",
                color: watchIssueStatus.tone.color
            )
            StatBadge(
                value: "\(sessionCount)",
                label: "Sessions",
                icon: "rectangle.stack",
                color: sessionStatus.tone.color
            )
            StatBadge(
                value: "\(eventCount)",
                label: "Events",
                icon: "list.bullet.rectangle.portrait",
                color: eventStatus.tone.color
            )
        }
        .padding(.horizontal, 6)
    }
}

private struct OnCallStatusCard: View {
    let digestLine: String
    let liveAlertCount: Int
    let acknowledgedAt: Date?
    let isAcknowledged: Bool
    let mutedAlertCount: Int
    let watchCount: Int
    let lastRefresh: Date?

    private var snapshotState: AlertSnapshotState {
        AlertSnapshotState(
            liveAlertCount: liveAlertCount,
            mutedAlertCount: mutedAlertCount,
            isAcknowledged: isAcknowledged
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonitoringFactsRow(
                verticalSpacing: 10,
                headerVerticalSpacing: 6,
                factsFont: .caption2
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Operator Snapshot"))
                        .font(.subheadline.weight(.semibold))
                    Text(digestLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } accessory: {
                PresentationToneBadge(text: snapshotState.onCallLabel, tone: snapshotState.tone)
            } facts: {
                Label(
                    liveAlertCount == 1 ? String(localized: "1 live alert") : String(localized: "\(liveAlertCount) live alerts"),
                    systemImage: "bell.badge"
                )
                Label(
                    watchCount == 1 ? String(localized: "1 watched agent") : String(localized: "\(watchCount) watched agents"),
                    systemImage: "star.fill"
                )
                Label(
                    mutedAlertCount == 1 ? String(localized: "1 muted alert") : String(localized: "\(mutedAlertCount) muted alerts"),
                    systemImage: "bell.slash"
                )
            }

            ResponsiveInlineGroup(horizontalSpacing: 10, verticalSpacing: 4) {
                if let acknowledgedAt, isAcknowledged {
                    Text("Acknowledged \(acknowledgedAt, style: .relative) ago")
                }

                if let lastRefresh {
                    Text("Last refreshed \(lastRefresh, style: .relative)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct OnCallPriorityInventoryDeck: View {
    let items: [OnCallPriorityItem]
    let visibleCount: Int

    private var criticalCount: Int {
        items.filter { $0.severity == .critical }.count
    }

    private var warningCount: Int {
        items.filter { $0.severity == .warning }.count
    }

    private var advisoryCount: Int {
        items.filter { $0.severity == .advisory }.count
    }

    private var routeGroupCount: Int {
        Set(items.map(routeGroupLabel(for:))).count
    }

    private var agentRouteCount: Int {
        items.filter {
            if case .agent = $0.route { return true }
            return false
        }.count
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
                    if advisoryCount > 0 {
                        PresentationToneBadge(
                            text: advisoryCount == 1 ? String(localized: "1 advisory visible") : String(localized: "\(advisoryCount) advisories visible"),
                            tone: .caution
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Queue inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Use the compact queue slice to judge severity mix and destination spread before opening each on-call row."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == items.count
                        ? String(localized: "Full queue")
                        : String(localized: "\(visibleCount)/\(items.count) visible"),
                    tone: visibleCount == items.count ? .positive : .neutral
                )
            } facts: {
                Label(
                    items.count == 1 ? String(localized: "1 queued item") : String(localized: "\(items.count) queued items"),
                    systemImage: "waveform.path.ecg"
                )
                Label(
                    routeGroupCount == 1 ? String(localized: "1 route group") : String(localized: "\(routeGroupCount) route groups"),
                    systemImage: "arrowshape.turn.up.right"
                )
                if agentRouteCount > 0 {
                    Label(
                        agentRouteCount == 1 ? String(localized: "1 agent route") : String(localized: "\(agentRouteCount) agent routes"),
                        systemImage: "person.crop.circle"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if visibleCount == items.count {
            return items.count == 1
                ? String(localized: "The on-call queue is showing the only active priority.")
                : String(localized: "The on-call queue is showing all \(items.count) active priorities.")
        }
        return String(localized: "The on-call queue is showing \(visibleCount) of \(items.count) active priorities.")
    }

    private var detailLine: String {
        String(localized: "Critical, warning, and advisory pressure stay summarized here before the ranked queue rows.")
    }

    private func routeGroupLabel(for item: OnCallPriorityItem) -> String {
        switch item.route {
        case .incidents: return "incidents"
        case .approvals: return "approvals"
        case .agent: return "agent"
        case .sessionsAttention, .sessionsSearch: return "sessions"
        case .eventsCritical, .eventsSearch: return "events"
        case .automation: return "automation"
        case .integrations, .integrationsAttention, .integrationsSearch: return "integrations"
        case .handoffCenter: return "handoff"
        }
    }
}

private struct OnCallPriorityRow: View {
    let item: OnCallPriorityItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: item.symbolName)
                    .foregroundStyle(item.severity.tone.color)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(item.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        PresentationToneBadge(
                            text: item.severity.label,
                            tone: item.severity.tone,
                            horizontalPadding: 6,
                            verticalPadding: 2
                        )
                    }

                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text(item.footnote)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct WatchedAgentRow: View {
    let agent: Agent
    let reasons: [String]
    let severity: Int
    let isHealthy: Bool
    let diagnostics: WatchedAgentDiagnosticsSummary?

    private var watchAccentColor: Color {
        PresentationTone.caution.color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(agent.identity?.emoji ?? "🤖")
                    .font(.body)
                Text(agent.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(watchAccentColor)
                if let diagnostics, diagnostics.hasIssues {
                    let issueBadge = watchedAgentDiagnosticIssueCountBadge(summary: diagnostics)
                    PresentationToneBadge(
                        text: issueBadge.text,
                        tone: issueBadge.tone,
                        horizontalPadding: 6,
                        verticalPadding: 2
                    )
                    let headlineBadge = watchedAgentDiagnosticHeadlineBadge(summary: diagnostics)
                    PresentationToneBadge(
                        text: headlineBadge.text,
                        tone: headlineBadge.tone,
                        horizontalPadding: 6,
                        verticalPadding: 2
                    )
                }
            }

            if isHealthy, diagnostics == nil {
                Text(
                    agent.isRunning
                        ? String(localized: "Running normally")
                        : String(localized: "Pinned for watch, not currently running")
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let diagnostics, diagnostics.hasIssues {
                Text(([reasons.prefix(1).first].compactMap { $0 } + [diagnostics.summaryLine]).joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text(reasons.prefix(3).joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                PresentationToneBadge(
                    text: agent.stateLabel,
                    tone: watchedAgentStateTone(agent: agent, severity: severity, diagnostics: diagnostics),
                    horizontalPadding: 6,
                    verticalPadding: 2
                )

                if let lastActive = agent.lastActive {
                    OnCallRelativeTimeText(dateString: lastActive)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct OnCallWatchlistInventoryDeck: View {
    let watchedCount: Int
    let visibleCount: Int
    let issueCount: Int
    let failedDeliveryCount: Int
    let missingIdentityCount: Int
    let fallbackDriftCount: Int
    let pausedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(summary: summaryLine, detail: detailLine) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: watchedCount == 1 ? String(localized: "1 watched agent") : String(localized: "\(watchedCount) watched agents"),
                        tone: watchedCount > 0 ? .positive : .neutral
                    )
                    if issueCount > 0 {
                        PresentationToneBadge(
                            text: issueCount == 1 ? String(localized: "1 issue visible") : String(localized: "\(issueCount) issues visible"),
                            tone: .warning
                        )
                    }
                    if failedDeliveryCount > 0 {
                        PresentationToneBadge(
                            text: failedDeliveryCount == 1 ? String(localized: "1 delivery failure") : String(localized: "\(failedDeliveryCount) delivery failures"),
                            tone: .critical
                        )
                    }
                    if fallbackDriftCount > 0 {
                        PresentationToneBadge(
                            text: fallbackDriftCount == 1 ? String(localized: "1 fallback drift") : String(localized: "\(fallbackDriftCount) fallback drift"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Watchlist inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep watched-agent pressure, diagnostics drift, and paused coverage visible before opening the pinned agents."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == watchedCount
                        ? String(localized: "Full watchlist")
                        : String(localized: "\(visibleCount)/\(watchedCount) visible"),
                    tone: visibleCount == watchedCount ? .positive : .neutral
                )
            } facts: {
                Label(
                    issueCount == 1 ? String(localized: "1 operator issue") : String(localized: "\(issueCount) operator issues"),
                    systemImage: "exclamationmark.triangle"
                )
                if failedDeliveryCount > 0 {
                    Label(
                        failedDeliveryCount == 1 ? String(localized: "1 delivery failure") : String(localized: "\(failedDeliveryCount) delivery failures"),
                        systemImage: "shippingbox"
                    )
                }
                if missingIdentityCount > 0 {
                    Label(
                        missingIdentityCount == 1 ? String(localized: "1 identity gap") : String(localized: "\(missingIdentityCount) identity gaps"),
                        systemImage: "doc.badge.gearshape"
                    )
                }
                if fallbackDriftCount > 0 {
                    Label(
                        fallbackDriftCount == 1 ? String(localized: "1 fallback drift") : String(localized: "\(fallbackDriftCount) fallback drift"),
                        systemImage: "square.stack.3d.up.slash"
                    )
                }
                if pausedCount > 0 {
                    Label(
                        pausedCount == 1 ? String(localized: "1 paused watch") : String(localized: "\(pausedCount) paused watches"),
                        systemImage: "pause.circle"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if visibleCount == watchedCount {
            return watchedCount == 1
                ? String(localized: "The watchlist is showing the only pinned agent.")
                : String(localized: "The watchlist is showing all \(watchedCount) pinned agents.")
        }
        return String(localized: "The watchlist is showing \(visibleCount) of \(watchedCount) pinned agents.")
    }

    private var detailLine: String {
        String(localized: "Issue-heavy watched agents and diagnostic drift stay summarized here before the pinned rows.")
    }
}

private struct OnCallRelativeTimeText: View {
    let dateString: String

    var body: some View {
        if let date = parseDate(dateString) {
            Text(date, style: .relative)
        } else {
            Text(dateString)
        }
    }

    private func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

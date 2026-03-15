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
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    headerLabel
                    Spacer(minLength: 8)
                    queueBadge
                }
                VStack(alignment: .leading, spacing: 6) {
                    headerLabel
                    queueBadge
                }
            }

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    criticalLabel
                    watchLabel
                    Spacer(minLength: 8)
                    openBadge
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        criticalLabel
                        watchLabel
                    }
                    openBadge
                }
            }
            .font(.caption2)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var headerLabel: some View {
        Label("On Call", systemImage: "waveform.path.ecg")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
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
    private var criticalCount: Int {
        visibleAlerts.filter { $0.severity == .critical }.count
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
                OnCallQueueSnapshotCard(
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
                    readiness: draftHandoffReadiness
                )
            } footer: {
                Text("Queue pressure, follow-up readiness, and local watchlist issues stay visible before the longer sections.")
            }

            Section("Shift Status") {
                OnCallStatusCard(
                    digestLine: digestLine,
                    liveAlertCount: visibleAlerts.count,
                    acknowledgedAt: incidentStateStore.currentAcknowledgementDate(for: vm.monitoringAlerts),
                    isAcknowledged: incidentStateStore.isCurrentSnapshotAcknowledged(alerts: vm.monitoringAlerts),
                    mutedAlertCount: mutedAlertCount,
                    watchCount: watchedAgents.count,
                    lastRefresh: vm.lastRefresh
                )

                OnCallHandoffStatusRow(
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

                NavigationLink(value: OnCallRoute.incidents) {
                    Label("Open Incidents Center", systemImage: "bell.badge")
                }

                NavigationLink {
                    NightWatchView()
                } label: {
                    Label("Open Night Watch", systemImage: "moon.stars")
                }

                NavigationLink {
                    StandbyDigestView()
                } label: {
                    Label("Open Standby Digest", systemImage: "rectangle.inset.filled")
                }

                NavigationLink {
                    HandoffCenterView(
                        summary: handoffText,
                        queueCount: priorityItems.count,
                        criticalCount: criticalCount,
                        liveAlertCount: visibleAlerts.count
                    )
                } label: {
                    Label("Open Handoff Center", systemImage: "text.badge.plus")
                }

                ShareLink(item: handoffText) {
                    Label("Share Handoff Summary", systemImage: "square.and.arrow.up")
                }
            }

            if !priorityItems.isEmpty {
                Section {
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

            if !watchedAttentionItems.isEmpty {
                Section {
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

            Section {
                OnCallJumpCard(
                    approvalCount: vm.pendingApprovalCount,
                    sessionCount: vm.sessionAttentionCount,
                    eventCount: vm.recentCriticalAuditCount,
                    automationIssueCount: automationIssueCount,
                    integrationIssueCount: integrationIssueCount,
                    criticalCount: criticalCount,
                    handoffText: handoffText,
                    queueCount: priorityItems.count,
                    liveAlertCount: visibleAlerts.count
                )
            } footer: {
                Text("Keep the highest-value drilldowns visible without jumping through multiple menus.")
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
                        Label("Open Incidents Center", systemImage: "bell.badge")
                    }

                    NavigationLink {
                        NightWatchView()
                    } label: {
                        Label("Open Night Watch", systemImage: "moon.stars")
                    }

                    NavigationLink {
                        StandbyDigestView()
                    } label: {
                        Label("Open Standby Digest", systemImage: "rectangle.inset.filled")
                    }

                    NavigationLink {
                        HandoffCenterView(
                            summary: handoffText,
                            queueCount: priorityItems.count,
                            criticalCount: criticalCount,
                            liveAlertCount: visibleAlerts.count
                        )
                    } label: {
                        Label("Open Handoff Center", systemImage: "text.badge.plus")
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
                    description: Text("The watched agent is no longer available in the current monitoring snapshot.")
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
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    headerLabel
                    Spacer(minLength: 8)
                    PresentationToneBadge(text: readiness.state.label, tone: readiness.state.tone)
                }

                VStack(alignment: .leading, spacing: 8) {
                    headerLabel
                    PresentationToneBadge(text: readiness.state.label, tone: readiness.state.tone)
                }
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

private struct OnCallJumpCard: View {
    let approvalCount: Int
    let sessionCount: Int
    let eventCount: Int
    let automationIssueCount: Int
    let integrationIssueCount: Int
    let criticalCount: Int
    let handoffText: String
    let queueCount: Int
    let liveAlertCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Quick Links", systemImage: "arrowshape.turn.up.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                if approvalCount > 0 {
                    PresentationToneBadge(
                        text: approvalCount == 1 ? String(localized: "1 approval waiting") : String(localized: "\(approvalCount) approvals waiting"),
                        tone: .critical
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
            }

            NavigationLink(value: OnCallRoute.incidents) {
                OnCallJumpRow(
                    title: String(localized: "Open Incidents Center"),
                    detail: criticalCount > 0
                        ? (criticalCount == 1
                            ? String(localized: "1 critical item is still active on this phone.")
                            : String(localized: "\(criticalCount) critical items are still active on this phone."))
                        : String(localized: "Review muted alerts, approvals, and active incidents in one queue."),
                    systemImage: "bell.badge"
                )
            }

            NavigationLink(value: OnCallRoute.sessionsAttention) {
                OnCallJumpRow(
                    title: String(localized: "Session Pressure"),
                    detail: sessionCount > 0
                        ? (sessionCount == 1
                            ? String(localized: "1 session hotspot is already surfaced for review.")
                            : String(localized: "\(sessionCount) session hotspots are already surfaced for review."))
                        : String(localized: "Jump straight into duplicated, unlabeled, or high-volume sessions."),
                    systemImage: "rectangle.stack"
                )
            }

            NavigationLink(value: OnCallRoute.eventsCritical) {
                OnCallJumpRow(
                    title: String(localized: "Critical Event Feed"),
                    detail: eventCount > 0
                        ? (eventCount == 1
                            ? String(localized: "1 critical audit event needs review.")
                            : String(localized: "\(eventCount) critical audit events need review."))
                        : String(localized: "Review the recent audit feed without leaving the on-call flow."),
                    systemImage: "list.bullet.rectangle.portrait"
                )
            }

            NavigationLink {
                HandoffCenterView(
                    summary: handoffText,
                    queueCount: queueCount,
                    criticalCount: criticalCount,
                    liveAlertCount: liveAlertCount
                )
            } label: {
                OnCallJumpRow(
                    title: String(localized: "Open Handoff Center"),
                    detail: String(localized: "Capture the current queue and keep the next operator aligned."),
                    systemImage: "text.badge.plus"
                )
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                iconBadge
                contentBlock
                Spacer(minLength: 8)
            }

            VStack(alignment: .leading, spacing: 10) {
                iconBadge
                contentBlock
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Latest Handoff", systemImage: "text.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                PresentationToneBadge(text: freshnessState.label, tone: freshnessState.tone)
            }

            Text(freshnessSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Cadence")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                PresentationToneBadge(text: cadenceState.label, tone: cadenceState.tone)
            }

            Text(cadenceSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let drift {
                HStack {
                    Text("Drift")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    PresentationToneBadge(text: drift.state.label, tone: drift.state.tone)
                }

                Text(drift.compactSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let carryover {
                HStack {
                    Text("Carryover")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    PresentationToneBadge(text: carryover.state.label, tone: carryover.state.tone)
                }

                Text(carryover.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Next Handoff")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                PresentationToneBadge(text: readiness.state.label, tone: readiness.state.tone)
            }

            Text(readiness.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let checkInStatus {
                HStack {
                    Text("Check-in")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    PresentationToneBadge(text: checkInStatus.state.label, tone: checkInStatus.state.tone)
                }

                Text(checkInStatus.dueLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(checkInStatus.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !followUpStatuses.isEmpty {
                let followUpSummary = HandoffFollowUpSummary.summarize(statuses: followUpStatuses)

                HStack {
                    Text("Follow-ups")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    PresentationToneBadge(text: followUpSummary.badgeLabel, tone: followUpSummary.tone)
                }

                Text(followUpSummary.detailLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let latestEntry {
                HStack {
                    HandoffKindBadge(kind: latestEntry.kind)
                    Spacer()
                    Text(String(localized: "Checklist \(latestEntry.checklist.progressLabel) · \(latestEntry.createdAt.formatted(date: .omitted, time: .shortened))"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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

                if !followUpStatuses.isEmpty {
                    Text(String(localized: "\(completedFollowUpCount) complete · \(pendingFollowUpCount) pending"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
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
        LazyVGrid(columns: columns, spacing: 10) {
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
        .padding(.horizontal)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Operator Snapshot", systemImage: "person.crop.rectangle.badge.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                PresentationToneBadge(text: snapshotState.onCallLabel, tone: snapshotState.tone)
            }

            Text(digestLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    statusChip(
                        text: watchCount == 1 ? String(localized: "1 watched agent") : String(localized: "\(watchCount) watched agents"),
                        systemImage: "star.fill"
                    )
                    statusChip(
                        text: mutedAlertCount == 1 ? String(localized: "1 muted alert") : String(localized: "\(mutedAlertCount) muted alerts"),
                        systemImage: "bell.slash"
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    statusChip(
                        text: watchCount == 1 ? String(localized: "1 watched agent") : String(localized: "\(watchCount) watched agents"),
                        systemImage: "star.fill"
                    )
                    statusChip(
                        text: mutedAlertCount == 1 ? String(localized: "1 muted alert") : String(localized: "\(mutedAlertCount) muted alerts"),
                        systemImage: "bell.slash"
                    )
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if let acknowledgedAt, isAcknowledged {
                Text("Acknowledged \(acknowledgedAt, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let lastRefresh {
                Text("Last refreshed \(lastRefresh, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusChip(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }
}

private struct OnCallPriorityRow: View {
    let item: OnCallPriorityItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.symbolName)
                    .foregroundStyle(item.severity.tone.color)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
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

            HStack(spacing: 8) {
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

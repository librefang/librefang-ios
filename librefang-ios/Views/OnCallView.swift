import SwiftUI

struct OnCallDigestCard: View {
    let queueCount: Int
    let criticalCount: Int
    let watchCount: Int
    let summary: String

    private var criticalStatus: MonitoringSummaryStatus {
        .countStatus(criticalCount, activeTone: .critical)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow(verticalSpacing: 8) {
                Label("On Call", systemImage: "waveform.path.ecg")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } accessory: {
                queueBadge
            }

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            FlowLayout(spacing: 8) {
                PresentationToneBadge(
                    text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                    tone: criticalStatus.tone
                )

                if watchCount > 0 {
                    PresentationToneBadge(
                        text: watchCount == 1 ? String(localized: "1 watch") : String(localized: "\(watchCount) watch"),
                        tone: .caution
                    )
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var queueBadge: some View {
        PresentationToneBadge(
            text: queueCount == 1 ? String(localized: "1 queued") : String(localized: "\(queueCount) queued"),
            tone: criticalStatus.tone
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
    private var activeWatchedAttentionItems: [AgentAttentionItem] {
        watchedAttentionItems.filter { $0.severity > 0 }
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
            scoreboardSection
            priorityQueueSection
            watchlistSection
            calmStateSection
        }
        .navigationTitle(String(localized: "On Call"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                trailingMenu
            }
        }
        .navigationDestination(for: OnCallRoute.self) { route in
            destination(for: route)
        }
        .monitoringRefreshInteractionGate(isRefreshing: vm.isLoading)
        .refreshable {
            await refreshAndSync()
        }
        .overlay {
            if vm.isLoading && vm.lastRefresh == nil {
                ProgressView(String(localized: "Loading on-call view..."))
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
    private var trailingMenu: some View {
        Menu {
            ShareLink(item: handoffText) {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            NavigationLink(value: OnCallRoute.incidents) {
                Label("Incidents", systemImage: "bell.badge")
            }

            NavigationLink {
                NightWatchView()
            } label: {
                Label("Night Watch", systemImage: "moon.stars")
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

    @ViewBuilder
    private var scoreboardSection: some View {
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
    }

    @ViewBuilder
    private var priorityQueueSection: some View {
        if !priorityItems.isEmpty {
            Section {
                ForEach(priorityItems.prefix(5)) { item in
                    NavigationLink(value: item.route) {
                        OnCallPriorityRow(item: item)
                    }
                }
            } header: {
                Text("Priority Queue")
            }
        }
    }

    @ViewBuilder
    private var watchlistSection: some View {
        if !activeWatchedAttentionItems.isEmpty {
            Section {
                ForEach(activeWatchedAttentionItems.prefix(3)) { item in
                    NavigationLink(value: OnCallRoute.agent(item.agent.id)) {
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
            }
        }
    }

    @ViewBuilder
    private var calmStateSection: some View {
        if priorityItems.isEmpty
            && activeWatchedAttentionItems.isEmpty
            && vm.pendingApprovalCount == 0
            && vm.recentCriticalAuditCount == 0 {
            Section("On Call") {
                ContentUnavailableView(
                    "Calm State",
                    systemImage: "checkmark.shield",
                    description: Text("No live priorities right now.")
                )
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
            if let item = activeWatchedAttentionItems.first(where: { $0.agent.id == id }) {
                watchedDiagnosticsDestination(for: item)
            } else if let agent = vm.agents.first(where: { $0.id == id }) {
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

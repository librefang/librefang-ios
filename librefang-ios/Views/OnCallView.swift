import SwiftUI

struct OnCallDigestCard: View {
    let queueCount: Int
    let criticalCount: Int
    let watchCount: Int
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("On Call", systemImage: "waveform.path.ecg")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(queueCount == 1 ? String(localized: "1 queued") : String(localized: "\(queueCount) queued"))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((criticalCount > 0 ? Color.red : Color.secondary).opacity(0.12))
                    .foregroundStyle(criticalCount > 0 ? .red : .secondary)
                    .clipShape(Capsule())
            }

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 12) {
                Label("\(criticalCount)", systemImage: "xmark.octagon")
                    .foregroundStyle(criticalCount > 0 ? .red : .secondary)
                Label("\(watchCount)", systemImage: "star.fill")
                    .foregroundStyle(watchCount > 0 ? .yellow : .secondary)
                Spacer()
                Text("Open")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
            .font(.caption2)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    criticalCount: visibleAlerts.filter { $0.severity == .critical }.count,
                    liveAlertCount: visibleAlerts.count,
                    approvalCount: vm.pendingApprovalCount,
                    watchIssueCount: watchedAttentionItems.filter { $0.severity > 0 }.count,
                    sessionCount: vm.sessionAttentionCount,
                    eventCount: vm.recentCriticalAuditCount
                )
                .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
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
                        criticalCount: visibleAlerts.filter { $0.severity == .critical }.count,
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

            Section("Quick Links") {
                NavigationLink(value: OnCallRoute.sessionsAttention) {
                    Label("Session Pressure", systemImage: "rectangle.stack")
                }
                NavigationLink(value: OnCallRoute.eventsCritical) {
                    Label("Critical Event Feed", systemImage: "list.bullet.rectangle.portrait")
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
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    ShareLink(item: handoffText) {
                        Image(systemName: "square.and.arrow.up")
                    }

                    NavigationLink {
                        StandbyDigestView()
                    } label: {
                        Image(systemName: "rectangle.inset.filled")
                    }

                    NavigationLink {
                        HandoffCenterView(
                            summary: handoffText,
                            queueCount: priorityItems.count,
                            criticalCount: visibleAlerts.filter { $0.severity == .critical }.count,
                            liveAlertCount: visibleAlerts.count
                        )
                    } label: {
                        Image(systemName: "text.badge.plus")
                    }

                    NavigationLink {
                        NightWatchView()
                    } label: {
                        Image(systemName: "moon.stars")
                    }
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
                criticalCount: visibleAlerts.filter { $0.severity == .critical }.count,
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
                Text(freshnessState.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(freshnessState.tone.color.opacity(0.12))
                    .foregroundStyle(freshnessState.tone.color)
                    .clipShape(Capsule())
            }

            Text(freshnessSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Cadence")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(cadenceState.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(cadenceState.tone.color.opacity(0.12))
                    .foregroundStyle(cadenceState.tone.color)
                    .clipShape(Capsule())
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
                    Text(drift.state.label)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(drift.state.tone.color.opacity(0.12))
                        .foregroundStyle(drift.state.tone.color)
                        .clipShape(Capsule())
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
                    Text(carryover.state.label)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(carryover.state.tone.color.opacity(0.12))
                        .foregroundStyle(carryover.state.tone.color)
                        .clipShape(Capsule())
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
                Text(readiness.state.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(readiness.state.tone.color.opacity(0.12))
                    .foregroundStyle(readiness.state.tone.color)
                    .clipShape(Capsule())
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
                    Text(checkInStatus.state.label)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(checkInStatus.state.tone.color.opacity(0.12))
                        .foregroundStyle(checkInStatus.state.tone.color)
                        .clipShape(Capsule())
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
                    Text(followUpSummary.badgeLabel)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(followUpSummary.tone.color.opacity(0.12))
                        .foregroundStyle(followUpSummary.tone.color)
                        .clipShape(Capsule())
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
    let criticalCount: Int
    let liveAlertCount: Int
    let approvalCount: Int
    let watchIssueCount: Int
    let sessionCount: Int
    let eventCount: Int

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
                value: "\(liveAlertCount)",
                label: "Live Alerts",
                icon: "bell.badge",
                color: liveAlertCount > 0 ? .orange : .secondary
            )
            StatBadge(
                value: "\(approvalCount)",
                label: "Approvals",
                icon: "exclamationmark.shield",
                color: approvalCount > 0 ? .red : .secondary
            )
            StatBadge(
                value: "\(watchIssueCount)",
                label: "Watchlist",
                icon: "star.fill",
                color: watchIssueCount > 0 ? .yellow : .secondary
            )
            StatBadge(
                value: "\(sessionCount)",
                label: "Sessions",
                icon: "rectangle.stack",
                color: sessionCount > 0 ? .orange : .secondary
            )
            StatBadge(
                value: "\(eventCount)",
                label: "Events",
                icon: "list.bullet.rectangle.portrait",
                color: eventCount > 0 ? .red : .secondary
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
                Text(snapshotState.onCallLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(snapshotState.tone.color.opacity(0.12))
                    .foregroundStyle(snapshotState.tone.color)
                    .clipShape(Capsule())
            }

            Text(digestLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Label(
                    watchCount == 1 ? String(localized: "1 watched agent") : String(localized: "\(watchCount) watched agents"),
                    systemImage: "star.fill"
                )
                Label(
                    mutedAlertCount == 1 ? String(localized: "1 muted alert") : String(localized: "\(mutedAlertCount) muted alerts"),
                    systemImage: "bell.slash"
                )
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
                        Text(item.severity.label)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(item.severity.tone.color.opacity(0.12))
                            .foregroundStyle(item.severity.tone.color)
                            .clipShape(Capsule())
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
                    .foregroundStyle(.yellow)
                if let diagnostics, diagnostics.hasIssues {
                    let issueBadge = watchedAgentDiagnosticIssueCountBadge(summary: diagnostics)
                    Text(issueBadge.text)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(issueBadge.tone.color.opacity(0.12))
                        .foregroundStyle(issueBadge.tone.color)
                        .clipShape(Capsule())
                    let headlineBadge = watchedAgentDiagnosticHeadlineBadge(summary: diagnostics)
                    Text(headlineBadge.text)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(headlineBadge.tone.color.opacity(0.12))
                        .foregroundStyle(headlineBadge.tone.color)
                        .clipShape(Capsule())
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
                Text(agent.stateLabel)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(watchedAgentStateTone(agent: agent, severity: severity, diagnostics: diagnostics).color.opacity(0.12))
                    .foregroundStyle(watchedAgentStateTone(agent: agent, severity: severity, diagnostics: diagnostics).color)
                    .clipShape(Capsule())

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

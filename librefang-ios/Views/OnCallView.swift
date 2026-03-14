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
                Text(queueCount == 1 ? "1 queued" : "\(queueCount) queued")
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

    private var watchedAttentionItems: [AgentAttentionItem] {
        watchedAgents
            .map { vm.attentionItem(for: $0) }
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

    private var priorityItems: [OnCallPriorityItem] {
        vm.onCallPriorityItems(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems
        )
    }

    private var digestLine: String {
        vm.onCallDigestLine(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            mutedAlertCount: mutedAlertCount,
            isAcknowledged: incidentStateStore.isCurrentSnapshotAcknowledged(alerts: vm.monitoringAlerts)
        )
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

                NavigationLink(value: OnCallRoute.incidents) {
                    Label("Open Incidents Center", systemImage: "bell.badge")
                }

                NavigationLink {
                    NightWatchView()
                } label: {
                    Label("Open Night Watch", systemImage: "moon.stars")
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
                        NavigationLink(value: OnCallRoute.agent(item.agent.id)) {
                            WatchedAgentRow(
                                agent: item.agent,
                                reasons: item.reasons,
                                severity: item.severity,
                                isHealthy: item.severity == 0
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
                NavigationLink {
                    NightWatchView()
                } label: {
                    Image(systemName: "moon.stars")
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
        case .eventsCritical:
            EventsView(api: deps.apiClient, initialScope: .critical)
        case .eventsSearch(let query):
            EventsView(api: deps.apiClient, initialSearchText: query, initialScope: .critical)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Operator Snapshot", systemImage: "person.crop.rectangle.badge.exclamationmark")
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

            Text(digestLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Label(watchCount == 1 ? "1 watched agent" : "\(watchCount) watched agents", systemImage: "star.fill")
                Label(mutedAlertCount == 1 ? "1 muted alert" : "\(mutedAlertCount) muted alerts", systemImage: "bell.slash")
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

    private var statusLabel: String {
        if liveAlertCount > 0 {
            return isAcknowledged ? "Acked" : "Live"
        }
        if isAcknowledged { return "Acked" }
        if mutedAlertCount > 0 { return "Watching" }
        return "Calm"
    }

    private var statusColor: Color {
        if liveAlertCount > 0 {
            return isAcknowledged ? .orange : .red
        }
        if isAcknowledged { return .orange }
        if mutedAlertCount > 0 { return .secondary }
        return .green
    }
}

private struct OnCallPriorityRow: View {
    let item: OnCallPriorityItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.symbolName)
                    .foregroundStyle(severityColor)
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
                            .background(severityColor.opacity(0.12))
                            .foregroundStyle(severityColor)
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

    private var severityColor: Color {
        switch item.severity {
        case .critical:
            .red
        case .warning:
            .orange
        case .advisory:
            .yellow
        }
    }
}

private struct WatchedAgentRow: View {
    let agent: Agent
    let reasons: [String]
    let severity: Int
    let isHealthy: Bool

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
            }

            if isHealthy {
                Text(agent.isRunning ? "Running normally" : "Pinned for watch, not currently running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(reasons.prefix(3).joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text(agent.state)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(stateColor.opacity(0.12))
                    .foregroundStyle(stateColor)
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

    private var stateColor: Color {
        if severity >= 10 { return .red }
        if severity > 0 { return .orange }
        return agent.isRunning ? .green : .secondary
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

import SwiftUI

private enum StandbyTone {
    case calm
    case watch
    case alert
    case critical

    var gradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .calm:
            colors = [Color(red: 0.07, green: 0.14, blue: 0.11), Color(red: 0.03, green: 0.07, blue: 0.08)]
        case .watch:
            colors = [Color(red: 0.06, green: 0.10, blue: 0.17), Color(red: 0.03, green: 0.06, blue: 0.10)]
        case .alert:
            colors = [Color(red: 0.18, green: 0.11, blue: 0.05), Color(red: 0.08, green: 0.05, blue: 0.07)]
        case .critical:
            colors = [Color(red: 0.22, green: 0.07, blue: 0.09), Color(red: 0.08, green: 0.04, blue: 0.08)]
        }

        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var accent: Color {
        switch self {
        case .calm:
            .green
        case .watch:
            .blue
        case .alert:
            .orange
        case .critical:
            .red
        }
    }

    var label: String {
        switch self {
        case .calm:
            "Calm"
        case .watch:
            "Watching"
        case .alert:
            "Attention"
        case .critical:
            "Critical"
        }
    }
}

struct StandbyDigestView: View {
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

    private var watchedAttentionItems: [AgentAttentionItem] {
        watchlistStore.watchedAgents(from: vm.agents)
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
            watchedAttentionItems: watchedAttentionItems,
            handoffCheckInStatus: deps.onCallHandoffStore.latestCheckInStatus,
            handoffFollowUpStatuses: deps.onCallHandoffStore.latestFollowUpStatuses
        )
    }

    private var criticalCount: Int {
        visibleAlerts.filter { $0.severity == .critical }.count
    }

    private var primaryItems: [OnCallPriorityItem] {
        Array(priorityItems.prefix(4))
    }

    private var watchItems: [AgentAttentionItem] {
        Array(watchedAttentionItems.filter { $0.severity > 0 }.prefix(3))
    }

    private var isAcknowledged: Bool {
        incidentStateStore.isCurrentSnapshotAcknowledged(alerts: vm.monitoringAlerts)
    }

    private var tone: StandbyTone {
        if criticalCount > 0 || vm.pendingApprovalCount > 0 {
            return .critical
        }
        if priorityItems.contains(where: { $0.severity == .warning }) {
            return .alert
        }
        if !priorityItems.isEmpty || mutedAlertCount > 0 || !watchItems.isEmpty {
            return .watch
        }
        return .calm
    }

    private var digestLine: String {
        vm.onCallDigestLine(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            mutedAlertCount: mutedAlertCount,
            isAcknowledged: isAcknowledged,
            handoffCheckInStatus: deps.onCallHandoffStore.latestCheckInStatus,
            handoffFollowUpStatuses: deps.onCallHandoffStore.latestFollowUpStatuses
        )
    }
    private var handoffText: String {
        vm.onCallHandoffText(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            mutedAlertCount: mutedAlertCount,
            isAcknowledged: isAcknowledged,
            handoffCheckInStatus: deps.onCallHandoffStore.latestCheckInStatus,
            handoffFollowUpStatuses: deps.onCallHandoffStore.latestFollowUpStatuses
        )
    }

    var body: some View {
        ZStack {
            tone.gradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    glanceCard

                    if !watchItems.isEmpty {
                        watchlistCard
                    }

                    actionCard
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Standby")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    NightWatchView()
                } label: {
                    Image(systemName: "moon.stars")
                }

                NavigationLink {
                    OnCallView()
                } label: {
                    Image(systemName: "waveform.path.ecg")
                }
            }
        }
        .navigationDestination(for: OnCallRoute.self) { route in
            destination(for: route)
        }
        .refreshable {
            await refreshAndSync()
        }
        .task {
            if vm.lastRefresh == nil {
                await refreshAndSync()
            } else {
                syncWatchlist()
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date(), style: .time)
                        .font(.system(size: 52, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)

                    Text(Date(), format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.76))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text(tone.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.14))
                        .clipShape(Capsule())

                    if let lastRefresh = vm.lastRefresh {
                        Text(lastRefresh, style: .relative)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
            }

            Text(digestLine)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(3)

            HStack(spacing: 10) {
                StandbyCountPill(value: criticalCount, label: "Critical")
                StandbyCountPill(value: priorityItems.count, label: "Queued")
                StandbyCountPill(value: watchItems.count, label: "Watched")
                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    incidentStateStore.acknowledgeCurrentSnapshot(alerts: vm.monitoringAlerts)
                } label: {
                    Label("Acknowledge", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StandbyActionButtonStyle(fill: .white.opacity(0.12)))

                if isAcknowledged {
                    Button {
                        incidentStateStore.clearAcknowledgement()
                    } label: {
                        Label("Clear Ack", systemImage: "arrow.uturn.backward.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(StandbyActionButtonStyle(fill: .white.opacity(0.16)))
                }
            }
        }
        .padding(18)
        .background(.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }

    @ViewBuilder
    private var glanceCard: some View {
        if primaryItems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Standby is quiet", systemImage: "checkmark.shield")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(mutedAlertCount > 0
                     ? "\(mutedAlertCount) muted alerts remain hidden on this iPhone."
                     : "No live critical pressure is visible right now.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.76))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("At a Glance", systemImage: "rectangle.inset.filled")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(primaryItems.count == 1 ? "1 card" : "\(primaryItems.count) cards")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.74))
                }

                ForEach(primaryItems) { item in
                    NavigationLink(value: item.route) {
                        StandbyPriorityRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .background(.white.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var watchlistCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pinned Watchlist", systemImage: "star.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(watchItems.count == 1 ? "1 agent" : "\(watchItems.count) agents")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.74))
            }

            ForEach(watchItems) { item in
                NavigationLink(value: OnCallRoute.agent(item.agent.id)) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(item.agent.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Spacer()
                            Text(item.agent.isRunning ? "Running" : "Idle")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white.opacity(0.72))
                        }

                        Text(item.reasons.prefix(2).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.76))
                            .lineLimit(2)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(.white.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Jump", systemImage: "arrowshape.turn.up.right")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            NavigationLink {
                NightWatchView()
            } label: {
                StandbyActionRow(
                    title: "Night Watch",
                    detail: "Open the stronger triage surface with deeper priority ordering.",
                    systemImage: "moon.stars"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                OnCallView()
            } label: {
                StandbyActionRow(
                    title: "Full On Call Queue",
                    detail: "Open the complete queue with sections, watchlist, and quick links.",
                    systemImage: "waveform.path.ecg"
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: OnCallRoute.incidents) {
                StandbyActionRow(
                    title: "Incidents Center",
                    detail: "Inspect all live alerts, muted alerts, and pending approvals.",
                    systemImage: "bell.badge"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                HandoffCenterView(
                    summary: handoffText,
                    queueCount: priorityItems.count,
                    criticalCount: criticalCount,
                    liveAlertCount: visibleAlerts.count
                )
            } label: {
                StandbyActionRow(
                    title: "Handoff Center",
                    detail: "Save a local note and keep recent handoff snapshots on this iPhone.",
                    systemImage: "text.badge.plus"
                )
            }
            .buttonStyle(.plain)

            ShareLink(item: handoffText) {
                StandbyActionRow(
                    title: "Share Handoff Summary",
                    detail: "Export the current standby snapshot as plain text.",
                    systemImage: "square.and.arrow.up"
                )
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(.white.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                    description: Text("This agent is no longer present in the current monitoring snapshot.")
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
        case .handoffCenter:
            HandoffCenterView(
                summary: handoffText,
                queueCount: priorityItems.count,
                criticalCount: criticalCount,
                liveAlertCount: visibleAlerts.count
            )
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

private struct StandbyPriorityRow: View {
    let item: OnCallPriorityItem

    private var tint: Color {
        switch item.severity {
        case .critical:
            .red
        case .warning:
            .orange
        case .advisory:
            .blue
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.34))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.80))
                    .lineLimit(2)

                Text(item.footnote)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct StandbyActionRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct StandbyCountPill: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct StandbyActionButtonStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .background(fill.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

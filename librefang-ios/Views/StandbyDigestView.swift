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
            String(localized: "Calm")
        case .watch:
            String(localized: "Watching")
        case .alert:
            String(localized: "Attention")
        case .critical:
            String(localized: "Critical")
        }
    }
}

struct StandbyDigestView: View {
    @Environment(\.dependencies) private var deps
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
        Array(priorityItems.prefix(2))
    }

    private var watchItems: [AgentAttentionItem] {
        Array(watchedAttentionItems.filter { $0.severity > 0 }.prefix(1))
    }
    private var activeWatchItems: [AgentAttentionItem] {
        watchedAttentionItems.filter { $0.severity > 0 }
    }
    private var watchIssueCount: Int {
        activeWatchItems.count
    }
    private var warningQueueCount: Int {
        priorityItems.filter { $0.severity == .warning }.count
    }
    private var advisoryQueueCount: Int {
        priorityItems.filter { $0.severity == .advisory }.count
    }
    private var pendingFollowUpCount: Int {
        deps.onCallHandoffStore.latestFollowUpStatuses.filter { !$0.isCompleted }.count
    }
    private var checkInStatus: HandoffCheckInStatus? {
        deps.onCallHandoffStore.latestCheckInStatus
    }
    private var automationIssueCount: Int {
        vm.automationPressureIssueCategoryCount
    }
    private var integrationIssueCount: Int {
        vm.integrationPressureIssueCategoryCount
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
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(String(localized: "Standby"))
        .navigationBarTitleDisplayMode(.inline)
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
            NavigationLink {
                OnCallView()
            } label: {
                Label("On Call", systemImage: "waveform.path.ecg")
            }

            NavigationLink(value: OnCallRoute.incidents) {
                Label("Incidents", systemImage: "bell.badge")
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

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            ResponsiveAccessoryRow(horizontalAlignment: .top, verticalSpacing: 12, spacerMinLength: 12) {
                heroClock
            } accessory: {
                heroStatus
            }

            Text(digestLine)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)

            LazyVGrid(columns: standbyCountColumns, alignment: .leading, spacing: 10) {
                StandbyCountPill(value: criticalCount, label: String(localized: "Critical"))
                StandbyCountPill(value: priorityItems.count, label: String(localized: "Queued"))
                StandbyCountPill(value: watchItems.count, label: String(localized: "Watched"))
            }

            ResponsiveInlineGroup(horizontalSpacing: 10, verticalSpacing: 10) {
                acknowledgeButton
                if isAcknowledged {
                    clearAcknowledgementButton
                }
            }
        }
        .padding(18)
        .glassPanel(fillOpacity: 0.10, cornerRadius: 26, strokeOpacity: 0.08)
    }

    private var heroClock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date(), style: .time)
                .font(.system(size: 52, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(Date(), format: .dateTime.weekday(.wide).month(.abbreviated).day())
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.76))
        }
    }

    private var heroStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassCapsuleBadge(text: tone.label, backgroundOpacity: 0.14, horizontalPadding: 10, verticalPadding: 6)

            if let lastRefresh = vm.lastRefresh {
                Text(lastRefresh, style: .relative)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity, alignment: horizontalSizeClass == .compact ? .leading : .trailing)
    }

    private var standbyCountColumns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    private var acknowledgeButton: some View {
        Button {
            incidentStateStore.acknowledgeCurrentSnapshot(alerts: vm.monitoringAlerts)
        } label: {
            Label {
                Text(String(localized: "Acknowledge"))
            } icon: {
                Image(systemName: "checkmark.seal")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassPanelButtonStyle(fillOpacity: 0.12, cornerRadius: 14))
    }

    private var clearAcknowledgementButton: some View {
        Button {
            incidentStateStore.clearAcknowledgement()
        } label: {
            Label {
                Text(String(localized: "Clear Ack"))
            } icon: {
                Image(systemName: "arrow.uturn.backward.circle")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassPanelButtonStyle(fillOpacity: 0.16, cornerRadius: 14))
    }

    @ViewBuilder
    private var glanceCard: some View {
        if primaryItems.isEmpty && watchItems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(String(localized: "Standby is quiet"))
                } icon: {
                    Image(systemName: "checkmark.shield")
                }
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(
                    mutedAlertCount > 0
                        ? (mutedAlertCount == 1
                            ? String(localized: "1 muted alert remains hidden on this iPhone.")
                            : String(localized: "\(mutedAlertCount) muted alerts remain hidden on this iPhone."))
                        : String(localized: "No live critical pressure is visible right now.")
                )
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.76))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .glassPanel(fillOpacity: 0.08, cornerRadius: 22)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ResponsiveAccessoryRow {
                    glanceTitle
                } accessory: {
                    glanceCount
                }

                if primaryItems.isEmpty {
                    Text(String(localized: "No live priority cards are currently leading standby."))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.76))
                } else {
                    ForEach(primaryItems) { item in
                        NavigationLink(value: item.route) {
                            StandbyPriorityRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !watchItems.isEmpty {
                    Divider()
                        .overlay(.white.opacity(0.08))

                    ResponsiveAccessoryRow {
                        watchlistTitle
                    } accessory: {
                        watchlistCount
                    }

                    ForEach(watchItems) { item in
                        NavigationLink(value: OnCallRoute.agent(item.agent.id)) {
                            VStack(alignment: .leading, spacing: 5) {
                                ResponsiveAccessoryRow(verticalSpacing: 4) {
                                    watchItemName(item)
                                } accessory: {
                                    watchItemState(item)
                                }

                                Text(item.reasons.prefix(2).joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.76))
                                    .lineLimit(2)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassPanel(fillOpacity: 0.08, cornerRadius: 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
            .glassPanel(fillOpacity: 0.09, cornerRadius: 22)
        }
    }

    private var glanceTitle: some View {
        Label {
            Text(String(localized: "At a Glance"))
        } icon: {
            Image(systemName: "rectangle.inset.filled")
        }
        .font(.headline.weight(.semibold))
        .foregroundStyle(.white)
    }

    private var glanceCount: some View {
        Text(primaryItems.count == 1 ? String(localized: "1 card") : String(localized: "\(primaryItems.count) cards"))
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.74))
    }

    private var watchlistTitle: some View {
        Label {
            Text(String(localized: "Pinned Watchlist"))
        } icon: {
            Image(systemName: "star.fill")
        }
        .font(.headline.weight(.semibold))
        .foregroundStyle(.white)
    }

    private var watchlistCount: some View {
        Text(watchItems.count == 1 ? String(localized: "1 agent") : String(localized: "\(watchItems.count) agents"))
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.74))
    }

    private func watchItemName(_ item: AgentAttentionItem) -> some View {
        Text(item.agent.name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(2)
    }

    private func watchItemState(_ item: AgentAttentionItem) -> some View {
        GlassCapsuleBadge(
            text: item.agent.isRunning ? String(localized: "Running") : String(localized: "Idle"),
            foregroundStyle: .white.opacity(0.88),
            backgroundOpacity: 0.10
        )
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
                    description: Text("This agent is no longer present in the current snapshot.")
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
        ResponsiveIconDetailRow(horizontalAlignment: .top, verticalSpacing: 10) {
            iconBadge
        } detail: {
            contentBlock
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassPanel(fillOpacity: 0.08, cornerRadius: 16)
    }

    private var iconBadge: some View {
        Image(systemName: item.symbolName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .glassPanel(fillStyle: tint, fillOpacity: 0.34, cornerRadius: 10)
    }

    private var contentBlock: some View {
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
                .lineLimit(2)
        }
    }
}

private struct StandbyActionRow: View {
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
        .glassPanel(fillOpacity: 0.08, cornerRadius: 16)
    }

    private var iconBadge: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .glassPanel(fillOpacity: 0.10, cornerRadius: 12)
    }

    private var contentBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(2)
        }
    }
}

private struct StandbySurfaceSectionCard<Content: View>: View {
    let title: String
    let detail: String
    let content: Content

    init(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: "arrowshape.turn.up.right")
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))

            content
        }
        .padding(18)
        .glassPanel(fillOpacity: 0.09, cornerRadius: 22)
    }
}

private struct StandbySurfaceGroupLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.90))
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(fillOpacity: 0.10, cornerRadius: 14)
    }
}

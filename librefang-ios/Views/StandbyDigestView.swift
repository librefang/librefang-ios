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
        Array(priorityItems.prefix(4))
    }

    private var watchItems: [AgentAttentionItem] {
        Array(watchedAttentionItems.filter { $0.severity > 0 }.prefix(3))
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
                    controlDeckCard
                    glanceCard
                    surfaceDeckCard
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Standby")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink {
                        NightWatchView()
                    } label: {
                        Label("Night Watch", systemImage: "moon.stars")
                    }

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
            ResponsiveAccessoryRow(horizontalAlignment: .top, verticalSpacing: 12, spacerMinLength: 12) {
                heroClock
            } accessory: {
                heroStatus
            }

            Text(digestLine)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(3)

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

    private var snapshotCard: some View {
        StandbySnapshotCard(
            toneLabel: tone.label,
            criticalCount: criticalCount,
            queueCount: priorityItems.count,
            watchIssueCount: watchIssueCount,
            mutedAlertCount: mutedAlertCount,
            pendingFollowUpCount: pendingFollowUpCount,
            approvalCount: vm.pendingApprovalCount,
            automationIssueCount: automationIssueCount,
            integrationIssueCount: integrationIssueCount,
            isAcknowledged: isAcknowledged,
            checkInStatus: checkInStatus
        )
    }

    private var controlDeckCard: some View {
        VStack(spacing: 12) {
            snapshotCard
            signalFactsCard
        }
    }

    private var signalFactsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResponsiveAccessoryRow {
                Label {
                    Text(String(localized: "Signal Facts"))
                } icon: {
                    Image(systemName: "waveform.path.ecg")
                }
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            } accessory: {
                GlassCapsuleBadge(text: tone.label, backgroundOpacity: 0.14)
            }

            Text(String(localized: "Keep standby tone, queue size, and pressure readable before opening deeper surfaces."))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 8) {
                GlassCapsuleBadge(
                    text: priorityItems.count == 1 ? String(localized: "1 queued") : String(localized: "\(priorityItems.count) queued"),
                    backgroundOpacity: 0.14
                )
                GlassCapsuleBadge(
                    text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                    backgroundOpacity: criticalCount > 0 ? 0.18 : 0.10
                )
                if vm.pendingApprovalCount > 0 {
                    GlassCapsuleBadge(
                        text: vm.pendingApprovalCount == 1 ? String(localized: "1 approval") : String(localized: "\(vm.pendingApprovalCount) approvals"),
                        backgroundOpacity: 0.14
                    )
                }
                if watchIssueCount > 0 {
                    GlassCapsuleBadge(
                        text: watchIssueCount == 1 ? String(localized: "1 watch issue") : String(localized: "\(watchIssueCount) watch issues"),
                        backgroundOpacity: 0.12
                    )
                }
                if pendingFollowUpCount > 0 {
                    GlassCapsuleBadge(
                        text: pendingFollowUpCount == 1 ? String(localized: "1 follow-up open") : String(localized: "\(pendingFollowUpCount) follow-ups open"),
                        backgroundOpacity: 0.14
                    )
                }
                if automationIssueCount > 0 {
                    GlassCapsuleBadge(
                        text: automationIssueCount == 1 ? String(localized: "1 automation issue") : String(localized: "\(automationIssueCount) automation issues"),
                        backgroundOpacity: 0.12
                    )
                }
                if integrationIssueCount > 0 {
                    GlassCapsuleBadge(
                        text: integrationIssueCount == 1 ? String(localized: "1 integration issue") : String(localized: "\(integrationIssueCount) integration issues"),
                        backgroundOpacity: 0.12
                    )
                }
                if let checkInStatus {
                    GlassCapsuleBadge(text: checkInStatus.state.label, backgroundOpacity: 0.14)
                }
            }
        }
        .padding(18)
        .glassPanel(fillOpacity: 0.09, cornerRadius: 22)
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

                StandbyGlanceInventoryCard(
                    visibleCount: primaryItems.count,
                    totalCount: priorityItems.count,
                    criticalCount: criticalCount,
                    warningCount: warningQueueCount,
                    advisoryCount: advisoryQueueCount,
                    mutedAlertCount: mutedAlertCount,
                    followUpCount: pendingFollowUpCount,
                    approvalCount: vm.pendingApprovalCount,
                    isAcknowledged: isAcknowledged,
                    checkInStatus: checkInStatus
                )

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

                    StandbyWatchlistInventoryCard(
                        items: activeWatchItems,
                        visibleCount: watchItems.count,
                        totalPinnedCount: watchedAttentionItems.count
                    )

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

    private var surfaceDeckCard: some View {
        StandbySurfaceSectionCard(
            title: String(localized: "Routes"),
            detail: String(localized: "Keep the next standby drills in one deck.")
        ) {
            StandbySurfaceGroupLabel(title: String(localized: "Primary"))

            FlowLayout(spacing: 8) {
                NavigationLink {
                    NightWatchView()
                } label: {
                    GlassSurfaceShortcutChip(
                        title: String(localized: "Night Watch"),
                        systemImage: "moon.stars",
                        accent: criticalCount > 0 ? .red : .white,
                        badgeText: criticalCount > 0 ? String(localized: "\(criticalCount) critical") : nil
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    OnCallView()
                } label: {
                    GlassSurfaceShortcutChip(
                        title: String(localized: "On Call"),
                        systemImage: "waveform.path.ecg",
                        badgeText: priorityItems.isEmpty ? nil : (priorityItems.count == 1 ? String(localized: "1 queued") : String(localized: "\(priorityItems.count) queued"))
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: OnCallRoute.incidents) {
                    GlassSurfaceShortcutChip(
                        title: String(localized: "Incidents"),
                        systemImage: "bell.badge",
                        accent: criticalCount > 0 ? .red : .white,
                        badgeText: visibleAlerts.isEmpty ? nil : (visibleAlerts.count == 1 ? String(localized: "1 alert") : String(localized: "\(visibleAlerts.count) alerts"))
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    RuntimeView()
                } label: {
                    GlassSurfaceShortcutChip(
                        title: String(localized: "Runtime"),
                        systemImage: "server.rack"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ApprovalsView()
                } label: {
                    GlassSurfaceShortcutChip(
                        title: String(localized: "Approvals"),
                        systemImage: "checkmark.shield",
                        accent: vm.pendingApprovalCount > 0 ? .red : .white,
                        badgeText: vm.pendingApprovalCount > 0 ? String(localized: "\(vm.pendingApprovalCount) waiting") : nil
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
                    GlassSurfaceShortcutChip(
                        title: String(localized: "Handoff"),
                        systemImage: "text.badge.plus",
                        accent: pendingFollowUpCount > 0 ? .orange : .white,
                        badgeText: pendingFollowUpCount > 0 ? String(localized: "\(pendingFollowUpCount) open") : nil
                    )
                }
                .buttonStyle(.plain)
            }

            Divider()
                .overlay(.white.opacity(0.08))

            StandbySurfaceGroupLabel(title: String(localized: "Support"))

            FlowLayout(spacing: 8) {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    GlassSurfaceShortcutChip(
                        title: String(localized: "Diagnostics"),
                        systemImage: "stethoscope"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    IntegrationsView(initialScope: .attention)
                } label: {
                    GlassSurfaceShortcutChip(
                        title: String(localized: "Integrations"),
                        systemImage: "square.3.layers.3d.down.forward",
                        accent: integrationIssueCount > 0 ? .red : .white,
                        badgeText: integrationIssueCount > 0 ? String(localized: "\(integrationIssueCount) issues") : nil
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: OnCallRoute.sessionsAttention) {
                    GlassSurfaceShortcutChip(
                        title: String(localized: "Sessions"),
                        systemImage: "rectangle.stack",
                        accent: vm.sessionAttentionCount > 0 ? .orange : .white,
                        badgeText: vm.sessionAttentionCount > 0 ? String(localized: "\(vm.sessionAttentionCount) hotspots") : nil
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    CommsView(api: deps.apiClient)
                } label: {
                    GlassSurfaceShortcutChip(
                        title: String(localized: "Comms"),
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    SettingsView()
                } label: {
                    GlassSurfaceShortcutChip(
                        title: String(localized: "Settings"),
                        systemImage: "gearshape"
                    )
                }
                .buttonStyle(.plain)

                ShareLink(item: handoffText) {
                    GlassSurfaceShortcutChip(
                        title: String(localized: "Share Handoff"),
                        systemImage: "square.and.arrow.up"
                    )
                }
                .buttonStyle(.plain)
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

private struct StandbySnapshotCard: View {
    let toneLabel: String
    let criticalCount: Int
    let queueCount: Int
    let watchIssueCount: Int
    let mutedAlertCount: Int
    let pendingFollowUpCount: Int
    let approvalCount: Int
    let automationIssueCount: Int
    let integrationIssueCount: Int
    let isAcknowledged: Bool
    let checkInStatus: HandoffCheckInStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResponsiveAccessoryRow(verticalSpacing: 8) {
                Label("Standby Snapshot", systemImage: "rectangle.inset.filled")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            } accessory: {
                GlassCapsuleBadge(text: toneLabel, backgroundOpacity: 0.14)
            }

            Text(String(localized: "Standby keeps the top queue, muted pressure, and handoff follow-ups visible while the phone stays calm."))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 8) {
                GlassCapsuleBadge(
                    text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                    backgroundOpacity: criticalCount > 0 ? 0.18 : 0.10
                )
                GlassCapsuleBadge(
                    text: queueCount == 1 ? String(localized: "1 queued") : String(localized: "\(queueCount) queued"),
                    backgroundOpacity: 0.16
                )
                if watchIssueCount > 0 {
                    GlassCapsuleBadge(
                        text: watchIssueCount == 1 ? String(localized: "1 watch issue") : String(localized: "\(watchIssueCount) watch issues"),
                        backgroundOpacity: 0.14
                    )
                }
                if mutedAlertCount > 0 {
                    GlassCapsuleBadge(
                        text: mutedAlertCount == 1 ? String(localized: "1 muted") : String(localized: "\(mutedAlertCount) muted"),
                        backgroundOpacity: 0.12
                    )
                }
                if pendingFollowUpCount > 0 {
                    GlassCapsuleBadge(
                        text: pendingFollowUpCount == 1 ? String(localized: "1 follow-up open") : String(localized: "\(pendingFollowUpCount) follow-ups open"),
                        backgroundOpacity: 0.16
                    )
                }
                if approvalCount > 0 {
                    GlassCapsuleBadge(
                        text: approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                        backgroundOpacity: 0.18
                    )
                }
                if automationIssueCount > 0 {
                    GlassCapsuleBadge(
                        text: automationIssueCount == 1 ? String(localized: "1 automation issue") : String(localized: "\(automationIssueCount) automation issues"),
                        backgroundOpacity: 0.14
                    )
                }
                if integrationIssueCount > 0 {
                    GlassCapsuleBadge(
                        text: integrationIssueCount == 1 ? String(localized: "1 integration issue") : String(localized: "\(integrationIssueCount) integration issues"),
                        backgroundOpacity: 0.16
                    )
                }
                if let checkInStatus {
                    GlassCapsuleBadge(text: checkInStatus.state.label, backgroundOpacity: 0.16)
                }
                if isAcknowledged {
                    GlassCapsuleBadge(text: String(localized: "Acknowledged"), backgroundOpacity: 0.12)
                }
            }
        }
        .padding(18)
        .glassPanel(fillOpacity: 0.09, cornerRadius: 22)
    }
}

private struct StandbyGlanceInventoryCard: View {
    let visibleCount: Int
    let totalCount: Int
    let criticalCount: Int
    let warningCount: Int
    let advisoryCount: Int
    let mutedAlertCount: Int
    let followUpCount: Int
    let approvalCount: Int
    let isAcknowledged: Bool
    let checkInStatus: HandoffCheckInStatus?

    private var remainingCount: Int {
        max(totalCount - visibleCount, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: detailLine,
                verticalPadding: 2
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: visibleCount == 1 ? String(localized: "1 card in view") : String(localized: "\(visibleCount) cards in view"),
                        tone: .neutral
                    )
                    if isAcknowledged {
                        PresentationToneBadge(text: String(localized: "Acknowledged"), tone: .positive)
                    }
                    if let checkInStatus {
                        PresentationToneBadge(text: checkInStatus.state.label, tone: checkInStatus.state.tone)
                    }
                }
            }

            MonitoringFactsRow(
                factsColor: .white.opacity(0.72)
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Glance inventory"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Text(String(localized: "The top standby slice stays compact so queue pressure, muted alerts, and follow-ups remain readable on a locked-down phone."))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: remainingCount == 0
                        ? String(localized: "Top slice is full")
                        : String(localized: "\(remainingCount) lower cards"),
                    tone: remainingCount == 0 ? .positive : .warning
                )
            } facts: {
                Label(
                    totalCount == 1 ? String(localized: "1 queued card") : String(localized: "\(totalCount) queued cards"),
                    systemImage: "rectangle.stack"
                )
                if criticalCount > 0 {
                    Label(
                        criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                        systemImage: "exclamationmark.octagon"
                    )
                }
                if warningCount > 0 {
                    Label(
                        warningCount == 1 ? String(localized: "1 warning") : String(localized: "\(warningCount) warnings"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if advisoryCount > 0 {
                    Label(
                        advisoryCount == 1 ? String(localized: "1 advisory") : String(localized: "\(advisoryCount) advisories"),
                        systemImage: "bell"
                    )
                }
                if mutedAlertCount > 0 {
                    Label(
                        mutedAlertCount == 1 ? String(localized: "1 muted alert") : String(localized: "\(mutedAlertCount) muted alerts"),
                        systemImage: "bell.slash"
                    )
                }
                if followUpCount > 0 {
                    Label(
                        followUpCount == 1 ? String(localized: "1 follow-up open") : String(localized: "\(followUpCount) follow-ups open"),
                        systemImage: "checklist.unchecked"
                    )
                }
                if approvalCount > 0 {
                    Label(
                        approvalCount == 1 ? String(localized: "1 pending approval") : String(localized: "\(approvalCount) pending approvals"),
                        systemImage: "checkmark.shield"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if visibleCount == totalCount {
            return visibleCount == 1
                ? String(localized: "At a Glance is showing the only live standby card.")
                : String(localized: "At a Glance is showing all \(visibleCount) live standby cards.")
        }
        return String(localized: "At a Glance is showing \(visibleCount) of \(totalCount) live standby cards.")
    }

    private var detailLine: String {
        remainingCount == 0
            ? String(localized: "Nothing is hidden below the fold, so the standby queue is fully represented in the glance deck.")
            : String(localized: "The glance deck is holding the sharpest standby slice while \(remainingCount) lower-priority cards stay below.")
    }
}

private struct StandbyWatchlistInventoryCard: View {
    let items: [AgentAttentionItem]
    let visibleCount: Int
    let totalPinnedCount: Int

    private var quietPinnedCount: Int {
        max(totalPinnedCount - items.count, 0)
    }

    private var runningCount: Int {
        items.filter { $0.agent.isRunning }.count
    }

    private var authIssueCount: Int {
        items.filter(\.hasAuthIssue).count
    }

    private var staleCount: Int {
        items.filter(\.isStale).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: detailLine,
                verticalPadding: 2
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: visibleCount == 1 ? String(localized: "1 pinned agent in view") : String(localized: "\(visibleCount) pinned agents in view"),
                        tone: .neutral
                    )
                    if quietPinnedCount > 0 {
                        PresentationToneBadge(
                            text: quietPinnedCount == 1 ? String(localized: "1 quiet pin") : String(localized: "\(quietPinnedCount) quiet pins"),
                            tone: .positive
                        )
                    }
                    if authIssueCount > 0 {
                        PresentationToneBadge(
                            text: authIssueCount == 1 ? String(localized: "1 auth issue") : String(localized: "\(authIssueCount) auth issues"),
                            tone: .critical
                        )
                    }
                }
            }

            MonitoringFactsRow(
                factsColor: .white.opacity(0.72)
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Pinned watch inventory"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Text(String(localized: "Pinned agents remain visible here even when standby is otherwise calm and most drilldowns stay collapsed."))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: items.count == 1 ? String(localized: "1 active watch") : String(localized: "\(items.count) active watches"),
                    tone: .warning
                )
            } facts: {
                Label(
                    totalPinnedCount == 1 ? String(localized: "1 pinned agent") : String(localized: "\(totalPinnedCount) pinned agents"),
                    systemImage: "star"
                )
                if runningCount > 0 {
                    Label(
                        runningCount == 1 ? String(localized: "1 running") : String(localized: "\(runningCount) running"),
                        systemImage: "play.circle"
                    )
                }
                if staleCount > 0 {
                    Label(
                        staleCount == 1 ? String(localized: "1 stale") : String(localized: "\(staleCount) stale"),
                        systemImage: "clock.badge.exclamationmark"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if visibleCount == items.count {
            return items.count == 1
                ? String(localized: "Pinned watchlist is showing the only active standby watch.")
                : String(localized: "Pinned watchlist is showing all \(items.count) active standby watches.")
        }
        return String(localized: "Pinned watchlist is showing \(visibleCount) of \(items.count) active standby watches.")
    }

    private var detailLine: String {
        quietPinnedCount == 0
            ? String(localized: "Every pinned agent currently has some live pressure, so this watchlist row carries the full local watch surface.")
            : String(localized: "\(quietPinnedCount) pinned agents are quiet right now, so the watchlist row stays focused on the agents with live standby pressure.")
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

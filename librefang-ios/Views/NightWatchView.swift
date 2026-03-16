import SwiftUI

private enum NightWatchTone {
    case calm
    case watching
    case elevated
    case critical

    var label: String {
        switch self {
        case .calm:
            String(localized: "Calm")
        case .watching:
            String(localized: "Watching")
        case .elevated:
            String(localized: "Elevated")
        case .critical:
            String(localized: "Critical")
        }
    }

    var color: Color {
        switch self {
        case .calm:
            .green
        case .watching:
            .blue
        case .elevated:
            .orange
        case .critical:
            .red
        }
    }

    var gradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .calm:
            colors = [Color(red: 0.07, green: 0.15, blue: 0.12), Color(red: 0.03, green: 0.07, blue: 0.08)]
        case .watching:
            colors = [Color(red: 0.05, green: 0.11, blue: 0.18), Color(red: 0.03, green: 0.05, blue: 0.10)]
        case .elevated:
            colors = [Color(red: 0.18, green: 0.11, blue: 0.05), Color(red: 0.06, green: 0.04, blue: 0.06)]
        case .critical:
            colors = [Color(red: 0.20, green: 0.06, blue: 0.07), Color(red: 0.06, green: 0.03, blue: 0.07)]
        }

        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct NightWatchView: View {
    @Environment(\.dependencies) private var deps

    private var vm: DashboardViewModel { deps.dashboardViewModel }
    private var incidentStateStore: IncidentStateStore { deps.incidentStateStore }
    private var watchlistStore: AgentWatchlistStore { deps.agentWatchlistStore }
    private var focusStore: OnCallFocusStore { deps.onCallFocusStore }

    private var visibleAlerts: [MonitoringAlertItem] {
        incidentStateStore.visibleAlerts(from: vm.monitoringAlerts)
    }

    private var mutedAlertCount: Int {
        incidentStateStore.activeMutedAlerts(from: vm.monitoringAlerts).count
    }

    private var watchedAgents: [Agent] {
        watchlistStore.watchedAgents(from: vm.agents)
    }

    private var watchedAgentIDs: Set<String> {
        Set(watchedAgents.map(\.id))
    }

    private var watchedAttentionItems: [AgentAttentionItem] {
        watchedAgents
            .map { vm.attentionItem(for: $0) }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return lhs.severity > rhs.severity
                }
                return lhs.agent.name.localizedCompare(rhs.agent.name) == .orderedAscending
            }
    }

    private var allPriorityItems: [OnCallPriorityItem] {
        vm.onCallPriorityItems(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            handoffCheckInStatus: deps.onCallHandoffStore.latestCheckInStatus,
            handoffFollowUpStatuses: deps.onCallHandoffStore.latestFollowUpStatuses
        )
    }

    private var priorityItems: [OnCallPriorityItem] {
        switch focusStore.mode {
        case .balanced:
            return allPriorityItems
        case .criticalOnly:
            return allPriorityItems.filter { $0.severity == .critical }
        case .watchlistFirst:
            return allPriorityItems.sorted { lhs, rhs in
                let lhsBoost = watchPriorityBoost(for: lhs)
                let rhsBoost = watchPriorityBoost(for: rhs)
                if lhsBoost != rhsBoost {
                    return lhsBoost > rhsBoost
                }
                if lhs.rank != rhs.rank {
                    return lhs.rank > rhs.rank
                }
                return lhs.title.localizedCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private var primaryItems: [OnCallPriorityItem] {
        Array(priorityItems.prefix(3))
    }

    private var secondaryItems: [OnCallPriorityItem] {
        Array(priorityItems.dropFirst(3).prefix(3))
    }
    private var activeWatchedItems: [AgentAttentionItem] {
        watchedAttentionItems.filter { $0.severity > 0 }
    }
    private var advisoryCount: Int {
        priorityItems.filter { $0.severity == .advisory }.count
    }
    private var warningCount: Int {
        priorityItems.filter { $0.severity == .warning }.count
    }
    private var watchedQueueCount: Int {
        priorityItems.filter { isWatchedRoute($0.route) }.count
    }
    private var criticalCount: Int {
        priorityItems.filter { $0.severity == .critical }.count
    }
    private var watchIssueCount: Int {
        activeWatchedItems.count
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
    private var nightWatchSectionCount: Int {
        [
            true,
            !primaryItems.isEmpty,
            !secondaryItems.isEmpty,
            !activeWatchedItems.isEmpty
        ]
        .filter { $0 }
        .count
    }
    private var nightWatchSectionPreviewTitles: [String] {
        var sections: [String] = [String(localized: "Hero")]
        if !primaryItems.isEmpty {
            sections.append(String(localized: "Primary Queue"))
        }
        if !secondaryItems.isEmpty {
            sections.append(String(localized: "Secondary Queue"))
        }
        if !activeWatchedItems.isEmpty {
            sections.append(String(localized: "Watchlist"))
        }
        sections.append(String(localized: "Surfaces"))
        return sections
    }

    private var tone: NightWatchTone {
        if primaryItems.contains(where: { $0.severity == .critical }) {
            return .critical
        }
        if primaryItems.contains(where: { $0.severity == .warning }) || vm.pendingApprovalCount > 0 {
            return .elevated
        }
        if !primaryItems.isEmpty || mutedAlertCount > 0 || !watchedAttentionItems.isEmpty {
            return .watching
        }
        return .calm
    }

    private var digestLine: String {
        vm.onCallDigestLine(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            mutedAlertCount: mutedAlertCount,
            isAcknowledged: incidentStateStore.isCurrentSnapshotAcknowledged(alerts: vm.monitoringAlerts),
            handoffCheckInStatus: deps.onCallHandoffStore.latestCheckInStatus,
            handoffFollowUpStatuses: deps.onCallHandoffStore.latestFollowUpStatuses
        )
    }

    private var handoffText: String {
        vm.onCallHandoffText(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            mutedAlertCount: mutedAlertCount,
            isAcknowledged: incidentStateStore.isCurrentSnapshotAcknowledged(alerts: vm.monitoringAlerts),
            handoffCheckInStatus: deps.onCallHandoffStore.latestCheckInStatus,
            handoffFollowUpStatuses: deps.onCallHandoffStore.latestFollowUpStatuses
        )
    }

    private var focusSummary: String {
        switch focusStore.mode {
        case .balanced:
            String(localized: "Balanced triage keeps live alerts, approvals, watchlist issues, and session hotspots together.")
        case .criticalOnly:
            String(localized: "Critical-only mode suppresses lower-severity noise so the top screen stays quiet until something truly urgent lands.")
        case .watchlistFirst:
            String(localized: "Watchlist-first mode promotes pinned agents above the rest of the queue.")
        }
    }

    var body: some View {
        ZStack {
            tone.gradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    controlDeckCard
                    primaryQueueCard
                    secondaryQueueCard
                    watchlistCard
                    surfaceDeckCard
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Night Watch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            toolbarContent
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
    private var heroCard: some View {
        NightWatchHeroCard(
            tone: tone,
            queueCount: priorityItems.count,
            criticalCount: criticalCount,
            watchCount: watchIssueCount,
            summary: digestLine,
            focusModeLabel: focusStore.mode.label,
            lastRefresh: vm.lastRefresh,
            acknowledgedAt: incidentStateStore.currentAcknowledgementDate(for: vm.monitoringAlerts),
            isAcknowledged: incidentStateStore.isCurrentSnapshotAcknowledged(alerts: vm.monitoringAlerts),
            onAcknowledge: {
                incidentStateStore.acknowledgeCurrentSnapshot(alerts: vm.monitoringAlerts)
            },
            onClearAcknowledgement: {
                incidentStateStore.clearAcknowledgement()
            }
        )
    }

    private var snapshotCard: some View {
        NightWatchSnapshotCard(
            focusModeLabel: focusStore.mode.label,
            preferredSurfaceLabel: focusStore.preferredSurface.label,
            queueCount: priorityItems.count,
            criticalCount: criticalCount,
            approvalCount: vm.pendingApprovalCount,
            watchIssueCount: watchIssueCount,
            mutedAlertCount: mutedAlertCount,
            pendingFollowUpCount: pendingFollowUpCount,
            automationIssueCount: automationIssueCount,
            integrationIssueCount: integrationIssueCount,
            checkInStatus: checkInStatus
        )
    }

    private var controlDeckCard: some View {
        VStack(spacing: 12) {
            snapshotCard
            signalFactsCard
            NightWatchSectionInventoryDeck(
                sectionCount: nightWatchSectionCount,
                primaryQueueCount: primaryItems.count,
                secondaryQueueCount: secondaryItems.count,
                watchCount: activeWatchedItems.count,
                pendingFollowUpCount: pendingFollowUpCount,
                approvalCount: vm.pendingApprovalCount,
                criticalCount: criticalCount,
                automationIssueCount: automationIssueCount,
                integrationIssueCount: integrationIssueCount
            )
            if !nightWatchSectionPreviewTitles.isEmpty {
                MonitoringSectionPreviewDeck(
                    title: String(localized: "Section Preview"),
                    detail: String(localized: "Keep the next night-watch stacks visible before the primary queue, secondary queue, and watchlist cards expand."),
                    sectionTitles: nightWatchSectionPreviewTitles,
                    tone: criticalCount > 0 ? .critical : ((warningCount > 0 || watchIssueCount > 0) ? .warning : .neutral),
                    maxVisibleSections: 5
                )
            }
            NightWatchSupportPressureDeck(
                mutedAlertCount: mutedAlertCount,
                pendingFollowUpCount: pendingFollowUpCount,
                approvalCount: vm.pendingApprovalCount,
                automationIssueCount: automationIssueCount,
                integrationIssueCount: integrationIssueCount,
                checkInStatus: checkInStatus
            )
            NightWatchSupportCoverageDeck(
                totalWatchedCount: watchedAgents.count,
                activeWatchCount: activeWatchedItems.count,
                watchedQueueCount: watchedQueueCount,
                focusModeLabel: focusStore.mode.label,
                preferredSurfaceLabel: focusStore.preferredSurface.label,
                showsMutedSummary: focusStore.showsMutedSummary,
                checkInStatus: checkInStatus
            )
            NightWatchActionReadinessDeck(
                queueCount: priorityItems.count,
                criticalCount: criticalCount,
                isAcknowledged: incidentStateStore.isCurrentSnapshotAcknowledged(alerts: vm.monitoringAlerts),
                pendingFollowUpCount: pendingFollowUpCount,
                approvalCount: vm.pendingApprovalCount,
                focusModeLabel: focusStore.mode.label,
                checkInStatus: checkInStatus
            )
            NightWatchFocusCoverageDeck(
                queueCount: priorityItems.count,
                primaryQueueCount: primaryItems.count,
                secondaryQueueCount: secondaryItems.count,
                criticalCount: criticalCount,
                watchIssueCount: watchIssueCount,
                pendingFollowUpCount: pendingFollowUpCount,
                automationIssueCount: automationIssueCount,
                integrationIssueCount: integrationIssueCount,
                focusModeLabel: focusStore.mode.label,
                checkInStatus: checkInStatus
            )
            NightWatchWorkstreamCoverageDeck(
                primaryQueueCount: primaryItems.count,
                secondaryQueueCount: secondaryItems.count,
                watchCount: activeWatchedItems.count,
                mutedAlertCount: mutedAlertCount,
                pendingFollowUpCount: pendingFollowUpCount,
                approvalCount: vm.pendingApprovalCount,
                automationIssueCount: automationIssueCount,
                integrationIssueCount: integrationIssueCount
            )
            NightWatchQueueCoverageDeck(
                criticalCount: criticalCount,
                warningCount: warningCount,
                advisoryCount: advisoryCount,
                approvalCount: vm.pendingApprovalCount,
                watchIssueCount: watchIssueCount,
                pendingFollowUpCount: pendingFollowUpCount
            )
        }
    }

    private var signalFactsCard: some View {
        NightWatchSectionCard(
            title: String(localized: "Signal Facts"),
            detail: String(localized: "Keep focus mode, queue size, and current pressure visible before opening deeper night-duty surfaces.")
        ) {
            FlowLayout(spacing: 8) {
                GlassCapsuleBadge(text: focusStore.mode.label, backgroundOpacity: 0.16)
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

            if focusStore.showsMutedSummary, mutedAlertCount > 0 {
                Divider()
                    .overlay(.white.opacity(0.08))

                ResponsiveIconDetailRow(horizontalAlignment: .top, horizontalSpacing: 10, verticalSpacing: 8) {
                    Image(systemName: "bell.slash.fill")
                        .foregroundStyle(.orange)
                } detail: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            mutedAlertCount == 1
                                ? String(localized: "1 alert muted locally")
                                : String(localized: "\(mutedAlertCount) alerts muted locally")
                        )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(String(localized: "Muted alerts stay out of the queue until you unmute them in incidents."))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .glassPanel(fillOpacity: 0.07, cornerRadius: 14)
            }
        }
    }

    @ViewBuilder
    private var primaryQueueCard: some View {
        if primaryItems.isEmpty {
            NightWatchCalmCard(
                title: calmStateTitle,
                detail: calmStateDetail
            )
        } else {
            NightWatchSectionCard(title: String(localized: "Immediate Queue"), detail: focusSummary) {
                NightWatchQueueInventoryCard(
                    visibleCount: primaryItems.count,
                    totalCount: priorityItems.count,
                    criticalCount: criticalCount,
                    warningCount: warningCount,
                    advisoryCount: advisoryCount,
                    watchedQueueCount: watchedQueueCount,
                    pendingApprovalCount: vm.pendingApprovalCount
                )

                ForEach(primaryItems) { item in
                    NavigationLink(value: item.route) {
                        NightWatchPriorityCard(
                            item: item,
                            isWatched: isWatchedRoute(item.route),
                            emphasis: .primary
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var secondaryQueueCard: some View {
        if !secondaryItems.isEmpty {
            NightWatchSectionCard(
                title: String(localized: "Follow-up Queue"),
                detail: String(localized: "Lower on the page, but still above the fold for one-hand triage.")
            ) {
                ForEach(secondaryItems) { item in
                    NavigationLink(value: item.route) {
                        NightWatchPriorityCard(
                            item: item,
                            isWatched: isWatchedRoute(item.route),
                            emphasis: .secondary
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var watchlistCard: some View {
        if !activeWatchedItems.isEmpty && focusStore.mode != .criticalOnly {
            NightWatchSectionCard(
                title: String(localized: "Pinned Agents"),
                detail: String(localized: "Locally watched on this iPhone so they stay visible during on-call.")
            ) {
                NightWatchWatchlistInventoryCard(
                    items: activeWatchedItems,
                    totalWatchedCount: watchedAgents.count
                )

                ForEach(activeWatchedItems.prefix(3)) { item in
                    NavigationLink(value: OnCallRoute.agent(item.agent.id)) {
                        NightWatchWatchlistRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var surfaceDeckCard: some View {
        NightWatchSectionCard(
            title: String(localized: "Controls"),
            detail: String(localized: "Keep display controls and the next night-duty drills in one deck.")
        ) {
            NightWatchRouteInventoryCard(
                primaryRouteCount: 5,
                supportRouteCount: 8,
                queueCount: priorityItems.count,
                criticalCount: criticalCount,
                approvalCount: vm.pendingApprovalCount,
                sessionCount: vm.sessionAttentionCount,
                eventCount: vm.recentCriticalAuditCount,
                automationIssueCount: automationIssueCount,
                integrationIssueCount: integrationIssueCount
            )

            NightWatchSurfaceGroupLabel(title: String(localized: "Display Controls"))

            NightWatchControlMenuRow(
                title: String(localized: "Queue Mode"),
                detail: focusStore.mode.summary
            ) {
                Menu {
                    ForEach(OnCallFocusMode.allCases) { option in
                        Button(option.label) {
                            focusStore.mode = option
                        }
                    }
                } label: {
                    GlassCapsuleBadge(text: focusStore.mode.label, backgroundOpacity: 0.12)
                }
            }

            NightWatchControlMenuRow(
                title: String(localized: "Critical Banner"),
                detail: focusStore.preferredSurface.summary
            ) {
                Menu {
                    ForEach(OnCallSurfacePreference.allCases) { option in
                        Button(option.label) {
                            focusStore.preferredSurface = option
                        }
                    }
                } label: {
                    GlassCapsuleBadge(text: focusStore.preferredSurface.label, backgroundOpacity: 0.12)
                }
            }

            ResponsiveAccessoryRow(horizontalAlignment: .top, verticalSpacing: 8, spacerMinLength: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Muted Summary"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(
                        focusStore.showsMutedSummary
                            ? String(localized: "Muted alerts stay visible in the signal deck.")
                            : String(localized: "Muted alerts stay hidden until you open incidents or re-enable the summary.")
                    )
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
                }
            } accessory: {
                Toggle(isOn: Binding(
                    get: { focusStore.showsMutedSummary },
                    set: { focusStore.showsMutedSummary = $0 }
                )) {
                    EmptyView()
                }
                .labelsHidden()
                .tint(.orange)
            }

            Divider()
                .overlay(.white.opacity(0.08))

            NightWatchSurfaceGroupLabel(title: String(localized: "Primary"))

            FlowLayout(spacing: 8) {
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

                NavigationLink(value: OnCallRoute.sessionsAttention) {
                    GlassSurfaceShortcutChip(
                        title: String(localized: "Sessions"),
                        systemImage: "rectangle.stack",
                        accent: vm.sessionAttentionCount > 0 ? .orange : .white,
                        badgeText: vm.sessionAttentionCount > 0 ? String(localized: "\(vm.sessionAttentionCount) hotspots") : nil
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: OnCallRoute.eventsCritical) {
                    GlassSurfaceShortcutChip(
                        title: String(localized: "Critical Events"),
                        systemImage: "list.bullet.rectangle.portrait",
                        accent: vm.recentCriticalAuditCount > 0 ? .red : .white,
                        badgeText: vm.recentCriticalAuditCount > 0 ? String(localized: "\(vm.recentCriticalAuditCount) critical") : nil
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

            NightWatchSurfaceGroupLabel(title: String(localized: "Support"))

            FlowLayout(spacing: 8) {
                NavigationLink {
                    StandbyDigestView()
                } label: {
                    GlassSurfaceShortcutChip(
                        title: String(localized: "Standby"),
                        systemImage: "rectangle.inset.filled"
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
                    CommsView(api: deps.apiClient)
                } label: {
                    GlassSurfaceShortcutChip(
                        title: String(localized: "Comms"),
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    DiagnosticsView()
                } label: {
                    GlassSurfaceShortcutChip(
                        title: String(localized: "Diagnostics"),
                        systemImage: "stethoscope"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: OnCallRoute.integrationsAttention) {
                    GlassSurfaceShortcutChip(
                        title: String(localized: "Integrations"),
                        systemImage: "square.3.layers.3d.down.forward",
                        accent: integrationIssueCount > 0 ? .red : .white,
                        badgeText: integrationIssueCount > 0 ? String(localized: "\(integrationIssueCount) issues") : nil
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: OnCallRoute.automation) {
                    GlassSurfaceShortcutChip(
                        title: String(localized: "Automation"),
                        systemImage: "flowchart",
                        accent: automationIssueCount > 0 ? .orange : .white,
                        badgeText: automationIssueCount > 0 ? String(localized: "\(automationIssueCount) issues") : nil
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
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Picker("Display Mode", selection: Binding(
                    get: { focusStore.mode },
                    set: { focusStore.mode = $0 }
                )) {
                    ForEach(OnCallFocusMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Picker("Critical Banner", selection: Binding(
                    get: { focusStore.preferredSurface },
                    set: { focusStore.preferredSurface = $0 }
                )) {
                    ForEach(OnCallSurfacePreference.allCases) { surface in
                        Text(surface.label).tag(surface)
                    }
                }

                Toggle("Show muted summary", isOn: Binding(
                    get: { focusStore.showsMutedSummary },
                    set: { focusStore.showsMutedSummary = $0 }
                ))
            } label: {
                Image(systemName: "slider.horizontal.3")
            }

            NavigationLink {
                StandbyDigestView()
            } label: {
                Image(systemName: "rectangle.inset.filled")
            }

            NavigationLink(value: OnCallRoute.incidents) {
                Image(systemName: "bell.badge")
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
                queueCount: allPriorityItems.count,
                criticalCount: visibleAlerts.filter { $0.severity == .critical }.count,
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

    private func watchPriorityBoost(for item: OnCallPriorityItem) -> Int {
        switch item.route {
        case .agent(let id):
            return watchedAgentIDs.contains(id) ? 100 : 0
        case .sessionsSearch(let query):
            return watchedAgentIDs.contains(query) ? 90 : 0
        case .eventsSearch(let query):
            return watchedAgentIDs.contains(query) ? 85 : 0
        default:
            return 0
        }
    }

    private func isWatchedRoute(_ route: OnCallRoute) -> Bool {
        switch route {
        case .agent(let id):
            return watchedAgentIDs.contains(id)
        case .eventsSearch(let query):
            return watchedAgentIDs.contains(query)
        case .sessionsSearch(let query):
            return watchedAgentIDs.contains(query)
        default:
            return false
        }
    }

    private var calmStateTitle: String {
        if focusStore.mode == .criticalOnly {
            return String(localized: "No Critical Incidents")
        }
        return String(localized: "Queue Is Quiet")
    }

    private var calmStateDetail: String {
        if focusStore.mode == .criticalOnly, !allPriorityItems.isEmpty {
            return String(localized: "Lower-severity items still exist in the broader on-call queue, but critical-only mode is intentionally suppressing them here.")
        }
        return String(localized: "No urgent work is currently surfacing on this phone. Pull to refresh or open the full on-call queue for more detail.")
    }
}

private struct NightWatchHeroCard: View {
    let tone: NightWatchTone
    let queueCount: Int
    let criticalCount: Int
    let watchCount: Int
    let summary: String
    let focusModeLabel: String
    let lastRefresh: Date?
    let acknowledgedAt: Date?
    let isAcknowledged: Bool
    let onAcknowledge: () -> Void
    let onClearAcknowledgement: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ResponsiveAccessoryRow(horizontalAlignment: .top, verticalSpacing: 10, spacerMinLength: 12) {
                headerSummary
            } accessory: {
                headerStatus
            }

            LazyVGrid(columns: countColumns, alignment: .leading, spacing: 10) {
                NightWatchCountPill(value: queueCount, label: String(localized: "Queued"))
                NightWatchCountPill(value: criticalCount, label: String(localized: "Critical"))
                NightWatchCountPill(value: watchCount, label: String(localized: "Watched"))
            }

            ResponsiveInlineGroup(horizontalSpacing: 10, verticalSpacing: 10) {
                if let acknowledgementAction {
                    acknowledgementAction
                }
                fullQueueButton
            }

            ResponsiveInlineGroup(horizontalSpacing: 12, verticalSpacing: 6) {
                acknowledgementFootnote
                refreshFootnote
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.68))
        }
        .padding(18)
        .glassPanel(fillStyle: .black, fillOpacity: 0.26, cornerRadius: 20, strokeOpacity: 0.08)
    }

    private var headerSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Night Watch")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassCapsuleBadge(text: tone.label, backgroundOpacity: 0.14, horizontalPadding: 10, verticalPadding: 6)
            Text(focusModeLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.74))
        }
        .frame(maxWidth: .infinity, alignment: horizontalSizeClass == .compact ? .leading : .trailing)
    }

    private var countColumns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    private var acknowledgementAction: AnyView? {
        if isAcknowledged {
            return AnyView(
                Button(action: onClearAcknowledgement) {
                    Text(String(localized: "Clear Ack"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassCapsuleButtonStyle(fillOpacity: 0.16))
            )
        }

        if queueCount > 0 {
            return AnyView(
                Button(action: onAcknowledge) {
                    Text(String(localized: "Acknowledge Snapshot"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassCapsuleButtonStyle(fillOpacity: 0.16))
            )
        }

        return nil
    }

    private var fullQueueButton: some View {
        NavigationLink {
            OnCallView()
        } label: {
            Text(String(localized: "Full Queue"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassCapsuleButtonStyle(fillOpacity: 0.10))
    }

    @ViewBuilder
    private var acknowledgementFootnote: some View {
        if let acknowledgedAt, isAcknowledged {
            Label {
                Text(String(localized: "Acknowledged \(acknowledgedAt.formatted(.relative(presentation: .named)))"))
            } icon: {
                Image(systemName: "checkmark.seal")
            }
        }
    }

    @ViewBuilder
    private var refreshFootnote: some View {
        if let lastRefresh {
            Label {
                Text(String(localized: "Refreshed \(lastRefresh.formatted(.relative(presentation: .named)))"))
            } icon: {
                Image(systemName: "clock")
            }
        }
    }
}

private struct NightWatchMutedSummaryCard: View {
    let mutedAlertCount: Int

    var body: some View {
        ResponsiveValueRow(
            horizontalAlignment: .top,
            horizontalSpacing: 10,
            verticalSpacing: 10,
            horizontalTextAlignment: .leading
        ) {
            iconLabel
        } value: {
            summaryBlock
        }
        .padding(14)
        .glassPanel(fillStyle: .black, fillOpacity: 0.22, cornerRadius: 16, strokeOpacity: 0.08)
    }

    private var iconLabel: some View {
        Image(systemName: "bell.slash.fill")
            .foregroundStyle(.orange)
    }

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(
                mutedAlertCount == 1
                    ? String(localized: "1 alert muted locally")
                    : String(localized: "\(mutedAlertCount) alerts muted locally")
            )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(String(localized: "Muted alerts stay out of the queue until you unmute them in Incidents."))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
        }
    }
}

private struct NightWatchSnapshotCard: View {
    let focusModeLabel: String
    let preferredSurfaceLabel: String
    let queueCount: Int
    let criticalCount: Int
    let approvalCount: Int
    let watchIssueCount: Int
    let mutedAlertCount: Int
    let pendingFollowUpCount: Int
    let automationIssueCount: Int
    let integrationIssueCount: Int
    let checkInStatus: HandoffCheckInStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResponsiveAccessoryRow(verticalSpacing: 8) {
                Label("Snapshot", systemImage: "waveform.path.ecg.rectangle")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            } accessory: {
                GlassCapsuleBadge(text: focusModeLabel, backgroundOpacity: 0.16)
            }

            Text(String(localized: "Night Watch keeps the current queue, follow-up pressure, and preferred surface visible before the deeper drilldowns."))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 8) {
                GlassCapsuleBadge(
                    text: queueCount == 1 ? String(localized: "1 queued") : String(localized: "\(queueCount) queued"),
                    backgroundOpacity: 0.16
                )
                GlassCapsuleBadge(
                    text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                    backgroundOpacity: criticalCount > 0 ? 0.18 : 0.10
                )
                if approvalCount > 0 {
                    GlassCapsuleBadge(
                        text: approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                        backgroundOpacity: 0.18
                    )
                }
                if watchIssueCount > 0 {
                    GlassCapsuleBadge(
                        text: watchIssueCount == 1 ? String(localized: "1 watch issue") : String(localized: "\(watchIssueCount) watch issues"),
                        backgroundOpacity: 0.16
                    )
                }
                if mutedAlertCount > 0 {
                    GlassCapsuleBadge(
                        text: mutedAlertCount == 1 ? String(localized: "1 muted") : String(localized: "\(mutedAlertCount) muted"),
                        backgroundOpacity: 0.14
                    )
                }
                if pendingFollowUpCount > 0 {
                    GlassCapsuleBadge(
                        text: pendingFollowUpCount == 1 ? String(localized: "1 follow-up open") : String(localized: "\(pendingFollowUpCount) follow-ups open"),
                        backgroundOpacity: 0.18
                    )
                }
                if automationIssueCount > 0 {
                    GlassCapsuleBadge(
                        text: automationIssueCount == 1 ? String(localized: "1 automation issue") : String(localized: "\(automationIssueCount) automation issues"),
                        backgroundOpacity: 0.16
                    )
                }
                if integrationIssueCount > 0 {
                    GlassCapsuleBadge(
                        text: integrationIssueCount == 1 ? String(localized: "1 integration issue") : String(localized: "\(integrationIssueCount) integration issues"),
                        backgroundOpacity: 0.18
                    )
                }
                if let checkInStatus {
                    GlassCapsuleBadge(text: checkInStatus.state.label, backgroundOpacity: 0.18)
                }
                GlassCapsuleBadge(text: preferredSurfaceLabel, backgroundOpacity: 0.12)
            }
        }
        .padding(16)
        .glassPanel(fillStyle: .black, fillOpacity: 0.22, cornerRadius: 18, strokeOpacity: 0.08)
    }
}

private struct NightWatchQueueInventoryCard: View {
    let visibleCount: Int
    let totalCount: Int
    let criticalCount: Int
    let warningCount: Int
    let advisoryCount: Int
    let watchedQueueCount: Int
    let pendingApprovalCount: Int

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
                        text: visibleCount == 1 ? String(localized: "1 item in view") : String(localized: "\(visibleCount) items in view"),
                        tone: .neutral
                    )
                    if criticalCount > 0 {
                        PresentationToneBadge(
                            text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                            tone: .critical
                        )
                    }
                    if watchedQueueCount > 0 {
                        PresentationToneBadge(
                            text: watchedQueueCount == 1 ? String(localized: "1 watch-promoted") : String(localized: "\(watchedQueueCount) watch-promoted"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow(
                factsColor: .white.opacity(0.72)
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Queue inventory"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Text(String(localized: "This compact slice keeps the top queue visible before you scroll into the deeper follow-up queue."))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: remainingCount == 0
                        ? String(localized: "Top slice is full")
                        : String(localized: "\(remainingCount) more below"),
                    tone: remainingCount == 0 ? .positive : .warning
                )
            } facts: {
                Label(
                    totalCount == 1 ? String(localized: "1 queued item") : String(localized: "\(totalCount) queued items"),
                    systemImage: "tray.full"
                )
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
                if pendingApprovalCount > 0 {
                    Label(
                        pendingApprovalCount == 1 ? String(localized: "1 pending approval") : String(localized: "\(pendingApprovalCount) pending approvals"),
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
                ? String(localized: "Immediate Queue is showing the only live priority item.")
                : String(localized: "Immediate Queue is showing all \(visibleCount) live priority items.")
        }
        return String(localized: "Immediate Queue is showing \(visibleCount) of \(totalCount) live priority items.")
    }

    private var detailLine: String {
        remainingCount == 0
            ? String(localized: "Nothing is hiding below the fold, so the current queue is fully represented in the top card stack.")
            : String(localized: "The top card stack is holding the sharpest slice while \(remainingCount) lower-priority items stay in the follow-up queue.")
    }
}

private struct NightWatchWatchlistInventoryCard: View {
    let items: [AgentAttentionItem]
    let totalWatchedCount: Int

    private var visibleCount: Int {
        min(items.count, 3)
    }

    private var runningCount: Int {
        items.filter { $0.agent.isRunning }.count
    }

    private var quietWatchedCount: Int {
        max(totalWatchedCount - items.count, 0)
    }

    private var authIssueCount: Int {
        items.filter(\.hasAuthIssue).count
    }

    private var staleCount: Int {
        items.filter(\.isStale).count
    }

    private var sessionPressureCount: Int {
        items.filter(\.sessionPressure).count
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
                    if quietWatchedCount > 0 {
                        PresentationToneBadge(
                            text: quietWatchedCount == 1 ? String(localized: "1 quiet pin") : String(localized: "\(quietWatchedCount) quiet pins"),
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
                    Text(String(localized: "Pinned agents stay visible here even when the rest of the queue is re-ranked for one-hand triage."))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: items.count == 1 ? String(localized: "1 agent needs attention") : String(localized: "\(items.count) agents need attention"),
                    tone: .warning
                )
            } facts: {
                Label(
                    totalWatchedCount == 1 ? String(localized: "1 pinned agent") : String(localized: "\(totalWatchedCount) pinned agents"),
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
                if sessionPressureCount > 0 {
                    Label(
                        sessionPressureCount == 1 ? String(localized: "1 session hotspot") : String(localized: "\(sessionPressureCount) session hotspots"),
                        systemImage: "rectangle.stack.badge.person.crop"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if visibleCount == items.count {
            return items.count == 1
                ? String(localized: "Pinned watchlist is showing the only active watched agent.")
                : String(localized: "Pinned watchlist is showing all \(items.count) active watched agents.")
        }
        return String(localized: "Pinned watchlist is showing \(visibleCount) of \(items.count) active watched agents.")
    }

    private var detailLine: String {
        quietWatchedCount == 0
            ? String(localized: "Every pinned agent is currently active, so the watchlist row is carrying the full local watch surface.")
            : String(localized: "\(quietWatchedCount) pinned agents are quiet right now, so this row stays focused on the agents with live pressure.")
    }
}

private struct NightWatchRouteInventoryCard: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let queueCount: Int
    let criticalCount: Int
    let approvalCount: Int
    let sessionCount: Int
    let eventCount: Int
    let automationIssueCount: Int
    let integrationIssueCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Night Watch is grouping \(primaryRouteCount) primary routes and \(supportRouteCount) support drills in one control rail."),
                detail: String(localized: "Display settings stay first, then the route rail splits immediate night-duty exits from slower support surfaces."),
                verticalPadding: 2
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
                }
            }

            MonitoringFactsRow(factsColor: .white.opacity(0.72)) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Route inventory"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Text(String(localized: "Primary routes keep the next live moves above the slower runtime, diagnostics, and settings drills."))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.66))
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

private struct NightWatchSectionInventoryDeck: View {
    let sectionCount: Int
    let primaryQueueCount: Int
    let secondaryQueueCount: Int
    let watchCount: Int
    let pendingFollowUpCount: Int
    let approvalCount: Int
    let criticalCount: Int
    let automationIssueCount: Int
    let integrationIssueCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: detailLine,
                verticalPadding: 2
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: sectionCount == 1 ? String(localized: "1 live section") : String(localized: "\(sectionCount) live sections"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: primaryQueueCount == 1 ? String(localized: "1 primary card") : String(localized: "\(primaryQueueCount) primary cards"),
                        tone: primaryQueueCount > 0 ? .warning : .neutral
                    )
                    if secondaryQueueCount > 0 {
                        PresentationToneBadge(
                            text: secondaryQueueCount == 1 ? String(localized: "1 secondary card") : String(localized: "\(secondaryQueueCount) secondary cards"),
                            tone: .neutral
                        )
                    }
                    if watchCount > 0 {
                        PresentationToneBadge(
                            text: watchCount == 1 ? String(localized: "1 watched item") : String(localized: "\(watchCount) watched items"),
                            tone: .caution
                        )
                    }
                }
            }

            MonitoringFactsRow(factsColor: .white.opacity(0.72)) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Section inventory"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Text(String(localized: "Keep queue depth, watch pressure, and supporting issue buckets visible before the display controls and route rails."))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                    tone: approvalCount > 0 ? .warning : .neutral
                )
            } facts: {
                Label(
                    criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                    systemImage: "exclamationmark.triangle"
                )
                if pendingFollowUpCount > 0 {
                    Label(
                        pendingFollowUpCount == 1 ? String(localized: "1 follow-up") : String(localized: "\(pendingFollowUpCount) follow-ups"),
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

    private var summaryLine: String {
        sectionCount == 1
            ? String(localized: "1 night-watch section is active below the hero snapshot.")
            : String(localized: "\(sectionCount) night-watch sections are active below the hero snapshot.")
    }

    private var detailLine: String {
        String(localized: "Priority cards, watchlist pressure, and support issue buckets stay summarized before the display controls and route rails take over.")
    }
}

private struct NightWatchQueueCoverageDeck: View {
    let criticalCount: Int
    let warningCount: Int
    let advisoryCount: Int
    let approvalCount: Int
    let watchIssueCount: Int
    let pendingFollowUpCount: Int

    var body: some View {
        NightWatchSectionCard(
            title: String(localized: "Queue Coverage"),
            detail: String(localized: "Keep severity mix and follow-up drag readable before the primary and secondary night queue cards.")
        ) {
            FlowLayout(spacing: 8) {
                if criticalCount > 0 {
                    GlassCapsuleBadge(
                        text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                        backgroundOpacity: 0.18
                    )
                }
                if warningCount > 0 {
                    GlassCapsuleBadge(
                        text: warningCount == 1 ? String(localized: "1 warning") : String(localized: "\(warningCount) warnings"),
                        backgroundOpacity: 0.14
                    )
                }
                if advisoryCount > 0 {
                    GlassCapsuleBadge(
                        text: advisoryCount == 1 ? String(localized: "1 advisory") : String(localized: "\(advisoryCount) advisories"),
                        backgroundOpacity: 0.10
                    )
                }
                if approvalCount > 0 {
                    GlassCapsuleBadge(
                        text: approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
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
                        text: pendingFollowUpCount == 1 ? String(localized: "1 follow-up") : String(localized: "\(pendingFollowUpCount) follow-ups"),
                        backgroundOpacity: 0.14
                    )
                }
            }
        }
    }
}

private struct NightWatchWorkstreamCoverageDeck: View {
    let primaryQueueCount: Int
    let secondaryQueueCount: Int
    let watchCount: Int
    let mutedAlertCount: Int
    let pendingFollowUpCount: Int
    let approvalCount: Int
    let automationIssueCount: Int
    let integrationIssueCount: Int

    var body: some View {
        NightWatchSectionCard(
            title: String(localized: "Workstream Coverage"),
            detail: String(localized: "Keep the primary queue, secondary queue, watchlist, and slower support lanes readable before the night-duty cards expand.")
        ) {
            FlowLayout(spacing: 8) {
                if primaryQueueCount > 0 {
                    GlassCapsuleBadge(
                        text: primaryQueueCount == 1 ? String(localized: "1 primary item") : String(localized: "\(primaryQueueCount) primary items"),
                        backgroundOpacity: 0.18
                    )
                }
                if secondaryQueueCount > 0 {
                    GlassCapsuleBadge(
                        text: secondaryQueueCount == 1 ? String(localized: "1 secondary item") : String(localized: "\(secondaryQueueCount) secondary items"),
                        backgroundOpacity: 0.12
                    )
                }
                if watchCount > 0 {
                    GlassCapsuleBadge(
                        text: watchCount == 1 ? String(localized: "1 watch row") : String(localized: "\(watchCount) watch rows"),
                        backgroundOpacity: 0.12
                    )
                }
                if supportCount > 0 {
                    GlassCapsuleBadge(
                        text: supportCount == 1 ? String(localized: "1 support lane") : String(localized: "\(supportCount) support lanes"),
                        backgroundOpacity: 0.10
                    )
                }
            }
        }
    }

    private var supportCount: Int {
        mutedAlertCount + pendingFollowUpCount + approvalCount + automationIssueCount + integrationIssueCount
    }
}

private struct NightWatchSupportPressureDeck: View {
    let mutedAlertCount: Int
    let pendingFollowUpCount: Int
    let approvalCount: Int
    let automationIssueCount: Int
    let integrationIssueCount: Int
    let checkInStatus: HandoffCheckInStatus?

    var body: some View {
        NightWatchSectionCard(
            title: String(localized: "Support Pressure"),
            detail: String(localized: "Keep muted alerts, check-ins, follow-ups, and platform drift readable before the queue cards and route rails.")
        ) {
            FlowLayout(spacing: 8) {
                if mutedAlertCount > 0 {
                    GlassCapsuleBadge(
                        text: mutedAlertCount == 1 ? String(localized: "1 muted alert") : String(localized: "\(mutedAlertCount) muted alerts"),
                        backgroundOpacity: 0.10
                    )
                }
                if pendingFollowUpCount > 0 {
                    GlassCapsuleBadge(
                        text: pendingFollowUpCount == 1 ? String(localized: "1 follow-up") : String(localized: "\(pendingFollowUpCount) follow-ups"),
                        backgroundOpacity: 0.14
                    )
                }
                if approvalCount > 0 {
                    GlassCapsuleBadge(
                        text: approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                        backgroundOpacity: 0.14
                    )
                }
                if let checkInStatus {
                    GlassCapsuleBadge(text: checkInStatus.state.label, backgroundOpacity: 0.16)
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
            }
        }
    }
}

private struct NightWatchSupportCoverageDeck: View {
    let totalWatchedCount: Int
    let activeWatchCount: Int
    let watchedQueueCount: Int
    let focusModeLabel: String
    let preferredSurfaceLabel: String
    let showsMutedSummary: Bool
    let checkInStatus: HandoffCheckInStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep pinned watch breadth, focus mode, muted-summary behavior, and preferred surface visible before the action-readiness deck and route rails expand."),
                verticalPadding: 2
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: focusModeLabel, tone: .neutral)
                    PresentationToneBadge(text: preferredSurfaceLabel, tone: .positive)
                    PresentationToneBadge(
                        text: showsMutedSummary ? String(localized: "Muted summary on") : String(localized: "Muted summary off"),
                        tone: showsMutedSummary ? .neutral : .warning
                    )
                }
            }

            MonitoringFactsRow(factsColor: .white.opacity(0.72)) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Support coverage"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Text(String(localized: "Keep pinned fleet breadth, watched queue spillover, and local surface preferences readable before the next night-duty exits take over."))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: totalWatchedCount == 1 ? String(localized: "1 watched agent") : String(localized: "\(totalWatchedCount) watched agents"),
                    tone: totalWatchedCount > 0 ? .caution : .neutral
                )
            } facts: {
                if activeWatchCount > 0 {
                    Label(
                        activeWatchCount == 1 ? String(localized: "1 active watch") : String(localized: "\(activeWatchCount) active watches"),
                        systemImage: "star.fill"
                    )
                }
                if watchedQueueCount > 0 {
                    Label(
                        watchedQueueCount == 1 ? String(localized: "1 watched queue item") : String(localized: "\(watchedQueueCount) watched queue items"),
                        systemImage: "list.bullet"
                    )
                }
                if let checkInStatus {
                    Label(checkInStatus.state.label, systemImage: "calendar.badge.clock")
                }
            }
        }
    }

    private var summaryLine: String {
        if activeWatchCount > 0 || watchedQueueCount > 0 {
            return String(localized: "Night Watch support coverage is currently anchored by pinned watchlist breadth and watched queue spillover.")
        }
        if !showsMutedSummary {
            return String(localized: "Night Watch support coverage is currently narrowed because muted-summary visibility is turned off.")
        }
        if checkInStatus != nil {
            return String(localized: "Night Watch support coverage is currently anchored by handoff check-in state and local surface preferences.")
        }
        return String(localized: "Night Watch support coverage is currently light and mostly reflects focus mode plus preferred surface state.")
    }
}

private struct NightWatchActionReadinessDeck: View {
    let queueCount: Int
    let criticalCount: Int
    let isAcknowledged: Bool
    let pendingFollowUpCount: Int
    let approvalCount: Int
    let focusModeLabel: String
    let checkInStatus: HandoffCheckInStatus?

    private let primaryRouteCount = 5
    private let supportRouteCount = 8

    var body: some View {
        NightWatchSectionCard(
            title: String(localized: "Action Readiness"),
            detail: String(localized: "Keep acknowledge state, focus mode, and route readiness visible before opening the compact night queue.")
        ) {
            FlowLayout(spacing: 8) {
                GlassCapsuleBadge(text: focusModeLabel, backgroundOpacity: 0.16)
                GlassCapsuleBadge(
                    text: isAcknowledged ? String(localized: "Snapshot acknowledged") : String(localized: "Snapshot live"),
                    backgroundOpacity: 0.14
                )
                GlassCapsuleBadge(
                    text: String(localized: "\(primaryRouteCount + supportRouteCount) exits"),
                    backgroundOpacity: 0.12
                )
                if let checkInStatus {
                    GlassCapsuleBadge(text: checkInStatus.state.label, backgroundOpacity: 0.14)
                }
                if approvalCount > 0 {
                    GlassCapsuleBadge(
                        text: approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                        backgroundOpacity: 0.14
                    )
                }
                if pendingFollowUpCount > 0 {
                    GlassCapsuleBadge(
                        text: pendingFollowUpCount == 1 ? String(localized: "1 follow-up") : String(localized: "\(pendingFollowUpCount) follow-ups"),
                        backgroundOpacity: 0.14
                    )
                }
                if criticalCount > 0 {
                    GlassCapsuleBadge(
                        text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                        backgroundOpacity: 0.18
                    )
                }
                if queueCount > 0 {
                    GlassCapsuleBadge(
                        text: queueCount == 1 ? String(localized: "1 queued") : String(localized: "\(queueCount) queued"),
                        backgroundOpacity: 0.12
                    )
                }
            }
        }
    }
}

private struct NightWatchFocusCoverageDeck: View {
    let queueCount: Int
    let primaryQueueCount: Int
    let secondaryQueueCount: Int
    let criticalCount: Int
    let watchIssueCount: Int
    let pendingFollowUpCount: Int
    let automationIssueCount: Int
    let integrationIssueCount: Int
    let focusModeLabel: String
    let checkInStatus: HandoffCheckInStatus?

    var body: some View {
        NightWatchSectionCard(
            title: String(localized: "Focus coverage"),
            detail: String(localized: "Keep the dominant night-duty lane readable before moving from the control deck into primary and support queue cards.")
        ) {
            FlowLayout(spacing: 8) {
                GlassCapsuleBadge(text: focusModeLabel, backgroundOpacity: 0.16)
                GlassCapsuleBadge(
                    text: primaryQueueCount == 1 ? String(localized: "1 primary item") : String(localized: "\(primaryQueueCount) primary items"),
                    backgroundOpacity: primaryQueueCount > 0 ? 0.16 : 0.10
                )
                if secondaryQueueCount > 0 {
                    GlassCapsuleBadge(
                        text: secondaryQueueCount == 1 ? String(localized: "1 support item") : String(localized: "\(secondaryQueueCount) support items"),
                        backgroundOpacity: 0.12
                    )
                }
                if let checkInStatus {
                    GlassCapsuleBadge(text: checkInStatus.state.label, backgroundOpacity: 0.14)
                }
                if criticalCount > 0 {
                    GlassCapsuleBadge(
                        text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                        backgroundOpacity: 0.18
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
                        text: pendingFollowUpCount == 1 ? String(localized: "1 follow-up") : String(localized: "\(pendingFollowUpCount) follow-ups"),
                        backgroundOpacity: 0.12
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
                if queueCount > 0 {
                    GlassCapsuleBadge(
                        text: queueCount == 1 ? String(localized: "1 queued") : String(localized: "\(queueCount) queued"),
                        backgroundOpacity: 0.10
                    )
                }
            }
        }
    }
}

private struct NightWatchCalmCard: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveIconDetailRow(horizontalAlignment: .top, horizontalSpacing: 10, verticalSpacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            } detail: {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.76))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassPanel(fillStyle: .black, fillOpacity: 0.22, cornerRadius: 18, strokeOpacity: 0.08)
    }
}

private struct NightWatchSectionCard<Content: View>: View {
    let title: String
    let detail: String
    let content: Content

    init(title: String, detail: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassPanel(fillStyle: .black, fillOpacity: 0.22, cornerRadius: 18, strokeOpacity: 0.08)
    }
}

private struct NightWatchPriorityCard: View {
    enum Emphasis {
        case primary
        case secondary
    }

    let item: OnCallPriorityItem
    let isWatched: Bool
    let emphasis: Emphasis

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.symbolName)
                .font(.headline)
                .foregroundStyle(item.severity.tone.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 6) {
                ResponsiveAccessoryRow(horizontalAlignment: .center) {
                    titleLabel
                } accessory: {
                    severityBadge
                }

                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)

                ResponsiveAccessoryRow(horizontalSpacing: 8, verticalSpacing: 4) {
                    footnoteLabel
                } accessory: {
                    watchedBadge
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassPanel(fillOpacity: emphasis == .primary ? 0.09 : 0.06, cornerRadius: 14)
    }

    private var titleLabel: some View {
        Text(item.title)
            .font(emphasis == .primary ? .headline.weight(.semibold) : .subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(2)
    }

    private var severityBadge: some View {
        PresentationToneBadge(text: item.severity.label, tone: item.severity.tone)
    }

    private var footnoteLabel: some View {
        Text(item.footnote)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.58))
            .lineLimit(2)
    }

    @ViewBuilder
    private var watchedBadge: some View {
        if isWatched {
            GlassLabelBadge(
                text: String(localized: "Watched"),
                systemImage: "star.fill",
                foregroundStyle: .yellow,
                backgroundOpacity: 0.10
            )
        }
    }
}

private struct NightWatchWatchlistRow: View {
    let item: AgentAttentionItem

    var body: some View {
        ResponsiveIconDetailRow(horizontalAlignment: .top, horizontalSpacing: 12, verticalSpacing: 8, spacerMinLength: 0) {
            Image(systemName: "star.fill")
                .foregroundStyle(PresentationTone.caution.color)
                .frame(width: 18)
        } detail: {
            VStack(alignment: .leading, spacing: 5) {
                ResponsiveAccessoryRow(verticalSpacing: 6) {
                    agentName
                } accessory: {
                    statusBadge
                }

                Text(item.reasons.prefix(2).joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassPanel(fillOpacity: 0.07, cornerRadius: 14)
    }

    private var agentName: some View {
        Text(item.agent.name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(2)
    }

    private var statusBadge: some View {
        PresentationToneBadge(
            text: item.severity >= 10 ? String(localized: "Critical") : String(localized: "Watch"),
            tone: item.tone
        )
    }
}

private struct NightWatchControlsCard: View {
    @Binding var mode: OnCallFocusMode
    @Binding var preferredSurface: OnCallSurfacePreference
    @Binding var showsMutedSummary: Bool

    var body: some View {
        NightWatchSectionCard(
            title: String(localized: "Display Controls"),
            detail: String(localized: "All settings are local to this iPhone.")
        ) {
            NightWatchControlMenuRow(
                title: String(localized: "Queue Mode"),
                detail: mode.summary
            ) {
                Menu {
                    ForEach(OnCallFocusMode.allCases) { option in
                        Button(option.label) {
                            mode = option
                        }
                    }
                } label: {
                    GlassCapsuleBadge(text: mode.label, backgroundOpacity: 0.12)
                }
            }

            NightWatchControlMenuRow(
                title: String(localized: "Critical Banner"),
                detail: preferredSurface.summary
            ) {
                Menu {
                    ForEach(OnCallSurfacePreference.allCases) { option in
                        Button(option.label) {
                            preferredSurface = option
                        }
                    }
                } label: {
                    GlassCapsuleBadge(text: preferredSurface.label, backgroundOpacity: 0.12)
                }
            }

            ResponsiveAccessoryRow(horizontalAlignment: .top, verticalSpacing: 8, spacerMinLength: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Muted Summary"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(
                        showsMutedSummary
                            ? String(localized: "Muted alerts stay visible in a separate summary card.")
                            : String(localized: "Muted alerts stay hidden until you open incidents or re-enable the summary.")
                    )
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
                }
            } accessory: {
                Toggle(isOn: $showsMutedSummary) {
                    EmptyView()
                }
                .labelsHidden()
                .tint(.orange)
            }
        }
    }
}

private struct NightWatchSurfaceGroupLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.90))
    }
}

private struct NightWatchControlMenuRow<Accessory: View>: View {
    let title: String
    let detail: String
    let accessory: Accessory

    init(
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ResponsiveAccessoryRow(horizontalAlignment: .top, verticalSpacing: 8, spacerMinLength: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.66))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } accessory: {
                accessory
            }
        }
    }
}

private struct NightWatchActionRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        ResponsiveIconDetailRow(horizontalAlignment: .top, horizontalSpacing: 12, verticalSpacing: 8, spacerMinLength: 0) {
            Image(systemName: systemImage)
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 20)
        } detail: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassPanel(fillOpacity: 0.07, cornerRadius: 14)
    }
}

private struct NightWatchCountPill: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline.monospacedDigit().weight(.semibold))
            Text(label)
                .font(.caption2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(fillOpacity: 0.10, cornerRadius: 12)
    }
}

import SwiftUI

private enum OverviewSectionAnchor: Hashable {
    case diagnostics
    case integrations
    case automation
    case watchlist
    case sessions
    case audit
    case agents
}

struct OverviewView: View {
    @Environment(\.dependencies) private var deps
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var vm: DashboardViewModel { deps.dashboardViewModel }
    private var visibleMonitoringAlerts: [MonitoringAlertItem] {
        deps.incidentStateStore.visibleAlerts(from: vm.monitoringAlerts)
    }
    private var activeMutedAlertCount: Int {
        deps.incidentStateStore.activeMutedAlerts(from: vm.monitoringAlerts).count
    }
    private var isCurrentSnapshotAcknowledged: Bool {
        deps.incidentStateStore.isCurrentSnapshotAcknowledged(alerts: vm.monitoringAlerts)
    }
    private var watchedAttentionItems: [AgentAttentionItem] {
        watchedAgentAttentionItemsSorted(
            deps.agentWatchlistStore.watchedAgents(from: vm.agents)
                .map { vm.attentionItem(for: $0) },
            summaries: watchedDiagnostics
        )
    }
    private var watchedDiagnostics: [String: WatchedAgentDiagnosticsSummary] {
        deps.watchedAgentDiagnosticsStore.summaries
    }
    private var watchedDiagnosticPriorityItems: [OnCallPriorityItem] {
        watchedAgentDiagnosticPriorityItems(
            agents: deps.agentWatchlistStore.watchedAgents(from: vm.agents),
            summaries: watchedDiagnostics
        )
    }
    private var onCallPriorityItems: [OnCallPriorityItem] {
        mergeOnCallPriorityItems(
            vm.onCallPriorityItems(
                visibleAlerts: visibleMonitoringAlerts,
                watchedAttentionItems: watchedAttentionItems,
                handoffCheckInStatus: deps.onCallHandoffStore.latestCheckInStatus,
                handoffFollowUpStatuses: deps.onCallHandoffStore.latestFollowUpStatuses
            ),
            with: watchedDiagnosticPriorityItems
        )
    }
    private var onCallDigestLine: String {
        let base = vm.onCallDigestLine(
            visibleAlerts: visibleMonitoringAlerts,
            watchedAttentionItems: watchedAttentionItems,
            mutedAlertCount: activeMutedAlertCount,
            isAcknowledged: isCurrentSnapshotAcknowledged,
            handoffCheckInStatus: deps.onCallHandoffStore.latestCheckInStatus,
            handoffFollowUpStatuses: deps.onCallHandoffStore.latestFollowUpStatuses
        )
        if let diagnosticsSummary = watchedAgentDiagnosticDigestSummary(summaries: watchedDiagnostics) {
            return [base, diagnosticsSummary].joined(separator: " · ")
        }
        return base
    }
    private var handoffText: String {
        vm.onCallHandoffText(
            visibleAlerts: visibleMonitoringAlerts,
            watchedAttentionItems: watchedAttentionItems,
            mutedAlertCount: activeMutedAlertCount,
            isAcknowledged: isCurrentSnapshotAcknowledged,
            handoffCheckInStatus: deps.onCallHandoffStore.latestCheckInStatus,
            handoffFollowUpStatuses: deps.onCallHandoffStore.latestFollowUpStatuses
        )
    }
    private var preferredOnCallSurface: OnCallSurfacePreference {
        deps.onCallFocusStore.preferredSurface
    }
    private var configuredServerURL: String {
        ServerConfig.saved.baseURL
    }
    private var isLoopbackServer: Bool {
        let normalized = configuredServerURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.contains("127.0.0.1") || normalized.contains("localhost")
    }
    private var latestHandoffGapLabel: String? {
        deps.onCallHandoffStore.timelineItems.first?.gapToOlderEntry.map(OnCallHandoffStore.formatInterval)
    }
    private var latestHandoffDrift: HandoffSnapshotDrift? {
        deps.onCallHandoffStore.driftFromLatest(
            queueCount: onCallPriorityItems.count,
            criticalCount: visibleMonitoringAlerts.filter { $0.severity == .critical }.count,
            liveAlertCount: visibleMonitoringAlerts.count
        )
    }
    private var latestHandoffCarryover: HandoffCarryoverStatus? {
        deps.onCallHandoffStore.carryoverFromLatest(
            liveAlertCount: visibleMonitoringAlerts.count,
            pendingApprovalCount: vm.pendingApprovalCount,
            watchlistIssueCount: watchedAttentionItems.filter { $0.severity > 0 }.count,
            sessionAttentionCount: vm.sessionAttentionCount,
            criticalAuditCount: vm.recentCriticalAuditCount
        )
    }
    private var overviewWatchIssueCount: Int {
        watchedAttentionItems.filter { $0.severity > 0 }.count
    }
    private var summaryColumns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        if let error = vm.error {
                            ErrorBanner(message: error, onRetry: {
                                await vm.refresh()
                            }, onDismiss: {
                                vm.error = nil
                            })
                        }

                        ConnectionCard(health: vm.health, lastRefresh: vm.lastRefresh, isStale: vm.isDataStale)

                        if !visibleMonitoringAlerts.isEmpty || activeMutedAlertCount > 0 {
                            NavigationLink {
                                IncidentsView()
                            } label: {
                                AlertsCard(
                                    alerts: visibleMonitoringAlerts,
                                    mutedCount: activeMutedAlertCount,
                                    snapshotAcknowledged: isCurrentSnapshotAcknowledged
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        NavigationLink {
                            preferredSurfaceView
                        } label: {
                            OnCallDigestCard(
                                queueCount: onCallPriorityItems.count,
                                criticalCount: visibleMonitoringAlerts.filter { $0.severity == .critical }.count,
                                watchCount: watchedAttentionItems.count,
                                summary: onCallDigestLine
                            )
                        }
                        .buttonStyle(.plain)

                        if let latestHandoff = deps.onCallHandoffStore.latestEntry {
                            NavigationLink {
                                HandoffCenterView(
                                    summary: handoffText,
                                    queueCount: onCallPriorityItems.count,
                                    criticalCount: visibleMonitoringAlerts.filter { $0.severity == .critical }.count,
                                    liveAlertCount: visibleMonitoringAlerts.count
                                )
                            } label: {
                                RecentHandoffCard(
                                    entry: latestHandoff,
                                    gapLabel: latestHandoffGapLabel,
                                    checkInStatus: deps.onCallHandoffStore.latestCheckInStatus,
                                    drift: latestHandoffDrift,
                                    carryover: latestHandoffCarryover,
                                    pendingFollowUpCount: deps.onCallHandoffStore.pendingLatestFollowUpCount,
                                    completedFollowUpCount: deps.onCallHandoffStore.completedLatestFollowUpCount
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        OverviewStatusDeckCard(
                            queueCount: onCallPriorityItems.count,
                            criticalCount: visibleMonitoringAlerts.filter { $0.severity == .critical }.count,
                            approvalCount: vm.pendingApprovalCount,
                            sessionCount: vm.sessionAttentionCount,
                            watchIssueCount: overviewWatchIssueCount,
                            automationIssueCount: vm.automationPressureIssueCategoryCount,
                            integrationIssueCount: vm.integrationPressureIssueCategoryCount,
                            isDataStale: vm.isDataStale,
                            isLoopbackServer: isLoopbackServer,
                            providerCount: vm.configuredProviderCount,
                            channelCount: vm.readyChannelCount,
                            handoffStateLabel: deps.onCallHandoffStore.freshnessLabel,
                            handoffTone: deps.onCallHandoffStore.freshnessState.tone
                        )

                        OverviewEntryDeckCard(
                            criticalCount: visibleMonitoringAlerts.filter { $0.severity == .critical }.count,
                            approvalCount: vm.pendingApprovalCount,
                            sessionCount: vm.sessionAttentionCount,
                            automationIssueCount: vm.automationPressureIssueCategoryCount,
                            integrationIssueCount: vm.integrationPressureIssueCategoryCount,
                            diagnosticsWarningCount: vm.diagnosticsConfigWarningCount,
                            budgetDailyCost: vm.budget?.dailySpend,
                            handoffText: handoffText,
                            queueCount: onCallPriorityItems.count,
                            liveAlertCount: visibleMonitoringAlerts.count,
                            watchIssueCount: overviewWatchIssueCount,
                            auditCount: vm.recentAudit.count,
                            agentCount: vm.attentionAgents.isEmpty ? vm.agents.count : vm.attentionAgents.count,
                            showsDiagnostics: vm.healthDetail != nil || vm.versionInfo != nil || vm.metricsSnapshot != nil,
                            showsIntegrations: !vm.providers.isEmpty || !vm.channels.isEmpty || !vm.catalogModels.isEmpty,
                            showsAutomation: vm.automationDefinitionCount > 0 || !vm.workflowRuns.isEmpty,
                            showsWatchlist: !watchedAttentionItems.isEmpty,
                            showsSessions: !vm.sessionAttentionItems.isEmpty,
                            showsAudit: !vm.recentAudit.isEmpty,
                            showsAgents: !vm.agents.isEmpty
                        ) { anchor in
                            jump(proxy, to: anchor)
                        }

                        LazyVGrid(columns: summaryColumns, spacing: 8) {
                            StatBadge(
                                value: "\(vm.runningCount)",
                                label: "Running",
                                icon: "play.circle.fill",
                                color: vm.runningAgentStatus.color(positive: .green)
                            )
                            StatBadge(
                                value: formatCost(vm.budget?.dailySpend),
                                label: "Today",
                                icon: "dollarsign.circle",
                                color: StatusPresentation.budgetUtilizationStatus(for: vm.budget?.dailyPct)?.color() ?? .primary
                            )
                            StatBadge(
                                value: "\(vm.pendingApprovalCount)",
                                label: "Approvals",
                                icon: "exclamationmark.shield",
                                color: vm.approvalBacklogStatus.color(positive: .green)
                            )
                            StatBadge(
                                value: "\(vm.configuredProviderCount)",
                                label: "Providers",
                                icon: "key.horizontal",
                                color: vm.providerReadinessStatus.color(positive: .blue)
                            )
                            StatBadge(
                                value: "\(vm.readyChannelCount)",
                                label: "Channels",
                                icon: "bubble.left.and.bubble.right",
                                color: vm.channelReadinessStatus.color(positive: .teal)
                            )
                            StatBadge(
                                value: "\(vm.activeHandCount)",
                                label: "Hands",
                                icon: "hand.raised",
                                color: vm.handReadinessStatus.color(positive: .indigo)
                            )
                        }

                        if let status = vm.status {
                            SystemSnapshotCard(
                                status: status,
                                security: vm.security,
                                usageSummary: vm.usageSummary,
                                connectedProviders: vm.configuredProviderCount,
                                networkStatus: vm.networkStatus,
                                sessionCount: vm.totalSessionCount,
                                mcpConnectedServers: vm.connectedMCPServerCount
                            )
                        }

                        if vm.healthDetail != nil || vm.versionInfo != nil || vm.metricsSnapshot != nil {
                            NavigationLink {
                                DiagnosticsView()
                            } label: {
                                DiagnosticsOverviewCard(vm: vm)
                            }
                            .buttonStyle(.plain)
                            .id(OverviewSectionAnchor.diagnostics)
                        }

                        if !vm.providers.isEmpty || !vm.channels.isEmpty || !vm.catalogModels.isEmpty {
                            NavigationLink {
                                IntegrationsView()
                            } label: {
                                IntegrationsOverviewCard(vm: vm)
                            }
                            .buttonStyle(.plain)
                            .id(OverviewSectionAnchor.integrations)
                        }

                        ReadinessCard(vm: vm)

                        if let usageSummary = vm.usageSummary {
                            UsageSnapshotCard(usageSummary: usageSummary)
                        }

                        if let budget = vm.budget {
                            BudgetGaugesCard(budget: budget)
                        }

                        if let ranking = vm.budgetAgents, !ranking.agents.isEmpty {
                            TopSpendersCard(agents: ranking.agents)
                        }

                        if !vm.activeHands.isEmpty || !vm.approvals.isEmpty {
                            LiveSignalsCard(activeHands: vm.activeHands, approvals: vm.approvals, hands: vm.hands)
                        }

                        if vm.automationDefinitionCount > 0 || !vm.workflowRuns.isEmpty {
                            NavigationLink {
                                AutomationView()
                            } label: {
                                AutomationOverviewCard(vm: vm)
                            }
                            .buttonStyle(.plain)
                            .id(OverviewSectionAnchor.automation)
                        }

                        if !watchedAttentionItems.isEmpty {
                            WatchlistCard(items: watchedAttentionItems, diagnostics: watchedDiagnostics)
                                .id(OverviewSectionAnchor.watchlist)
                        }

                        if !vm.sessionAttentionItems.isEmpty {
                            SessionWatchlistCard(items: vm.sessionAttentionItems)
                                .id(OverviewSectionAnchor.sessions)
                        }

                        if !vm.attentionAgents.isEmpty {
                            AttentionAgentsCard(items: vm.attentionAgents)
                        }

                        if !vm.recentAudit.isEmpty {
                            AuditFeedCard(entries: vm.recentAudit)
                                .id(OverviewSectionAnchor.audit)
                        }

                        if let a2a = vm.a2aAgents, a2a.total > 0 {
                            A2ASummaryCard(count: a2a.total)
                        }

                        if !vm.agents.isEmpty {
                            AgentPreviewCard(agents: vm.attentionAgents.isEmpty ? vm.agents : vm.attentionAgents.map(\.agent))
                                .id(OverviewSectionAnchor.agents)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("LibreFang")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        IncidentsView()
                    } label: {
                        Image(systemName: "bell.badge")
                    }

                    Menu {
                        Section("On Call") {
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
                                    queueCount: onCallPriorityItems.count,
                                    criticalCount: visibleMonitoringAlerts.filter { $0.severity == .critical }.count,
                                    liveAlertCount: visibleMonitoringAlerts.count
                                )
                            } label: {
                                Label("Handoff", systemImage: "text.badge.plus")
                            }
                        }

                        Section("Monitoring") {
                            NavigationLink {
                                ApprovalsView()
                            } label: {
                                Label("Approvals", systemImage: "checkmark.shield")
                            }

                            NavigationLink {
                                AutomationView()
                            } label: {
                                Label("Automation", systemImage: "flowchart")
                            }

                            NavigationLink {
                                DiagnosticsView()
                            } label: {
                                Label("Diagnostics", systemImage: "stethoscope")
                            }

                            NavigationLink {
                                IntegrationsView()
                            } label: {
                                Label("Integrations", systemImage: "square.3.layers.3d.down.forward")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .refreshable {
                await vm.refresh()
                deps.agentWatchlistStore.removeMissingAgents(validIDs: Set(vm.agents.map(\.id)))
            }
            .task {
                if vm.agents.isEmpty && vm.status == nil {
                    await vm.refresh()
                }
                deps.agentWatchlistStore.removeMissingAgents(validIDs: Set(vm.agents.map(\.id)))
            }
            .overlay {
                if vm.isLoading && vm.agents.isEmpty && vm.error == nil {
                    StartupConnectionCard(
                        serverURL: configuredServerURL,
                        showsLoopbackHint: isLoopbackServer
                    )
                    .padding()
                }
            }
        }
    }

    private func formatCost(_ value: Double?) -> String {
        guard let value else { return "--" }
        return localizedUSDCurrency(value)
    }

    @ViewBuilder
    private var preferredSurfaceView: some View {
        switch preferredOnCallSurface {
        case .onCall:
            OnCallView()
        case .nightWatch:
            NightWatchView()
        case .standbyDigest:
            StandbyDigestView()
        }
    }

    private func jump(_ proxy: ScrollViewProxy, to anchor: OverviewSectionAnchor) {
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }
}

private struct OverviewStatusDeckCard: View {
    let queueCount: Int
    let criticalCount: Int
    let approvalCount: Int
    let sessionCount: Int
    let watchIssueCount: Int
    let automationIssueCount: Int
    let integrationIssueCount: Int
    let isDataStale: Bool
    let isLoopbackServer: Bool
    let providerCount: Int
    let channelCount: Int
    let handoffStateLabel: String
    let handoffTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(summary: String(localized: "Mobile triage is ready from the current snapshot.")) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: queueCount == 1 ? String(localized: "1 queued item") : String(localized: "\(queueCount) queued items"),
                        tone: queueCount > 0 ? .warning : .neutral
                    )
                    PresentationToneBadge(
                        text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                        tone: criticalCount > 0 ? .critical : .neutral
                    )
                    PresentationToneBadge(
                        text: approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                        tone: approvalCount > 0 ? .warning : .neutral
                    )
                    PresentationToneBadge(
                        text: sessionCount == 1 ? String(localized: "1 session") : String(localized: "\(sessionCount) sessions"),
                        tone: sessionCount > 0 ? .warning : .neutral
                    )
                    PresentationToneBadge(
                        text: watchIssueCount == 1 ? String(localized: "1 watch issue") : String(localized: "\(watchIssueCount) watch issues"),
                        tone: watchIssueCount > 0 ? .warning : .neutral
                    )
                    if automationIssueCount > 0 {
                        PresentationToneBadge(
                            text: automationIssueCount == 1 ? String(localized: "1 automation issue") : String(localized: "\(automationIssueCount) automation issues"),
                            tone: .warning
                        )
                    }
                    if integrationIssueCount > 0 {
                        PresentationToneBadge(
                            text: integrationIssueCount == 1 ? String(localized: "1 integration issue") : String(localized: "\(integrationIssueCount) integration issues"),
                            tone: .warning
                        )
                    }
                    PresentationToneBadge(text: handoffStateLabel, tone: handoffTone)
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Overview signal facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep connection, queue, and pressure visible before opening the overview cards."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: isDataStale ? String(localized: "Stale") : String(localized: "Live"),
                    tone: isDataStale ? .warning : .positive
                )
            } facts: {
                Label(
                    isLoopbackServer ? String(localized: "Loopback server") : String(localized: "Remote server"),
                    systemImage: "network"
                )
                Label(
                    providerCount == 1 ? String(localized: "1 provider") : String(localized: "\(providerCount) providers"),
                    systemImage: "key.horizontal"
                )
                Label(
                    channelCount == 1 ? String(localized: "1 ready channel") : String(localized: "\(channelCount) ready channels"),
                    systemImage: "bubble.left.and.bubble.right"
                )
                if approvalCount > 0 {
                    Label(
                        approvalCount == 1 ? String(localized: "1 pending approval") : String(localized: "\(approvalCount) pending approvals"),
                        systemImage: "checkmark.shield"
                    )
                }
                if sessionCount > 0 {
                    Label(
                        sessionCount == 1 ? String(localized: "1 session hotspot") : String(localized: "\(sessionCount) session hotspots"),
                        systemImage: "rectangle.stack"
                    )
                }
                if watchIssueCount > 0 {
                    Label(
                        watchIssueCount == 1 ? String(localized: "1 watch issue") : String(localized: "\(watchIssueCount) watch issues"),
                        systemImage: "star.fill"
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

private struct OverviewEntryDeckCard: View {
    let criticalCount: Int
    let approvalCount: Int
    let sessionCount: Int
    let automationIssueCount: Int
    let integrationIssueCount: Int
    let diagnosticsWarningCount: Int
    let budgetDailyCost: Double?
    let handoffText: String
    let queueCount: Int
    let liveAlertCount: Int
    let watchIssueCount: Int
    let auditCount: Int
    let agentCount: Int
    let showsDiagnostics: Bool
    let showsIntegrations: Bool
    let showsAutomation: Bool
    let showsWatchlist: Bool
    let showsSessions: Bool
    let showsAudit: Bool
    let showsAgents: Bool
    let onJump: (OverviewSectionAnchor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: String(localized: "Overview control deck keeps the next operator surfaces visible without stacking multiple similar cards."),
                detail: String(localized: "Use these exits when the top snapshot already tells you where to go next.")
            ) {
                FlowLayout(spacing: 8) {
                    if criticalCount > 0 {
                        PresentationToneBadge(
                            text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                            tone: .critical
                        )
                    }
                    if approvalCount > 0 {
                        PresentationToneBadge(
                            text: approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                            tone: .warning
                        )
                    }
                    if sessionCount > 0 {
                        PresentationToneBadge(
                            text: sessionCount == 1 ? String(localized: "1 session hotspot") : String(localized: "\(sessionCount) session hotspots"),
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
                    if diagnosticsWarningCount > 0 {
                        PresentationToneBadge(
                            text: diagnosticsWarningCount == 1 ? String(localized: "1 diagnostics warning") : String(localized: "\(diagnosticsWarningCount) diagnostics warnings"),
                            tone: .warning
                        )
                    }
                    if let budgetDailyCost {
                        PresentationToneBadge(
                            text: String(localized: "Today \(localizedUSDCurrency(budgetDailyCost))"),
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringSurfaceGroupCard(
                title: String(localized: "Routes"),
                detail: String(localized: "Keep the first overview exits and lower-section jumps in one compact deck.")
            ) {
                OverviewRouteInventoryDeck(
                    primaryCount: 4,
                    supportCount: 4,
                    jumpCount: visibleJumpCount,
                    queueCount: queueCount,
                    criticalCount: criticalCount,
                    watchIssueCount: watchIssueCount
                )

                MonitoringShortcutRail(
                    title: String(localized: "Primary"),
                    detail: String(localized: "Keep the first operator exits right below the overview snapshot.")
                ) {
                    NavigationLink {
                        IncidentsView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Incidents"),
                            systemImage: "bell.badge",
                            tone: criticalCount > 0 ? .critical : .neutral,
                            badgeText: criticalCount > 0
                                ? (criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"))
                                : nil
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        RuntimeView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Runtime"),
                            systemImage: "waveform.path.ecg",
                            tone: approvalCount > 0 || sessionCount > 0 ? .warning : .neutral
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Diagnostics"),
                            systemImage: "stethoscope",
                            tone: diagnosticsWarningCount > 0 ? .warning : .neutral,
                            badgeText: diagnosticsWarningCount > 0
                                ? (diagnosticsWarningCount == 1 ? String(localized: "1 warning") : String(localized: "\(diagnosticsWarningCount) warnings"))
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
                            tone: liveAlertCount > 0 ? .warning : .neutral,
                            badgeText: queueCount > 0
                                ? (queueCount == 1 ? String(localized: "1 queued") : String(localized: "\(queueCount) queued"))
                                : nil
                        )
                    }
                    .buttonStyle(.plain)
                }

                MonitoringShortcutRail(
                    title: String(localized: "Support"),
                    detail: String(localized: "Keep slower spend and config routes in a secondary rail.")
                ) {
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
                        AutomationView()
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
                        BudgetView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Budget"),
                            systemImage: "chart.bar",
                            tone: budgetDailyCost == nil ? .neutral : .warning,
                            badgeText: budgetDailyCost.map { localizedUSDCurrency($0) }
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SettingsView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Settings"),
                            systemImage: "gearshape"
                        )
                    }
                    .buttonStyle(.plain)
                }

                MonitoringShortcutRail(
                    title: String(localized: "Jumps"),
                    detail: String(localized: "Jump to lower overview sections without long thumb-scrolling.")
                ) {
                    if showsDiagnostics {
                        jumpChip(
                            title: String(localized: "Diagnostics"),
                            systemImage: "stethoscope",
                            tone: diagnosticsWarningCount > 0 ? .warning : .neutral,
                            badgeText: diagnosticsWarningCount > 0
                                ? (diagnosticsWarningCount == 1 ? String(localized: "1 warning") : String(localized: "\(diagnosticsWarningCount) warnings"))
                                : nil,
                            anchor: .diagnostics
                        )
                    }

                    if showsIntegrations {
                        jumpChip(
                            title: String(localized: "Integrations"),
                            systemImage: "square.3.layers.3d.down.forward",
                            tone: integrationIssueCount > 0 ? .warning : .neutral,
                            badgeText: integrationIssueCount > 0
                                ? (integrationIssueCount == 1 ? String(localized: "1 issue") : String(localized: "\(integrationIssueCount) issues"))
                                : nil,
                            anchor: .integrations
                        )
                    }

                    if showsAutomation {
                        jumpChip(
                            title: String(localized: "Automation"),
                            systemImage: "flowchart",
                            tone: automationIssueCount > 0 ? .warning : .neutral,
                            badgeText: automationIssueCount > 0
                                ? (automationIssueCount == 1 ? String(localized: "1 issue") : String(localized: "\(automationIssueCount) issues"))
                                : nil,
                            anchor: .automation
                        )
                    }

                    if showsWatchlist {
                        jumpChip(
                            title: String(localized: "Watchlist"),
                            systemImage: "star.fill",
                            tone: watchIssueCount > 0 ? .warning : .neutral,
                            badgeText: watchIssueCount == 1 ? String(localized: "1 issue") : String(localized: "\(watchIssueCount) issues"),
                            anchor: .watchlist
                        )
                    }

                    if showsSessions {
                        jumpChip(
                            title: String(localized: "Sessions"),
                            systemImage: "text.bubble",
                            tone: sessionCount > 0 ? .warning : .neutral,
                            badgeText: sessionCount == 1 ? String(localized: "1 hot session") : String(localized: "\(sessionCount) hot sessions"),
                            anchor: .sessions
                        )
                    }

                    if showsAudit {
                        jumpChip(
                            title: String(localized: "Audit"),
                            systemImage: "text.justify.leading",
                            tone: .neutral,
                            badgeText: auditCount == 1 ? String(localized: "1 recent event") : String(localized: "\(auditCount) recent events"),
                            anchor: .audit
                        )
                    }

                    if showsAgents {
                        jumpChip(
                            title: String(localized: "Agents"),
                            systemImage: "person.3",
                            tone: .neutral,
                            badgeText: agentCount == 1 ? String(localized: "1 agent") : String(localized: "\(agentCount) agents"),
                            anchor: .agents
                        )
                    }
                }
            }
        }
    }

    private var visibleJumpCount: Int {
        [showsDiagnostics, showsIntegrations, showsAutomation, showsWatchlist, showsSessions, showsAudit, showsAgents]
            .filter { $0 }
            .count
    }

    private func jumpChip(
        title: String,
        systemImage: String,
        tone: PresentationTone,
        badgeText: String?,
        anchor: OverviewSectionAnchor
    ) -> some View {
        Button {
            onJump(anchor)
        } label: {
            MonitoringSurfaceShortcutChip(
                title: title,
                systemImage: systemImage,
                tone: tone,
                badgeText: badgeText
            )
        }
        .buttonStyle(.plain)
    }
}

private struct OverviewRouteInventoryDeck: View {
    let primaryCount: Int
    let supportCount: Int
    let jumpCount: Int
    let queueCount: Int
    let criticalCount: Int
    let watchIssueCount: Int

    var body: some View {
        MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
            FlowLayout(spacing: 8) {
                PresentationToneBadge(
                    text: primaryCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryCount) primary routes"),
                    tone: .neutral
                )
                PresentationToneBadge(
                    text: supportCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportCount) support routes"),
                    tone: .neutral
                )
                PresentationToneBadge(
                    text: jumpCount == 1 ? String(localized: "1 jump") : String(localized: "\(jumpCount) jumps"),
                    tone: jumpCount > 0 ? .positive : .neutral
                )
                if criticalCount > 0 {
                    PresentationToneBadge(
                        text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                        tone: .critical
                    )
                }
                if queueCount > 0 {
                    PresentationToneBadge(
                        text: queueCount == 1 ? String(localized: "1 queued") : String(localized: "\(queueCount) queued"),
                        tone: .warning
                    )
                }
                if watchIssueCount > 0 {
                    PresentationToneBadge(
                        text: watchIssueCount == 1 ? String(localized: "1 watch issue") : String(localized: "\(watchIssueCount) watch issues"),
                        tone: .warning
                    )
                }
            }
        }
    }

    private var summaryLine: String {
        let totalRoutes = primaryCount + supportCount + jumpCount
        return totalRoutes == 1
            ? String(localized: "1 overview route is grouped in this deck.")
            : String(localized: "\(totalRoutes) overview routes are grouped in this deck.")
    }

    private var detailLine: String {
        if jumpCount == 0 {
            return String(localized: "Primary and support exits stay together before the lower overview sections load.")
        }
        return String(localized: "Primary exits, slower support routes, and lower-section jumps stay together in one compact deck.")
    }
}

private struct AlertsCard: View {
    let alerts: [MonitoringAlertItem]
    let mutedCount: Int
    let snapshotAcknowledged: Bool

    private var snapshotState: AlertSnapshotState {
        AlertSnapshotState(
            liveAlertCount: alerts.count,
            mutedAlertCount: mutedCount,
            isAcknowledged: snapshotAcknowledged
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow {
                Label("Attention", systemImage: "bell.badge")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } accessory: {
                PresentationToneBadge(text: snapshotState.overviewLabel, tone: snapshotState.tone)
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Alert inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep live, muted, and acknowledgement state visible before reading each alert row."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: snapshotAcknowledged ? String(localized: "Acknowledged") : String(localized: "Live"),
                    tone: snapshotAcknowledged ? .neutral : snapshotState.tone
                )
            } facts: {
                Label(
                    alerts.count == 1 ? String(localized: "1 live alert") : String(localized: "\(alerts.count) live alerts"),
                    systemImage: "bell.badge"
                )
                if mutedCount > 0 {
                    Label(
                        mutedCount == 1 ? String(localized: "1 muted locally") : String(localized: "\(mutedCount) muted locally"),
                        systemImage: "bell.slash"
                    )
                }
                if let leadAlert = alerts.first {
                    Label(leadAlert.title, systemImage: leadAlert.symbolName)
                }
            }

            if alerts.isEmpty {
                Text(String(localized: "All current alert cards are muted on this iPhone. Open incidents to review or unmute them."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(alerts.prefix(4)) { alert in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: alert.symbolName)
                            .foregroundStyle(alert.severity.tone.color)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.title)
                                .font(.subheadline.weight(.medium))
                            Text(alert.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct RecentHandoffCard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let entry: OnCallHandoffEntry
    let gapLabel: String?
    let checkInStatus: HandoffCheckInStatus?
    let drift: HandoffSnapshotDrift?
    let carryover: HandoffCarryoverStatus?
    let pendingFollowUpCount: Int
    let completedFollowUpCount: Int

    private var badgeColumns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 4
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow(horizontalAlignment: .firstTextBaseline, verticalSpacing: 8) {
                Label("Last Handoff", systemImage: "text.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } accessory: {
                let freshnessState = freshnessState(for: entry)
                PresentationToneBadge(text: freshnessState.label, tone: freshnessState.tone)
            }

            HandoffKindBadge(kind: entry.kind)

            Text(entry.note.isEmpty ? entry.summary : entry.note)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(entry.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Text(entry.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: badgeColumns, spacing: 8) {
                HandoffBadge(value: entry.queueCount, label: String(localized: "Queued"))
                HandoffBadge(value: entry.criticalCount, label: String(localized: "Critical"))
                HandoffBadge(value: entry.liveAlertCount, label: String(localized: "Live"))
                HandoffBadge(value: entry.checklist.completedCount, label: String(localized: "Checks"))
            }

            HStack {
                Spacer()
                TintedCapsuleBadge(
                    text: String(localized: "Open"),
                    foregroundStyle: .secondary,
                    backgroundStyle: .secondary.opacity(0.12)
                )
            }

            Text(
                entry.checklist.summaryLabel
            )
                .font(.caption2)
                .foregroundStyle(entry.checklist.tone.color)
                .lineLimit(2)

            if !entry.focusAreas.items.isEmpty {
                Text(String(localized: "Focus: \(entry.focusAreas.summaryLabel)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !entry.followUpItems.isEmpty {
                let followUpSummary = HandoffFollowUpSummary.summarize(
                    pendingCount: pendingFollowUpCount,
                    completedCount: completedFollowUpCount
                )

                Text(String(localized: "Follow-ups: \(followUpSummary.settingsLabel)"))
                    .font(.caption2)
                    .foregroundStyle(followUpSummary.tone.color)
            }

            if let checkInStatus {
                Text(String(localized: "Check-in: \(checkInStatus.state.label) · \(checkInStatus.dueLabel)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if entry.checkInWindow != .none {
                Text(String(localized: "Check-in: \(entry.checkInWindow.dueLabel(from: entry.createdAt))"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let drift {
                Text(String(localized: "Drift: \(drift.state.label) · \(drift.compactSummary)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let carryover {
                Text(String(localized: "Carryover: \(carryover.state.label) · \(carryover.summary)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let gapLabel {
                Text(String(localized: "Gap to prior handoff: \(gapLabel)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func freshnessState(for entry: OnCallHandoffEntry) -> HandoffFreshnessState {
        if Date().timeIntervalSince(entry.createdAt) >= 8 * 60 * 60 {
            return .stale
        }
        return .fresh
    }
}

private struct HandoffBadge: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.caption.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct StartupConnectionCard: View {
    let serverURL: String
    let showsLoopbackHint: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MonitoringSnapshotCard(
                summary: String(localized: "Connecting to LibreFang"),
                detail: serverURL,
                verticalPadding: 6
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: String(localized: "Connecting"), tone: .warning)
                    if showsLoopbackHint {
                        PresentationToneBadge(text: String(localized: "Loopback host"), tone: .warning)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Connection inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the target server and loopback hint visible while the first snapshot is loading."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                ProgressView()
                    .controlSize(.small)
            } facts: {
                Label(serverURL, systemImage: "network")
                if showsLoopbackHint {
                    Label(String(localized: "Use your Mac LAN IP on a physical iPhone"), systemImage: "iphone")
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }
}

private struct ConnectionCard: View {
    let health: HealthStatus?
    let lastRefresh: Date?
    let isStale: Bool

    private var connectionTone: PresentationTone {
        guard let health else { return .critical }
        if health.isHealthy && isStale {
            return .warning
        }
        return health.statusTone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: connectionText,
                detail: (health?.version).map { String(localized: "Server v\($0)") },
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: connectionText, tone: connectionTone)
                    if let date = lastRefresh {
                        PresentationToneBadge(
                            text: String(localized: "Updated \(date.formatted(.relative(presentation: .named)))"),
                            tone: isStale ? .warning : .neutral
                        )
                    }
                    if health?.isHealthy == true && !isStale {
                        PresentationToneBadge(text: String(localized: "Live"), tone: .positive)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Connection inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep connection health, refresh age, and server version visible before opening deeper cards."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: isStale ? String(localized: "Stale") : String(localized: "Fresh"),
                    tone: isStale ? .warning : .positive
                )
            } facts: {
                if let health {
                    Label(health.localizedStatusLabel, systemImage: "stethoscope")
                    Label(health.version, systemImage: "shippingbox")
                } else {
                    Label(String(localized: "No health snapshot"), systemImage: "xmark.octagon")
                }
                if let date = lastRefresh {
                    Label(date.formatted(.relative(presentation: .named)), systemImage: "clock")
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var connectionText: String {
        if health?.isHealthy != true {
            return String(localized: "Disconnected")
        }
        if isStale {
            return String(localized: "Connected (stale)")
        }
        return String(localized: "Connected")
    }
}

private struct SystemSnapshotCard: View {
    let status: SystemStatus
    let security: SecurityStatus?
    let usageSummary: UsageSummary?
    let connectedProviders: Int
    let networkStatus: NetworkStatus?
    let sessionCount: Int
    let mcpConnectedServers: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Kernel \(status.localizedStatusLabel) · \(formatDuration(status.uptimeSeconds)) uptime"),
                detail: String(localized: "System version \(status.version) with mobile runtime, provider, session, and security context.")
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: status.localizedStatusLabel, tone: status.statusTone)
                    PresentationToneBadge(
                        text: status.networkEnabled ? String(localized: "Network enabled") : String(localized: "Network disabled"),
                        tone: status.networkEnabled ? .positive : .warning
                    )
                    PresentationToneBadge(
                        text: connectedProviders == 1 ? String(localized: "1 provider") : String(localized: "\(connectedProviders) providers"),
                        tone: connectedProviders > 0 ? .positive : .neutral
                    )
                    PresentationToneBadge(
                        text: sessionCount == 1 ? String(localized: "1 session") : String(localized: "\(sessionCount) sessions"),
                        tone: sessionCount > 0 ? .neutral : .neutral
                    )
                    if let networkStatus {
                        PresentationToneBadge(
                            text: String(localized: "\(networkStatus.connectedPeers)/\(networkStatus.totalPeers) peers"),
                            tone: networkStatus.connectedPeers > 0 ? .positive : .neutral
                        )
                    }
                    if mcpConnectedServers > 0 || security != nil {
                        PresentationToneBadge(
                            text: mcpConnectedServers == 1 ? String(localized: "1 MCP server") : String(localized: "\(mcpConnectedServers) MCP servers"),
                            tone: mcpConnectedServers > 0 ? .positive : .neutral
                        )
                    }
                }
            }

            ResponsiveValueRow {
                Text(String(localized: "Default Provider"))
                    .foregroundStyle(.secondary)
            } value: {
                Text(status.defaultProvider)
                    .fontWeight(.medium)
            }

            ResponsiveValueRow {
                Text(String(localized: "Default Model"))
                    .foregroundStyle(.secondary)
            } value: {
                Text(status.defaultModel)
                    .fontWeight(.medium)
            }

            if let networkStatus {
                ResponsiveValueRow {
                    Text(String(localized: "Connected Peers"))
                        .foregroundStyle(.secondary)
                } value: {
                    Text("\(networkStatus.connectedPeers)/\(networkStatus.totalPeers)")
                        .fontWeight(.medium)
                }
            }

            if let usageSummary {
                ResponsiveValueRow {
                    Text(String(localized: "Total Tokens"))
                        .foregroundStyle(.secondary)
                } value: {
                    Text((usageSummary.totalInputTokens + usageSummary.totalOutputTokens).formatted())
                        .fontWeight(.medium)
                }
            }

            if let security {
                ResponsiveValueRow {
                    Text(String(localized: "Security Features"))
                        .foregroundStyle(.secondary)
                } value: {
                    Text("\(security.totalFeatures)")
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formatDuration(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            return String(localized: "\(days)d \(hours)h")
        }
        if hours > 0 {
            return String(localized: "\(hours)h \(minutes)m")
        }
        return String(localized: "\(minutes)m")
    }
}

private struct OverviewMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

private struct ReadinessCard: View {
    let vm: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Readiness layers summarize provider, channel, hand, approval, peer, and tooling health."),
                detail: String(localized: "This card keeps the main readiness layers readable on mobile before you open the deeper monitors.")
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: vm.providerReadinessStatus.summary, tone: vm.providerReadinessStatus.tone)
                    PresentationToneBadge(text: vm.channelReadinessStatus.summary, tone: vm.channelReadinessStatus.tone)
                    PresentationToneBadge(text: vm.handReadinessStatus.summary, tone: vm.handReadinessStatus.tone)
                    PresentationToneBadge(text: vm.approvalBacklogStatus.summary, tone: vm.approvalBacklogStatus.tone)
                }
            }

            ReadinessRow(
                title: String(localized: "Model Layer"),
                subtitle: vm.providerReadinessStatus.summary,
                color: vm.providerReadinessStatus.tone.color
            )
            ReadinessRow(
                title: String(localized: "Channels"),
                subtitle: vm.channelReadinessStatus.summary,
                color: vm.channelReadinessStatus.tone.color
            )
            ReadinessRow(
                title: String(localized: "Autonomous Hands"),
                subtitle: vm.handReadinessStatus.summary,
                color: vm.handReadinessStatus.tone.color
            )
            ReadinessRow(
                title: String(localized: "Approvals"),
                subtitle: vm.approvalBacklogStatus.summary,
                color: vm.approvalBacklogStatus.tone.color
            )
            ReadinessRow(
                title: String(localized: "Peer Network"),
                subtitle: vm.peerConnectivityStatus.summary,
                color: vm.peerConnectivityStatus.tone.color
            )
            ReadinessRow(
                title: String(localized: "Tooling"),
                subtitle: vm.mcpConnectivityStatus.summary,
                color: vm.mcpConnectivityStatus.tone.color
            )
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

}

private struct ReadinessRow: View {
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

private struct UsageSnapshotCard: View {
    let usageSummary: UsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Usage")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                CompactMetric(value: usageSummary.totalInputTokens.formatted(), label: String(localized: "Input"))
                CompactMetric(value: usageSummary.totalOutputTokens.formatted(), label: String(localized: "Output"))
                CompactMetric(value: usageSummary.totalToolCalls.formatted(), label: String(localized: "Tools"))
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accumulated Cost")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatCost(usageSummary.totalCostUsd))
                        .font(.title3.weight(.semibold).monospacedDigit())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("LLM Calls")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(usageSummary.callCount.formatted())
                        .font(.headline.monospacedDigit())
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formatCost(_ value: Double) -> String {
        return localizedUSDCurrency(value)
    }
}

private struct CompactMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct BudgetGaugesCard: View {
    let budget: BudgetOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cost Overview")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                GaugeItem(label: "Hourly", spend: budget.hourlySpend, limit: budget.hourlyLimit, pct: budget.hourlyPct)
                GaugeItem(label: "Daily", spend: budget.dailySpend, limit: budget.dailyLimit, pct: budget.dailyPct)
                GaugeItem(label: "Monthly", spend: budget.monthlySpend, limit: budget.monthlyLimit, pct: budget.monthlyPct)
            }

            if budget.alertThreshold > 0 {
                let maxPct = max(budget.hourlyPct, budget.dailyPct, budget.monthlyPct)
                if maxPct >= budget.alertThreshold {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Approaching budget limit (\(Int(maxPct * 100))%)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct GaugeItem: View {
    let label: LocalizedStringResource
    let spend: Double
    let limit: Double
    let pct: Double

    var body: some View {
        let utilizationStatus = StatusPresentation.budgetUtilizationStatus(for: pct) ?? .normal

        VStack(spacing: 8) {
            Gauge(value: min(pct, 1.0)) {
                EmptyView()
            } currentValueLabel: {
                Text("\(Int(pct * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(utilizationStatus.color())
            .scaleEffect(0.85)

            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            Text(localizedUSDCurrency(spend, standardPrecision: 2, smallValuePrecision: 4))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TopSpendersCard: View {
    let agents: [AgentBudgetItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top Spenders Today")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach(Array(agents.prefix(5).enumerated()), id: \.element.id) { index, agent in
                ResponsiveValueRow(horizontalSpacing: 8) {
                    HStack(spacing: 8) {
                        rankLabel(index)
                        nameLabel(agent)
                    }
                } value: {
                    costLabel(agent)
                }

                if index < min(agents.count, 5) - 1 {
                    Divider()
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func rankLabel(_ index: Int) -> some View {
        Text("#\(index + 1)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.tertiary)
            .frame(width: 20)
    }

    private func nameLabel(_ agent: AgentBudgetItem) -> some View {
        Text(agent.name)
            .font(.subheadline)
            .lineLimit(2)
    }

    private func costLabel(_ agent: AgentBudgetItem) -> some View {
        Text(localizedUSDCurrency(agent.dailyCostUsd, standardPrecision: 2, smallValuePrecision: 4))
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(agent.dailySpendStatus.color(normalColor: .primary))
    }
}

private struct LiveSignalsCard: View {
    let activeHands: [HandInstance]
    let approvals: [ApprovalItem]
    let hands: [HandDefinition]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Signals")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            if !approvals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pending Approvals")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(approvals.prefix(2)) { approval in
                        ResponsiveValueRow {
                            Label(approval.actionSummary, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        } value: {
                            Text(approval.agentName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !activeHands.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Active Hands")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(activeHands.prefix(3)) { instance in
                        ResponsiveValueRow {
                            Label(instance.displayName(using: hands), systemImage: "hand.raised.fill")
                                .foregroundStyle(.indigo)
                        } value: {
                            Text(instance.localizedStatusLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct AutomationOverviewCard: View {
    let vm: DashboardViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResponsiveAccessoryRow {
                titleLabel
            } accessory: {
                summaryBadge
            }

            LazyVGrid(columns: metricColumns, spacing: 12) {
                automationMetric("\(vm.workflowCount)", label: String(localized: "Workflows"), systemImage: "flowchart")
                automationMetric("\(vm.enabledTriggerCount)/\(vm.triggers.count)", label: String(localized: "Triggers"), systemImage: "bolt.horizontal.circle")
                automationMetric("\(vm.enabledScheduleCount + vm.enabledCronJobCount)", label: String(localized: "Active Jobs"), systemImage: "calendar.badge.clock")
            }

            if vm.automationOverviewIssueCount == 0 {
                Text(String(localized: "Workflow runs, triggers, schedules, and cron jobs are visible without active scheduler pressure."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if vm.failedWorkflowRunCount > 0 {
                        issueRow(
                            icon: "exclamationmark.triangle.fill",
                            color: .red,
                            text: vm.failedWorkflowRunCount == 1
                                ? String(localized: "1 workflow run failed")
                                : String(localized: "\(vm.failedWorkflowRunCount) workflow runs failed")
                        )
                    }
                    if vm.exhaustedTriggerCount > 0 {
                        issueRow(
                            icon: "bolt.badge.clock",
                            color: .orange,
                            text: vm.exhaustedTriggerCount == 1
                                ? String(localized: "1 trigger exhausted")
                                : String(localized: "\(vm.exhaustedTriggerCount) triggers exhausted")
                        )
                    }
                    if vm.stalledCronJobCount > 0 {
                        issueRow(
                            icon: "calendar.badge.exclamationmark",
                            color: .orange,
                            text: vm.stalledCronJobCount == 1
                                ? String(localized: "1 cron job missing next run")
                                : String(localized: "\(vm.stalledCronJobCount) cron jobs missing next run")
                        )
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var titleLabel: some View {
        Text("Automation")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private var summaryBadge: some View {
        PresentationToneBadge(
            text: vm.automationOverviewSummaryLabel,
            tone: vm.automationPressureTone
        )
    }

    private var metricColumns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    @ViewBuilder
    private func automationMetric(_ value: String, label: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder
    private func issueRow(icon: String, color: Color, text: String) -> some View {
        ResponsiveIconDetailRow(horizontalSpacing: 10, verticalSpacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 16)
        } detail: {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DiagnosticsOverviewCard: View {
    let vm: DashboardViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var supervisorEvents: Int {
        vm.supervisorPanicCount + vm.supervisorRestartCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResponsiveAccessoryRow {
                titleLabel
            } accessory: {
                summaryBadge
            }

            LazyVGrid(columns: metricColumns, spacing: 10) {
                diagnosticsMetric(
                    vm.healthDetail?.localizedDatabaseLabel ?? "--",
                    label: String(localized: "Database"),
                    systemImage: "externaldrive"
                )
                diagnosticsMetric(
                    "\(vm.diagnosticsConfigWarningCount)",
                    label: String(localized: "Warnings"),
                    systemImage: "exclamationmark.triangle"
                )
                diagnosticsMetric(
                    "\(supervisorEvents)",
                    label: String(localized: "Supervisor"),
                    systemImage: "bolt.trianglebadge.exclamationmark"
                )
            }

            if let versionInfo = vm.versionInfo {
                Text("\(versionInfo.version) · \(versionInfo.platform)/\(versionInfo.arch) · \(String(versionInfo.gitSHA.prefix(12)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let metrics = vm.metricsSnapshot {
                Text("\(metrics.activeAgents)/\(metrics.totalAgents) active · \(metrics.totalRollingTokens.formatted()) rolling tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var titleLabel: some View {
        Text("Diagnostics")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private var summaryBadge: some View {
        PresentationToneBadge(
            text: vm.diagnosticsSummaryLabel,
            tone: vm.diagnosticsSummaryTone
        )
    }

    private var metricColumns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    @ViewBuilder
    private func diagnosticsMetric(_ value: String, label: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

private struct IntegrationsOverviewCard: View {
    let vm: DashboardViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResponsiveAccessoryRow {
                titleLabel
            } accessory: {
                summaryBadge
            }

            LazyVGrid(columns: metricColumns, spacing: 10) {
                integrationMetric(
                    "\(vm.configuredProviderCount)/\(vm.providers.count)",
                    label: String(localized: "Providers"),
                    systemImage: "key.horizontal"
                )
                integrationMetric(
                    "\(vm.readyChannelCount)/\(vm.configuredChannelCount)",
                    label: String(localized: "Channels"),
                    systemImage: "bubble.left.and.bubble.right"
                )
                integrationMetric(
                    "\(vm.availableCatalogModelCount)",
                    label: String(localized: "Models"),
                    systemImage: "square.stack.3d.up"
                )
            }

            if vm.integrationsOverviewIssueCount == 0 {
                Text(String(localized: "Providers, channels, and the model catalog look consistent from the latest mobile snapshot."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if vm.unreachableLocalProviderCount > 0 {
                        issueRow(
                            icon: "network.slash",
                            color: .orange,
                            text: vm.unreachableLocalProviderCount == 1
                                ? String(localized: "1 local provider probe failed")
                                : String(localized: "\(vm.unreachableLocalProviderCount) local provider probes failed"),
                            detail: vm.unreachableLocalProviders.prefix(2).map(\.displayName).joined(separator: " • ")
                        )
                    }
                    if vm.channelRequiredFieldGapCount > 0 {
                        issueRow(
                            icon: "bubble.left.and.exclamationmark.bubble.right",
                            color: .orange,
                            text: vm.channelRequiredFieldGapCount == 1
                                ? String(localized: "1 configured channel is missing required fields")
                                : String(localized: "\(vm.channelRequiredFieldGapCount) configured channels are missing required fields"),
                            detail: vm.missingRequiredChannelFieldCount == 1
                                ? String(localized: "1 required field missing")
                                : String(localized: "\(vm.missingRequiredChannelFieldCount) required fields missing")
                        )
                    }
                    if vm.hasEmptyModelCatalog {
                        issueRow(
                            icon: "square.stack.3d.up.slash",
                            color: .red,
                            text: String(localized: "The catalog currently exposes no available models"),
                            detail: String(localized: "\(vm.configuredProviderCount) configured providers are not yielding executable models")
                        )
                    }
                    if vm.hasCatalogFreshnessIssue {
                        issueRow(
                            icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                            color: vm.catalogFreshnessIssueTone.color,
                            text: vm.catalogLastSyncDate == nil
                                ? String(localized: "Catalog sync timestamp missing")
                                : String(localized: "Catalog sync is stale"),
                            detail: catalogFreshnessDetail
                        )
                    }
                    if !vm.agentsWithModelDiagnostics.isEmpty {
                        issueRow(
                            icon: "cpu",
                            color: vm.modelDriftIssueTone.color,
                            text: vm.agentsWithModelDiagnostics.count == 1
                                ? String(localized: "1 agent resolves to a drifted catalog model")
                                : String(localized: "\(vm.agentsWithModelDiagnostics.count) agents resolve to drifted catalog models"),
                            detail: vm.agentsWithModelDiagnostics.prefix(2).map { "\($0.agent.name) (\($0.issueSummary))" }.joined(separator: " • ")
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var titleLabel: some View {
        Text("Integrations")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private var summaryBadge: some View {
        PresentationToneBadge(
            text: vm.integrationsOverviewSummaryLabel,
            tone: vm.integrationPressureTone
        )
    }

    private var metricColumns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    private var catalogFreshnessDetail: String {
        guard let catalogLastSyncDate = vm.catalogLastSyncDate else {
            return vm.catalogModels.isEmpty
                ? String(localized: "The server has not reported a sync timestamp and the catalog is empty.")
                : String(localized: "The server did not report a catalog sync timestamp.")
        }
        return String(localized: "Last synced \(RelativeDateTimeFormatter().localizedString(for: catalogLastSyncDate, relativeTo: Date()))")
    }

    @ViewBuilder
    private func integrationMetric(_ value: String, label: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder
    private func issueRow(icon: String, color: Color, text: String, detail: String = "") -> some View {
        ResponsiveIconDetailRow(horizontalSpacing: 10, verticalSpacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 16)
        } detail: {
            issueTextBlock(text: text, detail: detail)
        }
    }

    @ViewBuilder
    private func issueTextBlock(text: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct WatchlistCard: View {
    let items: [AgentAttentionItem]
    let diagnostics: [String: WatchedAgentDiagnosticsSummary]

    private var watchAccentColor: Color {
        PresentationTone.caution.color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Watchlist")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(items.count == 1 ? String(localized: "1 pinned") : String(localized: "\(items.count) pinned"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            ForEach(items.prefix(4)) { item in
                NavigationLink {
                    destination(for: item)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.agent.identity?.emoji ?? "🤖")
                            .font(.body)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(item.agent.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(watchAccentColor)
                                if item.severity > 0 {
                                    PresentationToneBadge(
                                        text: item.reasons.prefix(1).first ?? String(localized: "Needs attention"),
                                        tone: item.tone,
                                        horizontalPadding: 6,
                                        verticalPadding: 2
                                    )
                                }
                                if let summary = diagnostics[item.agent.id], summary.hasIssues {
                                    let issueBadge = watchedAgentDiagnosticIssueCountBadge(summary: summary)
                                    PresentationToneBadge(
                                        text: issueBadge.text,
                                        tone: issueBadge.tone,
                                        horizontalPadding: 6,
                                        verticalPadding: 2
                                    )
                                    let headlineBadge = watchedAgentDiagnosticHeadlineBadge(summary: summary)
                                    PresentationToneBadge(
                                        text: headlineBadge.text,
                                        tone: headlineBadge.tone,
                                        horizontalPadding: 6,
                                        verticalPadding: 2
                                    )
                                }
                            }

                            if item.reasons.isEmpty, diagnostics[item.agent.id] == nil {
                                Text(item.agent.isRunning ? String(localized: "Running normally") : String(localized: "Not currently running"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if let summary = diagnostics[item.agent.id], summary.hasIssues {
                                Text(([item.reasons.prefix(1).first].compactMap { $0 } + [summary.summaryLine]).joined(separator: " • "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            } else {
                                Text(item.reasons.prefix(2).joined(separator: " • "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }

            Label("Use the Agents tab to edit this watchlist", systemImage: "cpu")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func destination(for item: AgentAttentionItem) -> some View {
        if let summary = diagnostics[item.agent.id], summary.failedDeliveries > 0 {
            AgentDeliveriesView(agent: item.agent, initialScope: .failed)
        } else if let summary = diagnostics[item.agent.id], !summary.missingIdentityFiles.isEmpty {
            AgentFilesView(agent: item.agent, initialScope: .missing)
        } else {
            AgentDetailView(agent: item.agent)
        }
    }
}

private struct AttentionAgentsCard: View {
    let items: [AgentAttentionItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Needs Attention")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            ForEach(items.prefix(4)) { item in
                HStack(alignment: .top, spacing: 10) {
                    Text(item.agent.identity?.emoji ?? "🤖")
                        .font(.body)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.agent.name)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            if item.pendingApprovals > 0 {
                                PresentationToneBadge(
                                    text: item.pendingApprovals == 1
                                        ? String(localized: "1 approval")
                                        : String(localized: "\(item.pendingApprovals) approvals"),
                                    tone: .critical,
                                    horizontalPadding: 6,
                                    verticalPadding: 2
                                )
                            }
                        }

                        Text(item.reasons.prefix(2).joined(separator: " • "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct SessionWatchlistCard: View {
    let items: [SessionAttentionItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Session Watchlist")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            ForEach(items.prefix(3)) { item in
                if let sessionQuery = sessionQuery(for: item) {
                    NavigationLink {
                        SessionsView(initialSearchText: sessionQuery, initialFilter: .attention)
                    } label: {
                        sessionSummaryRow(item)
                    }
                    .buttonStyle(.plain)
                } else {
                    sessionSummaryRow(item)
                }
            }

            NavigationLink {
                SessionsView(initialFilter: .attention)
            } label: {
                Label("Sessions", systemImage: "rectangle.stack")
                    .font(.caption.weight(.medium))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func displayTitle(_ item: SessionAttentionItem) -> String {
        let label = (item.session.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? String(item.session.sessionId.prefix(8)) : label
    }

    @ViewBuilder
    private func sessionSummaryRow(_ item: SessionAttentionItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "rectangle.stack")
                .foregroundStyle(item.tone.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                ResponsiveAccessoryRow(verticalSpacing: 4) {
                    Text(displayTitle(item))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                } accessory: {
                    Text(String(localized: "\(item.session.messageCount) msgs"))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(item.agent?.name ?? item.session.agentId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(item.reasons.prefix(2).joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func sessionQuery(for item: SessionAttentionItem) -> String? {
        let agentID = item.agent?.id ?? item.session.agentId
        return agentID.isEmpty ? nil : agentID
    }
}

private struct AuditFeedCard: View {
    @Environment(\.dependencies) private var deps
    let entries: [AuditEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Events")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach(entries.prefix(4)) { entry in
                NavigationLink {
                    if entry.agentId.isEmpty {
                        EventsView(api: deps.apiClient, initialScope: .critical)
                    } else {
                        EventsView(api: deps.apiClient, initialSearchText: entry.agentId, initialScope: .critical)
                    }
                } label: {
                    eventSummaryRow(entry)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func relativeTime(_ timestamp: String) -> String {
        guard let date = parseDate(timestamp) else { return timestamp }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private func eventSummaryRow(_ entry: AuditEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(entry.severity.tone.color)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                ResponsiveAccessoryRow(verticalSpacing: 4) {
                    Text(entry.friendlyAction)
                        .font(.subheadline.weight(.medium))
                } accessory: {
                    Text(relativeTime(entry.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(entry.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(entry.agentId)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
    
    private func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private func localizedUSDCurrency(
    _ value: Double,
    standardPrecision: Int = 2,
    smallValuePrecision: Int? = nil,
    minimumDisplayValue: Double = 0.01
) -> String {
    let style = FloatingPointFormatStyle<Double>.Currency(code: "USD")
    if value == 0 {
        return value.formatted(style.precision(.fractionLength(standardPrecision)))
    }
    if value < minimumDisplayValue {
        return "<\(minimumDisplayValue.formatted(style.precision(.fractionLength(standardPrecision))))"
    }
    let precision = value < 1 ? (smallValuePrecision ?? standardPrecision) : standardPrecision
    return value.formatted(style.precision(.fractionLength(precision)))
}

private struct A2ASummaryCard: View {
    let count: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("A2A Network")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(count)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                    Text(count == 1 ? String(localized: "1 external agent") : String(localized: "\(count) external agents"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "network")
                .font(.system(size: 28))
                .foregroundStyle(.blue.opacity(0.3))
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct AgentPreviewCard: View {
    let agents: [Agent]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Agents")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(localized: "\(agents.count) total"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            ForEach(agents.prefix(4)) { agent in
                HStack(spacing: 8) {
                    Text(agent.identity?.emoji ?? "🤖")
                        .font(.body)
                    Text(agent.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    Circle()
                        .fill(agent.stateTone.color)
                        .frame(width: 8, height: 8)
                }
            }

            if agents.count > 4 {
                Text(String(localized: "+\(agents.count - 4) more"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

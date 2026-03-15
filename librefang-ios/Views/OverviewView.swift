import SwiftUI

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
    private var summaryColumns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
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

                    LazyVGrid(columns: summaryColumns, spacing: 10) {
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
                    }

                    if !vm.providers.isEmpty || !vm.channels.isEmpty || !vm.catalogModels.isEmpty {
                        NavigationLink {
                            IntegrationsView()
                        } label: {
                            IntegrationsOverviewCard(vm: vm)
                        }
                        .buttonStyle(.plain)
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
                    }

                    if !watchedAttentionItems.isEmpty {
                        WatchlistCard(items: watchedAttentionItems, diagnostics: watchedDiagnostics)
                    }

                    if !vm.sessionAttentionItems.isEmpty {
                        SessionWatchlistCard(items: vm.sessionAttentionItems)
                    }

                    if !vm.attentionAgents.isEmpty {
                        AttentionAgentsCard(items: vm.attentionAgents)
                    }

                    if !vm.recentAudit.isEmpty {
                        AuditFeedCard(entries: vm.recentAudit)
                    }

                    if let a2a = vm.a2aAgents, a2a.total > 0 {
                        A2ASummaryCard(count: a2a.total)
                    }

                    if !vm.agents.isEmpty {
                        AgentPreviewCard(agents: vm.attentionAgents.isEmpty ? vm.agents : vm.attentionAgents.map(\.agent))
                    }
                }
                .padding()
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
                                    queueCount: onCallPriorityItems.count,
                                    criticalCount: visibleMonitoringAlerts.filter { $0.severity == .critical }.count,
                                    liveAlertCount: visibleMonitoringAlerts.count
                                )
                            } label: {
                                Label("Open Handoff Center", systemImage: "text.badge.plus")
                            }
                        }

                        Section("Monitoring") {
                            NavigationLink {
                                ApprovalsView()
                            } label: {
                                Label("Open Approvals", systemImage: "checkmark.shield")
                            }

                            NavigationLink {
                                AutomationView()
                            } label: {
                                Label("Open Automation", systemImage: "flowchart")
                            }

                            NavigationLink {
                                DiagnosticsView()
                            } label: {
                                Label("Open Diagnostics", systemImage: "stethoscope")
                            }

                            NavigationLink {
                                IntegrationsView()
                            } label: {
                                Label("Open Integrations", systemImage: "square.3.layers.3d.down.forward")
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Attention", systemImage: "bell.badge")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                PresentationToneBadge(text: snapshotState.overviewLabel, tone: snapshotState.tone)
            }

            if alerts.isEmpty {
                Text(String(localized: "All current alert cards are muted on this iPhone. Open incidents to review or unmute them."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(alerts.prefix(4)) { alert in
                    HStack(alignment: .top, spacing: 10) {
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

            if mutedCount > 0 {
                Text(
                    mutedCount == 1
                        ? String(localized: "1 alert is muted locally.")
                        : String(localized: "\(mutedCount) alerts are muted locally.")
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
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
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Last Handoff", systemImage: "text.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
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

            LazyVGrid(columns: badgeColumns, spacing: 10) {
                HandoffBadge(value: entry.queueCount, label: String(localized: "Queued"))
                HandoffBadge(value: entry.criticalCount, label: String(localized: "Critical"))
                HandoffBadge(value: entry.liveAlertCount, label: String(localized: "Live"))
                HandoffBadge(value: entry.checklist.completedCount, label: String(localized: "Checks"))
            }

            HStack {
                Spacer()
                Text(String(localized: "Open"))
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.12))
                    .clipShape(Capsule())
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
        .padding()
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct StartupConnectionCard: View {
    let serverURL: String
    let showsLoopbackHint: Bool

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)

            VStack(spacing: 6) {
                Text("Connecting to LibreFang")
                    .font(.headline)

                Text(serverURL)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if showsLoopbackHint {
                Text("If this app is running on a physical iPhone, 127.0.0.1 or localhost points to the phone itself. Use your Mac's LAN IP in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(connectionTone.color)
                    .frame(width: 10, height: 10)
                    .overlay {
                        if health?.isHealthy == true && !isStale {
                            Circle()
                                .fill(.green.opacity(0.3))
                                .frame(width: 20, height: 20)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(connectionText)
                        .font(.subheadline.weight(.medium))
                    if let version = health?.version {
                        Text("Server v\(version)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if let date = lastRefresh {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Updated")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
            Text("System Snapshot")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.version)
                        .font(.title3.weight(.bold))
                    Text("Kernel \(status.localizedStatusLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatDuration(status.uptimeSeconds))
                        .font(.headline.monospacedDigit())
                    Text("uptime")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            OverviewMetricRow(label: String(localized: "Default Provider"), value: status.defaultProvider)
            OverviewMetricRow(label: String(localized: "Default Model"), value: status.defaultModel)
            OverviewMetricRow(
                label: String(localized: "Network"),
                value: status.networkEnabled ? String(localized: "Enabled") : String(localized: "Disabled")
            )
            OverviewMetricRow(label: String(localized: "Configured Providers"), value: "\(connectedProviders)")
            if let networkStatus {
                OverviewMetricRow(
                    label: String(localized: "Connected Peers"),
                    value: "\(networkStatus.connectedPeers)/\(networkStatus.totalPeers)"
                )
            }
            OverviewMetricRow(label: String(localized: "Sessions"), value: "\(sessionCount)")
            OverviewMetricRow(label: String(localized: "MCP Servers"), value: "\(mcpConnectedServers)")

            if let usageSummary {
                OverviewMetricRow(
                    label: String(localized: "Total Tokens"),
                    value: (usageSummary.totalInputTokens + usageSummary.totalOutputTokens).formatted()
                )
            }

            if let security {
                OverviewMetricRow(label: String(localized: "Security Features"), value: "\(security.totalFeatures)")
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
            Text("Readiness")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

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
                HStack(spacing: 8) {
                    Text("#\(index + 1)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 20)

                    Text(agent.name)
                        .font(.subheadline)
                        .lineLimit(1)

                    Spacer()

                    Text(localizedUSDCurrency(agent.dailyCostUsd, standardPrecision: 2, smallValuePrecision: 4))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(agent.dailySpendStatus.color(normalColor: .primary))
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
                        HStack {
                            Label(approval.actionSummary, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .lineLimit(1)
                            Spacer()
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
                        HStack {
                            Label(instance.displayName(using: hands), systemImage: "hand.raised.fill")
                                .foregroundStyle(.indigo)
                            Spacer()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Automation")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(vm.automationOverviewSummaryLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(vm.automationPressureTone.color.opacity(0.12))
                    .foregroundStyle(vm.automationPressureTone.color)
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
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
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func issueRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private struct DiagnosticsOverviewCard: View {
    let vm: DashboardViewModel

    private var supervisorEvents: Int {
        vm.supervisorPanicCount + vm.supervisorRestartCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostics")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(vm.diagnosticsSummaryLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(vm.diagnosticsSummaryTone.color.opacity(0.12))
                    .foregroundStyle(vm.diagnosticsSummaryTone.color)
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
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
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct IntegrationsOverviewCard: View {
    let vm: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Integrations")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(vm.integrationsOverviewSummaryLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(vm.integrationPressureTone.color.opacity(0.12))
                    .foregroundStyle(vm.integrationPressureTone.color)
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
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
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func issueRow(icon: String, color: Color, text: String, detail: String = "") -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 16)
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
            Spacer()
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
                                Text(item.pendingApprovals == 1 ? String(localized: "1 approval") : String(localized: "\(item.pendingApprovals) approvals"))
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.red.opacity(0.12))
                                    .foregroundStyle(.red)
                                    .clipShape(Capsule())
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
                Label("Open Session Monitor", systemImage: "rectangle.stack")
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
                HStack {
                    Text(displayTitle(item))
                        .font(.subheadline.weight(.medium))
                    Spacer()
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
                HStack {
                    Text(entry.friendlyAction)
                        .font(.subheadline.weight(.medium))
                    Spacer()
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

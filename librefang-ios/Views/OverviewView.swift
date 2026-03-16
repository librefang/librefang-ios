import SwiftUI

struct OverviewView: View {
    @Environment(\.dependencies) private var deps

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
    private var overviewWatchIssueCount: Int {
        watchedAttentionItems.filter { $0.severity > 0 }.count
    }
    private var shouldShowWatchlistCard: Bool {
        overviewWatchIssueCount > 0
    }
    private var shouldShowSessionWatchlistCard: Bool {
        vm.sessionAttentionCount > 0
    }
    private var shouldShowAttentionAgentsCard: Bool {
        vm.issueAgentCount > 0
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let error = vm.error {
                        ErrorBanner(message: error, onRetry: {
                            await vm.refresh()
                        }, onDismiss: {
                            vm.error = nil
                        })
                    }

                    ConnectionCard(
                        health: vm.health,
                        lastRefresh: vm.lastRefresh,
                        isStale: vm.isDataStale,
                        hasConnectionEvidence: vm.hasPrimaryConnectionEvidence,
                        errorMessage: vm.error
                    )

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

                    if shouldShowWatchlistCard {
                        WatchlistCard(items: watchedAttentionItems, diagnostics: watchedDiagnostics)
                    } else if shouldShowSessionWatchlistCard {
                        SessionWatchlistCard(items: vm.sessionAttentionItems)
                    } else if shouldShowAttentionAgentsCard {
                        AttentionAgentsCard(items: vm.attentionAgents)
                    }

                }
                .padding()
                .monitoringRefreshInteractionGate(
                    isRefreshing: vm.isLoading,
                    restoreDelay: 0.9
                )
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
                        NavigationLink {
                            NightWatchView()
                        } label: {
                            Label("Night Watch", systemImage: "moon.stars")
                        }

                        NavigationLink {
                            RuntimeView()
                        } label: {
                            Label("Runtime", systemImage: "server.rack")
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
                if vm.isLoading && !vm.hasPrimaryConnectionEvidence && vm.error == nil {
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
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow {
                Label("Attention", systemImage: "bell.badge")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } accessory: {
                PresentationToneBadge(text: snapshotState.overviewLabel, tone: snapshotState.tone)
            }

            FlowLayout(spacing: 8) {
                PresentationToneBadge(
                    text: alerts.count == 1 ? String(localized: "1 live") : String(localized: "\(alerts.count) live"),
                    tone: alerts.isEmpty ? .neutral : snapshotState.tone
                )
                if mutedCount > 0 {
                    PresentationToneBadge(
                        text: mutedCount == 1 ? String(localized: "1 muted") : String(localized: "\(mutedCount) muted"),
                        tone: .neutral
                    )
                }
                if snapshotAcknowledged {
                    PresentationToneBadge(text: String(localized: "Acknowledged"), tone: .neutral)
                }
            }

            if alerts.isEmpty {
                Text(String(localized: "All current alert cards are muted on this iPhone. Open incidents to review or unmute them."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(alerts.prefix(3)) { alert in
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
            ResponsiveAccessoryRow(verticalSpacing: 8) {
                Label(String(localized: "Connecting to LibreFang"), systemImage: "network")
                    .font(.headline)
                    .foregroundStyle(.primary)
            } accessory: {
                PresentationToneBadge(text: String(localized: "Connecting"), tone: .warning)
            }

            Text(serverURL)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if showsLoopbackHint {
                Text(String(localized: "Use your Mac LAN IP on a physical iPhone"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    let hasConnectionEvidence: Bool
    let errorMessage: String?

    private var connectionTone: PresentationTone {
        guard let health else {
            if hasConnectionEvidence {
                return .positive
            }
            return errorMessage == nil ? .warning : .critical
        }
        if health.isHealthy && isStale {
            return .warning
        }
        return health.statusTone
    }

    private var inventoryBadgeText: String {
        guard health != nil else {
            if hasConnectionEvidence {
                return String(localized: "Connected")
            }
            return errorMessage == nil ? String(localized: "Connecting") : String(localized: "Disconnected")
        }
        return isStale ? String(localized: "Stale") : String(localized: "Fresh")
    }

    private var inventoryBadgeTone: PresentationTone {
        guard health != nil else {
            if hasConnectionEvidence {
                return .positive
            }
            return errorMessage == nil ? .warning : .critical
        }
        return isStale ? .warning : .positive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow(verticalSpacing: 8) {
                Label(String(localized: "Connection"), systemImage: "network")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } accessory: {
                PresentationToneBadge(text: connectionText, tone: connectionTone)
            }

            FlowLayout(spacing: 8) {
                PresentationToneBadge(text: inventoryBadgeText, tone: inventoryBadgeTone)
                if let health {
                    PresentationToneBadge(text: health.version, tone: .neutral)
                }
                if let date = lastRefresh {
                    PresentationToneBadge(
                        text: String(localized: "Updated \(date.formatted(.relative(presentation: .named)))"),
                        tone: isStale ? .warning : .neutral
                    )
                }
            }

            if let errorMessage, !hasConnectionEvidence {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var connectionText: String {
        guard let health else {
            if hasConnectionEvidence {
                return String(localized: "Connected")
            }
            return errorMessage == nil ? String(localized: "Connecting") : String(localized: "Disconnected")
        }
        if !health.isHealthy {
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
            ResponsiveAccessoryRow(verticalSpacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(String(localized: "System"), systemImage: "server.rack")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Kernel \(status.localizedStatusLabel) · \(formatDuration(status.uptimeSeconds)) uptime"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: status.localizedStatusLabel, tone: status.statusTone)
            }

            FlowLayout(spacing: 8) {
                PresentationToneBadge(text: status.version, tone: .neutral)
                PresentationToneBadge(
                    text: connectedProviders == 1 ? String(localized: "1 provider") : String(localized: "\(connectedProviders) providers"),
                    tone: connectedProviders > 0 ? .positive : .neutral
                )
                PresentationToneBadge(
                    text: sessionCount == 1 ? String(localized: "1 session") : String(localized: "\(sessionCount) sessions"),
                    tone: .neutral
                )
                if let networkStatus {
                    PresentationToneBadge(
                        text: String(localized: "\(networkStatus.connectedPeers)/\(networkStatus.totalPeers) peers"),
                        tone: networkStatus.connectedPeers > 0 ? .positive : .neutral
                    )
                }
                if mcpConnectedServers > 0 {
                    PresentationToneBadge(
                        text: mcpConnectedServers == 1 ? String(localized: "1 MCP") : String(localized: "\(mcpConnectedServers) MCP"),
                        tone: .positive
                    )
                }
                if let usageSummary {
                    PresentationToneBadge(
                        text: (usageSummary.totalInputTokens + usageSummary.totalOutputTokens).formatted(),
                        tone: .neutral
                    )
                }
                if let security {
                    PresentationToneBadge(
                        text: security.totalFeatures == 1 ? String(localized: "1 security feature") : String(localized: "\(security.totalFeatures) security features"),
                        tone: .neutral
                    )
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

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Readiness inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep model, channel, hand, approval, peer, and tooling readiness visible without a long mobile list."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: vm.peerConnectivityStatus.summary, tone: vm.peerConnectivityStatus.tone)
            } facts: {
                Label(String(localized: "Model layer · \(vm.providerReadinessStatus.summary)"), systemImage: "key.horizontal")
                Label(String(localized: "Channels · \(vm.channelReadinessStatus.summary)"), systemImage: "bubble.left.and.bubble.right")
                Label(String(localized: "Hands · \(vm.handReadinessStatus.summary)"), systemImage: "hand.raised")
                Label(String(localized: "Approvals · \(vm.approvalBacklogStatus.summary)"), systemImage: "checkmark.shield")
                Label(String(localized: "Peers · \(vm.peerConnectivityStatus.summary)"), systemImage: "point.3.connected.trianglepath.dotted")
                Label(String(localized: "Tooling · \(vm.mcpConnectivityStatus.summary)"), systemImage: "shippingbox")
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct UsageSnapshotCard: View {
    let usageSummary: UsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Usage inventory keeps spend, tokens, tool calls, and LLM calls visible on mobile."),
                detail: String(localized: "Use this compact slice before opening budget, diagnostics, or per-agent usage views."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: String(localized: "\(usageSummary.callCount.formatted()) calls"),
                        tone: usageSummary.callCount > 0 ? .positive : .neutral
                    )
                    PresentationToneBadge(
                        text: String(localized: "\(usageSummary.totalToolCalls.formatted()) tool calls"),
                        tone: usageSummary.totalToolCalls > 0 ? .warning : .neutral
                    )
                    PresentationToneBadge(
                        text: formatCost(usageSummary.totalCostUsd),
                        tone: usageSummary.totalCostUsd > 0 ? .warning : .neutral
                    )
                }
            }

            HStack(spacing: 10) {
                CompactMetric(value: usageSummary.totalInputTokens.formatted(), label: String(localized: "Input"))
                CompactMetric(value: usageSummary.totalOutputTokens.formatted(), label: String(localized: "Output"))
                CompactMetric(value: usageSummary.totalToolCalls.formatted(), label: String(localized: "Tools"))
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Usage facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep accumulated spend, total traffic, and call volume visible without another full-width totals row."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: formatCost(usageSummary.totalCostUsd),
                    tone: usageSummary.totalCostUsd > 0 ? .warning : .neutral
                )
            } facts: {
                Label(usageSummary.callCount.formatted(), systemImage: "message")
                Label((usageSummary.totalInputTokens + usageSummary.totalOutputTokens).formatted(), systemImage: "number")
                Label(
                    usageSummary.totalToolCalls == 1
                        ? String(localized: "1 tool call")
                        : String(localized: "\(usageSummary.totalToolCalls.formatted()) tool calls"),
                    systemImage: "wrench.and.screwdriver"
                )
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

private struct TopSpendersCard: View {
    let agents: [AgentBudgetItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: agents.isEmpty
                    ? String(localized: "No agent spend has been recorded for today.")
                    : String(localized: "Top spenders stay ranked here before you open the deeper budget monitor."),
                detail: agents.first.map { String(localized: "\($0.name) is currently leading today's spend.") },
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: agents.count == 1 ? String(localized: "1 ranked agent") : String(localized: "\(agents.count) ranked agents"),
                        tone: agents.isEmpty ? .neutral : .positive
                    )
                    if let lead = agents.first {
                        PresentationToneBadge(
                            text: localizedUSDCurrency(lead.dailyCostUsd, standardPrecision: 2, smallValuePrecision: 4),
                            tone: lead.dailySpendStatus.tone
                        )
                    }
                }
            }

            if let lead = agents.first {
                MonitoringFactsRow {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "Spend inventory"))
                            .font(.subheadline.weight(.medium))
                        Text(String(localized: "Keep the lead agent and visible ranking depth summarized before the per-agent spend rows."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } accessory: {
                    PresentationToneBadge(text: lead.name, tone: lead.dailySpendStatus.tone)
                } facts: {
                    Label(localizedUSDCurrency(lead.dailyCostUsd, standardPrecision: 2, smallValuePrecision: 4), systemImage: "dollarsign.circle")
                    Label(
                        agents.count == 1 ? String(localized: "1 ranked agent") : String(localized: "\(agents.count) ranked agents"),
                        systemImage: "person.3"
                    )
                }
            }

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
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Keep the active approvals and running hands visible before opening the runtime monitor."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: approvals.count == 1 ? String(localized: "1 approval") : String(localized: "\(approvals.count) approvals"),
                        tone: approvals.isEmpty ? .neutral : .critical
                    )
                    PresentationToneBadge(
                        text: activeHands.count == 1 ? String(localized: "1 hand") : String(localized: "\(activeHands.count) hands"),
                        tone: activeHands.isEmpty ? .neutral : .positive
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Live inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep pending approvals and active hands visible without opening the deeper runtime queues."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: approvals.isEmpty ? String(localized: "Runtime") : String(localized: "Needs review"),
                    tone: approvals.isEmpty ? .neutral : .warning
                )
            } facts: {
                if let firstApproval = approvals.first {
                    Label(firstApproval.agentName, systemImage: "checkmark.shield")
                }
                if let firstHand = activeHands.first {
                    Label(firstHand.displayName(using: hands), systemImage: "hand.raised")
                }
                if approvals.count > 1 {
                    Label(
                        approvals.count == 1 ? String(localized: "1 pending approval") : String(localized: "\(approvals.count) pending approvals"),
                        systemImage: "bell.badge"
                    )
                }
            }

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

    private var summaryLine: String {
        if approvals.isEmpty && activeHands.isEmpty {
            return String(localized: "No live approvals or autonomous hands are active in this snapshot.")
        }
        return String(localized: "Live approvals and hands stay grouped here for quick runtime triage.")
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

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Automation inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep active workflow depth and scheduler pressure visible before opening the automation monitor."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                summaryBadge
            } facts: {
                Label("\(vm.workflowCount)", systemImage: "flowchart")
                Label("\(vm.workflowRuns.count)", systemImage: "play.circle")
                Label("\(vm.enabledScheduleCount + vm.enabledCronJobCount)", systemImage: "calendar.badge.clock")
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

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Diagnostics inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep database, warning, and supervisor pressure visible before opening the deep diagnostics view."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                summaryBadge
            } facts: {
                Label(vm.healthDetail?.localizedDatabaseLabel ?? "--", systemImage: "externaldrive")
                Label("\(vm.diagnosticsConfigWarningCount)", systemImage: "exclamationmark.triangle")
                Label("\(supervisorEvents)", systemImage: "bolt.trianglebadge.exclamationmark")
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

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Integration inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep provider, channel, and model drift pressure visible before opening the integration monitor."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                summaryBadge
            } facts: {
                Label("\(vm.configuredProviderCount)/\(vm.providers.count)", systemImage: "key.horizontal")
                Label("\(vm.readyChannelCount)/\(vm.configuredChannelCount)", systemImage: "bubble.left.and.bubble.right")
                Label("\(vm.availableCatalogModelCount)", systemImage: "square.stack.3d.up")
                if vm.agentsWithModelDiagnostics.count > 0 {
                    Label("\(vm.agentsWithModelDiagnostics.count)", systemImage: "cpu")
                }
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
            ResponsiveAccessoryRow(verticalSpacing: 8) {
                Label(String(localized: "Watchlist"), systemImage: "star.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } accessory: {
                PresentationToneBadge(
                    text: items.count == 1 ? String(localized: "1 pinned") : String(localized: "\(items.count) pinned"),
                    tone: items.isEmpty ? .neutral : .caution
                )
            }

            let issueCount = items.filter { $0.severity > 0 }.count
            if issueCount > 0 {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: issueCount == 1 ? String(localized: "1 issue") : String(localized: "\(issueCount) issues"),
                        tone: .warning
                    )
                }
            }

            ForEach(items.prefix(2)) { item in
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
            ResponsiveAccessoryRow(verticalSpacing: 8) {
                Label(String(localized: "Needs Attention"), systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } accessory: {
                PresentationToneBadge(
                    text: items.count == 1 ? String(localized: "1 agent") : String(localized: "\(items.count) agents"),
                    tone: items.isEmpty ? .neutral : .warning
                )
            }

            let approvalCount = items.reduce(0) { $0 + $1.pendingApprovals }
            if approvalCount > 0 {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                        tone: .critical
                    )
                }
            }

            ForEach(items.prefix(2)) { item in
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
            ResponsiveAccessoryRow(verticalSpacing: 8) {
                Label(String(localized: "Sessions"), systemImage: "rectangle.stack")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } accessory: {
                PresentationToneBadge(
                    text: items.count == 1 ? String(localized: "1 hotspot") : String(localized: "\(items.count) hotspots"),
                    tone: items.isEmpty ? .neutral : .warning
                )
            }

            let highVolumeCount = items.filter { $0.reasons.contains(where: { $0.localizedCaseInsensitiveContains("message") }) }.count
            if highVolumeCount > 0 {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: highVolumeCount == 1 ? String(localized: "1 high-volume") : String(localized: "\(highVolumeCount) high-volume"),
                        tone: .warning
                    )
                }
            }

            ForEach(items.prefix(2)) { item in
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
            MonitoringSnapshotCard(
                summary: entries.count == 1
                    ? String(localized: "1 recent event is visible in the audit feed.")
                    : String(localized: "\(entries.count) recent events are visible in the audit feed."),
                detail: String(localized: "Critical and recent audit entries stay grouped here before opening the full event feed."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    let criticalCount = entries.filter { $0.severity == .critical }.count
                    PresentationToneBadge(
                        text: entries.count == 1 ? String(localized: "1 event") : String(localized: "\(entries.count) events"),
                        tone: entries.isEmpty ? .neutral : .positive
                    )
                    if criticalCount > 0 {
                        PresentationToneBadge(
                            text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                            tone: .critical
                        )
                    }
                }
            }

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

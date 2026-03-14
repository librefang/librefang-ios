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
        deps.agentWatchlistStore.watchedAgents(from: vm.agents)
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
    private var onCallPriorityItems: [OnCallPriorityItem] {
        vm.onCallPriorityItems(
            visibleAlerts: visibleMonitoringAlerts,
            watchedAttentionItems: watchedAttentionItems
        )
    }
    private var onCallDigestLine: String {
        vm.onCallDigestLine(
            visibleAlerts: visibleMonitoringAlerts,
            watchedAttentionItems: watchedAttentionItems,
            mutedAlertCount: activeMutedAlertCount,
            isAcknowledged: isCurrentSnapshotAcknowledged
        )
    }
    private var handoffText: String {
        vm.onCallHandoffText(
            visibleAlerts: visibleMonitoringAlerts,
            watchedAttentionItems: watchedAttentionItems,
            mutedAlertCount: activeMutedAlertCount,
            isAcknowledged: isCurrentSnapshotAcknowledged
        )
    }
    private var preferredOnCallSurface: OnCallSurfacePreference {
        deps.onCallFocusStore.preferredSurface
    }
    private var latestHandoffGapLabel: String? {
        deps.onCallHandoffStore.timelineItems.first?.gapToOlderEntry.map(OnCallHandoffStore.formatInterval)
    }
    private let summaryColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

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
                            RecentHandoffCard(entry: latestHandoff, gapLabel: latestHandoffGapLabel)
                        }
                        .buttonStyle(.plain)
                    }

                    LazyVGrid(columns: summaryColumns, spacing: 10) {
                        StatBadge(
                            value: "\(vm.runningCount)",
                            label: "Running",
                            icon: "play.circle.fill",
                            color: .green
                        )
                        StatBadge(
                            value: formatCost(vm.budget?.dailySpend),
                            label: "Today",
                            icon: "dollarsign.circle",
                            color: costColor(vm.budget?.dailyPct)
                        )
                        StatBadge(
                            value: "\(vm.pendingApprovalCount)",
                            label: "Approvals",
                            icon: "exclamationmark.shield",
                            color: vm.pendingApprovalCount > 0 ? .red : .green
                        )
                        StatBadge(
                            value: "\(vm.configuredProviderCount)",
                            label: "Providers",
                            icon: "key.horizontal",
                            color: vm.configuredProviderCount > 0 ? .blue : .orange
                        )
                        StatBadge(
                            value: "\(vm.readyChannelCount)",
                            label: "Channels",
                            icon: "bubble.left.and.bubble.right",
                            color: vm.readyChannelCount > 0 ? .teal : .secondary
                        )
                        StatBadge(
                            value: "\(vm.activeHandCount)",
                            label: "Hands",
                            icon: "hand.raised",
                            color: vm.degradedHandCount > 0 ? .orange : .indigo
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

                    ReadinessCard(
                        providerCount: vm.configuredProviderCount,
                        channelCount: vm.readyChannelCount,
                        activeHands: vm.activeHandCount,
                        degradedHands: vm.degradedHandCount,
                        pendingApprovals: vm.pendingApprovalCount,
                        connectedPeers: vm.connectedPeerCount,
                        totalPeers: vm.totalPeerCount,
                        connectedMCPServers: vm.connectedMCPServerCount,
                        configuredMCPServers: vm.configuredMCPServerCount
                    )

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
                        LiveSignalsCard(activeHands: vm.activeHands, approvals: vm.approvals)
                    }

                    if !watchedAttentionItems.isEmpty {
                        WatchlistCard(items: watchedAttentionItems)
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
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        NavigationLink {
                            StandbyDigestView()
                        } label: {
                            Image(systemName: "rectangle.inset.filled")
                        }

                        NavigationLink {
                            NightWatchView()
                        } label: {
                            Image(systemName: "moon.stars")
                        }

                        NavigationLink {
                            IncidentsView()
                        } label: {
                            Image(systemName: "bell.badge")
                        }

                        NavigationLink {
                            HandoffCenterView(
                                summary: handoffText,
                                queueCount: onCallPriorityItems.count,
                                criticalCount: visibleMonitoringAlerts.filter { $0.severity == .critical }.count,
                                liveAlertCount: visibleMonitoringAlerts.count
                            )
                        } label: {
                            Image(systemName: "text.badge.plus")
                        }
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
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Connecting to server...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func formatCost(_ value: Double?) -> String {
        guard let value else { return "--" }
        if value < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", value)
    }

    private func costColor(_ pct: Double?) -> Color {
        guard let pct else { return .primary }
        if pct > 0.9 { return .red }
        if pct > 0.7 { return .orange }
        return .green
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Attention", systemImage: "bell.badge")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(statusText)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.12))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }

            if alerts.isEmpty {
                Text("All current alert cards are muted on this iPhone. Open incidents to review or unmute them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(alerts.prefix(4)) { alert in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: alert.symbolName)
                            .foregroundStyle(color(for: alert.severity))
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
                Text(mutedCount == 1 ? "1 alert is muted locally." : "\(mutedCount) alerts are muted locally.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statusColor: Color {
        if alerts.isEmpty && mutedCount > 0 {
            return .secondary
        }
        return snapshotAcknowledged ? .orange : .red
    }

    private var statusText: String {
        if alerts.isEmpty && mutedCount > 0 {
            return "Muted"
        }
        if snapshotAcknowledged {
            return "Acked"
        }
        return alerts.count == 1 ? "1 live" : "\(alerts.count) live"
    }

    private func color(for severity: MonitoringAlertSeverity) -> Color {
        switch severity {
        case .critical:
            .red
        case .warning:
            .orange
        case .info:
            .yellow
        }
    }
}

private struct RecentHandoffCard: View {
    let entry: OnCallHandoffEntry
    let gapLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Last Handoff", systemImage: "text.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(statusText(for: entry))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(for: entry).opacity(0.12))
                    .foregroundStyle(statusColor(for: entry))
                    .clipShape(Capsule())
            }

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

            HStack(spacing: 10) {
                HandoffBadge(value: entry.queueCount, label: "Queued")
                HandoffBadge(value: entry.criticalCount, label: "Critical")
                HandoffBadge(value: entry.liveAlertCount, label: "Live")
                HandoffBadge(value: entry.checklist.completedCount, label: "Checks")
                Spacer()
                Text("Open")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(entry.checklist.pendingLabels.isEmpty ? "Checklist complete" : "Pending: \(entry.checklist.pendingLabels.joined(separator: ", "))")
                .font(.caption2)
                .foregroundStyle(entry.checklist.pendingLabels.isEmpty ? .green : .secondary)
                .lineLimit(2)

            if let gapLabel {
                Text("Gap to prior handoff: \(gapLabel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statusText(for entry: OnCallHandoffEntry) -> String {
        if Date().timeIntervalSince(entry.createdAt) >= 8 * 60 * 60 {
            return "Stale"
        }
        return "Fresh"
    }

    private func statusColor(for entry: OnCallHandoffEntry) -> Color {
        statusText(for: entry) == "Fresh" ? .green : .orange
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

private struct ConnectionCard: View {
    let health: HealthStatus?
    let lastRefresh: Date?
    let isStale: Bool

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(connectionColor)
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
            return "Connected (stale)"
        }
        return String(localized: "Connected")
    }

    private var connectionColor: Color {
        if health?.isHealthy != true {
            return .red
        }
        return isStale ? .orange : .green
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
                    Text("Kernel \(status.status)")
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

            OverviewMetricRow(label: "Default Provider", value: status.defaultProvider)
            OverviewMetricRow(label: "Default Model", value: status.defaultModel)
            OverviewMetricRow(label: "Network", value: status.networkEnabled ? "Enabled" : "Disabled")
            OverviewMetricRow(label: "Configured Providers", value: "\(connectedProviders)")
            if let networkStatus {
                OverviewMetricRow(label: "Connected Peers", value: "\(networkStatus.connectedPeers)/\(networkStatus.totalPeers)")
            }
            OverviewMetricRow(label: "Sessions", value: "\(sessionCount)")
            OverviewMetricRow(label: "MCP Servers", value: "\(mcpConnectedServers)")

            if let usageSummary {
                OverviewMetricRow(
                    label: "Total Tokens",
                    value: (usageSummary.totalInputTokens + usageSummary.totalOutputTokens).formatted()
                )
            }

            if let security {
                OverviewMetricRow(label: "Security Features", value: "\(security.totalFeatures)")
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
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
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
    let providerCount: Int
    let channelCount: Int
    let activeHands: Int
    let degradedHands: Int
    let pendingApprovals: Int
    let connectedPeers: Int
    let totalPeers: Int
    let connectedMCPServers: Int
    let configuredMCPServers: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Readiness")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            ReadinessRow(
                title: "Model Layer",
                subtitle: providerCount > 0 ? "\(providerCount) provider ready" : "No provider configured",
                color: providerCount > 0 ? .green : .orange
            )
            ReadinessRow(
                title: "Channels",
                subtitle: channelCount > 0 ? "\(channelCount) channel delivering" : "No channel configured",
                color: channelCount > 0 ? .green : .secondary
            )
            ReadinessRow(
                title: "Autonomous Hands",
                subtitle: activeHands > 0 ? "\(activeHands) active, \(degradedHands) degraded" : "No active hands",
                color: degradedHands > 0 ? .orange : activeHands > 0 ? .green : .secondary
            )
            ReadinessRow(
                title: "Approvals",
                subtitle: pendingApprovals > 0 ? "\(pendingApprovals) action waiting" : "No approval backlog",
                color: pendingApprovals > 0 ? .red : .green
            )
            ReadinessRow(
                title: "Peer Network",
                subtitle: totalPeers > 0 ? "\(connectedPeers)/\(totalPeers) peer links active" : "No peer links discovered",
                color: connectedPeers > 0 ? .green : .secondary
            )
            ReadinessRow(
                title: "Tooling",
                subtitle: configuredMCPServers > 0 ? "\(connectedMCPServers)/\(configuredMCPServers) MCP servers online" : "No MCP extension servers configured",
                color: connectedMCPServers > 0 ? .green : configuredMCPServers > 0 ? .orange : .secondary
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
                CompactMetric(value: usageSummary.totalInputTokens.formatted(), label: "Input")
                CompactMetric(value: usageSummary.totalOutputTokens.formatted(), label: "Output")
                CompactMetric(value: usageSummary.totalToolCalls.formatted(), label: "Tools")
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
        if value == 0 { return "$0.00" }
        if value < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", value)
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
    let label: LocalizedStringKey
    let spend: Double
    let limit: Double
    let pct: Double

    var body: some View {
        VStack(spacing: 8) {
            Gauge(value: min(pct, 1.0)) {
                EmptyView()
            } currentValueLabel: {
                Text("\(Int(pct * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(gaugeColor)
            .scaleEffect(0.85)

            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            Text("$\(spend, specifier: spend < 1 ? "%.4f" : "%.2f")")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }

    private var gaugeColor: Color {
        if pct > 0.9 { return .red }
        if pct > 0.7 { return .orange }
        return .green
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

                    Text("$\(agent.dailyCostUsd, specifier: "%.4f")")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(agent.dailyCostUsd > 1.0 ? .red : .primary)
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
                            Label(instance.handId.capitalized, systemImage: "hand.raised.fill")
                                .foregroundStyle(.indigo)
                            Spacer()
                            Text(instance.status.capitalized)
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

private struct WatchlistCard: View {
    let items: [AgentAttentionItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Watchlist")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(items.count == 1 ? "1 pinned" : "\(items.count) pinned")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            ForEach(items.prefix(4)) { item in
                NavigationLink {
                    AgentDetailView(agent: item.agent)
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
                                    .foregroundStyle(.yellow)
                                if item.severity > 0 {
                                    Text(item.reasons.prefix(1).first ?? "Needs attention")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(signalColor(for: item).opacity(0.12))
                                        .foregroundStyle(signalColor(for: item))
                                        .clipShape(Capsule())
                                }
                            }

                            if item.reasons.isEmpty {
                                Text(item.agent.isRunning ? "Running normally" : "Not currently running")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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

    private func signalColor(for item: AgentAttentionItem) -> Color {
        if item.pendingApprovals > 0 || item.hasAuthIssue {
            return .red
        }
        if item.severity > 0 {
            return .orange
        }
        return .secondary
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
                                Text(item.pendingApprovals == 1 ? "1 approval" : "\(item.pendingApprovals) approvals")
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
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "rectangle.stack")
                        .foregroundStyle(item.severity >= 6 ? .red : .orange)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(displayTitle(item))
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(item.session.messageCount) msgs")
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

            NavigationLink {
                SessionsView()
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
}

private struct AuditFeedCard: View {
    let entries: [AuditEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Events")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach(entries.prefix(4)) { entry in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(severityColor(entry.severity))
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
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func severityColor(_ severity: AuditEventSeverity) -> Color {
        switch severity {
        case .critical:
            .red
        case .warning:
            .orange
        case .info:
            .blue
        }
    }

    private func relativeTime(_ timestamp: String) -> String {
        guard let date = parseDate(timestamp) else { return timestamp }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
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
                Text("\(agents.count) total")
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
                        .fill(agent.isRunning ? .green : .gray)
                        .frame(width: 8, height: 8)
                }
            }

            if agents.count > 4 {
                Text("+\(agents.count - 4) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

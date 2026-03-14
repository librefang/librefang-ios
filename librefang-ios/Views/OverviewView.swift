import SwiftUI

struct OverviewView: View {
    @Environment(\.dependencies) private var deps

    private var vm: DashboardViewModel { deps.dashboardViewModel }
    private let summaryColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var alerts: [OverviewAlert] {
        var items: [OverviewAlert] = []

        if vm.health?.isHealthy != true {
            items.append(.init(
                title: "Server disconnected",
                detail: "The app cannot confirm the current LibreFang status.",
                color: .red,
                icon: "bolt.horizontal.circle"
            ))
        }

        if let budget = vm.budget {
            let maxPct = max(budget.hourlyPct, budget.dailyPct, budget.monthlyPct)
            if maxPct >= budget.alertThreshold, budget.alertThreshold > 0 {
                items.append(.init(
                    title: "Budget threshold reached",
                    detail: "Current spend is at \(Int(maxPct * 100))% of the configured limit.",
                    color: .orange,
                    icon: "chart.line.uptrend.xyaxis"
                ))
            }
        }

        if vm.pendingApprovalCount > 0 {
            items.append(.init(
                title: "\(vm.pendingApprovalCount) approval waiting",
                detail: "Sensitive agent actions are blocked pending operator review.",
                color: .red,
                icon: "exclamationmark.shield"
            ))
        }

        if vm.degradedHandCount > 0 {
            items.append(.init(
                title: "\(vm.degradedHandCount) hand degraded",
                detail: "At least one autonomous hand is active but not fully healthy.",
                color: .orange,
                icon: "hand.raised.slash"
            ))
        }

        if let network = vm.networkStatus, network.enabled, network.connectedPeers == 0 {
            items.append(.init(
                title: "Peer network idle",
                detail: "OFP networking is enabled but no peers are currently connected.",
                color: .yellow,
                icon: "point.3.connected.trianglepath.dotted"
            ))
        }

        if vm.configuredProviderCount == 0 {
            items.append(.init(
                title: "No provider configured",
                detail: "Agents may exist, but the model layer is not ready.",
                color: .yellow,
                icon: "key.slash"
            ))
        }

        return items
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

                    ConnectionCard(health: vm.health, lastRefresh: vm.lastRefresh)

                    if !alerts.isEmpty {
                        AlertsCard(alerts: alerts)
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
                            networkStatus: vm.networkStatus
                        )
                    }

                    ReadinessCard(
                        providerCount: vm.configuredProviderCount,
                        channelCount: vm.readyChannelCount,
                        activeHands: vm.activeHandCount,
                        degradedHands: vm.degradedHandCount,
                        pendingApprovals: vm.pendingApprovalCount,
                        connectedPeers: vm.connectedPeerCount,
                        totalPeers: vm.totalPeerCount
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

                    if let a2a = vm.a2aAgents, a2a.total > 0 {
                        A2ASummaryCard(count: a2a.total)
                    }

                    if !vm.agents.isEmpty {
                        AgentPreviewCard(agents: vm.agents)
                    }
                }
                .padding()
            }
            .navigationTitle("LibreFang")
            .refreshable {
                await vm.refresh()
            }
            .task {
                if vm.agents.isEmpty && vm.status == nil {
                    await vm.refresh()
                }
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
}

private struct OverviewAlert: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let color: Color
    let icon: String
}

private struct AlertsCard: View {
    let alerts: [OverviewAlert]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Attention", systemImage: "bell.badge")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(alerts.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            ForEach(alerts.prefix(4)) { alert in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: alert.icon)
                        .foregroundStyle(alert.color)
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
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct ConnectionCard: View {
    let health: HealthStatus?
    let lastRefresh: Date?

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(health?.isHealthy == true ? .green : .red)
                    .frame(width: 10, height: 10)
                    .overlay {
                        if health?.isHealthy == true {
                            Circle()
                                .fill(.green.opacity(0.3))
                                .frame(width: 20, height: 20)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(health?.isHealthy == true ? String(localized: "Connected") : String(localized: "Disconnected"))
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
}

private struct SystemSnapshotCard: View {
    let status: SystemStatus
    let security: SecurityStatus?
    let usageSummary: UsageSummary?
    let connectedProviders: Int
    let networkStatus: NetworkStatus?

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

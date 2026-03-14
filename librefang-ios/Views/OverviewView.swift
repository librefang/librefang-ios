import SwiftUI

struct OverviewView: View {
    @Environment(\.dependencies) private var deps

    private var vm: DashboardViewModel { deps.dashboardViewModel }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Error
                    if let error = vm.error {
                        ErrorBanner(message: error, onRetry: {
                            await vm.refresh()
                        }, onDismiss: {
                            vm.error = nil
                        })
                    }

                    // Connection
                    ConnectionCard(health: vm.health, lastRefresh: vm.lastRefresh)

                    // Quick Stats
                    HStack(spacing: 10) {
                        StatBadge(
                            value: "\(vm.runningCount)",
                            label: "Running",
                            icon: "play.circle.fill",
                            color: .green
                        )
                        StatBadge(
                            value: "\(vm.totalCount)",
                            label: "Total",
                            icon: "cpu",
                            color: .blue
                        )
                        StatBadge(
                            value: formatCost(vm.budget?.dailySpend),
                            label: "Today",
                            icon: "dollarsign.circle",
                            color: costColor(vm.budget?.dailyPct)
                        )
                    }

                    // Budget Gauges
                    if let budget = vm.budget {
                        BudgetGaugesCard(budget: budget)
                    }

                    // Top Spenders
                    if let ranking = vm.budgetAgents, !ranking.agents.isEmpty {
                        TopSpendersCard(agents: ranking.agents)
                    }

                    // A2A
                    if let a2a = vm.a2aAgents, a2a.total > 0 {
                        A2ASummaryCard(count: a2a.total)
                    }

                    // Agent List Preview
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
                if vm.agents.isEmpty {
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

// MARK: - Connection Card

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

// MARK: - Budget Gauges Card

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

// MARK: - Top Spenders Card

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

// MARK: - A2A Summary Card

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

// MARK: - Agent Preview Card

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

            ForEach(agents.prefix(3)) { agent in
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

            if agents.count > 3 {
                Text("+\(agents.count - 3) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

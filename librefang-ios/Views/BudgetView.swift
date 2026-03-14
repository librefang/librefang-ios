import SwiftUI
import Charts

struct BudgetView: View {
    @Environment(\.dependencies) private var deps
    @State private var sortOrder: BudgetSort = .costDesc

    private var vm: DashboardViewModel { deps.dashboardViewModel }

    private var sortedAgents: [AgentBudgetItem] {
        guard let agents = vm.budgetAgents?.agents else { return [] }
        switch sortOrder {
        case .costDesc: return agents.sorted { $0.dailyCostUsd > $1.dailyCostUsd }
        case .costAsc: return agents.sorted { $0.dailyCostUsd < $1.dailyCostUsd }
        case .name: return agents.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let budget = vm.budget {
                    // Chart
                    Section {
                        BudgetBarChart(budget: budget)
                            .frame(height: 180)
                            .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                    }

                    // Overview Numbers
                    Section("Limits") {
                        BudgetLimitRow(label: "Hourly", spend: budget.hourlySpend, limit: budget.hourlyLimit, pct: budget.hourlyPct)
                        BudgetLimitRow(label: "Daily", spend: budget.dailySpend, limit: budget.dailyLimit, pct: budget.dailyPct)
                        BudgetLimitRow(label: "Monthly", spend: budget.monthlySpend, limit: budget.monthlyLimit, pct: budget.monthlyPct)
                    }

                    // Alert Threshold
                    Section("Alert") {
                        LabeledContent("Threshold") {
                            Text("\(Int(budget.alertThreshold * 100))%")
                                .foregroundStyle(.orange)
                        }
                        if let maxTokens = budget.defaultMaxLlmTokensPerHour, maxTokens > 0 {
                            LabeledContent("Default Token Limit/hr") {
                                Text(maxTokens.formatted())
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                // Per-Agent Ranking
                if !sortedAgents.isEmpty {
                    Section {
                        ForEach(sortedAgents) { item in
                            AgentCostRow(item: item)
                        }
                    } header: {
                        HStack {
                            Text("Per-Agent Cost")
                            Spacer()
                            Menu {
                                Picker("Sort", selection: $sortOrder) {
                                    ForEach(BudgetSort.allCases, id: \.self) { sort in
                                        Label(sort.label, systemImage: sort.icon)
                                    }
                                }
                            } label: {
                                Label("Sort", systemImage: "arrow.up.arrow.down")
                                    .font(.caption)
                            }
                        }
                    }
                }

                if vm.budget == nil && !vm.isLoading {
                    ContentUnavailableView(
                        "No Budget Data",
                        systemImage: "chart.bar",
                        description: Text("Pull to refresh or check server connection.")
                    )
                }
            }
            .navigationTitle("Budget")
            .refreshable {
                HapticManager.impact(.light)
                await vm.refresh()
            }
            .overlay {
                if vm.isLoading && vm.budget == nil {
                    ProgressView("Loading...")
                }
            }
            .task {
                if vm.budget == nil {
                    await vm.refresh()
                }
            }
        }
    }
}

// MARK: - Sort

private enum BudgetSort: CaseIterable {
    case costDesc, costAsc, name

    var label: String {
        switch self {
        case .costDesc: String(localized: "Cost (High to Low)")
        case .costAsc: String(localized: "Cost (Low to High)")
        case .name: String(localized: "Name")
        }
    }

    var icon: String {
        switch self {
        case .costDesc: "arrow.down"
        case .costAsc: "arrow.up"
        case .name: "textformat.abc"
        }
    }
}

// MARK: - Bar Chart

private struct BudgetBarChart: View {
    let budget: BudgetOverview

    private var data: [ChartEntry] {
        [
            ChartEntry(period: String(localized: "Hourly"), spend: budget.hourlySpend, limit: budget.hourlyLimit),
            ChartEntry(period: String(localized: "Daily"), spend: budget.dailySpend, limit: budget.dailyLimit),
            ChartEntry(period: String(localized: "Monthly"), spend: budget.monthlySpend, limit: budget.monthlyLimit),
        ]
    }

    var body: some View {
        Chart(data) { entry in
            BarMark(
                x: .value("Period", entry.period),
                y: .value("Amount", entry.spend)
            )
            .foregroundStyle(barColor(spend: entry.spend, limit: entry.limit).gradient)
            .cornerRadius(4)

            // Limit line
            if entry.limit > 0 {
                RuleMark(y: .value("Limit", entry.limit))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.red.opacity(0.5))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("$\(entry.limit, specifier: "%.0f")")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.6))
                    }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text("$\(amount, specifier: "%.0f")")
                            .font(.caption2)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func barColor(spend: Double, limit: Double) -> Color {
        guard limit > 0 else { return .blue }
        let pct = spend / limit
        if pct > 0.9 { return .red }
        if pct > 0.7 { return .orange }
        return .blue
    }
}

private struct ChartEntry: Identifiable {
    let period: String
    let spend: Double
    let limit: Double
    var id: String { period }
}

// MARK: - Budget Limit Row

private struct BudgetLimitRow: View {
    let label: LocalizedStringKey
    let spend: Double
    let limit: Double
    let pct: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text("$\(spend, specifier: "%.4f")")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                Text("/ $\(limit, specifier: "%.2f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("(\(Int(pct * 100))%)")
                    .font(.caption2)
                    .foregroundStyle(pct > 0.9 ? .red : pct > 0.7 ? .orange : .secondary)
            }
            Gauge(value: min(pct, 1.0)) { EmptyView() }
                .gaugeStyle(.linearCapacity)
                .tint(pct > 0.9 ? .red : pct > 0.7 ? .orange : .green)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Agent Cost Row

private struct AgentCostRow: View {
    let item: AgentBudgetItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline)
                Text(String(item.agentId.prefix(12)) + "...")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("$\(item.dailyCostUsd, specifier: "%.4f")")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(item.dailyCostUsd > 1.0 ? .red : .primary)
                if let limit = item.dailyLimit, limit > 0 {
                    Text("limit ") + Text("$\(limit, specifier: "%.2f")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

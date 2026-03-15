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

    private var sortedModels: [ModelUsage] {
        vm.usageByModel.sorted { lhs, rhs in
            if lhs.totalCostUsd == rhs.totalCostUsd {
                return lhs.totalTokens > rhs.totalTokens
            }
            return lhs.totalCostUsd > rhs.totalCostUsd
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let budget = vm.budget {
                    Section {
                        BudgetBarChart(budget: budget)
                            .frame(height: 180)
                            .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                    }

                    Section("Limits") {
                        BudgetLimitRow(label: "Hourly", spend: budget.hourlySpend, limit: budget.hourlyLimit, pct: budget.hourlyPct)
                        BudgetLimitRow(label: "Daily", spend: budget.dailySpend, limit: budget.dailyLimit, pct: budget.dailyPct)
                        BudgetLimitRow(label: "Monthly", spend: budget.monthlySpend, limit: budget.monthlyLimit, pct: budget.monthlyPct)
                    }

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

                if let usageSummary = vm.usageSummary {
                    Section("Cost Signals") {
                        LabeledContent("Total Recorded Cost") {
                            Text(formatCost(usageSummary.totalCostUsd))
                                .monospacedDigit()
                        }
                        LabeledContent("Avg Cost / Call") {
                            Text(formatCost(averageCostPerCall(usageSummary)))
                                .monospacedDigit()
                        }
                        if let projected = projectedMonthlyCost(usageSummary) {
                            LabeledContent("Projected 30-Day Cost") {
                                Text(formatCost(projected))
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                if !vm.usageDaily.isEmpty {
                    Section {
                        DailyCostTrendChart(days: vm.usageDaily)
                            .frame(height: 210)
                            .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                    } header: {
                        Text("7-Day Cost Trend")
                    } footer: {
                        Text("Today: \(formatCost(vm.usageTodayCost))")
                    }

                    Section("Daily Breakdown") {
                        ForEach(vm.usageDaily.reversed()) { day in
                            DailyUsageRow(day: day)
                        }
                    }
                }

                if !sortedModels.isEmpty {
                    Section {
                        CostDistributionCard(models: sortedModels)
                            .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                    } header: {
                        Text("Model Cost Distribution")
                    }

                    Section {
                        ForEach(sortedModels.prefix(8)) { model in
                            ModelCostRow(model: model, maxCost: max(vm.highestModelCost, 0.01))
                        }
                    } header: {
                        Text("By Model")
                    } footer: {
                        if sortedModels.count > 8 {
                            Text("Showing top 8 of \(sortedModels.count) models")
                        }
                    }
                }

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
                                            .tag(sort)
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
                if vm.isLoading && vm.budget == nil && vm.usageDaily.isEmpty {
                    ProgressView("Loading...")
                }
            }
            .task {
                if vm.budget == nil && vm.usageDaily.isEmpty {
                    await vm.refresh()
                }
            }
        }
    }

    private func formatCost(_ value: Double) -> String {
        return localizedUSDCurrency(value)
    }

    private func averageCostPerCall(_ usage: UsageSummary) -> Double {
        guard usage.callCount > 0 else { return 0 }
        return usage.totalCostUsd / Double(usage.callCount)
    }

    private func projectedMonthlyCost(_ usage: UsageSummary) -> Double? {
        guard usage.totalCostUsd > 0,
              let firstEventDate = vm.firstUsageEventDate,
              let firstDate = firstEventDate.usageDate
        else {
            return nil
        }

        let elapsed = max(Date().timeIntervalSince(firstDate), 86_400)
        let days = elapsed / 86_400
        return (usage.totalCostUsd / days) * 30
    }
}

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

private struct BudgetBarChart: View {
    let budget: BudgetOverview

    private var data: [BudgetChartEntry] {
        [
            BudgetChartEntry(period: String(localized: "Hourly"), spend: budget.hourlySpend, limit: budget.hourlyLimit),
            BudgetChartEntry(period: String(localized: "Daily"), spend: budget.dailySpend, limit: budget.dailyLimit),
            BudgetChartEntry(period: String(localized: "Monthly"), spend: budget.monthlySpend, limit: budget.monthlyLimit),
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

            if entry.limit > 0 {
                RuleMark(y: .value("Limit", entry.limit))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.red.opacity(0.5))
                    .annotation(position: .top, alignment: .trailing) {
                        Text(localizedUSDCurrency(entry.limit, standardPrecision: 0))
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.6))
                    }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(localizedUSDCurrency(amount, standardPrecision: 0))
                            .font(.caption2)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func barColor(spend: Double, limit: Double) -> Color {
        let pct = limit > 0 ? spend / limit : nil
        return (StatusPresentation.budgetUtilizationStatus(for: pct) ?? .normal).color(normalColor: .blue)
    }
}

private struct DailyCostTrendChart: View {
    let days: [DailyUsage]

    private var chartDays: [DailyUsagePoint] {
        days.compactMap { day in
            guard let date = day.date.usageDate else { return nil }
            return DailyUsagePoint(date: date, cost: day.costUsd, tokens: day.tokens, calls: day.calls)
        }
    }

    var body: some View {
        Chart(chartDays) { day in
            AreaMark(
                x: .value("Date", day.date),
                y: .value("Cost", day.cost)
            )
            .foregroundStyle(.teal.opacity(0.16))

            LineMark(
                x: .value("Date", day.date),
                y: .value("Cost", day.cost)
            )
            .foregroundStyle(.teal)
            .lineStyle(.init(lineWidth: 2.5))

            PointMark(
                x: .value("Date", day.date),
                y: .value("Cost", day.cost)
            )
            .foregroundStyle(.teal)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick()
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(localizedUSDCurrency(amount, standardPrecision: amount >= 1 ? 0 : 2))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let latest = chartDays.last,
                   let xPosition = proxy.position(forX: latest.date) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localizedUSDCurrency(latest.cost, standardPrecision: 2, smallValuePrecision: 4))
                            .font(.caption.weight(.semibold))
                        Text("\(latest.tokens.formatted()) tokens")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .position(x: min(xPosition + 40, geometry.size.width - 48), y: 20)
                }
            }
        }
        .padding(.horizontal)
    }
}

private struct CostDistributionCard: View {
    let models: [ModelUsage]

    private var totalCost: Double {
        models.reduce(0) { $0 + $1.totalCostUsd }
    }

    private var topSlices: [CostSlice] {
        let ranked = models.sorted { $0.totalCostUsd > $1.totalCostUsd }
        let head = Array(ranked.prefix(4))
        let tail = ranked.dropFirst(4)
        let othersCost = tail.reduce(0) { $0 + $1.totalCostUsd }

        var slices = head.enumerated().map { index, model in
            CostSlice(
                id: model.id,
                title: shortModelName(model.model),
                value: model.totalCostUsd,
                color: palette[index % palette.count]
            )
        }

        if othersCost > 0 {
            slices.append(CostSlice(
                id: "others",
                title: String(localized: "Others"),
                value: othersCost,
                color: .gray
            ))
        }

        return slices
    }

    private let palette: [Color] = [.orange, .blue, .green, .pink, .indigo]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatCost(totalCost))
                    .font(.title3.monospacedDigit().weight(.semibold))
                Text("Accumulated model cost")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                let spacing = CGFloat(max(topSlices.count - 1, 0) * 4)
                let availableWidth = max(0, geometry.size.width - spacing)
                HStack(spacing: 4) {
                    ForEach(topSlices) { slice in
                        Capsule()
                            .fill(slice.color)
                            .frame(width: max(10, availableWidth * CGFloat(slice.value / max(totalCost, 0.0001))), height: 16)
                    }
                }
            }
            .frame(height: 16)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(topSlices) { slice in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(slice.color)
                            .frame(width: 8, height: 8)
                        Text(slice.title)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(formatCost(slice.value))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(percentText(for: slice.value))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    private func percentText(for value: Double) -> String {
        guard totalCost > 0 else { return "0%" }
        return "\(Int((value / totalCost) * 100))%"
    }

    private func formatCost(_ value: Double) -> String {
        localizedUSDCurrency(value)
    }

    private func shortModelName(_ name: String) -> String {
        if let last = name.split(separator: "/").last {
            return String(last)
        }
        return name
    }
}

private struct BudgetChartEntry: Identifiable {
    let period: String
    let spend: Double
    let limit: Double
    var id: String { period }
}

private struct DailyUsagePoint: Identifiable {
    let date: Date
    let cost: Double
    let tokens: Int
    let calls: Int
    var id: Date { date }
}

private struct CostSlice: Identifiable {
    let id: String
    let title: String
    let value: Double
    let color: Color
}

private struct BudgetLimitRow: View {
    let label: LocalizedStringResource
    let spend: Double
    let limit: Double
    let pct: Double

    var body: some View {
        let utilizationStatus = StatusPresentation.budgetUtilizationStatus(for: pct) ?? .normal

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(localizedUSDCurrency(spend, standardPrecision: 2, smallValuePrecision: 4))
                    .font(.subheadline.monospacedDigit().weight(.medium))
                Text("/ \(localizedUSDCurrency(limit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("(\(Int(pct * 100))%)")
                    .font(.caption2)
                    .foregroundStyle(utilizationStatus.color(normalColor: .secondary))
            }
            Gauge(value: min(pct, 1.0)) { EmptyView() }
                .gaugeStyle(.linearCapacity)
                .tint(utilizationStatus.color())
        }
        .padding(.vertical, 2)
    }
}

private struct DailyUsageRow: View {
    let day: DailyUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(formattedDate)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(costText)
                    .font(.subheadline.monospacedDigit())
            }

            HStack(spacing: 12) {
                Label(day.tokens.formatted(), systemImage: "number")
                Label(day.calls.formatted(), systemImage: "waveform")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var formattedDate: String {
        guard let date = day.date.usageDate else { return day.date }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var costText: String {
        return localizedUSDCurrency(day.costUsd)
    }
}

private struct ModelCostRow: View {
    let model: ModelUsage
    let maxCost: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(modelName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    Text(providerName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(costText)
                    .font(.subheadline.monospacedDigit().weight(.medium))
            }

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray5))
                    .frame(height: 8)

                Capsule()
                    .fill(costColor.gradient)
                    .frame(width: max(12, CGFloat(model.totalCostUsd / maxCost) * 220), height: 8)
            }

            HStack(spacing: 12) {
                Label(model.totalTokens.formatted(), systemImage: "number")
                Label(model.callCount.formatted(), systemImage: "waveform")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var modelName: String {
        if let last = model.model.split(separator: "/").last {
            return String(last)
        }
        return model.model
    }

    private var providerName: String {
        let lower = model.model.lowercased()
        if lower.contains("claude") || lower.contains("haiku") || lower.contains("sonnet") || lower.contains("opus") {
            return "Anthropic"
        }
        if lower.contains("gemini") || lower.contains("gemma") {
            return "Google"
        }
        if lower.contains("gpt") || lower.contains("o1") || lower.contains("o3") || lower.contains("o4") {
            return "OpenAI"
        }
        if lower.contains("groq") || lower.contains("llama") || lower.contains("mixtral") {
            return "Groq"
        }
        if lower.contains("deepseek") {
            return "DeepSeek"
        }
        if lower.contains("mistral") {
            return "Mistral"
        }
        return String(localized: "Other")
    }

    private var costText: String {
        return localizedUSDCurrency(model.totalCostUsd)
    }

    private var costColor: Color {
        let ratio = model.totalCostUsd / maxCost
        if ratio > 0.7 { return .red }
        if ratio > 0.35 { return .orange }
        return .blue
    }
}

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
                Text(localizedUSDCurrency(item.dailyCostUsd, standardPrecision: 2, smallValuePrecision: 4))
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(item.dailySpendStatus.color(normalColor: .primary))
                if let limit = item.dailyLimit, limit > 0 {
                    Text(localizedUSDCurrency(limit))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private extension String {
    var usageDate: Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: self) {
            return date
        }

        let shortFormatter = DateFormatter()
        shortFormatter.locale = Locale(identifier: "en_US_POSIX")
        shortFormatter.dateFormat = "yyyy-MM-dd"
        return shortFormatter.date(from: self)
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

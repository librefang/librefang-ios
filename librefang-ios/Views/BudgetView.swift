import SwiftUI
import Charts

struct BudgetView: View {
    @Environment(\.dependencies) private var deps
    @State private var sortOrder: BudgetSort = .costDesc

    private var vm: DashboardViewModel { deps.dashboardViewModel }
    private var visibleAgents: [AgentBudgetItem] { Array(sortedAgents.prefix(10)) }

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

    private var trendAverageDailyCost: Double? {
        guard !vm.usageDaily.isEmpty else { return nil }
        let total = vm.usageDaily.reduce(0) { $0 + $1.costUsd }
        return total / Double(vm.usageDaily.count)
    }

    private var trendTotalCalls: Int {
        vm.usageDaily.reduce(0) { $0 + $1.calls }
    }

    private var trendTotalTokens: Int {
        vm.usageDaily.reduce(0) { $0 + $1.tokens }
    }

    private var peakUsageDay: DailyUsage? {
        vm.usageDaily.max { $0.costUsd < $1.costUsd }
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
                }

                if let budget = vm.budget {
                    Section {
                        BudgetLimitRow(label: "Hourly", spend: budget.hourlySpend, limit: budget.hourlyLimit, pct: budget.hourlyPct)
                        BudgetLimitRow(label: "Daily", spend: budget.dailySpend, limit: budget.dailyLimit, pct: budget.dailyPct)
                        BudgetLimitRow(label: "Monthly", spend: budget.monthlySpend, limit: budget.monthlyLimit, pct: budget.monthlyPct)
                        BudgetValueRow(label: "Threshold") {
                            Text("\(Int(budget.alertThreshold * 100))%")
                                .foregroundStyle(.orange)
                        }
                        if let maxTokens = budget.defaultMaxLlmTokensPerHour, maxTokens > 0 {
                            BudgetValueRow(label: "Default Token Limit/hr") {
                                Text(maxTokens.formatted())
                                    .monospacedDigit()
                            }
                        }
                    } header: {
                        Text("Limits & Alerts")
                    }
                }

                if let usageSummary = vm.usageSummary {
                    Section("Cost Signals") {
                        BudgetValueRow(label: "Total Recorded Cost") {
                            Text(formatCost(usageSummary.totalCostUsd))
                                .monospacedDigit()
                        }
                        BudgetValueRow(label: "Avg Cost / Call") {
                            Text(formatCost(averageCostPerCall(usageSummary)))
                                .monospacedDigit()
                        }
                        if let projected = projectedMonthlyCost(usageSummary) {
                            BudgetValueRow(label: "Projected 30-Day Cost") {
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
                    }
                }

                if !sortedAgents.isEmpty {
                    Section {
                        ForEach(visibleAgents) { item in
                            AgentCostRow(item: item)
                        }
                    } header: {
                        ResponsiveAccessoryRow(verticalSpacing: 6) {
                            Text("Per-Agent Cost")
                        } accessory: {
                            sortMenu
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
            .navigationTitle(String(localized: "Budget"))
            .monitoringRefreshInteractionGate(isRefreshing: vm.isLoading)
            .refreshable {
                HapticManager.impact(.light)
                await vm.refresh()
            }
            .overlay {
                if vm.isLoading && vm.budget == nil && vm.usageDaily.isEmpty {
                    ProgressView(String(localized: "Loading..."))
                }
            }
            .task {
                if vm.budget == nil && vm.usageDaily.isEmpty {
                    await vm.refresh()
                }
            }
        }
    }

    private var sortMenu: some View {
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
                title: model.displayName,
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
                    ResponsiveAccessoryRow(verticalSpacing: 4) {
                        sliceTitle(slice)
                    } accessory: {
                        sliceValues(slice)
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

    private func sliceTitle(_ slice: CostSlice) -> some View {
        ResponsiveInlineGroup(horizontalSpacing: 8, verticalSpacing: 4) {
            Circle()
                .fill(slice.color)
                .frame(width: 8, height: 8)
            Text(slice.title)
                .font(.caption)
                .lineLimit(1)
        }
    }

    private func sliceValues(_ slice: CostSlice) -> some View {
        ResponsiveInlineGroup(horizontalSpacing: 8, verticalSpacing: 2, verticalAlignment: .trailing) {
            Text(formatCost(slice.value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(percentText(for: slice.value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
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

private struct BudgetValueRow<Content: View>: View {
    let label: LocalizedStringKey
    let content: Content

    init(label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        ResponsiveValueRow(horizontalSpacing: 12) {
            Text(label)
        } value: {
            content
        }
    }
}

private struct BudgetLimitRow: View {
    let label: LocalizedStringResource
    let spend: Double
    let limit: Double
    let pct: Double

    var body: some View {
        let utilizationStatus = StatusPresentation.budgetUtilizationStatus(for: pct) ?? .normal

        VStack(alignment: .leading, spacing: 6) {
            ResponsiveAccessoryRow(
                horizontalAlignment: .firstTextBaseline,
                horizontalSpacing: 8,
                verticalSpacing: 4
            ) {
                Text(label)
                    .font(.subheadline)
            } accessory: {
                spendSummary(utilizationStatus: utilizationStatus)
            }
            Gauge(value: min(pct, 1.0)) { EmptyView() }
                .gaugeStyle(.linearCapacity)
                .tint(utilizationStatus.color())
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func spendSummary(utilizationStatus: BudgetUtilizationStatus) -> some View {
        ResponsiveAccessoryRow(
            horizontalAlignment: .firstTextBaseline,
            horizontalSpacing: 4,
            verticalSpacing: 2,
            spacerMinLength: 4
        ) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                amountLabel
                limitLabel
            }
        } accessory: {
            utilizationLabel(utilizationStatus: utilizationStatus)
        }
    }

    private var amountLabel: some View {
        Text(localizedUSDCurrency(spend, standardPrecision: 2, smallValuePrecision: 4))
            .font(.subheadline.monospacedDigit().weight(.medium))
    }

    private var limitLabel: some View {
        Text("/ \(localizedUSDCurrency(limit))")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func utilizationLabel(utilizationStatus: BudgetUtilizationStatus) -> some View {
        Text("(\(Int(pct * 100))%)")
            .font(.caption2)
            .foregroundStyle(utilizationStatus.color(normalColor: .secondary))
    }
}

private struct DailyUsageRow: View {
    let day: DailyUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ResponsiveAccessoryRow(
                horizontalAlignment: .firstTextBaseline,
                horizontalSpacing: 12,
                verticalSpacing: 2
            ) {
                titleLabel
            } accessory: {
                costLabel
            }

            FlowLayout(spacing: 12) {
                tokensLabel
                callsLabel
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var titleLabel: some View {
        Text(formattedDate)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
    }

    private var costLabel: some View {
        Text(costText)
            .font(.subheadline.monospacedDigit())
    }

    private var tokensLabel: some View {
        Label(day.tokens.formatted(), systemImage: "number")
    }

    private var callsLabel: some View {
        Label(day.calls.formatted(), systemImage: "waveform")
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
            ResponsiveAccessoryRow(horizontalAlignment: .top, verticalSpacing: 4) {
                summaryBlock
            } accessory: {
                costLabel
            }

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray5))
                    .frame(height: 8)

                Capsule()
                    .fill(costColor.gradient)
                    .frame(width: max(12, CGFloat(model.totalCostUsd / maxCost) * 220), height: 8)
            }

            FlowLayout(spacing: 12) {
                tokensLabel
                callsLabel
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(modelName)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Text(providerName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var costLabel: some View {
        Text(costText)
            .font(.subheadline.monospacedDigit().weight(.medium))
    }

    private var tokensLabel: some View {
        Label(model.totalTokens.formatted(), systemImage: "number")
    }

    private var callsLabel: some View {
        Label(model.callCount.formatted(), systemImage: "waveform")
    }

    private var modelName: String {
        model.displayName
    }

    private var providerName: String {
        model.inferredProviderName
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
        ResponsiveAccessoryRow(horizontalAlignment: .top, verticalSpacing: 6) {
            summaryBlock
        } accessory: {
            spendBlock(alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.name)
                .font(.subheadline)
                .lineLimit(2)
            PresentationToneBadge(
                text: budgetStatusLabel,
                tone: budgetTone
            )
            Text(item.agentId)
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private func spendBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
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

    private var budgetTone: PresentationTone {
        switch item.dailySpendStatus {
        case .normal:
            return .neutral
        case .warning:
            return .warning
        case .critical:
            return .critical
        }
    }

    private var budgetStatusLabel: String {
        switch item.dailySpendStatus {
        case .normal:
            return String(localized: "Normal")
        case .warning:
            return String(localized: "Warning")
        case .critical:
            return String(localized: "Critical")
        }
    }
}

private struct BudgetSignalsCard: View {
    let budget: BudgetOverview?
    let usageSummary: UsageSummary
    let visibleAgentCount: Int
    let sortOrderLabel: String
    let projectedMonthlyCost: Double?

    private var avgCostPerCall: Double {
        guard usageSummary.callCount > 0 else { return 0 }
        return usageSummary.totalCostUsd / Double(usageSummary.callCount)
    }

    private var budgetPressureStatus: BudgetUtilizationStatus? {
        guard let budget else { return nil }
        return StatusPresentation.budgetUtilizationStatus(
            for: max(budget.hourlyPct, budget.dailyPct, budget.monthlyPct)
        )
    }

    private var budgetPressureTone: PresentationTone {
        budgetPressureStatus?.tone ?? (usageSummary.totalCostUsd > 0 ? .neutral : .positive)
    }

    private var budgetPressureLabel: String {
        guard let budgetPressureStatus else {
            return usageSummary.totalCostUsd > 0
                ? String(localized: "Usage only")
                : String(localized: "No pressure")
        }

        switch budgetPressureStatus {
        case .normal:
            return String(localized: "Within limit")
        case .warning:
            return String(localized: "Near limit")
        case .critical:
            return String(localized: "Over limit")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Budget pressure is summarized for quick mobile review."),
                detail: String(localized: "Use the current badges to decide whether limits, trends, models, or agent spend needs the next tap."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: sortOrderLabel, tone: .neutral)
                    PresentationToneBadge(
                        text: usageSummary.callCount == 1
                            ? String(localized: "1 call recorded")
                            : String(localized: "\(usageSummary.callCount) calls recorded"),
                        tone: usageSummary.callCount > 0 ? .positive : .neutral
                    )
                    PresentationToneBadge(
                        text: String(localized: "Avg \(localizedUSDCurrency(avgCostPerCall)) / call"),
                        tone: .neutral
                    )
                    if let projectedMonthlyCost {
                        PresentationToneBadge(
                            text: String(localized: "30-day \(localizedUSDCurrency(projectedMonthlyCost))"),
                            tone: .warning
                        )
                    }
                    if let budget {
                        PresentationToneBadge(
                            text: String(localized: "Daily \(Int(budget.dailyPct * 100))%"),
                            tone: StatusPresentation.budgetUtilizationStatus(for: budget.dailyPct)?.tone ?? .neutral
                        )
                        PresentationToneBadge(
                            text: String(localized: "Monthly \(Int(budget.monthlyPct * 100))%"),
                            tone: StatusPresentation.budgetUtilizationStatus(for: budget.monthlyPct)?.tone ?? .neutral
                        )
                    }
                    if visibleAgentCount > 0 {
                        PresentationToneBadge(
                            text: visibleAgentCount == 1
                                ? String(localized: "1 agent shown")
                                : String(localized: "\(visibleAgentCount) agents shown"),
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Budget signal facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep current pressure, projected spend, and live usage totals visible before drilling into the longer charts and rankings."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: budgetPressureLabel,
                    tone: budgetPressureTone
                )
            } facts: {
                Label(
                    String(localized: "Total \(localizedUSDCurrency(usageSummary.totalCostUsd))"),
                    systemImage: "dollarsign.circle"
                )
                Label(
                    String(localized: "Avg \(localizedUSDCurrency(avgCostPerCall)) / call"),
                    systemImage: "waveform"
                )
                if usageSummary.totalToolCalls > 0 {
                    Label(
                        usageSummary.totalToolCalls == 1
                            ? String(localized: "1 tool call")
                            : String(localized: "\(usageSummary.totalToolCalls) tool calls"),
                        systemImage: "wrench.and.screwdriver"
                    )
                }
                if let projectedMonthlyCost {
                    Label(
                        String(localized: "Projected \(localizedUSDCurrency(projectedMonthlyCost))"),
                        systemImage: "calendar"
                    )
                }
                if let budget {
                    Label(
                        String(localized: "Daily \(Int(budget.dailyPct * 100))% of limit"),
                        systemImage: "sun.max"
                    )
                    Label(
                        String(localized: "Monthly \(Int(budget.monthlyPct * 100))% of limit"),
                        systemImage: "calendar.badge.clock"
                    )
                }
                if visibleAgentCount > 0 {
                    Label(
                        visibleAgentCount == 1
                            ? String(localized: "1 visible agent")
                            : String(localized: "\(visibleAgentCount) visible agents"),
                        systemImage: "person.3"
                    )
                }
            }
        }
    }
}

private struct BudgetTrendSnapshotCard: View {
    let trendDays: Int
    let todayCost: Double
    let averageDailyCost: Double?
    let totalCalls: Int
    let totalTokens: Int
    let peakDay: DailyUsage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Trend pressure stays visible before the 7-day cost chart."),
                detail: String(localized: "Use the badges to decide whether today's spike, average burn, or the busiest day needs the next glance."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: trendDays == 1 ? String(localized: "1 day loaded") : String(localized: "\(trendDays) days loaded"),
                        tone: trendDays > 0 ? .positive : .neutral
                    )
                    PresentationToneBadge(
                        text: String(localized: "Today \(localizedUSDCurrency(todayCost))"),
                        tone: todayCost > 0 ? .warning : .neutral
                    )
                    if let averageDailyCost {
                        PresentationToneBadge(
                            text: String(localized: "Avg \(localizedUSDCurrency(averageDailyCost)) / day"),
                            tone: .neutral
                        )
                    }
                    if let peakDay {
                        PresentationToneBadge(
                            text: String(localized: "Peak \(localizedUSDCurrency(peakDay.costUsd))"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Trend facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep cumulative cost, call volume, and token load visible before opening the longer daily breakdown."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: peakDay?.date ?? String(localized: "No peak day"),
                    tone: peakDay == nil ? .neutral : .warning
                )
            } facts: {
                Label(String(localized: "Today \(localizedUSDCurrency(todayCost))"), systemImage: "sun.max")
                if let averageDailyCost {
                    Label(String(localized: "Avg \(localizedUSDCurrency(averageDailyCost))"), systemImage: "waveform.path.ecg")
                }
                Label(
                    totalCalls == 1 ? String(localized: "1 total call") : String(localized: "\(totalCalls) total calls"),
                    systemImage: "waveform"
                )
                Label(
                    String(localized: "\(totalTokens.formatted()) tokens"),
                    systemImage: "number"
                )
            }
        }
    }
}

private struct BudgetCostSignalsSnapshotCard: View {
    let usageSummary: UsageSummary
    let budget: BudgetOverview?
    let projectedMonthlyCost: Double?

    private var averageCostPerCall: Double {
        guard usageSummary.callCount > 0 else { return 0 }
        return usageSummary.totalCostUsd / Double(usageSummary.callCount)
    }

    private var totalTokens: Int {
        usageSummary.totalInputTokens + usageSummary.totalOutputTokens
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Cost signals stay visible before the raw spend rows."),
                detail: String(localized: "Use this compact slice to decide whether total cost, projected spend, or per-call efficiency needs the next glance."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: String(localized: "Total \(localizedUSDCurrency(usageSummary.totalCostUsd))"), tone: .warning)
                    PresentationToneBadge(
                        text: usageSummary.callCount == 1 ? String(localized: "1 call") : String(localized: "\(usageSummary.callCount) calls"),
                        tone: usageSummary.callCount > 0 ? .positive : .neutral
                    )
                    if let projectedMonthlyCost {
                        PresentationToneBadge(text: String(localized: "30-day \(localizedUSDCurrency(projectedMonthlyCost))"), tone: .warning)
                    }
                    if let budget {
                        PresentationToneBadge(
                            text: String(localized: "Daily \(Int(budget.dailyPct * 100))%"),
                            tone: StatusPresentation.budgetUtilizationStatus(for: budget.dailyPct)?.tone ?? .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Cost signal snapshot"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep total spend, efficiency, and projected burn visible before reading the individual signal rows."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: String(localized: "Avg \(localizedUSDCurrency(averageCostPerCall)) / call"),
                    tone: .neutral
                )
            } facts: {
                Label(String(localized: "Total \(localizedUSDCurrency(usageSummary.totalCostUsd))"), systemImage: "dollarsign.circle")
                if usageSummary.totalToolCalls > 0 {
                    Label(
                        usageSummary.totalToolCalls == 1 ? String(localized: "1 tool call") : String(localized: "\(usageSummary.totalToolCalls) tool calls"),
                        systemImage: "wrench.and.screwdriver"
                    )
                }
                Label(String(localized: "\(totalTokens.formatted()) tokens"), systemImage: "number")
                if let projectedMonthlyCost {
                    Label(String(localized: "Projected \(localizedUSDCurrency(projectedMonthlyCost))"), systemImage: "calendar")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct BudgetDailyBreakdownSnapshotCard: View {
    let days: [DailyUsage]
    let peakDay: DailyUsage?
    let averageDailyCost: Double?
    let totalCalls: Int
    let totalTokens: Int

    private var latestDay: DailyUsage? {
        days.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Daily breakdown stays visible before the full reverse-chronological spend list."),
                detail: String(localized: "Use the compact slice to see the loaded day count, peak spend, and current average before opening every day row."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: days.count == 1 ? String(localized: "1 day loaded") : String(localized: "\(days.count) days loaded"),
                        tone: .positive
                    )
                    if let latestDay {
                        PresentationToneBadge(text: latestDay.date, tone: .neutral)
                    }
                    if let peakDay {
                        PresentationToneBadge(text: String(localized: "Peak \(localizedUSDCurrency(peakDay.costUsd))"), tone: .warning)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Daily breakdown snapshot"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep average burn, total calls, and total tokens visible before scanning the full day-by-day spend history."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: averageDailyCost == nil ? String(localized: "No average") : String(localized: "Avg \(localizedUSDCurrency(averageDailyCost!))"),
                    tone: averageDailyCost == nil ? .neutral : .warning
                )
            } facts: {
                if let peakDay {
                    Label(String(localized: "Peak \(peakDay.date)"), systemImage: "chart.line.uptrend.xyaxis")
                }
                Label(
                    totalCalls == 1 ? String(localized: "1 total call") : String(localized: "\(totalCalls) total calls"),
                    systemImage: "waveform"
                )
                Label(String(localized: "\(totalTokens.formatted()) tokens"), systemImage: "number")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct BudgetModelSnapshotCard: View {
    let models: [ModelUsage]
    let topModel: ModelUsage?

    private var totalModelCost: Double {
        models.reduce(0) { $0 + $1.totalCostUsd }
    }

    private var totalCalls: Int {
        models.reduce(0) { $0 + $1.callCount }
    }

    private var totalTokens: Int {
        models.reduce(0) { $0 + $1.totalTokens }
    }

    private var providerCount: Int {
        Set(models.map(\.inferredProviderName)).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Model concentration stays visible before the distribution chart and ranked model list."),
                detail: String(localized: "Use the summary to see whether one provider or one model dominates current spend."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: models.count == 1 ? String(localized: "1 model tracked") : String(localized: "\(models.count) models tracked"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: providerCount == 1 ? String(localized: "1 provider") : String(localized: "\(providerCount) providers"),
                        tone: .neutral
                    )
                    PresentationToneBadge(
                        text: String(localized: "Total \(localizedUSDCurrency(totalModelCost))"),
                        tone: .warning
                    )
                    if let topModel {
                        PresentationToneBadge(
                            text: topModel.displayName,
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Model facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep total tokens, call volume, and the current top model visible before opening the longer cost ranking."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if let topModel {
                    PresentationToneBadge(
                        text: topModel.inferredProviderName,
                        tone: .neutral
                    )
                }
            } facts: {
                Label(String(localized: "Total \(localizedUSDCurrency(totalModelCost))"), systemImage: "dollarsign.circle")
                Label(
                    totalCalls == 1 ? String(localized: "1 model call") : String(localized: "\(totalCalls) model calls"),
                    systemImage: "waveform"
                )
                Label(
                    String(localized: "\(totalTokens.formatted()) tokens"),
                    systemImage: "number"
                )
                if let topModel {
                    Label(
                        String(localized: "\(topModel.displayName) \(localizedUSDCurrency(topModel.totalCostUsd))"),
                        systemImage: "bolt.horizontal.circle"
                    )
                }
            }
        }
    }
}

private struct BudgetAgentSnapshotCard: View {
    let items: [AgentBudgetItem]
    let totalAgentCount: Int
    let sortOrderLabel: String
    let topAgent: AgentBudgetItem?

    private var averageVisibleSpend: Double {
        guard !items.isEmpty else { return 0 }
        return items.reduce(0) { $0 + $1.dailyCostUsd } / Double(items.count)
    }

    private var flaggedAgentCount: Int {
        items.filter { $0.dailySpendStatus != .normal }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Per-agent cost pressure stays visible before the detailed agent spend ranking."),
                detail: String(localized: "Use the compact summary to decide whether ranking order or top spenders need the next tap."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: items.count == 1 ? String(localized: "1 agent visible") : String(localized: "\(items.count) agents visible"),
                        tone: .positive
                    )
                    if totalAgentCount > items.count {
                        PresentationToneBadge(
                            text: String(localized: "\(totalAgentCount) total tracked"),
                            tone: .neutral
                        )
                    }
                    PresentationToneBadge(text: sortOrderLabel, tone: .neutral)
                    if flaggedAgentCount > 0 {
                        PresentationToneBadge(
                            text: flaggedAgentCount == 1 ? String(localized: "1 flagged") : String(localized: "\(flaggedAgentCount) flagged"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Agent cost facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the top spender, current average, and any flagged agents visible before opening the longer per-agent list."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if let topAgent {
                    PresentationToneBadge(
                        text: localizedUSDCurrency(topAgent.dailyCostUsd, standardPrecision: 2, smallValuePrecision: 4),
                        tone: topAgent.dailySpendStatus.tone
                    )
                }
            } facts: {
                if let topAgent {
                    Label(topAgent.name, systemImage: "person.crop.circle")
                }
                Label(
                    String(localized: "Avg \(localizedUSDCurrency(averageVisibleSpend))"),
                    systemImage: "chart.bar"
                )
                if flaggedAgentCount > 0 {
                    Label(
                        flaggedAgentCount == 1 ? String(localized: "1 agent near limit") : String(localized: "\(flaggedAgentCount) agents near limit"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                Label(
                    totalAgentCount == 1 ? String(localized: "1 tracked agent") : String(localized: "\(totalAgentCount) tracked agents"),
                    systemImage: "person.3"
                )
            }
        }
    }
}

private struct BudgetStatusDeckCard: View {
    let trendDays: Int
    let modelCount: Int
    let agentCount: Int
    let sortOrderLabel: String
    let topAgentName: String?
    let topAgentCost: Double?
    let topModelName: String?
    let budgetPressureTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Budget breakdown is ready for quick triage."),
                verticalPadding: 4
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    FlowLayout(spacing: 8) {
                        PresentationToneBadge(
                            text: trendDays == 1 ? String(localized: "1 trend day") : String(localized: "\(trendDays) trend days"),
                            tone: trendDays > 0 ? .positive : .neutral
                        )
                        PresentationToneBadge(
                            text: modelCount == 1 ? String(localized: "1 model") : String(localized: "\(modelCount) models"),
                            tone: modelCount > 0 ? .positive : .neutral
                        )
                        PresentationToneBadge(
                            text: agentCount == 1 ? String(localized: "1 agent") : String(localized: "\(agentCount) agents"),
                            tone: agentCount > 0 ? .positive : .neutral
                        )
                        PresentationToneBadge(text: sortOrderLabel, tone: .neutral)
                    }

                    if let topAgentName, let topAgentCost {
                        ResponsiveAccessoryRow(
                            horizontalAlignment: .firstTextBaseline,
                            horizontalSpacing: 12,
                            verticalSpacing: 4
                        ) {
                            Text(String(localized: "Top agent today"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } accessory: {
                            Text("\(topAgentName) · \(localizedUSDCurrency(topAgentCost))")
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                        }
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Budget signal facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep trend depth, ranking mode, and the current heavy spenders visible before the longer charts and lists."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: sortOrderLabel,
                    tone: budgetPressureTone
                )
            } facts: {
                Label(
                    trendDays == 1 ? String(localized: "1 trend day") : String(localized: "\(trendDays) trend days"),
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                Label(
                    modelCount == 1 ? String(localized: "1 model") : String(localized: "\(modelCount) models"),
                    systemImage: "square.stack.3d.up"
                )
                Label(
                    agentCount == 1 ? String(localized: "1 agent") : String(localized: "\(agentCount) agents"),
                    systemImage: "person.3"
                )
                if let topModelName {
                    Label(topModelName, systemImage: "bolt.horizontal.circle")
                }
                if let topAgentName {
                    Label(topAgentName, systemImage: "person.crop.circle")
                }
            }
        }
    }
}

private struct BudgetRouteInventoryDeck: View {
    let primaryAreaCount: Int
    let supportAreaCount: Int
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let trendDays: Int
    let modelCount: Int
    let agentCount: Int

    var body: some View {
        MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
            FlowLayout(spacing: 8) {
                PresentationToneBadge(
                    text: primaryAreaCount == 1 ? String(localized: "1 primary area") : String(localized: "\(primaryAreaCount) primary areas"),
                    tone: .neutral
                )
                PresentationToneBadge(
                    text: supportAreaCount == 1 ? String(localized: "1 support area") : String(localized: "\(supportAreaCount) support areas"),
                    tone: supportAreaCount > 0 ? .positive : .neutral
                )
                PresentationToneBadge(
                    text: primaryRouteCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryRouteCount) primary routes"),
                    tone: .neutral
                )
                PresentationToneBadge(
                    text: supportRouteCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportRouteCount) support routes"),
                    tone: .neutral
                )
                if trendDays > 0 {
                    PresentationToneBadge(
                        text: trendDays == 1 ? String(localized: "1 trend day") : String(localized: "\(trendDays) trend days"),
                        tone: .positive
                    )
                }
                if modelCount > 0 {
                    PresentationToneBadge(
                        text: modelCount == 1 ? String(localized: "1 model") : String(localized: "\(modelCount) models"),
                        tone: .neutral
                    )
                }
                if agentCount > 0 {
                    PresentationToneBadge(
                        text: agentCount == 1 ? String(localized: "1 agent") : String(localized: "\(agentCount) agents"),
                        tone: .neutral
                    )
                }
            }
        }
    }

    private var summaryLine: String {
        let totalItems = primaryAreaCount + supportAreaCount + primaryRouteCount + supportRouteCount
        return totalItems == 1
            ? String(localized: "1 budget focus and route item is grouped in this deck.")
            : String(localized: "\(totalItems) budget focus and route items are grouped in this deck.")
    }

    private var detailLine: String {
        String(localized: "Focus areas and operator exits stay summarized here before the longer charts and spend rankings.")
    }
}

private struct BudgetSectionInventoryDeck: View {
    let sectionCount: Int
    let trendDays: Int
    let modelCount: Int
    let agentCount: Int
    let hasBudgetGuardrails: Bool
    let hasUsageSignals: Bool
    let topModelName: String?
    let topAgentName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: hasBudgetGuardrails ? String(localized: "Limits ready") : String(localized: "Limits pending"),
                        tone: hasBudgetGuardrails ? .positive : .neutral
                    )
                    PresentationToneBadge(
                        text: hasUsageSignals ? String(localized: "Signals ready") : String(localized: "Signals pending"),
                        tone: hasUsageSignals ? .warning : .neutral
                    )
                    PresentationToneBadge(
                        text: trendDays > 0 ? String(localized: "\(trendDays) trend days") : String(localized: "Trend pending"),
                        tone: trendDays > 0 ? .positive : .neutral
                    )
                    PresentationToneBadge(
                        text: modelCount == 1 ? String(localized: "1 model") : String(localized: "\(modelCount) models"),
                        tone: modelCount > 0 ? .neutral : .neutral
                    )
                    PresentationToneBadge(
                        text: agentCount == 1 ? String(localized: "1 agent") : String(localized: "\(agentCount) agents"),
                        tone: agentCount > 0 ? .neutral : .neutral
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Budget inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep guardrails, trend coverage, and rankings visible before the focus rail and long spend sections."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: sectionCount == 1 ? String(localized: "1 section") : String(localized: "\(sectionCount) sections"),
                    tone: sectionCount > 0 ? .positive : .neutral
                )
            } facts: {
                if let topModelName {
                    Label(topModelName, systemImage: "square.stack.3d.up")
                }
                if let topAgentName {
                    Label(topAgentName, systemImage: "person.3")
                }
                Label(
                    trendDays == 1 ? String(localized: "1 trend day") : String(localized: "\(trendDays) trend days"),
                    systemImage: "chart.xyaxis.line"
                )
                Label(
                    modelCount == 1 ? String(localized: "1 model rank") : String(localized: "\(modelCount) model ranks"),
                    systemImage: "chart.pie"
                )
            }
        }
    }

    private var summaryLine: String {
        sectionCount == 1
            ? String(localized: "1 budget section is loaded into the compact operator deck.")
            : String(localized: "\(sectionCount) budget sections are loaded into the compact operator deck.")
    }

    private var detailLine: String {
        String(localized: "Budget guardrails, cost signals, trend coverage, and rankings stay grouped before the route rails take over.")
    }
}

private struct BudgetPressureCoverageDeck: View {
    let dailySpend: Double?
    let projectedMonthlyCost: Double?
    let trendDays: Int
    let modelCount: Int
    let agentCount: Int
    let hasUsageSignals: Bool
    let alertThreshold: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: String(localized: "Pressure coverage keeps spend, projection, and ranking breadth readable before the long budget sections begin."),
                detail: String(localized: "Use this deck to judge whether current budget pressure comes from daily burn, weak signal coverage, or broad model and agent spread."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if let dailySpend {
                        PresentationToneBadge(
                            text: localizedUSDCurrency(dailySpend),
                            tone: dailySpend > 0 ? .warning : .neutral
                        )
                    }
                    if let projectedMonthlyCost {
                        PresentationToneBadge(
                            text: localizedUSDCurrency(projectedMonthlyCost),
                            tone: projectedMonthlyCost > 0 ? .warning : .neutral
                        )
                    }
                    if let alertThreshold {
                        PresentationToneBadge(
                            text: String(localized: "\(Int(alertThreshold * 100))% alert"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Pressure coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep usage-signal coverage and ranking breadth readable before diving into limits, trend charts, and spend distributions."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: hasUsageSignals ? String(localized: "Signals ready") : String(localized: "Signals pending"),
                    tone: hasUsageSignals ? .positive : .neutral
                )
            } facts: {
                Label(
                    trendDays == 1 ? String(localized: "1 trend day") : String(localized: "\(trendDays) trend days"),
                    systemImage: "chart.xyaxis.line"
                )
                Label(
                    modelCount == 1 ? String(localized: "1 ranked model") : String(localized: "\(modelCount) ranked models"),
                    systemImage: "chart.pie"
                )
                Label(
                    agentCount == 1 ? String(localized: "1 ranked agent") : String(localized: "\(agentCount) ranked agents"),
                    systemImage: "person.3"
                )
            }
        }
    }
}

private struct BudgetSupportCoverageDeck: View {
    let hasUsageSignals: Bool
    let trendDays: Int
    let totalCalls: Int
    let totalTokens: Int
    let topModelName: String?
    let topAgentName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep trend depth, token volume, and current spend leaders readable before the charts and rankings begin."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: hasUsageSignals ? String(localized: "Signals ready") : String(localized: "Signals pending"),
                        tone: hasUsageSignals ? .positive : .neutral
                    )
                    if let topModelName {
                        PresentationToneBadge(text: topModelName, tone: .neutral)
                    }
                    if let topAgentName {
                        PresentationToneBadge(text: topAgentName, tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Support coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep usage depth and current ranking leaders visible before the longer limit, trend, and spend sections take over."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: trendDays == 1 ? String(localized: "1 trend day") : String(localized: "\(trendDays) trend days"),
                    tone: trendDays > 0 ? .positive : .neutral
                )
            } facts: {
                if totalCalls > 0 {
                    Label(
                        totalCalls == 1 ? String(localized: "1 call") : String(localized: "\(totalCalls) calls"),
                        systemImage: "phone.connection"
                    )
                }
                if totalTokens > 0 {
                    Label(totalTokens.formatted(), systemImage: "number")
                }
            }
        }
    }

    private var summaryLine: String {
        if !hasUsageSignals {
            return String(localized: "Budget support coverage is currently waiting on usage signals.")
        }
        if topModelName != nil || topAgentName != nil {
            return String(localized: "Budget support coverage is currently anchored by trend depth and current spend leaders.")
        }
        return String(localized: "Budget support coverage is currently light and mostly reflects trend depth.")
    }
}

private struct BudgetActionReadinessDeck: View {
    let primaryAreaCount: Int
    let supportAreaCount: Int
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let sortOrderLabel: String
    let hasBudgetGuardrails: Bool
    let hasUsageSignals: Bool
    let trendDays: Int
    let modelCount: Int
    let agentCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to check whether the budget view is ready for sorting, chart review, and route jumps before opening the long trend sections."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: sortOrderLabel, tone: .neutral)
                    PresentationToneBadge(
                        text: hasBudgetGuardrails ? String(localized: "Limits ready") : String(localized: "Limits pending"),
                        tone: hasBudgetGuardrails ? .positive : .neutral
                    )
                    PresentationToneBadge(
                        text: hasUsageSignals ? String(localized: "Signals ready") : String(localized: "Signals pending"),
                        tone: hasUsageSignals ? .positive : .neutral
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Action readiness"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep sort state, chart breadth, and route readiness visible before diving into limits, trends, models, and agent spend sections."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: String(localized: "\(primaryRouteCount + supportRouteCount) exits"),
                    tone: .neutral
                )
            } facts: {
                Label(
                    primaryAreaCount == 1 ? String(localized: "1 primary area") : String(localized: "\(primaryAreaCount) primary areas"),
                    systemImage: "scope"
                )
                Label(
                    supportAreaCount == 1 ? String(localized: "1 support area") : String(localized: "\(supportAreaCount) support areas"),
                    systemImage: "square.grid.2x2"
                )
                if trendDays > 0 {
                    Label(
                        trendDays == 1 ? String(localized: "1 trend day") : String(localized: "\(trendDays) trend days"),
                        systemImage: "chart.xyaxis.line"
                    )
                }
                if modelCount > 0 {
                    Label(
                        modelCount == 1 ? String(localized: "1 model") : String(localized: "\(modelCount) models"),
                        systemImage: "square.stack.3d.up"
                    )
                }
                if agentCount > 0 {
                    Label(
                        agentCount == 1 ? String(localized: "1 agent") : String(localized: "\(agentCount) agents"),
                        systemImage: "person.3"
                    )
                }
            }
        }
    }

    private var summaryLine: String {
        if !hasUsageSignals {
            return String(localized: "Budget action readiness is currently waiting on usage signals before the longer trend and spend sections are useful.")
        }
        if !hasBudgetGuardrails {
            return String(localized: "Budget action readiness is currently centered on analysis because spend limits are not loaded.")
        }
        return String(localized: "Budget action readiness is currently clear enough for chart review, sorting, and route jumps.")
    }
}

private struct BudgetFocusCoverageDeck: View {
    let trendDays: Int
    let modelCount: Int
    let agentCount: Int
    let hasBudgetGuardrails: Bool
    let hasUsageSignals: Bool
    let sortOrderLabel: String
    let totalCalls: Int
    let totalTokens: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep the dominant budget lane visible before opening trends, rankings, and lower chart sections."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: sortOrderLabel, tone: .neutral)
                    PresentationToneBadge(
                        text: trendDays == 1 ? String(localized: "1 trend day") : String(localized: "\(trendDays) trend days"),
                        tone: trendDays > 0 ? .positive : .neutral
                    )
                    if hasBudgetGuardrails {
                        PresentationToneBadge(text: String(localized: "Guardrails ready"), tone: .positive)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Focus coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the dominant budget lane readable before moving from the top decks into charts, models, and agent spend lists."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: hasUsageSignals ? String(localized: "Signals ready") : String(localized: "Signals pending"),
                    tone: hasUsageSignals ? .positive : .neutral
                )
            } facts: {
                if modelCount > 0 {
                    Label(
                        modelCount == 1 ? String(localized: "1 model lane") : String(localized: "\(modelCount) model lanes"),
                        systemImage: "square.stack.3d.up"
                    )
                }
                if agentCount > 0 {
                    Label(
                        agentCount == 1 ? String(localized: "1 agent lane") : String(localized: "\(agentCount) agent lanes"),
                        systemImage: "person.2"
                    )
                }
                if totalCalls > 0 {
                    Label(
                        totalCalls == 1 ? String(localized: "1 call tracked") : String(localized: "\(totalCalls) calls tracked"),
                        systemImage: "phone.arrow.up.right"
                    )
                }
                if totalTokens > 0 {
                    Label(
                        String(localized: "\(totalTokens.formatted()) tokens tracked"),
                        systemImage: "number"
                    )
                }
            }
        }
    }

    private var summaryLine: String {
        if hasBudgetGuardrails && hasUsageSignals {
            return String(localized: "Budget focus coverage is currently anchored by guardrails, usage signals, and ranked spend lanes.")
        }
        if hasUsageSignals {
            return String(localized: "Budget focus coverage is currently anchored by usage trends and ranked spend lanes.")
        }
        return String(localized: "Budget focus coverage is currently light and mostly reflects layout readiness for lower charts and rankings.")
    }
}

private struct BudgetWorkstreamCoverageDeck: View {
    let trendDays: Int
    let modelCount: Int
    let agentCount: Int
    let hasBudgetGuardrails: Bool
    let hasUsageSignals: Bool
    let totalCalls: Int
    let totalTokens: Int
    let topModelName: String?
    let topAgentName: String?
    let sortOrderLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to see whether the budget view is currently led by trend review, ranking review, or guardrail context before the long charts and rankings begin."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: sortOrderLabel, tone: .neutral)
                    PresentationToneBadge(
                        text: hasUsageSignals ? String(localized: "Signals ready") : String(localized: "Signals pending"),
                        tone: hasUsageSignals ? .positive : .neutral
                    )
                    if let topModelName {
                        PresentationToneBadge(text: topModelName, tone: .neutral)
                    }
                    if let topAgentName {
                        PresentationToneBadge(text: topAgentName, tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Workstream coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep trend review, spend rankings, and guardrail context readable before the limit, chart, model, and agent sections take over."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: trendDays == 1 ? String(localized: "1 trend day") : String(localized: "\(trendDays) trend days"),
                    tone: trendDays > 0 ? .positive : .neutral
                )
            } facts: {
                if modelCount > 0 {
                    Label(
                        modelCount == 1 ? String(localized: "1 model") : String(localized: "\(modelCount) models"),
                        systemImage: "square.stack.3d.up"
                    )
                }
                if agentCount > 0 {
                    Label(
                        agentCount == 1 ? String(localized: "1 agent") : String(localized: "\(agentCount) agents"),
                        systemImage: "person.3"
                    )
                }
                if totalCalls > 0 {
                    Label(
                        totalCalls == 1 ? String(localized: "1 call") : String(localized: "\(totalCalls) calls"),
                        systemImage: "phone.connection"
                    )
                }
                if totalTokens > 0 {
                    Label(String(localized: "\(totalTokens.formatted()) tokens"), systemImage: "number")
                }
                Label(
                    hasBudgetGuardrails ? String(localized: "Guardrails ready") : String(localized: "Guardrails pending"),
                    systemImage: "gauge.with.needle"
                )
            }
        }
    }

    private var summaryLine: String {
        if !hasUsageSignals {
            return String(localized: "Budget workstream coverage is currently waiting on usage signals.")
        }
        if trendDays > 0 || totalCalls > 0 {
            return String(localized: "Budget workstream coverage is currently anchored by trend review.")
        }
        if modelCount > 0 || agentCount > 0 {
            return String(localized: "Budget workstream coverage is currently anchored by spend leaderboards.")
        }
        if hasBudgetGuardrails {
            return String(localized: "Budget workstream coverage is currently anchored by guardrail review.")
        }
        return String(localized: "Budget workstream coverage is currently light across the visible lanes.")
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

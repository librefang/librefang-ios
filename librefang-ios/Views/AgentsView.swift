import SwiftUI

struct AgentsView: View {
    @Environment(\.dependencies) private var deps
    @State private var searchText = ""
    @State private var filterState: AgentFilter = .all

    private var vm: DashboardViewModel { deps.dashboardViewModel }
    private var watchlistStore: AgentWatchlistStore { deps.agentWatchlistStore }

    private var filteredAgents: [AgentAttentionItem] {
        var result = vm.agents.map { vm.attentionItem(for: $0) }

        switch filterState {
        case .all: break
        case .attention: result = result.filter { $0.severity > 0 }
        case .watchlist: result = result.filter { watchlistStore.isWatched($0.agent) }
        case .running: result = result.filter { $0.agent.isRunning }
        case .stopped: result = result.filter { !$0.agent.isRunning }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.agent.name.localizedCaseInsensitiveContains(searchText)
                || ($0.agent.modelProvider?.localizedCaseInsensitiveContains(searchText) ?? false)
                || ($0.agent.modelName?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return result.sorted { lhs, rhs in
            let lhsWatched = watchlistStore.isWatched(lhs.agent)
            let rhsWatched = watchlistStore.isWatched(rhs.agent)
            if lhsWatched != rhsWatched {
                return lhsWatched && !rhsWatched
            }
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            if lhs.agent.isRunning != rhs.agent.isRunning {
                return lhs.agent.isRunning && !rhs.agent.isRunning
            }
            return lhs.agent.name.localizedCompare(rhs.agent.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                    if vm.agents.isEmpty && !vm.isLoading {
                        ContentUnavailableView(
                            "No Agents",
                            systemImage: "cpu.fill"
                        )
                    } else if filteredAgents.isEmpty && !searchText.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else if filteredAgents.isEmpty && filterState == .attention {
                        ContentUnavailableView(
                            "No Active Agent Issues",
                            systemImage: "checkmark.shield"
                        )
                    } else if filteredAgents.isEmpty && filterState == .watchlist {
                        ContentUnavailableView(
                            "No Watched Agents",
                            systemImage: "star"
                        )
                    } else if filteredAgents.isEmpty {
                        ContentUnavailableView(
                            "No Agents In This Filter",
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                    } else {
                        List {
                            if !filteredAgents.isEmpty {
                                FlowLayout(spacing: 8) {
                                    ForEach(AgentFilter.allCases, id: \.self) { filter in
                                        Button {
                                            filterState = filter
                                        } label: {
                                            SelectableLabelCapsuleBadge(
                                                text: filter.label,
                                                systemImage: filter.icon,
                                                isSelected: filterState == filter
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                ForEach(filteredAgents) { item in
                                    NavigationLink(value: item.agent.id) {
                                        AgentRow(
                                            attention: item,
                                            isWatched: watchlistStore.isWatched(item.agent)
                                        )
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            watchlistStore.toggle(item.agent)
                                        } label: {
                                            Label(
                                                watchlistStore.isWatched(item.agent)
                                                    ? String(localized: "Unwatch")
                                                    : String(localized: "Watch"),
                                                systemImage: watchlistStore.isWatched(item.agent) ? "star.slash" : "star"
                                            )
                                        }
                                        .tint(.yellow)
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationDestination(for: String.self) { agentId in
                    if let agent = vm.agents.first(where: { $0.id == agentId }) {
                        AgentDetailView(agent: agent)
                    } else {
                        EmptyView()
                    }
                }
            }
            .navigationTitle(String(localized: "Agents"))
            .searchable(text: $searchText, prompt: Text(String(localized: "Search agents...")))
            .monitoringRefreshInteractionGate(isRefreshing: vm.isLoading)
            .refreshable {
                await vm.refresh()
                watchlistStore.removeMissingAgents(validIDs: Set(vm.agents.map(\.id)))
            }
            .overlay {
                if vm.isLoading && vm.agents.isEmpty {
                    ProgressView(String(localized: "Loading..."))
                }
            }
            .task {
                if vm.agents.isEmpty {
                    await vm.refresh()
                }
                watchlistStore.removeMissingAgents(validIDs: Set(vm.agents.map(\.id)))
            }
            .safeAreaInset(edge: .top) {
                if let error = vm.error {
                    ErrorBanner(message: error, onRetry: {
                        await vm.refresh()
                    }, onDismiss: {
                        vm.error = nil
                    })
                    .padding(.top, 4)
                }
            }
    }
}

// MARK: - Agent Filter

private enum AgentFilter: CaseIterable {
    case all, attention, watchlist, running, stopped

    var label: String {
        switch self {
        case .all: String(localized: "All")
        case .attention: String(localized: "Attention")
        case .watchlist: String(localized: "Watchlist")
        case .running: String(localized: "Running")
        case .stopped: String(localized: "Stopped")
        }
    }

    var icon: String {
        switch self {
        case .all: "list.bullet"
        case .attention: "exclamationmark.triangle"
        case .watchlist: "star"
        case .running: "play.circle"
        case .stopped: "stop.circle"
        }
    }
}

// MARK: - Agent Row

private struct AgentRow: View {
    let attention: AgentAttentionItem
    let isWatched: Bool

    private var agent: Agent { attention.agent }
    private var watchAccentColor: Color { PresentationTone.caution.color }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(agent.identity?.emoji ?? "🤖")
                .font(.title2)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                ResponsiveInlineGroup(horizontalSpacing: 6, verticalSpacing: 4) {
                    nameLabel
                    watchedIcon
                }

                FlowLayout(spacing: 6) {
                    statusSummary
                }
                if let lastActive = agent.lastActive {
                    RelativeTimeText(dateString: lastActive)
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var nameLabel: some View {
        Text(agent.name)
            .font(.subheadline.weight(.medium))
            .lineLimit(2)
    }

    @ViewBuilder
    private var watchedIcon: some View {
        if isWatched {
            Image(systemName: "star.fill")
                .font(.caption2)
                .foregroundStyle(watchAccentColor)
        }
    }

    private var statusSummary: some View {
        Group {
            StatePill(state: agent.state)

            ForEach(attention.statusPills) { pill in
                InlineStatusPill(
                    label: pill.label,
                    tone: pill.tone,
                    systemImage: pill.systemImage
                )
            }

            if let provider = agent.modelProvider {
                Text(provider)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

// MARK: - State Pill

private struct StatePill: View {
    let state: String

    var body: some View {
        PresentationToneBadge(
            text: Agent.localizedStateLabel(for: state),
            tone: Agent.stateTone(for: state),
            horizontalPadding: 6,
            verticalPadding: 2
        )
    }
}

private struct InlineStatusPill: View {
    let label: String
    let tone: PresentationTone
    let systemImage: String

    var body: some View {
        PresentationToneLabelBadge(
            text: label,
            systemImage: systemImage,
            tone: tone,
            horizontalPadding: 6,
            verticalPadding: 2
        )
    }
}

private struct AgentFleetSummaryCard: View {
    let runningCount: Int
    let issueCount: Int
    let approvalCount: Int
    let staleCount: Int
    let watchlistCount: Int

    private var runningStatus: MonitoringSummaryStatus {
        .countStatus(runningCount, activeTone: .positive)
    }

    private var attentionStatus: MonitoringSummaryStatus {
        .countStatus(issueCount, activeTone: .warning)
    }

    private var staleStatus: MonitoringSummaryStatus {
        .countStatus(staleCount, activeTone: .warning)
    }

    private var approvalStatus: MonitoringSummaryStatus {
        .countStatus(approvalCount, activeTone: .critical)
    }

    private var watchlistStatus: MonitoringSummaryStatus {
        .countStatus(watchlistCount, activeTone: .positive)
    }

    private var tertiaryLabelColor: Color {
        Color(uiColor: .tertiaryLabel)
    }

    var body: some View {
        VStack(spacing: 10) {
            FlowLayout(spacing: 10) {
                SummaryChip(value: "\(runningCount)", label: String(localized: "Running"), color: runningStatus.tone.color)
                SummaryChip(value: "\(issueCount)", label: String(localized: "Attention"), color: attentionStatus.tone.color)
                SummaryChip(value: "\(staleCount)", label: String(localized: "Stale"), color: staleStatus.tone.color)
                SummaryChip(value: "\(approvalCount)", label: String(localized: "Approvals"), color: approvalStatus.tone.color)
            }

            watchlistLabel
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
    }

    private var watchlistLabel: some View {
        Label(
            watchlistCount == 1
                ? String(localized: "1 watched agent pinned on this iPhone")
                : String(localized: "\(watchlistCount) watched agents pinned on this iPhone"),
            systemImage: "star.fill"
        )
        .font(.caption)
        .foregroundStyle(watchlistStatus.color(positive: .secondary, neutral: tertiaryLabelColor))
    }
}

private struct SummaryChip: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Relative Time

private struct RelativeTimeText: View {
    let dateString: String

    var body: some View {
        if let date = parseDate(dateString) {
            Text(date, style: .relative)
        } else {
            Text(dateString)
        }
    }

    private func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

// MARK: - Status Indicator

private struct StatusIndicator: View {
    let health: HealthStatus?

    private var tone: PresentationTone {
        health?.statusTone ?? .neutral
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tone.color)
                .frame(width: 8, height: 8)
            if let version = health?.version {
                Text("v\(version)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

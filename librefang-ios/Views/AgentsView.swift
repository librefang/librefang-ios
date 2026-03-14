import SwiftUI

struct AgentsView: View {
    @Environment(\.dependencies) private var deps
    @State private var searchText = ""
    @State private var filterState: AgentFilter = .all

    private var vm: DashboardViewModel { deps.dashboardViewModel }
    private var watchlistStore: AgentWatchlistStore { deps.agentWatchlistStore }
    private var watchedAgents: [Agent] {
        watchlistStore.watchedAgents(from: vm.agents)
    }

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
                        systemImage: "cpu.fill",
                        description: Text("Pull to refresh or check server connection.")
                    )
                } else if filteredAgents.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else if filteredAgents.isEmpty && filterState == .attention {
                    ContentUnavailableView(
                        "No Active Agent Issues",
                        systemImage: "checkmark.shield",
                        description: Text("Running agents, approvals, auth, and stale activity all look normal right now.")
                    )
                } else if filteredAgents.isEmpty && filterState == .watchlist {
                    ContentUnavailableView(
                        "No Watched Agents",
                        systemImage: "star",
                        description: Text("Mark important agents from the list or detail page to keep them near the top on mobile.")
                    )
                } else if filteredAgents.isEmpty {
                    ContentUnavailableView(
                        "No Agents In This Filter",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Switch filters or pull to refresh to inspect the full fleet.")
                    )
                } else {
                    List {
                        if !filteredAgents.isEmpty {
                            Section {
                                AgentFleetSummaryCard(
                                    runningCount: filteredAgents.filter { $0.agent.isRunning }.count,
                                    issueCount: filteredAgents.filter { $0.severity > 0 }.count,
                                    approvalCount: filteredAgents.reduce(0) { $0 + $1.pendingApprovals },
                                    staleCount: filteredAgents.filter(\.isStale).count,
                                    watchlistCount: watchedAgents.count
                                )
                                .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
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
                                    Label(watchlistStore.isWatched(item.agent) ? "Unwatch" : "Watch", systemImage: watchlistStore.isWatched(item.agent) ? "star.slash" : "star")
                                }
                                .tint(.yellow)
                            }
                            .swipeActions(edge: .trailing) {
                                if item.agent.isRunning {
                                    Button {
                                        // future: stop agent
                                    } label: {
                                        Label("Message", systemImage: "paperplane")
                                    }
                                    .tint(.blue)
                                }
                            }
                        }
                    }
                    .navigationDestination(for: String.self) { agentId in
                        if let agent = vm.agents.first(where: { $0.id == agentId }) {
                            AgentDetailView(agent: agent)
                        }
                    }
                }
            }
            .navigationTitle("Agents")
            .searchable(text: $searchText, prompt: "Search agents...")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Filter", selection: $filterState) {
                            ForEach(AgentFilter.allCases, id: \.self) { filter in
                                Label(filter.label, systemImage: filter.icon)
                                    .tag(filter)
                            }
                        }
                    } label: {
                        Image(systemName: filterState == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    StatusIndicator(health: vm.health)
                }
            }
            .refreshable {
                await vm.refresh()
                watchlistStore.removeMissingAgents(validIDs: Set(vm.agents.map(\.id)))
            }
            .overlay {
                if vm.isLoading && vm.agents.isEmpty {
                    ProgressView("Loading...")
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
}

// MARK: - Agent Filter

private enum AgentFilter: CaseIterable {
    case all, attention, watchlist, running, stopped

    var label: String {
        switch self {
        case .all: String(localized: "All")
        case .attention: "Attention"
        case .watchlist: "Watchlist"
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

    var body: some View {
        HStack(spacing: 12) {
            Text(agent.identity?.emoji ?? "🤖")
                .font(.title2)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(agent.name)
                        .font(.subheadline.weight(.medium))
                    if isWatched {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }

                HStack(spacing: 6) {
                    StatePill(state: agent.state)

                    if attention.pendingApprovals > 0 {
                        InlineStatusPill(
                            label: attention.pendingApprovals == 1 ? "1 approval" : "\(attention.pendingApprovals) approvals",
                            color: .red,
                            systemImage: "exclamationmark.shield"
                        )
                    }

                    if !agent.ready {
                        InlineStatusPill(
                            label: "Not ready",
                            color: .orange,
                            systemImage: "hourglass"
                        )
                    }

                    if attention.hasAuthIssue {
                        InlineStatusPill(
                            label: "Auth",
                            color: .red,
                            systemImage: "lock.slash"
                        )
                    }

                    if attention.isStale {
                        InlineStatusPill(
                            label: "Stale",
                            color: .orange,
                            systemImage: "clock.badge.exclamationmark"
                        )
                    }

                    if attention.sessionPressure {
                        InlineStatusPill(
                            label: "Sessions",
                            color: .orange,
                            systemImage: "rectangle.stack.badge.person.crop"
                        )
                    }

                    if let provider = agent.modelProvider {
                        Text(provider)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let model = agent.modelName {
                    Text(model)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
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
}

// MARK: - State Pill

private struct StatePill: View {
    let state: String

    var body: some View {
        Text(state)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch state {
        case "Running": .green
        case "Suspended": .yellow
        case "Terminated": .red
        default: .gray
        }
    }
}

private struct InlineStatusPill: View {
    let label: String
    let color: Color
    let systemImage: String

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

private struct AgentFleetSummaryCard: View {
    let runningCount: Int
    let issueCount: Int
    let approvalCount: Int
    let staleCount: Int
    let watchlistCount: Int

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                SummaryChip(value: "\(runningCount)", label: "Running", color: .green)
                SummaryChip(value: "\(issueCount)", label: "Attention", color: issueCount > 0 ? .orange : .secondary)
                SummaryChip(value: "\(staleCount)", label: "Stale", color: staleCount > 0 ? .orange : .secondary)
                SummaryChip(value: "\(approvalCount)", label: "Approvals", color: approvalCount > 0 ? .red : .secondary)
            }

            HStack {
                Label(
                    watchlistCount == 1 ? "1 watched agent pinned on this iPhone" : "\(watchlistCount) watched agents pinned on this iPhone",
                    systemImage: "star.fill"
                )
                .font(.caption)
                .foregroundStyle(watchlistCount > 0 ? .secondary : .tertiary)
                Spacer()
            }
        }
        .padding(.horizontal)
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

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(health?.isHealthy == true ? .green : .red)
                .frame(width: 8, height: 8)
            if let version = health?.version {
                Text("v\(version)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

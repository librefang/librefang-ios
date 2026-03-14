import SwiftUI

struct AgentsView: View {
    @Environment(\.dependencies) private var deps
    @State private var searchText = ""
    @State private var filterState: AgentFilter = .all

    private var vm: DashboardViewModel { deps.dashboardViewModel }

    private var filteredAgents: [Agent] {
        var result = vm.agents

        switch filterState {
        case .all: break
        case .running: result = result.filter(\.isRunning)
        case .stopped: result = result.filter { !$0.isRunning }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.modelProvider?.localizedCaseInsensitiveContains(searchText) ?? false)
                || ($0.modelName?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return result
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
                } else {
                    List(filteredAgents) { agent in
                        NavigationLink(value: agent.id) {
                            AgentRow(
                                agent: agent,
                                pendingApprovals: pendingApprovalCount(for: agent),
                                hasAuthIssue: hasAuthIssue(for: agent)
                            )
                        }
                        .swipeActions(edge: .trailing) {
                            if agent.isRunning {
                                Button {
                                    // future: stop agent
                                } label: {
                                    Label("Message", systemImage: "paperplane")
                                }
                                .tint(.blue)
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
    case all, running, stopped

    var label: String {
        switch self {
        case .all: String(localized: "All")
        case .running: String(localized: "Running")
        case .stopped: String(localized: "Stopped")
        }
    }

    var icon: String {
        switch self {
        case .all: "list.bullet"
        case .running: "play.circle"
        case .stopped: "stop.circle"
        }
    }
}

// MARK: - Agent Row

private struct AgentRow: View {
    let agent: Agent
    let pendingApprovals: Int
    let hasAuthIssue: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(agent.identity?.emoji ?? "🤖")
                .font(.title2)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(agent.name)
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 6) {
                    StatePill(state: agent.state)

                    if pendingApprovals > 0 {
                        InlineStatusPill(
                            label: pendingApprovals == 1 ? "1 approval" : "\(pendingApprovals) approvals",
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

                    if hasAuthIssue {
                        InlineStatusPill(
                            label: "Auth",
                            color: .red,
                            systemImage: "lock.slash"
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

private extension AgentsView {
    func pendingApprovalCount(for agent: Agent) -> Int {
        vm.approvals.filter { $0.agentId == agent.id || $0.agentName == agent.name }.count
    }

    func hasAuthIssue(for agent: Agent) -> Bool {
        guard let authStatus = agent.authStatus?.lowercased() else { return false }
        return authStatus != "configured"
    }
}

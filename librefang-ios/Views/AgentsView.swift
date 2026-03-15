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

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var filterSummaryLine: String {
        switch filterState {
        case .all:
            return String(localized: "Showing the full fleet with watched agents and attention items promoted to the top.")
        case .attention:
            return String(localized: "Attention mode keeps stale, auth, approval, and delivery issues at the front.")
        case .watchlist:
            return String(localized: "Watchlist mode limits the fleet to agents pinned locally on this iPhone.")
        case .running:
            return String(localized: "Running mode keeps only active agents in the list.")
        case .stopped:
            return String(localized: "Stopped mode isolates idle agents for quick review.")
        }
    }

    private var searchSummaryLine: String {
        if normalizedSearchText.isEmpty {
            return String(localized: "\(filteredAgents.count) agents visible in the current fleet view.")
        }
        return String(localized: "\(filteredAgents.count) agents visible for \"\(searchText)\".")
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
                                MonitoringFilterCard(summary: filterSummaryLine, detail: searchSummaryLine) {
                                    PresentationToneBadge(
                                        text: filterState.label,
                                        tone: filterState == .attention ? .warning : .neutral
                                    )
                                } controls: {
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
                                }

                                MonitoringSurfaceGroupCard(
                                    title: String(localized: "Routes"),
                                    detail: String(localized: "Keep the broader operator queues one tap away from the compact fleet filter.")
                                ) {
                                    MonitoringShortcutRail(
                                        title: String(localized: "Primary"),
                                        detail: String(localized: "Use these routes when fleet review needs broader incident or runtime context.")
                                    ) {
                                        NavigationLink {
                                            OnCallView()
                                        } label: {
                                            MonitoringSurfaceShortcutChip(
                                                title: String(localized: "On Call"),
                                                systemImage: "waveform.path.ecg",
                                                tone: vm.issueAgentCount > 0 ? .warning : .neutral,
                                                badgeText: vm.issueAgentCount > 0 ? "\(vm.issueAgentCount)" : nil
                                            )
                                        }
                                        .buttonStyle(.plain)

                                        NavigationLink {
                                            IncidentsView()
                                        } label: {
                                            MonitoringSurfaceShortcutChip(
                                                title: String(localized: "Incidents"),
                                                systemImage: "bell.badge",
                                                tone: vm.monitoringAlerts.contains { $0.severity == .critical } ? .critical : .neutral,
                                                badgeText: vm.monitoringAlerts.isEmpty ? nil : "\(vm.monitoringAlerts.count)"
                                            )
                                        }
                                        .buttonStyle(.plain)

                                        NavigationLink {
                                            RuntimeView()
                                        } label: {
                                            MonitoringSurfaceShortcutChip(
                                                title: String(localized: "Runtime"),
                                                systemImage: "server.rack",
                                                tone: vm.runtimeAlertCount > 0 ? .warning : .neutral,
                                                badgeText: vm.runtimeAlertCount > 0 ? "\(vm.runtimeAlertCount)" : nil
                                            )
                                        }
                                        .buttonStyle(.plain)

                                        if vm.sessionAttentionCount > 0 {
                                            NavigationLink {
                                                SessionsView(initialFilter: .attention)
                                            } label: {
                                                MonitoringSurfaceShortcutChip(
                                                    title: String(localized: "Sessions"),
                                                    systemImage: "rectangle.stack",
                                                    tone: .warning,
                                                    badgeText: "\(vm.sessionAttentionCount)"
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }

                                    MonitoringShortcutRail(
                                        title: String(localized: "Support"),
                                        detail: String(localized: "Keep approvals, diagnostics, and slower fleet drilldowns reachable without leaving the compact list flow.")
                                    ) {
                                        if vm.pendingApprovalCount > 0 {
                                            NavigationLink {
                                                ApprovalsView()
                                            } label: {
                                                MonitoringSurfaceShortcutChip(
                                                    title: String(localized: "Approvals"),
                                                    systemImage: "checkmark.shield",
                                                    tone: .warning,
                                                    badgeText: "\(vm.pendingApprovalCount)"
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }

                                        NavigationLink {
                                            DiagnosticsView()
                                        } label: {
                                            MonitoringSurfaceShortcutChip(
                                                title: String(localized: "Diagnostics"),
                                                systemImage: "stethoscope",
                                                tone: vm.diagnosticsConfigWarningCount > 0 ? .warning : .neutral,
                                                badgeText: vm.diagnosticsConfigWarningCount > 0 ? "\(vm.diagnosticsConfigWarningCount)" : nil
                                            )
                                        }
                                        .buttonStyle(.plain)

                                        NavigationLink {
                                            IntegrationsView(initialScope: .attention)
                                        } label: {
                                            MonitoringSurfaceShortcutChip(
                                                title: String(localized: "Integrations"),
                                                systemImage: "square.3.layers.3d.down.forward",
                                                tone: vm.integrationPressureIssueCategoryCount > 0 ? .critical : .neutral,
                                                badgeText: vm.integrationPressureIssueCategoryCount > 0 ? "\(vm.integrationPressureIssueCategoryCount)" : nil
                                            )
                                        }
                                        .buttonStyle(.plain)

                                        NavigationLink {
                                            AutomationView(initialScope: .attention)
                                        } label: {
                                            MonitoringSurfaceShortcutChip(
                                                title: String(localized: "Automation"),
                                                systemImage: "flowchart",
                                                tone: vm.automationPressureIssueCategoryCount > 0 ? .warning : .neutral,
                                                badgeText: vm.automationPressureIssueCategoryCount > 0 ? "\(vm.automationPressureIssueCategoryCount)" : nil
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            } footer: {
                                Text("Keep the fleet filter visible on mobile instead of relying on the top-bar menu alone.")
                            }

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
                                    Label(
                                        watchlistStore.isWatched(item.agent)
                                            ? String(localized: "Unwatch")
                                            : String(localized: "Watch"),
                                        systemImage: watchlistStore.isWatched(item.agent) ? "star.slash" : "star"
                                    )
                                }
                                .tint(.yellow)
                            }
                            .swipeActions(edge: .trailing) {
                                if item.agent.isRunning {
                                    Button {
                                        // future: stop agent
                                    } label: {
                                        Label(String(localized: "Message"), systemImage: "paperplane")
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

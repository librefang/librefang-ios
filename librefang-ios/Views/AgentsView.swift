import SwiftUI

struct AgentsView: View {
    @Environment(\.dependencies) private var deps
    @State private var searchText = ""
    @State private var filterState: AgentFilter = .all

    private var vm: DashboardViewModel { deps.dashboardViewModel }
    private var watchlistStore: AgentWatchlistStore { deps.agentWatchlistStore }
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

    private var sectionTitle: String {
        switch filterState {
        case .all:
            return String(localized: "Fleet")
        case .attention:
            return String(localized: "Attention")
        case .watchlist:
            return String(localized: "Watchlist")
        case .running:
            return String(localized: "Running")
        case .stopped:
            return String(localized: "Stopped")
        }
    }

    private var searchSummaryLine: String {
        if normalizedSearchText.isEmpty {
            return String(localized: "\(filteredAgents.count) agents visible in the current fleet view.")
        }
        return String(localized: "\(filteredAgents.count) agents visible for \"\(searchText)\".")
    }

    private var filteredRunningCount: Int {
        filteredAgents.filter { $0.agent.isRunning }.count
    }

    private var filteredIssueCount: Int {
        filteredAgents.filter { $0.severity > 0 }.count
    }

    private var filteredApprovalCount: Int {
        filteredAgents.reduce(0) { $0 + $1.pendingApprovals }
    }

    private var filteredStaleCount: Int {
        filteredAgents.filter(\.isStale).count
    }

    private var filteredWatchedCount: Int {
        filteredAgents.filter { watchlistStore.isWatched($0.agent) }.count
    }

    private var filteredAuthIssueCount: Int {
        filteredAgents.filter(\.hasAuthIssue).count
    }

    private var filteredModelIssueCount: Int {
        filteredAgents.filter { $0.modelDiagnostic != nil }.count
    }

    private var filteredSessionPressureCount: Int {
        filteredAgents.filter(\.sessionPressure).count
    }

    private var agentRoutePrimaryCount: Int {
        3 + (vm.sessionAttentionCount > 0 ? 1 : 0)
    }

    private var agentRouteSupportCount: Int {
        3 + (vm.pendingApprovalCount > 0 ? 1 : 0)
    }
    private var agentsSectionCount: Int { 2 }
    private var agentsSectionPreviewTitles: [String] {
        switch filterState {
        case .all:
            [String(localized: "Fleet")]
        case .attention:
            [String(localized: "Attention Queue")]
        case .watchlist:
            [String(localized: "Watchlist")]
        case .running:
            [String(localized: "Running Fleet")]
        case .stopped:
            [String(localized: "Stopped Fleet")]
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

                                    if filterState != .all || !normalizedSearchText.isEmpty {
                                        Text(searchSummaryLine)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
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
                                } header: {
                                    Text(sectionTitle)
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
            .navigationTitle(String(localized: "Agents"))
            .searchable(text: $searchText, prompt: Text(String(localized: "Search agents...")))
            .monitoringRefreshInteractionGate(isRefreshing: vm.isLoading)
            .toolbar {
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

private struct AgentsRouteInventoryDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let issueCount: Int
    let watchlistCount: Int
    let runtimeAlertCount: Int
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: hasSearchScope
                    ? String(localized: "The route rail stays compact while the fleet list is search-scoped.")
                    : String(localized: "The route rail stays compact before the broader fleet drilldowns."),
                detail: String(localized: "Use the route inventory to gauge how many primary and support exits are active before leaving the fleet list."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: primaryRouteCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryRouteCount) primary routes"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: supportRouteCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportRouteCount) support routes"),
                        tone: .neutral
                    )
                    if issueCount > 0 {
                        PresentationToneBadge(
                            text: issueCount == 1 ? String(localized: "1 agent needs attention") : String(localized: "\(issueCount) agents need attention"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Route Facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep fleet pressure and available exits visible before pivoting into incidents, runtime, or adjacent monitoring surfaces."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: watchlistCount == 1 ? String(localized: "1 watched agent visible") : String(localized: "\(watchlistCount) watched agents visible"),
                    tone: watchlistCount > 0 ? .positive : .neutral
                )
            } facts: {
                if runtimeAlertCount > 0 {
                    Label(
                        runtimeAlertCount == 1 ? String(localized: "1 runtime alert") : String(localized: "\(runtimeAlertCount) runtime alerts"),
                        systemImage: "server.rack"
                    )
                }
                if issueCount > 0 {
                    Label(
                        issueCount == 1 ? String(localized: "1 fleet issue") : String(localized: "\(issueCount) fleet issues"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AgentsSectionInventoryDeck: View {
    let sectionCount: Int
    let visibleCount: Int
    let totalCount: Int
    let runningCount: Int
    let issueCount: Int
    let approvalCount: Int
    let staleCount: Int
    let watchlistCount: Int
    let authIssueCount: Int
    let sessionPressureCount: Int
    let hasSearchScope: Bool
    let filterLabel: String
    let filterTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: detailLine,
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: sectionCount == 1 ? String(localized: "1 live section") : String(localized: "\(sectionCount) live sections"),
                        tone: .positive
                    )
                    PresentationToneBadge(text: filterLabel, tone: filterTone)
                    PresentationToneBadge(
                        text: visibleCount == 1 ? String(localized: "1 visible agent") : String(localized: "\(visibleCount) visible agents"),
                        tone: visibleCount > 0 ? .positive : .neutral
                    )
                    if issueCount > 0 {
                        PresentationToneBadge(
                            text: issueCount == 1 ? String(localized: "1 fleet issue") : String(localized: "\(issueCount) fleet issues"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Section inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep fleet coverage, active pressure, and watchlist load visible before the route rail and agent rows take over."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: runningCount == 1 ? String(localized: "1 running") : String(localized: "\(runningCount) running"),
                    tone: runningCount > 0 ? .positive : .neutral
                )
            } facts: {
                if watchlistCount > 0 {
                    Label(
                        watchlistCount == 1 ? String(localized: "1 watched agent") : String(localized: "\(watchlistCount) watched agents"),
                        systemImage: "star.fill"
                    )
                }
                if approvalCount > 0 {
                    Label(
                        approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                        systemImage: "checkmark.shield"
                    )
                }
                if staleCount > 0 {
                    Label(
                        staleCount == 1 ? String(localized: "1 stale agent") : String(localized: "\(staleCount) stale agents"),
                        systemImage: "clock.badge.exclamationmark"
                    )
                }
                if authIssueCount > 0 {
                    Label(
                        authIssueCount == 1 ? String(localized: "1 auth issue") : String(localized: "\(authIssueCount) auth issues"),
                        systemImage: "key.horizontal"
                    )
                }
                if sessionPressureCount > 0 {
                    Label(
                        sessionPressureCount == 1 ? String(localized: "1 session hotspot") : String(localized: "\(sessionPressureCount) session hotspots"),
                        systemImage: "text.bubble"
                    )
                }
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
                Label(
                    totalCount == 1 ? String(localized: "1 total agent") : String(localized: "\(totalCount) total agents"),
                    systemImage: "person.3"
                )
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        sectionCount == 1
            ? String(localized: "1 fleet section is active below the controls deck.")
            : String(localized: "\(sectionCount) fleet sections are active below the controls deck.")
    }

    private var detailLine: String {
        String(localized: "Fleet coverage, active pressure, and watchlist load stay summarized before the route rail and filtered agent rows take over.")
    }
}

private struct AgentsPressureCoverageDeck: View {
    let issueCount: Int
    let approvalCount: Int
    let staleCount: Int
    let watchlistCount: Int
    let authIssueCount: Int
    let modelIssueCount: Int
    let sessionPressureCount: Int
    let runningCount: Int
    let visibleCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Pressure coverage keeps the fleet’s sharpest issue categories readable before the filtered agent rows begin."),
                detail: String(localized: "Use this deck to judge whether current fleet drag is coming from auth, model drift, session pressure, stale agents, or raw approval volume."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if issueCount > 0 {
                        PresentationToneBadge(
                            text: issueCount == 1 ? String(localized: "1 issue") : String(localized: "\(issueCount) issues"),
                            tone: .warning
                        )
                    }
                    if approvalCount > 0 {
                        PresentationToneBadge(
                            text: approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                            tone: .critical
                        )
                    }
                    if authIssueCount > 0 {
                        PresentationToneBadge(
                            text: authIssueCount == 1 ? String(localized: "1 auth issue") : String(localized: "\(authIssueCount) auth issues"),
                            tone: .warning
                        )
                    }
                    if sessionPressureCount > 0 {
                        PresentationToneBadge(
                            text: sessionPressureCount == 1 ? String(localized: "1 session hotspot") : String(localized: "\(sessionPressureCount) session hotspots"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Pressure coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep running coverage, stale agents, model drift, and watchlist pressure readable before opening individual agent cards."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: runningCount == 1 ? String(localized: "1 running agent") : String(localized: "\(runningCount) running agents"),
                    tone: runningCount > 0 ? .positive : .neutral
                )
            } facts: {
                Label(
                    visibleCount == 1 ? String(localized: "1 visible agent") : String(localized: "\(visibleCount) visible agents"),
                    systemImage: "person.3"
                )
                if staleCount > 0 {
                    Label(
                        staleCount == 1 ? String(localized: "1 stale agent") : String(localized: "\(staleCount) stale agents"),
                        systemImage: "clock.badge.exclamationmark"
                    )
                }
                if modelIssueCount > 0 {
                    Label(
                        modelIssueCount == 1 ? String(localized: "1 model issue") : String(localized: "\(modelIssueCount) model issues"),
                        systemImage: "square.stack.3d.up.slash"
                    )
                }
                if watchlistCount > 0 {
                    Label(
                        watchlistCount == 1 ? String(localized: "1 watched agent") : String(localized: "\(watchlistCount) watched agents"),
                        systemImage: "star"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AgentsSupportCoverageDeck: View {
    let totalCount: Int
    let runningCount: Int
    let watchlistCount: Int
    let authIssueCount: Int
    let modelIssueCount: Int
    let sessionPressureCount: Int
    let hasSearchScope: Bool
    let filterLabel: String
    let filterTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep fleet breadth, filter scope, and slower auth or model drag readable before opening individual agent cards."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: filterLabel, tone: filterTone)
                    PresentationToneBadge(
                        text: totalCount == 1 ? String(localized: "1 total agent") : String(localized: "\(totalCount) total agents"),
                        tone: totalCount > 0 ? .positive : .neutral
                    )
                    if hasSearchScope {
                        PresentationToneBadge(text: String(localized: "Search scoped"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Support coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep watchlist breadth, auth drift, model drift, and session pressure visible before the fleet list fans out."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: runningCount == 1 ? String(localized: "1 running") : String(localized: "\(runningCount) running"),
                    tone: runningCount > 0 ? .positive : .neutral
                )
            } facts: {
                if watchlistCount > 0 {
                    Label(
                        watchlistCount == 1 ? String(localized: "1 watched agent") : String(localized: "\(watchlistCount) watched agents"),
                        systemImage: "star.fill"
                    )
                }
                if authIssueCount > 0 {
                    Label(
                        authIssueCount == 1 ? String(localized: "1 auth issue") : String(localized: "\(authIssueCount) auth issues"),
                        systemImage: "key.horizontal"
                    )
                }
                if modelIssueCount > 0 {
                    Label(
                        modelIssueCount == 1 ? String(localized: "1 model issue") : String(localized: "\(modelIssueCount) model issues"),
                        systemImage: "square.stack.3d.up.slash"
                    )
                }
                if sessionPressureCount > 0 {
                    Label(
                        sessionPressureCount == 1 ? String(localized: "1 session hotspot") : String(localized: "\(sessionPressureCount) session hotspots"),
                        systemImage: "text.bubble"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if hasSearchScope {
            return String(localized: "Fleet support coverage is currently narrowed to a filtered slice of the agent list.")
        }
        if watchlistCount > 0 || authIssueCount > 0 || modelIssueCount > 0 {
            return String(localized: "Fleet support coverage is currently anchored by watchlist load and slower config drift.")
        }
        return String(localized: "Fleet support coverage is currently light and mostly reflects total agent breadth.")
    }
}

private struct AgentsWorkstreamCoverageDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let issueCount: Int
    let staleCount: Int
    let watchlistCount: Int
    let authIssueCount: Int
    let modelIssueCount: Int
    let sessionPressureCount: Int
    let hasSearchScope: Bool
    let filterLabel: String
    let filterTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to see whether fleet review is currently led by active issues, watched agents, or slower support drag before the agent list expands."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: filterLabel, tone: filterTone)
                    PresentationToneBadge(
                        text: visibleCount == 1 ? String(localized: "1 visible agent") : String(localized: "\(visibleCount) visible agents"),
                        tone: visibleCount > 0 ? .positive : .neutral
                    )
                    if hasSearchScope {
                        PresentationToneBadge(text: String(localized: "Search scoped"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Workstream coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep live fleet pressure, watchlist follow-through, and slower support drag readable before the fleet list or adjacent surfaces take over."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: totalCount == 1 ? String(localized: "1 total agent") : String(localized: "\(totalCount) total agents"),
                    tone: totalCount > 0 ? .positive : .neutral
                )
            } facts: {
                if issueSignalCount > 0 {
                    Label(
                        issueSignalCount == 1 ? String(localized: "1 live issue") : String(localized: "\(issueSignalCount) live issues"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if watchlistCount > 0 {
                    Label(
                        watchlistCount == 1 ? String(localized: "1 watched agent") : String(localized: "\(watchlistCount) watched agents"),
                        systemImage: "star.fill"
                    )
                }
                if supportSignalCount > 0 {
                    Label(
                        supportSignalCount == 1 ? String(localized: "1 support signal") : String(localized: "\(supportSignalCount) support signals"),
                        systemImage: "wrench.and.screwdriver"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var issueSignalCount: Int {
        issueCount + staleCount
    }

    private var supportSignalCount: Int {
        authIssueCount + modelIssueCount + sessionPressureCount
    }

    private var summaryLine: String {
        if issueSignalCount >= max(watchlistCount, supportSignalCount), issueSignalCount > 0 {
            return String(localized: "Fleet workstream coverage is currently anchored by active issue follow-through.")
        }
        if watchlistCount >= supportSignalCount, watchlistCount > 0 {
            return String(localized: "Fleet workstream coverage is currently anchored by watched-agent follow-through.")
        }
        if supportSignalCount > 0 || hasSearchScope {
            return String(localized: "Fleet workstream coverage is currently anchored by slower support drag and scoped review.")
        }
        return String(localized: "Fleet workstream coverage is currently light across the visible lanes.")
    }
}

private struct AgentsActionReadinessDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let visibleCount: Int
    let totalCount: Int
    let runningCount: Int
    let issueCount: Int
    let approvalCount: Int
    let watchlistCount: Int
    let sessionPressureCount: Int
    let hasSearchScope: Bool
    let filterLabel: String
    let filterTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to confirm route breadth, visible fleet slice, and filter readiness before opening individual agent rows or leaving the fleet list."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: filterLabel, tone: filterTone)
                    PresentationToneBadge(
                        text: String(localized: "\(primaryRouteCount + supportRouteCount) routes"),
                        tone: .neutral
                    )
                    if hasSearchScope {
                        PresentationToneBadge(text: String(localized: "Search scoped"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Action readiness"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep fleet slice, route exits, and pressure categories visible before drilling into agent detail or adjacent monitoring surfaces."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == 1 ? String(localized: "1 visible agent") : String(localized: "\(visibleCount) visible agents"),
                    tone: visibleCount > 0 ? .positive : .neutral
                )
            } facts: {
                Label(
                    totalCount == 1 ? String(localized: "1 total agent") : String(localized: "\(totalCount) total agents"),
                    systemImage: "person.3"
                )
                Label(
                    runningCount == 1 ? String(localized: "1 running") : String(localized: "\(runningCount) running"),
                    systemImage: "play.circle"
                )
                if issueCount > 0 {
                    Label(
                        issueCount == 1 ? String(localized: "1 issue") : String(localized: "\(issueCount) issues"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if approvalCount > 0 {
                    Label(
                        approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                        systemImage: "checkmark.shield"
                    )
                }
                if watchlistCount > 0 {
                    Label(
                        watchlistCount == 1 ? String(localized: "1 watched agent") : String(localized: "\(watchlistCount) watched agents"),
                        systemImage: "star.fill"
                    )
                }
                if sessionPressureCount > 0 {
                    Label(
                        sessionPressureCount == 1 ? String(localized: "1 session hotspot") : String(localized: "\(sessionPressureCount) session hotspots"),
                        systemImage: "text.bubble"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if hasSearchScope {
            return String(localized: "Agent action readiness is currently narrowed by a search-scoped fleet slice.")
        }
        if issueCount > 0 || approvalCount > 0 || sessionPressureCount > 0 {
            return String(localized: "Agent action readiness is currently centered on fleet pressure before deeper drilldown.")
        }
        return String(localized: "Agent action readiness is currently clear enough for route pivots and detail drilldown.")
    }
}

private struct AgentsFocusCoverageDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let runningCount: Int
    let issueCount: Int
    let staleCount: Int
    let watchlistCount: Int
    let authIssueCount: Int
    let modelIssueCount: Int
    let sessionPressureCount: Int
    let hasSearchScope: Bool
    let filterLabel: String
    let filterTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep the dominant fleet-review lane readable before opening individual agent rows or leaving the fleet list."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: filterLabel, tone: filterTone)
                    PresentationToneBadge(
                        text: visibleCount == 1 ? String(localized: "1 visible agent") : String(localized: "\(visibleCount) visible agents"),
                        tone: visibleCount > 0 ? .positive : .neutral
                    )
                    if hasSearchScope {
                        PresentationToneBadge(text: String(localized: "Search scoped"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Focus coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the dominant fleet slice readable before moving from the compact operator deck into individual agents and adjacent monitoring routes."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: runningCount == 1 ? String(localized: "1 running") : String(localized: "\(runningCount) running"),
                    tone: runningCount > 0 ? .positive : .neutral
                )
            } facts: {
                Label(
                    totalCount == 1 ? String(localized: "1 total agent") : String(localized: "\(totalCount) total agents"),
                    systemImage: "person.3"
                )
                if issueCount > 0 {
                    Label(
                        issueCount == 1 ? String(localized: "1 issue") : String(localized: "\(issueCount) issues"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if staleCount > 0 {
                    Label(
                        staleCount == 1 ? String(localized: "1 stale agent") : String(localized: "\(staleCount) stale agents"),
                        systemImage: "clock.badge.exclamationmark"
                    )
                }
                if watchlistCount > 0 {
                    Label(
                        watchlistCount == 1 ? String(localized: "1 watched agent") : String(localized: "\(watchlistCount) watched agents"),
                        systemImage: "star.fill"
                    )
                }
                if authIssueCount > 0 {
                    Label(
                        authIssueCount == 1 ? String(localized: "1 auth issue") : String(localized: "\(authIssueCount) auth issues"),
                        systemImage: "key.horizontal"
                    )
                }
                if modelIssueCount > 0 {
                    Label(
                        modelIssueCount == 1 ? String(localized: "1 model issue") : String(localized: "\(modelIssueCount) model issues"),
                        systemImage: "square.stack.3d.up.slash"
                    )
                }
                if sessionPressureCount > 0 {
                    Label(
                        sessionPressureCount == 1 ? String(localized: "1 session hotspot") : String(localized: "\(sessionPressureCount) session hotspots"),
                        systemImage: "text.bubble"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if hasSearchScope {
            return String(localized: "Fleet focus coverage is currently narrowed to a search-scoped slice of the agent list.")
        }
        if issueCount > 0 || staleCount > 0 || sessionPressureCount > 0 {
            return String(localized: "Fleet focus coverage is currently anchored by issue-heavy and stale fleet lanes.")
        }
        if watchlistCount > 0 || authIssueCount > 0 || modelIssueCount > 0 {
            return String(localized: "Fleet focus coverage is currently anchored by watched agents and slower configuration drift.")
        }
        return String(localized: "Fleet focus coverage is currently balanced across the visible running fleet slice.")
    }
}

private struct AgentsFleetInventoryDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let runningCount: Int
    let issueCount: Int
    let approvalCount: Int
    let staleCount: Int
    let watchlistCount: Int
    let visibleWatchlistCount: Int
    let authIssueCount: Int
    let modelIssueCount: Int
    let sessionPressureCount: Int
    let hasSearchScope: Bool
    let filterLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: visibleCount == totalCount
                    ? String(localized: "The compact fleet slice is showing the full visible agent registry.")
                    : String(localized: "The compact fleet slice is showing \(visibleCount) of \(totalCount) agents."),
                detail: hasSearchScope
                    ? String(localized: "Search is narrowing the fleet, so this deck keeps the visible slice readable before the full list.")
                    : String(localized: "Use the fleet inventory deck to gauge running load, watch pressure, and auth drift before scanning every agent row."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: filterLabel, tone: .neutral)
                    PresentationToneBadge(
                        text: visibleCount == 1 ? String(localized: "1 visible agent") : String(localized: "\(visibleCount) visible agents"),
                        tone: .positive
                    )
                    if issueCount > 0 {
                        PresentationToneBadge(
                            text: issueCount == 1 ? String(localized: "1 issue") : String(localized: "\(issueCount) issues"),
                            tone: .warning
                        )
                    }
                    if approvalCount > 0 {
                        PresentationToneBadge(
                            text: approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                            tone: .critical
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Fleet Facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep running coverage, watchlist visibility, and the sharpest issue categories visible before opening individual agent cards."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: runningCount == 1 ? String(localized: "1 running agent") : String(localized: "\(runningCount) running agents"),
                    tone: runningCount > 0 ? .positive : .neutral
                )
            } facts: {
                if visibleWatchlistCount > 0 || watchlistCount > 0 {
                    Label(
                        visibleWatchlistCount == watchlistCount
                            ? (watchlistCount == 1 ? String(localized: "1 watched agent visible") : String(localized: "\(watchlistCount) watched agents visible"))
                            : String(localized: "\(visibleWatchlistCount) of \(watchlistCount) watched visible"),
                        systemImage: "star"
                    )
                }
                if staleCount > 0 {
                    Label(
                        staleCount == 1 ? String(localized: "1 stale agent") : String(localized: "\(staleCount) stale agents"),
                        systemImage: "clock.badge.exclamationmark"
                    )
                }
                if authIssueCount > 0 {
                    Label(
                        authIssueCount == 1 ? String(localized: "1 auth issue") : String(localized: "\(authIssueCount) auth issues"),
                        systemImage: "lock.slash"
                    )
                }
                if modelIssueCount > 0 {
                    Label(
                        modelIssueCount == 1 ? String(localized: "1 model issue") : String(localized: "\(modelIssueCount) model issues"),
                        systemImage: "square.stack.3d.up.slash"
                    )
                }
                if sessionPressureCount > 0 {
                    Label(
                        sessionPressureCount == 1 ? String(localized: "1 session hotspot") : String(localized: "\(sessionPressureCount) session hotspots"),
                        systemImage: "rectangle.stack.badge.person.crop"
                    )
                }
            }
        }
        .padding(.vertical, 2)
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

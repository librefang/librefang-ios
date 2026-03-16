import SwiftUI

private enum SessionsSectionAnchor: Hashable {
    case sessions
}

struct SessionsView: View {
    @Environment(\.dependencies) private var deps
    @State private var searchText: String
    @State private var filter: SessionFilter
    @State private var pendingSessionAction: AgentSessionControlAction?
    @State private var sessionActionInFlightID: String?
    @State private var editingSession: SessionInfo?
    @State private var sessionLabelDraft = ""
    @State private var pendingDeleteSession: SessionInfo?
    @State private var sessionCatalogActionInFlightID: String?
    @State private var operatorNotice: OperatorActionNotice?

    init(initialSearchText: String = "", initialFilter: SessionFilter = .all) {
        _searchText = State(initialValue: initialSearchText)
        _filter = State(initialValue: initialFilter)
    }

    private var vm: DashboardViewModel { deps.dashboardViewModel }

    private var filteredItems: [SessionAttentionItem] {
        let base = vm.sessions.map { vm.sessionAttentionItem(for: $0) }

        return base
            .filter { item in
                switch filter {
                case .all:
                    true
                case .attention:
                    item.severity > 0
                case .highVolume:
                    item.session.messageCount >= 40
                case .unlabeled:
                    !item.hasLabel
                }
            }
            .filter { item in
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { return true }
                let haystack = [
                    item.agent?.name ?? "",
                    item.session.agentId,
                    item.session.label ?? "",
                    item.reasons.joined(separator: " ")
                ]
                .joined(separator: " ")
                .lowercased()
                return haystack.contains(query.lowercased())
            }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return lhs.severity > rhs.severity
                }
                if lhs.session.messageCount != rhs.session.messageCount {
                    return lhs.session.messageCount > rhs.session.messageCount
                }
                return lhs.session.createdAt > rhs.session.createdAt
            }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var snapshotFilterTone: PresentationTone {
        switch filter {
        case .attention, .highVolume:
            return .warning
        case .unlabeled:
            return .caution
        case .all:
            return .neutral
        }
    }

    private var highVolumeThreshold: Int { 40 }

    private var visibleAttentionCount: Int {
        filteredItems.filter { $0.severity > 0 }.count
    }

    private var visibleHighVolumeCount: Int {
        filteredItems.filter { $0.session.messageCount >= highVolumeThreshold }.count
    }

    private var visibleUnlabeledCount: Int {
        filteredItems.filter { !$0.hasLabel }.count
    }

    private var visibleDuplicateAgentCount: Int {
        Set(filteredItems.filter { $0.duplicateCount > 1 }.map { $0.session.agentId }).count
    }

    private var sessionsSectionCount: Int { 1 }
    private var sessionsPrimaryRouteCount: Int { 3 }
    private var sessionsSupportRouteCount: Int { 2 }
    private var sessionsSectionPreviewTitles: [String] {
        [String(localized: "Sessions")]
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    SessionScoreboard(vm: vm)
                        .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
                }

                if filteredItems.isEmpty && !vm.isLoading {
                    Section("Sessions") {
                        ContentUnavailableView(
                            searchText.isEmpty ? String(localized: "No Sessions In This Filter") : String(localized: "No Search Results"),
                            systemImage: "rectangle.stack",
                            description: Text(searchText.isEmpty ? String(localized: "Change the filter or refresh.") : String(localized: "Try a different search."))
                        )
                    }
                    .id(SessionsSectionAnchor.sessions)
                } else {
                    Section("Sessions") {
                        ForEach(filteredItems) { item in
                            sessionRow(for: item)
                        }
                    }
                    .id(SessionsSectionAnchor.sessions)
                }
            }
            .navigationTitle(String(localized: "Sessions"))
            .searchable(text: $searchText, prompt: Text(String(localized: "Search session, label, or agent")))
            .monitoringRefreshInteractionGate(isRefreshing: vm.isLoading)
            .refreshable {
                await vm.refresh()
            }
            .overlay {
                if vm.isLoading && vm.sessions.isEmpty {
                    ProgressView(String(localized: "Loading sessions..."))
                }
            }
            .task {
                if vm.sessions.isEmpty {
                    await vm.refresh()
                }
            }
            .confirmationDialog(
                pendingSessionAction?.title ?? "",
                isPresented: sessionActionConfirmationPresented,
                titleVisibility: .visible,
                presenting: pendingSessionAction
            ) { action in
                Button(action.confirmLabel, role: action.isDestructive ? .destructive : nil) {
                    Task { await performSessionAction(action) }
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: { action in
                Text(action.message)
            }
            .confirmationDialog(
                String(localized: "Delete Session"),
                isPresented: deleteSessionConfirmationPresented,
                titleVisibility: .visible,
                presenting: pendingDeleteSession
            ) { session in
                Button(String(localized: "Delete Session"), role: .destructive) {
                    Task { await deleteSession(session) }
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: { session in
                Text(String(localized: "Remove \(displayTitle(for: session)) and its messages from LibreFang? This cannot be undone."))
            }
            .sheet(item: $editingSession) { session in
                NavigationStack {
                    Form {
                        Section {
                            TextField(String(localized: "Optional label"), text: $sessionLabelDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } header: {
                            Text(String(localized: "Session Label"))
                        }
                    }
                    .navigationTitle(String(localized: "Edit Label"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "Cancel")) {
                                editingSession = nil
                            }
                            .disabled(isCatalogActionBusy)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                Task { await saveSessionLabel(for: session) }
                            } label: {
                                if sessionCatalogActionInFlightID == "label:\(session.sessionId)" {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text(String(localized: "Save"))
                                }
                            }
                            .disabled(isCatalogActionBusy)
                        }
                    }
                }
            }
            .alert(item: $operatorNotice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text(String(localized: "OK")))
                )
            }
        }
    }

    private func jump(_ proxy: ScrollViewProxy, to anchor: SessionsSectionAnchor) {
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    private func sessionsSectionPreviewJumpItems(_ proxy: ScrollViewProxy) -> [MonitoringSectionJumpItem] {
        [
            MonitoringSectionJumpItem(
                title: String(localized: "Sessions"),
                systemImage: "rectangle.stack",
                tone: snapshotFilterTone
            ) {
                jump(proxy, to: .sessions)
            }
        ]
    }

    private var sessionsStatusDeckCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: vm.totalSessionCount == 1
                    ? String(localized: "1 session is visible in the current workspace snapshot.")
                    : String(localized: "\(vm.totalSessionCount) sessions are visible in the current workspace snapshot."),
                detail: String(localized: "High-volume, unlabeled, and duplicated sessions stay visible before the list.")
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: filter.label, tone: snapshotFilterTone)
                    if vm.sessionAttentionCount > 0 {
                        PresentationToneBadge(
                            text: vm.sessionAttentionCount == 1 ? String(localized: "1 attention item") : String(localized: "\(vm.sessionAttentionCount) attention items"),
                            tone: .warning
                        )
                    }
                    if vm.highVolumeSessionCount > 0 {
                        PresentationToneBadge(
                            text: vm.highVolumeSessionCount == 1 ? String(localized: "1 high-volume session") : String(localized: "\(vm.highVolumeSessionCount) high-volume sessions"),
                            tone: .warning
                        )
                    }
                    if vm.unlabeledSessionCount > 0 {
                        PresentationToneBadge(
                            text: vm.unlabeledSessionCount == 1 ? String(localized: "1 unlabeled session") : String(localized: "\(vm.unlabeledSessionCount) unlabeled sessions"),
                            tone: .caution
                        )
                    }
                    if vm.multiSessionAgentCount > 0 {
                        PresentationToneBadge(
                            text: vm.multiSessionAgentCount == 1 ? String(localized: "1 agent with multiple sessions") : String(localized: "\(vm.multiSessionAgentCount) agents with multiple sessions"),
                            tone: .warning
                        )
                    }
                    if !normalizedSearchText.isEmpty {
                        PresentationToneBadge(
                            text: filteredItems.count == 1 ? String(localized: "1 visible result") : String(localized: "\(filteredItems.count) visible results"),
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Session queue facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep backlog scope, hotspot counts, and result volume visible before working the session list."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: filter.label, tone: snapshotFilterTone)
            } facts: {
                Label(
                    vm.totalSessionCount == 1 ? String(localized: "1 total session") : String(localized: "\(vm.totalSessionCount) total sessions"),
                    systemImage: "text.bubble"
                )
                if vm.sessionAttentionCount > 0 {
                    Label(
                        vm.sessionAttentionCount == 1 ? String(localized: "1 hotspot") : String(localized: "\(vm.sessionAttentionCount) hotspots"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if vm.highVolumeSessionCount > 0 {
                    Label(
                        vm.highVolumeSessionCount == 1 ? String(localized: "1 high-volume session") : String(localized: "\(vm.highVolumeSessionCount) high-volume sessions"),
                        systemImage: "chart.bar.xaxis"
                    )
                }
                if vm.unlabeledSessionCount > 0 {
                    Label(
                        vm.unlabeledSessionCount == 1 ? String(localized: "1 unlabeled session") : String(localized: "\(vm.unlabeledSessionCount) unlabeled sessions"),
                        systemImage: "tag.slash"
                    )
                }
                if vm.multiSessionAgentCount > 0 {
                    Label(
                        vm.multiSessionAgentCount == 1 ? String(localized: "1 multi-session agent") : String(localized: "\(vm.multiSessionAgentCount) multi-session agents"),
                        systemImage: "person.3"
                    )
                }
                Label(
                    filteredItems.count == 1 ? String(localized: "1 visible result") : String(localized: "\(filteredItems.count) visible results"),
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            }
        }
    }

    private var sessionsControlDeckCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SessionFilterCard(
                filter: $filter,
                searchText: searchText,
                visibleCount: filteredItems.count,
                totalCount: vm.sessions.count
            )
        }
    }

    private var sessionsSectionInventoryDeck: some View {
        SessionsSectionInventoryDeck(
            sectionCount: sessionsSectionCount,
            visibleCount: filteredItems.count,
            totalCount: vm.sessions.count,
            attentionCount: visibleAttentionCount,
            highVolumeCount: visibleHighVolumeCount,
            unlabeledCount: visibleUnlabeledCount,
            duplicateAgentCount: visibleDuplicateAgentCount,
            hasSearchScope: !normalizedSearchText.isEmpty,
            filterLabel: filter.label,
            filterTone: snapshotFilterTone
        )
    }

    private var sessionsPressureCoverageDeck: some View {
        SessionsPressureCoverageDeck(
            attentionCount: visibleAttentionCount,
            highVolumeCount: visibleHighVolumeCount,
            unlabeledCount: visibleUnlabeledCount,
            duplicateAgentCount: visibleDuplicateAgentCount,
            visibleCount: filteredItems.count,
            totalCount: vm.sessions.count,
            hasSearchScope: !normalizedSearchText.isEmpty,
            filterLabel: filter.label,
            filterTone: snapshotFilterTone,
            showsFilterBadge: {
                switch filter {
                case .all:
                    false
                default:
                    true
                }
            }()
        )
    }

    private var sessionsQueueCoverageDeck: some View {
        SessionsQueueCoverageDeck(
            attentionCount: visibleAttentionCount,
            highVolumeCount: visibleHighVolumeCount,
            unlabeledCount: visibleUnlabeledCount,
            duplicateAgentCount: visibleDuplicateAgentCount,
            visibleCount: filteredItems.count,
            totalCount: vm.sessions.count,
            hasSearchScope: !normalizedSearchText.isEmpty
        )
    }

    private var sessionsSupportCoverageDeck: some View {
        SessionsSupportCoverageDeck(
            totalCount: vm.sessions.count,
            highVolumeCount: visibleHighVolumeCount,
            unlabeledCount: visibleUnlabeledCount,
            duplicateAgentCount: visibleDuplicateAgentCount,
            hasSearchScope: !normalizedSearchText.isEmpty,
            filterLabel: filter.label,
            filterTone: snapshotFilterTone
        )
    }

    private var sessionsActionReadinessDeck: some View {
        SessionsActionReadinessDeck(
            primaryRouteCount: sessionsPrimaryRouteCount,
            supportRouteCount: sessionsSupportRouteCount,
            visibleCount: filteredItems.count,
            attentionCount: visibleAttentionCount,
            highVolumeCount: visibleHighVolumeCount,
            unlabeledCount: visibleUnlabeledCount,
            hasSearchScope: !normalizedSearchText.isEmpty,
            filterLabel: filter.label,
            filterTone: snapshotFilterTone
        )
    }

    private var sessionsFocusCoverageDeck: some View {
        SessionsFocusCoverageDeck(
            visibleCount: filteredItems.count,
            attentionCount: visibleAttentionCount,
            highVolumeCount: visibleHighVolumeCount,
            unlabeledCount: visibleUnlabeledCount,
            duplicateAgentCount: visibleDuplicateAgentCount,
            hasSearchScope: !normalizedSearchText.isEmpty,
            filterLabel: filter.label,
            filterTone: snapshotFilterTone
        )
    }

    private var sessionsWorkstreamCoverageDeck: some View {
        SessionsWorkstreamCoverageDeck(
            visibleCount: filteredItems.count,
            attentionCount: visibleAttentionCount,
            highVolumeCount: visibleHighVolumeCount,
            unlabeledCount: visibleUnlabeledCount,
            duplicateAgentCount: visibleDuplicateAgentCount,
            hasSearchScope: !normalizedSearchText.isEmpty,
            filterLabel: filter.label,
            filterTone: snapshotFilterTone
        )
    }

    private var sessionsScopeCoverageDeck: some View {
        SessionsScopeCoverageDeck(
            visibleCount: filteredItems.count,
            totalCount: vm.sessions.count,
            attentionCount: visibleAttentionCount,
            highVolumeCount: visibleHighVolumeCount,
            unlabeledCount: visibleUnlabeledCount,
            duplicateAgentCount: visibleDuplicateAgentCount,
            hasSearchScope: !normalizedSearchText.isEmpty,
            isFilterScoped: filter != .all,
            filterLabel: filter.label,
            filterTone: snapshotFilterTone
        )
    }

private struct SessionsRouteInventoryDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let visibleCount: Int
    let totalCount: Int
    let attentionCount: Int
    let highVolumeCount: Int
    let hasSearchScope: Bool
    let filterLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: hasSearchScope
                    ? String(localized: "Session routes stay compact while the backlog is search-scoped.")
                    : String(localized: "Session routes stay compact before the wider runtime and incident drilldowns."),
                detail: String(localized: "Use the route inventory to gauge the active session slice before leaving the queue."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: filterLabel, tone: .neutral)
                    PresentationToneBadge(
                        text: primaryRouteCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryRouteCount) primary routes"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: supportRouteCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportRouteCount) support routes"),
                        tone: .neutral
                    )
                    if attentionCount > 0 {
                        PresentationToneBadge(
                            text: attentionCount == 1 ? String(localized: "1 hotspot") : String(localized: "\(attentionCount) hotspots"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Route Facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep visible backlog size and high-volume pressure readable before pivoting into runtime, incidents, agents, or events."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == totalCount
                        ? (visibleCount == 1 ? String(localized: "1 visible session") : String(localized: "\(visibleCount) visible sessions"))
                        : String(localized: "\(visibleCount) of \(totalCount) visible"),
                    tone: .positive
                )
            } facts: {
                if highVolumeCount > 0 {
                    Label(
                        highVolumeCount == 1 ? String(localized: "1 high-volume session") : String(localized: "\(highVolumeCount) high-volume sessions"),
                        systemImage: "chart.bar.xaxis"
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

private struct SessionsActionReadinessDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let visibleCount: Int
    let attentionCount: Int
    let highVolumeCount: Int
    let unlabeledCount: Int
    let hasSearchScope: Bool
    let filterLabel: String
    let filterTone: PresentationTone

    private var totalRouteCount: Int {
        primaryRouteCount + supportRouteCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to check route breadth, filter scope, and backlog readiness before opening the session route deck."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: filterLabel, tone: filterTone)
                    PresentationToneBadge(
                        text: totalRouteCount == 1 ? String(localized: "1 route ready") : String(localized: "\(totalRouteCount) routes ready"),
                        tone: totalRouteCount > 0 ? .positive : .neutral
                    )
                    if attentionCount > 0 {
                        PresentationToneBadge(
                            text: attentionCount == 1 ? String(localized: "1 hotspot") : String(localized: "\(attentionCount) hotspots"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Action readiness"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep route breadth, filter scope, and visible backlog shape readable before leaving the session queue for other monitors."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == 1 ? String(localized: "1 visible session") : String(localized: "\(visibleCount) visible sessions"),
                    tone: visibleCount > 0 ? .positive : .neutral
                )
            } facts: {
                Label(
                    primaryRouteCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryRouteCount) primary routes"),
                    systemImage: "arrowshape.turn.up.right"
                )
                if supportRouteCount > 0 {
                    Label(
                        supportRouteCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportRouteCount) support routes"),
                        systemImage: "square.grid.2x2"
                    )
                }
                if highVolumeCount > 0 {
                    Label(
                        highVolumeCount == 1 ? String(localized: "1 high-volume session") : String(localized: "\(highVolumeCount) high-volume sessions"),
                        systemImage: "chart.bar"
                    )
                }
                if unlabeledCount > 0 {
                    Label(
                        unlabeledCount == 1 ? String(localized: "1 unlabeled session") : String(localized: "\(unlabeledCount) unlabeled sessions"),
                        systemImage: "tag.slash"
                    )
                }
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
    }

    private var summaryLine: String {
        if attentionCount > 0 || highVolumeCount > 0 || unlabeledCount > 0 {
            return String(localized: "Session action readiness is currently anchored by visible backlog pressure and the next operator exits.")
        }
        if hasSearchScope {
            return String(localized: "Session action readiness is currently anchored by the active search scope and filtered backlog slice.")
        }
        return String(localized: "Session action readiness is currently centered on grouped session routes and backlog coverage.")
    }
}

private struct SessionsFocusCoverageDeck: View {
    let visibleCount: Int
    let attentionCount: Int
    let highVolumeCount: Int
    let unlabeledCount: Int
    let duplicateAgentCount: Int
    let hasSearchScope: Bool
    let filterLabel: String
    let filterTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep the dominant session lane visible before opening route rails and the full session backlog."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: filterLabel, tone: filterTone)
                    PresentationToneBadge(
                        text: visibleCount == 1 ? String(localized: "1 visible session") : String(localized: "\(visibleCount) visible sessions"),
                        tone: visibleCount > 0 ? .positive : .neutral
                    )
                    if attentionCount > 0 {
                        PresentationToneBadge(
                            text: attentionCount == 1 ? String(localized: "1 hotspot") : String(localized: "\(attentionCount) hotspots"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Focus coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the dominant session lane readable before moving from compact control decks into the backlog list and route rails."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: highVolumeCount == 1 ? String(localized: "1 high-volume") : String(localized: "\(highVolumeCount) high-volume"),
                    tone: highVolumeCount > 0 ? .warning : .neutral
                )
            } facts: {
                if unlabeledCount > 0 {
                    Label(
                        unlabeledCount == 1 ? String(localized: "1 unlabeled") : String(localized: "\(unlabeledCount) unlabeled"),
                        systemImage: "tag.slash"
                    )
                }
                if duplicateAgentCount > 0 {
                    Label(
                        duplicateAgentCount == 1 ? String(localized: "1 duplicate agent") : String(localized: "\(duplicateAgentCount) duplicate agents"),
                        systemImage: "person.2"
                    )
                }
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
    }

    private var summaryLine: String {
        if attentionCount > 0 || highVolumeCount > 0 || unlabeledCount > 0 {
            return String(localized: "Session focus coverage is currently anchored by backlog pressure and label hygiene.")
        }
        if hasSearchScope {
            return String(localized: "Session focus coverage is currently anchored by the filtered backlog slice.")
        }
        return String(localized: "Session focus coverage is currently balanced across the visible session lanes.")
    }
}

private struct SessionsWorkstreamCoverageDeck: View {
    let visibleCount: Int
    let attentionCount: Int
    let highVolumeCount: Int
    let unlabeledCount: Int
    let duplicateAgentCount: Int
    let hasSearchScope: Bool
    let filterLabel: String
    let filterTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to see whether session review is currently led by hotspots, label hygiene, or a filtered backlog slice before the full queue opens."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: filterLabel, tone: filterTone)
                    PresentationToneBadge(
                        text: visibleCount == 1 ? String(localized: "1 visible session") : String(localized: "\(visibleCount) visible sessions"),
                        tone: visibleCount > 0 ? .positive : .neutral
                    )
                    if attentionCount > 0 {
                        PresentationToneBadge(
                            text: attentionCount == 1 ? String(localized: "1 hotspot") : String(localized: "\(attentionCount) hotspots"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Workstream coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep hotspot pressure, label hygiene, and duplicate-agent spread readable before moving through the session backlog."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: highVolumeCount == 1 ? String(localized: "1 high-volume") : String(localized: "\(highVolumeCount) high-volume"),
                    tone: highVolumeCount > 0 ? .warning : .neutral
                )
            } facts: {
                if unlabeledCount > 0 {
                    Label(
                        unlabeledCount == 1 ? String(localized: "1 unlabeled") : String(localized: "\(unlabeledCount) unlabeled"),
                        systemImage: "tag.slash"
                    )
                }
                if duplicateAgentCount > 0 {
                    Label(
                        duplicateAgentCount == 1 ? String(localized: "1 duplicate agent") : String(localized: "\(duplicateAgentCount) duplicate agents"),
                        systemImage: "person.2"
                    )
                }
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
    }

    private var summaryLine: String {
        if attentionCount > 0 || highVolumeCount > 0 {
            return String(localized: "Session workstream coverage is currently anchored by hotspot and high-volume backlog pressure.")
        }
        if unlabeledCount > 0 {
            return String(localized: "Session workstream coverage is currently anchored by label hygiene work.")
        }
        if duplicateAgentCount > 0 {
            return String(localized: "Session workstream coverage is currently anchored by duplicate-agent backlog lanes.")
        }
        if hasSearchScope {
            return String(localized: "Session workstream coverage is currently anchored by the filtered backlog slice.")
        }
        return String(localized: "Session workstream coverage is currently light across the visible backlog.")
    }
}

private struct SessionsScopeCoverageDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let attentionCount: Int
    let highVolumeCount: Int
    let unlabeledCount: Int
    let duplicateAgentCount: Int
    let hasSearchScope: Bool
    let isFilterScoped: Bool
    let filterLabel: String
    let filterTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep filter scope, search state, and visible backlog breadth readable before opening routes and session rows."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: filterLabel, tone: filterTone)
                    if hasSearchScope {
                        PresentationToneBadge(text: String(localized: "Search scoped"), tone: .neutral)
                    }
                    PresentationToneBadge(
                        text: visibleCount == totalCount
                            ? (visibleCount == 1 ? String(localized: "1 visible session") : String(localized: "\(visibleCount) visible sessions"))
                            : String(localized: "\(visibleCount) of \(totalCount) visible"),
                        tone: visibleCount > 0 ? .positive : .neutral
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Scope coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the active backlog slice, label hygiene, and duplicate-agent spread readable before moving into queue rows and route rails."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: filterLabel, tone: filterTone)
            } facts: {
                if attentionCount > 0 {
                    Label(
                        attentionCount == 1 ? String(localized: "1 hotspot") : String(localized: "\(attentionCount) hotspots"),
                        systemImage: "exclamationmark.circle"
                    )
                }
                if highVolumeCount > 0 {
                    Label(
                        highVolumeCount == 1 ? String(localized: "1 high-volume") : String(localized: "\(highVolumeCount) high-volume"),
                        systemImage: "chart.bar"
                    )
                }
                if unlabeledCount > 0 {
                    Label(
                        unlabeledCount == 1 ? String(localized: "1 unlabeled") : String(localized: "\(unlabeledCount) unlabeled"),
                        systemImage: "tag.slash"
                    )
                }
                if duplicateAgentCount > 0 {
                    Label(
                        duplicateAgentCount == 1 ? String(localized: "1 duplicate agent") : String(localized: "\(duplicateAgentCount) duplicate agents"),
                        systemImage: "person.2"
                    )
                }
                if isFilterScoped {
                    Label(String(localized: "Filter scoped"), systemImage: "line.3.horizontal.decrease.circle")
                }
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
    }

    private var summaryLine: String {
        if hasSearchScope {
            return String(localized: "Session scope coverage is currently anchored by the active search slice.")
        }
        if isFilterScoped {
            return String(localized: "Session scope coverage is currently narrowed to a filtered backlog slice.")
        }
        if visibleCount == totalCount {
            return String(localized: "Session scope coverage is currently balanced across the visible backlog.")
        }
        return String(localized: "Session scope coverage is currently centered on the visible mobile backlog slice.")
    }
}

private struct SessionsSectionInventoryDeck: View {
    let sectionCount: Int
    let visibleCount: Int
    let totalCount: Int
    let attentionCount: Int
    let highVolumeCount: Int
    let unlabeledCount: Int
    let duplicateAgentCount: Int
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
                        text: visibleCount == 1 ? String(localized: "1 visible session") : String(localized: "\(visibleCount) visible sessions"),
                        tone: visibleCount > 0 ? .positive : .neutral
                    )
                    if attentionCount > 0 {
                        PresentationToneBadge(
                            text: attentionCount == 1 ? String(localized: "1 hotspot") : String(localized: "\(attentionCount) hotspots"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Section inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep hotspot counts, label hygiene, and duplicate-agent pressure visible before the session rows take over."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: totalCount == 1 ? String(localized: "1 total session") : String(localized: "\(totalCount) total sessions"),
                    tone: .neutral
                )
            } facts: {
                if highVolumeCount > 0 {
                    Label(
                        highVolumeCount == 1 ? String(localized: "1 high-volume session") : String(localized: "\(highVolumeCount) high-volume sessions"),
                        systemImage: "chart.bar.xaxis"
                    )
                }
                if unlabeledCount > 0 {
                    Label(
                        unlabeledCount == 1 ? String(localized: "1 unlabeled session") : String(localized: "\(unlabeledCount) unlabeled sessions"),
                        systemImage: "tag.slash"
                    )
                }
                if duplicateAgentCount > 0 {
                    Label(
                        duplicateAgentCount == 1 ? String(localized: "1 multi-session agent") : String(localized: "\(duplicateAgentCount) multi-session agents"),
                        systemImage: "person.3"
                    )
                }
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        sectionCount == 1
            ? String(localized: "1 session section is active below the controls deck.")
            : String(localized: "\(sectionCount) session sections are active below the controls deck.")
    }

    private var detailLine: String {
        String(localized: "Hotspot counts, label hygiene, and duplicate-agent pressure stay summarized before the session list takes over the page.")
    }
}

private struct SessionsPressureCoverageDeck: View {
    let attentionCount: Int
    let highVolumeCount: Int
    let unlabeledCount: Int
    let duplicateAgentCount: Int
    let visibleCount: Int
    let totalCount: Int
    let hasSearchScope: Bool
    let filterLabel: String
    let filterTone: PresentationTone
    let showsFilterBadge: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this pressure slice to separate hotspot churn, label hygiene gaps, and scoped session work before the queue rows begin."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if attentionCount > 0 {
                        PresentationToneBadge(
                            text: attentionCount == 1 ? String(localized: "1 hotspot") : String(localized: "\(attentionCount) hotspots"),
                            tone: .warning
                        )
                    }
                    if highVolumeCount > 0 {
                        PresentationToneBadge(
                            text: highVolumeCount == 1 ? String(localized: "1 high-volume") : String(localized: "\(highVolumeCount) high-volume"),
                            tone: .warning
                        )
                    }
                    if unlabeledCount > 0 {
                        PresentationToneBadge(
                            text: unlabeledCount == 1 ? String(localized: "1 unlabeled") : String(localized: "\(unlabeledCount) unlabeled"),
                            tone: .caution
                        )
                    }
                    if showsFilterBadge {
                        PresentationToneBadge(text: filterLabel, tone: filterTone)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Pressure coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep visible session breadth, duplicate-agent churn, and scoped backlog pressure readable before drilling into the session queue."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == totalCount
                        ? (visibleCount == 1 ? String(localized: "1 visible session") : String(localized: "\(visibleCount) visible sessions"))
                        : String(localized: "\(visibleCount) of \(totalCount) visible"),
                    tone: attentionCount > 0 || highVolumeCount > 0 ? .warning : .positive
                )
            } facts: {
                Label(
                    totalCount == 1 ? String(localized: "1 total session") : String(localized: "\(totalCount) total sessions"),
                    systemImage: "rectangle.stack"
                )
                if duplicateAgentCount > 0 {
                    Label(
                        duplicateAgentCount == 1 ? String(localized: "1 multi-session agent") : String(localized: "\(duplicateAgentCount) multi-session agents"),
                        systemImage: "person.3"
                    )
                }
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if attentionCount > 0 {
            return attentionCount == 1
                ? String(localized: "Session pressure is currently anchored by 1 hotspot.")
                : String(localized: "Session pressure is currently anchored by \(attentionCount) hotspots.")
        }
        if highVolumeCount > 0 {
            return highVolumeCount == 1
                ? String(localized: "Session pressure is currently concentrated in 1 high-volume session.")
                : String(localized: "Session pressure is currently concentrated in \(highVolumeCount) high-volume sessions.")
        }
        if unlabeledCount > 0 {
            return unlabeledCount == 1
                ? String(localized: "Session pressure is currently concentrated in 1 unlabeled session.")
                : String(localized: "Session pressure is currently concentrated in \(unlabeledCount) unlabeled sessions.")
        }
        if duplicateAgentCount > 0 {
            return duplicateAgentCount == 1
                ? String(localized: "Session pressure is currently concentrated in 1 multi-session agent.")
                : String(localized: "Session pressure is currently concentrated in \(duplicateAgentCount) multi-session agents.")
        }
        if hasSearchScope || showsFilterBadge {
            return String(localized: "Session pressure is currently narrowed by the active backlog filter or search scope.")
        }
        return String(localized: "Session pressure is currently spread across the visible session backlog.")
    }
}

private struct SessionsSupportCoverageDeck: View {
    let totalCount: Int
    let highVolumeCount: Int
    let unlabeledCount: Int
    let duplicateAgentCount: Int
    let hasSearchScope: Bool
    let filterLabel: String
    let filterTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep backlog scope, label hygiene, and duplicate-agent churn readable before the session queue rows begin."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: filterLabel, tone: filterTone)
                    PresentationToneBadge(
                        text: totalCount == 1 ? String(localized: "1 total session") : String(localized: "\(totalCount) total sessions"),
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
                    Text(String(localized: "Keep high-volume churn, label hygiene, and multi-session agent drag readable before drilling into individual sessions."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: highVolumeCount == 1 ? String(localized: "1 high-volume") : String(localized: "\(highVolumeCount) high-volume"),
                    tone: highVolumeCount > 0 ? .warning : .neutral
                )
            } facts: {
                if unlabeledCount > 0 {
                    Label(
                        unlabeledCount == 1 ? String(localized: "1 unlabeled") : String(localized: "\(unlabeledCount) unlabeled"),
                        systemImage: "tag.slash"
                    )
                }
                if duplicateAgentCount > 0 {
                    Label(
                        duplicateAgentCount == 1 ? String(localized: "1 multi-session agent") : String(localized: "\(duplicateAgentCount) multi-session agents"),
                        systemImage: "person.3"
                    )
                }
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if hasSearchScope {
            return String(localized: "Session support coverage is currently narrowed by the active backlog filter or search scope.")
        }
        if unlabeledCount > 0 || duplicateAgentCount > 0 {
            return String(localized: "Session support coverage is currently anchored by label hygiene and duplicate-agent churn.")
        }
        if highVolumeCount > 0 {
            return String(localized: "Session support coverage is currently anchored by high-volume backlog churn.")
        }
        return String(localized: "Session support coverage is currently light and mostly reflects backlog breadth.")
    }
}

private struct SessionsQueueCoverageDeck: View {
    let attentionCount: Int
    let highVolumeCount: Int
    let unlabeledCount: Int
    let duplicateAgentCount: Int
    let visibleCount: Int
    let totalCount: Int
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Queue coverage keeps session pressure readable before the session rows begin."),
                detail: String(localized: "Use this deck to gauge whether the current slice is dominated by hotspots, unlabeled sessions, or duplicate-agent churn."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if attentionCount > 0 {
                        PresentationToneBadge(
                            text: attentionCount == 1 ? String(localized: "1 hotspot") : String(localized: "\(attentionCount) hotspots"),
                            tone: .warning
                        )
                    }
                    if highVolumeCount > 0 {
                        PresentationToneBadge(
                            text: highVolumeCount == 1 ? String(localized: "1 high-volume") : String(localized: "\(highVolumeCount) high-volume"),
                            tone: .warning
                        )
                    }
                    if unlabeledCount > 0 {
                        PresentationToneBadge(
                            text: unlabeledCount == 1 ? String(localized: "1 unlabeled") : String(localized: "\(unlabeledCount) unlabeled"),
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Queue coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep visible session breadth and duplicate-agent churn readable before drilling into the queue."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == totalCount
                        ? (visibleCount == 1 ? String(localized: "1 visible session") : String(localized: "\(visibleCount) visible sessions"))
                        : String(localized: "\(visibleCount) of \(totalCount) visible"),
                    tone: .positive
                )
            } facts: {
                if duplicateAgentCount > 0 {
                    Label(
                        duplicateAgentCount == 1 ? String(localized: "1 multi-session agent") : String(localized: "\(duplicateAgentCount) multi-session agents"),
                        systemImage: "person.3"
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

    @ViewBuilder
    private func sessionRow(for item: SessionAttentionItem) -> some View {
        let row = SessionMonitorRow(
            item: item,
            isBusy: isSessionBusy(item.session)
        )

        if let agent = item.agent {
            NavigationLink {
                AgentDetailView(agent: agent)
            } label: {
                row
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(String(localized: "Switch")) {
                    pendingSessionAction = .switchSession(
                        agentID: agent.id,
                        agentName: agent.name,
                        session: item.session
                    )
                }
                .tint(.blue)

                Button(String(localized: "Delete"), role: .destructive) {
                    pendingDeleteSession = item.session
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button(String(localized: "Label")) {
                    startEditingLabel(for: item.session)
                }
                .tint(.indigo)
            }
            .contextMenu {
                Button {
                    pendingSessionAction = .switchSession(
                        agentID: agent.id,
                        agentName: agent.name,
                        session: item.session
                    )
                } label: {
                    Label("Switch Active Session", systemImage: "arrow.triangle.swap")
                }

                Button {
                    startEditingLabel(for: item.session)
                } label: {
                    Label("Edit Label", systemImage: "tag")
                }

                Button(role: .destructive) {
                    pendingDeleteSession = item.session
                } label: {
                    Label("Delete Session", systemImage: "trash")
                }
            }
        } else {
            row
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !item.session.agentId.isEmpty {
                        Button(String(localized: "Switch")) {
                            pendingSessionAction = .switchSession(
                                agentID: item.session.agentId,
                                agentName: item.session.agentId,
                                session: item.session
                            )
                }
                .tint(.blue)
            }

                    Button(String(localized: "Delete"), role: .destructive) {
                        pendingDeleteSession = item.session
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button(String(localized: "Label")) {
                        startEditingLabel(for: item.session)
                    }
                    .tint(.indigo)
                }
                .contextMenu {
                    if !item.session.agentId.isEmpty {
                        Button {
                            pendingSessionAction = .switchSession(
                                agentID: item.session.agentId,
                                agentName: item.session.agentId,
                                session: item.session
                            )
                        } label: {
                            Label("Switch Active Session", systemImage: "arrow.triangle.swap")
                        }
                    }

                    Button {
                        startEditingLabel(for: item.session)
                    } label: {
                        Label("Edit Label", systemImage: "tag")
                    }

                    Button(role: .destructive) {
                        pendingDeleteSession = item.session
                    } label: {
                        Label("Delete Session", systemImage: "trash")
                    }
                }
        }
    }

    private var sessionActionConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingSessionAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingSessionAction = nil
                }
            }
        )
    }

    private var deleteSessionConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteSession != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteSession = nil
                }
            }
        )
    }

    private var isCatalogActionBusy: Bool {
        sessionCatalogActionInFlightID != nil
    }

    private func isSessionBusy(_ session: SessionInfo) -> Bool {
        sessionActionInFlightID == "switch:\(session.agentId):\(session.id)"
            || sessionCatalogActionInFlightID == "label:\(session.sessionId)"
            || sessionCatalogActionInFlightID == "delete:\(session.sessionId)"
    }

    private func startEditingLabel(for session: SessionInfo) {
        sessionLabelDraft = session.label ?? ""
        editingSession = session
    }

    private func displayTitle(for session: SessionInfo) -> String {
        let label = (session.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? String(session.sessionId.prefix(8)) : label
    }

    @MainActor
    private func performSessionAction(_ action: AgentSessionControlAction) async {
        pendingSessionAction = nil
        sessionActionInFlightID = action.id
        defer { sessionActionInFlightID = nil }

        do {
            let response = try await action.perform(using: deps.apiClient)
            await vm.refresh()
            operatorNotice = action.successNotice(from: response)
        } catch {
            operatorNotice = OperatorActionNotice(
                title: action.title,
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func saveSessionLabel(for session: SessionInfo) async {
        let trimmedLabel = sessionLabelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        sessionCatalogActionInFlightID = "label:\(session.sessionId)"
        defer { sessionCatalogActionInFlightID = nil }

        do {
            let response = try await deps.apiClient.setSessionLabel(
                id: session.sessionId,
                label: trimmedLabel.isEmpty ? nil : trimmedLabel
            )
            editingSession = nil
            sessionLabelDraft = ""
            await vm.refresh()
            operatorNotice = OperatorActionNotice(
                title: String(localized: "Session Label"),
                message: response.message ?? (trimmedLabel.isEmpty ? String(localized: "Session label cleared.") : String(localized: "Session label updated."))
            )
        } catch {
            operatorNotice = OperatorActionNotice(
                title: String(localized: "Session Label"),
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func deleteSession(_ session: SessionInfo) async {
        pendingDeleteSession = nil
        sessionCatalogActionInFlightID = "delete:\(session.sessionId)"
        defer { sessionCatalogActionInFlightID = nil }

        do {
            let response = try await deps.apiClient.deleteSession(id: session.sessionId)
            await vm.refresh()
            operatorNotice = OperatorActionNotice(
                title: String(localized: "Delete Session"),
                message: response.message ?? String(localized: "Session deleted.")
            )
        } catch {
            operatorNotice = OperatorActionNotice(
                title: String(localized: "Delete Session"),
                message: error.localizedDescription
            )
        }
    }
}

enum SessionFilter: CaseIterable {
    case all
    case attention
    case highVolume
    case unlabeled

    var label: String {
        switch self {
        case .all:
            String(localized: "All")
        case .attention:
            String(localized: "Attention")
        case .highVolume:
            String(localized: "High Volume")
        case .unlabeled:
            String(localized: "Unlabeled")
        }
    }

    var icon: String {
        switch self {
        case .all:
            "list.bullet"
        case .attention:
            "exclamationmark.triangle"
        case .highVolume:
            "bubble.left.and.bubble.right"
        case .unlabeled:
            "tag.slash"
        }
    }
}

private struct SessionScoreboard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let vm: DashboardViewModel

    private var attentionStatus: MonitoringSummaryStatus {
        .countStatus(vm.sessionAttentionCount, activeTone: .warning)
    }

    private var highVolumeStatus: MonitoringSummaryStatus {
        .countStatus(vm.highVolumeSessionCount, activeTone: .warning)
    }

    private var unlabeledStatus: MonitoringSummaryStatus {
        .countStatus(vm.unlabeledSessionCount, activeTone: .caution)
    }

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 4
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            StatBadge(
                value: "\(vm.totalSessionCount)",
                label: "Sessions",
                icon: "rectangle.stack",
                color: .blue
            )
            StatBadge(
                value: "\(vm.sessionAttentionCount)",
                label: "Attention",
                icon: "exclamationmark.triangle",
                color: attentionStatus.tone.color
            )
            StatBadge(
                value: "\(vm.highVolumeSessionCount)",
                label: "High Volume",
                icon: "bubble.left.and.bubble.right",
                color: highVolumeStatus.tone.color
            )
            StatBadge(
                value: "\(vm.unlabeledSessionCount)",
                label: "Unlabeled",
                icon: "tag.slash",
                color: unlabeledStatus.tone.color
            )
        }
        .padding(.horizontal)
    }
}

private struct SessionFilterCard: View {
    @Binding var filter: SessionFilter
    let searchText: String
    let visibleCount: Int
    let totalCount: Int

    var body: some View {
        MonitoringFilterCard(summary: summaryLine, detail: searchSummary) {
            activeBadge
        } controls: {
            FlowLayout(spacing: 8) {
                ForEach(SessionFilter.allCases, id: \.self) { option in
                    Button {
                        filter = option
                    } label: {
                        SessionFilterChip(
                            label: option.label,
                            systemImage: option.icon,
                            isSelected: filter == option
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var activeBadge: some View {
        PresentationToneBadge(
            text: filter.label,
            tone: badgeTone
        )
    }

    private var summaryLine: String {
        if visibleCount == totalCount {
            return totalCount == 1
                ? String(localized: "1 session in monitor")
                : String(localized: "\(totalCount) sessions in monitor")
        }

        return String(localized: "\(visibleCount) of \(totalCount) sessions visible")
    }

    private var searchSummary: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return String(localized: "Search by session label, agent, or attention reason.")
        }
        return String(localized: "Search active: \"\(query)\"")
    }

    private var badgeTone: PresentationTone {
        switch filter {
        case .all:
            return .neutral
        case .attention:
            return .warning
        case .highVolume:
            return .caution
        case .unlabeled:
            return .critical
        }
    }
}

private struct SessionFilterChip: View {
    let label: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        SelectableLabelCapsuleBadge(
            text: label,
            systemImage: systemImage,
            isSelected: isSelected
        )
    }
}

private struct SessionListInventoryDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let attentionCount: Int
    let highVolumeCount: Int
    let unlabeledCount: Int
    let duplicateAgentCount: Int
    let searchText: String
    let filter: SessionFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(summary: summaryLine, detail: detailLine) {
                FlowLayout(spacing: 6) {
                    PresentationToneBadge(
                        text: visibleCount == 1 ? String(localized: "1 visible") : String(localized: "\(visibleCount) visible"),
                        tone: visibleCount > 0 ? .positive : .neutral
                    )
                    PresentationToneBadge(
                        text: attentionCount == 1 ? String(localized: "1 attention") : String(localized: "\(attentionCount) attention"),
                        tone: attentionCount > 0 ? .warning : .neutral
                    )
                    if highVolumeCount > 0 {
                        PresentationToneBadge(
                            text: highVolumeCount == 1 ? String(localized: "1 high-volume") : String(localized: "\(highVolumeCount) high-volume"),
                            tone: .warning
                        )
                    }
                    if unlabeledCount > 0 {
                        PresentationToneBadge(
                            text: unlabeledCount == 1 ? String(localized: "1 unlabeled") : String(localized: "\(unlabeledCount) unlabeled"),
                            tone: .caution
                        )
                    }
                    PresentationToneBadge(text: filter.label, tone: filterTone)
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Session inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Use the compact queue slice to judge volume, labeling debt, and duplicate-agent spread before opening the rows."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: filter.label,
                    tone: filterTone
                )
            } facts: {
                Label(
                    visibleCount == 1 ? String(localized: "1 visible session") : String(localized: "\(visibleCount) visible sessions"),
                    systemImage: "text.bubble"
                )
                Label(
                    attentionCount == 1 ? String(localized: "1 hotspot") : String(localized: "\(attentionCount) hotspots"),
                    systemImage: "exclamationmark.triangle"
                )
                if highVolumeCount > 0 {
                    Label(
                        highVolumeCount == 1 ? String(localized: "1 high-volume session") : String(localized: "\(highVolumeCount) high-volume sessions"),
                        systemImage: "chart.bar.xaxis"
                    )
                }
                if unlabeledCount > 0 {
                    Label(
                        unlabeledCount == 1 ? String(localized: "1 unlabeled session") : String(localized: "\(unlabeledCount) unlabeled sessions"),
                        systemImage: "tag.slash"
                    )
                }
                if duplicateAgentCount > 0 {
                    Label(
                        duplicateAgentCount == 1 ? String(localized: "1 duplicate agent") : String(localized: "\(duplicateAgentCount) duplicate agents"),
                        systemImage: "person.2"
                    )
                }
            }
        }
    }

    private var summaryLine: String {
        if visibleCount == totalCount {
            return totalCount == 1
                ? String(localized: "1 session is ready in this monitor.")
                : String(localized: "\(totalCount) sessions are ready in this monitor.")
        }

        return String(localized: "\(visibleCount) of \(totalCount) sessions are visible in this monitor.")
    }

    private var detailLine: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return String(localized: "Attention pressure stays summarized before the session list.")
        }
        return String(localized: "Filtered by \"\(query)\" before the session list.")
    }

    private var filterTone: PresentationTone {
        switch filter {
        case .all:
            return .neutral
        case .attention:
            return .warning
        case .highVolume:
            return .caution
        case .unlabeled:
            return .critical
        }
    }
}

private struct SessionMonitorRow: View {
    let item: SessionAttentionItem
    var isBusy = false

    var body: some View {
        MonitoringFactsRow(
            horizontalAlignment: .top,
            verticalSpacing: 8,
            headerVerticalSpacing: 6,
            factsSpacing: 8
        ) {
            summaryBlock
        } accessory: {
            trailingBlock
        } facts: {
            sessionFacts
        }
        .padding(.vertical, 2)
    }

    private var displayTitle: String {
        let label = (item.session.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? String(item.session.sessionId.prefix(8)) : label
    }

    private var relativeCreatedAt: String {
        guard let date = item.session.createdAt.sessionISO8601Date else { return item.session.createdAt }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displayTitle)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text(item.agent?.name ?? item.session.agentId)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var trailingBlock: some View {
        ResponsiveInlineGroup(horizontalSpacing: 8, verticalSpacing: 4) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            Text(relativeCreatedAt)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var sessionFacts: some View {
        Label("\(item.session.messageCount)", systemImage: "bubble.left.and.bubble.right")
            .font(.caption)
            .foregroundStyle(item.messageCountTone.color)

        if !item.reasons.isEmpty {
            ForEach(item.reasons.prefix(1), id: \.self) { reason in
                PresentationToneBadge(
                    text: reason,
                    tone: item.tone,
                    horizontalPadding: 6,
                    verticalPadding: 2
                )
            }
        }
    }
}

private extension String {
    var sessionISO8601Date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: self) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: self)
    }
}

import SwiftUI

struct EventsView: View {
    @Environment(\.dependencies) private var deps
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: EventsViewModel
    @State private var searchText: String
    @State private var scope: AuditSeverityScope

    init(api: APIClientProtocol, initialSearchText: String = "", initialScope: AuditSeverityScope = .all) {
        _viewModel = State(initialValue: EventsViewModel(api: api))
        _searchText = State(initialValue: initialSearchText)
        _scope = State(initialValue: initialScope)
    }

    private var filteredEntries: [AuditEntry] {
        viewModel.entries.filter { entry in
            scope.contains(entry.severity)
                && entry.matchesSearch(searchText, agentName: agentName(for: entry.agentId))
        }
    }
    private var scopeTone: PresentationTone {
        switch scope {
        case .all:
            return .neutral
        case .critical:
            return .critical
        case .warning:
            return .warning
        case .info:
            return .positive
        }
    }
    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var eventSectionCount: Int { 1 }
    private var eventsPrimaryRouteCount: Int { 3 }
    private var eventsSupportRouteCount: Int { 2 }

    var body: some View {
        List {
            eventsErrorSection
            eventsScoreboardSection
            eventsControlsSection
            eventsFeedSection
        }
        .navigationTitle("Events")
        .searchable(text: $searchText, prompt: "Search action, detail, or agent")
        .refreshable {
            await viewModel.refresh()
        }
        .overlay {
            if viewModel.isLoading && viewModel.entries.isEmpty {
                ProgressView("Loading events...")
            }
        }
        .onAppear {
            viewModel.startAutoRefresh()
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                viewModel.startAutoRefresh()
                Task { await viewModel.refresh() }
            case .background:
                viewModel.stopAutoRefresh()
            default:
                break
            }
        }
    }

    private func agentName(for id: String) -> String? {
        deps.dashboardViewModel.agents.first(where: { $0.id == id })?.name
    }

    @ViewBuilder
    private var eventsErrorSection: some View {
        if let error = viewModel.error, viewModel.entries.isEmpty {
            Section {
                ErrorBanner(message: error, onRetry: {
                    await viewModel.refresh()
                }, onDismiss: {
                    viewModel.error = nil
                })
                .listRowInsets(.init())
                .listRowBackground(Color.clear)
            }
        }
    }

    private var eventsScoreboardSection: some View {
        Section {
            EventScoreboard(viewModel: viewModel)
                .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
        }
    }

    private var eventsControlsSection: some View {
        Section {
            eventsStatusDeckCard
            eventsSectionInventoryDeck
            eventsPressureCoverageDeck
            eventsSupportCoverageDeck
            eventsFeedCoverageDeck
            eventsControlDeckCard
        } header: {
            Text("Controls")
        } footer: {
            Text("Event pressure, routes, and filters stay together before the feed.")
        }
    }

    @ViewBuilder
    private var eventsFeedSection: some View {
        if filteredEntries.isEmpty && !viewModel.isLoading {
            Section("Feed") {
                ContentUnavailableView(
                    trimmedSearchText.isEmpty ? String(localized: "No Matching Events") : String(localized: "No Search Results"),
                    systemImage: scope == .all ? "list.bullet.rectangle" : "line.3.horizontal.decrease.circle",
                    description: Text(trimmedSearchText.isEmpty ? String(localized: "Pull to refresh or widen the severity filter.") : String(localized: "Try a different agent, action, or detail query."))
                )
            }
        } else {
            Section {
                EventFeedInventoryDeck(
                    visibleCount: filteredEntries.count,
                    totalCount: viewModel.entries.count,
                    criticalCount: filteredEntries.filter { $0.severity == .critical }.count,
                    isStreaming: viewModel.isStreaming,
                    searchText: searchText
                )
                .listRowInsets(.init(top: 10, leading: 0, bottom: 8, trailing: 0))

                ForEach(filteredEntries) { entry in
                    EventRow(entry: entry, agentName: agentName(for: entry.agentId))
                }
            } header: {
                Text("Feed")
            } footer: {
                eventsFeedFooter
            }
        }
    }

    @ViewBuilder
    private var eventsFeedFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(filteredEntries.count) of \(viewModel.entries.count) events visible")
            if let tipHash = viewModel.tipHash, !tipHash.isEmpty {
                Text("Tip \(String(tipHash.prefix(16)))...")
            }
        }
    }

    private var eventsStatusDeckCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: filteredEntries.isEmpty
                    ? String(localized: "Event feed is ready for a fresh mobile review.")
                    : (filteredEntries.count == 1
                        ? String(localized: "1 event is visible in the current event feed.")
                        : String(localized: "\(filteredEntries.count) events are visible in the current event feed.")),
                detail: String(localized: "Critical audit pressure and transport state stay visible before the feed.")
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: scope.label, tone: scopeTone)
                    PresentationToneBadge(
                        text: viewModel.isStreaming ? String(localized: "Live") : String(localized: "Polling"),
                        tone: viewModel.isStreaming ? .positive : .warning
                    )
                    if viewModel.criticalCount > 0 {
                        PresentationToneBadge(
                            text: viewModel.criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(viewModel.criticalCount) critical"),
                            tone: .critical
                        )
                    }
                    if viewModel.warningCount > 0 {
                        PresentationToneBadge(
                            text: viewModel.warningCount == 1 ? String(localized: "1 warning") : String(localized: "\(viewModel.warningCount) warnings"),
                            tone: .warning
                        )
                    }
                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        PresentationToneBadge(
                            text: filteredEntries.count == 1 ? String(localized: "1 visible result") : String(localized: "\(filteredEntries.count) visible results"),
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Event feed facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep severity scope, transport mode, and audit pressure readable before opening the full feed."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: scope.label, tone: scopeTone)
            } facts: {
                Label(
                    filteredEntries.count == 1 ? String(localized: "1 visible event") : String(localized: "\(filteredEntries.count) visible events"),
                    systemImage: "list.bullet.rectangle"
                )
                Label(
                    viewModel.isStreaming ? String(localized: "Live transport") : String(localized: "Polling transport"),
                    systemImage: "dot.radiowaves.left.and.right"
                )
                if viewModel.criticalCount > 0 {
                    Label(
                        viewModel.criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(viewModel.criticalCount) critical"),
                        systemImage: "xmark.octagon"
                    )
                }
                if viewModel.warningCount > 0 {
                    Label(
                        viewModel.warningCount == 1 ? String(localized: "1 warning") : String(localized: "\(viewModel.warningCount) warnings"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(String(localized: "Scoped search"), systemImage: "magnifyingglass")
                }
            }
        }
    }

    private var eventsControlDeckCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            EventsRouteInventoryDeck(
                primaryRouteCount: eventsPrimaryRouteCount,
                supportRouteCount: eventsSupportRouteCount,
                visibleCount: filteredEntries.count,
                totalCount: viewModel.entries.count,
                criticalCount: viewModel.criticalCount,
                warningCount: viewModel.warningCount,
                hasSearchScope: !trimmedSearchText.isEmpty,
                scopeLabel: scope.label,
                scopeTone: scopeTone
            )

            MonitoringSurfaceGroupCard(
                title: String(localized: "Routes"),
                detail: String(localized: "Jump straight to incidents, runtime, sessions, diagnostics, or comms without another long route stack.")
            ) {
                MonitoringShortcutRail(
                    title: String(localized: "Primary"),
                    detail: String(localized: "Keep the next queue and runtime exits closest to the event feed.")
                ) {
                    NavigationLink {
                        IncidentsView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Incidents"),
                            systemImage: "bell.badge",
                            tone: viewModel.criticalCount > 0 ? .critical : .neutral,
                            badgeText: viewModel.criticalCount > 0
                                ? (viewModel.criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(viewModel.criticalCount) critical"))
                                : nil
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        RuntimeView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Runtime"),
                            systemImage: "server.rack",
                            tone: viewModel.warningCount > 0 ? .warning : .neutral,
                            badgeText: viewModel.warningCount > 0
                                ? (viewModel.warningCount == 1 ? String(localized: "1 warning") : String(localized: "\(viewModel.warningCount) warnings"))
                                : nil
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SessionsView(initialFilter: .attention)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Sessions"),
                            systemImage: "text.bubble",
                            tone: .warning
                        )
                    }
                    .buttonStyle(.plain)
                }

                MonitoringShortcutRail(
                    title: String(localized: "Support"),
                    detail: String(localized: "Keep deeper diagnostics and comms context behind the primary event routes.")
                ) {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Diagnostics"),
                            systemImage: "stethoscope"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        CommsView(api: deps.apiClient)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Comms"),
                            systemImage: "point.3.connected.trianglepath.dotted"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            EventFilterCard(
                scope: $scope,
                searchText: searchText,
                visibleCount: filteredEntries.count,
                totalCount: viewModel.entries.count,
                isStreaming: viewModel.isStreaming
            )
        }
    }

    private var eventsSectionInventoryDeck: some View {
        EventsSectionInventoryDeck(
            sectionCount: eventSectionCount,
            visibleCount: filteredEntries.count,
            totalCount: viewModel.entries.count,
            criticalCount: filteredEntries.filter { $0.severity == .critical }.count,
            warningCount: filteredEntries.filter { $0.severity == .warning }.count,
            infoCount: filteredEntries.filter { $0.severity == .info }.count,
            isStreaming: viewModel.isStreaming,
            hasSearchScope: !trimmedSearchText.isEmpty
        )
    }

    private var eventsPressureCoverageDeck: some View {
        EventsPressureCoverageDeck(
            visibleCount: filteredEntries.count,
            totalCount: viewModel.entries.count,
            criticalCount: filteredEntries.filter { $0.severity == .critical }.count,
            warningCount: filteredEntries.filter { $0.severity == .warning }.count,
            infoCount: filteredEntries.filter { $0.severity == .info }.count,
            isStreaming: viewModel.isStreaming,
            hasSearchScope: !trimmedSearchText.isEmpty,
            scopeLabel: scope.label,
            scopeTone: scopeTone,
            showsScopeBadge: scope != .all
        )
    }

    private var eventsFeedCoverageDeck: some View {
        EventsFeedCoverageDeck(
            visibleCount: filteredEntries.count,
            totalCount: viewModel.entries.count,
            criticalCount: filteredEntries.filter { $0.severity == .critical }.count,
            warningCount: filteredEntries.filter { $0.severity == .warning }.count,
            infoCount: filteredEntries.filter { $0.severity == .info }.count,
            isStreaming: viewModel.isStreaming,
            hasSearchScope: !trimmedSearchText.isEmpty
        )
    }

    private var eventsSupportCoverageDeck: some View {
        EventsSupportCoverageDeck(
            visibleCount: filteredEntries.count,
            totalCount: viewModel.entries.count,
            infoCount: filteredEntries.filter { $0.severity == .info }.count,
            isStreaming: viewModel.isStreaming,
            hasSearchScope: !trimmedSearchText.isEmpty,
            scopeLabel: scope.label,
            scopeTone: scopeTone,
            showsScopeBadge: scope != .all
        )
    }
}

private struct EventsSectionInventoryDeck: View {
    let sectionCount: Int
    let visibleCount: Int
    let totalCount: Int
    let criticalCount: Int
    let warningCount: Int
    let infoCount: Int
    let isStreaming: Bool
    let hasSearchScope: Bool

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
                    PresentationToneBadge(
                        text: visibleCount == 1 ? String(localized: "1 visible event") : String(localized: "\(visibleCount) visible events"),
                        tone: visibleCount > 0 ? .positive : .neutral
                    )
                    if criticalCount > 0 {
                        PresentationToneBadge(
                            text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                            tone: .critical
                        )
                    }
                    if warningCount > 0 {
                        PresentationToneBadge(
                            text: warningCount == 1 ? String(localized: "1 warning") : String(localized: "\(warningCount) warnings"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Section inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep event severity, result volume, and transport state visible before the feed rows take over."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: isStreaming ? String(localized: "Live") : String(localized: "Polling"),
                    tone: isStreaming ? .positive : .warning
                )
            } facts: {
                Label(
                    totalCount == 1 ? String(localized: "1 total event") : String(localized: "\(totalCount) total events"),
                    systemImage: "list.bullet.rectangle"
                )
                if infoCount > 0 {
                    Label(
                        infoCount == 1 ? String(localized: "1 info") : String(localized: "\(infoCount) info"),
                        systemImage: "info.circle"
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
            ? String(localized: "1 event section is active below the controls deck.")
            : String(localized: "\(sectionCount) event sections are active below the controls deck.")
    }

    private var detailLine: String {
        String(localized: "Severity mix, result volume, and transport mode stay summarized before the event feed takes over the page.")
    }
}

private struct EventsPressureCoverageDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let criticalCount: Int
    let warningCount: Int
    let infoCount: Int
    let isStreaming: Bool
    let hasSearchScope: Bool
    let scopeLabel: String
    let scopeTone: PresentationTone
    let showsScopeBadge: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this pressure slice to separate critical audit drag from scoped warnings and lower-noise feed traffic before the event rows begin."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if criticalCount > 0 {
                        PresentationToneBadge(
                            text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                            tone: .critical
                        )
                    }
                    if warningCount > 0 {
                        PresentationToneBadge(
                            text: warningCount == 1 ? String(localized: "1 warning") : String(localized: "\(warningCount) warnings"),
                            tone: .warning
                        )
                    }
                    if showsScopeBadge {
                        PresentationToneBadge(text: scopeLabel, tone: scopeTone)
                    }
                    if hasSearchScope {
                        PresentationToneBadge(text: String(localized: "Search scoped"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Pressure coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep severity pressure, transport mode, and visible slice breadth readable before drilling into the audit feed."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == totalCount
                        ? (visibleCount == 1 ? String(localized: "1 visible event") : String(localized: "\(visibleCount) visible events"))
                        : String(localized: "\(visibleCount) of \(totalCount) visible"),
                    tone: criticalCount > 0 ? .critical : (warningCount > 0 ? .warning : .positive)
                )
            } facts: {
                Label(
                    isStreaming ? String(localized: "Live transport") : String(localized: "Polling transport"),
                    systemImage: "dot.radiowaves.left.and.right"
                )
                if infoCount > 0 {
                    Label(
                        infoCount == 1 ? String(localized: "1 info") : String(localized: "\(infoCount) info"),
                        systemImage: "info.circle"
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
        if criticalCount > 0 {
            return criticalCount == 1
                ? String(localized: "Event pressure is currently anchored by 1 critical audit event.")
                : String(localized: "Event pressure is currently anchored by \(criticalCount) critical audit events.")
        }
        if warningCount > 0 && warningCount >= max(infoCount, 1) {
            return warningCount == 1
                ? String(localized: "Event pressure is currently concentrated in 1 warning event.")
                : String(localized: "Event pressure is currently concentrated in \(warningCount) warning events.")
        }
        if hasSearchScope || showsScopeBadge {
            return String(localized: "Event pressure is currently narrowed by the active severity or search scope.")
        }
        return String(localized: "Event pressure is currently spread across lower-noise feed traffic and background audit flow.")
    }
}

private struct EventsSupportCoverageDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let infoCount: Int
    let isStreaming: Bool
    let hasSearchScope: Bool
    let scopeLabel: String
    let scopeTone: PresentationTone
    let showsScopeBadge: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep transport mode, lower-noise feed traffic, and scope state readable before the event feed rows begin."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: isStreaming ? String(localized: "Live transport") : String(localized: "Polling transport"),
                        tone: isStreaming ? .positive : .warning
                    )
                    if showsScopeBadge {
                        PresentationToneBadge(text: scopeLabel, tone: scopeTone)
                    }
                    if hasSearchScope {
                        PresentationToneBadge(text: String(localized: "Search scoped"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Support coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep transport mode, info traffic, and scope state readable before the event feed expands into row-by-row audit detail."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == totalCount
                        ? (visibleCount == 1 ? String(localized: "1 visible event") : String(localized: "\(visibleCount) visible events"))
                        : String(localized: "\(visibleCount) of \(totalCount) visible"),
                    tone: visibleCount > 0 ? .positive : .neutral
                )
            } facts: {
                if infoCount > 0 {
                    Label(
                        infoCount == 1 ? String(localized: "1 info") : String(localized: "\(infoCount) info"),
                        systemImage: "info.circle"
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
        if hasSearchScope || showsScopeBadge {
            return String(localized: "Event support coverage is currently narrowed by the active severity or search scope.")
        }
        if !isStreaming {
            return String(localized: "Event support coverage is currently leaning on polling transport.")
        }
        if infoCount > 0 {
            return String(localized: "Event support coverage is currently light and mostly reflects lower-noise feed traffic.")
        }
        return String(localized: "Event support coverage is currently light and mostly reflects transport readiness.")
    }
}

private struct EventsFeedCoverageDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let criticalCount: Int
    let warningCount: Int
    let infoCount: Int
    let isStreaming: Bool
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Feed coverage keeps the active severity mix readable before the event rows begin."),
                detail: String(localized: "Use this deck to judge whether the current event slice is dominated by criticals, warnings, or lower-noise feed traffic."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if criticalCount > 0 {
                        PresentationToneBadge(
                            text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                            tone: .critical
                        )
                    }
                    if warningCount > 0 {
                        PresentationToneBadge(
                            text: warningCount == 1 ? String(localized: "1 warning") : String(localized: "\(warningCount) warnings"),
                            tone: .warning
                        )
                    }
                    if infoCount > 0 {
                        PresentationToneBadge(
                            text: infoCount == 1 ? String(localized: "1 info") : String(localized: "\(infoCount) info"),
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Feed coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep transport mode and visible feed breadth readable before diving into individual audit rows."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: isStreaming ? String(localized: "Live") : String(localized: "Polling"),
                    tone: isStreaming ? .positive : .warning
                )
            } facts: {
                Label(
                    visibleCount == totalCount
                        ? (visibleCount == 1 ? String(localized: "1 visible event") : String(localized: "\(visibleCount) visible events"))
                        : String(localized: "\(visibleCount) of \(totalCount) visible"),
                    systemImage: "list.bullet.rectangle"
                )
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct EventsRouteInventoryDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let visibleCount: Int
    let totalCount: Int
    let criticalCount: Int
    let warningCount: Int
    let hasSearchScope: Bool
    let scopeLabel: String
    let scopeTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: hasSearchScope
                    ? String(localized: "Event routes stay compact while the feed is search-scoped.")
                    : String(localized: "Event routes stay compact before the surrounding incident and runtime drilldowns."),
                detail: String(localized: "Use the route inventory to gauge the active event slice before leaving the feed."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: scopeLabel, tone: scopeTone)
                    PresentationToneBadge(
                        text: primaryRouteCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryRouteCount) primary routes"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: supportRouteCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportRouteCount) support routes"),
                        tone: .neutral
                    )
                    if criticalCount > 0 {
                        PresentationToneBadge(
                            text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                            tone: .critical
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Route Facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep feed scope and event pressure visible before pivoting into incidents, runtime, sessions, diagnostics, or comms."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == totalCount
                        ? (visibleCount == 1 ? String(localized: "1 visible event") : String(localized: "\(visibleCount) visible events"))
                        : String(localized: "\(visibleCount) of \(totalCount) visible"),
                    tone: .positive
                )
            } facts: {
                if warningCount > 0 {
                    Label(
                        warningCount == 1 ? String(localized: "1 warning") : String(localized: "\(warningCount) warnings"),
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

private struct EventFilterCard: View {
    @Binding var scope: AuditSeverityScope
    let searchText: String
    let visibleCount: Int
    let totalCount: Int
    let isStreaming: Bool

    var body: some View {
        MonitoringFilterCard(summary: summaryLine, detail: searchSummary) {
            statusBadges
        } controls: {
            FlowLayout(spacing: 8) {
                ForEach(AuditSeverityScope.allCases) { option in
                    Button {
                        scope = option
                    } label: {
                        EventFilterChip(
                            label: option.label,
                            isSelected: scope == option
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var statusBadges: some View {
        FlowLayout(spacing: 6) {
            PresentationToneBadge(text: scope.label, tone: scopeTone)
            PresentationToneBadge(
                text: isStreaming ? String(localized: "Live") : String(localized: "Polling"),
                tone: isStreaming ? .positive : .warning
            )
        }
    }

    private var summaryLine: String {
        if visibleCount == totalCount {
            return totalCount == 1
                ? String(localized: "1 event in feed")
                : String(localized: "\(totalCount) events in feed")
        }

        return String(localized: "\(visibleCount) of \(totalCount) events visible")
    }

    private var searchSummary: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return String(localized: "Search by action, detail, or agent to narrow the event stream.")
        }
        return String(localized: "Search active: \"\(query)\"")
    }

    private var scopeTone: PresentationTone {
        switch scope {
        case .all:
            return .neutral
        case .critical:
            return .critical
        case .warning:
            return .warning
        case .info:
            return .positive
        }
    }
}

private struct EventFeedInventoryDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let criticalCount: Int
    let isStreaming: Bool
    let searchText: String

    var body: some View {
        MonitoringSnapshotCard(summary: summaryLine, detail: detailLine) {
            FlowLayout(spacing: 6) {
                PresentationToneBadge(
                    text: visibleCount == 1 ? String(localized: "1 visible") : String(localized: "\(visibleCount) visible"),
                    tone: visibleCount > 0 ? .positive : .neutral
                )
                PresentationToneBadge(
                    text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                    tone: criticalCount > 0 ? .critical : .neutral
                )
                PresentationToneBadge(
                    text: isStreaming ? String(localized: "Live") : String(localized: "Polling"),
                    tone: isStreaming ? .positive : .warning
                )
            }
        }
    }

    private var summaryLine: String {
        if visibleCount == totalCount {
            return totalCount == 1
                ? String(localized: "1 event is ready in the feed.")
                : String(localized: "\(totalCount) events are ready in the feed.")
        }

        return String(localized: "\(visibleCount) of \(totalCount) events are visible in this feed.")
    }

    private var detailLine: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return String(localized: "Critical entries stay summarized before the event list.")
        }
        return String(localized: "Filtered by \"\(query)\" before the event list.")
    }
}

private struct EventFilterChip: View {
    let label: String
    let isSelected: Bool

    var body: some View {
        SelectableCapsuleBadge(text: label, isSelected: isSelected)
    }
}

private struct EventScoreboard: View {
    let viewModel: EventsViewModel

    private var criticalStatus: MonitoringSummaryStatus {
        .countStatus(viewModel.criticalCount, activeTone: .critical)
    }

    private var warningStatus: MonitoringSummaryStatus {
        .countStatus(viewModel.warningCount, activeTone: .warning)
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 380
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: isCompact ? 2 : 3),
                spacing: 10
            ) {
                StatBadge(
                    value: "\(viewModel.criticalCount)",
                    label: "Critical",
                    icon: "xmark.octagon",
                    color: criticalStatus.tone.color
                )
                StatBadge(
                    value: "\(viewModel.warningCount)",
                    label: "Warnings",
                    icon: "exclamationmark.triangle",
                    color: warningStatus.tone.color
                )
                StatBadge(
                    value: "\(viewModel.infoCount)",
                    label: "Info",
                    icon: "info.circle",
                    color: .blue
                )
                StatBadge(
                    value: chainLabel,
                    label: "Audit Chain",
                    icon: "checkmark.shield",
                    color: chainColor
                )
                StatBadge(
                    value: viewModel.isStreaming ? String(localized: "Live") : String(localized: "Polling"),
                    label: "Transport",
                    icon: viewModel.isStreaming ? "dot.radiowaves.left.and.right" : "arrow.clockwise",
                    color: viewModel.isStreaming ? .green : .orange
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
        .frame(minHeight: 136)
    }

    private var chainLabel: String {
        guard let verify = viewModel.auditVerify else { return "--" }
        return verify.valid ? String(localized: "Valid") : String(localized: "Broken")
    }

    private var chainColor: Color {
        guard let verify = viewModel.auditVerify else { return .secondary }
        return verify.valid ? .green : .red
    }
}

private struct EventRow: View {
    let entry: AuditEntry
    let agentName: String?

    var body: some View {
        ResponsiveIconDetailRow(horizontalAlignment: .top, horizontalSpacing: 10, verticalSpacing: 8, spacerMinLength: 0) {
            Image(systemName: entry.severity.symbolName)
                .foregroundStyle(entry.severity.tone.color)
                .frame(width: 18)
        } detail: {
            VStack(alignment: .leading, spacing: 4) {
                ResponsiveAccessoryRow(
                    horizontalAlignment: .firstTextBaseline,
                    verticalSpacing: 2
                ) {
                    titleLabel
                } accessory: {
                    timestampLabel
                }

                ResponsiveAccessoryRow(
                    horizontalAlignment: .firstTextBaseline,
                    horizontalSpacing: 8,
                    spacerMinLength: 0
                ) {
                    agentLabel
                } accessory: {
                    outcomeBadge
                }

                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var shortAgentId: String {
        entry.agentId.isEmpty ? "-" : String(entry.agentId.prefix(8))
    }

    private var titleLabel: some View {
        Text(entry.friendlyAction)
            .font(.subheadline.weight(.medium))
            .lineLimit(2)
    }

    private var timestampLabel: some View {
        Text(relativeTimestamp)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }

    private var agentLabel: some View {
        Text(agentName ?? shortAgentId)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var outcomeBadge: some View {
        PresentationToneBadge(
            text: entry.localizedOutcomeLabel,
            tone: entry.severity.tone,
            horizontalPadding: 6,
            verticalPadding: 2
        )
    }

    private var relativeTimestamp: String {
        guard let date = entry.timestamp.eventsISO8601Date else { return entry.timestamp }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

private extension String {
    var eventsISO8601Date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: self) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: self)
    }
}

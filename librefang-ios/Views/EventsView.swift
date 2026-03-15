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

    var body: some View {
        List {
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

            Section {
                EventScoreboard(viewModel: viewModel)
                    .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
            }

            Section {
                MonitoringSnapshotCard(
                    summary: filteredEntries.isEmpty
                        ? String(localized: "Event feed is ready for a fresh mobile review.")
                        : (filteredEntries.count == 1
                            ? String(localized: "1 event is visible in the current event feed.")
                            : String(localized: "\(filteredEntries.count) events are visible in the current event feed.")),
                    detail: String(localized: "Critical audit pressure and transport state stay visible before the longer event list.")
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
            } footer: {
                Text("Use the snapshot to judge event pressure and transport state before scanning the full feed.")
            }

            Section {
                MonitoringFactsRow {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "Event feed facts"))
                            .font(.subheadline.weight(.medium))
                        Text(String(localized: "Keep severity scope, transport mode, and visible audit pressure readable before opening the full event list."))
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
            } footer: {
                Text("This compact facts row keeps severity and transport state visible before you scan the event feed.")
            }

            Section {
                MonitoringSurfaceGroupCard(
                    title: String(localized: "Primary Surfaces"),
                    detail: String(localized: "Keep the incident, runtime, and session exits closest to the live event feed.")
                ) {
                    NavigationLink {
                        IncidentsView()
                    } label: {
                        MonitoringJumpRow(
                            title: String(localized: "Open Incidents"),
                            detail: String(localized: "Switch to incident queue when critical events should be triaged beside alerts and approvals."),
                            systemImage: "bell.badge",
                            tone: viewModel.criticalCount > 0 ? .critical : .neutral,
                            badgeText: viewModel.criticalCount > 0
                                ? (viewModel.criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(viewModel.criticalCount) critical"))
                                : nil,
                            badgeTone: .critical
                        )
                    }

                    NavigationLink {
                        RuntimeView()
                    } label: {
                        MonitoringJumpRow(
                            title: String(localized: "Open Runtime"),
                            detail: String(localized: "Switch to runtime when event pressure needs system, provider, or approval context."),
                            systemImage: "server.rack",
                            tone: viewModel.warningCount > 0 ? .warning : .neutral,
                            badgeText: viewModel.warningCount > 0
                                ? (viewModel.warningCount == 1 ? String(localized: "1 warning") : String(localized: "\(viewModel.warningCount) warnings"))
                                : nil,
                            badgeTone: .warning
                        )
                    }

                    NavigationLink {
                        SessionsView(initialFilter: .attention)
                    } label: {
                        MonitoringJumpRow(
                            title: String(localized: "Open Sessions"),
                            detail: String(localized: "Switch to session hotspots when audit events suggest backlog or session drift."),
                            systemImage: "text.bubble",
                            tone: .warning,
                            badgeText: nil,
                            badgeTone: .warning
                        )
                    }
                }

                MonitoringSurfaceGroupCard(
                    title: String(localized: "Supporting Surfaces"),
                    detail: String(localized: "Keep deeper health and comms context behind the primary event exits.")
                ) {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        MonitoringJumpRow(
                            title: String(localized: "Open Diagnostics"),
                            detail: String(localized: "Switch to diagnostics when audit activity may reflect deeper runtime problems."),
                            systemImage: "stethoscope",
                            tone: .neutral
                        )
                    }

                    NavigationLink {
                        CommsView(api: deps.apiClient)
                    } label: {
                        MonitoringJumpRow(
                            title: String(localized: "Open Comms"),
                            detail: String(localized: "Switch to live inter-agent traffic when audit events need communication context."),
                            systemImage: "point.3.connected.trianglepath.dotted",
                            tone: .neutral
                        )
                    }
                }
            } header: {
                Text("Operator Surfaces")
            } footer: {
                Text("Use these routes when the event feed is only one part of the operator path.")
            }

            Section {
                EventFilterCard(
                    scope: $scope,
                    searchText: searchText,
                    visibleCount: filteredEntries.count,
                    totalCount: viewModel.entries.count,
                    isStreaming: viewModel.isStreaming
                )
            } header: {
                Text("Filter")
            }

            if filteredEntries.isEmpty && !viewModel.isLoading {
                Section("Event Feed") {
                    ContentUnavailableView(
                        searchText.isEmpty ? String(localized: "No Matching Events") : String(localized: "No Search Results"),
                        systemImage: scope == .all ? "list.bullet.rectangle" : "line.3.horizontal.decrease.circle",
                        description: Text(searchText.isEmpty ? String(localized: "Pull to refresh or widen the severity filter.") : String(localized: "Try a different agent, action, or detail query."))
                    )
                }
            } else {
                Section {
                    ForEach(filteredEntries) { entry in
                        EventRow(entry: entry, agentName: agentName(for: entry.agentId))
                    }
                } header: {
                    Text("Event Feed")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(filteredEntries.count) of \(viewModel.entries.count) events visible")
                        if let tipHash = viewModel.tipHash, !tipHash.isEmpty {
                            Text("Tip \(String(tipHash.prefix(16)))...")
                        }
                    }
                }
            }
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

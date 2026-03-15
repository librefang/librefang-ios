import SwiftUI

struct CommsView: View {
    @Environment(\.dependencies) private var deps
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: CommsViewModel
    @State private var searchText = ""

    init(api: APIClientProtocol) {
        _viewModel = State(initialValue: CommsViewModel(api: api))
    }

    private var visibleEdges: [CommsEdge] {
        guard let edges = viewModel.topology?.edges else { return [] }
        return Array(edges.prefix(6))
    }

    private var filteredEvents: [CommsEvent] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.events }

        return viewModel.events.filter { event in
            event.sourceName.localizedCaseInsensitiveContains(query)
                || event.targetName.localizedCaseInsensitiveContains(query)
                || event.sourceID.localizedCaseInsensitiveContains(query)
                || event.targetID.localizedCaseInsensitiveContains(query)
                || event.detail.localizedCaseInsensitiveContains(query)
                || event.kind.label.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            if let error = viewModel.error, viewModel.events.isEmpty {
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
                CommsScoreboard(viewModel: viewModel)
                    .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
            }

            Section {
                commsStatusDeckCard
                commsControlDeckCard
            } header: {
                Text("Controls")
            } footer: {
                Text("Comms pressure, routes, and filters stay together before topology and traffic.")
            }

            Section {
                if let topology = viewModel.topology {
                    CommsTopologyInventoryDeck(
                        topology: topology,
                        visibleEdges: visibleEdges
                    )
                    .listRowInsets(.init(top: 10, leading: 0, bottom: 8, trailing: 0))
                }

                CommsSummaryRow(label: "Agents") {
                    Text("\(viewModel.nodeCount)")
                        .monospacedDigit()
                }
                CommsSummaryRow(label: "Links") {
                    Text("\(viewModel.edgeCount)")
                        .monospacedDigit()
                }
                if let topology = viewModel.topology, !topology.edges.isEmpty {
                    ForEach(visibleEdges) { edge in
                        CommsTopologyEdgeRow(
                            title: edgeTitle(edge, topology: topology),
                            kind: edge.kind
                        )
                    }
                } else {
                    ContentUnavailableView(
                        "No Active Links",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("When agents start messaging, spawning, or coordinating tasks, their topology appears here.")
                    )
                }
            } header: {
                Text("Topology")
            } footer: {
                if let topology = viewModel.topology, topology.edges.count > visibleEdges.count {
                    Text("Showing \(visibleEdges.count) of \(topology.edges.count) active links")
                }
            }

            if filteredEvents.isEmpty && !viewModel.isLoading {
                Section("Traffic") {
                    ContentUnavailableView(
                        searchText.isEmpty ? String(localized: "No Communication Events") : String(localized: "No Search Results"),
                        systemImage: "arrow.left.arrow.right.circle",
                        description: Text(searchText.isEmpty ? String(localized: "Live inter-agent traffic will appear here.") : String(localized: "Try a different agent, task, or detail query."))
                    )
                }
            } else {
                Section {
                    CommsTrafficInventoryDeck(
                        visibleCount: filteredEvents.count,
                        totalCount: viewModel.events.count,
                        activeLinks: visibleEdges.count,
                        isStreaming: viewModel.isStreaming,
                        searchText: searchText
                    )
                    .listRowInsets(.init(top: 10, leading: 0, bottom: 8, trailing: 0))

                    ForEach(filteredEvents) { event in
                        CommsEventRow(event: event)
                    }
                } header: {
                    Text("Traffic")
                } footer: {
                    Text("\(filteredEvents.count) of \(viewModel.events.count) events visible")
                }
            }
        }
        .navigationTitle("Comms")
        .searchable(text: $searchText, prompt: "Search source, target, or detail")
        .refreshable {
            await viewModel.refresh()
        }
        .overlay {
            if viewModel.isLoading && viewModel.events.isEmpty {
                ProgressView("Loading comms...")
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

    private func edgeTitle(_ edge: CommsEdge, topology: CommsTopology) -> String {
        let source = topology.nodes.first(where: { $0.id == edge.from })?.name ?? shortID(edge.from)
        let target = topology.nodes.first(where: { $0.id == edge.to })?.name ?? shortID(edge.to)
        return "\(source) → \(target)"
    }

    private func shortID(_ id: String) -> String {
        guard id.count > 8 else { return id }
        return String(id.prefix(8))
    }

    private var commsStatusDeckCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: filteredEvents.isEmpty
                    ? String(localized: "Comms monitor is ready for live operator traffic.")
                    : (filteredEvents.count == 1
                        ? String(localized: "1 comms event is visible in the current mobile feed.")
                        : String(localized: "\(filteredEvents.count) comms events are visible in the current mobile feed.")),
                detail: String(localized: "Use the snapshot to judge whether comms traffic, links, or event flow deserves the next drilldown.")
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: viewModel.isStreaming ? String(localized: "Live") : String(localized: "Polling"),
                        tone: viewModel.isStreaming ? .positive : .warning
                    )
                    PresentationToneBadge(
                        text: viewModel.nodeCount == 1 ? String(localized: "1 agent") : String(localized: "\(viewModel.nodeCount) agents"),
                        tone: viewModel.nodeCount > 1 ? .positive : .neutral
                    )
                    PresentationToneBadge(
                        text: viewModel.edgeCount == 1 ? String(localized: "1 link") : String(localized: "\(viewModel.edgeCount) links"),
                        tone: viewModel.edgeCount > 0 ? .positive : .neutral
                    )
                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        PresentationToneBadge(
                            text: filteredEvents.count == 1 ? String(localized: "1 visible result") : String(localized: "\(filteredEvents.count) visible results"),
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Comms signal facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep transport mode, topology depth, and event flow visible before opening deeper comms sections."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: viewModel.isStreaming ? String(localized: "Live") : String(localized: "Polling"),
                    tone: viewModel.isStreaming ? .positive : .warning
                )
            } facts: {
                Label(
                    viewModel.nodeCount == 1 ? String(localized: "1 agent") : String(localized: "\(viewModel.nodeCount) agents"),
                    systemImage: "cpu"
                )
                Label(
                    viewModel.edgeCount == 1 ? String(localized: "1 link") : String(localized: "\(viewModel.edgeCount) links"),
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                Label(
                    viewModel.taskEventCount == 1 ? String(localized: "1 task-flow event") : String(localized: "\(viewModel.taskEventCount) task-flow events"),
                    systemImage: "checklist"
                )
                Label(
                    filteredEvents.count == 1 ? String(localized: "1 visible event") : String(localized: "\(filteredEvents.count) visible events"),
                    systemImage: "arrow.left.arrow.right.circle"
                )
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(String(localized: "Scoped search"), systemImage: "magnifyingglass")
                }
                if viewModel.topology != nil {
                    Label(String(localized: "Topology loaded"), systemImage: "wave.3.right")
                }
            }
        }
    }

    private var commsControlDeckCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSurfaceGroupCard(
                title: String(localized: "Routes"),
                detail: String(localized: "Jump straight to runtime, incidents, audit, or external-agent inventory without another long route stack.")
            ) {
                MonitoringShortcutRail(
                    title: String(localized: "Primary"),
                    detail: String(localized: "Keep runtime, incidents, and event review closest to the live comms feed.")
                ) {
                    NavigationLink {
                        RuntimeView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Runtime"),
                            systemImage: "server.rack"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        IncidentsView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Incidents"),
                            systemImage: "bell.badge",
                            tone: filteredEvents.isEmpty ? .neutral : .warning,
                            badgeText: filteredEvents.isEmpty ? nil : String(localized: "\(filteredEvents.count) events")
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        EventsView(api: deps.apiClient, initialScope: .critical)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Critical Events"),
                            systemImage: "text.justify.leading"
                        )
                    }
                    .buttonStyle(.plain)
                }

                MonitoringShortcutRail(
                    title: String(localized: "Support"),
                    detail: String(localized: "Keep external-agent inventory behind the primary comms routes.")
                ) {
                    NavigationLink {
                        A2AAgentsView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "A2A Agents"),
                            systemImage: "link.circle"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            CommsFilterCard(
                searchText: searchText,
                visibleCount: filteredEvents.count,
                totalCount: viewModel.events.count,
                isStreaming: viewModel.isStreaming,
                nodeCount: viewModel.nodeCount,
                edgeCount: viewModel.edgeCount
            )
        }
    }
}

private struct CommsFilterCard: View {
    let searchText: String
    let visibleCount: Int
    let totalCount: Int
    let isStreaming: Bool
    let nodeCount: Int
    let edgeCount: Int

    var body: some View {
        MonitoringFilterCard(summary: summaryLine, detail: searchSummary) {
            statusBadges
        }
    }

    private var statusBadges: some View {
        FlowLayout(spacing: 6) {
            PresentationToneBadge(
                text: isStreaming ? String(localized: "Live") : String(localized: "Polling"),
                tone: isStreaming ? .positive : .warning
            )
            PresentationToneBadge(
                text: nodeCount == 1 ? String(localized: "1 agent") : String(localized: "\(nodeCount) agents"),
                tone: nodeCount > 1 ? .positive : .neutral
            )
            PresentationToneBadge(
                text: edgeCount == 1 ? String(localized: "1 link") : String(localized: "\(edgeCount) links"),
                tone: edgeCount > 0 ? .positive : .neutral
            )
        }
    }

    private var summaryLine: String {
        if visibleCount == totalCount {
            return totalCount == 1
                ? String(localized: "1 comms event in feed")
                : String(localized: "\(totalCount) comms events in feed")
        }

        return String(localized: "\(visibleCount) of \(totalCount) comms events visible")
    }

    private var searchSummary: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return String(localized: "Search by source, target, task, or event detail.")
        }
        return String(localized: "Search active: \"\(query)\"")
    }
}

private struct CommsTrafficInventoryDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let activeLinks: Int
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
                    text: activeLinks == 1 ? String(localized: "1 live link") : String(localized: "\(activeLinks) live links"),
                    tone: activeLinks > 0 ? .positive : .neutral
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
                ? String(localized: "1 comms event is ready in the traffic feed.")
                : String(localized: "\(totalCount) comms events are ready in the traffic feed.")
        }

        return String(localized: "\(visibleCount) of \(totalCount) comms events are visible in the traffic feed.")
    }

    private var detailLine: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return String(localized: "Live links and transport state stay summarized before the traffic feed.")
        }
        return String(localized: "Filtered by \"\(query)\" before the traffic feed.")
    }
}

private struct CommsTopologyInventoryDeck: View {
    let topology: CommsTopology
    let visibleEdges: [CommsEdge]

    private var peerCount: Int {
        topology.edges.filter { $0.kind == .peer }.count
    }

    private var parentChildCount: Int {
        topology.edges.filter { $0.kind == .parentChild }.count
    }

    private var representedNodeCount: Int {
        Set(visibleEdges.flatMap { [$0.from, $0.to] }).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(summary: summaryLine, detail: detailLine) {
                FlowLayout(spacing: 6) {
                    PresentationToneBadge(
                        text: topology.nodes.count == 1 ? String(localized: "1 agent mapped") : String(localized: "\(topology.nodes.count) agents mapped"),
                        tone: topology.nodes.count > 1 ? .positive : .neutral
                    )
                    PresentationToneBadge(
                        text: topology.edges.count == 1 ? String(localized: "1 live link") : String(localized: "\(topology.edges.count) live links"),
                        tone: topology.edges.isEmpty ? .neutral : .positive
                    )
                    if peerCount > 0 {
                        PresentationToneBadge(
                            text: peerCount == 1 ? String(localized: "1 peer link") : String(localized: "\(peerCount) peer links"),
                            tone: .positive
                        )
                    }
                    if parentChildCount > 0 {
                        PresentationToneBadge(
                            text: parentChildCount == 1 ? String(localized: "1 parent-child link") : String(localized: "\(parentChildCount) parent-child links"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Topology inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep node spread, relationship mix, and visible route depth summarized before the link rows."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleEdges.count == topology.edges.count
                        ? String(localized: "Full topology")
                        : String(localized: "\(visibleEdges.count)/\(topology.edges.count) visible"),
                    tone: visibleEdges.count == topology.edges.count ? .positive : .neutral
                )
            } facts: {
                Label(
                    representedNodeCount == 1 ? String(localized: "1 visible endpoint") : String(localized: "\(representedNodeCount) visible endpoints"),
                    systemImage: "circle.grid.2x2"
                )
                Label(
                    peerCount == 1 ? String(localized: "1 peer route") : String(localized: "\(peerCount) peer routes"),
                    systemImage: "arrow.left.arrow.right"
                )
                Label(
                    parentChildCount == 1 ? String(localized: "1 parent-child route") : String(localized: "\(parentChildCount) parent-child routes"),
                    systemImage: "arrow.down.forward.and.arrow.up.backward"
                )
            }
        }
    }

    private var summaryLine: String {
        if topology.edges.isEmpty {
            return String(localized: "Topology is ready for the first live agent link.")
        }
        if visibleEdges.count == topology.edges.count {
            return topology.edges.count == 1
                ? String(localized: "The topology section is showing the only live comms link.")
                : String(localized: "The topology section is showing all \(topology.edges.count) live comms links.")
        }
        return String(localized: "The topology section is showing \(visibleEdges.count) of \(topology.edges.count) live comms links.")
    }

    private var detailLine: String {
        String(localized: "Agent count, link mix, and route visibility stay summarized here before the topology rows.")
    }
}

private struct CommsTopologyEdgeRow: View {
    let title: String
    let kind: CommsEdgeKind

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ResponsiveAccessoryRow(horizontalSpacing: 10, verticalSpacing: 4) {
                titleLabel
            } accessory: {
                relationshipBadge
            }

            Text(kind == .parentChild ? String(localized: "Parent-child relationship") : String(localized: "Peer communication path"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private var titleLabel: some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .lineLimit(2)
    }

    private var relationshipBadge: some View {
        PresentationToneBadge(
            text: kind == .parentChild ? String(localized: "Parent Child") : String(localized: "Peer"),
            tone: kind == .parentChild ? .warning : .positive
        )
    }
}

private struct CommsSummaryRow<Content: View>: View {
    let label: LocalizedStringKey
    let content: Content

    init(label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        ResponsiveValueRow {
            Text(label)
        } value: {
            content
        }
    }
}

private struct CommsScoreboard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let viewModel: CommsViewModel

    private var agentStatus: MonitoringSummaryStatus {
        MonitoringSummaryStatus(
            summary: "\(viewModel.nodeCount)",
            tone: viewModel.nodeCount > 1 ? .positive : .neutral
        )
    }

    private var linkStatus: MonitoringSummaryStatus {
        .countStatus(viewModel.edgeCount, activeTone: .positive)
    }

    private var taskFlowStatus: MonitoringSummaryStatus {
        .countStatus(viewModel.taskEventCount, activeTone: .warning)
    }

    private var transportStatus: MonitoringSummaryStatus {
        MonitoringSummaryStatus(
            summary: viewModel.isStreaming ? String(localized: "Live") : String(localized: "Polling"),
            tone: viewModel.isStreaming ? .positive : .warning
        )
    }

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 4
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            StatBadge(
                value: "\(viewModel.nodeCount)",
                label: "Agents",
                icon: "cpu",
                color: agentStatus.color(positive: .green)
            )
            StatBadge(
                value: "\(viewModel.edgeCount)",
                label: "Links",
                icon: "point.3.connected.trianglepath.dotted",
                color: linkStatus.color(positive: .blue)
            )
            StatBadge(
                value: "\(viewModel.taskEventCount)",
                label: "Task Flow",
                icon: "checklist",
                color: taskFlowStatus.tone.color
            )
            StatBadge(
                value: transportStatus.summary,
                label: "Transport",
                icon: viewModel.isStreaming ? "dot.radiowaves.left.and.right" : "arrow.clockwise",
                color: transportStatus.tone.color
            )
        }
        .padding(.horizontal)
    }
}

private struct CommsEventRow: View {
    let event: CommsEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: event.kind.symbolName)
                    .foregroundStyle(iconColor)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    ResponsiveAccessoryRow(horizontalAlignment: .top, horizontalSpacing: 8, verticalSpacing: 4, spacerMinLength: 10) {
                        titleLabel
                    } accessory: {
                        timestampLabel
                    }

                    ResponsiveIconDetailRow(horizontalSpacing: 6, verticalSpacing: 2, spacerMinLength: 0) {
                        sourceLabelView
                    } detail: {
                        targetLabelView
                    }

                    if !event.detail.isEmpty {
                        Text(event.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var sourceLabel: String {
        event.sourceName.isEmpty ? shortID(event.sourceID) : event.sourceName
    }

    private var targetLabel: String {
        event.targetName.isEmpty ? shortID(event.targetID) : event.targetName
    }

    private var iconColor: Color {
        switch event.kind {
        case .agentMessage:
            .blue
        case .agentSpawned:
            .green
        case .agentTerminated:
            .red
        case .taskPosted:
            .orange
        case .taskClaimed:
            .teal
        case .taskCompleted:
            .green
        }
    }

    private var relativeTimestamp: String {
        guard let date = event.timestamp.eventsISO8601Date else { return event.timestamp }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private var titleLabel: some View {
        Text(event.kind.label)
            .font(.subheadline.weight(.medium))
    }

    private var timestampLabel: some View {
        Text(relativeTimestamp)
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private var sourceLabelView: some View {
        Text(sourceLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var targetLabelView: some View {
        Text(targetLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func shortID(_ id: String) -> String {
        guard id.count > 8 else { return id }
        return String(id.prefix(8))
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

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
                        description: Text("Active links appear here.")
                    )
                }
            } header: {
                Text("Topology")
            }

            if filteredEvents.isEmpty && !viewModel.isLoading {
                Section("Traffic") {
                    ContentUnavailableView(
                        searchText.isEmpty ? String(localized: "No Communication Events") : String(localized: "No Search Results"),
                        systemImage: "arrow.left.arrow.right.circle",
                        description: Text(searchText.isEmpty ? String(localized: "Traffic appears here.") : String(localized: "Try a different search."))
                    )
                }
            } else {
                Section {
                    ForEach(filteredEvents) { event in
                        CommsEventRow(event: event)
                    }
                } header: {
                    Text("Traffic")
                }
            }
        }
        .navigationTitle(String(localized: "Comms"))
        .searchable(text: $searchText, prompt: Text(String(localized: "Search source, target, or detail")))
        .monitoringRefreshInteractionGate(isRefreshing: viewModel.isLoading)
        .refreshable {
            await viewModel.refresh()
        }
        .overlay {
            if viewModel.isLoading && viewModel.events.isEmpty {
                ProgressView(String(localized: "Loading comms..."))
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
}

private struct CommsTopologyEdgeRow: View {
    let title: String
    let kind: CommsEdgeKind

    var body: some View {
        ResponsiveAccessoryRow(horizontalSpacing: 10, verticalSpacing: 4) {
            titleLabel
        } accessory: {
            relationshipBadge
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

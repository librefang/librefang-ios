import SwiftUI

struct CommsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: CommsViewModel
    @State private var searchText = ""

    init(api: APIClientProtocol) {
        _viewModel = State(initialValue: CommsViewModel(api: api))
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

            Section("Topology") {
                LabeledContent("Agents") {
                    Text("\(viewModel.nodeCount)")
                        .monospacedDigit()
                }
                LabeledContent("Links") {
                    Text("\(viewModel.edgeCount)")
                        .monospacedDigit()
                }
                if let topology = viewModel.topology, !topology.edges.isEmpty {
                    ForEach(topology.edges.prefix(8)) { edge in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(edgeTitle(edge, topology: topology))
                                .font(.subheadline.weight(.medium))
                            Text(edge.kind == .parentChild ? "Parent-child relationship" : "Peer communication path")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    ContentUnavailableView(
                        "No Active Links",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("When agents start messaging, spawning, or coordinating tasks, their topology appears here.")
                    )
                }
            }

            if filteredEvents.isEmpty && !viewModel.isLoading {
                Section("Recent Comms") {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Communication Events" : "No Search Results",
                        systemImage: "arrow.left.arrow.right.circle",
                        description: Text(searchText.isEmpty ? "Live inter-agent traffic will appear here." : "Try a different agent, task, or detail query.")
                    )
                }
            } else {
                Section {
                    ForEach(filteredEvents) { event in
                        CommsEventRow(event: event)
                    }
                } header: {
                    Text("Recent Comms")
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
}

private struct CommsScoreboard: View {
    let viewModel: CommsViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            StatBadge(
                value: "\(viewModel.nodeCount)",
                label: "Agents",
                icon: "cpu",
                color: viewModel.nodeCount > 1 ? .green : .secondary
            )
            StatBadge(
                value: "\(viewModel.edgeCount)",
                label: "Links",
                icon: "point.3.connected.trianglepath.dotted",
                color: viewModel.edgeCount > 0 ? .blue : .secondary
            )
            StatBadge(
                value: "\(viewModel.taskEventCount)",
                label: "Task Flow",
                icon: "checklist",
                color: viewModel.taskEventCount > 0 ? .orange : .secondary
            )
            StatBadge(
                value: viewModel.isStreaming ? "Live" : "Polling",
                label: "Transport",
                icon: viewModel.isStreaming ? "dot.radiowaves.left.and.right" : "arrow.clockwise",
                color: viewModel.isStreaming ? .green : .orange
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
                    HStack {
                        Text(event.kind.label)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(relativeTimestamp)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Text("\(sourceLabel) → \(targetLabel)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

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

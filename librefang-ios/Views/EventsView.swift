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

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        List {
            eventsErrorSection
            eventsFeedSection
        }
        .navigationTitle(String(localized: "Events"))
        .searchable(text: $searchText, prompt: Text(String(localized: "Search action, detail, or agent")))
        .monitoringRefreshInteractionGate(isRefreshing: viewModel.isLoading)
        .refreshable {
            await viewModel.refresh()
        }
        .overlay {
            if viewModel.isLoading && viewModel.entries.isEmpty {
                ProgressView(String(localized: "Loading events..."))
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

    @ViewBuilder
    private var eventsFeedSection: some View {
        if !viewModel.entries.isEmpty {
            Section {
                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No Matching Events"),
                        systemImage: "magnifyingglass",
                        description: Text(String(localized: "Try adjusting your search or severity filter."))
                    )
                } else {
                    ForEach(filteredEntries) { entry in
                        EventRow(entry: entry, agentName: agentName(for: entry.agentId))
                    }
                }
            } header: {
                Text(String(localized: "Event Feed"))
            }
        }
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
            VStack(alignment: .leading, spacing: 3) {
                ResponsiveAccessoryRow(
                    horizontalAlignment: .firstTextBaseline,
                    verticalSpacing: 2
                ) {
                    titleLabel
                } accessory: {
                    outcomeBadge
                }

                captionLabel
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

    private var captionLabel: some View {
        Text("\(agentName ?? shortAgentId) · \(relativeTimestamp)")
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

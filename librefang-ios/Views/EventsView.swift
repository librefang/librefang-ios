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

            Section("Filter") {
                Picker("Severity", selection: $scope) {
                    ForEach(AuditSeverityScope.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: entry.severity.symbolName)
                    .foregroundStyle(entry.severity.tone.color)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            titleLabel
                            Spacer(minLength: 8)
                            timestampLabel
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            titleLabel
                            timestampLabel
                        }
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            agentLabel
                            outcomeBadge
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            agentLabel
                            outcomeBadge
                        }
                    }

                    if !entry.detail.isEmpty {
                        Text(entry.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
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

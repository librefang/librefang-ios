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
                        searchText.isEmpty ? "No Matching Events" : "No Search Results",
                        systemImage: scope == .all ? "list.bullet.rectangle" : "line.3.horizontal.decrease.circle",
                        description: Text(searchText.isEmpty ? "Pull to refresh or widen the severity filter." : "Try a different agent, action, or detail query.")
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

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            StatBadge(
                value: "\(viewModel.criticalCount)",
                label: "Critical",
                icon: "xmark.octagon",
                color: viewModel.criticalCount > 0 ? .red : .secondary
            )
            StatBadge(
                value: "\(viewModel.warningCount)",
                label: "Warnings",
                icon: "exclamationmark.triangle",
                color: viewModel.warningCount > 0 ? .orange : .secondary
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
        }
        .padding(.horizontal)
    }

    private var chainLabel: String {
        guard let verify = viewModel.auditVerify else { return "--" }
        return verify.valid ? "Valid" : "Broken"
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
                    .foregroundStyle(severityColor)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.friendlyAction)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(relativeTimestamp)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 8) {
                        Text(agentName ?? shortAgentId)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(entry.outcome.capitalized)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(severityColor.opacity(0.12))
                            .foregroundStyle(severityColor)
                            .clipShape(Capsule())
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

    private var relativeTimestamp: String {
        guard let date = entry.timestamp.eventsISO8601Date else { return entry.timestamp }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private var severityColor: Color {
        switch entry.severity {
        case .critical:
            .red
        case .warning:
            .orange
        case .info:
            .blue
        }
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

import SwiftUI

struct SessionsView: View {
    @Environment(\.dependencies) private var deps
    @State private var searchText: String
    @State private var filter: SessionFilter

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

    var body: some View {
        List {
            Section {
                SessionScoreboard(vm: vm)
                    .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
            }

            if filteredItems.isEmpty && !vm.isLoading {
                Section("Sessions") {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Sessions In This Filter" : "No Search Results",
                        systemImage: "rectangle.stack",
                        description: Text(searchText.isEmpty ? "Pull to refresh or switch the session filter." : "Try a different agent name, label, or session signal.")
                    )
                }
            } else {
                Section("Sessions") {
                    ForEach(filteredItems) { item in
                        if let agent = item.agent {
                            NavigationLink {
                                AgentDetailView(agent: agent)
                            } label: {
                                SessionMonitorRow(item: item)
                            }
                        } else {
                            SessionMonitorRow(item: item)
                        }
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .searchable(text: $searchText, prompt: "Search session, label, or agent")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Filter", selection: $filter) {
                        ForEach(SessionFilter.allCases, id: \.self) { option in
                            Label(option.label, systemImage: option.icon)
                                .tag(option)
                        }
                    }
                } label: {
                    Image(systemName: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .refreshable {
            await vm.refresh()
        }
        .overlay {
            if vm.isLoading && vm.sessions.isEmpty {
                ProgressView("Loading sessions...")
            }
        }
        .task {
            if vm.sessions.isEmpty {
                await vm.refresh()
            }
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
            "All"
        case .attention:
            "Attention"
        case .highVolume:
            "High Volume"
        case .unlabeled:
            "Unlabeled"
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
    let vm: DashboardViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

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
                color: vm.sessionAttentionCount > 0 ? .orange : .secondary
            )
            StatBadge(
                value: "\(vm.highVolumeSessionCount)",
                label: "High Volume",
                icon: "bubble.left.and.bubble.right",
                color: vm.highVolumeSessionCount > 0 ? .orange : .secondary
            )
            StatBadge(
                value: "\(vm.unlabeledSessionCount)",
                label: "Unlabeled",
                icon: "tag.slash",
                color: vm.unlabeledSessionCount > 0 ? .yellow : .secondary
            )
        }
        .padding(.horizontal)
    }
}

private struct SessionMonitorRow: View {
    let item: SessionAttentionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(.subheadline.weight(.medium))
                    Text(item.agent?.name ?? item.session.agentId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(relativeCreatedAt)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                Label("\(item.session.messageCount)", systemImage: "bubble.left.and.bubble.right")
                    .font(.caption)
                    .foregroundStyle(item.session.messageCount >= 40 ? .orange : .secondary)

                if !item.reasons.isEmpty {
                    ForEach(item.reasons.prefix(2), id: \.self) { reason in
                        Text(reason)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(signalColor.opacity(0.12))
                            .foregroundStyle(signalColor)
                            .clipShape(Capsule())
                    }
                }
            }
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

    private var signalColor: Color {
        if item.severity >= 6 { return .red }
        if item.severity > 0 { return .orange }
        return .secondary
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

import SwiftUI

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

    var body: some View {
        List {
            if filteredItems.isEmpty && !vm.isLoading {
                ContentUnavailableView(
                    searchText.isEmpty ? String(localized: "No Sessions In This Filter") : String(localized: "No Search Results"),
                    systemImage: "rectangle.stack",
                    description: Text(searchText.isEmpty ? String(localized: "Change the filter.") : String(localized: "Try a different search."))
                )
            } else {
                ForEach(filteredItems) { item in
                    sessionRow(for: item)
                }
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
        Text(displayTitle)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
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
        Text(item.agent?.name ?? item.session.agentId)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)

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

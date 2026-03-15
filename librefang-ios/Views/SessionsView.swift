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

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var snapshotFilterTone: PresentationTone {
        switch filter {
        case .attention, .highVolume:
            return .warning
        case .unlabeled:
            return .caution
        case .all:
            return .neutral
        }
    }

    var body: some View {
        List {
            Section {
                SessionScoreboard(vm: vm)
                    .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
            }

            Section {
                sessionsStatusDeckCard
                sessionsControlDeckCard
            } header: {
                Text("Operator Deck")
            } footer: {
                Text("Keep session backlog pressure, drilldowns, and filter scope grouped together before the long queue.")
            }

            if filteredItems.isEmpty && !vm.isLoading {
                Section("Sessions") {
                    ContentUnavailableView(
                        searchText.isEmpty ? String(localized: "No Sessions In This Filter") : String(localized: "No Search Results"),
                        systemImage: "rectangle.stack",
                        description: Text(searchText.isEmpty ? String(localized: "Pull to refresh or switch the session filter.") : String(localized: "Try a different agent name, label, or session signal."))
                    )
                }
            } else {
                Section("Sessions") {
                    ForEach(filteredItems) { item in
                        sessionRow(for: item)
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .searchable(text: $searchText, prompt: "Search session, label, or agent")
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
        .confirmationDialog(
            pendingSessionAction?.title ?? "",
            isPresented: sessionActionConfirmationPresented,
            titleVisibility: .visible,
            presenting: pendingSessionAction
        ) { action in
            Button(action.confirmLabel, role: action.isDestructive ? .destructive : nil) {
                Task { await performSessionAction(action) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(action.message)
        }
        .confirmationDialog(
            "Delete Session",
            isPresented: deleteSessionConfirmationPresented,
            titleVisibility: .visible,
            presenting: pendingDeleteSession
        ) { session in
            Button("Delete Session", role: .destructive) {
                Task { await deleteSession(session) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { session in
            Text("Remove \(displayTitle(for: session)) and its messages from LibreFang? This cannot be undone.")
        }
        .sheet(item: $editingSession) { session in
            NavigationStack {
                Form {
                    Section {
                        TextField("Optional label", text: $sessionLabelDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Text("Clear the field to remove the label. Labels make on-call session lookup much faster.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Session Label")
                    } footer: {
                        Text(displayTitle(for: session))
                    }
                }
                .navigationTitle("Edit Label")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
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
                                Text("Save")
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
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var sessionsStatusDeckCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: vm.totalSessionCount == 1
                    ? String(localized: "1 session is visible in the current workspace snapshot.")
                    : String(localized: "\(vm.totalSessionCount) sessions are visible in the current workspace snapshot."),
                detail: String(localized: "High-volume, unlabeled, and duplicated sessions stay visible before the longer operator list.")
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: filter.label, tone: snapshotFilterTone)
                    if vm.sessionAttentionCount > 0 {
                        PresentationToneBadge(
                            text: vm.sessionAttentionCount == 1 ? String(localized: "1 attention item") : String(localized: "\(vm.sessionAttentionCount) attention items"),
                            tone: .warning
                        )
                    }
                    if vm.highVolumeSessionCount > 0 {
                        PresentationToneBadge(
                            text: vm.highVolumeSessionCount == 1 ? String(localized: "1 high-volume session") : String(localized: "\(vm.highVolumeSessionCount) high-volume sessions"),
                            tone: .warning
                        )
                    }
                    if vm.unlabeledSessionCount > 0 {
                        PresentationToneBadge(
                            text: vm.unlabeledSessionCount == 1 ? String(localized: "1 unlabeled session") : String(localized: "\(vm.unlabeledSessionCount) unlabeled sessions"),
                            tone: .caution
                        )
                    }
                    if vm.multiSessionAgentCount > 0 {
                        PresentationToneBadge(
                            text: vm.multiSessionAgentCount == 1 ? String(localized: "1 agent with multiple sessions") : String(localized: "\(vm.multiSessionAgentCount) agents with multiple sessions"),
                            tone: .warning
                        )
                    }
                    if !normalizedSearchText.isEmpty {
                        PresentationToneBadge(
                            text: filteredItems.count == 1 ? String(localized: "1 visible result") : String(localized: "\(filteredItems.count) visible results"),
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Session queue facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep backlog scope, hotspot counts, and current result volume visible before working through the session list."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: filter.label, tone: snapshotFilterTone)
            } facts: {
                Label(
                    vm.totalSessionCount == 1 ? String(localized: "1 total session") : String(localized: "\(vm.totalSessionCount) total sessions"),
                    systemImage: "text.bubble"
                )
                if vm.sessionAttentionCount > 0 {
                    Label(
                        vm.sessionAttentionCount == 1 ? String(localized: "1 hotspot") : String(localized: "\(vm.sessionAttentionCount) hotspots"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if vm.highVolumeSessionCount > 0 {
                    Label(
                        vm.highVolumeSessionCount == 1 ? String(localized: "1 high-volume session") : String(localized: "\(vm.highVolumeSessionCount) high-volume sessions"),
                        systemImage: "chart.bar.xaxis"
                    )
                }
                if vm.unlabeledSessionCount > 0 {
                    Label(
                        vm.unlabeledSessionCount == 1 ? String(localized: "1 unlabeled session") : String(localized: "\(vm.unlabeledSessionCount) unlabeled sessions"),
                        systemImage: "tag.slash"
                    )
                }
                if vm.multiSessionAgentCount > 0 {
                    Label(
                        vm.multiSessionAgentCount == 1 ? String(localized: "1 multi-session agent") : String(localized: "\(vm.multiSessionAgentCount) multi-session agents"),
                        systemImage: "person.3"
                    )
                }
                Label(
                    filteredItems.count == 1 ? String(localized: "1 visible result") : String(localized: "\(filteredItems.count) visible results"),
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            }
        }
    }

    private var sessionsControlDeckCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSurfaceGroupCard(
                title: String(localized: "Quick Routes"),
                detail: String(localized: "Jump straight to the next queue, fleet, or audit surface without another stack of long route cards.")
            ) {
                FlowLayout(spacing: 8) {
                    NavigationLink {
                        RuntimeView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Runtime"),
                            systemImage: "server.rack",
                            tone: vm.sessionAttentionCount > 0 ? .warning : .neutral,
                            badgeText: vm.sessionAttentionCount > 0
                                ? (vm.sessionAttentionCount == 1 ? String(localized: "1 hotspot") : String(localized: "\(vm.sessionAttentionCount) hotspots"))
                                : nil
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        IncidentsView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Incidents"),
                            systemImage: "bell.badge",
                            tone: vm.sessionAttentionCount > 0 ? .warning : .neutral,
                            badgeText: vm.sessionAttentionCount > 0
                                ? (vm.sessionAttentionCount == 1 ? String(localized: "1 queue item") : String(localized: "\(vm.sessionAttentionCount) queue items"))
                                : nil
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        OnCallView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "On Call"),
                            systemImage: "waveform.path.ecg",
                            tone: vm.sessionAttentionCount > 0 ? .warning : .neutral,
                            badgeText: vm.sessionAttentionCount > 0
                                ? (vm.sessionAttentionCount == 1 ? String(localized: "1 session issue") : String(localized: "\(vm.sessionAttentionCount) session issues"))
                                : nil
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        AgentsView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Agents"),
                            systemImage: "person.3",
                            tone: vm.multiSessionAgentCount > 0 ? .warning : .neutral,
                            badgeText: vm.multiSessionAgentCount > 0
                                ? (vm.multiSessionAgentCount == 1 ? String(localized: "1 agent") : String(localized: "\(vm.multiSessionAgentCount) agents"))
                                : nil
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        EventsView(api: deps.apiClient, initialScope: .warning)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Events"),
                            systemImage: "list.bullet.rectangle.portrait",
                            tone: .warning
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            SessionFilterCard(
                filter: $filter,
                searchText: searchText,
                visibleCount: filteredItems.count,
                totalCount: vm.sessions.count
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
                Button("Switch") {
                    pendingSessionAction = .switchSession(
                        agentID: agent.id,
                        agentName: agent.name,
                        session: item.session
                    )
                }
                .tint(.blue)

                Button("Delete", role: .destructive) {
                    pendingDeleteSession = item.session
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button("Label") {
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
                        Button("Switch") {
                            pendingSessionAction = .switchSession(
                                agentID: item.session.agentId,
                                agentName: item.session.agentId,
                                session: item.session
                            )
                        }
                        .tint(.blue)
                    }

                    Button("Delete", role: .destructive) {
                        pendingDeleteSession = item.session
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button("Label") {
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

private struct SessionFilterCard: View {
    @Binding var filter: SessionFilter
    let searchText: String
    let visibleCount: Int
    let totalCount: Int

    var body: some View {
        MonitoringFilterCard(summary: summaryLine, detail: searchSummary) {
            activeBadge
        } controls: {
            FlowLayout(spacing: 8) {
                ForEach(SessionFilter.allCases, id: \.self) { option in
                    Button {
                        filter = option
                    } label: {
                        SessionFilterChip(
                            label: option.label,
                            systemImage: option.icon,
                            isSelected: filter == option
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var activeBadge: some View {
        PresentationToneBadge(
            text: filter.label,
            tone: badgeTone
        )
    }

    private var summaryLine: String {
        if visibleCount == totalCount {
            return totalCount == 1
                ? String(localized: "1 session in monitor")
                : String(localized: "\(totalCount) sessions in monitor")
        }

        return String(localized: "\(visibleCount) of \(totalCount) sessions visible")
    }

    private var searchSummary: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return String(localized: "Search by session label, agent, or attention reason.")
        }
        return String(localized: "Search active: \"\(query)\"")
    }

    private var badgeTone: PresentationTone {
        switch filter {
        case .all:
            return .neutral
        case .attention:
            return .warning
        case .highVolume:
            return .caution
        case .unlabeled:
            return .critical
        }
    }
}

private struct SessionFilterChip: View {
    let label: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        SelectableLabelCapsuleBadge(
            text: label,
            systemImage: systemImage,
            isSelected: isSelected
        )
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
        VStack(alignment: .leading, spacing: 2) {
            Text(displayTitle)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Text(item.agent?.name ?? item.session.agentId)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
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
        Label("\(item.session.messageCount)", systemImage: "bubble.left.and.bubble.right")
            .font(.caption)
            .foregroundStyle(item.messageCountTone.color)

        if !item.reasons.isEmpty {
            ForEach(item.reasons.prefix(2), id: \.self) { reason in
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

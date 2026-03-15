import SwiftUI

struct AgentFilesView: View {
    let agent: Agent
    let initialFiles: [AgentWorkspaceFileSummary]

    @Environment(\.dependencies) private var deps
    @State private var searchText = ""
    @State private var scope: AgentFileScope
    @State private var files: [AgentWorkspaceFileSummary]
    @State private var isLoading: Bool
    @State private var loadError: String?

    init(agent: Agent, initialFiles: [AgentWorkspaceFileSummary] = [], initialScope: AgentFileScope? = nil) {
        self.agent = agent
        self.initialFiles = initialFiles
        _scope = State(initialValue: initialScope ?? (initialFiles.contains(where: { !$0.exists }) ? .missing : .all))
        _files = State(initialValue: initialFiles.sorted { $0.name < $1.name })
        _isLoading = State(initialValue: initialFiles.isEmpty)
    }

    private var filteredFiles: [AgentWorkspaceFileSummary] {
        let scoped = files.filter { file in
            switch scope {
            case .all:
                return true
            case .missing:
                return !file.exists
            case .present:
                return file.exists
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return scoped }
        return scoped.filter { $0.name.lowercased().contains(query) }
    }

    private var existingCount: Int {
        files.filter(\.exists).count
    }

    private var missingCount: Int {
        files.count - existingCount
    }

    private var workspaceIdentitySummary: WorkspaceIdentitySummary {
        .summarize(existingCount: existingCount, totalCount: files.count)
    }

    private var missingStatus: MonitoringSummaryStatus {
        .countStatus(missingCount, activeTone: .warning)
    }

    private var hasActiveFilter: Bool {
        scope != .all || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var summarySnapshotText: String {
        if missingCount > 0 {
            return String(localized: "Workspace identity drift stays visible before the full file inventory.")
        }
        if files.isEmpty {
            return String(localized: "This surface keeps workspace identity visible before any files load.")
        }
        return String(localized: "Workspace identity stays summarized before the per-file inspection list.")
    }

    private var summarySnapshotDetail: String {
        if hasActiveFilter {
            return filteredFiles.count == 1
                ? String(localized: "1 file matches the current workspace filter.")
                : String(localized: "\(filteredFiles.count) files match the current workspace filter.")
        }
        return String(localized: "Use the route deck when identity files need memory, session, or delivery context.")
    }

    private var exportText: String {
        let header = [
            String(localized: "LibreFang Workspace Identity Snapshot"),
            String(localized: "Agent: \(agent.name)"),
            String(localized: "Scope: \(scope.label)"),
            String(localized: "Visible files: \(filteredFiles.count)"),
            String(localized: "Present: \(existingCount)"),
            String(localized: "Missing: \(missingCount)")
        ]

        let rows = filteredFiles.map { file in
            if file.exists {
                let size = ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file)
                return String(localized: "Present · \(file.name) · \(size)")
            } else {
                return String(localized: "Missing · \(file.name)")
            }
        }

        return (header + [""] + rows).joined(separator: "\n")
    }

    var body: some View {
        List {
            Section {
                MonitoringSnapshotCard(
                    summary: summarySnapshotText,
                    detail: summarySnapshotDetail
                ) {
                    FlowLayout(spacing: 8) {
                        PresentationToneBadge(
                            text: String(localized: "\(existingCount)/\(files.count) present"),
                            tone: workspaceIdentitySummary.tone
                        )
                        PresentationToneBadge(
                            text: missingCount == 1 ? String(localized: "1 missing") : String(localized: "\(missingCount) missing"),
                            tone: missingStatus.tone
                        )
                        if hasActiveFilter {
                            PresentationToneBadge(
                                text: filteredFiles.count == 1 ? String(localized: "1 visible") : String(localized: "\(filteredFiles.count) visible"),
                                tone: .neutral
                            )
                        }
                    }
                }

                MonitoringFactsRow {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "Active Workspace Slice"))
                            .font(.subheadline.weight(.medium))
                        Text(String(localized: "Keep the current scope, visible result count, and agent identity nearby while checking file presence."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } accessory: {
                    PresentationToneBadge(text: scope.label, tone: scope.tone)
                } facts: {
                    Label(agent.name, systemImage: "cpu")
                    Label(
                        filteredFiles.count == 1 ? String(localized: "1 visible file") : String(localized: "\(filteredFiles.count) visible files"),
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                    Label(
                        missingCount == 1 ? String(localized: "1 missing file") : String(localized: "\(missingCount) missing files"),
                        systemImage: "doc.badge.gearshape"
                    )
                }
            } header: {
                Text("Workspace Identity")
            } footer: {
                Text("LibreFang only exposes the whitelisted identity files that shape how an agent behaves and self-describes.")
            }

            Section {
                MonitoringSurfaceGroupCard(
                    title: String(localized: "Primary Routes"),
                    detail: String(localized: "Keep the agent, memory, and session exits closest to workspace identity inspection.")
                ) {
                    NavigationLink {
                        AgentDetailView(agent: agent)
                    } label: {
                        MonitoringJumpRow(
                            title: String(localized: "Back To Agent"),
                            detail: String(localized: "Return to the full agent detail page with deliveries, memory, sessions, and approvals."),
                            systemImage: "cpu",
                            tone: .neutral
                        )
                    }

                    NavigationLink {
                        AgentMemoryView(agent: agent)
                    } label: {
                        MonitoringJumpRow(
                            title: String(localized: "Memory"),
                            detail: String(localized: "Switch to durable memory when workspace identity files alone do not explain agent behavior."),
                            systemImage: "internaldrive",
                            tone: missingCount > 0 ? .warning : .neutral,
                            badgeText: missingCount > 0
                                ? (missingCount == 1 ? String(localized: "1 missing") : String(localized: "\(missingCount) missing"))
                                : nil,
                            badgeTone: .warning
                        )
                    }

                    NavigationLink {
                        SessionsView(initialSearchText: agent.id, initialFilter: .all)
                    } label: {
                        MonitoringJumpRow(
                            title: String(localized: "Sessions"),
                            detail: String(localized: "Switch to the agent's sessions when identity files and live context need to be compared together."),
                            systemImage: "rectangle.stack",
                            tone: .neutral
                        )
                    }
                }

                MonitoringSurfaceGroupCard(
                    title: String(localized: "Support Routes"),
                    detail: String(localized: "Keep outbound delivery context behind the primary workspace identity exits.")
                ) {
                    NavigationLink {
                        AgentDeliveriesView(agent: agent)
                    } label: {
                        MonitoringJumpRow(
                            title: String(localized: "Deliveries"),
                            detail: String(localized: "Switch to channel delivery receipts when workspace identity drift may be affecting output."),
                            systemImage: "paperplane",
                            tone: .neutral
                        )
                    }
                }
            } header: {
                Text("Route Deck")
            } footer: {
                Text("Use these routes when identity files need memory, delivery, or session context rather than isolated file checks.")
            }

            if let loadError {
                Section("Status") {
                    ContentUnavailableView(
                        "Workspace Files Unavailable",
                        systemImage: "doc.badge.exclamationmark",
                        description: Text(loadError)
                    )
                }
            } else {
                Section("Files") {
                    ForEach(filteredFiles) { file in
                        if file.exists {
                            NavigationLink {
                                AgentFileDetailView(agent: agent, file: file)
                            } label: {
                                AgentWorkspaceFileRow(file: file)
                            }
                        } else {
                            AgentWorkspaceFileRow(file: file)
                        }
                    }
                }
            }
        }
        .navigationTitle("Agent Files")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search workspace files")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !filteredFiles.isEmpty {
                    ShareLink(
                        item: exportText,
                        preview: SharePreview(
                            String(localized: "\(agent.name) Workspace Identity"),
                            image: Image(systemName: "doc.text")
                        )
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }

                Menu {
                    Picker("Scope", selection: $scope) {
                        ForEach(AgentFileScope.allCases, id: \.self) { option in
                            Label(option.label, systemImage: option.icon)
                                .tag(option)
                        }
                    }
                } label: {
                    Image(systemName: scope == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .refreshable {
            await loadFiles()
        }
        .overlay {
            if isLoading && files.isEmpty {
                ProgressView("Loading files...")
            }
        }
        .task {
            if files.isEmpty {
                await loadFiles()
            }
        }
    }

    @MainActor
    private func loadFiles() async {
        isLoading = true
        defer { isLoading = false }

        do {
            files = (try await deps.apiClient.agentFiles(agentId: agent.id)).files
                .sorted { $0.name < $1.name }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

enum AgentFileScope: CaseIterable {
    case all
    case missing
    case present

    var label: String {
        switch self {
        case .all:
            return String(localized: "All")
        case .missing:
            return String(localized: "Missing")
        case .present:
            return String(localized: "Present")
        }
    }

    var icon: String {
        switch self {
        case .all:
            return "doc.text"
        case .missing:
            return "exclamationmark.bubble"
        case .present:
            return "checkmark.circle"
        }
    }

    var tone: PresentationTone {
        switch self {
        case .all:
            return .neutral
        case .missing:
            return .warning
        case .present:
            return .positive
        }
    }
}

private struct AgentFileDetailView: View {
    let agent: Agent
    let file: AgentWorkspaceFileSummary

    @Environment(\.dependencies) private var deps
    @State private var detail: AgentWorkspaceFileDetail?
    @State private var isLoading = true
    @State private var loadError: String?

    private var shareText: String? {
        guard let detail else { return nil }

        return [
            String(localized: "LibreFang Workspace Identity File"),
            String(localized: "Agent: \(agent.name)"),
            String(localized: "File: \(detail.name)"),
            String(localized: "Size: \(ByteCountFormatter.string(fromByteCount: Int64(detail.sizeBytes), countStyle: .file))"),
            "",
            detail.content.isEmpty ? String(localized: "File is empty.") : detail.content
        ].joined(separator: "\n")
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading file...")
            } else if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ResponsiveAccessoryRow(horizontalAlignment: .top) {
                            Text(detail.name)
                                .font(.headline)
                                .lineLimit(2)
                        } accessory: {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(detail.sizeBytes), countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(detail.content.isEmpty ? "File is empty." : detail.content)
                            .textSelection(.enabled)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "File Unavailable",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(loadError ?? "LibreFang could not load this workspace file.")
                )
            }
        }
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let shareText, let detail {
                    ShareLink(
                        item: shareText,
                        preview: SharePreview(
                            String(localized: "\(agent.name) \(detail.name)"),
                            image: Image(systemName: "doc.text")
                        )
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }

                if let detail {
                    Button {
                        UIPasteboard.general.string = detail.content
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
        }
        .task {
            await loadDetail()
        }
    }

    @MainActor
    private func loadDetail() async {
        isLoading = true
        defer { isLoading = false }

        do {
            detail = try await deps.apiClient.agentFile(agentId: agent.id, name: file.name)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
            detail = nil
        }
    }
}

private struct AgentWorkspaceFileRow: View {
    let file: AgentWorkspaceFileSummary

    private var tone: PresentationTone {
        file.exists ? .positive : .warning
    }

    var body: some View {
        ResponsiveIconDetailRow(horizontalAlignment: .top, verticalSpacing: 6) {
            Image(systemName: file.exists ? "doc.text" : "doc")
                .foregroundStyle(file.exists ? Color.blue : tone.color)
        } detail: {
            ResponsiveAccessoryRow(horizontalAlignment: .top, verticalSpacing: 6) {
                fileSummary
            } accessory: {
                presenceBadge
            }
        }
        .padding(.vertical, 2)
    }

    private var fileSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(file.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)

            if file.exists {
                Text(ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "Missing"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var presenceBadge: some View {
        PresentationToneBadge(
            text: file.exists ? String(localized: "Present") : String(localized: "Missing"),
            tone: tone,
            horizontalPadding: 6,
            verticalPadding: 2
        )
    }
}

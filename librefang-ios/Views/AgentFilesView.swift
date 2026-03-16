import SwiftUI

private enum AgentFilesSectionAnchor: Hashable {
    case files
}

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

    private var agentFilesSectionCount: Int {
        isLoading && files.isEmpty && loadError == nil ? 2 : 3
    }
    private var agentFilesSectionPreviewTitles: [String] {
        [String(localized: "Files")]
    }

    private var agentFilesPrimaryRouteCount: Int { 3 }
    private var agentFilesSupportRouteCount: Int { 1 }

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
        ScrollViewReader { proxy in
            List {
            if let loadError {
                Section("Status") {
                    ContentUnavailableView(
                        String(localized: "Workspace Files Unavailable"),
                        systemImage: "doc.badge.exclamationmark",
                        description: Text(loadError)
                    )
                }
                .id(AgentFilesSectionAnchor.files)
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
                .id(AgentFilesSectionAnchor.files)
            }
            }
            .navigationTitle(String(localized: "Agent Files"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: Text(String(localized: "Search workspace files")))
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
                        Picker(String(localized: "Scope"), selection: $scope) {
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
            .monitoringRefreshInteractionGate(isRefreshing: isLoading)
            .refreshable {
                await loadFiles()
            }
            .overlay {
                if isLoading && files.isEmpty {
                    ProgressView(String(localized: "Loading files..."))
                }
            }
            .task {
                if files.isEmpty {
                    await loadFiles()
                }
            }
        }
    }

    private func jump(_ proxy: ScrollViewProxy, to anchor: AgentFilesSectionAnchor) {
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    private func agentFilesSectionPreviewJumpItems(_ proxy: ScrollViewProxy) -> [MonitoringSectionJumpItem] {
        [
            MonitoringSectionJumpItem(
                title: String(localized: "Files"),
                systemImage: "doc.text",
                tone: missingStatus.tone
            ) {
                jump(proxy, to: .files)
            }
        ]
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

private struct AgentFilesSectionInventoryDeck: View {
    let sectionCount: Int
    let visibleCount: Int
    let totalCount: Int
    let missingCount: Int
    let hasActiveFilter: Bool
    let scopeLabel: String
    let scopeTone: PresentationTone
    let isLoading: Bool
    let hasLoadError: Bool

    private var coverageTone: PresentationTone {
        if hasLoadError { return .critical }
        if isLoading { return .warning }
        return .positive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: isLoading
                    ? String(localized: "Section coverage stays visible while workspace identity is still loading.")
                    : String(localized: "Section coverage stays visible before routes and individual identity files."),
                detail: hasActiveFilter
                    ? String(localized: "Use section coverage to confirm the active workspace scope before pivoting into related agent surfaces.")
                    : String(localized: "Use section coverage to confirm how much identity context is ready before leaving file inspection."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: sectionCount == 1 ? String(localized: "1 section ready") : String(localized: "\(sectionCount) sections ready"),
                        tone: coverageTone
                    )
                    PresentationToneBadge(text: scopeLabel, tone: scopeTone)
                    if missingCount > 0 {
                        PresentationToneBadge(
                            text: missingCount == 1 ? String(localized: "1 missing file") : String(localized: "\(missingCount) missing files"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Section Coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep summary, routes, and file coverage readable before drilling into specific workspace identity files."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if isLoading {
                    PresentationToneBadge(text: String(localized: "Loading"), tone: .warning)
                } else if hasLoadError {
                    PresentationToneBadge(text: String(localized: "Blocked"), tone: .critical)
                } else {
                    PresentationToneBadge(
                        text: visibleCount == totalCount
                            ? (visibleCount == 1 ? String(localized: "1 visible file") : String(localized: "\(visibleCount) visible files"))
                            : String(localized: "\(visibleCount) of \(totalCount) visible"),
                        tone: .positive
                    )
                }
            } facts: {
                if hasActiveFilter {
                    Label(String(localized: "Scoped inventory"), systemImage: "line.3.horizontal.decrease.circle")
                }
                Label(
                    missingCount == 1 ? String(localized: "1 missing file") : String(localized: "\(missingCount) missing files"),
                    systemImage: "doc.badge.gearshape"
                )
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AgentFilesPressureCoverageDeck: View {
    let visibleCount: Int
    let existingCount: Int
    let missingCount: Int
    let hasActiveFilter: Bool
    let scopeLabel: String
    let scopeTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to separate identity-file drift from simple scope filtering before opening individual workspace files."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: scopeLabel, tone: scopeTone)
                    if missingCount > 0 {
                        PresentationToneBadge(
                            text: missingCount == 1 ? String(localized: "1 missing file") : String(localized: "\(missingCount) missing files"),
                            tone: .warning
                        )
                    }
                    if existingCount > 0 {
                        PresentationToneBadge(
                            text: existingCount == 1 ? String(localized: "1 present file") : String(localized: "\(existingCount) present files"),
                            tone: .positive
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Pressure coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep identity drift and scope pressure readable before the workspace file rows take over."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == 1 ? String(localized: "1 visible file") : String(localized: "\(visibleCount) visible files"),
                    tone: .positive
                )
            } facts: {
                if hasActiveFilter {
                    Label(String(localized: "Scoped inventory"), systemImage: "line.3.horizontal.decrease.circle")
                }
                if missingCount == 0 {
                    Label(String(localized: "Identity intact"), systemImage: "checkmark.seal")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if missingCount > 0 {
            return String(localized: "Workspace pressure is currently anchored by missing identity files.")
        }
        if hasActiveFilter {
            return String(localized: "Workspace pressure is currently concentrated in a scoped file slice.")
        }
        return String(localized: "Workspace pressure is currently low and mostly reflects present identity files.")
    }
}

private struct AgentFilesSupportCoverageDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let existingCount: Int
    let missingCount: Int
    let hasActiveFilter: Bool
    let scopeLabel: String
    let scopeTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep workspace identity support, visible scope, and missing-file context readable before leaving the compact file monitor."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: scopeLabel, tone: scopeTone)
                    if hasActiveFilter {
                        PresentationToneBadge(text: String(localized: "Filter active"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Support coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep present identity files, missing-file drift, and scoped workspace support readable before moving into adjacent agent surfaces."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == totalCount
                        ? (visibleCount == 1 ? String(localized: "1 visible file") : String(localized: "\(visibleCount) visible files"))
                        : String(localized: "\(visibleCount) of \(totalCount) visible"),
                    tone: visibleCount > 0 ? .positive : .neutral
                )
            } facts: {
                if existingCount > 0 {
                    Label(
                        existingCount == 1 ? String(localized: "1 present file") : String(localized: "\(existingCount) present files"),
                        systemImage: "doc.text"
                    )
                }
                if missingCount > 0 {
                    Label(
                        missingCount == 1 ? String(localized: "1 missing file") : String(localized: "\(missingCount) missing files"),
                        systemImage: "doc.badge.gearshape"
                    )
                }
                if hasActiveFilter {
                    Label(String(localized: "Filter active"), systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if missingCount > 0 {
            return String(localized: "Workspace support coverage is currently anchored by missing identity files.")
        }
        if hasActiveFilter {
            return String(localized: "Workspace support coverage is currently narrowed to the filtered identity slice.")
        }
        if existingCount > 0 {
            return String(localized: "Workspace support coverage is currently anchored by present identity files.")
        }
        return String(localized: "Workspace support coverage is currently light across the visible inventory.")
    }
}

private struct AgentFilesFocusCoverageDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let existingCount: Int
    let missingCount: Int
    let hasActiveFilter: Bool
    let scopeLabel: String
    let scopeTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep the dominant workspace-identity lane visible before opening route rails and the full file inventory."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: scopeLabel, tone: scopeTone)
                    PresentationToneBadge(
                        text: visibleCount == totalCount
                            ? (visibleCount == 1 ? String(localized: "1 visible file") : String(localized: "\(visibleCount) visible files"))
                            : String(localized: "\(visibleCount) of \(totalCount) visible"),
                        tone: visibleCount > 0 ? .positive : .neutral
                    )
                    if hasActiveFilter {
                        PresentationToneBadge(text: String(localized: "Filter active"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Focus coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the dominant workspace-identity lane readable before moving from compact identity decks into file rows and adjacent agent surfaces."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: existingCount == 1 ? String(localized: "1 present") : String(localized: "\(existingCount) present"),
                    tone: existingCount > 0 ? .positive : .neutral
                )
            } facts: {
                if missingCount > 0 {
                    Label(
                        missingCount == 1 ? String(localized: "1 missing file") : String(localized: "\(missingCount) missing files"),
                        systemImage: "doc.badge.gearshape"
                    )
                }
                if hasActiveFilter {
                    Label(String(localized: "Filter active"), systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    private var summaryLine: String {
        if missingCount > 0 {
            return String(localized: "Workspace focus coverage is currently anchored by missing identity files.")
        }
        if hasActiveFilter {
            return String(localized: "Workspace focus coverage is currently anchored by the filtered identity slice.")
        }
        return String(localized: "Workspace focus coverage is currently balanced across the visible identity files.")
    }
}

private struct AgentFilesWorkstreamCoverageDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let existingCount: Int
    let missingCount: Int
    let hasActiveFilter: Bool
    let scopeLabel: String
    let scopeTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to see whether workspace identity review is currently led by missing files, present files, or scoped inspection before the full inventory opens."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: scopeLabel, tone: scopeTone)
                    if missingCount > 0 {
                        PresentationToneBadge(
                            text: missingCount == 1 ? String(localized: "1 missing file") : String(localized: "\(missingCount) missing files"),
                            tone: .warning
                        )
                    }
                    if hasActiveFilter {
                        PresentationToneBadge(text: String(localized: "Filter active"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Workstream coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep missing identity files, present workspace files, and scoped inspection state readable before moving into the file rows."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == totalCount
                        ? (visibleCount == 1 ? String(localized: "1 visible file") : String(localized: "\(visibleCount) visible files"))
                        : String(localized: "\(visibleCount) of \(totalCount) visible"),
                    tone: visibleCount > 0 ? .positive : .neutral
                )
            } facts: {
                if existingCount > 0 {
                    Label(
                        existingCount == 1 ? String(localized: "1 present file") : String(localized: "\(existingCount) present files"),
                        systemImage: "doc.text"
                    )
                }
                if hasActiveFilter {
                    Label(String(localized: "Filter active"), systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    private var summaryLine: String {
        if missingCount > 0 {
            return String(localized: "Workspace workstream coverage is currently anchored by missing identity files.")
        }
        if existingCount > 0 {
            return String(localized: "Workspace workstream coverage is currently anchored by present identity files.")
        }
        if hasActiveFilter {
            return String(localized: "Workspace workstream coverage is currently anchored by a filtered identity slice.")
        }
        return String(localized: "Workspace workstream coverage is currently light across the visible inventory.")
    }
}

private struct AgentFilesActionReadinessDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let visibleCount: Int
    let totalCount: Int
    let existingCount: Int
    let missingCount: Int
    let hasActiveFilter: Bool
    let scopeLabel: String
    let scopeTone: PresentationTone

    private var totalRouteCount: Int {
        primaryRouteCount + supportRouteCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to check route breadth, workspace identity drift, and visible file coverage before leaving the compact file monitor."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: scopeLabel, tone: scopeTone)
                    PresentationToneBadge(
                        text: totalRouteCount == 1 ? String(localized: "1 route ready") : String(localized: "\(totalRouteCount) routes ready"),
                        tone: totalRouteCount > 0 ? .positive : .neutral
                    )
                    if hasActiveFilter {
                        PresentationToneBadge(text: String(localized: "Scoped inventory"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Action readiness"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep route breadth, missing-file drift, and visible workspace identity coverage readable before pivoting into adjacent agent surfaces."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == totalCount
                        ? (visibleCount == 1 ? String(localized: "1 visible file") : String(localized: "\(visibleCount) visible files"))
                        : String(localized: "\(visibleCount) of \(totalCount) visible"),
                    tone: visibleCount > 0 ? .positive : .neutral
                )
            } facts: {
                Label(
                    primaryRouteCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryRouteCount) primary routes"),
                    systemImage: "arrowshape.turn.up.right"
                )
                if supportRouteCount > 0 {
                    Label(
                        supportRouteCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportRouteCount) support routes"),
                        systemImage: "square.grid.2x2"
                    )
                }
                if existingCount > 0 {
                    Label(
                        existingCount == 1 ? String(localized: "1 present file") : String(localized: "\(existingCount) present files"),
                        systemImage: "doc.text"
                    )
                }
                if missingCount > 0 {
                    Label(
                        missingCount == 1 ? String(localized: "1 missing file") : String(localized: "\(missingCount) missing files"),
                        systemImage: "doc.badge.gearshape"
                    )
                }
                if hasActiveFilter {
                    Label(String(localized: "Scoped inventory"), systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    private var summaryLine: String {
        if missingCount > 0 {
            return String(localized: "Workspace action readiness is currently anchored by missing identity files and the next route exits.")
        }
        if hasActiveFilter {
            return String(localized: "Workspace action readiness is currently anchored by the scoped identity slice and nearby route exits.")
        }
        return String(localized: "Workspace action readiness is currently clear enough for route pivots and workspace identity review.")
    }
}

private struct AgentFilesRouteInventoryDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let visibleCount: Int
    let totalCount: Int
    let missingCount: Int
    let hasActiveFilter: Bool
    let scopeLabel: String
    let scopeTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: hasActiveFilter
                    ? String(localized: "Workspace-file routes stay compact while the identity inventory is scoped.")
                    : String(localized: "Workspace-file routes stay compact before the surrounding memory and session drilldowns."),
                detail: String(localized: "Use the route inventory to gauge the visible workspace slice before leaving file inspection."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: scopeLabel, tone: scopeTone)
                    PresentationToneBadge(
                        text: primaryRouteCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryRouteCount) primary routes"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: supportRouteCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportRouteCount) support routes"),
                        tone: .neutral
                    )
                    if missingCount > 0 {
                        PresentationToneBadge(
                            text: missingCount == 1 ? String(localized: "1 missing file") : String(localized: "\(missingCount) missing files"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Route Facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the visible workspace slice and identity drift readable before pivoting into agent, memory, session, or delivery context."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == totalCount
                        ? (visibleCount == 1 ? String(localized: "1 visible file") : String(localized: "\(visibleCount) visible files"))
                        : String(localized: "\(visibleCount) of \(totalCount) visible"),
                    tone: .positive
                )
            } facts: {
                if hasActiveFilter {
                    Label(String(localized: "Scoped inventory"), systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AgentFilesInventoryDeck: View {
    let files: [AgentWorkspaceFileSummary]
    let totalFiles: Int
    let scope: AgentFileScope
    let searchText: String

    private var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var presentFiles: [AgentWorkspaceFileSummary] {
        files.filter(\.exists)
    }

    private var missingCount: Int {
        files.count - presentFiles.count
    }

    private var totalVisibleBytes: Int {
        presentFiles.reduce(0) { $0 + $1.sizeBytes }
    }

    private var largestVisibleFile: AgentWorkspaceFileSummary? {
        presentFiles.max { $0.sizeBytes < $1.sizeBytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: hasActiveSearch
                    ? String(localized: "The filtered workspace identity slice stays compact before the full file list.")
                    : String(localized: "The active workspace identity slice stays compact before the full file list."),
                detail: hasActiveSearch
                    ? (files.count == 1
                        ? String(localized: "1 file matches the current workspace search.")
                        : String(localized: "\(files.count) files match the current workspace search."))
                    : String(localized: "Use the deck to gauge missing files, visible footprint, and the largest present file before opening each workspace row."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: files.count == totalFiles
                            ? (files.count == 1 ? String(localized: "1 visible file") : String(localized: "\(files.count) visible files"))
                            : String(localized: "\(files.count) of \(totalFiles) visible"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: presentFiles.count == 1 ? String(localized: "1 present") : String(localized: "\(presentFiles.count) present"),
                        tone: presentFiles.isEmpty ? .neutral : .positive
                    )
                    if missingCount > 0 {
                        PresentationToneBadge(
                            text: missingCount == 1 ? String(localized: "1 missing") : String(localized: "\(missingCount) missing"),
                            tone: .warning
                        )
                    }
                    if totalVisibleBytes > 0 {
                        PresentationToneBadge(
                            text: ByteCountFormatter.string(fromByteCount: Int64(totalVisibleBytes), countStyle: .file),
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Workspace Facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the active scope, visible file footprint, and the heaviest identity file visible while scanning workspace identity."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: scope.label, tone: scope.tone)
            } facts: {
                if let largestVisibleFile {
                    Label(largestVisibleFile.name, systemImage: "doc.text")
                }
                if totalVisibleBytes > 0 {
                    Label(ByteCountFormatter.string(fromByteCount: Int64(totalVisibleBytes), countStyle: .file), systemImage: "externaldrive")
                }
                Label(
                    missingCount == 1 ? String(localized: "1 missing file") : String(localized: "\(missingCount) missing files"),
                    systemImage: "doc.badge.gearshape"
                )
            }
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
                ProgressView(String(localized: "Loading file..."))
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

import SwiftUI

struct AgentMemoryView: View {
    let agent: Agent
    let onUpdate: (([AgentMemoryEntry]) -> Void)?

    @Environment(\.dependencies) private var deps
    @State private var exportSnapshot: AgentMemoryExportSnapshot?
    @State private var entries: [AgentMemoryEntry]
    @State private var searchText = ""
    @State private var isLoading: Bool
    @State private var isExporting = false
    @State private var loadError: String?
    @State private var editorState: MemoryEditorState?
    @State private var pendingDelete: AgentMemoryEntry?
    @State private var actionInFlightKey: String?
    @State private var notice: OperatorActionNotice?

    init(agent: Agent, initialEntries: [AgentMemoryEntry] = [], onUpdate: (([AgentMemoryEntry]) -> Void)? = nil) {
        self.agent = agent
        self.onUpdate = onUpdate
        _entries = State(initialValue: initialEntries.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending })
        _isLoading = State(initialValue: initialEntries.isEmpty)
    }

    private var filteredEntries: [AgentMemoryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }

        return entries.filter { entry in
            entry.key.lowercased().contains(query)
                || entry.summary.lowercased().contains(query)
                || entry.editorText.lowercased().contains(query)
        }
    }

    private var structuredEntryCount: Int {
        entries.filter(\.isStructured).count
    }

    private var scalarEntryCount: Int {
        entries.count - structuredEntryCount
    }

    private var structuredStatus: MonitoringSummaryStatus {
        .countStatus(structuredEntryCount, activeTone: .warning)
    }

    private var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var agentMemorySectionCount: Int {
        isLoading && entries.isEmpty && loadError == nil ? 2 : 3
    }
    private var agentMemorySectionPreviewTitles: [String] {
        [String(localized: "Memory")]
    }

    private var agentMemoryPrimaryRouteCount: Int { 3 }
    private var agentMemorySupportRouteCount: Int { 1 }

    private var summarySnapshotText: String {
        if structuredEntryCount > 0 {
            return String(localized: "Structured memory and editable state stay visible before the raw key list.")
        }
        if entries.isEmpty {
            return String(localized: "This surface keeps durable agent memory visible before any keys exist.")
        }
        return String(localized: "This surface keeps durable agent memory visible before individual key edits.")
    }

    private var summarySnapshotDetail: String {
        if hasActiveSearch {
            return filteredEntries.count == 1
                ? String(localized: "1 key matches the current memory search.")
                : String(localized: "\(filteredEntries.count) keys match the current memory search.")
        }
        return String(localized: "Use the route deck when memory state needs session, incident, or runtime context.")
    }

    var body: some View {
        List {
            summarySection
            operatorSurfacesSection

            if let loadError {
                Section("Memory Status") {
                    ContentUnavailableView(
                        "Memory Unavailable",
                        systemImage: "externaldrive.badge.exclamationmark",
                        description: Text(loadError)
                    )
                }
            } else if filteredEntries.isEmpty, !isLoading {
                Section("Memory") {
                    ContentUnavailableView(
                        entries.isEmpty ? String(localized: "No Memory Keys") : String(localized: "No Matching Keys"),
                        systemImage: "internaldrive",
                        description: Text(entries.isEmpty ? String(localized: "This agent has not stored any KV entries yet.") : String(localized: "Try a different key or value search."))
                    )
                }
            } else {
                Section("Memory") {
                    AgentMemoryInventoryDeck(
                        entries: filteredEntries,
                        totalEntries: entries.count,
                        searchText: searchText,
                        exportReady: exportSnapshot != nil,
                        isExporting: isExporting
                    )

                    ForEach(filteredEntries) { entry in
                        AgentMemoryRow(entry: entry, isBusy: actionInFlightKey == entry.key)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) {
                                    pendingDelete = entry
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button("Edit") {
                                    editorState = .edit(entry)
                                }
                                .tint(.indigo)
                            }
                            .contextMenu {
                                Button {
                                    editorState = .edit(entry)
                                } label: {
                                    Label("Edit Value", systemImage: "pencil")
                                }

                                Button {
                                    UIPasteboard.general.string = entry.editorText
                                    notice = OperatorActionNotice(
                                        title: String(localized: "Memory Value"),
                                        message: String(localized: "\"\(entry.key)\" copied to the clipboard.")
                                    )
                                } label: {
                                    Label("Copy Value", systemImage: "doc.on.doc")
                                }

                                Button(role: .destructive) {
                                    pendingDelete = entry
                                } label: {
                                    Label("Delete Key", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Agent Memory")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search memory key or value")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        editorState = .create(agentName: agent.name)
                    } label: {
                        Label("New Memory Key", systemImage: "plus")
                    }
                    .disabled(isActionBusy)

                    Divider()

                    Button {
                        Task { await copyExportJSON() }
                    } label: {
                        Label("Copy Export JSON", systemImage: "doc.on.doc")
                    }
                    .disabled(isActionBusy || isExporting)

                    if let exportSnapshot {
                        ShareLink(
                            item: exportSnapshot.prettyPrintedJSONString,
                            preview: SharePreview(
                                String(localized: "\(agent.name) Memory Export"),
                                image: Image(systemName: "externaldrive.badge.checkmark")
                            )
                        ) {
                            Label("Share Export Snapshot", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            Task { await prepareExportSnapshot() }
                        } label: {
                            if isExporting {
                                Label("Preparing Export…", systemImage: "square.and.arrow.up")
                            } else {
                                Label("Prepare Export Snapshot", systemImage: "square.and.arrow.up")
                            }
                        }
                        .disabled(isActionBusy || isExporting)
                    }
                } label: {
                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                .disabled(isActionBusy && !isExporting)
            }
        }
        .refreshable {
            await loadMemory()
        }
        .overlay {
            if isLoading && entries.isEmpty {
                ProgressView("Loading memory...")
            }
        }
        .task {
            if entries.isEmpty {
                await loadMemory()
            }
        }
        .sheet(item: $editorState) { state in
            NavigationStack {
                AgentMemoryEditor(
                    title: state.title,
                    key: state.key,
                    keyEditable: state.keyEditable,
                    valueText: state.valueText
                ) { key, valueText in
                    await saveEntry(key: key, valueText: valueText)
                }
            }
        }
        .confirmationDialog(
            "Delete Memory Key",
            isPresented: deleteConfirmationPresented,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { entry in
            Button("Delete Key", role: .destructive) {
                Task { await deleteEntry(entry) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text("Delete memory key \"\(entry.key)\" from \(agent.name)? This cannot be undone.")
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var operatorSurfacesSection: some View {
        Section {
            AgentMemorySectionInventoryDeck(
                sectionCount: agentMemorySectionCount,
                visibleCount: filteredEntries.count,
                totalCount: entries.count,
                structuredCount: structuredEntryCount,
                hasActiveSearch: hasActiveSearch,
                isLoading: isLoading && entries.isEmpty && loadError == nil,
                hasLoadError: loadError != nil
            )
            if !agentMemorySectionPreviewTitles.isEmpty {
                MonitoringSectionPreviewDeck(
                    title: String(localized: "Section Preview"),
                    detail: String(localized: "Keep the next memory stack visible before the key list opens into raw entry rows."),
                    sectionTitles: agentMemorySectionPreviewTitles
                )
            }

            AgentMemoryPressureCoverageDeck(
                visibleCount: filteredEntries.count,
                totalCount: entries.count,
                structuredCount: structuredEntryCount,
                scalarCount: scalarEntryCount,
                hasActiveSearch: hasActiveSearch,
                exportReady: exportSnapshot != nil
            )

            AgentMemoryFocusCoverageDeck(
                visibleCount: filteredEntries.count,
                totalCount: entries.count,
                structuredCount: structuredEntryCount,
                scalarCount: scalarEntryCount,
                hasActiveSearch: hasActiveSearch,
                exportReady: exportSnapshot != nil
            )
            AgentMemoryWorkstreamCoverageDeck(
                visibleCount: filteredEntries.count,
                totalCount: entries.count,
                structuredCount: structuredEntryCount,
                scalarCount: scalarEntryCount,
                hasActiveSearch: hasActiveSearch,
                exportReady: exportSnapshot != nil
            )

            AgentMemoryRouteInventoryDeck(
                primaryRouteCount: agentMemoryPrimaryRouteCount,
                supportRouteCount: agentMemorySupportRouteCount,
                visibleCount: filteredEntries.count,
                totalCount: entries.count,
                structuredCount: structuredEntryCount,
                hasActiveSearch: hasActiveSearch
            )

            MonitoringSurfaceGroupCard(
                title: String(localized: "Routes"),
                detail: String(localized: "Keep nearby agent, session, and runtime exits closest to durable memory inspection.")
            ) {
                MonitoringShortcutRail(
                    title: String(localized: "Primary"),
                    detail: String(localized: "Use nearby agent and incident surfaces first.")
                ) {
                    NavigationLink {
                        AgentDetailView(agent: agent)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Agent"),
                            systemImage: "cpu"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SessionsView(initialSearchText: agent.id, initialFilter: .all)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Sessions"),
                            systemImage: "rectangle.stack",
                            tone: entries.isEmpty ? .neutral : .warning,
                            badgeText: entries.isEmpty ? nil : String(localized: "\(entries.count) keys")
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        IncidentsView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Incidents"),
                            systemImage: "bell.badge",
                            tone: structuredEntryCount > 0 ? .warning : .neutral,
                            badgeText: structuredEntryCount > 0
                                ? (structuredEntryCount == 1 ? String(localized: "1 structured") : String(localized: "\(structuredEntryCount) structured"))
                                : nil
                        )
                    }
                    .buttonStyle(.plain)
                }

                MonitoringShortcutRail(
                    title: String(localized: "Support"),
                    detail: String(localized: "Use broader runtime context when memory alone is not enough.")
                ) {
                    NavigationLink {
                        RuntimeView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Runtime"),
                            systemImage: "server.rack"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Routes")
        } footer: {
            Text("Use these routes when agent memory needs session, runtime, or incident context instead of isolated key inspection.")
        }
    }

    private var summarySection: some View {
        Section {
            MonitoringSnapshotCard(
                summary: summarySnapshotText,
                detail: summarySnapshotDetail
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: entries.count == 1 ? String(localized: "1 key") : String(localized: "\(entries.count) keys"),
                        tone: entries.isEmpty ? .neutral : .positive
                    )
                    PresentationToneBadge(
                        text: structuredEntryCount == 1 ? String(localized: "1 structured") : String(localized: "\(structuredEntryCount) structured"),
                        tone: structuredStatus.tone
                    )
                    PresentationToneBadge(
                        text: scalarEntryCount == 1 ? String(localized: "1 scalar") : String(localized: "\(scalarEntryCount) scalar"),
                        tone: .neutral
                    )
                    if hasActiveSearch {
                        PresentationToneBadge(
                            text: filteredEntries.count == 1 ? String(localized: "1 visible") : String(localized: "\(filteredEntries.count) visible"),
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Working Set"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the current agent, visible results, and export state available while searching or editing memory."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if isExporting {
                    ProgressView()
                        .controlSize(.small)
                } else if exportSnapshot != nil {
                    PresentationToneBadge(text: String(localized: "Export Ready"), tone: .positive)
                }
            } facts: {
                Label(agent.name, systemImage: "cpu")
                Label(
                    hasActiveSearch
                        ? (filteredEntries.count == 1 ? String(localized: "1 visible result") : String(localized: "\(filteredEntries.count) visible results"))
                        : (entries.count == 1 ? String(localized: "1 stored key") : String(localized: "\(entries.count) stored keys")),
                    systemImage: hasActiveSearch ? "line.3.horizontal.decrease.circle" : "internaldrive"
                )
                Label(
                    structuredEntryCount == 1 ? String(localized: "1 structured value") : String(localized: "\(structuredEntryCount) structured values"),
                    systemImage: "square.brackets"
                )
            }
        } header: {
            Text("Summary")
        } footer: {
            Text("LibreFang agent memory is shared operator state. Structured values are usually the most useful during triage.")
        }
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDelete = nil
                }
            }
        )
    }

    private var isActionBusy: Bool {
        actionInFlightKey != nil
    }

    @MainActor
    private func loadMemory() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await deps.apiClient.agentMemory(agentId: agent.id)
            let sorted = response.kvPairs.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            entries = sorted
            loadError = nil
            onUpdate?(sorted)
        } catch {
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func saveEntry(key: String, valueText: String) async -> Bool {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            notice = OperatorActionNotice(
                title: String(localized: "Memory Key"),
                message: String(localized: "A memory key is required.")
            )
            return false
        }

        actionInFlightKey = trimmedKey
        defer { actionInFlightKey = nil }

        do {
            let response = try await deps.apiClient.setAgentMemory(
                agentId: agent.id,
                key: trimmedKey,
                value: .parseMemoryEditorText(valueText)
            )
            editorState = nil
            await loadMemory()
            notice = OperatorActionNotice(
                title: String(localized: "Memory Key"),
                message: response.message ?? String(localized: "Saved \"\(trimmedKey)\".")
            )
            return true
        } catch {
            notice = OperatorActionNotice(
                title: String(localized: "Memory Key"),
                message: error.localizedDescription
            )
            return false
        }
    }

    @MainActor
    private func deleteEntry(_ entry: AgentMemoryEntry) async {
        pendingDelete = nil
        actionInFlightKey = entry.key
        defer { actionInFlightKey = nil }

        do {
            let response = try await deps.apiClient.deleteAgentMemory(agentId: agent.id, key: entry.key)
            await loadMemory()
            notice = OperatorActionNotice(
                title: String(localized: "Delete Memory Key"),
                message: response.message ?? String(localized: "Deleted \"\(entry.key)\".")
            )
        } catch {
            notice = OperatorActionNotice(
                title: String(localized: "Delete Memory Key"),
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func prepareExportSnapshot() async {
        isExporting = true
        defer { isExporting = false }

        do {
            exportSnapshot = try await deps.apiClient.exportAgentMemory(agentId: agent.id)
            notice = OperatorActionNotice(
                title: String(localized: "Memory Export"),
                message: String(localized: "Export snapshot is ready to share.")
            )
        } catch {
            notice = OperatorActionNotice(
                title: String(localized: "Memory Export"),
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func copyExportJSON() async {
        isExporting = true
        defer { isExporting = false }

        do {
            let snapshot = try await deps.apiClient.exportAgentMemory(agentId: agent.id)
            exportSnapshot = snapshot
            UIPasteboard.general.string = snapshot.prettyPrintedJSONString
            notice = OperatorActionNotice(
                title: String(localized: "Memory Export"),
                message: String(localized: "\"\(agent.name)\" memory JSON copied to the clipboard.")
            )
        } catch {
            notice = OperatorActionNotice(
                title: String(localized: "Memory Export"),
                message: error.localizedDescription
            )
        }
    }
}

private enum MemoryEditorState: Identifiable {
    case create(agentName: String)
    case edit(AgentMemoryEntry)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let entry):
            return entry.key
        }
    }

    var title: String {
        switch self {
        case .create:
            return String(localized: "New Memory Key")
        case .edit:
            return String(localized: "Edit Memory")
        }
    }

    var key: String {
        switch self {
        case .create:
            return ""
        case .edit(let entry):
            return entry.key
        }
    }

    var keyEditable: Bool {
        switch self {
        case .create:
            return true
        case .edit:
            return false
        }
    }

    var valueText: String {
        switch self {
        case .create:
            return "\"\""
        case .edit(let entry):
            return entry.editorText
        }
    }
}

private struct AgentMemoryEditor: View {
    let title: String
    @State private var key: String
    let keyEditable: Bool
    @State private var valueText: String
    let onSave: @MainActor (String, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    init(title: String, key: String, keyEditable: Bool, valueText: String, onSave: @escaping @MainActor (String, String) async -> Bool) {
        self.title = title
        self.keyEditable = keyEditable
        self.onSave = onSave
        _key = State(initialValue: key)
        _valueText = State(initialValue: valueText)
    }

    var body: some View {
        Form {
            Section {
                TextField("Memory Key", text: $key, prompt: Text(String(localized: "Memory Key")))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(!keyEditable)
            } header: {
                Text("Key")
            }

            Section {
                TextEditor(text: $valueText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 240)
            } header: {
                Text("Value")
            } footer: {
                Text("Objects, arrays, booleans, numbers, and null will be stored as JSON. Any other input is saved as a plain string.")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task {
                        isSaving = true
                        let saved = await onSave(key, valueText)
                        isSaving = false
                        if saved {
                            dismiss()
                        }
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Save")
                    }
                }
                .disabled(isSaving)
            }
        }
    }
}

private struct AgentMemoryRow: View {
    let entry: AgentMemoryEntry
    let isBusy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ResponsiveAccessoryRow(horizontalSpacing: 8, verticalSpacing: 4) {
                keyLabel
            } accessory: {
                trailingIndicators
            }

            Text(entry.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(entry.editorText)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(3)
        }
        .padding(.vertical, 2)
    }

    private var keyLabel: some View {
        Text(entry.key)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var trailingIndicators: some View {
        HStack(spacing: 8) {
            if let structureBadgeLabel = entry.structureBadgeLabel,
               let structureTone = entry.structureTone {
                PresentationToneBadge(
                    text: structureBadgeLabel,
                    tone: structureTone,
                    horizontalPadding: 6,
                    verticalPadding: 2
                )
            }

            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}

private struct AgentMemorySectionInventoryDeck: View {
    let sectionCount: Int
    let visibleCount: Int
    let totalCount: Int
    let structuredCount: Int
    let hasActiveSearch: Bool
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
                    ? String(localized: "Section coverage stays visible while agent memory is still loading.")
                    : String(localized: "Section coverage stays visible before memory routes and editable keys."),
                detail: hasActiveSearch
                    ? String(localized: "Use section coverage to confirm the filtered memory slice before pivoting into routes or key edits.")
                    : String(localized: "Use section coverage to confirm how much memory context is ready before leaving the current agent."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: sectionCount == 1 ? String(localized: "1 section ready") : String(localized: "\(sectionCount) sections ready"),
                        tone: coverageTone
                    )
                    PresentationToneBadge(
                        text: totalCount == 1 ? String(localized: "1 stored key") : String(localized: "\(totalCount) stored keys"),
                        tone: totalCount == 0 ? .neutral : .positive
                    )
                    if structuredCount > 0 {
                        PresentationToneBadge(
                            text: structuredCount == 1 ? String(localized: "1 structured block") : String(localized: "\(structuredCount) structured blocks"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Section Coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep summary, routes, and memory sections visible before drilling into individual key edits."))
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
                    PresentationToneBadge(text: String(localized: "Ready"), tone: .positive)
                }
            } facts: {
                if hasActiveSearch {
                    Label(
                        visibleCount == 1 ? String(localized: "1 visible key") : String(localized: "\(visibleCount) visible keys"),
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                }
                Label(
                    structuredCount == 1 ? String(localized: "1 structured value") : String(localized: "\(structuredCount) structured values"),
                    systemImage: "square.brackets"
                )
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AgentMemoryPressureCoverageDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let structuredCount: Int
    let scalarCount: Int
    let hasActiveSearch: Bool
    let exportReady: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to separate structured state, scalar keys, search scope, and export readiness before drilling into individual memory edits."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if structuredCount > 0 {
                        PresentationToneBadge(
                            text: structuredCount == 1 ? String(localized: "1 structured value") : String(localized: "\(structuredCount) structured values"),
                            tone: .warning
                        )
                    }
                    if scalarCount > 0 {
                        PresentationToneBadge(
                            text: scalarCount == 1 ? String(localized: "1 scalar key") : String(localized: "\(scalarCount) scalar keys"),
                            tone: .neutral
                        )
                    }
                    PresentationToneBadge(
                        text: exportReady ? String(localized: "Export ready") : String(localized: "Export pending"),
                        tone: exportReady ? .positive : .neutral
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Pressure coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep durable-state shape and export readiness visible before the editable key rows take over."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == totalCount
                        ? (visibleCount == 1 ? String(localized: "1 visible key") : String(localized: "\(visibleCount) visible keys"))
                        : String(localized: "\(visibleCount) of \(totalCount) visible"),
                    tone: .positive
                )
            } facts: {
                if hasActiveSearch {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
                if structuredCount > 0 && scalarCount > 0 {
                    Label(String(localized: "Mixed state"), systemImage: "square.stack.3d.up")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if structuredCount > 0 {
            return String(localized: "Memory pressure is currently anchored by structured durable state.")
        }
        if hasActiveSearch {
            return String(localized: "Memory pressure is currently concentrated in a search-scoped slice.")
        }
        return String(localized: "Memory pressure is currently light and mostly reflects scalar durable keys.")
    }
}

private struct AgentMemoryFocusCoverageDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let structuredCount: Int
    let scalarCount: Int
    let hasActiveSearch: Bool
    let exportReady: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep the dominant memory lane visible before opening route rails and the full key list."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: visibleCount == totalCount
                            ? (visibleCount == 1 ? String(localized: "1 visible key") : String(localized: "\(visibleCount) visible keys"))
                            : String(localized: "\(visibleCount) of \(totalCount) visible"),
                        tone: visibleCount > 0 ? .positive : .neutral
                    )
                    if exportReady {
                        PresentationToneBadge(text: String(localized: "Export ready"), tone: .positive)
                    }
                    if hasActiveSearch {
                        PresentationToneBadge(text: String(localized: "Search scoped"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Focus coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the dominant memory lane readable before moving from compact memory decks into editable keys and adjacent monitoring routes."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: structuredCount == 1 ? String(localized: "1 structured key") : String(localized: "\(structuredCount) structured keys"),
                    tone: structuredCount > 0 ? .warning : .neutral
                )
            } facts: {
                if scalarCount > 0 {
                    Label(
                        scalarCount == 1 ? String(localized: "1 scalar key") : String(localized: "\(scalarCount) scalar keys"),
                        systemImage: "text.cursor"
                    )
                }
                if hasActiveSearch {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
                if exportReady {
                    Label(String(localized: "Export snapshot ready"), systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private var summaryLine: String {
        if structuredCount > 0 {
            return String(localized: "Memory focus coverage is currently anchored by structured state.")
        }
        if hasActiveSearch {
            return String(localized: "Memory focus coverage is currently anchored by the filtered memory slice.")
        }
        if exportReady {
            return String(localized: "Memory focus coverage is currently anchored by export-ready durable state.")
        }
        return String(localized: "Memory focus coverage is currently balanced across the visible key set.")
    }
}

private struct AgentMemoryWorkstreamCoverageDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let structuredCount: Int
    let scalarCount: Int
    let hasActiveSearch: Bool
    let exportReady: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to see whether memory review is currently led by structured state, scalar keys, or export and search work before opening the full key list."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if structuredCount > 0 {
                        PresentationToneBadge(
                            text: structuredCount == 1 ? String(localized: "1 structured key") : String(localized: "\(structuredCount) structured keys"),
                            tone: .warning
                        )
                    }
                    if scalarCount > 0 {
                        PresentationToneBadge(
                            text: scalarCount == 1 ? String(localized: "1 scalar key") : String(localized: "\(scalarCount) scalar keys"),
                            tone: .neutral
                        )
                    }
                    if exportReady {
                        PresentationToneBadge(text: String(localized: "Export ready"), tone: .positive)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Workstream coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep structured state, scalar durable keys, and export or search readiness readable before moving through editable memory rows."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == totalCount
                        ? (visibleCount == 1 ? String(localized: "1 visible key") : String(localized: "\(visibleCount) visible keys"))
                        : String(localized: "\(visibleCount) of \(totalCount) visible"),
                    tone: visibleCount > 0 ? .positive : .neutral
                )
            } facts: {
                if hasActiveSearch {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
                if structuredCount > 0 && scalarCount > 0 {
                    Label(String(localized: "Mixed state"), systemImage: "square.stack.3d.up")
                }
            }
        }
    }

    private var summaryLine: String {
        if structuredCount >= scalarCount && structuredCount > 0 {
            return String(localized: "Memory workstream coverage is currently anchored by structured durable state.")
        }
        if scalarCount > 0 {
            return String(localized: "Memory workstream coverage is currently anchored by scalar durable keys.")
        }
        if hasActiveSearch || exportReady {
            return String(localized: "Memory workstream coverage is currently anchored by scoped export and search work.")
        }
        return String(localized: "Memory workstream coverage is currently light across the visible keys.")
    }
}

private struct AgentMemoryRouteInventoryDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let visibleCount: Int
    let totalCount: Int
    let structuredCount: Int
    let hasActiveSearch: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: hasActiveSearch
                    ? String(localized: "Memory routes stay compact while the durable key list is search-scoped.")
                    : String(localized: "Memory routes stay compact before the surrounding incident and runtime drilldowns."),
                detail: String(localized: "Use the route inventory to gauge the visible durable-memory slice before leaving key inspection."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: primaryRouteCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryRouteCount) primary routes"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: supportRouteCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportRouteCount) support routes"),
                        tone: .neutral
                    )
                    if structuredCount > 0 {
                        PresentationToneBadge(
                            text: structuredCount == 1 ? String(localized: "1 structured key") : String(localized: "\(structuredCount) structured keys"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Route Facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep durable-memory size and structured-key pressure visible before pivoting into agent, session, incident, or runtime context."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == totalCount
                        ? (visibleCount == 1 ? String(localized: "1 visible key") : String(localized: "\(visibleCount) visible keys"))
                        : String(localized: "\(visibleCount) of \(totalCount) visible"),
                    tone: .positive
                )
            } facts: {
                if hasActiveSearch {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AgentMemoryInventoryDeck: View {
    let entries: [AgentMemoryEntry]
    let totalEntries: Int
    let searchText: String
    let exportReady: Bool
    let isExporting: Bool

    private var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var structuredCount: Int {
        entries.filter(\.isStructured).count
    }

    private var scalarCount: Int {
        entries.count - structuredCount
    }

    private var longestKey: String? {
        entries.max { $0.key.count < $1.key.count }?.key
    }

    private var summaryCharacterCount: Int {
        entries.reduce(0) { $0 + $1.summary.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: hasActiveSearch
                    ? String(localized: "The filtered memory slice stays compact before the editable key list.")
                    : String(localized: "The active memory slice stays compact before the editable key list."),
                detail: hasActiveSearch
                    ? (entries.count == 1
                        ? String(localized: "1 memory key matches the current search.")
                        : String(localized: "\(entries.count) memory keys match the current search."))
                    : String(localized: "Use the deck to gauge structured memory, current export state, and the longest key before opening individual memory rows."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: entries.count == totalEntries
                            ? (entries.count == 1 ? String(localized: "1 visible key") : String(localized: "\(entries.count) visible keys"))
                            : String(localized: "\(entries.count) of \(totalEntries) visible"),
                        tone: .positive
                    )
                    if structuredCount > 0 {
                        PresentationToneBadge(
                            text: structuredCount == 1 ? String(localized: "1 structured") : String(localized: "\(structuredCount) structured"),
                            tone: .warning
                        )
                    }
                    if scalarCount > 0 {
                        PresentationToneBadge(
                            text: scalarCount == 1 ? String(localized: "1 scalar") : String(localized: "\(scalarCount) scalar"),
                            tone: .neutral
                        )
                    }
                    if summaryCharacterCount > 0 {
                        PresentationToneBadge(
                            text: summaryCharacterCount == 1 ? String(localized: "1 summary char") : String(localized: "\(summaryCharacterCount) summary chars"),
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Memory Facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep export state, visible structure mix, and the longest key visible while editing or triaging durable memory."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if isExporting {
                    ProgressView()
                        .controlSize(.small)
                } else if exportReady {
                    PresentationToneBadge(text: String(localized: "Export Ready"), tone: .positive)
                }
            } facts: {
                Label(
                    structuredCount == 1 ? String(localized: "1 structured key") : String(localized: "\(structuredCount) structured keys"),
                    systemImage: "square.brackets"
                )
                Label(
                    scalarCount == 1 ? String(localized: "1 scalar key") : String(localized: "\(scalarCount) scalar keys"),
                    systemImage: "text.cursor"
                )
                if let longestKey {
                    Label(longestKey, systemImage: "arrow.left.and.right.text.vertical")
                }
            }
        }
    }
}

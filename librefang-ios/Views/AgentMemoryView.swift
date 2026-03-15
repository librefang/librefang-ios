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

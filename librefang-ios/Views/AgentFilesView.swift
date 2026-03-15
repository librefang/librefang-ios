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

    init(agent: Agent, initialFiles: [AgentWorkspaceFileSummary] = []) {
        self.agent = agent
        self.initialFiles = initialFiles
        _scope = State(initialValue: initialFiles.contains(where: { !$0.exists }) ? .missing : .all)
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

    var body: some View {
        List {
            Section {
                LabeledContent("Agent") {
                    Text(agent.name)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Present") {
                    Text("\(existingCount)/\(files.count)")
                        .foregroundStyle(existingCount < files.count ? .orange : .green)
                        .monospacedDigit()
                }
                LabeledContent("Missing") {
                    Text(missingCount.formatted())
                        .foregroundStyle(missingCount > 0 ? .orange : .secondary)
                        .monospacedDigit()
                }
            } header: {
                Text("Workspace Identity")
            } footer: {
                Text("LibreFang only exposes the whitelisted identity files that shape how an agent behaves and self-describes.")
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
            ToolbarItem(placement: .topBarTrailing) {
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

private enum AgentFileScope: CaseIterable {
    case all
    case missing
    case present

    var label: String {
        switch self {
        case .all:
            return "All"
        case .missing:
            return "Missing"
        case .present:
            return "Present"
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
}

private struct AgentFileDetailView: View {
    let agent: Agent
    let file: AgentWorkspaceFileSummary

    @Environment(\.dependencies) private var deps
    @State private var detail: AgentWorkspaceFileDetail?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading file...")
            } else if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(detail.name)
                                .font(.headline)
                            Spacer()
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
            ToolbarItem(placement: .topBarTrailing) {
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.exists ? "doc.text" : "doc")
                .foregroundStyle(file.exists ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.subheadline.weight(.medium))

                if file.exists {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Missing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(file.exists ? "Present" : "Missing")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((file.exists ? Color.green : Color.orange).opacity(0.12))
                .foregroundStyle(file.exists ? .green : .orange)
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
    }
}

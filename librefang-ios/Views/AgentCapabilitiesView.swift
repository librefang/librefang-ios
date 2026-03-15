import SwiftUI

struct AgentCapabilitiesView: View {
    let agent: Agent
    let initialToolFilters: AgentToolFilters?
    let initialSkills: AgentAssignmentScope?
    let initialMCPServers: AgentAssignmentScope?

    @Environment(\.dependencies) private var deps
    @State private var toolFilters: AgentToolFilters?
    @State private var skills: AgentAssignmentScope?
    @State private var mcpServers: AgentAssignmentScope?
    @State private var isRefreshing = false
    @State private var loadError: String?

    init(
        agent: Agent,
        initialToolFilters: AgentToolFilters? = nil,
        initialSkills: AgentAssignmentScope? = nil,
        initialMCPServers: AgentAssignmentScope? = nil
    ) {
        self.agent = agent
        self.initialToolFilters = initialToolFilters
        self.initialSkills = initialSkills
        self.initialMCPServers = initialMCPServers
        _toolFilters = State(initialValue: initialToolFilters)
        _skills = State(initialValue: initialSkills)
        _mcpServers = State(initialValue: initialMCPServers)
    }

    private var toolCatalog: [String: ToolInfo] {
        Dictionary(uniqueKeysWithValues: deps.dashboardViewModel.tools.map { ($0.name, $0) })
    }

    private var configuredMCPServerNames: Set<String> {
        Set(deps.dashboardViewModel.mcpConfiguredServers.map(\.name))
    }

    private var connectedMCPServerNames: Set<String> {
        Set(deps.dashboardViewModel.mcpConnectedServers.map(\.name))
    }

    private var hasLoadedAnything: Bool {
        toolFilters != nil || skills != nil || mcpServers != nil
    }

    var body: some View {
        List {
            if isRefreshing && !hasLoadedAnything {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }

            if let toolFilters {
                toolFiltersSection(toolFilters)
            }

            if let skills {
                skillsSection(skills)
            }

            if let mcpServers {
                mcpServersSection(mcpServers)
            }

            if let loadError, !hasLoadedAnything {
                Section {
                    ContentUnavailableView(
                        "Capabilities Unavailable",
                        systemImage: "slider.horizontal.3",
                        description: Text(loadError)
                    )
                }
            }
        }
        .navigationTitle("Capabilities")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await refresh()
        }
        .task {
            await refresh()
        }
    }

    private func toolFiltersSection(_ filters: AgentToolFilters) -> some View {
        Section {
            CapabilityDetailRow(
                icon: "slider.horizontal.3",
                label: String(localized: "Scope"),
                value: filters.scopeLabel,
                valueColor: filters.scopeTone.color
            )
            CapabilityDetailRow(
                icon: "checkmark.circle",
                label: String(localized: "Allowlist"),
                value: filters.toolAllowlist.isEmpty ? String(localized: "None") : "\(filters.toolAllowlist.count)"
            )
            CapabilityDetailRow(
                icon: "nosign",
                label: String(localized: "Blocklist"),
                value: filters.toolBlocklist.isEmpty ? String(localized: "None") : "\(filters.toolBlocklist.count)",
                valueColor: filters.toolBlocklistTone.color
            )

            capabilityNamesSection(
                title: String(localized: "Allowed Tools"),
                names: filters.toolAllowlist,
                emptyText: String(localized: "This agent inherits the full tool catalog unless tools are blocked elsewhere.")
            ) { name in
                toolCatalog[name]?.description
            }

            capabilityNamesSection(
                title: String(localized: "Blocked Tools"),
                names: filters.toolBlocklist,
                emptyText: String(localized: "No blocked tools.")
            ) { name in
                toolCatalog[name]?.description
            }
        } header: {
            Text("Tool Filters")
        } footer: {
            Text("These filters are applied on top of the agent profile and determine which tools the runtime can actually call.")
        }
    }

    private func skillsSection(_ assignment: AgentAssignmentScope) -> some View {
        Section {
            CapabilityDetailRow(
                icon: "sparkles",
                label: String(localized: "Mode"),
                value: assignment.scopeLabel(openAccessLabel: String(localized: "All skills")),
                valueColor: assignment.scopeTone.color
            )
            CapabilityDetailRow(
                icon: "wand.and.stars",
                label: String(localized: "Assigned"),
                value: assignment.assigned.isEmpty ? String(localized: "None") : "\(assignment.assigned.count)"
            )
            CapabilityDetailRow(
                icon: "square.stack.3d.up",
                label: String(localized: "Available"),
                value: "\(assignment.available.count)"
            )

            capabilityNamesSection(
                title: String(localized: "Assigned Skills"),
                names: assignment.assigned,
                emptyText: assignment.usesAllowlist
                    ? String(localized: "No skills are currently assigned.")
                    : String(localized: "This agent inherits all available skills.")
            ) { _ in
                nil
            }
        } header: {
            Text("Skills")
        } footer: {
            Text("LibreFang resolves skills server-side. An empty allowlist means the agent can see every installed skill.")
        }
    }

    private func mcpServersSection(_ assignment: AgentAssignmentScope) -> some View {
        Section {
            CapabilityDetailRow(
                icon: "shippingbox",
                label: String(localized: "Mode"),
                value: assignment.scopeLabel(openAccessLabel: String(localized: "All connected servers")),
                valueColor: assignment.scopeTone.color
            )
            CapabilityDetailRow(
                icon: "checkmark.rectangle.stack",
                label: String(localized: "Assigned"),
                value: assignment.assigned.isEmpty ? String(localized: "None") : "\(assignment.assigned.count)"
            )
            CapabilityDetailRow(
                icon: "point.3.connected.trianglepath.dotted",
                label: String(localized: "Available"),
                value: "\(assignment.available.count)"
            )

            capabilityNamesSection(
                title: String(localized: "Assigned MCP Servers"),
                names: assignment.assigned,
                emptyText: assignment.usesAllowlist
                    ? String(localized: "No MCP servers are explicitly assigned.")
                    : String(localized: "This agent inherits all currently available MCP servers.")
            ) { name in
                mcpServerStatus(name)
            }

            capabilityNamesSection(
                title: String(localized: "Available MCP Servers"),
                names: assignment.available,
                emptyText: String(localized: "No MCP servers are currently discoverable for this agent.")
            ) { name in
                mcpServerStatus(name)
            }
        } header: {
            Text("MCP Servers")
        } footer: {
            Text("This shows the MCP server scope that the daemon exposes to the agent after runtime discovery.")
        }
    }

    @ViewBuilder
    private func capabilityNamesSection(
        title: String,
        names: [String],
        emptyText: String,
        detail: @escaping (String) -> String?
    ) -> some View {
        if names.isEmpty {
            Text(emptyText)
                .foregroundStyle(.secondary)
        } else {
            ForEach(names.prefix(8), id: \.self) { name in
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.subheadline.weight(.medium))
                    if let detail = detail(name), !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            if names.count > 8 {
                Text(String(localized: "Showing 8 of \(names.count) items in \(title)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func mcpServerStatus(_ name: String) -> String {
        if connectedMCPServerNames.contains(name) {
            return String(localized: "Connected")
        }
        if configuredMCPServerNames.contains(name) {
            return String(localized: "Configured")
        }
        return String(localized: "Discovered")
    }

    @MainActor
    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            async let toolFilters = deps.apiClient.agentToolFilters(agentId: agent.id)
            async let skills = deps.apiClient.agentSkills(agentId: agent.id)
            async let mcpServers = deps.apiClient.agentMCPServers(agentId: agent.id)

            self.toolFilters = try await toolFilters
            self.skills = try await skills
            self.mcpServers = try await mcpServers
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct CapabilityDetailRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

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

            if hasLoadedAnything {
                Section {
                    CapabilitiesSnapshotCard(
                        toolFilters: toolFilters,
                        skills: skills,
                        mcpServers: mcpServers
                    )
                } header: {
                    Text("Snapshot")
                } footer: {
                    Text("This snapshot shows which capability feeds have loaded and how much access the agent currently has.")
                }

                Section {
                    MonitoringSurfaceGroupCard(
                        title: String(localized: "Primary Surfaces"),
                        detail: String(localized: "Keep the agent, profile, and runtime exits closest to compact capability inspection.")
                    ) {
                        NavigationLink {
                            AgentDetailView(agent: agent)
                        } label: {
                            MonitoringJumpRow(
                                title: String(localized: "Back To Agent"),
                                detail: String(localized: "Return to the full agent detail page with sessions, memory, files, and deliveries."),
                                systemImage: "cpu",
                                tone: .neutral
                            )
                        }

                        if let profile = agent.profile, !profile.isEmpty {
                            NavigationLink {
                                ToolProfilesView(selectedProfileName: profile)
                            } label: {
                                MonitoringJumpRow(
                                    title: String(localized: "Open Tool Profile"),
                                    detail: String(localized: "Switch to the profile definition that sits underneath these capability filters."),
                                    systemImage: "person.crop.rectangle.stack",
                                    tone: .neutral,
                                    badgeText: profile,
                                    badgeTone: .neutral
                                )
                            }
                        }

                        NavigationLink {
                            RuntimeView()
                        } label: {
                            MonitoringJumpRow(
                                title: String(localized: "Open Runtime"),
                                detail: String(localized: "Switch to runtime when capability scope needs broader MCP, provider, or approval context."),
                                systemImage: "server.rack",
                                tone: .neutral
                            )
                        }
                    }

                    MonitoringSurfaceGroupCard(
                        title: String(localized: "Supporting Surfaces"),
                        detail: String(localized: "Keep integration drift checks behind the primary capability exits.")
                    ) {
                        NavigationLink {
                            IntegrationsView(initialSearchText: agent.id, initialScope: .attention)
                        } label: {
                            MonitoringJumpRow(
                                title: String(localized: "Open Integrations"),
                                detail: String(localized: "Switch to integrations when capability scope looks healthy but model or channel drift remains."),
                                systemImage: "square.3.layers.3d.down.forward",
                                tone: .neutral
                            )
                        }
                    }
                } header: {
                    Text("Operator Surfaces")
                } footer: {
                    Text("Use these routes when capability scope needs profile, runtime, or integration context.")
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
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach(names.prefix(8), id: \.self) { name in
                CapabilityNameRow(name: name, detail: detail(name))
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

private struct CapabilitiesSnapshotCard: View {
    let toolFilters: AgentToolFilters?
    let skills: AgentAssignmentScope?
    let mcpServers: AgentAssignmentScope?

    var body: some View {
        MonitoringSnapshotCard(
            summary: String(localized: "Agent capability scope is loaded for quick review."),
            verticalPadding: 4
        ) {
            FlowLayout(spacing: 8) {
                snapshotBadge(
                    label: String(localized: "Tool Filters"),
                    isPresent: toolFilters != nil,
                    tone: toolFilters?.scopeTone ?? .neutral
                )
                snapshotBadge(
                    label: String(localized: "Skills"),
                    isPresent: skills != nil,
                    tone: skills?.scopeTone ?? .neutral
                )
                snapshotBadge(
                    label: String(localized: "MCP"),
                    isPresent: mcpServers != nil,
                    tone: mcpServers?.scopeTone ?? .neutral
                )

                if let toolFilters {
                    PresentationToneBadge(
                        text: toolFilters.toolAllowlist.isEmpty
                            ? String(localized: "Open tool access")
                            : String(localized: "\(toolFilters.toolAllowlist.count) allowed"),
                        tone: toolFilters.scopeTone
                    )
                }

                if let skills {
                    PresentationToneBadge(
                        text: skills.assigned.isEmpty
                            ? String(localized: "No assigned skills")
                            : String(localized: "\(skills.assigned.count) assigned skills"),
                        tone: skills.scopeTone
                    )
                }

                if let mcpServers {
                    PresentationToneBadge(
                        text: mcpServers.assigned.isEmpty
                            ? String(localized: "No assigned MCP")
                            : String(localized: "\(mcpServers.assigned.count) assigned MCP"),
                        tone: mcpServers.scopeTone
                    )
                }
            }
        }
    }

    private func snapshotBadge(label: String, isPresent: Bool, tone: PresentationTone) -> some View {
        PresentationToneBadge(
            text: isPresent ? label : String(localized: "\(label) missing"),
            tone: isPresent ? tone : .neutral
        )
    }
}

private struct CapabilityNameRow: View {
    let name: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct CapabilityDetailRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        ResponsiveValueRow(verticalSpacing: 6) {
            HStack(spacing: 12) {
                iconLabel
                Text(label)
            }
        } value: {
            valueLabel
        }
    }

    private var iconLabel: some View {
        Image(systemName: icon)
            .foregroundStyle(.secondary)
            .frame(width: 18)
    }

    private var valueLabel: some View {
        Text(value)
            .foregroundStyle(valueColor)
            .multilineTextAlignment(.leading)
            .lineLimit(3)
    }
}

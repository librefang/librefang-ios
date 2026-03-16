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

    private var capabilitiesPrimaryRouteCount: Int {
        2 + ((agent.profile?.isEmpty == false) ? 1 : 0)
    }

    private var capabilitiesSupportRouteCount: Int { 1 }

    private var loadedCapabilityFeedCount: Int {
        [toolFilters != nil, skills != nil, mcpServers != nil].filter { $0 }.count
    }

    private var capabilitiesSectionCount: Int {
        hasLoadedAnything ? (2 + loadedCapabilityFeedCount) : 1
    }
    private var capabilitiesSectionPreviewTitles: [String] {
        var sections: [String] = []
        if toolFilters != nil {
            sections.append(String(localized: "Tool Filters"))
        }
        if skills != nil {
            sections.append(String(localized: "Skills"))
        }
        if mcpServers != nil {
            sections.append(String(localized: "MCP Servers"))
        }
        return sections
    }
    private var toolRestrictionCount: Int {
        (toolFilters?.toolAllowlist.count ?? 0) + (toolFilters?.toolBlocklist.count ?? 0)
    }
    private var assignedSkillCount: Int {
        skills?.assigned.count ?? 0
    }
    private var assignedServerCount: Int {
        mcpServers?.assigned.count ?? 0
    }
    private var configuredAvailableServerCount: Int {
        mcpServers?.available.filter { configuredMCPServerNames.contains($0) }.count ?? 0
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
                    CapabilitiesSectionInventoryDeck(
                        sectionCount: capabilitiesSectionCount,
                        loadedFeedCount: loadedCapabilityFeedCount,
                        hasProfileRoute: agent.profile?.isEmpty == false,
                        hasToolFilters: toolFilters != nil,
                        hasSkills: skills != nil,
                        hasMCPServers: mcpServers != nil,
                        isRefreshingOnly: isRefreshing && hasLoadedAnything
                    )
                    if !capabilitiesSectionPreviewTitles.isEmpty {
                        MonitoringSectionPreviewDeck(
                            title: String(localized: "Section Preview"),
                            detail: String(localized: "Keep the next capability stacks visible before tool filters, skills, and MCP server sections open up."),
                            sectionTitles: capabilitiesSectionPreviewTitles,
                            tone: loadedCapabilityFeedCount > 0 ? .positive : .neutral,
                            maxVisibleSections: 5
                        )
                    }

                    CapabilitiesPressureCoverageDeck(
                        loadedFeedCount: loadedCapabilityFeedCount,
                        toolRestrictionCount: toolRestrictionCount,
                        assignedSkillCount: assignedSkillCount,
                        assignedServerCount: assignedServerCount,
                        configuredAvailableServerCount: configuredAvailableServerCount,
                        hasProfileRoute: agent.profile?.isEmpty == false,
                        isRefreshingOnly: isRefreshing && hasLoadedAnything
                    )
                    CapabilitiesSupportCoverageDeck(
                        loadedFeedCount: loadedCapabilityFeedCount,
                        toolRestrictionCount: toolRestrictionCount,
                        assignedSkillCount: assignedSkillCount,
                        assignedServerCount: assignedServerCount,
                        configuredAvailableServerCount: configuredAvailableServerCount,
                        hasProfileRoute: agent.profile?.isEmpty == false,
                        hasToolFilters: toolFilters != nil,
                        hasSkills: skills != nil,
                        hasMCPServers: mcpServers != nil,
                        isRefreshingOnly: isRefreshing && hasLoadedAnything
                    )

                    CapabilitiesFocusCoverageDeck(
                        loadedFeedCount: loadedCapabilityFeedCount,
                        toolRestrictionCount: toolRestrictionCount,
                        assignedSkillCount: assignedSkillCount,
                        assignedServerCount: assignedServerCount,
                        configuredAvailableServerCount: configuredAvailableServerCount,
                        hasProfileRoute: agent.profile?.isEmpty == false,
                        hasToolFilters: toolFilters != nil,
                        hasSkills: skills != nil,
                        hasMCPServers: mcpServers != nil,
                        isRefreshingOnly: isRefreshing && hasLoadedAnything
                    )
                    CapabilitiesWorkstreamCoverageDeck(
                        loadedFeedCount: loadedCapabilityFeedCount,
                        toolRestrictionCount: toolRestrictionCount,
                        assignedSkillCount: assignedSkillCount,
                        assignedServerCount: assignedServerCount,
                        configuredAvailableServerCount: configuredAvailableServerCount,
                        hasProfileRoute: agent.profile?.isEmpty == false,
                        hasToolFilters: toolFilters != nil,
                        hasSkills: skills != nil,
                        hasMCPServers: mcpServers != nil,
                        isRefreshingOnly: isRefreshing && hasLoadedAnything
                    )
                    CapabilitiesActionReadinessDeck(
                        primaryRouteCount: capabilitiesPrimaryRouteCount,
                        supportRouteCount: capabilitiesSupportRouteCount,
                        loadedFeedCount: loadedCapabilityFeedCount,
                        toolRestrictionCount: toolRestrictionCount,
                        assignedSkillCount: assignedSkillCount,
                        assignedServerCount: assignedServerCount,
                        configuredAvailableServerCount: configuredAvailableServerCount,
                        hasProfileRoute: agent.profile?.isEmpty == false,
                        hasToolFilters: toolFilters != nil,
                        hasSkills: skills != nil,
                        hasMCPServers: mcpServers != nil,
                        isRefreshingOnly: isRefreshing && hasLoadedAnything
                    )

                    CapabilitiesRouteInventoryDeck(
                        primaryRouteCount: capabilitiesPrimaryRouteCount,
                        supportRouteCount: capabilitiesSupportRouteCount,
                        loadedFeedCount: loadedCapabilityFeedCount,
                        hasProfileRoute: agent.profile?.isEmpty == false,
                        hasToolFilters: toolFilters != nil,
                        hasSkills: skills != nil,
                        hasMCPServers: mcpServers != nil
                    )

                    MonitoringSurfaceGroupCard(
                        title: String(localized: "Routes"),
                        detail: String(localized: "Keep nearby agent, profile, runtime, and integration exits closest to compact capability inspection.")
                    ) {
                        MonitoringShortcutRail(
                            title: String(localized: "Primary"),
                            detail: String(localized: "Use nearby agent, profile, and runtime surfaces first.")
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

                            if let profile = agent.profile, !profile.isEmpty {
                                NavigationLink {
                                    ToolProfilesView(selectedProfileName: profile)
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "Tool Profile"),
                                        systemImage: "person.crop.rectangle.stack",
                                        badgeText: profile
                                    )
                                }
                                .buttonStyle(.plain)
                            }

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

                        MonitoringShortcutRail(
                            title: String(localized: "Support"),
                            detail: String(localized: "Keep integration drift checks behind the primary capability exits.")
                        ) {
                            NavigationLink {
                                IntegrationsView(initialSearchText: agent.id, initialScope: .attention)
                            } label: {
                                MonitoringSurfaceShortcutChip(
                                    title: String(localized: "Integrations"),
                                    systemImage: "square.3.layers.3d.down.forward"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Routes")
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
        .monitoringRefreshInteractionGate(isRefreshing: isRefreshing)
        .refreshable {
            await refresh()
        }
        .task {
            await refresh()
        }
    }

    private func toolFiltersSection(_ filters: AgentToolFilters) -> some View {
        Section {
            ToolFiltersDeckCard(filters: filters)

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
            SkillsDeckCard(assignment: assignment)

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
            MCPServersDeckCard(
                assignment: assignment,
                connectedServerNames: connectedMCPServerNames,
                configuredServerNames: configuredMCPServerNames
            )

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

private struct CapabilitiesSectionInventoryDeck: View {
    let sectionCount: Int
    let loadedFeedCount: Int
    let hasProfileRoute: Bool
    let hasToolFilters: Bool
    let hasSkills: Bool
    let hasMCPServers: Bool
    let isRefreshingOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: isRefreshingOnly
                    ? String(localized: "Section coverage stays visible while capability feeds refresh in place.")
                    : String(localized: "Section coverage stays visible before routes and the loaded capability feeds."),
                detail: String(localized: "Use section coverage to confirm which capability feeds are available before pivoting into profile, runtime, or integration context."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: sectionCount == 1 ? String(localized: "1 section ready") : String(localized: "\(sectionCount) sections ready"),
                        tone: isRefreshingOnly ? .warning : .positive
                    )
                    PresentationToneBadge(
                        text: loadedFeedCount == 1 ? String(localized: "1 feed loaded") : String(localized: "\(loadedFeedCount) feeds loaded"),
                        tone: loadedFeedCount > 0 ? .positive : .neutral
                    )
                    if hasProfileRoute {
                        PresentationToneBadge(text: String(localized: "Profile linked"), tone: .positive)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Section Coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep snapshot, routes, and each loaded capability feed visible before drilling into tool, skill, or MCP scope."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: loadedFeedCount == 1 ? String(localized: "1 live feed") : String(localized: "\(loadedFeedCount) live feeds"),
                    tone: loadedFeedCount > 0 ? .positive : .neutral
                )
            } facts: {
                if hasToolFilters {
                    Label(String(localized: "Tool filters"), systemImage: "slider.horizontal.3")
                }
                if hasSkills {
                    Label(String(localized: "Skills"), systemImage: "sparkles")
                }
                if hasMCPServers {
                    Label(String(localized: "MCP"), systemImage: "shippingbox")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct CapabilitiesPressureCoverageDeck: View {
    let loadedFeedCount: Int
    let toolRestrictionCount: Int
    let assignedSkillCount: Int
    let assignedServerCount: Int
    let configuredAvailableServerCount: Int
    let hasProfileRoute: Bool
    let isRefreshingOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to separate tool restrictions, assigned skills, and MCP server scope before opening the capability feeds below."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if toolRestrictionCount > 0 {
                        PresentationToneBadge(
                            text: toolRestrictionCount == 1 ? String(localized: "1 tool rule") : String(localized: "\(toolRestrictionCount) tool rules"),
                            tone: .warning
                        )
                    }
                    if assignedSkillCount > 0 {
                        PresentationToneBadge(
                            text: assignedSkillCount == 1 ? String(localized: "1 assigned skill") : String(localized: "\(assignedSkillCount) assigned skills"),
                            tone: .positive
                        )
                    }
                    if assignedServerCount > 0 {
                        PresentationToneBadge(
                            text: assignedServerCount == 1 ? String(localized: "1 assigned server") : String(localized: "\(assignedServerCount) assigned servers"),
                            tone: .positive
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Pressure coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep restrictions, assigned capability scope, and MCP server coverage readable before the capability feeds take over."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: loadedFeedCount == 1 ? String(localized: "1 live feed") : String(localized: "\(loadedFeedCount) live feeds"),
                    tone: loadedFeedCount > 0 ? .positive : .neutral
                )
            } facts: {
                if configuredAvailableServerCount > 0 {
                    Label(
                        configuredAvailableServerCount == 1 ? String(localized: "1 configured server") : String(localized: "\(configuredAvailableServerCount) configured servers"),
                        systemImage: "shippingbox"
                    )
                }
                if hasProfileRoute {
                    Label(String(localized: "Profile linked"), systemImage: "person.crop.rectangle.stack")
                }
                if isRefreshingOnly {
                    Label(String(localized: "Refresh in progress"), systemImage: "arrow.clockwise")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if toolRestrictionCount > 0 || assignedServerCount > 0 {
            return String(localized: "Capability pressure is currently anchored by tool restrictions or explicit server scope.")
        }
        if assignedSkillCount > 0 {
            return String(localized: "Capability pressure is currently concentrated in assigned skill scope.")
        }
        return String(localized: "Capability pressure is currently low and mostly reflects feed readiness.")
    }
}

private struct CapabilitiesSupportCoverageDeck: View {
    let loadedFeedCount: Int
    let toolRestrictionCount: Int
    let assignedSkillCount: Int
    let assignedServerCount: Int
    let configuredAvailableServerCount: Int
    let hasProfileRoute: Bool
    let hasToolFilters: Bool
    let hasSkills: Bool
    let hasMCPServers: Bool
    let isRefreshingOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep linked profile support, loaded capability feeds, and assigned scope readable before drilling into tool, skill, and MCP details."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: loadedFeedCount == 1 ? String(localized: "1 live feed") : String(localized: "\(loadedFeedCount) live feeds"),
                        tone: loadedFeedCount > 0 ? .positive : .neutral
                    )
                    if hasProfileRoute {
                        PresentationToneBadge(text: String(localized: "Profile linked"), tone: .positive)
                    }
                    if isRefreshingOnly {
                        PresentationToneBadge(text: String(localized: "Refreshing"), tone: .warning)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Support coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep linked profile context, explicit rules, and assigned skill or server support readable before leaving capability scope."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: configuredAvailableServerCount == 1 ? String(localized: "1 configured server") : String(localized: "\(configuredAvailableServerCount) configured servers"),
                    tone: configuredAvailableServerCount > 0 ? .positive : .neutral
                )
            } facts: {
                if toolRestrictionCount > 0 {
                    Label(
                        toolRestrictionCount == 1 ? String(localized: "1 tool rule") : String(localized: "\(toolRestrictionCount) tool rules"),
                        systemImage: "slider.horizontal.3"
                    )
                }
                if assignedSkillCount > 0 {
                    Label(
                        assignedSkillCount == 1 ? String(localized: "1 assigned skill") : String(localized: "\(assignedSkillCount) assigned skills"),
                        systemImage: "sparkles"
                    )
                }
                if assignedServerCount > 0 {
                    Label(
                        assignedServerCount == 1 ? String(localized: "1 assigned server") : String(localized: "\(assignedServerCount) assigned servers"),
                        systemImage: "server.rack"
                    )
                }
                if hasToolFilters {
                    Label(String(localized: "Tool filters loaded"), systemImage: "checkmark.circle")
                }
                if hasSkills {
                    Label(String(localized: "Skills loaded"), systemImage: "wand.and.stars")
                }
                if hasMCPServers {
                    Label(String(localized: "MCP loaded"), systemImage: "shippingbox.fill")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if isRefreshingOnly {
            return String(localized: "Capability support coverage is currently waiting on refreshed feed state.")
        }
        if assignedServerCount > 0 || configuredAvailableServerCount > 0 {
            return String(localized: "Capability support coverage is currently anchored by MCP server scope and connected support.")
        }
        if toolRestrictionCount > 0 || assignedSkillCount > 0 {
            return String(localized: "Capability support coverage is currently anchored by explicit tool and skill scope.")
        }
        if hasToolFilters || hasSkills || hasMCPServers {
            return String(localized: "Capability support coverage is currently anchored by loaded capability feeds.")
        }
        return String(localized: "Capability support coverage is currently light across the visible feeds.")
    }
}

private struct CapabilitiesFocusCoverageDeck: View {
    let loadedFeedCount: Int
    let toolRestrictionCount: Int
    let assignedSkillCount: Int
    let assignedServerCount: Int
    let configuredAvailableServerCount: Int
    let hasProfileRoute: Bool
    let hasToolFilters: Bool
    let hasSkills: Bool
    let hasMCPServers: Bool
    let isRefreshingOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep the dominant capability lane visible before moving from compact capability decks into tool, skill, and MCP detail."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: loadedFeedCount == 1 ? String(localized: "1 live feed") : String(localized: "\(loadedFeedCount) live feeds"),
                        tone: loadedFeedCount > 0 ? .positive : .neutral
                    )
                    if hasProfileRoute {
                        PresentationToneBadge(text: String(localized: "Profile linked"), tone: .positive)
                    }
                    if isRefreshingOnly {
                        PresentationToneBadge(text: String(localized: "Refreshing"), tone: .warning)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Focus coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the dominant capability lane readable before drilling into explicit tool rules, assigned skills, or MCP server scope."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: configuredAvailableServerCount == 1 ? String(localized: "1 configured server") : String(localized: "\(configuredAvailableServerCount) configured servers"),
                    tone: configuredAvailableServerCount > 0 ? .positive : .neutral
                )
            } facts: {
                if toolRestrictionCount > 0 {
                    Label(
                        toolRestrictionCount == 1 ? String(localized: "1 tool rule") : String(localized: "\(toolRestrictionCount) tool rules"),
                        systemImage: "slider.horizontal.3"
                    )
                }
                if assignedSkillCount > 0 {
                    Label(
                        assignedSkillCount == 1 ? String(localized: "1 assigned skill") : String(localized: "\(assignedSkillCount) assigned skills"),
                        systemImage: "sparkles"
                    )
                }
                if assignedServerCount > 0 {
                    Label(
                        assignedServerCount == 1 ? String(localized: "1 assigned server") : String(localized: "\(assignedServerCount) assigned servers"),
                        systemImage: "shippingbox"
                    )
                }
                if hasToolFilters {
                    Label(String(localized: "Tool filters loaded"), systemImage: "checkmark.circle")
                }
                if hasSkills {
                    Label(String(localized: "Skills loaded"), systemImage: "wand.and.stars")
                }
                if hasMCPServers {
                    Label(String(localized: "MCP loaded"), systemImage: "shippingbox.fill")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if toolRestrictionCount > 0 || assignedServerCount > 0 {
            return String(localized: "Capability focus coverage is currently anchored by explicit tool rules and server scope.")
        }
        if assignedSkillCount > 0 {
            return String(localized: "Capability focus coverage is currently anchored by assigned skill scope.")
        }
        if isRefreshingOnly {
            return String(localized: "Capability focus coverage is currently waiting on refreshed feed state.")
        }
        return String(localized: "Capability focus coverage is currently balanced across loaded tool, skill, and MCP feeds.")
    }
}

private struct CapabilitiesWorkstreamCoverageDeck: View {
    let loadedFeedCount: Int
    let toolRestrictionCount: Int
    let assignedSkillCount: Int
    let assignedServerCount: Int
    let configuredAvailableServerCount: Int
    let hasProfileRoute: Bool
    let hasToolFilters: Bool
    let hasSkills: Bool
    let hasMCPServers: Bool
    let isRefreshingOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to see whether capability review is currently led by explicit restrictions, assigned scope, or feed readiness before drilling into detailed capability sections."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: loadedFeedCount == 1 ? String(localized: "1 live feed") : String(localized: "\(loadedFeedCount) live feeds"),
                        tone: loadedFeedCount > 0 ? .positive : .neutral
                    )
                    if hasProfileRoute {
                        PresentationToneBadge(text: String(localized: "Profile linked"), tone: .positive)
                    }
                    if isRefreshingOnly {
                        PresentationToneBadge(text: String(localized: "Refreshing"), tone: .warning)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Workstream coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep explicit restrictions, assigned skill or MCP scope, and feed readiness readable before moving through tool, skill, and server detail."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: configuredAvailableServerCount == 1 ? String(localized: "1 configured server") : String(localized: "\(configuredAvailableServerCount) configured servers"),
                    tone: configuredAvailableServerCount > 0 ? .positive : .neutral
                )
            } facts: {
                if toolRestrictionCount > 0 {
                    Label(
                        toolRestrictionCount == 1 ? String(localized: "1 tool rule") : String(localized: "\(toolRestrictionCount) tool rules"),
                        systemImage: "slider.horizontal.3"
                    )
                }
                if assignedSkillCount > 0 {
                    Label(
                        assignedSkillCount == 1 ? String(localized: "1 assigned skill") : String(localized: "\(assignedSkillCount) assigned skills"),
                        systemImage: "sparkles"
                    )
                }
                if assignedServerCount > 0 {
                    Label(
                        assignedServerCount == 1 ? String(localized: "1 assigned server") : String(localized: "\(assignedServerCount) assigned servers"),
                        systemImage: "server.rack"
                    )
                }
                if isRefreshingOnly {
                    Label(String(localized: "Refresh in progress"), systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var summaryLine: String {
        if toolRestrictionCount > 0 || assignedServerCount > 0 {
            return String(localized: "Capabilities workstream coverage is currently anchored by explicit restrictions and server scope.")
        }
        if assignedSkillCount > 0 {
            return String(localized: "Capabilities workstream coverage is currently anchored by assigned skill scope.")
        }
        if hasToolFilters || hasSkills || hasMCPServers {
            return String(localized: "Capabilities workstream coverage is currently anchored by loaded capability feeds.")
        }
        return String(localized: "Capabilities workstream coverage is currently light across the visible feeds.")
    }
}

private struct CapabilitiesActionReadinessDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let loadedFeedCount: Int
    let toolRestrictionCount: Int
    let assignedSkillCount: Int
    let assignedServerCount: Int
    let configuredAvailableServerCount: Int
    let hasProfileRoute: Bool
    let hasToolFilters: Bool
    let hasSkills: Bool
    let hasMCPServers: Bool
    let isRefreshingOnly: Bool

    private var totalRouteCount: Int {
        primaryRouteCount + supportRouteCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to check route breadth, feed readiness, and explicit capability scope before drilling into tool, skill, and MCP sections."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: totalRouteCount == 1 ? String(localized: "1 route ready") : String(localized: "\(totalRouteCount) routes ready"),
                        tone: totalRouteCount > 0 ? .positive : .neutral
                    )
                    if hasProfileRoute {
                        PresentationToneBadge(text: String(localized: "Profile linked"), tone: .positive)
                    }
                    if isRefreshingOnly {
                        PresentationToneBadge(text: String(localized: "Refreshing"), tone: .warning)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Action readiness"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep route breadth, loaded feeds, and explicit capability scope readable before leaving the compact capability monitor for surrounding operator surfaces."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: loadedFeedCount == 1 ? String(localized: "1 live feed") : String(localized: "\(loadedFeedCount) live feeds"),
                    tone: loadedFeedCount > 0 ? .positive : .neutral
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
                if toolRestrictionCount > 0 {
                    Label(
                        toolRestrictionCount == 1 ? String(localized: "1 tool rule") : String(localized: "\(toolRestrictionCount) tool rules"),
                        systemImage: "slider.horizontal.3"
                    )
                }
                if assignedSkillCount > 0 {
                    Label(
                        assignedSkillCount == 1 ? String(localized: "1 assigned skill") : String(localized: "\(assignedSkillCount) assigned skills"),
                        systemImage: "sparkles"
                    )
                }
                if assignedServerCount > 0 {
                    Label(
                        assignedServerCount == 1 ? String(localized: "1 assigned server") : String(localized: "\(assignedServerCount) assigned servers"),
                        systemImage: "shippingbox"
                    )
                } else if configuredAvailableServerCount > 0 {
                    Label(
                        configuredAvailableServerCount == 1 ? String(localized: "1 configured server") : String(localized: "\(configuredAvailableServerCount) configured servers"),
                        systemImage: "server.rack"
                    )
                }
                if hasToolFilters || hasSkills || hasMCPServers {
                    Label(String(localized: "Capability feeds loaded"), systemImage: "checkmark.circle")
                }
            }
        }
    }

    private var summaryLine: String {
        if isRefreshingOnly {
            return String(localized: "Capabilities action readiness is currently waiting on refreshed feed state.")
        }
        if toolRestrictionCount > 0 || assignedServerCount > 0 {
            return String(localized: "Capabilities action readiness is currently anchored by explicit tool rules and server scope.")
        }
        if assignedSkillCount > 0 {
            return String(localized: "Capabilities action readiness is currently anchored by assigned skill scope.")
        }
        return String(localized: "Capabilities action readiness is currently clear enough for route pivots and deeper capability drilldown.")
    }
}

private struct CapabilitiesRouteInventoryDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let loadedFeedCount: Int
    let hasProfileRoute: Bool
    let hasToolFilters: Bool
    let hasSkills: Bool
    let hasMCPServers: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Capability routes stay compact before the adjacent agent, runtime, and integration drilldowns."),
                detail: String(localized: "Use the route inventory to gauge loaded capability feeds before leaving the capability scope view."),
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
                    PresentationToneBadge(
                        text: loadedFeedCount == 1 ? String(localized: "1 capability feed loaded") : String(localized: "\(loadedFeedCount) capability feeds loaded"),
                        tone: loadedFeedCount > 0 ? .positive : .neutral
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Route Facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep route availability and feed coverage visible before pivoting into tool profiles, runtime, or integration context."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if hasProfileRoute {
                    PresentationToneBadge(text: String(localized: "Profile route ready"), tone: .positive)
                }
            } facts: {
                if hasToolFilters {
                    Label(String(localized: "Tool filters loaded"), systemImage: "slider.horizontal.3")
                }
                if hasSkills {
                    Label(String(localized: "Skills loaded"), systemImage: "sparkles")
                }
                if hasMCPServers {
                    Label(String(localized: "MCP loaded"), systemImage: "shippingbox")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ToolFiltersDeckCard: View {
    let filters: AgentToolFilters

    private var visibleRuleCount: Int {
        filters.toolAllowlist.count + filters.toolBlocklist.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Tool filter scope stays compact before the detailed allowlist and blocklist rows."),
                detail: String(localized: "Use the compact deck to confirm open access versus restricted mode before inspecting specific tool rules."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: filters.scopeLabel, tone: filters.scopeTone)
                    PresentationToneBadge(
                        text: filters.toolAllowlist.isEmpty ? String(localized: "No allowlist") : String(localized: "\(filters.toolAllowlist.count) allowed"),
                        tone: filters.toolAllowlist.isEmpty ? .neutral : .positive
                    )
                    PresentationToneBadge(
                        text: filters.toolBlocklist.isEmpty ? String(localized: "No blocklist") : String(localized: "\(filters.toolBlocklist.count) blocked"),
                        tone: filters.toolBlocklist.isEmpty ? .neutral : .warning
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Tool Filter Facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep rule depth and access mode visible before opening individual allowed or blocked tool names."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleRuleCount == 1 ? String(localized: "1 explicit rule") : String(localized: "\(visibleRuleCount) explicit rules"),
                    tone: visibleRuleCount > 0 ? .warning : .neutral
                )
            } facts: {
                Label(
                    filters.toolAllowlist.count == 1 ? String(localized: "1 allowed tool") : String(localized: "\(filters.toolAllowlist.count) allowed tools"),
                    systemImage: "checkmark.circle"
                )
                Label(
                    filters.toolBlocklist.count == 1 ? String(localized: "1 blocked tool") : String(localized: "\(filters.toolBlocklist.count) blocked tools"),
                    systemImage: "nosign"
                )
            }
        }
    }
}

private struct SkillsDeckCard: View {
    let assignment: AgentAssignmentScope

    private var inheritedCount: Int {
        max(assignment.available.count - assignment.assigned.count, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Skill scope stays compact before the assigned skill list."),
                detail: String(localized: "Use the compact deck to confirm allowlist mode and inherited coverage before opening the full skill assignment list."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: assignment.scopeLabel(openAccessLabel: String(localized: "All skills")),
                        tone: assignment.scopeTone
                    )
                    PresentationToneBadge(
                        text: assignment.assigned.count == 1 ? String(localized: "1 assigned skill") : String(localized: "\(assignment.assigned.count) assigned skills"),
                        tone: assignment.assigned.isEmpty ? .neutral : .positive
                    )
                    PresentationToneBadge(
                        text: assignment.available.count == 1 ? String(localized: "1 available skill") : String(localized: "\(assignment.available.count) available skills"),
                        tone: .neutral
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Skill Scope Facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep assigned, available, and inherited skill coverage visible before opening individual skill names."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if !assignment.usesAllowlist {
                    PresentationToneBadge(
                        text: inheritedCount == 1 ? String(localized: "1 inherited skill") : String(localized: "\(inheritedCount) inherited skills"),
                        tone: .positive
                    )
                }
            } facts: {
                Label(
                    assignment.assigned.count == 1 ? String(localized: "1 assigned skill") : String(localized: "\(assignment.assigned.count) assigned skills"),
                    systemImage: "sparkles"
                )
                Label(
                    assignment.available.count == 1 ? String(localized: "1 visible skill") : String(localized: "\(assignment.available.count) visible skills"),
                    systemImage: "square.stack.3d.up"
                )
            }
        }
    }
}

private struct MCPServersDeckCard: View {
    let assignment: AgentAssignmentScope
    let connectedServerNames: Set<String>
    let configuredServerNames: Set<String>

    private var connectedAssignedCount: Int {
        assignment.assigned.filter { connectedServerNames.contains($0) }.count
    }

    private var configuredAvailableCount: Int {
        assignment.available.filter { configuredServerNames.contains($0) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "MCP scope stays compact before the assigned and available server lists."),
                detail: String(localized: "Use the compact deck to confirm connected coverage and allowlist mode before opening the detailed MCP server inventory."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: assignment.scopeLabel(openAccessLabel: String(localized: "All connected servers")),
                        tone: assignment.scopeTone
                    )
                    PresentationToneBadge(
                        text: assignment.assigned.count == 1 ? String(localized: "1 assigned server") : String(localized: "\(assignment.assigned.count) assigned servers"),
                        tone: assignment.assigned.isEmpty ? .neutral : .positive
                    )
                    PresentationToneBadge(
                        text: assignment.available.count == 1 ? String(localized: "1 available server") : String(localized: "\(assignment.available.count) available servers"),
                        tone: .neutral
                    )
                    if connectedAssignedCount > 0 {
                        PresentationToneBadge(
                            text: connectedAssignedCount == 1 ? String(localized: "1 connected assignment") : String(localized: "\(connectedAssignedCount) connected assignments"),
                            tone: .positive
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "MCP Scope Facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep assigned server count, connected coverage, and configured availability visible before opening individual MCP rows."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if configuredAvailableCount > 0 {
                    PresentationToneBadge(
                        text: configuredAvailableCount == 1 ? String(localized: "1 configured server") : String(localized: "\(configuredAvailableCount) configured servers"),
                        tone: .neutral
                    )
                }
            } facts: {
                Label(
                    assignment.assigned.count == 1 ? String(localized: "1 assigned server") : String(localized: "\(assignment.assigned.count) assigned servers"),
                    systemImage: "shippingbox"
                )
                Label(
                    assignment.available.count == 1 ? String(localized: "1 discoverable server") : String(localized: "\(assignment.available.count) discoverable servers"),
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                if connectedAssignedCount > 0 {
                    Label(
                        connectedAssignedCount == 1 ? String(localized: "1 connected assignment") : String(localized: "\(connectedAssignedCount) connected assignments"),
                        systemImage: "checkmark.rectangle.stack"
                    )
                }
            }
        }
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

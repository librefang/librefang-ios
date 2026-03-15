import SwiftUI

internal enum IntegrationsModelFilter: String, CaseIterable, Identifiable {
    case available
    case all
    case unavailable

    var id: String { rawValue }

    var label: String {
        switch self {
        case .available:
            String(localized: "Available")
        case .all:
            String(localized: "All")
        case .unavailable:
            String(localized: "Unavailable")
        }
    }
}

internal enum IntegrationsScope: String, CaseIterable, Identifiable {
    case attention
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .attention:
            String(localized: "Attention")
        case .all:
            String(localized: "All")
        }
    }
}

private enum IntegrationsSectionAnchor: Hashable {
    case providers
    case channels
    case models
    case aliases
    case drift
}

struct IntegrationsView: View {
    @Environment(\.dependencies) private var deps
    @State private var searchText = ""
    @State private var scope: IntegrationsScope = .attention
    @State private var modelFilter: IntegrationsModelFilter = .available
    @State private var providerProbeResults: [String: IntegrationProbeResult] = [:]
    @State private var channelProbeResults: [String: IntegrationProbeResult] = [:]
    @State private var providerProbeInFlightID: String?
    @State private var channelProbeInFlightID: String?
    @State private var operatorNotice: OperatorActionNotice?

    private var vm: DashboardViewModel { deps.dashboardViewModel }

    internal init(
        initialSearchText: String = "",
        initialScope: IntegrationsScope = .attention,
        initialModelFilter: IntegrationsModelFilter = .available
    ) {
        _searchText = State(initialValue: initialSearchText)
        _scope = State(initialValue: initialScope)
        _modelFilter = State(initialValue: initialModelFilter)
    }

    private var filteredProviders: [ProviderStatus] {
        vm.providers
            .filter { provider in
                guard scope == .attention else { return true }
                return (provider.isLocal == true && provider.reachable == false)
                    || ((provider.error ?? "").isEmpty == false)
            }
            .filter { provider in
                guard !normalizedSearchText.isEmpty else { return true }
                let haystack = [
                    provider.displayName,
                    provider.id,
                    provider.baseURL ?? "",
                    provider.apiKeyEnv ?? "",
                    provider.error ?? "",
                    provider.discoveredModels?.joined(separator: " ") ?? ""
                ]
                    .joined(separator: " ")
                    .lowercased()
                return haystack.contains(normalizedSearchText)
            }
            .sorted { lhs, rhs in
                if providerRank(lhs) != providerRank(rhs) {
                    return providerRank(lhs) > providerRank(rhs)
                }
                return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
            }
    }

    private var filteredChannels: [ChannelStatus] {
        vm.channels
            .filter { channel in
                guard scope == .attention else { return true }
                let requiredFields = channel.fields?.filter(\.required) ?? []
                return requiredFields.contains(where: { !$0.hasValue })
            }
            .filter { channel in
                guard !normalizedSearchText.isEmpty else { return true }
                let haystack = [
                    channel.displayName,
                    channel.name,
                    channel.category,
                    channel.description,
                    channel.setupType,
                    channel.fields?.map(\.label).joined(separator: " ") ?? ""
                ]
                    .joined(separator: " ")
                    .lowercased()
                return haystack.contains(normalizedSearchText)
            }
            .sorted { lhs, rhs in
                if channelRank(lhs) != channelRank(rhs) {
                    return channelRank(lhs) > channelRank(rhs)
                }
                return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
            }
    }

    private var filteredModels: [CatalogModel] {
        vm.catalogModels
            .filter { model in
                if scope == .attention {
                    return !model.available
                }
                switch modelFilter {
                case .available:
                    return model.available
                case .all:
                    return true
                case .unavailable:
                    return !model.available
                }
            }
            .filter { model in
                guard !normalizedSearchText.isEmpty else { return true }
                let haystack = [
                    model.displayName,
                    model.id,
                    model.provider,
                    model.tier
                ]
                    .joined(separator: " ")
                    .lowercased()
                return haystack.contains(normalizedSearchText)
            }
            .sorted { lhs, rhs in
                if lhs.available != rhs.available {
                    return lhs.available && !rhs.available
                }
                if lhs.provider != rhs.provider {
                    return lhs.provider.localizedCompare(rhs.provider) == .orderedAscending
                }
                return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
            }
    }

    private var filteredAliases: [ModelAliasEntry] {
        guard scope == .all else { return [] }
        return vm.modelAliases
            .filter { alias in
                guard !normalizedSearchText.isEmpty else { return true }
                return "\(alias.alias) \(alias.modelId)".lowercased().contains(normalizedSearchText)
            }
            .sorted { lhs, rhs in
                lhs.alias.localizedCompare(rhs.alias) == .orderedAscending
            }
    }

    private var filteredAgentDiagnostics: [AgentModelDiagnostic] {
        vm.agentsWithModelDiagnostics
            .filter { diagnostic in
                guard !normalizedSearchText.isEmpty else { return true }
                let haystack = [
                    diagnostic.agent.name,
                    diagnostic.agent.id,
                    diagnostic.requestedModel,
                    diagnostic.resolvedModel?.id ?? "",
                    diagnostic.resolvedAlias?.alias ?? "",
                    diagnostic.issueSummary,
                    diagnostic.detail
                ]
                .joined(separator: " ")
                .lowercased()
                return haystack.contains(normalizedSearchText)
            }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var hasAnyContent: Bool {
        !vm.providers.isEmpty || !vm.channels.isEmpty || !vm.catalogModels.isEmpty || !vm.modelAliases.isEmpty || !vm.agentsWithModelDiagnostics.isEmpty
    }

    private var visibleResultCount: Int {
        filteredProviders.count
            + filteredChannels.count
            + filteredModels.count
            + filteredAliases.count
            + filteredAgentDiagnostics.count
    }
    private var providerAttentionCount: Int { vm.unreachableLocalProviderCount }
    private var channelAttentionCount: Int { vm.channelRequiredFieldGapCount }
    private var modelAttentionCount: Int { vm.unavailableCatalogModelCount }
    private var driftAttentionCount: Int { vm.agentsWithModelDiagnostics.count }

    private var scopeSummaryLine: String {
        scope == .attention
            ? String(localized: "Attention mode focuses on outages, field gaps, unavailable models, and agent drift.")
            : String(localized: "All mode keeps the full provider, channel, model, and alias inventory visible on mobile.")
    }

    private var searchSummaryLine: String {
        if normalizedSearchText.isEmpty {
            return String(localized: "Search providers, channels, models, aliases, or agent drift from one place.")
        }
        return String(localized: "\(visibleResultCount) integration results visible for \"\(searchText)\".")
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    IntegrationsScoreboard(vm: vm)
                        .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
                }

                Section {
                    MonitoringFilterCard(summary: scopeSummaryLine, detail: searchSummaryLine) {
                        PresentationToneBadge(
                            text: scope.label,
                            tone: scope == .attention ? .warning : .neutral
                        )
                    } controls: {
                        FlowLayout(spacing: 8) {
                            ForEach(IntegrationsScope.allCases) { candidate in
                                Button {
                                    scope = candidate
                                } label: {
                                    SelectableCapsuleBadge(text: candidate.label, isSelected: scope == candidate)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } footer: {
                    Text(
                        scope == .attention
                            ? String(localized: "Attention mode shows only provider outages, channel field gaps, unavailable models, and agent drift.")
                            : String(localized: "All mode shows the full provider, channel, model, and alias inventory.")
                    )
                }

                Section {
                    MonitoringFactsRow {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "Operator snapshot"))
                                .font(.subheadline.weight(.medium))
                            Text(String(localized: "Keep provider, channel, catalog, and agent-drift counts visible before diving into the inventory."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    } accessory: {
                        PresentationToneBadge(
                            text: scope.label,
                            tone: scope == .attention ? .warning : .neutral
                        )
                    } facts: {
                        Label(
                            providerAttentionCount == 1 ? String(localized: "1 provider issue") : String(localized: "\(providerAttentionCount) provider issues"),
                            systemImage: "key.horizontal"
                        )
                        Label(
                            channelAttentionCount == 1 ? String(localized: "1 channel gap") : String(localized: "\(channelAttentionCount) channel gaps"),
                            systemImage: "bubble.left.and.bubble.right"
                        )
                        Label(
                            modelAttentionCount == 1 ? String(localized: "1 unavailable model") : String(localized: "\(modelAttentionCount) unavailable models"),
                            systemImage: "square.stack.3d.up"
                        )
                        Label(
                            driftAttentionCount == 1 ? String(localized: "1 drifted agent") : String(localized: "\(driftAttentionCount) drifted agents"),
                            systemImage: "cpu"
                        )
                    }
                } footer: {
                    Text("This compact snapshot keeps the highest-signal integration counts visible on mobile.")
                }

                if vm.catalogStatus != nil || !vm.catalogModels.isEmpty {
                    Section {
                        IntegrationCatalogStatusCard(vm: vm)
                    } header: {
                        Text("Catalog Sync")
                    } footer: {
                        Text("LibreFang syncs the model catalog on startup and then in the background every 24 hours.")
                    }
                }

                if !vm.catalogModels.isEmpty && scope == .all {
                    Section {
                        MonitoringFilterCard(
                            summary: String(localized: "Model filter keeps the catalog focused without hiding the broader provider and channel diagnostics."),
                            detail: filteredModels.isEmpty
                                ? String(localized: "No catalog models match the current filter.")
                                : String(localized: "\(filteredModels.count) catalog models visible in \(modelFilter.label.lowercased()) mode.")
                        ) {
                            PresentationToneBadge(
                                text: modelFilter.label,
                                tone: modelFilter == .unavailable ? .warning : .neutral
                            )
                        } controls: {
                            FlowLayout(spacing: 8) {
                                ForEach(IntegrationsModelFilter.allCases) { filter in
                                    Button {
                                        modelFilter = filter
                                    } label: {
                                        SelectableCapsuleBadge(text: filter.label, isSelected: modelFilter == filter)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } header: {
                        Text("Model Filter")
                    } footer: {
                        Text("The catalog comes from LibreFang's model registry, including discovered local models and aliases.")
                    }
                }

                if hasAnyContent {
                    Section {
                        integrationsFocusSection(proxy)
                    } header: {
                        Text("Focus Areas")
                    } footer: {
                        Text("Use these jump targets to move through the compact integrations monitor instead of scrolling the full inventory.")
                    }

                    Section {
                        IntegrationSurfaceGroup(
                            title: String(localized: "Primary Surfaces"),
                            detail: String(localized: "Keep the next operator exits closest to provider, channel, and drift inventory.")
                        ) {
                            NavigationLink {
                                RuntimeView()
                            } label: {
                                MonitoringJumpRow(
                                    title: String(localized: "Open Runtime"),
                                    detail: String(localized: "Switch back to runtime with integration pressure folded into the main operator monitor."),
                                    systemImage: "server.rack",
                                    tone: vm.integrationPressureIssueCategoryCount > 0 ? .critical : .neutral,
                                    badgeText: vm.integrationPressureIssueCategoryCount > 0
                                        ? (vm.integrationPressureIssueCategoryCount == 1 ? String(localized: "1 issue") : String(localized: "\(vm.integrationPressureIssueCategoryCount) issues"))
                                        : nil,
                                    badgeTone: .critical
                                )
                            }

                            NavigationLink {
                                DiagnosticsView()
                            } label: {
                                MonitoringJumpRow(
                                    title: String(localized: "Open Diagnostics"),
                                    detail: String(localized: "Switch to diagnostics when model or provider drift may reflect health or config trouble."),
                                    systemImage: "stethoscope",
                                    tone: vm.diagnosticsSummaryTone,
                                    badgeText: vm.diagnosticsConfigWarningCount > 0
                                        ? (vm.diagnosticsConfigWarningCount == 1 ? String(localized: "1 warning") : String(localized: "\(vm.diagnosticsConfigWarningCount) warnings"))
                                        : nil,
                                    badgeTone: .warning
                                )
                            }

                            NavigationLink {
                                IncidentsView()
                            } label: {
                                MonitoringJumpRow(
                                    title: String(localized: "Open Incidents"),
                                    detail: String(localized: "Switch to incidents when integration drift has already surfaced in the mobile queue."),
                                    systemImage: "bell.badge",
                                    tone: vm.integrationPressureIssueCategoryCount > 0 ? .critical : .neutral,
                                    badgeText: driftAttentionCount > 0
                                        ? (driftAttentionCount == 1 ? String(localized: "1 drift item") : String(localized: "\(driftAttentionCount) drift items"))
                                        : nil,
                                    badgeTone: .warning
                                )
                            }

                            NavigationLink {
                                AgentsView()
                            } label: {
                                MonitoringJumpRow(
                                    title: String(localized: "Open Agents"),
                                    detail: String(localized: "Switch to fleet view when model drift or provider mismatch clusters around specific agents."),
                                    systemImage: "person.3",
                                    tone: driftAttentionCount > 0 ? .warning : .neutral,
                                    badgeText: driftAttentionCount > 0
                                        ? (driftAttentionCount == 1 ? String(localized: "1 drifted agent") : String(localized: "\(driftAttentionCount) drifted agents"))
                                        : nil,
                                    badgeTone: .warning
                                )
                            }
                        }

                        IntegrationSurfaceGroup(
                            title: String(localized: "Supporting Surfaces"),
                            detail: String(localized: "Keep slower spend, automation, and routing drilldowns behind the primary exits.")
                        ) {
                            NavigationLink {
                                AutomationView(initialScope: .attention)
                            } label: {
                                MonitoringJumpRow(
                                    title: String(localized: "Open Automation"),
                                    detail: String(localized: "Switch to workflow pressure when provider or model drift may be breaking scheduled work."),
                                    systemImage: "flowchart",
                                    tone: vm.automationPressureIssueCategoryCount > 0 ? .warning : .neutral,
                                    badgeText: vm.automationPressureIssueCategoryCount > 0
                                        ? (vm.automationPressureIssueCategoryCount == 1 ? String(localized: "1 automation issue") : String(localized: "\(vm.automationPressureIssueCategoryCount) automation issues"))
                                        : nil,
                                    badgeTone: .warning
                                )
                            }

                            NavigationLink {
                                BudgetView()
                            } label: {
                                MonitoringJumpRow(
                                    title: String(localized: "Open Budget"),
                                    detail: String(localized: "Switch to spend limits and model cost concentration when integration drift may already be showing up in usage."),
                                    systemImage: "chart.bar",
                                    tone: .neutral
                                )
                            }

                            NavigationLink {
                                CommsView(api: deps.apiClient)
                            } label: {
                                MonitoringJumpRow(
                                    title: String(localized: "Open Comms"),
                                    detail: String(localized: "Switch to live inter-agent traffic when provider or channel drift may reflect routing behavior."),
                                    systemImage: "point.3.connected.trianglepath.dotted",
                                    tone: .neutral
                                )
                            }
                        }
                    } header: {
                        Text("Operator Surfaces")
                    } footer: {
                        Text("Use these routes when provider, channel, model, or drift diagnostics need runtime, incident, or fleet context.")
                    }
                }

                if !filteredProviders.isEmpty {
                    Section {
                        ForEach(filteredProviders) { provider in
                            IntegrationProviderRow(
                                provider: provider,
                                probeResult: providerProbeResults[provider.id],
                                isTesting: providerProbeInFlightID == provider.id,
                                onTest: {
                                    Task { await testProvider(provider) }
                                }
                            )
                        }
                    } header: {
                        Text("Providers")
                    } footer: {
                        Text("Remote providers surface auth readiness. Local providers also surface probe reachability, latency, and discovered models.")
                    }
                    .id(IntegrationsSectionAnchor.providers)
                }

                if !filteredChannels.isEmpty {
                    Section {
                        ForEach(filteredChannels) { channel in
                            IntegrationChannelRow(
                                channel: channel,
                                probeResult: channelProbeResults[channel.id],
                                isTesting: channelProbeInFlightID == channel.id,
                                onTest: {
                                    Task { await testChannel(channel) }
                                }
                            )
                        }
                    } header: {
                        Text("Channels")
                    } footer: {
                        Text("Channel diagnostics only run credential validation unless the server receives a specific target channel or chat ID.")
                    }
                    .id(IntegrationsSectionAnchor.channels)
                }

                if !filteredModels.isEmpty {
                    Section {
                        ForEach(filteredModels.prefix(40)) { model in
                            IntegrationModelRow(model: model)
                        }
                    } header: {
                        Text("Models")
                    } footer: {
                        if filteredModels.count > 40 {
                            Text("Showing 40 of \(filteredModels.count) catalog models after filtering.")
                        } else {
                            Text("\(filteredModels.count) models visible after filtering.")
                        }
                    }
                    .id(IntegrationsSectionAnchor.models)
                }

                if !filteredAliases.isEmpty {
                    Section {
                        ForEach(filteredAliases.prefix(20)) { alias in
                            IntegrationAliasRow(alias: alias)
                        }
                    } header: {
                        Text("Aliases")
                    } footer: {
                        if filteredAliases.count > 20 {
                            Text("Showing 20 of \(filteredAliases.count) aliases after filtering.")
                        }
                    }
                    .id(IntegrationsSectionAnchor.aliases)
                }

                if !filteredAgentDiagnostics.isEmpty {
                    Section {
                        ForEach(filteredAgentDiagnostics.prefix(20)) { diagnostic in
                            NavigationLink {
                                AgentDetailView(agent: diagnostic.agent)
                            } label: {
                                IntegrationAgentModelRow(diagnostic: diagnostic)
                            }
                        }
                    } header: {
                        Text("Agent Model Drift")
                    } footer: {
                        if filteredAgentDiagnostics.count > 20 {
                            Text("Showing 20 of \(filteredAgentDiagnostics.count) agents with catalog drift.")
                        }
                    }
                    .id(IntegrationsSectionAnchor.drift)
                }

                if !hasAnyContent && !vm.isLoading {
                    Section {
                        ContentUnavailableView(
                            "No Integration Diagnostics",
                            systemImage: "square.3.layers.3d.down.forward",
                            description: Text("Pull to refresh after the server exposes provider, channel, and model inventory.")
                        )
                    }
                } else if hasAnyContent
                            && filteredProviders.isEmpty
                            && filteredChannels.isEmpty
                            && filteredModels.isEmpty
                            && filteredAliases.isEmpty
                            && filteredAgentDiagnostics.isEmpty
                            && !vm.isLoading {
                    Section {
                        ContentUnavailableView(
                            "No Search Results",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different provider, channel, model, or alias query.")
                        )
                    }
                }
            }
            .navigationTitle("Integrations")
            .searchable(text: $searchText, prompt: "Search provider, channel, model, alias, agent")
            .refreshable {
                await vm.refresh()
            }
            .overlay {
                if vm.isLoading && !hasAnyContent {
                    ProgressView("Loading integrations...")
                }
            }
            .task {
                if !hasAnyContent {
                    await vm.refresh()
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
    }

    @ViewBuilder
    private func integrationsFocusSection(_ proxy: ScrollViewProxy) -> some View {
        Button {
            jump(proxy, to: .providers)
        } label: {
            MonitoringJumpRow(
                title: String(localized: "Provider Health"),
                detail: filteredProviders.isEmpty
                    ? String(localized: "No providers are visible in the current integration scope.")
                    : String(localized: "Jump to provider outages, auth readiness, and manual probe status."),
                systemImage: "key.horizontal",
                tone: vm.unreachableLocalProviderCount > 0 ? .warning : .neutral,
                badgeText: filteredProviders.isEmpty ? String(localized: "Empty") : String(localized: "\(filteredProviders.count) visible"),
                badgeTone: vm.unreachableLocalProviderCount > 0 ? .warning : .neutral
            )
        }
        .buttonStyle(.plain)
        .disabled(filteredProviders.isEmpty)

        Button {
            jump(proxy, to: .channels)
        } label: {
            MonitoringJumpRow(
                title: String(localized: "Channel Readiness"),
                detail: filteredChannels.isEmpty
                    ? String(localized: "No channels are visible in the current integration scope.")
                    : String(localized: "Jump to required field gaps and manual channel validation."),
                systemImage: "bubble.left.and.bubble.right",
                tone: vm.channelCredentialGapCount > 0 ? .warning : .neutral,
                badgeText: filteredChannels.isEmpty ? String(localized: "Empty") : String(localized: "\(filteredChannels.count) visible"),
                badgeTone: vm.channelCredentialGapCount > 0 ? .warning : .neutral
            )
        }
        .buttonStyle(.plain)
        .disabled(filteredChannels.isEmpty)

        Button {
            jump(proxy, to: .models)
        } label: {
            MonitoringJumpRow(
                title: String(localized: "Model Catalog"),
                detail: filteredModels.isEmpty
                    ? String(localized: "No catalog models are visible for the current model filter.")
                    : String(localized: "Jump to model availability, pricing, and capability coverage."),
                systemImage: "square.stack.3d.up",
                tone: modelFilter == .unavailable ? .warning : .neutral,
                badgeText: filteredModels.isEmpty ? String(localized: "Empty") : String(localized: "\(filteredModels.count) visible"),
                badgeTone: modelFilter == .unavailable ? .warning : .neutral
            )
        }
        .buttonStyle(.plain)
        .disabled(filteredModels.isEmpty)

        if !filteredAliases.isEmpty {
            Button {
                jump(proxy, to: .aliases)
            } label: {
                MonitoringJumpRow(
                    title: String(localized: "Aliases"),
                    detail: String(localized: "Jump to the alias map that resolves requested model names into catalog models."),
                    systemImage: "arrow.left.arrow.right",
                    tone: .neutral,
                    badgeText: String(localized: "\(filteredAliases.count) visible"),
                    badgeTone: .neutral
                )
            }
            .buttonStyle(.plain)
        }

        Button {
            jump(proxy, to: .drift)
        } label: {
            MonitoringJumpRow(
                title: String(localized: "Agent Model Drift"),
                detail: filteredAgentDiagnostics.isEmpty
                    ? String(localized: "No agent model drift is visible in the current integration scope.")
                    : String(localized: "Jump to agents whose requested model or provider no longer aligns with the live catalog."),
                systemImage: "cpu",
                tone: filteredAgentDiagnostics.isEmpty ? .neutral : .warning,
                badgeText: filteredAgentDiagnostics.isEmpty ? String(localized: "Clear") : String(localized: "\(filteredAgentDiagnostics.count) agents"),
                badgeTone: filteredAgentDiagnostics.isEmpty ? .positive : .warning
            )
        }
        .buttonStyle(.plain)
        .disabled(filteredAgentDiagnostics.isEmpty)
    }

    private func jump(_ proxy: ScrollViewProxy, to anchor: IntegrationsSectionAnchor) {
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    private struct IntegrationSurfaceGroup<Content: View>: View {
        let title: String
        let detail: String
        let content: Content

        init(title: String, detail: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.detail = detail
            self.content = content()
        }

        var body: some View {
            MonitoringSnapshotCard(summary: title, detail: detail) {
                VStack(spacing: 10) {
                    content
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func providerRank(_ provider: ProviderStatus) -> Int {
        if provider.isLocal == true && provider.reachable == false {
            return 4
        }
        if provider.isConfigured {
            return 3
        }
        if provider.keyRequired {
            return 2
        }
        return 1
    }

    private func channelRank(_ channel: ChannelStatus) -> Int {
        if channel.configured && !channel.hasToken {
            return 3
        }
        if channel.configured {
            return 2
        }
        return 1
    }

    @MainActor
    private func testProvider(_ provider: ProviderStatus) async {
        providerProbeInFlightID = provider.id
        defer { providerProbeInFlightID = nil }

        do {
            let result = try await deps.apiClient.testProvider(name: provider.id)
            providerProbeResults[provider.id] = result
            operatorNotice = OperatorActionNotice(
                title: String(localized: "\(provider.displayName) Test"),
                message: probeSummary(for: result)
            )
        } catch {
            operatorNotice = OperatorActionNotice(
                title: String(localized: "\(provider.displayName) Test"),
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func testChannel(_ channel: ChannelStatus) async {
        channelProbeInFlightID = channel.id
        defer { channelProbeInFlightID = nil }

        do {
            let result = try await deps.apiClient.testChannel(name: channel.name)
            channelProbeResults[channel.id] = result
            operatorNotice = OperatorActionNotice(
                title: String(localized: "\(channel.displayName) Test"),
                message: probeSummary(for: result)
            )
        } catch {
            operatorNotice = OperatorActionNotice(
                title: String(localized: "\(channel.displayName) Test"),
                message: error.localizedDescription
            )
        }
    }

    private func probeSummary(for result: IntegrationProbeResult) -> String {
        if let message = result.message, !message.isEmpty {
            return message
        }
        if let error = result.error, !error.isEmpty {
            return error
        }
        if let note = result.note, !note.isEmpty {
            return note
        }
        if let latencyMs = result.latencyMs {
            return result.isHealthy
                ? String(localized: "Probe passed in \(latencyMs) ms.")
                : String(localized: "Probe failed after \(latencyMs) ms.")
        }
        return result.isHealthy
            ? String(localized: "Probe passed.")
            : String(localized: "Probe failed.")
    }
}

private struct IntegrationsScoreboard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let vm: DashboardViewModel

    private var providerStatus: MonitoringSummaryStatus {
        vm.providerReadinessStatus
    }

    private var localProviderStatus: MonitoringSummaryStatus {
        .countStatus(vm.unreachableLocalProviderCount, activeTone: .warning)
    }

    private var channelStatus: MonitoringSummaryStatus {
        vm.channelReadinessStatus
    }

    private var credentialGapStatus: MonitoringSummaryStatus {
        .countStatus(vm.channelCredentialGapCount, activeTone: .warning)
    }

    private var modelStatus: MonitoringSummaryStatus {
        .countStatus(vm.availableCatalogModelCount, activeTone: .positive, inactiveTone: .warning)
    }

    private var aliasStatus: MonitoringSummaryStatus {
        .countStatus(vm.modelAliasCount, activeTone: .positive)
    }

    private var modelDriftStatus: MonitoringSummaryStatus {
        .countStatus(vm.agentsWithModelDiagnostics.count, activeTone: .warning)
    }

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            StatBadge(
                value: "\(vm.configuredProviderCount)/\(max(vm.providers.count, 1))",
                label: "Providers",
                icon: "key.horizontal",
                color: providerStatus.color(positive: .blue)
            )
            StatBadge(
                value: "\(vm.unreachableLocalProviderCount)",
                label: "Local Down",
                icon: "network.slash",
                color: localProviderStatus.tone.color
            )
            StatBadge(
                value: "\(vm.readyChannelCount)/\(max(vm.configuredChannelCount, 1))",
                label: "Channels",
                icon: "bubble.left.and.bubble.right",
                color: channelStatus.color(positive: .teal)
            )
            StatBadge(
                value: "\(vm.channelCredentialGapCount)",
                label: "Credential Gaps",
                icon: "bubble.left.and.exclamationmark.bubble.right",
                color: credentialGapStatus.tone.color
            )
            StatBadge(
                value: "\(vm.availableCatalogModelCount)/\(max(vm.catalogModels.count, 1))",
                label: "Models",
                icon: "square.stack.3d.up",
                color: modelStatus.color(positive: .green)
            )
            StatBadge(
                value: "\(vm.modelAliasCount)",
                label: "Aliases",
                icon: "arrow.left.arrow.right",
                color: aliasStatus.color(positive: .indigo)
            )
            StatBadge(
                value: "\(vm.agentsWithModelDiagnostics.count)",
                label: "Agent Drift",
                icon: "cpu",
                color: modelDriftStatus.tone.color
            )
        }
    }
}

private struct IntegrationCatalogStatusCard: View {
    let vm: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow(verticalSpacing: 8) {
                titleLabel
            } accessory: {
                IntegrationStatusChip(text: vm.catalogSyncStatusLabel, tone: vm.catalogSyncTone)
            }

            Text(detailText)
                .font(.caption)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 12) {
                summaryFacts
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var detailText: String {
        if let catalogLastSyncDate = vm.catalogLastSyncDate {
            let relative = RelativeDateTimeFormatter().localizedString(for: catalogLastSyncDate, relativeTo: Date())
            if vm.isCatalogSyncStale {
                return String(localized: "The model catalog last synced \(relative). Review provider hub freshness if newly added models are missing.")
            }
            return String(localized: "The model catalog last synced \(relative). Current aliases and provider auth were enriched from that snapshot.")
        }
        return vm.catalogModels.isEmpty
            ? String(localized: "This server has not reported a catalog sync timestamp and currently exposes no catalog models.")
            : String(localized: "This server did not report a catalog sync timestamp, but the current cached catalog is still available.")
    }

    private var relativeSyncText: String? {
        guard let catalogLastSyncDate = vm.catalogLastSyncDate else { return nil }
        return RelativeDateTimeFormatter().localizedString(for: catalogLastSyncDate, relativeTo: Date())
    }

    private var titleLabel: some View {
        Label("Catalog Freshness", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            .font(.subheadline.weight(.medium))
    }

    @ViewBuilder
    private var summaryFacts: some View {
        Label("\(vm.catalogModels.count) models", systemImage: "square.stack.3d.up")
        Label("\(vm.modelAliasCount) aliases", systemImage: "arrow.left.arrow.right")
        if let relativeSyncText {
            Label(relativeSyncText, systemImage: "clock")
        }
    }
}

private struct IntegrationProviderRow: View {
    let provider: ProviderStatus
    let probeResult: IntegrationProbeResult?
    let isTesting: Bool
    let onTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonitoringFactsRow(horizontalAlignment: .top, verticalSpacing: 8, headerVerticalSpacing: 8) {
                providerSummary
            } accessory: {
                providerControls
            } facts: {
                providerFacts
            }

            if let error = provider.error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let probeResult {
                Text(probeCaption(for: probeResult))
                    .font(.caption)
                    .foregroundStyle(probeResult.isHealthy ? Color.secondary : Color.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private func probeCaption(for result: IntegrationProbeResult) -> String {
        if let error = result.error, !error.isEmpty {
            return error
        }
        if let message = result.message, !message.isEmpty {
            return message
        }
        if let note = result.note, !note.isEmpty {
            return note
        }
        if let latencyMs = result.latencyMs {
            return result.isHealthy
                ? String(localized: "Last manual probe: \(latencyMs) ms")
                : String(localized: "Last manual probe failed in \(latencyMs) ms")
        }
        return result.isHealthy
            ? String(localized: "Last manual probe passed.")
            : String(localized: "Last manual probe failed.")
    }

    private var providerSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(provider.displayName)
                .font(.subheadline.weight(.medium))
            Text(provider.id)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let baseURL = provider.baseURL, !baseURL.isEmpty {
                Text(baseURL)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var providerControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            IntegrationStatusChip(text: provider.localizedStatusLabel, tone: provider.statusTone)
            Button {
                onTest()
            } label: {
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Test")
                }
            }
            .buttonStyle(.bordered)
            .font(.caption.weight(.semibold))
            .disabled(isTesting)
        }
    }

    @ViewBuilder
    private var providerFacts: some View {
        Label("\(provider.modelCount)", systemImage: "square.stack.3d.up")
        if provider.keyRequired {
            Label(provider.apiKeyEnv ?? String(localized: "API key"), systemImage: "key.horizontal")
        }
        if let latencyMs = provider.latencyMs, provider.isLocal == true {
            Label("\(latencyMs) ms", systemImage: "speedometer")
        }
        if let discoveredModels = provider.discoveredModels, !discoveredModels.isEmpty {
            Label("\(discoveredModels.count) discovered", systemImage: "sparkles")
        }
    }
}

private struct IntegrationChannelRow: View {
    let channel: ChannelStatus
    let probeResult: IntegrationProbeResult?
    let isTesting: Bool
    let onTest: () -> Void

    private var requiredFields: [ChannelConfigField] {
        channel.fields?.filter(\.required) ?? []
    }

    private var missingRequiredFields: [ChannelConfigField] {
        requiredFields.filter { !$0.hasValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonitoringFactsRow(horizontalAlignment: .top, verticalSpacing: 8, headerVerticalSpacing: 8) {
                channelSummary
            } accessory: {
                channelControls
            } facts: {
                channelFacts
            }

            if !missingRequiredFields.isEmpty {
                Text(missingFieldSummary)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let probeResult {
                Text(probeCaption(for: probeResult))
                    .font(.caption)
                    .foregroundStyle(probeResult.isHealthy ? Color.secondary : Color.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private func probeCaption(for result: IntegrationProbeResult) -> String {
        if let message = result.message, !message.isEmpty {
            return message
        }
        if let error = result.error, !error.isEmpty {
            return error
        }
        return result.isHealthy
            ? String(localized: "Credential probe passed.")
            : String(localized: "Credential probe failed.")
    }

    private var missingFieldSummary: String {
        let preview = missingRequiredFields.prefix(3).map { field in
            field.envVar ?? field.label
        }
        let suffix = missingRequiredFields.count > preview.count
            ? String(localized: " +\(missingRequiredFields.count - preview.count) more")
            : ""
        return String(localized: "Missing required fields: \(preview.joined(separator: " • "))\(suffix)")
    }

    private var channelSummary: some View {
        ResponsiveIconDetailRow(horizontalSpacing: 12, verticalSpacing: 6, spacerMinLength: 0) {
            Text(channel.icon)
                .font(.title3)
                .frame(width: 28)
        } detail: {
            VStack(alignment: .leading, spacing: 3) {
                Text(channel.displayName)
                    .font(.subheadline.weight(.medium))
                Text(channel.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("\(channel.localizedCategoryLabel) · \(channel.localizedSetupTypeLabel) · \(channel.localizedDifficultyLabel)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var channelControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            IntegrationStatusChip(text: channel.localizedConfigurationLabel, tone: channel.configurationTone)
            Button {
                onTest()
            } label: {
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Test")
                }
            }
            .buttonStyle(.bordered)
            .font(.caption.weight(.semibold))
            .disabled(isTesting)
        }
    }

    @ViewBuilder
    private var channelFacts: some View {
        if !requiredFields.isEmpty {
            Label("\(requiredFields.count) req", systemImage: "checklist")
                .foregroundStyle(.secondary)
            Label("\(requiredFields.filter(\.hasValue).count) set", systemImage: "checkmark.circle")
                .foregroundStyle(missingRequiredFields.isEmpty ? Color.green : Color.secondary)
        }
        if !missingRequiredFields.isEmpty {
            Label("\(missingRequiredFields.count) missing", systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
        }
        if let setupSteps = channel.setupSteps {
            Label("\(setupSteps.count) steps", systemImage: "list.number")
                .foregroundStyle(.secondary)
        }
        if channel.quickSetup {
            Label("Quick", systemImage: "bolt")
                .foregroundStyle(.secondary)
        }
    }
}

private struct IntegrationModelRow: View {
    let model: CatalogModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonitoringFactsRow(horizontalAlignment: .top, verticalSpacing: 8, headerVerticalSpacing: 8) {
                modelSummary
            } accessory: {
                availabilityChip
            } facts: {
                modelFacts
            }

            FlowLayout(spacing: 8) {
                capabilityChips
            }

            if model.inputCostPerM != nil || model.outputCostPerM != nil {
                Text(costLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var costLine: String {
        let input = model.inputCostPerM.map {
            String(
                localized: "\(localizedUSDCurrency($0, standardPrecision: 2))/M in"
            )
        } ?? String(localized: "n/a in")
        let output = model.outputCostPerM.map {
            String(
                localized: "\(localizedUSDCurrency($0, standardPrecision: 2))/M out"
            )
        } ?? String(localized: "n/a out")
        return String(localized: "\(input) · \(output)")
    }

    private func capabilityTag(_ title: String, isEnabled: Bool) -> some View {
        PresentationToneBadge(
            text: title,
            tone: isEnabled ? .positive : .neutral,
            horizontalPadding: 6,
            verticalPadding: 2
        )
    }

    private var modelSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.displayName)
                .font(.subheadline.weight(.medium))
            Text(model.id)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private var availabilityChip: some View {
        IntegrationStatusChip(
            text: model.localizedAvailabilityLabel,
            tone: model.availabilityTone
        )
    }

    @ViewBuilder
    private var modelFacts: some View {
        Label(model.provider, systemImage: "cloud")
        Label(model.localizedTierLabel, systemImage: "square.3.layers.3d")
        if let contextWindow = model.contextWindow {
            Label(contextWindow.formatted(), systemImage: "text.redaction")
        }
        if let maxOutputTokens = model.maxOutputTokens {
            Label(maxOutputTokens.formatted(), systemImage: "arrow.up.right.square")
        }
    }

    @ViewBuilder
    private var capabilityChips: some View {
        capabilityTag(String(localized: "Tools"), isEnabled: model.supportsTools)
        capabilityTag(String(localized: "Vision"), isEnabled: model.supportsVision)
        capabilityTag(String(localized: "Streaming"), isEnabled: model.supportsStreaming)
    }
}

private struct IntegrationAliasRow: View {
    let alias: ModelAliasEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(alias.alias)
                .font(.subheadline.weight(.medium))
            Text(alias.modelId)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

private struct IntegrationAgentModelRow: View {
    let diagnostic: AgentModelDiagnostic

    var body: some View {
        MonitoringFactsRow(horizontalAlignment: .top, verticalSpacing: 8, headerVerticalSpacing: 8) {
            diagnosticSummary
        } accessory: {
            IntegrationStatusChip(text: diagnostic.localizedStatusLabel, tone: diagnostic.statusTone)
        } facts: {
            diagnosticFacts
        }
        .padding(.vertical, 2)
    }

    private var diagnosticSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(diagnostic.agent.name)
                .font(.subheadline.weight(.medium))
            Text(diagnostic.issueSummary)
                .font(.caption)
                .foregroundStyle(.orange)
            Text(diagnostic.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var diagnosticFacts: some View {
        Label(diagnostic.requestedModel, systemImage: "cpu")
        if let resolvedAlias = diagnostic.resolvedAlias {
            Label(resolvedAlias.alias, systemImage: "arrow.left.arrow.right")
        }
        if let resolvedModel = diagnostic.resolvedModel {
            Label(resolvedModel.provider, systemImage: "cloud")
        }
    }

}

private struct IntegrationStatusChip: View {
    let text: String
    let tone: PresentationTone

    var body: some View {
        PresentationToneBadge(text: text, tone: tone)
    }
}

private func localizedUSDCurrency(
    _ value: Double,
    standardPrecision: Int = 2,
    smallValuePrecision: Int? = nil,
    minimumDisplayValue: Double = 0.01
) -> String {
    let standard = FloatingPointFormatStyle<Double>.Currency(code: "USD")
        .precision(.fractionLength(standardPrecision))
    if value == 0 {
        return value.formatted(standard)
    }
    if value < minimumDisplayValue {
        let minimumPrecision = smallValuePrecision ?? standardPrecision
        let minimumStyle = FloatingPointFormatStyle<Double>.Currency(code: "USD")
            .precision(.fractionLength(minimumPrecision))
        return "<\(minimumDisplayValue.formatted(minimumStyle))"
    }
    if let smallValuePrecision, value < 1 {
        let small = FloatingPointFormatStyle<Double>.Currency(code: "USD")
            .precision(.fractionLength(smallValuePrecision))
        return value.formatted(small)
    }
    return value.formatted(standard)
}

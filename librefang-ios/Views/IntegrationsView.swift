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
    private var integrationsJumpCount: Int {
        [
            !filteredProviders.isEmpty,
            !filteredChannels.isEmpty,
            !filteredModels.isEmpty,
            !filteredAliases.isEmpty,
            !filteredAgentDiagnostics.isEmpty
        ]
        .filter { $0 }
        .count
    }
    private var integrationsSectionCount: Int {
        [
            !filteredProviders.isEmpty,
            !filteredChannels.isEmpty,
            !filteredModels.isEmpty,
            !filteredAliases.isEmpty,
            !filteredAgentDiagnostics.isEmpty
        ]
        .filter { $0 }
        .count
    }
    private var configuredProviderCount: Int {
        filteredProviders.filter(\.isConfigured).count
    }
    private var localProviderCount: Int {
        filteredProviders.filter { $0.isLocal == true }.count
    }
    private var unreachableFilteredProviderCount: Int {
        filteredProviders.filter { $0.isLocal == true && $0.reachable == false }.count
    }
    private var discoveredProviderModelCount: Int {
        filteredProviders.reduce(0) { $0 + ($1.discoveredModels?.count ?? 0) }
    }
    private var readyChannelCount: Int {
        filteredChannels.filter { $0.configured && $0.hasToken }.count
    }
    private var missingCredentialChannelCount: Int {
        filteredChannels.filter { channel in
            let requiredFields = channel.fields?.filter(\.required) ?? []
            return requiredFields.contains(where: { !$0.hasValue })
        }
        .count
    }
    private var quickSetupChannelCount: Int {
        filteredChannels.filter(\.quickSetup).count
    }
    private var missingRequiredFieldCount: Int {
        filteredChannels.reduce(0) { partialResult, channel in
            partialResult + (channel.fields?.filter(\.required).filter { !$0.hasValue }.count ?? 0)
        }
    }

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
                    IntegrationsStatusDeckCard(
                        scope: $scope,
                        scopeSummaryLine: scopeSummaryLine,
                        searchSummaryLine: searchSummaryLine,
                        providerAttentionCount: providerAttentionCount,
                        channelAttentionCount: channelAttentionCount,
                        modelAttentionCount: modelAttentionCount,
                        driftAttentionCount: driftAttentionCount
                    )
                } header: {
                    Text("Snapshot")
                } footer: {
                    Text("Keep scope, attention filters, and highest-signal integration counts in one compact digest.")
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
                        IntegrationsSectionInventoryDeck(
                            sectionCount: integrationsSectionCount,
                            visibleResultCount: visibleResultCount,
                            providerCount: filteredProviders.count,
                            channelCount: filteredChannels.count,
                            modelCount: filteredModels.count,
                            aliasCount: filteredAliases.count,
                            driftCount: filteredAgentDiagnostics.count,
                            providerAttentionCount: providerAttentionCount,
                            channelAttentionCount: channelAttentionCount,
                            modelAttentionCount: modelAttentionCount
                        )
                        IntegrationsPressureCoverageDeck(
                            providerAttentionCount: providerAttentionCount,
                            channelAttentionCount: channelAttentionCount,
                            modelAttentionCount: modelAttentionCount,
                            driftAttentionCount: driftAttentionCount,
                            visibleResultCount: visibleResultCount,
                            scopeLabel: scope.label,
                            modelFilterLabel: modelFilter.label,
                            hasSearchScope: !normalizedSearchText.isEmpty
                        )
                        IntegrationsActionReadinessDeck(
                            primaryRouteCount: 4,
                            supportRouteCount: 3,
                            jumpCount: integrationsJumpCount,
                            visibleResultCount: visibleResultCount,
                            providerCount: filteredProviders.count,
                            channelCount: filteredChannels.count,
                            modelCount: filteredModels.count,
                            driftCount: filteredAgentDiagnostics.count,
                            scopeLabel: scope.label,
                            modelFilterLabel: modelFilter.label,
                            hasSearchScope: !normalizedSearchText.isEmpty
                        )
                    } header: {
                        Text("Inventory")
                    } footer: {
                        Text("Keep section coverage visible before jumping around the integration inventory.")
                    }

                    Section {
                        integrationsFocusSection(proxy)
                    } header: {
                        Text("Jumps")
                    } footer: {
                        Text("Use these jumps to move through integrations without scrolling the full inventory.")
                    }

                    Section {
                        MonitoringSurfaceGroupCard(
                            title: String(localized: "Routes"),
                            detail: String(localized: "Keep the next operator exits compact and visible above the provider, channel, and drift inventory.")
                        ) {
                            IntegrationsRouteInventoryDeck(
                                primaryRouteCount: 4,
                                supportRouteCount: 3,
                                jumpCount: integrationsJumpCount,
                                providerAttentionCount: providerAttentionCount,
                                channelAttentionCount: channelAttentionCount,
                                driftAttentionCount: driftAttentionCount
                            )

                            MonitoringShortcutRail(
                                title: String(localized: "Primary"),
                                detail: String(localized: "Use these routes first when provider, channel, or drift diagnostics need broader context.")
                            ) {
                                NavigationLink {
                                    RuntimeView()
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "Runtime"),
                                        systemImage: "server.rack",
                                        tone: vm.integrationPressureIssueCategoryCount > 0 ? .critical : .neutral,
                                        badgeText: vm.integrationPressureIssueCategoryCount > 0
                                            ? (vm.integrationPressureIssueCategoryCount == 1 ? String(localized: "1 issue") : String(localized: "\(vm.integrationPressureIssueCategoryCount) issues"))
                                            : nil
                                    )
                                }
                                .buttonStyle(.plain)

                                NavigationLink {
                                    DiagnosticsView()
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "Diagnostics"),
                                        systemImage: "stethoscope",
                                        tone: vm.diagnosticsSummaryTone,
                                        badgeText: vm.diagnosticsConfigWarningCount > 0
                                            ? (vm.diagnosticsConfigWarningCount == 1 ? String(localized: "1 warning") : String(localized: "\(vm.diagnosticsConfigWarningCount) warnings"))
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
                                        tone: vm.integrationPressureIssueCategoryCount > 0 ? .critical : .neutral,
                                        badgeText: driftAttentionCount > 0
                                            ? (driftAttentionCount == 1 ? String(localized: "1 drift") : String(localized: "\(driftAttentionCount) drift"))
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
                                        tone: driftAttentionCount > 0 ? .warning : .neutral,
                                        badgeText: driftAttentionCount > 0
                                            ? (driftAttentionCount == 1 ? String(localized: "1 drifted") : String(localized: "\(driftAttentionCount) drifted"))
                                            : nil
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            MonitoringShortcutRail(
                                title: String(localized: "Support"),
                                detail: String(localized: "Keep slower spend, automation, and routing drilldowns behind the primary exits.")
                            ) {
                                NavigationLink {
                                    AutomationView(initialScope: .attention)
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "Automation"),
                                        systemImage: "flowchart",
                                        tone: vm.automationPressureIssueCategoryCount > 0 ? .warning : .neutral,
                                        badgeText: vm.automationPressureIssueCategoryCount > 0
                                            ? (vm.automationPressureIssueCategoryCount == 1 ? String(localized: "1 issue") : String(localized: "\(vm.automationPressureIssueCategoryCount) issues"))
                                            : nil
                                    )
                                }
                                .buttonStyle(.plain)

                                NavigationLink {
                                    BudgetView()
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "Budget"),
                                        systemImage: "chart.bar"
                                    )
                                }
                                .buttonStyle(.plain)

                                NavigationLink {
                                    CommsView(api: deps.apiClient)
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "Comms"),
                                        systemImage: "point.3.connected.trianglepath.dotted"
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("Controls")
                    } footer: {
                        Text("Use these routes when provider, channel, model, or drift diagnostics need runtime, incident, or fleet context.")
                    }
                }

                if !filteredProviders.isEmpty {
                    Section {
                        IntegrationProvidersSnapshotCard(
                            providers: filteredProviders
                        )
                        IntegrationsProviderSectionInventoryDeck(
                            visibleCount: filteredProviders.count,
                            configuredCount: configuredProviderCount,
                            localCount: localProviderCount,
                            unreachableLocalCount: unreachableFilteredProviderCount,
                            discoveredModelCount: discoveredProviderModelCount,
                            isTesting: providerProbeInFlightID != nil,
                            hasSearchScope: !normalizedSearchText.isEmpty
                        )

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
                        IntegrationChannelsSnapshotCard(
                            channels: filteredChannels
                        )
                        IntegrationsChannelSectionInventoryDeck(
                            visibleCount: filteredChannels.count,
                            readyCount: readyChannelCount,
                            missingCredentialCount: missingCredentialChannelCount,
                            missingRequiredFieldCount: missingRequiredFieldCount,
                            quickSetupCount: quickSetupChannelCount,
                            isTesting: channelProbeInFlightID != nil,
                            hasSearchScope: !normalizedSearchText.isEmpty
                        )

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
                        IntegrationModelsSnapshotCard(
                            models: filteredModels,
                            modelFilter: modelFilter
                        )

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
                        IntegrationAliasesSnapshotCard(
                            aliases: filteredAliases
                        )

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
                        IntegrationDriftSnapshotCard(
                            diagnostics: filteredAgentDiagnostics
                        )

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

private struct IntegrationsStatusDeckCard: View {
    @Binding var scope: IntegrationsScope
    let scopeSummaryLine: String
    let searchSummaryLine: String
    let providerAttentionCount: Int
    let channelAttentionCount: Int
    let modelAttentionCount: Int
    let driftAttentionCount: Int

    private var scopeTone: PresentationTone {
        scope == .attention ? .warning : .neutral
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringFilterCard(summary: scopeSummaryLine, detail: searchSummaryLine) {
                PresentationToneBadge(
                    text: scope.label,
                    tone: scopeTone
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
                    tone: scopeTone
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
        }
    }
}

private struct IntegrationsRouteInventoryDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let jumpCount: Int
    let providerAttentionCount: Int
    let channelAttentionCount: Int
    let driftAttentionCount: Int

    var body: some View {
        MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
            FlowLayout(spacing: 8) {
                PresentationToneBadge(
                    text: primaryRouteCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryRouteCount) primary routes"),
                    tone: .neutral
                )
                PresentationToneBadge(
                    text: supportRouteCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportRouteCount) support routes"),
                    tone: .neutral
                )
                PresentationToneBadge(
                    text: jumpCount == 1 ? String(localized: "1 jump") : String(localized: "\(jumpCount) jumps"),
                    tone: jumpCount > 0 ? .positive : .neutral
                )
                if providerAttentionCount > 0 {
                    PresentationToneBadge(
                        text: providerAttentionCount == 1 ? String(localized: "1 provider issue") : String(localized: "\(providerAttentionCount) provider issues"),
                        tone: .warning
                    )
                }
                if channelAttentionCount > 0 {
                    PresentationToneBadge(
                        text: channelAttentionCount == 1 ? String(localized: "1 channel gap") : String(localized: "\(channelAttentionCount) channel gaps"),
                        tone: .warning
                    )
                }
                if driftAttentionCount > 0 {
                    PresentationToneBadge(
                        text: driftAttentionCount == 1 ? String(localized: "1 drifted agent") : String(localized: "\(driftAttentionCount) drifted agents"),
                        tone: .critical
                    )
                }
            }
        }
    }

    private var summaryLine: String {
        let totalRoutes = primaryRouteCount + supportRouteCount + jumpCount
        return totalRoutes == 1
            ? String(localized: "1 integration route or jump is grouped in this deck.")
            : String(localized: "\(totalRoutes) integration routes and jumps are grouped in this deck.")
    }

    private var detailLine: String {
        String(localized: "Routes and section jumps stay summarized here before provider, channel, model, and drift inventories.")
    }
}

private struct IntegrationsSectionInventoryDeck: View {
    let sectionCount: Int
    let visibleResultCount: Int
    let providerCount: Int
    let channelCount: Int
    let modelCount: Int
    let aliasCount: Int
    let driftCount: Int
    let providerAttentionCount: Int
    let channelAttentionCount: Int
    let modelAttentionCount: Int

    var body: some View {
        MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
            FlowLayout(spacing: 8) {
                PresentationToneBadge(
                    text: sectionCount == 1 ? String(localized: "1 live section") : String(localized: "\(sectionCount) live sections"),
                    tone: .positive
                )
                PresentationToneBadge(
                    text: visibleResultCount == 1 ? String(localized: "1 visible result") : String(localized: "\(visibleResultCount) visible results"),
                    tone: .neutral
                )
                if providerAttentionCount > 0 {
                    PresentationToneBadge(
                        text: providerAttentionCount == 1 ? String(localized: "1 provider issue") : String(localized: "\(providerAttentionCount) provider issues"),
                        tone: .warning
                    )
                }
                if channelAttentionCount > 0 {
                    PresentationToneBadge(
                        text: channelAttentionCount == 1 ? String(localized: "1 channel gap") : String(localized: "\(channelAttentionCount) channel gaps"),
                        tone: .warning
                    )
                }
                if modelAttentionCount > 0 {
                    PresentationToneBadge(
                        text: modelAttentionCount == 1 ? String(localized: "1 unavailable model") : String(localized: "\(modelAttentionCount) unavailable models"),
                        tone: .warning
                    )
                }
            }
        }

        MonitoringFactsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Section inventory"))
                    .font(.subheadline.weight(.medium))
                Text(String(localized: "Keep provider, channel, model, alias, and drift coverage visible before the jump rail and operator routes."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } accessory: {
            PresentationToneBadge(
                text: driftCount == 1 ? String(localized: "1 drift case") : String(localized: "\(driftCount) drift cases"),
                tone: driftCount > 0 ? .critical : .neutral
            )
        } facts: {
            Label(
                providerCount == 1 ? String(localized: "1 provider") : String(localized: "\(providerCount) providers"),
                systemImage: "key.horizontal"
            )
            Label(
                channelCount == 1 ? String(localized: "1 channel") : String(localized: "\(channelCount) channels"),
                systemImage: "bubble.left.and.bubble.right"
            )
            Label(
                modelCount == 1 ? String(localized: "1 model") : String(localized: "\(modelCount) models"),
                systemImage: "square.stack.3d.up"
            )
            if aliasCount > 0 {
                Label(
                    aliasCount == 1 ? String(localized: "1 alias") : String(localized: "\(aliasCount) aliases"),
                    systemImage: "arrow.triangle.branch"
                )
            }
        }
    }

    private var summaryLine: String {
        sectionCount == 1
            ? String(localized: "1 integration section is active below the snapshot.")
            : String(localized: "\(sectionCount) integration sections are active below the snapshot.")
    }

    private var detailLine: String {
        String(localized: "Providers, channels, models, aliases, and drift stay summarized before the jump rail and deeper operator routes.")
    }
}

private struct IntegrationsPressureCoverageDeck: View {
    let providerAttentionCount: Int
    let channelAttentionCount: Int
    let modelAttentionCount: Int
    let driftAttentionCount: Int
    let visibleResultCount: Int
    let scopeLabel: String
    let modelFilterLabel: String
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to tell whether integration drag is mostly provider reachability, channel setup gaps, catalog availability, or agent model drift before opening the inventory below."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if providerAttentionCount > 0 {
                        PresentationToneBadge(
                            text: providerAttentionCount == 1 ? String(localized: "1 provider issue") : String(localized: "\(providerAttentionCount) provider issues"),
                            tone: .critical
                        )
                    }
                    if channelAttentionCount > 0 {
                        PresentationToneBadge(
                            text: channelAttentionCount == 1 ? String(localized: "1 channel gap") : String(localized: "\(channelAttentionCount) channel gaps"),
                            tone: .warning
                        )
                    }
                    if modelAttentionCount > 0 {
                        PresentationToneBadge(
                            text: modelAttentionCount == 1 ? String(localized: "1 unavailable model") : String(localized: "\(modelAttentionCount) unavailable models"),
                            tone: .warning
                        )
                    }
                    if driftAttentionCount > 0 {
                        PresentationToneBadge(
                            text: driftAttentionCount == 1 ? String(localized: "1 drift case") : String(localized: "\(driftAttentionCount) drift cases"),
                            tone: .critical
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Pressure coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep search scope, inventory breadth, and the loudest provider, channel, catalog, and drift buckets readable before opening routes and jumps."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: scopeLabel, tone: .neutral)
            } facts: {
                Label(
                    visibleResultCount == 1 ? String(localized: "1 visible result") : String(localized: "\(visibleResultCount) visible results"),
                    systemImage: "square.grid.2x2"
                )
                Label(modelFilterLabel, systemImage: "line.3.horizontal.decrease.circle")
                if hasSearchScope {
                    Label(String(localized: "Search active"), systemImage: "magnifyingglass")
                }
            }
        }
    }

    private var summaryLine: String {
        if providerAttentionCount > 0 || driftAttentionCount > 0 {
            return String(localized: "Integration pressure is currently anchored by provider reachability or agent model drift.")
        }
        if channelAttentionCount > 0 || modelAttentionCount > 0 {
            return String(localized: "Integration pressure is currently concentrated in channel setup gaps and catalog availability.")
        }
        return String(localized: "Integration pressure is currently low and mostly reflects scope, search, and catalog breadth.")
    }
}

private struct IntegrationsActionReadinessDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let jumpCount: Int
    let visibleResultCount: Int
    let providerCount: Int
    let channelCount: Int
    let modelCount: Int
    let driftCount: Int
    let scopeLabel: String
    let modelFilterLabel: String
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to check whether route jumps, model filtering, and integration inventory breadth are ready before opening the provider, channel, model, and drift sections."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: scopeLabel, tone: .neutral)
                    PresentationToneBadge(text: modelFilterLabel, tone: .neutral)
                    if hasSearchScope {
                        PresentationToneBadge(text: String(localized: "Search scoped"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Action readiness"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep route breadth, jump coverage, and integration inventory depth visible before drilling into provider, channel, model, and drift details."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: String(localized: "\(primaryRouteCount + supportRouteCount + jumpCount) actions"),
                    tone: .neutral
                )
            } facts: {
                Label(
                    visibleResultCount == 1 ? String(localized: "1 visible result") : String(localized: "\(visibleResultCount) visible results"),
                    systemImage: "line.3.horizontal.decrease.circle"
                )
                Label(
                    providerCount == 1 ? String(localized: "1 provider") : String(localized: "\(providerCount) providers"),
                    systemImage: "key.horizontal"
                )
                Label(
                    channelCount == 1 ? String(localized: "1 channel") : String(localized: "\(channelCount) channels"),
                    systemImage: "bubble.left.and.bubble.right"
                )
                Label(
                    modelCount == 1 ? String(localized: "1 model") : String(localized: "\(modelCount) models"),
                    systemImage: "square.stack.3d.up"
                )
                if driftCount > 0 {
                    Label(
                        driftCount == 1 ? String(localized: "1 drift case") : String(localized: "\(driftCount) drift cases"),
                        systemImage: "arrow.triangle.branch"
                    )
                }
            }
        }
    }

    private var summaryLine: String {
        if hasSearchScope {
            return String(localized: "Integration action readiness is currently narrowed by an active search scope.")
        }
        if driftCount > 0 {
            return String(localized: "Integration action readiness is currently anchored by model or provider drift that is ready for deeper drilldown.")
        }
        return String(localized: "Integration action readiness is currently clear enough for route jumps and inventory review.")
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

private struct IntegrationProvidersSnapshotCard: View {
    let providers: [ProviderStatus]

    private var configuredCount: Int {
        providers.filter(\.isConfigured).count
    }

    private var localCount: Int {
        providers.filter { $0.isLocal == true }.count
    }

    private var unreachableLocalCount: Int {
        providers.filter { $0.isLocal == true && $0.reachable == false }.count
    }

    private var discoveredModelCount: Int {
        providers.reduce(0) { $0 + ($1.discoveredModels?.count ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Provider readiness stays visible before the detailed provider inventory."),
                detail: String(localized: "Use the compact summary to see local outages, configured providers, and discovery depth before opening individual provider rows."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: providers.count == 1 ? String(localized: "1 provider visible") : String(localized: "\(providers.count) providers visible"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: configuredCount == 1 ? String(localized: "1 configured") : String(localized: "\(configuredCount) configured"),
                        tone: configuredCount > 0 ? .positive : .neutral
                    )
                    if localCount > 0 {
                        PresentationToneBadge(
                            text: localCount == 1 ? String(localized: "1 local") : String(localized: "\(localCount) local"),
                            tone: .neutral
                        )
                    }
                    if unreachableLocalCount > 0 {
                        PresentationToneBadge(
                            text: unreachableLocalCount == 1 ? String(localized: "1 local down") : String(localized: "\(unreachableLocalCount) local down"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Provider facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep auth readiness, local reachability, and discovered model depth visible before the longer provider list."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if discoveredModelCount > 0 {
                    PresentationToneBadge(
                        text: discoveredModelCount == 1 ? String(localized: "1 discovered model") : String(localized: "\(discoveredModelCount) discovered models"),
                        tone: .neutral
                    )
                }
            } facts: {
                Label(
                    providers.count == 1 ? String(localized: "1 provider") : String(localized: "\(providers.count) providers"),
                    systemImage: "key.horizontal"
                )
                Label(
                    configuredCount == 1 ? String(localized: "1 configured") : String(localized: "\(configuredCount) configured"),
                    systemImage: "checkmark.circle"
                )
                if localCount > 0 {
                    Label(
                        localCount == 1 ? String(localized: "1 local provider") : String(localized: "\(localCount) local providers"),
                        systemImage: "network"
                    )
                }
                if unreachableLocalCount > 0 {
                    Label(
                        unreachableLocalCount == 1 ? String(localized: "1 local outage") : String(localized: "\(unreachableLocalCount) local outages"),
                        systemImage: "network.slash"
                    )
                }
            }
        }
    }
}

private struct IntegrationsProviderSectionInventoryDeck: View {
    let visibleCount: Int
    let configuredCount: Int
    let localCount: Int
    let unreachableLocalCount: Int
    let discoveredModelCount: Int
    let isTesting: Bool
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Keep provider coverage, local reachability, and live probe state visible before the longer provider rows take over."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: visibleCount == 1 ? String(localized: "1 visible provider") : String(localized: "\(visibleCount) visible providers"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: configuredCount == 1 ? String(localized: "1 configured") : String(localized: "\(configuredCount) configured"),
                        tone: configuredCount > 0 ? .positive : .neutral
                    )
                    if unreachableLocalCount > 0 {
                        PresentationToneBadge(
                            text: unreachableLocalCount == 1 ? String(localized: "1 local outage") : String(localized: "\(unreachableLocalCount) local outages"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Provider section coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Use this slice to see whether the visible provider section is mostly configured inventory, local outage follow-up, or discovery detail."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: isTesting ? String(localized: "Probe running") : String(localized: "Idle"),
                    tone: isTesting ? .warning : .neutral
                )
            } facts: {
                if localCount > 0 {
                    Label(
                        localCount == 1 ? String(localized: "1 local provider") : String(localized: "\(localCount) local providers"),
                        systemImage: "network"
                    )
                }
                if discoveredModelCount > 0 {
                    Label(
                        discoveredModelCount == 1 ? String(localized: "1 discovered model") : String(localized: "\(discoveredModelCount) discovered models"),
                        systemImage: "sparkles"
                    )
                }
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        unreachableLocalCount > 0
            ? String(localized: "Provider coverage is currently anchored by \(unreachableLocalCount) local outages inside the visible section.")
            : String(localized: "Provider coverage currently spans \(configuredCount) configured providers in the visible section.")
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

private struct IntegrationChannelsSnapshotCard: View {
    let channels: [ChannelStatus]

    private var readyCount: Int {
        channels.filter { $0.configured && $0.hasToken }.count
    }

    private var missingRequiredCount: Int {
        channels.reduce(0) { partialResult, channel in
            partialResult + (channel.fields?.filter { $0.required && !$0.hasValue }.count ?? 0)
        }
    }

    private var quickSetupCount: Int {
        channels.filter(\.quickSetup).count
    }

    private var setupStepCount: Int {
        channels.reduce(0) { partialResult, channel in
            partialResult + (channel.setupSteps?.count ?? 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Channel readiness stays visible before the longer channel setup inventory."),
                detail: String(localized: "Use the summary to see ready channels, missing fields, and setup weight before opening per-channel diagnostics."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: channels.count == 1 ? String(localized: "1 channel visible") : String(localized: "\(channels.count) channels visible"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: readyCount == 1 ? String(localized: "1 ready") : String(localized: "\(readyCount) ready"),
                        tone: readyCount > 0 ? .positive : .neutral
                    )
                    if missingRequiredCount > 0 {
                        PresentationToneBadge(
                            text: missingRequiredCount == 1 ? String(localized: "1 missing field") : String(localized: "\(missingRequiredCount) missing fields"),
                            tone: .warning
                        )
                    }
                    if quickSetupCount > 0 {
                        PresentationToneBadge(
                            text: quickSetupCount == 1 ? String(localized: "1 quick setup") : String(localized: "\(quickSetupCount) quick setups"),
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Channel facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep readiness, setup depth, and missing field pressure visible before opening each channel row."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if setupStepCount > 0 {
                    PresentationToneBadge(
                        text: setupStepCount == 1 ? String(localized: "1 setup step") : String(localized: "\(setupStepCount) setup steps"),
                        tone: .neutral
                    )
                }
            } facts: {
                Label(
                    channels.count == 1 ? String(localized: "1 channel") : String(localized: "\(channels.count) channels"),
                    systemImage: "bubble.left.and.bubble.right"
                )
                Label(
                    readyCount == 1 ? String(localized: "1 ready") : String(localized: "\(readyCount) ready"),
                    systemImage: "checkmark.circle"
                )
                if missingRequiredCount > 0 {
                    Label(
                        missingRequiredCount == 1 ? String(localized: "1 missing field") : String(localized: "\(missingRequiredCount) missing fields"),
                        systemImage: "exclamationmark.circle"
                    )
                }
                if quickSetupCount > 0 {
                    Label(
                        quickSetupCount == 1 ? String(localized: "1 quick setup") : String(localized: "\(quickSetupCount) quick setups"),
                        systemImage: "bolt"
                    )
                }
            }
        }
    }
}

private struct IntegrationsChannelSectionInventoryDeck: View {
    let visibleCount: Int
    let readyCount: Int
    let missingCredentialCount: Int
    let missingRequiredFieldCount: Int
    let quickSetupCount: Int
    let isTesting: Bool
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Keep credential gaps, quick-setup surface area, and probe activity visible before dropping into the full channel list."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: visibleCount == 1 ? String(localized: "1 visible channel") : String(localized: "\(visibleCount) visible channels"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: readyCount == 1 ? String(localized: "1 ready") : String(localized: "\(readyCount) ready"),
                        tone: readyCount > 0 ? .positive : .neutral
                    )
                    if missingCredentialCount > 0 {
                        PresentationToneBadge(
                            text: missingCredentialCount == 1 ? String(localized: "1 credential gap") : String(localized: "\(missingCredentialCount) credential gaps"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Channel section coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Use this slice to tell whether the visible channel section is mostly ready routes, missing fields, or quick-setup follow-up."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: isTesting ? String(localized: "Probe running") : String(localized: "Idle"),
                    tone: isTesting ? .warning : .neutral
                )
            } facts: {
                if missingRequiredFieldCount > 0 {
                    Label(
                        missingRequiredFieldCount == 1 ? String(localized: "1 missing field") : String(localized: "\(missingRequiredFieldCount) missing fields"),
                        systemImage: "exclamationmark.circle"
                    )
                }
                if quickSetupCount > 0 {
                    Label(
                        quickSetupCount == 1 ? String(localized: "1 quick-setup channel") : String(localized: "\(quickSetupCount) quick-setup channels"),
                        systemImage: "bolt"
                    )
                }
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        missingCredentialCount > 0
            ? String(localized: "Channel coverage is currently anchored by \(missingCredentialCount) visible credential gaps.")
            : String(localized: "Channel coverage currently spans \(readyCount) ready channels in the visible section.")
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

private struct IntegrationModelsSnapshotCard: View {
    let models: [CatalogModel]
    let modelFilter: IntegrationsModelFilter

    private var providerCount: Int {
        Set(models.map { $0.provider.lowercased() }).count
    }

    private var availableCount: Int {
        models.filter(\.available).count
    }

    private var toolReadyCount: Int {
        models.filter(\.supportsTools).count
    }

    private var topProvider: String? {
        Dictionary(grouping: models, by: { $0.provider })
            .max { $0.value.count < $1.value.count }?
            .key
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Model availability stays visible before the longer catalog inventory."),
                detail: String(localized: "Use the summary to see provider spread, available models, and tool-capable coverage before opening the model rows."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: models.count == 1 ? String(localized: "1 model visible") : String(localized: "\(models.count) models visible"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: availableCount == 1 ? String(localized: "1 available") : String(localized: "\(availableCount) available"),
                        tone: availableCount > 0 ? .positive : .warning
                    )
                    PresentationToneBadge(
                        text: providerCount == 1 ? String(localized: "1 provider") : String(localized: "\(providerCount) providers"),
                        tone: .neutral
                    )
                    PresentationToneBadge(
                        text: modelFilter.label,
                        tone: modelFilter == .unavailable ? .warning : .neutral
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Model facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep availability, provider spread, and tool-capable catalog depth visible before scanning the model list."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if let topProvider {
                    PresentationToneBadge(
                        text: topProvider,
                        tone: .neutral
                    )
                }
            } facts: {
                Label(
                    models.count == 1 ? String(localized: "1 model") : String(localized: "\(models.count) models"),
                    systemImage: "square.stack.3d.up"
                )
                Label(
                    availableCount == 1 ? String(localized: "1 available") : String(localized: "\(availableCount) available"),
                    systemImage: "checkmark.circle"
                )
                Label(
                    toolReadyCount == 1 ? String(localized: "1 tool-ready") : String(localized: "\(toolReadyCount) tool-ready"),
                    systemImage: "hammer"
                )
                if let topProvider {
                    Label(topProvider, systemImage: "cloud")
                }
            }
        }
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

private struct IntegrationAliasesSnapshotCard: View {
    let aliases: [ModelAliasEntry]

    private var targetCount: Int {
        Set(aliases.map(\.modelId)).count
    }

    private var longestAlias: ModelAliasEntry? {
        aliases.max { $0.alias.count < $1.alias.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Alias coverage stays visible before the longer alias map."),
                detail: String(localized: "Use the summary to see how many alias entries point into the catalog before opening the alias list."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: aliases.count == 1 ? String(localized: "1 alias visible") : String(localized: "\(aliases.count) aliases visible"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: targetCount == 1 ? String(localized: "1 target model") : String(localized: "\(targetCount) target models"),
                        tone: .neutral
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Alias facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep alias count and target coverage visible before scrolling the longer alias mapping list."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if let longestAlias {
                    PresentationToneBadge(
                        text: longestAlias.alias,
                        tone: .neutral
                    )
                }
            } facts: {
                Label(
                    aliases.count == 1 ? String(localized: "1 alias") : String(localized: "\(aliases.count) aliases"),
                    systemImage: "arrow.left.arrow.right"
                )
                Label(
                    targetCount == 1 ? String(localized: "1 target model") : String(localized: "\(targetCount) target models"),
                    systemImage: "square.stack.3d.up"
                )
                if let longestAlias {
                    Label(longestAlias.modelId, systemImage: "cpu")
                }
            }
        }
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

private struct IntegrationDriftSnapshotCard: View {
    let diagnostics: [AgentModelDiagnostic]

    private var unknownCount: Int {
        diagnostics.filter { $0.kind == .unknownModel }.count
    }

    private var unavailableCount: Int {
        diagnostics.filter { $0.kind == .unavailableModel }.count
    }

    private var mismatchCount: Int {
        diagnostics.filter { $0.kind == .providerMismatch }.count
    }

    private var affectedProviderCount: Int {
        Set(diagnostics.compactMap { $0.resolvedModel?.provider.lowercased() }).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Agent drift stays visible before the longer mismatch list."),
                detail: String(localized: "Use the summary to see how many agents are unknown, unavailable, or provider-mismatched before opening the drift inventory."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: diagnostics.count == 1 ? String(localized: "1 drifted agent") : String(localized: "\(diagnostics.count) drifted agents"),
                        tone: .warning
                    )
                    if unknownCount > 0 {
                        PresentationToneBadge(
                            text: unknownCount == 1 ? String(localized: "1 unknown") : String(localized: "\(unknownCount) unknown"),
                            tone: .critical
                        )
                    }
                    if unavailableCount > 0 {
                        PresentationToneBadge(
                            text: unavailableCount == 1 ? String(localized: "1 unavailable") : String(localized: "\(unavailableCount) unavailable"),
                            tone: .warning
                        )
                    }
                    if mismatchCount > 0 {
                        PresentationToneBadge(
                            text: mismatchCount == 1 ? String(localized: "1 mismatch") : String(localized: "\(mismatchCount) mismatches"),
                            tone: .caution
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Drift facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep unknown models, unavailable catalog entries, and provider mismatch spread visible before opening affected agents."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if affectedProviderCount > 0 {
                    PresentationToneBadge(
                        text: affectedProviderCount == 1 ? String(localized: "1 provider") : String(localized: "\(affectedProviderCount) providers"),
                        tone: .neutral
                    )
                }
            } facts: {
                Label(
                    diagnostics.count == 1 ? String(localized: "1 drifted agent") : String(localized: "\(diagnostics.count) drifted agents"),
                    systemImage: "cpu"
                )
                if unknownCount > 0 {
                    Label(
                        unknownCount == 1 ? String(localized: "1 unknown") : String(localized: "\(unknownCount) unknown"),
                        systemImage: "questionmark.circle"
                    )
                }
                if unavailableCount > 0 {
                    Label(
                        unavailableCount == 1 ? String(localized: "1 unavailable") : String(localized: "\(unavailableCount) unavailable"),
                        systemImage: "xmark.circle"
                    )
                }
                if mismatchCount > 0 {
                    Label(
                        mismatchCount == 1 ? String(localized: "1 mismatch") : String(localized: "\(mismatchCount) mismatches"),
                        systemImage: "arrow.triangle.branch"
                    )
                }
            }
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

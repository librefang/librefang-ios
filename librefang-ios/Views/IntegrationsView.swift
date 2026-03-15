import SwiftUI

private enum IntegrationsModelFilter: String, CaseIterable, Identifiable {
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

enum IntegrationsScope: String, CaseIterable, Identifiable {
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

    init(initialSearchText: String = "", initialScope: IntegrationsScope = .attention) {
        _searchText = State(initialValue: initialSearchText)
        _scope = State(initialValue: initialScope)
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
            ViewThatFits(in: .horizontal) {
                HStack {
                    titleLabel
                    Spacer()
                    IntegrationStatusChip(text: vm.catalogSyncStatusLabel, tone: vm.catalogSyncTone)
                }

                VStack(alignment: .leading, spacing: 8) {
                    titleLabel
                    IntegrationStatusChip(text: vm.catalogSyncStatusLabel, tone: vm.catalogSyncTone)
                }
            }

            Text(detailText)
                .font(.caption)
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    summaryFacts
                }

                VStack(alignment: .leading, spacing: 4) {
                    summaryFacts
                }
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
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    providerSummary
                    Spacer()
                    providerControls
                }

                VStack(alignment: .leading, spacing: 8) {
                    providerSummary
                    providerControls
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    providerFacts
                }

                VStack(alignment: .leading, spacing: 4) {
                    providerFacts
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

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
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    channelSummary
                    Spacer()
                    channelControls
                }

                VStack(alignment: .leading, spacing: 8) {
                    channelSummary
                    channelControls
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    channelFacts
                }

                VStack(alignment: .leading, spacing: 4) {
                    channelFacts
                }
            }
            .font(.caption)

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
        HStack(alignment: .top, spacing: 12) {
            Text(channel.icon)
                .font(.title3)
                .frame(width: 28)

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
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    modelSummary
                    Spacer()
                    availabilityChip
                }

                VStack(alignment: .leading, spacing: 8) {
                    modelSummary
                    availabilityChip
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    modelFacts
                }

                VStack(alignment: .leading, spacing: 4) {
                    modelFacts
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    capabilityChips
                }

                VStack(alignment: .leading, spacing: 4) {
                    capabilityChips
                }
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
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    diagnosticSummary
                    Spacer()
                    IntegrationStatusChip(text: diagnostic.localizedStatusLabel, tone: diagnostic.statusTone)
                }

                VStack(alignment: .leading, spacing: 8) {
                    diagnosticSummary
                    IntegrationStatusChip(text: diagnostic.localizedStatusLabel, tone: diagnostic.statusTone)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    diagnosticFacts
                }

                VStack(alignment: .leading, spacing: 4) {
                    diagnosticFacts
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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

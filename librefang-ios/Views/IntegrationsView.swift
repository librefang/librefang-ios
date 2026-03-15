import SwiftUI

private enum IntegrationsModelFilter: String, CaseIterable, Identifiable {
    case available
    case all
    case unavailable

    var id: String { rawValue }

    var label: String {
        switch self {
        case .available:
            "Available"
        case .all:
            "All"
        case .unavailable:
            "Unavailable"
        }
    }
}

struct IntegrationsView: View {
    @Environment(\.dependencies) private var deps
    @State private var searchText = ""
    @State private var modelFilter: IntegrationsModelFilter = .available
    @State private var providerProbeResults: [String: IntegrationProbeResult] = [:]
    @State private var channelProbeResults: [String: IntegrationProbeResult] = [:]
    @State private var providerProbeInFlightID: String?
    @State private var channelProbeInFlightID: String?
    @State private var operatorNotice: OperatorActionNotice?

    private var vm: DashboardViewModel { deps.dashboardViewModel }

    init(initialSearchText: String = "") {
        _searchText = State(initialValue: initialSearchText)
    }

    private var filteredProviders: [ProviderStatus] {
        vm.providers
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
        vm.modelAliases
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

    var body: some View {
        List {
            Section {
                IntegrationsScoreboard(vm: vm)
                    .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
            }

            if !vm.catalogModels.isEmpty {
                Section {
                    Picker("Models", selection: $modelFilter) {
                        ForEach(IntegrationsModelFilter.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
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
                title: "\(provider.displayName) Test",
                message: probeSummary(for: result)
            )
        } catch {
            operatorNotice = OperatorActionNotice(
                title: "\(provider.displayName) Test",
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
                title: "\(channel.displayName) Test",
                message: probeSummary(for: result)
            )
        } catch {
            operatorNotice = OperatorActionNotice(
                title: "\(channel.displayName) Test",
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
            return result.isHealthy ? "Probe passed in \(latencyMs) ms." : "Probe failed after \(latencyMs) ms."
        }
        return result.isHealthy ? "Probe passed." : "Probe failed."
    }
}

private struct IntegrationsScoreboard: View {
    let vm: DashboardViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            StatBadge(
                value: "\(vm.configuredProviderCount)/\(max(vm.providers.count, 1))",
                label: "Providers",
                icon: "key.horizontal",
                color: vm.configuredProviderCount > 0 ? .blue : .orange
            )
            StatBadge(
                value: "\(vm.unreachableLocalProviderCount)",
                label: "Local Down",
                icon: "network.slash",
                color: vm.unreachableLocalProviderCount > 0 ? .orange : .secondary
            )
            StatBadge(
                value: "\(vm.readyChannelCount)/\(max(vm.configuredChannelCount, 1))",
                label: "Channels",
                icon: "bubble.left.and.bubble.right",
                color: vm.readyChannelCount > 0 ? .teal : .secondary
            )
            StatBadge(
                value: "\(vm.channelCredentialGapCount)",
                label: "Credential Gaps",
                icon: "bubble.left.and.exclamationmark.bubble.right",
                color: vm.channelCredentialGapCount > 0 ? .orange : .secondary
            )
            StatBadge(
                value: "\(vm.availableCatalogModelCount)/\(max(vm.catalogModels.count, 1))",
                label: "Models",
                icon: "square.stack.3d.up",
                color: vm.availableCatalogModelCount > 0 ? .green : .orange
            )
            StatBadge(
                value: "\(vm.modelAliasCount)",
                label: "Aliases",
                icon: "arrow.left.arrow.right",
                color: vm.modelAliasCount > 0 ? .indigo : .secondary
            )
            StatBadge(
                value: "\(vm.agentsWithModelDiagnostics.count)",
                label: "Agent Drift",
                icon: "cpu",
                color: vm.agentsWithModelDiagnostics.isEmpty ? .secondary : .orange
            )
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
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.displayName)
                        .font(.subheadline.weight(.medium))
                    Text(provider.id)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let baseURL = provider.baseURL, !baseURL.isEmpty {
                        Text(baseURL)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    IntegrationStatusChip(text: statusText, color: statusColor)
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

            HStack(spacing: 12) {
                Label("\(provider.modelCount)", systemImage: "square.stack.3d.up")
                if provider.keyRequired {
                    Label(provider.apiKeyEnv ?? "API key", systemImage: "key.horizontal")
                }
                if let latencyMs = provider.latencyMs, provider.isLocal == true {
                    Label("\(latencyMs) ms", systemImage: "speedometer")
                }
                if let discoveredModels = provider.discoveredModels, !discoveredModels.isEmpty {
                    Label("\(discoveredModels.count) discovered", systemImage: "sparkles")
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

    private var statusText: String {
        if provider.isLocal == true {
            if provider.reachable == true {
                return "Reachable"
            }
            if provider.reachable == false {
                return "Unavailable"
            }
            return "Local"
        }
        return provider.isConfigured ? "Configured" : "Missing"
    }

    private var statusColor: Color {
        if provider.isLocal == true {
            return provider.reachable == false ? .orange : .green
        }
        return provider.isConfigured ? .green : .secondary
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
            return result.isHealthy ? "Last manual probe: \(latencyMs) ms" : "Last manual probe failed in \(latencyMs) ms"
        }
        return result.isHealthy ? "Last manual probe passed." : "Last manual probe failed."
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
                    Text("\(channel.category.capitalized) · \(channel.setupType.capitalized) · \(channel.difficulty.capitalized)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    IntegrationStatusChip(text: statusText, color: statusColor)
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

            HStack(spacing: 12) {
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

    private var statusText: String {
        if channel.configured {
            return channel.hasToken ? "Ready" : "Needs Token"
        }
        return "Not Set"
    }

    private var statusColor: Color {
        if channel.configured {
            return channel.hasToken ? .green : .orange
        }
        return .secondary
    }

    private func probeCaption(for result: IntegrationProbeResult) -> String {
        if let message = result.message, !message.isEmpty {
            return message
        }
        if let error = result.error, !error.isEmpty {
            return error
        }
        return result.isHealthy ? "Credential probe passed." : "Credential probe failed."
    }

    private var missingFieldSummary: String {
        let preview = missingRequiredFields.prefix(3).map { field in
            field.envVar ?? field.label
        }
        let suffix = missingRequiredFields.count > preview.count ? " +\(missingRequiredFields.count - preview.count) more" : ""
        return "Missing required fields: \(preview.joined(separator: " • "))\(suffix)"
    }
}

private struct IntegrationModelRow: View {
    let model: CatalogModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.displayName)
                        .font(.subheadline.weight(.medium))
                    Text(model.id)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                IntegrationStatusChip(text: model.available ? "Available" : "Unavailable", color: model.available ? .green : .orange)
            }

            HStack(spacing: 12) {
                Label(model.provider, systemImage: "cloud")
                Label(model.tier.capitalized, systemImage: "square.3.layers.3d")
                if let contextWindow = model.contextWindow {
                    Label(contextWindow.formatted(), systemImage: "text.redaction")
                }
                if let maxOutputTokens = model.maxOutputTokens {
                    Label(maxOutputTokens.formatted(), systemImage: "arrow.up.right.square")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                capabilityTag("Tools", isEnabled: model.supportsTools)
                capabilityTag("Vision", isEnabled: model.supportsVision)
                capabilityTag("Streaming", isEnabled: model.supportsStreaming)
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
        let input = model.inputCostPerM.map { String(format: "$%.2f/M in", $0) } ?? "n/a in"
        let output = model.outputCostPerM.map { String(format: "$%.2f/M out", $0) } ?? "n/a out"
        return "\(input) · \(output)"
    }

    private func capabilityTag(_ title: String, isEnabled: Bool) -> some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((isEnabled ? Color.green : Color.secondary).opacity(0.12))
            .foregroundStyle(isEnabled ? .green : .secondary)
            .clipShape(Capsule())
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
            HStack(alignment: .top, spacing: 12) {
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
                Spacer()
                IntegrationStatusChip(text: statusText, color: statusColor)
            }

            HStack(spacing: 12) {
                Label(diagnostic.requestedModel, systemImage: "cpu")
                if let resolvedAlias = diagnostic.resolvedAlias {
                    Label(resolvedAlias.alias, systemImage: "arrow.left.arrow.right")
                }
                if let resolvedModel = diagnostic.resolvedModel {
                    Label(resolvedModel.provider, systemImage: "cloud")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var statusText: String {
        switch diagnostic.kind {
        case .unknownModel:
            "Unknown"
        case .unavailableModel:
            "Unavailable"
        case .providerMismatch:
            "Mismatch"
        }
    }

    private var statusColor: Color {
        switch diagnostic.kind {
        case .unknownModel:
            .red
        case .unavailableModel:
            .orange
        case .providerMismatch:
            .indigo
        }
    }
}

private struct IntegrationStatusChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

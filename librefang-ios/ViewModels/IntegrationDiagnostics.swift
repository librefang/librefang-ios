import Foundation

enum AgentModelDiagnosticKind: String {
    case unknownModel
    case unavailableModel
    case providerMismatch
}

struct AgentModelDiagnostic: Identifiable {
    let agent: Agent
    let requestedModel: String
    let resolvedModel: CatalogModel?
    let resolvedAlias: ModelAliasEntry?
    let kind: AgentModelDiagnosticKind
    let issueSummary: String
    let detail: String
    let severity: Int

    var id: String { agent.id }
}

extension DashboardViewModel {
    var unreachableLocalProviders: [ProviderStatus] {
        providers
            .filter { $0.isLocal == true && $0.reachable == false }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
            }
    }

    var channelsMissingRequiredFields: [ChannelStatus] {
        channels
            .filter { channel in
                let requiredFields = channel.fields?.filter(\.required) ?? []
                return !requiredFields.isEmpty && requiredFields.contains(where: { !$0.hasValue })
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
            }
    }

    var channelRequiredFieldGapCount: Int {
        channelsMissingRequiredFields.count
    }

    var missingRequiredChannelFieldCount: Int {
        channelsMissingRequiredFields.reduce(0) { partialResult, channel in
            partialResult + (channel.fields?.filter { $0.required && !$0.hasValue }.count ?? 0)
        }
    }

    var hasEmptyModelCatalog: Bool {
        !catalogModels.isEmpty && configuredProviderCount > 0 && availableCatalogModelCount == 0
    }

    var agentsWithModelDiagnostics: [AgentModelDiagnostic] {
        agents.compactMap(modelDiagnostic(for:))
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return lhs.severity > rhs.severity
                }
                return lhs.agent.name.localizedCompare(rhs.agent.name) == .orderedAscending
            }
    }

    var unavailableModelAgentCount: Int {
        agentsWithModelDiagnostics.filter { $0.kind == .unavailableModel }.count
    }

    func requestedModelReference(for agent: Agent) -> String? {
        normalizedModelReference(agent.modelName)
    }

    func resolvedAlias(for agent: Agent) -> ModelAliasEntry? {
        guard let requestedModel = normalizedModelReference(agent.modelName) else { return nil }
        return resolvedAlias(for: requestedModel)
    }

    func modelDiagnostic(for agent: Agent) -> AgentModelDiagnostic? {
        guard let requestedModel = normalizedModelReference(agent.modelName) else { return nil }

        let alias = resolvedAlias(for: requestedModel)
        let resolvedModel = resolvedCatalogModel(for: requestedModel)

        if let resolvedModel {
            if !resolvedModel.available {
                return AgentModelDiagnostic(
                    agent: agent,
                    requestedModel: requestedModel,
                    resolvedModel: resolvedModel,
                    resolvedAlias: alias,
                    kind: .unavailableModel,
                    issueSummary: String(localized: "Catalog model unavailable"),
                    detail: String(localized: "\(resolvedModel.displayName) is present in the catalog but not currently available for execution."),
                    severity: 4
                )
            }

            if let agentProvider = normalizedProviderReference(agent.modelProvider),
               agentProvider != resolvedModel.provider.lowercased() {
                return AgentModelDiagnostic(
                    agent: agent,
                    requestedModel: requestedModel,
                    resolvedModel: resolvedModel,
                    resolvedAlias: alias,
                    kind: .providerMismatch,
                    issueSummary: String(localized: "Provider drift"),
                    detail: String(localized: "Agent expects \(agentProvider), but the catalog resolves \(requestedModel) to \(resolvedModel.provider)."),
                    severity: 2
                )
            }

            return nil
        }

        return AgentModelDiagnostic(
            agent: agent,
            requestedModel: requestedModel,
            resolvedModel: nil,
            resolvedAlias: alias,
            kind: .unknownModel,
            issueSummary: String(localized: "Model missing from catalog"),
            detail: String(localized: "LibreFang cannot resolve \(requestedModel) from the current model catalog or alias map."),
            severity: 5
        )
    }

    func resolvedCatalogModel(for agent: Agent) -> CatalogModel? {
        guard let requestedModel = normalizedModelReference(agent.modelName) else { return nil }
        return resolvedCatalogModel(for: requestedModel)
    }

    private func resolvedCatalogModel(for requestedModel: String) -> CatalogModel? {
        if let direct = catalogModels.first(where: { $0.id.compare(requestedModel, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return direct
        }

        if let alias = resolvedAlias(for: requestedModel) {
            return catalogModels.first {
                $0.id.compare(alias.modelId, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }

        return nil
    }

    private func resolvedAlias(for requestedModel: String) -> ModelAliasEntry? {
        modelAliases.first {
            $0.alias.compare(requestedModel, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    private func normalizedModelReference(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedProviderReference(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}

import Foundation

@MainActor
@Observable
final class WatchedAgentDiagnosticsStore {
    private(set) var summaries: [String: WatchedAgentDiagnosticsSummary] = [:]
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false

    func summary(for agentID: String) -> WatchedAgentDiagnosticsSummary? {
        summaries[agentID]
    }

    func refresh(api: APIClientProtocol, agents: [Agent]) async {
        let watchedAgents = agents
        guard !watchedAgents.isEmpty else {
            summaries = [:]
            lastRefresh = Date()
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefresh = Date()
        }

        var updated: [String: WatchedAgentDiagnosticsSummary] = [:]

        await withTaskGroup(of: (String, WatchedAgentDiagnosticsSummary?).self) { group in
            for agent in watchedAgents {
                group.addTask {
                    async let deliveriesResponse = try? api.agentDeliveries(agentId: agent.id, limit: 20)
                    async let filesResponse = try? api.agentFiles(agentId: agent.id)

                    let deliveries = await deliveriesResponse?.receipts ?? []
                    let files = await filesResponse?.files ?? []

                    let failedDeliveries = deliveries.filter { $0.status == .failed }.count
                    let unsettledDeliveries = deliveries.filter { $0.status == .sent || $0.status == .bestEffort }.count
                    let missingIdentityFiles = files.filter { !$0.exists }.map(\.name)

                    let summary = WatchedAgentDiagnosticsSummary(
                        agentID: agent.id,
                        failedDeliveries: failedDeliveries,
                        unsettledDeliveries: unsettledDeliveries,
                        missingIdentityFiles: missingIdentityFiles
                    )

                    if summary.hasIssues {
                        return (agent.id, summary)
                    }
                    return (agent.id, nil)
                }
            }

            for await (agentID, summary) in group {
                if let summary {
                    updated[agentID] = summary
                } else {
                    updated.removeValue(forKey: agentID)
                }
            }
        }

        summaries = updated
    }
}

nonisolated struct WatchedAgentDiagnosticsSummary: Sendable, Hashable {
    let agentID: String
    let failedDeliveries: Int
    let unsettledDeliveries: Int
    let missingIdentityFiles: [String]

    var hasIssues: Bool {
        failedDeliveries > 0 || unsettledDeliveries > 0 || !missingIdentityFiles.isEmpty
    }

    var issueCount: Int {
        let deliveryIssues = (failedDeliveries > 0 ? 1 : 0) + (unsettledDeliveries > 0 ? 1 : 0)
        let fileIssues = missingIdentityFiles.isEmpty ? 0 : 1
        return deliveryIssues + fileIssues
    }

    var summaryLine: String {
        var parts: [String] = []
        if failedDeliveries > 0 {
            parts.append("\(failedDeliveries) failed deliveries")
        }
        if unsettledDeliveries > 0 {
            parts.append("\(unsettledDeliveries) unsettled")
        }
        if !missingIdentityFiles.isEmpty {
            parts.append("\(missingIdentityFiles.count) identity files missing")
        }
        return parts.joined(separator: " • ")
    }
}

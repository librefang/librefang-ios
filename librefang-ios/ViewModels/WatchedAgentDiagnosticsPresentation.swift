import Foundation

@MainActor
func watchedAgentDiagnosticPriorityItems(
    agents: [Agent],
    summaries: [String: WatchedAgentDiagnosticsSummary]
) -> [OnCallPriorityItem] {
    agents.compactMap { agent in
        guard let summary = summaries[agent.id], summary.hasIssues else { return nil }

        let severity: OnCallPrioritySeverity = summary.failedDeliveries > 0 ? .critical : .warning
        let rank = summary.failedDeliveries > 0 ? 82 : 68

        return OnCallPriorityItem(
            id: "watched-diagnostics:\(agent.id)",
            title: agent.name,
            detail: summary.summaryLine,
            footnote: "Watched agent diagnostics",
            symbolName: summary.failedDeliveries > 0 ? "exclamationmark.triangle.fill" : "doc.badge.gearshape",
            severity: severity,
            rank: rank,
            route: .agent(agent.id)
        )
    }
    .sorted { lhs, rhs in
        if lhs.rank != rhs.rank {
            return lhs.rank > rhs.rank
        }
        return lhs.title.localizedCompare(rhs.title) == .orderedAscending
    }
}

func mergeOnCallPriorityItems(
    _ base: [OnCallPriorityItem],
    with extras: [OnCallPriorityItem]
) -> [OnCallPriorityItem] {
    (base + extras).sorted { lhs, rhs in
        if lhs.rank != rhs.rank {
            return lhs.rank > rhs.rank
        }
        return lhs.title.localizedCompare(rhs.title) == .orderedAscending
    }
}

func watchedAgentDiagnosticDigestSummary(
    summaries: [String: WatchedAgentDiagnosticsSummary]
) -> String? {
    let issueAgents = summaries.values.filter(\.hasIssues)
    guard !issueAgents.isEmpty else { return nil }

    let failedAgents = issueAgents.filter { $0.failedDeliveries > 0 }.count
    let missingFileAgents = issueAgents.filter { !$0.missingIdentityFiles.isEmpty }.count

    var parts: [String] = []
    if failedAgents > 0 {
        parts.append(failedAgents == 1 ? "1 watched agent has delivery failures" : "\(failedAgents) watched agents have delivery failures")
    }
    if missingFileAgents > 0 {
        parts.append(missingFileAgents == 1 ? "1 watched agent is missing identity files" : "\(missingFileAgents) watched agents are missing identity files")
    }
    return parts.isEmpty ? "\(issueAgents.count) watched agents have operator issues" : parts.joined(separator: " · ")
}

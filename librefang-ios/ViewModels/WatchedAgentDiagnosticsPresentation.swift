import Foundation

@MainActor
func watchedAgentDiagnosticPriorityItems(
    agents: [Agent],
    summaries: [String: WatchedAgentDiagnosticsSummary]
) -> [OnCallPriorityItem] {
    agents.compactMap { agent in
        guard let summary = summaries[agent.id], summary.hasIssues else { return nil }

        let severity: OnCallPrioritySeverity = summary.failedDeliveries > 0 ? .critical : .warning
        let rank = summary.failedDeliveries > 0 ? 82 : (!summary.unavailableFallbackModels.isEmpty ? 74 : 68)

        return OnCallPriorityItem(
            id: "watched-diagnostics:\(agent.id)",
            title: agent.name,
            detail: summary.summaryLine,
            footnote: String(localized: "Watched agent diagnostics"),
            symbolName: summary.failedDeliveries > 0
                ? "exclamationmark.triangle.fill"
                : (!summary.unavailableFallbackModels.isEmpty ? "square.stack.3d.up.slash" : "doc.badge.gearshape"),
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
    let fallbackAgents = issueAgents.filter { !$0.unavailableFallbackModels.isEmpty }.count

    var parts: [String] = []
    if failedAgents > 0 {
        parts.append(failedAgents == 1
            ? String(localized: "1 watched agent has delivery failures")
            : String(localized: "\(failedAgents) watched agents have delivery failures"))
    }
    if missingFileAgents > 0 {
        parts.append(missingFileAgents == 1
            ? String(localized: "1 watched agent is missing identity files")
            : String(localized: "\(missingFileAgents) watched agents are missing identity files"))
    }
    if fallbackAgents > 0 {
        parts.append(fallbackAgents == 1
            ? String(localized: "1 watched agent has fallback drift")
            : String(localized: "\(fallbackAgents) watched agents have fallback drift"))
    }
    return parts.isEmpty
        ? String(localized: "\(issueAgents.count) watched agents have operator issues")
        : parts.joined(separator: " · ")
}

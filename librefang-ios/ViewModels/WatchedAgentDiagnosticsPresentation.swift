import Foundation

struct WatchedAgentDiagnosticBadge: Sendable, Hashable {
    let text: String
    let tone: PresentationTone
}

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

func watchedAgentAttentionItemsSorted(
    _ items: [AgentAttentionItem],
    summaries: [String: WatchedAgentDiagnosticsSummary]
) -> [AgentAttentionItem] {
    items.sorted { lhs, rhs in
        let lhsDiagnosticRank = watchedAgentDiagnosticRank(summary: summaries[lhs.agent.id])
        let rhsDiagnosticRank = watchedAgentDiagnosticRank(summary: summaries[rhs.agent.id])

        if lhsDiagnosticRank != rhsDiagnosticRank {
            return lhsDiagnosticRank > rhsDiagnosticRank
        }
        if lhs.severity != rhs.severity {
            return lhs.severity > rhs.severity
        }
        if lhs.agent.isRunning != rhs.agent.isRunning {
            return lhs.agent.isRunning && !rhs.agent.isRunning
        }
        return lhs.agent.name.localizedCompare(rhs.agent.name) == .orderedAscending
    }
}

func watchedAgentDiagnosticHeadline(summary: WatchedAgentDiagnosticsSummary) -> String {
    if summary.failedDeliveries > 0 {
        return String(localized: "Delivery failures")
    }
    if !summary.unavailableFallbackModels.isEmpty {
        return String(localized: "Fallback drift")
    }
    if !summary.missingIdentityFiles.isEmpty {
        return String(localized: "Identity files missing")
    }
    if summary.unsettledDeliveries > 0 {
        return String(localized: "Unsettled deliveries")
    }
    return String(localized: "Operator issue")
}

func watchedAgentDiagnosticIssueCountBadge(summary: WatchedAgentDiagnosticsSummary) -> WatchedAgentDiagnosticBadge {
    WatchedAgentDiagnosticBadge(
        text: summary.issueCount == 1
            ? String(localized: "1 operator issue")
            : String(localized: "\(summary.issueCount) operator issues"),
        tone: watchedAgentDiagnosticTone(summary: summary)
    )
}

func watchedAgentDiagnosticHeadlineBadge(summary: WatchedAgentDiagnosticsSummary) -> WatchedAgentDiagnosticBadge {
    WatchedAgentDiagnosticBadge(
        text: watchedAgentDiagnosticHeadline(summary: summary),
        tone: watchedAgentDiagnosticTone(summary: summary)
    )
}

func watchedAgentDiagnosticStatusBadge(summary: WatchedAgentDiagnosticsSummary) -> WatchedAgentDiagnosticBadge {
    if summary.failedDeliveries > 0 {
        return WatchedAgentDiagnosticBadge(
            text: summary.failedDeliveries == 1
                ? String(localized: "1 failed")
                : String(localized: "\(summary.failedDeliveries) failed"),
            tone: .critical
        )
    }
    if !summary.unavailableFallbackModels.isEmpty {
        return WatchedAgentDiagnosticBadge(
            text: summary.unavailableFallbackModels.count == 1
                ? String(localized: "1 fallback drift")
                : String(localized: "\(summary.unavailableFallbackModels.count) fallback drift"),
            tone: .warning
        )
    }
    return WatchedAgentDiagnosticBadge(
        text: summary.issueCount == 1
            ? String(localized: "1 issue")
            : String(localized: "\(summary.issueCount) issues"),
        tone: watchedAgentDiagnosticTone(summary: summary)
    )
}

func watchedAgentStateTone(
    agent: Agent,
    severity: Int,
    diagnostics: WatchedAgentDiagnosticsSummary?
) -> PresentationTone {
    if let diagnostics, diagnostics.hasIssues {
        return watchedAgentDiagnosticTone(summary: diagnostics)
    }
    if severity >= 10 {
        return .critical
    }
    if severity > 0 {
        return .warning
    }
    return agent.isRunning ? .positive : .neutral
}

private func watchedAgentDiagnosticTone(summary: WatchedAgentDiagnosticsSummary) -> PresentationTone {
    summary.failedDeliveries > 0 ? .critical : .warning
}

private func watchedAgentDiagnosticRank(summary: WatchedAgentDiagnosticsSummary?) -> Int {
    guard let summary, summary.hasIssues else { return 0 }

    if summary.failedDeliveries > 0 {
        return 400 + summary.failedDeliveries
    }
    if !summary.unavailableFallbackModels.isEmpty {
        return 300 + summary.unavailableFallbackModels.count
    }
    if !summary.missingIdentityFiles.isEmpty {
        return 200 + summary.missingIdentityFiles.count
    }
    if summary.unsettledDeliveries > 0 {
        return 100 + summary.unsettledDeliveries
    }
    return summary.issueCount
}

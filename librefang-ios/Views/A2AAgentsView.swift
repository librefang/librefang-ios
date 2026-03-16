import SwiftUI

private enum A2ASectionAnchor: Hashable {
    case agents
}

struct A2AAgentsView: View {
    @Environment(\.dependencies) private var deps
    @State private var searchText = ""

    private var agents: [A2AAgent] { deps.dashboardViewModel.a2aAgents?.agents ?? [] }
    private var filteredAgents: [A2AAgent] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return agents }
        return agents.filter { agent in
            agent.name.lowercased().contains(query)
                || (agent.description?.lowercased().contains(query) ?? false)
                || agent.url.lowercased().contains(query)
                || (agent.skills?.map(\.name).joined(separator: " ").lowercased().contains(query) ?? false)
        }
    }
    private var a2aPrimaryRouteCount: Int { 2 }
    private var a2aSupportRouteCount: Int { 1 }
    private var a2aSectionCount: Int { 3 }
    private var a2aSectionPreviewTitles: [String] {
        [String(localized: "Agents")]
    }
    private var visibleHostCount: Int {
        Set(filteredAgents.compactMap { URL(string: $0.url)?.host?.lowercased() }).count
    }
    private var visibleStreamingCount: Int {
        filteredAgents.filter { $0.capabilities?.streaming == true }.count
    }

    var body: some View {
        Group {
            if agents.isEmpty {
                ContentUnavailableView(
                    String(localized: "No External Agents"),
                    systemImage: "link.circle",
                    description: Text(String(localized: "Discover A2A agents from the server."))
                )
            } else {
                ScrollViewReader { proxy in
                    List {
                        Section {
                            A2ASummaryCard(
                                totalAgents: agents.count,
                                visibleAgents: filteredAgents.count,
                                streamingCount: agents.filter { $0.capabilities?.streaming == true }.count,
                                pushCount: agents.filter { $0.capabilities?.pushNotifications == true }.count
                            )
                        }

                        Section {
                            MonitoringSurfaceGroupCard(
                                title: String(localized: "Shortcuts"),
                                detail: String(localized: "Keep comms, runtime, and diagnostics exits closest to the external-agent directory.")
                            ) {
                                MonitoringShortcutRail(
                                    title: String(localized: "Primary"),
                                    detail: String(localized: "Use comms and runtime surfaces first.")
                                ) {
                                    NavigationLink {
                                        CommsView(api: deps.apiClient)
                                    } label: {
                                        MonitoringSurfaceShortcutChip(
                                            title: String(localized: "Comms"),
                                            systemImage: "point.3.connected.trianglepath.dotted"
                                        )
                                    }
                                    .buttonStyle(.plain)

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
                                    detail: String(localized: "Keep broader health and config checks behind the primary A2A exits.")
                                ) {
                                    NavigationLink {
                                        DiagnosticsView()
                                    } label: {
                                        MonitoringSurfaceShortcutChip(
                                            title: String(localized: "Diagnostics"),
                                            systemImage: "stethoscope"
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } header: {
                            Text(String(localized: "Shortcuts"))
                        } footer: {
                            Text(String(localized: "Use these routes when the external-agent directory needs runtime, comms, or diagnostics context."))
                        }

                        if filteredAgents.isEmpty {
                            Section {
                                ContentUnavailableView(
                                    String(localized: "No Search Results"),
                                    systemImage: "magnifyingglass",
                                    description: Text(String(localized: "Try a different agent name, skill, or endpoint query."))
                                )
                            } header: {
                                Text(String(localized: "Agents"))
                            }
                            .id(A2ASectionAnchor.agents)
                        } else {
                            Section {
                                ForEach(filteredAgents) { agent in
                                    A2AAgentRow(agent: agent)
                                }
                            } header: {
                                Text(String(localized: "Agents"))
                            }
                            .id(A2ASectionAnchor.agents)
                        }
                    }
                    .searchable(text: $searchText, prompt: Text(String(localized: "Search agent, skill, or URL")))
                    .navigationTitle(String(localized: "A2A Agents"))
                }
            }
        }
    }

    private func jump(_ proxy: ScrollViewProxy, to anchor: A2ASectionAnchor) {
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    private func a2aSectionPreviewJumpItems(_ proxy: ScrollViewProxy) -> [MonitoringSectionJumpItem] {
        [
            MonitoringSectionJumpItem(
                title: String(localized: "Agents"),
                systemImage: "link.circle",
                tone: visibleStreamingCount > 0 ? .positive : .neutral
            ) {
                jump(proxy, to: .agents)
            }
        ]
    }
}

private struct A2ASummaryCard: View {
    let totalAgents: Int
    let visibleAgents: Int
    let streamingCount: Int
    let pushCount: Int

    var body: some View {
        MonitoringSnapshotCard(
            summary: String(localized: "External agent inventory is available for quick inspection."),
            verticalPadding: 4
        ) {
            FlowLayout(spacing: 8) {
                PresentationToneBadge(
                    text: totalAgents == 1 ? String(localized: "1 agent") : String(localized: "\(totalAgents) agents"),
                    tone: .positive
                )
                if visibleAgents != totalAgents {
                    PresentationToneBadge(
                        text: String(localized: "\(visibleAgents) visible"),
                        tone: .warning
                    )
                }
                PresentationToneBadge(
                    text: streamingCount == 1 ? String(localized: "1 stream") : String(localized: "\(streamingCount) stream"),
                    tone: streamingCount > 0 ? .positive : .neutral
                )
                PresentationToneBadge(
                    text: pushCount == 1 ? String(localized: "1 push") : String(localized: "\(pushCount) push"),
                    tone: pushCount > 0 ? .positive : .neutral
                )
            }
        }
    }
}

private struct A2ASectionInventoryDeck: View {
    let sectionCount: Int
    let visibleAgentCount: Int
    let totalAgentCount: Int
    let hostCount: Int
    let streamingCount: Int
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Section coverage stays visible before routes and the external-agent directory."),
                detail: hasSearchScope
                    ? String(localized: "Use section coverage to confirm the scoped directory before pivoting into comms or runtime context.")
                    : String(localized: "Use section coverage to confirm how much external-agent context is ready before leaving the directory."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: sectionCount == 1 ? String(localized: "1 section ready") : String(localized: "\(sectionCount) sections ready"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: totalAgentCount == 1 ? String(localized: "1 catalog agent") : String(localized: "\(totalAgentCount) catalog agents"),
                        tone: totalAgentCount == 0 ? .neutral : .positive
                    )
                    if streamingCount > 0 {
                        PresentationToneBadge(
                            text: streamingCount == 1 ? String(localized: "1 stream-ready agent") : String(localized: "\(streamingCount) stream-ready agents"),
                            tone: .positive
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Section Coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep summary, routes, and the active directory slice visible before drilling into external-agent records."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleAgentCount == totalAgentCount
                        ? (visibleAgentCount == 1 ? String(localized: "1 visible agent") : String(localized: "\(visibleAgentCount) visible agents"))
                        : String(localized: "\(visibleAgentCount) of \(totalAgentCount) visible"),
                    tone: .positive
                )
            } facts: {
                Label(
                    hostCount == 1 ? String(localized: "1 endpoint host") : String(localized: "\(hostCount) endpoint hosts"),
                    systemImage: "network"
                )
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct A2APressureCoverageDeck: View {
    let visibleAgentCount: Int
    let hostCount: Int
    let streamingCount: Int
    let pushCount: Int
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to separate endpoint spread, streaming readiness, and push capability before opening the external-agent directory rows."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if hostCount > 0 {
                        PresentationToneBadge(
                            text: hostCount == 1 ? String(localized: "1 endpoint host") : String(localized: "\(hostCount) endpoint hosts"),
                            tone: .positive
                        )
                    }
                    if streamingCount > 0 {
                        PresentationToneBadge(
                            text: streamingCount == 1 ? String(localized: "1 stream-ready agent") : String(localized: "\(streamingCount) stream-ready agents"),
                            tone: .positive
                        )
                    }
                    if pushCount > 0 {
                        PresentationToneBadge(
                            text: pushCount == 1 ? String(localized: "1 push-ready agent") : String(localized: "\(pushCount) push-ready agents"),
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Pressure coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep directory breadth and capability spread readable before the external-agent rows and route rails take over."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleAgentCount == 1 ? String(localized: "1 visible agent") : String(localized: "\(visibleAgentCount) visible agents"),
                    tone: .positive
                )
            } facts: {
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
                if hostCount > 1 {
                    Label(String(localized: "Multi-host directory"), systemImage: "network")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if hasSearchScope {
            return String(localized: "A2A directory pressure is currently concentrated in a search-scoped external-agent slice.")
        }
        if hostCount > 1 {
            return String(localized: "A2A directory pressure is currently spread across multiple endpoint hosts.")
        }
        return String(localized: "A2A directory pressure is currently low and mostly reflects capability readiness.")
    }
}

private struct A2ASupportCoverageDeck: View {
    let visibleAgentCount: Int
    let totalAgentCount: Int
    let hostCount: Int
    let streamingCount: Int
    let pushCount: Int
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep endpoint breadth and capability-ready external-agent support visible before moving into comms, runtime, or diagnostics context."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: visibleAgentCount == totalAgentCount
                            ? (visibleAgentCount == 1 ? String(localized: "1 visible agent") : String(localized: "\(visibleAgentCount) visible agents"))
                            : String(localized: "\(visibleAgentCount) of \(totalAgentCount) visible"),
                        tone: visibleAgentCount > 0 ? .positive : .neutral
                    )
                    if hasSearchScope {
                        PresentationToneBadge(text: String(localized: "Search scoped"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Support coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep endpoint host spread, streaming readiness, and push support readable before leaving the external-agent directory."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: hostCount == 1 ? String(localized: "1 endpoint host") : String(localized: "\(hostCount) endpoint hosts"),
                    tone: hostCount > 0 ? .positive : .neutral
                )
            } facts: {
                if streamingCount > 0 {
                    Label(
                        streamingCount == 1 ? String(localized: "1 stream-ready agent") : String(localized: "\(streamingCount) stream-ready agents"),
                        systemImage: "waveform"
                    )
                }
                if pushCount > 0 {
                    Label(
                        pushCount == 1 ? String(localized: "1 push-ready agent") : String(localized: "\(pushCount) push-ready agents"),
                        systemImage: "bell.badge"
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
        if hasSearchScope {
            return String(localized: "A2A support coverage is currently narrowed to a filtered directory slice.")
        }
        if hostCount > 1 {
            return String(localized: "A2A support coverage is currently anchored by endpoint host spread.")
        }
        if streamingCount > 0 || pushCount > 0 {
            return String(localized: "A2A support coverage is currently anchored by streaming and push-ready agents.")
        }
        return String(localized: "A2A support coverage is currently light across the visible directory.")
    }
}

private struct A2AFocusCoverageDeck: View {
    let visibleAgentCount: Int
    let totalAgentCount: Int
    let hostCount: Int
    let streamingCount: Int
    let pushCount: Int
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep the dominant external-agent lane visible before moving from compact inventory into route rails and the full directory."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: visibleAgentCount == totalAgentCount
                            ? (visibleAgentCount == 1 ? String(localized: "1 visible agent") : String(localized: "\(visibleAgentCount) visible agents"))
                            : String(localized: "\(visibleAgentCount) of \(totalAgentCount) visible"),
                        tone: visibleAgentCount > 0 ? .positive : .neutral
                    )
                    if streamingCount > 0 {
                        PresentationToneBadge(
                            text: streamingCount == 1 ? String(localized: "1 stream-ready") : String(localized: "\(streamingCount) stream-ready"),
                            tone: .positive
                        )
                    }
                    if hasSearchScope {
                        PresentationToneBadge(text: String(localized: "Search scoped"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Focus coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the dominant external-agent lane readable before leaving the directory for comms, runtime, or diagnostics context."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: hostCount == 1 ? String(localized: "1 endpoint host") : String(localized: "\(hostCount) endpoint hosts"),
                    tone: hostCount > 0 ? .positive : .neutral
                )
            } facts: {
                if pushCount > 0 {
                    Label(
                        pushCount == 1 ? String(localized: "1 push-ready agent") : String(localized: "\(pushCount) push-ready agents"),
                        systemImage: "bell.badge"
                    )
                }
                if hostCount > 1 {
                    Label(String(localized: "Multi-host directory"), systemImage: "network")
                }
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if hasSearchScope {
            return String(localized: "A2A focus coverage is currently anchored by the filtered external-agent slice.")
        }
        if hostCount > 1 {
            return String(localized: "A2A focus coverage is currently anchored by multi-host endpoint spread.")
        }
        if streamingCount > 0 || pushCount > 0 {
            return String(localized: "A2A focus coverage is currently anchored by stream and push capability readiness.")
        }
        return String(localized: "A2A focus coverage is currently balanced across the visible external-agent directory.")
    }
}

private struct A2AWorkstreamCoverageDeck: View {
    let visibleAgentCount: Int
    let totalAgentCount: Int
    let hostCount: Int
    let streamingCount: Int
    let pushCount: Int
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to see whether external-agent review is currently led by host spread, streaming readiness, or scoped search before opening the full directory."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: visibleAgentCount == totalAgentCount
                            ? (visibleAgentCount == 1 ? String(localized: "1 visible agent") : String(localized: "\(visibleAgentCount) visible agents"))
                            : String(localized: "\(visibleAgentCount) of \(totalAgentCount) visible"),
                        tone: visibleAgentCount > 0 ? .positive : .neutral
                    )
                    if streamingCount > 0 {
                        PresentationToneBadge(
                            text: streamingCount == 1 ? String(localized: "1 stream-ready") : String(localized: "\(streamingCount) stream-ready"),
                            tone: .positive
                        )
                    }
                    if hasSearchScope {
                        PresentationToneBadge(text: String(localized: "Search scoped"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Workstream coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep host spread, streaming or push readiness, and scoped directory state readable before moving through the external-agent list."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: hostCount == 1 ? String(localized: "1 host") : String(localized: "\(hostCount) hosts"),
                    tone: hostCount > 0 ? .neutral : .positive
                )
            } facts: {
                if pushCount > 0 {
                    Label(
                        pushCount == 1 ? String(localized: "1 push-ready") : String(localized: "\(pushCount) push-ready"),
                        systemImage: "app.badge"
                    )
                }
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
    }

    private var summaryLine: String {
        if hostCount > 1 {
            return String(localized: "A2A workstream coverage is currently anchored by endpoint host spread.")
        }
        if streamingCount > 0 || pushCount > 0 {
            return String(localized: "A2A workstream coverage is currently anchored by capability readiness across visible agents.")
        }
        if hasSearchScope {
            return String(localized: "A2A workstream coverage is currently anchored by the filtered directory slice.")
        }
        return String(localized: "A2A workstream coverage is currently light across the visible directory.")
    }
}

private struct A2AActionReadinessDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let visibleAgentCount: Int
    let totalAgentCount: Int
    let hostCount: Int
    let streamingCount: Int
    let pushCount: Int
    let hasSearchScope: Bool

    private var totalRouteCount: Int {
        primaryRouteCount + supportRouteCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to check route breadth, host spread, and visible external-agent coverage before leaving the compact directory for comms, runtime, or diagnostics."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: totalRouteCount == 1 ? String(localized: "1 route ready") : String(localized: "\(totalRouteCount) routes ready"),
                        tone: totalRouteCount > 0 ? .positive : .neutral
                    )
                    if streamingCount > 0 {
                        PresentationToneBadge(
                            text: streamingCount == 1 ? String(localized: "1 stream-ready") : String(localized: "\(streamingCount) stream-ready"),
                            tone: .positive
                        )
                    }
                    if hasSearchScope {
                        PresentationToneBadge(text: String(localized: "Search scoped"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Action readiness"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep route breadth, endpoint host spread, and visible external-agent coverage readable before moving into the surrounding operator surfaces."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleAgentCount == totalAgentCount
                        ? (visibleAgentCount == 1 ? String(localized: "1 visible agent") : String(localized: "\(visibleAgentCount) visible agents"))
                        : String(localized: "\(visibleAgentCount) of \(totalAgentCount) visible"),
                    tone: visibleAgentCount > 0 ? .positive : .neutral
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
                Label(
                    hostCount == 1 ? String(localized: "1 endpoint host") : String(localized: "\(hostCount) endpoint hosts"),
                    systemImage: "network"
                )
                if pushCount > 0 {
                    Label(
                        pushCount == 1 ? String(localized: "1 push-ready agent") : String(localized: "\(pushCount) push-ready agents"),
                        systemImage: "bell.badge"
                    )
                }
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
    }

    private var summaryLine: String {
        if hasSearchScope {
            return String(localized: "A2A action readiness is currently anchored by the filtered external-agent slice and the next route exits.")
        }
        if hostCount > 1 {
            return String(localized: "A2A action readiness is currently anchored by multi-host endpoint spread and nearby route exits.")
        }
        if streamingCount > 0 || pushCount > 0 {
            return String(localized: "A2A action readiness is currently anchored by stream and push-ready external agents.")
        }
        return String(localized: "A2A action readiness is currently centered on compact route breadth and visible directory coverage.")
    }
}

private struct A2ARouteInventoryDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let visibleAgentCount: Int
    let totalAgentCount: Int
    let hostCount: Int
    let streamingCount: Int
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: hasSearchScope
                    ? String(localized: "External-agent routes stay compact while the directory is search-scoped.")
                    : String(localized: "External-agent routes stay compact before the comms and runtime drilldowns."),
                detail: String(localized: "Use the route inventory to gauge the active agent slice before leaving the external-agent directory."),
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
                    if streamingCount > 0 {
                        PresentationToneBadge(
                            text: streamingCount == 1 ? String(localized: "1 stream-ready agent") : String(localized: "\(streamingCount) stream-ready agents"),
                            tone: .positive
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Route Facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the visible external-agent slice and host spread visible before pivoting into comms, runtime, or diagnostics context."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleAgentCount == totalAgentCount
                        ? (visibleAgentCount == 1 ? String(localized: "1 visible agent") : String(localized: "\(visibleAgentCount) visible agents"))
                        : String(localized: "\(visibleAgentCount) of \(totalAgentCount) visible"),
                    tone: .positive
                )
            } facts: {
                Label(
                    hostCount == 1 ? String(localized: "1 endpoint host") : String(localized: "\(hostCount) endpoint hosts"),
                    systemImage: "network"
                )
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct A2AInventoryDeckCard: View {
    let agents: [A2AAgent]
    let totalAgents: Int
    let searchText: String

    private var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var streamingCount: Int {
        agents.filter { $0.capabilities?.streaming == true }.count
    }

    private var pushCount: Int {
        agents.filter { $0.capabilities?.pushNotifications == true }.count
    }

    private var historyCount: Int {
        agents.filter { $0.capabilities?.stateTransitionHistory == true }.count
    }

    private var hostCount: Int {
        Set(agents.compactMap { URL(string: $0.url)?.host?.lowercased() }).count
    }

    private var skillCount: Int {
        Set(agents.flatMap { $0.skills?.map(\.name) ?? [] }).count
    }

    private var tagCount: Int {
        Set(agents.flatMap { ($0.skills ?? []).flatMap { $0.tags ?? [] } }).count
    }

    private var mostSkilledAgent: A2AAgent? {
        agents.max { ($0.skills?.count ?? 0) < ($1.skills?.count ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: hasActiveSearch
                    ? String(localized: "The current external-agent slice stays summarized before the filtered directory.")
                    : String(localized: "The active external-agent slice stays summarized before the full directory."),
                detail: hasActiveSearch
                    ? (agents.count == 1
                        ? String(localized: "1 external agent matches the current query.")
                        : String(localized: "\(agents.count) external agents match the current query."))
                    : String(localized: "Use the compact deck to gauge streaming, push, and skill coverage before opening each external agent."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: agents.count == totalAgents
                            ? (agents.count == 1 ? String(localized: "1 visible agent") : String(localized: "\(agents.count) visible agents"))
                            : String(localized: "\(agents.count) of \(totalAgents) visible"),
                        tone: .positive
                    )
                    if streamingCount > 0 {
                        PresentationToneBadge(
                            text: streamingCount == 1 ? String(localized: "1 stream-ready") : String(localized: "\(streamingCount) stream-ready"),
                            tone: .positive
                        )
                    }
                    if pushCount > 0 {
                        PresentationToneBadge(
                            text: pushCount == 1 ? String(localized: "1 push-ready") : String(localized: "\(pushCount) push-ready"),
                            tone: .positive
                        )
                    }
                    if historyCount > 0 {
                        PresentationToneBadge(
                            text: historyCount == 1 ? String(localized: "1 history feed") : String(localized: "\(historyCount) history feeds"),
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Directory Facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep endpoint host spread, skill coverage, and the richest agent summary visible while triaging the external-agent directory."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if let mostSkilledAgent {
                    PresentationToneBadge(
                        text: (mostSkilledAgent.skills?.count ?? 0) == 1
                            ? String(localized: "Top agent: 1 skill")
                            : String(localized: "Top agent: \((mostSkilledAgent.skills?.count ?? 0)) skills"),
                        tone: .neutral
                    )
                }
            } facts: {
                Label(
                    hostCount == 1 ? String(localized: "1 endpoint host") : String(localized: "\(hostCount) endpoint hosts"),
                    systemImage: "network"
                )
                Label(
                    skillCount == 1 ? String(localized: "1 visible skill") : String(localized: "\(skillCount) visible skills"),
                    systemImage: "sparkles"
                )
                if tagCount > 0 {
                    Label(
                        tagCount == 1 ? String(localized: "1 skill tag") : String(localized: "\(tagCount) skill tags"),
                        systemImage: "tag"
                    )
                }
                if let mostSkilledAgent {
                    Label(mostSkilledAgent.name, systemImage: "person.crop.circle.badge.checkmark")
                }
            }
        }
    }
}

private struct A2AAgentRow: View {
    let agent: A2AAgent
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let desc = agent.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                A2AValueRow(label: "URL") {
                    Text(agent.url)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                if let version = agent.version {
                    A2AValueRow(label: "Version") {
                        Text(version)
                            .font(.caption)
                    }
                }

                if let caps = agent.capabilities {
                    FlowLayout(spacing: 6) {
                        CapabilityBadge(label: String(localized: "Stream"), enabled: caps.streaming ?? false)
                        CapabilityBadge(label: String(localized: "Push"), enabled: caps.pushNotifications ?? false)
                    }
                }

                if let skills = agent.skills, !skills.isEmpty {
                    Text(String(localized: "Skills"))
                        .font(.caption.weight(.medium))
                    FlowLayout(spacing: 4) {
                        ForEach(skills) { skill in
                            PresentationToneBadge(
                                text: skill.name,
                                tone: .neutral,
                                horizontalPadding: 8,
                                verticalPadding: 3
                            )
                        }
                    }
                }
            }
        } label: {
            ResponsiveIconDetailRow(verticalSpacing: 6) {
                headerIcon
            } detail: {
                headerSummary
            }
        }
    }

    private var headerIcon: some View {
        Image(systemName: "link.circle.fill")
            .foregroundStyle(.blue)
    }

    private var headerSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(agent.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            if let desc = agent.description {
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            FlowLayout(spacing: 6) {
                if let version = agent.version, !version.isEmpty {
                    PresentationToneBadge(text: version, tone: .neutral, horizontalPadding: 6, verticalPadding: 2)
                }
                if let skillCount = agent.skills?.count, skillCount > 0 {
                    PresentationToneBadge(
                        text: skillCount == 1 ? String(localized: "1 skill") : String(localized: "\(skillCount) skills"),
                        tone: .positive,
                        horizontalPadding: 6,
                        verticalPadding: 2
                    )
                }
            }
        }
    }
}

private struct CapabilityBadge: View {
    let label: String
    let enabled: Bool

    private var tone: PresentationTone {
        enabled ? .positive : .neutral
    }

    var body: some View {
        PresentationToneLabelBadge(
            text: label,
            systemImage: enabled ? "checkmark.circle.fill" : "xmark.circle",
            tone: tone
        )
    }
}

private struct A2AValueRow<Content: View>: View {
    let label: LocalizedStringKey
    let content: Content

    init(label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        ResponsiveValueRow {
            Text(label)
        } value: {
            content
        }
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

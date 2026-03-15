import SwiftUI

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

    var body: some View {
        Group {
            if agents.isEmpty {
                ContentUnavailableView(
                    String(localized: "No External Agents"),
                    systemImage: "link.circle",
                    description: Text(String(localized: "Discover A2A agents from the server."))
                )
            } else {
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
                            title: String(localized: "Primary Routes"),
                            detail: String(localized: "Keep comms and runtime exits closest to the external-agent directory.")
                        ) {
                            NavigationLink {
                                CommsView(api: deps.apiClient)
                            } label: {
                                MonitoringJumpRow(
                                    title: String(localized: "Comms"),
                                    detail: String(localized: "Switch to comms topology when external agents matter more than local inventory."),
                                    systemImage: "point.3.connected.trianglepath.dotted",
                                    tone: .neutral
                                )
                            }

                            NavigationLink {
                                RuntimeView()
                            } label: {
                                MonitoringJumpRow(
                                    title: String(localized: "Runtime"),
                                    detail: String(localized: "Switch to runtime when external-agent inventory needs broader network or hand context."),
                                    systemImage: "server.rack",
                                    tone: .neutral
                                )
                            }
                        }

                        MonitoringSurfaceGroupCard(
                            title: String(localized: "Support Routes"),
                            detail: String(localized: "Keep broader health and config checks behind the primary A2A exits.")
                        ) {
                            NavigationLink {
                                DiagnosticsView()
                            } label: {
                                MonitoringJumpRow(
                                    title: String(localized: "Diagnostics"),
                                    detail: String(localized: "Switch to diagnostics when A2A visibility issues may reflect runtime health or config drift."),
                                    systemImage: "stethoscope",
                                    tone: .neutral
                                )
                            }
                        }
                    } header: {
                        Text("Route Deck")
                    } footer: {
                        Text("Use these routes when the external-agent directory needs runtime, comms, or diagnostics context.")
                    }

                    if filteredAgents.isEmpty {
                        Section("Agents") {
                            ContentUnavailableView(
                                String(localized: "No Search Results"),
                                systemImage: "magnifyingglass",
                                description: Text(String(localized: "Try a different agent name, skill, or endpoint query."))
                            )
                        }
                    } else {
                        Section("Agents") {
                            ForEach(filteredAgents) { agent in
                                A2AAgentRow(agent: agent)
                            }
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search agent, skill, or URL")
                .navigationTitle("A2A Agents")
            }
        }
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

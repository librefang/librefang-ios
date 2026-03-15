import SwiftUI

struct A2AAgentsView: View {
    @Environment(\.dependencies) private var deps

    private var agents: [A2AAgent] { deps.dashboardViewModel.a2aAgents?.agents ?? [] }

    var body: some View {
        Group {
            if agents.isEmpty {
                ContentUnavailableView(
                    String(localized: "No External Agents"),
                    systemImage: "link.circle",
                    description: Text(String(localized: "Discover A2A agents from the server."))
                )
            } else {
                List(agents) { agent in
                    A2AAgentRow(agent: agent)
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

                LabeledContent {
                    Text(agent.url)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } label: {
                    Text(String(localized: "URL"))
                }

                if let version = agent.version {
                    LabeledContent {
                        Text(version)
                    } label: {
                        Text(String(localized: "Version"))
                    }
                        .font(.caption)
                }

                if let caps = agent.capabilities {
                    HStack(spacing: 12) {
                        CapabilityBadge(label: String(localized: "Stream"), enabled: caps.streaming ?? false)
                        CapabilityBadge(label: String(localized: "Push"), enabled: caps.pushNotifications ?? false)
                    }
                }

                if let skills = agent.skills, !skills.isEmpty {
                    Text(String(localized: "Skills"))
                        .font(.caption.weight(.medium))
                    FlowLayout(spacing: 4) {
                        ForEach(skills) { skill in
                            Text(skill.name)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(.systemGray5))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "link.circle.fill")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.subheadline.weight(.medium))
                    if let desc = agent.description {
                        Text(desc)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

private struct CapabilityBadge: View {
    let label: String
    let enabled: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle")
                .font(.caption2)
                .foregroundStyle(enabled ? .green : .secondary)
            Text(label)
                .font(.caption2)
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

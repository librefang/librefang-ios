import SwiftUI

struct RuntimeView: View {
    @Environment(\.dependencies) private var deps

    private var vm: DashboardViewModel { deps.dashboardViewModel }

    private var sortedProviders: [ProviderStatus] {
        vm.providers.sorted { lhs, rhs in
            switch (lhs.isConfigured, rhs.isConfigured) {
            case (true, false): true
            case (false, true): false
            default: lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
            }
        }
    }

    private var configuredChannels: [ChannelStatus] {
        vm.channels.filter(\.configured).sorted {
            $0.displayName.localizedCompare($1.displayName) == .orderedAscending
        }
    }

    private var degradedHands: [HandDefinition] {
        vm.hands.filter(\.degraded).sorted {
            $0.name.localizedCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = vm.error, vm.status == nil {
                    Section {
                        ErrorBanner(message: error, onRetry: {
                            await vm.refresh()
                        }, onDismiss: {
                            vm.error = nil
                        })
                        .listRowInsets(.init())
                        .listRowBackground(Color.clear)
                    }
                }

                Section {
                    RuntimeScoreboard(vm: vm)
                        .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
                }

                if let status = vm.status {
                    Section("System") {
                        LabeledContent("Kernel") {
                            StatusPill(text: status.status.capitalized, color: status.status == "running" ? .green : .red)
                        }
                        LabeledContent("Version", value: status.version)
                        LabeledContent("Uptime") {
                            Text(formatDuration(status.uptimeSeconds))
                                .monospacedDigit()
                        }
                        LabeledContent("Agents") {
                            Text("\(status.agentCount)")
                                .monospacedDigit()
                        }
                        LabeledContent("Default Model") {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(status.defaultModel)
                                    .lineLimit(1)
                                Text(status.defaultProvider)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        LabeledContent("Network") {
                            StatusPill(text: status.networkEnabled ? "Enabled" : "Disabled", color: status.networkEnabled ? .green : .orange)
                        }
                    }
                }

                if let usage = vm.usageSummary {
                    Section("Usage") {
                        RuntimeMetricRow(
                            label: "Tokens",
                            value: "\(usage.totalInputTokens.formatted()) in / \(usage.totalOutputTokens.formatted()) out",
                            detail: "\(vm.totalTokenCount.formatted()) total"
                        )
                        RuntimeMetricRow(
                            label: "Tool Calls",
                            value: usage.totalToolCalls.formatted(),
                            detail: "\(usage.callCount.formatted()) LLM calls"
                        )
                        RuntimeMetricRow(
                            label: "Accumulated Cost",
                            value: currency(usage.totalCostUsd),
                            detail: usage.totalCostUsd > 0 ? "All recorded sessions" : "No spend recorded"
                        )
                    }
                }

                if !sortedProviders.isEmpty {
                    Section("Providers") {
                        ForEach(sortedProviders) { provider in
                            ProviderStatusRow(provider: provider)
                        }
                    } footer: {
                        Text("\(vm.configuredProviderCount)/\(sortedProviders.count) configured")
                    }
                }

                if !configuredChannels.isEmpty || !vm.channels.isEmpty {
                    Section("Channels") {
                        if configuredChannels.isEmpty {
                            RuntimeEmptyRow(
                                title: "No channels configured",
                                subtitle: "Desktop or web can finish setup. Mobile focuses on status tracking."
                            )
                        } else {
                            ForEach(configuredChannels.prefix(8)) { channel in
                                ChannelStatusRow(channel: channel)
                            }
                        }
                    } footer: {
                        if configuredChannels.count > 8 {
                            Text("Showing 8 of \(configuredChannels.count) configured channels")
                        } else {
                            Text("\(vm.readyChannelCount) ready, \(vm.configuredChannelCount) configured")
                        }
                    }
                }

                if let a2a = vm.a2aAgents, a2a.total > 0 {
                    Section("A2A Network") {
                        RuntimeMetricRow(
                            label: "Connected Agents",
                            value: "\(a2a.total)",
                            detail: "External agents discovered through A2A"
                        )

                        ForEach(a2a.agents.prefix(5)) { agent in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(agent.name)
                                    .font(.subheadline.weight(.medium))
                                if let description = agent.description, !description.isEmpty {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if let network = vm.networkStatus {
                    Section("OFP Network") {
                        RuntimeMetricRow(
                            label: "Status",
                            value: network.enabled ? "Enabled" : "Disabled",
                            detail: network.enabled ? network.listenAddress : "Shared secret or network mode not configured"
                        )
                        RuntimeMetricRow(
                            label: "Peers",
                            value: "\(network.connectedPeers)/\(max(network.totalPeers, vm.peers.count)) connected",
                            detail: network.nodeId.isEmpty ? "Local node inactive" : "Node \(shortNodeId(network.nodeId))"
                        )

                        if vm.peers.isEmpty {
                            RuntimeEmptyRow(
                                title: "No peers discovered",
                                subtitle: network.enabled ? "The wire network is enabled but no peers are currently visible." : "Enable peer networking on the server to surface node status."
                            )
                        } else {
                            ForEach(vm.peers.prefix(5)) { peer in
                                PeerRow(peer: peer)
                            }
                        }
                    }
                }

                if !vm.activeHands.isEmpty || !degradedHands.isEmpty || !vm.hands.isEmpty {
                    Section("Hands") {
                        if vm.activeHands.isEmpty {
                            RuntimeEmptyRow(
                                title: "No active hands",
                                subtitle: "When autonomous hands are activated, their runtime status appears here."
                            )
                        } else {
                            ForEach(vm.activeHands) { instance in
                                HandInstanceRow(instance: instance)
                            }
                        }

                        if !degradedHands.isEmpty {
                            ForEach(degradedHands.prefix(4)) { hand in
                                HandDefinitionRow(hand: hand)
                            }
                        }
                    } footer: {
                        Text("\(vm.activeHandCount) active, \(vm.degradedHandCount) degraded")
                    }
                }

                if !vm.approvals.isEmpty {
                    Section("Pending Approvals") {
                        ForEach(vm.approvals) { approval in
                            ApprovalRow(approval: approval)
                        }
                    } footer: {
                        Text("Approvals require attention in the primary dashboard or desktop UI.")
                    }
                }

                if let security = vm.security {
                    Section("Security") {
                        RuntimeMetricRow(
                            label: "Protections",
                            value: "\(security.totalFeatures)",
                            detail: "Active defense layers"
                        )
                        RuntimeMetricRow(
                            label: "Auth",
                            value: security.configurable.auth.mode.replacingOccurrences(of: "_", with: " ").capitalized,
                            detail: security.configurable.auth.apiKeySet ? "API key configured" : "No API key configured"
                        )
                        RuntimeMetricRow(
                            label: "Audit Trail",
                            value: security.monitoring.auditTrail.algorithm,
                            detail: "\(security.monitoring.auditTrail.entryCount.formatted()) entries"
                        )
                    }
                }
            }
            .navigationTitle("Runtime")
            .refreshable {
                await vm.refresh()
            }
            .overlay {
                if vm.isLoading && vm.status == nil && vm.providers.isEmpty && vm.channels.isEmpty {
                    ProgressView("Loading runtime...")
                }
            }
            .task {
                if vm.status == nil && vm.providers.isEmpty {
                    await vm.refresh()
                }
            }
        }
    }

    private func currency(_ value: Double) -> String {
        if value == 0 { return "$0.00" }
        if value < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", value)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func shortNodeId(_ id: String) -> String {
        guard id.count > 12 else { return id }
        return String(id.prefix(6)) + "..." + String(id.suffix(4))
    }
}

private struct RuntimeScoreboard: View {
    let vm: DashboardViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            StatBadge(
                value: "\(vm.runningCount)/\(vm.totalCount)",
                label: "Agents",
                icon: "cpu",
                color: vm.runningCount > 0 ? .green : .secondary
            )
            StatBadge(
                value: "\(vm.configuredProviderCount)",
                label: "Providers",
                icon: "key.horizontal",
                color: vm.configuredProviderCount > 0 ? .blue : .orange
            )
            StatBadge(
                value: "\(vm.readyChannelCount)",
                label: "Channels",
                icon: "bubble.left.and.bubble.right",
                color: vm.readyChannelCount > 0 ? .teal : .secondary
            )
            StatBadge(
                value: "\(vm.activeHandCount)",
                label: "Hands",
                icon: "hand.raised",
                color: vm.degradedHandCount > 0 ? .orange : .indigo
            )
            StatBadge(
                value: "\(vm.pendingApprovalCount)",
                label: "Approvals",
                icon: "exclamationmark.shield",
                color: vm.pendingApprovalCount > 0 ? .red : .green
            )
            StatBadge(
                value: "\(vm.securityFeatureCount)",
                label: "Security",
                icon: "lock.shield",
                color: vm.securityFeatureCount > 0 ? .green : .secondary
            )
        }
        .padding(.horizontal)
    }
}

private struct RuntimeMetricRow: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.trailing)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

private struct ProviderStatusRow: View {
    let provider: ProviderStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.subheadline.weight(.medium))
                    Text(provider.id)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(text: statusText, color: statusColor)
            }

            HStack(spacing: 12) {
                Label("\(provider.modelCount)", systemImage: "square.stack.3d.up")
                    .foregroundStyle(.secondary)
                if let latencyMs = provider.latencyMs, provider.isLocal == true {
                    Label("\(latencyMs) ms", systemImage: "speedometer")
                        .foregroundStyle(.secondary)
                }
                if provider.discoveredModels?.isEmpty == false {
                    Label("\(provider.discoveredModels?.count ?? 0) discovered", systemImage: "sparkles")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }

    private var statusText: String {
        if provider.isLocal == true {
            return provider.reachable == true ? "Reachable" : "Unavailable"
        }
        return provider.isConfigured ? "Configured" : "Missing"
    }

    private var statusColor: Color {
        if provider.isLocal == true {
            return provider.reachable == true ? .green : .orange
        }
        return provider.isConfigured ? .green : .secondary
    }
}

private struct ChannelStatusRow: View {
    let channel: ChannelStatus

    var body: some View {
        HStack(spacing: 12) {
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
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                StatusPill(
                    text: channel.hasToken ? "Ready" : "Needs Token",
                    color: channel.hasToken ? .green : .orange
                )
                Text(channel.category.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct HandInstanceRow: View {
    let instance: HandInstance

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(instance.handId.capitalized)
                        .font(.subheadline.weight(.medium))
                    if let agentName = instance.agentName, !agentName.isEmpty {
                        Text(agentName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                StatusPill(text: instance.status.capitalized, color: statusColor)
            }

            HStack(spacing: 12) {
                Label(relativeText(from: instance.activatedAt), systemImage: "play.circle")
                Label(relativeText(from: instance.updatedAt), systemImage: "clock.arrow.circlepath")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        switch instance.status.lowercased() {
        case "active", "running":
            .green
        case "paused":
            .orange
        default:
            .secondary
        }
    }

    private func relativeText(from value: String) -> String {
        guard let date = value.iso8601Date else { return value }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

private struct HandDefinitionRow: View {
    let hand: HandDefinition

    var body: some View {
        HStack(spacing: 12) {
            Text(hand.icon)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(hand.name)
                    .font(.subheadline.weight(.medium))
                Text(hand.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            StatusPill(
                text: hand.degraded ? "Degraded" : hand.requirementsMet ? "Ready" : "Blocked",
                color: hand.degraded ? .orange : hand.requirementsMet ? .green : .secondary
            )
        }
        .padding(.vertical, 2)
    }
}

private struct ApprovalRow: View {
    let approval: ApprovalItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(approval.actionSummary)
                        .font(.subheadline.weight(.medium))
                    Text(approval.agentName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(text: approval.riskLevel.capitalized, color: riskColor)
            }

            if !approval.description.isEmpty {
                Text(approval.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 12) {
                Label(approval.toolName, systemImage: "wrench.and.screwdriver")
                Label(relativeRequestedAt, systemImage: "clock")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var riskColor: Color {
        switch approval.riskLevel.lowercased() {
        case "critical":
            .red
        case "high":
            .orange
        default:
            .yellow
        }
    }

    private var relativeRequestedAt: String {
        guard let date = approval.requestedAt.iso8601Date else { return approval.requestedAt }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

private struct PeerRow: View {
    let peer: PeerStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(peer.nodeName.isEmpty ? peer.nodeId : peer.nodeName)
                        .font(.subheadline.weight(.medium))
                    Text(peer.address)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                StatusPill(text: peer.state.capitalized, color: peer.state.lowercased().contains("connected") ? .green : .orange)
            }

            HStack(spacing: 12) {
                Label("\(peer.agents.count) agents", systemImage: "cpu")
                Label(peer.protocolVersion, systemImage: "point.3.connected.trianglepath.dotted")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct RuntimeEmptyRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

private extension String {
    var iso8601Date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: self) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: self)
    }
}

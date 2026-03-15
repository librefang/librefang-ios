import SwiftUI

struct RuntimeView: View {
    @Environment(\.dependencies) private var deps
    @State private var pendingApprovalAction: ApprovalDecisionAction?
    @State private var approvalActionInFlightID: String?
    @State private var operatorNotice: OperatorActionNotice?

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

    private var builtinToolCount: Int {
        vm.tools.filter { ($0.source ?? "builtin") != "mcp" }.count
    }

    private var mcpBackedToolCount: Int {
        vm.tools.filter { ($0.source ?? "") == "mcp" }.count
    }

    var body: some View {
        NavigationStack {
            List {
                errorSection
                scoreboardSection
                systemSection
                diagnosticsSection
                integrationsSection
                usageSection
                automationSection
                sessionsSection
                providersSection
                toolingSection
                channelsSection
                a2aSection
                commsSection
                ofpNetworkSection
                handsSection
                approvalsSection
                auditSection
                securitySection
            }
            .navigationTitle("Runtime")
            .toolbar {
                runtimeToolbar
            }
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
        .confirmationDialog(
            pendingApprovalAction?.title ?? "",
            isPresented: approvalActionConfirmationPresented,
            titleVisibility: .visible,
            presenting: pendingApprovalAction
        ) { action in
            Button(action.confirmLabel, role: action.isDestructive ? .destructive : nil) {
                Task { await performApprovalAction(action) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(action.message)
        }
        .alert(item: $operatorNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var errorSection: some View {
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
    }

    private var scoreboardSection: some View {
        Section {
            RuntimeScoreboard(vm: vm)
                .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
        }
    }

    @ViewBuilder
    private var systemSection: some View {
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
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        if vm.healthDetail != nil || vm.versionInfo != nil || vm.configSummary != nil || vm.metricsSnapshot != nil {
            Section {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open Deep Diagnostics")
                            .font(.subheadline.weight(.medium))
                        Text("Inspect health detail, build info, config warnings, and Prometheus metrics from the daemon.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let healthDetail = vm.healthDetail {
                    RuntimeMetricRow(
                        label: "Health",
                        value: healthDetail.status.capitalized,
                        detail: "Database \(healthDetail.database.capitalized), \(healthDetail.configWarnings.count) config warnings"
                    )
                    RuntimeMetricRow(
                        label: "Supervisor",
                        value: "\(healthDetail.panicCount) panics / \(healthDetail.restartCount) restarts",
                        detail: "Recovered kernel events since startup"
                    )
                }

                if let versionInfo = vm.versionInfo {
                    RuntimeMetricRow(
                        label: "Build",
                        value: versionInfo.version,
                        detail: "\(versionInfo.platform) / \(versionInfo.arch) · \(shortSHA(versionInfo.gitSHA))"
                    )
                }

                if let metrics = vm.metricsSnapshot {
                    RuntimeMetricRow(
                        label: "Metrics",
                        value: "\(metrics.activeAgents)/\(metrics.totalAgents) active",
                        detail: "\(metrics.totalRollingTokens.formatted()) rolling tokens · \(metrics.totalRollingToolCalls.formatted()) tool calls"
                    )
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("This section surfaces daemon-level health and build drift that the higher-level monitoring cards can miss.")
            }
        }
    }

    @ViewBuilder
    private var integrationsSection: some View {
        if !vm.providers.isEmpty || !vm.channels.isEmpty || !vm.catalogModels.isEmpty {
            Section {
                NavigationLink {
                    IntegrationsView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open Integrations Diagnostics")
                            .font(.subheadline.weight(.medium))
                        Text("Inspect provider probes, channel credential gaps, catalog models, and aliases.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                RuntimeMetricRow(
                    label: "Providers",
                    value: "\(vm.configuredProviderCount)/\(vm.providers.count)",
                    detail: vm.unreachableLocalProviderCount > 0
                        ? "\(vm.unreachableLocalProviderCount) local unreachable"
                        : "\(vm.reachableLocalProviderCount) local reachable"
                )
                RuntimeMetricRow(
                    label: "Channels",
                    value: "\(vm.readyChannelCount)/\(vm.configuredChannelCount)",
                    detail: vm.channelRequiredFieldGapCount > 0
                        ? "\(vm.channelRequiredFieldGapCount) channels missing \(vm.missingRequiredChannelFieldCount) required fields"
                        : "Configured channels have required fields"
                )
                RuntimeMetricRow(
                    label: "Catalog",
                    value: "\(vm.availableCatalogModelCount)/\(vm.catalogModels.count) available",
                    detail: vm.hasEmptyModelCatalog ? "No executable models in the current catalog" : "\(vm.modelAliasCount) aliases"
                )
                RuntimeMetricRow(
                    label: "Catalog Sync",
                    value: catalogSyncValue,
                    detail: catalogSyncDetail
                )
                if !vm.agentsWithModelDiagnostics.isEmpty {
                    RuntimeMetricRow(
                        label: "Agent Drift",
                        value: "\(vm.agentsWithModelDiagnostics.count)",
                        detail: "\(vm.unavailableModelAgentCount) unavailable, \(vm.agentsWithModelDiagnostics.count - vm.unavailableModelAgentCount) mismatched or unknown"
                    )
                }
            } header: {
                Text("Integrations")
            } footer: {
                Text("This section focuses on model providers, delivery channels, and the model catalog rather than runtime execution.")
            }
        }
    }

    private var catalogSyncValue: String {
        if vm.hasEmptyModelCatalog {
            return "Empty"
        }
        if vm.isCatalogSyncStale {
            return "Stale"
        }
        if vm.catalogLastSyncDate == nil {
            return "Unknown"
        }
        return "Fresh"
    }

    private var catalogSyncDetail: String {
        guard let catalogLastSyncDate = vm.catalogLastSyncDate else {
            return vm.catalogModels.isEmpty ? "No catalog sync timestamp and no cached models" : "Sync timestamp unavailable"
        }
        return RelativeDateTimeFormatter().localizedString(for: catalogLastSyncDate, relativeTo: Date())
    }

    @ViewBuilder
    private var usageSection: some View {
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
                RuntimeMetricRow(
                    label: "Sessions",
                    value: "\(vm.totalSessionCount)",
                    detail: "\(vm.totalSessionMessages.formatted()) messages retained"
                )
            }
        }
    }

    @ViewBuilder
    private var automationSection: some View {
        if vm.automationDefinitionCount > 0 || !vm.workflowRuns.isEmpty {
            Section {
                NavigationLink {
                    AutomationView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open Automation Monitor")
                            .font(.subheadline.weight(.medium))
                        Text("Inspect workflows, recent runs, triggers, schedules, and cron pressure from one mobile view.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                RuntimeMetricRow(
                    label: "Workflows",
                    value: "\(vm.workflowCount)",
                    detail: "\(vm.failedWorkflowRunCount) failed runs, \(vm.runningWorkflowRunCount) in flight"
                )
                RuntimeMetricRow(
                    label: "Triggers",
                    value: "\(vm.enabledTriggerCount)/\(vm.triggers.count) enabled",
                    detail: "\(vm.exhaustedTriggerCount) exhausted, \(vm.disabledTriggerCount) disabled"
                )
                RuntimeMetricRow(
                    label: "Schedules",
                    value: "\(vm.enabledScheduleCount)/\(vm.schedules.count) enabled",
                    detail: "\(vm.pausedScheduleCount) paused, \(vm.enabledCronJobCount)/\(vm.cronJobs.count) cron enabled"
                )
                if vm.stalledCronJobCount > 0 {
                    RuntimeMetricRow(
                        label: "Cron Health",
                        value: "\(vm.stalledCronJobCount) missing next run",
                        detail: "Enabled jobs without a next execution should be reviewed in the scheduler."
                    )
                }
            } header: {
                Text("Automation")
            } footer: {
                Text("\(vm.automationDefinitionCount) total automation objects across workflows, triggers, schedules, and cron")
            }
        }
    }

    @ViewBuilder
    private var sessionsSection: some View {
        if !vm.sessions.isEmpty {
            Section {
                ForEach(vm.sessions.prefix(5)) { session in
                    let query = session.agentId
                    NavigationLink {
                        SessionsView(initialSearchText: query, initialFilter: .attention)
                    } label: {
                        SessionRow(
                            session: session,
                            agentName: vm.agents.first(where: { $0.id == session.agentId })?.name
                        )
                    }
                }

                NavigationLink {
                    SessionsView(initialFilter: .attention)
                } label: {
                    Label("Open Session Monitor", systemImage: "rectangle.stack")
                }
            } header: {
                Text("Recent Sessions")
            } footer: {
                Text("\(vm.totalSessionCount) sessions across the workspace, \(vm.sessionAttentionCount) need attention")
            }
        }
    }

    @ViewBuilder
    private var providersSection: some View {
        if !sortedProviders.isEmpty {
            Section {
                ForEach(sortedProviders) { provider in
                    ProviderStatusRow(provider: provider)
                }
            } header: {
                Text("Providers")
            } footer: {
                Text("\(vm.configuredProviderCount)/\(sortedProviders.count) configured")
            }
        }
    }

    @ViewBuilder
    private var toolingSection: some View {
        if !vm.mcpConfiguredServers.isEmpty || !vm.mcpConnectedServers.isEmpty || !vm.tools.isEmpty {
            Section("Tooling") {
                RuntimeMetricRow(
                    label: "MCP Servers",
                    value: "\(vm.connectedMCPServerCount)/\(max(vm.configuredMCPServerCount, vm.mcpConnectedServers.count)) connected",
                    detail: "\(vm.mcpToolCount) MCP tools available"
                )
                RuntimeMetricRow(
                    label: "Tool Inventory",
                    value: "\(vm.totalToolCount)",
                    detail: "\(builtinToolCount) built-in + \(mcpBackedToolCount) MCP-backed"
                )

                if !vm.mcpConnectedServers.isEmpty {
                    ForEach(vm.mcpConnectedServers.prefix(4)) { server in
                        MCPServerRow(server: server)
                    }
                } else if !vm.mcpConfiguredServers.isEmpty {
                    RuntimeEmptyRow(
                        title: "Configured but not connected",
                        subtitle: "MCP servers are configured on disk but none are currently attached."
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var channelsSection: some View {
        if !configuredChannels.isEmpty || !vm.channels.isEmpty {
            Section {
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
            } header: {
                Text("Channels")
            } footer: {
                if configuredChannels.count > 8 {
                    Text("Showing 8 of \(configuredChannels.count) configured channels")
                } else {
                    Text("\(vm.readyChannelCount) ready, \(vm.configuredChannelCount) configured")
                }
            }
        }
    }

    @ViewBuilder
    private var a2aSection: some View {
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
    }

    private var commsSection: some View {
        Section("Comms") {
            NavigationLink {
                CommsView(api: deps.apiClient)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Open Live Comms Monitor")
                        .font(.subheadline.weight(.medium))
                    Text("Track inter-agent messages, spawns, and task coordination in real time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var ofpNetworkSection: some View {
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
    }

    @ViewBuilder
    private var handsSection: some View {
        if !vm.activeHands.isEmpty || !degradedHands.isEmpty || !vm.hands.isEmpty {
            Section {
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
            } header: {
                Text("Hands")
            } footer: {
                Text("\(vm.activeHandCount) active, \(vm.degradedHandCount) degraded")
            }
        }
    }

    @ViewBuilder
    private var approvalsSection: some View {
        if !vm.approvals.isEmpty {
            Section {
                ForEach(vm.approvals) { approval in
                    ApprovalOperatorRow(
                        approval: approval,
                        isBusy: approvalActionInFlightID == approval.id,
                        onApprove: {
                            pendingApprovalAction = .approve(approval)
                        },
                        onReject: {
                            pendingApprovalAction = .reject(approval)
                        }
                    )
                }

                NavigationLink {
                    ApprovalsView()
                } label: {
                    Label("Open Full Approval Queue", systemImage: "checkmark.shield")
                }
            } header: {
                Text("Pending Approvals")
            } footer: {
                Text("High-risk tool approvals can now be resolved directly from mobile after confirmation.")
            }
        }
    }

    @ViewBuilder
    private var auditSection: some View {
        if !vm.recentAudit.isEmpty || vm.auditVerify != nil {
            Section("Recent Audit") {
                if vm.recentAudit.isEmpty {
                    RuntimeEmptyRow(
                        title: "No recent audit events",
                        subtitle: "Open the full event feed to refresh or inspect a larger time window."
                    )
                } else {
                    ForEach(vm.recentAudit.prefix(6)) { entry in
                        NavigationLink {
                            if entry.agentId.isEmpty {
                                EventsView(api: deps.apiClient, initialScope: .critical)
                            } else {
                                EventsView(api: deps.apiClient, initialSearchText: entry.agentId)
                            }
                        } label: {
                            AuditEventRow(entry: entry)
                        }
                    }
                }

                NavigationLink {
                    EventsView(api: deps.apiClient, initialScope: .critical)
                } label: {
                    Label("Open Full Event Feed", systemImage: "list.bullet.rectangle.portrait")
                }
            }
        }
    }

    @ViewBuilder
    private var securitySection: some View {
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
                if let auditVerify = vm.auditVerify {
                    RuntimeMetricRow(
                        label: "Audit Integrity",
                        value: auditVerify.valid ? "Valid" : "Broken",
                        detail: auditVerify.warning ?? auditVerify.error ?? "\(auditVerify.entries) entries verified"
                    )
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var runtimeToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 14) {
                NavigationLink {
                    IncidentsView()
                } label: {
                    Image(systemName: "bell.badge")
                }

                NavigationLink {
                    ApprovalsView()
                } label: {
                    Image(systemName: "checkmark.shield")
                }

                NavigationLink {
                    SessionsView(initialFilter: .attention)
                } label: {
                    Image(systemName: "rectangle.stack")
                }

                NavigationLink {
                    EventsView(api: deps.apiClient, initialScope: .critical)
                } label: {
                    Image(systemName: "list.bullet.rectangle.portrait")
                }

                NavigationLink {
                    CommsView(api: deps.apiClient)
                } label: {
                    Image(systemName: "arrow.left.arrow.right.circle")
                }

                NavigationLink {
                    AutomationView()
                } label: {
                    Image(systemName: "flowchart")
                }

                NavigationLink {
                    IntegrationsView()
                } label: {
                    Image(systemName: "square.3.layers.3d.down.forward")
                }

                NavigationLink {
                    DiagnosticsView()
                } label: {
                    Image(systemName: "stethoscope")
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

    private func shortSHA(_ value: String) -> String {
        guard value.count > 12 else { return value }
        return String(value.prefix(12))
    }

    private var approvalActionConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingApprovalAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingApprovalAction = nil
                }
            }
        )
    }

    @MainActor
    private func performApprovalAction(_ action: ApprovalDecisionAction) async {
        pendingApprovalAction = nil
        approvalActionInFlightID = action.approvalID
        defer { approvalActionInFlightID = nil }

        do {
            let response = try await action.perform(using: deps.apiClient)
            await vm.refresh()
            operatorNotice = action.successNotice(from: response)
        } catch {
            operatorNotice = OperatorActionNotice(
                title: action.title,
                message: error.localizedDescription
            )
        }
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
                value: "\(vm.enabledAutomationCount)/\(vm.automationDefinitionCount)",
                label: "Automation",
                icon: "flowchart",
                color: vm.failedWorkflowRunCount > 0 || vm.exhaustedTriggerCount > 0 || vm.stalledCronJobCount > 0 ? .orange : .blue
            )
            StatBadge(
                value: "\(vm.diagnosticsIssueCount)",
                label: "Diagnostics",
                icon: "stethoscope",
                color: vm.hasDiagnosticsIssue ? .orange : .green
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

private struct SessionRow: View {
    let session: SessionInfo
    let agentName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text((session.label?.isEmpty == false ? session.label : nil) ?? shortSessionId)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(relativeCreatedAt)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Label(agentName ?? session.agentId, systemImage: "cpu")
                Label("\(session.messageCount)", systemImage: "bubble.left.and.bubble.right")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var shortSessionId: String {
        String(session.sessionId.prefix(8))
    }

    private var relativeCreatedAt: String {
        guard let date = session.createdAt.iso8601Date else { return session.createdAt }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

private struct MCPServerRow: View {
    let server: MCPConnectedServer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(server.name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                StatusPill(text: server.connected ? "Connected" : "Offline", color: server.connected ? .green : .orange)
            }

            HStack(spacing: 12) {
                Label("\(server.toolsCount) tools", systemImage: "wrench.and.screwdriver")
                if let topTool = server.tools.first?.name {
                    Label(topTool, systemImage: "hammer")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
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

private struct AuditEventRow: View {
    let entry: AuditEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(entry.friendlyAction)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(relativeText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(entry.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(entry.outcome)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(outcomeColor)
        }
        .padding(.vertical, 2)
    }

    private var relativeText: String {
        guard let date = entry.timestamp.iso8601Date else { return entry.timestamp }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private var outcomeColor: Color {
        switch entry.severity {
        case .critical:
            .red
        case .warning:
            .orange
        case .info:
            .green
        }
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

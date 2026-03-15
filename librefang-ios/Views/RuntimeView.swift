import SwiftUI

private enum RuntimeSectionAnchor: Hashable {
    case system
    case diagnostics
    case integrations
    case automation
    case sessions
    case approvals
    case audit
    case security
}

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

    private var visibleProviders: [ProviderStatus] {
        Array(sortedProviders.prefix(6))
    }

    private var visibleActiveHands: [HandInstance] {
        Array(vm.activeHands.prefix(4))
    }

    private var visibleApprovals: [ApprovalItem] {
        Array(vm.approvals.prefix(4))
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

    private var runtimeSnapshotSummary: String {
        if let status = vm.status {
            return String(localized: "Kernel \(status.localizedStatusLabel) with \(status.agentCount) agents and \(vm.pendingApprovalCount) pending approvals in the current runtime snapshot.")
        }
        return String(localized: "Runtime monitoring is collecting the latest system, integrations, automation, and approval state.")
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    errorSection
                    scoreboardSection
                    runtimeOperatorDeckSection(proxy)
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

    private func runtimeOperatorDeckSection(_ proxy: ScrollViewProxy) -> some View {
        Section {
            RuntimeStatusDeckCard(vm: vm, runtimeSnapshotSummary: runtimeSnapshotSummary)
            runtimeRouteDeckCard(proxy)
        } header: {
            Text("Controls")
        } footer: {
            Text("Keep the digest, routes, and jumps together before drilling deeper.")
        }
    }

    private func runtimeRouteDeckCard(_ proxy: ScrollViewProxy) -> some View {
        MonitoringSurfaceGroupCard(
            title: String(localized: "Routes"),
            detail: String(localized: "Keep runtime surfaces and long-section jumps in one compact deck.")
        ) {
            MonitoringShortcutRail(
                title: String(localized: "Primary"),
                detail: String(localized: "Keep the next runtime drills right below the digest.")
            ) {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Diagnostics"),
                        systemImage: "stethoscope",
                        tone: vm.diagnosticsSummaryTone,
                        badgeText: vm.diagnosticsConfigWarningCount > 0
                            ? (vm.diagnosticsConfigWarningCount == 1 ? String(localized: "1 warning") : String(localized: "\(vm.diagnosticsConfigWarningCount) warnings"))
                            : nil
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    IntegrationsView(initialScope: .attention)
                } label: {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Integrations"),
                        systemImage: "square.3.layers.3d.down.forward",
                        tone: vm.integrationPressureIssueCategoryCount > 0 ? .critical : .neutral,
                        badgeText: vm.integrationPressureIssueCategoryCount > 0
                            ? (vm.integrationPressureIssueCategoryCount == 1 ? String(localized: "1 issue") : String(localized: "\(vm.integrationPressureIssueCategoryCount) issues"))
                            : nil
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ApprovalsView()
                } label: {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Approvals"),
                        systemImage: "checkmark.shield",
                        tone: vm.pendingApprovalCount > 0 ? .critical : .neutral,
                        badgeText: vm.pendingApprovalCount > 0
                            ? (vm.pendingApprovalCount == 1 ? String(localized: "1 pending") : String(localized: "\(vm.pendingApprovalCount) pending"))
                            : nil
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    SessionsView(initialFilter: .attention)
                } label: {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Sessions"),
                        systemImage: "text.bubble",
                        tone: vm.sessionAttentionCount > 0 ? .warning : .neutral,
                        badgeText: vm.sessionAttentionCount > 0
                            ? (vm.sessionAttentionCount == 1 ? String(localized: "1 hotspot") : String(localized: "\(vm.sessionAttentionCount) hotspots"))
                            : nil
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    EventsView(api: deps.apiClient, initialScope: .critical)
                } label: {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Critical Events"),
                        systemImage: "text.justify.leading",
                        tone: vm.recentCriticalAuditCount > 0 ? .critical : .neutral,
                        badgeText: vm.recentCriticalAuditCount > 0
                            ? (vm.recentCriticalAuditCount == 1 ? String(localized: "1 critical") : String(localized: "\(vm.recentCriticalAuditCount) critical"))
                            : nil
                    )
                }
                .buttonStyle(.plain)
            }

            MonitoringShortcutRail(
                title: String(localized: "Support"),
                detail: String(localized: "Keep slower infra and config routes in a secondary rail.")
            ) {
                NavigationLink {
                    AutomationView(initialScope: .attention)
                } label: {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Automation"),
                        systemImage: "flowchart",
                        tone: vm.automationPressureIssueCategoryCount > 0 ? .warning : .neutral,
                        badgeText: vm.automationPressureIssueCategoryCount > 0
                            ? (vm.automationPressureIssueCategoryCount == 1 ? String(localized: "1 issue") : String(localized: "\(vm.automationPressureIssueCategoryCount) issues"))
                            : nil
                    )
                }
                .buttonStyle(.plain)

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
                    A2AAgentsView()
                } label: {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "A2A Agents"),
                        systemImage: "link.circle"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    SettingsView()
                } label: {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Settings"),
                        systemImage: "gearshape"
                    )
                }
                .buttonStyle(.plain)
            }

            MonitoringShortcutRail(
                title: String(localized: "Jumps"),
                detail: String(localized: "Keep the longest runtime sections reachable as compact jumps.")
            ) {
                if vm.status != nil {
                    Button {
                        jump(proxy, to: .system)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "System"),
                            systemImage: "server.rack",
                            tone: vm.status?.statusTone ?? .neutral
                        )
                    }
                    .buttonStyle(.plain)
                }

                if vm.healthDetail != nil || vm.versionInfo != nil || vm.configSummary != nil || vm.metricsSnapshot != nil {
                    Button {
                        jump(proxy, to: .diagnostics)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Diagnostics"),
                            systemImage: "stethoscope",
                            tone: vm.diagnosticsSummaryTone,
                            badgeText: vm.diagnosticsConfigWarningCount == 0 ? nil : String(localized: "\(vm.diagnosticsConfigWarningCount) warnings")
                        )
                    }
                    .buttonStyle(.plain)
                }

                if !vm.providers.isEmpty || !vm.channels.isEmpty || !vm.catalogModels.isEmpty {
                    Button {
                        jump(proxy, to: .integrations)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Integrations"),
                            systemImage: "square.3.layers.3d.down.forward",
                            tone: vm.integrationPressureIssueCategoryCount > 0 ? .critical : .neutral,
                            badgeText: vm.integrationPressureIssueCategoryCount == 0 ? nil : String(localized: "\(vm.integrationPressureIssueCategoryCount) issues")
                        )
                    }
                    .buttonStyle(.plain)
                }

                if vm.automationDefinitionCount > 0 || !vm.workflowRuns.isEmpty {
                    Button {
                        jump(proxy, to: .automation)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Automation"),
                            systemImage: "flowchart",
                            tone: vm.automationPressureTone,
                            badgeText: vm.automationPressureIssueCategoryCount == 0 ? nil : String(localized: "\(vm.automationPressureIssueCategoryCount) issues")
                        )
                    }
                    .buttonStyle(.plain)
                }

                if !vm.sessions.isEmpty {
                    Button {
                        jump(proxy, to: .sessions)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Sessions"),
                            systemImage: "rectangle.stack",
                            tone: vm.sessionAttentionCount > 0 ? .warning : .neutral,
                            badgeText: vm.sessionAttentionCount == 0 ? nil : String(localized: "\(vm.sessionAttentionCount) hotspots")
                        )
                    }
                    .buttonStyle(.plain)
                }

                if !vm.approvals.isEmpty {
                    Button {
                        jump(proxy, to: .approvals)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Approvals"),
                            systemImage: "checkmark.shield",
                            tone: .critical,
                            badgeText: vm.pendingApprovalCount == 1 ? String(localized: "1 waiting") : String(localized: "\(vm.pendingApprovalCount) waiting")
                        )
                    }
                    .buttonStyle(.plain)
                }

                if !vm.recentAudit.isEmpty {
                    Button {
                        jump(proxy, to: .audit)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Audit"),
                            systemImage: "list.bullet.rectangle.portrait",
                            tone: vm.recentCriticalAuditCount > 0 ? .critical : .neutral,
                            badgeText: vm.recentCriticalAuditCount == 0 ? nil : String(localized: "\(vm.recentCriticalAuditCount) critical")
                        )
                    }
                    .buttonStyle(.plain)
                }

                if vm.security != nil {
                    Button {
                        jump(proxy, to: .security)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Security"),
                            systemImage: "lock.shield",
                            tone: .neutral
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var systemSection: some View {
        if let status = vm.status {
            Section("System") {
                RuntimeSystemRow(label: "Kernel") {
                    StatusPill(text: status.localizedStatusLabel, color: status.statusTone.color)
                }
                RuntimeSystemRow(label: "Version") {
                    Text(status.version)
                }
                RuntimeSystemRow(label: "Uptime") {
                    Text(formatDuration(status.uptimeSeconds))
                        .monospacedDigit()
                }
                RuntimeSystemRow(label: "Agents") {
                    Text("\(status.agentCount)")
                        .monospacedDigit()
                }
                RuntimeSystemRow(label: "Default Model") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(status.defaultModel)
                            .lineLimit(1)
                        Text(status.defaultProvider)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                RuntimeSystemRow(label: "Network") {
                    StatusPill(text: status.networkEnabled ? String(localized: "Enabled") : String(localized: "Disabled"), color: status.networkEnabled ? .green : .orange)
                }
            }
            .id(RuntimeSectionAnchor.system)
        }
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        if vm.healthDetail != nil || vm.versionInfo != nil || vm.configSummary != nil || vm.metricsSnapshot != nil {
            Section {
                MonitoringSurfaceGroupCard(
                    title: String(localized: "Routes"),
                    detail: String(localized: "Open deeper diagnostics without another long text row.")
                ) {
                    MonitoringShortcutRail(title: String(localized: "Primary")) {
                        NavigationLink {
                            DiagnosticsView()
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Diagnostics"),
                                systemImage: "stethoscope",
                                tone: vm.diagnosticsSummaryTone,
                                badgeText: vm.diagnosticsConfigWarningCount > 0 ? "\(vm.diagnosticsConfigWarningCount)" : nil
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            IncidentsView()
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Incidents"),
                                systemImage: "bell.badge",
                                tone: vm.monitoringAlerts.contains { $0.severity == .critical } ? .critical : .neutral
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let healthDetail = vm.healthDetail {
                    RuntimeMetricRow(
                        label: String(localized: "Health"),
                        value: healthDetail.localizedStatusLabel,
                        detail: String(
                            localized: "Database \(healthDetail.localizedDatabaseLabel), \(configWarningSummary(healthDetail.configWarnings.count))"
                        )
                    )
                    RuntimeMetricRow(
                        label: String(localized: "Supervisor"),
                        value: String(localized: "\(healthDetail.panicCount) panics / \(healthDetail.restartCount) restarts"),
                        detail: String(localized: "Recovered kernel events since startup")
                    )
                }

                if let versionInfo = vm.versionInfo {
                    RuntimeMetricRow(
                        label: String(localized: "Build"),
                        value: versionInfo.version,
                        detail: String(localized: "\(versionInfo.platform) / \(versionInfo.arch) · \(shortSHA(versionInfo.gitSHA))")
                    )
                }

                if let metrics = vm.metricsSnapshot {
                    RuntimeMetricRow(
                        label: String(localized: "Metrics"),
                        value: String(localized: "\(metrics.activeAgents)/\(metrics.totalAgents) active"),
                        detail: String(localized: "\(metrics.totalRollingTokens.formatted()) rolling tokens · \(metrics.totalRollingToolCalls.formatted()) tool calls")
                    )
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Daemon-level health and build drift that the higher-level cards can miss.")
            }
            .id(RuntimeSectionAnchor.diagnostics)
        }
    }

    @ViewBuilder
    private var integrationsSection: some View {
        if !vm.providers.isEmpty || !vm.channels.isEmpty || !vm.catalogModels.isEmpty {
            Section {
                MonitoringSurfaceGroupCard(
                    title: String(localized: "Routes"),
                    detail: String(localized: "Open provider, channel, and catalog diagnostics without another full-width text row.")
                ) {
                    MonitoringShortcutRail(title: String(localized: "Primary")) {
                        NavigationLink {
                            IntegrationsView(initialScope: .attention)
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Integrations"),
                                systemImage: "square.3.layers.3d.down.forward",
                                tone: vm.integrationPressureIssueCategoryCount > 0 ? .critical : .neutral,
                                badgeText: vm.integrationPressureIssueCategoryCount > 0 ? "\(vm.integrationPressureIssueCategoryCount)" : nil
                            )
                        }
                        .buttonStyle(.plain)

                        if vm.unreachableLocalProviderCount > 0 {
                            NavigationLink {
                                IntegrationsView(
                                    initialSearchText: vm.unreachableLocalProviders.count == 1 ? vm.unreachableLocalProviders[0].displayName : "",
                                    initialScope: .attention
                                )
                            } label: {
                                MonitoringSurfaceShortcutChip(
                                    title: String(localized: "Provider Failures"),
                                    systemImage: "network.slash",
                                    tone: .critical,
                                    badgeText: "\(vm.unreachableLocalProviderCount)"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if vm.channelRequiredFieldGapCount > 0 {
                            NavigationLink {
                                IntegrationsView(
                                    initialSearchText: vm.channelsMissingRequiredFields.count == 1 ? vm.channelsMissingRequiredFields[0].displayName : "",
                                    initialScope: .attention
                                )
                            } label: {
                                MonitoringSurfaceShortcutChip(
                                    title: String(localized: "Channel Gaps"),
                                    systemImage: "bubble.left.and.exclamationmark.bubble.right",
                                    tone: .warning,
                                    badgeText: "\(vm.channelRequiredFieldGapCount)"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if vm.hasEmptyModelCatalog {
                            NavigationLink {
                                IntegrationsView(initialScope: .attention)
                            } label: {
                                MonitoringSurfaceShortcutChip(
                                    title: String(localized: "Catalog"),
                                    systemImage: "square.stack.3d.up.slash",
                                    tone: .critical
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                RuntimeMetricRow(
                    label: String(localized: "Providers"),
                    value: "\(vm.configuredProviderCount)/\(vm.providers.count)",
                    detail: vm.unreachableLocalProviderCount > 0
                        ? String(localized: "\(vm.unreachableLocalProviderCount) local unreachable")
                        : String(localized: "\(vm.reachableLocalProviderCount) local reachable")
                )
                RuntimeMetricRow(
                    label: String(localized: "Channels"),
                    value: "\(vm.readyChannelCount)/\(vm.configuredChannelCount)",
                    detail: vm.channelRequiredFieldGapCount > 0
                        ? String(localized: "\(vm.channelRequiredFieldGapCount) channels missing \(vm.missingRequiredChannelFieldCount) required fields")
                        : String(localized: "Configured channels have required fields")
                )
                RuntimeMetricRow(
                    label: String(localized: "Catalog"),
                    value: String(localized: "\(vm.availableCatalogModelCount)/\(vm.catalogModels.count) available"),
                    detail: vm.hasEmptyModelCatalog ? String(localized: "No executable models in the current catalog") : String(localized: "\(vm.modelAliasCount) aliases")
                )
                RuntimeMetricRow(
                    label: String(localized: "Catalog Sync"),
                    value: vm.catalogSyncStatusLabel,
                    detail: catalogSyncDetail
                )
                if !vm.agentsWithModelDiagnostics.isEmpty {
                    RuntimeMetricRow(
                        label: String(localized: "Agent Drift"),
                        value: "\(vm.agentsWithModelDiagnostics.count)",
                        detail: String(localized: "\(vm.unavailableModelAgentCount) unavailable, \(vm.agentsWithModelDiagnostics.count - vm.unavailableModelAgentCount) mismatched or unknown")
                    )
                }
            } header: {
                Text("Integrations")
            } footer: {
                Text("This section focuses on model providers, delivery channels, and the model catalog rather than runtime execution.")
            }
            .id(RuntimeSectionAnchor.integrations)
        }
    }

    private var catalogSyncDetail: String {
        guard let catalogLastSyncDate = vm.catalogLastSyncDate else {
            return vm.catalogModels.isEmpty ? String(localized: "No catalog sync timestamp and no cached models") : String(localized: "Sync timestamp unavailable")
        }
        return RelativeDateTimeFormatter().localizedString(for: catalogLastSyncDate, relativeTo: Date())
    }

    @ViewBuilder
    private var usageSection: some View {
        if let usage = vm.usageSummary {
            Section("Usage") {
                RuntimeMetricRow(
                    label: String(localized: "Tokens"),
                    value: String(localized: "\(usage.totalInputTokens.formatted()) in / \(usage.totalOutputTokens.formatted()) out"),
                    detail: String(localized: "\(vm.totalTokenCount.formatted()) total")
                )
                RuntimeMetricRow(
                    label: String(localized: "Tool Calls"),
                    value: usage.totalToolCalls.formatted(),
                    detail: String(localized: "\(usage.callCount.formatted()) LLM calls")
                )
                RuntimeMetricRow(
                    label: String(localized: "Accumulated Cost"),
                    value: currency(usage.totalCostUsd),
                    detail: usage.totalCostUsd > 0 ? String(localized: "All recorded sessions") : String(localized: "No spend recorded")
                )
                RuntimeMetricRow(
                    label: String(localized: "Sessions"),
                    value: "\(vm.totalSessionCount)",
                    detail: String(localized: "\(vm.totalSessionMessages.formatted()) messages retained")
                )
            }
        }
    }

    @ViewBuilder
    private var automationSection: some View {
        if vm.automationDefinitionCount > 0 || !vm.workflowRuns.isEmpty {
            Section {
                MonitoringSurfaceGroupCard(
                    title: String(localized: "Routes"),
                    detail: String(localized: "Open workflow pressure and scheduler diagnostics without another dense text row.")
                ) {
                    MonitoringShortcutRail(title: String(localized: "Primary")) {
                        NavigationLink {
                            AutomationView()
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Automation Monitor"),
                                systemImage: "flowchart",
                                tone: vm.automationPressureTone,
                                badgeText: vm.automationPressureIssueCategoryCount > 0 ? "\(vm.automationPressureIssueCategoryCount)" : nil
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            IncidentsView()
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Incidents"),
                                systemImage: "bell.badge",
                                tone: vm.automationPressureIssueCategoryCount > 0 ? .warning : .neutral
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                RuntimeMetricRow(
                    label: String(localized: "Workflows"),
                    value: "\(vm.workflowCount)",
                    detail: String(localized: "\(vm.failedWorkflowRunCount) failed runs, \(vm.runningWorkflowRunCount) in flight")
                )
                RuntimeMetricRow(
                    label: String(localized: "Triggers"),
                    value: String(localized: "\(vm.enabledTriggerCount)/\(vm.triggers.count) enabled"),
                    detail: String(localized: "\(vm.exhaustedTriggerCount) exhausted, \(vm.disabledTriggerCount) disabled")
                )
                RuntimeMetricRow(
                    label: String(localized: "Schedules"),
                    value: String(localized: "\(vm.enabledScheduleCount)/\(vm.schedules.count) enabled"),
                    detail: String(localized: "\(vm.pausedScheduleCount) paused, \(vm.enabledCronJobCount)/\(vm.cronJobs.count) cron enabled")
                )
                if vm.stalledCronJobCount > 0 {
                    RuntimeMetricRow(
                        label: String(localized: "Cron Health"),
                        value: String(localized: "\(vm.stalledCronJobCount) missing next run"),
                        detail: String(localized: "Enabled jobs without a next execution should be reviewed in the scheduler.")
                    )
                }
            } header: {
                Text("Automation")
            } footer: {
                Text("\(vm.automationDefinitionCount) total automation objects across workflows, triggers, schedules, and cron")
            }
            .id(RuntimeSectionAnchor.automation)
        }
    }

    @ViewBuilder
    private var sessionsSection: some View {
        if !vm.sessions.isEmpty {
            Section {
                MonitoringSurfaceGroupCard(
                    title: String(localized: "Routes"),
                    detail: String(localized: "Jump into the session monitor when the compact runtime list is not enough.")
                ) {
                    MonitoringShortcutRail(title: String(localized: "Primary")) {
                        NavigationLink {
                            SessionsView(initialFilter: .attention)
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Sessions"),
                                systemImage: "rectangle.stack",
                                tone: vm.sessionAttentionCount > 0 ? .warning : .neutral,
                                badgeText: vm.sessionAttentionCount > 0 ? "\(vm.sessionAttentionCount)" : nil
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            IncidentsView()
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Incidents"),
                                systemImage: "bell.badge",
                                tone: vm.sessionAttentionCount > 0 ? .warning : .neutral
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

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

            } header: {
                Text("Recent Sessions")
            } footer: {
                Text("\(vm.totalSessionCount) sessions across the workspace, \(vm.sessionAttentionCount) need attention")
            }
            .id(RuntimeSectionAnchor.sessions)
        }
    }

    @ViewBuilder
    private var providersSection: some View {
        if !sortedProviders.isEmpty {
            Section {
                ForEach(visibleProviders) { provider in
                    ProviderStatusRow(provider: provider)
                }
            } header: {
                Text("Providers")
            } footer: {
                if sortedProviders.count > visibleProviders.count {
                    Text("Showing \(visibleProviders.count) of \(sortedProviders.count) providers, \(vm.configuredProviderCount) configured")
                } else {
                    Text("\(vm.configuredProviderCount)/\(sortedProviders.count) configured")
                }
            }
        }
    }

    @ViewBuilder
    private var toolingSection: some View {
        if !vm.mcpConfiguredServers.isEmpty || !vm.mcpConnectedServers.isEmpty || !vm.tools.isEmpty {
            Section("Tooling") {
                RuntimeMetricRow(
                    label: String(localized: "MCP Servers"),
                    value: String(localized: "\(vm.connectedMCPServerCount)/\(max(vm.configuredMCPServerCount, vm.mcpConnectedServers.count)) connected"),
                    detail: String(localized: "\(vm.mcpToolCount) MCP tools available")
                )
                RuntimeMetricRow(
                    label: String(localized: "Tool Inventory"),
                    value: "\(vm.totalToolCount)",
                    detail: String(localized: "\(builtinToolCount) built-in + \(mcpBackedToolCount) MCP-backed")
                )

                if !vm.mcpConnectedServers.isEmpty {
                    ForEach(vm.mcpConnectedServers.prefix(4)) { server in
                        MCPServerRow(server: server)
                    }
                } else if !vm.mcpConfiguredServers.isEmpty {
                    RuntimeEmptyRow(
                        title: String(localized: "Configured but not connected"),
                        subtitle: String(localized: "MCP servers are configured on disk but none are currently attached.")
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
                        title: String(localized: "No channels configured"),
                        subtitle: String(localized: "Desktop or web can finish setup. Mobile focuses on status tracking.")
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
                    label: String(localized: "Connected Agents"),
                    value: "\(a2a.total)",
                    detail: String(localized: "External agents discovered through A2A")
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
                    Text("Comms")
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
                    label: String(localized: "Status"),
                    value: network.enabled ? String(localized: "Enabled") : String(localized: "Disabled"),
                    detail: network.enabled ? network.listenAddress : String(localized: "Shared secret or network mode not configured")
                )
                RuntimeMetricRow(
                    label: String(localized: "Peers"),
                    value: String(localized: "\(network.connectedPeers)/\(max(network.totalPeers, vm.peers.count)) connected"),
                    detail: network.nodeId.isEmpty ? String(localized: "Local node inactive") : String(localized: "Node \(shortNodeId(network.nodeId))")
                )

                if vm.peers.isEmpty {
                    RuntimeEmptyRow(
                        title: String(localized: "No peers discovered"),
                        subtitle: network.enabled ? String(localized: "The wire network is enabled but no peers are currently visible.") : String(localized: "Enable peer networking on the server to surface node status.")
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
                        title: String(localized: "No active hands"),
                        subtitle: String(localized: "When autonomous hands are activated, their runtime status appears here.")
                    )
                } else {
                    ForEach(visibleActiveHands) { instance in
                        HandInstanceRow(instance: instance, handDisplayName: instance.displayName(using: vm.hands))
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
                if vm.activeHands.count > visibleActiveHands.count {
                    Text("Showing \(visibleActiveHands.count) of \(vm.activeHands.count) active hands, \(vm.degradedHandCount) degraded")
                } else {
                    Text("\(vm.activeHandCount) active, \(vm.degradedHandCount) degraded")
                }
            }
        }
    }

    @ViewBuilder
    private var approvalsSection: some View {
        if !vm.approvals.isEmpty {
            Section {
                ForEach(visibleApprovals) { approval in
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
                    Label("Approvals", systemImage: "checkmark.shield")
                }
            } header: {
                Text("Pending Approvals")
            } footer: {
                if vm.approvals.count > visibleApprovals.count {
                    Text("Showing \(visibleApprovals.count) of \(vm.approvals.count) approvals. High-risk tool approvals can now be resolved directly from mobile after confirmation.")
                } else {
                    Text("High-risk tool approvals can now be resolved directly from mobile after confirmation.")
                }
            }
            .id(RuntimeSectionAnchor.approvals)
        }
    }

    @ViewBuilder
    private var auditSection: some View {
        if !vm.recentAudit.isEmpty || vm.auditVerify != nil {
            Section("Audit") {
                if vm.recentAudit.isEmpty {
                    RuntimeEmptyRow(
                        title: String(localized: "No recent audit events"),
                        subtitle: String(localized: "Open the full event feed to refresh or inspect a larger time window.")
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
                    Label("Critical Events", systemImage: "list.bullet.rectangle.portrait")
                }
            }
            .id(RuntimeSectionAnchor.audit)
        }
    }

    @ViewBuilder
    private var securitySection: some View {
        if let security = vm.security {
            Section("Security") {
                RuntimeMetricRow(
                    label: String(localized: "Protections"),
                    value: "\(security.totalFeatures)",
                    detail: String(localized: "Active defense layers")
                )
                RuntimeMetricRow(
                    label: String(localized: "Auth"),
                    value: security.configurable.auth.localizedModeLabel,
                    detail: security.configurable.auth.apiKeySet ? String(localized: "API key configured") : String(localized: "No API key configured")
                )
                RuntimeMetricRow(
                    label: String(localized: "Audit Trail"),
                    value: security.monitoring.auditTrail.algorithm,
                    detail: String(localized: "\(security.monitoring.auditTrail.entryCount.formatted()) entries")
                )
                if let auditVerify = vm.auditVerify {
                    RuntimeMetricRow(
                        label: String(localized: "Audit Integrity"),
                        value: auditVerify.valid ? String(localized: "Valid") : String(localized: "Broken"),
                        detail: auditVerify.warning ?? auditVerify.error ?? String(localized: "\(auditVerify.entries) entries verified")
                    )
                }
            }
            .id(RuntimeSectionAnchor.security)
        }
    }

    private func jump(_ proxy: ScrollViewProxy, to anchor: RuntimeSectionAnchor) {
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    @ToolbarContentBuilder
    private var runtimeToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            NavigationLink {
                IncidentsView()
            } label: {
                Image(systemName: "bell.badge")
            }

            Menu {
                Section("Queues") {
                    NavigationLink {
                        ApprovalsView()
                    } label: {
                        Label("Approvals", systemImage: "checkmark.shield")
                    }

                    NavigationLink {
                        SessionsView(initialFilter: .attention)
                    } label: {
                        Label("Sessions", systemImage: "rectangle.stack")
                    }

                    NavigationLink {
                        EventsView(api: deps.apiClient, initialScope: .critical)
                    } label: {
                        Label("Critical Events", systemImage: "list.bullet.rectangle.portrait")
                    }
                }

                Section("Drilldowns") {
                    NavigationLink {
                        CommsView(api: deps.apiClient)
                    } label: {
                        Label("Comms", systemImage: "arrow.left.arrow.right.circle")
                    }

                    NavigationLink {
                        AutomationView()
                    } label: {
                        Label("Automation", systemImage: "flowchart")
                    }

                    NavigationLink {
                        IntegrationsView()
                    } label: {
                        Label("Integrations", systemImage: "square.3.layers.3d.down.forward")
                    }

                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("Diagnostics", systemImage: "stethoscope")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func currency(_ value: Double) -> String {
        let style = FloatingPointFormatStyle<Double>.Currency(code: "USD")
        if value == 0 {
            return value.formatted(style.precision(.fractionLength(2)))
        }
        if value < 0.01 {
            return "<\(0.01.formatted(style.precision(.fractionLength(2))))"
        }
        return value.formatted(style.precision(.fractionLength(2)))
    }

    private func formatDuration(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            return String(localized: "\(days)d \(hours)h")
        }
        if hours > 0 {
            return String(localized: "\(hours)h \(minutes)m")
        }
        return String(localized: "\(minutes)m")
    }

    private func configWarningSummary(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "1 config warning")
        }
        return String(localized: "\(count) config warnings")
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

private struct RuntimeSystemRow<Content: View>: View {
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

private struct RuntimeStatusDeckCard: View {
    let vm: DashboardViewModel
    let runtimeSnapshotSummary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: runtimeSnapshotSummary,
                detail: String(localized: "This mobile snapshot keeps the most important runtime buckets visible before the longer provider and hand lists.")
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: vm.pendingApprovalCount == 1 ? String(localized: "1 approval") : String(localized: "\(vm.pendingApprovalCount) approvals"),
                        tone: vm.pendingApprovalCount > 0 ? .critical : .neutral
                    )
                    PresentationToneBadge(
                        text: vm.sessionAttentionCount == 1 ? String(localized: "1 session hotspot") : String(localized: "\(vm.sessionAttentionCount) session hotspots"),
                        tone: vm.sessionAttentionCount > 0 ? .warning : .neutral
                    )
                    if vm.recentCriticalAuditCount > 0 {
                        PresentationToneBadge(
                            text: vm.recentCriticalAuditCount == 1 ? String(localized: "1 critical audit event") : String(localized: "\(vm.recentCriticalAuditCount) critical audit events"),
                            tone: .critical
                        )
                    }
                    if vm.runtimeAlertCount > 0 {
                        PresentationToneBadge(
                            text: vm.runtimeAlertCount == 1 ? String(localized: "1 runtime alert") : String(localized: "\(vm.runtimeAlertCount) runtime alerts"),
                            tone: .warning
                        )
                    }
                    if vm.automationPressureIssueCategoryCount > 0 {
                        PresentationToneBadge(
                            text: vm.automationPressureIssueCategoryCount == 1 ? String(localized: "1 automation issue") : String(localized: "\(vm.automationPressureIssueCategoryCount) automation issues"),
                            tone: .warning
                        )
                    }
                    if vm.integrationPressureIssueCategoryCount > 0 {
                        PresentationToneBadge(
                            text: vm.integrationPressureIssueCategoryCount == 1 ? String(localized: "1 integration issue") : String(localized: "\(vm.integrationPressureIssueCategoryCount) integration issues"),
                            tone: .critical
                        )
                    }
                    if vm.degradedHandCount > 0 {
                        PresentationToneBadge(
                            text: vm.degradedHandCount == 1 ? String(localized: "1 degraded hand") : String(localized: "\(vm.degradedHandCount) degraded hands"),
                            tone: .warning
                        )
                    }
                    if vm.connectedMCPServerCount > 0 || vm.configuredMCPServerCount > 0 {
                        PresentationToneBadge(
                            text: String(localized: "\(vm.connectedMCPServerCount)/\(max(vm.configuredMCPServerCount, vm.connectedMCPServerCount)) MCP connected"),
                            tone: vm.connectedMCPServerCount > 0 ? .positive : .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Runtime facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep provider, channel, hand, network, and MCP pressure visible before opening deeper runtime sections."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: vm.status?.localizedStatusLabel ?? String(localized: "Unavailable"),
                    tone: vm.status?.statusTone ?? .neutral
                )
            } facts: {
                Label(
                    vm.configuredProviderCount == 1 ? String(localized: "1 provider") : String(localized: "\(vm.configuredProviderCount) providers"),
                    systemImage: "key.horizontal"
                )
                Label(
                    vm.readyChannelCount == 1 ? String(localized: "1 ready channel") : String(localized: "\(vm.readyChannelCount) ready channels"),
                    systemImage: "bubble.left.and.bubble.right"
                )
                Label(
                    vm.activeHandCount == 1 ? String(localized: "1 active hand") : String(localized: "\(vm.activeHandCount) active hands"),
                    systemImage: "hand.raised"
                )
                Label(
                    vm.connectedMCPServerCount == 1 ? String(localized: "1 MCP server") : String(localized: "\(vm.connectedMCPServerCount) MCP servers"),
                    systemImage: "shippingbox"
                )
                Label(
                    (vm.networkStatus?.connectedPeers ?? 0) == 1
                        ? String(localized: "1 connected peer")
                        : String(localized: "\((vm.networkStatus?.connectedPeers ?? 0)) connected peers"),
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
            }
        }
    }
}

private struct RuntimeScoreboard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let vm: DashboardViewModel

    private var agentStatus: MonitoringSummaryStatus {
        vm.runningAgentStatus
    }

    private var providerStatus: MonitoringSummaryStatus {
        .countStatus(vm.configuredProviderCount, activeTone: .positive, inactiveTone: .warning)
    }

    private var channelStatus: MonitoringSummaryStatus {
        .countStatus(vm.readyChannelCount, activeTone: .positive)
    }

    private var handStatus: MonitoringSummaryStatus {
        MonitoringSummaryStatus(summary: "\(vm.activeHandCount)", tone: vm.handReadinessStatus.tone)
    }

    private var approvalStatus: MonitoringSummaryStatus {
        vm.approvalBacklogStatus
    }

    private var automationStatus: MonitoringSummaryStatus {
        MonitoringSummaryStatus(summary: "\(vm.enabledAutomationCount)/\(vm.automationDefinitionCount)", tone: vm.automationPressureTone)
    }

    private var diagnosticsStatus: MonitoringSummaryStatus {
        MonitoringSummaryStatus(summary: "\(vm.diagnosticsIssueCount)", tone: vm.diagnosticsSummaryTone)
    }

    private var securityStatus: MonitoringSummaryStatus {
        .countStatus(vm.securityFeatureCount, activeTone: .positive)
    }

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 4
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            StatBadge(
                value: "\(vm.runningCount)/\(vm.totalCount)",
                label: "Agents",
                icon: "cpu",
                color: agentStatus.color(positive: .green)
            )
            StatBadge(
                value: "\(vm.configuredProviderCount)",
                label: "Providers",
                icon: "key.horizontal",
                color: providerStatus.color(positive: .blue)
            )
            StatBadge(
                value: "\(vm.readyChannelCount)",
                label: "Channels",
                icon: "bubble.left.and.bubble.right",
                color: channelStatus.color(positive: .teal)
            )
            StatBadge(
                value: "\(vm.activeHandCount)",
                label: "Hands",
                icon: "hand.raised",
                color: handStatus.color(positive: .indigo)
            )
            StatBadge(
                value: "\(vm.pendingApprovalCount)",
                label: "Approvals",
                icon: "exclamationmark.shield",
                color: approvalStatus.color(positive: .green)
            )
            StatBadge(
                value: "\(vm.enabledAutomationCount)/\(vm.automationDefinitionCount)",
                label: "Automation",
                icon: "flowchart",
                color: automationStatus.color(positive: .blue)
            )
            StatBadge(
                value: "\(vm.diagnosticsIssueCount)",
                label: "Diagnostics",
                icon: "stethoscope",
                color: diagnosticsStatus.color(positive: .green)
            )
            StatBadge(
                value: "\(vm.securityFeatureCount)",
                label: "Security",
                icon: "lock.shield",
                color: securityStatus.color(positive: .green)
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
            ResponsiveValueRow(horizontalSpacing: 10) {
                Text(label)
                    .foregroundStyle(.secondary)
            } value: {
                Text(value)
                    .fontWeight(.medium)
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
        MonitoringFactsRow(verticalSpacing: 8, headerVerticalSpacing: 6) {
            providerSummary
        } accessory: {
            StatusPill(text: provider.localizedStatusLabel, color: provider.statusTone.color)
        } facts: {
            providerFacts
        }
        .padding(.vertical, 2)
    }

    private var discoveredModelsLabel: String {
        let count = provider.discoveredModels?.count ?? 0
        return count == 1
            ? String(localized: "1 discovered")
            : String(localized: "\(count) discovered")
    }

    private var providerSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(provider.displayName)
                .font(.subheadline.weight(.medium))
            Text(provider.id)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var providerFacts: some View {
        Label("\(provider.modelCount)", systemImage: "square.stack.3d.up")
            .foregroundStyle(.secondary)
        if let latencyMs = provider.latencyMs, provider.isLocal == true {
            Label("\(latencyMs) ms", systemImage: "speedometer")
                .foregroundStyle(.secondary)
        }
        if provider.discoveredModels?.isEmpty == false {
            Label(discoveredModelsLabel, systemImage: "sparkles")
                .foregroundStyle(.secondary)
        }
    }
}

private struct SessionRow: View {
    let session: SessionInfo
    let agentName: String?

    var body: some View {
        MonitoringFactsRow(verticalSpacing: 6, headerHorizontalSpacing: 8) {
            titleLabel
        } accessory: {
            timestampLabel
        } facts: {
            metadataLabels
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

    private var titleLabel: some View {
        Text((session.label?.isEmpty == false ? session.label : nil) ?? shortSessionId)
            .font(.subheadline.weight(.medium))
            .lineLimit(2)
    }

    private var timestampLabel: some View {
        Text(relativeCreatedAt)
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private var metadataLabels: some View {
        Label(agentName ?? session.agentId, systemImage: "cpu")
        Label("\(session.messageCount)", systemImage: "bubble.left.and.bubble.right")
    }
}

private struct MCPServerRow: View {
    let server: MCPConnectedServer

    var body: some View {
        MonitoringFactsRow(verticalSpacing: 6, headerVerticalSpacing: 6) {
            Text(server.name)
                .font(.subheadline.weight(.medium))
        } accessory: {
            StatusPill(text: server.connected ? String(localized: "Connected") : String(localized: "Offline"), color: server.connected ? .green : .orange)
        } facts: {
            toolsFacts
        }
        .padding(.vertical, 2)
    }

    private var toolsLabel: String {
        server.toolsCount == 1
            ? String(localized: "1 tool")
            : String(localized: "\(server.toolsCount) tools")
    }

    @ViewBuilder
    private var toolsFacts: some View {
        Label(toolsLabel, systemImage: "wrench.and.screwdriver")
        if let topTool = server.tools.first?.name {
            Label(topTool, systemImage: "hammer")
        }
    }
}

private struct ChannelStatusRow: View {
    let channel: ChannelStatus

    var body: some View {
        ResponsiveAccessoryRow(horizontalAlignment: .top, verticalSpacing: 8) {
            channelSummary
        } accessory: {
            channelStatus
        }
        .padding(.vertical, 2)
    }

    private var channelSummary: some View {
        ResponsiveIconDetailRow(horizontalSpacing: 12, verticalSpacing: 6, spacerMinLength: 0) {
            channelIcon
        } detail: {
            channelTextBlock
        }
    }

    private var channelIcon: some View {
        Text(channel.icon)
            .font(.title3)
            .frame(width: 28, alignment: .leading)
    }

    private var channelTextBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(channel.displayName)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Text(channel.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var channelStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            StatusPill(
                text: channel.localizedConfigurationLabel,
                color: channel.configurationTone.color
            )
            Text(channel.localizedCategoryLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct HandInstanceRow: View {
    let instance: HandInstance
    let handDisplayName: String

    var body: some View {
        MonitoringFactsRow(verticalSpacing: 6, headerVerticalSpacing: 6) {
            handSummary
        } accessory: {
            StatusPill(text: statusText, color: instance.statusTone.color)
        } facts: {
            handFacts
        }
        .padding(.vertical, 2)
    }

    private var handSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(handDisplayName)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            if let agentName = instance.agentName, !agentName.isEmpty {
                Text(agentName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var handFacts: some View {
        Label(relativeText(from: instance.activatedAt), systemImage: "play.circle")
        Label(relativeText(from: instance.updatedAt), systemImage: "clock.arrow.circlepath")
    }

    private var statusText: String {
        instance.localizedStatusLabel
    }

    private func relativeText(from value: String) -> String {
        guard let date = value.iso8601Date else { return value }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

private struct HandDefinitionRow: View {
    let hand: HandDefinition

    var body: some View {
        ResponsiveAccessoryRow(horizontalAlignment: .top, verticalSpacing: 8) {
            handSummary
        } accessory: {
            readinessBadge
        }
        .padding(.vertical, 2)
    }

    private var handSummary: some View {
        ResponsiveIconDetailRow(horizontalSpacing: 12, verticalSpacing: 6, spacerMinLength: 0) {
            handIcon
        } detail: {
            handTextBlock
        }
    }

    private var handIcon: some View {
        Text(hand.icon)
            .font(.title3)
            .frame(width: 28, alignment: .leading)
    }

    private var handTextBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hand.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Text(hand.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var readinessBadge: some View {
        StatusPill(
            text: hand.degraded ? String(localized: "Degraded") : hand.requirementsMet ? String(localized: "Ready") : String(localized: "Blocked"),
            color: hand.degraded ? .orange : hand.requirementsMet ? .green : .secondary
        )
    }
}

private struct ApprovalRow: View {
    let approval: ApprovalItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ResponsiveAccessoryRow(verticalSpacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(approval.actionSummary)
                        .font(.subheadline.weight(.medium))
                    Text(approval.agentName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } accessory: {
                StatusPill(text: localizedRiskLevel, color: approval.riskTone.color)
            }

            if !approval.description.isEmpty {
                Text(approval.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            FlowLayout(spacing: 12) {
                Label(approval.toolName, systemImage: "wrench.and.screwdriver")
                Label(relativeRequestedAt, systemImage: "clock")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var relativeRequestedAt: String {
        guard let date = approval.requestedAt.iso8601Date else { return approval.requestedAt }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private var localizedRiskLevel: String {
        approval.localizedRiskLabel
    }
}

private struct PeerRow: View {
    let peer: PeerStatus

    var body: some View {
        MonitoringFactsRow(verticalSpacing: 6, headerVerticalSpacing: 6) {
            peerSummary
        } accessory: {
            StatusPill(text: localizedStateLabel, color: peer.stateTone.color)
        } facts: {
            peerFacts
        }
        .padding(.vertical, 2)
    }

    private var peerSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(peer.nodeName.isEmpty ? peer.nodeId : peer.nodeName)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Text(peer.address)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var peerFacts: some View {
        Label(agentsLabel, systemImage: "cpu")
        Label(peer.protocolVersion, systemImage: "point.3.connected.trianglepath.dotted")
    }

    private var localizedStateLabel: String {
        peer.localizedStateLabel
    }

    private var agentsLabel: String {
        peer.agents.count == 1
            ? String(localized: "1 agent")
            : String(localized: "\(peer.agents.count) agents")
    }
}

private struct AuditEventRow: View {
    let entry: AuditEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ResponsiveAccessoryRow(verticalSpacing: 4) {
                titleLabel
            } accessory: {
                timestampLabel
            }
            Text(entry.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(entry.outcome)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(entry.severity.tone.color)
        }
        .padding(.vertical, 2)
    }

    private var relativeText: String {
        guard let date = entry.timestamp.iso8601Date else { return entry.timestamp }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private var titleLabel: some View {
        Text(entry.friendlyAction)
            .font(.subheadline.weight(.medium))
            .lineLimit(2)
    }

    private var timestampLabel: some View {
        Text(relativeText)
            .font(.caption2)
            .foregroundStyle(.tertiary)
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
        TintedCapsuleBadge(
            text: text,
            foregroundStyle: color,
            backgroundStyle: color.opacity(0.14)
        )
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

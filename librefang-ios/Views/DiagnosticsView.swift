import SwiftUI

private enum DiagnosticsSectionAnchor: Hashable {
    case health
    case warnings
    case build
    case config
    case metrics
    case tokenLeaders
    case toolLeaders
}

struct DiagnosticsView: View {
    @Environment(\.dependencies) private var deps

    private var vm: DashboardViewModel { deps.dashboardViewModel }
    private var metrics: PrometheusMetricsSnapshot? { vm.metricsSnapshot }
    private var hasDiagnosticsData: Bool {
        vm.healthDetail != nil || vm.versionInfo != nil || vm.configSummary != nil || metrics != nil
    }
    private var diagnosticsJumpCount: Int {
        [
            vm.healthDetail != nil,
            !(vm.healthDetail?.configWarnings.isEmpty ?? true),
            vm.versionInfo != nil,
            vm.configSummary != nil,
            metrics != nil,
            !(metrics?.tokenLeaders.isEmpty ?? true),
            !(metrics?.toolCallLeaders.isEmpty ?? true)
        ]
        .filter { $0 }
        .count
    }
    private var loadedFeedCount: Int {
        [
            vm.healthDetail != nil,
            vm.versionInfo != nil,
            vm.configSummary != nil,
            metrics != nil
        ]
        .filter { $0 }
        .count
    }
    private var leaderboardCount: Int {
        [
            !(metrics?.tokenLeaders.isEmpty ?? true),
            !(metrics?.toolCallLeaders.isEmpty ?? true)
        ]
        .filter { $0 }
        .count
    }
    private var diagnosticsSectionCount: Int {
        [
            vm.healthDetail != nil,
            !(vm.healthDetail?.configWarnings.isEmpty ?? true),
            vm.versionInfo != nil,
            vm.configSummary != nil,
            metrics != nil,
            !(metrics?.tokenLeaders.isEmpty ?? true),
            !(metrics?.toolCallLeaders.isEmpty ?? true)
        ]
        .filter { $0 }
        .count
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if let error = vm.error, !hasDiagnosticsData {
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
                    DiagnosticsScoreboard(vm: vm, metrics: metrics)
                        .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
                }

                if hasDiagnosticsData {
                    Section {
                        DiagnosticsStatusDeckCard(vm: vm, metrics: metrics)
                        DiagnosticsFeedInventoryDeck(
                            loadedFeedCount: loadedFeedCount,
                            leaderboardCount: leaderboardCount,
                            warningCount: vm.diagnosticsConfigWarningCount,
                            panicCount: vm.supervisorPanicCount,
                            restartCount: vm.supervisorRestartCount,
                            hasMetrics: metrics != nil,
                            hasHealth: vm.healthDetail != nil,
                            hasBuild: vm.versionInfo != nil,
                            hasConfig: vm.configSummary != nil
                        )
                        DiagnosticsSectionInventoryDeck(
                            sectionCount: diagnosticsSectionCount,
                            loadedFeedCount: loadedFeedCount,
                            leaderboardCount: leaderboardCount,
                            warningCount: vm.diagnosticsConfigWarningCount,
                            hasMetrics: metrics != nil,
                            hasHealth: vm.healthDetail != nil,
                            hasBuild: vm.versionInfo != nil,
                            hasConfig: vm.configSummary != nil
                        )
                        DiagnosticsPressureCoverageDeck(
                            warningCount: vm.diagnosticsConfigWarningCount,
                            panicCount: vm.supervisorPanicCount,
                            restartCount: vm.supervisorRestartCount,
                            loadedFeedCount: loadedFeedCount,
                            leaderboardCount: leaderboardCount,
                            hasMetrics: metrics != nil
                        )
                        DiagnosticsSupportCoverageDeck(
                            hasHealth: vm.healthDetail != nil,
                            hasBuild: vm.versionInfo != nil,
                            hasConfig: vm.configSummary != nil,
                            hasMetrics: metrics != nil,
                            warningCount: vm.diagnosticsConfigWarningCount,
                            panicCount: vm.supervisorPanicCount,
                            restartCount: vm.supervisorRestartCount
                        )
                        diagnosticsRouteDeck(proxy)
                    } header: {
                        Text("Controls")
                    } footer: {
                        Text("Keep state, jumps, and nearby surfaces together before the long sections.")
                    }
                }

                if let healthDetail = vm.healthDetail {
                    Section {
                        HealthDetailInventoryCard(
                            healthDetail: healthDetail,
                            uptimeLabel: formatDuration(healthDetail.uptimeSeconds)
                        )

                        DiagnosticsMetricRow(
                            label: String(localized: "Kernel Status"),
                            value: healthDetail.localizedStatusLabel,
                            detail: String(localized: "Database \(healthDetail.localizedDatabaseLabel)")
                        )
                        DiagnosticsMetricRow(
                            label: String(localized: "Uptime"),
                            value: formatDuration(healthDetail.uptimeSeconds),
                            detail: healthDetail.agentCount == 1
                                ? String(localized: "1 agent in registry")
                                : String(localized: "\(healthDetail.agentCount) agents in registry")
                        )
                        DiagnosticsMetricRow(
                            label: String(localized: "Supervisor"),
                            value: String(localized: "\(healthDetail.panicCount) panics / \(healthDetail.restartCount) restarts"),
                            detail: healthDetail.panicCount > 0 ? String(localized: "Kernel supervisor recovered at least one panic.") : String(localized: "No panic recovery recorded.")
                        )
                    } header: {
                        Text("Health Detail")
                    } footer: {
                        Text(healthDetail.isHealthy ? String(localized: "Deep health diagnostics are currently healthy.") : String(localized: "Deep health diagnostics report degraded runtime state."))
                    }
                    .id(DiagnosticsSectionAnchor.health)

                    if !healthDetail.configWarnings.isEmpty {
                        Section {
                            DiagnosticsWarningsInventoryCard(
                                warnings: healthDetail.configWarnings,
                                statusLabel: healthDetail.localizedStatusLabel
                            )

                            ForEach(Array(healthDetail.configWarnings.enumerated()), id: \.offset) { _, warning in
                                DiagnosticsWarningRow(warning: warning)
                            }
                        } header: {
                            Text("Config Warnings")
                        } footer: {
                            Text("These warnings come from the kernel config validator and usually explain drift before it becomes an outage.")
                        }
                        .id(DiagnosticsSectionAnchor.warnings)
                    }
                }

                if let versionInfo = vm.versionInfo {
                    Section {
                        BuildInventoryCard(
                            versionInfo: versionInfo,
                            shortSHA: shortSHA(versionInfo.gitSHA)
                        )

                        DiagnosticsMetricRow(
                            label: String(localized: "Version"),
                            value: versionInfo.version,
                            detail: versionInfo.name
                        )
                        DiagnosticsMetricRow(
                            label: String(localized: "Git SHA"),
                            value: shortSHA(versionInfo.gitSHA),
                            detail: versionInfo.buildDate
                        )
                        DiagnosticsMetricRow(
                            label: String(localized: "Toolchain"),
                            value: versionInfo.rustVersion,
                            detail: String(localized: "\(versionInfo.platform) / \(versionInfo.arch)")
                        )
                    } header: {
                        Text("Build")
                    }
                    .id(DiagnosticsSectionAnchor.build)
                }

                if let configSummary = vm.configSummary {
                    Section {
                        ConfigInventoryCard(configSummary: configSummary)

                        DiagnosticsMetricRow(
                            label: String(localized: "Home Dir"),
                            value: configSummary.homeDir,
                            detail: configSummary.dataDir
                        )
                        DiagnosticsMetricRow(
                            label: String(localized: "Default Model"),
                            value: configSummary.defaultModel.model,
                            detail: configSummary.defaultModel.provider
                        )
                        DiagnosticsMetricRow(
                            label: String(localized: "API Key"),
                            value: configSummary.apiKey,
                            detail: configSummary.defaultModel.apiKeyEnv ?? String(localized: "No provider env override")
                        )
                        DiagnosticsMetricRow(
                            label: String(localized: "Memory Decay"),
                            value: configSummary.memory.decayRate.formatted(.number.precision(.fractionLength(3))),
                            detail: String(localized: "Kernel memory compaction / decay tuning")
                        )
                    } header: {
                        Text("Config")
                    } footer: {
                        Text("This is the redacted runtime config view from the server, not local iPhone settings.")
                    }
                    .id(DiagnosticsSectionAnchor.config)
                }

                if let metrics {
                    Section {
                        MetricsInventoryCard(metrics: metrics)

                        DiagnosticsMetricRow(
                            label: String(localized: "Agents"),
                            value: String(localized: "\(metrics.activeAgents)/\(metrics.totalAgents) active"),
                            detail: String(localized: "Prometheus gauge snapshot")
                        )
                        DiagnosticsMetricRow(
                            label: String(localized: "Rolling Tokens"),
                            value: metrics.totalRollingTokens.formatted(),
                            detail: metrics.totalRollingToolCalls == 1
                                ? String(localized: "1 tool call in the current metrics window")
                                : String(localized: "\(metrics.totalRollingToolCalls.formatted()) tool calls in the current metrics window")
                        )
                        DiagnosticsMetricRow(
                            label: String(localized: "Supervisor Counters"),
                            value: String(localized: "\(metrics.panicCount) panics / \(metrics.restartCount) restarts"),
                            detail: String(localized: "Exported through /api/metrics")
                        )
                        if let versionLabel = metrics.versionLabel {
                            DiagnosticsMetricRow(
                                label: String(localized: "Metrics Version"),
                                value: versionLabel,
                                detail: String(localized: "Version label from librefang_info")
                            )
                        }
                    } header: {
                        Text("Metrics")
                    }
                    .id(DiagnosticsSectionAnchor.metrics)

                    if !metrics.tokenLeaders.isEmpty {
                        Section {
                            DiagnosticsLeadersInventoryCard(
                                title: String(localized: "Token Leaderboard"),
                                detail: String(localized: "Use the compact token slice to see top agent demand before reading the ranked rows."),
                                samples: metrics.tokenLeaders,
                                metricUnitSingular: String(localized: "token"),
                                metricUnitPlural: String(localized: "tokens"),
                                accessoryText: metrics.totalRollingTokens.formatted(),
                                accessoryTone: .warning
                            )

                            ForEach(Array(metrics.tokenLeaders.prefix(5).enumerated()), id: \.offset) { index, sample in
                                DiagnosticsMetricListRow(
                                    rank: index + 1,
                                    title: sample.labels["agent"] ?? String(localized: "Unknown agent"),
                                    subtitle: sample.labels["model"] ?? sample.labels["provider"] ?? String(localized: "Token usage"),
                                    value: Int(sample.value).formatted()
                                )
                            }
                        } header: {
                            Text("Token Leaders")
                        }
                        .id(DiagnosticsSectionAnchor.tokenLeaders)
                    }

                    if !metrics.toolCallLeaders.isEmpty {
                        Section {
                            DiagnosticsLeadersInventoryCard(
                                title: String(localized: "Tool Leaderboard"),
                                detail: String(localized: "Use the compact tool-call slice to see which agents are driving the most operator activity."),
                                samples: metrics.toolCallLeaders,
                                metricUnitSingular: String(localized: "tool call"),
                                metricUnitPlural: String(localized: "tool calls"),
                                accessoryText: metrics.totalRollingToolCalls.formatted(),
                                accessoryTone: .warning
                            )

                            ForEach(Array(metrics.toolCallLeaders.prefix(5).enumerated()), id: \.offset) { index, sample in
                                DiagnosticsMetricListRow(
                                    rank: index + 1,
                                    title: sample.labels["agent"] ?? String(localized: "Unknown agent"),
                                    subtitle: String(localized: "Tool calls"),
                                    value: Int(sample.value).formatted()
                                )
                            }
                        } header: {
                            Text("Tool Leaders")
                        }
                        .id(DiagnosticsSectionAnchor.toolLeaders)
                    }
                }

                if !hasDiagnosticsData && !vm.isLoading {
                    Section("Diagnostics") {
                        ContentUnavailableView(
                            "No Diagnostic Snapshot",
                            systemImage: "stethoscope",
                            description: Text("Deep runtime diagnostics are not available from the current server snapshot.")
                        )
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .refreshable {
                await vm.refresh()
            }
            .overlay {
                if vm.isLoading && !hasDiagnosticsData {
                    ProgressView("Loading diagnostics...")
                }
            }
            .task {
                if !hasDiagnosticsData {
                    await vm.refresh()
                }
            }
        }
    }

    @ViewBuilder
    private func diagnosticsRouteDeck(_ proxy: ScrollViewProxy) -> some View {
        MonitoringSurfaceGroupCard(
            title: String(localized: "Routes"),
            detail: String(localized: "Keep long diagnostic sections and nearby surfaces in one compact deck.")
        ) {
            DiagnosticsRouteInventoryDeck(
                primaryCount: 5,
                supportCount: 2,
                jumpCount: diagnosticsJumpCount,
                warningCount: vm.diagnosticsConfigWarningCount,
                panicCount: vm.supervisorPanicCount,
                hasMetrics: metrics != nil
            )
            DiagnosticsActionReadinessDeck(
                primaryCount: 5,
                supportCount: 2,
                jumpCount: diagnosticsJumpCount,
                hasHealth: vm.healthDetail != nil,
                hasBuild: vm.versionInfo != nil,
                hasConfig: vm.configSummary != nil,
                hasMetrics: metrics != nil,
                warningCount: vm.diagnosticsConfigWarningCount,
                panicCount: vm.supervisorPanicCount
            )

            MonitoringShortcutRail(
                title: String(localized: "Jumps"),
                detail: String(localized: "Jump through the longest diagnostic sections without scanning the full monitor.")
            ) {
                if let healthDetail = vm.healthDetail {
                    Button {
                        jump(proxy, to: .health)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Health"),
                            systemImage: "stethoscope",
                            tone: healthDetail.isHealthy ? .positive : .warning,
                            badgeText: healthDetail.localizedStatusLabel
                        )
                    }
                    .buttonStyle(.plain)

                    if !healthDetail.configWarnings.isEmpty {
                        Button {
                            jump(proxy, to: .warnings)
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Warnings"),
                                systemImage: "exclamationmark.triangle",
                                tone: .warning,
                                badgeText: healthDetail.configWarnings.count == 1 ? String(localized: "1 warning") : String(localized: "\(healthDetail.configWarnings.count) warnings")
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if vm.versionInfo != nil {
                    Button {
                        jump(proxy, to: .build)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Build"),
                            systemImage: "shippingbox"
                        )
                    }
                    .buttonStyle(.plain)
                }

                if vm.configSummary != nil {
                    Button {
                        jump(proxy, to: .config)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Config"),
                            systemImage: "gearshape.2"
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let metrics {
                    Button {
                        jump(proxy, to: .metrics)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Metrics"),
                            systemImage: "chart.xyaxis.line",
                            badgeText: metrics.totalRollingTokens.formatted()
                        )
                    }
                    .buttonStyle(.plain)

                    if !metrics.tokenLeaders.isEmpty {
                        Button {
                            jump(proxy, to: .tokenLeaders)
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Tokens"),
                                systemImage: "number",
                                tone: .warning,
                                badgeText: metrics.tokenLeaders.count == 1 ? String(localized: "1 leader") : String(localized: "\(metrics.tokenLeaders.count) leaders")
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if !metrics.toolCallLeaders.isEmpty {
                        Button {
                            jump(proxy, to: .toolLeaders)
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Tools"),
                                systemImage: "wrench.and.screwdriver",
                                tone: .warning,
                                badgeText: metrics.toolCallLeaders.count == 1 ? String(localized: "1 leader") : String(localized: "\(metrics.toolCallLeaders.count) leaders")
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            MonitoringShortcutRail(
                title: String(localized: "Primary"),
                detail: String(localized: "Keep the next diagnostic exits right below the deep-diagnostic digest.")
            ) {
                NavigationLink {
                    RuntimeView()
                } label: {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Runtime"),
                        systemImage: "server.rack",
                        tone: vm.runtimeAlertCount > 0 ? .warning : .neutral,
                        badgeText: vm.runtimeAlertCount > 0
                            ? (vm.runtimeAlertCount == 1 ? String(localized: "1 alert") : String(localized: "\(vm.runtimeAlertCount) alerts"))
                            : nil
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    IncidentsView()
                } label: {
                    MonitoringSurfaceShortcutChip(
                        title: String(localized: "Incidents"),
                        systemImage: "bell.badge",
                        tone: vm.monitoringAlerts.contains { $0.severity == .critical } ? .critical : .neutral,
                        badgeText: vm.monitoringAlerts.isEmpty
                            ? nil
                            : (vm.monitoringAlerts.count == 1 ? String(localized: "1 alert") : String(localized: "\(vm.monitoringAlerts.count) alerts"))
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
                detail: String(localized: "Keep workflow and comms drilldowns visible as secondary shortcuts instead of another long route stack.")
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
            }
        }
    }

    private func jump(_ proxy: ScrollViewProxy, to anchor: DiagnosticsSectionAnchor) {
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
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

    private func shortSHA(_ sha: String) -> String {
        guard sha.count > 12 else { return sha }
        return String(sha.prefix(12))
    }
}

private struct DiagnosticsScoreboard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let vm: DashboardViewModel
    let metrics: PrometheusMetricsSnapshot?

    private var warningStatus: MonitoringSummaryStatus {
        .countStatus(vm.diagnosticsConfigWarningCount, activeTone: .warning)
    }

    private var panicStatus: MonitoringSummaryStatus {
        .countStatus(vm.supervisorPanicCount, activeTone: .critical)
    }

    private var restartStatus: MonitoringSummaryStatus {
        .countStatus(vm.supervisorRestartCount, activeTone: .warning)
    }

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            StatBadge(
                value: vm.healthDetail?.localizedStatusLabel ?? "--",
                label: "Status",
                icon: "stethoscope",
                color: vm.diagnosticsSummaryTone.color
            )
            StatBadge(
                value: "\(vm.diagnosticsConfigWarningCount)",
                label: "Warnings",
                icon: "exclamationmark.triangle",
                color: warningStatus.tone.color
            )
            StatBadge(
                value: "\(vm.supervisorPanicCount)",
                label: "Panics",
                icon: "bolt.trianglebadge.exclamationmark",
                color: panicStatus.tone.color
            )
            StatBadge(
                value: "\(vm.supervisorRestartCount)",
                label: "Restarts",
                icon: "arrow.clockwise.circle",
                color: restartStatus.tone.color
            )
            StatBadge(
                value: "\(metrics?.totalRollingTokens ?? 0)",
                label: "Tokens",
                icon: "number",
                color: .blue
            )
            StatBadge(
                value: "\(metrics?.totalRollingToolCalls ?? 0)",
                label: "Tool Calls",
                icon: "wrench.and.screwdriver",
                color: .indigo
            )
        }
        .padding(.horizontal, 6)
    }
}

private struct DiagnosticsStatusDeckCard: View {
    let vm: DashboardViewModel
    let metrics: PrometheusMetricsSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(summary: summaryLine, verticalPadding: 4) {
                FlowLayout(spacing: 8) {
                    snapshotBadge(
                        label: String(localized: "Health"),
                        isPresent: vm.healthDetail != nil,
                        activeTone: vm.healthDetail?.isHealthy == false ? .warning : .positive
                    )
                    snapshotBadge(
                        label: String(localized: "Build"),
                        isPresent: vm.versionInfo != nil,
                        activeTone: .neutral
                    )
                    snapshotBadge(
                        label: String(localized: "Config"),
                        isPresent: vm.configSummary != nil,
                        activeTone: vm.diagnosticsConfigWarningCount > 0 ? .warning : .positive
                    )
                    snapshotBadge(
                        label: String(localized: "Metrics"),
                        isPresent: metrics != nil,
                        activeTone: .positive
                    )

                    if vm.diagnosticsConfigWarningCount > 0 {
                        PresentationToneBadge(
                            text: vm.diagnosticsConfigWarningCount == 1
                                ? String(localized: "1 warning")
                                : String(localized: "\(vm.diagnosticsConfigWarningCount) warnings"),
                            tone: .warning
                        )
                    }

                    if vm.supervisorPanicCount > 0 || vm.supervisorRestartCount > 0 {
                        PresentationToneBadge(
                            text: String(localized: "\(vm.supervisorPanicCount) panics / \(vm.supervisorRestartCount) restarts"),
                            tone: vm.supervisorPanicCount > 0 ? .critical : .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Deep-diagnostic facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Use this compact digest to decide whether health, config, or metrics deserves the next tap."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: vm.healthDetail?.localizedStatusLabel ?? String(localized: "Unavailable"),
                    tone: vm.diagnosticsSummaryTone
                )
            } facts: {
                Label(
                    vm.diagnosticsConfigWarningCount == 1 ? String(localized: "1 warning") : String(localized: "\(vm.diagnosticsConfigWarningCount) warnings"),
                    systemImage: "exclamationmark.triangle"
                )
                Label(
                    vm.supervisorPanicCount == 1 ? String(localized: "1 panic") : String(localized: "\(vm.supervisorPanicCount) panics"),
                    systemImage: "bolt.trianglebadge.exclamationmark"
                )
                Label(
                    vm.supervisorRestartCount == 1 ? String(localized: "1 restart") : String(localized: "\(vm.supervisorRestartCount) restarts"),
                    systemImage: "arrow.clockwise.circle"
                )
                Label(
                    metrics == nil
                        ? String(localized: "Metrics unavailable")
                        : String(localized: "\(metrics?.totalRollingTokens ?? 0) rolling tokens"),
                    systemImage: "number"
                )
                Label(
                    metrics == nil
                        ? String(localized: "No tool-call metrics")
                        : String(localized: "\(metrics?.totalRollingToolCalls ?? 0) tool calls"),
                    systemImage: "wrench.and.screwdriver"
                )
            }
        }
    }

    private var summaryLine: String {
        let loadedCount = [vm.healthDetail != nil, vm.versionInfo != nil, vm.configSummary != nil, metrics != nil]
            .filter { $0 }
            .count

        return loadedCount == 1
            ? String(localized: "1 diagnostic feed loaded")
            : String(localized: "\(loadedCount) diagnostic feeds loaded")
    }

    private func snapshotBadge(label: String, isPresent: Bool, activeTone: PresentationTone) -> some View {
        PresentationToneBadge(
            text: isPresent ? label : String(localized: "\(label) missing"),
            tone: isPresent ? activeTone : .neutral
        )
    }
}

private struct DiagnosticsFeedInventoryDeck: View {
    let loadedFeedCount: Int
    let leaderboardCount: Int
    let warningCount: Int
    let panicCount: Int
    let restartCount: Int
    let hasMetrics: Bool
    let hasHealth: Bool
    let hasBuild: Bool
    let hasConfig: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: hasHealth ? String(localized: "Health loaded") : String(localized: "Health pending"),
                        tone: hasHealth ? .positive : .neutral
                    )
                    PresentationToneBadge(
                        text: hasBuild ? String(localized: "Build loaded") : String(localized: "Build pending"),
                        tone: hasBuild ? .positive : .neutral
                    )
                    PresentationToneBadge(
                        text: hasConfig ? String(localized: "Config loaded") : String(localized: "Config pending"),
                        tone: hasConfig ? .positive : .neutral
                    )
                    PresentationToneBadge(
                        text: hasMetrics ? String(localized: "Metrics loaded") : String(localized: "Metrics pending"),
                        tone: hasMetrics ? .positive : .neutral
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Feed inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep feed coverage, leaderboards, and recovery counters visible before the route deck and long diagnostics sections."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: loadedFeedCount == 1 ? String(localized: "1 feed") : String(localized: "\(loadedFeedCount) feeds"),
                    tone: loadedFeedCount > 0 ? .positive : .neutral
                )
            } facts: {
                Label(
                    leaderboardCount == 1 ? String(localized: "1 leaderboard") : String(localized: "\(leaderboardCount) leaderboards"),
                    systemImage: "list.number"
                )
                Label(
                    warningCount == 1 ? String(localized: "1 warning") : String(localized: "\(warningCount) warnings"),
                    systemImage: "exclamationmark.triangle"
                )
                Label(
                    panicCount == 1 ? String(localized: "1 panic") : String(localized: "\(panicCount) panics"),
                    systemImage: "bolt.trianglebadge.exclamationmark"
                )
                Label(
                    restartCount == 1 ? String(localized: "1 restart") : String(localized: "\(restartCount) restarts"),
                    systemImage: "arrow.clockwise.circle"
                )
            }
        }
    }

    private var summaryLine: String {
        loadedFeedCount == 1
            ? String(localized: "1 deep-diagnostic feed is loaded into the current snapshot.")
            : String(localized: "\(loadedFeedCount) deep-diagnostic feeds are loaded into the current snapshot.")
    }

    private var detailLine: String {
        if leaderboardCount == 0 {
            return String(localized: "Feed coverage is grouped ahead of the route deck even when no token or tool leaderboard is present.")
        }
        return String(localized: "Feed coverage and leaderboard presence stay grouped before the route deck, so diagnostics start with signal coverage instead of links.")
    }
}

private struct DiagnosticsSectionInventoryDeck: View {
    let sectionCount: Int
    let loadedFeedCount: Int
    let leaderboardCount: Int
    let warningCount: Int
    let hasMetrics: Bool
    let hasHealth: Bool
    let hasBuild: Bool
    let hasConfig: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: detailLine,
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: sectionCount == 1 ? String(localized: "1 live section") : String(localized: "\(sectionCount) live sections"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: loadedFeedCount == 1 ? String(localized: "1 loaded feed") : String(localized: "\(loadedFeedCount) loaded feeds"),
                        tone: loadedFeedCount > 0 ? .positive : .neutral
                    )
                    if leaderboardCount > 0 {
                        PresentationToneBadge(
                            text: leaderboardCount == 1 ? String(localized: "1 leaderboard") : String(localized: "\(leaderboardCount) leaderboards"),
                            tone: .warning
                        )
                    }
                    if warningCount > 0 {
                        PresentationToneBadge(
                            text: warningCount == 1 ? String(localized: "1 warning") : String(localized: "\(warningCount) warnings"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Section inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep deep-diagnostic coverage visible before the long health, build, config, metrics, and leaderboard sections take over."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: hasMetrics ? String(localized: "Metrics ready") : String(localized: "Metrics pending"),
                    tone: hasMetrics ? .positive : .neutral
                )
            } facts: {
                if hasHealth {
                    Label(String(localized: "Health loaded"), systemImage: "stethoscope")
                }
                if hasBuild {
                    Label(String(localized: "Build loaded"), systemImage: "shippingbox")
                }
                if hasConfig {
                    Label(String(localized: "Config loaded"), systemImage: "gearshape.2")
                }
            }
        }
    }

    private var summaryLine: String {
        sectionCount == 1
            ? String(localized: "1 diagnostics section is active below the controls deck.")
            : String(localized: "\(sectionCount) diagnostics sections are active below the controls deck.")
    }

    private var detailLine: String {
        String(localized: "Deep-diagnostic coverage stays summarized here so the longer health, config, metrics, and leaderboard sections start with context.")
    }
}

private struct DiagnosticsPressureCoverageDeck: View {
    let warningCount: Int
    let panicCount: Int
    let restartCount: Int
    let loadedFeedCount: Int
    let leaderboardCount: Int
    let hasMetrics: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Pressure coverage keeps warnings and recovery counters readable before the long diagnostics sections begin."),
                detail: String(localized: "Use this deck to judge whether current diagnostics drag is config-heavy, recovery-heavy, or mostly metrics and leaderboards."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if warningCount > 0 {
                        PresentationToneBadge(
                            text: warningCount == 1 ? String(localized: "1 warning") : String(localized: "\(warningCount) warnings"),
                            tone: .warning
                        )
                    }
                    if panicCount > 0 {
                        PresentationToneBadge(
                            text: panicCount == 1 ? String(localized: "1 panic") : String(localized: "\(panicCount) panics"),
                            tone: .critical
                        )
                    }
                    if restartCount > 0 {
                        PresentationToneBadge(
                            text: restartCount == 1 ? String(localized: "1 restart") : String(localized: "\(restartCount) restarts"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Pressure coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep loaded feeds, leaderboards, and recovery counters readable before digging into health, config, and metrics detail."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: loadedFeedCount == 1 ? String(localized: "1 feed") : String(localized: "\(loadedFeedCount) feeds"),
                    tone: loadedFeedCount > 0 ? .positive : .neutral
                )
            } facts: {
                Label(
                    leaderboardCount == 1 ? String(localized: "1 leaderboard") : String(localized: "\(leaderboardCount) leaderboards"),
                    systemImage: "list.number"
                )
                Label(
                    hasMetrics ? String(localized: "Metrics ready") : String(localized: "Metrics pending"),
                    systemImage: "chart.xyaxis.line"
                )
            }
        }
    }
}

private struct DiagnosticsSupportCoverageDeck: View {
    let hasHealth: Bool
    let hasBuild: Bool
    let hasConfig: Bool
    let hasMetrics: Bool
    let warningCount: Int
    let panicCount: Int
    let restartCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep loaded diagnostics feeds and slower recovery or config drag readable before opening the detailed health, build, config, and metrics sections."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: hasHealth ? String(localized: "Health ready") : String(localized: "Health pending"),
                        tone: hasHealth ? .positive : .neutral
                    )
                    PresentationToneBadge(
                        text: hasConfig ? String(localized: "Config ready") : String(localized: "Config pending"),
                        tone: hasConfig ? .positive : .neutral
                    )
                    PresentationToneBadge(
                        text: hasMetrics ? String(localized: "Metrics ready") : String(localized: "Metrics pending"),
                        tone: hasMetrics ? .positive : .neutral
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Support coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep slower config, recovery, build, and metrics readiness visible before the detailed diagnostics feeds take over."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: hasBuild ? String(localized: "Build ready") : String(localized: "Build pending"),
                    tone: hasBuild ? .positive : .neutral
                )
            } facts: {
                if warningCount > 0 {
                    Label(
                        warningCount == 1 ? String(localized: "1 warning") : String(localized: "\(warningCount) warnings"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if panicCount > 0 || restartCount > 0 {
                    Label(
                        String(localized: "\(panicCount) panics / \(restartCount) restarts"),
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
            }
        }
    }

    private var summaryLine: String {
        if !hasMetrics || !hasConfig {
            return String(localized: "Diagnostics support coverage is currently waiting on one or more deep feeds.")
        }
        if warningCount > 0 || panicCount > 0 || restartCount > 0 {
            return String(localized: "Diagnostics support coverage is currently anchored by config or recovery drag.")
        }
        return String(localized: "Diagnostics support coverage is currently light and mostly reflects feed readiness.")
    }
}

private struct DiagnosticsRouteInventoryDeck: View {
    let primaryCount: Int
    let supportCount: Int
    let jumpCount: Int
    let warningCount: Int
    let panicCount: Int
    let hasMetrics: Bool

    var body: some View {
        MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
            FlowLayout(spacing: 8) {
                PresentationToneBadge(
                    text: primaryCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryCount) primary routes"),
                    tone: .neutral
                )
                PresentationToneBadge(
                    text: supportCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportCount) support routes"),
                    tone: .neutral
                )
                PresentationToneBadge(
                    text: jumpCount == 1 ? String(localized: "1 jump") : String(localized: "\(jumpCount) jumps"),
                    tone: jumpCount > 0 ? .positive : .neutral
                )
                if warningCount > 0 {
                    PresentationToneBadge(
                        text: warningCount == 1 ? String(localized: "1 warning") : String(localized: "\(warningCount) warnings"),
                        tone: .warning
                    )
                }
                if panicCount > 0 {
                    PresentationToneBadge(
                        text: panicCount == 1 ? String(localized: "1 panic") : String(localized: "\(panicCount) panics"),
                        tone: .critical
                    )
                }
                PresentationToneBadge(
                    text: hasMetrics ? String(localized: "Metrics ready") : String(localized: "Metrics missing"),
                    tone: hasMetrics ? .positive : .neutral
                )
            }
        }
    }

    private var summaryLine: String {
        let totalRoutes = primaryCount + supportCount + jumpCount
        return totalRoutes == 1
            ? String(localized: "1 diagnostic route is grouped in this deck.")
            : String(localized: "\(totalRoutes) diagnostic routes are grouped in this deck.")
    }

    private var detailLine: String {
        if jumpCount == 0 {
            return String(localized: "Primary and support routes stay grouped before the deep-diagnostic sections load.")
        }
        return String(localized: "Primary routes, support surfaces, and deep-section jumps stay grouped in one compact diagnostic deck.")
    }
}

private struct DiagnosticsActionReadinessDeck: View {
    let primaryCount: Int
    let supportCount: Int
    let jumpCount: Int
    let hasHealth: Bool
    let hasBuild: Bool
    let hasConfig: Bool
    let hasMetrics: Bool
    let warningCount: Int
    let panicCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to check whether health, config, metrics, and section jumps are ready before drilling into the deep diagnostics sections."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: hasHealth ? String(localized: "Health ready") : String(localized: "Health pending"),
                        tone: hasHealth ? .positive : .neutral
                    )
                    PresentationToneBadge(
                        text: hasMetrics ? String(localized: "Metrics ready") : String(localized: "Metrics pending"),
                        tone: hasMetrics ? .positive : .neutral
                    )
                    if warningCount > 0 {
                        PresentationToneBadge(
                            text: warningCount == 1 ? String(localized: "1 warning") : String(localized: "\(warningCount) warnings"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Action readiness"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep loaded feeds, jump breadth, and recovery pressure visible before opening health, build, config, and metrics sections."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: String(localized: "\(primaryCount + supportCount + jumpCount) actions"),
                    tone: .neutral
                )
            } facts: {
                Label(
                    primaryCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryCount) primary routes"),
                    systemImage: "arrowshape.turn.up.right"
                )
                Label(
                    supportCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportCount) support routes"),
                    systemImage: "square.grid.2x2"
                )
                if jumpCount > 0 {
                    Label(
                        jumpCount == 1 ? String(localized: "1 jump") : String(localized: "\(jumpCount) jumps"),
                        systemImage: "arrow.down.to.line"
                    )
                }
                if hasBuild {
                    Label(String(localized: "Build ready"), systemImage: "shippingbox")
                }
                if hasConfig {
                    Label(String(localized: "Config ready"), systemImage: "gearshape.2")
                }
                if panicCount > 0 {
                    Label(
                        panicCount == 1 ? String(localized: "1 panic") : String(localized: "\(panicCount) panics"),
                        systemImage: "bolt.trianglebadge.exclamationmark"
                    )
                }
            }
        }
    }

    private var summaryLine: String {
        if !hasHealth || !hasConfig || !hasMetrics {
            return String(localized: "Diagnostics action readiness is currently waiting on one or more deep feeds.")
        }
        if warningCount > 0 || panicCount > 0 {
            return String(localized: "Diagnostics action readiness is currently anchored by warning or recovery pressure.")
        }
        return String(localized: "Diagnostics action readiness is currently clear enough for deep section jumps and broader route pivots.")
    }
}

private struct HealthDetailInventoryCard: View {
    let healthDetail: HealthDetail
    let uptimeLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Kernel \(healthDetail.localizedStatusLabel) after \(uptimeLabel) of uptime."),
                detail: detailLine,
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: healthDetail.localizedStatusLabel, tone: healthDetail.statusTone)
                    PresentationToneBadge(
                        text: healthDetail.localizedDatabaseLabel,
                        tone: healthDetail.isHealthy ? .positive : .warning
                    )
                    if healthDetail.configWarnings.isEmpty {
                        PresentationToneBadge(text: String(localized: "No config warnings"), tone: .positive)
                    } else {
                        PresentationToneBadge(
                            text: healthDetail.configWarnings.count == 1
                                ? String(localized: "1 config warning")
                                : String(localized: "\(healthDetail.configWarnings.count) config warnings"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Health inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep kernel state, registry size, and supervisor recovery visible before drilling into warnings."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: uptimeLabel, tone: .neutral)
            } facts: {
                Label(
                    healthDetail.agentCount == 1 ? String(localized: "1 agent in registry") : String(localized: "\(healthDetail.agentCount) agents in registry"),
                    systemImage: "cpu"
                )
                Label(
                    healthDetail.panicCount == 1 ? String(localized: "1 panic") : String(localized: "\(healthDetail.panicCount) panics"),
                    systemImage: "bolt.trianglebadge.exclamationmark"
                )
                Label(
                    healthDetail.restartCount == 1 ? String(localized: "1 restart") : String(localized: "\(healthDetail.restartCount) restarts"),
                    systemImage: "arrow.clockwise.circle"
                )
                Label(healthDetail.version, systemImage: "shippingbox")
            }
        }
        .padding(.vertical, 2)
    }

    private var detailLine: String {
        if healthDetail.configWarnings.isEmpty {
            return String(localized: "Database connectivity is healthy and the runtime validator has not raised any config warnings.")
        }
        return String(localized: "Database \(healthDetail.localizedDatabaseLabel). Validator surfaced \(healthDetail.configWarnings.count) config warnings for follow-up.")
    }
}

private struct BuildInventoryCard: View {
    let versionInfo: BuildVersionInfo
    let shortSHA: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "\(versionInfo.name) \(versionInfo.version) is the active server build."),
                detail: String(localized: "Built on \(versionInfo.buildDate) for \(versionInfo.platform) / \(versionInfo.arch)."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: versionInfo.version, tone: .neutral)
                    PresentationToneBadge(text: shortSHA, tone: .neutral)
                    PresentationToneBadge(text: versionInfo.platform, tone: .neutral)
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Build inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the deployed build identity visible before comparing logs, metrics, or runtime drift."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: versionInfo.arch, tone: .neutral)
            } facts: {
                Label(versionInfo.name, systemImage: "shippingbox")
                Label(versionInfo.rustVersion, systemImage: "hammer")
                Label(versionInfo.buildDate, systemImage: "calendar")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ConfigInventoryCard: View {
    let configSummary: RuntimeConfigSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "\(configSummary.defaultModel.provider) / \(configSummary.defaultModel.model) is the runtime default model."),
                detail: String(localized: "This redacted config snapshot comes from the server and keeps home, data, auth, and memory tuning visible before deeper config rows."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: configSummary.defaultModel.provider, tone: .neutral)
                    PresentationToneBadge(text: configSummary.defaultModel.model, tone: .neutral)
                    PresentationToneBadge(
                        text: configSummary.defaultModel.apiKeyEnv ?? String(localized: "Default auth env"),
                        tone: configSummary.defaultModel.apiKeyEnv == nil ? .neutral : .positive
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Config inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Use this compact config slice to confirm model, auth, and memory tuning before reading full path details."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: configSummary.memory.decayRate.formatted(.number.precision(.fractionLength(3))),
                    tone: .neutral
                )
            } facts: {
                Label(configSummary.homeDir, systemImage: "house")
                Label(configSummary.dataDir, systemImage: "internaldrive")
                Label(configSummary.apiKey, systemImage: "key")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct MetricsInventoryCard: View {
    let metrics: PrometheusMetricsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "\(metrics.activeAgents)/\(metrics.totalAgents) agents are active in the current metrics window."),
                detail: String(localized: "\(metrics.totalRollingTokens.formatted()) rolling tokens and \(metrics.totalRollingToolCalls.formatted()) tool calls are flowing through the Prometheus snapshot."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if let versionLabel = metrics.versionLabel {
                        PresentationToneBadge(text: versionLabel, tone: .neutral)
                    }
                    PresentationToneBadge(
                        text: metrics.tokenLeaders.count == 1 ? String(localized: "1 token leader") : String(localized: "\(metrics.tokenLeaders.count) token leaders"),
                        tone: metrics.tokenLeaders.isEmpty ? .neutral : .warning
                    )
                    PresentationToneBadge(
                        text: metrics.toolCallLeaders.count == 1 ? String(localized: "1 tool leader") : String(localized: "\(metrics.toolCallLeaders.count) tool leaders"),
                        tone: metrics.toolCallLeaders.isEmpty ? .neutral : .warning
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Metrics inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep rolling demand, supervisor counters, and leaderboard presence visible before opening the raw metric rows."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: metrics.totalRollingTokens.formatted(),
                    tone: metrics.totalRollingTokens > 0 ? .warning : .neutral
                )
            } facts: {
                Label(
                    metrics.totalRollingToolCalls == 1 ? String(localized: "1 tool call") : String(localized: "\(metrics.totalRollingToolCalls.formatted()) tool calls"),
                    systemImage: "wrench.and.screwdriver"
                )
                Label(
                    metrics.panicCount == 1 ? String(localized: "1 panic") : String(localized: "\(metrics.panicCount) panics"),
                    systemImage: "bolt.trianglebadge.exclamationmark"
                )
                Label(
                    metrics.restartCount == 1 ? String(localized: "1 restart") : String(localized: "\(metrics.restartCount) restarts"),
                    systemImage: "arrow.clockwise.circle"
                )
                Label(
                    metrics.uptimeSeconds > 0 ? String(localized: "\(metrics.uptimeSeconds) seconds tracked") : String(localized: "Uptime exporting"),
                    systemImage: "timer"
                )
            }
        }
        .padding(.vertical, 2)
    }
}

private struct DiagnosticsWarningsInventoryCard: View {
    let warnings: [String]
    let statusLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: warnings.count == 1
                    ? String(localized: "1 validator warning is active in the current runtime snapshot.")
                    : String(localized: "\(warnings.count) validator warnings are active in the current runtime snapshot."),
                detail: String(localized: "Use the compact warning slice to judge config drift before reading each validator message."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: statusLabel, tone: .warning)
                    PresentationToneBadge(
                        text: warnings.count == 1 ? String(localized: "1 warning visible") : String(localized: "\(warnings.count) warnings visible"),
                        tone: .warning
                    )
                    PresentationToneBadge(
                        text: uniqueWarningWordCount == 1
                            ? String(localized: "1 keyword cluster")
                            : String(localized: "\(uniqueWarningWordCount) keyword clusters"),
                        tone: uniqueWarningWordCount > 1 ? .caution : .neutral
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Warning inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep validator depth, repeated warning themes, and kernel state visible before the warning list."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: warnings.count == 1 ? String(localized: "Single issue") : String(localized: "Drift cluster"),
                    tone: warnings.count > 1 ? .warning : .caution
                )
            } facts: {
                Label(
                    warnings.count == 1 ? String(localized: "1 validator warning") : String(localized: "\(warnings.count) validator warnings"),
                    systemImage: "exclamationmark.triangle"
                )
                Label(
                    longestWarningLabel,
                    systemImage: "text.alignleft"
                )
                Label(
                    uniqueWarningWordCount == 1
                        ? String(localized: "1 warning theme")
                        : String(localized: "\(uniqueWarningWordCount) warning themes"),
                    systemImage: "square.stack.3d.down.right"
                )
            }
        }
        .padding(.vertical, 2)
    }

    private var uniqueWarningWordCount: Int {
        Set(
            warnings.compactMap { warning in
                warning
                    .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                    .first
                    .map { String($0).lowercased() }
            }
        ).count
    }

    private var longestWarningLabel: String {
        let maxLength = warnings.map(\.count).max() ?? 0
        return maxLength > 80
            ? String(localized: "Long-form warning present")
            : String(localized: "Compact warning set")
    }
}

private struct DiagnosticsLeadersInventoryCard: View {
    let title: String
    let detail: String
    let samples: [PrometheusMetricSample]
    let metricUnitSingular: String
    let metricUnitPlural: String
    let accessoryText: String
    let accessoryTone: PresentationTone

    private var visibleSamples: [PrometheusMetricSample] {
        Array(samples.prefix(5))
    }

    private var leader: PrometheusMetricSample? {
        visibleSamples.first
    }

    private var uniqueAgentCount: Int {
        Set(visibleSamples.map { $0.labels["agent"] ?? String(localized: "Unknown agent") }).count
    }

    private var visibleValueTotal: Int {
        Int(visibleSamples.reduce(0) { $0 + $1.value })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: detailLine,
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if let leader {
                        PresentationToneBadge(text: leaderTitle(for: leader), tone: accessoryTone)
                    }
                    PresentationToneBadge(
                        text: visibleSamples.count == 1
                            ? String(localized: "1 visible leader")
                            : String(localized: "\(visibleSamples.count) visible leaders"),
                        tone: .neutral
                    )
                    PresentationToneBadge(
                        text: uniqueAgentCount == 1
                            ? String(localized: "1 agent represented")
                            : String(localized: "\(uniqueAgentCount) agents represented"),
                        tone: uniqueAgentCount > 1 ? .positive : .neutral
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: accessoryText, tone: accessoryTone)
            } facts: {
                if let leader {
                    Label(leaderTitle(for: leader), systemImage: "person.crop.circle")
                    if let modelLabel = modelLabel(for: leader) {
                        Label(modelLabel, systemImage: "square.stack.3d.up")
                    }
                    Label(valueLabel(for: leader), systemImage: "number")
                }
                Label(
                    visibleValueTotal == 1
                        ? String(localized: "1 visible \(metricUnitSingular)")
                        : String(localized: "\(visibleValueTotal.formatted()) visible \(metricUnitPlural)"),
                    systemImage: "chart.bar"
                )
                Label(
                    uniqueAgentCount == 1 ? String(localized: "1 agent") : String(localized: "\(uniqueAgentCount) agents"),
                    systemImage: "person.2"
                )
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        guard let leader else {
            return String(localized: "No leaders are available in this metrics slice.")
        }
        return String(localized: "\(leaderTitle(for: leader)) is currently leading this metrics slice.")
    }

    private var detailLine: String {
        if visibleSamples.count == samples.count {
            return samples.count == 1
                ? String(localized: "The only ranked sample is surfaced before the leaderboard rows.")
                : String(localized: "All \(samples.count) ranked samples are surfaced before the leaderboard rows.")
        }
        return String(localized: "\(visibleSamples.count) of \(samples.count) ranked samples are surfaced before the leaderboard rows.")
    }

    private func leaderTitle(for sample: PrometheusMetricSample) -> String {
        sample.labels["agent"] ?? String(localized: "Unknown agent")
    }

    private func modelLabel(for sample: PrometheusMetricSample) -> String? {
        sample.labels["model"] ?? sample.labels["provider"]
    }

    private func valueLabel(for sample: PrometheusMetricSample) -> String {
        let value = Int(sample.value).formatted()
        return Int(sample.value) == 1
            ? String(localized: "\(value) \(metricUnitSingular)")
            : String(localized: "\(value) \(metricUnitPlural)")
    }
}

private struct DiagnosticsMetricRow: View {
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
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

private struct DiagnosticsMetricListRow: View {
    let rank: Int
    let title: String
    let subtitle: String
    let value: String

    var body: some View {
        ResponsiveValueRow(horizontalSpacing: 10, verticalSpacing: 6) {
            HStack(spacing: 10) {
                rankLabel
                titleBlock
            }
        } value: {
            valueLabel
        }
        .padding(.vertical, 2)
    }

    private var rankLabel: some View {
        Text("#\(rank)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.tertiary)
            .frame(width: 24)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var valueLabel: some View {
        Text(value)
            .font(.subheadline.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private struct DiagnosticsWarningRow: View {
    let warning: String

    var body: some View {
        ResponsiveValueRow(
            horizontalAlignment: .top,
            horizontalSpacing: 10,
            verticalSpacing: 6,
            horizontalTextAlignment: .leading
        ) {
            warningIcon
        } value: {
            warningText
        }
        .padding(.vertical, 2)
    }

    private var warningIcon: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
    }

    private var warningText: some View {
        Text(warning)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

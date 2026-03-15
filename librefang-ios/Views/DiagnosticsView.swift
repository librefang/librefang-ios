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
                        diagnosticsRouteDeck(proxy)
                    } header: {
                        Text("Operator Deck")
                    } footer: {
                        Text("Keep diagnostic state, deeper focus jumps, and neighboring operator surfaces together before the long sections.")
                    }
                }

                if let healthDetail = vm.healthDetail {
                    Section {
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
                            ForEach(Array(metrics.tokenLeaders.prefix(5).enumerated()), id: \.offset) { index, sample in
                                DiagnosticsMetricListRow(
                                    rank: index + 1,
                                    title: sample.labels["agent"] ?? String(localized: "Unknown agent"),
                                    subtitle: sample.labels["model"] ?? sample.labels["provider"] ?? String(localized: "Token usage"),
                                    value: Int(sample.value).formatted()
                                )
                            }
                        } header: {
                            Text("Top Token Usage")
                        }
                        .id(DiagnosticsSectionAnchor.tokenLeaders)
                    }

                    if !metrics.toolCallLeaders.isEmpty {
                        Section {
                            ForEach(Array(metrics.toolCallLeaders.prefix(5).enumerated()), id: \.offset) { index, sample in
                                DiagnosticsMetricListRow(
                                    rank: index + 1,
                                    title: sample.labels["agent"] ?? String(localized: "Unknown agent"),
                                    subtitle: String(localized: "Tool calls"),
                                    value: Int(sample.value).formatted()
                                )
                            }
                        } header: {
                            Text("Top Tool Calls")
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
            title: String(localized: "Route Deck"),
            detail: String(localized: "Keep the longest diagnostic sections and neighboring operator surfaces in one compact deck.")
        ) {
            MonitoringShortcutRail(
                title: String(localized: "Focus Areas"),
                detail: String(localized: "Keep the longest diagnostic sections reachable as compact jump targets without scanning the full monitor.")
            ) {
                if let healthDetail = vm.healthDetail {
                    Button {
                        jump(proxy, to: .health)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Health Detail"),
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
                                title: String(localized: "Config Warnings"),
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
                            title: String(localized: "Build Metadata"),
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
                            title: String(localized: "Runtime Config"),
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
                            title: String(localized: "Metrics Snapshot"),
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
                                title: String(localized: "Top Token Usage"),
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
                                title: String(localized: "Top Tool Calls"),
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
                title: String(localized: "Primary Routes"),
                detail: String(localized: "Keep the next diagnostic exits visible as compact shortcuts beside the deep-diagnostic digest.")
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
                title: String(localized: "Support Routes"),
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
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
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
        .padding(.horizontal)
    }
}

private struct DiagnosticsStatusDeckCard: View {
    let vm: DashboardViewModel
    let metrics: PrometheusMetricsSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

import SwiftUI

struct DiagnosticsView: View {
    @Environment(\.dependencies) private var deps

    private var vm: DashboardViewModel { deps.dashboardViewModel }
    private var metrics: PrometheusMetricsSnapshot? { vm.metricsSnapshot }
    private var hasDiagnosticsData: Bool {
        vm.healthDetail != nil || vm.versionInfo != nil || vm.configSummary != nil || metrics != nil
    }

    var body: some View {
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

                if !healthDetail.configWarnings.isEmpty {
                    Section {
                        ForEach(Array(healthDetail.configWarnings.enumerated()), id: \.offset) { _, warning in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(warning)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Config Warnings")
                    } footer: {
                        Text("These warnings come from the kernel config validator and usually explain drift before it becomes an outage.")
                    }
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

private struct DiagnosticsMetricRow: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(label)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(value)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.trailing)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .fontWeight(.medium)
                }
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                rankLabel
                titleBlock
                Spacer()
                valueLabel
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    rankLabel
                    titleBlock
                }
                valueLabel
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var valueLabel: some View {
        Text(value)
            .font(.subheadline.monospacedDigit())
    }
}

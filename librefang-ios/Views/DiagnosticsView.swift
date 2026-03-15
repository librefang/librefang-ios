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
                        label: "Kernel Status",
                        value: healthDetail.status.capitalized,
                        detail: "Database \(healthDetail.database.capitalized)"
                    )
                    DiagnosticsMetricRow(
                        label: "Uptime",
                        value: formatDuration(healthDetail.uptimeSeconds),
                        detail: "\(healthDetail.agentCount) agents in registry"
                    )
                    DiagnosticsMetricRow(
                        label: "Supervisor",
                        value: "\(healthDetail.panicCount) panics / \(healthDetail.restartCount) restarts",
                        detail: healthDetail.panicCount > 0 ? "Kernel supervisor recovered at least one panic." : "No panic recovery recorded."
                    )
                } header: {
                    Text("Health Detail")
                } footer: {
                    Text(healthDetail.isHealthy ? "Deep health diagnostics are currently healthy." : "Deep health diagnostics report degraded runtime state.")
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
                        label: "Version",
                        value: versionInfo.version,
                        detail: versionInfo.name
                    )
                    DiagnosticsMetricRow(
                        label: "Git SHA",
                        value: shortSHA(versionInfo.gitSHA),
                        detail: versionInfo.buildDate
                    )
                    DiagnosticsMetricRow(
                        label: "Toolchain",
                        value: versionInfo.rustVersion,
                        detail: "\(versionInfo.platform) / \(versionInfo.arch)"
                    )
                } header: {
                    Text("Build")
                }
            }

            if let configSummary = vm.configSummary {
                Section {
                    DiagnosticsMetricRow(
                        label: "Home Dir",
                        value: configSummary.homeDir,
                        detail: configSummary.dataDir
                    )
                    DiagnosticsMetricRow(
                        label: "Default Model",
                        value: configSummary.defaultModel.model,
                        detail: configSummary.defaultModel.provider
                    )
                    DiagnosticsMetricRow(
                        label: "API Key",
                        value: configSummary.apiKey,
                        detail: configSummary.defaultModel.apiKeyEnv ?? "No provider env override"
                    )
                    DiagnosticsMetricRow(
                        label: "Memory Decay",
                        value: String(format: "%.3f", configSummary.memory.decayRate),
                        detail: "Kernel memory compaction / decay tuning"
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
                        label: "Agents",
                        value: "\(metrics.activeAgents)/\(metrics.totalAgents) active",
                        detail: "Prometheus gauge snapshot"
                    )
                    DiagnosticsMetricRow(
                        label: "Rolling Tokens",
                        value: metrics.totalRollingTokens.formatted(),
                        detail: "\(metrics.totalRollingToolCalls.formatted()) tool calls in the current metrics window"
                    )
                    DiagnosticsMetricRow(
                        label: "Supervisor Counters",
                        value: "\(metrics.panicCount) panics / \(metrics.restartCount) restarts",
                        detail: "Exported through /api/metrics"
                    )
                    if let versionLabel = metrics.versionLabel {
                        DiagnosticsMetricRow(
                            label: "Metrics Version",
                            value: versionLabel,
                            detail: "Version label from librefang_info"
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
                                title: sample.labels["agent"] ?? "Unknown agent",
                                subtitle: sample.labels["model"] ?? sample.labels["provider"] ?? "Token usage",
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
                                title: sample.labels["agent"] ?? "Unknown agent",
                                subtitle: "Tool calls",
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
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func shortSHA(_ sha: String) -> String {
        guard sha.count > 12 else { return sha }
        return String(sha.prefix(12))
    }
}

private struct DiagnosticsScoreboard: View {
    let vm: DashboardViewModel
    let metrics: PrometheusMetricsSnapshot?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            StatBadge(
                value: vm.healthDetail?.status.capitalized ?? "--",
                label: "Status",
                icon: "stethoscope",
                color: vm.hasDiagnosticsIssue ? .orange : .green
            )
            StatBadge(
                value: "\(vm.diagnosticsConfigWarningCount)",
                label: "Warnings",
                icon: "exclamationmark.triangle",
                color: vm.diagnosticsConfigWarningCount > 0 ? .orange : .secondary
            )
            StatBadge(
                value: "\(vm.supervisorPanicCount)",
                label: "Panics",
                icon: "bolt.trianglebadge.exclamationmark",
                color: vm.supervisorPanicCount > 0 ? .red : .secondary
            )
            StatBadge(
                value: "\(vm.supervisorRestartCount)",
                label: "Restarts",
                icon: "arrow.clockwise.circle",
                color: vm.supervisorRestartCount > 0 ? .orange : .secondary
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
        HStack(spacing: 10) {
            Text("#\(rank)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(value)
                .font(.subheadline.monospacedDigit())
        }
        .padding(.vertical, 2)
    }
}

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

            if let healthDetail = vm.healthDetail {
                Section {
                    DiagnosticsMetricRow(
                        label: String(localized: "Kernel Status"),
                        value: healthDetail.localizedStatusLabel,
                        detail: nil
                    )
                    DiagnosticsMetricRow(
                        label: String(localized: "Uptime"),
                        value: formatDuration(healthDetail.uptimeSeconds),
                        detail: nil
                    )
                    DiagnosticsMetricRow(
                        label: String(localized: "Supervisor"),
                        value: String(localized: "\(healthDetail.panicCount) panics / \(healthDetail.restartCount) restarts")
                    )
                } header: {
                    Text("Health Detail")
                }

                if !healthDetail.configWarnings.isEmpty {
                    Section {
                        ForEach(Array(healthDetail.configWarnings.enumerated()), id: \.offset) { _, warning in
                            DiagnosticsWarningRow(warning: warning)
                        }
                    } header: {
                        Text("Config Warnings")
                    }
                }
            }

            if let versionInfo = vm.versionInfo {
                Section {
                    DiagnosticsMetricRow(
                        label: String(localized: "Version"),
                        value: versionInfo.version
                    )
                    DiagnosticsMetricRow(
                        label: String(localized: "Toolchain"),
                        value: versionInfo.rustVersion
                    )
                } header: {
                    Text("Build")
                }
            }

            if let configSummary = vm.configSummary {
                Section {
                    DiagnosticsMetricRow(
                        label: String(localized: "Home Dir"),
                        value: configSummary.homeDir
                    )
                    DiagnosticsMetricRow(
                        label: String(localized: "Default Model"),
                        value: configSummary.defaultModel.model,
                        detail: configSummary.defaultModel.provider
                    )
                    DiagnosticsMetricRow(
                        label: String(localized: "API Key"),
                        value: configSummary.apiKey
                    )
                } header: {
                    Text("Config")
                }
            }

            if let metrics {
                Section {
                    DiagnosticsMetricRow(
                        label: String(localized: "Agents"),
                        value: String(localized: "\(metrics.activeAgents)/\(metrics.totalAgents) active")
                    )
                    DiagnosticsMetricRow(
                        label: String(localized: "Rolling Tokens"),
                        value: metrics.totalRollingTokens.formatted()
                    )
                    DiagnosticsMetricRow(
                        label: String(localized: "Supervisor Counters"),
                        value: String(localized: "\(metrics.panicCount) panics / \(metrics.restartCount) restarts")
                    )
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
                        Text("Token Leaders")
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
                        Text("Tool Leaders")
                    }
                }
            }

            if !hasDiagnosticsData && !vm.isLoading {
                Section("Diagnostics") {
                    ContentUnavailableView(
                        "No Diagnostic Snapshot",
                        systemImage: "stethoscope",
                        description: Text("No deep diagnostic snapshot right now.")
                    )
                }
            }
        }
        .navigationTitle(String(localized: "Diagnostics"))
        .monitoringRefreshInteractionGate(isRefreshing: vm.isLoading)
        .refreshable {
            await vm.refresh()
        }
        .overlay {
            if vm.isLoading && !hasDiagnosticsData {
                ProgressView(String(localized: "Loading diagnostics..."))
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
}

private struct DiagnosticsMetricRow: View {

    let label: String
    let value: String
    let detail: String?

    var body: some View {
        ResponsiveValueRow(horizontalSpacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
        } value: {
            Text(displayValue)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }

    private var displayValue: String {
        guard let detail, !detail.isEmpty else { return value }
        return "\(value) · \(detail)"
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

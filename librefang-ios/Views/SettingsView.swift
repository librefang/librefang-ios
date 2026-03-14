import SwiftUI

struct SettingsView: View {
    @Environment(\.dependencies) private var deps
    @State private var serverURL = ServerConfig.saved.baseURL
    @State private var apiKey = ServerConfig.saved.apiKey
    @State private var refreshInterval: Double = UserDefaults.standard.double(forKey: "refreshInterval").clamped(to: 10...300, default: 30)
    @State private var isSaving = false
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Server URL", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("API Key (optional)", text: $apiKey)
                        .textInputAutocapitalization(.never)

                    Button {
                        Task { await saveAndTest() }
                    } label: {
                        HStack {
                            Text("Save & Test Connection")
                            Spacer()
                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                            } else if showSuccess {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .disabled(isSaving)
                }

                Section("Auto Refresh") {
                    HStack {
                        Text("Interval")
                        Spacer()
                        Text("\(Int(refreshInterval))s")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $refreshInterval, in: 10...120, step: 5) {
                        Text("Refresh Interval")
                    }
                    .onChange(of: refreshInterval) {
                        UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
                        deps.dashboardViewModel.startAutoRefresh(interval: refreshInterval)
                    }
                }

                Section("A2A Network") {
                    NavigationLink {
                        A2AAgentsView()
                            .navigationTitle("A2A Agents")
                    } label: {
                        HStack {
                            Label("External Agents", systemImage: "link.circle")
                            Spacer()
                            if let count = deps.dashboardViewModel.a2aAgents?.total {
                                Text("\(count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Monitoring") {
                    LabeledContent("Agents") {
                        Text("\(deps.dashboardViewModel.issueAgentCount) need attention")
                            .foregroundStyle(deps.dashboardViewModel.issueAgentCount > 0 ? .orange : .secondary)
                    }
                    LabeledContent("Providers") {
                        Text("\(deps.dashboardViewModel.configuredProviderCount) configured")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Channels") {
                        Text("\(deps.dashboardViewModel.readyChannelCount) ready")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Hands") {
                        Text("\(deps.dashboardViewModel.activeHandCount) active")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Approvals") {
                        Text("\(deps.dashboardViewModel.pendingApprovalCount) pending")
                            .foregroundStyle(deps.dashboardViewModel.pendingApprovalCount > 0 ? .red : .secondary)
                    }
                    LabeledContent("Peers") {
                        Text("\(deps.dashboardViewModel.connectedPeerCount)/\(deps.dashboardViewModel.totalPeerCount)")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("MCP") {
                        Text("\(deps.dashboardViewModel.connectedMCPServerCount)/\(deps.dashboardViewModel.configuredMCPServerCount)")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Sessions") {
                        Text("\(deps.dashboardViewModel.totalSessionCount)")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Watchlist") {
                        Text("\(deps.agentWatchlistStore.watchedAgentIDs.count)")
                            .foregroundStyle(deps.agentWatchlistStore.watchedAgentIDs.isEmpty ? .tertiary : .secondary)
                    }
                    LabeledContent("On Call Queue") {
                        Text("\(onCallQueueCount)")
                            .foregroundStyle(onCallQueueCount > 0 ? .orange : .secondary)
                    }
                    LabeledContent("Muted Alerts") {
                        Text("\(activeMutedAlertCount)")
                            .foregroundStyle(activeMutedAlertCount > 0 ? .secondary : .tertiary)
                    }
                    LabeledContent("Incident Snapshot") {
                        Text(snapshotStatus)
                            .foregroundStyle(snapshotStatusColor)
                    }
                    LabeledContent("Audit") {
                        Text(auditStatus)
                            .foregroundStyle(deps.dashboardViewModel.hasAuditIntegrityIssue ? .red : .secondary)
                    }
                    LabeledContent("Security") {
                        Text("\(deps.dashboardViewModel.securityFeatureCount) features")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "LibreFang iOS")
                    if let health = deps.dashboardViewModel.health {
                        LabeledContent("Server Version", value: health.version)
                        LabeledContent("Server Status", value: health.status)
                    }
                    if let refresh = deps.dashboardViewModel.lastRefresh {
                        LabeledContent("Last Refresh") {
                            Text(refresh, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func saveAndTest() async {
        isSaving = true
        showSuccess = false
        let config = ServerConfig(baseURL: serverURL, apiKey: apiKey)
        await deps.dashboardViewModel.updateServer(config)
        isSaving = false
        if deps.dashboardViewModel.health?.isHealthy == true {
            showSuccess = true
        }
    }

    private var auditStatus: String {
        guard let verify = deps.dashboardViewModel.auditVerify else { return "Unavailable" }
        return verify.valid ? "Verified" : "Broken"
    }

    private var activeMutedAlertCount: Int {
        deps.incidentStateStore.activeMutedAlerts(from: deps.dashboardViewModel.monitoringAlerts).count
    }

    private var onCallQueueCount: Int {
        let visibleAlerts = deps.incidentStateStore.visibleAlerts(from: deps.dashboardViewModel.monitoringAlerts)
        let watchedAttentionItems = deps.agentWatchlistStore
            .watchedAgents(from: deps.dashboardViewModel.agents)
            .map { deps.dashboardViewModel.attentionItem(for: $0) }

        return deps.dashboardViewModel.onCallPriorityItems(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems
        ).count
    }

    private var snapshotStatus: String {
        let visibleAlerts = deps.incidentStateStore.visibleAlerts(from: deps.dashboardViewModel.monitoringAlerts)

        if visibleAlerts.isEmpty {
            return activeMutedAlertCount > 0 ? "Muted" : "Clear"
        }

        return deps.incidentStateStore.isCurrentSnapshotAcknowledged(alerts: deps.dashboardViewModel.monitoringAlerts)
            ? "Acknowledged"
            : "Needs review"
    }

    private var snapshotStatusColor: Color {
        switch snapshotStatus {
        case "Needs review":
            .red
        case "Acknowledged":
            .orange
        case "Muted":
            .secondary
        default:
            .green
        }
    }
}

// MARK: - Helpers

private extension Double {
    func clamped(to range: ClosedRange<Double>, default defaultValue: Double) -> Double {
        if self == 0 { return defaultValue }
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

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
}

// MARK: - Helpers

private extension Double {
    func clamped(to range: ClosedRange<Double>, default defaultValue: Double) -> Double {
        if self == 0 { return defaultValue }
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

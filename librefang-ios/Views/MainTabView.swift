import SwiftUI

struct MainTabView: View {
    @Environment(\.dependencies) private var deps
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var showOnCall = false

    private var vm: DashboardViewModel { deps.dashboardViewModel }
    private var visibleMonitoringAlerts: [MonitoringAlertItem] {
        deps.incidentStateStore.visibleAlerts(from: vm.monitoringAlerts)
    }
    private var activeMutedAlertCount: Int {
        deps.incidentStateStore.activeMutedAlerts(from: vm.monitoringAlerts).count
    }
    private var visibleCriticalAlertCount: Int {
        visibleMonitoringAlerts.filter { $0.severity == .critical }.count
    }
    private var isCurrentSnapshotAcknowledged: Bool {
        deps.incidentStateStore.isCurrentSnapshotAcknowledged(alerts: vm.monitoringAlerts)
    }
    private var preferredOnCallSurface: OnCallSurfacePreference {
        deps.onCallFocusStore.preferredSurface
    }
    private var watchedAttentionItems: [AgentAttentionItem] {
        deps.agentWatchlistStore
            .watchedAgents(from: vm.agents)
            .map { vm.attentionItem(for: $0) }
            .filter { $0.severity > 0 }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return lhs.severity > rhs.severity
                }
                if lhs.agent.isRunning != rhs.agent.isRunning {
                    return lhs.agent.isRunning && !rhs.agent.isRunning
                }
                return lhs.agent.name.localizedCompare(rhs.agent.name) == .orderedAscending
            }
    }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                OverviewView()
                    .tabItem {
                        Label("Overview", systemImage: "gauge.open.with.lines.needle.33percent")
                    }
                    .tag(0)

                AgentsView()
                    .tabItem {
                        Label("Agents", systemImage: "cpu")
                    }
                    .badge(vm.issueAgentCount > 0 ? vm.issueAgentCount : 0)
                    .tag(1)

                RuntimeView()
                    .tabItem {
                        Label("Runtime", systemImage: "waveform.path.ecg")
                    }
                    .badge(runtimeAlertBadge)
                    .tag(2)

                BudgetView()
                    .tabItem {
                        Label("Budget", systemImage: "chart.bar")
                    }
                    .badge(budgetAlertBadge)
                    .tag(3)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(4)
            }
            .onChange(of: selectedTab) {
                HapticManager.selection()
            }

            // Offline Banner
            if !deps.networkMonitor.isConnected {
                OfflineBanner()
            } else if visibleCriticalAlertCount > 0 {
                Button {
                    showOnCall = true
                } label: {
                    if isCurrentSnapshotAcknowledged {
                        AcknowledgedIncidentBanner(count: visibleCriticalAlertCount, mutedCount: activeMutedAlertCount)
                    } else {
                        CriticalIncidentBanner(count: visibleCriticalAlertCount, mutedCount: activeMutedAlertCount)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            deps.dashboardViewModel.startAutoRefresh(interval: storedRefreshInterval)
            Task { await deps.onCallNotificationManager.refreshAuthorizationStatus() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                deps.dashboardViewModel.startAutoRefresh(interval: storedRefreshInterval)
                Task {
                    await deps.dashboardViewModel.refresh()
                    await deps.onCallNotificationManager.refreshAuthorizationStatus()
                    await deps.onCallNotificationManager.cancelPendingReminder()
                }
            case .background:
                deps.dashboardViewModel.stopAutoRefresh()
                Task {
                    await deps.onCallNotificationManager.armStandbyReminder(snapshot: reminderSnapshot)
                }
            default:
                break
            }
        }
        .sheet(isPresented: $showOnCall) {
            NavigationStack {
                if preferredOnCallSurface == .nightWatch {
                    NightWatchView()
                } else {
                    OnCallView()
                }
            }
        }
    }

    private var budgetAlertBadge: Int {
        vm.hasBudgetAlert ? 1 : 0
    }

    private var runtimeAlertBadge: Int {
        vm.runtimeAlertCount
    }

    private var storedRefreshInterval: TimeInterval {
        let value = UserDefaults.standard.double(forKey: "refreshInterval")
        return value == 0 ? 30 : min(max(value, 10), 120)
    }

    private var reminderSnapshot: OnCallReminderSnapshot? {
        vm.onCallReminderSnapshot(
            visibleAlerts: visibleMonitoringAlerts,
            watchedAttentionItems: watchedAttentionItems,
            scope: deps.onCallNotificationManager.scope,
            isAcknowledged: isCurrentSnapshotAcknowledged
        )
    }
}

// MARK: - Offline Banner

private struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .font(.caption2)
            Text("No Internet Connection")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.red.opacity(0.9))
    }
}

private struct CriticalIncidentBanner: View {
    let count: Int
    let mutedCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.badge.fill")
                .font(.caption)
            Text(count == 1 ? "1 critical incident active" : "\(count) critical incidents active")
                .font(.caption.weight(.semibold))
            Spacer()
            if mutedCount > 0 {
                Text("\(mutedCount) muted")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.12))
                    .clipShape(Capsule())
            }
            Text("On Call")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.18))
                .clipShape(Capsule())
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.red.opacity(0.92))
    }
}

private struct AcknowledgedIncidentBanner: View {
    let count: Int
    let mutedCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.caption)
            Text(count == 1 ? "1 critical incident acknowledged" : "\(count) critical incidents acknowledged")
                .font(.caption.weight(.semibold))
            Spacer()
            if mutedCount > 0 {
                Text("\(mutedCount) muted")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.12))
                    .clipShape(Capsule())
            }
            Text("On Call")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.18))
                .clipShape(Capsule())
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.92))
    }
}

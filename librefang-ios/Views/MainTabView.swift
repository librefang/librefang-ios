import SwiftUI

struct MainTabView: View {
    @Environment(\.dependencies) private var deps
    @State private var selectedTab = 0

    private var vm: DashboardViewModel { deps.dashboardViewModel }

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
                    .badge(vm.runningCount > 0 ? vm.runningCount : 0)
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
            }
        }
        .onAppear {
            deps.dashboardViewModel.startAutoRefresh(interval: storedRefreshInterval)
        }
    }

    private var budgetAlertBadge: Int {
        guard let budget = vm.budget else { return 0 }
        let maxPct = max(budget.hourlyPct, budget.dailyPct, budget.monthlyPct)
        return maxPct >= budget.alertThreshold ? 1 : 0
    }

    private var runtimeAlertBadge: Int {
        max(vm.pendingApprovalCount, vm.degradedHandCount > 0 ? 1 : 0)
    }

    private var storedRefreshInterval: TimeInterval {
        let value = UserDefaults.standard.double(forKey: "refreshInterval")
        return value == 0 ? 30 : min(max(value, 10), 120)
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

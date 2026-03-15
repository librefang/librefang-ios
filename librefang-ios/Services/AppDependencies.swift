import SwiftUI

// MARK: - Dependency Container

@MainActor
@Observable
final class AppDependencies {
    let apiClient: APIClientProtocol
    let dashboardViewModel: DashboardViewModel
    let networkMonitor: NetworkMonitor
    let incidentStateStore: IncidentStateStore
    let agentWatchlistStore: AgentWatchlistStore
    let watchedAgentDiagnosticsStore: WatchedAgentDiagnosticsStore
    let appShortcutLaunchStore: AppShortcutLaunchStore
    let onCallFocusStore: OnCallFocusStore
    let onCallNotificationManager: OnCallNotificationManager
    let onCallHandoffStore: OnCallHandoffStore

    init(apiClient: APIClientProtocol? = nil) {
        let client = apiClient ?? APIClient(config: .saved)
        self.apiClient = client
        self.dashboardViewModel = DashboardViewModel(api: client)
        self.networkMonitor = NetworkMonitor()
        self.incidentStateStore = IncidentStateStore()
        self.agentWatchlistStore = AgentWatchlistStore()
        self.watchedAgentDiagnosticsStore = WatchedAgentDiagnosticsStore()
        self.appShortcutLaunchStore = AppShortcutLaunchStore()
        self.onCallFocusStore = OnCallFocusStore()
        self.onCallNotificationManager = OnCallNotificationManager()
        self.onCallHandoffStore = OnCallHandoffStore()
        self.networkMonitor.start()
    }

    func makeChatViewModel(for agent: Agent) -> ChatViewModel {
        ChatViewModel(agent: agent, api: apiClient)
    }
}

// MARK: - Environment Key

private struct AppDependenciesKey: EnvironmentKey {
    @MainActor static let defaultValue = AppDependencies()
}

extension EnvironmentValues {
    var dependencies: AppDependencies {
        get { self[AppDependenciesKey.self] }
        set { self[AppDependenciesKey.self] = newValue }
    }
}

import Foundation

@Observable
final class DashboardViewModel {
    var agents: [Agent] = []
    var budget: BudgetOverview?
    var budgetAgents: AgentBudgetRanking?
    var a2aAgents: A2AAgentList?
    var health: HealthStatus?
    var isLoading = false
    var error: String?
    var lastRefresh: Date?

    private let api: APIClientProtocol
    private var refreshTask: Task<Void, Never>?

    init(api: APIClientProtocol) {
        self.api = api
    }

    // MARK: - Auto Refresh

    func startAutoRefresh(interval: TimeInterval = 30) {
        stopAutoRefresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Manual Refresh

    @MainActor
    func refresh() async {
        isLoading = true
        error = nil

        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                do { self.health = try await self.api.health() }
                catch { self.error = self.error ?? error.localizedDescription }
            }
            group.addTask { @MainActor in
                do { self.agents = try await self.api.agents() }
                catch { self.error = self.error ?? error.localizedDescription }
            }
            group.addTask { @MainActor in
                do { self.budget = try await self.api.budget() }
                catch { self.error = self.error ?? error.localizedDescription }
            }
            group.addTask { @MainActor in
                do { self.budgetAgents = try await self.api.budgetAgents() }
                catch { self.error = self.error ?? error.localizedDescription }
            }
            group.addTask { @MainActor in
                do { self.a2aAgents = try await self.api.a2aAgents() }
                catch { /* A2A is optional, don't set error */ }
            }
        }

        lastRefresh = Date()
        isLoading = false
    }

    @MainActor
    func updateServer(_ config: ServerConfig) async {
        config.save()
        await api.updateConfig(config)
        await refresh()
    }

    // MARK: - Computed

    var runningCount: Int { agents.filter(\.isRunning).count }
    var totalCount: Int { agents.count }
    var isConnected: Bool { health?.isHealthy == true }
}

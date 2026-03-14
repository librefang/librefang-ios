import Foundation

@Observable
final class DashboardViewModel {
    var agents: [Agent] = []
    var budget: BudgetOverview?
    var budgetAgents: AgentBudgetRanking?
    var a2aAgents: A2AAgentList?
    var health: HealthStatus?
    var status: SystemStatus?
    var usageSummary: UsageSummary?
    var usageByModel: [ModelUsage] = []
    var usageDaily: [DailyUsage] = []
    var usageTodayCost = 0.0
    var firstUsageEventDate: String?
    var providers: [ProviderStatus] = []
    var channels: [ChannelStatus] = []
    var hands: [HandDefinition] = []
    var activeHands: [HandInstance] = []
    var approvals: [ApprovalItem] = []
    var sessions: [SessionInfo] = []
    var recentAudit: [AuditEntry] = []
    var auditVerify: AuditVerifyStatus?
    var security: SecurityStatus?
    var mcpConfiguredServers: [MCPConfiguredServer] = []
    var mcpConnectedServers: [MCPConnectedServer] = []
    var tools: [ToolInfo] = []
    var networkStatus: NetworkStatus?
    var peers: [PeerStatus] = []
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
                do { self.status = try await self.api.status() }
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
            group.addTask { @MainActor in
                do { self.usageSummary = try await self.api.usageSummary() }
                catch { /* Usage summary is optional */ }
            }
            group.addTask { @MainActor in
                do { self.usageByModel = (try await self.api.usageByModel()).models }
                catch { /* Model breakdown is optional */ }
            }
            group.addTask { @MainActor in
                do {
                    let daily = try await self.api.usageDaily()
                    self.usageDaily = daily.days
                    self.usageTodayCost = daily.todayCostUsd
                    self.firstUsageEventDate = daily.firstEventDate
                } catch {
                    /* Daily usage trend is optional */
                }
            }
            group.addTask { @MainActor in
                do { self.providers = (try await self.api.providers()).providers }
                catch { /* Provider probes are optional for mobile */ }
            }
            group.addTask { @MainActor in
                do { self.channels = (try await self.api.channels()).channels }
                catch { /* Channel inventory is optional */ }
            }
            group.addTask { @MainActor in
                do { self.hands = (try await self.api.hands()).hands }
                catch { /* Hands are optional */ }
            }
            group.addTask { @MainActor in
                do { self.activeHands = (try await self.api.activeHands()).instances }
                catch { /* Active hands are optional */ }
            }
            group.addTask { @MainActor in
                do { self.approvals = (try await self.api.approvals()).approvals }
                catch { /* Approval queue is optional */ }
            }
            group.addTask { @MainActor in
                do { self.sessions = (try await self.api.sessions()).sessions }
                catch { /* Session inventory is optional */ }
            }
            group.addTask { @MainActor in
                do { self.recentAudit = (try await self.api.recentAudit(limit: 8)).entries }
                catch { /* Audit feed is optional */ }
            }
            group.addTask { @MainActor in
                do { self.auditVerify = try await self.api.auditVerify() }
                catch { /* Audit verification is optional */ }
            }
            group.addTask { @MainActor in
                do { self.security = try await self.api.security() }
                catch { /* Security summary is optional */ }
            }
            group.addTask { @MainActor in
                do {
                    let mcp = try await self.api.mcpServers()
                    self.mcpConfiguredServers = mcp.configured
                    self.mcpConnectedServers = mcp.connected
                } catch {
                    /* MCP inventory is optional */
                }
            }
            group.addTask { @MainActor in
                do { self.tools = (try await self.api.tools()).tools }
                catch { /* Tool inventory is optional */ }
            }
            group.addTask { @MainActor in
                do { self.networkStatus = try await self.api.networkStatus() }
                catch { /* Peer network is optional */ }
            }
            group.addTask { @MainActor in
                do { self.peers = (try await self.api.peers()).peers }
                catch { /* Peer inventory is optional */ }
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
    var configuredProviderCount: Int { providers.filter(\.isConfigured).count }
    var reachableLocalProviderCount: Int {
        providers.filter { ($0.isLocal ?? false) && ($0.reachable ?? false) }.count
    }
    var configuredChannelCount: Int { channels.filter(\.configured).count }
    var readyChannelCount: Int { channels.filter { $0.configured && $0.hasToken }.count }
    var activeHandCount: Int { activeHands.count }
    var degradedHandCount: Int { hands.filter(\.degraded).count }
    var pendingApprovalCount: Int { approvals.count }
    var securityFeatureCount: Int { security?.totalFeatures ?? 0 }
    var totalTokenCount: Int {
        (usageSummary?.totalInputTokens ?? 0) + (usageSummary?.totalOutputTokens ?? 0)
    }
    var highestModelCost: Double {
        usageByModel.map(\.totalCostUsd).max() ?? 0
    }
    var connectedPeerCount: Int { networkStatus?.connectedPeers ?? 0 }
    var totalPeerCount: Int { networkStatus?.totalPeers ?? peers.count }
    var totalSessionCount: Int { sessions.count }
    var totalSessionMessages: Int { sessions.reduce(0) { $0 + $1.messageCount } }
    var connectedMCPServerCount: Int { mcpConnectedServers.count }
    var configuredMCPServerCount: Int { mcpConfiguredServers.count }
    var mcpToolCount: Int { mcpConnectedServers.reduce(0) { $0 + $1.toolsCount } }
    var totalToolCount: Int { tools.count }
}

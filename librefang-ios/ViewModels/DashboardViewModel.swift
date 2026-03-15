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
    var catalogModels: [CatalogModel] = []
    var modelAliases: [ModelAliasEntry] = []
    var catalogStatus: CatalogStatusResponse?
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
    var workflows: [WorkflowSummary] = []
    var workflowRuns: [WorkflowRun] = []
    var triggers: [TriggerDefinition] = []
    var schedules: [ScheduleEntry] = []
    var cronJobs: [CronJob] = []
    var healthDetail: HealthDetail?
    var versionInfo: BuildVersionInfo?
    var configSummary: RuntimeConfigSummary?
    var metricsRawText: String?
    var isLoading = false
    var error: String?
    var lastRefresh: Date?

    private let api: APIClientProtocol
    private var refreshTask: Task<Void, Never>?
    private var isRefreshInFlight = false

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
        guard !isRefreshInFlight else { return }

        isRefreshInFlight = true
        isLoading = true
        error = nil
        defer {
            lastRefresh = Date()
            isLoading = false
            isRefreshInFlight = false
        }

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
                do { self.catalogModels = (try await self.api.models()).models }
                catch { /* Model catalog is optional */ }
            }
            group.addTask { @MainActor in
                do { self.modelAliases = (try await self.api.modelAliases()).aliases }
                catch { /* Alias inventory is optional */ }
            }
            group.addTask { @MainActor in
                do { self.catalogStatus = try await self.api.catalogStatus() }
                catch { /* Catalog sync status is optional */ }
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
            group.addTask { @MainActor in
                do { self.healthDetail = try await self.api.healthDetail() }
                catch { /* Deep health diagnostics are optional */ }
            }
            group.addTask { @MainActor in
                do { self.versionInfo = try await self.api.versionInfo() }
                catch { /* Build metadata is optional */ }
            }
            group.addTask { @MainActor in
                do { self.configSummary = try await self.api.configSummary() }
                catch { /* Config summary is optional */ }
            }
            group.addTask { @MainActor in
                do { self.metricsRawText = try await self.api.metricsText() }
                catch { /* Prometheus metrics are optional */ }
            }
            group.addTask { @MainActor in
                do {
                    let workflows = try await self.api.workflows()
                    self.workflows = workflows

                    if let sampleWorkflow = workflows.first {
                        do {
                            self.workflowRuns = try await self.api.workflowRuns(workflowID: sampleWorkflow.id)
                        } catch {
                            self.workflowRuns = []
                        }
                    } else {
                        self.workflowRuns = []
                    }
                } catch {
                    /* Workflow inventory is optional */
                }
            }
            group.addTask { @MainActor in
                do { self.triggers = try await self.api.triggers() }
                catch { /* Event triggers are optional */ }
            }
            group.addTask { @MainActor in
                do { self.schedules = (try await self.api.schedules()).schedules }
                catch { /* Schedule inventory is optional */ }
            }
            group.addTask { @MainActor in
                do { self.cronJobs = (try await self.api.cronJobs()).jobs }
                catch { /* Cron inventory is optional */ }
            }
        }
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
    var localProviderCount: Int { providers.filter { $0.isLocal == true }.count }
    var unreachableLocalProviderCount: Int { providers.filter { $0.isLocal == true && $0.reachable == false }.count }
    var providerErrorCount: Int { providers.filter { ($0.error ?? "").isEmpty == false }.count }
    var reachableLocalProviderCount: Int {
        providers.filter { ($0.isLocal ?? false) && ($0.reachable ?? false) }.count
    }
    var configuredChannelCount: Int { channels.filter(\.configured).count }
    var channelCredentialGapCount: Int { channels.filter { $0.configured && !$0.hasToken }.count }
    var readyChannelCount: Int { channels.filter { $0.configured && $0.hasToken }.count }
    var availableCatalogModelCount: Int { catalogModels.filter(\.available).count }
    var unavailableCatalogModelCount: Int { catalogModels.filter { !$0.available }.count }
    var modelAliasCount: Int { modelAliases.count }
    var catalogLastSyncDate: Date? {
        guard let raw = catalogStatus?.lastSync, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: raw)
    }
    var isCatalogSyncStale: Bool {
        guard let catalogLastSyncDate else { return false }
        return Date().timeIntervalSince(catalogLastSyncDate) > 60 * 60 * 48
    }
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
    var workflowCount: Int { workflows.count }
    var recentWorkflowRunCount: Int { workflowRuns.count }
    var failedWorkflowRunCount: Int { workflowRuns.filter { $0.state == .failed }.count }
    var runningWorkflowRunCount: Int { workflowRuns.filter { $0.state == .running }.count }
    var enabledTriggerCount: Int { triggers.filter(\.enabled).count }
    var exhaustedTriggerCount: Int { triggers.filter(\.isExhausted).count }
    var pausedScheduleCount: Int { schedules.filter { !$0.enabled }.count }
    var enabledScheduleCount: Int { schedules.filter(\.enabled).count }
    var pausedCronJobCount: Int { cronJobs.filter { !$0.enabled }.count }
    var enabledCronJobCount: Int { cronJobs.filter(\.enabled).count }
    var stalledCronJobCount: Int { cronJobs.filter { $0.enabled && $0.nextRun == nil }.count }
    var automationDefinitionCount: Int { workflows.count + triggers.count + schedules.count + cronJobs.count }
    var enabledAutomationCount: Int { enabledTriggerCount + enabledScheduleCount + enabledCronJobCount }
    var pausedAutomationCount: Int { pausedScheduleCount + pausedCronJobCount + triggers.filter { !$0.enabled }.count }
    var metricsSnapshot: PrometheusMetricsSnapshot? {
        guard let metricsRawText, !metricsRawText.isEmpty else { return nil }
        return PrometheusMetricsSnapshot.parse(metricsRawText)
    }
    var diagnosticsConfigWarningCount: Int { healthDetail?.configWarnings.count ?? 0 }
    var supervisorRestartCount: Int { healthDetail?.restartCount ?? metricsSnapshot?.restartCount ?? 0 }
    var supervisorPanicCount: Int { healthDetail?.panicCount ?? metricsSnapshot?.panicCount ?? 0 }
    var diagnosticsIssueCount: Int {
        (hasHealthDatabaseIssue ? 1 : 0)
            + (diagnosticsConfigWarningCount > 0 ? 1 : 0)
            + ((supervisorRestartCount + supervisorPanicCount) > 0 ? 1 : 0)
    }
    var hasHealthDatabaseIssue: Bool {
        guard let database = healthDetail?.database else { return false }
        return database.lowercased() != "connected"
    }
}

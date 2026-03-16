import SwiftUI

enum AutomationMonitorScope: String, CaseIterable, Identifiable {
    case all
    case attention
    case active

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            String(localized: "All")
        case .attention:
            String(localized: "Attention")
        case .active:
            String(localized: "Active")
        }
    }
}

private enum AutomationSectionAnchor: Hashable {
    case workflows
    case runs
    case triggers
    case schedules
    case cron
}

struct AutomationView: View {
    @Environment(\.dependencies) private var deps
    @State private var searchText = ""
    @State private var scope: AutomationMonitorScope = .all

    private var vm: DashboardViewModel { deps.dashboardViewModel }
    private var visibleWorkflows: [WorkflowSummary] { Array(filteredWorkflows.prefix(8)) }
    private var visibleWorkflowRuns: [WorkflowRun] { Array(filteredWorkflowRuns.prefix(8)) }
    private var visibleTriggers: [TriggerDefinition] { Array(filteredTriggers.prefix(8)) }
    private var visibleSchedules: [ScheduleEntry] { Array(filteredSchedules.prefix(8)) }
    private var visibleCronJobs: [CronJob] { Array(filteredCronJobs.prefix(8)) }

    private var hasAutomationData: Bool {
        vm.automationDefinitionCount > 0 || !vm.workflowRuns.isEmpty
    }

    private var filteredWorkflows: [WorkflowSummary] {
        vm.workflows
            .filter { workflow in
                matchesSearch(
                    searchText,
                    values: [workflow.name, workflow.description]
                ) && workflowMatchesScope(workflow)
            }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var filteredWorkflowRuns: [WorkflowRun] {
        vm.workflowRuns
            .filter { run in
                matchesSearch(searchText, values: [run.workflowName, run.state.rawValue]) && workflowRunMatchesScope(run)
            }
            .sorted { lhs, rhs in
                (lhs.startedAt.automationISO8601Date ?? .distantPast) > (rhs.startedAt.automationISO8601Date ?? .distantPast)
            }
    }

    private var filteredTriggers: [TriggerDefinition] {
        vm.triggers
            .filter { trigger in
                matchesSearch(
                    searchText,
                    values: [
                        trigger.patternSummary,
                        trigger.promptTemplate,
                        trigger.agentId,
                        agentName(for: trigger.agentId) ?? ""
                    ]
                ) && triggerMatchesScope(trigger)
            }
            .sorted { lhs, rhs in
                if lhs.isExhausted != rhs.isExhausted {
                    return lhs.isExhausted && !rhs.isExhausted
                }
                if lhs.enabled != rhs.enabled {
                    return lhs.enabled && !rhs.enabled
                }
                return lhs.patternSummary.localizedCompare(rhs.patternSummary) == .orderedAscending
            }
    }

    private var filteredSchedules: [ScheduleEntry] {
        vm.schedules
            .filter { schedule in
                matchesSearch(
                    searchText,
                    values: [schedule.name, schedule.cron, schedule.message, schedule.agentId, agentName(for: schedule.agentId) ?? ""]
                ) && scheduleMatchesScope(schedule)
            }
            .sorted { lhs, rhs in
                if lhs.enabled != rhs.enabled {
                    return lhs.enabled && !rhs.enabled
                }
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
    }

    private var filteredCronJobs: [CronJob] {
        vm.cronJobs
            .filter { job in
                matchesSearch(
                    searchText,
                    values: [
                        job.name,
                        cronScheduleSummary(job.schedule),
                        cronActionSummary(job.action),
                        cronDeliverySummary(job.delivery),
                        job.agentId,
                        agentName(for: job.agentId) ?? ""
                    ]
                ) && cronJobMatchesScope(job)
            }
            .sorted { lhs, rhs in
                if cronJobNeedsAttention(lhs) != cronJobNeedsAttention(rhs) {
                    return cronJobNeedsAttention(lhs) && !cronJobNeedsAttention(rhs)
                }
                if lhs.enabled != rhs.enabled {
                    return lhs.enabled && !rhs.enabled
                }
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
    }

    private var automationSnapshotSummary: String {
        if vm.failedWorkflowRunCount > 0 || vm.exhaustedTriggerCount > 0 || vm.stalledCronJobCount > 0 {
            return String(localized: "Automation pressure is already visible from failed runs, exhausted triggers, or stalled cron jobs.")
        }
        return String(localized: "Automation monitor keeps workflows, runs, triggers, schedules, and cron jobs grouped on one mobile page.")
    }
    private var automationJumpCount: Int {
        [
            !filteredWorkflows.isEmpty,
            !filteredWorkflowRuns.isEmpty,
            !filteredTriggers.isEmpty,
            !filteredSchedules.isEmpty,
            !filteredCronJobs.isEmpty
        ]
        .filter { $0 }
        .count
    }
    private var automationSectionCount: Int {
        [
            !filteredWorkflows.isEmpty,
            !filteredWorkflowRuns.isEmpty,
            !filteredTriggers.isEmpty,
            !filteredSchedules.isEmpty,
            !filteredCronJobs.isEmpty
        ]
        .filter { $0 }
        .count
    }

    init(initialSearchText: String = "", initialScope: AutomationMonitorScope = .all) {
        _searchText = State(initialValue: initialSearchText)
        _scope = State(initialValue: initialScope)
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if let error = vm.error, !hasAutomationData {
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
                    AutomationScoreboard(vm: vm)
                        .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
                }

                Section {
                    AutomationStatusDeckCard(
                        vm: vm,
                        scope: scope,
                        searchText: searchText,
                        visibleItemCount: visibleItemCount,
                        automationSnapshotSummary: automationSnapshotSummary
                    )
                    AutomationSectionInventoryDeck(
                        sectionCount: automationSectionCount,
                        visibleItemCount: visibleItemCount,
                        workflowCount: filteredWorkflows.count,
                        runCount: filteredWorkflowRuns.count,
                        triggerCount: filteredTriggers.count,
                        scheduleCount: filteredSchedules.count,
                        cronCount: filteredCronJobs.count,
                        failedRunCount: vm.failedWorkflowRunCount,
                        exhaustedTriggerCount: vm.exhaustedTriggerCount,
                        stalledCronCount: vm.stalledCronJobCount
                    )
                    AutomationPressureCoverageDeck(
                        failedRunCount: vm.failedWorkflowRunCount,
                        exhaustedTriggerCount: vm.exhaustedTriggerCount,
                        stalledCronCount: vm.stalledCronJobCount,
                        workflowCount: filteredWorkflows.count,
                        triggerCount: filteredTriggers.count,
                        cronCount: filteredCronJobs.count,
                        visibleItemCount: visibleItemCount
                    )
                    AutomationSupportCoverageDeck(
                        visibleItemCount: visibleItemCount,
                        workflowCount: filteredWorkflows.count,
                        triggerCount: filteredTriggers.count,
                        scheduleCount: filteredSchedules.count,
                        cronCount: filteredCronJobs.count,
                        jumpCount: automationJumpCount,
                        scopeLabel: scope.label,
                        hasSearchScope: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    AutomationActionReadinessDeck(
                        primaryRouteCount: 4,
                        supportRouteCount: 1,
                        jumpCount: automationJumpCount,
                        visibleItemCount: visibleItemCount,
                        workflowCount: filteredWorkflows.count,
                        runCount: filteredWorkflowRuns.count,
                        failedRunCount: vm.failedWorkflowRunCount,
                        scopeLabel: scope.label,
                        hasSearchScope: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    AutomationFocusCoverageDeck(
                        visibleItemCount: visibleItemCount,
                        workflowCount: filteredWorkflows.count,
                        runCount: filteredWorkflowRuns.count,
                        triggerCount: filteredTriggers.count,
                        scheduleCount: filteredSchedules.count,
                        cronCount: filteredCronJobs.count,
                        failedRunCount: vm.failedWorkflowRunCount,
                        exhaustedTriggerCount: vm.exhaustedTriggerCount,
                        stalledCronCount: vm.stalledCronJobCount,
                        scopeLabel: scope.label,
                        hasSearchScope: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    AutomationRouteInventoryDeck(
                        primaryRouteCount: 4,
                        supportRouteCount: 1,
                        jumpCount: automationJumpCount,
                        failedRunCount: vm.failedWorkflowRunCount,
                        stalledCronCount: vm.stalledCronJobCount,
                        visibleItemCount: visibleItemCount
                    )

                    MonitoringSurfaceGroupCard(
                        title: String(localized: "Routes"),
                        detail: String(localized: "Keep the next automation exits compact and visible above the grouped workflow lists.")
                    ) {
                        MonitoringShortcutRail(
                            title: String(localized: "Primary"),
                            detail: String(localized: "Use these routes first when workflow or scheduler pressure needs broader context.")
                        ) {
                            NavigationLink {
                                RuntimeView()
                            } label: {
                                MonitoringSurfaceShortcutChip(
                                    title: String(localized: "Runtime"),
                                    systemImage: "server.rack",
                                    tone: vm.automationPressureIssueCategoryCount > 0 ? .warning : .neutral,
                                    badgeText: vm.automationPressureIssueCategoryCount > 0
                                        ? (vm.automationPressureIssueCategoryCount == 1 ? String(localized: "1 issue") : String(localized: "\(vm.automationPressureIssueCategoryCount) issues"))
                                        : nil
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                IncidentsView()
                            } label: {
                                MonitoringSurfaceShortcutChip(
                                    title: String(localized: "Incidents"),
                                    systemImage: "bell.badge",
                                    tone: vm.automationPressureIssueCategoryCount > 0 ? .warning : .neutral,
                                    badgeText: vm.failedWorkflowRunCount > 0
                                        ? (vm.failedWorkflowRunCount == 1 ? String(localized: "1 failed run") : String(localized: "\(vm.failedWorkflowRunCount) failed runs"))
                                        : nil
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                DiagnosticsView()
                            } label: {
                                MonitoringSurfaceShortcutChip(
                                    title: String(localized: "Diagnostics"),
                                    systemImage: "stethoscope",
                                    tone: vm.diagnosticsSummaryTone,
                                    badgeText: vm.diagnosticsConfigWarningCount > 0
                                        ? (vm.diagnosticsConfigWarningCount == 1 ? String(localized: "1 warning") : String(localized: "\(vm.diagnosticsConfigWarningCount) warnings"))
                                        : nil
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                EventsView(api: deps.apiClient, initialScope: .critical)
                            } label: {
                                MonitoringSurfaceShortcutChip(
                                    title: String(localized: "Events"),
                                    systemImage: "text.justify.leading",
                                    tone: vm.recentCriticalAuditCount > 0 ? .critical : .neutral,
                                    badgeText: vm.recentCriticalAuditCount > 0
                                        ? (vm.recentCriticalAuditCount == 1 ? String(localized: "1 critical") : String(localized: "\(vm.recentCriticalAuditCount) critical"))
                                        : nil
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        MonitoringShortcutRail(
                            title: String(localized: "Support"),
                            detail: String(localized: "Keep integration context behind the primary automation exits.")
                        ) {
                            NavigationLink {
                                IntegrationsView(initialScope: .attention)
                            } label: {
                                MonitoringSurfaceShortcutChip(
                                    title: String(localized: "Integrations"),
                                    systemImage: "square.3.layers.3d.down.forward",
                                    tone: vm.integrationPressureIssueCategoryCount > 0 ? .critical : .neutral,
                                    badgeText: vm.integrationPressureIssueCategoryCount > 0
                                        ? (vm.integrationPressureIssueCategoryCount == 1 ? String(localized: "1 issue") : String(localized: "\(vm.integrationPressureIssueCategoryCount) issues"))
                                        : nil
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    AutomationFilterCard(
                        scope: $scope,
                        searchText: searchText,
                        visibleCount: visibleItemCount,
                        totalCount: totalItemCount
                    )
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Keep status, routes, and filters together before the grouped workflow sections.")
                }

                if hasAutomationData {
                    Section {
                        automationFocusSection(proxy)
                    } header: {
                        Text("Jumps")
                    } footer: {
                        Text("Use these jumps to move through the automation monitor without a long iPhone scroll.")
                    }
                }

                if !hasAutomationData && !vm.isLoading {
                    Section("Automation") {
                        ContentUnavailableView(
                            "No Automation Inventory",
                            systemImage: "flowchart",
                            description: Text("LibreFang has no workflows, triggers, schedules, or cron jobs in the current snapshot.")
                        )
                    }
                } else {
                    if filteredWorkflows.isEmpty
                        && filteredWorkflowRuns.isEmpty
                        && filteredTriggers.isEmpty
                        && filteredSchedules.isEmpty
                        && filteredCronJobs.isEmpty
                        && !vm.isLoading {
                        Section("Automation") {
                            ContentUnavailableView(
                                searchText.isEmpty
                                    ? String(localized: "No Matching Automation")
                                    : String(localized: "No Search Results"),
                                systemImage: scope == .all ? "flowchart" : "line.3.horizontal.decrease.circle",
                                description: Text(
                                    searchText.isEmpty
                                        ? String(localized: "Widen the scope or wait for the next dashboard refresh.")
                                        : String(localized: "Try a different workflow, trigger, or agent query.")
                                )
                            )
                        }
                    } else {
                        workflowsSection
                        workflowRunsSection
                        triggersSection
                        schedulesSection
                        cronJobsSection
                    }
                }
            }
            .navigationTitle("Automation")
            .searchable(text: $searchText, prompt: "Search workflow, trigger, or job")
            .refreshable {
                await vm.refresh()
            }
            .overlay {
                if vm.isLoading && !hasAutomationData {
                    ProgressView("Loading automation...")
                }
            }
            .task {
                if !hasAutomationData {
                    await vm.refresh()
                }
            }
        }
    }

    @ViewBuilder
    private func automationFocusSection(_ proxy: ScrollViewProxy) -> some View {
        Button {
            jump(proxy, to: .workflows)
        } label: {
            MonitoringJumpRow(
                title: String(localized: "Workflow Definitions"),
                detail: filteredWorkflows.isEmpty
                    ? String(localized: "No workflows are visible in the current automation scope.")
                    : String(localized: "Jump to workflow definitions before digging into recent runs."),
                systemImage: "flowchart",
                tone: vm.failedWorkflowRunCount > 0 ? .warning : .neutral,
                badgeText: filteredWorkflows.isEmpty ? String(localized: "Empty") : String(localized: "\(filteredWorkflows.count) visible"),
                badgeTone: .neutral
            )
        }
        .buttonStyle(.plain)
        .disabled(filteredWorkflows.isEmpty)

        Button {
            jump(proxy, to: .runs)
        } label: {
            MonitoringJumpRow(
                title: String(localized: "Recent Runs"),
                detail: filteredWorkflowRuns.isEmpty
                    ? String(localized: "No recent workflow runs are visible in the current automation scope.")
                    : String(localized: "Jump to recent workflow executions and their current run state."),
                systemImage: "play.rectangle.on.rectangle",
                tone: vm.failedWorkflowRunCount > 0 ? .critical : .neutral,
                badgeText: filteredWorkflowRuns.isEmpty ? String(localized: "Empty") : String(localized: "\(filteredWorkflowRuns.count) visible"),
                badgeTone: vm.failedWorkflowRunCount > 0 ? .critical : .neutral
            )
        }
        .buttonStyle(.plain)
        .disabled(filteredWorkflowRuns.isEmpty)

        Button {
            jump(proxy, to: .triggers)
        } label: {
            MonitoringJumpRow(
                title: String(localized: "Triggers"),
                detail: filteredTriggers.isEmpty
                    ? String(localized: "No triggers are visible in the current automation scope.")
                    : String(localized: "Jump to trigger exhaustion, enablement, and agent targeting."),
                systemImage: "bolt.horizontal.circle",
                tone: vm.exhaustedTriggerCount > 0 ? .warning : .neutral,
                badgeText: filteredTriggers.isEmpty ? String(localized: "Empty") : String(localized: "\(filteredTriggers.count) visible"),
                badgeTone: vm.exhaustedTriggerCount > 0 ? .warning : .neutral
            )
        }
        .buttonStyle(.plain)
        .disabled(filteredTriggers.isEmpty)

        Button {
            jump(proxy, to: .schedules)
        } label: {
            MonitoringJumpRow(
                title: String(localized: "Schedules"),
                detail: filteredSchedules.isEmpty
                    ? String(localized: "No schedules are visible in the current automation scope.")
                    : String(localized: "Jump to enabled and paused schedules without scanning the full page."),
                systemImage: "calendar",
                tone: vm.pausedScheduleCount > 0 ? .warning : .neutral,
                badgeText: filteredSchedules.isEmpty ? String(localized: "Empty") : String(localized: "\(filteredSchedules.count) visible"),
                badgeTone: vm.pausedScheduleCount > 0 ? .warning : .neutral
            )
        }
        .buttonStyle(.plain)
        .disabled(filteredSchedules.isEmpty)

        Button {
            jump(proxy, to: .cron)
        } label: {
            MonitoringJumpRow(
                title: String(localized: "Cron Jobs"),
                detail: filteredCronJobs.isEmpty
                    ? String(localized: "No cron jobs are visible in the current automation scope.")
                    : String(localized: "Jump to cron timing, delivery targets, and missing next-run state."),
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                tone: vm.stalledCronJobCount > 0 ? .warning : .neutral,
                badgeText: filteredCronJobs.isEmpty ? String(localized: "Empty") : String(localized: "\(filteredCronJobs.count) visible"),
                badgeTone: vm.stalledCronJobCount > 0 ? .warning : .neutral
            )
        }
        .buttonStyle(.plain)
        .disabled(filteredCronJobs.isEmpty)
    }

    private func jump(_ proxy: ScrollViewProxy, to anchor: AutomationSectionAnchor) {
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    @ViewBuilder
    private var workflowsSection: some View {
        if !filteredWorkflows.isEmpty {
            Section {
                AutomationWorkflowsSnapshotCard(
                    workflows: filteredWorkflows,
                    visibleCount: visibleWorkflows.count,
                    failedWorkflowNames: Set(vm.workflowRuns.filter { $0.state == .failed }.map(\.workflowName)),
                    runningWorkflowNames: Set(vm.workflowRuns.filter { $0.state == .running || $0.state == .pending }.map(\.workflowName))
                )

                ForEach(visibleWorkflows) { workflow in
                    WorkflowDefinitionRow(
                        workflow: workflow,
                        failedRuns: vm.workflowRuns.filter { $0.workflowName == workflow.name && $0.state == .failed }.count,
                        runningRuns: vm.workflowRuns.filter { $0.workflowName == workflow.name && $0.state == .running }.count
                    )
                }
            } header: {
                Text("Workflows")
            } footer: {
                if filteredWorkflows.count > visibleWorkflows.count {
                    Text("Showing \(visibleWorkflows.count) of \(filteredWorkflows.count) workflows")
                } else {
                    Text("\(vm.workflowCount) definitions, \(vm.recentWorkflowRunCount) recent runs cached from the server")
                }
            }
            .id(AutomationSectionAnchor.workflows)
        }
    }

    @ViewBuilder
    private var workflowRunsSection: some View {
        if !filteredWorkflowRuns.isEmpty {
            Section {
                AutomationWorkflowRunsSnapshotCard(
                    runs: filteredWorkflowRuns,
                    visibleCount: visibleWorkflowRuns.count
                )

                ForEach(visibleWorkflowRuns) { run in
                    WorkflowRunRow(run: run)
                }
            } header: {
                Text("Recent Runs")
            } footer: {
                if filteredWorkflowRuns.count > visibleWorkflowRuns.count {
                    Text("Showing \(visibleWorkflowRuns.count) of \(filteredWorkflowRuns.count) recent runs")
                } else {
                    Text("\(vm.failedWorkflowRunCount) failed, \(vm.runningWorkflowRunCount) still running")
                }
            }
            .id(AutomationSectionAnchor.runs)
        }
    }

    @ViewBuilder
    private var triggersSection: some View {
        if !filteredTriggers.isEmpty {
            Section {
                AutomationTriggersSnapshotCard(
                    triggers: filteredTriggers,
                    visibleCount: visibleTriggers.count
                )

                ForEach(visibleTriggers) { trigger in
                    TriggerRow(trigger: trigger, agentName: agentName(for: trigger.agentId))
                }
            } header: {
                Text("Triggers")
            } footer: {
                if filteredTriggers.count > visibleTriggers.count {
                    Text("Showing \(visibleTriggers.count) of \(filteredTriggers.count) triggers")
                } else {
                    Text("\(vm.enabledTriggerCount) enabled, \(vm.exhaustedTriggerCount) exhausted")
                }
            }
            .id(AutomationSectionAnchor.triggers)
        }
    }

    @ViewBuilder
    private var schedulesSection: some View {
        if !filteredSchedules.isEmpty {
            Section {
                AutomationSchedulesSnapshotCard(
                    schedules: filteredSchedules,
                    visibleCount: visibleSchedules.count
                )

                ForEach(visibleSchedules) { schedule in
                    ScheduleRow(schedule: schedule, agentName: agentName(for: schedule.agentId))
                }
            } header: {
                Text("Schedules")
            } footer: {
                if filteredSchedules.count > visibleSchedules.count {
                    Text("Showing \(visibleSchedules.count) of \(filteredSchedules.count) schedules")
                } else {
                    Text("\(vm.enabledScheduleCount) enabled, \(vm.pausedScheduleCount) paused")
                }
            }
            .id(AutomationSectionAnchor.schedules)
        }
    }

    @ViewBuilder
    private var cronJobsSection: some View {
        if !filteredCronJobs.isEmpty {
            Section {
                AutomationCronJobsSnapshotCard(
                    jobs: filteredCronJobs,
                    visibleCount: visibleCronJobs.count
                )

                ForEach(visibleCronJobs) { job in
                    CronJobRow(
                        job: job,
                        agentName: agentName(for: job.agentId),
                        scheduleSummary: cronScheduleSummary(job.schedule),
                        actionSummary: cronActionSummary(job.action),
                        deliverySummary: cronDeliverySummary(job.delivery)
                    )
                }
            } header: {
                Text("Cron Jobs")
            } footer: {
                if filteredCronJobs.count > visibleCronJobs.count {
                    Text("Showing \(visibleCronJobs.count) of \(filteredCronJobs.count) cron jobs")
                } else {
                    Text("\(vm.enabledCronJobCount) enabled, \(vm.pausedCronJobCount) paused, \(vm.stalledCronJobCount) missing next run")
                }
            }
            .id(AutomationSectionAnchor.cron)
        }
    }

    private var totalItemCount: Int {
        vm.workflows.count + vm.workflowRuns.count + vm.triggers.count + vm.schedules.count + vm.cronJobs.count
    }

    private var visibleItemCount: Int {
        filteredWorkflows.count + filteredWorkflowRuns.count + filteredTriggers.count + filteredSchedules.count + filteredCronJobs.count
    }

    private func workflowMatchesScope(_ workflow: WorkflowSummary) -> Bool {
        switch scope {
        case .all:
            return true
        case .attention:
            return vm.workflowRuns.contains { $0.workflowName == workflow.name && $0.state == .failed }
        case .active:
            return vm.workflowRuns.contains { $0.workflowName == workflow.name && ($0.state == .running || $0.state == .pending) }
                || !vm.workflowRuns.contains { $0.workflowName == workflow.name }
        }
    }

    private func workflowRunMatchesScope(_ run: WorkflowRun) -> Bool {
        switch scope {
        case .all:
            return true
        case .attention:
            return run.state == .failed
        case .active:
            return run.state == .running || run.state == .pending
        }
    }

    private func triggerMatchesScope(_ trigger: TriggerDefinition) -> Bool {
        switch scope {
        case .all:
            return true
        case .attention:
            return trigger.isExhausted || !trigger.enabled
        case .active:
            return trigger.enabled
        }
    }

    private func scheduleMatchesScope(_ schedule: ScheduleEntry) -> Bool {
        switch scope {
        case .all:
            return true
        case .attention:
            return !schedule.enabled
        case .active:
            return schedule.enabled
        }
    }

    private func cronJobMatchesScope(_ job: CronJob) -> Bool {
        switch scope {
        case .all:
            return true
        case .attention:
            return cronJobNeedsAttention(job)
        case .active:
            return job.enabled
        }
    }

    private func cronJobNeedsAttention(_ job: CronJob) -> Bool {
        !job.enabled || (job.enabled && job.nextRun == nil)
    }

    private func agentName(for agentID: String) -> String? {
        deps.dashboardViewModel.agents.first(where: { $0.id == agentID })?.name
    }

    private func matchesSearch(_ query: String, values: [String]) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        let needle = normalized.lowercased()
        return values.contains { $0.lowercased().contains(needle) }
    }

    private func cronScheduleSummary(_ schedule: CronScheduleDescriptor) -> String {
        switch schedule.kind {
        case .cron:
            if let expr = schedule.expr, !expr.isEmpty {
                if let tz = schedule.tz, !tz.isEmpty {
                    return String(localized: "\(expr) · \(tz)")
                }
                return expr
            }
            return String(localized: "Cron schedule")
        case .every:
            guard let everySecs = schedule.everySecs else { return String(localized: "Recurring interval") }
            return everySecs >= 3600
                ? String(localized: "Every \(everySecs / 3600)h")
                : String(localized: "Every \(everySecs / 60)m")
        case .at:
            guard let at = schedule.at, let date = at.automationISO8601Date else {
                return schedule.at ?? String(localized: "One-shot")
            }
            return String(localized: "At \(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()))")
        }
    }

    private func cronActionSummary(_ action: CronActionDescriptor) -> String {
        switch action.kind {
        case .agentTurn:
            let summary = (action.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return summary.isEmpty ? String(localized: "Agent turn") : summary
        case .systemEvent:
            let summary = (action.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return summary.isEmpty ? String(localized: "System event") : summary
        }
    }

    private func cronDeliverySummary(_ delivery: CronDeliveryDescriptor) -> String {
        switch delivery.kind {
        case .none:
            return String(localized: "No delivery")
        case .lastChannel:
            return String(localized: "Last channel")
        case .channel:
            let channel = delivery.channel ?? String(localized: "channel")
            let to = delivery.to ?? String(localized: "recipient")
            return String(localized: "\(channel) → \(to)")
        case .webhook:
            return delivery.url ?? String(localized: "Webhook")
        }
    }
}

private struct AutomationStatusDeckCard: View {
    let vm: DashboardViewModel
    let scope: AutomationMonitorScope
    let searchText: String
    let visibleItemCount: Int
    let automationSnapshotSummary: String

    private var scopeTone: PresentationTone {
        switch scope {
        case .all:
            .neutral
        case .attention:
            .warning
        case .active:
            .positive
        }
    }

    private var hasSearchScope: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: automationSnapshotSummary,
                detail: String(localized: "Use the snapshot to judge workflow and scheduler pressure before digging into the sectioned lists.")
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: scope.label, tone: scopeTone)
                    if vm.failedWorkflowRunCount > 0 {
                        PresentationToneBadge(
                            text: vm.failedWorkflowRunCount == 1 ? String(localized: "1 failed run") : String(localized: "\(vm.failedWorkflowRunCount) failed runs"),
                            tone: .critical
                        )
                    }
                    if vm.exhaustedTriggerCount > 0 {
                        PresentationToneBadge(
                            text: vm.exhaustedTriggerCount == 1 ? String(localized: "1 exhausted trigger") : String(localized: "\(vm.exhaustedTriggerCount) exhausted triggers"),
                            tone: .warning
                        )
                    }
                    if vm.pausedScheduleCount > 0 {
                        PresentationToneBadge(
                            text: vm.pausedScheduleCount == 1 ? String(localized: "1 paused schedule") : String(localized: "\(vm.pausedScheduleCount) paused schedules"),
                            tone: .warning
                        )
                    }
                    if vm.stalledCronJobCount > 0 {
                        PresentationToneBadge(
                            text: vm.stalledCronJobCount == 1 ? String(localized: "1 stalled cron") : String(localized: "\(vm.stalledCronJobCount) stalled cron jobs"),
                            tone: .warning
                        )
                    }
                    if hasSearchScope {
                        PresentationToneBadge(
                            text: visibleItemCount == 1 ? String(localized: "1 visible result") : String(localized: "\(visibleItemCount) visible results"),
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Automation signal facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep scope, inventory size, and failure categories visible before drilling into workflows, runs, triggers, schedules, and cron jobs."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: scope.label,
                    tone: scopeTone
                )
            } facts: {
                Label(
                    vm.workflows.count == 1 ? String(localized: "1 workflow") : String(localized: "\(vm.workflows.count) workflows"),
                    systemImage: "flowchart"
                )
                Label(
                    vm.workflowRuns.count == 1 ? String(localized: "1 run") : String(localized: "\(vm.workflowRuns.count) runs"),
                    systemImage: "play.circle"
                )
                Label(
                    vm.triggers.count == 1 ? String(localized: "1 trigger") : String(localized: "\(vm.triggers.count) triggers"),
                    systemImage: "bolt.badge.clock"
                )
                Label(
                    visibleItemCount == 1 ? String(localized: "1 visible result") : String(localized: "\(visibleItemCount) visible results"),
                    systemImage: "line.3.horizontal.decrease.circle"
                )
                if vm.failedWorkflowRunCount > 0 {
                    Label(
                        vm.failedWorkflowRunCount == 1 ? String(localized: "1 failed run") : String(localized: "\(vm.failedWorkflowRunCount) failed runs"),
                        systemImage: "xmark.octagon"
                    )
                }
                if vm.stalledCronJobCount > 0 {
                    Label(
                        vm.stalledCronJobCount == 1 ? String(localized: "1 stalled cron") : String(localized: "\(vm.stalledCronJobCount) stalled cron jobs"),
                        systemImage: "clock.badge.exclamationmark"
                    )
                }
            }
        }
    }
}

private struct AutomationFilterCard: View {
    @Binding var scope: AutomationMonitorScope
    let searchText: String
    let visibleCount: Int
    let totalCount: Int

    var body: some View {
        MonitoringFilterCard(summary: summaryLine, detail: searchSummary) {
            activeBadge
        } controls: {
            FlowLayout(spacing: 8) {
                ForEach(AutomationMonitorScope.allCases) { option in
                    Button {
                        scope = option
                    } label: {
                        SelectableCapsuleBadge(text: option.label, isSelected: scope == option)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var activeBadge: some View {
        PresentationToneBadge(
            text: scope.label,
            tone: badgeTone
        )
    }

    private var summaryLine: String {
        if visibleCount == totalCount {
            return totalCount == 1
                ? String(localized: "1 automation item in monitor")
                : String(localized: "\(totalCount) automation items in monitor")
        }

        return String(localized: "\(visibleCount) of \(totalCount) automation items visible")
    }

    private var searchSummary: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return String(localized: "Search workflows, triggers, schedules, or cron jobs.")
        }
        return String(localized: "Search active: \"\(query)\"")
    }

    private var badgeTone: PresentationTone {
        switch scope {
        case .all:
            return .neutral
        case .attention:
            return .warning
        case .active:
            return .positive
        }
    }
}

private struct AutomationRouteInventoryDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let jumpCount: Int
    let failedRunCount: Int
    let stalledCronCount: Int
    let visibleItemCount: Int

    var body: some View {
        MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
            FlowLayout(spacing: 8) {
                PresentationToneBadge(
                    text: primaryRouteCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryRouteCount) primary routes"),
                    tone: .neutral
                )
                PresentationToneBadge(
                    text: supportRouteCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportRouteCount) support routes"),
                    tone: .neutral
                )
                PresentationToneBadge(
                    text: jumpCount == 1 ? String(localized: "1 jump") : String(localized: "\(jumpCount) jumps"),
                    tone: jumpCount > 0 ? .positive : .neutral
                )
                if failedRunCount > 0 {
                    PresentationToneBadge(
                        text: failedRunCount == 1 ? String(localized: "1 failed run") : String(localized: "\(failedRunCount) failed runs"),
                        tone: .critical
                    )
                }
                if stalledCronCount > 0 {
                    PresentationToneBadge(
                        text: stalledCronCount == 1 ? String(localized: "1 stalled cron") : String(localized: "\(stalledCronCount) stalled cron jobs"),
                        tone: .warning
                    )
                }
                PresentationToneBadge(
                    text: visibleItemCount == 1 ? String(localized: "1 visible item") : String(localized: "\(visibleItemCount) visible items"),
                    tone: .neutral
                )
            }
        }
    }

    private var summaryLine: String {
        let totalRoutes = primaryRouteCount + supportRouteCount + jumpCount
        return totalRoutes == 1
            ? String(localized: "1 automation route or jump is grouped in this deck.")
            : String(localized: "\(totalRoutes) automation routes and jumps are grouped in this deck.")
    }

    private var detailLine: String {
        String(localized: "Routes and long-section jumps stay summarized here before the grouped workflow lists.")
    }
}

private struct AutomationSectionInventoryDeck: View {
    let sectionCount: Int
    let visibleItemCount: Int
    let workflowCount: Int
    let runCount: Int
    let triggerCount: Int
    let scheduleCount: Int
    let cronCount: Int
    let failedRunCount: Int
    let exhaustedTriggerCount: Int
    let stalledCronCount: Int

    var body: some View {
        MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
            FlowLayout(spacing: 8) {
                PresentationToneBadge(
                    text: sectionCount == 1 ? String(localized: "1 live section") : String(localized: "\(sectionCount) live sections"),
                    tone: .positive
                )
                PresentationToneBadge(
                    text: visibleItemCount == 1 ? String(localized: "1 visible item") : String(localized: "\(visibleItemCount) visible items"),
                    tone: .neutral
                )
                if failedRunCount > 0 {
                    PresentationToneBadge(
                        text: failedRunCount == 1 ? String(localized: "1 failed run") : String(localized: "\(failedRunCount) failed runs"),
                        tone: .critical
                    )
                }
                if stalledCronCount > 0 {
                    PresentationToneBadge(
                        text: stalledCronCount == 1 ? String(localized: "1 stalled cron") : String(localized: "\(stalledCronCount) stalled cron jobs"),
                        tone: .warning
                    )
                }
            }
        }
        .overlay(alignment: .bottom) { EmptyView() }

        MonitoringFactsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Section inventory"))
                    .font(.subheadline.weight(.medium))
                Text(String(localized: "Keep workflow, trigger, schedule, and cron coverage visible before the route rail and grouped automation lists."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } accessory: {
            PresentationToneBadge(
                text: workflowCount == 1 ? String(localized: "1 workflow") : String(localized: "\(workflowCount) workflows"),
                tone: workflowCount > 0 ? .positive : .neutral
            )
        } facts: {
            Label(
                runCount == 1 ? String(localized: "1 run") : String(localized: "\(runCount) runs"),
                systemImage: "play.rectangle.on.rectangle"
            )
            Label(
                triggerCount == 1 ? String(localized: "1 trigger") : String(localized: "\(triggerCount) triggers"),
                systemImage: "bolt.badge.clock"
            )
            Label(
                scheduleCount == 1 ? String(localized: "1 schedule") : String(localized: "\(scheduleCount) schedules"),
                systemImage: "calendar"
            )
            Label(
                cronCount == 1 ? String(localized: "1 cron") : String(localized: "\(cronCount) cron jobs"),
                systemImage: "clock.arrow.circlepath"
            )
            if exhaustedTriggerCount > 0 {
                Label(
                    exhaustedTriggerCount == 1 ? String(localized: "1 exhausted trigger") : String(localized: "\(exhaustedTriggerCount) exhausted triggers"),
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
    }

    private var summaryLine: String {
        sectionCount == 1
            ? String(localized: "1 automation section is active below the controls deck.")
            : String(localized: "\(sectionCount) automation sections are active below the controls deck.")
    }

    private var detailLine: String {
        String(localized: "Workflow, trigger, schedule, and cron coverage stay summarized before the route rail and longer automation inventories.")
    }
}

private struct AutomationPressureCoverageDeck: View {
    let failedRunCount: Int
    let exhaustedTriggerCount: Int
    let stalledCronCount: Int
    let workflowCount: Int
    let triggerCount: Int
    let cronCount: Int
    let visibleItemCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Pressure coverage keeps automation failure mix readable before the grouped workflow lists begin."),
                detail: String(localized: "Use this deck to judge whether current automation drag comes from failed runs, exhausted triggers, or stalled cron work."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if failedRunCount > 0 {
                        PresentationToneBadge(
                            text: failedRunCount == 1 ? String(localized: "1 failed run") : String(localized: "\(failedRunCount) failed runs"),
                            tone: .critical
                        )
                    }
                    if exhaustedTriggerCount > 0 {
                        PresentationToneBadge(
                            text: exhaustedTriggerCount == 1 ? String(localized: "1 exhausted trigger") : String(localized: "\(exhaustedTriggerCount) exhausted triggers"),
                            tone: .warning
                        )
                    }
                    if stalledCronCount > 0 {
                        PresentationToneBadge(
                            text: stalledCronCount == 1 ? String(localized: "1 stalled cron") : String(localized: "\(stalledCronCount) stalled cron jobs"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Pressure coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep visible automation breadth readable before opening the longer workflow, trigger, schedule, and cron sections."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleItemCount == 1 ? String(localized: "1 visible item") : String(localized: "\(visibleItemCount) visible items"),
                    tone: visibleItemCount > 0 ? .positive : .neutral
                )
            } facts: {
                Label(
                    workflowCount == 1 ? String(localized: "1 workflow") : String(localized: "\(workflowCount) workflows"),
                    systemImage: "square.stack.3d.up"
                )
                Label(
                    triggerCount == 1 ? String(localized: "1 trigger") : String(localized: "\(triggerCount) triggers"),
                    systemImage: "bolt.badge.clock"
                )
                Label(
                    cronCount == 1 ? String(localized: "1 cron") : String(localized: "\(cronCount) cron jobs"),
                    systemImage: "clock.arrow.circlepath"
                )
            }
        }
    }
}

private struct AutomationSupportCoverageDeck: View {
    let visibleItemCount: Int
    let workflowCount: Int
    let triggerCount: Int
    let scheduleCount: Int
    let cronCount: Int
    let jumpCount: Int
    let scopeLabel: String
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep scope, search state, and automation breadth readable before opening the grouped workflow, trigger, schedule, and cron lists."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: scopeLabel, tone: .neutral)
                    if hasSearchScope {
                        PresentationToneBadge(text: String(localized: "Search scoped"), tone: .neutral)
                    }
                    if jumpCount > 0 {
                        PresentationToneBadge(
                            text: jumpCount == 1 ? String(localized: "1 jump") : String(localized: "\(jumpCount) jumps"),
                            tone: .positive
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Support coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep active automation families and surface breadth visible before the grouped automation inventories take over."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleItemCount == 1 ? String(localized: "1 visible item") : String(localized: "\(visibleItemCount) visible items"),
                    tone: visibleItemCount > 0 ? .positive : .neutral
                )
            } facts: {
                if workflowCount > 0 {
                    Label(
                        workflowCount == 1 ? String(localized: "1 workflow") : String(localized: "\(workflowCount) workflows"),
                        systemImage: "square.stack.3d.down.forward"
                    )
                }
                if triggerCount > 0 {
                    Label(
                        triggerCount == 1 ? String(localized: "1 trigger") : String(localized: "\(triggerCount) triggers"),
                        systemImage: "bolt.badge.clock"
                    )
                }
                if scheduleCount + cronCount > 0 {
                    Label(
                        scheduleCount + cronCount == 1
                            ? String(localized: "1 scheduler entry")
                            : String(localized: "\(scheduleCount + cronCount) scheduler entries"),
                        systemImage: "calendar"
                    )
                }
            }
        }
    }

    private var summaryLine: String {
        if hasSearchScope {
            return String(localized: "Automation support coverage is currently concentrated in a scoped automation slice.")
        }
        if scheduleCount + cronCount > 0 {
            return String(localized: "Automation support coverage is currently anchored by workflow breadth and scheduler depth.")
        }
        return String(localized: "Automation support coverage is currently light and mostly reflects active route breadth.")
    }
}

private struct AutomationActionReadinessDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let jumpCount: Int
    let visibleItemCount: Int
    let workflowCount: Int
    let runCount: Int
    let failedRunCount: Int
    let scopeLabel: String
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to check whether route jumps, workflow coverage, and scoped queue actions are ready before opening the grouped automation lists."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: scopeLabel, tone: .neutral)
                    if hasSearchScope {
                        PresentationToneBadge(text: String(localized: "Search scoped"), tone: .neutral)
                    }
                    PresentationToneBadge(
                        text: String(localized: "\(primaryRouteCount + supportRouteCount + jumpCount) actions"),
                        tone: .neutral
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Action readiness"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep route breadth, jump coverage, and workflow visibility readable before drilling into runs, triggers, schedules, or cron jobs."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleItemCount == 1 ? String(localized: "1 visible item") : String(localized: "\(visibleItemCount) visible items"),
                    tone: visibleItemCount > 0 ? .positive : .neutral
                )
            } facts: {
                Label(
                    workflowCount == 1 ? String(localized: "1 workflow") : String(localized: "\(workflowCount) workflows"),
                    systemImage: "square.stack.3d.up"
                )
                Label(
                    runCount == 1 ? String(localized: "1 run") : String(localized: "\(runCount) runs"),
                    systemImage: "play.rectangle.on.rectangle"
                )
                if failedRunCount > 0 {
                    Label(
                        failedRunCount == 1 ? String(localized: "1 failed run") : String(localized: "\(failedRunCount) failed runs"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if jumpCount > 0 {
                    Label(
                        jumpCount == 1 ? String(localized: "1 jump") : String(localized: "\(jumpCount) jumps"),
                        systemImage: "arrow.down.to.line"
                    )
                }
            }
        }
    }

    private var summaryLine: String {
        if hasSearchScope {
            return String(localized: "Automation action readiness is currently narrowed by an active search scope.")
        }
        if failedRunCount > 0 {
            return String(localized: "Automation action readiness is currently anchored by failed runs that are ready for deeper drilldown.")
        }
        return String(localized: "Automation action readiness is currently clear enough for route jumps and grouped automation review.")
    }
}

private struct AutomationFocusCoverageDeck: View {
    let visibleItemCount: Int
    let workflowCount: Int
    let runCount: Int
    let triggerCount: Int
    let scheduleCount: Int
    let cronCount: Int
    let failedRunCount: Int
    let exhaustedTriggerCount: Int
    let stalledCronCount: Int
    let scopeLabel: String
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep the dominant automation lane visible before opening grouped workflow, trigger, and schedule sections."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: scopeLabel, tone: .neutral)
                    PresentationToneBadge(
                        text: visibleItemCount == 1 ? String(localized: "1 visible item") : String(localized: "\(visibleItemCount) visible items"),
                        tone: visibleItemCount > 0 ? .positive : .neutral
                    )
                    if failedRunCount > 0 {
                        PresentationToneBadge(
                            text: failedRunCount == 1 ? String(localized: "1 failed run") : String(localized: "\(failedRunCount) failed runs"),
                            tone: .critical
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Focus coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the dominant automation lane readable before moving from the compact decks into workflow, trigger, and scheduler detail."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: workflowCount == 1 ? String(localized: "1 workflow lane") : String(localized: "\(workflowCount) workflow lanes"),
                    tone: workflowCount > 0 ? .positive : .neutral
                )
            } facts: {
                if runCount > 0 {
                    Label(
                        runCount == 1 ? String(localized: "1 run lane") : String(localized: "\(runCount) run lanes"),
                        systemImage: "play.rectangle"
                    )
                }
                if triggerCount > 0 {
                    Label(
                        triggerCount == 1 ? String(localized: "1 trigger lane") : String(localized: "\(triggerCount) trigger lanes"),
                        systemImage: "bolt"
                    )
                }
                if scheduleCount > 0 {
                    Label(
                        scheduleCount == 1 ? String(localized: "1 schedule lane") : String(localized: "\(scheduleCount) schedule lanes"),
                        systemImage: "calendar"
                    )
                }
                if cronCount > 0 {
                    Label(
                        cronCount == 1 ? String(localized: "1 cron lane") : String(localized: "\(cronCount) cron lanes"),
                        systemImage: "clock.arrow.circlepath"
                    )
                }
                if exhaustedTriggerCount > 0 {
                    Label(
                        exhaustedTriggerCount == 1 ? String(localized: "1 exhausted trigger") : String(localized: "\(exhaustedTriggerCount) exhausted triggers"),
                        systemImage: "bolt.slash"
                    )
                }
                if stalledCronCount > 0 {
                    Label(
                        stalledCronCount == 1 ? String(localized: "1 stalled cron") : String(localized: "\(stalledCronCount) stalled crons"),
                        systemImage: "hourglass"
                    )
                }
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
    }

    private var summaryLine: String {
        if failedRunCount > 0 || exhaustedTriggerCount > 0 || stalledCronCount > 0 {
            return String(localized: "Automation focus coverage is currently anchored by failed or stalled automation lanes.")
        }
        if hasSearchScope {
            return String(localized: "Automation focus coverage is currently anchored by the filtered automation slice.")
        }
        return String(localized: "Automation focus coverage is currently balanced across workflow, trigger, and schedule lanes.")
    }
}

private struct AutomationScoreboard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let vm: DashboardViewModel

    private var issueCount: Int {
        vm.failedWorkflowRunCount
            + vm.exhaustedTriggerCount
            + vm.pausedScheduleCount
            + vm.pausedCronJobCount
            + vm.stalledCronJobCount
    }

    private var workflowStatus: MonitoringSummaryStatus {
        .countStatus(vm.workflowCount, activeTone: .positive)
    }

    private var failedRunStatus: MonitoringSummaryStatus {
        .countStatus(vm.failedWorkflowRunCount, activeTone: .critical)
    }

    private var triggerStatus: MonitoringSummaryStatus {
        MonitoringSummaryStatus(
            summary: "\(vm.enabledTriggerCount)/\(vm.triggers.count)",
            tone: vm.exhaustedTriggerCount > 0 ? .warning : .positive
        )
    }

    private var scheduleStatus: MonitoringSummaryStatus {
        MonitoringSummaryStatus(
            summary: "\(vm.enabledScheduleCount)/\(vm.schedules.count)",
            tone: vm.pausedScheduleCount > 0 ? .warning : .positive
        )
    }

    private var cronStatus: MonitoringSummaryStatus {
        MonitoringSummaryStatus(
            summary: "\(vm.enabledCronJobCount)/\(vm.cronJobs.count)",
            tone: vm.stalledCronJobCount > 0 ? .warning : .positive
        )
    }

    private var issueStatus: MonitoringSummaryStatus {
        MonitoringSummaryStatus(summary: "\(issueCount)", tone: vm.automationPressureTone)
    }

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            StatBadge(
                value: "\(vm.workflowCount)",
                label: "Workflows",
                icon: "flowchart",
                color: workflowStatus.color(positive: .blue)
            )
            StatBadge(
                value: "\(vm.failedWorkflowRunCount)",
                label: "Failed Runs",
                icon: "exclamationmark.triangle",
                color: failedRunStatus.tone.color
            )
            StatBadge(
                value: triggerStatus.summary,
                label: "Triggers",
                icon: "bolt.horizontal.circle",
                color: triggerStatus.color(positive: .green)
            )
            StatBadge(
                value: scheduleStatus.summary,
                label: "Schedules",
                icon: "calendar",
                color: scheduleStatus.color(positive: .teal)
            )
            StatBadge(
                value: cronStatus.summary,
                label: "Cron",
                icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                color: cronStatus.color(positive: .indigo)
            )
            StatBadge(
                value: issueStatus.summary,
                label: "Issues",
                icon: "bell.badge",
                color: issueStatus.color(positive: .green)
            )
        }
        .padding(.horizontal)
    }
}

private struct AutomationWorkflowsSnapshotCard: View {
    let workflows: [WorkflowSummary]
    let visibleCount: Int
    let failedWorkflowNames: Set<String>
    let runningWorkflowNames: Set<String>

    private var totalSteps: Int {
        workflows.reduce(0) { $0 + $1.steps }
    }

    private var averageSteps: Int {
        guard !workflows.isEmpty else { return 0 }
        return totalSteps / workflows.count
    }

    private var newestWorkflow: WorkflowSummary? {
        workflows.max {
            ($0.createdAt.automationISO8601Date ?? .distantPast) < ($1.createdAt.automationISO8601Date ?? .distantPast)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Workflow definitions stay visible before the longer workflow inventory."),
                detail: String(localized: "Use the compact summary to see definition depth, failing workflows, and the newest workflow before opening the full list."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: visibleCount == workflows.count
                            ? (workflows.count == 1 ? String(localized: "1 workflow visible") : String(localized: "\(workflows.count) workflows visible"))
                            : String(localized: "\(visibleCount) of \(workflows.count) visible"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: averageSteps == 1 ? String(localized: "1 avg step") : String(localized: "\(averageSteps) avg steps"),
                        tone: .neutral
                    )
                    if !failedWorkflowNames.isEmpty {
                        PresentationToneBadge(
                            text: failedWorkflowNames.count == 1 ? String(localized: "1 failing workflow") : String(localized: "\(failedWorkflowNames.count) failing workflows"),
                            tone: .critical
                        )
                    }
                    if !runningWorkflowNames.isEmpty {
                        PresentationToneBadge(
                            text: runningWorkflowNames.count == 1 ? String(localized: "1 active workflow") : String(localized: "\(runningWorkflowNames.count) active workflows"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Workflow facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep total step depth, visible count, and the newest definition clear before the detailed workflow rows."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if let newestWorkflow {
                    PresentationToneBadge(
                        text: newestWorkflow.createdAt.automationRelativeText(prefix: String(localized: "Newest")),
                        tone: .neutral
                    )
                }
            } facts: {
                Label(
                    workflows.count == 1 ? String(localized: "1 workflow") : String(localized: "\(workflows.count) workflows"),
                    systemImage: "flowchart"
                )
                Label(
                    totalSteps == 1 ? String(localized: "1 total step") : String(localized: "\(totalSteps) total steps"),
                    systemImage: "list.number"
                )
                Label(
                    averageSteps == 1 ? String(localized: "1 avg step") : String(localized: "\(averageSteps) avg steps"),
                    systemImage: "chart.bar"
                )
                if let newestWorkflow {
                    Label(newestWorkflow.name, systemImage: "clock.badge")
                }
            }
        }
    }
}

private struct AutomationWorkflowRunsSnapshotCard: View {
    let runs: [WorkflowRun]
    let visibleCount: Int

    private var failedCount: Int {
        runs.filter { $0.state == .failed }.count
    }

    private var runningCount: Int {
        runs.filter { $0.state == .running || $0.state == .pending }.count
    }

    private var completedCount: Int {
        runs.filter { $0.state == .completed }.count
    }

    private var latestRun: WorkflowRun? {
        runs.max {
            ($0.startedAt.automationISO8601Date ?? .distantPast) < ($1.startedAt.automationISO8601Date ?? .distantPast)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Recent run pressure stays visible before the per-run execution log."),
                detail: String(localized: "Use the summary to see failures, active runs, and the latest run start time before opening each execution row."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: visibleCount == runs.count
                            ? (runs.count == 1 ? String(localized: "1 run visible") : String(localized: "\(runs.count) runs visible"))
                            : String(localized: "\(visibleCount) of \(runs.count) visible"),
                        tone: .positive
                    )
                    if failedCount > 0 {
                        PresentationToneBadge(
                            text: failedCount == 1 ? String(localized: "1 failed") : String(localized: "\(failedCount) failed"),
                            tone: .critical
                        )
                    }
                    if runningCount > 0 {
                        PresentationToneBadge(
                            text: runningCount == 1 ? String(localized: "1 active") : String(localized: "\(runningCount) active"),
                            tone: .warning
                        )
                    }
                    if completedCount > 0 {
                        PresentationToneBadge(
                            text: completedCount == 1 ? String(localized: "1 completed") : String(localized: "\(completedCount) completed"),
                            tone: .positive
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Run facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep active, failed, and completed execution counts visible before the longer run history."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if let latestRun {
                    PresentationToneBadge(
                        text: latestRun.startedAt.automationRelativeText(prefix: String(localized: "Latest")),
                        tone: latestRun.state == .failed ? .critical : latestRun.state == .completed ? .positive : .warning
                    )
                }
            } facts: {
                Label(
                    runs.count == 1 ? String(localized: "1 run") : String(localized: "\(runs.count) runs"),
                    systemImage: "play.circle"
                )
                if failedCount > 0 {
                    Label(
                        failedCount == 1 ? String(localized: "1 failed") : String(localized: "\(failedCount) failed"),
                        systemImage: "xmark.octagon"
                    )
                }
                if runningCount > 0 {
                    Label(
                        runningCount == 1 ? String(localized: "1 active") : String(localized: "\(runningCount) active"),
                        systemImage: "bolt.circle"
                    )
                }
                if let latestRun {
                    Label(latestRun.workflowName, systemImage: "clock.badge")
                }
            }
        }
    }
}

private struct AutomationTriggersSnapshotCard: View {
    let triggers: [TriggerDefinition]
    let visibleCount: Int

    private var enabledCount: Int {
        triggers.filter(\.enabled).count
    }

    private var exhaustedCount: Int {
        triggers.filter(\.isExhausted).count
    }

    private var limitedCount: Int {
        triggers.filter { $0.maxFires > 0 }.count
    }

    private var uniqueAgentCount: Int {
        Set(triggers.map(\.agentId)).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Trigger coverage stays visible before the longer trigger inventory."),
                detail: String(localized: "Use the summary to see enablement, exhaustion, and how widely trigger definitions are spread across agents."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: visibleCount == triggers.count
                            ? (triggers.count == 1 ? String(localized: "1 trigger visible") : String(localized: "\(triggers.count) triggers visible"))
                            : String(localized: "\(visibleCount) of \(triggers.count) visible"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: enabledCount == 1 ? String(localized: "1 enabled") : String(localized: "\(enabledCount) enabled"),
                        tone: enabledCount > 0 ? .positive : .neutral
                    )
                    if exhaustedCount > 0 {
                        PresentationToneBadge(
                            text: exhaustedCount == 1 ? String(localized: "1 exhausted") : String(localized: "\(exhaustedCount) exhausted"),
                            tone: .critical
                        )
                    }
                    if limitedCount > 0 {
                        PresentationToneBadge(
                            text: limitedCount == 1 ? String(localized: "1 capped") : String(localized: "\(limitedCount) capped"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Trigger facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep enablement, capped triggers, and agent spread visible before opening each trigger rule."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: uniqueAgentCount == 1 ? String(localized: "1 agent") : String(localized: "\(uniqueAgentCount) agents"),
                    tone: .neutral
                )
            } facts: {
                Label(
                    triggers.count == 1 ? String(localized: "1 trigger") : String(localized: "\(triggers.count) triggers"),
                    systemImage: "bolt.badge.clock"
                )
                Label(
                    enabledCount == 1 ? String(localized: "1 enabled") : String(localized: "\(enabledCount) enabled"),
                    systemImage: "checkmark.circle"
                )
                if exhaustedCount > 0 {
                    Label(
                        exhaustedCount == 1 ? String(localized: "1 exhausted") : String(localized: "\(exhaustedCount) exhausted"),
                        systemImage: "gauge.badge.minus"
                    )
                }
                Label(
                    uniqueAgentCount == 1 ? String(localized: "1 agent targeted") : String(localized: "\(uniqueAgentCount) agents targeted"),
                    systemImage: "person.3"
                )
            }
        }
    }
}

private struct AutomationSchedulesSnapshotCard: View {
    let schedules: [ScheduleEntry]
    let visibleCount: Int

    private var enabledCount: Int {
        schedules.filter(\.enabled).count
    }

    private var pausedCount: Int {
        schedules.count - enabledCount
    }

    private var uniqueAgentCount: Int {
        Set(schedules.map(\.agentId)).count
    }

    private var recentlyRunCount: Int {
        schedules.filter { $0.lastRun != nil }.count
    }

    private var busiestSchedule: ScheduleEntry? {
        schedules.max { $0.runCount < $1.runCount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Schedule state stays visible before the longer list of timer-driven prompts."),
                detail: String(localized: "Use the summary to see paused schedules, covered agents, and the most active schedule before scanning the rows."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: visibleCount == schedules.count
                            ? (schedules.count == 1 ? String(localized: "1 schedule visible") : String(localized: "\(schedules.count) schedules visible"))
                            : String(localized: "\(visibleCount) of \(schedules.count) visible"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: enabledCount == 1 ? String(localized: "1 enabled") : String(localized: "\(enabledCount) enabled"),
                        tone: enabledCount > 0 ? .positive : .neutral
                    )
                    if pausedCount > 0 {
                        PresentationToneBadge(
                            text: pausedCount == 1 ? String(localized: "1 paused") : String(localized: "\(pausedCount) paused"),
                            tone: .warning
                        )
                    }
                    if recentlyRunCount > 0 {
                        PresentationToneBadge(
                            text: recentlyRunCount == 1 ? String(localized: "1 with history") : String(localized: "\(recentlyRunCount) with history"),
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Schedule facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep agent coverage, recent activity, and the busiest schedule visible before the longer schedule list."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if let busiestSchedule {
                    PresentationToneBadge(
                        text: busiestSchedule.runCount == 1 ? String(localized: "1 run") : String(localized: "\(busiestSchedule.runCount) runs"),
                        tone: busiestSchedule.enabled ? .positive : .warning
                    )
                }
            } facts: {
                Label(
                    schedules.count == 1 ? String(localized: "1 schedule") : String(localized: "\(schedules.count) schedules"),
                    systemImage: "calendar"
                )
                Label(
                    uniqueAgentCount == 1 ? String(localized: "1 agent") : String(localized: "\(uniqueAgentCount) agents"),
                    systemImage: "person.3"
                )
                if recentlyRunCount > 0 {
                    Label(
                        recentlyRunCount == 1 ? String(localized: "1 recent run") : String(localized: "\(recentlyRunCount) recent runs"),
                        systemImage: "clock.arrow.circlepath"
                    )
                }
                if let busiestSchedule {
                    Label(busiestSchedule.name, systemImage: "chart.bar")
                }
            }
        }
    }
}

private struct AutomationCronJobsSnapshotCard: View {
    let jobs: [CronJob]
    let visibleCount: Int

    private var enabledCount: Int {
        jobs.filter(\.enabled).count
    }

    private var pausedCount: Int {
        jobs.count - enabledCount
    }

    private var stalledCount: Int {
        jobs.filter { $0.enabled && $0.nextRun == nil }.count
    }

    private var deliveryCount: Int {
        Set(jobs.map(\.delivery.kind)).count
    }

    private var nextRunCount: Int {
        jobs.filter { $0.nextRun != nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Cron timing stays visible before the longer cron delivery inventory."),
                detail: String(localized: "Use the summary to see stalled jobs, enabled coverage, and delivery spread before opening the cron rows."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: visibleCount == jobs.count
                            ? (jobs.count == 1 ? String(localized: "1 cron job visible") : String(localized: "\(jobs.count) cron jobs visible"))
                            : String(localized: "\(visibleCount) of \(jobs.count) visible"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: enabledCount == 1 ? String(localized: "1 enabled") : String(localized: "\(enabledCount) enabled"),
                        tone: enabledCount > 0 ? .positive : .neutral
                    )
                    if pausedCount > 0 {
                        PresentationToneBadge(
                            text: pausedCount == 1 ? String(localized: "1 paused") : String(localized: "\(pausedCount) paused"),
                            tone: .warning
                        )
                    }
                    if stalledCount > 0 {
                        PresentationToneBadge(
                            text: stalledCount == 1 ? String(localized: "1 stalled") : String(localized: "\(stalledCount) stalled"),
                            tone: .critical
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Cron facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep enabled coverage, next-run health, and delivery diversity visible before the full cron list."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: deliveryCount == 1 ? String(localized: "1 delivery mode") : String(localized: "\(deliveryCount) delivery modes"),
                    tone: .neutral
                )
            } facts: {
                Label(
                    jobs.count == 1 ? String(localized: "1 cron job") : String(localized: "\(jobs.count) cron jobs"),
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                )
                Label(
                    enabledCount == 1 ? String(localized: "1 enabled") : String(localized: "\(enabledCount) enabled"),
                    systemImage: "checkmark.circle"
                )
                if nextRunCount > 0 {
                    Label(
                        nextRunCount == 1 ? String(localized: "1 next run ready") : String(localized: "\(nextRunCount) next runs ready"),
                        systemImage: "clock.badge"
                    )
                }
                if stalledCount > 0 {
                    Label(
                        stalledCount == 1 ? String(localized: "1 stalled") : String(localized: "\(stalledCount) stalled"),
                        systemImage: "clock.badge.exclamationmark"
                    )
                }
            }
        }
    }
}

private struct WorkflowDefinitionRow: View {
    let workflow: WorkflowSummary
    let failedRuns: Int
    let runningRuns: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ResponsiveAccessoryRow(horizontalAlignment: .top, verticalSpacing: 8) {
                summaryBlock
            } accessory: {
                statusBlock
            }

            Text(relativeText(from: workflow.createdAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func relativeText(from value: String) -> String {
        guard let date = value.automationISO8601Date else { return value }
        return String(localized: "Created \(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()))")
    }

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(workflow.name)
                .font(.subheadline.weight(.medium))
            if !workflow.description.isEmpty {
                Text(workflow.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            PresentationToneBadge(text: String(localized: "\(workflow.steps) steps"), tone: .neutral)
            if failedRuns > 0 {
                PresentationToneBadge(
                    text: failedRuns == 1
                        ? String(localized: "1 failed run")
                        : String(localized: "\(failedRuns) failed"),
                    tone: .critical
                )
            } else if runningRuns > 0 {
                PresentationToneBadge(
                    text: runningRuns == 1
                        ? String(localized: "1 running")
                        : String(localized: "\(runningRuns) running"),
                    tone: .warning
                )
            }
        }
    }
}

private struct WorkflowRunRow: View {
    let run: WorkflowRun

    var body: some View {
        MonitoringFactsRow(horizontalAlignment: .top, verticalSpacing: 8, headerVerticalSpacing: 8) {
            summaryBlock
        } accessory: {
            PresentationToneBadge(text: run.state.label, tone: tone)
        } facts: {
            facts
        }
        .padding(.vertical, 2)
    }

    private var tone: PresentationTone {
        switch run.state {
        case .failed:
            .critical
        case .running, .pending:
            .warning
        case .completed:
            .positive
        }
    }

    private func relativeText(from value: String) -> String {
        guard let date = value.automationISO8601Date else { return value }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(run.workflowName)
                .font(.subheadline.weight(.medium))
            Text("Started \(relativeText(from: run.startedAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var facts: some View {
        Label("\(run.stepsCompleted) steps", systemImage: "list.number")
        if let completedAt = run.completedAt {
            Label(relativeText(from: completedAt), systemImage: "clock")
        }
    }
}

private struct TriggerRow: View {
    let trigger: TriggerDefinition
    let agentName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonitoringFactsRow(horizontalAlignment: .top, verticalSpacing: 8, headerVerticalSpacing: 8) {
                summaryBlock
            } accessory: {
                PresentationToneBadge(text: statusLabel, tone: tone)
            } facts: {
                facts
            }

            if !trigger.promptTemplate.isEmpty {
                Text(trigger.promptTemplate)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusLabel: String {
        if trigger.isExhausted {
            return String(localized: "Exhausted")
        }
        return trigger.enabled
            ? String(localized: "Enabled")
            : String(localized: "Disabled")
    }

    private var tone: PresentationTone {
        if trigger.isExhausted {
            return .critical
        }
        return trigger.enabled ? .positive : .neutral
    }

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trigger.patternSummary)
                .font(.subheadline.weight(.medium))
            Text(agentName ?? trigger.agentId)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var facts: some View {
        Label("\(trigger.fireCount) fires", systemImage: "bolt.circle")
        if trigger.maxFires > 0 {
            Label("\(trigger.maxFires) max", systemImage: "gauge.with.dots.needle.67percent")
        } else {
            Label("Unlimited", systemImage: "infinity")
        }
    }
}

private struct ScheduleRow: View {
    let schedule: ScheduleEntry
    let agentName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonitoringFactsRow(horizontalAlignment: .top, verticalSpacing: 8, headerVerticalSpacing: 8) {
                summaryBlock
            } accessory: {
                PresentationToneBadge(
                    text: schedule.enabled
                        ? String(localized: "Enabled")
                        : String(localized: "Paused"),
                    tone: schedule.enabled ? .positive : .warning
                )
            } facts: {
                facts
            }

            if !schedule.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(schedule.message)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            if let lastRun = schedule.lastRun {
                Text("Last run \(relativeText(from: lastRun))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func relativeText(from value: String) -> String {
        guard let date = value.automationISO8601Date else { return value }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(schedule.name)
                .font(.subheadline.weight(.medium))
            Text(agentName ?? schedule.agentId)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var facts: some View {
        Label(schedule.cron, systemImage: "calendar")
        Label("\(schedule.runCount) runs", systemImage: "clock.arrow.circlepath")
    }
}

private struct CronJobRow: View {
    let job: CronJob
    let agentName: String?
    let scheduleSummary: String
    let actionSummary: String
    let deliverySummary: String

    var body: some View {
        MonitoringFactsRow(
            horizontalAlignment: .top,
            verticalSpacing: 8,
            headerVerticalSpacing: 8,
            factsFont: .caption2,
            factsColor: .secondary
        ) {
            summaryContent
        } accessory: {
            PresentationToneBadge(text: statusLabel, tone: tone)
        } facts: {
            timingFacts
        }
        .padding(.vertical, 2)
    }

    private var statusLabel: String {
        if !job.enabled {
            return String(localized: "Paused")
        }
        return job.nextRun == nil
            ? String(localized: "Missing next run")
            : String(localized: "Enabled")
    }

    private var tone: PresentationTone {
        if !job.enabled {
            return .warning
        }
        return job.nextRun == nil ? .critical : .positive
    }

    private func relativeText(from value: String) -> String {
        guard let date = value.automationISO8601Date else { return value }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(job.name)
                    .font(.subheadline.weight(.medium))
                Text(agentName ?? job.agentId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Label(scheduleSummary, systemImage: "calendar.badge.clock")
                Label(actionSummary, systemImage: "paperplane")
                Label(deliverySummary, systemImage: "point.3.filled.connected.trianglepath.dotted")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var timingFacts: some View {
        if let nextRun = job.nextRun {
            Label("Next \(relativeText(from: nextRun))", systemImage: "clock.badge")
        } else if job.enabled {
            Label("No next run", systemImage: "clock.badge.exclamationmark")
        }
        if let lastRun = job.lastRun {
            Label("Last \(relativeText(from: lastRun))", systemImage: "clock.arrow.circlepath")
        }
    }
}

private extension String {
    var automationISO8601Date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: self) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: self)
    }

    func automationRelativeText(prefix: String) -> String {
        guard let date = automationISO8601Date else { return self }
        let relative = RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        return String(localized: "\(prefix) \(relative)")
    }
}

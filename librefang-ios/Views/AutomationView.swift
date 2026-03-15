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
                } header: {
                    Text("Status Deck")
                } footer: {
                    Text("Keep scope, inventory size, and failure pressure in one compact automation digest before the grouped workflow sections.")
                }

                Section {
                    AutomationFilterCard(
                        scope: $scope,
                        searchText: searchText,
                        visibleCount: visibleItemCount,
                        totalCount: totalItemCount
                    )
                } header: {
                    Text("Filter")
                }

                Section {
                    MonitoringSurfaceGroupCard(
                        title: String(localized: "Primary Surfaces"),
                        detail: String(localized: "Keep the next operator exits closest to workflow and scheduler pressure.")
                    ) {
                        NavigationLink {
                            RuntimeView()
                        } label: {
                            MonitoringJumpRow(
                                title: String(localized: "Open Runtime"),
                                detail: String(localized: "Switch back to the runtime digest with automation pressure folded into the main monitor."),
                                systemImage: "server.rack",
                                tone: vm.automationPressureIssueCategoryCount > 0 ? .warning : .neutral,
                                badgeText: vm.automationPressureIssueCategoryCount > 0
                                    ? (vm.automationPressureIssueCategoryCount == 1 ? String(localized: "1 issue") : String(localized: "\(vm.automationPressureIssueCategoryCount) issues"))
                                    : nil,
                                badgeTone: .warning
                            )
                        }

                        NavigationLink {
                            IncidentsView()
                        } label: {
                            MonitoringJumpRow(
                                title: String(localized: "Open Incidents"),
                                detail: String(localized: "Switch to the incident queue where automation pressure is ranked with alerts and approvals."),
                                systemImage: "bell.badge",
                                tone: vm.automationPressureIssueCategoryCount > 0 ? .warning : .neutral,
                                badgeText: vm.failedWorkflowRunCount > 0
                                    ? (vm.failedWorkflowRunCount == 1 ? String(localized: "1 failed run") : String(localized: "\(vm.failedWorkflowRunCount) failed runs"))
                                    : nil,
                                badgeTone: .critical
                            )
                        }

                        NavigationLink {
                            DiagnosticsView()
                        } label: {
                            MonitoringJumpRow(
                                title: String(localized: "Open Diagnostics"),
                                detail: String(localized: "Switch to runtime health, build, config, and metrics when automation failures may be systemic."),
                                systemImage: "stethoscope",
                                tone: vm.diagnosticsSummaryTone,
                                badgeText: vm.diagnosticsConfigWarningCount > 0
                                    ? (vm.diagnosticsConfigWarningCount == 1 ? String(localized: "1 warning") : String(localized: "\(vm.diagnosticsConfigWarningCount) warnings"))
                                    : nil,
                                badgeTone: .warning
                            )
                        }

                        NavigationLink {
                            EventsView(api: deps.apiClient, initialScope: .critical)
                        } label: {
                            MonitoringJumpRow(
                                title: String(localized: "Open Critical Events"),
                                detail: String(localized: "Switch to the critical event feed if workflow failures correlate with audit activity."),
                                systemImage: "text.justify.leading",
                                tone: vm.recentCriticalAuditCount > 0 ? .critical : .neutral,
                                badgeText: vm.recentCriticalAuditCount > 0
                                    ? (vm.recentCriticalAuditCount == 1 ? String(localized: "1 critical") : String(localized: "\(vm.recentCriticalAuditCount) critical"))
                                    : nil,
                                badgeTone: .critical
                            )
                        }
                    }

                    MonitoringSurfaceGroupCard(
                        title: String(localized: "Supporting Surfaces"),
                        detail: String(localized: "Keep integration context behind the primary automation exits.")
                    ) {
                        NavigationLink {
                            IntegrationsView(initialScope: .attention)
                        } label: {
                            MonitoringJumpRow(
                                title: String(localized: "Open Integrations"),
                                detail: String(localized: "Switch to providers, channels, and model drift when automation failures may be rooted in integration trouble."),
                                systemImage: "square.3.layers.3d.down.forward",
                                tone: vm.integrationPressureIssueCategoryCount > 0 ? .critical : .neutral,
                                badgeText: vm.integrationPressureIssueCategoryCount > 0
                                    ? (vm.integrationPressureIssueCategoryCount == 1 ? String(localized: "1 integration issue") : String(localized: "\(vm.integrationPressureIssueCategoryCount) integration issues"))
                                    : nil,
                                badgeTone: .critical
                            )
                        }
                    }
                } header: {
                    Text("Operator Surfaces")
                } footer: {
                    Text("Use these routes when automation issues need incident, runtime, or event context beyond the current filtered list.")
                }

                if hasAutomationData {
                    Section {
                        automationFocusSection(proxy)
                    } header: {
                        Text("Focus Areas")
                    } footer: {
                        Text("These jump targets move through the long automation monitor without forcing a full scroll on iPhone.")
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
}

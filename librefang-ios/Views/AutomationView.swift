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

    init(initialSearchText: String = "", initialScope: AutomationMonitorScope = .all) {
        _searchText = State(initialValue: initialSearchText)
        _scope = State(initialValue: initialScope)
    }

    var body: some View {
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
                FlowLayout(spacing: 8) {
                    ForEach(AutomationMonitorScope.allCases) { option in
                        Button {
                            scope = option
                        } label: {
                            SelectableLabelCapsuleBadge(
                                text: option.label,
                                systemImage: option == .attention ? "exclamationmark.triangle" : option == .active ? "bolt.fill" : "list.bullet",
                                isSelected: scope == option
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !hasAutomationData && !vm.isLoading {
                Section("Automation") {
                    ContentUnavailableView(
                        "No Automation Inventory",
                        systemImage: "flowchart",
                        description: Text("No workflows or jobs in the current snapshot.")
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
                                    ? String(localized: "Change the scope or refresh.")
                                    : String(localized: "Try a different search.")
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
        .navigationTitle(String(localized: "Automation"))
        .searchable(text: $searchText, prompt: Text(String(localized: "Search workflow, trigger, or job")))
        .monitoringRefreshInteractionGate(isRefreshing: vm.isLoading)
        .refreshable {
            await vm.refresh()
        }
        .overlay {
            if vm.isLoading && !hasAutomationData {
                ProgressView(String(localized: "Loading automation..."))
            }
        }
        .task {
            if !hasAutomationData {
                await vm.refresh()
            }
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
            }
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
            }
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
            }
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
            }
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
            }
        }
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

private struct WorkflowDefinitionRow: View {
    let workflow: WorkflowSummary
    let failedRuns: Int
    let runningRuns: Int

    var body: some View {
        ResponsiveAccessoryRow(horizontalAlignment: .top, verticalSpacing: 8) {
            summaryBlock
        } accessory: {
            statusBlock
        }
        .padding(.vertical, 2)
    }

    private var summaryBlock: some View {
        Text(workflow.name)
            .font(.subheadline.weight(.medium))
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
        .padding(.vertical, 2)
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

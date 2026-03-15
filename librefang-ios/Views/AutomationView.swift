import SwiftUI

private enum AutomationMonitorScope: String, CaseIterable, Identifiable {
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
                AutomationScoreboard(vm: vm)
                    .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
            }

            Section("Filter") {
                Picker("Scope", selection: $scope) {
                    ForEach(AutomationMonitorScope.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
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

    @ViewBuilder
    private var workflowsSection: some View {
        if !filteredWorkflows.isEmpty {
            Section {
                ForEach(filteredWorkflows) { workflow in
                    WorkflowDefinitionRow(
                        workflow: workflow,
                        failedRuns: vm.workflowRuns.filter { $0.workflowName == workflow.name && $0.state == .failed }.count,
                        runningRuns: vm.workflowRuns.filter { $0.workflowName == workflow.name && $0.state == .running }.count
                    )
                }
            } header: {
                Text("Workflows")
            } footer: {
                Text("\(vm.workflowCount) definitions, \(vm.recentWorkflowRunCount) recent runs cached from the server")
            }
        }
    }

    @ViewBuilder
    private var workflowRunsSection: some View {
        if !filteredWorkflowRuns.isEmpty {
            Section {
                ForEach(filteredWorkflowRuns.prefix(10)) { run in
                    WorkflowRunRow(run: run)
                }
            } header: {
                Text("Recent Runs")
            } footer: {
                Text("\(vm.failedWorkflowRunCount) failed, \(vm.runningWorkflowRunCount) still running")
            }
        }
    }

    @ViewBuilder
    private var triggersSection: some View {
        if !filteredTriggers.isEmpty {
            Section {
                ForEach(filteredTriggers) { trigger in
                    TriggerRow(trigger: trigger, agentName: agentName(for: trigger.agentId))
                }
            } header: {
                Text("Triggers")
            } footer: {
                Text("\(vm.enabledTriggerCount) enabled, \(vm.exhaustedTriggerCount) exhausted")
            }
        }
    }

    @ViewBuilder
    private var schedulesSection: some View {
        if !filteredSchedules.isEmpty {
            Section {
                ForEach(filteredSchedules) { schedule in
                    ScheduleRow(schedule: schedule, agentName: agentName(for: schedule.agentId))
                }
            } header: {
                Text("Schedules")
            } footer: {
                Text("\(vm.enabledScheduleCount) enabled, \(vm.pausedScheduleCount) paused")
            }
        }
    }

    @ViewBuilder
    private var cronJobsSection: some View {
        if !filteredCronJobs.isEmpty {
            Section {
                ForEach(filteredCronJobs) { job in
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
                Text("\(vm.enabledCronJobCount) enabled, \(vm.pausedCronJobCount) paused, \(vm.stalledCronJobCount) missing next run")
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
            ViewThatFits(in: .horizontal) {
                HStack {
                    summaryBlock
                    Spacer()
                    statusBlock
                }

                VStack(alignment: .leading, spacing: 8) {
                    summaryBlock
                    statusBlock
                }
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
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    summaryBlock
                    Spacer()
                    PresentationToneBadge(text: run.state.label, tone: tone)
                }

                VStack(alignment: .leading, spacing: 8) {
                    summaryBlock
                    PresentationToneBadge(text: run.state.label, tone: tone)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    facts
                }

                VStack(alignment: .leading, spacing: 4) {
                    facts
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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
            ViewThatFits(in: .horizontal) {
                HStack {
                    summaryBlock
                    Spacer()
                    PresentationToneBadge(text: statusLabel, tone: tone)
                }

                VStack(alignment: .leading, spacing: 8) {
                    summaryBlock
                    PresentationToneBadge(text: statusLabel, tone: tone)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    facts
                }

                VStack(alignment: .leading, spacing: 4) {
                    facts
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

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
            ViewThatFits(in: .horizontal) {
                HStack {
                    summaryBlock
                    Spacer()
                    PresentationToneBadge(
                        text: schedule.enabled
                            ? String(localized: "Enabled")
                            : String(localized: "Paused"),
                        tone: schedule.enabled ? .positive : .warning
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    summaryBlock
                    PresentationToneBadge(
                        text: schedule.enabled
                            ? String(localized: "Enabled")
                            : String(localized: "Paused"),
                        tone: schedule.enabled ? .positive : .warning
                    )
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    facts
                }

                VStack(alignment: .leading, spacing: 4) {
                    facts
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

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
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    summaryBlock
                    Spacer()
                    PresentationToneBadge(text: statusLabel, tone: tone)
                }

                VStack(alignment: .leading, spacing: 8) {
                    summaryBlock
                    PresentationToneBadge(text: statusLabel, tone: tone)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Label(scheduleSummary, systemImage: "calendar.badge.clock")
                Label(actionSummary, systemImage: "paperplane")
                Label(deliverySummary, systemImage: "point.3.filled.connected.trianglepath.dotted")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    timingFacts
                }

                VStack(alignment: .leading, spacing: 4) {
                    timingFacts
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
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

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(job.name)
                .font(.subheadline.weight(.medium))
            Text(agentName ?? job.agentId)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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

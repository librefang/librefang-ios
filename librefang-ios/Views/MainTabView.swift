import SwiftUI

struct MainTabView: View {
    @Environment(\.dependencies) private var deps
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var presentedTarget: AppShortcutLaunchTarget?
    @State private var incidentCue: ActiveIncidentCue?
    @State private var hasObservedCriticalState = false
    @State private var handoffCue: ActiveHandoffCue?
    @State private var hasObservedCheckInState = false

    private var vm: DashboardViewModel { deps.dashboardViewModel }
    private var watchedAgents: [Agent] {
        deps.agentWatchlistStore.watchedAgents(from: vm.agents)
    }
    private var visibleMonitoringAlerts: [MonitoringAlertItem] {
        deps.incidentStateStore.visibleAlerts(from: vm.monitoringAlerts)
    }
    private var visibleCriticalAlerts: [MonitoringAlertItem] {
        visibleMonitoringAlerts.filter { $0.severity == .critical }
    }
    private var activeMutedAlertCount: Int {
        deps.incidentStateStore.activeMutedAlerts(from: vm.monitoringAlerts).count
    }
    private var visibleCriticalAlertCount: Int {
        visibleCriticalAlerts.count
    }
    private var handoffCheckInStatus: HandoffCheckInStatus? {
        deps.onCallHandoffStore.latestCheckInStatus
    }
    private var handoffBannerStatus: HandoffCheckInStatus? {
        guard let handoffCheckInStatus, handoffCheckInStatus.state != .scheduled else { return nil }
        return handoffCheckInStatus
    }
    private var latestFollowUpStatuses: [HandoffFollowUpStatus] {
        deps.onCallHandoffStore.latestFollowUpStatuses
    }
    private var pendingLatestFollowUpStatuses: [HandoffFollowUpStatus] {
        latestFollowUpStatuses.filter { !$0.isCompleted }
    }
    private var pendingLatestFollowUpCount: Int {
        pendingLatestFollowUpStatuses.count
    }
    private var pendingLatestFollowUpPreview: String? {
        let preview = pendingLatestFollowUpStatuses.prefix(2).map(\.item).joined(separator: " • ")
        return preview.isEmpty ? nil : preview
    }
    private var isCurrentSnapshotAcknowledged: Bool {
        deps.incidentStateStore.isCurrentSnapshotAcknowledged(alerts: vm.monitoringAlerts)
    }
    private var preferredOnCallSurface: OnCallSurfacePreference {
        deps.onCallFocusStore.preferredSurface
    }
    private var showsForegroundCues: Bool {
        deps.onCallFocusStore.showsForegroundCues
    }
    private var watchedAttentionItems: [AgentAttentionItem] {
        watchedAgents
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
    private var watchedIssueCount: Int {
        watchedAttentionItems.count
    }
    private var watchedDiagnosticPriorityItems: [OnCallPriorityItem] {
        watchedAgentDiagnosticPriorityItems(
            agents: watchedAgents,
            summaries: deps.watchedAgentDiagnosticsStore.summaries
        )
    }
    private var criticalTrackingState: CriticalTrackingState {
        CriticalTrackingState(
            count: visibleCriticalAlertCount,
            signature: visibleCriticalAlerts
                .map { "\($0.id)|\($0.title)|\($0.detail)" }
                .sorted()
                .joined(separator: "||")
        )
    }
    private var handoffCheckInTrackingState: HandoffCheckInTrackingState {
        guard let handoffBannerStatus else { return .init(level: 0, pendingFollowUpCount: 0, signature: "none") }
        return HandoffCheckInTrackingState(
            level: handoffBannerStatus.state == .overdue ? 2 : 1,
            pendingFollowUpCount: pendingLatestFollowUpCount,
            signature: "\(handoffBannerStatus.state.label)|\(handoffBannerStatus.dueDate.timeIntervalSinceReferenceDate.rounded())|\(pendingLatestFollowUpStatuses.map(\.id).sorted().joined(separator: "|"))"
        )
    }
    private var onCallPriorityItems: [OnCallPriorityItem] {
        mergeOnCallPriorityItems(
            vm.onCallPriorityItems(
                visibleAlerts: visibleMonitoringAlerts,
                watchedAttentionItems: watchedAttentionItems,
                handoffCheckInStatus: handoffCheckInStatus,
                handoffFollowUpStatuses: latestFollowUpStatuses
            ),
            with: watchedDiagnosticPriorityItems
        )
    }
    private var handoffText: String {
        vm.onCallHandoffText(
            visibleAlerts: visibleMonitoringAlerts,
            watchedAttentionItems: watchedAttentionItems,
            mutedAlertCount: activeMutedAlertCount,
            isAcknowledged: isCurrentSnapshotAcknowledged,
            handoffCheckInStatus: handoffCheckInStatus,
            handoffFollowUpStatuses: latestFollowUpStatuses
        )
    }
    private var overlaySummaryLine: String {
        if !deps.networkMonitor.isConnected {
            return String(localized: "Monitoring data may be stale while this iPhone is offline.")
        }
        if visibleCriticalAlertCount > 0 {
            return visibleCriticalAlertCount == 1
                ? String(localized: "A critical incident is active and ready for triage.")
                : String(localized: "\(visibleCriticalAlertCount) critical incidents are active and ready for triage.")
        }
        if let handoffBannerStatus {
            return handoffBannerStatus.summary
        }
        if pendingLatestFollowUpCount > 0 {
            return pendingLatestFollowUpCount == 1
                ? String(localized: "1 handoff follow-up is still open on this phone.")
                : String(localized: "\(pendingLatestFollowUpCount) handoff follow-ups are still open on this phone.")
        }
        return String(localized: "Use the current snapshot to jump straight into the most relevant surface.")
    }

    var body: some View {
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
        .safeAreaInset(edge: .top, spacing: 0) {
            topOverlay
        }
        .onChange(of: selectedTab) {
            HapticManager.selection()
        }
        .onAppear {
            deps.dashboardViewModel.startAutoRefresh(interval: storedRefreshInterval)
            deps.appShortcutLaunchStore.refreshFromDefaults()
            handlePendingAppShortcut()
            Task { await deps.onCallNotificationManager.refreshAuthorizationStatus() }
            Task { await refreshWatchedAgentDiagnostics() }
        }
        .onChange(of: criticalTrackingState) { oldValue, newValue in
            handleCriticalTrackingChange(from: oldValue, to: newValue)
        }
        .onChange(of: handoffCheckInTrackingState) { oldValue, newValue in
            handleHandoffCheckInChange(from: oldValue, to: newValue)
        }
        .onChange(of: isCurrentSnapshotAcknowledged) { _, isAcknowledged in
            if isAcknowledged {
                incidentCue = nil
            }
        }
        .onChange(of: showsForegroundCues) { _, isEnabled in
            if !isEnabled {
                incidentCue = nil
                handoffCue = nil
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                deps.dashboardViewModel.startAutoRefresh(interval: storedRefreshInterval)
                Task {
                    await deps.dashboardViewModel.refresh()
                    await deps.onCallNotificationManager.refreshAuthorizationStatus()
                    await deps.onCallNotificationManager.cancelPendingReminder()
                    await MainActor.run {
                        deps.appShortcutLaunchStore.refreshFromDefaults()
                        handlePendingAppShortcut()
                    }
                }
            case .background:
                deps.dashboardViewModel.stopAutoRefresh()
                incidentCue = nil
                handoffCue = nil
                Task {
                    await deps.onCallNotificationManager.armStandbyReminder(snapshot: reminderSnapshot)
                }
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            deps.appShortcutLaunchStore.refreshFromDefaults()
            handlePendingAppShortcut()
        }
        .onChange(of: vm.lastRefresh) { _, _ in
            Task { await refreshWatchedAgentDiagnostics() }
        }
        .onChange(of: deps.agentWatchlistStore.watchedAgentIDs) { _, _ in
            Task { await refreshWatchedAgentDiagnostics() }
        }
        .task(id: incidentCue?.id) {
            guard let cueID = incidentCue?.id else { return }
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard incidentCue?.id == cueID else { return }
            incidentCue = nil
        }
        .task(id: handoffCue?.id) {
            guard let cueID = handoffCue?.id else { return }
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard handoffCue?.id == cueID else { return }
            handoffCue = nil
        }
        .sheet(item: $presentedTarget) { target in
            NavigationStack {
                monitoringRouteView(for: target)
            }
        }
    }

    @MainActor
    private func refreshWatchedAgentDiagnostics() async {
        await deps.watchedAgentDiagnosticsStore.refresh(
            api: deps.apiClient,
            agents: watchedAgents,
            catalogModels: deps.dashboardViewModel.catalogModels
        )
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
            isAcknowledged: isCurrentSnapshotAcknowledged,
            handoffCheckInStatus: handoffCheckInStatus,
            handoffFollowUpStatuses: latestFollowUpStatuses
        )
    }

    @ViewBuilder
    private var topOverlay: some View {
        if !deps.networkMonitor.isConnected
            || visibleCriticalAlertCount > 0
            || handoffBannerStatus != nil
            || (incidentCue != nil && showsForegroundCues)
            || (handoffCue != nil && showsForegroundCues) {
            VStack(spacing: 8) {
                if !deps.networkMonitor.isConnected {
                    OfflineBanner()
                } else if visibleCriticalAlertCount > 0 {
                    Button {
                        openPreferredSurface()
                    } label: {
                        if isCurrentSnapshotAcknowledged {
                            AcknowledgedIncidentBanner(count: visibleCriticalAlertCount, mutedCount: activeMutedAlertCount)
                        } else {
                            CriticalIncidentBanner(count: visibleCriticalAlertCount, mutedCount: activeMutedAlertCount)
                        }
                    }
                    .buttonStyle(.plain)
                } else if let handoffBannerStatus {
                    Button {
                        openHandoffCenter()
                    } label: {
                        HandoffCheckInBanner(
                            status: handoffBannerStatus,
                            pendingFollowUpCount: pendingLatestFollowUpCount
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let activeIncidentCue = incidentCue, showsForegroundCues {
                    IncidentCueBanner(
                        cue: activeIncidentCue,
                        onOpen: { openPreferredSurface() },
                        onAcknowledge: {
                            deps.incidentStateStore.acknowledgeCurrentSnapshot(alerts: vm.monitoringAlerts)
                            incidentCue = nil
                        },
                        onDismiss: {
                            incidentCue = nil
                        }
                    )
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                } else if let handoffCue, showsForegroundCues {
                    HandoffCueBanner(
                        cue: handoffCue,
                        onOpen: { openHandoffCenter() },
                        onDismiss: {
                            self.handoffCue = nil
                        }
                    )
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                OperatorOverlayDeck(
                    summary: overlaySummaryLine,
                    criticalCount: visibleCriticalAlertCount,
                    approvalCount: vm.pendingApprovalCount,
                    watchIssueCount: watchedIssueCount,
                    sessionCount: vm.sessionAttentionCount,
                    pendingFollowUpCount: pendingLatestFollowUpCount,
                    preferredSurfaceLabel: preferredOnCallSurface.label,
                    isOffline: !deps.networkMonitor.isConnected,
                    actions: overlayQuickActions
                )
                    .padding(.horizontal, 12)
            }
            .padding(.top, 4)
            .padding(.bottom, 8)
            .background(.bar)
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: incidentCue?.id)
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: handoffCue?.id)
        }
    }

    @ViewBuilder
    private func monitoringRouteView(for route: AppShortcutLaunchTarget) -> some View {
        switch route {
        case .surface(.onCall):
            OnCallView()
        case .surface(.approvals):
            ApprovalsView()
        case .surface(.handoffCenter):
            HandoffCenterView(
                summary: handoffText,
                queueCount: onCallPriorityItems.count,
                criticalCount: visibleCriticalAlertCount,
                liveAlertCount: visibleMonitoringAlerts.count
            )
        case .surface(.incidents):
            IncidentsView()
        case .surface(.nightWatch):
            NightWatchView()
        case .surface(.standbyDigest):
            StandbyDigestView()
        case .surface(.automation):
            AutomationView()
        case .surface(.diagnostics):
            DiagnosticsView()
        case .surface(.integrations):
            IntegrationsView()
        case .integrationsAttention:
            IntegrationsView(initialScope: .attention)
        case .integrationsSearch(let query):
            IntegrationsView(initialSearchText: query, initialScope: .attention)
        case .agent(let id):
            if let agent = vm.agents.first(where: { $0.id == id }) {
                AgentDetailView(agent: agent)
            } else {
                ContentUnavailableView(
                    "Agent Unavailable",
                    systemImage: "cpu",
                    description: Text("The requested agent is not available in the current dashboard snapshot.")
                )
            }
        case .sessionsAttention:
            SessionsView(initialFilter: .attention)
        case .sessionsSearch(let query):
            SessionsView(initialSearchText: query, initialFilter: .attention)
        case .eventsCritical:
            EventsView(api: deps.apiClient, initialScope: .critical)
        case .eventsSearch(let query):
            EventsView(api: deps.apiClient, initialSearchText: query, initialScope: .critical)
        }
    }

    private func handleCriticalTrackingChange(from oldValue: CriticalTrackingState, to newValue: CriticalTrackingState) {
        guard scenePhase == .active else {
            hasObservedCriticalState = true
            return
        }

        guard showsForegroundCues else {
            incidentCue = nil
            hasObservedCriticalState = true
            return
        }

        guard hasObservedCriticalState else {
            hasObservedCriticalState = true
            return
        }

        guard !isCurrentSnapshotAcknowledged else {
            incidentCue = nil
            return
        }

        guard newValue.count > 0 else {
            incidentCue = nil
            return
        }

        let queueIntensified = newValue.count >= oldValue.count
        let queueChanged = newValue.signature != oldValue.signature

        guard queueChanged, queueIntensified else { return }

        let leadAlert = visibleCriticalAlerts.first
        let fallbackLeadTitle = String(localized: "Critical queue changed")
        let followUpPrompt = String(localized: "Open the on-call surface to inspect the latest pressure.")
        incidentCue = ActiveIncidentCue(
            id: newValue.signature,
            title: newValue.count == 1
                ? (leadAlert?.title ?? String(localized: "Critical incident changed"))
                : String(localized: "\(newValue.count) critical incidents changed"),
            detail: newValue.count == 1
                ? (leadAlert?.detail ?? String(localized: "Open the on-call surface to review the new state."))
                : [leadAlert?.title ?? fallbackLeadTitle, followUpPrompt].joined(separator: " · ")
        )
        HapticManager.notification(.error)
    }

    private func handleHandoffCheckInChange(from oldValue: HandoffCheckInTrackingState, to newValue: HandoffCheckInTrackingState) {
        guard scenePhase == .active else {
            hasObservedCheckInState = true
            return
        }

        guard showsForegroundCues else {
            handoffCue = nil
            hasObservedCheckInState = true
            return
        }

        guard hasObservedCheckInState else {
            hasObservedCheckInState = true
            return
        }

        guard visibleCriticalAlertCount == 0 else {
            handoffCue = nil
            return
        }

        let checkInEscalated = newValue.level > oldValue.level
        let followUpsIntensified = newValue.pendingFollowUpCount > oldValue.pendingFollowUpCount

        guard newValue.level > 0, newValue.signature != oldValue.signature, (checkInEscalated || followUpsIntensified) else {
            if newValue.level == 0 {
                handoffCue = nil
            }
            return
        }

        guard let handoffBannerStatus else { return }

        handoffCue = ActiveHandoffCue(
            id: newValue.signature,
            title: handoffCueTitle(for: handoffBannerStatus, pendingFollowUpCount: pendingLatestFollowUpCount),
            detail: handoffCueDetail(for: handoffBannerStatus)
        )
        HapticManager.notification(handoffBannerStatus.state == .overdue ? .error : .warning)
    }

    private func handoffCueTitle(for status: HandoffCheckInStatus, pendingFollowUpCount: Int) -> String {
        guard pendingFollowUpCount > 0 else {
            return status.state == .overdue ? String(localized: "Handoff check-in overdue") : String(localized: "Handoff check-in due soon")
        }

        let followUpSummary = pendingFollowUpCount == 1
            ? String(localized: "1 follow-up open")
            : String(localized: "\(pendingFollowUpCount) follow-ups open")

        return status.state == .overdue
            ? String(localized: "Handoff overdue · \(followUpSummary)")
            : String(localized: "Handoff due soon · \(followUpSummary)")
    }

    private func handoffCueDetail(for status: HandoffCheckInStatus) -> String {
        var segments = [status.dueLabel]
        if pendingLatestFollowUpCount > 0 {
            let followUpSummary = pendingLatestFollowUpCount == 1
                ? String(localized: "1 handoff follow-up still open")
                : String(localized: "\(pendingLatestFollowUpCount) handoff follow-ups still open")

            if let pendingLatestFollowUpPreview {
                segments.append(String(localized: "\(followUpSummary): \(pendingLatestFollowUpPreview)"))
            } else {
                segments.append(followUpSummary)
            }
        } else {
            segments.append(status.summary)
        }
        return segments.joined(separator: " · ")
    }

    private func openPreferredSurface() {
        switch preferredOnCallSurface {
        case .onCall:
            openSurface(.onCall)
        case .nightWatch:
            openSurface(.nightWatch)
        case .standbyDigest:
            openSurface(.standbyDigest)
        }
    }

    private func openHandoffCenter() {
        openSurface(.handoffCenter)
    }

    private func openSurface(_ surface: AppShortcutSurface) {
        openRoute(.surface(surface))
    }

    private func openAgent(_ id: String) {
        openRoute(.agent(id))
    }

    private func openRoute(_ route: AppShortcutLaunchTarget) {
        incidentCue = nil
        handoffCue = nil
        presentedTarget = route
    }

    private func handlePendingAppShortcut() {
        guard let target = deps.appShortcutLaunchStore.consumePendingTarget() else { return }
        openRoute(target)
    }

    private var overlayQuickActions: [OperatorOverlayQuickAction] {
        var actions = [
            OperatorOverlayQuickAction(
                title: preferredOnCallSurface.label,
                systemImage: preferredSurfaceSymbolName,
                tone: visibleCriticalAlertCount > 0 ? .critical : .neutral,
                badgeText: visibleCriticalAlertCount > 0
                    ? (visibleCriticalAlertCount == 1 ? String(localized: "1 critical") : String(localized: "\(visibleCriticalAlertCount) critical"))
                    : nil,
                action: openPreferredSurface
            )
        ]

        if visibleMonitoringAlerts.count > 0 {
            actions.append(
                OperatorOverlayQuickAction(
                    title: String(localized: "Incidents"),
                    systemImage: "bell.badge",
                    tone: visibleCriticalAlertCount > 0 ? .critical : .warning,
                    badgeText: visibleMonitoringAlerts.count == 1
                        ? String(localized: "1 alert")
                        : String(localized: "\(visibleMonitoringAlerts.count) alerts"),
                    action: { openSurface(.incidents) }
                )
            )
        }

        if vm.pendingApprovalCount > 0 {
            actions.append(
                OperatorOverlayQuickAction(
                    title: String(localized: "Approvals"),
                    systemImage: "checkmark.shield",
                    tone: .warning,
                    badgeText: vm.pendingApprovalCount == 1
                        ? String(localized: "1 pending")
                        : String(localized: "\(vm.pendingApprovalCount) pending"),
                    action: { openSurface(.approvals) }
                )
            )
        }

        if handoffBannerStatus != nil || pendingLatestFollowUpCount > 0 {
            actions.append(
                OperatorOverlayQuickAction(
                    title: String(localized: "Handoff"),
                    systemImage: "person.2.wave.2",
                    tone: handoffBannerStatus?.state == .overdue ? .critical : .warning,
                    badgeText: pendingLatestFollowUpCount > 0
                        ? (pendingLatestFollowUpCount == 1 ? String(localized: "1 open") : String(localized: "\(pendingLatestFollowUpCount) open"))
                        : nil,
                    action: openHandoffCenter
                )
            )
        }

        if vm.sessionAttentionCount > 0 {
            actions.append(
                OperatorOverlayQuickAction(
                    title: String(localized: "Sessions"),
                    systemImage: "text.bubble",
                    tone: .warning,
                    badgeText: vm.sessionAttentionCount == 1
                        ? String(localized: "1 hotspot")
                        : String(localized: "\(vm.sessionAttentionCount) hotspots"),
                    action: { openRoute(.sessionsAttention) }
                )
            )
        }

        if !deps.networkMonitor.isConnected || vm.runtimeAlertCount > 0 {
            actions.append(
                OperatorOverlayQuickAction(
                    title: String(localized: "Diagnostics"),
                    systemImage: "stethoscope",
                    tone: !deps.networkMonitor.isConnected ? .critical : .warning,
                    badgeText: vm.runtimeAlertCount > 0
                        ? (vm.runtimeAlertCount == 1 ? String(localized: "1 issue") : String(localized: "\(vm.runtimeAlertCount) issues"))
                        : nil,
                    action: { openSurface(.diagnostics) }
                )
            )
        }

        return actions
    }

    private var preferredSurfaceSymbolName: String {
        switch preferredOnCallSurface {
        case .onCall:
            return "waveform.path.ecg"
        case .nightWatch:
            return "moon.stars"
        case .standbyDigest:
            return "rectangle.compress.vertical"
        }
    }
}

private struct CriticalTrackingState: Equatable {
    let count: Int
    let signature: String
}

private struct ActiveIncidentCue: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
}

private struct HandoffCheckInTrackingState: Equatable {
    let level: Int
    let pendingFollowUpCount: Int
    let signature: String
}

private struct ActiveHandoffCue: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
}

private struct OperatorOverlayDeck: View {
    let summary: String
    let criticalCount: Int
    let approvalCount: Int
    let watchIssueCount: Int
    let sessionCount: Int
    let pendingFollowUpCount: Int
    let preferredSurfaceLabel: String
    let isOffline: Bool
    let actions: [OperatorOverlayQuickAction]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Operator Deck"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 8) {
                if isOffline {
                    GlassCapsuleBadge(
                        text: String(localized: "Offline"),
                        foregroundStyle: .primary,
                        backgroundOpacity: 0.10
                    )
                }
                if criticalCount > 0 {
                    GlassCapsuleBadge(
                        text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                        foregroundStyle: .primary,
                        backgroundOpacity: 0.10
                    )
                }
                if approvalCount > 0 {
                    GlassCapsuleBadge(
                        text: approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                        foregroundStyle: .primary,
                        backgroundOpacity: 0.10
                    )
                }
                if watchIssueCount > 0 {
                    GlassCapsuleBadge(
                        text: watchIssueCount == 1 ? String(localized: "1 watch issue") : String(localized: "\(watchIssueCount) watch issues"),
                        foregroundStyle: .primary,
                        backgroundOpacity: 0.10
                    )
                }
                if sessionCount > 0 {
                    GlassCapsuleBadge(
                        text: sessionCount == 1 ? String(localized: "1 session hotspot") : String(localized: "\(sessionCount) session hotspots"),
                        foregroundStyle: .primary,
                        backgroundOpacity: 0.10
                    )
                }
                if pendingFollowUpCount > 0 {
                    GlassCapsuleBadge(
                        text: pendingFollowUpCount == 1 ? String(localized: "1 follow-up open") : String(localized: "\(pendingFollowUpCount) follow-ups open"),
                        foregroundStyle: .primary,
                        backgroundOpacity: 0.10
                    )
                }
                GlassCapsuleBadge(
                    text: preferredSurfaceLabel,
                    foregroundStyle: .secondary,
                    backgroundOpacity: 0.08
                )
            }

            if !actions.isEmpty {
                Divider()
                    .overlay(.white.opacity(0.08))

                FlowLayout(spacing: 8) {
                    ForEach(actions) { action in
                        Button(action: action.action) {
                            HStack(spacing: 8) {
                                Image(systemName: action.systemImage)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))

                                Text(action.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                if let badgeText = action.badgeText {
                                    Text(badgeText)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(action.tone.color)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.white.opacity(0.96), in: Capsule())
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OperatorOverlayQuickAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let tone: PresentationTone
    let badgeText: String?
    let action: () -> Void
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

private struct MainTabStatusBanner<Summary: View, Accessory: View>: View {
    let tint: Color
    let summary: Summary
    let accessory: Accessory

    init(
        tint: Color,
        @ViewBuilder summary: () -> Summary,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.tint = tint
        self.summary = summary()
        self.accessory = accessory()
    }

    var body: some View {
        ResponsiveAccessoryRow(verticalSpacing: 8) {
            summary
        } accessory: {
            accessory
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.92))
    }
}

private struct CriticalIncidentBanner: View {
    let count: Int
    let mutedCount: Int

    var body: some View {
        MainTabStatusBanner(tint: .red) {
            summaryLabel
        } accessory: {
            bannerBadges
        }
    }

    private var summaryLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.badge.fill")
                .font(.caption)
            Text(count == 1 ? String(localized: "1 critical incident active") : String(localized: "\(count) critical incidents active"))
                .font(.caption.weight(.semibold))
                .lineLimit(2)
        }
    }

    private var bannerBadges: some View {
        FlowLayout(spacing: 8) {
            mutedBadge
            GlassCapsuleBadge(text: String(localized: "On Call"), backgroundOpacity: 0.18)
        }
    }

    @ViewBuilder
    private var mutedBadge: some View {
        if mutedCount > 0 {
            GlassCapsuleBadge(text: String(localized: "\(mutedCount) muted"))
        }
    }
}

private struct HandoffCheckInBanner: View {
    let status: HandoffCheckInStatus
    let pendingFollowUpCount: Int

    private var tint: Color {
        status.state == .overdue ? .red : .orange
    }

    var body: some View {
        MainTabStatusBanner(tint: tint) {
            summaryLabel
        } accessory: {
            bannerBadges
        }
    }

    private var summaryLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.caption)
            Text(status.state == .overdue ? String(localized: "Handoff check-in overdue") : String(localized: "Handoff check-in due soon"))
                .font(.caption.weight(.semibold))
                .lineLimit(2)
        }
    }

    private var bannerBadges: some View {
        FlowLayout(spacing: 8) {
            GlassCapsuleBadge(text: status.window.label)
            pendingFollowUpBadge
            GlassCapsuleBadge(text: String(localized: "Handoff"), backgroundOpacity: 0.18)
        }
    }

    @ViewBuilder
    private var pendingFollowUpBadge: some View {
        if pendingFollowUpCount > 0 {
            GlassCapsuleBadge(
                text: pendingFollowUpCount == 1 ? String(localized: "1 open") : String(localized: "\(pendingFollowUpCount) open")
            )
        }
    }
}

private struct AcknowledgedIncidentBanner: View {
    let count: Int
    let mutedCount: Int

    var body: some View {
        MainTabStatusBanner(tint: .orange) {
            summaryLabel
        } accessory: {
            bannerBadges
        }
    }

    private var summaryLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.caption)
            Text(count == 1 ? String(localized: "1 critical incident acknowledged") : String(localized: "\(count) critical incidents acknowledged"))
                .font(.caption.weight(.semibold))
                .lineLimit(2)
        }
    }

    private var bannerBadges: some View {
        FlowLayout(spacing: 8) {
            mutedBadge
            GlassCapsuleBadge(text: String(localized: "On Call"), backgroundOpacity: 0.18)
        }
    }

    @ViewBuilder
    private var mutedBadge: some View {
        if mutedCount > 0 {
            GlassCapsuleBadge(text: String(localized: "\(mutedCount) muted"))
        }
    }
}

private struct IncidentCueBanner: View {
    let cue: ActiveIncidentCue
    let onOpen: () -> Void
    let onAcknowledge: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResponsiveAccessoryRow(horizontalAlignment: .top, verticalSpacing: 8) {
                cueSummary
            } accessory: {
                dismissButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            ResponsiveInlineGroup(horizontalSpacing: 10, verticalSpacing: 8) {
                acknowledgeButton
                openButton
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color(red: 0.38, green: 0.08, blue: 0.10), Color(red: 0.17, green: 0.05, blue: 0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }

    private var cueSummary: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.title3)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 4) {
                Text(cue.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(cue.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(3)
            }
        }
    }

    private var dismissButton: some View {
        GlassCircleIconButton(systemImage: "xmark", action: onDismiss)
    }

    private var acknowledgeButton: some View {
        Button(action: onAcknowledge) {
            Label("Acknowledge", systemImage: "checkmark.seal")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassPanelButtonStyle(fillOpacity: 0.12))
    }

    private var openButton: some View {
        Button(action: onOpen) {
            Label("Open", systemImage: "arrow.up.forward.app")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassPanelButtonStyle(fillOpacity: 0.22))
    }
}

private struct HandoffCueBanner: View {
    let cue: ActiveHandoffCue
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResponsiveAccessoryRow(horizontalAlignment: .top, verticalSpacing: 8) {
                cueSummary
            } accessory: {
                dismissButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Button(action: onOpen) {
                Label("Open Handoff Center", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassPanelButtonStyle(fillOpacity: 0.20))
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color(red: 0.42, green: 0.19, blue: 0.04), Color(red: 0.18, green: 0.08, blue: 0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }

    private var cueSummary: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "timer")
                .font(.title3)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 4) {
                Text(cue.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(cue.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(3)
            }
        }
    }

    private var dismissButton: some View {
        GlassCircleIconButton(systemImage: "xmark", action: onDismiss)
    }
}

import SwiftUI

struct MainTabView: View {
    private static let maxPendingShortcutAge: TimeInterval = 10
    private static let pendingShortcutRetryDelay: TimeInterval = 0.5
    private static let routePresentationCooldown: TimeInterval = 1

    @Environment(\.dependencies) private var deps
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var handledPendingShortcutToken: String?
    @State private var isRoutePresentationSuspended = true
    @State private var routePresentationBlockedUntil = Date.distantPast
    @State private var pendingShortcutRetryTask: Task<Void, Never>?
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
    private var overviewTabSignalCount: Int {
        visibleCriticalAlertCount + watchedIssueCount
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

    private var shouldShowOverlayDeck: Bool {
        !deps.networkMonitor.isConnected
    }
    private var overlaySectionCount: Int {
        [
            !deps.networkMonitor.isConnected || visibleCriticalAlertCount > 0 || handoffBannerStatus != nil,
            (incidentCue != nil && showsForegroundCues) || (handoffCue != nil && showsForegroundCues),
            shouldShowOverlayDeck
        ]
        .filter { $0 }
        .count
    }

    var body: some View {
        presentedMainContent
    }

    private var presentedMainContent: some View {
        mainContent
            .sheet(item: $presentedTarget) { target in
                NavigationStack {
                    monitoringRouteView(for: target)
                }
            }
    }

    private var mainContent: some View {
        taskManagedContent
    }

    private var taskManagedContent: some View {
        lifecycleManagedContent
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
    }

    private var lifecycleManagedContent: some View {
        chromeContent
            .onAppear {
                handleMainViewAppear()
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
                handleScenePhaseChange(newPhase)
            }
            .onReceive(NotificationCenter.default.publisher(for: .appShortcutLaunchQueued)) { _ in
                deps.appShortcutLaunchStore.refreshFromDefaults()
                handlePendingAppShortcutIfNeeded()
            }
            .onChange(of: vm.isLoading) { _, isLoading in
                updateRoutePresentationWindow(for: isLoading)
            }
            .onChange(of: presentedTarget?.id) { _, presentedID in
                if presentedID == nil {
                    handlePendingAppShortcutIfNeeded()
                }
            }
            .onChange(of: vm.lastRefresh) { _, _ in
                Task { await refreshWatchedAgentDiagnostics() }
            }
            .onChange(of: deps.agentWatchlistStore.watchedAgentIDs) { _, _ in
                Task { await refreshWatchedAgentDiagnostics() }
            }
    }

    private var chromeContent: some View {
        tabContainer
            .safeAreaInset(edge: .top, spacing: 0) {
                topOverlay
            }
            .onChange(of: selectedTab) {
                HapticManager.selection()
            }
    }

    private var tabContainer: some View {
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

    private var settingsTabSignalCount: Int {
        pendingLatestFollowUpCount + activeMutedAlertCount
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
                    OfflineBanner(
                        runtimeIssueCount: vm.runtimeAlertCount,
                        approvalCount: vm.pendingApprovalCount,
                        followUpCount: pendingLatestFollowUpCount
                    )
                } else if visibleCriticalAlertCount > 0 {
                    Button {
                        openPreferredSurface()
                    } label: {
                        if isCurrentSnapshotAcknowledged {
                            AcknowledgedIncidentBanner(
                                count: visibleCriticalAlertCount,
                                mutedCount: activeMutedAlertCount,
                                approvalCount: vm.pendingApprovalCount,
                                watchIssueCount: watchedIssueCount,
                                sessionCount: vm.sessionAttentionCount
                            )
                        } else {
                            CriticalIncidentBanner(
                                count: visibleCriticalAlertCount,
                                mutedCount: activeMutedAlertCount,
                                approvalCount: vm.pendingApprovalCount,
                                watchIssueCount: watchedIssueCount,
                                sessionCount: vm.sessionAttentionCount
                            )
                        }
                    }
                    .buttonStyle(.plain)
                } else if let handoffBannerStatus {
                    Button {
                        openHandoffCenter()
                    } label: {
                        HandoffCheckInBanner(
                            status: handoffBannerStatus,
                            pendingFollowUpCount: pendingLatestFollowUpCount,
                            watchIssueCount: watchedIssueCount,
                            sessionCount: vm.sessionAttentionCount
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let activeIncidentCue = incidentCue, showsForegroundCues {
                    IncidentCueBanner(
                        cue: activeIncidentCue,
                        criticalCount: visibleCriticalAlertCount,
                        mutedCount: activeMutedAlertCount,
                        approvalCount: vm.pendingApprovalCount,
                        sessionCount: vm.sessionAttentionCount,
                        watchIssueCount: watchedIssueCount,
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
                        dueLabel: handoffBannerStatus?.dueLabel,
                        pendingFollowUpCount: pendingLatestFollowUpCount,
                        watchIssueCount: watchedIssueCount,
                        sessionCount: vm.sessionAttentionCount,
                        onOpen: { openHandoffCenter() },
                        onDismiss: {
                            self.handoffCue = nil
                        }
                    )
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if shouldShowOverlayDeck {
                    OperatorOverlayDeck(
                        summary: overlaySummaryLine,
                        sectionCount: overlaySectionCount,
                        criticalCount: visibleCriticalAlertCount,
                        approvalCount: vm.pendingApprovalCount,
                        watchIssueCount: watchedIssueCount,
                        sessionCount: vm.sessionAttentionCount,
                        pendingFollowUpCount: pendingLatestFollowUpCount,
                        mutedAlertCount: activeMutedAlertCount,
                        preferredSurfaceLabel: preferredOnCallSurface.label,
                        isOffline: !deps.networkMonitor.isConnected,
                        isSnapshotAcknowledged: isCurrentSnapshotAcknowledged,
                        overviewCount: overviewTabSignalCount,
                        agentsCount: vm.issueAgentCount,
                        runtimeCount: runtimeAlertBadge,
                        budgetCount: budgetAlertBadge,
                        settingsCount: settingsTabSignalCount,
                        actions: overlayQuickActions
                    )
                    .padding(.horizontal, 12)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 8)
            .background(.bar)
            .monitoringRefreshInteractionGate(
                isRefreshing: vm.isLoading,
                restoreDelay: 0.7
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: incidentCue?.id)
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: handoffCue?.id)
        }
    }

    @ViewBuilder
    private func monitoringRouteView(for route: AppShortcutLaunchTarget) -> some View {
        switch route {
        case .surface(.onCall):
            OnCallView()
        case .surface(.agents):
            AgentsView()
        case .surface(.runtime):
            RuntimeView()
        case .surface(.budget):
            BudgetView()
        case .surface(.settings):
            SettingsView()
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
        _ = openRoute(.surface(surface), respectingPresentationGate: false)
    }

    private func openAgent(_ id: String) {
        _ = openRoute(.agent(id), respectingPresentationGate: false)
    }

    @discardableResult
    private func openRoute(
        _ route: AppShortcutLaunchTarget,
        respectingPresentationGate: Bool
    ) -> Bool {
        incidentCue = nil
        handoffCue = nil
        if respectingPresentationGate {
            guard canPresentPendingShortcutRoute else { return false }
        }
        if case .surface(let surface) = route, let tabSelection = surface.tabSelection {
            presentedTarget = nil
            selectedTab = tabSelection
            return true
        }
        presentedTarget = route
        return true
    }

    private func handlePendingAppShortcutIfNeeded() {
        guard let pendingToken = deps.appShortcutLaunchStore.pendingToken else {
            cancelPendingShortcutRetry()
            return
        }

        guard let queuedAt = deps.appShortcutLaunchStore.pendingQueuedAt else {
            deps.appShortcutLaunchStore.discardPendingTarget()
            handledPendingShortcutToken = pendingToken
            cancelPendingShortcutRetry()
            return
        }

        let age = Date().timeIntervalSince(queuedAt)
        guard age <= Self.maxPendingShortcutAge else {
            deps.appShortcutLaunchStore.discardPendingTarget()
            handledPendingShortcutToken = pendingToken
            cancelPendingShortcutRetry()
            return
        }

        guard pendingToken != handledPendingShortcutToken else {
            deps.appShortcutLaunchStore.discardPendingTarget()
            cancelPendingShortcutRetry()
            return
        }

        guard let target = deps.appShortcutLaunchStore.pendingTarget else {
            deps.appShortcutLaunchStore.discardPendingTarget()
            handledPendingShortcutToken = pendingToken
            cancelPendingShortcutRetry()
            return
        }

        if presentedTarget?.id == target.id {
            handledPendingShortcutToken = pendingToken
            deps.appShortcutLaunchStore.discardPendingTarget()
            cancelPendingShortcutRetry()
            return
        }

        guard presentedTarget == nil else {
            cancelPendingShortcutRetry()
            return
        }

        guard !vm.isLoading else {
            cancelPendingShortcutRetry()
            return
        }

        guard !isRoutePresentationSuspended, Date() >= routePresentationBlockedUntil else {
            schedulePendingShortcutRetry(after: max(routePresentationBlockedUntil.timeIntervalSinceNow, Self.pendingShortcutRetryDelay))
            return
        }

        guard openRoute(target, respectingPresentationGate: true) else {
            schedulePendingShortcutRetry()
            return
        }

        handledPendingShortcutToken = pendingToken
        deps.appShortcutLaunchStore.consumePendingTarget()
        cancelPendingShortcutRetry()
    }

    private func handleMainViewAppear() {
        suspendRoutePresentation()
        deps.dashboardViewModel.startAutoRefresh(interval: storedRefreshInterval)
        deps.appShortcutLaunchStore.refreshFromDefaults()
        handlePendingAppShortcutIfNeeded()
        Task { await deps.onCallNotificationManager.refreshAuthorizationStatus() }
        Task { await refreshWatchedAgentDiagnostics() }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            suspendRoutePresentation()
            deps.dashboardViewModel.startAutoRefresh(interval: storedRefreshInterval)
            deps.appShortcutLaunchStore.refreshFromDefaults()
            handlePendingAppShortcutIfNeeded()
            Task {
                await deps.dashboardViewModel.refresh()
                await deps.onCallNotificationManager.refreshAuthorizationStatus()
                await deps.onCallNotificationManager.cancelPendingReminder()
                await MainActor.run {
                    deps.appShortcutLaunchStore.refreshFromDefaults()
                    handlePendingAppShortcutIfNeeded()
                }
            }
        case .background:
            cancelPendingShortcutRetry()
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

    private func updateRoutePresentationWindow(for isLoading: Bool) {
        guard !isLoading else {
            cancelPendingShortcutRetry()
            suspendRoutePresentation()
            return
        }

        isRoutePresentationSuspended = false
        routePresentationBlockedUntil = Date().addingTimeInterval(Self.routePresentationCooldown)
        schedulePendingShortcutRetry(after: max(routePresentationBlockedUntil.timeIntervalSinceNow, 0))
    }

    private func suspendRoutePresentation() {
        isRoutePresentationSuspended = true
        routePresentationBlockedUntil = Date().addingTimeInterval(Self.routePresentationCooldown)
    }

    private var canPresentPendingShortcutRoute: Bool {
        !isRoutePresentationSuspended
            && !vm.isLoading
            && presentedTarget == nil
            && Date() >= routePresentationBlockedUntil
    }

    private func schedulePendingShortcutRetry(after delay: TimeInterval = Self.pendingShortcutRetryDelay) {
        guard deps.appShortcutLaunchStore.pendingToken != nil else {
            cancelPendingShortcutRetry()
            return
        }

        pendingShortcutRetryTask?.cancel()
        pendingShortcutRetryTask = Task { [delay] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                pendingShortcutRetryTask = nil
                deps.appShortcutLaunchStore.refreshFromDefaults()
                handlePendingAppShortcutIfNeeded()
            }
        }
    }

    private func cancelPendingShortcutRetry() {
        pendingShortcutRetryTask?.cancel()
        pendingShortcutRetryTask = nil
    }

    private var overlayQuickActions: [OperatorOverlayQuickAction] {
        var actions = [
            OperatorOverlayQuickAction(
                title: preferredOnCallSurface.label,
                systemImage: preferredSurfaceSymbolName,
                tone: visibleCriticalAlertCount > 0 ? .critical : .neutral,
                priority: .primary,
                isCritical: visibleCriticalAlertCount > 0,
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
                    priority: .primary,
                    isCritical: visibleCriticalAlertCount > 0,
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
                    priority: .primary,
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
                    priority: .primary,
                    isCritical: handoffBannerStatus?.state == .overdue,
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
                    priority: .support,
                    badgeText: vm.sessionAttentionCount == 1
                        ? String(localized: "1 hotspot")
                        : String(localized: "\(vm.sessionAttentionCount) hotspots"),
                    action: { _ = openRoute(.sessionsAttention, respectingPresentationGate: false) }
                )
            )
        }

        if !deps.networkMonitor.isConnected || vm.runtimeAlertCount > 0 {
            actions.append(
                OperatorOverlayQuickAction(
                    title: String(localized: "Diagnostics"),
                    systemImage: "stethoscope",
                    tone: !deps.networkMonitor.isConnected ? .critical : .warning,
                    priority: .support,
                    isCritical: !deps.networkMonitor.isConnected,
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
    let sectionCount: Int
    let criticalCount: Int
    let approvalCount: Int
    let watchIssueCount: Int
    let sessionCount: Int
    let pendingFollowUpCount: Int
    let mutedAlertCount: Int
    let preferredSurfaceLabel: String
    let isOffline: Bool
    let isSnapshotAcknowledged: Bool
    let overviewCount: Int
    let agentsCount: Int
    let runtimeCount: Int
    let budgetCount: Int
    let settingsCount: Int
    let actions: [OperatorOverlayQuickAction]

    private var primaryActions: [OperatorOverlayQuickAction] {
        actions.filter { $0.priority == .primary }
    }

    private var supportActions: [OperatorOverlayQuickAction] {
        actions.filter { $0.priority == .support }
    }

    private var badgedActionCount: Int {
        actions.filter(\.hasBadge).count
    }

    private var criticalActionCount: Int {
        actions.filter(\.isCritical).count
    }

    private var tabSignalCount: Int {
        [overviewCount, agentsCount, runtimeCount, budgetCount, settingsCount]
            .filter { $0 > 0 }
            .count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ResponsiveAccessoryRow(horizontalSpacing: 10, verticalSpacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Quick Actions"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } accessory: {
                GlassCapsuleBadge(
                    text: preferredSurfaceLabel,
                    foregroundStyle: .secondary,
                    backgroundOpacity: 0.08
                )
            }

            OperatorOverlayInventoryDeck(
                preferredSurfaceLabel: preferredSurfaceLabel,
                isOffline: isOffline,
                primaryActionCount: primaryActions.count,
                supportActionCount: supportActions.count,
                badgedActionCount: badgedActionCount,
                criticalActionCount: criticalActionCount
            )

            OperatorOverlaySectionDeck(
                sectionCount: sectionCount,
                isOffline: isOffline,
                hasActions: !primaryActions.isEmpty || !supportActions.isEmpty,
                criticalCount: criticalCount,
                approvalCount: approvalCount,
                watchIssueCount: watchIssueCount,
                sessionCount: sessionCount,
                pendingFollowUpCount: pendingFollowUpCount
            )

            if tabSignalCount > 0 {
                OperatorOverlayTabDeck(
                    overviewCount: overviewCount,
                    agentsCount: agentsCount,
                    runtimeCount: runtimeCount,
                    budgetCount: budgetCount,
                    settingsCount: settingsCount
                )
            }

            OperatorOverlayPressureDeck(
                isOffline: isOffline,
                criticalCount: criticalCount,
                approvalCount: approvalCount,
                watchIssueCount: watchIssueCount,
                sessionCount: sessionCount,
                pendingFollowUpCount: pendingFollowUpCount
            )

            OperatorOverlayActionReadinessDeck(
                preferredSurfaceLabel: preferredSurfaceLabel,
                primaryActionCount: primaryActions.count,
                supportActionCount: supportActions.count,
                badgedActionCount: badgedActionCount,
                criticalActionCount: criticalActionCount,
                tabSignalCount: tabSignalCount,
                isOffline: isOffline,
                isSnapshotAcknowledged: isSnapshotAcknowledged,
                mutedAlertCount: mutedAlertCount,
                pendingFollowUpCount: pendingFollowUpCount
            )
            OperatorOverlayFocusCoverageDeck(
                preferredSurfaceLabel: preferredSurfaceLabel,
                tabSignalCount: tabSignalCount,
                criticalCount: criticalCount,
                approvalCount: approvalCount,
                watchIssueCount: watchIssueCount,
                sessionCount: sessionCount,
                mutedAlertCount: mutedAlertCount,
                pendingFollowUpCount: pendingFollowUpCount,
                isOffline: isOffline
            )
            OperatorOverlayWorkstreamCoverageDeck(
                preferredSurfaceLabel: preferredSurfaceLabel,
                tabSignalCount: tabSignalCount,
                criticalCount: criticalCount,
                approvalCount: approvalCount,
                watchIssueCount: watchIssueCount,
                sessionCount: sessionCount,
                mutedAlertCount: mutedAlertCount,
                pendingFollowUpCount: pendingFollowUpCount,
                isOffline: isOffline
            )

            if !primaryActions.isEmpty || !supportActions.isEmpty {
                OperatorOverlayRouteDeck(
                    preferredSurfaceLabel: preferredSurfaceLabel,
                    isOffline: isOffline,
                    primaryActions: primaryActions,
                    supportActions: supportActions,
                    badgedActionCount: badgedActionCount,
                    criticalActionCount: criticalActionCount
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OperatorOverlayTabDeck: View {
    let overviewCount: Int
    let agentsCount: Int
    let runtimeCount: Int
    let budgetCount: Int
    let settingsCount: Int

    private var liveTabCount: Int {
        [overviewCount, agentsCount, runtimeCount, budgetCount, settingsCount]
            .filter { $0 > 0 }
            .count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ResponsiveAccessoryRow(horizontalSpacing: 10, verticalSpacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Tab coverage"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Keep tab-level pressure readable before jumping into the next monitor surface."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } accessory: {
                GlassCapsuleBadge(
                    text: liveTabCount == 1 ? String(localized: "1 live tab") : String(localized: "\(liveTabCount) live tabs"),
                    foregroundStyle: .secondary,
                    backgroundOpacity: 0.08
                )
            }

            FlowLayout(spacing: 8) {
                if overviewCount > 0 {
                    tabBadge(title: String(localized: "Overview"), count: overviewCount)
                }
                if agentsCount > 0 {
                    tabBadge(title: String(localized: "Agents"), count: agentsCount)
                }
                if runtimeCount > 0 {
                    tabBadge(title: String(localized: "Runtime"), count: runtimeCount)
                }
                if budgetCount > 0 {
                    tabBadge(title: String(localized: "Budget"), count: budgetCount)
                }
                if settingsCount > 0 {
                    tabBadge(title: String(localized: "Settings"), count: settingsCount)
                }
            }
        }
    }

    private func tabBadge(title: String, count: Int) -> some View {
        GlassCapsuleBadge(
            text: count == 1 ? String(localized: "\(title) 1 issue") : String(localized: "\(title) \(count) issues"),
            foregroundStyle: .primary,
            backgroundOpacity: 0.10
        )
    }
}

private struct OperatorOverlaySectionDeck: View {
    let sectionCount: Int
    let isOffline: Bool
    let hasActions: Bool
    let criticalCount: Int
    let approvalCount: Int
    let watchIssueCount: Int
    let sessionCount: Int
    let pendingFollowUpCount: Int

    private var activePressureCount: Int {
        [
            isOffline,
            criticalCount > 0,
            approvalCount > 0,
            watchIssueCount > 0,
            sessionCount > 0,
            pendingFollowUpCount > 0
        ]
        .filter { $0 }
        .count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ResponsiveAccessoryRow(horizontalSpacing: 10, verticalSpacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Section inventory"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Keep overlay coverage readable before the quick-action rails and pressure badges."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } accessory: {
                GlassCapsuleBadge(
                    text: sectionCount == 1 ? String(localized: "1 live section") : String(localized: "\(sectionCount) live sections"),
                    foregroundStyle: .secondary,
                    backgroundOpacity: 0.08
                )
            }

            FlowLayout(spacing: 8) {
                GlassCapsuleBadge(
                    text: activePressureCount == 1 ? String(localized: "1 pressure bucket") : String(localized: "\(activePressureCount) pressure buckets"),
                    foregroundStyle: .primary,
                    backgroundOpacity: 0.10
                )
                if hasActions {
                    GlassCapsuleBadge(
                        text: String(localized: "Actions ready"),
                        foregroundStyle: .primary,
                        backgroundOpacity: 0.10
                    )
                }
                if isOffline {
                    GlassCapsuleBadge(
                        text: String(localized: "Offline banner"),
                        foregroundStyle: .primary,
                        backgroundOpacity: 0.10
                    )
                }
            }
        }
    }
}

private struct OperatorOverlayInventoryDeck: View {
    let preferredSurfaceLabel: String
    let isOffline: Bool
    let primaryActionCount: Int
    let supportActionCount: Int
    let badgedActionCount: Int
    let criticalActionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ResponsiveAccessoryRow(horizontalSpacing: 10, verticalSpacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Route inventory"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Keep the preferred surface and quick-action split readable before opening the full monitor surface."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } accessory: {
                GlassCapsuleBadge(
                    text: preferredSurfaceLabel,
                    foregroundStyle: .secondary,
                    backgroundOpacity: 0.08
                )
            }

            FlowLayout(spacing: 8) {
                GlassCapsuleBadge(
                    text: primaryActionCount == 1 ? String(localized: "1 primary") : String(localized: "\(primaryActionCount) primary"),
                    foregroundStyle: .primary,
                    backgroundOpacity: 0.10
                )
                if supportActionCount > 0 {
                    GlassCapsuleBadge(
                        text: supportActionCount == 1 ? String(localized: "1 support") : String(localized: "\(supportActionCount) support"),
                        foregroundStyle: .primary,
                        backgroundOpacity: 0.10
                    )
                }
                if badgedActionCount > 0 {
                    GlassCapsuleBadge(
                        text: badgedActionCount == 1 ? String(localized: "1 badged") : String(localized: "\(badgedActionCount) badged"),
                        foregroundStyle: .primary,
                        backgroundOpacity: 0.10
                    )
                }
                if criticalActionCount > 0 {
                    GlassCapsuleBadge(
                        text: criticalActionCount == 1 ? String(localized: "1 urgent route") : String(localized: "\(criticalActionCount) urgent routes"),
                        foregroundStyle: .primary,
                        backgroundOpacity: 0.10
                    )
                }
                if isOffline {
                    GlassCapsuleBadge(
                        text: String(localized: "Offline fallback"),
                        foregroundStyle: .primary,
                        backgroundOpacity: 0.10
                    )
                }
            }
        }
    }
}

private struct OperatorOverlayPressureDeck: View {
    let isOffline: Bool
    let criticalCount: Int
    let approvalCount: Int
    let watchIssueCount: Int
    let sessionCount: Int
    let pendingFollowUpCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Pressure"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                if isOffline {
                    pressureBadge(String(localized: "Offline"))
                }
                if criticalCount > 0 {
                    pressureBadge(criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"))
                }
                if approvalCount > 0 {
                    pressureBadge(approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"))
                }
                if watchIssueCount > 0 {
                    pressureBadge(watchIssueCount == 1 ? String(localized: "1 watch issue") : String(localized: "\(watchIssueCount) watch issues"))
                }
                if sessionCount > 0 {
                    pressureBadge(sessionCount == 1 ? String(localized: "1 session hotspot") : String(localized: "\(sessionCount) session hotspots"))
                }
                if pendingFollowUpCount > 0 {
                    pressureBadge(pendingFollowUpCount == 1 ? String(localized: "1 follow-up open") : String(localized: "\(pendingFollowUpCount) follow-ups open"))
                }
            }
        }
    }

    private func pressureBadge(_ text: String) -> some View {
        GlassCapsuleBadge(
            text: text,
            foregroundStyle: .primary,
            backgroundOpacity: 0.10
        )
    }
}

private struct OperatorOverlayActionReadinessDeck: View {
    let preferredSurfaceLabel: String
    let primaryActionCount: Int
    let supportActionCount: Int
    let badgedActionCount: Int
    let criticalActionCount: Int
    let tabSignalCount: Int
    let isOffline: Bool
    let isSnapshotAcknowledged: Bool
    let mutedAlertCount: Int
    let pendingFollowUpCount: Int

    private var totalActionCount: Int {
        primaryActionCount + supportActionCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to check whether the preferred surface, overlay exits, and follow-through actions are ready before opening the larger route groups."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: preferredSurfaceLabel,
                        tone: isOffline ? .warning : .neutral
                    )
                    PresentationToneBadge(
                        text: isSnapshotAcknowledged ? String(localized: "Snapshot acknowledged") : String(localized: "Snapshot live"),
                        tone: isSnapshotAcknowledged ? .positive : .warning
                    )
                    PresentationToneBadge(
                        text: totalActionCount == 1 ? String(localized: "1 route ready") : String(localized: "\(totalActionCount) routes ready"),
                        tone: totalActionCount > 0 ? .positive : .neutral
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Action readiness"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep overlay route breadth, snapshot state, and follow-up readiness visible before opening the primary and support exits."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: tabSignalCount == 1 ? String(localized: "1 live tab") : String(localized: "\(tabSignalCount) live tabs"),
                    tone: tabSignalCount > 0 ? .warning : .neutral
                )
            } facts: {
                Label(
                    primaryActionCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryActionCount) primary routes"),
                    systemImage: "arrowshape.turn.up.right"
                )
                if supportActionCount > 0 {
                    Label(
                        supportActionCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportActionCount) support routes"),
                        systemImage: "square.grid.2x2"
                    )
                }
                if criticalActionCount > 0 {
                    Label(
                        criticalActionCount == 1 ? String(localized: "1 urgent route") : String(localized: "\(criticalActionCount) urgent routes"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if badgedActionCount > 0 {
                    Label(
                        badgedActionCount == 1 ? String(localized: "1 counted route") : String(localized: "\(badgedActionCount) counted routes"),
                        systemImage: "number"
                    )
                }
                if mutedAlertCount > 0 {
                    Label(
                        mutedAlertCount == 1 ? String(localized: "1 muted alert") : String(localized: "\(mutedAlertCount) muted alerts"),
                        systemImage: "bell.slash"
                    )
                }
                if pendingFollowUpCount > 0 {
                    Label(
                        pendingFollowUpCount == 1 ? String(localized: "1 follow-up open") : String(localized: "\(pendingFollowUpCount) follow-ups open"),
                        systemImage: "checklist.unchecked"
                    )
                }
            }
        }
    }

    private var summaryLine: String {
        if isOffline {
            return String(localized: "Overlay action readiness is currently anchored by offline recovery and fallback routes.")
        }
        if criticalActionCount > 0 {
            return String(localized: "Overlay action readiness is currently anchored by urgent exits from the active snapshot.")
        }
        if pendingFollowUpCount > 0 || mutedAlertCount > 0 {
            return String(localized: "Overlay action readiness is currently anchored by follow-up and muted-alert follow-through.")
        }
        return String(localized: "Overlay action readiness is currently centered on the preferred surface and nearby operator exits.")
    }
}

private struct OperatorOverlayFocusCoverageDeck: View {
    let preferredSurfaceLabel: String
    let tabSignalCount: Int
    let criticalCount: Int
    let approvalCount: Int
    let watchIssueCount: Int
    let sessionCount: Int
    let mutedAlertCount: Int
    let pendingFollowUpCount: Int
    let isOffline: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep the dominant overlay lane readable before opening the broader primary and support route groups."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: preferredSurfaceLabel, tone: .neutral)
                    PresentationToneBadge(
                        text: tabSignalCount == 1 ? String(localized: "1 live tab") : String(localized: "\(tabSignalCount) live tabs"),
                        tone: tabSignalCount > 0 ? .warning : .neutral
                    )
                    if isOffline {
                        PresentationToneBadge(text: String(localized: "Offline"), tone: .warning)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Focus coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the dominant overlay lane readable before moving from the top overlay summary into quick-action exits."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                    tone: criticalCount > 0 ? .critical : .neutral
                )
            } facts: {
                if approvalCount > 0 {
                    Label(
                        approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                        systemImage: "checkmark.shield"
                    )
                }
                if watchIssueCount > 0 {
                    Label(
                        watchIssueCount == 1 ? String(localized: "1 watch issue") : String(localized: "\(watchIssueCount) watch issues"),
                        systemImage: "star.fill"
                    )
                }
                if sessionCount > 0 {
                    Label(
                        sessionCount == 1 ? String(localized: "1 session hotspot") : String(localized: "\(sessionCount) session hotspots"),
                        systemImage: "text.bubble"
                    )
                }
                if mutedAlertCount > 0 {
                    Label(
                        mutedAlertCount == 1 ? String(localized: "1 muted alert") : String(localized: "\(mutedAlertCount) muted alerts"),
                        systemImage: "bell.slash"
                    )
                }
                if pendingFollowUpCount > 0 {
                    Label(
                        pendingFollowUpCount == 1 ? String(localized: "1 follow-up") : String(localized: "\(pendingFollowUpCount) follow-ups"),
                        systemImage: "checklist.unchecked"
                    )
                }
            }
        }
    }

    private var summaryLine: String {
        if isOffline {
            return String(localized: "Overlay focus coverage is currently anchored by offline recovery.")
        }
        if criticalCount > 0 || approvalCount > 0 || sessionCount > 0 {
            return String(localized: "Overlay focus coverage is currently anchored by live triage pressure.")
        }
        if watchIssueCount > 0 || mutedAlertCount > 0 || pendingFollowUpCount > 0 {
            return String(localized: "Overlay focus coverage is currently anchored by watch, muted-alert, and follow-up drag.")
        }
        return String(localized: "Overlay focus coverage is currently centered on the preferred surface and nearby tabs.")
    }
}

private struct OperatorOverlayWorkstreamCoverageDeck: View {
    let preferredSurfaceLabel: String
    let tabSignalCount: Int
    let criticalCount: Int
    let approvalCount: Int
    let watchIssueCount: Int
    let sessionCount: Int
    let mutedAlertCount: Int
    let pendingFollowUpCount: Int
    let isOffline: Bool

    private var activeLaneCount: Int {
        [
            criticalCount > 0,
            approvalCount > 0,
            watchIssueCount > 0,
            sessionCount > 0,
            mutedAlertCount > 0,
            pendingFollowUpCount > 0,
            isOffline
        ].filter { $0 }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to see whether the overlay is currently led by live triage, follow-through drag, or offline recovery before opening the route groups."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: preferredSurfaceLabel, tone: .neutral)
                    PresentationToneBadge(
                        text: tabSignalCount == 1 ? String(localized: "1 live tab") : String(localized: "\(tabSignalCount) live tabs"),
                        tone: tabSignalCount > 0 ? .warning : .neutral
                    )
                    if isOffline {
                        PresentationToneBadge(text: String(localized: "Offline"), tone: .warning)
                    } else if criticalCount > 0 {
                        PresentationToneBadge(
                            text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                            tone: .critical
                        )
                    } else if pendingFollowUpCount > 0 {
                        PresentationToneBadge(
                            text: pendingFollowUpCount == 1 ? String(localized: "1 follow-up") : String(localized: "\(pendingFollowUpCount) follow-ups"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Workstream coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep live triage, watch drag, and follow-through pressure readable before moving from the overlay into deeper route groups."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: activeLaneCount == 1 ? String(localized: "1 active lane") : String(localized: "\(activeLaneCount) active lanes"),
                    tone: activeLaneCount > 0 ? .warning : .neutral
                )
            } facts: {
                if criticalCount > 0 {
                    Label(
                        criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if approvalCount > 0 {
                    Label(
                        approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                        systemImage: "checkmark.shield"
                    )
                }
                if watchIssueCount > 0 {
                    Label(
                        watchIssueCount == 1 ? String(localized: "1 watch issue") : String(localized: "\(watchIssueCount) watch issues"),
                        systemImage: "star.fill"
                    )
                }
                if sessionCount > 0 {
                    Label(
                        sessionCount == 1 ? String(localized: "1 session hotspot") : String(localized: "\(sessionCount) session hotspots"),
                        systemImage: "text.bubble"
                    )
                }
                if mutedAlertCount > 0 {
                    Label(
                        mutedAlertCount == 1 ? String(localized: "1 muted alert") : String(localized: "\(mutedAlertCount) muted alerts"),
                        systemImage: "bell.slash"
                    )
                }
                if pendingFollowUpCount > 0 {
                    Label(
                        pendingFollowUpCount == 1 ? String(localized: "1 follow-up open") : String(localized: "\(pendingFollowUpCount) follow-ups open"),
                        systemImage: "checklist.unchecked"
                    )
                }
            }
        }
    }

    private var summaryLine: String {
        if isOffline {
            return String(localized: "Overlay workstream coverage is currently anchored by offline recovery.")
        }
        if criticalCount > 0 || approvalCount > 0 || sessionCount > 0 {
            return String(localized: "Overlay workstream coverage is currently anchored by live triage pressure.")
        }
        if watchIssueCount > 0 || mutedAlertCount > 0 || pendingFollowUpCount > 0 {
            return String(localized: "Overlay workstream coverage is currently anchored by watch drag and follow-through work.")
        }
        return String(localized: "Overlay workstream coverage is currently centered on the preferred surface and live tab context.")
    }
}

private struct OperatorOverlayRouteDeck: View {
    let preferredSurfaceLabel: String
    let isOffline: Bool
    let primaryActions: [OperatorOverlayQuickAction]
    let supportActions: [OperatorOverlayQuickAction]
    let badgedActionCount: Int
    let criticalActionCount: Int

    private var totalRouteCount: Int {
        primaryActions.count + supportActions.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Keep the preferred surface, urgent drilldowns, and supporting operator exits reachable from the overlay without expanding the full monitoring stack."),
                verticalPadding: 2
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: totalRouteCount == 1 ? String(localized: "1 live route") : String(localized: "\(totalRouteCount) live routes"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: primaryActions.count == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryActions.count) primary routes"),
                        tone: primaryActions.isEmpty ? .neutral : .warning
                    )
                    if !supportActions.isEmpty {
                        PresentationToneBadge(
                            text: supportActions.count == 1 ? String(localized: "1 support route") : String(localized: "\(supportActions.count) support routes"),
                            tone: .neutral
                        )
                    }
                    if badgedActionCount > 0 {
                        PresentationToneBadge(
                            text: badgedActionCount == 1 ? String(localized: "1 counted route") : String(localized: "\(badgedActionCount) counted routes"),
                            tone: .warning
                        )
                    }
                    if criticalActionCount > 0 {
                        PresentationToneBadge(
                            text: criticalActionCount == 1 ? String(localized: "1 urgent route") : String(localized: "\(criticalActionCount) urgent routes"),
                            tone: .critical
                        )
                    }
                }
            }

            if !primaryActions.isEmpty {
                MonitoringSurfaceGroupCard(
                    title: String(localized: "Primary routes"),
                    detail: String(localized: "Anchor the overlay around the preferred surface, active incidents, approvals, and handoff recovery without leaving the top-level operator context.")
                ) {
                    MonitoringShortcutRail(
                        title: String(localized: "Immediate exits"),
                        detail: String(localized: "Use the routes with the most active pressure first.")
                    ) {
                        ForEach(primaryActions) { action in
                            routeButton(action)
                        }
                    }
                }
            }

            if !supportActions.isEmpty {
                MonitoringSurfaceGroupCard(
                    title: String(localized: "Support routes"),
                    detail: String(localized: "Keep supporting diagnostics and session drilldowns close when the overlay is carrying secondary pressure.")
                ) {
                    MonitoringShortcutRail(
                        title: String(localized: "Support exits"),
                        detail: String(localized: "Use these when the primary routes are stable but operator follow-through is still needed.")
                    ) {
                        ForEach(supportActions) { action in
                            routeButton(action)
                        }
                    }
                }
            }
        }
    }

    private func routeButton(_ action: OperatorOverlayQuickAction) -> some View {
        Button(action: action.action) {
            MonitoringSurfaceShortcutChip(
                title: action.title,
                systemImage: action.systemImage,
                tone: action.tone,
                badgeText: action.badgeText
            )
        }
        .buttonStyle(.plain)
    }

    private var summaryLine: String {
        if isOffline {
            return String(localized: "Overlay routes are currently anchored by offline recovery and fallback operator exits.")
        }
        if criticalActionCount > 0 {
            return String(localized: "Overlay routes are currently anchored by urgent operator exits.")
        }
        if badgedActionCount > 0 {
            return String(localized: "Overlay routes are currently anchored by counted live signals from the top monitor surfaces.")
        }
        return String(localized: "Overlay routes are currently centered on the preferred surface and nearby operator follow-through.")
    }
}

private enum OperatorOverlayActionPriority {
    case primary
    case support
}

private struct OperatorOverlayQuickAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let tone: PresentationTone
    let priority: OperatorOverlayActionPriority
    let isCritical: Bool
    let badgeText: String?
    let action: () -> Void

    init(
        title: String,
        systemImage: String,
        tone: PresentationTone,
        priority: OperatorOverlayActionPriority,
        isCritical: Bool = false,
        badgeText: String?,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.priority = priority
        self.isCritical = isCritical
        self.badgeText = badgeText
        self.action = action
    }

    var hasBadge: Bool {
        badgeText != nil
    }
}

// MARK: - Offline Banner

private struct OfflineBanner: View {
    let runtimeIssueCount: Int
    let approvalCount: Int
    let followUpCount: Int

    var body: some View {
        MainTabStatusBanner(tint: .red) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.caption2)
                    Text("No Internet Connection")
                        .font(.caption.weight(.semibold))
                }

                Text(String(localized: "The iPhone is offline, so the monitoring snapshot may be stale until connectivity returns."))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } accessory: {
            FlowLayout(spacing: 8) {
                GlassCapsuleBadge(text: String(localized: "Stale snapshot"), backgroundOpacity: 0.18)
                if runtimeIssueCount > 0 {
                    GlassCapsuleBadge(
                        text: runtimeIssueCount == 1 ? String(localized: "1 runtime issue") : String(localized: "\(runtimeIssueCount) runtime issues")
                    )
                }
                if approvalCount > 0 {
                    GlassCapsuleBadge(
                        text: approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals")
                    )
                }
                if followUpCount > 0 {
                    GlassCapsuleBadge(
                        text: followUpCount == 1 ? String(localized: "1 handoff open") : String(localized: "\(followUpCount) handoff open")
                    )
                }
            }
        }
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
    let approvalCount: Int
    let watchIssueCount: Int
    let sessionCount: Int

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
            contextBadge(count: approvalCount, singular: String(localized: "1 approval"), plural: String(localized: "\(approvalCount) approvals"))
            contextBadge(count: watchIssueCount, singular: String(localized: "1 watch issue"), plural: String(localized: "\(watchIssueCount) watch issues"))
            contextBadge(count: sessionCount, singular: String(localized: "1 hotspot"), plural: String(localized: "\(sessionCount) hotspots"))
            GlassCapsuleBadge(text: String(localized: "On Call"), backgroundOpacity: 0.18)
        }
    }

    @ViewBuilder
    private var mutedBadge: some View {
        if mutedCount > 0 {
            GlassCapsuleBadge(text: String(localized: "\(mutedCount) muted"))
        }
    }

    @ViewBuilder
    private func contextBadge(count: Int, singular: String, plural: String) -> some View {
        if count > 0 {
            GlassCapsuleBadge(text: count == 1 ? singular : plural)
        }
    }
}

private struct HandoffCheckInBanner: View {
    let status: HandoffCheckInStatus
    let pendingFollowUpCount: Int
    let watchIssueCount: Int
    let sessionCount: Int

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
            contextBadge(count: watchIssueCount, singular: String(localized: "1 watch issue"), plural: String(localized: "\(watchIssueCount) watch issues"))
            contextBadge(count: sessionCount, singular: String(localized: "1 hotspot"), plural: String(localized: "\(sessionCount) hotspots"))
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

    @ViewBuilder
    private func contextBadge(count: Int, singular: String, plural: String) -> some View {
        if count > 0 {
            GlassCapsuleBadge(text: count == 1 ? singular : plural)
        }
    }
}

private struct AcknowledgedIncidentBanner: View {
    let count: Int
    let mutedCount: Int
    let approvalCount: Int
    let watchIssueCount: Int
    let sessionCount: Int

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
            contextBadge(count: approvalCount, singular: String(localized: "1 approval"), plural: String(localized: "\(approvalCount) approvals"))
            contextBadge(count: watchIssueCount, singular: String(localized: "1 watch issue"), plural: String(localized: "\(watchIssueCount) watch issues"))
            contextBadge(count: sessionCount, singular: String(localized: "1 hotspot"), plural: String(localized: "\(sessionCount) hotspots"))
            GlassCapsuleBadge(text: String(localized: "On Call"), backgroundOpacity: 0.18)
        }
    }

    @ViewBuilder
    private var mutedBadge: some View {
        if mutedCount > 0 {
            GlassCapsuleBadge(text: String(localized: "\(mutedCount) muted"))
        }
    }

    @ViewBuilder
    private func contextBadge(count: Int, singular: String, plural: String) -> some View {
        if count > 0 {
            GlassCapsuleBadge(text: count == 1 ? singular : plural)
        }
    }
}

private struct IncidentCueBanner: View {
    let cue: ActiveIncidentCue
    let criticalCount: Int
    let mutedCount: Int
    let approvalCount: Int
    let sessionCount: Int
    let watchIssueCount: Int
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

            FlowLayout(spacing: 8) {
                GlassCapsuleBadge(
                    text: criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical")
                )
                if mutedCount > 0 {
                    GlassCapsuleBadge(
                        text: mutedCount == 1 ? String(localized: "1 muted") : String(localized: "\(mutedCount) muted")
                    )
                }
                if approvalCount > 0 {
                    GlassCapsuleBadge(
                        text: approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals")
                    )
                }
                if sessionCount > 0 {
                    GlassCapsuleBadge(
                        text: sessionCount == 1 ? String(localized: "1 hotspot") : String(localized: "\(sessionCount) hotspots")
                    )
                }
                if watchIssueCount > 0 {
                    GlassCapsuleBadge(
                        text: watchIssueCount == 1 ? String(localized: "1 watch issue") : String(localized: "\(watchIssueCount) watch issues")
                    )
                }
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
    let dueLabel: String?
    let pendingFollowUpCount: Int
    let watchIssueCount: Int
    let sessionCount: Int
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

            FlowLayout(spacing: 8) {
                if let dueLabel {
                    GlassCapsuleBadge(text: dueLabel)
                }
                if pendingFollowUpCount > 0 {
                    GlassCapsuleBadge(
                        text: pendingFollowUpCount == 1 ? String(localized: "1 follow-up open") : String(localized: "\(pendingFollowUpCount) follow-ups open")
                    )
                }
                if watchIssueCount > 0 {
                    GlassCapsuleBadge(
                        text: watchIssueCount == 1 ? String(localized: "1 watch issue") : String(localized: "\(watchIssueCount) watch issues")
                    )
                }
                if sessionCount > 0 {
                    GlassCapsuleBadge(
                        text: sessionCount == 1 ? String(localized: "1 hotspot") : String(localized: "\(sessionCount) hotspots")
                    )
                }
            }

            Button(action: onOpen) {
                Label("Handoff", systemImage: "arrow.up.forward.app")
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

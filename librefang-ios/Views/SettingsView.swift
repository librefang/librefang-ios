import SwiftUI

struct SettingsView: View {
    @Environment(\.dependencies) private var deps
    @Environment(\.openURL) private var openURL
    @State private var serverURL = ServerConfig.saved.baseURL
    @State private var apiKey = ServerConfig.saved.apiKey
    @State private var refreshInterval: Double = UserDefaults.standard.double(forKey: "refreshInterval").clamped(to: 10...300, default: 30)
    @State private var isSaving = false
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Server URL", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("API Key (optional)", text: $apiKey)
                        .textInputAutocapitalization(.never)

                    Button {
                        Task { await saveAndTest() }
                    } label: {
                        HStack {
                            Text("Save & Test Connection")
                            Spacer()
                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                            } else if showSuccess {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .disabled(isSaving)

                    Text(serverConnectionHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Auto Refresh") {
                    HStack {
                        Text("Interval")
                        Spacer()
                        Text("\(Int(refreshInterval))s")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $refreshInterval, in: 10...120, step: 5) {
                        Text("Refresh Interval")
                    }
                    .onChange(of: refreshInterval) {
                        UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
                        deps.dashboardViewModel.startAutoRefresh(interval: refreshInterval)
                    }
                }

                Section("Language") {
                    SettingsValueRow("Current") {
                        Text(currentLanguageLabel)
                            .foregroundStyle(.secondary)
                    }

                    SettingsValueRow("Supported") {
                        Text(supportedLanguageLabels.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        Label("Open iPhone Language Settings", systemImage: "globe")
                    }

                    Text("LibreFang iOS follows iPhone per-app language settings so String Catalog translations stay consistent across SwiftUI views and system surfaces. In Settings, open the app page and choose Language.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("A2A Network") {
                    NavigationLink {
                        A2AAgentsView()
                            .navigationTitle("A2A Agents")
                    } label: {
                        HStack {
                            Label("External Agents", systemImage: "link.circle")
                            Spacer()
                            if let count = deps.dashboardViewModel.a2aAgents?.total {
                                Text("\(count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Runtime Catalogs") {
                    NavigationLink {
                        ToolProfilesView()
                    } label: {
                        Label("Tool Profiles", systemImage: "person.crop.rectangle.stack")
                    }
                }

                Section("On Call Focus") {
                    Picker("Queue Mode", selection: Binding(
                        get: { deps.onCallFocusStore.mode },
                        set: { deps.onCallFocusStore.mode = $0 }
                    )) {
                        ForEach(OnCallFocusMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }

                    Text(deps.onCallFocusStore.mode.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Critical Banner", selection: Binding(
                        get: { deps.onCallFocusStore.preferredSurface },
                        set: { deps.onCallFocusStore.preferredSurface = $0 }
                    )) {
                        ForEach(OnCallSurfacePreference.allCases) { surface in
                            Text(surface.label).tag(surface)
                        }
                    }

                    Text(deps.onCallFocusStore.preferredSurface.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Show Muted Summary", isOn: Binding(
                        get: { deps.onCallFocusStore.showsMutedSummary },
                        set: { deps.onCallFocusStore.showsMutedSummary = $0 }
                    ))

                    Toggle("Foreground Critical Cue", isOn: Binding(
                        get: { deps.onCallFocusStore.showsForegroundCues },
                        set: { deps.onCallFocusStore.showsForegroundCues = $0 }
                    ))

                    Text("When a new critical incident appears while the app is open, show a temporary cue and haptic.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Standby Reminder") {
                    Toggle("Enable Reminder", isOn: Binding(
                        get: { deps.onCallNotificationManager.isEnabled },
                        set: { deps.onCallNotificationManager.isEnabled = $0 }
                    ))

                    SettingsValueRow("Authorization") {
                        Text(deps.onCallNotificationManager.authorizationLabel)
                            .foregroundStyle(deps.onCallNotificationManager.authorizationTone.color)
                    }

                    Text(deps.onCallNotificationManager.authorizationSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if deps.onCallNotificationManager.authorizationStatus != .authorized
                        && deps.onCallNotificationManager.authorizationStatus != .provisional
                        && deps.onCallNotificationManager.authorizationStatus != .ephemeral {
                        Button("Enable iPhone Notifications") {
                            Task { await deps.onCallNotificationManager.requestAuthorization() }
                        }
                    }

                    if deps.onCallNotificationManager.isEnabled {
                        Picker("Reminder Scope", selection: Binding(
                            get: { deps.onCallNotificationManager.scope },
                            set: { deps.onCallNotificationManager.scope = $0 }
                        )) {
                            ForEach(OnCallReminderScope.allCases) { scope in
                                Text(scope.label).tag(scope)
                            }
                        }

                        Text(deps.onCallNotificationManager.scope.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Remind After", selection: Binding(
                            get: { deps.onCallNotificationManager.remindAfterMinutes },
                            set: { deps.onCallNotificationManager.remindAfterMinutes = $0 }
                        )) {
                            ForEach(deps.onCallNotificationManager.delayOptions, id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }

                        SettingsValueRow("Queued Reminder") {
                            Text(deps.onCallNotificationManager.pendingReminderLabel)
                                .foregroundStyle(reminderArmStatus.color(positive: .secondary, neutral: tertiaryLabelColor))
                        }

                        SettingsValueRow("Schedule Driver") {
                            Text(deps.onCallNotificationManager.pendingReminderSourceLabel)
                                .foregroundStyle(reminderArmStatus.color(positive: .secondary, neutral: tertiaryLabelColor))
                        }

                        if let pendingReminderSummary = deps.onCallNotificationManager.pendingReminderSummary {
                            Text(pendingReminderSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("If a handoff check-in is due before the standby delay, the reminder is pulled forward to that local checkpoint.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Handoff") {
                    NavigationLink {
                        HandoffCenterView(
                            summary: handoffText,
                            queueCount: onCallQueueCount,
                            criticalCount: currentCriticalCount,
                            liveAlertCount: visibleAlertCount
                        )
                    } label: {
                        HStack {
                            Label("Open Handoff Center", systemImage: "text.badge.plus")
                            Spacer()
                            if let latest = deps.onCallHandoffStore.latestEntry {
                                Text(latest.createdAt, style: .relative)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let latest = deps.onCallHandoffStore.latestEntry {
                        let followUpSummary = deps.onCallHandoffStore.latestFollowUpSummary

                        SettingsValueRow("Last Saved") {
                            Text(latest.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                .foregroundStyle(.secondary)
                        }
                        SettingsValueRow("Snapshot") {
                            Text("\(latest.queueCount) queued · \(latest.criticalCount) critical")
                                .foregroundStyle(snapshotCriticalStatus(for: latest).color(positive: .secondary))
                        }
                        SettingsValueRow("Checklist") {
                            Text(latest.checklist.progressLabel)
                                .foregroundStyle(latest.checklist.tone.color)
                        }
                        SettingsValueRow("Type") {
                            Text(latest.kind.label)
                                .foregroundStyle(latest.kind.tintColor)
                        }
                        SettingsValueRow("Focus") {
                            Text(latest.focusAreas.summaryLabel)
                                .foregroundStyle(handoffFocusStatus(for: latest).color(positive: .primary))
                        }
                        SettingsValueRow("Follow-ups") {
                            Text(followUpSummary.settingsLabel)
                                .foregroundStyle(followUpSummary.tone.color)
                        }
                        SettingsValueRow("Check-in") {
                            if let checkInStatus = deps.onCallHandoffStore.latestCheckInStatus {
                                Text(checkInStatus.state.label)
                                    .foregroundStyle(checkInStatus.state.tone.color)
                            } else {
                                Text(latest.checkInWindow == .none ? String(localized: "None") : latest.checkInWindow.label)
                                    .foregroundStyle(checkInWindowStatus(for: latest).color(positive: .primary))
                            }
                        }
                        if latest.checkInWindow != .none {
                            Text(latest.checkInWindow.dueLabel(from: latest.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        SettingsValueRow("Draft Readiness") {
                            Text(draftHandoffReadiness.state.label)
                                .foregroundStyle(draftHandoffReadiness.state.tone.color)
                        }
                        Text(draftHandoffReadiness.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let drift = deps.onCallHandoffStore.driftFromLatest(
                            queueCount: onCallQueueCount,
                            criticalCount: currentCriticalCount,
                            liveAlertCount: visibleAlertCount
                        ) {
                            SettingsValueRow("Drift") {
                                Text(drift.state.label)
                                    .foregroundStyle(drift.state.tone.color)
                            }
                            Text(drift.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let carryover = handoffCarryoverStatus {
                            SettingsValueRow("Carryover") {
                                Text(carryover.state.label)
                                    .foregroundStyle(carryover.state.tone.color)
                            }
                            Text(carryover.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        SettingsValueRow("Freshness") {
                            Text(deps.onCallHandoffStore.freshnessLabel)
                                .foregroundStyle(deps.onCallHandoffStore.freshnessState.tone.color)
                        }
                        SettingsValueRow("Cadence") {
                            Text(deps.onCallHandoffStore.cadenceState.label)
                                .foregroundStyle(deps.onCallHandoffStore.cadenceState.tone.color)
                        }
                        if !latest.checklist.pendingLabels.isEmpty {
                            Text(String(localized: "Pending: \(latest.checklist.pendingLabels.joined(separator: ", "))"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(deps.onCallHandoffStore.freshnessSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(deps.onCallHandoffStore.cadenceSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No local handoff snapshots saved on this iPhone yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Monitoring") {
                    SettingsValueRow("Agents") {
                        Text(deps.dashboardViewModel.agentAttentionStatus.summary)
                            .foregroundStyle(deps.dashboardViewModel.agentAttentionStatus.tone.color)
                    }
                    SettingsValueRow("Providers") {
                        Text(deps.dashboardViewModel.providerReadinessStatus.summary)
                            .foregroundStyle(deps.dashboardViewModel.providerReadinessStatus.tone.color)
                    }
                    SettingsValueRow("Channels") {
                        Text(deps.dashboardViewModel.channelReadinessStatus.summary)
                            .foregroundStyle(deps.dashboardViewModel.channelReadinessStatus.tone.color)
                    }
                    SettingsValueRow("Hands") {
                        Text(deps.dashboardViewModel.handReadinessStatus.summary)
                            .foregroundStyle(deps.dashboardViewModel.handReadinessStatus.tone.color)
                    }
                    SettingsValueRow("Approvals") {
                        Text(deps.dashboardViewModel.approvalBacklogStatus.summary)
                            .foregroundStyle(deps.dashboardViewModel.approvalBacklogStatus.tone.color)
                    }
                    SettingsValueRow("Peers") {
                        Text(deps.dashboardViewModel.peerConnectivityStatus.summary)
                            .foregroundStyle(deps.dashboardViewModel.peerConnectivityStatus.tone.color)
                    }
                    SettingsValueRow("MCP") {
                        Text(deps.dashboardViewModel.mcpConnectivityStatus.summary)
                            .foregroundStyle(deps.dashboardViewModel.mcpConnectivityStatus.tone.color)
                    }
                    SettingsValueRow("Sessions") {
                        Text("\(deps.dashboardViewModel.totalSessionCount)")
                            .foregroundStyle(.secondary)
                    }
                    SettingsValueRow("Watchlist") {
                        Text("\(deps.agentWatchlistStore.watchedAgentIDs.count)")
                            .foregroundStyle(watchlistStatus.color(positive: .secondary, neutral: tertiaryLabelColor))
                    }
                    SettingsValueRow("On Call Queue") {
                        Text("\(onCallQueueCount)")
                            .foregroundStyle(onCallQueueStatus.color(positive: .secondary))
                    }
                    SettingsValueRow("Muted Alerts") {
                        Text("\(activeMutedAlertCount)")
                            .foregroundStyle(mutedAlertStatus.color(positive: .secondary, neutral: tertiaryLabelColor))
                    }
                    SettingsValueRow("Incident Snapshot") {
                        Text(snapshotStatus.settingsLabel)
                            .foregroundStyle(snapshotStatus.tone.color)
                    }
                    SettingsValueRow("Audit") {
                        Text(deps.dashboardViewModel.auditIntegrityStatus.summary)
                            .foregroundStyle(deps.dashboardViewModel.auditIntegrityStatus.tone.color)
                    }
                    SettingsValueRow("Security") {
                        Text("\(deps.dashboardViewModel.securityFeatureCount) features")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    SettingsValueRow("App") {
                        Text("LibreFang iOS")
                    }
                    if let health = deps.dashboardViewModel.health {
                        SettingsValueRow("Server Version") {
                            Text(health.version)
                        }
                        SettingsValueRow("Server Status") {
                            Text(health.localizedStatusLabel)
                        }
                    }
                    if let refresh = deps.dashboardViewModel.lastRefresh {
                        SettingsValueRow("Last Refresh") {
                            Text(refresh, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func saveAndTest() async {
        isSaving = true
        showSuccess = false
        let config = ServerConfig(baseURL: serverURL, apiKey: apiKey)
        await deps.dashboardViewModel.updateServer(config)
        isSaving = false
        if deps.dashboardViewModel.health?.isHealthy == true {
            showSuccess = true
        }
    }

    private var serverConnectionHint: String {
        let normalized = serverURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.contains("127.0.0.1") || normalized.contains("localhost") {
            return String(localized: "127.0.0.1 and localhost only work when the daemon is reachable from the same host. On a physical iPhone, use your Mac's LAN IP, for example http://192.168.x.x:4545.")
        }

        return String(localized: "The app connects to this base URL on launch and refreshes the dashboard immediately after you save.")
    }

    private var currentLanguageLabel: String {
        if let languageCode = Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first {
            return localizedLanguageName(for: languageCode)
        }
        return String(localized: "System Default")
    }

    private var supportedLanguageLabels: [String] {
        let rawLocalizations = Bundle.main.localizations.filter { $0 != "Base" }
        let deduplicated = Array(Set(rawLocalizations)).sorted()
        return deduplicated.map(localizedLanguageName(for:))
    }

    private func localizedLanguageName(for identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier)
            ?? Locale(identifier: identifier).localizedString(forIdentifier: identifier)
            ?? identifier
    }

    private var activeMutedAlertCount: Int {
        deps.incidentStateStore.activeMutedAlerts(from: deps.dashboardViewModel.monitoringAlerts).count
    }

    private var visibleAlerts: [MonitoringAlertItem] {
        deps.incidentStateStore.visibleAlerts(from: deps.dashboardViewModel.monitoringAlerts)
    }

    private var watchedAttentionItems: [AgentAttentionItem] {
        deps.agentWatchlistStore
            .watchedAgents(from: deps.dashboardViewModel.agents)
            .map { deps.dashboardViewModel.attentionItem(for: $0) }
    }

    private var visibleAlertCount: Int {
        visibleAlerts.count
    }

    private var currentCriticalCount: Int {
        visibleAlerts.filter { $0.severity == .critical }.count
    }

    private var onCallQueueCount: Int {
        return deps.dashboardViewModel.onCallPriorityItems(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            handoffCheckInStatus: deps.onCallHandoffStore.latestCheckInStatus,
            handoffFollowUpStatuses: deps.onCallHandoffStore.latestFollowUpStatuses
        ).count
    }

    private var handoffText: String {
        deps.dashboardViewModel.onCallHandoffText(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            mutedAlertCount: activeMutedAlertCount,
            isAcknowledged: deps.incidentStateStore.isCurrentSnapshotAcknowledged(alerts: deps.dashboardViewModel.monitoringAlerts),
            handoffCheckInStatus: deps.onCallHandoffStore.latestCheckInStatus,
            handoffFollowUpStatuses: deps.onCallHandoffStore.latestFollowUpStatuses
        )
    }

    private var handoffCarryoverStatus: HandoffCarryoverStatus? {
        deps.onCallHandoffStore.carryoverFromLatest(
            liveAlertCount: visibleAlertCount,
            pendingApprovalCount: deps.dashboardViewModel.pendingApprovalCount,
            watchlistIssueCount: watchedAttentionItems.filter { $0.severity > 0 }.count,
            sessionAttentionCount: deps.dashboardViewModel.sessionAttentionCount,
            criticalAuditCount: deps.dashboardViewModel.recentCriticalAuditCount
        )
    }

    private var draftHandoffReadiness: HandoffReadinessStatus {
        deps.onCallHandoffStore.evaluateDraftReadiness(
            note: deps.onCallHandoffStore.draftNote,
            checklist: deps.onCallHandoffStore.draftChecklist,
            focusAreas: deps.onCallHandoffStore.draftFocusAreas,
            followUpItems: deps.onCallHandoffStore.draftFollowUpItems,
            checkInWindow: deps.onCallHandoffStore.draftCheckInWindow,
            liveAlertCount: visibleAlertCount,
            pendingApprovalCount: deps.dashboardViewModel.pendingApprovalCount,
            watchlistIssueCount: watchedAttentionItems.filter { $0.severity > 0 }.count,
            sessionAttentionCount: deps.dashboardViewModel.sessionAttentionCount,
            criticalAuditCount: deps.dashboardViewModel.recentCriticalAuditCount,
            carryover: handoffCarryoverStatus
        )
    }

    private var snapshotStatus: AlertSnapshotState {
        AlertSnapshotState(
            liveAlertCount: visibleAlerts.count,
            mutedAlertCount: activeMutedAlertCount,
            isAcknowledged: deps.incidentStateStore.isCurrentSnapshotAcknowledged(alerts: deps.dashboardViewModel.monitoringAlerts)
        )
    }

    private var tertiaryLabelColor: Color {
        Color(uiColor: .tertiaryLabel)
    }

    private var reminderArmStatus: MonitoringSummaryStatus {
        MonitoringSummaryStatus.presenceStatus(
            isPresent: deps.onCallNotificationManager.pendingReminderDate != nil
        )
    }

    private var watchlistStatus: MonitoringSummaryStatus {
        MonitoringSummaryStatus.countStatus(
            deps.agentWatchlistStore.watchedAgentIDs.count,
            activeTone: .positive
        )
    }

    private var onCallQueueStatus: MonitoringSummaryStatus {
        MonitoringSummaryStatus.countStatus(onCallQueueCount, activeTone: .warning)
    }

    private var mutedAlertStatus: MonitoringSummaryStatus {
        MonitoringSummaryStatus.countStatus(activeMutedAlertCount, activeTone: .positive)
    }

    private func snapshotCriticalStatus(for entry: OnCallHandoffEntry) -> MonitoringSummaryStatus {
        MonitoringSummaryStatus.countStatus(entry.criticalCount, activeTone: .warning)
    }

    private func handoffFocusStatus(for entry: OnCallHandoffEntry) -> MonitoringSummaryStatus {
        MonitoringSummaryStatus.presenceStatus(isPresent: !entry.focusAreas.items.isEmpty)
    }

    private func checkInWindowStatus(for entry: OnCallHandoffEntry) -> MonitoringSummaryStatus {
        MonitoringSummaryStatus.presenceStatus(isPresent: entry.checkInWindow != .none)
    }

}

private struct SettingsValueRow<Value: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let title: LocalizedStringKey
    let value: Value

    init(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                Spacer(minLength: 12)
                value
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                value
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, horizontalSizeClass == .compact ? 2 : 0)
    }
}

// MARK: - Helpers

private extension Double {
    func clamped(to range: ClosedRange<Double>, default defaultValue: Double) -> Double {
        if self == 0 { return defaultValue }
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

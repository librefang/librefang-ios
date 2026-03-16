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
                    TextField(String(localized: "Server URL"), text: $serverURL)
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

                }

                    Section("Auto Refresh") {
                    SettingsValueRow("Interval") {
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
                        SettingsTagFlow(labels: supportedLanguageLabels)
                    }

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        Label("Open iPhone Language Settings", systemImage: "globe")
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

                    Picker("Critical Banner", selection: Binding(
                        get: { deps.onCallFocusStore.preferredSurface },
                        set: { deps.onCallFocusStore.preferredSurface = $0 }
                    )) {
                        ForEach(OnCallSurfacePreference.allCases) { surface in
                            Text(surface.label).tag(surface)
                        }
                    }

                    Toggle("Show Muted Summary", isOn: Binding(
                        get: { deps.onCallFocusStore.showsMutedSummary },
                        set: { deps.onCallFocusStore.showsMutedSummary = $0 }
                    ))

                    Toggle("Foreground Critical Cue", isOn: Binding(
                        get: { deps.onCallFocusStore.showsForegroundCues },
                        set: { deps.onCallFocusStore.showsForegroundCues = $0 }
                    ))
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
                            Label("Handoff", systemImage: "text.badge.plus")
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
                        SettingsValueRow("Draft Readiness") {
                            Text(draftHandoffReadiness.state.label)
                                .foregroundStyle(draftHandoffReadiness.state.tone.color)
                        }
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
                    SettingsValueRow("Approvals") {
                        Text(deps.dashboardViewModel.approvalBacklogStatus.summary)
                            .foregroundStyle(deps.dashboardViewModel.approvalBacklogStatus.tone.color)
                    }
                    SettingsValueRow("Sessions") {
                        Text("\(deps.dashboardViewModel.totalSessionCount)")
                            .foregroundStyle(.secondary)
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
                    SettingsValueRow("Security") {
                        Text("\(deps.dashboardViewModel.securityFeatureCount) features")
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        A2AAgentsView()
                            .navigationTitle(String(localized: "A2A Agents"))
                    } label: {
                        Label("External Agents", systemImage: "link.circle")
                    }

                    NavigationLink {
                        ToolProfilesView()
                    } label: {
                        Label("Tool Profiles", systemImage: "person.crop.rectangle.stack")
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
                .navigationTitle(String(localized: "Settings"))
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

    private var onCallQueueStatus: MonitoringSummaryStatus {
        MonitoringSummaryStatus.countStatus(onCallQueueCount, activeTone: .warning)
    }

    private var mutedAlertStatus: MonitoringSummaryStatus {
        MonitoringSummaryStatus.countStatus(activeMutedAlertCount, activeTone: .positive)
    }

    private func snapshotCriticalStatus(for entry: OnCallHandoffEntry) -> MonitoringSummaryStatus {
        MonitoringSummaryStatus.countStatus(entry.criticalCount, activeTone: .warning)
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
        ResponsiveValueRow(
            horizontalSpacing: 12,
            verticalSpacing: 6,
            spacerMinLength: 12
        ) {
            Text(title)
        } value: {
            value
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, horizontalSizeClass == .compact ? 2 : 0)
    }
}

private struct SettingsTagFlow: View {
    let labels: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(labels, id: \.self) { label in
                SettingsBadge(
                    text: label,
                    tone: .neutral
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsBadge: View {
    let text: String
    let tone: PresentationTone

    var body: some View {
        PresentationToneBadge(
            text: text,
            tone: tone,
            horizontalPadding: 10,
            verticalPadding: 6
        )
    }
}

// MARK: - Helpers

private extension Double {
    func clamped(to range: ClosedRange<Double>, default defaultValue: Double) -> Double {
        if self == 0 { return defaultValue }
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

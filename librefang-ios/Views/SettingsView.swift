import SwiftUI

private enum SettingsSnapshotStatus {
    case clear
    case muted
    case acknowledged
    case needsReview

    var label: String {
        switch self {
        case .clear:
            String(localized: "Clear")
        case .muted:
            String(localized: "Muted")
        case .acknowledged:
            String(localized: "Acknowledged")
        case .needsReview:
            String(localized: "Needs review")
        }
    }

    var color: Color {
        switch self {
        case .needsReview:
            .red
        case .acknowledged:
            .orange
        case .muted:
            .secondary
        case .clear:
            .green
        }
    }
}

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
                    LabeledContent("Current") {
                        Text(currentLanguageLabel)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Supported") {
                        Text(supportedLanguageLabels.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
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

                    LabeledContent("Authorization") {
                        Text(deps.onCallNotificationManager.authorizationLabel)
                            .foregroundStyle(notificationAuthorizationColor)
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

                        LabeledContent("Queued Reminder") {
                            Text(deps.onCallNotificationManager.pendingReminderLabel)
                                .foregroundStyle(deps.onCallNotificationManager.pendingReminderDate == nil ? .tertiary : .secondary)
                        }

                        LabeledContent("Schedule Driver") {
                            Text(deps.onCallNotificationManager.pendingReminderSourceLabel)
                                .foregroundStyle(deps.onCallNotificationManager.pendingReminderDate == nil ? .tertiary : .secondary)
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
                        LabeledContent("Last Saved") {
                            Text(latest.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Snapshot") {
                            Text("\(latest.queueCount) queued · \(latest.criticalCount) critical")
                                .foregroundStyle(latest.criticalCount > 0 ? .orange : .secondary)
                        }
                        LabeledContent("Checklist") {
                            Text(latest.checklist.progressLabel)
                                .foregroundStyle(latest.checklist.pendingLabels.isEmpty ? .green : .secondary)
                        }
                        LabeledContent("Type") {
                            Text(latest.kind.label)
                                .foregroundStyle(handoffKindColor(for: latest.kind))
                        }
                        LabeledContent("Focus") {
                            Text(latest.focusAreas.summaryLabel)
                                .foregroundStyle(latest.focusAreas.items.isEmpty ? Color.secondary : Color.primary)
                        }
                        LabeledContent("Follow-ups") {
                            Text(latest.followUpItems.isEmpty
                                ? String(localized: "None")
                                : String(localized: "\(deps.onCallHandoffStore.pendingLatestFollowUpCount) pending · \(deps.onCallHandoffStore.completedLatestFollowUpCount) done"))
                                .foregroundStyle(
                                    latest.followUpItems.isEmpty
                                        ? Color.secondary
                                        : (deps.onCallHandoffStore.pendingLatestFollowUpCount == 0 ? Color.green : Color.primary)
                                )
                        }
                        LabeledContent("Check-in") {
                            if let checkInStatus = deps.onCallHandoffStore.latestCheckInStatus {
                                Text(checkInStatus.state.label)
                                    .foregroundStyle(handoffCheckInColor(for: checkInStatus))
                            } else {
                                Text(latest.checkInWindow == .none ? String(localized: "None") : latest.checkInWindow.label)
                                    .foregroundStyle(latest.checkInWindow == .none ? Color.secondary : Color.primary)
                            }
                        }
                        if latest.checkInWindow != .none {
                            Text(latest.checkInWindow.dueLabel(from: latest.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Draft Readiness") {
                            Text(draftHandoffReadiness.state.label)
                                .foregroundStyle(handoffReadinessColor)
                        }
                        Text(draftHandoffReadiness.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let drift = deps.onCallHandoffStore.driftFromLatest(
                            queueCount: onCallQueueCount,
                            criticalCount: currentCriticalCount,
                            liveAlertCount: visibleAlertCount
                        ) {
                            LabeledContent("Drift") {
                                Text(drift.state.label)
                                    .foregroundStyle(handoffDriftColor(for: drift))
                            }
                            Text(drift.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let carryover = handoffCarryoverStatus {
                            LabeledContent("Carryover") {
                                Text(carryover.state.label)
                                    .foregroundStyle(handoffCarryoverColor(for: carryover))
                            }
                            Text(carryover.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Freshness") {
                            Text(deps.onCallHandoffStore.freshnessLabel)
                                .foregroundStyle(handoffFreshnessColor)
                        }
                        LabeledContent("Cadence") {
                            Text(deps.onCallHandoffStore.cadenceState.label)
                                .foregroundStyle(handoffCadenceColor)
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
                    LabeledContent("Agents") {
                        Text("\(deps.dashboardViewModel.issueAgentCount) need attention")
                            .foregroundStyle(deps.dashboardViewModel.issueAgentCount > 0 ? .orange : .secondary)
                    }
                    LabeledContent("Providers") {
                        Text("\(deps.dashboardViewModel.configuredProviderCount) configured")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Channels") {
                        Text("\(deps.dashboardViewModel.readyChannelCount) ready")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Hands") {
                        Text("\(deps.dashboardViewModel.activeHandCount) active")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Approvals") {
                        Text("\(deps.dashboardViewModel.pendingApprovalCount) pending")
                            .foregroundStyle(deps.dashboardViewModel.pendingApprovalCount > 0 ? .red : .secondary)
                    }
                    LabeledContent("Peers") {
                        Text("\(deps.dashboardViewModel.connectedPeerCount)/\(deps.dashboardViewModel.totalPeerCount)")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("MCP") {
                        Text("\(deps.dashboardViewModel.connectedMCPServerCount)/\(deps.dashboardViewModel.configuredMCPServerCount)")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Sessions") {
                        Text("\(deps.dashboardViewModel.totalSessionCount)")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Watchlist") {
                        Text("\(deps.agentWatchlistStore.watchedAgentIDs.count)")
                            .foregroundStyle(deps.agentWatchlistStore.watchedAgentIDs.isEmpty ? .tertiary : .secondary)
                    }
                    LabeledContent("On Call Queue") {
                        Text("\(onCallQueueCount)")
                            .foregroundStyle(onCallQueueCount > 0 ? .orange : .secondary)
                    }
                    LabeledContent("Muted Alerts") {
                        Text("\(activeMutedAlertCount)")
                            .foregroundStyle(activeMutedAlertCount > 0 ? .secondary : .tertiary)
                    }
                    LabeledContent("Incident Snapshot") {
                        Text(snapshotStatus.label)
                            .foregroundStyle(snapshotStatus.color)
                    }
                    LabeledContent("Audit") {
                        Text(auditStatus)
                            .foregroundStyle(deps.dashboardViewModel.hasAuditIntegrityIssue ? .red : .secondary)
                    }
                    LabeledContent("Security") {
                        Text("\(deps.dashboardViewModel.securityFeatureCount) features")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "LibreFang iOS")
                    if let health = deps.dashboardViewModel.health {
                        LabeledContent("Server Version", value: health.version)
                        LabeledContent("Server Status", value: health.status)
                    }
                    if let refresh = deps.dashboardViewModel.lastRefresh {
                        LabeledContent("Last Refresh") {
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

    private var auditStatus: String {
        guard let verify = deps.dashboardViewModel.auditVerify else { return String(localized: "Unavailable") }
        return verify.valid ? String(localized: "Verified") : String(localized: "Broken")
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

    private var snapshotStatus: SettingsSnapshotStatus {
        if visibleAlerts.isEmpty {
            return activeMutedAlertCount > 0 ? .muted : .clear
        }

        return deps.incidentStateStore.isCurrentSnapshotAcknowledged(alerts: deps.dashboardViewModel.monitoringAlerts)
            ? .acknowledged
            : .needsReview
    }

    private var notificationAuthorizationColor: Color {
        switch deps.onCallNotificationManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            .green
        case .denied:
            .red
        default:
            .secondary
        }
    }

    private var handoffFreshnessColor: Color {
        switch deps.onCallHandoffStore.freshnessState {
        case .fresh:
            .green
        case .stale:
            .orange
        case .missing:
            .red
        }
    }

    private var handoffCadenceColor: Color {
        switch deps.onCallHandoffStore.cadenceState {
        case .steady:
            .green
        case .sparse:
            .orange
        default:
            .secondary
        }
    }

    private func handoffKindColor(for kind: HandoffSnapshotKind) -> Color {
        switch kind {
        case .routine:
            .blue
        case .watch:
            .yellow
        case .incident:
            .red
        case .recovery:
            .green
        }
    }

    private func handoffDriftColor(for drift: HandoffSnapshotDrift) -> Color {
        switch drift.state {
        case .steady:
            .secondary
        case .improving:
            .green
        case .worsening:
            .red
        case .mixed:
            .orange
        }
    }

    private func handoffCarryoverColor(for carryover: HandoffCarryoverStatus) -> Color {
        switch carryover.state {
        case .cleared:
            .green
        case .partial:
            .orange
        case .active:
            .red
        }
    }

    private func handoffCheckInColor(for status: HandoffCheckInStatus) -> Color {
        switch status.state {
        case .scheduled:
            .blue
        case .dueSoon:
            .orange
        case .overdue:
            .red
        }
    }

    private var handoffReadinessColor: Color {
        switch draftHandoffReadiness.state {
        case .ready:
            .green
        case .caution:
            .orange
        case .blocked:
            .red
        }
    }
}

// MARK: - Helpers

private extension Double {
    func clamped(to range: ClosedRange<Double>, default defaultValue: Double) -> Double {
        if self == 0 { return defaultValue }
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

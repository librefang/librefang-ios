import SwiftUI

private enum SettingsSectionAnchor: Hashable {
    case server
    case refresh
    case language
    case onCall
    case reminder
    case handoff
    case monitoring
    case about
}

struct SettingsView: View {
    @Environment(\.dependencies) private var deps
    @Environment(\.openURL) private var openURL
    @State private var serverURL = ServerConfig.saved.baseURL
    @State private var apiKey = ServerConfig.saved.apiKey
    @State private var refreshInterval: Double = UserDefaults.standard.double(forKey: "refreshInterval").clamped(to: 10...300, default: 30)
    @State private var isSaving = false
    @State private var showSuccess = false

    private var primaryRouteCount: Int { 3 }
    private var supportRouteCount: Int { 2 }
    private var primaryControlCount: Int { 4 }
    private var supportControlCount: Int { 4 }
    private var utilityRouteCount: Int { 2 }
    private var settingsSectionCount: Int { 8 }
    private var settingsSectionPreviewTitles: [String] {
        [
            String(localized: "Server"),
            String(localized: "Auto Refresh"),
            String(localized: "Language"),
            String(localized: "On-Call Focus"),
            String(localized: "Standby Reminder"),
            String(localized: "Handoff"),
            String(localized: "Monitoring"),
            String(localized: "About")
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    Section {
                        MonitoringSnapshotCard(
                            summary: String(localized: "Settings keeps server, language, refresh, and on-call state visible before the longer forms."),
                            detail: String(localized: "Use this summary to confirm device-level monitoring behavior without digging through each section.")
                        ) {
                            FlowLayout(spacing: 8) {
                                SettingsBadge(text: currentLanguageLabel, tone: .neutral)
                                SettingsBadge(
                                    text: String(localized: "\(Int(refreshInterval))s refresh"),
                                    tone: .neutral
                                )
                                SettingsBadge(
                                    text: snapshotStatus.settingsLabel,
                                    tone: snapshotStatus.tone
                                )
                                SettingsBadge(
                                    text: onCallQueueCount == 1 ? String(localized: "1 on-call item") : String(localized: "\(onCallQueueCount) on-call items"),
                                    tone: onCallQueueStatus.tone
                                )
                                SettingsBadge(
                                    text: deps.onCallNotificationManager.authorizationLabel,
                                    tone: deps.onCallNotificationManager.authorizationStatus == .authorized ? .positive : .warning
                                )
                                if deps.onCallNotificationManager.pendingReminderDate != nil {
                                    SettingsBadge(text: deps.onCallNotificationManager.pendingReminderSourceLabel, tone: .caution)
                                }
                            }
                        }

                        MonitoringSurfaceGroupCard(
                            title: String(localized: "Shortcuts"),
                            detail: String(localized: "Keep the highest-value monitoring exits together before the longer device-control form.")
                        ) {
                            MonitoringShortcutRail(
                                title: String(localized: "Primary"),
                                detail: String(localized: "Keep the shift-management routes closest to settings.")
                            ) {
                                NavigationLink {
                                    OnCallView()
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "On Call"),
                                        systemImage: "waveform.path.ecg",
                                        tone: onCallQueueStatus.tone,
                                        badgeText: onCallQueueCount > 0 ? "\(onCallQueueCount)" : nil
                                    )
                                }
                                .buttonStyle(.plain)

                                NavigationLink {
                                    IncidentsView()
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "Incidents"),
                                        systemImage: "bell.badge",
                                        tone: currentCriticalCount > 0 ? .critical : .neutral,
                                        badgeText: currentCriticalCount > 0 ? "\(currentCriticalCount)" : nil
                                    )
                                }
                                .buttonStyle(.plain)

                                NavigationLink {
                                    HandoffCenterView(
                                        summary: handoffText,
                                        queueCount: onCallQueueCount,
                                        criticalCount: currentCriticalCount,
                                        liveAlertCount: visibleAlertCount
                                    )
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "Handoff"),
                                        systemImage: "text.badge.plus",
                                        tone: deps.onCallHandoffStore.freshnessState.tone
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            MonitoringShortcutRail(
                                title: String(localized: "Support"),
                                detail: String(localized: "Keep runtime and diagnostics behind the primary shift-management exits.")
                            ) {
                                NavigationLink {
                                    RuntimeView()
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "Runtime"),
                                        systemImage: "server.rack",
                                        tone: snapshotStatus.tone
                                    )
                                }
                                .buttonStyle(.plain)

                                NavigationLink {
                                    DiagnosticsView()
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "Diagnostics"),
                                        systemImage: "stethoscope",
                                        tone: .neutral
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        MonitoringSurfaceGroupCard(
                            title: String(localized: "Controls"),
                            detail: String(localized: "Keep the longest settings groups reachable on a single-handed mobile layout.")
                        ) {
                            MonitoringShortcutRail(
                                title: String(localized: "Primary"),
                                detail: String(localized: "Keep the most frequently adjusted device settings closest to the top of the form.")
                            ) {
                                Button {
                                    jump(proxy, to: .server)
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "Server"),
                                        systemImage: "server.rack",
                                        tone: snapshotStatus.tone
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    jump(proxy, to: .refresh)
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "Refresh"),
                                        systemImage: "arrow.clockwise",
                                        tone: .neutral,
                                        badgeText: "\(Int(refreshInterval))s"
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    jump(proxy, to: .language)
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "Language"),
                                        systemImage: "globe",
                                        tone: .neutral
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    jump(proxy, to: .onCall)
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "On-Call Focus"),
                                        systemImage: "waveform.path.ecg",
                                        tone: onCallQueueStatus.tone,
                                        badgeText: onCallQueueCount > 0 ? "\(onCallQueueCount)" : nil
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            MonitoringShortcutRail(
                                title: String(localized: "Support"),
                                detail: String(localized: "Keep reminders, handoff state, monitoring summary, and app metadata behind the primary jumps.")
                            ) {
                                Button {
                                    jump(proxy, to: .reminder)
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "Reminder"),
                                        systemImage: "bell.badge",
                                        tone: deps.onCallNotificationManager.authorizationStatus == .authorized ? .positive : .warning
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    jump(proxy, to: .handoff)
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "Handoff"),
                                        systemImage: "text.badge.plus",
                                        tone: deps.onCallHandoffStore.freshnessState.tone
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    jump(proxy, to: .monitoring)
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "Monitoring"),
                                        systemImage: "chart.bar.xaxis",
                                        tone: snapshotStatus.tone
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    jump(proxy, to: .about)
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "About"),
                                        systemImage: "info.circle",
                                        tone: .neutral
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("Controls")
                    } footer: {
                        Text("Keep snapshot, routes, and device controls together before the longer settings form.")
                    }

                    Section("Server") {
                    SettingsServerSnapshotCard(
                        serverURL: serverURL,
                        apiKey: apiKey,
                        serverStatusLabel: deps.dashboardViewModel.health?.localizedStatusLabel ?? String(localized: "Unavailable"),
                        serverStatusTone: deps.dashboardViewModel.health?.statusTone ?? .neutral,
                        connectionHint: serverConnectionHint
                    )

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

                    Text(serverConnectionHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .id(SettingsSectionAnchor.server)

                    Section("Auto Refresh") {
                    SettingsRefreshSnapshotCard(
                        refreshInterval: Int(refreshInterval),
                        lastRefresh: deps.dashboardViewModel.lastRefresh
                    )

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
                .id(SettingsSectionAnchor.refresh)

                    Section("Language") {
                    SettingsLanguageSnapshotCard(
                        currentLanguageLabel: currentLanguageLabel,
                        supportedLanguageLabels: supportedLanguageLabels
                    )

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

                    Text("LibreFang iOS follows iPhone per-app language settings so String Catalog translations stay consistent across SwiftUI views and system surfaces. In Settings, open the app page and choose Language.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .id(SettingsSectionAnchor.language)

                    Section {
                        MonitoringSurfaceGroupCard(
                            title: String(localized: "Utility Deck"),
                            detail: String(localized: "Keep secondary runtime catalogs and external-agent routes close without letting them crowd the primary control deck.")
                        ) {
                            MonitoringShortcutRail(
                                title: String(localized: "Secondary Catalogs"),
                                detail: String(localized: "Open supporting runtime inventories when device settings need adjacent catalog context.")
                            ) {
                                NavigationLink {
                                    A2AAgentsView()
                                        .navigationTitle(String(localized: "A2A Agents"))
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "External Agents"),
                                        systemImage: "link.circle",
                                        tone: .neutral,
                                        badgeText: deps.dashboardViewModel.a2aAgents.map { String($0.total) }
                                    )
                                }
                                .buttonStyle(.plain)

                                NavigationLink {
                                    ToolProfilesView()
                                } label: {
                                    MonitoringSurfaceShortcutChip(
                                        title: String(localized: "Tool Profiles"),
                                        systemImage: "person.crop.rectangle.stack",
                                        tone: .neutral
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("Utility Deck")
                    }

                    Section("On Call Focus") {
                    SettingsBadgeFlow(items: onCallFocusBadges)

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
                .id(SettingsSectionAnchor.onCall)

                    Section("Standby Reminder") {
                    SettingsReminderSnapshotCard(
                        isEnabled: deps.onCallNotificationManager.isEnabled,
                        authorizationLabel: deps.onCallNotificationManager.authorizationLabel,
                        authorizationTone: deps.onCallNotificationManager.authorizationTone,
                        authorizationSummary: deps.onCallNotificationManager.authorizationSummary,
                        scopeLabel: deps.onCallNotificationManager.isEnabled ? deps.onCallNotificationManager.scope.label : nil,
                        delayMinutes: deps.onCallNotificationManager.isEnabled ? deps.onCallNotificationManager.remindAfterMinutes : nil,
                        pendingReminderLabel: deps.onCallNotificationManager.pendingReminderLabel,
                        pendingReminderSourceLabel: deps.onCallNotificationManager.pendingReminderSourceLabel,
                        pendingReminderSummary: deps.onCallNotificationManager.pendingReminderSummary
                    )

                    SettingsBadgeFlow(items: standbyReminderBadges)

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
                .id(SettingsSectionAnchor.reminder)

                    Section("Handoff") {
                    MonitoringSnapshotCard(
                        summary: deps.onCallHandoffStore.freshnessSummary,
                        detail: draftHandoffReadiness.summary
                    ) {
                        SettingsBadgeFlow(items: handoffSummaryBadges)
                    }

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
                .id(SettingsSectionAnchor.handoff)

                    Section("Monitoring") {
                    MonitoringSnapshotCard(
                        summary: String(localized: "Device-local monitoring state stays visible here before the longer per-signal rows."),
                        detail: String(localized: "Use this digest to confirm queue pressure, watchlist pressure, and readiness signals without scanning every value.")
                    ) {
                        SettingsBadgeFlow(items: monitoringSummaryBadges)
                    }

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
                .id(SettingsSectionAnchor.monitoring)

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
                .id(SettingsSectionAnchor.about)
                }
                .navigationTitle(String(localized: "Settings"))
            }
        }
    }

    private func jump(_ proxy: ScrollViewProxy, to anchor: SettingsSectionAnchor) {
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    private func settingsSectionPreviewJumpItems(_ proxy: ScrollViewProxy) -> [MonitoringSectionJumpItem] {
        [
            MonitoringSectionJumpItem(
                title: String(localized: "Server"),
                systemImage: "server.rack",
                tone: snapshotStatus.tone
            ) {
                jump(proxy, to: .server)
            },
            MonitoringSectionJumpItem(
                title: String(localized: "Refresh"),
                systemImage: "arrow.clockwise",
                tone: .neutral
            ) {
                jump(proxy, to: .refresh)
            },
            MonitoringSectionJumpItem(
                title: String(localized: "Language"),
                systemImage: "globe",
                tone: .neutral
            ) {
                jump(proxy, to: .language)
            },
            MonitoringSectionJumpItem(
                title: String(localized: "On Call"),
                systemImage: "waveform.path.ecg",
                tone: onCallQueueStatus.tone
            ) {
                jump(proxy, to: .onCall)
            },
            MonitoringSectionJumpItem(
                title: String(localized: "Reminder"),
                systemImage: "bell.badge",
                tone: deps.onCallNotificationManager.pendingReminderDate != nil
                    ? .caution
                    : (deps.onCallNotificationManager.authorizationStatus == .authorized ? .neutral : .warning)
            ) {
                jump(proxy, to: .reminder)
            },
            MonitoringSectionJumpItem(
                title: String(localized: "Handoff"),
                systemImage: "text.badge.plus",
                tone: deps.onCallHandoffStore.freshnessState.tone
            ) {
                jump(proxy, to: .handoff)
            },
            MonitoringSectionJumpItem(
                title: String(localized: "Monitoring"),
                systemImage: "gauge.with.dots.needle.33percent",
                tone: currentCriticalCount > 0 ? .critical : (visibleAlertCount > 0 ? .warning : .neutral)
            ) {
                jump(proxy, to: .monitoring)
            },
            MonitoringSectionJumpItem(
                title: String(localized: "About"),
                systemImage: "info.circle",
                tone: .neutral
            ) {
                jump(proxy, to: .about)
            }
        ]
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

    private var onCallFocusBadges: [SettingsBadgeItem] {
        [
            SettingsBadgeItem(text: deps.onCallFocusStore.mode.label, tone: .warning),
            SettingsBadgeItem(text: deps.onCallFocusStore.preferredSurface.label, tone: .neutral),
            SettingsBadgeItem(
                text: deps.onCallFocusStore.showsMutedSummary ? String(localized: "Muted Summary On") : String(localized: "Muted Summary Off"),
                tone: deps.onCallFocusStore.showsMutedSummary ? .positive : .neutral
            ),
            SettingsBadgeItem(
                text: deps.onCallFocusStore.showsForegroundCues ? String(localized: "Cue On") : String(localized: "Cue Off"),
                tone: deps.onCallFocusStore.showsForegroundCues ? .positive : .neutral
            ),
        ]
    }

    private var standbyReminderBadges: [SettingsBadgeItem] {
        var items: [SettingsBadgeItem] = [
            SettingsBadgeItem(
                text: deps.onCallNotificationManager.isEnabled ? String(localized: "Reminder On") : String(localized: "Reminder Off"),
                tone: deps.onCallNotificationManager.isEnabled ? .positive : .neutral
            ),
            SettingsBadgeItem(
                text: deps.onCallNotificationManager.authorizationLabel,
                tone: deps.onCallNotificationManager.authorizationStatus == .authorized ? .positive : .warning
            ),
        ]

        if deps.onCallNotificationManager.isEnabled {
            items.append(SettingsBadgeItem(text: deps.onCallNotificationManager.scope.label, tone: .warning))
        }

        if deps.onCallNotificationManager.pendingReminderDate != nil {
            items.append(SettingsBadgeItem(text: deps.onCallNotificationManager.pendingReminderSourceLabel, tone: .caution))
        }

        return items
    }

    private var handoffSummaryBadges: [SettingsBadgeItem] {
        var items: [SettingsBadgeItem] = [
            SettingsBadgeItem(text: deps.onCallHandoffStore.freshnessLabel, tone: deps.onCallHandoffStore.freshnessState.tone),
            SettingsBadgeItem(text: draftHandoffReadiness.state.label, tone: draftHandoffReadiness.state.tone),
        ]

        if let latest = deps.onCallHandoffStore.latestEntry {
            items.append(SettingsBadgeItem(text: latest.kind.label, tone: .neutral))
            items.append(SettingsBadgeItem(text: latest.focusAreas.summaryLabel, tone: handoffFocusStatus(for: latest).tone))
        }

        if let checkInStatus = deps.onCallHandoffStore.latestCheckInStatus {
            items.append(SettingsBadgeItem(text: checkInStatus.state.label, tone: checkInStatus.state.tone))
        }

        let followUpSummary = deps.onCallHandoffStore.latestFollowUpSummary
        items.append(SettingsBadgeItem(text: followUpSummary.settingsLabel, tone: followUpSummary.tone))

        return items
    }

    private var monitoringSummaryBadges: [SettingsBadgeItem] {
        [
            SettingsBadgeItem(text: deps.dashboardViewModel.agentAttentionStatus.summary, tone: deps.dashboardViewModel.agentAttentionStatus.tone),
            SettingsBadgeItem(text: deps.dashboardViewModel.providerReadinessStatus.summary, tone: deps.dashboardViewModel.providerReadinessStatus.tone),
            SettingsBadgeItem(text: deps.dashboardViewModel.channelReadinessStatus.summary, tone: deps.dashboardViewModel.channelReadinessStatus.tone),
            SettingsBadgeItem(text: deps.dashboardViewModel.approvalBacklogStatus.summary, tone: deps.dashboardViewModel.approvalBacklogStatus.tone),
            SettingsBadgeItem(text: onCallQueueCount == 1 ? String(localized: "1 on-call item") : String(localized: "\(onCallQueueCount) on-call items"), tone: onCallQueueStatus.tone),
            SettingsBadgeItem(text: activeMutedAlertCount == 1 ? String(localized: "1 muted alert") : String(localized: "\(activeMutedAlertCount) muted alerts"), tone: mutedAlertStatus.tone),
            SettingsBadgeItem(text: deps.agentWatchlistStore.watchedAgentIDs.count == 1 ? String(localized: "1 watched agent") : String(localized: "\(deps.agentWatchlistStore.watchedAgentIDs.count) watched agents"), tone: watchlistStatus.tone),
            SettingsBadgeItem(text: snapshotStatus.settingsLabel, tone: snapshotStatus.tone),
        ]
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

private struct SettingsServerSnapshotCard: View {
    let serverURL: String
    let apiKey: String
    let serverStatusLabel: String
    let serverStatusTone: PresentationTone
    let connectionHint: String

    private var trimmedURL: String {
        serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hostLabel: String {
        guard !trimmedURL.isEmpty else { return String(localized: "No server URL") }
        return URL(string: trimmedURL)?.host ?? trimmedURL
    }

    private var hostTone: PresentationTone {
        let normalized = trimmedURL.lowercased()
        if normalized.contains("127.0.0.1") || normalized.contains("localhost") {
            return .warning
        }
        return trimmedURL.isEmpty ? .neutral : .positive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: connectionHint,
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    SettingsBadge(text: hostLabel, tone: hostTone)
                    SettingsBadge(
                        text: apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "No API key") : String(localized: "API key set"),
                        tone: apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .neutral : .positive
                    )
                    SettingsBadge(text: serverStatusLabel, tone: serverStatusTone)
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Server settings snapshot"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep address scope, auth state, and current server reachability visible before editing connection fields."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                SettingsBadge(
                    text: trimmedURL.isEmpty ? String(localized: "Unset") : String(localized: "Configured"),
                    tone: trimmedURL.isEmpty ? .neutral : .positive
                )
            } facts: {
                Label(hostLabel, systemImage: "server.rack")
                Label(
                    apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "No auth override") : String(localized: "Auth override present"),
                    systemImage: "key"
                )
                Label(serverStatusLabel, systemImage: "bolt.horizontal.circle")
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if trimmedURL.isEmpty {
            return String(localized: "No server endpoint is configured for this device yet.")
        }
        return String(localized: "This device is pointed at \(hostLabel) for runtime refreshes and action routing.")
    }
}

private struct SettingsRefreshSnapshotCard: View {
    let refreshInterval: Int
    let lastRefresh: Date?

    private var refreshTone: PresentationTone {
        if refreshInterval <= 15 {
            return .warning
        }
        if refreshInterval >= 60 {
            return .neutral
        }
        return .positive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Dashboard refresh is set to every \(refreshInterval) seconds."),
                detail: String(localized: "Shorter intervals keep mobile triage fresh but increase server polling pressure."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    SettingsBadge(text: String(localized: "\(refreshInterval)s cadence"), tone: refreshTone)
                    if let lastRefresh {
                        SettingsBadge(
                            text: RelativeDateTimeFormatter().localizedString(for: lastRefresh, relativeTo: Date()),
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Refresh snapshot"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the polling cadence and latest successful refresh visible before tuning the device refresh slider."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                SettingsBadge(
                    text: refreshInterval <= 15 ? String(localized: "Fast") : refreshInterval >= 60 ? String(localized: "Relaxed") : String(localized: "Balanced"),
                    tone: refreshTone
                )
            } facts: {
                Label(String(localized: "\(refreshInterval)s interval"), systemImage: "arrow.clockwise")
                if let lastRefresh {
                    Label(RelativeDateTimeFormatter().localizedString(for: lastRefresh, relativeTo: Date()), systemImage: "clock")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsLanguageSnapshotCard: View {
    let currentLanguageLabel: String
    let supportedLanguageLabels: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "This iPhone is currently using \(currentLanguageLabel) for LibreFang."),
                detail: String(localized: "Per-app language is controlled in iPhone settings, so UI strings and system surfaces stay aligned."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    SettingsBadge(text: currentLanguageLabel, tone: .neutral)
                    SettingsBadge(
                        text: supportedLanguageLabels.count == 1 ? String(localized: "1 supported language") : String(localized: "\(supportedLanguageLabels.count) supported languages"),
                        tone: .positive
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Language snapshot"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the active locale and supported catalog visible before leaving the app for system language settings."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                SettingsBadge(text: String(localized: "Per-app"), tone: .neutral)
            } facts: {
                Label(currentLanguageLabel, systemImage: "globe")
                Label(
                    supportedLanguageLabels.count == 1 ? String(localized: "1 supported language") : String(localized: "\(supportedLanguageLabels.count) supported languages"),
                    systemImage: "textformat.abc"
                )
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsReminderSnapshotCard: View {
    let isEnabled: Bool
    let authorizationLabel: String
    let authorizationTone: PresentationTone
    let authorizationSummary: String
    let scopeLabel: String?
    let delayMinutes: Int?
    let pendingReminderLabel: String
    let pendingReminderSourceLabel: String
    let pendingReminderSummary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: pendingReminderSummary ?? authorizationSummary,
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    SettingsBadge(
                        text: isEnabled ? String(localized: "Reminder On") : String(localized: "Reminder Off"),
                        tone: isEnabled ? .positive : .neutral
                    )
                    SettingsBadge(text: authorizationLabel, tone: authorizationTone)
                    if let scopeLabel {
                        SettingsBadge(text: scopeLabel, tone: .warning)
                    }
                    if let delayMinutes {
                        SettingsBadge(text: String(localized: "\(delayMinutes) min"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Reminder snapshot"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep authorization, arming scope, and any queued reminder visible before adjusting standby reminder controls."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                SettingsBadge(
                    text: pendingReminderSummary == nil ? String(localized: "No queued reminder") : String(localized: "Queued"),
                    tone: pendingReminderSummary == nil ? .neutral : .caution
                )
            } facts: {
                Label(pendingReminderLabel, systemImage: "bell.badge")
                Label(pendingReminderSourceLabel, systemImage: "arrow.triangle.2.circlepath")
                if let delayMinutes {
                    Label(String(localized: "\(delayMinutes) min delay"), systemImage: "timer")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if !isEnabled {
            return String(localized: "Standby reminders are currently disabled on this device.")
        }
        return String(localized: "Standby reminders are armed for queued on-call pressure on this device.")
    }
}

private struct SettingsRouteInventoryDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let primaryControlCount: Int
    let supportControlCount: Int
    let utilityRouteCount: Int
    let onCallQueueCount: Int
    let currentCriticalCount: Int
    let refreshIntervalLabel: String
    let languageLabel: String

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
                    text: primaryControlCount == 1 ? String(localized: "1 primary control") : String(localized: "\(primaryControlCount) primary controls"),
                    tone: .neutral
                )
                PresentationToneBadge(
                    text: supportControlCount == 1 ? String(localized: "1 support control") : String(localized: "\(supportControlCount) support controls"),
                    tone: .neutral
                )
                PresentationToneBadge(
                    text: utilityRouteCount == 1 ? String(localized: "1 utility route") : String(localized: "\(utilityRouteCount) utility routes"),
                    tone: utilityRouteCount > 0 ? .positive : .neutral
                )
                if onCallQueueCount > 0 {
                    PresentationToneBadge(
                        text: onCallQueueCount == 1 ? String(localized: "1 on-call item") : String(localized: "\(onCallQueueCount) on-call items"),
                        tone: .warning
                    )
                }
                if currentCriticalCount > 0 {
                    PresentationToneBadge(
                        text: currentCriticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(currentCriticalCount) critical"),
                        tone: .critical
                    )
                }
                PresentationToneBadge(text: refreshIntervalLabel, tone: .neutral)
                PresentationToneBadge(text: languageLabel, tone: .neutral)
            }
        }
    }

    private var summaryLine: String {
        let totalItems = primaryRouteCount + supportRouteCount + primaryControlCount + supportControlCount + utilityRouteCount
        return totalItems == 1
            ? String(localized: "1 settings route or control is grouped in this deck.")
            : String(localized: "\(totalItems) settings routes and controls are grouped in this deck.")
    }

    private var detailLine: String {
        String(localized: "Monitoring exits, device controls, and utility routes stay summarized here before the longer settings form.")
    }
}

private struct SettingsSectionInventoryDeck: View {
    let sectionCount: Int
    let onCallQueueCount: Int
    let currentCriticalCount: Int
    let visibleAlertCount: Int
    let hasQueuedReminder: Bool
    let refreshIntervalLabel: String
    let languageLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: languageLabel, tone: .neutral)
                    PresentationToneBadge(text: refreshIntervalLabel, tone: .neutral)
                    PresentationToneBadge(
                        text: onCallQueueCount == 1 ? String(localized: "1 on-call item") : String(localized: "\(onCallQueueCount) on-call items"),
                        tone: onCallQueueCount > 0 ? .warning : .neutral
                    )
                    PresentationToneBadge(
                        text: hasQueuedReminder ? String(localized: "Reminder queued") : String(localized: "Reminder idle"),
                        tone: hasQueuedReminder ? .caution : .neutral
                    )
                    if currentCriticalCount > 0 {
                        PresentationToneBadge(
                            text: currentCriticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(currentCriticalCount) critical"),
                            tone: .critical
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Settings inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep device sections, queued reminders, and on-call pressure visible before the longer settings form opens up."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: sectionCount == 1 ? String(localized: "1 section") : String(localized: "\(sectionCount) sections"),
                    tone: sectionCount > 0 ? .positive : .neutral
                )
            } facts: {
                Label(languageLabel, systemImage: "globe")
                Label(String(localized: "Refresh \(refreshIntervalLabel)"), systemImage: "arrow.clockwise")
                Label(
                    visibleAlertCount == 1 ? String(localized: "1 live alert") : String(localized: "\(visibleAlertCount) live alerts"),
                    systemImage: "bell.badge"
                )
                Label(
                    hasQueuedReminder ? String(localized: "Reminder armed") : String(localized: "Reminder idle"),
                    systemImage: "bell"
                )
            }
        }
    }

    private var summaryLine: String {
        sectionCount == 1
            ? String(localized: "1 settings section is loaded into the compact device deck.")
            : String(localized: "\(sectionCount) settings sections are loaded into the compact device deck.")
    }

    private var detailLine: String {
        String(localized: "Server, language, refresh, on-call, reminder, handoff, monitoring, and about sections stay summarized before the deeper form.")
    }
}

private struct SettingsPressureCoverageDeck: View {
    let onCallQueueCount: Int
    let currentCriticalCount: Int
    let visibleAlertCount: Int
    let hasQueuedReminder: Bool
    let notificationLabel: String
    let notificationTone: PresentationTone
    let refreshIntervalLabel: String
    let languageLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: String(localized: "Pressure coverage keeps on-call state, reminders, and device readiness readable before the longer settings form."),
                detail: String(localized: "Use this deck to judge whether the phone is currently burdened by queue pressure, critical alerts, or reminder state rather than static configuration."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if onCallQueueCount > 0 {
                        PresentationToneBadge(
                            text: onCallQueueCount == 1 ? String(localized: "1 on-call item") : String(localized: "\(onCallQueueCount) on-call items"),
                            tone: .warning
                        )
                    }
                    if currentCriticalCount > 0 {
                        PresentationToneBadge(
                            text: currentCriticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(currentCriticalCount) critical"),
                            tone: .critical
                        )
                    }
                    PresentationToneBadge(text: notificationLabel, tone: notificationTone)
                    if hasQueuedReminder {
                        PresentationToneBadge(text: String(localized: "Reminder queued"), tone: .caution)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Pressure coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep mobile readiness, queue pressure, and reminder state readable before opening the full settings form."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: refreshIntervalLabel, tone: .neutral)
            } facts: {
                Label(languageLabel, systemImage: "globe")
                Label(
                    visibleAlertCount == 1 ? String(localized: "1 live alert") : String(localized: "\(visibleAlertCount) live alerts"),
                    systemImage: "bell.badge"
                )
                if hasQueuedReminder {
                    Label(String(localized: "Reminder queued"), systemImage: "bell.badge.fill")
                }
            }
        }
    }
}

private struct SettingsSupportCoverageDeck: View {
    let onCallQueueCount: Int
    let currentCriticalCount: Int
    let visibleAlertCount: Int
    let hasQueuedReminder: Bool
    let notificationLabel: String
    let notificationTone: PresentationTone
    let refreshIntervalLabel: String
    let languageLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep reminder state, notification readiness, refresh cadence, and language context readable before opening the full device form."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: notificationLabel, tone: notificationTone)
                    PresentationToneBadge(text: languageLabel, tone: .neutral)
                    PresentationToneBadge(text: refreshIntervalLabel, tone: .neutral)
                    if hasQueuedReminder {
                        PresentationToneBadge(text: String(localized: "Reminder queued"), tone: .caution)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Support coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep device readiness, reminder state, and low-frequency monitoring context visible before the settings form expands into controls and toggles."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: onCallQueueCount == 1 ? String(localized: "1 on-call item") : String(localized: "\(onCallQueueCount) on-call items"),
                    tone: onCallQueueCount > 0 ? .warning : .neutral
                )
            } facts: {
                Label(
                    visibleAlertCount == 1 ? String(localized: "1 live alert") : String(localized: "\(visibleAlertCount) live alerts"),
                    systemImage: "bell.badge"
                )
                if currentCriticalCount > 0 {
                    Label(
                        currentCriticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(currentCriticalCount) critical"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if hasQueuedReminder {
                    Label(String(localized: "Reminder queued"), systemImage: "bell.badge.fill")
                }
            }
        }
    }

    private var summaryLine: String {
        if hasQueuedReminder {
            return String(localized: "Settings support coverage is currently anchored by reminder state and device readiness.")
        }
        if onCallQueueCount > 0 || visibleAlertCount > 0 || currentCriticalCount > 0 {
            return String(localized: "Settings support coverage is currently anchored by live monitoring load reaching the device layer.")
        }
        return String(localized: "Settings support coverage is currently light and mostly reflects refresh cadence and language readiness.")
    }
}

private struct SettingsWorkstreamCoverageDeck: View {
    let onCallQueueCount: Int
    let currentCriticalCount: Int
    let visibleAlertCount: Int
    let hasQueuedReminder: Bool
    let notificationLabel: String
    let notificationTone: PresentationTone
    let refreshIntervalLabel: String
    let languageLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to see whether settings is currently led by live device-facing monitoring, queued reminder follow-through, or passive device configuration context before the longer form opens."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: notificationLabel, tone: notificationTone)
                    PresentationToneBadge(text: languageLabel, tone: .neutral)
                    PresentationToneBadge(text: refreshIntervalLabel, tone: .neutral)
                    if hasQueuedReminder {
                        PresentationToneBadge(text: String(localized: "Reminder queued"), tone: .caution)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Workstream coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep live alert reach, on-call follow-through, and slower device configuration context readable before the server, reminder, and monitoring forms take over."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: onCallQueueCount == 1 ? String(localized: "1 on-call item") : String(localized: "\(onCallQueueCount) on-call items"),
                    tone: onCallQueueCount > 0 ? .warning : .neutral
                )
            } facts: {
                Label(
                    visibleAlertCount == 1 ? String(localized: "1 live alert") : String(localized: "\(visibleAlertCount) live alerts"),
                    systemImage: "bell.badge"
                )
                if currentCriticalCount > 0 {
                    Label(
                        currentCriticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(currentCriticalCount) critical"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if hasQueuedReminder {
                    Label(String(localized: "Reminder queued"), systemImage: "bell.badge.fill")
                }
                Label(languageLabel, systemImage: "globe")
            }
        }
    }

    private var summaryLine: String {
        if currentCriticalCount > 0 || visibleAlertCount > 0 {
            return String(localized: "Settings workstream coverage is currently anchored by live monitoring reaching the device layer.")
        }
        if onCallQueueCount > 0 || hasQueuedReminder {
            return String(localized: "Settings workstream coverage is currently anchored by on-call follow-through and queued reminder state.")
        }
        return String(localized: "Settings workstream coverage is currently anchored by passive device configuration context.")
    }
}

private struct SettingsActionReadinessDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let primaryControlCount: Int
    let supportControlCount: Int
    let utilityRouteCount: Int
    let sectionCount: Int
    let onCallQueueCount: Int
    let currentCriticalCount: Int
    let visibleAlertCount: Int
    let hasQueuedReminder: Bool
    let refreshIntervalLabel: String
    let languageLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to confirm control breadth, route exits, and live device readiness before opening the longer settings form."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: String(localized: "\(primaryRouteCount + supportRouteCount + primaryControlCount + supportControlCount + utilityRouteCount) actions"),
                        tone: .neutral
                    )
                    PresentationToneBadge(
                        text: sectionCount == 1 ? String(localized: "1 section") : String(localized: "\(sectionCount) sections"),
                        tone: sectionCount > 0 ? .positive : .neutral
                    )
                    PresentationToneBadge(text: refreshIntervalLabel, tone: .neutral)
                    PresentationToneBadge(text: languageLabel, tone: .neutral)
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Action readiness"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep route exits, device controls, and live monitoring load visible before the server, reminder, handoff, and monitoring settings expand into the full form."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: onCallQueueCount == 1 ? String(localized: "1 on-call item") : String(localized: "\(onCallQueueCount) on-call items"),
                    tone: onCallQueueCount > 0 ? .warning : .neutral
                )
            } facts: {
                Label(
                    visibleAlertCount == 1 ? String(localized: "1 live alert") : String(localized: "\(visibleAlertCount) live alerts"),
                    systemImage: "bell.badge"
                )
                if currentCriticalCount > 0 {
                    Label(
                        currentCriticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(currentCriticalCount) critical"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if hasQueuedReminder {
                    Label(String(localized: "Reminder queued"), systemImage: "bell.badge.fill")
                }
                Label(languageLabel, systemImage: "globe")
            }
        }
    }

    private var summaryLine: String {
        if currentCriticalCount > 0 || visibleAlertCount > 0 {
            return String(localized: "Settings action readiness is currently anchored by live alert pressure reaching the device layer.")
        }
        if onCallQueueCount > 0 || hasQueuedReminder {
            return String(localized: "Settings action readiness is currently centered on on-call queue state and reminder follow-through.")
        }
        return String(localized: "Settings action readiness is currently clear enough for route pivots and deeper settings review.")
    }
}

private struct SettingsFocusCoverageDeck: View {
    let onCallQueueCount: Int
    let currentCriticalCount: Int
    let visibleAlertCount: Int
    let hasQueuedReminder: Bool
    let notificationLabel: String
    let notificationTone: PresentationTone
    let refreshIntervalLabel: String
    let languageLabel: String
    let sectionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep the dominant device-facing settings lane readable before opening the longer server, reminder, and monitoring form."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: notificationLabel, tone: notificationTone)
                    PresentationToneBadge(text: refreshIntervalLabel, tone: .neutral)
                    PresentationToneBadge(text: languageLabel, tone: .neutral)
                    if hasQueuedReminder {
                        PresentationToneBadge(text: String(localized: "Reminder queued"), tone: .caution)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Focus coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the dominant settings lane readable before moving from compact device readiness decks into the full control form."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: sectionCount == 1 ? String(localized: "1 section") : String(localized: "\(sectionCount) sections"),
                    tone: sectionCount > 0 ? .positive : .neutral
                )
            } facts: {
                if onCallQueueCount > 0 {
                    Label(
                        onCallQueueCount == 1 ? String(localized: "1 on-call item") : String(localized: "\(onCallQueueCount) on-call items"),
                        systemImage: "waveform.path.ecg"
                    )
                }
                if currentCriticalCount > 0 {
                    Label(
                        currentCriticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(currentCriticalCount) critical"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if visibleAlertCount > 0 {
                    Label(
                        visibleAlertCount == 1 ? String(localized: "1 live alert") : String(localized: "\(visibleAlertCount) live alerts"),
                        systemImage: "bell.badge"
                    )
                }
                if hasQueuedReminder {
                    Label(String(localized: "Reminder queued"), systemImage: "bell.badge.fill")
                }
                Label(languageLabel, systemImage: "globe")
                Label(String(localized: "Refresh \(refreshIntervalLabel)"), systemImage: "arrow.clockwise")
            }
        }
    }

    private var summaryLine: String {
        if currentCriticalCount > 0 || visibleAlertCount > 0 {
            return String(localized: "Settings focus coverage is currently anchored by live alert pressure reaching the device layer.")
        }
        if onCallQueueCount > 0 || hasQueuedReminder {
            return String(localized: "Settings focus coverage is currently anchored by on-call follow-through and reminder state.")
        }
        return String(localized: "Settings focus coverage is currently centered on notification, refresh, and language readiness.")
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

private struct SettingsBadgeFlow: View {
    let items: [SettingsBadgeItem]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items) { item in
                SettingsBadge(text: item.text, tone: item.tone)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsBadgeItem: Identifiable {
    let text: String
    let tone: PresentationTone

    var id: String { text }
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

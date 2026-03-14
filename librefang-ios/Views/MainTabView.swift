import SwiftUI

struct MainTabView: View {
    @Environment(\.dependencies) private var deps
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var showOnCall = false
    @State private var incidentCue: ActiveIncidentCue?
    @State private var hasObservedCriticalState = false

    private var vm: DashboardViewModel { deps.dashboardViewModel }
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
        deps.agentWatchlistStore
            .watchedAgents(from: vm.agents)
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
    private var criticalTrackingState: CriticalTrackingState {
        CriticalTrackingState(
            count: visibleCriticalAlertCount,
            signature: visibleCriticalAlerts
                .map { "\($0.id)|\($0.title)|\($0.detail)" }
                .sorted()
                .joined(separator: "||")
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
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
            .onChange(of: selectedTab) {
                HapticManager.selection()
            }

            topOverlay
        }
        .onAppear {
            deps.dashboardViewModel.startAutoRefresh(interval: storedRefreshInterval)
            Task { await deps.onCallNotificationManager.refreshAuthorizationStatus() }
        }
        .onChange(of: criticalTrackingState) { oldValue, newValue in
            handleCriticalTrackingChange(from: oldValue, to: newValue)
        }
        .onChange(of: isCurrentSnapshotAcknowledged) { _, isAcknowledged in
            if isAcknowledged {
                incidentCue = nil
            }
        }
        .onChange(of: showsForegroundCues) { _, isEnabled in
            if !isEnabled {
                incidentCue = nil
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
                }
            case .background:
                deps.dashboardViewModel.stopAutoRefresh()
                incidentCue = nil
                Task {
                    await deps.onCallNotificationManager.armStandbyReminder(snapshot: reminderSnapshot)
                }
            default:
                break
            }
        }
        .task(id: incidentCue?.id) {
            guard let cueID = incidentCue?.id else { return }
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard incidentCue?.id == cueID else { return }
            incidentCue = nil
        }
        .sheet(isPresented: $showOnCall) {
            NavigationStack {
                preferredSurfaceView
            }
        }
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
            isAcknowledged: isCurrentSnapshotAcknowledged
        )
    }

    @ViewBuilder
    private var preferredSurfaceView: some View {
        switch preferredOnCallSurface {
        case .onCall:
            OnCallView()
        case .nightWatch:
            NightWatchView()
        case .standbyDigest:
            StandbyDigestView()
        }
    }

    @ViewBuilder
    private var topOverlay: some View {
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
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: incidentCue?.id)
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
        incidentCue = ActiveIncidentCue(
            id: newValue.signature,
            title: newValue.count == 1
                ? (leadAlert?.title ?? "Critical incident changed")
                : "\(newValue.count) critical incidents changed",
            detail: newValue.count == 1
                ? (leadAlert?.detail ?? "Open the on-call surface to review the new state.")
                : "\(leadAlert?.title ?? "Critical queue changed") · Open the on-call surface to inspect the latest pressure."
        )
        HapticManager.notification(.error)
    }

    private func openPreferredSurface() {
        incidentCue = nil
        showOnCall = true
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

private struct CriticalIncidentBanner: View {
    let count: Int
    let mutedCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.badge.fill")
                .font(.caption)
            Text(count == 1 ? "1 critical incident active" : "\(count) critical incidents active")
                .font(.caption.weight(.semibold))
            Spacer()
            if mutedCount > 0 {
                Text("\(mutedCount) muted")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.12))
                    .clipShape(Capsule())
            }
            Text("On Call")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.18))
                .clipShape(Capsule())
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.red.opacity(0.92))
    }
}

private struct AcknowledgedIncidentBanner: View {
    let count: Int
    let mutedCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.caption)
            Text(count == 1 ? "1 critical incident acknowledged" : "\(count) critical incidents acknowledged")
                .font(.caption.weight(.semibold))
            Spacer()
            if mutedCount > 0 {
                Text("\(mutedCount) muted")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.12))
                    .clipShape(Capsule())
            }
            Text("On Call")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.18))
                .clipShape(Capsule())
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.92))
    }
}

private struct IncidentCueBanner: View {
    let cue: ActiveIncidentCue
    let onOpen: () -> Void
    let onAcknowledge: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(8)
                        .background(.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Button(action: onAcknowledge) {
                    Label("Acknowledge", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(IncidentCueActionButtonStyle(fill: .white.opacity(0.12)))

                Button(action: onOpen) {
                    Label("Open", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(IncidentCueActionButtonStyle(fill: .white.opacity(0.22)))
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
}

private struct IncidentCueActionButtonStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(fill.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

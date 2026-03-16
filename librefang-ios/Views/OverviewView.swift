import SwiftUI

struct OverviewView: View {
    @Environment(\.dependencies) private var deps

    private var vm: DashboardViewModel { deps.dashboardViewModel }
    private var visibleMonitoringAlerts: [MonitoringAlertItem] {
        deps.incidentStateStore.visibleAlerts(from: vm.monitoringAlerts)
    }
    private var activeMutedAlertCount: Int {
        deps.incidentStateStore.activeMutedAlerts(from: vm.monitoringAlerts).count
    }
    private var isCurrentSnapshotAcknowledged: Bool {
        deps.incidentStateStore.isCurrentSnapshotAcknowledged(alerts: vm.monitoringAlerts)
    }
    private var watchedAttentionItems: [AgentAttentionItem] {
        watchedAgentAttentionItemsSorted(
            deps.agentWatchlistStore.watchedAgents(from: vm.agents)
                .map { vm.attentionItem(for: $0) },
            summaries: watchedDiagnostics
        )
    }
    private var watchedDiagnostics: [String: WatchedAgentDiagnosticsSummary] {
        deps.watchedAgentDiagnosticsStore.summaries
    }
    private var watchedDiagnosticPriorityItems: [OnCallPriorityItem] {
        watchedAgentDiagnosticPriorityItems(
            agents: deps.agentWatchlistStore.watchedAgents(from: vm.agents),
            summaries: watchedDiagnostics
        )
    }
    private var onCallPriorityItems: [OnCallPriorityItem] {
        mergeOnCallPriorityItems(
            vm.onCallPriorityItems(
                visibleAlerts: visibleMonitoringAlerts,
                watchedAttentionItems: watchedAttentionItems,
                handoffCheckInStatus: deps.onCallHandoffStore.latestCheckInStatus,
                handoffFollowUpStatuses: deps.onCallHandoffStore.latestFollowUpStatuses
            ),
            with: watchedDiagnosticPriorityItems
        )
    }
    private var onCallDigestLine: String {
        let base = vm.onCallDigestLine(
            visibleAlerts: visibleMonitoringAlerts,
            watchedAttentionItems: watchedAttentionItems,
            mutedAlertCount: activeMutedAlertCount,
            isAcknowledged: isCurrentSnapshotAcknowledged,
            handoffCheckInStatus: deps.onCallHandoffStore.latestCheckInStatus,
            handoffFollowUpStatuses: deps.onCallHandoffStore.latestFollowUpStatuses
        )
        if let diagnosticsSummary = watchedAgentDiagnosticDigestSummary(summaries: watchedDiagnostics) {
            return [base, diagnosticsSummary].joined(separator: " · ")
        }
        return base
    }
    private var handoffText: String {
        vm.onCallHandoffText(
            visibleAlerts: visibleMonitoringAlerts,
            watchedAttentionItems: watchedAttentionItems,
            mutedAlertCount: activeMutedAlertCount,
            isAcknowledged: isCurrentSnapshotAcknowledged,
            handoffCheckInStatus: deps.onCallHandoffStore.latestCheckInStatus,
            handoffFollowUpStatuses: deps.onCallHandoffStore.latestFollowUpStatuses
        )
    }
    private var preferredOnCallSurface: OnCallSurfacePreference {
        deps.onCallFocusStore.preferredSurface
    }
    private var configuredServerURL: String {
        ServerConfig.saved.baseURL
    }
    private var isLoopbackServer: Bool {
        let normalized = configuredServerURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.contains("127.0.0.1") || normalized.contains("localhost")
    }
    private var overviewWatchIssueCount: Int {
        watchedAttentionItems.filter { $0.severity > 0 }.count
    }
    private var shouldShowWatchlistCard: Bool {
        overviewWatchIssueCount > 0
    }
    private var shouldShowSessionWatchlistCard: Bool {
        vm.sessionAttentionCount > 0
    }
    private var shouldShowAttentionAgentsCard: Bool {
        vm.issueAgentCount > 0
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let error = vm.error {
                        ErrorBanner(message: error, onRetry: {
                            await vm.refresh()
                        }, onDismiss: {
                            vm.error = nil
                        })
                    }

                    ConnectionCard(
                        health: vm.health,
                        lastRefresh: vm.lastRefresh,
                        isStale: vm.isDataStale,
                        hasConnectionEvidence: vm.hasPrimaryConnectionEvidence,
                        errorMessage: vm.error
                    )

                    if !visibleMonitoringAlerts.isEmpty || activeMutedAlertCount > 0 {
                        NavigationLink {
                            IncidentsView()
                        } label: {
                            AlertsCard(
                                alerts: visibleMonitoringAlerts,
                                mutedCount: activeMutedAlertCount,
                                snapshotAcknowledged: isCurrentSnapshotAcknowledged
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    NavigationLink {
                        preferredSurfaceView
                    } label: {
                        OnCallDigestCard(
                            queueCount: onCallPriorityItems.count,
                            criticalCount: visibleMonitoringAlerts.filter { $0.severity == .critical }.count,
                            watchCount: watchedAttentionItems.count,
                            summary: onCallDigestLine
                        )
                    }
                    .buttonStyle(.plain)

                    if shouldShowWatchlistCard {
                        WatchlistCard(items: watchedAttentionItems, diagnostics: watchedDiagnostics)
                    } else if shouldShowSessionWatchlistCard {
                        SessionWatchlistCard(items: vm.sessionAttentionItems)
                    } else if shouldShowAttentionAgentsCard {
                        AttentionAgentsCard(items: vm.attentionAgents)
                    }

                }
                .padding()
                .monitoringRefreshInteractionGate(
                    isRefreshing: vm.isLoading,
                    restoreDelay: 0.9
                )
            }
            .navigationTitle("LibreFang")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink {
                            IncidentsView()
                        } label: {
                            Label("Incidents", systemImage: "bell.badge")
                        }

                        NavigationLink {
                            RuntimeView()
                        } label: {
                            Label("Runtime", systemImage: "server.rack")
                        }

                        NavigationLink {
                            HandoffCenterView(
                                summary: handoffText,
                                queueCount: onCallPriorityItems.count,
                                criticalCount: visibleMonitoringAlerts.filter { $0.severity == .critical }.count,
                                liveAlertCount: visibleMonitoringAlerts.count
                            )
                        } label: {
                            Label("Handoff", systemImage: "text.badge.plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .refreshable {
                await vm.refresh()
                deps.agentWatchlistStore.removeMissingAgents(validIDs: Set(vm.agents.map(\.id)))
            }
            .task {
                if vm.agents.isEmpty && vm.status == nil {
                    await vm.refresh()
                }
                deps.agentWatchlistStore.removeMissingAgents(validIDs: Set(vm.agents.map(\.id)))
            }
            .overlay {
                if vm.isLoading && !vm.hasPrimaryConnectionEvidence && vm.error == nil {
                    StartupConnectionCard(
                        serverURL: configuredServerURL,
                        showsLoopbackHint: isLoopbackServer
                    )
                    .padding()
                }
            }
        }
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
}

private struct AlertsCard: View {
    let alerts: [MonitoringAlertItem]
    let mutedCount: Int
    let snapshotAcknowledged: Bool

    private var snapshotState: AlertSnapshotState {
        AlertSnapshotState(
            liveAlertCount: alerts.count,
            mutedAlertCount: mutedCount,
            isAcknowledged: snapshotAcknowledged
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow {
                Label("Attention", systemImage: "bell.badge")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } accessory: {
                PresentationToneBadge(text: snapshotState.overviewLabel, tone: snapshotState.tone)
            }

            if alerts.isEmpty {
                Text(mutedCount > 0 ? String(localized: "Muted alerts are waiting in incidents.") : String(localized: "No live alerts right now."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(alerts.prefix(2)) { alert in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: alert.symbolName)
                            .foregroundStyle(alert.severity.tone.color)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct StartupConnectionCard: View {
    let serverURL: String
    let showsLoopbackHint: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ResponsiveAccessoryRow(verticalSpacing: 8) {
                Label(String(localized: "Connecting to LibreFang"), systemImage: "network")
                    .font(.headline)
                    .foregroundStyle(.primary)
            } accessory: {
                PresentationToneBadge(text: String(localized: "Connecting"), tone: .warning)
            }

            Text(serverURL)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if showsLoopbackHint {
                Text(String(localized: "Use your Mac LAN IP on a physical iPhone"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }
}

private struct ConnectionCard: View {
    let health: HealthStatus?
    let lastRefresh: Date?
    let isStale: Bool
    let hasConnectionEvidence: Bool
    let errorMessage: String?

    private var connectionTone: PresentationTone {
        guard let health else {
            if hasConnectionEvidence {
                return .positive
            }
            return errorMessage == nil ? .warning : .critical
        }
        if health.isHealthy && isStale {
            return .warning
        }
        return health.statusTone
    }

    private var inventoryBadgeText: String {
        guard health != nil else {
            if hasConnectionEvidence {
                return String(localized: "Connected")
            }
            return errorMessage == nil ? String(localized: "Connecting") : String(localized: "Disconnected")
        }
        return isStale ? String(localized: "Stale") : String(localized: "Fresh")
    }

    private var inventoryBadgeTone: PresentationTone {
        guard health != nil else {
            if hasConnectionEvidence {
                return .positive
            }
            return errorMessage == nil ? .warning : .critical
        }
        return isStale ? .warning : .positive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow(verticalSpacing: 8) {
                Label(String(localized: "Connection"), systemImage: "network")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } accessory: {
                PresentationToneBadge(text: connectionText, tone: connectionTone)
            }
            Text(connectionDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let errorMessage, !hasConnectionEvidence {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var connectionText: String {
        guard let health else {
            if hasConnectionEvidence {
                return String(localized: "Connected")
            }
            return errorMessage == nil ? String(localized: "Connecting") : String(localized: "Disconnected")
        }
        if !health.isHealthy {
            return String(localized: "Disconnected")
        }
        if isStale {
            return String(localized: "Connected (stale)")
        }
        return String(localized: "Connected")
    }

    private var connectionDetail: String {
        var parts: [String] = [inventoryBadgeText]
        if let health {
            parts.append(health.version)
        }
        if let date = lastRefresh {
            parts.append(String(localized: "Updated \(date.formatted(.relative(presentation: .named)))"))
        }
        return parts.joined(separator: " · ")
    }
}

private struct WatchlistCard: View {
    let items: [AgentAttentionItem]
    let diagnostics: [String: WatchedAgentDiagnosticsSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResponsiveAccessoryRow(verticalSpacing: 8) {
                Label(String(localized: "Watchlist"), systemImage: "star.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } accessory: {
                PresentationToneBadge(
                    text: items.count == 1 ? String(localized: "1 pinned") : String(localized: "\(items.count) pinned"),
                    tone: items.isEmpty ? .neutral : .caution
                )
            }

            ForEach(items.prefix(2)) { item in
                NavigationLink {
                    destination(for: item)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.agent.identity?.emoji ?? "🤖")
                            .font(.body)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(item.agent.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if let summary = diagnostics[item.agent.id], summary.hasIssues {
                                    let issueBadge = watchedAgentDiagnosticIssueCountBadge(summary: summary)
                                    PresentationToneBadge(text: issueBadge.text, tone: issueBadge.tone, horizontalPadding: 6, verticalPadding: 2)
                                } else if item.severity > 0 {
                                    PresentationToneBadge(
                                        text: item.reasons.prefix(1).first ?? String(localized: "Needs attention"),
                                        tone: item.tone,
                                        horizontalPadding: 6,
                                        verticalPadding: 2
                                    )
                                }
                            }

                            if item.reasons.isEmpty, diagnostics[item.agent.id] == nil {
                                Text(item.agent.isRunning ? String(localized: "Running normally") : String(localized: "Not currently running"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else if let summary = diagnostics[item.agent.id], summary.hasIssues {
                                Text(([item.reasons.prefix(1).first].compactMap { $0 } + [summary.summaryLine]).joined(separator: " • "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text(item.reasons.prefix(2).joined(separator: " • "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func destination(for item: AgentAttentionItem) -> some View {
        if let summary = diagnostics[item.agent.id], summary.failedDeliveries > 0 {
            AgentDeliveriesView(agent: item.agent, initialScope: .failed)
        } else if let summary = diagnostics[item.agent.id], !summary.missingIdentityFiles.isEmpty {
            AgentFilesView(agent: item.agent, initialScope: .missing)
        } else {
            AgentDetailView(agent: item.agent)
        }
    }
}

private struct AttentionAgentsCard: View {
    let items: [AgentAttentionItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResponsiveAccessoryRow(verticalSpacing: 8) {
                Label(String(localized: "Needs Attention"), systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } accessory: {
                PresentationToneBadge(
                    text: items.count == 1 ? String(localized: "1 agent") : String(localized: "\(items.count) agents"),
                    tone: items.isEmpty ? .neutral : .warning
                )
            }

            ForEach(items.prefix(2)) { item in
                HStack(alignment: .top, spacing: 10) {
                    Text(item.agent.identity?.emoji ?? "🤖")
                        .font(.body)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.agent.name)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            if item.pendingApprovals > 0 {
                                PresentationToneBadge(
                                    text: item.pendingApprovals == 1
                                        ? String(localized: "1 approval")
                                        : String(localized: "\(item.pendingApprovals) approvals"),
                                    tone: .critical,
                                    horizontalPadding: 6,
                                    verticalPadding: 2
                                )
                            }
                        }

                        Text(item.reasons.prefix(2).joined(separator: " • "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct SessionWatchlistCard: View {
    let items: [SessionAttentionItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResponsiveAccessoryRow(verticalSpacing: 8) {
                Label(String(localized: "Sessions"), systemImage: "rectangle.stack")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } accessory: {
                PresentationToneBadge(
                    text: items.count == 1 ? String(localized: "1 hotspot") : String(localized: "\(items.count) hotspots"),
                    tone: items.isEmpty ? .neutral : .warning
                )
            }

            ForEach(items.prefix(2)) { item in
                if let sessionQuery = sessionQuery(for: item) {
                    NavigationLink {
                        SessionsView(initialSearchText: sessionQuery, initialFilter: .attention)
                    } label: {
                        sessionSummaryRow(item)
                    }
                    .buttonStyle(.plain)
                } else {
                    sessionSummaryRow(item)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func displayTitle(_ item: SessionAttentionItem) -> String {
        let label = (item.session.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? String(item.session.sessionId.prefix(8)) : label
    }

    @ViewBuilder
    private func sessionSummaryRow(_ item: SessionAttentionItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "rectangle.stack")
                .foregroundStyle(item.tone.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                ResponsiveAccessoryRow(verticalSpacing: 4) {
                    Text(displayTitle(item))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                } accessory: {
                    Text(String(localized: "\(item.session.messageCount) msgs"))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text("\(item.agent?.name ?? item.session.agentId) · \(item.reasons.prefix(2).joined(separator: " • "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func sessionQuery(for item: SessionAttentionItem) -> String? {
        let agentID = item.agent?.id ?? item.session.agentId
        return agentID.isEmpty ? nil : agentID
    }
}

private func localizedUSDCurrency(
    _ value: Double,
    standardPrecision: Int = 2,
    smallValuePrecision: Int? = nil,
    minimumDisplayValue: Double = 0.01
) -> String {
    let style = FloatingPointFormatStyle<Double>.Currency(code: "USD")
    if value == 0 {
        return value.formatted(style.precision(.fractionLength(standardPrecision)))
    }
    if value < minimumDisplayValue {
        return "<\(minimumDisplayValue.formatted(style.precision(.fractionLength(standardPrecision))))"
    }
    let precision = value < 1 ? (smallValuePrecision ?? standardPrecision) : standardPrecision
    return value.formatted(style.precision(.fractionLength(precision)))
}

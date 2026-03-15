import SwiftUI

private enum NightWatchTone {
    case calm
    case watching
    case elevated
    case critical

    var label: String {
        switch self {
        case .calm:
            "Calm"
        case .watching:
            "Watching"
        case .elevated:
            "Elevated"
        case .critical:
            "Critical"
        }
    }

    var color: Color {
        switch self {
        case .calm:
            .green
        case .watching:
            .blue
        case .elevated:
            .orange
        case .critical:
            .red
        }
    }

    var gradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .calm:
            colors = [Color(red: 0.07, green: 0.15, blue: 0.12), Color(red: 0.03, green: 0.07, blue: 0.08)]
        case .watching:
            colors = [Color(red: 0.05, green: 0.11, blue: 0.18), Color(red: 0.03, green: 0.05, blue: 0.10)]
        case .elevated:
            colors = [Color(red: 0.18, green: 0.11, blue: 0.05), Color(red: 0.06, green: 0.04, blue: 0.06)]
        case .critical:
            colors = [Color(red: 0.20, green: 0.06, blue: 0.07), Color(red: 0.06, green: 0.03, blue: 0.07)]
        }

        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct NightWatchView: View {
    @Environment(\.dependencies) private var deps

    private var vm: DashboardViewModel { deps.dashboardViewModel }
    private var incidentStateStore: IncidentStateStore { deps.incidentStateStore }
    private var watchlistStore: AgentWatchlistStore { deps.agentWatchlistStore }
    private var focusStore: OnCallFocusStore { deps.onCallFocusStore }

    private var visibleAlerts: [MonitoringAlertItem] {
        incidentStateStore.visibleAlerts(from: vm.monitoringAlerts)
    }

    private var mutedAlertCount: Int {
        incidentStateStore.activeMutedAlerts(from: vm.monitoringAlerts).count
    }

    private var watchedAgents: [Agent] {
        watchlistStore.watchedAgents(from: vm.agents)
    }

    private var watchedAgentIDs: Set<String> {
        Set(watchedAgents.map(\.id))
    }

    private var watchedAttentionItems: [AgentAttentionItem] {
        watchedAgents
            .map { vm.attentionItem(for: $0) }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return lhs.severity > rhs.severity
                }
                return lhs.agent.name.localizedCompare(rhs.agent.name) == .orderedAscending
            }
    }

    private var allPriorityItems: [OnCallPriorityItem] {
        vm.onCallPriorityItems(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            handoffCheckInStatus: deps.onCallHandoffStore.latestCheckInStatus,
            handoffFollowUpStatuses: deps.onCallHandoffStore.latestFollowUpStatuses
        )
    }

    private var priorityItems: [OnCallPriorityItem] {
        switch focusStore.mode {
        case .balanced:
            return allPriorityItems
        case .criticalOnly:
            return allPriorityItems.filter { $0.severity == .critical }
        case .watchlistFirst:
            return allPriorityItems.sorted { lhs, rhs in
                let lhsBoost = watchPriorityBoost(for: lhs)
                let rhsBoost = watchPriorityBoost(for: rhs)
                if lhsBoost != rhsBoost {
                    return lhsBoost > rhsBoost
                }
                if lhs.rank != rhs.rank {
                    return lhs.rank > rhs.rank
                }
                return lhs.title.localizedCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private var primaryItems: [OnCallPriorityItem] {
        Array(priorityItems.prefix(3))
    }

    private var secondaryItems: [OnCallPriorityItem] {
        Array(priorityItems.dropFirst(3).prefix(3))
    }

    private var tone: NightWatchTone {
        if primaryItems.contains(where: { $0.severity == .critical }) {
            return .critical
        }
        if primaryItems.contains(where: { $0.severity == .warning }) || vm.pendingApprovalCount > 0 {
            return .elevated
        }
        if !primaryItems.isEmpty || mutedAlertCount > 0 || !watchedAttentionItems.isEmpty {
            return .watching
        }
        return .calm
    }

    private var digestLine: String {
        vm.onCallDigestLine(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            mutedAlertCount: mutedAlertCount,
            isAcknowledged: incidentStateStore.isCurrentSnapshotAcknowledged(alerts: vm.monitoringAlerts),
            handoffCheckInStatus: deps.onCallHandoffStore.latestCheckInStatus,
            handoffFollowUpStatuses: deps.onCallHandoffStore.latestFollowUpStatuses
        )
    }

    private var handoffText: String {
        vm.onCallHandoffText(
            visibleAlerts: visibleAlerts,
            watchedAttentionItems: watchedAttentionItems,
            mutedAlertCount: mutedAlertCount,
            isAcknowledged: incidentStateStore.isCurrentSnapshotAcknowledged(alerts: vm.monitoringAlerts),
            handoffCheckInStatus: deps.onCallHandoffStore.latestCheckInStatus,
            handoffFollowUpStatuses: deps.onCallHandoffStore.latestFollowUpStatuses
        )
    }

    private var focusSummary: String {
        switch focusStore.mode {
        case .balanced:
            "Balanced triage keeps live alerts, approvals, watchlist issues, and session hotspots together."
        case .criticalOnly:
            "Critical-only mode suppresses lower-severity noise so the top screen stays quiet until something truly urgent lands."
        case .watchlistFirst:
            "Watchlist-first mode promotes pinned agents above the rest of the queue."
        }
    }

    var body: some View {
        ZStack {
            tone.gradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    mutedSummaryCard
                    primaryQueueCard
                    secondaryQueueCard
                    watchlistCard
                    controlsCard
                    quickLinksCard
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Night Watch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            toolbarContent
        }
        .navigationDestination(for: OnCallRoute.self) { route in
            destination(for: route)
        }
        .refreshable {
            await refreshAndSync()
        }
        .task {
            if vm.lastRefresh == nil {
                await refreshAndSync()
            } else {
                syncWatchlist()
            }
        }
    }

    @ViewBuilder
    private var heroCard: some View {
        NightWatchHeroCard(
            tone: tone,
            queueCount: priorityItems.count,
            criticalCount: priorityItems.filter { $0.severity == .critical }.count,
            watchCount: watchedAttentionItems.filter { $0.severity > 0 }.count,
            summary: digestLine,
            focusModeLabel: focusStore.mode.label,
            lastRefresh: vm.lastRefresh,
            acknowledgedAt: incidentStateStore.currentAcknowledgementDate(for: vm.monitoringAlerts),
            isAcknowledged: incidentStateStore.isCurrentSnapshotAcknowledged(alerts: vm.monitoringAlerts),
            onAcknowledge: {
                incidentStateStore.acknowledgeCurrentSnapshot(alerts: vm.monitoringAlerts)
            },
            onClearAcknowledgement: {
                incidentStateStore.clearAcknowledgement()
            }
        )
    }

    @ViewBuilder
    private var mutedSummaryCard: some View {
        if focusStore.showsMutedSummary, mutedAlertCount > 0 {
            NightWatchMutedSummaryCard(mutedAlertCount: mutedAlertCount)
        }
    }

    @ViewBuilder
    private var primaryQueueCard: some View {
        if primaryItems.isEmpty {
            NightWatchCalmCard(
                title: calmStateTitle,
                detail: calmStateDetail
            )
        } else {
            NightWatchSectionCard(title: "Immediate Queue", detail: focusSummary) {
                ForEach(primaryItems) { item in
                    NavigationLink(value: item.route) {
                        NightWatchPriorityCard(
                            item: item,
                            isWatched: isWatchedRoute(item.route),
                            emphasis: .primary
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var secondaryQueueCard: some View {
        if !secondaryItems.isEmpty {
            NightWatchSectionCard(title: "Follow-up Queue", detail: "Lower on the page, but still above the fold for one-hand triage.") {
                ForEach(secondaryItems) { item in
                    NavigationLink(value: item.route) {
                        NightWatchPriorityCard(
                            item: item,
                            isWatched: isWatchedRoute(item.route),
                            emphasis: .secondary
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var watchlistCard: some View {
        let activeWatched = watchedAttentionItems.filter { $0.severity > 0 }
        if !activeWatched.isEmpty && focusStore.mode != .criticalOnly {
            NightWatchSectionCard(
                title: "Pinned Agents",
                detail: "Locally watched on this iPhone so they stay visible during on-call."
            ) {
                ForEach(activeWatched.prefix(3)) { item in
                    NavigationLink(value: OnCallRoute.agent(item.agent.id)) {
                        NightWatchWatchlistRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var controlsCard: some View {
        NightWatchControlsCard(
            mode: Binding(
                get: { focusStore.mode },
                set: { focusStore.mode = $0 }
            ),
            preferredSurface: Binding(
                get: { focusStore.preferredSurface },
                set: { focusStore.preferredSurface = $0 }
            ),
            showsMutedSummary: Binding(
                get: { focusStore.showsMutedSummary },
                set: { focusStore.showsMutedSummary = $0 }
            )
        )
    }

    private var quickLinksCard: some View {
        NightWatchSectionCard(title: "Jump To", detail: "Use the full queue when you need broader runtime context.") {
            NavigationLink {
                OnCallView()
            } label: {
                NightWatchActionRow(
                    title: "Open Full On Call Queue",
                    detail: "Switch back to the complete triage surface.",
                    systemImage: "waveform.path.ecg"
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: OnCallRoute.incidents) {
                NightWatchActionRow(
                    title: "Open Incidents Center",
                    detail: "Review muted alerts, approvals, and current incident state.",
                    systemImage: "bell.badge"
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: OnCallRoute.sessionsAttention) {
                NightWatchActionRow(
                    title: "Session Pressure",
                    detail: "Inspect duplicated, unlabeled, or high-volume sessions.",
                    systemImage: "rectangle.stack"
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: OnCallRoute.eventsCritical) {
                NightWatchActionRow(
                    title: "Critical Event Feed",
                    detail: "Jump straight into recent critical audit entries.",
                    systemImage: "list.bullet.rectangle.portrait"
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Picker("Display Mode", selection: Binding(
                    get: { focusStore.mode },
                    set: { focusStore.mode = $0 }
                )) {
                    ForEach(OnCallFocusMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Picker("Critical Banner", selection: Binding(
                    get: { focusStore.preferredSurface },
                    set: { focusStore.preferredSurface = $0 }
                )) {
                    ForEach(OnCallSurfacePreference.allCases) { surface in
                        Text(surface.label).tag(surface)
                    }
                }

                Toggle("Show muted summary", isOn: Binding(
                    get: { focusStore.showsMutedSummary },
                    set: { focusStore.showsMutedSummary = $0 }
                ))
            } label: {
                Image(systemName: "slider.horizontal.3")
            }

            NavigationLink {
                StandbyDigestView()
            } label: {
                Image(systemName: "rectangle.inset.filled")
            }

            NavigationLink(value: OnCallRoute.incidents) {
                Image(systemName: "bell.badge")
            }
        }
    }

    @ViewBuilder
    private func destination(for route: OnCallRoute) -> some View {
        switch route {
        case .incidents:
            IncidentsView()
        case .agent(let id):
            if let agent = vm.agents.first(where: { $0.id == id }) {
                AgentDetailView(agent: agent)
            } else {
                ContentUnavailableView(
                    "Agent Unavailable",
                    systemImage: "cpu",
                    description: Text("This agent is no longer present in the current monitoring snapshot.")
                )
            }
        case .sessionsAttention:
            SessionsView(initialFilter: .attention)
        case .eventsCritical:
            EventsView(api: deps.apiClient, initialScope: .critical)
        case .eventsSearch(let query):
            EventsView(api: deps.apiClient, initialSearchText: query, initialScope: .critical)
        case .handoffCenter:
            HandoffCenterView(
                summary: handoffText,
                queueCount: allPriorityItems.count,
                criticalCount: visibleAlerts.filter { $0.severity == .critical }.count,
                liveAlertCount: visibleAlerts.count
            )
        }
    }

    @MainActor
    private func refreshAndSync() async {
        await vm.refresh()
        syncWatchlist()
    }

    private func syncWatchlist() {
        watchlistStore.removeMissingAgents(validIDs: Set(vm.agents.map(\.id)))
    }

    private func watchPriorityBoost(for item: OnCallPriorityItem) -> Int {
        switch item.route {
        case .agent(let id):
            return watchedAgentIDs.contains(id) ? 100 : 0
        case .eventsSearch(let query):
            return watchedAgentIDs.contains(query) ? 85 : 0
        default:
            return item.footnote.localizedCaseInsensitiveContains("Watched") ? 70 : 0
        }
    }

    private func isWatchedRoute(_ route: OnCallRoute) -> Bool {
        switch route {
        case .agent(let id):
            return watchedAgentIDs.contains(id)
        case .eventsSearch(let query):
            return watchedAgentIDs.contains(query)
        default:
            return false
        }
    }

    private var calmStateTitle: String {
        if focusStore.mode == .criticalOnly {
            return "No Critical Incidents"
        }
        return "Queue Is Quiet"
    }

    private var calmStateDetail: String {
        if focusStore.mode == .criticalOnly, !allPriorityItems.isEmpty {
            return "Lower-severity items still exist in the broader on-call queue, but critical-only mode is intentionally suppressing them here."
        }
        return "No urgent work is currently surfacing on this phone. Pull to refresh or open the full on-call queue for more detail."
    }
}

private struct NightWatchHeroCard: View {
    let tone: NightWatchTone
    let queueCount: Int
    let criticalCount: Int
    let watchCount: Int
    let summary: String
    let focusModeLabel: String
    let lastRefresh: Date?
    let acknowledgedAt: Date?
    let isAcknowledged: Bool
    let onAcknowledge: () -> Void
    let onClearAcknowledgement: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Night Watch")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Text(tone.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.14))
                        .clipShape(Capsule())
                    Text(focusModeLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.74))
                }
            }

            HStack(spacing: 10) {
                NightWatchCountPill(value: queueCount, label: "Queued")
                NightWatchCountPill(value: criticalCount, label: "Critical")
                NightWatchCountPill(value: watchCount, label: "Watched")
            }

            HStack(spacing: 10) {
                if isAcknowledged {
                    Button("Clear Ack", action: onClearAcknowledgement)
                        .buttonStyle(NightWatchPrimaryButtonStyle(fill: .white.opacity(0.16)))
                } else if queueCount > 0 {
                    Button("Acknowledge Snapshot", action: onAcknowledge)
                        .buttonStyle(NightWatchPrimaryButtonStyle(fill: .white.opacity(0.16)))
                }

                NavigationLink {
                    OnCallView()
                } label: {
                    Text("Full Queue")
                }
                .buttonStyle(NightWatchPrimaryButtonStyle(fill: .white.opacity(0.10)))
            }

            HStack(spacing: 12) {
                if let acknowledgedAt, isAcknowledged {
                    Label("Acked \(acknowledgedAt, style: .relative) ago", systemImage: "checkmark.seal")
                }
                if let lastRefresh {
                    Label("Refreshed \(lastRefresh, style: .relative)", systemImage: "clock")
                }
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.68))
        }
        .padding(18)
        .background(.black.opacity(0.26))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct NightWatchMutedSummaryCard: View {
    let mutedAlertCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(mutedAlertCount == 1 ? "1 alert muted locally" : "\(mutedAlertCount) alerts muted locally")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Muted alerts stay out of the queue until you unmute them in Incidents.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }
            Spacer()
        }
        .padding(14)
        .background(.black.opacity(0.22))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct NightWatchCalmCard: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.76))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.black.opacity(0.22))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct NightWatchSectionCard<Content: View>: View {
    let title: String
    let detail: String
    let content: Content

    init(title: String, detail: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.black.opacity(0.22))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct NightWatchPriorityCard: View {
    enum Emphasis {
        case primary
        case secondary
    }

    let item: OnCallPriorityItem
    let isWatched: Bool
    let emphasis: Emphasis

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.symbolName)
                .font(.headline)
                .foregroundStyle(severityColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text(item.title)
                        .font(emphasis == .primary ? .headline.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(item.severity.label)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(severityColor.opacity(0.18))
                        .foregroundStyle(severityColor)
                        .clipShape(Capsule())
                }

                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(item.footnote)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                    if isWatched {
                        Label("Watched", systemImage: "star.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.yellow)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(emphasis == .primary ? 0.09 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var severityColor: Color {
        switch item.severity {
        case .critical:
            .red
        case .warning:
            .orange
        case .advisory:
            .blue
        }
    }
}

private struct NightWatchWatchlistRow: View {
    let item: AgentAttentionItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.agent.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(item.severity >= 10 ? "Critical" : "Watch")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((item.severity >= 10 ? Color.red : Color.orange).opacity(0.16))
                        .foregroundStyle(item.severity >= 10 ? .red : .orange)
                        .clipShape(Capsule())
                }

                Text(item.reasons.prefix(2).joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct NightWatchControlsCard: View {
    @Binding var mode: OnCallFocusMode
    @Binding var preferredSurface: OnCallSurfacePreference
    @Binding var showsMutedSummary: Bool

    var body: some View {
        NightWatchSectionCard(title: "Display Controls", detail: "All settings are local to this iPhone.") {
            LabeledContent("Queue Mode") {
                Menu {
                    ForEach(OnCallFocusMode.allCases) { option in
                        Button(option.label) {
                            mode = option
                        }
                    }
                } label: {
                    Text(mode.label)
                        .foregroundStyle(.white)
                }
            }
            .foregroundStyle(.white.opacity(0.74))

            Text(mode.summary)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.66))

            LabeledContent("Critical Banner") {
                Menu {
                    ForEach(OnCallSurfacePreference.allCases) { option in
                        Button(option.label) {
                            preferredSurface = option
                        }
                    }
                } label: {
                    Text(preferredSurface.label)
                        .foregroundStyle(.white)
                }
            }
            .foregroundStyle(.white.opacity(0.74))

            Text(preferredSurface.summary)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.66))

            Toggle(isOn: $showsMutedSummary) {
                Text("Show muted summary")
                    .foregroundStyle(.white)
            }
            .tint(.orange)
        }
    }
}

private struct NightWatchActionRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct NightWatchCountPill: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline.monospacedDigit().weight(.semibold))
            Text(label)
                .font(.caption2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct NightWatchPrimaryButtonStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(fill.opacity(configuration.isPressed ? 0.65 : 1))
            .clipShape(Capsule())
    }
}

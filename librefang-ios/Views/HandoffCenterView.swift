import SwiftUI

private enum HandoffHistoryFilter: String, CaseIterable, Identifiable {
    case all
    case critical
    case queued
    case calm

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            String(localized: "All")
        case .critical:
            String(localized: "Critical")
        case .queued:
            String(localized: "Queued")
        case .calm:
            String(localized: "Calm")
        }
    }
}

struct HandoffCenterView: View {
    @Environment(\.dependencies) private var deps
    @State private var searchText = ""
    @State private var historyFilter: HandoffHistoryFilter = .all
    @State private var draftFollowUpText = ""

    let summary: String
    let queueCount: Int
    let criticalCount: Int
    let liveAlertCount: Int

    private var handoffStore: OnCallHandoffStore { deps.onCallHandoffStore }
    private var vm: DashboardViewModel { deps.dashboardViewModel }
    private var watchlistStore: AgentWatchlistStore { deps.agentWatchlistStore }
    private var currentShareText: String {
        OnCallHandoffEntry.buildShareText(
            timestamp: Date(),
            kind: handoffStore.draftKind,
            note: handoffStore.draftNote.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary,
            queueCount: queueCount,
            criticalCount: criticalCount,
            liveAlertCount: liveAlertCount,
            checklist: handoffStore.draftChecklist,
            focusAreas: handoffStore.draftFocusAreas,
            followUpItems: handoffStore.draftFollowUpItems,
            checkInWindow: handoffStore.draftCheckInWindow
        )
    }
    private var suggestedTemplateNote: String {
        handoffStore.draftKind.suggestedNote(
            queueCount: queueCount,
            criticalCount: criticalCount,
            liveAlertCount: liveAlertCount
        )
    }
    private var filteredEntries: [OnCallHandoffEntry] {
        handoffStore.entries.filter { entry in
            matches(filter: historyFilter, for: entry) && matchesSearch(entry)
        }
    }
    private var historyFilterTone: PresentationTone {
        switch historyFilter {
        case .all:
            .neutral
        case .critical:
            .critical
        case .queued:
            .warning
        case .calm:
            .positive
        }
    }
    private var coverageEntries: [OnCallHandoffEntry] {
        handoffStore.recentEntries
    }
    private var timelineItems: [HandoffTimelineItem] {
        handoffStore.timelineItems
    }
    private var currentDrift: HandoffSnapshotDrift? {
        handoffStore.driftFromLatest(
            queueCount: queueCount,
            criticalCount: criticalCount,
            liveAlertCount: liveAlertCount
        )
    }
    private var latestFollowUpStatuses: [HandoffFollowUpStatus] {
        handoffStore.latestFollowUpStatuses
    }
    private var pendingLatestFollowUpCount: Int {
        latestFollowUpStatuses.filter { !$0.isCompleted }.count
    }
    private var completedLatestFollowUpCount: Int {
        latestFollowUpStatuses.filter(\.isCompleted).count
    }
    private var watchlistIssueCount: Int {
        watchlistStore.watchedAgents(from: vm.agents)
            .filter { vm.attentionItem(for: $0).severity > 0 }
            .count
    }
    private var uncoveredChecklistCount: Int {
        handoffStore.uncoveredChecklistKeys.count
    }
    private var timelineGapWarningCount: Int {
        timelineItems.filter(\.isGapWarning).count
    }
    private var carryoverStatus: HandoffCarryoverStatus? {
        handoffStore.carryoverFromLatest(
            liveAlertCount: liveAlertCount,
            pendingApprovalCount: vm.pendingApprovalCount,
            watchlistIssueCount: watchlistIssueCount,
            sessionAttentionCount: vm.sessionAttentionCount,
            criticalAuditCount: vm.recentCriticalAuditCount
        )
    }
    private var draftReadiness: HandoffReadinessStatus {
        handoffStore.evaluateDraftReadiness(
            note: handoffStore.draftNote,
            checklist: handoffStore.draftChecklist,
            focusAreas: handoffStore.draftFocusAreas,
            followUpItems: handoffStore.draftFollowUpItems,
            checkInWindow: handoffStore.draftCheckInWindow,
            liveAlertCount: liveAlertCount,
            pendingApprovalCount: vm.pendingApprovalCount,
            watchlistIssueCount: watchlistIssueCount,
            sessionAttentionCount: vm.sessionAttentionCount,
            criticalAuditCount: vm.recentCriticalAuditCount,
            carryover: carryoverStatus
        )
    }
    private var suggestedFocusAreas: Set<HandoffFocusArea> {
        var areas = Set<HandoffFocusArea>()

        if liveAlertCount > 0 || criticalCount > 0 {
            areas.insert(.alerts)
        }
        if vm.pendingApprovalCount > 0 {
            areas.insert(.approvals)
        }
        if watchlistIssueCount > 0 {
            areas.insert(.watchlist)
        }
        if vm.sessionAttentionCount > 0 {
            areas.insert(.sessions)
        }
        if vm.recentCriticalAuditCount > 0 {
            areas.insert(.audit)
        }

        return areas
    }
    private var suggestedFollowUps: [String] {
        var items: [String] = []

        if liveAlertCount > 0 {
            items.append(String(localized: "Review \(liveAlertCount) live alerts and confirm owner or next check."))
        }
        if vm.pendingApprovalCount > 0 {
            items.append(String(localized: "Triage \(vm.pendingApprovalCount) pending approvals."))
        }
        if watchlistIssueCount > 0 {
            items.append(String(localized: "Re-check \(watchlistIssueCount) watchlist agents for readiness, auth, or stale-session issues."))
        }
        if vm.sessionAttentionCount > 0 {
            items.append(String(localized: "Inspect \(vm.sessionAttentionCount) session hotspots for backlog or unlabeled sessions."))
        }
        if vm.recentCriticalAuditCount > 0 {
            items.append(String(localized: "Review \(vm.recentCriticalAuditCount) recent critical audit events."))
        }
        if let carryoverStatus, carryoverStatus.unresolvedCount > 0 {
            let labels = carryoverStatus.items.filter(\.isActive).map { $0.area.label }.joined(separator: ", ")
            items.append(String(localized: "Close remaining carryover focus: \(labels)."))
        }

        return items
    }
    private var handoffSectionCount: Int {
        [
            true,
            true,
            !timelineItems.isEmpty,
            !filteredEntries.isEmpty
        ]
        .filter { $0 }
        .count
    }

    var body: some View {
        List {
            Section {
                HandoffShiftContextInventoryDeck(
                    coverageCount: coverageEntries.count,
                    freshnessState: handoffStore.freshnessState,
                    cadenceState: handoffStore.cadenceState,
                    readiness: draftReadiness,
                    checkInStatus: handoffStore.latestCheckInStatus,
                    pendingFollowUpCount: pendingLatestFollowUpCount,
                    completedFollowUpCount: completedLatestFollowUpCount,
                    uncoveredChecklistCount: uncoveredChecklistCount,
                    carryoverStatus: carryoverStatus,
                    drift: currentDrift,
                    latestEntryDate: coverageEntries.map(\.createdAt).max()
                )

                HandoffFreshnessCard(
                    freshnessState: handoffStore.freshnessState,
                    freshnessSummary: handoffStore.freshnessSummary,
                    latestEntry: handoffStore.latestEntry,
                    uncoveredChecklistKeys: handoffStore.uncoveredChecklistKeys
                )

                HandoffCoverageCard(
                    entries: coverageEntries,
                    coverageCount: { handoffStore.recentCoverageCount(for: $0) }
                )

                HandoffCadenceCard(
                    cadenceState: handoffStore.cadenceState,
                    cadenceSummary: handoffStore.cadenceSummary,
                    warningCount: handoffStore.cadenceWarningCount
                )

                HandoffReadinessCard(status: draftReadiness)

                if let checkInStatus = handoffStore.latestCheckInStatus {
                    HandoffCheckInCard(status: checkInStatus)
                }

                if !latestFollowUpStatuses.isEmpty {
                    HandoffFollowUpTrackerCard(
                        statuses: latestFollowUpStatuses,
                        onToggle: { handoffStore.toggleFollowUpCompletion($0) }
                    )
                }

                if let carryoverStatus {
                    HandoffCarryoverCard(status: carryoverStatus)
                }

                if let currentDrift {
                    HandoffDriftCard(drift: currentDrift)
                }
            } header: {
                Text("Shift Context")
            }

            controlDeckSection

            Section {
                HandoffDraftContextCard(
                    kind: Binding(
                        get: { handoffStore.draftKind },
                        set: { handoffStore.draftKind = $0 }
                    ),
                    readiness: draftReadiness,
                    focusCount: handoffStore.draftFocusAreas.items.count,
                    followUpCount: handoffStore.draftFollowUpItems.count,
                    checkInWindow: Binding(
                        get: { handoffStore.draftCheckInWindow },
                        set: { handoffStore.draftCheckInWindow = $0 }
                    ),
                    queueCount: queueCount,
                    criticalCount: criticalCount,
                    liveAlertCount: liveAlertCount
                )

                HandoffNoteComposerCard(
                    note: Binding(
                        get: { handoffStore.draftNote },
                        set: { handoffStore.draftNote = $0 }
                    ),
                    kind: handoffStore.draftKind,
                    suggestedTemplateNote: suggestedTemplateNote,
                    onUseSuggestedNote: {
                        handoffStore.useSuggestedDraftNote(
                            queueCount: queueCount,
                            criticalCount: criticalCount,
                            liveAlertCount: liveAlertCount
                        )
                    }
                )
            } header: {
                Text("Draft")
            } footer: {
                Text("Keep snapshot type, live counts, check-in timing, and the summary together before the checklist and follow-ups.")
            }

            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HandoffActionDeckInventoryCard(
                        kind: handoffStore.draftKind,
                        readiness: draftReadiness,
                        checklist: handoffStore.draftChecklist,
                        focusAreas: handoffStore.draftFocusAreas,
                        followUpCount: handoffStore.draftFollowUpItems.count,
                        suggestedFocusCount: suggestedFocusAreas.count,
                        suggestedFollowUpCount: suggestedFollowUps.count,
                        checkInWindow: handoffStore.draftCheckInWindow
                    )

                    HandoffChecklistComposer(
                        checklist: handoffStore.draftChecklist,
                        toggle: { handoffStore.toggleDraftChecklist($0) }
                    )

                    HandoffFocusComposer(
                        focusAreas: handoffStore.draftFocusAreas,
                        toggle: { handoffStore.toggleDraftFocusArea($0) }
                    )

                    Button {
                        handoffStore.setDraftFocusAreas(suggestedFocusAreas)
                    } label: {
                        Label("Use Suggested Focus", systemImage: "scope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(suggestedFocusAreas.isEmpty)

                    if !suggestedFocusAreas.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(HandoffFocusArea.allCases.filter { suggestedFocusAreas.contains($0) }) { area in
                                    HandoffFocusAreaBadge(area: area)
                                }
                            }
                        }
                    }

                    HandoffFollowUpComposer(
                        items: handoffStore.draftFollowUpItems,
                        draftText: $draftFollowUpText,
                        addAction: {
                            handoffStore.addDraftFollowUp(draftFollowUpText)
                            draftFollowUpText = ""
                        },
                        removeAction: { offsets in
                            handoffStore.removeDraftFollowUps(at: offsets)
                        }
                    )

                    Button {
                        handoffStore.appendDraftFollowUps(suggestedFollowUps)
                    } label: {
                        Label("Use Suggested Follow-ups", systemImage: "checklist.unchecked")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(suggestedFollowUps.isEmpty)

                    HandoffDraftActionsCard(
                        readiness: draftReadiness,
                        shareText: currentShareText,
                        onSave: {
                            handoffStore.saveSnapshot(
                                summary: summary,
                                queueCount: queueCount,
                                criticalCount: criticalCount,
                                liveAlertCount: liveAlertCount
                            )
                        },
                        onReset: { handoffStore.resetDraft() }
                    )
                }
                .padding(.vertical, 4)
            } header: {
                Text("Action Deck")
            } footer: {
                Text("Checklist completion, focus areas, follow-ups, and save/share actions stay in one operator block so the handoff draft is easier to finish on a phone.")
            }

            if !timelineItems.isEmpty {
                Section {
                    HandoffTimelineInventoryDeck(
                        items: timelineItems,
                        gapWarningCount: timelineGapWarningCount
                    )

                    ForEach(timelineItems, id: \.id) { item in
                        HandoffTimelineRow(item: item)
                    }
                } header: {
                    Text("Timeline")
                } footer: {
                    Text("Shows recent local handoff cadence on this iPhone so shift gaps are visible.")
                }
            }

            if handoffStore.entries.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Saved Handoffs",
                        systemImage: "text.badge.plus",
                        description: Text("Save a snapshot to keep a local history of shift notes and queue state.")
                    )
                } header: {
                    Text("Recent Handoffs")
                }
            } else {
                Section {
                    HandoffHistoryInventoryDeck(
                        entries: filteredEntries,
                        totalCount: handoffStore.entries.count,
                        filterLabel: historyFilter.label,
                        filterTone: historyFilterTone,
                        searchText: searchText
                    )

                    HandoffHistoryFilterCard(
                        filter: $historyFilter,
                        searchText: searchText,
                        visibleCount: filteredEntries.count,
                        totalCount: handoffStore.entries.count
                    )

                    if filteredEntries.isEmpty {
                        ContentUnavailableView(
                            "No Matching Handoffs",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("Try a different filter or search term.")
                        )
                    } else {
                        ForEach(filteredEntries) { entry in
                            HandoffEntryCard(entry: entry)
                        }
                        .onDelete(perform: deleteFilteredEntries)
                    }
                } header: {
                    Text("Recent Handoffs")
                } footer: {
                    if !handoffStore.entries.isEmpty {
                        Button(role: .destructive) {
                            handoffStore.clearAll()
                        } label: {
                            Text("Clear History")
                        }
                    }
                }
            }
        }
        .navigationTitle("Handoff Center")
        .searchable(text: $searchText, prompt: "Search notes or summaries")
    }

    private var controlDeckSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                handoffSignalFactsCard
                HandoffSectionInventoryDeck(
                    sectionCount: handoffSectionCount,
                    timelineCount: timelineItems.count,
                    historyCount: filteredEntries.count,
                    focusCount: handoffStore.draftFocusAreas.items.count,
                    followUpCount: handoffStore.draftFollowUpItems.count,
                    pendingFollowUpCount: pendingLatestFollowUpCount,
                    readiness: draftReadiness,
                    queueCount: queueCount,
                    criticalCount: criticalCount
                )
                HandoffRouteInventoryDeck(
                    queueCount: queueCount,
                    criticalCount: criticalCount,
                    liveAlertCount: liveAlertCount,
                    pendingApprovalCount: vm.pendingApprovalCount,
                    diagnosticsWarningCount: vm.diagnosticsConfigWarningCount,
                    primaryRouteCount: 4,
                    supportRouteCount: 3
                )
                handoffSurfaceDeckCard
            }
        } header: {
            Text("Controls")
        } footer: {
            Text("Keep live pressure, draft readiness, and next routes together before editing.")
        }
    }

    private var handoffSignalFactsCard: some View {
        MonitoringFactsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Handoff signal facts"))
                    .font(.subheadline.weight(.medium))
                Text(String(localized: "Keep live queue shape, follow-up load, and draft state visible before editing."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } accessory: {
            PresentationToneBadge(
                text: draftReadiness.state.label,
                tone: draftReadiness.state.tone
            )
        } facts: {
            Label(
                queueCount == 1 ? String(localized: "1 queued item") : String(localized: "\(queueCount) queued items"),
                systemImage: "waveform.path.ecg"
            )
            Label(
                criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"),
                systemImage: "xmark.octagon"
            )
            Label(
                liveAlertCount == 1 ? String(localized: "1 live alert") : String(localized: "\(liveAlertCount) live alerts"),
                systemImage: "bell.badge"
            )
            if vm.pendingApprovalCount > 0 {
                Label(
                    vm.pendingApprovalCount == 1 ? String(localized: "1 approval") : String(localized: "\(vm.pendingApprovalCount) approvals"),
                    systemImage: "checkmark.shield"
                )
            }
            if vm.sessionAttentionCount > 0 {
                Label(
                    vm.sessionAttentionCount == 1 ? String(localized: "1 session hotspot") : String(localized: "\(vm.sessionAttentionCount) session hotspots"),
                    systemImage: "rectangle.stack"
                )
            }
            if pendingLatestFollowUpCount > 0 {
                Label(
                    pendingLatestFollowUpCount == 1 ? String(localized: "1 follow-up open") : String(localized: "\(pendingLatestFollowUpCount) follow-ups open"),
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            if handoffStore.draftFocusAreas.items.count > 0 {
                Label(
                    handoffStore.draftFocusAreas.items.count == 1 ? String(localized: "1 focus area") : String(localized: "\(handoffStore.draftFocusAreas.items.count) focus areas"),
                    systemImage: "scope"
                )
            }
        }
    }

    private var handoffSurfaceDeckCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSurfaceGroupCard(
                title: String(localized: "Primary"),
                detail: String(localized: "Keep the live queue and shift-facing exits closest to the handoff draft.")
            ) {
                FlowLayout(spacing: 8) {
                    NavigationLink {
                        OnCallView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "On Call"),
                            systemImage: "waveform.path.ecg",
                            tone: queueCount > 0 ? .warning : .neutral,
                            badgeText: queueCount == 0 ? nil : (queueCount == 1 ? String(localized: "1 queued") : String(localized: "\(queueCount) queued"))
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        NightWatchView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Night Watch"),
                            systemImage: "moon.stars",
                            tone: criticalCount > 0 ? .critical : .neutral,
                            badgeText: criticalCount == 0 ? nil : (criticalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalCount) critical"))
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        StandbyDigestView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Standby"),
                            systemImage: "rectangle.inset.filled",
                            tone: liveAlertCount > 0 ? .warning : .neutral,
                            badgeText: liveAlertCount == 0 ? nil : (liveAlertCount == 1 ? String(localized: "1 alert") : String(localized: "\(liveAlertCount) alerts"))
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        IncidentsView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Incidents"),
                            systemImage: "bell.badge",
                            tone: criticalCount > 0 ? .critical : .warning,
                            badgeText: liveAlertCount == 0 ? nil : (liveAlertCount == 1 ? String(localized: "1 alert") : String(localized: "\(liveAlertCount) alerts"))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            MonitoringSurfaceGroupCard(
                title: String(localized: "Support"),
                detail: String(localized: "Keep runtime, diagnostics, and settings in a secondary rail.")
            ) {
                FlowLayout(spacing: 8) {
                    NavigationLink {
                        RuntimeView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Runtime"),
                            systemImage: "server.rack",
                            tone: liveAlertCount > 0 ? .warning : .neutral
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Diagnostics"),
                            systemImage: "stethoscope",
                            tone: vm.diagnosticsSummaryTone,
                            badgeText: vm.diagnosticsConfigWarningCount > 0
                                ? (vm.diagnosticsConfigWarningCount == 1 ? String(localized: "1 warning") : String(localized: "\(vm.diagnosticsConfigWarningCount) warnings"))
                                : nil
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SettingsView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Settings"),
                            systemImage: "gearshape",
                            tone: handoffStore.freshnessState.tone
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func deleteFilteredEntries(at offsets: IndexSet) {
        let ids = offsets.compactMap { filteredEntries.indices.contains($0) ? filteredEntries[$0].id : nil }
        handoffStore.removeEntries(ids: ids)
    }

    private func matches(filter: HandoffHistoryFilter, for entry: OnCallHandoffEntry) -> Bool {
        switch filter {
        case .all:
            true
        case .critical:
            entry.criticalCount > 0
        case .queued:
            entry.queueCount > 0 || entry.liveAlertCount > 0
        case .calm:
            entry.queueCount == 0 && entry.criticalCount == 0 && entry.liveAlertCount == 0
        }
    }

    private func matchesSearch(_ entry: OnCallHandoffEntry) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        return entry.note.localizedCaseInsensitiveContains(query)
            || entry.summary.localizedCaseInsensitiveContains(query)
            || entry.followUpItems.contains(where: { $0.localizedCaseInsensitiveContains(query) })
    }
}

private struct HandoffDraftSnapshotCard: View {
    let kind: HandoffSnapshotKind
    let readiness: HandoffReadinessStatus
    let focusCount: Int
    let followUpCount: Int
    let checkInWindowLabel: String

    var body: some View {
        MonitoringSnapshotCard(summary: String(localized: "Draft snapshot is ready for handoff composition.")) {
            FlowLayout(spacing: 8) {
                PresentationToneBadge(text: kind.label, tone: .neutral)
                PresentationToneBadge(text: readiness.state.label, tone: readiness.state.tone)
                PresentationToneBadge(
                    text: focusCount == 1 ? String(localized: "1 focus area") : String(localized: "\(focusCount) focus areas"),
                    tone: focusCount > 0 ? .positive : .neutral
                )
                PresentationToneBadge(
                    text: followUpCount == 1 ? String(localized: "1 follow-up") : String(localized: "\(followUpCount) follow-ups"),
                    tone: followUpCount > 0 ? .warning : .neutral
                )
                PresentationToneBadge(text: checkInWindowLabel, tone: .neutral)
            }
        }
        .padding(.bottom, 2)
    }
}

private struct HandoffDraftContextCard: View {
    @Binding var kind: HandoffSnapshotKind
    let readiness: HandoffReadinessStatus
    let focusCount: Int
    let followUpCount: Int
    @Binding var checkInWindow: HandoffCheckInWindow
    let queueCount: Int
    let criticalCount: Int
    let liveAlertCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HandoffDraftSnapshotCard(
                kind: kind,
                readiness: readiness,
                focusCount: focusCount,
                followUpCount: followUpCount,
                checkInWindowLabel: checkInWindow.label
            )

            HandoffStatsRow(
                queueCount: queueCount,
                criticalCount: criticalCount,
                liveAlertCount: liveAlertCount
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Snapshot Type")
                    .font(.subheadline.weight(.semibold))

                Picker("Snapshot Type", selection: $kind) {
                    ForEach(HandoffSnapshotKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }

                Text(kind.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HandoffCheckInComposer(window: $checkInWindow)
        }
        .padding(.vertical, 4)
    }
}

private struct HandoffNoteComposerCard: View {
    @Binding var note: String
    let kind: HandoffSnapshotKind
    let suggestedTemplateNote: String
    let onUseSuggestedNote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResponsiveAccessoryRow(horizontalAlignment: .top, verticalSpacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Operator note")
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "Lead with a concise shift summary, then let the checklist and follow-ups carry the operational detail."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } accessory: {
                HandoffKindBadge(kind: kind)
            }

            TextEditor(text: $note)
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(suggestedTemplateNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: onUseSuggestedNote) {
                    Label("Use Suggested Note", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.vertical, 4)
    }
}

private struct HandoffDraftActionsCard: View {
    let readiness: HandoffReadinessStatus
    let shareText: String
    let onSave: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringFactsRow(
                verticalSpacing: 10,
                headerVerticalSpacing: 6,
                factsFont: .caption2
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Draft Actions"))
                        .font(.subheadline.weight(.semibold))
                    Text(readiness.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } accessory: {
                PresentationToneBadge(text: readiness.state.label, tone: readiness.state.tone)
            } facts: {
                ForEach(readiness.issues) { issue in
                    Label(issue.message, systemImage: issue.isBlocking ? "exclamationmark.triangle.fill" : "info.circle")
                        .foregroundStyle(issue.tone.color)
                }
            }

            Button(action: onSave) {
                Label(
                    readiness.state == .blocked ? String(localized: "Save Snapshot Anyway") : String(localized: "Save Snapshot"),
                    systemImage: "square.and.arrow.down"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    resetButton
                    shareButton
                }

                VStack(spacing: 10) {
                    resetButton
                    shareButton
                }
            }
        }
    }

    private var resetButton: some View {
        Button(role: .destructive, action: onReset) {
            Label("Reset Draft", systemImage: "arrow.counterclockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var shareButton: some View {
        ShareLink(item: shareText) {
            Label("Share Current Summary", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

private struct HandoffShiftContextInventoryDeck: View {
    let coverageCount: Int
    let freshnessState: HandoffFreshnessState
    let cadenceState: HandoffCadenceState
    let readiness: HandoffReadinessStatus
    let checkInStatus: HandoffCheckInStatus?
    let pendingFollowUpCount: Int
    let completedFollowUpCount: Int
    let uncoveredChecklistCount: Int
    let carryoverStatus: HandoffCarryoverStatus?
    let drift: HandoffSnapshotDrift?
    let latestEntryDate: Date?

    private var activeCarryoverCount: Int {
        carryoverStatus?.unresolvedCount ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: detailLine,
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: freshnessState.label, tone: freshnessState.tone)
                    PresentationToneBadge(text: cadenceState.label, tone: cadenceState.tone)
                    PresentationToneBadge(text: readiness.state.label, tone: readiness.state.tone)
                    if let checkInStatus {
                        PresentationToneBadge(text: checkInStatus.state.label, tone: checkInStatus.state.tone)
                    }
                    if let carryoverStatus {
                        PresentationToneBadge(text: carryoverStatus.state.label, tone: carryoverStatus.state.tone)
                    }
                    if let drift {
                        PresentationToneBadge(text: drift.state.label, tone: drift.state.tone)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Shift context inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Use this compact context slice to verify freshness, cadence, carryover, and follow-up load before opening the full handoff cards."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: coverageCount == 1 ? String(localized: "1 recent handoff") : String(localized: "\(coverageCount) recent handoffs"),
                    tone: coverageCount > 0 ? .positive : .neutral
                )
            } facts: {
                if pendingFollowUpCount > 0 {
                    Label(
                        pendingFollowUpCount == 1 ? String(localized: "1 pending follow-up") : String(localized: "\(pendingFollowUpCount) pending follow-ups"),
                        systemImage: "checklist.unchecked"
                    )
                }
                if completedFollowUpCount > 0 {
                    Label(
                        completedFollowUpCount == 1 ? String(localized: "1 follow-up done") : String(localized: "\(completedFollowUpCount) follow-ups done"),
                        systemImage: "checkmark.circle"
                    )
                }
                if uncoveredChecklistCount > 0 {
                    Label(
                        uncoveredChecklistCount == 1 ? String(localized: "1 checklist gap") : String(localized: "\(uncoveredChecklistCount) checklist gaps"),
                        systemImage: "square.dashed"
                    )
                }
                if activeCarryoverCount > 0 {
                    Label(
                        activeCarryoverCount == 1 ? String(localized: "1 carryover focus") : String(localized: "\(activeCarryoverCount) carryover focus areas"),
                        systemImage: "arrow.triangle.branch"
                    )
                }
                if let latestSavedLabel {
                    Label(latestSavedLabel, systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        switch readiness.state {
        case .ready:
            return String(localized: "Shift context is ready for handoff drafting.")
        case .caution:
            return String(localized: "Shift context is usable, but some operator context still needs review.")
        case .blocked:
            return String(localized: "Shift context still has blocking gaps before the draft should be saved.")
        }
    }

    private var detailLine: String {
        if coverageCount == 0 {
            return String(localized: "No local handoff history exists yet, so cadence and carryover can only be inferred from the live queue.")
        }
        if activeCarryoverCount > 0 {
            return String(localized: "Recent handoffs exist, but unresolved carryover areas still need explicit coverage before the next shift takes over.")
        }
        return String(localized: "Recent handoffs, cadence, and follow-up state are all visible here so the draft can stay focused on the next operator handoff.")
    }

    private var latestSavedLabel: String? {
        guard let latestEntryDate else { return nil }
        return String(localized: "Latest \(RelativeDateTimeFormatter().localizedString(for: latestEntryDate, relativeTo: Date()))")
    }
}

private struct HandoffActionDeckInventoryCard: View {
    let kind: HandoffSnapshotKind
    let readiness: HandoffReadinessStatus
    let checklist: HandoffChecklistState
    let focusAreas: HandoffFocusState
    let followUpCount: Int
    let suggestedFocusCount: Int
    let suggestedFollowUpCount: Int
    let checkInWindow: HandoffCheckInWindow

    private var pendingChecklistCount: Int {
        checklist.totalCount - checklist.completedCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: detailLine,
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: kind.label, tone: kindTone)
                    PresentationToneBadge(text: readiness.state.label, tone: readiness.state.tone)
                    PresentationToneBadge(text: String(localized: "Checklist \(checklist.progressLabel)"), tone: checklist.tone)
                    if checkInWindow != .none {
                        PresentationToneBadge(text: checkInWindow.label, tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Draft action inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "This compact deck keeps checklist progress, focus scope, and follow-up load visible before composing or saving the handoff."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: followUpCount == 1 ? String(localized: "1 draft follow-up") : String(localized: "\(followUpCount) draft follow-ups"),
                    tone: followUpCount > 0 ? .warning : .neutral
                )
            } facts: {
                Label(
                    focusAreas.items.count == 1 ? String(localized: "1 selected focus area") : String(localized: "\(focusAreas.items.count) selected focus areas"),
                    systemImage: "scope"
                )
                if pendingChecklistCount > 0 {
                    Label(
                        pendingChecklistCount == 1 ? String(localized: "1 checklist item pending") : String(localized: "\(pendingChecklistCount) checklist items pending"),
                        systemImage: "square.dashed"
                    )
                }
                if suggestedFocusCount > 0 {
                    Label(
                        suggestedFocusCount == 1 ? String(localized: "1 suggested focus") : String(localized: "\(suggestedFocusCount) suggested focus areas"),
                        systemImage: "lightbulb"
                    )
                }
                if suggestedFollowUpCount > 0 {
                    Label(
                        suggestedFollowUpCount == 1 ? String(localized: "1 suggested follow-up") : String(localized: "\(suggestedFollowUpCount) suggested follow-ups"),
                        systemImage: "wand.and.stars"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        switch readiness.state {
        case .ready:
            return String(localized: "Action Deck is ready to save or share.")
        case .caution:
            return String(localized: "Action Deck is usable, but the draft still needs a little more operator context.")
        case .blocked:
            return String(localized: "Action Deck is blocked until the draft covers the current runtime pressure.")
        }
    }

    private var detailLine: String {
        if followUpCount == 0 && focusAreas.items.isEmpty {
            return String(localized: "Checklist work is visible, but focus areas and follow-ups are still empty, so the saved handoff may feel thin.")
        }
        return String(localized: "Checklist progress, selected focus areas, and saved follow-ups are compacted here so the operator can finish the draft without hunting across the section.")
    }

    private var kindTone: PresentationTone {
        switch kind {
        case .routine:
            .neutral
        case .watch:
            .warning
        case .incident:
            .critical
        case .recovery:
            .positive
        }
    }
}

private struct HandoffTimelineInventoryDeck: View {
    let items: [HandoffTimelineItem]
    let gapWarningCount: Int

    private var queuedEntryCount: Int {
        items.filter { $0.entry.queueCount > 0 || $0.entry.liveAlertCount > 0 }.count
    }

    private var criticalEntryCount: Int {
        items.filter { $0.entry.criticalCount > 0 }.count
    }

    private var largestGap: TimeInterval? {
        items.compactMap(\.gapToOlderEntry).max()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: detailLine,
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: items.count == 1 ? String(localized: "1 timeline entry") : String(localized: "\(items.count) timeline entries"),
                        tone: .neutral
                    )
                    if gapWarningCount > 0 {
                        PresentationToneBadge(
                            text: gapWarningCount == 1 ? String(localized: "1 cadence gap") : String(localized: "\(gapWarningCount) cadence gaps"),
                            tone: .warning
                        )
                    }
                    if let latestLabel {
                        PresentationToneBadge(text: latestLabel, tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Timeline inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Use the compact timeline slice to spot cadence gaps before opening every saved handoff row in the chronology below."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: gapWarningCount == 0 ? String(localized: "Cadence steady") : String(localized: "Needs timeline review"),
                    tone: gapWarningCount == 0 ? .positive : .warning
                )
            } facts: {
                if queuedEntryCount > 0 {
                    Label(
                        queuedEntryCount == 1 ? String(localized: "1 queued handoff") : String(localized: "\(queuedEntryCount) queued handoffs"),
                        systemImage: "tray.full"
                    )
                }
                if criticalEntryCount > 0 {
                    Label(
                        criticalEntryCount == 1 ? String(localized: "1 critical handoff") : String(localized: "\(criticalEntryCount) critical handoffs"),
                        systemImage: "exclamationmark.octagon"
                    )
                }
                if let largestGap {
                    Label(
                        String(localized: "Largest gap \(OnCallHandoffStore.formatInterval(largestGap))"),
                        systemImage: "clock.badge.exclamationmark"
                    )
                }
                if let oldestLabel {
                    Label(oldestLabel, systemImage: "clock")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        gapWarningCount == 0
            ? String(localized: "Timeline is showing a steady local handoff cadence.")
            : String(localized: "Timeline is showing \(gapWarningCount) cadence gaps across recent local handoffs.")
    }

    private var detailLine: String {
        String(localized: "The timeline deck summarizes recent local handoff spacing before you drill into the full chronology row by row.")
    }

    private var latestLabel: String? {
        guard let latest = items.map(\.entry.createdAt).max() else { return nil }
        return String(localized: "Latest \(RelativeDateTimeFormatter().localizedString(for: latest, relativeTo: Date()))")
    }

    private var oldestLabel: String? {
        guard let oldest = items.map(\.entry.createdAt).min() else { return nil }
        return String(localized: "Oldest \(RelativeDateTimeFormatter().localizedString(for: oldest, relativeTo: Date()))")
    }
}

private struct HandoffRouteInventoryDeck: View {
    let queueCount: Int
    let criticalCount: Int
    let liveAlertCount: Int
    let pendingApprovalCount: Int
    let diagnosticsWarningCount: Int
    let primaryRouteCount: Int
    let supportRouteCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(
                summary: String(localized: "The handoff deck keeps \(primaryRouteCount) primary routes and \(supportRouteCount) support routes close to the draft."),
                detail: String(localized: "Live queue exits stay on the primary rail; runtime and settings stay behind them on the support rail."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: queueCount == 1 ? String(localized: "1 queued route context") : String(localized: "\(queueCount) queued route context"),
                        tone: queueCount > 0 ? .warning : .neutral
                    )
                    if criticalCount > 0 {
                        PresentationToneBadge(
                            text: criticalCount == 1 ? String(localized: "1 critical route") : String(localized: "\(criticalCount) critical routes"),
                            tone: .critical
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Route inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Use the compact route inventory before leaving the draft, so queue-first exits stay distinct from slower support drills."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: String(localized: "\(primaryRouteCount + supportRouteCount) exits"),
                    tone: .neutral
                )
            } facts: {
                Label(
                    primaryRouteCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryRouteCount) primary routes"),
                    systemImage: "arrowshape.turn.up.right"
                )
                Label(
                    supportRouteCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportRouteCount) support routes"),
                    systemImage: "square.grid.2x2"
                )
                if liveAlertCount > 0 {
                    Label(
                        liveAlertCount == 1 ? String(localized: "1 live alert") : String(localized: "\(liveAlertCount) live alerts"),
                        systemImage: "bell.badge"
                    )
                }
                if pendingApprovalCount > 0 {
                    Label(
                        pendingApprovalCount == 1 ? String(localized: "1 approval") : String(localized: "\(pendingApprovalCount) approvals"),
                        systemImage: "checkmark.shield"
                    )
                }
                if diagnosticsWarningCount > 0 {
                    Label(
                        diagnosticsWarningCount == 1 ? String(localized: "1 diagnostics warning") : String(localized: "\(diagnosticsWarningCount) diagnostics warnings"),
                        systemImage: "stethoscope"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct HandoffSectionInventoryDeck: View {
    let sectionCount: Int
    let timelineCount: Int
    let historyCount: Int
    let focusCount: Int
    let followUpCount: Int
    let pendingFollowUpCount: Int
    let readiness: HandoffReadinessStatus
    let queueCount: Int
    let criticalCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: sectionCount == 1 ? String(localized: "1 live section") : String(localized: "\(sectionCount) live sections"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: queueCount == 1 ? String(localized: "1 queued item") : String(localized: "\(queueCount) queued items"),
                        tone: queueCount > 0 ? .warning : .neutral
                    )
                    if pendingFollowUpCount > 0 {
                        PresentationToneBadge(
                            text: pendingFollowUpCount == 1 ? String(localized: "1 pending follow-up") : String(localized: "\(pendingFollowUpCount) pending follow-ups"),
                            tone: .warning
                        )
                    }
                    PresentationToneBadge(text: readiness.state.label, tone: readiness.state.tone)
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Section inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep draft readiness, timeline depth, and history coverage visible before the route deck and longer editor sections."))
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
                Label(
                    timelineCount == 1 ? String(localized: "1 timeline item") : String(localized: "\(timelineCount) timeline items"),
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                )
                Label(
                    historyCount == 1 ? String(localized: "1 history entry") : String(localized: "\(historyCount) history entries"),
                    systemImage: "text.badge.plus"
                )
                Label(
                    focusCount == 1 ? String(localized: "1 focus area") : String(localized: "\(focusCount) focus areas"),
                    systemImage: "scope"
                )
                Label(
                    followUpCount == 1 ? String(localized: "1 drafted follow-up") : String(localized: "\(followUpCount) drafted follow-ups"),
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
        }
    }

    private var summaryLine: String {
        sectionCount == 1
            ? String(localized: "1 handoff section is active below the controls deck.")
            : String(localized: "\(sectionCount) handoff sections are active below the controls deck.")
    }

    private var detailLine: String {
        String(localized: "Draft context, timeline depth, and saved history stay summarized before the route deck and editor sections take over.")
    }
}

private struct HandoffHistoryFilterCard: View {
    @Binding var filter: HandoffHistoryFilter
    let searchText: String
    let visibleCount: Int
    let totalCount: Int

    var body: some View {
        MonitoringFilterCard(summary: summaryLine, detail: searchSummary) {
            PresentationToneBadge(text: filter.label, tone: badgeTone)
        } controls: {
            FlowLayout(spacing: 8) {
                ForEach(HandoffHistoryFilter.allCases) { option in
                    Button {
                        filter = option
                    } label: {
                        SelectableCapsuleBadge(text: option.label, isSelected: filter == option)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var summaryLine: String {
        if visibleCount == totalCount {
            return totalCount == 1
                ? String(localized: "1 saved handoff in history")
                : String(localized: "\(totalCount) saved handoffs in history")
        }
        return String(localized: "\(visibleCount) of \(totalCount) handoffs visible")
    }

    private var searchSummary: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return String(localized: "Search notes or summaries to narrow the local handoff history.")
        }
        return String(localized: "Search active: \"\(query)\"")
    }

    private var badgeTone: PresentationTone {
        switch filter {
        case .all:
            return .neutral
        case .critical:
            return .critical
        case .queued:
            return .warning
        case .calm:
            return .positive
        }
    }
}

private struct HandoffHistoryInventoryDeck: View {
    let entries: [OnCallHandoffEntry]
    let totalCount: Int
    let filterLabel: String
    let filterTone: PresentationTone
    let searchText: String

    private var visibleCount: Int {
        entries.count
    }

    private var criticalEntryCount: Int {
        entries.filter { $0.criticalCount > 0 }.count
    }

    private var queuedEntryCount: Int {
        entries.filter { $0.queueCount > 0 || $0.liveAlertCount > 0 }.count
    }

    private var calmEntryCount: Int {
        entries.filter { $0.queueCount == 0 && $0.criticalCount == 0 && $0.liveAlertCount == 0 }.count
    }

    private var followUpItemCount: Int {
        entries.reduce(0) { $0 + $1.followUpItems.count }
    }

    private var focusAreaCount: Int {
        Set(entries.flatMap { $0.focusAreas.items.map(\.id) }).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: detailLine,
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: filterLabel, tone: filterTone)
                    if !trimmedSearchText.isEmpty {
                        PresentationToneBadge(text: String(localized: "Search scoped"), tone: .neutral)
                    }
                    if criticalEntryCount > 0 {
                        PresentationToneBadge(
                            text: criticalEntryCount == 1 ? String(localized: "1 critical handoff") : String(localized: "\(criticalEntryCount) critical handoffs"),
                            tone: .critical
                        )
                    }
                    if queuedEntryCount > 0 {
                        PresentationToneBadge(
                            text: queuedEntryCount == 1 ? String(localized: "1 queued handoff") : String(localized: "\(queuedEntryCount) queued handoffs"),
                            tone: .warning
                        )
                    }
                    if let latestSavedLabel {
                        PresentationToneBadge(text: latestSavedLabel, tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "History inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Use the compact history slice to gauge how much shift context is already visible before opening full handoff cards."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == totalCount
                        ? String(localized: "Full history")
                        : String(localized: "\(visibleCount)/\(totalCount) visible"),
                    tone: visibleCount == totalCount ? .positive : .neutral
                )
            } facts: {
                Label(
                    visibleCount == 1 ? String(localized: "1 saved handoff") : String(localized: "\(visibleCount) saved handoffs"),
                    systemImage: "tray.full"
                )
                if calmEntryCount > 0 {
                    Label(
                        calmEntryCount == 1 ? String(localized: "1 calm handoff") : String(localized: "\(calmEntryCount) calm handoffs"),
                        systemImage: "checkmark.circle"
                    )
                }
                if followUpItemCount > 0 {
                    Label(
                        followUpItemCount == 1 ? String(localized: "1 follow-up item") : String(localized: "\(followUpItemCount) follow-up items"),
                        systemImage: "checklist.unchecked"
                    )
                }
                if focusAreaCount > 0 {
                    Label(
                        focusAreaCount == 1 ? String(localized: "1 focus area") : String(localized: "\(focusAreaCount) focus areas"),
                        systemImage: "scope"
                    )
                }
                if let oldestVisibleLabel {
                    Label(oldestVisibleLabel, systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var summaryLine: String {
        if visibleCount == totalCount {
            return visibleCount == 1
                ? String(localized: "The saved history deck is showing the only local handoff entry.")
                : String(localized: "The saved history deck is showing all \(visibleCount) local handoff entries.")
        }
        return String(localized: "The saved history deck is showing \(visibleCount) of \(totalCount) local handoff entries.")
    }

    private var detailLine: String {
        if trimmedSearchText.isEmpty {
            return String(localized: "Filter by critical, queued, or calm handoffs first, then search notes or summaries only when the local history is still too broad.")
        }
        return String(localized: "Search is narrowed to \"\(trimmedSearchText)\", so the recent handoff history stays focused on the matching shift context.")
    }

    private var latestSavedLabel: String? {
        guard let latest = entries.map(\.createdAt).max() else { return nil }
        return String(localized: "Latest \(RelativeDateTimeFormatter().localizedString(for: latest, relativeTo: Date()))")
    }

    private var oldestVisibleLabel: String? {
        guard let oldest = entries.map(\.createdAt).min() else { return nil }
        return String(localized: "Oldest \(RelativeDateTimeFormatter().localizedString(for: oldest, relativeTo: Date()))")
    }
}

private struct HandoffCadenceCard: View {
    let cadenceState: HandoffCadenceState
    let cadenceSummary: String
    let warningCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow {
                titleLabel
            } accessory: {
                PresentationToneBadge(text: cadenceState.label, tone: cadenceState.tone)
            }

            Text(cadenceSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            if warningCount > 0 {
                Text(
                    warningCount == 1
                        ? String(localized: "1 recent handoff gap crossed the warning threshold.")
                        : String(localized: "\(warningCount) recent handoff gaps crossed the warning threshold.")
                )
                    .font(.caption2)
                    .foregroundStyle(PresentationTone.warning.color)
            }
        }
        .padding(.vertical, 6)
    }

    private var titleLabel: some View {
        Label("Cadence", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct HandoffDriftCard: View {
    let drift: HandoffSnapshotDrift

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow {
                titleLabel
            } accessory: {
                PresentationToneBadge(text: drift.state.label, tone: drift.state.tone)
            }

            Text(drift.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Baseline: \(drift.baseline.createdAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var titleLabel: some View {
        Label("Current Drift", systemImage: "arrow.left.arrow.right")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct HandoffCarryoverCard: View {
    let status: HandoffCarryoverStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow {
                titleLabel
            } accessory: {
                PresentationToneBadge(text: status.state.label, tone: status.state.tone)
            }

            Text(status.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(status.items) { item in
                ResponsiveValueRow(
                    horizontalAlignment: .top,
                    horizontalSpacing: 10,
                    verticalSpacing: 6,
                    horizontalTextAlignment: .leading
                ) {
                    HandoffFocusAreaBadge(area: item.area)
                } value: {
                    Text(item.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var titleLabel: some View {
        Label("Carryover", systemImage: "arrow.triangle.branch")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct HandoffReadinessCard: View {
    let status: HandoffReadinessStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow {
                titleLabel
            } accessory: {
                PresentationToneBadge(text: status.state.label, tone: status.state.tone)
            }

            Text(status.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(status.issues) { issue in
                Label(issue.message, systemImage: issue.isBlocking ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(.caption2)
                    .foregroundStyle(issue.tone.color)
            }
        }
        .padding(.vertical, 6)
    }

    private var titleLabel: some View {
        Label("Readiness", systemImage: "checkmark.seal")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct HandoffCheckInCard: View {
    let status: HandoffCheckInStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow {
                titleLabel
            } accessory: {
                PresentationToneBadge(text: status.state.label, tone: status.state.tone)
            }

            Text(status.dueLabel)
                .font(.caption)
                .foregroundStyle(.primary)

            Text(status.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var titleLabel: some View {
        Label("Check-in Window", systemImage: "timer")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct HandoffKindBadge: View {
    let kind: HandoffSnapshotKind

    var body: some View {
        TintedLabelCapsuleBadge(
            text: kind.label,
            systemImage: kind.symbolName,
            foregroundStyle: kind.tintColor,
            backgroundStyle: kind.badgeBackgroundColor,
            horizontalPadding: 8,
            verticalPadding: 5
        )
    }
}

private struct HandoffStatsRow: View {
    let queueCount: Int
    let criticalCount: Int
    let liveAlertCount: Int

    var body: some View {
        FlowLayout(spacing: 10) {
            HandoffStatPill(value: queueCount, label: String(localized: "Queued"))
            HandoffStatPill(value: criticalCount, label: String(localized: "Critical"))
            HandoffStatPill(value: liveAlertCount, label: String(localized: "Live"))
        }
    }
}

private struct HandoffTimelineRow: View {
    let item: HandoffTimelineItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ResponsiveAccessoryRow(horizontalAlignment: .top) {
                timelineSummary
            } accessory: {
                timelineBadges(alignment: .trailing)
            }

            if !item.entry.note.isEmpty {
                Text(item.entry.note)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            FlowLayout(spacing: 10) {
                HandoffStatPill(value: item.entry.queueCount, label: String(localized: "Queued"))
                HandoffStatPill(value: item.entry.criticalCount, label: String(localized: "Critical"))
                HandoffStatPill(value: item.entry.checklist.completedCount, label: String(localized: "Checks"))
            }

            if !item.entry.focusAreas.items.isEmpty {
                HandoffFocusSummaryRow(focusAreas: item.entry.focusAreas)
            }

            if item.entry.checkInWindow != .none {
                HandoffCheckInSummaryRow(window: item.entry.checkInWindow, createdAt: item.entry.createdAt)
            }

            if !item.entry.followUpItems.isEmpty {
                HandoffFollowUpSummaryRow(items: item.entry.followUpItems)
            }
        }
        .padding(.vertical, 4)
    }

    private var timelineSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.entry.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.subheadline.weight(.semibold))
            Text(item.entry.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func timelineBadges(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            HandoffKindBadge(kind: item.entry.kind)

            PresentationToneBadge(
                text: item.gapToOlderEntry == nil ? String(localized: "Latest") : item.gapLabel,
                tone: item.gapTone
            )
        }
    }
}

private struct HandoffFreshnessCard: View {
    let freshnessState: HandoffFreshnessState
    let freshnessSummary: String
    let latestEntry: OnCallHandoffEntry?
    let uncoveredChecklistKeys: [HandoffChecklistKey]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResponsiveAccessoryRow {
                titleLabel
            } accessory: {
                PresentationToneBadge(text: freshnessState.label, tone: freshnessState.tone)
            }

            Text(freshnessSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let latestEntry {
                HandoffStatsRow(
                    queueCount: latestEntry.queueCount,
                    criticalCount: latestEntry.criticalCount,
                    liveAlertCount: latestEntry.liveAlertCount
                )
            }

            if uncoveredChecklistKeys.isEmpty {
                Text("All checklist items appeared in the recent handoff window.")
                    .font(.caption2)
                    .foregroundStyle(PresentationTone.positive.color)
            } else {
                Text(String(localized: "Recent gap: \(uncoveredChecklistKeys.map(\.label).joined(separator: ", "))"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    private var titleLabel: some View {
        Label("Handoff Freshness", systemImage: "clock.badge.checkmark")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct HandoffCoverageCard: View {
    let entries: [OnCallHandoffEntry]
    let coverageCount: (HandoffChecklistKey) -> Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow {
                titleLabel
            } accessory: {
                coverageCountLabel
            }

            ForEach(Array(HandoffChecklistKey.allCases.enumerated()), id: \.element.rawValue) { _, key in
                let coverageTone = HandoffChecklistState.coverageTone(for: coverageCount(key))
                ResponsiveValueRow {
                    coverageLabel(for: key)
                } value: {
                    coverageValue(for: key, tone: coverageTone)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var titleLabel: some View {
        Label("Recent Coverage", systemImage: "list.bullet.clipboard")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var coverageCountLabel: some View {
        Text(entries.isEmpty ? String(localized: "No history") : String(localized: "\(entries.count) snapshots"))
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func coverageLabel(for key: HandoffChecklistKey) -> some View {
        Label(key.label, systemImage: key.symbolName)
            .font(.caption)
            .foregroundStyle(.primary)
    }

    private func coverageValue(for key: HandoffChecklistKey, tone: PresentationTone) -> some View {
        Text("\(coverageCount(key))/\(max(entries.count, 1))")
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone.color)
    }
}

private struct HandoffChecklistComposer: View {
    let checklist: HandoffChecklistState
    let toggle: (HandoffChecklistKey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow(verticalSpacing: 4) {
                titleLabel
            } accessory: {
                progressLabel
            }

            ForEach(HandoffChecklistKey.allCases) { key in
                Button {
                    toggle(key)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: checklist.contains(key) ? "checkmark.circle.fill" : key.symbolName)
                            .foregroundStyle(checklist.itemTone(for: key).color)
                            .frame(width: 18)

                        Text(key.label)
                            .foregroundStyle(.primary)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var titleLabel: some View {
        Text("Handoff checklist")
            .font(.subheadline.weight(.semibold))
    }

    private var progressLabel: some View {
        Text(checklist.progressLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct HandoffFollowUpTrackerCard: View {
    let statuses: [HandoffFollowUpStatus]
    let onToggle: (HandoffFollowUpStatus) -> Void

    private var followUpSummary: HandoffFollowUpSummary {
        HandoffFollowUpSummary.summarize(statuses: statuses)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow {
                titleLabel
            } accessory: {
                PresentationToneBadge(text: followUpSummary.badgeLabel, tone: followUpSummary.tone)
            }

            Text(followUpSummary.detailLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            ResponsiveInlineGroup(horizontalSpacing: 6, verticalSpacing: 2) {
                Text(String(localized: "\(followUpSummary.completedCount) complete"))
                Text(String(localized: "\(followUpSummary.pendingCount) pending"))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            ForEach(statuses) { status in
                Button {
                    onToggle(status)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: status.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(status.tone.color)
                            .font(.body)
                        Text(status.item)
                            .font(.caption)
                            .foregroundStyle(status.isCompleted ? .secondary : .primary)
                            .strikethrough(status.isCompleted, color: .secondary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private var titleLabel: some View {
        Label("Follow-up Tracker", systemImage: "checklist")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct HandoffFocusComposer: View {
    let focusAreas: HandoffFocusState
    let toggle: (HandoffFocusArea) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow(verticalSpacing: 4) {
                titleLabel
            } accessory: {
                countLabel
            }

            ForEach(HandoffFocusArea.allCases) { area in
                Button {
                    toggle(area)
                } label: {
                        let isSelected = focusAreas.contains(area)
                        HStack(spacing: 10) {
                            Image(systemName: area.symbolName)
                            .foregroundStyle(area.selectionColor(isSelected: isSelected))
                            .frame(width: 18)

                        Text(area.label)
                            .foregroundStyle(.primary)

                        Spacer()

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(area.selectionColor(isSelected: true))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var titleLabel: some View {
        Text("Focus areas")
            .font(.subheadline.weight(.semibold))
    }

    private var countLabel: some View {
        Text(focusAreas.items.isEmpty ? String(localized: "None") : String(localized: "\(focusAreas.items.count)"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct HandoffFollowUpComposer: View {
    let items: [String]
    @Binding var draftText: String
    let addAction: () -> Void
    let removeAction: (IndexSet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow(verticalSpacing: 4) {
                titleLabel
            } accessory: {
                itemCountLabel
            }

            ResponsiveAccessoryRow(
                horizontalAlignment: .center,
                horizontalSpacing: 10,
                verticalSpacing: 8,
                spacerMinLength: 10
            ) {
                followUpField
            } accessory: {
                addButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if items.isEmpty {
                Text("Capture concrete next-shift follow-ups when runtime pressure is still active.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1).")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(item)
                            .font(.caption)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                }

                Button(role: .destructive) {
                    removeAction(IndexSet(integersIn: items.indices))
                } label: {
                    Text("Clear Follow-ups")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var titleLabel: some View {
        Text("Follow-ups")
            .font(.subheadline.weight(.semibold))
    }

    private var itemCountLabel: some View {
        Text(items.isEmpty ? String(localized: "None") : String(localized: "\(items.count)"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var followUpField: some View {
        TextField(String(localized: "Add follow-up item"), text: $draftText)
            .textInputAutocapitalization(.sentences)
    }

    private var addButton: some View {
        Button(action: addAction) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
        }
        .buttonStyle(.plain)
        .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

private struct HandoffCheckInComposer: View {
    @Binding var window: HandoffCheckInWindow

    private var windowStatus: MonitoringSummaryStatus {
        .presenceStatus(isPresent: window != .none)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow(verticalSpacing: 4) {
                titleLabel
            } accessory: {
                windowLabel
            }

            Picker("Check-in Window", selection: $window) {
                ForEach(HandoffCheckInWindow.allCases) { option in
                    Text(option.label).tag(option)
                }
            }

            Text(window.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if window != .none {
                Text(String(localized: "Next check-in \(window.dueLabel(from: Date()))"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var titleLabel: some View {
        Text("Check-in window")
            .font(.subheadline.weight(.semibold))
    }

    private var windowLabel: some View {
        Text(window.label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(windowStatus.color(positive: .primary))
    }
}

struct HandoffFocusAreaBadge: View {
    let area: HandoffFocusArea

    var body: some View {
        TintedLabelCapsuleBadge(
            text: area.label,
            systemImage: area.symbolName,
            foregroundStyle: area.tintColor,
            backgroundStyle: area.badgeBackgroundColor,
            horizontalPadding: 8,
            verticalPadding: 5
        )
    }
}

struct HandoffFocusSummaryRow: View {
    let focusAreas: HandoffFocusState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ResponsiveAccessoryRow(verticalSpacing: 4) {
                titleLabel
            } accessory: {
                summaryLabel
            }

            if !focusAreas.items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(focusAreas.items) { area in
                            HandoffFocusAreaBadge(area: area)
                        }
                    }
                }
            }
        }
    }

    private var titleLabel: some View {
        Label("Focus", systemImage: "scope")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var summaryLabel: some View {
        Text(focusAreas.summaryLabel)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }
}

struct HandoffFollowUpSummaryRow: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ResponsiveAccessoryRow(verticalSpacing: 4) {
                titleLabel
            } accessory: {
                itemCountLabel
            }

            ForEach(Array(items.prefix(2).enumerated()), id: \.offset) { index, item in
                Text("\(index + 1). \(item)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var titleLabel: some View {
        Label("Follow-ups", systemImage: "checklist.unchecked")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var itemCountLabel: some View {
        Text(items.count == 1 ? String(localized: "1 item") : String(localized: "\(items.count) items"))
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

struct HandoffCheckInSummaryRow: View {
    let window: HandoffCheckInWindow
    let createdAt: Date

    var body: some View {
        ResponsiveAccessoryRow(verticalSpacing: 4) {
            titleLabel
        } accessory: {
            dueLabel
        }
    }

    private var titleLabel: some View {
        Label("Check-in", systemImage: "timer")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var dueLabel: some View {
        Text(window.dueLabel(from: createdAt))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }
}

private struct HandoffStatPill: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.subheadline.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct HandoffEntryCard: View {
    let entry: OnCallHandoffEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveAccessoryRow(horizontalAlignment: .top) {
                entrySummary
            } accessory: {
                entryControls
            }

            if !entry.note.isEmpty {
                Text(entry.note)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }

            Text(entry.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(6)

            HandoffStatsRow(
                queueCount: entry.queueCount,
                criticalCount: entry.criticalCount,
                liveAlertCount: entry.liveAlertCount
            )

            HandoffChecklistStatusRow(checklist: entry.checklist)

            if !entry.focusAreas.items.isEmpty {
                HandoffFocusSummaryRow(focusAreas: entry.focusAreas)
            }

            if entry.checkInWindow != .none {
                HandoffCheckInSummaryRow(window: entry.checkInWindow, createdAt: entry.createdAt)
            }

            if !entry.followUpItems.isEmpty {
                HandoffFollowUpSummaryRow(items: entry.followUpItems)
            }
        }
        .padding(.vertical, 6)
    }

    private var entrySummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.subheadline.weight(.semibold))
            Text(entry.createdAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var entryControls: some View {
        ResponsiveInlineGroup(horizontalSpacing: 10, verticalSpacing: 6) {
            HandoffKindBadge(kind: entry.kind)

            ShareLink(item: entry.shareText) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
        }
    }
}

private struct HandoffChecklistStatusRow: View {
    let checklist: HandoffChecklistState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ResponsiveAccessoryRow(verticalSpacing: 4) {
                titleLabel
            } accessory: {
                progressLabel
            }

            Text(checklist.summaryLabel)
                .font(.caption2)
                .foregroundStyle(checklist.tone.color)
                .lineLimit(2)
        }
    }

    private var titleLabel: some View {
        Label("Checklist", systemImage: "checklist")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var progressLabel: some View {
        Text(checklist.progressLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(checklist.tone.color)
    }
}

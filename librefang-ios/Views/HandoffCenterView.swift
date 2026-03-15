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
    private var carryoverStatus: HandoffCarryoverStatus? {
        handoffStore.carryoverFromLatest(
            liveAlertCount: liveAlertCount,
            pendingApprovalCount: vm.pendingApprovalCount,
            watchlistIssueCount: watchlistStore.watchedAgents(from: vm.agents).filter { vm.attentionItem(for: $0).severity > 0 }.count,
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
            watchlistIssueCount: watchlistStore.watchedAgents(from: vm.agents).filter { vm.attentionItem(for: $0).severity > 0 }.count,
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
        if watchlistStore.watchedAgents(from: vm.agents).contains(where: { vm.attentionItem(for: $0).severity > 0 }) {
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
        let watchIssues = watchlistStore.watchedAgents(from: vm.agents).filter { vm.attentionItem(for: $0).severity > 0 }.count
        if watchIssues > 0 {
            items.append(String(localized: "Re-check \(watchIssues) watchlist agents for readiness, auth, or stale-session issues."))
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

    var body: some View {
        List {
            Section {
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

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Operator note")
                        .font(.subheadline.weight(.semibold))

                    TextEditor(text: Binding(
                        get: { handoffStore.draftNote },
                        set: { handoffStore.draftNote = $0 }
                    ))
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    HandoffStatsRow(
                        queueCount: queueCount,
                        criticalCount: criticalCount,
                        liveAlertCount: liveAlertCount
                    )

                    Picker("Snapshot Type", selection: Binding(
                        get: { handoffStore.draftKind },
                        set: { handoffStore.draftKind = $0 }
                    )) {
                        ForEach(HandoffSnapshotKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }

                    Text(handoffStore.draftKind.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HandoffCheckInComposer(window: Binding(
                        get: { handoffStore.draftCheckInWindow },
                        set: { handoffStore.draftCheckInWindow = $0 }
                    ))

                    HStack(alignment: .top, spacing: 10) {
                        HandoffKindBadge(kind: handoffStore.draftKind)

                        Text(suggestedTemplateNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        handoffStore.useSuggestedDraftNote(
                            queueCount: queueCount,
                            criticalCount: criticalCount,
                            liveAlertCount: liveAlertCount
                        )
                    } label: {
                        Label("Use Suggested Note", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

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

                    Button {
                        handoffStore.saveSnapshot(
                            summary: summary,
                            queueCount: queueCount,
                            criticalCount: criticalCount,
                            liveAlertCount: liveAlertCount
                        )
                    } label: {
                        Label(
                            draftReadiness.state == .blocked ? String(localized: "Save Snapshot Anyway") : String(localized: "Save Snapshot"),
                            systemImage: "square.and.arrow.down"
                        )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    HStack(spacing: 10) {
                        Button(role: .destructive) {
                            handoffStore.resetDraft()
                        } label: {
                            Label("Reset Draft", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        ShareLink(item: currentShareText) {
                            Label("Share Current Summary", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Compose")
            } footer: {
                Text("Saved locally on this iPhone. Use this before handing the shift to another operator.")
            }

            if !timelineItems.isEmpty {
                Section {
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
                    Picker("History Filter", selection: $historyFilter) {
                        ForEach(HandoffHistoryFilter.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

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

private struct HandoffCadenceCard: View {
    let cadenceState: HandoffCadenceState
    let cadenceSummary: String
    let warningCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Cadence", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
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
}

private struct HandoffDriftCard: View {
    let drift: HandoffSnapshotDrift

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Current Drift", systemImage: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
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
}

private struct HandoffCarryoverCard: View {
    let status: HandoffCarryoverStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Carryover", systemImage: "arrow.triangle.branch")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                PresentationToneBadge(text: status.state.label, tone: status.state.tone)
            }

            Text(status.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(status.items) { item in
                HStack(alignment: .top, spacing: 10) {
                    HandoffFocusAreaBadge(area: item.area)
                    Text(item.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct HandoffReadinessCard: View {
    let status: HandoffReadinessStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Readiness", systemImage: "checkmark.seal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
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
}

private struct HandoffCheckInCard: View {
    let status: HandoffCheckInStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Check-in Window", systemImage: "timer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
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
}

struct HandoffKindBadge: View {
    let kind: HandoffSnapshotKind

    var body: some View {
        Label(kind.label, systemImage: kind.symbolName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(kind.badgeBackgroundColor)
            .foregroundStyle(kind.tintColor)
            .clipShape(Capsule())
    }
}

private struct HandoffStatsRow: View {
    let queueCount: Int
    let criticalCount: Int
    let liveAlertCount: Int

    var body: some View {
        HStack(spacing: 10) {
            HandoffStatPill(value: queueCount, label: String(localized: "Queued"))
            HandoffStatPill(value: criticalCount, label: String(localized: "Critical"))
            HandoffStatPill(value: liveAlertCount, label: String(localized: "Live"))
            Spacer()
        }
    }
}

private struct HandoffTimelineRow: View {
    let item: HandoffTimelineItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.entry.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.subheadline.weight(.semibold))
                    Text(item.entry.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    HandoffKindBadge(kind: item.entry.kind)

                    PresentationToneBadge(
                        text: item.gapToOlderEntry == nil ? String(localized: "Latest") : item.gapLabel,
                        tone: item.gapTone
                    )
                }
            }

            if !item.entry.note.isEmpty {
                Text(item.entry.note)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                HandoffStatPill(value: item.entry.queueCount, label: String(localized: "Queued"))
                HandoffStatPill(value: item.entry.criticalCount, label: String(localized: "Critical"))
                HandoffStatPill(value: item.entry.checklist.completedCount, label: String(localized: "Checks"))
                Spacer()
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
}

private struct HandoffFreshnessCard: View {
    let freshnessState: HandoffFreshnessState
    let freshnessSummary: String
    let latestEntry: OnCallHandoffEntry?
    let uncoveredChecklistKeys: [HandoffChecklistKey]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Handoff Freshness", systemImage: "clock.badge.checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
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
}

private struct HandoffCoverageCard: View {
    let entries: [OnCallHandoffEntry]
    let coverageCount: (HandoffChecklistKey) -> Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Recent Coverage", systemImage: "list.bullet.clipboard")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entries.isEmpty ? String(localized: "No history") : String(localized: "\(entries.count) snapshots"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(HandoffChecklistKey.allCases.enumerated()), id: \.element.rawValue) { _, key in
                let coverageTone = HandoffChecklistState.coverageTone(for: coverageCount(key))
                HStack {
                    Label(key.label, systemImage: key.symbolName)
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(coverageCount(key))/\(max(entries.count, 1))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(coverageTone.color)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct HandoffChecklistComposer: View {
    let checklist: HandoffChecklistState
    let toggle: (HandoffChecklistKey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Handoff checklist")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(checklist.progressLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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
}

private struct HandoffFollowUpTrackerCard: View {
    let statuses: [HandoffFollowUpStatus]
    let onToggle: (HandoffFollowUpStatus) -> Void

    private var followUpSummary: HandoffFollowUpSummary {
        HandoffFollowUpSummary.summarize(statuses: statuses)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Follow-up Tracker", systemImage: "checklist")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                PresentationToneBadge(text: followUpSummary.badgeLabel, tone: followUpSummary.tone)
            }

            Text(followUpSummary.detailLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(String(localized: "\(followUpSummary.completedCount) complete · \(followUpSummary.pendingCount) pending"))
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
}

private struct HandoffFocusComposer: View {
    let focusAreas: HandoffFocusState
    let toggle: (HandoffFocusArea) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Focus areas")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(focusAreas.items.isEmpty ? String(localized: "None") : String(localized: "\(focusAreas.items.count)"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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
}

private struct HandoffFollowUpComposer: View {
    let items: [String]
    @Binding var draftText: String
    let addAction: () -> Void
    let removeAction: (IndexSet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Follow-ups")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(items.isEmpty ? String(localized: "None") : String(localized: "\(items.count)"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                TextField(String(localized: "Add follow-up item"), text: $draftText)
                    .textInputAutocapitalization(.sentences)

                Button(action: addAction) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
}

private struct HandoffCheckInComposer: View {
    @Binding var window: HandoffCheckInWindow

    private var windowStatus: MonitoringSummaryStatus {
        .presenceStatus(isPresent: window != .none)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Check-in window")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(window.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(windowStatus.color(positive: .primary))
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
}

struct HandoffFocusAreaBadge: View {
    let area: HandoffFocusArea

    var body: some View {
        Label(area.label, systemImage: area.symbolName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(area.badgeBackgroundColor)
            .foregroundStyle(area.tintColor)
            .clipShape(Capsule())
    }
}

struct HandoffFocusSummaryRow: View {
    let focusAreas: HandoffFocusState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Focus", systemImage: "scope")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(focusAreas.summaryLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
}

struct HandoffFollowUpSummaryRow: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Follow-ups", systemImage: "checklist.unchecked")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(items.count == 1 ? String(localized: "1 item") : String(localized: "\(items.count) items"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(items.prefix(2).enumerated()), id: \.offset) { index, item in
                Text("\(index + 1). \(item)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

struct HandoffCheckInSummaryRow: View {
    let window: HandoffCheckInWindow
    let createdAt: Date

    var body: some View {
        HStack {
            Label("Check-in", systemImage: "timer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(window.dueLabel(from: createdAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
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
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.subheadline.weight(.semibold))
                    Text(entry.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    HandoffKindBadge(kind: entry.kind)

                    ShareLink(item: entry.shareText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                }
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
}

private struct HandoffChecklistStatusRow: View {
    let checklist: HandoffChecklistState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Checklist", systemImage: "checklist")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(checklist.progressLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(checklist.tone.color)
            }

            Text(checklist.summaryLabel)
                .font(.caption2)
                .foregroundStyle(checklist.tone.color)
                .lineLimit(2)
        }
    }
}

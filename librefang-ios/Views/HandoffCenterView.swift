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
            "All"
        case .critical:
            "Critical"
        case .queued:
            "Queued"
        case .calm:
            "Calm"
        }
    }
}

struct HandoffCenterView: View {
    @Environment(\.dependencies) private var deps
    @State private var searchText = ""
    @State private var historyFilter: HandoffHistoryFilter = .all

    let summary: String
    let queueCount: Int
    let criticalCount: Int
    let liveAlertCount: Int

    private var handoffStore: OnCallHandoffStore { deps.onCallHandoffStore }
    private var currentShareText: String {
        OnCallHandoffEntry.buildShareText(
            timestamp: Date(),
            kind: handoffStore.draftKind,
            note: handoffStore.draftNote.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary,
            queueCount: queueCount,
            criticalCount: criticalCount,
            liveAlertCount: liveAlertCount,
            checklist: handoffStore.draftChecklist
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

    var body: some View {
        List {
            Section {
                HandoffFreshnessCard(
                    freshnessLabel: handoffStore.freshnessLabel,
                    freshnessSummary: handoffStore.freshnessSummary,
                    latestEntry: handoffStore.latestEntry,
                    uncoveredChecklistKeys: handoffStore.uncoveredChecklistKeys
                )

                HandoffCoverageCard(
                    entries: coverageEntries,
                    coverageCount: { handoffStore.recentCoverageCount(for: $0) }
                )

                HandoffCadenceCard(
                    cadenceLabel: handoffStore.cadenceState.label,
                    cadenceSummary: handoffStore.cadenceSummary,
                    warningCount: handoffStore.cadenceWarningCount
                )
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

                    Button {
                        handoffStore.saveSnapshot(
                            summary: summary,
                            queueCount: queueCount,
                            criticalCount: criticalCount,
                            liveAlertCount: liveAlertCount
                        )
                    } label: {
                        Label("Save Snapshot", systemImage: "square.and.arrow.down")
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
    }
}

private struct HandoffCadenceCard: View {
    let cadenceLabel: String
    let cadenceSummary: String
    let warningCount: Int

    private var cadenceColor: Color {
        switch cadenceLabel {
        case "Steady":
            .green
        case "Sparse":
            .orange
        default:
            .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Cadence", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(cadenceLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(cadenceColor.opacity(0.12))
                    .foregroundStyle(cadenceColor)
                    .clipShape(Capsule())
            }

            Text(cadenceSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            if warningCount > 0 {
                Text(warningCount == 1 ? "1 recent handoff gap crossed the warning threshold." : "\(warningCount) recent handoff gaps crossed the warning threshold.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 6)
    }
}

struct HandoffKindBadge: View {
    let kind: HandoffSnapshotKind

    private var accentColor: Color {
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

    var body: some View {
        Label(kind.label, systemImage: kind.symbolName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(accentColor.opacity(0.12))
            .foregroundStyle(accentColor)
            .clipShape(Capsule())
    }
}

private struct HandoffStatsRow: View {
    let queueCount: Int
    let criticalCount: Int
    let liveAlertCount: Int

    var body: some View {
        HStack(spacing: 10) {
            HandoffStatPill(value: queueCount, label: "Queued")
            HandoffStatPill(value: criticalCount, label: "Critical")
            HandoffStatPill(value: liveAlertCount, label: "Live")
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

                    Text(item.gapToOlderEntry == nil ? "Latest" : item.gapLabel)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((item.isGapWarning ? Color.orange : Color.secondary).opacity(0.12))
                        .foregroundStyle(item.isGapWarning ? Color.orange : Color.secondary)
                        .clipShape(Capsule())
                }
            }

            if !item.entry.note.isEmpty {
                Text(item.entry.note)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                HandoffStatPill(value: item.entry.queueCount, label: "Queued")
                HandoffStatPill(value: item.entry.criticalCount, label: "Critical")
                HandoffStatPill(value: item.entry.checklist.completedCount, label: "Checks")
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HandoffFreshnessCard: View {
    let freshnessLabel: String
    let freshnessSummary: String
    let latestEntry: OnCallHandoffEntry?
    let uncoveredChecklistKeys: [HandoffChecklistKey]

    private var freshnessColor: Color {
        switch freshnessLabel {
        case "Fresh":
            .green
        case "Stale":
            .orange
        default:
            .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Handoff Freshness", systemImage: "clock.badge.checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(freshnessLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(freshnessColor.opacity(0.12))
                    .foregroundStyle(freshnessColor)
                    .clipShape(Capsule())
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
                    .foregroundStyle(.green)
            } else {
                Text("Recent gap: \(uncoveredChecklistKeys.map(\.label).joined(separator: ", "))")
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
                Text(entries.isEmpty ? "No history" : "\(entries.count) snapshots")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(HandoffChecklistKey.allCases.enumerated()), id: \.element.rawValue) { _, key in
                HStack {
                    Label(key.label, systemImage: key.symbolName)
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(coverageCount(key))/\(max(entries.count, 1))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(coverageCount(key) > 0 ? Color.secondary : Color.orange)
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
                            .foregroundStyle(checklist.contains(key) ? .green : .secondary)
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
                    .foregroundStyle(checklist.completedCount == checklist.totalCount ? .green : .secondary)
            }

            if checklist.pendingLabels.isEmpty {
                Text("All handoff checks completed.")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Text("Pending: \(checklist.pendingLabels.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

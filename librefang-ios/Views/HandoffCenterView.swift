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
        let note = handoffStore.draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = ["LibreFang live handoff summary · \(Date().formatted(date: .abbreviated, time: .shortened))"]

        if !note.isEmpty {
            lines.append("Operator note: \(note)")
        }

        lines.append("Queue: \(queueCount) · Critical: \(criticalCount) · Live alerts: \(liveAlertCount)")
        lines.append("")
        lines.append(summary)
        return lines.joined(separator: "\n")
    }
    private var filteredEntries: [OnCallHandoffEntry] {
        handoffStore.entries.filter { entry in
            matches(filter: historyFilter, for: entry) && matchesSearch(entry)
        }
    }

    var body: some View {
        List {
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

                    ShareLink(item: currentShareText) {
                        Label("Share Current Summary", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Compose")
            } footer: {
                Text("Saved locally on this iPhone. Use this before handing the shift to another operator.")
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

                ShareLink(item: entry.shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
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
        }
        .padding(.vertical, 6)
    }
}

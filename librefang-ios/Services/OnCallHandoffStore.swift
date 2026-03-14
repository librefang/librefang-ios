import Foundation

enum HandoffChecklistKey: String, CaseIterable, Codable, Identifiable {
    case criticalsReviewed
    case approvalsTriaged
    case watchlistChecked
    case reminderArmed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .criticalsReviewed:
            "Criticals reviewed"
        case .approvalsTriaged:
            "Approvals triaged"
        case .watchlistChecked:
            "Watchlist checked"
        case .reminderArmed:
            "Standby reminder armed"
        }
    }

    var symbolName: String {
        switch self {
        case .criticalsReviewed:
            "exclamationmark.octagon"
        case .approvalsTriaged:
            "checkmark.shield"
        case .watchlistChecked:
            "star"
        case .reminderArmed:
            "bell.badge"
        }
    }
}

struct HandoffChecklistState: Codable, Equatable {
    private(set) var completedKeys: Set<HandoffChecklistKey> = []

    init(completedKeys: Set<HandoffChecklistKey> = []) {
        self.completedKeys = completedKeys
    }

    func contains(_ key: HandoffChecklistKey) -> Bool {
        completedKeys.contains(key)
    }

    mutating func toggle(_ key: HandoffChecklistKey) {
        if completedKeys.contains(key) {
            completedKeys.remove(key)
        } else {
            completedKeys.insert(key)
        }
    }

    mutating func clear() {
        completedKeys.removeAll()
    }

    var completedCount: Int {
        completedKeys.count
    }

    var totalCount: Int {
        HandoffChecklistKey.allCases.count
    }

    var progressLabel: String {
        "\(completedCount)/\(totalCount)"
    }

    var pendingLabels: [String] {
        HandoffChecklistKey.allCases
            .filter { !completedKeys.contains($0) }
            .map(\.label)
    }

    var completedLabels: [String] {
        HandoffChecklistKey.allCases
            .filter { completedKeys.contains($0) }
            .map(\.label)
    }
}

struct OnCallHandoffEntry: Identifiable, Codable, Equatable {
    let id: String
    let createdAt: Date
    let note: String
    let summary: String
    let queueCount: Int
    let criticalCount: Int
    let liveAlertCount: Int
    let checklist: HandoffChecklistState

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case note
        case summary
        case queueCount
        case criticalCount
        case liveAlertCount
        case checklist
    }

    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        note: String,
        summary: String,
        queueCount: Int,
        criticalCount: Int,
        liveAlertCount: Int,
        checklist: HandoffChecklistState = HandoffChecklistState()
    ) {
        self.id = id
        self.createdAt = createdAt
        self.note = note
        self.summary = summary
        self.queueCount = queueCount
        self.criticalCount = criticalCount
        self.liveAlertCount = liveAlertCount
        self.checklist = checklist
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        note = try container.decode(String.self, forKey: .note)
        summary = try container.decode(String.self, forKey: .summary)
        queueCount = try container.decode(Int.self, forKey: .queueCount)
        criticalCount = try container.decode(Int.self, forKey: .criticalCount)
        liveAlertCount = try container.decode(Int.self, forKey: .liveAlertCount)
        checklist = try container.decodeIfPresent(HandoffChecklistState.self, forKey: .checklist) ?? HandoffChecklistState()
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(note, forKey: .note)
        try container.encode(summary, forKey: .summary)
        try container.encode(queueCount, forKey: .queueCount)
        try container.encode(criticalCount, forKey: .criticalCount)
        try container.encode(liveAlertCount, forKey: .liveAlertCount)
        try container.encode(checklist, forKey: .checklist)
    }

    static func buildShareText(
        timestamp: Date,
        note: String,
        summary: String,
        queueCount: Int,
        criticalCount: Int,
        liveAlertCount: Int,
        checklist: HandoffChecklistState
    ) -> String {
        var lines = ["LibreFang handoff snapshot · \(timestamp.formatted(date: .abbreviated, time: .shortened))"]

        if !note.isEmpty {
            lines.append("Operator note: \(note)")
        }

        lines.append("Queue: \(queueCount) · Critical: \(criticalCount) · Live alerts: \(liveAlertCount)")
        lines.append("Checklist: \(checklist.progressLabel)")

        if !checklist.completedLabels.isEmpty {
            lines.append("Completed: \(checklist.completedLabels.joined(separator: ", "))")
        }

        if !checklist.pendingLabels.isEmpty {
            lines.append("Pending: \(checklist.pendingLabels.joined(separator: ", "))")
        }

        lines.append("")
        lines.append(summary)
        return lines.joined(separator: "\n")
    }

    var shareText: String {
        Self.buildShareText(
            timestamp: createdAt,
            note: note,
            summary: summary,
            queueCount: queueCount,
            criticalCount: criticalCount,
            liveAlertCount: liveAlertCount,
            checklist: checklist
        )
    }
}

@MainActor
@Observable
final class OnCallHandoffStore {
    private enum StorageKey {
        static let entries = "oncall.handoff.entries"
        static let draftNote = "oncall.handoff.draftNote"
        static let draftChecklist = "oncall.handoff.draftChecklist"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let maxEntries = 20

    var draftNote: String {
        didSet {
            defaults.set(draftNote, forKey: StorageKey.draftNote)
        }
    }

    var draftChecklist: HandoffChecklistState {
        didSet {
            persistDraftChecklist()
        }
    }

    private(set) var entries: [OnCallHandoffEntry]

    var latestEntry: OnCallHandoffEntry? {
        entries.first
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.draftNote = defaults.string(forKey: StorageKey.draftNote) ?? ""
        if let data = defaults.data(forKey: StorageKey.draftChecklist),
           let decoded = try? decoder.decode(HandoffChecklistState.self, from: data) {
            self.draftChecklist = decoded
        } else {
            self.draftChecklist = HandoffChecklistState()
        }

        if let data = defaults.data(forKey: StorageKey.entries),
           let decoded = try? decoder.decode([OnCallHandoffEntry].self, from: data) {
            self.entries = decoded
        } else {
            self.entries = []
        }
    }

    func saveSnapshot(
        summary: String,
        queueCount: Int,
        criticalCount: Int,
        liveAlertCount: Int
    ) {
        let entry = OnCallHandoffEntry(
            note: draftNote.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary,
            queueCount: queueCount,
            criticalCount: criticalCount,
            liveAlertCount: liveAlertCount,
            checklist: draftChecklist
        )

        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        persistEntries()
    }

    func removeEntries(at offsets: IndexSet) {
        let ids = offsets.compactMap { entries.indices.contains($0) ? entries[$0].id : nil }
        removeEntries(ids: ids)
    }

    func removeEntries(ids: [String]) {
        guard !ids.isEmpty else { return }
        let removedIDs = Set(ids)
        entries.removeAll { removedIDs.contains($0.id) }
        persistEntries()
    }

    func clearAll() {
        entries.removeAll()
        persistEntries()
    }

    func toggleDraftChecklist(_ key: HandoffChecklistKey) {
        draftChecklist.toggle(key)
    }

    func resetDraft() {
        draftNote = ""
        draftChecklist = HandoffChecklistState()
    }

    private func persistEntries() {
        if let data = try? encoder.encode(entries) {
            defaults.set(data, forKey: StorageKey.entries)
        }
    }

    private func persistDraftChecklist() {
        if let data = try? encoder.encode(draftChecklist) {
            defaults.set(data, forKey: StorageKey.draftChecklist)
        }
    }
}

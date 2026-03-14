import Foundation

struct OnCallHandoffEntry: Identifiable, Codable, Equatable {
    let id: String
    let createdAt: Date
    let note: String
    let summary: String
    let queueCount: Int
    let criticalCount: Int
    let liveAlertCount: Int

    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        note: String,
        summary: String,
        queueCount: Int,
        criticalCount: Int,
        liveAlertCount: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.note = note
        self.summary = summary
        self.queueCount = queueCount
        self.criticalCount = criticalCount
        self.liveAlertCount = liveAlertCount
    }
}

@MainActor
@Observable
final class OnCallHandoffStore {
    private enum StorageKey {
        static let entries = "oncall.handoff.entries"
        static let draftNote = "oncall.handoff.draftNote"
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

    private(set) var entries: [OnCallHandoffEntry]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.draftNote = defaults.string(forKey: StorageKey.draftNote) ?? ""

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
            liveAlertCount: liveAlertCount
        )

        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        persistEntries()
    }

    func removeEntries(at offsets: IndexSet) {
        entries = entries.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
        persistEntries()
    }

    func clearAll() {
        entries.removeAll()
        persistEntries()
    }

    private func persistEntries() {
        if let data = try? encoder.encode(entries) {
            defaults.set(data, forKey: StorageKey.entries)
        }
    }
}

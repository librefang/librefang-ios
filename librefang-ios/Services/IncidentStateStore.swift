import Foundation

@MainActor
@Observable
final class IncidentStateStore {
    private enum StorageKey {
        static let mutedAlertIDs = "incident.mutedAlertIDs"
        static let acknowledgedSignature = "incident.acknowledgedSignature"
        static let acknowledgedAt = "incident.acknowledgedAt"
    }

    private let defaults: UserDefaults

    private(set) var mutedAlertIDs: Set<String>
    private(set) var acknowledgedSnapshotSignature: String?
    private(set) var acknowledgedAt: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.mutedAlertIDs = Set(defaults.stringArray(forKey: StorageKey.mutedAlertIDs) ?? [])
        self.acknowledgedSnapshotSignature = defaults.string(forKey: StorageKey.acknowledgedSignature)

        let timestamp = defaults.double(forKey: StorageKey.acknowledgedAt)
        self.acknowledgedAt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    func visibleAlerts(from alerts: [MonitoringAlertItem]) -> [MonitoringAlertItem] {
        alerts.filter { !mutedAlertIDs.contains($0.id) }
    }

    func activeMutedAlerts(from alerts: [MonitoringAlertItem]) -> [MonitoringAlertItem] {
        alerts.filter { mutedAlertIDs.contains($0.id) }
    }

    func isMuted(_ alert: MonitoringAlertItem) -> Bool {
        mutedAlertIDs.contains(alert.id)
    }

    func toggleMute(for alert: MonitoringAlertItem) {
        if mutedAlertIDs.contains(alert.id) {
            mutedAlertIDs.remove(alert.id)
        } else {
            mutedAlertIDs.insert(alert.id)
        }
        persistMutedAlerts()
    }

    func unmuteAll() {
        mutedAlertIDs.removeAll()
        persistMutedAlerts()
    }

    func acknowledgeCurrentSnapshot(alerts: [MonitoringAlertItem]) {
        let visible = visibleAlerts(from: alerts)
        guard !visible.isEmpty else {
            clearAcknowledgement()
            return
        }

        acknowledgedSnapshotSignature = signature(for: visible)
        acknowledgedAt = Date()
        persistAcknowledgement()
    }

    func clearAcknowledgement() {
        acknowledgedSnapshotSignature = nil
        acknowledgedAt = nil
        defaults.removeObject(forKey: StorageKey.acknowledgedSignature)
        defaults.removeObject(forKey: StorageKey.acknowledgedAt)
    }

    func isCurrentSnapshotAcknowledged(alerts: [MonitoringAlertItem]) -> Bool {
        guard let acknowledgedSnapshotSignature else { return false }
        let visible = visibleAlerts(from: alerts)
        guard !visible.isEmpty else { return false }
        return acknowledgedSnapshotSignature == signature(for: visible)
    }

    func currentAcknowledgementDate(for alerts: [MonitoringAlertItem]) -> Date? {
        guard isCurrentSnapshotAcknowledged(alerts: alerts) else { return nil }
        return acknowledgedAt
    }

    private func signature(for alerts: [MonitoringAlertItem]) -> String {
        alerts
            .map { "\($0.id)|\($0.severity.rawValue)|\($0.title)|\($0.detail)" }
            .sorted()
            .joined(separator: "||")
    }

    private func persistMutedAlerts() {
        defaults.set(Array(mutedAlertIDs).sorted(), forKey: StorageKey.mutedAlertIDs)
    }

    private func persistAcknowledgement() {
        defaults.set(acknowledgedSnapshotSignature, forKey: StorageKey.acknowledgedSignature)
        defaults.set(acknowledgedAt?.timeIntervalSince1970 ?? 0, forKey: StorageKey.acknowledgedAt)
    }
}

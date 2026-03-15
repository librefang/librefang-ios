import Foundation
import UserNotifications

@MainActor
@Observable
final class OnCallNotificationManager {
    private enum StorageKey {
        static let isEnabled = "oncall.notifications.enabled"
        static let remindAfterMinutes = "oncall.notifications.delayMinutes"
        static let scope = "oncall.notifications.scope"
    }

    private static let reminderIdentifier = "oncall.standby.reminder"
    private static let defaultDelayMinutes = 10
    private static let delayValues = [5, 10, 15, 30, 60]
    private static let minimumLeadTime: TimeInterval = 30

    private let defaults: UserDefaults
    private let center: UNUserNotificationCenter

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: StorageKey.isEnabled)
            if !isEnabled {
                Task { await cancelPendingReminder() }
            }
        }
    }

    var remindAfterMinutes: Int {
        didSet {
            if !Self.delayValues.contains(remindAfterMinutes) {
                remindAfterMinutes = Self.defaultDelayMinutes
            }
            defaults.set(remindAfterMinutes, forKey: StorageKey.remindAfterMinutes)
        }
    }

    var scope: OnCallReminderScope {
        didSet {
            defaults.set(scope.rawValue, forKey: StorageKey.scope)
        }
    }

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var pendingReminderDate: Date?
    private(set) var pendingReminderSummary: String?
    private(set) var pendingReminderSource: String?

    init(
        defaults: UserDefaults = .standard,
        center: UNUserNotificationCenter = .current()
    ) {
        self.defaults = defaults
        self.center = center
        self.isEnabled = defaults.object(forKey: StorageKey.isEnabled) as? Bool ?? false

        let storedDelay = defaults.integer(forKey: StorageKey.remindAfterMinutes)
        self.remindAfterMinutes = Self.delayValues.contains(storedDelay) ? storedDelay : Self.defaultDelayMinutes
        self.scope = OnCallReminderScope(rawValue: defaults.string(forKey: StorageKey.scope) ?? "") ?? .criticalOnly
    }

    var authorizationLabel: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            String(localized: "Allowed")
        case .denied:
            String(localized: "Denied")
        case .notDetermined:
            String(localized: "Not Requested")
        @unknown default:
            String(localized: "Unknown")
        }
    }

    var authorizationSummary: String {
        switch authorizationStatus {
        case .authorized:
            String(localized: "iOS banners and sounds are enabled for on-call reminders.")
        case .provisional:
            String(localized: "Notifications can be delivered quietly. Promote them in Settings if you want banners.")
        case .ephemeral:
            String(localized: "Notifications are temporarily allowed for this app session.")
        case .denied:
            String(localized: "Notifications are disabled in iOS Settings for this app.")
        case .notDetermined:
            String(localized: "Request permission once, then the app can arm background reminders.")
        @unknown default:
            String(localized: "Notification authorization state is unavailable.")
        }
    }

    var pendingReminderLabel: String {
        if let pendingReminderDate {
            return RelativeDateTimeFormatter().localizedString(for: pendingReminderDate, relativeTo: Date())
        }
        return String(localized: "Not armed")
    }

    var delayOptions: [Int] {
        Self.delayValues
    }

    var pendingReminderSourceLabel: String {
        pendingReminderDate == nil
            ? String(localized: "Not armed")
            : (pendingReminderSource ?? String(localized: "Standby delay"))
    }

    func refreshAuthorizationStatus() async {
        let settings = await notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorization() async {
        do {
            _ = try await requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            // Keep the manager silent; Settings renders the current authorization state.
        }

        await refreshAuthorizationStatus()
    }

    func armStandbyReminder(snapshot: OnCallReminderSnapshot?) async {
        guard isEnabled else {
            await cancelPendingReminder()
            return
        }

        if authorizationStatus == .notDetermined {
            await refreshAuthorizationStatus()
        }

        guard authorizationStatus == .authorized
            || authorizationStatus == .provisional
            || authorizationStatus == .ephemeral else {
            await cancelPendingReminder()
            return
        }

        guard let snapshot else {
            await cancelPendingReminder()
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: [Self.reminderIdentifier])

        let content = UNMutableNotificationContent()
        content.title = snapshot.title
        content.body = snapshot.body
        content.sound = .default
        content.badge = NSNumber(value: max(snapshot.criticalCount, snapshot.itemCount))
        content.categoryIdentifier = "ONCALL_REMINDER"
        content.threadIdentifier = "oncall-standby"
        content.userInfo = AppShortcutLaunchBridge.userInfo(for: snapshot.destinationTarget)

        let scheduledDate = scheduledReminderDate(for: snapshot)
        let delay = max(Self.minimumLeadTime, scheduledDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.reminderIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await add(request)
            pendingReminderDate = Date().addingTimeInterval(delay)
            pendingReminderSummary = snapshot.title
            pendingReminderSource = scheduledReminderSource(for: snapshot, scheduledDate: pendingReminderDate ?? scheduledDate)
        } catch {
            pendingReminderDate = nil
            pendingReminderSummary = nil
            pendingReminderSource = nil
        }
    }

    func cancelPendingReminder() async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.reminderIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.reminderIdentifier])
        pendingReminderDate = nil
        pendingReminderSummary = nil
        pendingReminderSource = nil
    }

    private func scheduledReminderDate(for snapshot: OnCallReminderSnapshot) -> Date {
        let standbyDate = Date().addingTimeInterval(TimeInterval(remindAfterMinutes * 60))

        guard let suggestedDate = snapshot.suggestedDeliveryDate else {
            return standbyDate
        }

        let earliestPermitted = Date().addingTimeInterval(Self.minimumLeadTime)
        let adjustedSuggestedDate = max(suggestedDate, earliestPermitted)
        return min(standbyDate, adjustedSuggestedDate)
    }

    private func scheduledReminderSource(for snapshot: OnCallReminderSnapshot, scheduledDate: Date) -> String {
        guard let suggestedDate = snapshot.suggestedDeliveryDate,
              let schedulingHint = snapshot.schedulingHint else {
            return String(localized: "Standby delay")
        }

        let earliestPermitted = Date().addingTimeInterval(Self.minimumLeadTime)
        let adjustedSuggestedDate = max(suggestedDate, earliestPermitted)
        if abs(adjustedSuggestedDate.timeIntervalSince(scheduledDate)) < 1 {
            return schedulingHint
        }

        return String(localized: "Standby delay")
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { (continuation: CheckedContinuation<UNNotificationSettings, Never>) in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            center.requestAuthorization(options: options) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

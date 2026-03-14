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
            "Allowed"
        case .denied:
            "Denied"
        case .notDetermined:
            "Not Requested"
        @unknown default:
            "Unknown"
        }
    }

    var authorizationSummary: String {
        switch authorizationStatus {
        case .authorized:
            "iOS banners and sounds are enabled for on-call reminders."
        case .provisional:
            "Notifications can be delivered quietly. Promote them in Settings if you want banners."
        case .ephemeral:
            "Notifications are temporarily allowed for this app session."
        case .denied:
            "Notifications are disabled in iOS Settings for this app."
        case .notDetermined:
            "Request permission once, then the app can arm background reminders."
        @unknown default:
            "Notification authorization state is unavailable."
        }
    }

    var pendingReminderLabel: String {
        if let pendingReminderDate {
            return RelativeDateTimeFormatter().localizedString(for: pendingReminderDate, relativeTo: Date())
        }
        return "Not armed"
    }

    var delayOptions: [Int] {
        Self.delayValues
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

        let delay = TimeInterval(remindAfterMinutes * 60)
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
        } catch {
            pendingReminderDate = nil
            pendingReminderSummary = nil
        }
    }

    func cancelPendingReminder() async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.reminderIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.reminderIdentifier])
        pendingReminderDate = nil
        pendingReminderSummary = nil
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

import Foundation
import UIKit
import UserNotifications

final class NotificationRoutingDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        if let notificationResponse = launchOptions?[.remoteNotification] as? [AnyHashable: Any],
           let surface = AppShortcutLaunchBridge.surface(from: notificationResponse) {
            AppShortcutLaunchBridge.queue(surface)
        }

        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let surface = AppShortcutLaunchBridge.surface(from: response.notification.request.content.userInfo) {
            AppShortcutLaunchBridge.queue(surface)
        }

        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}

import SwiftUI

@main
struct LibreFangApp: App {
    @UIApplicationDelegateAdaptor(NotificationRoutingDelegate.self) private var notificationDelegate
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(\.dependencies, dependencies)
                .onOpenURL { url in
                    guard let surface = AppShortcutLaunchBridge.surface(from: url) else { return }
                    dependencies.appShortcutLaunchStore.queue(surface)
                }
        }
    }
}

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
                    guard let target = AppShortcutLaunchBridge.target(from: url) else { return }
                    switch target {
                    case .surface(let surface):
                        dependencies.appShortcutLaunchStore.queue(surface)
                    case .agent(let id):
                        dependencies.appShortcutLaunchStore.queue(agentID: id)
                    }
                }
        }
    }
}

import SwiftUI

@main
struct LibreFangApp: App {
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(\.dependencies, dependencies)
        }
    }
}

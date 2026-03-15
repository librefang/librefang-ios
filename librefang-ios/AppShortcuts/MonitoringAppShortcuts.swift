import AppIntents

private protocol MonitoringSurfaceIntent: AppIntent {
    static var surface: AppShortcutSurface { get }
}

extension MonitoringSurfaceIntent {
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        AppShortcutLaunchBridge.queue(Self.surface)
        return .result()
    }
}

struct OpenOnCallIntent: MonitoringSurfaceIntent {
    static let surface: AppShortcutSurface = .onCall
    static var title: LocalizedStringResource = "Open On Call"
    static var description = IntentDescription("Open the live on-call queue in LibreFang.")
}

struct OpenIncidentsIntent: MonitoringSurfaceIntent {
    static let surface: AppShortcutSurface = .incidents
    static var title: LocalizedStringResource = "Open Incidents"
    static var description = IntentDescription("Open the incident center in LibreFang.")
}

struct OpenHandoffCenterIntent: MonitoringSurfaceIntent {
    static let surface: AppShortcutSurface = .handoffCenter
    static var title: LocalizedStringResource = "Open Handoff Center"
    static var description = IntentDescription("Open the local handoff center in LibreFang.")
}

struct OpenNightWatchIntent: MonitoringSurfaceIntent {
    static let surface: AppShortcutSurface = .nightWatch
    static var title: LocalizedStringResource = "Open Night Watch"
    static var description = IntentDescription("Open the compact night watch triage view in LibreFang.")
}

struct OpenStandbyDigestIntent: MonitoringSurfaceIntent {
    static let surface: AppShortcutSurface = .standbyDigest
    static var title: LocalizedStringResource = "Open Standby Digest"
    static var description = IntentDescription("Open the standby digest summary in LibreFang.")
}

struct LibreFangAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .teal

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenOnCallIntent(),
            phrases: [
                "Open On Call in \(.applicationName)",
                "Show the on-call queue in \(.applicationName)"
            ],
            shortTitle: "On Call",
            systemImageName: "waveform.path.ecg"
        )
        AppShortcut(
            intent: OpenIncidentsIntent(),
            phrases: [
                "Open Incidents in \(.applicationName)",
                "Show incidents in \(.applicationName)"
            ],
            shortTitle: "Incidents",
            systemImageName: "bell.badge"
        )
        AppShortcut(
            intent: OpenHandoffCenterIntent(),
            phrases: [
                "Open Handoff Center in \(.applicationName)",
                "Show the handoff center in \(.applicationName)"
            ],
            shortTitle: "Handoff",
            systemImageName: "text.badge.plus"
        )
        AppShortcut(
            intent: OpenNightWatchIntent(),
            phrases: [
                "Open Night Watch in \(.applicationName)",
                "Show night watch in \(.applicationName)"
            ],
            shortTitle: "Night Watch",
            systemImageName: "moon.stars"
        )
        AppShortcut(
            intent: OpenStandbyDigestIntent(),
            phrases: [
                "Open Standby Digest in \(.applicationName)",
                "Show the standby digest in \(.applicationName)"
            ],
            shortTitle: "Standby",
            systemImageName: "rectangle.inset.filled"
        )
    }
}

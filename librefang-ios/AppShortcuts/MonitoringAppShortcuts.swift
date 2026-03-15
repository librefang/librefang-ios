import AppIntents

private protocol MonitoringLaunchIntent: AppIntent {
    static var target: AppShortcutLaunchTarget { get }
}

extension MonitoringLaunchIntent {
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        AppShortcutLaunchBridge.queue(Self.target)
        return .result()
    }
}

struct OpenOnCallIntent: MonitoringLaunchIntent {
    static let target: AppShortcutLaunchTarget = .surface(.onCall)
    static var title: LocalizedStringResource = "Open On Call"
    static var description = IntentDescription("Open the live on-call queue in LibreFang.")
}

struct OpenIncidentsIntent: MonitoringLaunchIntent {
    static let target: AppShortcutLaunchTarget = .surface(.incidents)
    static var title: LocalizedStringResource = "Open Incidents"
    static var description = IntentDescription("Open the incident center in LibreFang.")
}

struct OpenHandoffCenterIntent: MonitoringLaunchIntent {
    static let target: AppShortcutLaunchTarget = .surface(.handoffCenter)
    static var title: LocalizedStringResource = "Open Handoff Center"
    static var description = IntentDescription("Open the local handoff center in LibreFang.")
}

struct OpenNightWatchIntent: MonitoringLaunchIntent {
    static let target: AppShortcutLaunchTarget = .surface(.nightWatch)
    static var title: LocalizedStringResource = "Open Night Watch"
    static var description = IntentDescription("Open the compact night watch triage view in LibreFang.")
}

struct OpenStandbyDigestIntent: MonitoringLaunchIntent {
    static let target: AppShortcutLaunchTarget = .surface(.standbyDigest)
    static var title: LocalizedStringResource = "Open Standby Digest"
    static var description = IntentDescription("Open the standby digest summary in LibreFang.")
}

struct OpenSessionMonitorIntent: MonitoringLaunchIntent {
    static let target: AppShortcutLaunchTarget = .sessionsAttention
    static var title: LocalizedStringResource = "Open Session Monitor"
    static var description = IntentDescription("Open the attention-filtered session monitor in LibreFang.")
}

struct OpenCriticalEventsIntent: MonitoringLaunchIntent {
    static let target: AppShortcutLaunchTarget = .eventsCritical
    static var title: LocalizedStringResource = "Open Critical Events"
    static var description = IntentDescription("Open the critical audit event feed in LibreFang.")
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
        AppShortcut(
            intent: OpenSessionMonitorIntent(),
            phrases: [
                "Open Session Monitor in \(.applicationName)",
                "Show session pressure in \(.applicationName)"
            ],
            shortTitle: "Sessions",
            systemImageName: "rectangle.stack"
        )
        AppShortcut(
            intent: OpenCriticalEventsIntent(),
            phrases: [
                "Open Critical Events in \(.applicationName)",
                "Show critical events in \(.applicationName)"
            ],
            shortTitle: "Events",
            systemImageName: "list.bullet.rectangle"
        )
    }
}

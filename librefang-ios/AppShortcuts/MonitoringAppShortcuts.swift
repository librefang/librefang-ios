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

struct OpenAgentsIntent: MonitoringLaunchIntent {
    static let target: AppShortcutLaunchTarget = .surface(.agents)
    static var title: LocalizedStringResource = "Open Agents"
    static var description = IntentDescription("Open the agent fleet monitor in LibreFang.")
}

struct OpenRuntimeIntent: MonitoringLaunchIntent {
    static let target: AppShortcutLaunchTarget = .surface(.runtime)
    static var title: LocalizedStringResource = "Open Runtime"
    static var description = IntentDescription("Open the live runtime operator deck in LibreFang.")
}

struct OpenBudgetIntent: MonitoringLaunchIntent {
    static let target: AppShortcutLaunchTarget = .surface(.budget)
    static var title: LocalizedStringResource = "Open Budget"
    static var description = IntentDescription("Open the budget, spend, and model usage monitor in LibreFang.")
}

struct OpenSettingsIntent: MonitoringLaunchIntent {
    static let target: AppShortcutLaunchTarget = .surface(.settings)
    static var title: LocalizedStringResource = "Open Settings"
    static var description = IntentDescription("Open the monitoring settings and device controls in LibreFang.")
}

struct OpenIncidentsIntent: MonitoringLaunchIntent {
    static let target: AppShortcutLaunchTarget = .surface(.incidents)
    static var title: LocalizedStringResource = "Open Incidents"
    static var description = IntentDescription("Open the incident center in LibreFang.")
}

struct OpenApprovalsIntent: MonitoringLaunchIntent {
    static let target: AppShortcutLaunchTarget = .surface(.approvals)
    static var title: LocalizedStringResource = "Open Approvals"
    static var description = IntentDescription("Open the live approval queue in LibreFang.")
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

struct OpenAutomationIntent: MonitoringLaunchIntent {
    static let target: AppShortcutLaunchTarget = .surface(.automation)
    static var title: LocalizedStringResource = "Open Automation"
    static var description = IntentDescription("Open the workflow, trigger, schedule, and cron monitor in LibreFang.")
}

struct OpenDiagnosticsIntent: MonitoringLaunchIntent {
    static let target: AppShortcutLaunchTarget = .surface(.diagnostics)
    static var title: LocalizedStringResource = "Open Diagnostics"
    static var description = IntentDescription("Open the deep runtime diagnostics view in LibreFang.")
}

struct OpenIntegrationsIntent: MonitoringLaunchIntent {
    static let target: AppShortcutLaunchTarget = .surface(.integrations)
    static var title: LocalizedStringResource = "Open Integrations"
    static var description = IntentDescription("Open provider, channel, model, and alias diagnostics in LibreFang.")
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
            intent: OpenAgentsIntent(),
            phrases: [
                "Open Agents in \(.applicationName)",
                "Show the agent fleet in \(.applicationName)"
            ],
            shortTitle: "Agents",
            systemImageName: "person.3.sequence"
        )
        AppShortcut(
            intent: OpenRuntimeIntent(),
            phrases: [
                "Open Runtime in \(.applicationName)",
                "Show runtime in \(.applicationName)"
            ],
            shortTitle: "Runtime",
            systemImageName: "bolt.shield"
        )
        AppShortcut(
            intent: OpenBudgetIntent(),
            phrases: [
                "Open Budget in \(.applicationName)",
                "Show budget in \(.applicationName)"
            ],
            shortTitle: "Budget",
            systemImageName: "chart.line.uptrend.xyaxis"
        )
        AppShortcut(
            intent: OpenSettingsIntent(),
            phrases: [
                "Open Settings in \(.applicationName)",
                "Show monitoring settings in \(.applicationName)"
            ],
            shortTitle: "Settings",
            systemImageName: "gearshape"
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
            intent: OpenApprovalsIntent(),
            phrases: [
                "Open Approvals in \(.applicationName)",
                "Show approvals in \(.applicationName)"
            ],
            shortTitle: "Approvals",
            systemImageName: "checkmark.shield"
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
                "Show standby digest in \(.applicationName)"
            ],
            shortTitle: "Standby",
            systemImageName: "rectangle.compress.vertical"
        )
    }
}

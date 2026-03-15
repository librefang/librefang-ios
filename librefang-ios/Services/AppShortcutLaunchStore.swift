import Foundation

enum AppShortcutSurface: String, CaseIterable, Identifiable {
    case onCall = "on-call"
    case incidents
    case handoffCenter = "handoff-center"
    case nightWatch = "night-watch"
    case standbyDigest = "standby-digest"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onCall:
            "On Call"
        case .incidents:
            "Incidents"
        case .handoffCenter:
            "Handoff Center"
        case .nightWatch:
            "Night Watch"
        case .standbyDigest:
            "Standby Digest"
        }
    }

    var deepLinkURL: URL {
        URL(string: "\(AppShortcutLaunchBridge.urlScheme)://surface/\(rawValue)")!
    }

    init?(routeValue: String) {
        let normalized = routeValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "on-call", "oncall":
            self = .onCall
        case "incidents", "incident":
            self = .incidents
        case "handoff-center", "handoff", "handoffcenter":
            self = .handoffCenter
        case "night-watch", "nightwatch":
            self = .nightWatch
        case "standby-digest", "standby", "digest":
            self = .standbyDigest
        default:
            return nil
        }
    }
}

enum AppShortcutLaunchTarget: Equatable {
    case surface(AppShortcutSurface)
    case agent(String)

    var deepLinkURL: URL {
        switch self {
        case .surface(let surface):
            return surface.deepLinkURL
        case .agent(let id):
            return URL(string: "\(AppShortcutLaunchBridge.urlScheme)://agent/\(id)")!
        }
    }
}

enum AppShortcutLaunchBridge {
    private enum StorageKey {
        static let pendingTargetKind = "appshortcuts.pendingTargetKind"
        static let pendingTargetValue = "appshortcuts.pendingTargetValue"
        static let pendingToken = "appshortcuts.pendingToken"
    }

    static let urlScheme = "librefang"
    static let notificationSurfaceKey = "monitoringSurface"
    static let notificationTargetKindKey = "monitoringTargetKind"
    static let notificationTargetValueKey = "monitoringTargetValue"

    static func queue(_ surface: AppShortcutSurface, defaults: UserDefaults = .standard) {
        queue(.surface(surface), defaults: defaults)
    }

    static func queue(agentID: String, defaults: UserDefaults = .standard) {
        queue(.agent(agentID), defaults: defaults)
    }

    static func queue(_ target: AppShortcutLaunchTarget, defaults: UserDefaults = .standard) {
        switch target {
        case .surface(let surface):
            defaults.set("surface", forKey: StorageKey.pendingTargetKind)
            defaults.set(surface.rawValue, forKey: StorageKey.pendingTargetValue)
        case .agent(let id):
            defaults.set("agent", forKey: StorageKey.pendingTargetKind)
            defaults.set(id, forKey: StorageKey.pendingTargetValue)
        }
        defaults.set(UUID().uuidString, forKey: StorageKey.pendingToken)
    }

    static func userInfo(for surface: AppShortcutSurface) -> [AnyHashable: Any] {
        userInfo(for: .surface(surface))
    }

    static func userInfo(for target: AppShortcutLaunchTarget) -> [AnyHashable: Any] {
        switch target {
        case .surface(let surface):
            return [
                notificationTargetKindKey: "surface",
                notificationTargetValueKey: surface.rawValue,
                notificationSurfaceKey: surface.rawValue,
            ]
        case .agent(let id):
            return [
                notificationTargetKindKey: "agent",
                notificationTargetValueKey: id,
            ]
        }
    }

    static func surface(from userInfo: [AnyHashable: Any]) -> AppShortcutSurface? {
        guard let rawValue = userInfo[notificationSurfaceKey] as? String else { return nil }
        return AppShortcutSurface(rawValue: rawValue)
    }

    static func target(from userInfo: [AnyHashable: Any]) -> AppShortcutLaunchTarget? {
        if let kind = userInfo[notificationTargetKindKey] as? String,
           let value = userInfo[notificationTargetValueKey] as? String {
            switch kind {
            case "surface":
                guard let surface = AppShortcutSurface(rawValue: value) else { return nil }
                return .surface(surface)
            case "agent":
                return .agent(value)
            default:
                break
            }
        }

        if let surface = surface(from: userInfo) {
            return .surface(surface)
        }

        return nil
    }

    static func surface(from url: URL) -> AppShortcutSurface? {
        if case .surface(let surface) = target(from: url) {
            return surface
        }
        return nil
    }

    static func target(from url: URL) -> AppShortcutLaunchTarget? {
        guard url.scheme?.lowercased() == urlScheme else { return nil }

        let host = url.host?.lowercased()
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if host == "agent" || host == "agents" {
            guard let id = pathComponents.first, !id.isEmpty else { return nil }
            return .agent(id)
        }

        if host == "surface", let candidate = pathComponents.first {
            guard let surface = AppShortcutSurface(routeValue: candidate) else { return nil }
            return .surface(surface)
        }

        if let host, let surface = AppShortcutSurface(routeValue: host) {
            return .surface(surface)
        }

        if let candidate = pathComponents.first,
           let surface = AppShortcutSurface(routeValue: candidate) {
            return .surface(surface)
        }

        return nil
    }

    static func pendingSurface(defaults: UserDefaults = .standard) -> AppShortcutSurface? {
        if case .surface(let surface) = pendingTarget(defaults: defaults) {
            return surface
        }
        return nil
    }

    static func pendingTarget(defaults: UserDefaults = .standard) -> AppShortcutLaunchTarget? {
        guard let kind = defaults.string(forKey: StorageKey.pendingTargetKind),
              let value = defaults.string(forKey: StorageKey.pendingTargetValue) else {
            return nil
        }

        switch kind {
        case "surface":
            guard let surface = AppShortcutSurface(rawValue: value) else { return nil }
            return .surface(surface)
        case "agent":
            return .agent(value)
        default:
            return nil
        }
    }

    static func pendingToken(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: StorageKey.pendingToken)
    }

    @discardableResult
    static func consume(defaults: UserDefaults = .standard) -> AppShortcutLaunchTarget? {
        let target = pendingTarget(defaults: defaults)
        defaults.removeObject(forKey: StorageKey.pendingTargetKind)
        defaults.removeObject(forKey: StorageKey.pendingTargetValue)
        defaults.removeObject(forKey: StorageKey.pendingToken)
        return target
    }
}

@MainActor
@Observable
final class AppShortcutLaunchStore {
    private let defaults: UserDefaults

    private(set) var pendingTarget: AppShortcutLaunchTarget?
    private(set) var pendingToken: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refreshFromDefaults()
    }

    func refreshFromDefaults() {
        pendingTarget = AppShortcutLaunchBridge.pendingTarget(defaults: defaults)
        pendingToken = AppShortcutLaunchBridge.pendingToken(defaults: defaults)
    }

    func queue(_ surface: AppShortcutSurface) {
        AppShortcutLaunchBridge.queue(surface, defaults: defaults)
        refreshFromDefaults()
    }

    func queue(agentID: String) {
        AppShortcutLaunchBridge.queue(agentID: agentID, defaults: defaults)
        refreshFromDefaults()
    }

    @discardableResult
    func consumePendingTarget() -> AppShortcutLaunchTarget? {
        let target = AppShortcutLaunchBridge.consume(defaults: defaults)
        refreshFromDefaults()
        return target
    }
}

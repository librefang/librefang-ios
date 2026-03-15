import Foundation

enum AppShortcutSurface: String, CaseIterable, Identifiable {
    case onCall = "on-call"
    case incidents
    case approvals
    case handoffCenter = "handoff-center"
    case nightWatch = "night-watch"
    case standbyDigest = "standby-digest"
    case automation
    case diagnostics
    case integrations

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onCall:
            "On Call"
        case .incidents:
            "Incidents"
        case .approvals:
            "Approvals"
        case .handoffCenter:
            "Handoff Center"
        case .nightWatch:
            "Night Watch"
        case .standbyDigest:
            "Standby Digest"
        case .automation:
            "Automation"
        case .diagnostics:
            "Diagnostics"
        case .integrations:
            "Integrations"
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
        case "approvals", "approval":
            self = .approvals
        case "handoff-center", "handoff", "handoffcenter":
            self = .handoffCenter
        case "night-watch", "nightwatch":
            self = .nightWatch
        case "standby-digest", "standby", "digest":
            self = .standbyDigest
        case "automation", "scheduler", "workflows":
            self = .automation
        case "diagnostics", "diagnostic", "health":
            self = .diagnostics
        case "integrations", "integration", "providers", "models", "catalog":
            self = .integrations
        default:
            return nil
        }
    }
}

enum AppShortcutLaunchTarget: Hashable, Identifiable {
    case surface(AppShortcutSurface)
    case agent(String)
    case sessionsAttention
    case sessionsSearch(String)
    case eventsCritical
    case eventsSearch(String)

    var id: String {
        switch self {
        case .surface(let surface):
            return "surface:\(surface.rawValue)"
        case .agent(let id):
            return "agent:\(id)"
        case .sessionsAttention:
            return "sessions:attention"
        case .sessionsSearch(let query):
            return "sessions:search:\(query)"
        case .eventsCritical:
            return "events:critical"
        case .eventsSearch(let query):
            return "events:search:\(query)"
        }
    }

    var label: String {
        switch self {
        case .surface(let surface):
            return surface.label
        case .agent:
            return "Agent Detail"
        case .sessionsAttention:
            return "Session Monitor"
        case .sessionsSearch:
            return "Filtered Sessions"
        case .eventsCritical:
            return "Critical Events"
        case .eventsSearch:
            return "Filtered Events"
        }
    }

    var deepLinkURL: URL {
        switch self {
        case .surface(let surface):
            return surface.deepLinkURL
        case .agent(let id):
            var components = URLComponents()
            components.scheme = AppShortcutLaunchBridge.urlScheme
            components.host = "agent"
            components.path = "/\(id)"
            return components.url!
        case .sessionsAttention:
            var components = URLComponents()
            components.scheme = AppShortcutLaunchBridge.urlScheme
            components.host = "sessions"
            components.path = "/attention"
            return components.url!
        case .sessionsSearch(let query):
            var components = URLComponents()
            components.scheme = AppShortcutLaunchBridge.urlScheme
            components.host = "sessions"
            components.path = "/search"
            components.queryItems = [URLQueryItem(name: "query", value: query)]
            return components.url!
        case .eventsCritical:
            var components = URLComponents()
            components.scheme = AppShortcutLaunchBridge.urlScheme
            components.host = "events"
            components.path = "/critical"
            return components.url!
        case .eventsSearch(let query):
            var components = URLComponents()
            components.scheme = AppShortcutLaunchBridge.urlScheme
            components.host = "events"
            components.path = "/search"
            components.queryItems = [URLQueryItem(name: "query", value: query)]
            return components.url!
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
        let kind: String
        let value: String

        switch target {
        case .surface(let surface):
            kind = "surface"
            value = surface.rawValue
        case .agent(let id):
            kind = "agent"
            value = id
        case .sessionsAttention:
            kind = "sessions-attention"
            value = ""
        case .sessionsSearch(let query):
            kind = "sessions-search"
            value = query
        case .eventsCritical:
            kind = "events-critical"
            value = ""
        case .eventsSearch(let query):
            kind = "events-search"
            value = query
        }
        defaults.set(kind, forKey: StorageKey.pendingTargetKind)
        defaults.set(value, forKey: StorageKey.pendingTargetValue)
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
        case .sessionsAttention:
            return [
                notificationTargetKindKey: "sessions-attention",
                notificationTargetValueKey: "",
            ]
        case .sessionsSearch(let query):
            return [
                notificationTargetKindKey: "sessions-search",
                notificationTargetValueKey: query,
            ]
        case .eventsCritical:
            return [
                notificationTargetKindKey: "events-critical",
                notificationTargetValueKey: "",
            ]
        case .eventsSearch(let query):
            return [
                notificationTargetKindKey: "events-search",
                notificationTargetValueKey: query,
            ]
        }
    }

    static func surface(from userInfo: [AnyHashable: Any]) -> AppShortcutSurface? {
        guard let rawValue = userInfo[notificationSurfaceKey] as? String else { return nil }
        return AppShortcutSurface(rawValue: rawValue)
    }

    static func target(from userInfo: [AnyHashable: Any]) -> AppShortcutLaunchTarget? {
        if let kind = userInfo[notificationTargetKindKey] as? String {
            let value = userInfo[notificationTargetValueKey] as? String ?? ""
            switch kind {
            case "surface":
                guard let surface = AppShortcutSurface(rawValue: value) else { return nil }
                return .surface(surface)
            case "agent":
                return .agent(value)
            case "sessions-attention":
                return .sessionsAttention
            case "sessions-search":
                guard !value.isEmpty else { return nil }
                return .sessionsSearch(value)
            case "events-critical":
                return .eventsCritical
            case "events-search":
                guard !value.isEmpty else { return nil }
                return .eventsSearch(value)
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

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = url.host?.lowercased()
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if host == "agent" || host == "agents" {
            guard let id = pathComponents.first, !id.isEmpty else { return nil }
            return .agent(id)
        }

        if host == "sessions" {
            if pathComponents.first?.lowercased() == "attention" {
                return .sessionsAttention
            }

            if pathComponents.first?.lowercased() == "search" {
                if let query = components?.queryItems?.first(where: { $0.name == "query" })?.value,
                   !query.isEmpty {
                    return .sessionsSearch(query)
                }

                if pathComponents.count > 1 {
                    let query = pathComponents[1].removingPercentEncoding ?? pathComponents[1]
                    guard !query.isEmpty else { return nil }
                    return .sessionsSearch(query)
                }
            }

            if let query = components?.queryItems?.first(where: { $0.name == "query" })?.value,
               !query.isEmpty {
                return .sessionsSearch(query)
            }

            if components?.queryItems?.first(where: { $0.name == "filter" })?.value?.lowercased() == "attention" {
                return .sessionsAttention
            }
        }

        if host == "events" {
            let firstComponent = pathComponents.first?.lowercased()
            if firstComponent == "critical" {
                return .eventsCritical
            }

            if firstComponent == "search" {
                if let query = components?.queryItems?.first(where: { $0.name == "query" })?.value,
                   !query.isEmpty {
                    return .eventsSearch(query)
                }

                if pathComponents.count > 1 {
                    let query = pathComponents[1].removingPercentEncoding ?? pathComponents[1]
                    guard !query.isEmpty else { return nil }
                    return .eventsSearch(query)
                }
            }

            if components?.queryItems?.first(where: { $0.name == "scope" })?.value?.lowercased() == "critical" {
                if let query = components?.queryItems?.first(where: { $0.name == "query" })?.value,
                   !query.isEmpty {
                    return .eventsSearch(query)
                }
                return .eventsCritical
            }
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
        guard let kind = defaults.string(forKey: StorageKey.pendingTargetKind) else {
            return nil
        }
        let value = defaults.string(forKey: StorageKey.pendingTargetValue) ?? ""

        switch kind {
        case "surface":
            guard let surface = AppShortcutSurface(rawValue: value) else { return nil }
            return .surface(surface)
        case "agent":
            return .agent(value)
        case "sessions-attention":
            return .sessionsAttention
        case "sessions-search":
            guard !value.isEmpty else { return nil }
            return .sessionsSearch(value)
        case "events-critical":
            return .eventsCritical
        case "events-search":
            guard !value.isEmpty else { return nil }
            return .eventsSearch(value)
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

    func queue(_ target: AppShortcutLaunchTarget) {
        AppShortcutLaunchBridge.queue(target, defaults: defaults)
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

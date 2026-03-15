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

enum AppShortcutLaunchBridge {
    private enum StorageKey {
        static let pendingSurface = "appshortcuts.pendingSurface"
        static let pendingToken = "appshortcuts.pendingToken"
    }

    static let urlScheme = "librefang"
    static let notificationSurfaceKey = "monitoringSurface"

    static func queue(_ surface: AppShortcutSurface, defaults: UserDefaults = .standard) {
        defaults.set(surface.rawValue, forKey: StorageKey.pendingSurface)
        defaults.set(UUID().uuidString, forKey: StorageKey.pendingToken)
    }

    static func userInfo(for surface: AppShortcutSurface) -> [AnyHashable: Any] {
        [notificationSurfaceKey: surface.rawValue]
    }

    static func surface(from userInfo: [AnyHashable: Any]) -> AppShortcutSurface? {
        guard let rawValue = userInfo[notificationSurfaceKey] as? String else { return nil }
        return AppShortcutSurface(rawValue: rawValue)
    }

    static func surface(from url: URL) -> AppShortcutSurface? {
        guard url.scheme?.lowercased() == urlScheme else { return nil }

        if let host = url.host, host != "surface", let surface = AppShortcutSurface(routeValue: host) {
            return surface
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        if let candidate = pathComponents.first,
           let surface = AppShortcutSurface(routeValue: candidate) {
            return surface
        }

        if url.host == "surface", pathComponents.count >= 2 {
            return AppShortcutSurface(routeValue: pathComponents[1])
        }

        return nil
    }

    static func pendingSurface(defaults: UserDefaults = .standard) -> AppShortcutSurface? {
        guard let rawValue = defaults.string(forKey: StorageKey.pendingSurface) else { return nil }
        return AppShortcutSurface(rawValue: rawValue)
    }

    static func pendingToken(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: StorageKey.pendingToken)
    }

    @discardableResult
    static func consume(defaults: UserDefaults = .standard) -> AppShortcutSurface? {
        let surface = pendingSurface(defaults: defaults)
        defaults.removeObject(forKey: StorageKey.pendingSurface)
        defaults.removeObject(forKey: StorageKey.pendingToken)
        return surface
    }
}

@MainActor
@Observable
final class AppShortcutLaunchStore {
    private let defaults: UserDefaults

    private(set) var pendingSurface: AppShortcutSurface?
    private(set) var pendingToken: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refreshFromDefaults()
    }

    func refreshFromDefaults() {
        pendingSurface = AppShortcutLaunchBridge.pendingSurface(defaults: defaults)
        pendingToken = AppShortcutLaunchBridge.pendingToken(defaults: defaults)
    }

    func queue(_ surface: AppShortcutSurface) {
        AppShortcutLaunchBridge.queue(surface, defaults: defaults)
        refreshFromDefaults()
    }

    @discardableResult
    func consumePendingSurface() -> AppShortcutSurface? {
        let surface = AppShortcutLaunchBridge.consume(defaults: defaults)
        refreshFromDefaults()
        return surface
    }
}

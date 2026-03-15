import Foundation

enum AppShortcutSurface: String, CaseIterable, Identifiable {
    case onCall = "on-call"
    case incidents
    case handoffCenter = "handoff-center"
    case nightWatch = "night-watch"
    case standbyDigest = "standby-digest"

    var id: String { rawValue }
}

enum AppShortcutLaunchBridge {
    private enum StorageKey {
        static let pendingSurface = "appshortcuts.pendingSurface"
        static let pendingToken = "appshortcuts.pendingToken"
    }

    static func queue(_ surface: AppShortcutSurface, defaults: UserDefaults = .standard) {
        defaults.set(surface.rawValue, forKey: StorageKey.pendingSurface)
        defaults.set(UUID().uuidString, forKey: StorageKey.pendingToken)
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

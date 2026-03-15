import Foundation

enum OnCallFocusMode: String, CaseIterable, Identifiable {
    case balanced
    case criticalOnly
    case watchlistFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .balanced:
            String(localized: "Balanced")
        case .criticalOnly:
            String(localized: "Critical Only")
        case .watchlistFirst:
            String(localized: "Watchlist First")
        }
    }

    var summary: String {
        switch self {
        case .balanced:
            String(localized: "Mix live alerts, approvals, watchlist pressure, and session hotspots.")
        case .criticalOnly:
            String(localized: "Only surface critical incidents unless you open deeper queues.")
        case .watchlistFirst:
            String(localized: "Pin watched agents to the front so their issues never get buried.")
        }
    }
}

enum OnCallSurfacePreference: String, CaseIterable, Identifiable {
    case onCall
    case nightWatch
    case standbyDigest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onCall:
            String(localized: "On Call")
        case .nightWatch:
            String(localized: "Night Watch")
        case .standbyDigest:
            String(localized: "Standby Digest")
        }
    }

    var summary: String {
        switch self {
        case .onCall:
            String(localized: "Open the full triage queue with supporting sections.")
        case .nightWatch:
            String(localized: "Jump straight into the minimal high-priority watch surface.")
        case .standbyDigest:
            String(localized: "Open the lockscreen-style glance view with the smallest possible incident summary.")
        }
    }
}

@MainActor
@Observable
final class OnCallFocusStore {
    private enum StorageKey {
        static let focusMode = "oncall.focus.mode"
        static let preferredSurface = "oncall.focus.surface"
        static let showMutedSummary = "oncall.focus.showMutedSummary"
        static let showForegroundCues = "oncall.focus.showForegroundCues"
    }

    private let defaults: UserDefaults

    var mode: OnCallFocusMode {
        didSet {
            defaults.set(mode.rawValue, forKey: StorageKey.focusMode)
        }
    }

    var preferredSurface: OnCallSurfacePreference {
        didSet {
            defaults.set(preferredSurface.rawValue, forKey: StorageKey.preferredSurface)
        }
    }

    var showsMutedSummary: Bool {
        didSet {
            defaults.set(showsMutedSummary, forKey: StorageKey.showMutedSummary)
        }
    }

    var showsForegroundCues: Bool {
        didSet {
            defaults.set(showsForegroundCues, forKey: StorageKey.showForegroundCues)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.mode = OnCallFocusMode(rawValue: defaults.string(forKey: StorageKey.focusMode) ?? "") ?? .balanced
        self.preferredSurface = OnCallSurfacePreference(rawValue: defaults.string(forKey: StorageKey.preferredSurface) ?? "") ?? .onCall

        if defaults.object(forKey: StorageKey.showMutedSummary) == nil {
            self.showsMutedSummary = true
        } else {
            self.showsMutedSummary = defaults.bool(forKey: StorageKey.showMutedSummary)
        }

        if defaults.object(forKey: StorageKey.showForegroundCues) == nil {
            self.showsForegroundCues = true
        } else {
            self.showsForegroundCues = defaults.bool(forKey: StorageKey.showForegroundCues)
        }
    }
}

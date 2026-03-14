import Foundation

enum OnCallFocusMode: String, CaseIterable, Identifiable {
    case balanced
    case criticalOnly
    case watchlistFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .balanced:
            "Balanced"
        case .criticalOnly:
            "Critical Only"
        case .watchlistFirst:
            "Watchlist First"
        }
    }

    var summary: String {
        switch self {
        case .balanced:
            "Mix live alerts, approvals, watchlist pressure, and session hotspots."
        case .criticalOnly:
            "Only surface critical incidents unless you open deeper queues."
        case .watchlistFirst:
            "Pin watched agents to the front so their issues never get buried."
        }
    }
}

enum OnCallSurfacePreference: String, CaseIterable, Identifiable {
    case onCall
    case nightWatch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onCall:
            "On Call"
        case .nightWatch:
            "Night Watch"
        }
    }

    var summary: String {
        switch self {
        case .onCall:
            "Open the full triage queue with supporting sections."
        case .nightWatch:
            "Jump straight into the minimal high-priority watch surface."
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

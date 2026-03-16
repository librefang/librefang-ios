import Foundation

nonisolated enum PresentationTone: Sendable {
    case positive
    case warning
    case caution
    case critical
    case neutral
}

nonisolated enum AlertSnapshotState: Sendable {
    case muted
    case clear
    case acknowledged
    case live(Int)

    init(liveAlertCount: Int, mutedAlertCount: Int, isAcknowledged: Bool) {
        if liveAlertCount == 0 {
            self = mutedAlertCount > 0 ? .muted : .clear
        } else if isAcknowledged {
            self = .acknowledged
        } else {
            self = .live(liveAlertCount)
        }
    }

    var tone: PresentationTone {
        switch self {
        case .muted:
            return .neutral
        case .clear:
            return .positive
        case .acknowledged:
            return .warning
        case .live:
            return .critical
        }
    }

    var overviewLabel: String {
        switch self {
        case .muted:
            return String(localized: "Muted")
        case .clear:
            return String(localized: "Clear")
        case .acknowledged:
            return String(localized: "Acked")
        case .live(let count):
            return count == 1
                ? String(localized: "1 live")
                : String(localized: "\(count) live")
        }
    }

    var operatorLabel: String {
        switch self {
        case .muted:
            return String(localized: "Muted")
        case .clear:
            return String(localized: "Clear")
        case .acknowledged:
            return String(localized: "Acked")
        case .live:
            return String(localized: "Needs review")
        }
    }

    var settingsLabel: String {
        switch self {
        case .muted:
            return String(localized: "Muted")
        case .clear:
            return String(localized: "Clear")
        case .acknowledged:
            return String(localized: "Acknowledged")
        case .live:
            return String(localized: "Needs review")
        }
    }

    var onCallLabel: String {
        switch self {
        case .muted:
            return String(localized: "Watching")
        case .clear:
            return String(localized: "Calm")
        case .acknowledged:
            return String(localized: "Acked")
        case .live:
            return String(localized: "Live")
        }
    }
}

nonisolated enum BudgetUtilizationStatus: Sendable {
    case normal
    case warning
    case critical

    var tone: PresentationTone {
        switch self {
        case .normal:
            return .positive
        case .warning:
            return .warning
        case .critical:
            return .critical
        }
    }
}

nonisolated enum DeliverySummaryStatus: Sendable {
    case noRecentSends
    case healthy
    case unsettled(Int)
    case failed(Int)

    var label: String {
        switch self {
        case .failed(let count):
            return count == 1
                ? String(localized: "1 failed")
                : String(localized: "\(count) failed")
        case .unsettled(let count):
            return count == 1
                ? String(localized: "1 unsettled")
                : String(localized: "\(count) unsettled")
        case .healthy:
            return String(localized: "No recent failures")
        case .noRecentSends:
            return String(localized: "No recent sends")
        }
    }

    var tone: PresentationTone {
        switch self {
        case .failed:
            return .critical
        case .unsettled:
            return .warning
        case .healthy:
            return .positive
        case .noRecentSends:
            return .neutral
        }
    }

    static func summarize(failedCount: Int, unsettledCount: Int, totalCount: Int) -> DeliverySummaryStatus {
        if failedCount > 0 {
            return .failed(failedCount)
        }
        if unsettledCount > 0 {
            return .unsettled(unsettledCount)
        }
        if totalCount > 0 {
            return .healthy
        }
        return .noRecentSends
    }
}

nonisolated struct WorkspaceIdentitySummary: Sendable {
    let existingCount: Int
    let totalCount: Int

    var missingCount: Int {
        max(totalCount - existingCount, 0)
    }

    var tone: PresentationTone {
        missingCount == 0 ? .positive : .warning
    }

    var statusLabel: String {
        missingCount == 0
            ? String(localized: "Identity files present")
            : String(localized: "\(missingCount) missing")
    }

    var progressLabel: String {
        "\(existingCount)/\(totalCount)"
    }

    static func summarize(existingCount: Int, totalCount: Int) -> WorkspaceIdentitySummary {
        WorkspaceIdentitySummary(existingCount: existingCount, totalCount: totalCount)
    }
}

nonisolated enum ProviderAlignmentStatus: Sendable {
    case match
    case drift

    init(isAligned: Bool) {
        self = isAligned ? .match : .drift
    }

    var label: String {
        switch self {
        case .match:
            return String(localized: "Match")
        case .drift:
            return String(localized: "Drift")
        }
    }

    var tone: PresentationTone {
        switch self {
        case .match:
            return .positive
        case .drift:
            return .warning
        }
    }
}

nonisolated enum ChatConnectionState: Sendable {
    case live
    case fallback

    init(isRealtimeConnected: Bool) {
        self = isRealtimeConnected ? .live : .fallback
    }

    var label: String {
        switch self {
        case .live:
            return String(localized: "Live")
        case .fallback:
            return String(localized: "Fallback")
        }
    }

    var symbolName: String {
        switch self {
        case .live:
            return "dot.radiowaves.left.and.right"
        case .fallback:
            return "arrow.clockwise"
        }
    }

    var tone: PresentationTone {
        switch self {
        case .live:
            return .positive
        case .fallback:
            return .warning
        }
    }
}

nonisolated enum StatusPresentation {
    static func budgetUtilizationStatus(for ratio: Double?) -> BudgetUtilizationStatus? {
        guard let ratio else { return nil }
        if ratio > 0.9 {
            return .critical
        }
        if ratio > 0.7 {
            return .warning
        }
        return .normal
    }

    static func localizedHealthLabel(for value: String) -> String {
        switch normalize(value) {
        case "ok", "healthy", "ready", "connected", "valid":
            return String(localized: "Healthy")
        case "warn", "warning", "degraded":
            return String(localized: "Degraded")
        case "error", "broken", "offline", "disconnected", "unhealthy", "invalid":
            return String(localized: "Broken")
        default:
            return localizedFallbackLabel(for: value)
        }
    }

    static func healthTone(for value: String) -> PresentationTone {
        switch normalize(value) {
        case "ok", "healthy", "ready", "connected", "valid":
            return .positive
        case "warn", "warning", "degraded":
            return .warning
        case "error", "broken", "offline", "disconnected", "unhealthy", "invalid":
            return .critical
        default:
            return .neutral
        }
    }

    static func localizedConnectionLabel(for value: String) -> String {
        switch normalize(value) {
        case "ok", "healthy", "ready", "connected":
            return String(localized: "Connected")
        case "connecting":
            return String(localized: "Connecting")
        case "warn", "warning", "degraded":
            return String(localized: "Degraded")
        case "error", "broken", "offline", "disconnected", "unhealthy":
            return String(localized: "Disconnected")
        default:
            return localizedFallbackLabel(for: value)
        }
    }

    static func localizedFallbackLabel(for value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return String(localized: "Unknown") }
        return trimmed
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

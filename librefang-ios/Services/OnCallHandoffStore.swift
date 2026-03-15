import Foundation

enum HandoffSnapshotKind: String, CaseIterable, Codable, Identifiable {
    case routine
    case watch
    case incident
    case recovery

    var id: String { rawValue }

    var label: String {
        switch self {
        case .routine:
            "Routine"
        case .watch:
            "Watch"
        case .incident:
            "Incident"
        case .recovery:
            "Recovery"
        }
    }

    var symbolName: String {
        switch self {
        case .routine:
            "clock.badge.checkmark"
        case .watch:
            "star.circle"
        case .incident:
            "exclamationmark.triangle"
        case .recovery:
            "checkmark.arrow.trianglehead.counterclockwise"
        }
    }

    var summary: String {
        switch self {
        case .routine:
            "Normal shift coverage with no unusual incident pressure."
        case .watch:
            "Use when the next operator should focus on pinned agents, approvals, or session hotspots."
        case .incident:
            "Use when active critical incidents or escalations are driving the queue."
        case .recovery:
            "Use when pressure is easing and the next operator mainly needs verification and follow-through."
        }
    }

    func suggestedNote(queueCount: Int, criticalCount: Int, liveAlertCount: Int) -> String {
        switch self {
        case .routine:
            return "Routine shift snapshot. Queue \(queueCount), live alerts \(liveAlertCount). Continue normal monitoring."
        case .watch:
            return "Watchlist-focused handoff. Prioritize pinned agents, pending approvals, and any stale sessions."
        case .incident:
            return "Incident handoff. \(criticalCount) critical and \(liveAlertCount) live alerts remain in play. Stay on the priority queue until conditions settle."
        case .recovery:
            return "Recovery handoff. Pressure is easing, but confirm approvals, session hotspots, and recent audit activity stay stable."
        }
    }
}

enum HandoffFocusArea: String, CaseIterable, Codable, Identifiable {
    case alerts
    case approvals
    case watchlist
    case sessions
    case audit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .alerts:
            "Alerts"
        case .approvals:
            "Approvals"
        case .watchlist:
            "Watchlist"
        case .sessions:
            "Sessions"
        case .audit:
            "Audit"
        }
    }

    var symbolName: String {
        switch self {
        case .alerts:
            "bell.badge"
        case .approvals:
            "checkmark.shield"
        case .watchlist:
            "star"
        case .sessions:
            "rectangle.stack"
        case .audit:
            "list.bullet.rectangle.portrait"
        }
    }
}

enum HandoffCadenceState {
    case missing
    case single
    case steady
    case sparse

    var label: String {
        switch self {
        case .missing:
            "Missing"
        case .single:
            "Single"
        case .steady:
            "Steady"
        case .sparse:
            "Sparse"
        }
    }
}

enum HandoffDriftState {
    case steady
    case improving
    case worsening
    case mixed

    var label: String {
        switch self {
        case .steady:
            "Steady"
        case .improving:
            "Improving"
        case .worsening:
            "Worsening"
        case .mixed:
            "Mixed"
        }
    }
}

enum HandoffCarryoverState {
    case cleared
    case partial
    case active

    var label: String {
        switch self {
        case .cleared:
            "Cleared"
        case .partial:
            "Partial"
        case .active:
            "Active"
        }
    }
}

enum HandoffReadinessState {
    case ready
    case caution
    case blocked

    var label: String {
        switch self {
        case .ready:
            "Ready"
        case .caution:
            "Caution"
        case .blocked:
            "Blocked"
        }
    }
}

enum HandoffCheckInWindow: String, CaseIterable, Codable, Identifiable {
    case none
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case fourHours
    case nextShift

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:
            "None"
        case .fifteenMinutes:
            "15 min"
        case .thirtyMinutes:
            "30 min"
        case .oneHour:
            "1 hour"
        case .twoHours:
            "2 hours"
        case .fourHours:
            "4 hours"
        case .nextShift:
            "Next shift"
        }
    }

    var summary: String {
        switch self {
        case .none:
            "No explicit re-check window is attached to this handoff."
        case .fifteenMinutes:
            "Use when the next operator should re-check almost immediately."
        case .thirtyMinutes:
            "Use for short follow-through after the handoff lands."
        case .oneHour:
            "Good default when incident pressure is active but stable."
        case .twoHours:
            "Use when the next shift needs a defined medium-term checkpoint."
        case .fourHours:
            "Use for slower recovery work that still needs a same-shift check."
        case .nextShift:
            "Use when the next meaningful re-check is expected at the next shift boundary."
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .none:
            nil
        case .fifteenMinutes:
            15 * 60
        case .thirtyMinutes:
            30 * 60
        case .oneHour:
            60 * 60
        case .twoHours:
            2 * 60 * 60
        case .fourHours:
            4 * 60 * 60
        case .nextShift:
            8 * 60 * 60
        }
    }

    func dueDate(from start: Date) -> Date? {
        guard let interval else { return nil }
        return start.addingTimeInterval(interval)
    }

    func dueLabel(from start: Date) -> String {
        guard let dueDate = dueDate(from: start) else { return "No check-in window" }
        return "\(label) · \(dueDate.formatted(date: .omitted, time: .shortened))"
    }
}

enum HandoffCheckInState {
    case scheduled
    case dueSoon
    case overdue

    var label: String {
        switch self {
        case .scheduled:
            "Scheduled"
        case .dueSoon:
            "Due Soon"
        case .overdue:
            "Overdue"
        }
    }
}

struct HandoffCheckInStatus {
    let baseline: OnCallHandoffEntry
    let window: HandoffCheckInWindow
    let dueDate: Date
    let remaining: TimeInterval
    let state: HandoffCheckInState

    var summary: String {
        switch state {
        case .scheduled:
            return "Next check-in is \(RelativeDateTimeFormatter().localizedString(for: dueDate, relativeTo: Date()))."
        case .dueSoon:
            return "Check-in is due soon at \(dueDate.formatted(date: .omitted, time: .shortened))."
        case .overdue:
            return "Check-in passed \(RelativeDateTimeFormatter().localizedString(for: dueDate, relativeTo: Date()))."
        }
    }

    var dueLabel: String {
        "\(window.label) · \(dueDate.formatted(date: .omitted, time: .shortened))"
    }
}

struct HandoffFollowUpStatus: Identifiable {
    let baseline: OnCallHandoffEntry
    let index: Int
    let item: String
    let isCompleted: Bool

    var id: String {
        OnCallHandoffStore.followUpCompletionKey(
            entryID: baseline.id,
            index: index,
            item: item
        )
    }
}

struct HandoffTimelineItem: Identifiable {
    let entry: OnCallHandoffEntry
    let gapToOlderEntry: TimeInterval?
    let gapWarningThreshold: TimeInterval

    var id: String { entry.id }

    var gapLabel: String {
        guard let gapToOlderEntry else { return "Latest in window" }
        return OnCallHandoffStore.formatInterval(gapToOlderEntry)
    }

    var isGapWarning: Bool {
        guard let gapToOlderEntry else { return false }
        return gapToOlderEntry >= gapWarningThreshold
    }
}

struct HandoffReadinessIssue: Identifiable {
    let id: String
    let message: String
    let isBlocking: Bool
}

struct HandoffReadinessStatus {
    let state: HandoffReadinessState
    let issues: [HandoffReadinessIssue]

    var blockingIssues: [HandoffReadinessIssue] {
        issues.filter(\.isBlocking)
    }

    var advisoryIssues: [HandoffReadinessIssue] {
        issues.filter { !$0.isBlocking }
    }

    var summary: String {
        switch state {
        case .ready:
            return "Checklist is complete and active monitoring pressure is reflected in the handoff draft."
        case .caution:
            return "The handoff draft is usable, but some operator context is still thin."
        case .blocked:
            return "The handoff draft is missing required context for current runtime pressure."
        }
    }
}

struct HandoffCarryoverItem: Identifiable {
    let area: HandoffFocusArea
    let isActive: Bool
    let detail: String

    var id: String { area.rawValue }
}

struct HandoffCarryoverStatus {
    let baseline: OnCallHandoffEntry
    let items: [HandoffCarryoverItem]
    let state: HandoffCarryoverState

    var unresolvedCount: Int {
        items.filter(\.isActive).count
    }

    var summary: String {
        switch state {
        case .cleared:
            return "All focus areas from the last handoff have settled."
        case .partial:
            return "\(unresolvedCount) of \(items.count) handoff focus areas are still active."
        case .active:
            return "All \(items.count) handoff focus areas are still active on this shift."
        }
    }
}

struct HandoffSnapshotDrift {
    let baseline: OnCallHandoffEntry
    let queueChange: Int
    let criticalChange: Int
    let liveAlertChange: Int
    let state: HandoffDriftState

    var compactSummary: String {
        [
            "Queue \(Self.formatChange(queueChange))",
            "Critical \(Self.formatChange(criticalChange))",
            "Live \(Self.formatChange(liveAlertChange))"
        ].joined(separator: " · ")
    }

    var summary: String {
        "Since the last handoff: \(compactSummary)."
    }

    private static func formatChange(_ value: Int) -> String {
        value == 0 ? "0" : value > 0 ? "+\(value)" : "\(value)"
    }
}

enum HandoffChecklistKey: String, CaseIterable, Codable, Identifiable {
    case criticalsReviewed
    case approvalsTriaged
    case watchlistChecked
    case reminderArmed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .criticalsReviewed:
            "Criticals reviewed"
        case .approvalsTriaged:
            "Approvals triaged"
        case .watchlistChecked:
            "Watchlist checked"
        case .reminderArmed:
            "Standby reminder armed"
        }
    }

    var symbolName: String {
        switch self {
        case .criticalsReviewed:
            "exclamationmark.octagon"
        case .approvalsTriaged:
            "checkmark.shield"
        case .watchlistChecked:
            "star"
        case .reminderArmed:
            "bell.badge"
        }
    }
}

struct HandoffChecklistState: Codable, Equatable {
    private(set) var completedKeys: Set<HandoffChecklistKey> = []

    init(completedKeys: Set<HandoffChecklistKey> = []) {
        self.completedKeys = completedKeys
    }

    func contains(_ key: HandoffChecklistKey) -> Bool {
        completedKeys.contains(key)
    }

    mutating func toggle(_ key: HandoffChecklistKey) {
        if completedKeys.contains(key) {
            completedKeys.remove(key)
        } else {
            completedKeys.insert(key)
        }
    }

    mutating func clear() {
        completedKeys.removeAll()
    }

    var completedCount: Int {
        completedKeys.count
    }

    var totalCount: Int {
        HandoffChecklistKey.allCases.count
    }

    var progressLabel: String {
        "\(completedCount)/\(totalCount)"
    }

    var pendingLabels: [String] {
        HandoffChecklistKey.allCases
            .filter { !completedKeys.contains($0) }
            .map(\.label)
    }

    var completedLabels: [String] {
        HandoffChecklistKey.allCases
            .filter { completedKeys.contains($0) }
            .map(\.label)
    }
}

struct HandoffFocusState: Codable, Equatable {
    private(set) var selectedAreas: Set<HandoffFocusArea> = []

    init(selectedAreas: Set<HandoffFocusArea> = []) {
        self.selectedAreas = selectedAreas
    }

    func contains(_ area: HandoffFocusArea) -> Bool {
        selectedAreas.contains(area)
    }

    mutating func toggle(_ area: HandoffFocusArea) {
        if selectedAreas.contains(area) {
            selectedAreas.remove(area)
        } else {
            selectedAreas.insert(area)
        }
    }

    mutating func set(_ areas: Set<HandoffFocusArea>) {
        selectedAreas = areas
    }

    mutating func clear() {
        selectedAreas.removeAll()
    }

    var items: [HandoffFocusArea] {
        HandoffFocusArea.allCases.filter { selectedAreas.contains($0) }
    }

    var labels: [String] {
        items.map(\.label)
    }

    var summaryLabel: String {
        labels.isEmpty ? "None" : labels.joined(separator: ", ")
    }
}

struct OnCallHandoffEntry: Identifiable, Codable, Equatable {
    let id: String
    let createdAt: Date
    let kind: HandoffSnapshotKind
    let note: String
    let summary: String
    let queueCount: Int
    let criticalCount: Int
    let liveAlertCount: Int
    let checklist: HandoffChecklistState
    let focusAreas: HandoffFocusState
    let followUpItems: [String]
    let checkInWindow: HandoffCheckInWindow

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case kind
        case note
        case summary
        case queueCount
        case criticalCount
        case liveAlertCount
        case checklist
        case focusAreas
        case followUpItems
        case checkInWindow
    }

    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        kind: HandoffSnapshotKind = .routine,
        note: String,
        summary: String,
        queueCount: Int,
        criticalCount: Int,
        liveAlertCount: Int,
        checklist: HandoffChecklistState = HandoffChecklistState(),
        focusAreas: HandoffFocusState = HandoffFocusState(),
        followUpItems: [String] = [],
        checkInWindow: HandoffCheckInWindow = .none
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.note = note
        self.summary = summary
        self.queueCount = queueCount
        self.criticalCount = criticalCount
        self.liveAlertCount = liveAlertCount
        self.checklist = checklist
        self.focusAreas = focusAreas
        self.followUpItems = followUpItems
        self.checkInWindow = checkInWindow
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        kind = try container.decodeIfPresent(HandoffSnapshotKind.self, forKey: .kind) ?? .routine
        note = try container.decode(String.self, forKey: .note)
        summary = try container.decode(String.self, forKey: .summary)
        queueCount = try container.decode(Int.self, forKey: .queueCount)
        criticalCount = try container.decode(Int.self, forKey: .criticalCount)
        liveAlertCount = try container.decode(Int.self, forKey: .liveAlertCount)
        checklist = try container.decodeIfPresent(HandoffChecklistState.self, forKey: .checklist) ?? HandoffChecklistState()
        focusAreas = try container.decodeIfPresent(HandoffFocusState.self, forKey: .focusAreas) ?? HandoffFocusState()
        followUpItems = try container.decodeIfPresent([String].self, forKey: .followUpItems) ?? []
        checkInWindow = try container.decodeIfPresent(HandoffCheckInWindow.self, forKey: .checkInWindow) ?? .none
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(kind, forKey: .kind)
        try container.encode(note, forKey: .note)
        try container.encode(summary, forKey: .summary)
        try container.encode(queueCount, forKey: .queueCount)
        try container.encode(criticalCount, forKey: .criticalCount)
        try container.encode(liveAlertCount, forKey: .liveAlertCount)
        try container.encode(checklist, forKey: .checklist)
        try container.encode(focusAreas, forKey: .focusAreas)
        try container.encode(followUpItems, forKey: .followUpItems)
        try container.encode(checkInWindow, forKey: .checkInWindow)
    }

    static func buildShareText(
        timestamp: Date,
        kind: HandoffSnapshotKind,
        note: String,
        summary: String,
        queueCount: Int,
        criticalCount: Int,
        liveAlertCount: Int,
        checklist: HandoffChecklistState,
        focusAreas: HandoffFocusState,
        followUpItems: [String],
        checkInWindow: HandoffCheckInWindow
    ) -> String {
        var lines = ["LibreFang handoff snapshot · \(timestamp.formatted(date: .abbreviated, time: .shortened))"]

        if !note.isEmpty {
            lines.append("Operator note: \(note)")
        }

        lines.append("Type: \(kind.label)")
        lines.append("Queue: \(queueCount) · Critical: \(criticalCount) · Live alerts: \(liveAlertCount)")
        lines.append("Checklist: \(checklist.progressLabel)")
        if !focusAreas.labels.isEmpty {
            lines.append("Focus: \(focusAreas.labels.joined(separator: ", "))")
        }

        if !checklist.completedLabels.isEmpty {
            lines.append("Completed: \(checklist.completedLabels.joined(separator: ", "))")
        }

        if !checklist.pendingLabels.isEmpty {
            lines.append("Pending: \(checklist.pendingLabels.joined(separator: ", "))")
        }

        if !followUpItems.isEmpty {
            lines.append("Follow-ups:")
            lines.append(contentsOf: followUpItems.map { "- \($0)" })
        }

        if checkInWindow != .none {
            lines.append("Check-in: \(checkInWindow.dueLabel(from: timestamp))")
        }

        lines.append("")
        lines.append(summary)
        return lines.joined(separator: "\n")
    }

    var shareText: String {
        Self.buildShareText(
            timestamp: createdAt,
            kind: kind,
            note: note,
            summary: summary,
            queueCount: queueCount,
            criticalCount: criticalCount,
            liveAlertCount: liveAlertCount,
            checklist: checklist,
            focusAreas: focusAreas,
            followUpItems: followUpItems,
            checkInWindow: checkInWindow
        )
    }
}

@MainActor
@Observable
final class OnCallHandoffStore {
    private enum StorageKey {
        static let entries = "oncall.handoff.entries"
        static let draftNote = "oncall.handoff.draftNote"
        static let draftChecklist = "oncall.handoff.draftChecklist"
        static let draftKind = "oncall.handoff.draftKind"
        static let draftFocusAreas = "oncall.handoff.draftFocusAreas"
        static let draftFollowUpItems = "oncall.handoff.draftFollowUpItems"
        static let draftCheckInWindow = "oncall.handoff.draftCheckInWindow"
        static let completedFollowUps = "oncall.handoff.completedFollowUps"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let maxEntries = 20
    private let staleThreshold: TimeInterval = 8 * 60 * 60
    private let cadenceWarningThreshold: TimeInterval = 12 * 60 * 60
    private let checkInSoonThreshold: TimeInterval = 30 * 60

    var draftNote: String {
        didSet {
            defaults.set(draftNote, forKey: StorageKey.draftNote)
        }
    }

    var draftChecklist: HandoffChecklistState {
        didSet {
            persistDraftChecklist()
        }
    }

    var draftKind: HandoffSnapshotKind {
        didSet {
            defaults.set(draftKind.rawValue, forKey: StorageKey.draftKind)
        }
    }

    var draftFocusAreas: HandoffFocusState {
        didSet {
            persistDraftFocusAreas()
        }
    }

    var draftFollowUpItems: [String] {
        didSet {
            persistDraftFollowUpItems()
        }
    }

    var draftCheckInWindow: HandoffCheckInWindow {
        didSet {
            defaults.set(draftCheckInWindow.rawValue, forKey: StorageKey.draftCheckInWindow)
        }
    }

    private var completedFollowUpKeys: Set<String> {
        didSet {
            persistCompletedFollowUpKeys()
        }
    }

    private(set) var entries: [OnCallHandoffEntry]

    var latestEntry: OnCallHandoffEntry? {
        entries.first
    }

    var latestEntryAge: TimeInterval? {
        guard let createdAt = latestEntry?.createdAt else { return nil }
        return Date().timeIntervalSince(createdAt)
    }

    var isLatestEntryStale: Bool {
        guard let latestEntryAge else { return false }
        return latestEntryAge >= staleThreshold
    }

    var freshnessLabel: String {
        guard latestEntry != nil else { return "Missing" }
        return isLatestEntryStale ? "Stale" : "Fresh"
    }

    var freshnessSummary: String {
        guard let latestEntry else {
            return "No local handoff snapshot saved on this iPhone yet."
        }

        let relative = RelativeDateTimeFormatter().localizedString(for: latestEntry.createdAt, relativeTo: Date())
        if isLatestEntryStale {
            return "Last handoff was \(relative). Review the queue before the next shift change."
        }
        return "Last handoff was \(relative). This iPhone has recent local shift context."
    }

    var recentEntries: [OnCallHandoffEntry] {
        Array(entries.prefix(5))
    }

    var timelineItems: [HandoffTimelineItem] {
        recentEntries.enumerated().map { index, entry in
            let olderEntry = recentEntries.indices.contains(index + 1) ? recentEntries[index + 1] : nil
            let gapToOlderEntry = olderEntry.map { entry.createdAt.timeIntervalSince($0.createdAt) }

            return HandoffTimelineItem(
                entry: entry,
                gapToOlderEntry: gapToOlderEntry,
                gapWarningThreshold: cadenceWarningThreshold
            )
        }
    }

    var latestGap: TimeInterval? {
        timelineItems.first?.gapToOlderEntry
    }

    var averageGap: TimeInterval? {
        let gaps = timelineItems.compactMap(\.gapToOlderEntry)
        guard !gaps.isEmpty else { return nil }
        return gaps.reduce(0, +) / Double(gaps.count)
    }

    var cadenceState: HandoffCadenceState {
        guard !entries.isEmpty else { return .missing }
        guard let latestGap else { return .single }
        return latestGap >= cadenceWarningThreshold ? .sparse : .steady
    }

    var cadenceSummary: String {
        switch cadenceState {
        case .missing:
            return "No recent local handoff history on this iPhone."
        case .single:
            return "Only one recent handoff is saved. Cadence needs more history."
        case .steady:
            let latestGapLabel = latestGap.map(Self.formatInterval) ?? "--"
            let averageGapLabel = averageGap.map(Self.formatInterval) ?? "--"
            return "Latest gap \(latestGapLabel). Average recent cadence \(averageGapLabel)."
        case .sparse:
            let latestGapLabel = latestGap.map(Self.formatInterval) ?? "--"
            return "Latest handoff gap stretched to \(latestGapLabel). Review shift coverage."
        }
    }

    var cadenceWarningCount: Int {
        timelineItems.filter(\.isGapWarning).count
    }

    var latestCheckInStatus: HandoffCheckInStatus? {
        guard let latestEntry,
              latestEntry.checkInWindow != .none,
              let dueDate = latestEntry.checkInWindow.dueDate(from: latestEntry.createdAt)
        else {
            return nil
        }

        let remaining = dueDate.timeIntervalSinceNow
        let state: HandoffCheckInState
        if remaining <= 0 {
            state = .overdue
        } else if remaining <= checkInSoonThreshold {
            state = .dueSoon
        } else {
            state = .scheduled
        }

        return HandoffCheckInStatus(
            baseline: latestEntry,
            window: latestEntry.checkInWindow,
            dueDate: dueDate,
            remaining: remaining,
            state: state
        )
    }

    var latestFollowUpStatuses: [HandoffFollowUpStatus] {
        guard let latestEntry else { return [] }
        return followUpStatuses(for: latestEntry)
    }

    var pendingLatestFollowUpCount: Int {
        latestFollowUpStatuses.filter { !$0.isCompleted }.count
    }

    var completedLatestFollowUpCount: Int {
        latestFollowUpStatuses.filter(\.isCompleted).count
    }

    func driftFromLatest(
        queueCount: Int,
        criticalCount: Int,
        liveAlertCount: Int
    ) -> HandoffSnapshotDrift? {
        guard let latestEntry else { return nil }

        let queueChange = queueCount - latestEntry.queueCount
        let criticalChange = criticalCount - latestEntry.criticalCount
        let liveAlertChange = liveAlertCount - latestEntry.liveAlertCount

        let hasPositive = [queueChange, criticalChange, liveAlertChange].contains { $0 > 0 }
        let hasNegative = [queueChange, criticalChange, liveAlertChange].contains { $0 < 0 }

        let state: HandoffDriftState
        if !hasPositive && !hasNegative {
            state = .steady
        } else if hasPositive && hasNegative {
            state = .mixed
        } else if criticalChange > 0 || liveAlertChange > 0 || queueChange > 0 {
            state = .worsening
        } else {
            state = .improving
        }

        return HandoffSnapshotDrift(
            baseline: latestEntry,
            queueChange: queueChange,
            criticalChange: criticalChange,
            liveAlertChange: liveAlertChange,
            state: state
        )
    }

    func carryoverFromLatest(
        liveAlertCount: Int,
        pendingApprovalCount: Int,
        watchlistIssueCount: Int,
        sessionAttentionCount: Int,
        criticalAuditCount: Int
    ) -> HandoffCarryoverStatus? {
        guard let latestEntry, !latestEntry.focusAreas.items.isEmpty else { return nil }

        let items = latestEntry.focusAreas.items.map { area in
            switch area {
            case .alerts:
                let isActive = liveAlertCount > 0
                return HandoffCarryoverItem(
                    area: area,
                    isActive: isActive,
                    detail: isActive ? "\(liveAlertCount) live alerts are still active." : "Live alerts are cleared."
                )
            case .approvals:
                let isActive = pendingApprovalCount > 0
                return HandoffCarryoverItem(
                    area: area,
                    isActive: isActive,
                    detail: isActive ? "\(pendingApprovalCount) approvals still need review." : "Pending approvals are cleared."
                )
            case .watchlist:
                let isActive = watchlistIssueCount > 0
                return HandoffCarryoverItem(
                    area: area,
                    isActive: isActive,
                    detail: isActive ? "\(watchlistIssueCount) watched agents still need attention." : "Watchlist attention is clear."
                )
            case .sessions:
                let isActive = sessionAttentionCount > 0
                return HandoffCarryoverItem(
                    area: area,
                    isActive: isActive,
                    detail: isActive ? "\(sessionAttentionCount) session hotspots are still present." : "Session pressure is clear."
                )
            case .audit:
                let isActive = criticalAuditCount > 0
                return HandoffCarryoverItem(
                    area: area,
                    isActive: isActive,
                    detail: isActive ? "\(criticalAuditCount) critical audit events are still recent." : "Critical audit carryover is clear."
                )
            }
        }

        let unresolvedCount = items.filter(\.isActive).count
        let state: HandoffCarryoverState
        if unresolvedCount == 0 {
            state = .cleared
        } else if unresolvedCount == items.count {
            state = .active
        } else {
            state = .partial
        }

        return HandoffCarryoverStatus(
            baseline: latestEntry,
            items: items,
            state: state
        )
    }

    func evaluateDraftReadiness(
        note: String,
        checklist: HandoffChecklistState,
        focusAreas: HandoffFocusState,
        followUpItems: [String],
        checkInWindow: HandoffCheckInWindow,
        liveAlertCount: Int,
        pendingApprovalCount: Int,
        watchlistIssueCount: Int,
        sessionAttentionCount: Int,
        criticalAuditCount: Int,
        carryover: HandoffCarryoverStatus?
    ) -> HandoffReadinessStatus {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        var issues: [HandoffReadinessIssue] = []

        if !checklist.pendingLabels.isEmpty {
            issues.append(
                HandoffReadinessIssue(
                    id: "checklist",
                    message: "Checklist incomplete: \(checklist.pendingLabels.joined(separator: ", ")).",
                    isBlocking: true
                )
            )
        }

        if trimmedNote.isEmpty {
            issues.append(
                HandoffReadinessIssue(
                    id: "note",
                    message: "Add a short operator note so the next shift has direct context.",
                    isBlocking: false
                )
            )
        }

        let hasRuntimePressure = liveAlertCount > 0
            || pendingApprovalCount > 0
            || watchlistIssueCount > 0
            || sessionAttentionCount > 0
            || criticalAuditCount > 0
            || (carryover?.unresolvedCount ?? 0) > 0

        if hasRuntimePressure && followUpItems.isEmpty {
            issues.append(
                HandoffReadinessIssue(
                    id: "followups",
                    message: "Active runtime pressure exists, but no follow-up items are captured for the next shift.",
                    isBlocking: true
                )
            )
        }

        if hasRuntimePressure && checkInWindow == .none {
            issues.append(
                HandoffReadinessIssue(
                    id: "checkin",
                    message: "Active runtime pressure exists, but no check-in window is set for the next shift.",
                    isBlocking: true
                )
            )
        } else if !followUpItems.isEmpty && checkInWindow == .none {
            issues.append(
                HandoffReadinessIssue(
                    id: "checkin-advisory",
                    message: "Follow-up items exist, but there is no explicit next check-in window.",
                    isBlocking: false
                )
            )
        }

        if liveAlertCount > 0 && !focusAreas.contains(.alerts) {
            issues.append(
                HandoffReadinessIssue(
                    id: "alerts",
                    message: "\(liveAlertCount) live alerts are active, but Alerts is not included in handoff focus.",
                    isBlocking: true
                )
            )
        }

        if pendingApprovalCount > 0 && !focusAreas.contains(.approvals) {
            issues.append(
                HandoffReadinessIssue(
                    id: "approvals",
                    message: "\(pendingApprovalCount) pending approvals are not captured in handoff focus.",
                    isBlocking: true
                )
            )
        }

        if watchlistIssueCount > 0 && !focusAreas.contains(.watchlist) {
            issues.append(
                HandoffReadinessIssue(
                    id: "watchlist",
                    message: "\(watchlistIssueCount) watched agents still need attention, but Watchlist is not included.",
                    isBlocking: true
                )
            )
        }

        if sessionAttentionCount > 0 && !focusAreas.contains(.sessions) {
            issues.append(
                HandoffReadinessIssue(
                    id: "sessions",
                    message: "\(sessionAttentionCount) session hotspots are active, but Sessions is not included.",
                    isBlocking: true
                )
            )
        }

        if criticalAuditCount > 0 && !focusAreas.contains(.audit) {
            issues.append(
                HandoffReadinessIssue(
                    id: "audit",
                    message: "\(criticalAuditCount) critical audit events are still recent, but Audit is not included.",
                    isBlocking: true
                )
            )
        }

        if let carryover {
            let missingCarryover = carryover.items
                .filter { $0.isActive && !focusAreas.contains($0.area) }
                .map(\.area.label)

            if !missingCarryover.isEmpty {
                issues.append(
                    HandoffReadinessIssue(
                        id: "carryover",
                        message: "Unresolved carryover is missing from focus: \(missingCarryover.joined(separator: ", ")).",
                        isBlocking: true
                    )
                )
            }
        }

        let state: HandoffReadinessState
        if issues.contains(where: \.isBlocking) {
            state = .blocked
        } else if issues.isEmpty {
            state = .ready
        } else {
            state = .caution
        }

        return HandoffReadinessStatus(
            state: state,
            issues: issues
        )
    }

    func recentCoverageCount(for key: HandoffChecklistKey) -> Int {
        recentEntries.filter { $0.checklist.contains(key) }.count
    }

    var uncoveredChecklistKeys: [HandoffChecklistKey] {
        HandoffChecklistKey.allCases.filter { recentCoverageCount(for: $0) == 0 }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.draftNote = defaults.string(forKey: StorageKey.draftNote) ?? ""
        self.draftKind = HandoffSnapshotKind(rawValue: defaults.string(forKey: StorageKey.draftKind) ?? "") ?? .routine
        if let data = defaults.data(forKey: StorageKey.draftChecklist),
           let decoded = try? decoder.decode(HandoffChecklistState.self, from: data) {
            self.draftChecklist = decoded
        } else {
            self.draftChecklist = HandoffChecklistState()
        }
        if let data = defaults.data(forKey: StorageKey.draftFocusAreas),
           let decoded = try? decoder.decode(HandoffFocusState.self, from: data) {
            self.draftFocusAreas = decoded
        } else {
            self.draftFocusAreas = HandoffFocusState()
        }
        if let data = defaults.data(forKey: StorageKey.draftFollowUpItems),
           let decoded = try? decoder.decode([String].self, from: data) {
            self.draftFollowUpItems = decoded
        } else {
            self.draftFollowUpItems = []
        }
        self.draftCheckInWindow = HandoffCheckInWindow(rawValue: defaults.string(forKey: StorageKey.draftCheckInWindow) ?? "") ?? .none
        if let data = defaults.data(forKey: StorageKey.completedFollowUps),
           let decoded = try? decoder.decode(Set<String>.self, from: data) {
            self.completedFollowUpKeys = decoded
        } else if let array = defaults.array(forKey: StorageKey.completedFollowUps) as? [String] {
            self.completedFollowUpKeys = Set(array)
        } else {
            self.completedFollowUpKeys = []
        }

        if let data = defaults.data(forKey: StorageKey.entries),
           let decoded = try? decoder.decode([OnCallHandoffEntry].self, from: data) {
            self.entries = decoded
        } else {
            self.entries = []
        }

        cleanupCompletedFollowUpKeys()
    }

    func saveSnapshot(
        summary: String,
        queueCount: Int,
        criticalCount: Int,
        liveAlertCount: Int
    ) {
        let entry = OnCallHandoffEntry(
            kind: draftKind,
            note: draftNote.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary,
            queueCount: queueCount,
            criticalCount: criticalCount,
            liveAlertCount: liveAlertCount,
            checklist: draftChecklist,
            focusAreas: draftFocusAreas,
            followUpItems: draftFollowUpItems,
            checkInWindow: draftCheckInWindow
        )

        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        persistEntries()
    }

    func removeEntries(at offsets: IndexSet) {
        let ids = offsets.compactMap { entries.indices.contains($0) ? entries[$0].id : nil }
        removeEntries(ids: ids)
    }

    func removeEntries(ids: [String]) {
        guard !ids.isEmpty else { return }
        let removedIDs = Set(ids)
        entries.removeAll { removedIDs.contains($0.id) }
        persistEntries()
    }

    func clearAll() {
        entries.removeAll()
        persistEntries()
    }

    func followUpStatuses(for entry: OnCallHandoffEntry) -> [HandoffFollowUpStatus] {
        entry.followUpItems.enumerated().map { index, item in
            let key = Self.followUpCompletionKey(entryID: entry.id, index: index, item: item)
            return HandoffFollowUpStatus(
                baseline: entry,
                index: index,
                item: item,
                isCompleted: completedFollowUpKeys.contains(key)
            )
        }
    }

    func toggleFollowUpCompletion(_ status: HandoffFollowUpStatus) {
        setFollowUpCompletion(!status.isCompleted, for: status)
    }

    func setFollowUpCompletion(_ isCompleted: Bool, for status: HandoffFollowUpStatus) {
        let key = status.id
        if isCompleted {
            completedFollowUpKeys.insert(key)
        } else {
            completedFollowUpKeys.remove(key)
        }
    }

    func toggleDraftChecklist(_ key: HandoffChecklistKey) {
        draftChecklist.toggle(key)
    }

    func toggleDraftFocusArea(_ area: HandoffFocusArea) {
        draftFocusAreas.toggle(area)
    }

    func setDraftFocusAreas(_ areas: Set<HandoffFocusArea>) {
        draftFocusAreas.set(areas)
    }

    func addDraftFollowUp(_ item: String) {
        let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !draftFollowUpItems.contains(trimmed) else { return }
        draftFollowUpItems.append(trimmed)
    }

    func appendDraftFollowUps(_ items: [String]) {
        for item in items {
            addDraftFollowUp(item)
        }
    }

    func removeDraftFollowUps(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) where draftFollowUpItems.indices.contains(offset) {
            draftFollowUpItems.remove(at: offset)
        }
    }

    func useSuggestedDraftNote(
        queueCount: Int,
        criticalCount: Int,
        liveAlertCount: Int
    ) {
        draftNote = draftKind.suggestedNote(
            queueCount: queueCount,
            criticalCount: criticalCount,
            liveAlertCount: liveAlertCount
        )
    }

    func resetDraft() {
        draftNote = ""
        draftChecklist = HandoffChecklistState()
        draftKind = .routine
        draftFocusAreas = HandoffFocusState()
        draftFollowUpItems = []
        draftCheckInWindow = .none
    }

    private func persistEntries() {
        cleanupCompletedFollowUpKeys()
        if let data = try? encoder.encode(entries) {
            defaults.set(data, forKey: StorageKey.entries)
        }
    }

    private func persistDraftChecklist() {
        if let data = try? encoder.encode(draftChecklist) {
            defaults.set(data, forKey: StorageKey.draftChecklist)
        }
    }

    private func persistDraftFocusAreas() {
        if let data = try? encoder.encode(draftFocusAreas) {
            defaults.set(data, forKey: StorageKey.draftFocusAreas)
        }
    }

    private func persistDraftFollowUpItems() {
        if let data = try? encoder.encode(draftFollowUpItems) {
            defaults.set(data, forKey: StorageKey.draftFollowUpItems)
        }
    }

    private func persistCompletedFollowUpKeys() {
        if let data = try? encoder.encode(completedFollowUpKeys) {
            defaults.set(data, forKey: StorageKey.completedFollowUps)
        }
    }

    private func cleanupCompletedFollowUpKeys() {
        let validKeys = Set(
            entries.flatMap { entry in
                entry.followUpItems.enumerated().map { index, item in
                    Self.followUpCompletionKey(entryID: entry.id, index: index, item: item)
                }
            }
        )
        let filtered = completedFollowUpKeys.intersection(validKeys)
        if filtered != completedFollowUpKeys {
            completedFollowUpKeys = filtered
        }
    }

    static func followUpCompletionKey(entryID: String, index: Int, item: String) -> String {
        "\(entryID)::\(index)::\(item.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    static func formatInterval(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: interval) ?? "<1m"
    }
}

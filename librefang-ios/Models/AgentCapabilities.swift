import Foundation

nonisolated struct AgentToolFilters: Codable, Sendable {
    let toolAllowlist: [String]
    let toolBlocklist: [String]

    enum CodingKeys: String, CodingKey {
        case toolAllowlist = "tool_allowlist"
        case toolBlocklist = "tool_blocklist"
    }

    var isRestricted: Bool {
        !toolAllowlist.isEmpty || !toolBlocklist.isEmpty
    }

    var scopeLabel: String {
        isRestricted ? String(localized: "Restricted") : String(localized: "All tools")
    }

    var scopeTone: PresentationTone {
        isRestricted ? .warning : .positive
    }
}

nonisolated struct AgentAssignmentScope: Codable, Sendable {
    let assigned: [String]
    let available: [String]
    let mode: String

    var usesAllowlist: Bool {
        mode.compare("allowlist", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    func scopeLabel(openAccessLabel: String) -> String {
        usesAllowlist ? String(localized: "Allowlist") : openAccessLabel
    }

    var scopeTone: PresentationTone {
        usesAllowlist ? .warning : .positive
    }
}

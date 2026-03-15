import SwiftUI

extension AgentSessionMessage {
    var localizedRoleLabel: String {
        switch normalizedRole {
        case "user":
            return String(localized: "User")
        case "system":
            return String(localized: "System")
        default:
            return String(localized: "Agent")
        }
    }

    var roleTintColor: Color {
        switch normalizedRole {
        case "user":
            return .blue
        case "system":
            return .orange
        default:
            return .green
        }
    }

    private var normalizedRole: String {
        role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

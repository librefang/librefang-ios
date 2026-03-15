import SwiftUI

extension HandoffSnapshotKind {
    var tintColor: Color {
        switch self {
        case .routine:
            return .blue
        case .watch:
            return .yellow
        case .incident:
            return .red
        case .recovery:
            return .green
        }
    }

    var badgeBackgroundColor: Color {
        tintColor.opacity(0.12)
    }
}

extension HandoffFocusArea {
    var tintColor: Color {
        switch self {
        case .alerts:
            return .red
        case .approvals:
            return .orange
        case .watchlist:
            return .yellow
        case .sessions:
            return .blue
        case .audit:
            return .purple
        }
    }

    var badgeBackgroundColor: Color {
        tintColor.opacity(0.12)
    }

    func selectionColor(isSelected: Bool) -> Color {
        isSelected ? tintColor : .secondary
    }
}

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
}

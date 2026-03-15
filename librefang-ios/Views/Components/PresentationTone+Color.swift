import SwiftUI

extension PresentationTone {
    var color: Color {
        switch self {
        case .positive:
            return .green
        case .warning:
            return .orange
        case .caution:
            return .yellow
        case .critical:
            return .red
        case .neutral:
            return .secondary
        }
    }
}

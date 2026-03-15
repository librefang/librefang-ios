import SwiftUI

extension BudgetUtilizationStatus {
    func color(normalColor: Color = .green) -> Color {
        switch self {
        case .normal:
            return normalColor
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }
}

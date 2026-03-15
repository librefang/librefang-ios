import SwiftUI

extension MonitoringSummaryStatus {
    func color(
        positive: Color,
        warning: Color = .orange,
        caution: Color = .yellow,
        critical: Color = .red,
        neutral: Color = .secondary
    ) -> Color {
        switch tone {
        case .positive:
            return positive
        case .warning:
            return warning
        case .caution:
            return caution
        case .critical:
            return critical
        case .neutral:
            return neutral
        }
    }
}

import SwiftUI

struct StatBadge: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let value: String
    let label: LocalizedStringKey
    let icon: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color.opacity(0.7))
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(horizontalSizeClass == .compact ? 2 : 1)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: horizontalSizeClass == .compact ? 88 : 80)
        .padding(.horizontal, 7)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

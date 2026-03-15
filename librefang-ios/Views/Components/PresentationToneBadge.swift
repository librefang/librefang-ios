import SwiftUI

struct PresentationToneBadge: View {
    let text: String
    let tone: PresentationTone
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    init(
        text: String,
        tone: PresentationTone,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 4
    ) {
        self.text = text
        self.tone = tone
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(tone.badgeBackgroundColor)
            .foregroundStyle(tone.color)
            .clipShape(Capsule())
    }
}

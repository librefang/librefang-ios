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

struct PresentationToneLabelBadge: View {
    let text: String
    let systemImage: String
    let tone: PresentationTone
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    init(
        text: String,
        systemImage: String,
        tone: PresentationTone,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 4
    ) {
        self.text = text
        self.systemImage = systemImage
        self.tone = tone
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(tone.badgeBackgroundColor)
            .foregroundStyle(tone.color)
            .clipShape(Capsule())
    }
}

import SwiftUI

struct PresentationToneBadge: View {
    let text: String
    let tone: PresentationTone

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tone.badgeBackgroundColor)
            .foregroundStyle(tone.color)
            .clipShape(Capsule())
    }
}

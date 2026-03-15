import SwiftUI

struct MonitoringSnapshotCard<Badges: View>: View {
    let summary: String
    let detail: String?
    let verticalPadding: CGFloat
    let badges: Badges

    init(
        summary: String,
        detail: String? = nil,
        verticalPadding: CGFloat = 0,
        @ViewBuilder badges: () -> Badges
    ) {
        self.summary = summary
        self.detail = detail
        self.verticalPadding = verticalPadding
        self.badges = badges()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSummaryTextBlock(summary: summary, detail: detail)
            badges
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, verticalPadding)
    }
}

struct MonitoringFilterCard<Accessory: View, Controls: View>: View {
    let summary: String
    let detail: String
    let verticalPadding: CGFloat
    let accessory: Accessory
    let controls: Controls
    let showsControls: Bool

    init(
        summary: String,
        detail: String,
        verticalPadding: CGFloat = 4,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder controls: () -> Controls
    ) {
        self.summary = summary
        self.detail = detail
        self.verticalPadding = verticalPadding
        self.accessory = accessory()
        self.controls = controls()
        self.showsControls = true
    }

    init(
        summary: String,
        detail: String,
        verticalPadding: CGFloat = 4,
        @ViewBuilder accessory: () -> Accessory
    ) where Controls == EmptyView {
        self.summary = summary
        self.detail = detail
        self.verticalPadding = verticalPadding
        self.accessory = accessory()
        self.controls = EmptyView()
        self.showsControls = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResponsiveAccessoryRow(horizontalAlignment: .top, horizontalSpacing: 12, verticalSpacing: 8, spacerMinLength: 10) {
                MonitoringSummaryTextBlock(summary: summary, detail: detail)
            } accessory: {
                accessory
            }

            if showsControls {
                controls
            }
        }
        .padding(.vertical, verticalPadding)
    }
}

struct MonitoringJumpRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let tone: PresentationTone
    let badgeText: String?
    let badgeTone: PresentationTone

    init(
        title: String,
        detail: String,
        systemImage: String,
        tone: PresentationTone = .neutral,
        badgeText: String? = nil,
        badgeTone: PresentationTone = .neutral
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.tone = tone
        self.badgeText = badgeText
        self.badgeTone = badgeTone
    }

    var body: some View {
        ResponsiveAccessoryRow(horizontalAlignment: .top, horizontalSpacing: 12, verticalSpacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                iconBadge
                contentBlock
            }
        } accessory: {
            if let badgeText {
                PresentationToneBadge(text: badgeText, tone: badgeTone)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private var iconBadge: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tone.color)
            .frame(width: 34, height: 34)
            .background(tone.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
    }

    private var contentBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MonitoringFactsRow<Summary: View, Accessory: View, Facts: View>: View {
    let horizontalAlignment: VerticalAlignment
    let verticalSpacing: CGFloat
    let headerHorizontalSpacing: CGFloat
    let headerVerticalSpacing: CGFloat
    let spacerMinLength: CGFloat
    let factsSpacing: CGFloat
    let factsFont: Font
    let factsColor: Color
    let summary: Summary
    let accessory: Accessory
    let facts: Facts

    init(
        horizontalAlignment: VerticalAlignment = .top,
        verticalSpacing: CGFloat = 8,
        headerHorizontalSpacing: CGFloat = 12,
        headerVerticalSpacing: CGFloat = 8,
        spacerMinLength: CGFloat = 8,
        factsSpacing: CGFloat = 12,
        factsFont: Font = .caption,
        factsColor: Color = .secondary,
        @ViewBuilder summary: () -> Summary,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder facts: () -> Facts
    ) {
        self.horizontalAlignment = horizontalAlignment
        self.verticalSpacing = verticalSpacing
        self.headerHorizontalSpacing = headerHorizontalSpacing
        self.headerVerticalSpacing = headerVerticalSpacing
        self.spacerMinLength = spacerMinLength
        self.factsSpacing = factsSpacing
        self.factsFont = factsFont
        self.factsColor = factsColor
        self.summary = summary()
        self.accessory = accessory()
        self.facts = facts()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            ResponsiveAccessoryRow(
                horizontalAlignment: horizontalAlignment,
                horizontalSpacing: headerHorizontalSpacing,
                verticalSpacing: headerVerticalSpacing,
                spacerMinLength: spacerMinLength
            ) {
                summary
            } accessory: {
                accessory
            }

            FlowLayout(spacing: factsSpacing) {
                facts
            }
            .font(factsFont)
            .foregroundStyle(factsColor)
        }
    }
}

private struct MonitoringSummaryTextBlock: View {
    let summary: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(summary)
                .font(.subheadline.weight(.medium))
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

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
        VStack(alignment: .leading, spacing: 8) {
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
        VStack(alignment: .leading, spacing: 10) {
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
        headerVerticalSpacing: CGFloat = 6,
        spacerMinLength: CGFloat = 8,
        factsSpacing: CGFloat = 10,
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

struct MonitoringSurfaceGroupCard<Content: View>: View {
    let title: String
    let detail: String
    let verticalPadding: CGFloat
    let content: Content

    init(
        title: String,
        detail: String,
        verticalPadding: CGFloat = 2,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    var body: some View {
        MonitoringSnapshotCard(
            summary: title,
            detail: detail,
            verticalPadding: verticalPadding
        ) {
            VStack(spacing: 10) {
                content
            }
        }
    }
}

struct MonitoringSectionPreviewDeck: View {
    let title: String
    let detail: String
    let sectionTitles: [String]
    let tone: PresentationTone
    let maxVisibleSections: Int

    init(
        title: String,
        detail: String,
        sectionTitles: [String],
        tone: PresentationTone = .neutral,
        maxVisibleSections: Int = 4
    ) {
        self.title = title
        self.detail = detail
        self.sectionTitles = sectionTitles
        self.tone = tone
        self.maxVisibleSections = maxVisibleSections
    }

    var body: some View {
        MonitoringSnapshotCard(
            summary: previewSummary,
            detail: detail,
            verticalPadding: 4
        ) {
            VStack(alignment: .leading, spacing: 10) {
                MonitoringFactsRow(
                    verticalSpacing: 6,
                    headerVerticalSpacing: 4,
                    factsSpacing: 8,
                    factsFont: .caption2
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.caption.weight(.semibold))
                        Text(String(localized: "Preview the next monitoring stacks before the longer lists and cards take over the screen."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } accessory: {
                    PresentationToneBadge(text: sectionCountLabel, tone: tone)
                } facts: {
                    if let firstVisibleSectionTitle {
                        Label(String(localized: "Starts with \(firstVisibleSectionTitle)"), systemImage: "arrow.turn.down.right")
                    }
                    if hiddenSectionCount > 0 {
                        Label(
                            hiddenSectionCount == 1 ? String(localized: "1 more section") : String(localized: "\(hiddenSectionCount) more sections"),
                            systemImage: "ellipsis.rectangle"
                        )
                    }
                }

                if let firstVisibleSectionTitle {
                    MonitoringJumpRow(
                        title: firstVisibleSectionTitle,
                        detail: leadSectionDetail,
                        systemImage: "arrowshape.turn.up.forward.fill",
                        tone: tone,
                        badgeText: String(localized: "First"),
                        badgeTone: tone
                    )
                }

                if !remainingVisibleSections.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(Array(remainingVisibleSections.enumerated()), id: \.offset) { index, sectionTitle in
                            MonitoringSequenceBadge(
                                index: index + 2,
                                title: sectionTitle,
                                tone: tone
                            )
                        }
                    }
                }
                if hiddenSectionCount > 0 {
                    PresentationToneBadge(
                        text: hiddenSectionCount == 1 ? String(localized: "1 more") : String(localized: "\(hiddenSectionCount) more"),
                        tone: .neutral
                    )
                }
            }
        }
    }

    private var firstVisibleSectionTitle: String? {
        visibleSectionTitles.first
    }

    private var previewSummary: String {
        guard let firstVisibleSectionTitle else { return title }
        return String(localized: "Next: \(firstVisibleSectionTitle)")
    }

    private var remainingVisibleSections: [String] {
        Array(visibleSectionTitles.dropFirst())
    }

    private var sectionCountLabel: String {
        sectionTitles.count == 1
            ? String(localized: "1 section")
            : String(localized: "\(sectionTitles.count) sections")
    }

    private var visibleSectionTitles: [String] {
        Array(sectionTitles.prefix(maxVisibleSections))
    }

    private var leadSectionDetail: String {
        if remainingVisibleSections.isEmpty {
            return hiddenSectionCount > 0
                ? String(localized: "Additional sections stay collapsed behind this first upcoming stack.")
                : String(localized: "This is the next stack the screen will open into.")
        }
        return String(localized: "Then \(remainingVisibleSections.count) more visible sections follow in sequence.")
    }

    private var hiddenSectionCount: Int {
        max(sectionTitles.count - maxVisibleSections, 0)
    }
}

private struct MonitoringSequenceBadge: View {
    let index: Int
    let title: String
    let tone: PresentationTone

    var body: some View {
        HStack(spacing: 6) {
            Text("\(index)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tone.color)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tone.color.opacity(0.10), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(tone.color.opacity(0.18))
        )
    }
}

struct MonitoringShortcutRail<Content: View>: View {
    let title: String
    let detail: String?
    let verticalSpacing: CGFloat
    let content: Content

    init(
        title: String,
        detail: String? = nil,
        verticalSpacing: CGFloat = 6,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.verticalSpacing = verticalSpacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            FlowLayout(spacing: 8) {
                content
            }
        }
    }
}

struct MonitoringSurfaceShortcutChip: View {
    let title: String
    let systemImage: String
    let tone: PresentationTone
    let badgeText: String?

    init(
        title: String,
        systemImage: String,
        tone: PresentationTone = .neutral,
        badgeText: String? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.badgeText = badgeText
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tone.color)
                .frame(width: 20, height: 20)
                .background(tone.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            if let badgeText {
                Text(badgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tone.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(tone.color.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.secondary.opacity(0.08), in: Capsule())
    }
}

private struct MonitoringSummaryTextBlock: View {
    let summary: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
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

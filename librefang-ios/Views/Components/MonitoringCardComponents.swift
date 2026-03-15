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
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    MonitoringSummaryTextBlock(summary: summary, detail: detail)
                    Spacer(minLength: 10)
                    accessory
                }

                VStack(alignment: .leading, spacing: 8) {
                    MonitoringSummaryTextBlock(summary: summary, detail: detail)
                    accessory
                }
            }

            if showsControls {
                controls
            }
        }
        .padding(.vertical, verticalPadding)
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

import SwiftUI

struct ResponsiveAccessoryRow<Leading: View, Accessory: View>: View {
    let horizontalAlignment: VerticalAlignment
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let spacerMinLength: CGFloat
    let leading: Leading
    let accessory: Accessory

    init(
        horizontalAlignment: VerticalAlignment = .firstTextBaseline,
        horizontalSpacing: CGFloat = 10,
        verticalSpacing: CGFloat = 5,
        spacerMinLength: CGFloat = 6,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.horizontalAlignment = horizontalAlignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.spacerMinLength = spacerMinLength
        self.leading = leading()
        self.accessory = accessory()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: horizontalAlignment, spacing: horizontalSpacing) {
                leading
                Spacer(minLength: spacerMinLength)
                accessory
            }

            VStack(alignment: .leading, spacing: verticalSpacing) {
                leading
                accessory
            }
        }
    }
}

struct ResponsiveValueRow<Leading: View, Value: View>: View {
    let horizontalAlignment: VerticalAlignment
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let spacerMinLength: CGFloat
    let horizontalTextAlignment: TextAlignment
    let verticalTextAlignment: TextAlignment
    let leading: Leading
    let value: Value

    init(
        horizontalAlignment: VerticalAlignment = .firstTextBaseline,
        horizontalSpacing: CGFloat = 10,
        verticalSpacing: CGFloat = 3,
        spacerMinLength: CGFloat = 6,
        horizontalTextAlignment: TextAlignment = .trailing,
        verticalTextAlignment: TextAlignment = .leading,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder value: () -> Value
    ) {
        self.horizontalAlignment = horizontalAlignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.spacerMinLength = spacerMinLength
        self.horizontalTextAlignment = horizontalTextAlignment
        self.verticalTextAlignment = verticalTextAlignment
        self.leading = leading()
        self.value = value()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: horizontalAlignment, spacing: horizontalSpacing) {
                leading
                Spacer(minLength: spacerMinLength)
                value
                    .multilineTextAlignment(horizontalTextAlignment)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: verticalSpacing) {
                leading
                value
                    .multilineTextAlignment(verticalTextAlignment)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct ResponsiveLabeledContentRow<Label: View, Value: View>: View {
    let verticalSpacing: CGFloat
    let horizontalTextAlignment: TextAlignment
    let verticalTextAlignment: TextAlignment
    let label: Label
    let value: Value

    init(
        verticalSpacing: CGFloat = 5,
        horizontalTextAlignment: TextAlignment = .trailing,
        verticalTextAlignment: TextAlignment = .leading,
        @ViewBuilder label: () -> Label,
        @ViewBuilder value: () -> Value
    ) {
        self.verticalSpacing = verticalSpacing
        self.horizontalTextAlignment = horizontalTextAlignment
        self.verticalTextAlignment = verticalTextAlignment
        self.label = label()
        self.value = value()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            LabeledContent {
                value
                    .multilineTextAlignment(horizontalTextAlignment)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } label: {
                label
            }

            VStack(alignment: .leading, spacing: verticalSpacing) {
                label
                value
                    .multilineTextAlignment(verticalTextAlignment)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct ResponsiveIconDetailRow<Icon: View, Detail: View>: View {
    let horizontalAlignment: VerticalAlignment
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let spacerMinLength: CGFloat
    let icon: Icon
    let detail: Detail

    init(
        horizontalAlignment: VerticalAlignment = .top,
        horizontalSpacing: CGFloat = 10,
        verticalSpacing: CGFloat = 8,
        spacerMinLength: CGFloat = 6,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder detail: () -> Detail
    ) {
        self.horizontalAlignment = horizontalAlignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.spacerMinLength = spacerMinLength
        self.icon = icon()
        self.detail = detail()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: horizontalAlignment, spacing: horizontalSpacing) {
                icon
                detail
                Spacer(minLength: spacerMinLength)
            }

            VStack(alignment: .leading, spacing: verticalSpacing) {
                icon
                detail
            }
        }
    }
}

struct ResponsiveInlineGroup<Content: View>: View {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let verticalAlignment: HorizontalAlignment
    let content: Content

    init(
        horizontalSpacing: CGFloat = 10,
        verticalSpacing: CGFloat = 6,
        verticalAlignment: HorizontalAlignment = .leading,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.verticalAlignment = verticalAlignment
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: horizontalSpacing) {
                content
            }

            VStack(alignment: verticalAlignment, spacing: verticalSpacing) {
                content
            }
        }
    }
}

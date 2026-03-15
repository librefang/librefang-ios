import SwiftUI

struct GlassCapsuleBadge: View {
    let text: String
    let foregroundStyle: Color
    let backgroundOpacity: Double
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    init(
        text: String,
        foregroundStyle: Color = .white,
        backgroundOpacity: Double = 0.12,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 4
    ) {
        self.text = text
        self.foregroundStyle = foregroundStyle
        self.backgroundOpacity = backgroundOpacity
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(.white.opacity(backgroundOpacity))
            .foregroundStyle(foregroundStyle)
            .clipShape(Capsule())
    }
}

struct TintedCapsuleBadge: View {
    let text: String
    let foregroundStyle: Color
    let backgroundStyle: Color
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    init(
        text: String,
        foregroundStyle: Color,
        backgroundStyle: Color,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 4
    ) {
        self.text = text
        self.foregroundStyle = foregroundStyle
        self.backgroundStyle = backgroundStyle
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundStyle)
            .foregroundStyle(foregroundStyle)
            .clipShape(Capsule())
    }
}

struct TintedLabelCapsuleBadge: View {
    let text: String
    let systemImage: String
    let foregroundStyle: Color
    let backgroundStyle: Color
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    init(
        text: String,
        systemImage: String,
        foregroundStyle: Color,
        backgroundStyle: Color,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 4
    ) {
        self.text = text
        self.systemImage = systemImage
        self.foregroundStyle = foregroundStyle
        self.backgroundStyle = backgroundStyle
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundStyle)
            .foregroundStyle(foregroundStyle)
            .clipShape(Capsule())
    }
}

struct SelectableCapsuleBadge: View {
    let text: String
    let isSelected: Bool
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    init(
        text: String,
        isSelected: Bool,
        horizontalPadding: CGFloat = 12,
        verticalPadding: CGFloat = 8
    ) {
        self.text = text
        self.isSelected = isSelected
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    var body: some View {
        TintedCapsuleBadge(
            text: text,
            foregroundStyle: isSelected ? .accentColor : .secondary,
            backgroundStyle: isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12),
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        )
    }
}

struct SelectableLabelCapsuleBadge: View {
    let text: String
    let systemImage: String
    let isSelected: Bool
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    init(
        text: String,
        systemImage: String,
        isSelected: Bool,
        horizontalPadding: CGFloat = 12,
        verticalPadding: CGFloat = 8
    ) {
        self.text = text
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    var body: some View {
        TintedLabelCapsuleBadge(
            text: text,
            systemImage: systemImage,
            foregroundStyle: isSelected ? .accentColor : .secondary,
            backgroundStyle: isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12),
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        )
    }
}

struct GlassLabelBadge: View {
    let text: String
    let systemImage: String
    let foregroundStyle: Color
    let backgroundOpacity: Double
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    init(
        text: String,
        systemImage: String,
        foregroundStyle: Color = .white,
        backgroundOpacity: Double = 0.12,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 4
    ) {
        self.text = text
        self.systemImage = systemImage
        self.foregroundStyle = foregroundStyle
        self.backgroundOpacity = backgroundOpacity
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(.white.opacity(backgroundOpacity))
            .foregroundStyle(foregroundStyle)
            .clipShape(Capsule())
    }
}

struct GlassCircleIconButton: View {
    let systemImage: String
    let foregroundStyle: Color
    let backgroundOpacity: Double
    let action: () -> Void

    init(
        systemImage: String,
        foregroundStyle: Color = .white.opacity(0.9),
        backgroundOpacity: Double = 0.12,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.foregroundStyle = foregroundStyle
        self.backgroundOpacity = backgroundOpacity
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(foregroundStyle)
                .padding(8)
                .background(.white.opacity(backgroundOpacity))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct TintedCircleIconButton: View {
    let systemImage: String
    let foregroundStyle: Color
    let backgroundStyle: Color
    let action: () -> Void

    init(
        systemImage: String,
        foregroundStyle: Color,
        backgroundStyle: Color,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.foregroundStyle = foregroundStyle
        self.backgroundStyle = backgroundStyle
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(foregroundStyle)
                .padding(6)
                .background(backgroundStyle)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct GlassPanelButtonStyle: ButtonStyle {
    let fillOpacity: Double
    let cornerRadius: CGFloat
    let foregroundStyle: Color

    init(
        fillOpacity: Double,
        cornerRadius: CGFloat = 12,
        foregroundStyle: Color = .white
    ) {
        self.fillOpacity = fillOpacity
        self.cornerRadius = cornerRadius
        self.foregroundStyle = foregroundStyle
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(foregroundStyle)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(.white.opacity(fillOpacity * (configuration.isPressed ? 0.8 : 1)))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct GlassCapsuleButtonStyle: ButtonStyle {
    let fillOpacity: Double
    let foregroundStyle: Color

    init(fillOpacity: Double, foregroundStyle: Color = .white) {
        self.fillOpacity = fillOpacity
        self.foregroundStyle = foregroundStyle
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.white.opacity(fillOpacity * (configuration.isPressed ? 0.65 : 1)))
            .clipShape(Capsule())
    }
}

private struct GlassPanelModifier: ViewModifier {
    let fillStyle: Color
    let fillOpacity: Double
    let cornerRadius: CGFloat
    let strokeOpacity: Double?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background(fillStyle.opacity(fillOpacity))
            .clipShape(shape)
            .overlay {
                if let strokeOpacity {
                    shape.strokeBorder(.white.opacity(strokeOpacity))
                }
            }
    }
}

extension View {
    func glassPanel(
        fillStyle: Color = .white,
        fillOpacity: Double,
        cornerRadius: CGFloat,
        strokeOpacity: Double? = nil
    ) -> some View {
        modifier(
            GlassPanelModifier(
                fillStyle: fillStyle,
                fillOpacity: fillOpacity,
                cornerRadius: cornerRadius,
                strokeOpacity: strokeOpacity
            )
        )
    }
}

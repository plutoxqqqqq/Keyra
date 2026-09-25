import SwiftUI

/// Where the long-press popup sits, in keyboard coordinates.
struct AlternatesPopupLayout: Equatable {
    var itemWidth: CGFloat
    var totalWidth: CGFloat
    var originX: CGFloat
    var originY: CGFloat
    var height: CGFloat
}

/// The row of alternatives shown while a key is held (é è ê above "e", ".com"
/// above ".", and so on). Selection is driven by the finger position passed in
/// from the key's drag gesture, so a single finger can pick an alternative.
struct KeyboardAlternatesPopupView: View {

    let items: [KeyboardKeyLongPress]
    let selectedIndex: Int
    let theme: KeyboardTheme
    let layout: AlternatesPopupLayout

    private var fontSize: CGFloat {
        CGFloat(KeyboardMetrics.clamp(theme.fontSize * 0.85, 9, 30, fallback: 18))
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.indices), id: \.self) { index in
                let item = items[index]
                Text(item.label)
                    .font(.system(size: fontSize, weight: theme.fontWeight.fontWeight))
                    .foregroundColor(theme.textColor.swiftUIColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(width: layout.itemWidth, height: layout.height)
                    .background(index == selectedIndex
                                ? theme.pressedKeyColor.swiftUIColor
                                : theme.keyColor.swiftUIColor)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(theme.cornerRadius) + 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CGFloat(theme.cornerRadius) + 4, style: .continuous)
                .strokeBorder(theme.borderColor.swiftUIColor, lineWidth: CGFloat(theme.borderWidth))
        )
        .shadow(color: Color.black.opacity(0.28), radius: 8, y: 3)
        .frame(width: layout.totalWidth, height: layout.height)
        .offset(x: layout.originX, y: layout.originY)
        // The finger is already tracked by the key's gesture; the popup must not
        // steal those events.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

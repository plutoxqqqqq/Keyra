import SwiftUI

/// Gesture callbacks supplied by the keyboard root view.
struct KeyboardKeyActions {
    var pressBegan: (KeyboardKey) -> Void
    var pressMoved: (KeyboardKey, CGPoint) -> Void
    var pressEnded: (KeyboardKey) -> Void
    var pressCancelled: (KeyboardKey) -> Void
}

/// One key, positioned by the geometry engine.
///
/// A plain shape + text with a zero-distance drag gesture rather than a Button:
/// buttons add latency and swallow the press/release timing the long-press and
/// repeat behaviour depends on.
struct KeyboardKeyView: View {

    let frame: KeyFrame
    let theme: KeyboardTheme
    let fontScale: Double
    let isPressed: Bool
    let isShiftActive: Bool
    let actions: KeyboardKeyActions

    private var key: KeyboardKey { frame.key }

    private var backgroundColor: Color {
        if isPressed { return theme.pressedKeyColor.swiftUIColor }
        if key.action == .shift, isShiftActive { return theme.pressedKeyColor.swiftUIColor }
        return (key.isSpecial ? theme.specialKeyColor : theme.keyColor).swiftUIColor
    }

    private var foregroundColor: Color {
        (key.isSpecial ? theme.specialTextColor : theme.textColor).swiftUIColor
    }

    private var fontSize: CGFloat {
        CGFloat(KeyboardMetrics.clamp(theme.fontSize * fontScale, 9, 40, fallback: 20))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CGFloat(theme.cornerRadius), style: .continuous)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: CGFloat(theme.cornerRadius), style: .continuous)
                        .strokeBorder(theme.borderColor.swiftUIColor, lineWidth: CGFloat(theme.borderWidth))
                )
                .shadow(
                    color: theme.keyShadowOpacity > 0 ? Color.black.opacity(theme.keyShadowOpacity) : Color.clear,
                    radius: CGFloat(theme.keyShadowRadius),
                    y: theme.keyShadowRadius > 0 ? 1 : 0
                )

            Text(frame.label)
                .font(.system(size: fontSize, weight: theme.fontWeight.fontWeight))
                .foregroundColor(foregroundColor)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, frame.width > 24 ? 3 : 0.5)
        }
        .frame(width: CGFloat(max(0, frame.width)), height: CGFloat(max(0, frame.height)))
        .contentShape(Rectangle())
        .scaleEffect(isPressed ? CGFloat(theme.pressedScale) : 1)
        .animation(.easeOut(duration: 0.06), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(KeyboardCoordinateSpace.name))
                .onChanged { value in
                    if !isPressed {
                        actions.pressBegan(key)
                    }
                    let travel = max(abs(value.translation.height), abs(value.translation.width))
                    if travel > KeyboardCoordinateSpace.minimumTouchCancelDistance, isPressed {
                        // The finger wandered off: treat it as a cancel.
                        actions.pressCancelled(key)
                    } else {
                        actions.pressMoved(key, value.location)
                    }
                }
                .onEnded { _ in
                    actions.pressEnded(key)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(key.spokenLabel))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("keyra.key.\(key.action.type.rawValue)")
    }
}

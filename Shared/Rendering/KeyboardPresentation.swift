import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Bridges the platform-neutral colour model to SwiftUI / UIKit.
extension KeyboardColor {

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    #if canImport(UIKit)
    var uiColor: UIColor {
        UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }

    init(uiColor: UIColor) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) {
            self.init(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
        } else {
            self = KeyboardColor.placeholder
        }
    }
    #endif
}

extension Color {
    /// Named constructor so it is obvious this is Keyra's own colour type.
    init(keyra color: KeyboardColor) {
        self = color.swiftUIColor
    }
}

extension KeyboardFontWeight {

    var fontWeight: Font.Weight {
        switch self {
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        }
    }

    #if canImport(UIKit)
    var uiFontWeight: UIFont.Weight {
        switch self {
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        }
    }
    #endif
}

extension ShiftState {
    var symbolName: String {
        switch self {
        case .off: return "shift"
        case .shift: return "shift.fill"
        case .capsLock: return "capslock.fill"
        }
    }
}

#if canImport(UIKit)
extension HapticStrength {

    /// `nil` for `.off` — public API only, no private feedback APIs.
    var impactStyle: UIImpactFeedbackGenerator.FeedbackStyle? {
        switch self {
        case .off: return nil
        case .light: return .light
        case .medium: return .medium
        case .strong: return .heavy
        }
    }
}
#endif

/// Names shared between the keyboard root view and the key views so gestures can
/// report positions in keyboard coordinates.
enum KeyboardCoordinateSpace {
    static let name = "keyra.keyboard"
    static let popupHeight: CGFloat = 46
    static let popupItemMinWidth: CGFloat = 34
    static let minimumTouchCancelDistance: CGFloat = 70
}

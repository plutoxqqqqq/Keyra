import SwiftUI

/// Renders one row using the frames computed by `KeyboardMetrics`.
///
/// The row knows nothing about how many keys it has or what they do — a row of
/// one key and a row of twenty keys both come out of the same code.
struct KeyboardRowView: View {

    let row: RowFrame
    let theme: KeyboardTheme
    let settings: KeyboardSettings
    let shiftState: ShiftState
    let pressedKeyID: UUID?
    let actions: KeyboardKeyActions

    var body: some View {
        ForEach(row.keys) { keyFrame in
            KeyboardKeyView(
                frame: keyFrame,
                theme: theme,
                fontScale: settings.fontScale,
                isPressed: pressedKeyID == keyFrame.id,
                isShiftActive: shiftState.isActive,
                actions: actions
            )
            .offset(x: CGFloat(keyFrame.x), y: CGFloat(keyFrame.y))
        }
    }
}

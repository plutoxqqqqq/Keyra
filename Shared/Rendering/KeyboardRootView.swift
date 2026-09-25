import SwiftUI

/// The keyboard itself.
///
/// Used unchanged by the keyboard extension and by the host app's live preview,
/// which is what guarantees the preview can never disagree with the real thing:
/// same model, same geometry engine, same key views, same action engine.
struct KeyboardRootView: View {

    @ObservedObject var model: KeyboardViewModel
    var isLandscape: Bool = false
    var showsBackground: Bool = true
    /// Vertical inset kept free for the home indicator area.
    var bottomInset: Double = 0
    /// Set to false in the host app so the preview does not open system popups.
    var showsNotice: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let geometry = model.geometry(for: size, isLandscape: isLandscape)
            let keyActions = makeActions(geometry: geometry)

            ZStack(alignment: .topLeading) {
                if showsBackground {
                    model.effectiveTheme.background.swiftUIColor
                }

                ForEach(geometry.rows) { row in
                    KeyboardRowView(
                        row: row,
                        theme: model.effectiveTheme,
                        settings: model.settings,
                        shiftState: model.shiftState,
                        pressedKeyID: model.pressedKeyID,
                        actions: keyActions
                    )
                }

                if let pending = model.alternates,
                   let popupKeyFrame = Self.keyFrame(for: pending.keyID, in: geometry) {
                    KeyboardAlternatesPopupView(
                        items: pending.items,
                        selectedIndex: pending.selectedIndex,
                        theme: model.effectiveTheme,
                        layout: Self.popupLayout(
                            for: popupKeyFrame,
                            itemCount: pending.items.count,
                            keyboardWidth: geometry.width
                        )
                    )
                }

                if showsNotice, let notice = model.notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundColor(model.effectiveTheme.textColor.swiftUIColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(model.effectiveTheme.specialKeyColor.swiftUIColor.opacity(0.95))
                        .clipShape(Capsule())
                        .padding(6)
                        .onTapGesture { model.dismissNotice() }
                        .accessibilityLabel(Text(notice))
                }
            }
            .frame(width: size.width, height: max(CGFloat(geometry.height) + CGFloat(bottomInset), 1), alignment: .topLeading)
            .coordinateSpace(name: KeyboardCoordinateSpace.name)
        }
    }

    // MARK: - Interaction wiring

    private func makeActions(geometry: KeyboardGeometry) -> KeyboardKeyActions {
        KeyboardKeyActions(
            pressBegan: { key in
                model.pressBegan(key)
            },
            pressMoved: { key, location in
                guard let pending = model.alternates, pending.keyID == key.id,
                      let popupKeyFrame = Self.keyFrame(for: key.id, in: geometry) else { return }
                let layout = Self.popupLayout(
                    for: popupKeyFrame,
                    itemCount: pending.items.count,
                    keyboardWidth: geometry.width
                )
                let index = Self.alternateIndex(
                    for: location.x,
                    layout: layout,
                    itemCount: pending.items.count
                )
                model.selectAlternate(index)
            },
            pressEnded: { key in
                model.pressEnded(key)
            },
            pressCancelled: { key in
                model.pressCancelled(key)
            }
        )
    }

    static func keyFrame(for keyID: UUID, in geometry: KeyboardGeometry) -> KeyFrame? {
        for row in geometry.rows {
            if let match = row.keys.first(where: { $0.id == keyID }) { return match }
        }
        return nil
    }

    static func popupLayout(for keyFrame: KeyFrame, itemCount: Int, keyboardWidth: Double) -> AlternatesPopupLayout {
        let count = max(1, itemCount)
        let itemWidth = max(KeyboardCoordinateSpace.popupItemMinWidth, CGFloat(keyFrame.width))
        let totalWidth = itemWidth * CGFloat(count)
        let centred = CGFloat(keyFrame.x) + ((CGFloat(keyFrame.width) - totalWidth) / 2)
        let maxOriginX = max(0, CGFloat(keyboardWidth) - totalWidth)
        let originX = min(max(0, centred), maxOriginX)
        let originY = max(0, CGFloat(keyFrame.y) - KeyboardCoordinateSpace.popupHeight)
        return AlternatesPopupLayout(
            itemWidth: itemWidth,
            totalWidth: totalWidth,
            originX: originX,
            originY: originY,
            height: KeyboardCoordinateSpace.popupHeight
        )
    }

    static func alternateIndex(for locationX: CGFloat, layout: AlternatesPopupLayout, itemCount: Int) -> Int {
        guard itemCount > 0, layout.itemWidth > 0 else { return 0 }
        let relative = locationX - layout.originX
        let raw = Int((relative / layout.itemWidth).rounded(.down))
        return min(max(0, raw), itemCount - 1)
    }
}

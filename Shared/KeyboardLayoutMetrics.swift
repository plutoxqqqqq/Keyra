import Foundation

/// Absolute frame of one key inside the keyboard, in points relative to the
/// keyboard's top-left corner. Produced by pure arithmetic so it can be unit
/// tested without any UIKit or SwiftUI involvement.
struct KeyFrame: Equatable, Identifiable {
    var id: UUID
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    /// Label to draw, already resolved for the current Shift state.
    var label: String
    /// The key this frame came from (carries action, styling hints, alternates).
    var key: KeyboardKey
}

struct RowFrame: Equatable, Identifiable {
    /// The row's own identifier so reordering rows animates correctly.
    var id: UUID
    var y: Double
    var height: Double
    var keys: [KeyFrame]

    var keyCount: Int { keys.count }
    var isEmpty: Bool { keys.isEmpty }
}

/// The complete computed layout of the keyboard for a given available size.
struct KeyboardGeometry: Equatable {

    var width: Double
    var height: Double
    var rows: [RowFrame]
    var keySpacing: Double
    var rowSpacing: Double

    /// `true` when the rows needed more vertical room than was offered (the
    /// extension then asks iOS for a taller input view).
    var isOverflowing: Bool
    /// Narrowest key in the whole keyboard, used for "keys are too small" hints.
    var minimumKeyWidth: Double
    var maxRowKeyCount: Int
    var keyCount: Int
    var isDrawnEmpty: Bool

    static let empty = KeyboardGeometry(
        width: 0,
        height: 0,
        rows: [],
        keySpacing: 0,
        rowSpacing: 0,
        isOverflowing: false,
        minimumKeyWidth: 0,
        maxRowKeyCount: 0,
        keyCount: 0,
        isDrawnEmpty: true
    )
}

/// All keyboard sizing maths lives here.
///
/// Rules that make the renderer fully dynamic:
/// * Rows are laid out from the data model — any number of rows, any weights.
/// * Keys are sized by *relative weight* normalised against the real available
///   width, so a 3-key row and a 20-key row both fill the screen correctly.
/// * Every input is validated: NaN, infinity, negative and absurd values are
///   replaced by safe defaults and can never produce a negative frame.
enum KeyboardMetrics {

    // MARK: - Tunables

    /// Reference device width used by the editor's "will it fit" hints.
    static let referencePortraitWidth = 390.0
    /// Reference keyboard height (iPhone portrait, incl. bottom bar).
    static let referenceKeyboardHeight = 291.0
    /// Below this a key becomes hard to hit reliably.
    static let readableKeyWidth = 26.0
    static let minimumKeyWidth = 6.0
    static let minimumKeyHeight = 20.0
    static let maximumKeyWidth = 130.0
    static let standardKeyHeight = 46.0
    /// Hard ceiling for the requested input-view height (fraction of the screen).
    static let maximumKeyboardHeightFraction = 0.62

    // MARK: - Helpers

    static func safe(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return value
    }

    static func clamp(_ value: Double, _ lower: Double, _ upper: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        if value < lower { return lower }
        if value > upper { return upper }
        return value
    }

    /// Height of one standard-key row for a given width and orientation.
    /// Scales with the screen instead of hardcoding a device resolution.
    static func unitKeyHeight(forWidth width: Double, isLandscape: Bool) -> Double {
        let safeWidth = clamp(width, 240, 900, fallback: referencePortraitWidth)
        if isLandscape {
            let compact = 34.0 * (safeWidth / 700.0)
            return clamp(compact, 28, 42, fallback: 34)
        }
        let scaled = standardKeyHeight * (safeWidth / referencePortraitWidth)
        return clamp(scaled, 38, 56, fallback: standardKeyHeight)
    }

    /// Rows that actually render (empty rows are skipped everywhere, which is
    /// what the editor warns about).
    static func renderedRows(of layout: KeyboardLayout) -> [KeyboardRow] {
        layout.rows.filter { !$0.keys.isEmpty }
    }

    // MARK: - Geometry

    static func geometry(
        layout: KeyboardLayout,
        availableWidth: Double,
        availableHeight: Double,
        keySpacing: Double,
        rowSpacing: Double,
        horizontalInset: Double = 0,
        isLandscape: Bool = false,
        justification: RowJustification = .capAndCenter,
        shiftState: ShiftState = .off
    ) -> KeyboardGeometry {

        let spacing = clamp(keySpacing, 0, 24, fallback: 6)
        let vSpacing = clamp(rowSpacing, 0, 32, fallback: 9)
        let insets = clamp(horizontalInset, 0, 80, fallback: 0)

        let width = clamp(availableWidth, 1, 4096, fallback: referencePortraitWidth)
        let usableWidth = max(0, width - (insets * 2))
        let rows = renderedRows(of: layout)

        guard !rows.isEmpty else {
            return KeyboardGeometry(
                width: width,
                height: 0,
                rows: [],
                keySpacing: spacing,
                rowSpacing: vSpacing,
                isOverflowing: false,
                minimumKeyWidth: 0,
                maxRowKeyCount: 0,
                keyCount: 0,
                isDrawnEmpty: true
            )
        }

        let unitHeight = unitKeyHeight(forWidth: width, isLandscape: isLandscape)

        // --- Row heights -------------------------------------------------
        let rowWeights = rows.map {
            clamp($0.height, KeyboardLimits.minRowHeightWeight, KeyboardLimits.maxRowHeightWeight, fallback: 1)
        }
        var rowHeights = rowWeights.map { unitHeight * $0 }
        let interRowSpacing = vSpacing * Double(max(0, rows.count - 1))
        let naturalTotal = rowHeights.reduce(0, +) + interRowSpacing

        let offeredHeight = safe(availableHeight, fallback: naturalTotal)
        var isOverflowing = false

        if offeredHeight > 0, naturalTotal > offeredHeight {
            let room = max(0, offeredHeight - interRowSpacing)
            let weightTotal = max(0.0001, rowWeights.reduce(0, +))
            rowHeights = rowWeights.map { weight in
                let share = room * (weight / weightTotal)
                return max(minimumKeyHeight, share)
            }
            let shrunkTotal = rowHeights.reduce(0, +) + interRowSpacing
            isOverflowing = shrunkTotal > offeredHeight + 0.5
        }

        // --- Rows and keys ----------------------------------------------
        var rowFrames: [RowFrame] = []
        var y = 0.0
        var minimumKeyWidth = Double.greatestFiniteMagnitude
        var maxRowKeyCount = 0
        var keyCount = 0

        for (rowIndex, row) in rows.enumerated() {
            let rowHeight = max(minimumKeyHeight, rowHeights[rowIndex])
            let keyCountInRow = row.keys.count
            maxRowKeyCount = max(maxRowKeyCount, keyCountInRow)
            keyCount += keyCountInRow

            let usableForKeys = max(0, usableWidth - (spacing * Double(max(0, keyCountInRow - 1))))

            let weights = row.keys.map {
                clamp($0.width, KeyboardLimits.minKeyWidthWeight, KeyboardLimits.maxKeyWidthWeight, fallback: 1)
            }
            let weightTotal = max(0.0001, weights.reduce(0, +))

            var widths = weights.map { usableForKeys * ($0 / weightTotal) }
            var originX = 0.0

            if justification == .capAndCenter, let widest = widths.max(), widest > maximumKeyWidth {
                widths = widths.map { min($0, maximumKeyWidth) }
                let used = widths.reduce(0, +) + (spacing * Double(max(0, keyCountInRow - 1)))
                originX = max(0, (usableWidth - used) / 2)
            }

            // Per-key height weight, normalised inside the row so a key can never
            // be taller than its row.
            let heightWeights = row.keys.map {
                clamp($0.height, KeyboardLimits.minKeyHeightWeight, KeyboardLimits.maxKeyHeightWeight, fallback: 1)
            }
            let maxHeightWeight = max(0.0001, heightWeights.max() ?? 1)

            var keyFrames: [KeyFrame] = []
            var x = insets + originX
            for (keyIndex, key) in row.keys.enumerated() {
                let keyWidth = max(0, widths[keyIndex])
                let keyHeight = max(0, rowHeight * (heightWeights[keyIndex] / maxHeightWeight))
                keyFrames.append(KeyFrame(
                    id: key.id,
                    x: x,
                    y: y + ((rowHeight - keyHeight) / 2),
                    width: keyWidth,
                    height: keyHeight,
                    label: key.displayLabel(forShiftState: shiftState),
                    key: key
                ))
                x += keyWidth + spacing
                minimumKeyWidth = min(minimumKeyWidth, keyWidth)
            }

            rowFrames.append(RowFrame(id: row.id, y: y, height: rowHeight, keys: keyFrames))
            y += rowHeight + vSpacing
        }

        let contentHeight = rowFrames.reduce(0) { $0 + $1.height } + (vSpacing * Double(max(0, rowFrames.count - 1)))

        return KeyboardGeometry(
            width: width,
            height: contentHeight,
            rows: rowFrames,
            keySpacing: spacing,
            rowSpacing: vSpacing,
            isOverflowing: isOverflowing,
            minimumKeyWidth: minimumKeyWidth == .greatestFiniteMagnitude ? 0 : minimumKeyWidth,
            maxRowKeyCount: maxRowKeyCount,
            keyCount: keyCount,
            isDrawnEmpty: false
        )
    }

    // MARK: - Preferred input view height

    /// The height the keyboard extension should request from iOS for a layout —
    /// computed from the rows that will actually be drawn.
    static func preferredKeyboardHeight(
        layout: KeyboardLayout,
        width: Double,
        isLandscape: Bool,
        keySpacing: Double,
        rowSpacing: Double,
        topInset: Double = 0,
        bottomInset: Double = 0
    ) -> Double {
        let rows = renderedRows(of: layout)
        guard !rows.isEmpty else { return 0 }

        let unitHeight = unitKeyHeight(forWidth: width, isLandscape: isLandscape)
        let weights = rows.map {
            clamp($0.height, KeyboardLimits.minRowHeightWeight, KeyboardLimits.maxRowHeightWeight, fallback: 1)
        }
        let rowsHeight = weights.reduce(0) { $0 + (unitHeight * $1) }
        let spacing = clamp(rowSpacing, 0, 32, fallback: 9) * Double(max(0, rows.count - 1))
        let insets = max(0, safe(topInset, fallback: 0)) + max(0, safe(bottomInset, fallback: 0))
        return rowsHeight + spacing + insets
    }

    /// Clamps a requested keyboard height so the keyboard can never cover the
    /// whole screen (which iOS would refuse or clip).
    static func clampedKeyboardHeight(_ requested: Double, screenHeight: Double) -> Double {
        let safeRequested = max(minimumKeyHeight, safe(requested, fallback: standardKeyHeight))
        let ceiling = safe(screenHeight, fallback: 844) * maximumKeyboardHeightFraction
        return min(safeRequested, max(minimumKeyHeight, ceiling))
    }
}

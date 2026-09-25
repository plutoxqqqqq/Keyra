import XCTest
@testable import KeyraShared

final class KeyboardMetricsTests: XCTestCase {

    private func layout(_ rows: [KeyboardRow]) -> KeyboardLayout {
        KeyboardLayout(name: "Geometry", rows: rows)
    }

    private func row(_ count: Int, width: Double = 1, height: Double = 1) -> KeyboardRow {
        KeyboardRow(height: height, keys: (0..<count).map { index in
            KeyboardKey(label: "k\(index)", action: .insertText("k\(index)"), width: width)
        })
    }

    private func geometry(_ layout: KeyboardLayout, width: Double = 390, height: Double = 0, justification: RowJustification = .capAndCenter) -> KeyboardGeometry {
        KeyboardMetrics.geometry(
            layout: layout,
            availableWidth: width,
            availableHeight: height,
            keySpacing: 6,
            rowSpacing: 10,
            justification: justification
        )
    }

    // MARK: - Row counts

    func testRowCountsFromOneToTwelve() {
        for count in 1...12 {
            let rows = (0..<count).map { _ in row(5) }
            let result = geometry(layout(rows))
            XCTAssertEqual(result.rows.count, count, "\(count) rows should render \(count) rows")
            XCTAssertGreaterThan(result.height, 0)
            XCTAssertFalse(result.isDrawnEmpty)
        }
    }

    func testEmptyLayoutProducesAnEmptyButValidGeometry() {
        let result = geometry(layout([]))
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertEqual(result.height, 0)
        XCTAssertTrue(result.isDrawnEmpty)
        XCTAssertEqual(result.keyCount, 0)
    }

    func testRowsWithoutKeysAreSkippedWithoutDisturbingTheRest() {
        let result = geometry(layout([row(3), KeyboardRow(height: 1, keys: []), row(4)]))
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows[0].keyCount, 3)
        XCTAssertEqual(result.rows[1].keyCount, 4)
    }

    // MARK: - Key counts and widths

    func testSingleKeyRowFillsButIsCappedAndCentred() {
        let result = geometry(layout([row(1)]))
        guard let frame = result.rows.first?.keys.first else {
            return XCTFail("expected one key")
        }
        XCTAssertLessThanOrEqual(frame.width, KeyboardMetrics.maximumKeyWidth + 0.01)
        XCTAssertGreaterThan(frame.width, 0)
        // A capped key must be centred, not glued to the left edge.
        XCTAssertGreaterThan(frame.x, 10)
    }

    func testTwentyKeyRowProducesPositiveWidths() {
        let result = geometry(layout([row(20)]))
        guard let frames = result.rows.first?.keys else {
            return XCTFail("expected a row")
        }
        XCTAssertEqual(frames.count, 20)
        for frame in frames {
            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertGreaterThanOrEqual(frame.height, KeyboardMetrics.minimumKeyHeight - 0.01)
        }
        let used = frames.reduce(0) { $0 + $1.width } + (6 * 19)
        XCTAssertLessThanOrEqual(used, 390 + 0.5, "a full row must not overflow the available width")
    }

    func testExtremeKeyCountsStayFinite() {
        let result = geometry(layout([row(KeyboardLimits.maxKeysPerRow)]))
        XCTAssertEqual(result.rows.first?.keys.count, KeyboardLimits.maxKeysPerRow)
        for frame in result.rows.first?.keys ?? [] {
            XCTAssertTrue(frame.width.isFinite)
            XCTAssertGreaterThanOrEqual(frame.width, 0)
        }
    }

    func testWideSpaceKeyTakesProportionallyMoreRoom() {
        let keys = [
            KeyboardKey(label: "a", action: .insertText("a")),
            KeyboardKey(label: "space", action: .space, width: 5),
            KeyboardKey(label: "b", action: .insertText("b"))
        ]
        let result = geometry(layout([KeyboardRow(height: 1, keys: keys)]))
        guard let frames = result.rows.first?.keys, frames.count == 3 else {
            return XCTFail("expected three keys")
        }
        XCTAssertGreaterThan(frames[1].width, frames[0].width * 2)
        XCTAssertGreaterThan(frames[1].width, frames[2].width * 2)
        XCTAssertEqual(frames[0].width, frames[2].width, accuracy: 0.01)
    }

    func testMixedWidthRowsCoexist() {
        let narrow = KeyboardRow(height: 1, keys: [
            KeyboardKey(label: "⇧", action: .shift, width: 1.5),
            KeyboardKey(label: "z", action: .insertText("z")),
            KeyboardKey(label: "x", action: .insertText("x")),
            KeyboardKey(label: "⌫", action: .backspace, width: 1.5)
        ])
        let wide = KeyboardRow(height: 1, keys: [
            KeyboardKey(label: "?123", action: .none, width: 1.6),
            KeyboardKey(label: "🌐", action: .nextKeyboard, width: 1.1),
            KeyboardKey(label: "space", action: .space, width: 4.4),
            KeyboardKey(label: "return", action: .newline, width: 1.9)
        ])
        let result = geometry(layout([narrow, wide]))
        XCTAssertEqual(result.rows.count, 2)
        for rowFrame in result.rows {
            let used = rowFrame.keys.reduce(0) { $0 + $1.width } + (6 * Double(rowFrame.keyCount - 1))
            XCTAssertLessThanOrEqual(used, 390 + 0.5)
        }
        let spaceWidth = result.rows[1].keys[2].width
        let letterWidth = result.rows[1].keys[1].width
        XCTAssertGreaterThan(spaceWidth, letterWidth)
        XCTAssertEqual(result.maxRowKeyCount, 4)
    }

    func testKeysAreLaidOutLeftToRightWithoutOverlap() {
        let result = geometry(layout([row(8)]))
        guard let frames = result.rows.first?.keys else { return XCTFail("no keys") }
        for index in 1..<frames.count {
            XCTAssertGreaterThanOrEqual(frames[index].x, frames[index - 1].x + frames[index - 1].width)
        }
    }

    func testPerKeyHeightWeightScalesWithinItsRow() {
        let tallRow = KeyboardRow(height: 1, keys: [
            KeyboardKey(label: "a", action: .insertText("a"), height: 1),
            KeyboardKey(label: "b", action: .insertText("b"), height: 0.5)
        ])
        let result = geometry(layout([tallRow]))
        guard let frames = result.rows.first?.keys, frames.count == 2 else { return XCTFail("no keys") }
        XCTAssertGreaterThan(frames[0].height, frames[1].height)
        XCTAssertLessThanOrEqual(frames[0].height, result.rows[0].height + 0.01,
                                 "a key must never be taller than its row")
    }

    // MARK: - Hostile input

    func testHostileDimensionsNeverProduceNegativeFrames() {
        let cases: [(Double, Double, Double, Double)] = [
            (0, 0, 0, 0),
            (-100, -50, -1, -1),
            (.nan, .nan, .nan, .nan),
            (.infinity, .infinity, .infinity, .infinity),
            (1e12, 1e12, 1e12, 1e12),
        ]
        for (width, height, spacing, weight) in cases {
            let badRow = KeyboardRow(height: weight, keys: [
                KeyboardKey(label: "a", action: .insertText("a"), width: weight),
                KeyboardKey(label: "b", action: .insertText("b"), width: weight)
            ])
            let result = KeyboardMetrics.geometry(
                layout: layout([badRow]),
                availableWidth: width,
                availableHeight: height,
                keySpacing: spacing,
                rowSpacing: spacing
            )
            XCTAssertTrue(result.width.isFinite, "width must stay finite for \(width)")
            XCTAssertTrue(result.height.isFinite)
            XCTAssertGreaterThanOrEqual(result.width, 0)
            XCTAssertGreaterThanOrEqual(result.height, 0)
            for frame in result.rows.first?.keys ?? [] {
                XCTAssertTrue(frame.width.isFinite)
                XCTAssertTrue(frame.height.isFinite)
                XCTAssertGreaterThanOrEqual(frame.width, 0)
                XCTAssertGreaterThanOrEqual(frame.height, 0)
            }
        }
    }

    func testTinyAvailableWidthDoesNotCrash() {
        let result = geometry(layout([row(15)]), width: 12)
        XCTAssertEqual(result.rows.count, 1)
        for frame in result.rows[0].keys {
            XCTAssertGreaterThanOrEqual(frame.width, 0)
        }
    }

    func testOverflowIsReportedWhenRowsDoNotFit() {
        let rows = (0..<12).map { _ in row(6) }
        let tooShort = geometry(layout(rows), height: 120)
        XCTAssertTrue(tooShort.isOverflowing, "12 rows in 120pt must be reported as overflowing")

        let roomy = geometry(layout(rows), height: 1000)
        XCTAssertFalse(roomy.isOverflowing)
    }

    // MARK: - Preferred height

    func testPreferredHeightGrowsWithRows() {
        let oneRow = KeyboardMetrics.preferredKeyboardHeight(
            layout: layout([row(5)]), width: 390, isLandscape: false, keySpacing: 6, rowSpacing: 10
        )
        let threeRows = KeyboardMetrics.preferredKeyboardHeight(
            layout: layout([row(5), row(5), row(5)]), width: 390, isLandscape: false, keySpacing: 6, rowSpacing: 10
        )
        XCTAssertGreaterThan(threeRows, oneRow)
        XCTAssertEqual(oneRow, KeyboardMetrics.unitKeyHeight(forWidth: 390, isLandscape: false), accuracy: 0.01)
    }

    func testPreferredHeightHonoursRowWeights() {
        let flat = KeyboardMetrics.preferredKeyboardHeight(
            layout: layout([row(5, height: 1), row(5, height: 1)]), width: 390, isLandscape: false, keySpacing: 6, rowSpacing: 10
        )
        let weighted = KeyboardMetrics.preferredKeyboardHeight(
            layout: layout([row(5, height: 1), row(5, height: 2)]), width: 390, isLandscape: false, keySpacing: 6, rowSpacing: 10
        )
        XCTAssertGreaterThan(weighted, flat)
    }

    func testPreferredHeightIsZeroForAnEmptyLayout() {
        let height = KeyboardMetrics.preferredKeyboardHeight(
            layout: layout([]), width: 390, isLandscape: false, keySpacing: 6, rowSpacing: 10
        )
        XCTAssertEqual(height, 0)
    }

    func testKeyboardHeightIsClampedToTheAvailableScreen() {
        let huge = KeyboardMetrics.clampedKeyboardHeight(5000, screenHeight: 844)
        XCTAssertLessThan(huge, 844)
        XCTAssertGreaterThan(huge, 0)

        let tiny = KeyboardMetrics.clampedKeyboardHeight(-10, screenHeight: 844)
        XCTAssertGreaterThanOrEqual(tiny, KeyboardMetrics.minimumKeyHeight)

        let nan = KeyboardMetrics.clampedKeyboardHeight(.nan, screenHeight: .nan)
        XCTAssertTrue(nan.isFinite)
        XCTAssertGreaterThan(nan, 0)
    }

    func testUnitKeyHeightAdaptsToWidthAndOrientation() {
        let narrow = KeyboardMetrics.unitKeyHeight(forWidth: 320, isLandscape: false)
        let wide = KeyboardMetrics.unitKeyHeight(forWidth: 430, isLandscape: false)
        let landscape = KeyboardMetrics.unitKeyHeight(forWidth: 844, isLandscape: true)

        XCTAssertGreaterThan(wide, narrow)
        XCTAssertLessThan(landscape, wide, "landscape rows are shorter")
        XCTAssertGreaterThanOrEqual(narrow, 38)
        XCTAssertLessThanOrEqual(wide, 56)
        XCTAssertGreaterThan(KeyboardMetrics.unitKeyHeight(forWidth: 0, isLandscape: false), 0)
        XCTAssertGreaterThan(KeyboardMetrics.unitKeyHeight(forWidth: .nan, isLandscape: false), 0)
    }

    func testJustificationModes() {
        let wide = KeyboardRow(height: 1, keys: [KeyboardKey(label: "space", action: .space, width: 1)])
        let capped = geometry(layout([wide]), justification: .capAndCenter)
        let filled = geometry(layout([wide]), justification: .fill)
        XCTAssertLessThanOrEqual(capped.rows[0].keys[0].width, KeyboardMetrics.maximumKeyWidth + 0.01)
        XCTAssertGreaterThan(capped.rows[0].keys[0].x, 0)
        XCTAssertGreaterThan(filled.rows[0].keys[0].width, KeyboardMetrics.maximumKeyWidth,
                             "fill mode stretches, cap mode does not")
    }

    func testShiftStateChangesRenderedLabels() {
        let keys = [KeyboardKey(label: "a", action: .insertText("a"), shiftOutput: "A")]
        let lower = geometry(layout([KeyboardRow(height: 1, keys: keys)]))
        XCTAssertEqual(lower.rows[0].keys[0].label, "a")

        let upper = KeyboardMetrics.geometry(
            layout: layout([KeyboardRow(height: 1, keys: keys)]),
            availableWidth: 390,
            availableHeight: 0,
            keySpacing: 6,
            rowSpacing: 10,
            shiftState: .shift
        )
        XCTAssertEqual(upper.rows[0].keys[0].label, "A", "the label should show what Shift will type")
    }
}

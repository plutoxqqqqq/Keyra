import XCTest
@testable import KeyraShared

final class StabilityTests: XCTestCase {

    // MARK: - Sanitiser

    func testSanitiseEmptyConfigurationRestoresSomethingUsable() {
        let empty = KeyboardConfiguration(
            layouts: [],
            themes: [],
            activeLayoutID: UUID(),
            activeThemeID: UUID()
        )
        let repaired = KeyboardValidator.sanitize(empty)
        XCTAssertFalse(repaired.configuration.layouts.isEmpty)
        XCTAssertFalse(repaired.configuration.themes.isEmpty)
        XCTAssertTrue(repaired.configuration.layouts.contains { $0.id == repaired.configuration.activeLayoutID })
        XCTAssertTrue(repaired.configuration.themes.contains { $0.id == repaired.configuration.activeThemeID })
        XCTAssertTrue(repaired.hasWarnings)
    }

    func testSanitiseClampsHostileDimensions() {
        var configuration = KeyboardDefaults.configuration()
        configuration.layouts[0].rows[0].height = .nan
        configuration.layouts[0].rows[1].height = -12
        configuration.layouts[0].rows[0].keys[0].width = .infinity
        configuration.layouts[0].rows[0].keys[1].width = 0
        configuration.layouts[0].rows[0].keys[2].height = -1
        configuration.themes[0].cornerRadius = .nan
        configuration.themes[0].fontSize = 5000
        configuration.themes[0].keySpacing = -4
        configuration.settings.longPressDelay = .nan
        configuration.settings.fontScale = 99

        let repaired = KeyboardValidator.sanitize(configuration).configuration
        XCTAssertTrue(repaired.layouts[0].rows[0].height.isFinite)
        XCTAssertGreaterThan(repaired.layouts[0].rows[0].height, 0)
        XCTAssertGreaterThan(repaired.layouts[0].rows[1].height, 0)
        for row in repaired.layouts[0].rows {
            for key in row.keys {
                XCTAssertTrue(key.width.isFinite)
                XCTAssertTrue(key.height.isFinite)
                XCTAssertGreaterThan(key.width, 0)
                XCTAssertGreaterThan(key.height, 0)
            }
        }
        XCTAssertTrue(repaired.themes[0].cornerRadius.isFinite)
        XCTAssertLessThanOrEqual(repaired.themes[0].fontSize, 44)
        XCTAssertGreaterThanOrEqual(repaired.themes[0].keySpacing, 0)
        XCTAssertTrue(repaired.settings.longPressDelay.isFinite)
        XCTAssertLessThanOrEqual(repaired.settings.fontScale, 1.8)
    }

    func testDuplicateKeyAndRowIdentifiersAreRepaired() {
        let sharedKeyID = UUID()
        let sharedRowID = UUID()
        let keys = [
            KeyboardKey(id: sharedKeyID, label: "a", action: .insertText("a")),
            KeyboardKey(id: sharedKeyID, label: "b", action: .insertText("b")),
            KeyboardKey(id: sharedKeyID, label: "c", action: .insertText("c"))
        ]
        let layout = KeyboardLayout(name: "Dupes", rows: [
            KeyboardRow(id: sharedRowID, height: 1, keys: keys),
            KeyboardRow(id: sharedRowID, height: 1, keys: [KeyboardKey(id: sharedKeyID, label: "d", action: .insertText("d"))])
        ])
        var configuration = KeyboardDefaults.configuration()
        configuration.layouts = [layout]
        configuration.activeLayoutID = layout.id

        let repaired = KeyboardValidator.sanitize(configuration).configuration
        let allKeys = repaired.layouts[0].allKeys
        XCTAssertEqual(Set(allKeys.map { $0.id }).count, allKeys.count, "key ids must be unique")
        XCTAssertEqual(Set(repaired.layouts[0].rows.map { $0.id }).count, repaired.layouts[0].rows.count)
    }

    func testDuplicateLayoutNamesAreDisambiguated() {
        var configuration = KeyboardDefaults.configuration()
        configuration.layouts.append(KeyboardLayout(name: KeyboardDefaults.qwertyName, rows: [KeyboardRow(height: 1, keys: [KeyboardKey(label: "a", action: .insertText("a"))])]))
        let repaired = KeyboardValidator.sanitize(configuration).configuration
        let names = repaired.layouts.map { $0.name.lowercased() }
        XCTAssertEqual(Set(names).count, names.count, "layout switching relies on unique names")
    }

    func testTooManyRowsAndKeysAreTrimmedWithAnExplanation() {
        let manyKeys = (0..<(KeyboardLimits.maxKeysPerRow + 20)).map {
            KeyboardKey(label: "k\($0)", action: .insertText("k\($0)"))
        }
        let manyRows = (0..<(KeyboardLimits.maxRows + 10)).map { _ in
            KeyboardRow(height: 1, keys: manyKeys)
        }
        var configuration = KeyboardDefaults.configuration()
        configuration.layouts = [KeyboardLayout(name: "Huge", rows: manyRows)]
        configuration.activeLayoutID = configuration.layouts[0].id

        let repaired = KeyboardValidator.sanitize(configuration)
        XCTAssertLessThanOrEqual(repaired.configuration.layouts[0].rows.count, KeyboardLimits.maxRows)
        XCTAssertLessThanOrEqual(repaired.configuration.layouts[0].rows[0].keys.count, KeyboardLimits.maxKeysPerRow)
        XCTAssertTrue(repaired.issues.contains { $0.severity == .error })
    }

    func testSanitiseIsNotDestructiveForHalfFinishedEdits() {
        // A key that the user has just switched to "switch layout" but not yet
        // pointed anywhere, and an "insert text" key with no text yet.
        let keys = [
            KeyboardKey(label: "123", action: .switchLayout(layoutID: nil, layoutName: nil)),
            KeyboardKey(label: "x", action: .insertText("")),
            KeyboardKey(label: "y", action: .insertMacro(""), shiftOutput: nil)
        ]
        var configuration = KeyboardDefaults.configuration()
        configuration.layouts = [KeyboardLayout(name: "Editing", rows: [KeyboardRow(height: 1, keys: keys)])]
        configuration.activeLayoutID = configuration.layouts[0].id

        let repaired = KeyboardValidator.sanitize(configuration)
        let actions = repaired.configuration.layouts[0].allKeys.map { $0.action.type }
        XCTAssertEqual(actions[0], .switchLayout, "the chosen action type must survive sanitising")
        XCTAssertEqual(actions[1], .insertText)
        XCTAssertTrue(repaired.issues.contains { $0.title.contains("does nothing") },
                      "the user must be warned about the half-finished key")

        let issues = KeyboardValidator.issues(for: repaired.configuration)
        XCTAssertTrue(issues.contains { $0.severity == .warning && $0.title.contains("incomplete") })
    }

    func testTextIsTruncatedAtTheConfiguredLimit() {
        let enormous = String(repeating: "a", count: KeyboardLimits.maxTextLength + 500)
        var configuration = KeyboardDefaults.configuration()
        configuration.layouts = [KeyboardLayout(name: "Long", rows: [
            KeyboardRow(height: 1, keys: [KeyboardKey(label: "x", action: .insertText(enormous))])
        ])]
        configuration.activeLayoutID = configuration.layouts[0].id
        let repaired = KeyboardValidator.sanitize(configuration).configuration
        if case .insertText(let text) = repaired.layouts[0].allKeys[0].action {
            XCTAssertEqual(text.count, KeyboardLimits.maxTextLength)
        } else {
            XCTFail("the action type changed unexpectedly")
        }
    }

    // MARK: - Import validation

    private func importLayout(_ json: String) throws -> ImportedLayout {
        try JSONImportExport.importLayout(from: Data(json.utf8))
    }

    func testInvalidJSONIsRejectedWithAReadableError() {
        XCTAssertThrowsError(try importLayout("not json")) { error in
            XCTAssertTrue(error is KeyboardImportError)
            XCTAssertTrue((error as? KeyboardImportError)?.errorDescription?.contains("not valid JSON") ?? false)
        }
    }

    func testLayoutWithoutRowsIsRejected() {
        XCTAssertThrowsError(try importLayout(#"{"name": "Empty"}"#)) { error in
            guard case .missingLayout? = error as? KeyboardImportError else {
                return XCTFail("expected a missingLayout error, got \(error)")
            }
        }
    }

    func testEmptyLayoutIsRejected() {
        XCTAssertThrowsError(try importLayout(#"{"name": "Nothing", "rows": []}"#)) { error in
            guard case .emptyLayout? = error as? KeyboardImportError else {
                return XCTFail("expected an emptyLayout error, got \(error)")
            }
        }
    }

    func testRowsOfTheWrongTypeAreRejectedWithThePath() {
        XCTAssertThrowsError(try importLayout(#"{"name": "Bad", "rows": {"not": "an array"}}"#)) { error in
            guard case .invalidField(let path, _)? = error as? KeyboardImportError else {
                return XCTFail("expected an invalidField error, got \(error)")
            }
            XCTAssertTrue(path.contains("rows"), path)
        }
    }

    func testNegativeAndNonNumericDimensionsAreRejected() {
        let negative = #"{"name":"Bad","rows":[{"keys":[{"label":"a","width":-2,"action":{"type":"insertText","text":"a"}}]}]}"#
        XCTAssertThrowsError(try importLayout(negative)) { error in
            guard case .invalidField(let path, let reason)? = error as? KeyboardImportError else {
                return XCTFail("expected an invalidField error, got \(error)")
            }
            XCTAssertTrue(path.contains("width"), path)
            XCTAssertTrue(reason.contains("greater than zero"), reason)
        }

        let text = #"{"name":"Bad","rows":[{"keys":[{"label":"a","height":"tall","action":{"type":"insertText","text":"a"}}]}]}"#
        XCTAssertThrowsError(try importLayout(text))
    }

    func testInsertActionWithoutTextIsRejected() {
        let json = #"{"name":"Bad","rows":[{"keys":[{"label":"a","action":{"type":"insertText"}}]}]}"#
        XCTAssertThrowsError(try importLayout(json)) { error in
            guard case .invalidField(let path, _)? = error as? KeyboardImportError else {
                return XCTFail("expected an invalidField error, got \(error)")
            }
            XCTAssertTrue(path.contains("action"), path)
        }
    }

    func testBadColourIsRejectedWithAHelpfulMessage() {
        let json = #"{"name":"Bad","rows":[{"keys":[{"label":"a","action":{"type":"insertText","text":"a"}}]}],"theme":{"keyColor":"purple-ish"}}"#
        XCTAssertThrowsError(try importLayout(json)) { error in
            guard case .invalidField(let path, let reason)? = error as? KeyboardImportError else {
                return XCTFail("expected an invalidField error, got \(error)")
            }
            XCTAssertTrue(path.contains("keyColor"), path)
            XCTAssertTrue(reason.contains("#"), reason)
        }
    }

    func testLayoutExportCanCarryItsThemeAndImportItBack() throws {
        let layout = KeyboardDefaults.math()
        let theme = KeyboardTheme.purple()
        let json = JSONImportExport.exportLayout(layout, theme: theme)

        let imported = try importLayout(json)
        XCTAssertEqual(imported.layout.name, layout.name)
        let importedTheme = try XCTUnwrap(imported.theme, "the theme should travel with the keyboard")
        XCTAssertNotEqual(importedTheme.id, theme.id, "an imported theme must get a fresh identity")
        XCTAssertEqual(importedTheme.background.hexString, theme.background.hexString)
        XCTAssertEqual(importedTheme.cornerRadius, theme.cornerRadius)
    }

    func testUnknownActionTypeImportsAsAWarningNotAFailure() throws {
        let json = #"{"name":"Future","rows":[{"keys":[{"label":"a","action":{"type":"hologram","text":"a"}},{"label":"b","action":{"type":"insertText","text":"b"}}]}]}"#
        let imported = try importLayout(json)
        XCTAssertEqual(imported.layout.keyCount, 2)
        XCTAssertEqual(imported.layout.allKeys[0].action, .none)
        XCTAssertEqual(imported.layout.allKeys[1].action, .insertText("b"))
        XCTAssertTrue(imported.warnings.contains { $0.lowercased().contains("hologram") })
    }

    func testImportedLayoutGetsAFreshIdentity() throws {
        let original = KeyboardDefaults.qwerty()
        let json = JSONImportExport.exportLayout(original)
        let imported = try importLayout(json)
        XCTAssertNotEqual(imported.layout.id, original.id, "importing twice must not collide")
        XCTAssertEqual(imported.layout.name, original.name)
        XCTAssertEqual(imported.layout.rows.count, original.rows.count)
        XCTAssertEqual(imported.layout.keyCount, original.keyCount)
        XCTAssertEqual(imported.layout.rows[0].keys[0].action, original.rows[0].keys[0].action)
        XCTAssertEqual(imported.warnings.isEmpty, true)
    }

    func testImportSwallowsUnknownFieldNames() throws {
        let json = #"{"name":"Extra","mystery":42,"rows":[{"height":1,"colour":"blue","keys":[{"label":"a","future":true,"action":{"type":"insertText","text":"a"}}]}]}"#
        let imported = try importLayout(json)
        XCTAssertEqual(imported.layout.name, "Extra")
        XCTAssertEqual(imported.layout.keyCount, 1)
    }

    func testImportOfAnExportedConfiguration() throws {
        let configuration = KeyboardDefaults.configuration()
        let json = JSONImportExport.exportConfiguration(configuration)
        let imported = try JSONImportExport.importConfiguration(from: Data(json.utf8))
        XCTAssertEqual(imported.configuration.layouts.count, configuration.layouts.count)
        XCTAssertEqual(imported.configuration.themes.count, configuration.themes.count)

        // Identifiers must all be fresh so importing never overwrites anything.
        let originalIDs = Set(configuration.layouts.map { $0.id })
        for layout in imported.configuration.layouts {
            XCTAssertFalse(originalIDs.contains(layout.id))
        }
    }

    func testExportedFileNamesAreSafe() {
        let layout = KeyboardLayout(name: "Math / Symbols & More!")
        let name = JSONImportExport.fileName(for: layout)
        XCTAssertTrue(name.hasPrefix("keyra-"))
        XCTAssertTrue(name.hasSuffix(".json"))
        XCTAssertFalse(name.contains(" "))
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains("&"))
    }

    // MARK: - Presets

    func testEveryPresetIsValidAndFullyWired() {
        let configuration = KeyboardDefaults.configuration()
        for preset in KeyboardDefaults.presets {
            let issues = KeyboardValidator.issues(for: preset, in: configuration)
            let errors = issues.filter { $0.severity == .error }
            XCTAssertTrue(errors.isEmpty, "\(preset.name) reported errors: \(errors.map { $0.title })")

            for key in preset.allKeys {
                XCTAssertFalse(key.action.isIncomplete,
                               "\(preset.name) has a key '\(key.label)' that would do nothing")
                if case .switchLayout(_, let name) = key.action, let name {
                    XCTAssertNotNil(configuration.layout(named: name),
                                    "\(preset.name) points at a keyboard that does not exist: \(name)")
                }
            }

            let actions = preset.allKeys.map { $0.action.type }
            XCTAssertTrue(actions.contains(.space), "\(preset.name) has no space key")
            XCTAssertTrue(actions.contains(.backspace), "\(preset.name) has no backspace key")
        }
    }

    func testEveryPresetContainsASensibleRowCountAndWidths() {
        for preset in KeyboardDefaults.presets {
            XCTAssertGreaterThanOrEqual(preset.rows.count, 3, preset.name)
            XCTAssertGreaterThanOrEqual(preset.keyCount, 20, preset.name)
            XCTAssertLessThanOrEqual(preset.rows.count, 8, preset.name)
            for row in preset.rows {
                XCTAssertFalse(row.keys.isEmpty, "\(preset.name) has an empty row")
                for key in row.keys {
                    XCTAssertGreaterThan(key.width, 0)
                    XCTAssertLessThanOrEqual(key.width, KeyboardLimits.maxKeyWidthWeight)
                }
            }
        }
    }

    func testFallbackLayoutsAreAlwaysRenderable() {
        for layout in [KeyboardDefaults.starterLayout] + KeyboardDefaults.presets {
            let geometry = KeyboardMetrics.geometry(
                layout: layout,
                availableWidth: 390,
                availableHeight: 0,
                keySpacing: 6,
                rowSpacing: 10
            )
            XCTAssertFalse(geometry.isDrawnEmpty, layout.name)
            XCTAssertGreaterThan(geometry.keyCount, 0, layout.name)
            for row in geometry.rows {
                XCTAssertGreaterThan(row.height, 0)
            }
        }
    }

    func testStarterConfigurationIsSelfConsistent() {
        let configuration = KeyboardDefaults.starterConfiguration
        XCTAssertFalse(configuration.layouts.isEmpty)
        XCTAssertFalse(configuration.themes.isEmpty)
        XCTAssertEqual(configuration.activeLayoutID, configuration.layouts[0].id)
        XCTAssertTrue(configuration.layouts[0].containsNextKeyboardKey, "the fallback must include a way out")
    }

    func testBundledFallbackLayoutDecodesWhenPresent() {
        // In the test bundle the resource is not shipped, so this must simply
        // return nil rather than throwing or crashing.
        let bundle = Bundle(for: type(of: self))
        let layout = KeyboardDefaults.bundledFallbackLayout(bundle: bundle)
        XCTAssertNil(layout)
        XCTAssertFalse(KeyboardDefaults.fallbackConfiguration(bundle: bundle).layouts.isEmpty)
    }

    // MARK: - Engine resilience

    func testEngineSurvivesAConfigurationWithNoLayouts() {
        let configuration = KeyboardConfiguration(
            layouts: [],
            themes: [],
            activeLayoutID: UUID(),
            activeThemeID: UUID()
        )
        let proxy = InMemoryTextProxy()
        let engine = KeyboardEngine(configuration: configuration, proxy: proxy)
        XCTAssertFalse(engine.activeLayout.isEmpty, "the engine must fall back to a usable layout")
        _ = engine.perform(key: KeyboardKey(label: "a", action: .insertText("a")))
        XCTAssertEqual(proxy.text, "a")
        XCTAssertFalse(engine.renderLayout().rows.isEmpty)
    }

    func testTypingIntoAnEmptyDocumentIsSafe() {
        let proxy = InMemoryTextProxy()
        let engine = KeyboardEngine(configuration: KeyboardDefaults.configuration(), proxy: proxy)
        _ = engine.perform(action: .backspace)
        _ = engine.perform(action: .cursorLeft)
        _ = engine.perform(action: .cursorRight)
        XCTAssertEqual(proxy.text, "")
        XCTAssertEqual(proxy.caretIndex, 0)
    }

    func testVeryLongDocumentsStayBounded() {
        let proxy = InMemoryTextProxy()
        let engine = KeyboardEngine(configuration: KeyboardDefaults.configuration(), proxy: proxy)
        let macro = String(repeating: "x", count: 500)
        for _ in 0..<20 {
            _ = engine.perform(action: .insertMacro(macro))
        }
        XCTAssertLessThanOrEqual(proxy.text.count, InMemoryTextProxy.maximumLength)
    }

    func testRenderingALargeLayoutIsBoundedAndFinite() {
        let rows = (0..<KeyboardLimits.maxRows).map { _ in
            KeyboardRow(height: 1, keys: (0..<KeyboardLimits.maxKeysPerRow).map {
                KeyboardKey(label: "k\($0)", action: .insertText("k\($0)"))
            })
        }
        let layout = KeyboardLayout(name: "Huge", rows: rows)
        let geometry = KeyboardMetrics.geometry(
            layout: layout,
            availableWidth: 390,
            availableHeight: 291,
            keySpacing: 6,
            rowSpacing: 10
        )
        XCTAssertEqual(geometry.rows.count, KeyboardLimits.maxRows)
        XCTAssertTrue(geometry.isOverflowing)
        for row in geometry.rows {
            for key in row.keys {
                XCTAssertTrue(key.width.isFinite)
                XCTAssertGreaterThanOrEqual(key.width, 0)
            }
        }
    }
}

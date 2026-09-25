import XCTest
@testable import KeyraShared

final class KeyboardModelTests: XCTestCase {

    // MARK: - Colour

    func testHexColourParsing() {
        XCTAssertEqual(KeyboardColor(hex: "#000000")?.hexString, "#000000")
        XCTAssertEqual(KeyboardColor(hex: "FFFFFF")?.hexString, "#FFFFFF")
        XCTAssertEqual(KeyboardColor(hex: "#abc")?.hexString, "#AABBCC")
        XCTAssertEqual(KeyboardColor(hex: "#10203040")?.hexString, "#10203040")
        XCTAssertEqual(KeyboardColor(hex: "0x00FF00")?.hexString, "#00FF00")
        XCTAssertNil(KeyboardColor(hex: "not a colour"))
        XCTAssertNil(KeyboardColor(hex: "#12345"))
    }

    func testColourDecodingFallsBackInsteadOfThrowing() {
        let json = """
        {"background": "definitely-not-a-colour", "keyColor": "#123456"}
        """.data(using: .utf8)!
        let decoded = KeyboardJSON.decode(KeyboardTheme.self, from: json)
        XCTAssertNotNil(decoded, "a broken colour must not take the whole theme down")
        XCTAssertEqual(decoded?.keyColor.hexString, "#123456")
        XCTAssertEqual(decoded?.background, KeyboardColor.placeholder)
    }

    func testColourAcceptsComponentArrays() {
        let json = "{\"keyColor\": [1, 0, 0]}".data(using: .utf8)!
        let decoded = KeyboardJSON.decode(KeyboardTheme.self, from: json)
        XCTAssertEqual(decoded?.keyColor.red, 1.0)
        XCTAssertEqual(decoded?.keyColor.green, 0.0)
    }

    // MARK: - Actions

    func testActionEncodingShape() throws {
        let action = KeyboardKeyAction.insertText("π")
        let data = try KeyboardJSON.encoder().encode(action)
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("\"type\""), text)
        XCTAssertTrue(text.contains("insertText"), text)
        XCTAssertTrue(text.contains("\"text\""), text)
    }

    func testActionDecodingAcceptsDocumentedAliases() {
        let samples: [(String, KeyboardKeyAction)] = [
            (#"{"type": "insertText", "value": "example@email.com"}"#, .insertText("example@email.com")),
            (#"{"type": "text", "text": "hi"}"#, .insertText("hi")),
            (#"{"type": "macro", "value": "a\nb"}"#, .insertMacro("a\nb")),
            (#"{"type": "deleteBackward"}"#, .backspace),
            (#"{"type": "return"}"#, .newline),
            (#"{"type": "globe"}"#, .nextKeyboard),
            (#"{"type": "cursorMoveByOffset", "offset": -3}"#, .cursorMoveByOffset(-3)),
            (#"{"type": "switchLayout", "layoutName": "Symbols"}"#, .switchLayout(layoutID: nil, layoutName: "Symbols")),
            (#"{"type": "noop"}"#, .none)
        ]
        for (json, expected) in samples {
            let decoded = KeyboardJSON.decode(KeyboardKeyAction.self, from: json)
            XCTAssertEqual(decoded, expected, "failed for \(json)")
        }
    }

    func testUnknownActionTypeBecomesNoOp() {
        let decoded = KeyboardJSON.decode(KeyboardKeyAction.self, from: #"{"type": "teleport"}"#)
        XCTAssertEqual(decoded, KeyboardKeyAction.none)
        XCTAssertTrue(KeyboardKeyAction.none.isIncomplete == false)
    }

    func testMultiCharacterAndUnicodeTextSurvivesRoundTrip() throws {
        let payloads = ["->", "Hello, world!", "😀", "🔥🔥", "∑", "https://example.com",
                        "Hello,\n\nThanks for your message.\n\nKind regards,\nJoseph", "    "]
        for payload in payloads {
            let action = KeyboardKeyAction.insertMacro(payload)
            let data = try KeyboardJSON.encoder().encode(action)
            let restored = try KeyboardJSON.decoder().decode(KeyboardKeyAction.self, from: data)
            XCTAssertEqual(restored, action)
            XCTAssertEqual(restored.unshiftedText, payload, "whitespace must not be trimmed")
        }
    }

    func testCodingKeysAreHumanReadable() throws {
        let layout = KeyboardDefaults.qwerty()
        let data = try KeyboardJSON.encoder().encode(layout)
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("\"rows\""), "the exported JSON should be readable")
        XCTAssertTrue(text.contains("\"keys\""))
        XCTAssertTrue(text.contains("\"width\""))
    }

    // MARK: - Layout

    func testLayoutRoundTrip() throws {
        let original = KeyboardDefaults.math()
        let data = try KeyboardJSON.encoder().encode(original)
        let restored = try KeyboardJSON.decoder().decode(KeyboardLayout.self, from: data)
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.name, original.name)
        XCTAssertEqual(restored.rows.count, original.rows.count)
        XCTAssertEqual(restored.keyCount, original.keyCount)
        XCTAssertEqual(restored.rows[0].keys[0].label, original.rows[0].keys[0].label)
    }

    func testConfigurationRoundTrip() throws {
        let configuration = KeyboardDefaults.configuration()
        let data = try KeyboardJSON.encoder().encode(configuration)
        let restored = try KeyboardJSON.decoder().decode(KeyboardConfiguration.self, from: data)
        XCTAssertEqual(restored.layouts.count, configuration.layouts.count)
        XCTAssertEqual(restored.themes.count, configuration.themes.count)
        XCTAssertEqual(restored.settings, configuration.settings)
        XCTAssertEqual(restored.activeLayout.id, configuration.activeLayout.id)
        XCTAssertEqual(restored.activeTheme.id, configuration.activeTheme.id)
    }

    func testMissingFieldsAreFilledWithDefaults() {
        let json = """
        {
          "layouts": [ { "name": "Bare", "rows": [ { "keys": [ { "label": "a" } ] } ] } ]
        }
        """.data(using: .utf8)!
        let decoded = KeyboardJSON.decode(KeyboardConfiguration.self, from: json)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.layouts.count, 1)
        XCTAssertEqual(decoded?.layouts.first?.rows.first?.keys.first?.label, "a")
        XCTAssertEqual(decoded?.layouts.first?.rows.first?.keys.first?.width, 1)
        XCTAssertEqual(decoded?.settings.haptics, KeyboardSettings().haptics)
        XCTAssertFalse(decoded?.themes.isEmpty ?? true, "missing themes must fall back to the built-in ones")
    }

    func testNumericStringsAreAccepted() {
        let json = """
        {"name": "Numeric", "rows": [ {"height": "1.5", "keys": [ {"label": "x", "width": "2", "height": "1"} ]} ]}
        """.data(using: .utf8)!
        let layout = KeyboardJSON.decode(KeyboardLayout.self, from: json)
        XCTAssertEqual(layout?.rows.first?.height, 1.5)
        XCTAssertEqual(layout?.rows.first?.keys.first?.width, 2)
    }

    func testLayoutLookups() {
        let configuration = KeyboardDefaults.configuration()
        XCTAssertEqual(configuration.layout(withID: configuration.activeLayoutID)?.id, configuration.activeLayoutID)
        XCTAssertNotNil(configuration.layout(named: KeyboardDefaults.qwertyName))
        XCTAssertNotNil(configuration.layout(named: "  symbols  "), "name lookup should ignore case and whitespace")
        XCTAssertNil(configuration.layout(named: "Nope"))

        let active = configuration.activeLayout
        XCTAssertNotNil(configuration.layout(after: active.id))
    }

    func testKeyAndRowHelpers() {
        let layout = KeyboardDefaults.qwerty()
        let key = layout.allKeys.first { $0.action == .shift }
        XCTAssertNotNil(key)
        if let key {
            XCTAssertEqual(layout.rowID(containing: key.id), layout.rows[2].id)
            XCTAssertEqual(layout.key(withID: key.id)?.label, "⇧")
        }
        XCTAssertTrue(layout.containsNextKeyboardKey)
        XCTAssertFalse(layout.isEmpty)
    }

    func testSpokenLabelsAreUseful() {
        let letter = KeyboardKey(label: "a", action: .insertText("a"))
        XCTAssertEqual(letter.spokenLabel, "Letter a")

        let backspace = KeyboardKey(label: "⌫", action: .backspace)
        XCTAssertEqual(backspace.spokenLabel, "Backspace")

        let globe = KeyboardKey(label: "🌐", action: .nextKeyboard)
        XCTAssertEqual(globe.spokenLabel, "Next Keyboard")

        let arrow = KeyboardKey(label: "→", action: .insertText("→"))
        XCTAssertTrue(arrow.spokenLabel.contains("→"))

        let custom = KeyboardKey(label: "x", action: .insertText("x"), accessibilityLabel: "Insert times sign")
        XCTAssertEqual(custom.spokenLabel, "Insert times sign")
    }

    // MARK: - Themes

    func testBuiltInThemesAreDistinct() {
        let themes = KeyboardTheme.builtIn
        XCTAssertEqual(themes.count, 4)
        XCTAssertEqual(Set(themes.map { $0.id }).count, 4)
        XCTAssertTrue(themes.contains { $0.name == "Light" })
        XCTAssertTrue(themes.contains { $0.name == "Dark" })
        XCTAssertTrue(themes.contains { $0.name == "Purple" })
        XCTAssertTrue(themes.contains { $0.name == "Minimal" })
    }

    func testThemeDuplicateGetsANewIdentity() {
        let theme = KeyboardTheme.purple()
        let copy = theme.duplicated()
        XCTAssertNotEqual(copy.id, theme.id)
        XCTAssertEqual(copy.cornerRadius, theme.cornerRadius)
        XCTAssertTrue(copy.name.contains("Copy"))
    }
}

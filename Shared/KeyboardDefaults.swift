import Foundation

/// Every preset is *data*, produced by the same `KeyboardLayout` model the user
/// edits.  Nothing in the renderer knows what QWERTY is — swapping in a 12-row
/// layout requires no code change anywhere.
enum KeyboardDefaults {

    // MARK: - Presets

    static let qwertyName = "QWERTY"
    static let symbolsName = "Symbols"
    static let mathName = "Math"
    static let emojiName = "Emoji"
    static let codingName = "Coding"

    static let presets: [KeyboardLayout] = [qwerty(), symbols(), math(), emoji(), coding()]

    // MARK: - Fallback used when nothing else can be loaded

    /// A guaranteed-valid layout. If the shared container cannot be read, if the
    /// stored JSON is corrupt, or if the user deletes every layout, this is what
    /// the keyboard still renders — the keyboard must never be a blank rectangle.
    static let starterLayout: KeyboardLayout = KeyboardLayout.starter(named: "Starter")

    static let starterConfiguration: KeyboardConfiguration = {
        let layout = starterLayout
        let themes = KeyboardTheme.builtIn
        let themeID = themes.first?.id ?? UUID()
        return KeyboardConfiguration(
            layouts: [layout],
            themes: themes,
            activeLayoutID: layout.id,
            activeThemeID: themeID,
            settings: KeyboardSettings()
        )
    }()

    /// A complete, ready-to-use configuration containing all presets.
    static func configuration() -> KeyboardConfiguration {
        var layouts: [KeyboardLayout] = []
        var sawQWERTY = false
        for preset in presets {
            layouts.append(preset)
            if preset.name == qwertyName { sawQWERTY = true }
        }
        if !sawQWERTY, let first = layouts.first {
            layouts.insert(qwerty(), at: 0)
        }
        let themes = KeyboardTheme.builtIn
        return KeyboardConfiguration(
            layouts: layouts.isEmpty ? [starterLayout] : layouts,
            themes: themes.isEmpty ? [KeyboardTheme.defaultTheme] : themes,
            activeLayoutID: layouts.first?.id ?? starterLayout.id,
            activeThemeID: themes.first?.id ?? UUID(),
            settings: KeyboardSettings()
        )
    }

    // MARK: - Bundled JSON fallback

    static let bundledLayoutResourceName = "default-layouts"

    /// Decodes the small keyboard shipped inside the extension bundle.
    ///
    /// This is defence in depth: the compiled presets above are normally all the
    /// extension needs, but the same JSON import path the app uses is also
    /// exercised at runtime, so a broken build can still show a usable keyboard.
    static func bundledFallbackLayout(bundle: Bundle = .main) -> KeyboardLayout? {
        guard let url = bundle.url(forResource: bundledLayoutResourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let layout = JSONImportExport.decodeLooseLayout(from: data),
              !layout.isEmpty
        else {
            return nil
        }
        var scratch: [KeyboardIssue] = []
        return KeyboardValidator.sanitizeLayout(layout, issues: &scratch)
    }

    /// The configuration to use when nothing readable is available. Always
    /// returns something the keyboard can render.
    static func fallbackConfiguration(bundle: Bundle = .main) -> KeyboardConfiguration {
        let compiled = configuration()
        if compiled.layouts.contains(where: { !$0.isEmpty }) {
            return compiled
        }
        if let layout = bundledFallbackLayout(bundle: bundle) {
            var configuration = compiled
            configuration.layouts = [layout]
            configuration.activeLayoutID = layout.id
            return KeyboardValidator.sanitize(configuration).configuration
        }
        return starterConfiguration
    }

    // MARK: - Starter content for the editor

    /// Templates offered by the key editor so users do not have to type long
    /// snippets by hand.  These are pure data; nothing is hardcoded in the UI.
    static let macroTemplates: [(name: String, text: String)] = [
        ("Email address", "example@email.com"),
        ("Website", "https://example.com"),
        ("Arrow", "->"),
        ("Fat arrow", "=>"),
        ("Comparison", "=="),
        ("Function call", "print()"),
        ("Code block", "{\n    \n}"),
        ("Signature", "Hello,\n\nThanks for your message.\n\nKind regards,\nJoseph"),
        ("One indent", "    ")
    ]

    /// Characters offered by the editor's quick-pick strip (grouped, pure data).
    static let quickCharacters: [(name: String, characters: [String])] = [
        ("Arrows", ["←", "↑", "→", "↓", "↔", "⇐", "⇒", "⇑", "⇓", "⇔"]),
        ("Math", ["π", "∑", "√", "∫", "∞", "≠", "≤", "≥", "±", "≈", "∆", "×", "÷", "μ", "θ"]),
        ("Symbols", ["★", "☆", "♥", "♡", "✓", "✗", "•", "…", "—", "«", "»", "©", "®", "™"]),
        ("Emoji", ["😀", "😭", "🔥", "👍", "🙏", "🎉", "❤️", "✨", "🤔", "😎"]),
        ("Accents", ["é", "è", "ê", "ë", "á", "à", "ä", "â", "ñ", "ü", "ö", "ç", "ø", "å"]),
        ("Keys", ["⌘", "⌥", "⌃", "⇧", "⇪", "⌫", "⌦", "⏎", "⎋", "⇥", "␠"])
    ]

    // MARK: - Builders

    static func text(
        _ label: String,
        _ output: String? = nil,
        shift: String? = nil,
        width: Double = 1,
        special: Bool = false,
        accessibility: String? = nil,
        longPress: [KeyboardKeyLongPress] = [],
        repeats: Bool = false
    ) -> KeyboardKey {
        KeyboardKey(
            label: label,
            action: .insertText(output ?? label),
            shiftOutput: shift,
            width: width,
            isSpecial: special,
            longPress: longPress,
            repeatsWhenHeld: repeats,
            accessibilityLabel: accessibility
        )
    }

    static func letter(_ character: String, accents: [String] = []) -> KeyboardKey {
        KeyboardKey(
            label: character,
            action: .insertText(character),
            shiftOutput: character.uppercased(),
            longPress: accents.map { KeyboardKeyLongPress(label: $0, action: .insertText($0)) }
        )
    }

    static func letters(_ characters: String, accents: [String: [String]] = [:]) -> [KeyboardKey] {
        characters.map { character in
            let text = String(character)
            return letter(text, accents: accents[text] ?? [])
        }
    }

    static func alternates(_ pairs: [(String, String)]) -> [KeyboardKeyLongPress] {
        pairs.map { KeyboardKeyLongPress(label: $0.0, action: .insertText($0.1)) }
    }

    // MARK: - QWERTY

    static func qwerty() -> KeyboardLayout {
        let topRow = letters("qwertyuiop")
        let homeRow = letters("asdfghjkl", accents: [
            "a": ["á", "à", "ä", "â", "ã"],
            "s": ["ß", "$"]
        ])
        let bottomRow: [KeyboardKey] = [
            KeyboardKey(
                label: "⇧",
                action: .shift,
                width: 1.5,
                isSpecial: true,
                accessibilityLabel: "Shift"
            )
        ] + letters("zxcvbnm", accents: ["e": ["é", "è", "ê", "ë"], "n": ["ñ"]]) + [
            KeyboardKey(
                label: "⌫",
                action: .backspace,
                width: 1.5,
                isSpecial: true,
                repeatsWhenHeld: true,
                accessibilityLabel: "Backspace"
            )
        ]

        let utilityRow: [KeyboardKey] = [
            KeyboardKey(
                label: "?123",
                action: .switchLayout(layoutID: nil, layoutName: symbolsName),
                width: 1.6,
                isSpecial: true,
                accessibilityLabel: "Numbers and symbols keyboard"
            ),
            KeyboardKey(
                label: "🌐",
                action: .nextKeyboard,
                width: 1.1,
                isSpecial: true,
                accessibilityLabel: "Next Keyboard"
            ),
            KeyboardKey(
                label: "space",
                action: .space,
                width: 4.4,
                isSpecial: true,
                longPress: [
                    KeyboardKeyLongPress(label: "Tab", action: .insertText("\t")),
                    KeyboardKeyLongPress(label: "→", action: .cursorMoveByOffset(1)),
                    KeyboardKeyLongPress(label: "←", action: .cursorMoveByOffset(-1))
                ],
                accessibilityLabel: "Space"
            ),
            KeyboardKey(
                label: "return",
                action: .newline,
                width: 1.9,
                isSpecial: true,
                accessibilityLabel: "Return"
            )
        ]

        return KeyboardLayout(
            name: qwertyName,
            rows: [
                KeyboardRow(name: "Top row", height: 1, keys: topRow),
                KeyboardRow(name: "Home row", height: 1, keys: homeRow),
                KeyboardRow(name: "Bottom row", height: 1, keys: bottomRow),
                KeyboardRow(name: "Bottom bar", height: 1.15, keys: utilityRow)
            ],
            notes: "Double-tap ⇧ for Caps Lock. Long-press a letter for accents, long-press space for Tab."
        )
    }

    // MARK: - Symbols

    static func symbols() -> KeyboardLayout {
        func symbolRow(_ characters: [String]) -> KeyboardRow {
            KeyboardRow(height: 1, keys: characters.map { KeyboardKey(label: $0, action: .insertText($0)) })
        }

        let numberRow = KeyboardRow(height: 1, keys: [
            KeyboardKey(label: "1", action: .insertText("1")),
            KeyboardKey(label: "2", action: .insertText("2")),
            KeyboardKey(label: "3", action: .insertText("3")),
            KeyboardKey(label: "4", action: .insertText("4")),
            KeyboardKey(label: "5", action: .insertText("5")),
            KeyboardKey(label: "6", action: .insertText("6")),
            KeyboardKey(label: "7", action: .insertText("7")),
            KeyboardKey(label: "8", action: .insertText("8")),
            KeyboardKey(label: "9", action: .insertText("9")),
            KeyboardKey(label: "0", action: .insertText("0"))
        ])

        let punctuationRow = KeyboardRow(height: 1, keys: [
            KeyboardKey(label: "-", action: .insertText("-"), longPress: alternates([("—", "—"), ("–", "–"), ("•", "•")])),
            KeyboardKey(label: "_", action: .insertText("_")),
            KeyboardKey(label: "=", action: .insertText("="), longPress: alternates([("≠", "≠"), ("≈", "≈")])),
            KeyboardKey(label: "+", action: .insertText("+")),
            KeyboardKey(label: "[", action: .insertText("[")),
            KeyboardKey(label: "]", action: .insertText("]")),
            KeyboardKey(label: "{", action: .insertText("{")),
            KeyboardKey(label: "}", action: .insertText("}")),
            KeyboardKey(label: "|", action: .insertText("|")),
            KeyboardKey(label: "\\", action: .insertText("\\"))
        ])

        let quoteRow = KeyboardRow(height: 1, keys: [
            KeyboardKey(label: "\"", action: .insertText("\""), longPress: alternates([("“", "“"), ("”", "”")])),
            KeyboardKey(label: "'", action: .insertText("'"), longPress: alternates([("’", "’"), ("‘", "‘")])),
            KeyboardKey(label: ";", action: .insertText(";")),
            KeyboardKey(label: ":", action: .insertText(":")),
            KeyboardKey(label: ",", action: .insertText(",")),
            KeyboardKey(label: ".", action: .insertText("."), longPress: alternates([(".com", ".com"), (".org", ".org"), (".net", ".net"), ("…", "…")])),
            KeyboardKey(label: "?", action: .insertText("?")),
            KeyboardKey(label: "/", action: .insertText("/")),
            KeyboardKey(label: "&", action: .insertText("&")),
            KeyboardKey(label: "*", action: .insertText("*"))
        ])

        let utilityRow = KeyboardRow(height: 1.15, keys: [
            KeyboardKey(label: "ABC", action: .switchLayout(layoutID: nil, layoutName: qwertyName), width: 1.8, isSpecial: true, accessibilityLabel: "Letters keyboard"),
            KeyboardKey(label: "#+=", action: .switchLayout(layoutID: nil, layoutName: mathName), width: 1.4, isSpecial: true, accessibilityLabel: "Math keyboard"),
            KeyboardKey(label: "space", action: .space, width: 3.6, isSpecial: true, accessibilityLabel: "Space"),
            KeyboardKey(label: "⌫", action: .backspace, width: 1.6, isSpecial: true, repeatsWhenHeld: true, accessibilityLabel: "Backspace")
        ])

        return KeyboardLayout(
            name: symbolsName,
            rows: [numberRow, symbolRow(["!", "@", "#", "$", "%", "^", "&", "*", "(", ")"]), punctuationRow, quoteRow, utilityRow],
            notes: "Long-press . for .com / .org / .net, long-press - for an em dash."
        )
    }

    // MARK: - Math

    static func math() -> KeyboardLayout {
        func key(_ label: String, _ output: String? = nil, width: Double = 1, special: Bool = false, accessibility: String? = nil, longPress: [KeyboardKeyLongPress] = []) -> KeyboardKey {
            KeyboardKey(label: label, action: .insertText(output ?? label), width: width, isSpecial: special, longPress: longPress, accessibilityLabel: accessibility)
        }

        let constants = KeyboardRow(height: 1, keys: [
            key("π"), key("∞"), key("∑"), key("√"), key("∫"),
            key("∆"), key("θ"), key("μ"), key("φ"), key("λ")
        ])
        let operators = KeyboardRow(height: 1, keys: [
            key("+"), key("−"), key("×"), key("÷"), key("≠", longPress: alternates([("≡", "≡")])),
            key("≤", longPress: alternates([("≥", "≥")])), key("≥"), key("≈"), key("±"), key("%")
        ])
        let arrows = KeyboardRow(height: 1, keys: [
            key("←", accessibility: "Insert arrow left"),
            key("→", accessibility: "Insert arrow right"),
            key("↑", accessibility: "Insert arrow up"),
            key("↓", accessibility: "Insert arrow down"),
            key("↔", accessibility: "Insert arrow left right"),
            key("⇐"), key("⇒"), key("⇑"), key("⇓"), key("⇔")
        ])
        let caretRow = KeyboardRow(height: 1, keys: [
            KeyboardKey(
                label: "◀",
                action: .cursorLeft,
                width: 1.3,
                isSpecial: true,
                repeatsWhenHeld: true,
                accessibilityLabel: "Move cursor left"
            ),
            KeyboardKey(
                label: "▶",
                action: .cursorRight,
                width: 1.3,
                isSpecial: true,
                repeatsWhenHeld: true,
                accessibilityLabel: "Move cursor right"
            ),
            KeyboardKey(label: "(", action: .insertText("("), width: 1),
            KeyboardKey(label: ")", action: .insertText(")"), width: 1),
            KeyboardKey(label: "=", action: .insertText("="), width: 1, longPress: alternates([("≠", "≠"), ("==", "==")])),
            KeyboardKey(label: "<", action: .insertText("<"), width: 1),
            KeyboardKey(label: ">", action: .insertText(">"), width: 1),
            KeyboardKey(label: ",", action: .insertText(","), width: 1),
            KeyboardKey(label: "space", action: .space, width: 2, isSpecial: true, accessibilityLabel: "Space"),
            KeyboardKey(label: "⌫", action: .backspace, width: 1.4, isSpecial: true, repeatsWhenHeld: true, accessibilityLabel: "Backspace"),
            KeyboardKey(label: "ABC", action: .switchLayout(layoutID: nil, layoutName: qwertyName), width: 1.6, isSpecial: true, accessibilityLabel: "Letters keyboard")
        ])
        let macroRow = KeyboardRow(height: 1, keys: [
            KeyboardKey(label: "x²", action: .insertText("²"), width: 1),
            KeyboardKey(label: "x³", action: .insertText("³"), width: 1),
            KeyboardKey(label: "∑(n)", action: .insertMacro("∑(n=1..N) "), width: 1.6, isSpecial: true, accessibilityLabel: "Insert summation macro"),
            KeyboardKey(label: "equation", action: .insertMacro("f(x) = "), width: 1.8, isSpecial: true, accessibilityLabel: "Insert function macro"),
            KeyboardKey(label: "return", action: .newline, width: 1.4, isSpecial: true, accessibilityLabel: "Return")
        ])

        return KeyboardLayout(
            name: mathName,
            rows: [constants, operators, arrows, caretRow, macroRow],
            notes: "◀ / ▶ move the text caret. ← → ↑ ↓ type arrow characters. Two different things, two different keys."
        )
    }

    // MARK: - Emoji

    static func emoji() -> KeyboardLayout {
        func emojiRow(_ characters: [String]) -> KeyboardRow {
            KeyboardRow(height: 1, keys: characters.map { character in
                KeyboardKey(label: character, action: .insertText(character), accessibilityLabel: nil)
            })
        }

        let utilityRow = KeyboardRow(height: 1.15, keys: [
            KeyboardKey(label: "ABC", action: .switchLayout(layoutID: nil, layoutName: qwertyName), width: 1.8, isSpecial: true, accessibilityLabel: "Letters keyboard"),
            KeyboardKey(label: "SYM", action: .switchLayout(layoutID: nil, layoutName: symbolsName), width: 1.4, isSpecial: true, accessibilityLabel: "Symbols keyboard"),
            KeyboardKey(label: "space", action: .space, width: 3.4, isSpecial: true, accessibilityLabel: "Space"),
            KeyboardKey(label: "⌫", action: .backspace, width: 1.6, isSpecial: true, repeatsWhenHeld: true, accessibilityLabel: "Backspace")
        ])

        return KeyboardLayout(
            name: emojiName,
            rows: [
                emojiRow(["😀", "😭", "🔥", "👍", "🙏", "🎉", "❤️", "✨"]),
                emojiRow(["😂", "😅", "🤔", "😎", "🥳", "😴", "🤯", "👀"]),
                emojiRow(["😊", "😉", "😇", "🤝", "💪", "🌟", "🌈", "☀️"]),
                KeyboardRow(height: 1, keys: [
                    KeyboardKey(label: "★", action: .insertText("★"), longPress: alternates([("☆", "☆")])),
                    KeyboardKey(label: "♥", action: .insertText("♥"), longPress: alternates([("♡", "♡")])),
                    KeyboardKey(label: "✓", action: .insertText("✓"), longPress: alternates([("✗", "✗")])),
                    KeyboardKey(label: "∞", action: .insertText("∞")),
                    KeyboardKey(label: "→", action: .insertText("→")),
                    KeyboardKey(label: "~", action: .insertText("~")),
                    KeyboardKey(label: "@", action: .insertText("@")),
                    KeyboardKey(label: "#", action: .insertText("#"))
                ]),
                utilityRow
            ],
            notes: "Emoji and dingbats are ordinary insert-text keys — add as many rows as you like."
        )
    }

    // MARK: - Coding

    static func coding() -> KeyboardLayout {
        func codeKey(_ label: String, _ output: String? = nil, width: Double = 1, special: Bool = false, accessibility: String? = nil, longPress: [KeyboardKeyLongPress] = []) -> KeyboardKey {
            KeyboardKey(label: label, action: .insertText(output ?? label), width: width, isSpecial: special, longPress: longPress, accessibilityLabel: accessibility)
        }

        let brackets = KeyboardRow(height: 1, keys: [
            codeKey("{"), codeKey("}"), codeKey("["), codeKey("]"), codeKey("("), codeKey(")"),
            codeKey("<"), codeKey(">"), codeKey("|"), codeKey("\\")
        ])
        let operators = KeyboardRow(height: 1, keys: [
            codeKey("=>"), codeKey("=="), codeKey("==="), codeKey("!="), codeKey("&&"), codeKey("||"),
            codeKey("!"), codeKey("??"), codeKey("?."), codeKey("...")
        ])
        let punctuation = KeyboardRow(height: 1, keys: [
            codeKey("::"), codeKey(";"), codeKey(","), codeKey(".", longPress: alternates([(".com", ".com"), (".swift", ".swift")])),
            codeKey("\""), codeKey("'"), codeKey("`"), codeKey("_"), codeKey("$"), codeKey("@")
        ])
        let macros = KeyboardRow(height: 1, keys: [
            KeyboardKey(label: "func", action: .insertMacro("func name() {\n    \n}"), width: 1.5, isSpecial: true, accessibilityLabel: "Insert function macro"),
            KeyboardKey(label: "print()", action: .insertMacro("print()"), width: 1.8, isSpecial: true, accessibilityLabel: "Insert print macro"),
            KeyboardKey(label: "url", action: .insertMacro("https://example.com"), width: 1.4, isSpecial: true, accessibilityLabel: "Insert URL macro"),
            KeyboardKey(label: "email", action: .insertMacro("example@email.com"), width: 1.6, isSpecial: true, accessibilityLabel: "Insert email macro"),
            KeyboardKey(label: "sig", action: .insertMacro("Hello,\n\nThanks for your message.\n\nKind regards,\nJoseph"), width: 1.4, isSpecial: true, accessibilityLabel: "Insert signature macro")
        ])
        let utilityRow = KeyboardRow(height: 1.15, keys: [
            KeyboardKey(label: "ABC", action: .switchLayout(layoutID: nil, layoutName: qwertyName), width: 1.6, isSpecial: true, accessibilityLabel: "Letters keyboard"),
            KeyboardKey(label: "#+=", action: .switchLayout(layoutID: nil, layoutName: symbolsName), width: 1.4, isSpecial: true, accessibilityLabel: "Symbols keyboard"),
            KeyboardKey(label: "tab", action: .insertText("    "), width: 1.3, isSpecial: true, accessibilityLabel: "Insert four spaces"),
            KeyboardKey(label: "space", action: .space, width: 3, isSpecial: true, accessibilityLabel: "Space"),
            KeyboardKey(label: "⏎", action: .newline, width: 1.4, isSpecial: true, accessibilityLabel: "Return"),
            KeyboardKey(label: "⌫", action: .backspace, width: 1.5, isSpecial: true, repeatsWhenHeld: true, accessibilityLabel: "Backspace")
        ])

        return KeyboardLayout(
            name: codingName,
            rows: [brackets, operators, punctuation, macros, utilityRow],
            notes: "Macro keys type multi-line snippets, including this signature: see the “sig” key."
        )
    }
}

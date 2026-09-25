import XCTest
@testable import KeyraShared

final class KeyboardEngineTests: XCTestCase {

    private func makeEngine(
        _ configuration: KeyboardConfiguration = KeyboardDefaults.configuration(),
        proxy: InMemoryTextProxy = InMemoryTextProxy(),
        clock: @escaping () -> TimeInterval = { 0 }
    ) -> (KeyboardEngine, InMemoryTextProxy) {
        let engine = KeyboardEngine(configuration: configuration, proxy: proxy, clock: clock)
        return (engine, proxy)
    }

    private func key(_ label: String, _ action: KeyboardKeyAction, shift: String? = nil, width: Double = 1, longPress: [KeyboardKeyLongPress] = [], repeats: Bool = false) -> KeyboardKey {
        KeyboardKey(label: label, action: action, shiftOutput: shift, width: width, isSpecial: false, longPress: longPress, repeatsWhenHeld: repeats)
    }

    // MARK: - Text insertion

    func testInsertText() {
        let (engine, proxy) = makeEngine()
        _ = engine.perform(key: key("a", .insertText("a")))
        XCTAssertEqual(proxy.text, "a")
    }

    func testInsertArbitraryUnicodeAndMultiCharacterStrings() {
        let (engine, proxy) = makeEngine()
        for value in ["→", "★", "😀", "->", "Hello, world!", "π", "≠"] {
            _ = engine.perform(key: key(value, .insertText(value)))
        }
        XCTAssertEqual(proxy.text, "→★😀->Hello, world!π≠")
    }

    func testMultilineMacroIsInsertedExactly() {
        let (engine, proxy) = makeEngine()
        let macro = "Hello,\n\nThanks for your message.\n\nKind regards,\nJoseph"
        _ = engine.perform(key: key("sig", .insertMacro(macro)))
        XCTAssertEqual(proxy.text, macro)
        XCTAssertEqual(proxy.text.filter { $0 == "\n" }.count, 4)
    }

    func testSpaceAndNewline() {
        let (engine, proxy) = makeEngine()
        _ = engine.perform(key: key("space", .space))
        _ = engine.perform(key: key("return", .newline))
        XCTAssertEqual(proxy.text, " \n")
    }

    func testBackspace() {
        let proxy = InMemoryTextProxy(text: "hello")
        let (engine, _) = makeEngine(proxy: proxy)
        _ = engine.perform(key: key("⌫", .backspace))
        XCTAssertEqual(proxy.text, "hell")

        for _ in 0..<10 { _ = engine.perform(key: key("⌫", .backspace)) }
        XCTAssertEqual(proxy.text, "", "backspace must never delete past the start of the document")
    }

    func testCaretMovement() {
        let proxy = InMemoryTextProxy(text: "abc")
        let (engine, _) = makeEngine(proxy: proxy)
        _ = engine.perform(action: .cursorLeft)
        XCTAssertEqual(proxy.caretIndex, 2)
        _ = engine.perform(action: .cursorRight)
        XCTAssertEqual(proxy.caretIndex, 3)
        _ = engine.perform(action: .cursorMoveByOffset(-2))
        XCTAssertEqual(proxy.caretIndex, 1)

        // Large requests are clamped rather than ignored silently.
        _ = engine.perform(action: .cursorMoveByOffset(5000))
        XCTAssertEqual(proxy.caretIndex, 3)
        _ = engine.perform(action: .cursorMoveByOffset(-5000))
        XCTAssertEqual(proxy.caretIndex, 0)
    }

    func testNextKeyboardEmitsTheSystemEffect() {
        let (engine, _) = makeEngine()
        let effects = engine.perform(key: key("🌐", .nextKeyboard))
        XCTAssertTrue(effects.contains(.nextInputMode),
                      "the globe key must call the public next-input-mode API, not fake it")
    }

    func testNoOpKeyDoesNothing() {
        let (engine, proxy) = makeEngine()
        let effects = engine.perform(key: key("•", .none))
        XCTAssertTrue(effects.isEmpty)
        XCTAssertEqual(proxy.text, "")
    }

    // MARK: - Shift

    func testShiftAppliesToExactlyOneCharacter() {
        let (engine, proxy) = makeEngine()
        _ = engine.toggleShift()
        XCTAssertEqual(engine.shiftState, .shift)
        _ = engine.perform(key: key("a", .insertText("a"), shift: "A"))
        XCTAssertEqual(proxy.text, "A")
        XCTAssertEqual(engine.shiftState, .off, "shift must be single-shot")

        _ = engine.perform(key: key("b", .insertText("b"), shift: "B"))
        XCTAssertEqual(proxy.text, "Ab")
    }

    func testCustomShiftOutputWinsOverAutomaticUppercasing() {
        let (engine, proxy) = makeEngine()
        _ = engine.toggleShift()
        _ = engine.perform(key: key("1", .insertText("1"), shift: "!"))
        XCTAssertEqual(proxy.text, "!")
    }

    func testAutomaticUppercasingOnlyAffectsSingleLowercaseLetters() {
        var settings = KeyboardSettings()
        settings.autoUppercaseOnShift = true
        var configuration = KeyboardDefaults.configuration()
        configuration.settings = settings
        let (engine, proxy) = makeEngine(configuration)

        _ = engine.toggleShift()
        _ = engine.perform(key: key("a", .insertText("a")))
        XCTAssertEqual(proxy.text, "A")

        _ = engine.toggleShift()
        _ = engine.perform(key: key("word", .insertText("word")))
        XCTAssertEqual(proxy.text, "Aword", "multi-character text must not be upper-cased blindly")
    }

    func testAutomaticUppercasingCanBeDisabled() {
        var settings = KeyboardSettings()
        settings.autoUppercaseOnShift = false
        var configuration = KeyboardDefaults.configuration()
        configuration.settings = settings
        let (engine, proxy) = makeEngine(configuration)

        _ = engine.toggleShift()
        _ = engine.perform(key: key("a", .insertText("a")))
        XCTAssertEqual(proxy.text, "a")
    }

    func testDoubleTapEnablesCapsLock() {
        let configuration = KeyboardDefaults.configuration()
        var settings = configuration.settings
        settings.doubleTapShiftEnablesCapsLock = true
        settings.doubleTapWindow = 0.35
        var configured = configuration
        configured.settings = settings

        let (engine, proxy) = makeEngine(configured, clock: { 10.0 })
        _ = engine.toggleShift()
        XCTAssertEqual(engine.shiftState, .shift)
        _ = engine.toggleShift()  // same timestamp: a double tap
        XCTAssertEqual(engine.shiftState, .capsLock)

        _ = engine.perform(key: key("a", .insertText("a"), shift: "A"))
        _ = engine.perform(key: key("b", .insertText("b"), shift: "B"))
        XCTAssertEqual(proxy.text, "AB", "caps lock must stay on")
        XCTAssertEqual(engine.shiftState, .capsLock)

        _ = engine.toggleShift()
        XCTAssertEqual(engine.shiftState, .off)
    }

    func testSlowSecondTapTurnsShiftOff() {
        var now = 100.0
        var configuration = KeyboardDefaults.configuration()
        configuration.settings.doubleTapWindow = 0.3
        let (engine, _) = makeEngine(configuration, clock: { now })
        _ = engine.toggleShift()
        now += 5.0
        _ = engine.toggleShift()
        XCTAssertEqual(engine.shiftState, .off)
    }

    func testCapsLockCanBeDisabled() {
        var configuration = KeyboardDefaults.configuration()
        configuration.settings.doubleTapShiftEnablesCapsLock = false
        let (engine, _) = makeEngine(configuration, clock: { 0 })
        _ = engine.toggleShift()
        _ = engine.toggleShift()
        XCTAssertNotEqual(engine.shiftState, .capsLock)
    }

    func testShiftIsNotConsumedByBackspaceOrCaretMovement() {
        let (engine, proxy) = makeEngine()
        proxy.insertText("abc")
        _ = engine.toggleShift()
        _ = engine.perform(key: key("⌫", .backspace))
        XCTAssertEqual(engine.shiftState, .shift, "backspace should keep Shift ready")
        _ = engine.perform(action: .cursorLeft)
        XCTAssertEqual(engine.shiftState, .shift)
    }

    func testShiftIsClearedWhenLeavingALayout() {
        var configuration = KeyboardDefaults.configuration()
        let second = KeyboardDefaults.symbols()
        configuration.layouts.append(second)
        let (engine, _) = makeEngine(configuration)
        _ = engine.toggleShift()
        _ = engine.toggleShift()  // caps lock
        _ = engine.activateLayout(id: second.id)
        XCTAssertEqual(engine.shiftState, .off, "switching layers must not leave caps lock stuck on")
    }

    // MARK: - Layout switching

    func testSwitchLayoutByName() {
        let configuration = KeyboardDefaults.configuration()
        let (engine, _) = makeEngine(configuration)
        let symbols = configuration.layout(named: KeyboardDefaults.symbolsName)
        XCTAssertNotNil(symbols)

        let effects = engine.perform(action: .switchLayout(layoutID: nil, layoutName: KeyboardDefaults.symbolsName))
        XCTAssertEqual(engine.activeLayout.name, KeyboardDefaults.symbolsName)
        XCTAssertTrue(effects.contains { if case .layoutChanged = $0 { return true } else { return false } })

        let back = engine.perform(action: .switchLayout(layoutID: nil, layoutName: KeyboardDefaults.qwertyName))
        XCTAssertEqual(engine.activeLayout.name, KeyboardDefaults.qwertyName)
        XCTAssertTrue(back.contains { if case .layoutChanged = $0 { return true } else { return false } })
    }

    func testSwitchLayoutByNameIsCaseInsensitive() {
        let (engine, _) = makeEngine()
        _ = engine.activateLayout(named: "sYmBoLs")
        XCTAssertEqual(engine.activeLayout.name, KeyboardDefaults.symbolsName)
    }

    func testSwitchLayoutToAMissingTargetIsReportedNotCrashed() {
        let (engine, _) = makeEngine()
        let effects = engine.perform(action: .switchLayout(layoutID: nil, layoutName: "Does Not Exist"))
        XCTAssertEqual(engine.activeLayout.name, KeyboardDefaults.qwertyName)
        XCTAssertTrue(effects.contains { if case .notice = $0 { return true } else { return false } })
    }

    func testCycleLayoutWrapsAround() {
        let configuration = KeyboardDefaults.configuration()
        let names = configuration.layouts.map { $0.name }
        let (engine, _) = makeEngine(configuration)
        XCTAssertEqual(engine.activeLayout.name, names[0])

        _ = engine.cycleLayout()
        XCTAssertEqual(engine.activeLayout.name, names[1])

        _ = engine.cycleLayout(forward: false)
        XCTAssertEqual(engine.activeLayout.name, names[0])

        _ = engine.cycleLayout(forward: false)
        XCTAssertEqual(engine.activeLayout.name, names[names.count - 1], "cycling backwards must wrap around")

        var visited: Set<String> = [engine.activeLayout.name]
        for _ in 1..<names.count {
            _ = engine.cycleLayout()
            visited.insert(engine.activeLayout.name)
        }
        XCTAssertEqual(visited.count, names.count, "every stored layout should be reachable by cycling")
    }

    func testSwitchingIntoALayoutThatDisappearedIsSafe() {
        let configuration = KeyboardDefaults.configuration()
        let (engine, _) = makeEngine(configuration)
        let missing = UUID()
        let effects = engine.activateLayout(id: missing)
        XCTAssertTrue(effects.contains { if case .notice = $0 { return true } else { return false } })
        XCTAssertEqual(engine.activeLayout.name, KeyboardDefaults.qwertyName)
    }

    func testApplyingANewConfigurationKeepsTheCurrentLayer() {
        let configuration = KeyboardDefaults.configuration()
        let (engine, _) = makeEngine(configuration)
        _ = engine.activateLayout(named: KeyboardDefaults.emojiName)
        XCTAssertEqual(engine.activeLayout.name, KeyboardDefaults.emojiName)

        var edited = configuration
        if let index = edited.layouts.firstIndex(where: { $0.name == KeyboardDefaults.emojiName }) {
            edited.layouts[index].rows[0].keys[0].label = "CHANGED"
        }
        _ = engine.apply(configuration: edited)
        XCTAssertEqual(engine.activeLayout.name, KeyboardDefaults.emojiName)
        XCTAssertEqual(engine.activeLayout.rows[0].keys[0].label, "CHANGED")
    }

    func testApplyingAConfigurationWithoutTheActiveLayerFallsBack() {
        let configuration = KeyboardDefaults.configuration()
        let (engine, _) = makeEngine(configuration)
        _ = engine.activateLayout(named: KeyboardDefaults.mathName)

        var trimmed = KeyboardDefaults.configuration()
        trimmed.layouts = [trimmed.layouts[0]]
        trimmed.activeLayoutID = trimmed.layouts[0].id
        let effects = engine.apply(configuration: trimmed)
        XCTAssertEqual(engine.activeLayout.id, trimmed.layouts[0].id)
        XCTAssertTrue(effects.contains { if case .layoutChanged = $0 { return true } else { return false } })
    }

    // MARK: - Globe key safety net

    func testGlobeKeyIsAddedAtRuntimeWhenNeeded() {
        var layout = KeyboardLayout(name: "No Globe", rows: [
            KeyboardRow(height: 1, keys: [key("a", .insertText("a"))])
        ])
        layout.rows[0].keys.append(key("space", .space, width: 3))
        let configuration = KeyboardConfiguration(
            layouts: [layout],
            themes: KeyboardTheme.builtIn,
            activeLayoutID: layout.id,
            activeThemeID: KeyboardTheme.builtIn[0].id
        )
        let proxy = InMemoryTextProxy(needsInputModeSwitchKey: true)
        let engine = KeyboardEngine(configuration: configuration, proxy: proxy)

        let rendered = engine.renderLayout()
        XCTAssertTrue(rendered.containsNextKeyboardKey, "a globe key must appear so the user is never trapped")

        // The saved layout itself must be untouched.
        XCTAssertFalse(engine.activeLayout.containsNextKeyboardKey)
        XCTAssertEqual(engine.activeLayout.rows[0].keys.count, 2)
        XCTAssertEqual(rendered.rows[0].keys.count, 3)
    }

    func testGlobeKeyIsNotAddedWhenNotNeededOrDisabled() {
        var layout = KeyboardLayout(name: "No Globe", rows: [
            KeyboardRow(height: 1, keys: [key("a", .insertText("a"))])
        ])
        layout.rows[0].keys.append(key("space", .space, width: 3))
        var configuration = KeyboardConfiguration(
            layouts: [layout],
            themes: KeyboardTheme.builtIn,
            activeLayoutID: layout.id,
            activeThemeID: KeyboardTheme.builtIn[0].id
        )

        let needsIt = InMemoryTextProxy(needsInputModeSwitchKey: true)
        XCTAssertTrue(KeyboardEngine(configuration: configuration, proxy: needsIt).renderLayout().containsNextKeyboardKey)

        let doesNotNeedIt = InMemoryTextProxy(needsInputModeSwitchKey: false)
        XCTAssertFalse(KeyboardEngine(configuration: configuration, proxy: doesNotNeedIt).renderLayout().containsNextKeyboardKey)

        configuration.settings.autoInsertNextKeyboardKey = false
        XCTAssertFalse(KeyboardEngine(configuration: configuration, proxy: needsIt).renderLayout().containsNextKeyboardKey)
    }

    // MARK: - Feedback

    func testHapticsAndSoundAreOnlyEmittedWhenEnabled() {
        var configuration = KeyboardDefaults.configuration()
        configuration.settings.haptics = .off
        configuration.settings.keyClickSound = false
        let (silent, _) = makeEngine(configuration)
        XCTAssertTrue(silent.perform(key: key("a", .insertText("a"))).isEmpty)

        configuration.settings.haptics = .medium
        configuration.settings.keyClickSound = true
        let (loud, _) = makeEngine(configuration)
        let effects = loud.perform(key: key("a", .insertText("a")))
        XCTAssertTrue(effects.contains(.haptic))
        XCTAssertTrue(effects.contains(.keyClick))
    }

    // MARK: - Press timing (tap, long press, repeat)

    func testTapPerformsThePrimaryActionOnRelease() {
        var interaction = PressInteraction.began(key: key("a", .insertText("a")), at: 0, settings: KeyboardSettings())
        XCTAssertTrue(interaction.pressed().isEmpty, "ordinary keys must not fire on touch-down")
        XCTAssertTrue(interaction.advance(to: 0.2).isEmpty)
        XCTAssertEqual(interaction.release(at: 0.25), [.performPrimary])
    }

    func testHoldingAKeyWithAlternatesShowsThePopupInsteadOfTyping() {
        let alternates = [
            KeyboardKeyLongPress(label: "é", action: .insertText("é")),
            KeyboardKeyLongPress(label: "è", action: .insertText("è"))
        ]
        let letter = key("e", .insertText("e"), longPress: alternates)
        var interaction = PressInteraction.began(key: letter, at: 0, settings: KeyboardSettings())
        _ = interaction.pressed()
        let atHold = interaction.advance(to: 0.5)
        XCTAssertEqual(atHold, [.showAlternates])
        XCTAssertTrue(interaction.alternatesShown)
        XCTAssertEqual(interaction.release(at: 0.7), [.hideAlternates], "a long press must not also type the key")
    }

    func testLongPressIsDisabledWhenConfiguredOff() {
        var settings = KeyboardSettings()
        settings.longPressEnabled = false
        var interaction = PressInteraction.began(
            key: key("e", .insertText("e"), longPress: [KeyboardKeyLongPress(label: "é", action: .insertText("é"))]),
            at: 0,
            settings: settings
        )
        XCTAssertFalse(interaction.allowsAlternates)
        XCTAssertTrue(interaction.advance(to: 2.0).isEmpty)
        XCTAssertEqual(interaction.release(at: 2.1), [.performPrimary])
    }

    func testBackspaceStartsImmediatelyAndRepeatsWhileHeld() {
        var settings = KeyboardSettings()
        settings.backspaceRepeatDelay = 0.4
        settings.backspaceRepeatInterval = 0.1
        let backspace = key("⌫", .backspace, repeats: true)

        var interaction = PressInteraction.began(key: backspace, at: 0, settings: settings)
        XCTAssertEqual(interaction.pressed(), [.performPrimary], "backspace should delete the moment it is pressed")

        XCTAssertTrue(interaction.advance(to: 0.2).isEmpty, "no repeat before the delay")
        XCTAssertTrue(interaction.advance(to: 0.45).contains(.repeatPrimary))
        XCTAssertTrue(interaction.advance(to: 0.55).contains(.repeatPrimary))

        // A long stall must not produce an unbounded burst of deletions.
        let burst = interaction.advance(to: 30.0)
        XCTAssertLessThanOrEqual(burst.count, 3)

        XCTAssertEqual(interaction.release(at: 31.0), [], "releasing must stop, not fire one more deletion")
    }

    func testRepeatingIsDisabledWhenConfiguredOff() {
        var settings = KeyboardSettings()
        settings.backspaceRepeatEnabled = false
        var interaction = PressInteraction.began(key: key("⌫", .backspace, repeats: true), at: 0, settings: settings)
        XCTAssertTrue(interaction.pressed().isEmpty)
        XCTAssertTrue(interaction.advance(to: 5.0).isEmpty)
        XCTAssertEqual(interaction.release(at: 5.0), [.performPrimary])
    }

    func testRepeatStopsWhenTheFingerLifts() {
        let proxy = InMemoryTextProxy(text: "0123456789")
        let engine = KeyboardEngine(configuration: KeyboardDefaults.configuration(), proxy: proxy)
        var settings = KeyboardSettings()
        settings.backspaceRepeatDelay = 0.2
        settings.backspaceRepeatInterval = 0.05
        let backspace = key("⌫", .backspace, repeats: true)

        var interaction = PressInteraction.began(key: backspace, at: 0, settings: settings)
        for event in interaction.pressed() where event == .performPrimary {
            _ = engine.perform(key: backspace)
        }
        for _ in 0..<6 {
            for event in interaction.advance(to: Double.random(in: 0.22...0.3)) where event == .repeatPrimary {
                _ = engine.perform(key: backspace)
            }
        }
        _ = interaction.release(at: 1.0)
        let lengthAfterRelease = proxy.text.count
        XCTAssertLessThan(lengthAfterRelease, 10)
    }
}

import Foundation

/// Shift is a three-state machine, not a boolean.
enum ShiftState: String, Codable, Equatable, CaseIterable {
    case off
    case shift
    case capsLock

    var isActive: Bool { self != .off }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .shift: return "Shift"
        case .capsLock: return "Caps Lock"
        }
    }
}

/// Things the engine asks the *host* (the view controller or the preview) to do,
/// because they need UIKit and cannot live in the pure engine.
enum KeyboardEffect: Equatable {
    /// Call `advanceToNextInputMode()` on the input view controller.
    case nextInputMode
    /// Play the configured haptic.
    case haptic
    /// Play the standard keyboard click (only when enabled).
    case keyClick
    /// The active layout changed; the renderer must rebuild.
    case layoutChanged(UUID)
    /// Configuration was replaced (e.g. the host app saved while we were open).
    case configurationReloaded
    /// Non-fatal message for the keyboard's status strip (e.g. missing layout).
    case notice(String)
}

/// Executes key actions against a text proxy and owns the Shift state.
///
/// Pure Foundation: no UIKit, no SwiftUI, no disk access. The same code path runs
/// in the extension, in the host app preview and in the unit tests.
final class KeyboardEngine {

    private(set) var configuration: KeyboardConfiguration
    private(set) var activeLayoutID: UUID
    private(set) var shiftState: ShiftState = .off

    let proxy: KeyboardTextProxy

    /// Injected clock so tests can control timing deterministically.
    private let clock: () -> TimeInterval
    private var lastShiftTapTime: TimeInterval = -1

    init(
        configuration: KeyboardConfiguration,
        proxy: KeyboardTextProxy,
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.configuration = configuration
        self.proxy = proxy
        self.clock = clock
        if configuration.layout(withID: configuration.activeLayoutID) != nil {
            self.activeLayoutID = configuration.activeLayoutID
        } else {
            self.activeLayoutID = configuration.layouts.first?.id ?? KeyboardDefaults.starterLayout.id
        }
    }

    // MARK: - State

    var settings: KeyboardSettings { configuration.settings }

    var activeLayout: KeyboardLayout {
        configuration.layout(withID: activeLayoutID) ?? configuration.layouts.first ?? KeyboardDefaults.starterLayout
    }

    var activeTheme: KeyboardTheme {
        configuration.theme(withID: configuration.activeThemeID) ?? KeyboardTheme.defaultTheme
    }

    var activeLayoutName: String { activeLayout.name }

    var isCapsLockEnabled: Bool { shiftState == .capsLock }

    /// Replaces the configuration (e.g. after the host app saved new content).
    /// The user's current layer is preserved when it still exists.
    @discardableResult
    func apply(configuration newConfiguration: KeyboardConfiguration) -> [KeyboardEffect] {
        configuration = newConfiguration
        var effects: [KeyboardEffect] = [.configurationReloaded]
        if newConfiguration.layout(withID: activeLayoutID) == nil {
            let fallback = newConfiguration.layouts.first?.id ?? KeyboardDefaults.starterLayout.id
            activeLayoutID = fallback
            effects.append(.layoutChanged(fallback))
        }
        return effects
    }

    // MARK: - Layout switching

    @discardableResult
    func activateLayout(id: UUID) -> [KeyboardEffect] {
        guard configuration.layout(withID: id) != nil else {
            return [.notice("That keyboard no longer exists.")]
        }
        guard id != activeLayoutID else { return [] }
        activeLayoutID = id
        // Leaving a layer must not leave Caps Lock or Shift stuck on.
        let shiftWasActive = shiftState.isActive
        shiftState = .off
        var effects: [KeyboardEffect] = [.layoutChanged(id)]
        if shiftWasActive { effects.append(contentsOf: feedbackEffects()) }
        return effects
    }

    @discardableResult
    func activateLayout(named name: String) -> [KeyboardEffect] {
        guard let layout = configuration.layout(named: name) else {
            return [.notice("No keyboard named “\(name)”.")]
        }
        return activateLayout(id: layout.id)
    }

    /// Cycles through stored layouts in order (used by "switch to next layer").
    @discardableResult
    func cycleLayout(forward: Bool = true) -> [KeyboardEffect] {
        guard !configuration.layouts.isEmpty else { return [] }
        guard let index = configuration.layouts.firstIndex(where: { $0.id == activeLayoutID }) else {
            let first = configuration.layouts[0].id
            return activateLayout(id: first)
        }
        let count = configuration.layouts.count
        let nextIndex = forward ? (index + 1) % count : (index - 1 + count) % count
        return activateLayout(id: configuration.layouts[nextIndex].id)
    }

    // MARK: - Shift

    /// Toggles Shift, using the clock to detect a double tap for Caps Lock.
    @discardableResult
    func toggleShift() -> [KeyboardEffect] {
        let now = clock()
        if shiftState == .off {
            lastShiftTapTime = now
            shiftState = .shift
        } else if shiftState == .shift {
            let isDoubleTap = lastShiftTapTime >= 0 && (now - lastShiftTapTime) <= settings.doubleTapWindow
            lastShiftTapTime = now
            if isDoubleTap, settings.doubleTapShiftEnablesCapsLock {
                shiftState = .capsLock
            } else if isDoubleTap {
                // Caps Lock disabled: a double tap behaves like a plain enable.
                shiftState = .shift
            } else {
                shiftState = .off
            }
        } else {
            lastShiftTapTime = now
            shiftState = .off
        }
        lastShiftTapTime = now
        return feedbackEffects()
    }

    func setShiftState(_ state: ShiftState) {
        shiftState = state
    }

    // MARK: - Performing actions

    /// Resolves and performs a key's action, applying Shift semantics.
    @discardableResult
    func perform(key: KeyboardKey) -> [KeyboardEffect] {
        switch key.action {
        case .shift:
            return toggleShift()
        case .none:
            return []
        default:
            break
        }

        if let insertion = key.insertion(forShiftState: shiftState, autoUppercase: settings.autoUppercaseOnShift) {
            // Space, newline, text and macros all funnel through insertText.
            return insert(insertion, consumesShift: true)
        }

        return perform(action: key.action)
    }

    /// Performs an action that is not a key press (layout switching, caret
    /// movement, backspace…). Shift is only consumed by text insertion.
    @discardableResult
    func perform(action: KeyboardKeyAction) -> [KeyboardEffect] {
        switch action {
        case .insertText(let text), .insertMacro(let text):
            return insert(text, consumesShift: true)

        case .space:
            return insert(" ", consumesShift: true)

        case .newline:
            return insert("\n", consumesShift: true)

        case .backspace:
            proxy.deleteBackward()
            return feedbackEffects()

        case .cursorLeft:
            proxy.adjustTextPosition(byCharacterOffset: -1)
            return feedbackEffects()

        case .cursorRight:
            proxy.adjustTextPosition(byCharacterOffset: 1)
            return feedbackEffects()

        case .cursorMoveByOffset(let offset):
            guard offset != 0 else { return [] }
            // iOS clamps large jumps; keep our request within a sane range.
            let bounded = max(-512, min(512, offset))
            proxy.adjustTextPosition(byCharacterOffset: bounded)
            return feedbackEffects()

        case .nextKeyboard:
            return [.nextInputMode] + feedbackEffects()

        case .shift:
            return toggleShift()

        case .switchLayout(let layoutID, let layoutName):
            if let layoutName, !layoutName.isEmpty {
                if let match = configuration.layout(named: layoutName) {
                    return activateLayout(id: match.id) + feedbackEffects()
                }
                if let layoutID, configuration.layout(withID: layoutID) != nil {
                    return activateLayout(id: layoutID) + feedbackEffects()
                }
                return [.notice("No keyboard named “\(layoutName)”.")]
            }
            if let layoutID {
                if configuration.layout(withID: layoutID) != nil {
                    return activateLayout(id: layoutID) + feedbackEffects()
                }
                return [.notice("That keyboard no longer exists.")]
            }
            return []

        case .none:
            return []
        }
    }

    /// Convenience used by the renderer and by tests: what would this key type?
    func resolveInsertion(for key: KeyboardKey) -> String? {
        key.insertion(forShiftState: shiftState, autoUppercase: settings.autoUppercaseOnShift)
    }

    // MARK: - Render layout (with the runtime globe-key safety net)

    /// The layout that should actually be drawn.
    ///
    /// If a text field needs the input-mode switch key and the active layout has
    /// no Next Keyboard action, a globe key is appended at runtime so the user
    /// can never be trapped in the keyboard. It is *never* written back into the
    /// saved configuration — the user's data is untouched.
    func renderLayout() -> KeyboardLayout {
        let layout = activeLayout
        guard settings.autoInsertNextKeyboardKey,
              proxy.needsInputModeSwitchKey,
              !layout.containsNextKeyboardKey
        else {
            return layout
        }

        var copy = layout
        let globeKey = KeyboardKey(
            label: "🌐",
            action: .nextKeyboard,
            width: 1.2,
            isSpecial: true,
            accessibilityLabel: "Next Keyboard"
        )

        if let lastIndex = copy.rows.lastIndex(where: { !$0.keys.isEmpty }) {
            copy.rows[lastIndex].keys.append(globeKey)
        } else {
            copy.rows = [KeyboardRow(height: 1, keys: [globeKey])]
        }
        return copy
    }

    // MARK: - Private

    private func insert(_ text: String, consumesShift: Bool) -> [KeyboardEffect] {
        guard !text.isEmpty else { return [] }
        proxy.insertText(text)
        // Shift is single-shot: it applies to exactly one inserted character
        // unless Caps Lock is engaged. The caller always re-reads `shiftState`
        // after performing an action, so no extra effect is needed here.
        if consumesShift, shiftState == .shift {
            shiftState = .off
        }
        return feedbackEffects()
    }

    private func feedbackEffects() -> [KeyboardEffect] {
        var effects: [KeyboardEffect] = []
        if settings.haptics != .off { effects.append(.haptic) }
        if settings.keyClickSound { effects.append(.keyClick) }
        return effects
    }
}

// MARK: - Press interaction (tap / long press / repeat)

/// Events produced while a key is held down.
enum PressEvent: Equatable {
    /// Perform the key's own action now (touch-down for repeating keys, touch-up
    /// for ordinary keys).
    case performPrimary
    /// Another repeat of a `repeatsWhenHeld` action.
    case repeatPrimary
    /// Show the long-press alternates popup.
    case showAlternates
    /// Hide the alternates popup (the caller decides which candidate to insert).
    case hideAlternates
}

/// The pure state machine behind tap, long-press and press-and-hold-repeat.
///
/// Side effects are deliberately *not* performed here: the caller feeds it
/// timestamps and acts on the returned events. That makes every timing rule unit
/// testable and guarantees there is exactly one place that decides whether a
/// press is a tap, a hold, or a repeat.
struct PressInteraction: Equatable {

    var key: KeyboardKey
    var beganAt: TimeInterval
    var longPressDelay: TimeInterval
    var repeatDelay: TimeInterval
    var repeatInterval: TimeInterval
    var allowsAlternates: Bool
    var allowsRepeat: Bool

    private(set) var alternatesShown: Bool = false
    private(set) var didRepeat: Bool = false
    private var lastRepeatAt: TimeInterval

    static func began(key: KeyboardKey, at now: TimeInterval, settings: KeyboardSettings) -> PressInteraction {
        let canRepeat = key.repeatsWhenHeld && settings.backspaceRepeatEnabled
        return PressInteraction(
            key: key,
            beganAt: now,
            longPressDelay: max(0.15, settings.longPressDelay),
            repeatDelay: max(0.15, settings.backspaceRepeatDelay),
            repeatInterval: max(0.02, settings.backspaceRepeatInterval),
            allowsAlternates: settings.longPressEnabled && !key.longPress.isEmpty && !canRepeat,
            allowsRepeat: canRepeat,
            lastRepeatAt: now
        )
    }

    /// Called when the finger goes down. Produces the immediate repeat, if any.
    mutating func pressed() -> [PressEvent] {
        guard allowsRepeat else { return [] }
        return [.performPrimary]
    }

    /// Called periodically (and on long-press timers) while the key is held.
    mutating func advance(to now: TimeInterval) -> [PressEvent] {
        var events: [PressEvent] = []

        if allowsRepeat {
            guard now - beganAt >= repeatDelay else { return events }
            var emitted = 0
            // Never emit more than a handful of repeats per tick, so a stalled
            // run loop cannot produce a burst that deletes a whole field.
            while (now - lastRepeatAt) >= repeatInterval && emitted < 3 {
                lastRepeatAt += repeatInterval
                emitted += 1
                didRepeat = true
                events.append(.repeatPrimary)
            }
            return events
        }

        if allowsAlternates, !alternatesShown, now - beganAt >= longPressDelay {
            alternatesShown = true
            events.append(.showAlternates)
        }

        return events
    }

    /// Called when the finger lifts (or the gesture is cancelled).
    mutating func release(at now: TimeInterval) -> [PressEvent] {
        if alternatesShown {
            // The caller inserts the highlighted candidate instead.
            return [.hideAlternates]
        }
        if allowsRepeat {
            // The primary action already ran on touch-down.
            return []
        }
        return [.performPrimary]
    }
}

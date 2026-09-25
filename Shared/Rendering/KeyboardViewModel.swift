import SwiftUI
import Combine

/// The state of the long-press alternates popup.
struct AlternatesState: Equatable {
    var keyID: UUID
    var items: [KeyboardKeyLongPress]
    var selectedIndex: Int
}

/// Drives the keyboard UI.
///
/// Both the real keyboard extension and the host app's live preview use *this*
/// class, with the same `KeyboardRootView`. The only differences are which
/// `KeyboardTextProxy` it is given and what the host does with the effects —
/// so the preview can never drift away from the real keyboard.
///
/// Always used from the main thread (UI events and main-run-loop timers).
final class KeyboardViewModel: ObservableObject {

    // Published state — deliberately only what affects rendering.
    @Published private(set) var layout: KeyboardLayout
    @Published private(set) var theme: KeyboardTheme
    @Published private(set) var settings: KeyboardSettings
    @Published private(set) var shiftState: ShiftState = .off
    @Published private(set) var pressedKeyID: UUID?
    @Published private(set) var alternates: AlternatesState?
    @Published private(set) var notice: String?

    /// Lets the host app's theme editor preview an unsaved theme live, without
    /// touching the saved configuration or the keyboard extension.
    @Published var previewThemeOverride: KeyboardTheme?

    /// The theme actually used for drawing.
    var effectiveTheme: KeyboardTheme { previewThemeOverride ?? theme }

    let engine: KeyboardEngine

    private var interaction: PressInteraction?
    private var timer: Timer?
    private let onEffect: (KeyboardEffect) -> Void
    private let clock: () -> TimeInterval

    init(
        configuration: KeyboardConfiguration,
        proxy: KeyboardTextProxy,
        onEffect: @escaping (KeyboardEffect) -> Void = { _ in },
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        let engine = KeyboardEngine(configuration: configuration, proxy: proxy, clock: clock)
        self.engine = engine
        self.onEffect = onEffect
        self.clock = clock
        self.layout = engine.renderLayout()
        self.theme = engine.activeTheme
        self.settings = engine.settings
        self.shiftState = engine.shiftState
    }

    deinit {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Configuration

    /// Called when the host app saved new content, or when the keyboard reappears.
    func reload(configuration: KeyboardConfiguration) {
        let effects = engine.apply(configuration: configuration)
        syncFromEngine()
        forward(effects)
    }

    func activateLayout(id: UUID) {
        forward(engine.activateLayout(id: id))
        cancelInteraction()
        syncFromEngine()
    }

    func cycleLayout() {
        forward(engine.cycleLayout())
        cancelInteraction()
        syncFromEngine()
    }

    // MARK: - Geometry

    /// Geometry for the current layout and theme in the given area.
    func geometry(for size: CGSize, isLandscape: Bool = false) -> KeyboardGeometry {
        let theme = effectiveTheme
        return KeyboardMetrics.geometry(
            layout: layout,
            availableWidth: Double(size.width),
            availableHeight: 0,
            keySpacing: theme.keySpacing,
            rowSpacing: theme.rowSpacing,
            horizontalInset: 3,
            isLandscape: isLandscape,
            justification: settings.rowJustification,
            shiftState: shiftState
        )
    }

    /// Rows needed for this layout at the given width.
    func preferredHeight(width: Double, isLandscape: Bool, topInset: Double = 0, bottomInset: Double = 0) -> Double {
        let theme = effectiveTheme
        return KeyboardMetrics.preferredKeyboardHeight(
            layout: layout,
            width: width,
            isLandscape: isLandscape,
            keySpacing: theme.keySpacing,
            rowSpacing: theme.rowSpacing,
            topInset: topInset,
            bottomInset: bottomInset
        )
    }

    // MARK: - Key input

    func pressBegan(_ key: KeyboardKey) {
        // Ignore repeat begins from a gesture that is already tracking this key.
        if let active = interaction, active.key.id == key.id { return }

        stopTimer()
        alternates = nil
        pressedKeyID = key.id

        var newInteraction = PressInteraction.began(key: key, at: clock(), settings: settings)
        let immediate = newInteraction.pressed()
        interaction = newInteraction

        if !immediate.isEmpty {
            // Repeating keys act on touch-down so backspace feels immediate.
            perform(key: key)
        }
        scheduleTimer()
    }

    /// Called continuously while the finger is down, so the user can slide onto
    /// an alternate. The host view converts the touch position into an index
    /// (it owns the popup geometry) and calls `selectAlternate`.
    func selectAlternate(_ index: Int) {
        guard var pending = alternates else { return }
        let clamped = max(0, min(index, max(0, pending.items.count - 1)))
        if clamped != pending.selectedIndex {
            pending.selectedIndex = clamped
            alternates = pending
        }
    }

    func pressEnded(_ key: KeyboardKey) {
        let now = clock()
        var released: [PressEvent] = []
        if let active = interaction, active.key.id == key.id {
            released = active.release(at: now)
        }
        interaction = nil
        stopTimer()
        pressedKeyID = nil

        // Long press popup: insert whatever is highlighted, then stop.
        if let pending = alternates, pending.keyID == key.id {
            let items = pending.items
            let index = pending.selectedIndex
            alternates = nil
            if index >= 0, index < items.count {
                perform(alternate: items[index])
            }
            return
        }

        // Ordinary tap (repeating keys already acted on touch-down).
        if released.contains(.performPrimary) {
            perform(key: key)
        }
    }

    /// Finger moved too far away — do not insert anything.
    func pressCancelled(_ key: KeyboardKey) {
        guard pressedKeyID == key.id else { return }
        cancelInteraction()
    }

    func cancelInteraction() {
        interaction = nil
        alternates = nil
        pressedKeyID = nil
        stopTimer()
    }

    /// Perform a key immediately (used by accessibility, VoiceOver activation,
    /// and the preview's "test this key" shortcut).
    func performImmediately(_ key: KeyboardKey) {
        perform(key: key)
    }

    func dismissNotice() {
        notice = nil
    }

    /// Shows (or, with an empty string, clears) the small status strip.
    func showNotice(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        notice = trimmed.isEmpty ? nil : trimmed
    }

    /// Re-reads engine state into the published properties. Safe to call from
    /// `viewWillAppear`: it only publishes when something really changed.
    func refreshRenderedLayout() {
        syncFromEngine()
    }

    // MARK: - Internals

    private func perform(key: KeyboardKey) {
        forward(engine.perform(key: key))
        syncFromEngine()
    }

    private func perform(alternate: KeyboardKeyLongPress) {
        forward(engine.perform(action: alternate.action))
        syncFromEngine()
    }

    private func tick() {
        guard var active = interaction else {
            stopTimer()
            return
        }
        let events = active.advance(to: clock())
        interaction = active
        guard !events.isEmpty else { return }

        for event in events {
            switch event {
            case .performPrimary:
                perform(key: active.key)
            case .repeatPrimary:
                // Straight to the action: never re-enter the press state machine.
                forward(engine.perform(action: active.key.action))
                syncFromEngine()
            case .showAlternates:
                alternates = AlternatesState(keyID: active.key.id, items: active.key.longPress, selectedIndex: 0)
            case .hideAlternates:
                alternates = nil
            }
        }

        if alternates == nil, !active.allowsRepeat {
            stopTimer()
        }
    }

    private func scheduleTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common keeps repeats running while the scroll view / keyboard is tracking.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func syncFromEngine() {
        let renderedLayout = engine.renderLayout()
        if renderedLayout != layout { layout = renderedLayout }

        let currentTheme = engine.activeTheme
        if currentTheme != theme { theme = currentTheme }

        let currentSettings = engine.settings
        if currentSettings != settings { settings = currentSettings }

        let currentShift = engine.shiftState
        if currentShift != shiftState { shiftState = currentShift }
    }

    private func forward(_ effects: [KeyboardEffect]) {
        for effect in effects {
            if case .notice(let message) = effect {
                notice = message
            }
            onEffect(effect)
        }
    }
}
